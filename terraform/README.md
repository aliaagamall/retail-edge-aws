# RetailEdge - Terraform Infrastructure

## 1. Architecture Overview

Request flow:

```
User
  |
  v
CloudFront  (WAF attached)
  |
  |-- default behavior "/*"     --> S3 (static React build)
  |-- ordered behavior "/api/*" --> ALB (internal, via VPC Origin)
                                        |
                                        v
                              EC2 Auto Scaling Group
                              (private app subnet)
                                        |
                          -------------------------------
                          |                             |
                          v                             v
                  RDS MySQL (private)         ElastiCache Redis (private)
```

Key design points:

- The ALB is internal (not public). It is only reachable through CloudFront's VPC Origin. It has no public IP.
- WAF is attached at the CloudFront level (scope = CLOUDFRONT), not on the ALB, since the ALB is internal.
- EC2 instances sit in a private subnet with no NAT Gateway. They reach ECR / SSM / Secrets Manager through VPC Interface Endpoints, and S3 through a Gateway Endpoint. No NAT cost, no direct internet egress from the app subnet.
- RDS and Redis sit in a separate database subnet tier, reachable only from the App Security Group.

Network tiers:

| Tier        | Purpose                          | Internet access                |
|-------------|-----------------------------------|---------------------------------|
| Public      | Reserved for future use (NAT/bastion) | Has route to Internet Gateway |
| Application | EC2 instances                     | Outbound only via VPC Endpoints |
| Database    | RDS, Redis                        | None                            |

---

## 2. Directory Structure

```
terraform/
├── backend.tf              S3 backend (state) + native locking
├── providers.tf             aws / tls / random providers
├── variables.tf              root-level variables
├── outputs.tf                 all outputs (read by validation scripts)
├── terraform.tfvars.example
│
├── networking.tf, security-groups.tf, vpc-endpoints.tf
├── alb.tf, compute.tf, ecr.tf, ssm-parameters.tf
├── rds.tf, elasticache.tf, s3.tf, s3-web.tf
├── cloudfront.tf, waf.tf, iam.tf, monitoring.tf
│
├── modules/                  each module has main.tf + variables.tf + outputs.tf
│   ├── networking/            VPC, subnets (public/app/db), route tables
│   ├── security-groups/       all security groups (alb, app, rds, redis, endpoints)
│   ├── vpc-endpoints/         Interface + Gateway endpoints
│   ├── alb/                   Internal ALB + target group + listeners
│   ├── compute/                Launch Template + ASG + scheduled scaling (Black Friday)
│   ├── ecr/                    ECR repo + lifecycle policy
│   ├── ssm-parameters/         parameter storing the current deployed image tag
│   ├── rds/                    MySQL instance + Secrets Manager secret
│   ├── elasticache/            Redis replication group + Secrets Manager secret
│   ├── s3/                     general purpose bucket (assets) - app role access only
│   ├── s3-web/                 bucket for the React build (read by CloudFront)
│   ├── cloudfront/              Distribution + OAC + VPC Origin
│   ├── waf/                     Web ACL (CLOUDFRONT scope) + managed rules + rate limit
│   ├── iam/                      EC2 role + GitHub OIDC deploy role
│   └── monitoring/                SNS + CloudWatch alarms + dashboard
│
├── environments/
│   ├── dev.tfvars      + dev.backend.hcl
│   ├── staging.tfvars  + staging.backend.hcl
│   └── prod.tfvars     + prod.backend.hcl
│
├── scripts/
│   ├── setup-backend.sh        creates the S3 state bucket (one time only)
│   ├── cleanup-backend.sh      deletes the state bucket (destructive)
│   └── validation/              per-module post-apply check scripts (use AWS CLI)
│
└── validation-results/          output logs from the last validation runs
```

---

## 3. Environments

There are three environments: `dev`, `staging`, `prod`. Each has:

- `environments/<env>.tfvars` - environment-specific values (instance sizes, retention, etc.)
- `environments/<env>.backend.hcl` - sets the state file `key` inside the shared S3 bucket

Differences between environments:

| Setting                          | dev      | staging  | prod                       |
|-----------------------------------|----------|----------|-----------------------------|
| RDS deletion protection           | No       | Yes      | Yes                         |
| RDS backup retention              | 0 days   | 7 days   | 7 days                      |
| Secrets recovery window           | 0 days   | 30 days  | 30 days                     |
| ALB deletion protection           | No       | No       | Yes                         |
| Black Friday scheduled scaling    | No       | No       | Yes (Nov 25 to Nov 29)      |
| App instance type                 | t3.micro | t3.micro | t3.small                    |

---

## 4. First-Time Setup (Backend)

State is stored in a single S3 bucket, `retailedge-tfstate` (same bucket for all environments, different `key` per environment). Locking uses `use_lockfile = true` (S3 native locking, no DynamoDB table).

```bash
# One time only, before any terraform init
./scripts/setup-backend.sh
```

Then, per environment:

```bash
terraform init -backend-config=environments/dev.backend.hcl
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

Switching environments (e.g. dev to staging) requires:

```bash
terraform init -reconfigure -backend-config=environments/staging.backend.hcl
```

Warning: `scripts/cleanup-backend.sh` deletes the state bucket including all object versions. Only run this if certain.

---

## 5. Required Variables (No Defaults)

These variables must be set explicitly, they have no default value:

| Variable          | Purpose                                                                 |
|--------------------|--------------------------------------------------------------------------|
| `github_org`       | GitHub org/username allowed to assume the deploy role via OIDC          |
| `github_repo`      | GitHub repo name allowed to assume the deploy role via OIDC             |
| `alert_email`      | Email that receives CloudWatch alarms via SNS - must confirm the subscription email after first apply |
| `certificate_arn`  | Leave as `""` until a domain and ACM certificate exist. While empty, the ALB and WAF run HTTP-only |

Current values: `github_org/github_repo = aliaagamall/retailedge-app`, branch `main`.

---

## 6. Validation Scripts

After each apply (or after changing a specific module), run its matching validation script in `scripts/validation/`:

```bash
cd terraform
./scripts/validation/validate-networking.sh
./scripts/validation/validate-alb.sh
./scripts/validation/validate-rds.sh
# ... one script per module

# or run everything at once:
./scripts/validation/validate-all.sh
```

Each script performs real checks against AWS (not just `terraform validate`) and saves its output to `validation-results/`. There is also `validate-infra.sh`, a broader script that checks the whole stack and separates results into:

- FAIL: a real problem that needs fixing
- INFO: expected at the current stage (for example: ALB targets unhealthy because no container is running yet, or the web bucket is empty because the React build has not been synced yet)

Requirements: `aws cli` configured, `jq`, and `terraform` (must be run from inside the `terraform/` directory).

---

## 7. Current Status (dev)

Based on the latest `validation-results/validate-infra-dev-*.log`:

| Component            | Status                                                    |
|------------------------|-------------------------------------------------------------|
| Networking             | OK                                                          |
| ALB                     | OK (active, internal)                                       |
| RDS                     | OK (available)                                              |
| Redis                   | OK (available)                                              |
| CloudFront              | OK (deployed)                                                |
| WAF                     | OK                                                            |
| Monitoring              | OK (alarms + dashboard)                                       |
| Auto Scaling Group      | Desired capacity = 0 (scaled down manually, likely to save cost while waiting on the deploy pipeline) |
| ECR                     | Repo exists but has 0 images pushed                           |
| Web bucket (S3)         | Empty, React build not synced yet                             |
| SSM current-image param | Still at placeholder value `none`                             |

Summary: the infrastructure is fully provisioned, but the application itself has not been deployed onto it yet.

---

## 8. Pending Work: Deployment Pipeline (Lambda)

Current state:

- The EC2 bootstrap script (in `modules/compute/main.tf`) reads the image tag from the SSM Parameter on boot only. If it finds `none`, it exits cleanly without doing anything. This is intentional, it confirms the conditional logic works (see `validate-ssm-and-bootstrap.sh`).
- The GitHub Actions role (in `modules/iam`) only has permission to push to ECR and to run `ssm:PutParameter`. There is currently no mechanism that takes a newly pushed image and actually deploys it to the running instances. Pushing to ECR and updating the SSM parameter alone do not deploy anything to a live instance.
- Planned (not yet implemented): a Lambda function, triggered after the ECR push (from GitHub Actions), that runs an SSM Run Command against the ASG instances to pull the new image and restart the container.
- CodeDeploy was previously part of this design and has been fully removed (confirmed in `validate-iam.sh` and `validate-ssm-and-bootstrap.sh`), in favor of the Lambda + SSM approach above.

Implication: if `modules/lambda` does not exist yet in the code, this is intentional, not missing work. It has not been built yet. Once it is built, this README will be updated with a new section describing:

- Where the Lambda module lives
- What triggers it
- How the GitHub Actions workflow calls it

---

## 9. Other Notes

- No secrets are stored in code or in `user_data`. Everything (DB credentials, Redis auth token) is stored in Secrets Manager and read by the application at runtime.
- Passwords are randomly generated via `random_password`. Do not set them manually.
- The SSM parameter holding the current image tag has `lifecycle { ignore_changes = [value] }`. After the first apply, GitHub Actions owns this value, and Terraform will not reset it back to `none` on later applies.
- ECR is set to `image_tag_mutability = IMMUTABLE`, meaning the same tag cannot be pushed twice. Each deployment needs a new tag.
- `terraform/docs/dependency-graph.svg` contains a full resource dependency graph (generated via `terraform graph`).

---

## 10. Application Repo

Application code (not infrastructure) is here:
https://github.com/aliaagamall/retailedge-app/tree/feat/retailedge-aws-integration

Expected GitHub Actions workflow steps:

1. Build the Docker image
2. Push to ECR (using the OIDC role defined here in `modules/iam`)
3. Update the SSM parameter with the new tag
4. (Pending) Invoke the Lambda function to perform the actual deployment to running instances - see Section 8
