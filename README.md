# RetailEdge Inc. - AWS Migration

This repository documents and implements RetailEdge Inc.'s migration from a bare-metal, co-located stack to AWS, using a three-tier architecture provisioned entirely with Terraform.

Companion repo (application code, Dockerfile, GitHub Actions workflow): [App Repo](https://github.com/aliaagamall/retailedge-app/tree/feat/retailedge-aws-integration)

---

## 1. Project Background

| Item                  | Detail                                                                 |
|------------------------|--------------------------------------------------------------------------|
| Company                | RetailEdge Inc., mid-size e-commerce                                     |
| Current platform       | Three bare-metal servers in a co-location data center                    |
| Users                  | Approximately 200,000 monthly active users                              |
| Peak traffic           | Approximately 12,000 concurrent users on Black Friday                   |
| Trigger for migration  | Co-location contract expires in 90 days                                 |
| Known pain points      | 2 to 3 hours of Black Friday downtime (about $80,000 in lost sales); manual deployments take about 4 hours and have caused 3 incidents this quarter from human error |
| Migration approach     | Replatform (minimize application code changes), not a rewrite           |

Full requirement documents:
- `docs/requirements/Business Requirements.md`
- `docs/requirements/Project Constraints.md`
- `docs/requirements/Technical Requirements.md`

---

## 2. Repository Structure

```
retail-edge-aws/
├── docs/
│   ├── requirements/        Business, technical, and constraint requirements
│   ├── architecture/        (reserved for architecture write-ups)
│   └── cost/                 (reserved for cost analysis write-ups)
│
├── diagrams/
│   └── architecture/         draw.io source files, architecture evolution over time
│
├── terraform/                 all infrastructure as code (see terraform/README.md)
│   ├── modules/                one module per AWS component
│   ├── environments/            dev / staging / prod tfvars + backend configs
│   ├── scripts/                  backend setup + per-module validation scripts
│   └── docs/                      dependency graph (terraform graph output)
│
├── load-testing/               capacity planning: load test scripts, results, CloudFormation
│   ├── scripts/                  load_test.sh, setup-app-server.sh
│   ├── cloudformation/            throwaway test infra (network, DB, EC2)
│   └── demo/                       recorded demo of the load test
│
├── reports/                    (reserved for narrative reports: migration, architecture-design, cost)
│
└── .gitignore
```

---

## 3. Architecture Evolution

The `diagrams/architecture/` folder tracks how the design evolved. Each file is a draw.io diagram; open with [Full Diagram](https://drive.google.com/file/d/1f83UDA0XaJHnHJWrDPZP6-UHTxyVNDM8/view?usp=sharing) or the draw.io desktop app.

| File                                              | Stage                          | Summary |
|----------------------------------------------------|----------------------------------|-----------|
| `01-initial-architecture.drawio`                    | Initial proposal                 | High-level three-tier sketch: Route 53, CloudFront, public ALB, EC2 ASG, RDS Multi-AZ, ElastiCache, S3 |
| `02-network-security-architecture.drawio`           | Detailed network + security       | VPC with public/private/database subnets across 2 AZs, security group reference table, public ALB with HTTPS |
| `03-target-architecture.drawio`                     | Target design                      | Adds NAT Gateway, IAM roles, Secrets Manager credential flow (no static DB credentials) |
| `04-retailedge-aws-integration-cicd.drawio`         | Current / as-built                 | Internal ALB behind CloudFront (VPC Origin, no NAT Gateway), WAF at CloudFront, containerized app on EC2, ECR, GitHub OIDC deploy role, planned Lambda + SSM deployment pipeline, CI/CD pipeline diagram, monitoring/logging diagram |

The current, as-built state matches page 1 to 7 of `04-retailedge-aws-integration-cicd.drawio` and the live Terraform code in `terraform/`. Diagrams 01 to 03 are kept for historical record of the design process, not as current documentation.

Current architecture, in short:

```
User
  |
  v
CloudFront (WAF attached)
  |
  |-- "/*"     --> S3 (static web build)
  |-- "/api/*" --> Internal ALB (via CloudFront VPC Origin, no public IP)
                       |
                       v
                EC2 Auto Scaling Group (private subnet, Docker containers)
                       |
           --------------------------
           |                        |
           v                        v
   RDS MySQL (Multi-AZ)     ElastiCache Redis
```

For the full breakdown of modules, environments, and operational commands, see `terraform/README.md`.

---

## 4. Load Testing and Capacity Planning

Before finalizing the Auto Scaling configuration, a load test was run against a single application server to find its practical capacity. Full detail: `load-testing/README.md` and `load-testing/load_test_results.md`.

Summary of results (against the `/health` endpoint):

| Concurrent Users | Success Rate |
|---:|---:|
| 1,000  | 100%   |
| 2,000  | 93.4%  |
| 8,000  | 21.7%  |
| 12,000 | 15.9%  |
| 15,000 | 17.9%  |

Conclusion drawn from the test:

- Roughly 1,000 concurrent users per instance is used as a planning baseline (approximate, since the test only exercises a lightweight endpoint).
- Normal-day Auto Scaling Group max capacity: 10 instances.
- Black Friday scheduled-scaling max capacity: 17 instances (headroom above the approximately 15 instances the 15,000-user target implies).
- These figures are reflected directly in `terraform/environments/prod.tfvars` (`asg_max_size`, `black_friday_max_size`, `black_friday_desired_capacity`).

The `load-testing/cloudformation/` templates provisioned a disposable, separate test environment (not part of the production Terraform state) purely to run this test.

---

## 5. Infrastructure (Terraform)

All production infrastructure lives in `terraform/`. See `terraform/README.md` for:

- Full module breakdown (networking, security groups, ALB, compute, RDS, ElastiCache, S3, CloudFront, WAF, IAM, monitoring)
- Environment differences (dev / staging / prod)
- Backend setup and day-to-day commands (`init`, `plan`, `apply`)
- Required variables with no defaults
- Validation scripts and how to run them
- Current deployment status
- What is intentionally not built yet (the Lambda-based deployment pipeline)

---

## 6. Status Summary

| Area                          | Status                                                              |
|---------------------------------|------------------------------------------------------------------------|
| Requirements gathering            | Done (`docs/requirements/`)                                            |
| Architecture design                | Done, iterated through 4 versions (`diagrams/architecture/`)           |
| Load testing / capacity planning   | Done (`load-testing/`)                                                  |
| Infrastructure as Code (Terraform) | Provisioned for `dev`; `staging` and `prod` tfvars ready but not yet applied |
| Application deployment pipeline    | Not yet built - GitHub Actions pushes to ECR, but nothing deploys the image to running instances yet (Lambda + SSM Run Command is planned, see `terraform/README.md` Section 8) |
| Cost analysis (3-year TCO)         | Not yet written (`docs/cost/`, `reports/cost/` reserved) |
| Architecture design report         | Not yet written (`reports/architecture-design/` reserved) |
| Migration report                   | Not yet written (`reports/migration/` reserved) |

---

## 7. Application Repository

The application itself (Node app, Dockerfile, GitHub Actions workflow) is maintained separately from this infrastructure repo:

https://github.com/aliaagamall/retailedge-app/tree/feat/retailedge-aws-integration

The IAM role that the app repo's GitHub Actions workflow assumes (via OIDC) is defined in this repo, in `terraform/modules/iam`.
