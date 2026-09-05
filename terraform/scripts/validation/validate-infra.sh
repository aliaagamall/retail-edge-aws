#!/usr/bin/env bash
#
# verify-infra.sh
#
# Post-`terraform apply` sanity check for the RetailEdge infrastructure.
#
# IMPORTANT: at this stage there is no application deployment mechanism
# wired up yet (CodeDeploy was dropped, Lambda+SSM deploy is not built).
# That means two things are EXPECTED right now, not failures:
#   1. ALB target group will show UNHEALTHY (no container listening on
#      the app port, so /health never responds).
#   2. The web S3 bucket will be empty (React build was never synced).
# This script separates "the resource exists and is correctly configured"
# (real checks) from "the application is actually running" (expected to
# be red right now, reported as INFO not FAIL).
#
# Usage:
#   cd terraform
#   ./scripts/verify-infra.sh dev
#
# Requires: aws cli (configured), jq, terraform (run from the terraform/
# directory so `terraform output` can read the local state).

set -uo pipefail

ENV="${1:-dev}"
PROJECT="retailedge"
PREFIX="${PROJECT}-${ENV}"

# ---------------------------------------------------------------------
# Save a plain-text copy of this run's output.
# Assumes the script is run from the terraform/ directory (as documented
# below), so ./validation-results resolves to terraform/validation-results
# on disk - e.g. D:\cloud\projects\retail-edge-aws\terraform\validation-results
# on Windows. Override with VALIDATION_RESULTS_DIR if you run it from
# somewhere else.
# ---------------------------------------------------------------------
RESULTS_DIR="${VALIDATION_RESULTS_DIR:-./validation-results}"
mkdir -p "$RESULTS_DIR"
LOGFILE="${RESULTS_DIR}/validate-infra-${ENV}-$(date +%Y%m%d-%H%M%S).log"
# Mirror everything to the terminal (with colors) and to the logfile
# (colors stripped, so it's readable in a plain text editor).
exec > >(tee >(sed -r "s/\x1B\[[0-9;]*[mK]//g" > "$LOGFILE")) 2>&1
echo "Logging this run to: $LOGFILE"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

PASS=0
FAIL=0
INFO=0

pass() { echo "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
info() { echo "${YELLOW}[INFO]${NC} $1 (expected at this stage)"; INFO=$((INFO+1)); }
section() { echo; echo "${BLUE}== $1 ==${NC}"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1"; exit 2; }
}
need aws
need jq
need terraform

section "Reading Terraform outputs"
TF_OUT=$(terraform output -json 2>/dev/null) || { echo "Could not read terraform output. Run this from the terraform/ directory."; exit 2; }

out() { echo "$TF_OUT" | jq -r ".${1}.value // empty"; }

ALB_ARN=$(out alb_arn)
ALB_DNS=$(out alb_dns_name)
TG_ARN=$(out target_group_arn)
ASG_NAME=$(out asg_name)
DB_ID=$(out db_instance_id)
REDIS_ID=$(out redis_replication_group_id)
DIST_ID=$(out distribution_id)
DIST_DOMAIN=$(out distribution_domain_name)
ECR_URL=$(out ecr_repository_url)
WEB_BUCKET=$(out web_bucket_name)
WAF_ARN=$(out waf_web_acl_arn)
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

if [ -z "$ALB_ARN" ] || [ -z "$ASG_NAME" ]; then
  fail "Terraform outputs look empty - was 'terraform apply' actually completed?"
  exit 1
fi
pass "Terraform outputs loaded (region: $REGION)"

# ---------------------------------------------------------------------
section "Networking"
# ---------------------------------------------------------------------
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PREFIX}-vpc" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  pass "VPC exists ($VPC_ID)"
else
  fail "VPC not found"
fi

SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'length(Subnets)' --output text 2>/dev/null)
[ "${SUBNET_COUNT:-0}" -ge 6 ] && pass "Subnets present ($SUBNET_COUNT found, expected 6)" \
  || fail "Expected 6 subnets, found ${SUBNET_COUNT:-0}"

# ---------------------------------------------------------------------
section "ALB"
# ---------------------------------------------------------------------
ALB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null)
[ "$ALB_STATE" == "active" ] && pass "ALB is active ($ALB_DNS)" \
  || fail "ALB state is '$ALB_STATE', expected 'active'"

TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].TargetHealth.State' --output text 2>/dev/null)
if echo "$TARGET_HEALTH" | grep -q "healthy" && ! echo "$TARGET_HEALTH" | grep -qv "healthy"; then
  pass "All ALB targets healthy"
else
  info "ALB targets not healthy yet ($TARGET_HEALTH) - no app container deployed"
fi

# ---------------------------------------------------------------------
section "Compute / Auto Scaling Group"
# ---------------------------------------------------------------------
ASG_JSON=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" 2>/dev/null)
DESIRED=$(echo "$ASG_JSON" | jq -r '.AutoScalingGroups[0].DesiredCapacity // "0"')
IN_SERVICE=$(echo "$ASG_JSON" | jq -r '[.AutoScalingGroups[0].Instances[]? | select(.LifecycleState=="InService")] | length')
pass "ASG exists (desired=$DESIRED, in-service=$IN_SERVICE)"

if [ "$DESIRED" != "0" ]; then
  echo "  ${YELLOW}Reminder:${NC} health_check_type=ELB means these instances will be"
  echo "  cycled/replaced by the ASG once the grace period passes, since no"
  echo "  app container is answering /health yet. Consider scaling to 0 until"
  echo "  a deployment mechanism exists (see warning above)."
fi

# ---------------------------------------------------------------------
section "RDS"
# ---------------------------------------------------------------------
RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)
[ "$RDS_STATUS" == "available" ] && pass "RDS instance available ($DB_ID)" \
  || fail "RDS status is '$RDS_STATUS', expected 'available'"

# ---------------------------------------------------------------------
section "ElastiCache (Redis)"
# ---------------------------------------------------------------------
REDIS_STATUS=$(aws elasticache describe-replication-groups --replication-group-id "$REDIS_ID" \
  --query 'ReplicationGroups[0].Status' --output text 2>/dev/null)
[ "$REDIS_STATUS" == "available" ] && pass "Redis replication group available ($REDIS_ID)" \
  || fail "Redis status is '$REDIS_STATUS', expected 'available'"

# ---------------------------------------------------------------------
section "CloudFront"
# ---------------------------------------------------------------------
CF_STATUS=$(aws cloudfront get-distribution --id "$DIST_ID" \
  --query 'Distribution.Status' --output text 2>/dev/null)
if [ "$CF_STATUS" == "Deployed" ]; then
  pass "CloudFront distribution deployed ($DIST_DOMAIN)"
else
  info "CloudFront status is '$CF_STATUS' - full propagation can take 15-20 min after apply"
fi

# ---------------------------------------------------------------------
section "WAF"
# ---------------------------------------------------------------------
WAF_NAME="${PREFIX}-waf"
WAF_FOUND=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
  --query "WebACLs[?Name=='${WAF_NAME}'].Name" --output text 2>/dev/null)
[ "$WAF_FOUND" == "$WAF_NAME" ] && pass "WAF Web ACL exists ($WAF_NAME)" \
  || fail "WAF Web ACL '$WAF_NAME' not found"

# ---------------------------------------------------------------------
section "ECR"
# ---------------------------------------------------------------------
ECR_REPO="${PROJECT}-${ENV}-app"
IMAGE_COUNT=$(aws ecr describe-images --repository-name "$ECR_REPO" \
  --query 'length(imageDetails)' --output text 2>/dev/null)
if [ -n "$IMAGE_COUNT" ] && [ "$IMAGE_COUNT" != "None" ]; then
  [ "$IMAGE_COUNT" -gt 0 ] && pass "ECR repo has $IMAGE_COUNT image(s)" \
    || info "ECR repo exists but has 0 images - no image pushed yet"
else
  fail "Could not read ECR repo '$ECR_REPO' - does it exist?"
fi

# ---------------------------------------------------------------------
section "S3 (web bucket)"
# ---------------------------------------------------------------------
OBJ_COUNT=$(aws s3api list-objects-v2 --bucket "$WEB_BUCKET" \
  --query 'length(Contents)' --output text 2>/dev/null)
if [ -n "$OBJ_COUNT" ] && [ "$OBJ_COUNT" != "None" ] && [ "$OBJ_COUNT" -gt 0 ]; then
  pass "Web bucket has $OBJ_COUNT object(s)"
else
  info "Web bucket '$WEB_BUCKET' is empty - React build not synced yet"
fi

# ---------------------------------------------------------------------
section "Monitoring"
# ---------------------------------------------------------------------
SNS_TOPIC_ARN="arn:aws:sns:${REGION}:$(aws sts get-caller-identity --query Account --output text):${PREFIX}-monitoring-alerts"
SUB_STATUS=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" \
  --query 'Subscriptions[0].SubscriptionArn' --output text 2>/dev/null)
if [ "$SUB_STATUS" == "PendingConfirmation" ]; then
  fail "SNS email subscription is PENDING - confirm the email sent to alert_email or you will not get alerts"
elif [ -n "$SUB_STATUS" ] && [ "$SUB_STATUS" != "None" ]; then
  pass "SNS email subscription confirmed"
else
  fail "No SNS subscription found on $SNS_TOPIC_ARN"
fi

ALARM_JSON=$(aws cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" 2>/dev/null)
ALARM_COUNT=$(echo "$ALARM_JSON" | jq '.MetricAlarms | length')
echo "  Alarms found: $ALARM_COUNT"
echo "$ALARM_JSON" | jq -r '.MetricAlarms[] | "  - \(.AlarmName): \(.StateValue)"'
INSUFFICIENT=$(echo "$ALARM_JSON" | jq '[.MetricAlarms[] | select(.StateValue=="INSUFFICIENT_DATA")] | length')
ALARM_STATE=$(echo "$ALARM_JSON" | jq -r '[.MetricAlarms[] | select(.StateValue=="ALARM")] | length')
[ "$ALARM_COUNT" -gt 0 ] && pass "$ALARM_COUNT alarms exist in CloudWatch" || fail "No alarms found with prefix $PREFIX"
[ "$INSUFFICIENT" -gt 0 ] && info "$INSUFFICIENT alarm(s) in INSUFFICIENT_DATA - normal right after apply, no traffic/metrics yet"
[ "$ALARM_STATE" -gt 0 ] && fail "$ALARM_STATE alarm(s) already in ALARM state - investigate"

DASHBOARD_NAME="${PREFIX}-overview"
aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" >/dev/null 2>&1 \
  && pass "Dashboard exists ($DASHBOARD_NAME)" \
  || fail "Dashboard '$DASHBOARD_NAME' not found"

# ---------------------------------------------------------------------
section "Summary"
# ---------------------------------------------------------------------
echo "${GREEN}PASS: $PASS${NC}   ${YELLOW}INFO: $INFO${NC}   ${RED}FAIL: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "${RED}Some checks failed - review above before moving on.${NC}"
  exit 1
else
  echo
  echo "${GREEN}Infrastructure looks correctly provisioned.${NC}"
  echo "INFO items above are expected until the app deployment pipeline is built."
  exit 0
fi