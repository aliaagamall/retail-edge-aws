# RetailEdge Inc. - AWS Migration

This repository documents and implements RetailEdge Inc.'s migration from a bare-metal, co-located stack to AWS, using a three-tier architecture provisioned entirely with Terraform.

Companion repository for the application code, Dockerfile, and GitHub Actions workflow:

[RetailEdge Application Repository](https://github.com/aliaagamall/retailedge-app/tree/feat/retailedge-aws-integration)

---

## 1. Project Background

| Item | Detail |
|---|---|
| **Company** | RetailEdge Inc., mid-size e-commerce |
| **Current platform** | Three bare-metal servers in a co-location data center |
| **Users** | Approximately 200,000 monthly active users |
| **Peak traffic** | Approximately 12,000 concurrent users on Black Friday |
| **Trigger for migration** | Co-location contract expires in 90 days |
| **Known pain points** | 2 to 3 hours of Black Friday downtime (about $80,000 in lost sales); manual deployments take about 4 hours and have caused 3 incidents this quarter from human error |
| **Migration approach** | Replatform (minimize application code changes), not a rewrite |

### Requirements

- [Business Requirements](./docs/requirements/Business%20Requirements.md)
- [Project Constraints](./docs/requirements/Project%20Constraints.md)
- [Technical Requirements](./docs/requirements/Technical%20Requirements.md)

---

## 2. Repository Structure

```text
retail-edge-aws/
│
├── docs/
│   ├── requirements/
│   │   ├── Business Requirements.md
│   │   ├── Project Constraints.md
│   │   └── Technical Requirements.md
│   │
│   ├── architecture/
│   │   └── (reserved for architecture write-ups)
│   │
│   └── cost/
│       └── (reserved for cost analysis write-ups)
│
├── diagrams/
│   └── architecture/
│       ├── 01-initial-architecture.drawio
│       ├── 02-network-security-architecture.drawio
│       ├── 03-target-architecture.drawio
│       └── 04-retailedge-aws-integration-cicd.drawio
│
├── terraform/
│   ├── modules/
│   │   ├── networking/
│   │   ├── security-groups/
│   │   ├── vpc-endpoints/
│   │   ├── iam/
│   │   ├── alb/
│   │   ├── compute/
│   │   ├── rds/
│   │   ├── elasticache/
│   │   ├── ecr/
│   │   ├── s3/
│   │   ├── cloudfront/
│   │   ├── waf/
│   │   ├── lambda-deploy/
│   │   └── monitoring/
│   │
│   ├── environments/
│   │   ├── dev.tfvars
│   │   ├── staging.tfvars
│   │   └── prod.tfvars
│   │
│   ├── lambda/
│   │   └── deploy/
│   │       └── handler.py
│   │
│   ├── scripts/
│   │   └── validation/
│   │       └── validate-api.sh
│   │
│   └── README.md
│
├── load-testing/
│   ├── scripts/
│   │   ├── load_test.sh
│   │   └── setup-app-server.sh
│   │
│   ├── cloudformation/
│   │   └── (throwaway load-testing infrastructure)
│   │
│   ├── demo/
│   │   └── (load-testing demo)
│   │
│   ├── load_test_results.md
│   └── README.md
│
├── reports/
│   ├── architecture-design/
│   ├── migration/
│   └── cost/
│
└── .gitignore
```

---

## 3. Architecture Evolution

The [`diagrams/architecture/`](./diagrams/architecture/) folder tracks how the architecture evolved throughout the project.

Each diagram represents a different stage of the design process.

| File | Stage | Summary |
|---|---|---|
| [`01-initial-architecture.drawio`](./diagrams/architecture/01-initial-architecture.drawio) | Initial proposal | High-level three-tier architecture with Route 53, CloudFront, public ALB, EC2 ASG, RDS Multi-AZ, ElastiCache, and S3 |
| [`02-network-security-architecture.drawio`](./diagrams/architecture/02-network-security-architecture.drawio) | Detailed network + security | VPC with public/private/database subnets across two AZs, security group relationships, and public ALB with HTTPS |
| [`03-target-architecture.drawio`](./diagrams/architecture/03-target-architecture.drawio) | Target design | Adds NAT Gateway, IAM roles, and Secrets Manager credential flow |
| [`04-retailedge-aws-integration-cicd.drawio`](./diagrams/architecture/04-retailedge-aws-integration-cicd.drawio) | Current / as-built | Internal ALB behind CloudFront VPC Origin, WAF at CloudFront, containerized application on EC2, ECR, GitHub OIDC, Lambda + SSM deployment pipeline, and monitoring/logging |

The first three diagrams are preserved as part of the project's architecture history.

The fourth diagram represents the current implemented architecture.

---

## 4. Current AWS Architecture

The current architecture uses CloudFront as the public entry point and keeps the application tier and database tier private.

```text
                              Internet
                                  |
                                  v
                         +----------------+
                         |   CloudFront   |
                         |  + WAF         |
                         +-------+--------+
                                 |
                 +---------------+---------------+
                 |                               |
              /* |                            /api/*
                 |                               |
                 v                               v
          +-------------+              +-------------------+
          |     S3      |              | CloudFront        |
          | Static Web  |              | Function          |
          |   Build     |              | Strip /api prefix |
          +-------------+              +---------+---------+
                                                |
                                                v
                                      +-------------------+
                                      | Internal ALB      |
                                      |  VPC Origin       |
                                      +---------+---------+
                                                |
                                                v
                                      +-------------------+
                                      | EC2 Auto Scaling  |
                                      |      Group        |
                                      |     Docker        |
                                      +---------+---------+
                                                |
                              +-----------------+-----------------+
                              |                                   |
                              v                                   v
                       +-------------+                    +-------------+
                       |  RDS MySQL  |                    | ElastiCache |
                       |  Multi-AZ   |                    |    Redis    |
                       +-------------+                    +-------------+
```

### API Request Flow

The public API uses the `/api/*` path to distinguish API requests from frontend requests.

For example:

```text
Client
  |
  | GET /api/health
  v
CloudFront
  |
  | /api/* behavior
  v
CloudFront Function
  |
  | Rewrite /api/health -> /health
  v
CloudFront VPC Origin
  |
  v
Internal ALB
  |
  v
EC2 / Docker Application
  |
  +----> MySQL
  |
  +----> Redis
```

The application itself does not need to implement an `/api` prefix.

The CloudFront Function removes the `/api` prefix before forwarding the request to the application.

---

## 5. Infrastructure as Code

All AWS infrastructure is defined using Terraform under [`terraform/`](./terraform/).

Detailed Terraform documentation is available in:

[Terraform README](./terraform/README.md)

### Main Terraform Components

| Component | Purpose |
|---|---|
| [`networking`](./terraform/modules/networking/) | VPC, subnets, route tables, Internet Gateway |
| [`security-groups`](./terraform/modules/security-groups/) | ALB, application, database, Redis, and VPC endpoint security groups |
| [`vpc-endpoints`](./terraform/modules/vpc-endpoints/) | Private connectivity to AWS services |
| [`iam`](./terraform/modules/iam/) | EC2, Lambda, GitHub OIDC, and deployment permissions |
| [`alb`](./terraform/modules/alb/) | Internal Application Load Balancer and target group |
| [`compute`](./terraform/modules/compute/) | EC2 Launch Template and Auto Scaling Group |
| [`rds`](./terraform/modules/rds/) | MySQL RDS Multi-AZ database |
| [`elasticache`](./terraform/modules/elasticache/) | Redis cache |
| [`ecr`](./terraform/modules/ecr/) | Container image repository |
| [`s3`](./terraform/modules/s3/) | Private static website storage |
| [`cloudfront`](./terraform/modules/cloudfront/) | CDN, VPC Origin, API routing, and URI rewrite |
| [`waf`](./terraform/modules/waf/) | Web Application Firewall |
| [`lambda-deploy`](./terraform/modules/lambda-deploy/) | Deployment orchestration through Lambda and SSM |
| [`monitoring`](./terraform/modules/monitoring/) | CloudWatch alarms, dashboard, and SNS notifications |

### Environments

Terraform environment configuration is stored under [`terraform/environments/`](./terraform/environments/).

- [`dev.tfvars`](./terraform/environments/dev.tfvars)
- [`staging.tfvars`](./terraform/environments/staging.tfvars)
- [`prod.tfvars`](./terraform/environments/prod.tfvars)

The development environment was provisioned and fully validated.

After validation, the development infrastructure was destroyed to avoid unnecessary AWS costs.

The infrastructure can be recreated from the Terraform configuration whenever required.

---

## 6. Load Testing and Capacity Planning

Before finalizing the Auto Scaling configuration, a load test was performed against the application to determine its practical capacity.

Detailed information is available in:

- [`load-testing/README.md`](./load-testing/README.md)
- [`load-testing/load_test_results.md`](./load-testing/load_test_results.md)
- [`load-testing/scripts/load_test.sh`](./load-testing/scripts/load_test.sh)

### Test Results

The test targeted the `/health` endpoint.

| Concurrent Users | Success Rate |
|---:|---:|
| 1,000 | 100% |
| 2,000 | 93.4% |
| 8,000 | 21.7% |
| 12,000 | 15.9% |
| 15,000 | 17.9% |

### Capacity Planning Conclusion

Based on the load-testing results:

- Approximately 1,000 concurrent users per instance is used as a planning baseline.
- Normal-day Auto Scaling Group maximum capacity: 10 instances.
- Black Friday scheduled-scaling maximum capacity: 17 instances.
- The production capacity configuration is defined in [`prod.tfvars`](./terraform/environments/prod.tfvars).

These numbers are planning estimates based on the tested workload and should be revalidated with realistic application traffic before production rollout.

The infrastructure under [`load-testing/cloudformation/`](./load-testing/cloudformation/) was created as a disposable test environment and is separate from the main Terraform infrastructure.

---

## 7. Deployment Architecture

Application deployment is implemented using GitHub Actions, Amazon ECR, AWS Lambda, and AWS Systems Manager Run Command.

```text
                    GitHub
                       |
                       v
              GitHub Actions
                       |
                       | Build Docker image
                       v
                     ECR
                       |
                       | Push image tagged with commit SHA
                       v
              Deployment Lambda
                       |
                       | Read current image from SSM
                       |
                       v
               EC2 Auto Scaling Group
                       |
                       | SSM Run Command
                       v
                 EC2 Instances
                       |
                       v
                Docker Application
```

### Deployment Flow

1. GitHub Actions builds the Docker image.
2. The image is tagged using the Git commit SHA.
3. The image is pushed to Amazon ECR.
4. GitHub Actions invokes the deployment Lambda.
5. Lambda retrieves the currently deployed image tag from SSM Parameter Store.
6. Lambda discovers the active EC2 instances in the Auto Scaling Group.
7. Lambda sends an SSM Run Command to the instances.
8. Each instance pulls the requested image from ECR.
9. The existing Docker container is replaced with the new version.
10. The deployment script performs application health checks.
11. If all instances are healthy, the SSM parameter is updated with the new image tag.
12. If deployment fails, Lambda rolls back the affected instances to the previous image.
13. If rollback also fails, Lambda publishes an alert through SNS.

### Deployment Components

- [`terraform/lambda/deploy/handler.py`](./terraform/lambda/deploy/handler.py)
- [`terraform/modules/lambda-deploy/`](./terraform/modules/lambda-deploy/)
- [`terraform/lambda-deploy.tf`](./terraform/lambda-deploy.tf)

The deployment process avoids requiring direct SSH access to application instances.

---

## 8. Security Architecture

The application is designed around private networking and least-privilege access.

### Network Isolation

```text
Internet
   |
   v
CloudFront + WAF
   |
   v
Internal ALB
   |
   v
Private Application Subnets
   |
   +----> Private Database Subnets
   |
   +----> AWS Service VPC Endpoints
```

### Security Group Flow

```text
CloudFront
    |
    | HTTP 80
    v
ALB Security Group
    |
    | TCP 8080
    v
Application Security Group
    |
    +----> TCP 3306 ----> RDS Security Group
    |
    +----> TCP 6379 ----> Redis Security Group
    |
    +----> TCP 443 -----> VPC Endpoint Security Group
```

The ALB accepts traffic from the AWS-managed CloudFront origin-facing prefix list rather than allowing arbitrary internet traffic.

The application security group only accepts application traffic from the ALB security group.

The database and Redis security groups only accept traffic from the application security group.

---

## 9. CloudFront API Routing

CloudFront serves two different types of traffic:

### Static Frontend

```text
/
├── index.html
├── assets/
└── ...
        |
        v
      S3
```

The S3 bucket remains private and is accessed through CloudFront using Origin Access Control (OAC).

### API

```text
/api/*
   |
   v
CloudFront Function
   |
   | Remove /api prefix
   v
VPC Origin
   |
   v
Internal ALB
   |
   v
EC2 Application
```

For example:

```text
/api/health
      |
      v
/health
```

This allows the public API to have a clean `/api/...` namespace while keeping the application routes unchanged.

---

## 10. End-to-End Validation

The API path was validated end-to-end through the public CloudFront endpoint.

Validation script:

[`terraform/scripts/validation/validate-api.sh`](./terraform/scripts/validation/validate-api.sh)

Validation result:

[`terraform/validation-results/api-validation.txt`](./terraform/validation-results/api-validation.txt)

The validation checks:

- CloudFront responds with HTTP 200.
- Application health status is `ok`.
- MySQL connection is healthy.
- Redis connection is healthy.
- The complete request path works through:

```text
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

Example successful response:

```json
{
  "status": "ok",
  "mysql": "connected",
  "redis": "connected"
}
```

This confirms that the public API path successfully reaches the private application and data tiers.

---

## 11. Monitoring and Observability

Monitoring is implemented using native AWS services.

### CloudWatch

The monitoring module provides:

- EC2 CPU utilization alarms
- ALB HTTP 5xx alarms
- ALB P95 latency alarms
- CloudWatch dashboard

### SNS

Amazon SNS is used to deliver monitoring alerts.

The Terraform monitoring module is available under:

[`terraform/modules/monitoring/`](./terraform/modules/monitoring/)

Monitoring outputs include:

- SNS topic ARN
- CloudWatch dashboard name
- CloudWatch dashboard URL

---

## 12. CI/CD

The application repository contains the GitHub Actions workflow responsible for building and publishing application images.

[RetailEdge Application Repository](https://github.com/aliaagamall/retailedge-app/tree/feat/retailedge-aws-integration)

The overall flow is:

```text
Developer
    |
    v
GitHub
    |
    v
GitHub Actions
    |
    +----> Build
    |
    +----> Test
    |
    +----> Docker Build
    |
    +----> Push to ECR
    |
    +----> Invoke Lambda
              |
              v
         SSM Run Command
              |
              v
         EC2 Auto Scaling Group
```

GitHub Actions authenticates with AWS using GitHub OIDC instead of storing long-lived AWS access keys.

---

## 13. Repository Validation

The project contains validation scripts and recorded validation results for different infrastructure components.

### API Validation

- [`validate-api.sh`](./terraform/scripts/validation/validate-api.sh)
- [`api-validation.txt`](./terraform/validation-results/api-validation.txt)

### Compute Validation

- [`compute-validation.txt`](./terraform/validation-results/compute-validation.txt)

### Load Testing

- [`load_test.sh`](./load-testing/scripts/load_test.sh)
- [`load_test_results.md`](./load-testing/load_test_results.md)

These files provide evidence that the implemented infrastructure was tested rather than only defined through Terraform.

---

## 14. Current Project Status

| Area | Status |
|---|---|
| Requirements gathering | Done |
| Architecture design | Done |
| Architecture evolution documentation | Done |
| Load testing | Done |
| Capacity planning | Done |
| Terraform infrastructure | Implemented |
| Development environment validation | Done |
| CloudFront distribution | Implemented |
| CloudFront VPC Origin | Implemented |
| CloudFront Function API rewrite | Implemented |
| Internal ALB | Implemented |
| EC2 Auto Scaling Group | Implemented |
| Dockerized application deployment | Implemented |
| RDS MySQL | Implemented |
| ElastiCache Redis | Implemented |
| ECR | Implemented |
| WAF | Implemented |
| GitHub OIDC | Implemented |
| Lambda deployment orchestration | Implemented |
| SSM-based deployment | Implemented |
| Deployment health checks | Implemented |
| Deployment rollback | Implemented |
| CloudWatch monitoring | Implemented |
| SNS alerting | Implemented |
| End-to-end API validation | Done |
| Cost-saving infrastructure cleanup | Done |
| 3-year TCO analysis | Not yet written |
| Architecture design report | Not yet written |
| Migration report | Not yet written |

---

## 15. Documentation Roadmap

The following sections are reserved for the project's final documentation and analysis:

### Architecture Design Report

Location:

[`reports/architecture-design/`](./reports/architecture-design/)

Expected content:

- Architecture decisions
- AWS service selection
- Network architecture
- Security architecture
- High availability
- Scalability
- Disaster recovery considerations
- Deployment architecture

### Migration Report

Location:

[`reports/migration/`](./reports/migration/)

Expected content:

- Current-state analysis
- Migration strategy
- Migration phases
- Data migration considerations
- Application migration
- Deployment strategy
- Rollback strategy
- Operational considerations

### Cost Analysis

Location:

[`reports/cost/`](./reports/cost/)

Expected content:

- AWS service cost breakdown
- Development environment cost
- Production environment cost
- Black Friday scaling cost
- 3-year TCO comparison
- Cost optimization opportunities

---

## 16. Cost Considerations

The project was intentionally tested using a development environment rather than leaving production-sized infrastructure running continuously.

After completing the end-to-end validation, the development infrastructure was destroyed to avoid unnecessary AWS charges.

The Terraform configuration remains the source of truth and can recreate the environment when needed.

For resources that contain data or images, destruction may require additional cleanup steps. For example, an ECR repository containing Docker images cannot be deleted unless the images are removed or the repository is configured with Terraform's `force_delete` option.

---

## 17. Application Repository

The application code is maintained separately from the infrastructure repository.

[RetailEdge Application Repository](https://github.com/aliaagamall/retailedge-app/tree/feat/retailedge-aws-integration)

The application repository contains:

- Node.js application
- Dockerfile
- Application configuration
- Health endpoint
- Database integration
- Redis integration
- GitHub Actions workflow
- ECR image publishing

The infrastructure repository contains the AWS resources and deployment orchestration required to run the application.

---

## 18. Final Architecture Summary

The final implemented solution provides:

- Public access through CloudFront
- AWS WAF protection at the edge
- Private static frontend storage in S3
- CloudFront VPC Origin for private API access
- CloudFront Function for API path rewriting
- Internal Application Load Balancer
- EC2 Auto Scaling Group
- Dockerized application deployment
- RDS MySQL Multi-AZ
- ElastiCache Redis
- Amazon ECR
- GitHub OIDC authentication
- Lambda-based deployment orchestration
- AWS Systems Manager Run Command
- Automated deployment health checks
- Automated rollback
- CloudWatch monitoring
- SNS alerting
- Infrastructure as Code with Terraform
- End-to-end validation through the public API

The resulting architecture is designed to improve availability, scalability, security, deployment reliability, and operational control compared with the original bare-metal environment.