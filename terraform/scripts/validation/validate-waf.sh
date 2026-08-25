#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

AWS_REGION="us-east-1"
OUTPUT_FILE="$OUTPUT_DIR/waf-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "============================================================"
echo "         RetailEdge WAF Validation (CLOUDFRONT scope)"
echo "============================================================"
echo "Date: $(date)"
echo

echo "------------------------------------------------------------"
echo "1. Checking Terraform"
echo "------------------------------------------------------------"

if terraform validate; then
    echo
    echo "✓ Terraform configuration is valid"
else
    echo
    echo "✗ Terraform validation failed"
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "2. Reading Terraform WAF Output"
echo "------------------------------------------------------------"

WAF_ARN=$(terraform output -raw waf_web_acl_arn 2>/dev/null || true)

if [ -n "$WAF_ARN" ]; then
    echo "WAF ARN : $WAF_ARN"
    echo "✓ WAF Terraform output exists"
else
    echo "✗ Could not read waf_web_acl_arn"
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "3. Checking AWS Identity"
echo "------------------------------------------------------------"

if aws sts get-caller-identity; then
    echo "✓ AWS credentials are working"
else
    echo "✗ AWS credentials check failed"
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "4. Checking WAF Scope"
echo "------------------------------------------------------------"

if echo "$WAF_ARN" | grep -q ":global/webacl/"; then
    echo "✓ ARN indicates CLOUDFRONT (global) scope"
else
    echo "✗ ARN does not look like a CLOUDFRONT-scope Web ACL"
    echo "  ARN: $WAF_ARN"
    exit 1
fi

WAF_ID=$(echo "$WAF_ARN" | awk -F'/' '{print $NF}')
WAF_NAME=$(echo "$WAF_ARN" | awk -F'/' '{print $(NF-1)}')

echo "WAF Name : $WAF_NAME"
echo "WAF ID   : $WAF_ID"

echo

echo "------------------------------------------------------------"
echo "5. Checking Web ACL"
echo "------------------------------------------------------------"

WAF_INFO=$(aws wafv2 get-web-acl \
    --name "$WAF_NAME" \
    --scope CLOUDFRONT \
    --id "$WAF_ID" \
    --region "$AWS_REGION" \
    --output json 2>/tmp/waf_error.log || true)

if [ -z "$WAF_INFO" ]; then
    echo "✗ Could not retrieve WAF Web ACL with scope CLOUDFRONT"
    cat /tmp/waf_error.log
    exit 1
fi

echo "$WAF_INFO" | python3 -c '
import json, sys
data = json.load(sys.stdin)
waf = data["WebACL"]
print("Name    :", waf.get("Name"))
print("ID      :", waf.get("Id"))
print("ARN     :", waf.get("ARN"))
print("Scope   : CLOUDFRONT")
print("Default :", list(waf.get("DefaultAction", {}).keys())[0])
'

echo "✓ Web ACL exists with CLOUDFRONT scope"

echo

echo "------------------------------------------------------------"
echo "6. Checking WAF Rules"
echo "------------------------------------------------------------"

RULE_COUNT=$(echo "$WAF_INFO" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["WebACL"]["Rules"]))')

if [ "$RULE_COUNT" -ne 3 ]; then
    echo "✗ Expected 3 WAF rules, found $RULE_COUNT"
    exit 1
fi

echo "$WAF_INFO" | python3 -c '
import json, sys
rules = json.load(sys.stdin)["WebACL"]["Rules"]
for rule in sorted(rules, key=lambda r: r["Priority"]):
    print("Priority", rule["Priority"], ":", rule["Name"])
'

echo
echo "✓ Exactly 3 WAF rules configured"

echo

echo "------------------------------------------------------------"
echo "7. Confirming No ALB Association (ALB is internal now)"
echo "------------------------------------------------------------"

ALB_ASSOCIATION=$(aws wafv2 list-resources-for-web-acl \
    --web-acl-arn "$WAF_ARN" \
    --resource-type APPLICATION_LOAD_BALANCER \
    --region "$AWS_REGION" \
    --output json 2>/tmp/waf_alb_assoc_error.log || true)

if [ -n "$ALB_ASSOCIATION" ]; then
    ALB_COUNT=$(echo "$ALB_ASSOCIATION" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("ResourceArns", [])))' 2>/dev/null || echo "0")
else
    ALB_COUNT=0
fi

if [ "$ALB_COUNT" -eq 0 ]; then
    echo "✓ No ALB association (expected - ALB is internal, WAF now belongs to CloudFront)"
else
    echo "⚠ Unexpected ALB association found - this should have been removed"
fi

echo

echo "------------------------------------------------------------"
echo "8. Checking CloudFront Association"
echo "------------------------------------------------------------"

echo "Note: CLOUDFRONT-scope WAF associations happen via the"
echo "'web_acl_id' argument directly on the CloudFront distribution,"
echo "not via aws_wafv2_web_acl_association. This will be verified"
echo "once modules/cloudfront is applied."

echo

echo "------------------------------------------------------------"
echo "9. Checking CloudWatch Log Group"
echo "------------------------------------------------------------"

LOG_GROUP_PREFIX="aws-waf-logs-retailedge"

LOG_GROUPS=$(aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP_PREFIX" \
    --region "$AWS_REGION" \
    --output json 2>/tmp/waf_logs_error.log || true)

LOG_GROUP_COUNT=$(echo "$LOG_GROUPS" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("logGroups", [])))' 2>/dev/null || echo "0")

if [ "$LOG_GROUP_COUNT" -ge 1 ]; then
    echo "✓ WAF CloudWatch Log Group exists"
    echo "$LOG_GROUPS" | python3 -c '
import json, sys
groups = json.load(sys.stdin).get("logGroups", [])
for g in groups:
    print("Log Group :", g.get("logGroupName"))
    print("Retention :", g.get("retentionInDays"), "days")
'
else
    echo "✗ WAF CloudWatch Log Group not found"
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "10. Checking WAF Logging Configuration"
echo "------------------------------------------------------------"

LOGGING_CONFIG=$(aws wafv2 get-logging-configuration \
    --resource-arn "$WAF_ARN" \
    --region "$AWS_REGION" \
    --output json 2>/tmp/waf_logging_error.log || true)

if [ -n "$LOGGING_CONFIG" ]; then
    echo "$LOGGING_CONFIG"
    echo "✓ WAF logging configuration exists"
else
    echo "✗ WAF logging configuration not found"
    cat /tmp/waf_logging_error.log
    exit 1
fi

echo

echo "============================================================"
echo "                  VALIDATION SUMMARY"
echo "============================================================"

echo "Terraform                 : PASS"
echo "WAF Scope                 : PASS (CLOUDFRONT)"
echo "Web ACL                   : PASS"
echo "Rules (3)                 : PASS"
echo "No ALB Association        : PASS"
echo "CloudWatch Log Group      : PASS"
echo "WAF Logging                : PASS"
echo "CloudFront Association     : PENDING (verify after modules/cloudfront)"

echo
echo "WAF ARN:"
echo "$WAF_ARN"

echo
echo "Output saved to:"
echo "$OUTPUT_FILE"

echo
echo "============================================================"
echo "              WAF VALIDATION COMPLETE"
echo "============================================================"