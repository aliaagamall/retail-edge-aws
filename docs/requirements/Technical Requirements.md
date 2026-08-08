# Technical Requirements

## 1. Current Platform

The existing application is a LAMP-based e-commerce platform consisting of:

- Linux
- Apache
- MySQL
- PHP
- Three bare-metal servers

## 2. User and Traffic Requirements

- Approximately 200,000 monthly active users.
- Peak traffic of approximately 12,000 concurrent users during Black Friday.

## 3. Target Architecture

The target solution must follow an AWS three-tier architecture consisting of:

### Web Tier
- Amazon Route 53
- Amazon CloudFront
- Application Load Balancer (ALB)

### Application Tier
- Amazon EC2
- EC2 Auto Scaling Group
- Minimum capacity: 2 instances
- Maximum capacity: 10 instances

### Data Tier
- Amazon RDS for MySQL with Multi-AZ
- Amazon ElastiCache for Redis
- Amazon S3

## 4. Scalability

The application tier must be capable of scaling based on workload and support significant seasonal traffic increases.

## 5. Availability

The architecture must improve availability compared with the current single-environment bare-metal deployment and reduce the risk of service disruption during peak traffic periods.

## 6. Infrastructure as Code

The AWS infrastructure must be provisioned using Terraform to provide a repeatable and consistent deployment process.

## 7. Migration Approach

The migration should prioritize a fast and low-risk transition while minimizing application changes.

The initial migration strategies are:

- Web Server: Replatform
- Application: Replatform
- Database: Replatform