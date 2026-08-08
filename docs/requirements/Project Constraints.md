# Project Constraints

## 1. Migration Timeline

The migration must be completed within 90 days due to the upcoming co-location contract renewal.

## 2. Application Changes

The migration should minimize application code changes. A replatforming approach is preferred over a major application refactor to reduce migration time and risk.

## 3. Existing Technology

The current application is based on the LAMP stack:

- Linux
- Apache
- MySQL
- PHP

The migration strategy should account for the existing technology stack.

## 4. Traffic Variability

The platform experiences significant seasonal traffic peaks, with approximately 12,000 concurrent users during Black Friday.

The architecture must therefore support variable workloads rather than relying solely on fixed capacity.

## 5. Cost

The current co-location environment costs approximately $18,000 per year.

The AWS solution should be evaluated against the current environment using a three-year Total Cost of Ownership (TCO) comparison.

## 6. Deployment Reliability

The current deployment process requires approximately four hours of manual work and has resulted in production incidents caused by human error.

The target solution should reduce manual deployment effort and improve deployment consistency.

## 7. Required AWS Architecture

The proposed architecture must implement the specified AWS three-tier architecture and required AWS services unless a justified architectural decision requires additional services.