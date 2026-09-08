# RetailEdge - Terraform Infrastructure

## 1. Architecture Overview

RetailEdge uses a three-tier AWS architecture with CloudFront as the public entry point.

### Request Flow

```
User
  |
  v
CloudFront
  |
  |-- default behavior "/*"
  |       --> S3 (static React build)
  |
  |-- ordered behavior "/api/*"
          --> CloudFront Function
                /api/* -> /*
                    |
                    v
                VPC Origin
                    |
                    v
                Internal ALB
                    |
                    v
                EC2 Auto Scaling Group
                    |
                    v
                Docker Application
                  |       |
                  v       v
              RDS MySQL  ElastiCache Redis
```

### Key Design Points

- The ALB is internal and has no public IP.
- The ALB is reachable through CloudFront's VPC Origin.
- CloudFront routes `/api/*` requests to the internal ALB.
- A CloudFront Function runs at viewer-request time and removes the `/api` prefix before forwarding the request.
- For example, `/api/health` is forwarded to the application as `/health`.
- The ALB allows CloudFront origin-facing traffic through the AWS-managed CloudFront origin-facing prefix list.
- The ALB communicates with the application tier on port 8080 using Security Group references.
- WAF is attached at the CloudFront level with `CLOUDFRONT` scope.
- EC2 instances run in private application subnets.
- EC2 instances have no direct internet access and use VPC endpoints for AWS service communication.
- RDS and Redis are isolated in the database tier and accept traffic only from the Application Security Group.
- Application secrets are stored in AWS Secrets Manager and retrieved at runtime.

---

## 2. Directory Structure

```
terraform/
├── backend.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
│
├── networking.tf
├── security-groups.tf
├── vpc-endpoints.tf
├── alb.tf
├── compute.tf
├── ecr.tf
├── ssm-parameters.tf
├── rds.tf
├── elasticache.tf
├── s3.tf
├── s3-web.tf
├── cloudfront.tf
├── waf.tf
├── iam.tf
├── lambda-deploy.tf
└── monitoring.tf
│
├── lambda/
│   └── deploy/
│       └── handler.py
│
├── modules/
│   ├── networking/
│   ├── security-groups/
│   ├── vpc-endpoints/
│   ├── alb/
│   ├── compute/
│   ├── ecr/
│   ├── ssm-parameters/
│   ├── rds/
│   ├── elasticache/
│   ├── s3/
│   ├── s3-web/
│   ├── cloudfront/
│   ├── waf/
│   ├── iam/
│   ├── lambda-deploy/
│   └── monitoring/
│
├── environments/
│   ├── dev.tfvars
│   ├── dev.backend.hcl
│   ├── staging.tfvars
│   ├── staging.backend.hcl
│   ├── prod.tfvars
│   └── prod.backend.hcl
│
├── scripts/
│   ├── setup-backend.sh
│   ├── cleanup-backend.sh
│   └── validation/
│       ├── common.sh
│       ├── validate-all.sh
│       ├── validate-api.sh
│       └── ...
│
└── validation-results/
    ├── api-validation.txt
    └── ...
```

---

## 3. Environments

There are three environments:

- `dev`
- `staging`
- `prod`

Each environment has:

- `environments/<env>.tfvars`
- `environments/<env>.backend.hcl`

Environment-specific settings include instance types, RDS retention, deletion protection, and scaling configuration.

| Setting                        | dev      | staging  | prod     |
|--------------------------------|----------|----------|----------|
| RDS deletion protection        | No       | Yes      | Yes      |
| RDS backup retention           | 0 days   | 7 days   | 7 days   |
| Secrets recovery window        | 0 days   | 30 days  | 30 days  |
| ALB deletion protection        | No       | No       | Yes      |
| Black Friday scheduled scaling | No       | No       | Yes      |

---

## 4. First-Time Setup

Terraform state is stored in the shared S3 bucket:

```
retailedge-tfstate
```

Each environment uses a different backend key.

S3 native locking is enabled with:

```
use_lockfile = true
```

### Create the Backend

Run once:

```bash
./scripts/setup-backend.sh
```

### Initialize an Environment

For `dev`:

```bash
terraform init -backend-config=environments/dev.backend.hcl
```

### Plan

```bash
terraform plan \
  -var-file=environments/dev.tfvars \
  -out=tfplan-dev
```

### Apply

```bash
terraform apply tfplan-dev
```

### Switch Environments

For example, to switch to `staging`:

```bash
terraform init -reconfigure \
  -backend-config=environments/staging.backend.hcl
```

> **Warning**  
> `scripts/cleanup-backend.sh` is destructive. It deletes the Terraform state bucket and its object versions.  
> Only run it when the backend itself needs to be permanently removed.

---

## 5. Required Variables

The following variables must be explicitly configured:

| Variable          | Purpose                                                                  |
|-------------------|--------------------------------------------------------------------------|
| `github_org`      | GitHub organization/username allowed to assume the deployment role       |
| `github_repo`     | GitHub repository allowed to assume the deployment role                  |
| `alert_email`     | Email used for CloudWatch alarm notifications                            |
| `certificate_arn` | ACM certificate ARN; leave empty when HTTPS on the ALB is not configured |

The GitHub deployment identity is restricted to the configured repository and branch.

---

## 6. Security Architecture

Security Groups follow least-privilege communication between tiers.

```
CloudFront
    |
    | HTTP :80
    v
ALB SG
    |
    | TCP :8080
    v
App SG
    |
    |---- TCP :3306 ----> RDS SG
    |
    |---- TCP :6379 ----> Redis SG
    |
    |---- TCP :443 -----> VPC Endpoint SG
```

### ALB

The ALB is internal.

CloudFront access is allowed using the AWS-managed prefix list:

```
com.amazonaws.global.cloudfront.origin-facing
```

The prefix list is looked up dynamically by Terraform instead of hardcoding its ID.

The ALB can reach the application tier only on port 8080.

### Application

The Application Security Group accepts traffic on port 8080 only from the ALB Security Group.

The application uses VPC endpoints to communicate with AWS services without requiring a NAT Gateway.

### Database

- RDS accepts MySQL traffic only from the Application Security Group.
- Redis accepts Redis traffic only from the Application Security Group.

---

## 7. Deployment Pipeline

Application deployment uses GitHub Actions, ECR, Lambda, SSM, and the EC2 instances managed by the Auto Scaling Group.

### Deployment Flow

```
GitHub Actions
      |
      | Build Docker image
      v
     ECR
      |
      | Push image tagged with commit SHA
      v
Invoke Lambda
      |
      v
Lambda Deployment Orchestrator
      |
      |-- Read current image tag from SSM
      |
      |-- Find InService ASG instances
      |
      |-- Send SSM Run Command
      v
EC2 instances
      |
      v
/opt/retailedge/deploy.sh
      |
      |-- Login to ECR
      |-- Pull requested image
      |-- Stop/remove current container
      |-- Start new container
      |-- Run /health checks
      v
Application
```

### Successful Deployment

If all instances become healthy:

```
New image
   |
   v
All instances healthy
   |
   v
Update SSM current-image parameter
```

### Failed Deployment

If an instance fails:

```
Deployment failure
      |
      v
Lambda identifies updated instances
      |
      v
Rollback to previous image
      |
      v
Health check rollback
```

If rollback itself fails, Lambda publishes an alert through SNS and reports a mixed deployment state.

### SSM Image Parameter

The currently deployed image tag is stored in:

```
/retailedge/dev/current-image
```

Terraform ignores changes to this parameter after initial provisioning so the deployment pipeline can manage its value.

### ECR

ECR uses immutable image tags.

Each deployment therefore uses a new image tag, typically the Git commit SHA.

### CodeDeploy

CodeDeploy was removed from the architecture.

Deployment orchestration is implemented using:

```
Lambda + SSM Run Command
```

---

## 8. CloudFront API Routing

CloudFront separates static frontend traffic from API traffic.

```
/*
  |
  v
S3

/api/*
  |
  v
CloudFront Function
  |
  | Remove "/api"
  v
VPC Origin
  |
  v
Internal ALB
```

**Example:**

```
Client request:
https://<cloudfront-domain>/api/health

CloudFront Function:
    /api/health -> /health

ALB/Application:
    /health
```

This allows the application to keep normal API routes without requiring `/api` in the application itself, while CloudFront still uses `/api/*` to distinguish API traffic from the static frontend.

---

## 9. Validation

Validation scripts perform real AWS checks using the AWS CLI.

They are not limited to:

```
terraform validate
```

### Run an Individual Validation

```bash
./scripts/validation/validate-networking.sh
./scripts/validation/validate-alb.sh
./scripts/validation/validate-api.sh
```

### Run the Full Validation Suite

```bash
./scripts/validation/validate-all.sh
```

### API End-to-End Validation

The API validation script:

```
scripts/validation/validate-api.sh
```

tests:

```
Client
  -> CloudFront
  -> /api/* behavior
  -> CloudFront Function
  -> VPC Origin
  -> Internal ALB
  -> EC2
  -> Docker Application
  -> MySQL
  -> Redis
```

It verifies:

- HTTP status 200
- Application status is `ok`
- MySQL is connected
- Redis is connected

The result is saved to:

```
validation-results/api-validation.txt
```

The successful end-to-end test returned:

```json
{
  "status": "ok",
  "mysql": "connected",
  "redis": "connected"
}
```

---

## 10. Monitoring

Monitoring uses native AWS services:

- CloudWatch alarms
- CloudWatch dashboard
- SNS notifications

The monitoring layer tracks application and load-balancer health, including CPU utilization, ALB errors, and latency.

SNS sends alarm notifications to the configured alert email.

---

## 11. Cost Considerations

The architecture avoids a NAT Gateway for the private application tier.

AWS service access is provided through VPC endpoints where required.

The `dev` environment can be scaled down or destroyed when it is not being used for testing.

For temporary testing environments, destroy the infrastructure after validation:

```bash
terraform destroy -var-file=environments/dev.tfvars
```

If ECR contains images, the repository must be emptied before Terraform can delete it unless the ECR resource is configured with `force_delete = true`.

---

## 12. Application Repository

Application code is maintained separately from the infrastructure repository.

The application repository is:

```
aliaagamall/retailedge-app
```

The expected deployment workflow is:

1. Build Docker image
2. Push image to ECR
3. Invoke deployment Lambda
4. Lambda deploys the image using SSM
5. Instances perform health checks
6. Lambda updates the current image tag
7. Failed deployments are rolled back

---

## 13. Current Infrastructure State

The architecture and deployment flow have been provisioned and end-to-end validated in the development environment.

The final API validation successfully verified:

```
CloudFront
    -> VPC Origin
    -> Internal ALB
    -> EC2
    -> Docker
    -> MySQL
    -> Redis
```

The development infrastructure was subsequently destroyed when no longer needed in order to avoid unnecessary AWS costs.

The Terraform code remains available to recreate the environment when required.
