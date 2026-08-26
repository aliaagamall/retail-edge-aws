#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUTPUT_FILE="$OUTPUT_DIR/cloudfront-validation.txt"
exec > >(tee "$OUTPUT_FILE") 2>&1

echo "============================================================"
echo "            RetailEdge CloudFront Validation"
echo "============================================================"
echo "Date: $(date)"
echo

echo "1. Checking Terraform"
terraform validate && echo "✓ valid"
echo

DIST_ID=$(terraform output -raw distribution_id 2>/dev/null || true)
DOMAIN=$(terraform output -raw distribution_domain_name 2>/dev/null || true)

echo "Distribution ID     : ${DIST_ID:-Not found}"
echo "Distribution Domain : ${DOMAIN:-Not found}"
echo

if [ -z "$DIST_ID" ]; then
  echo "✗ distribution_id output not found"
  exit 1
fi

echo "2. Checking Distribution Status"
STATUS=$(aws cloudfront get-distribution --id "$DIST_ID" --query 'Distribution.Status' --output text)
ENABLED=$(aws cloudfront get-distribution --id "$DIST_ID" --query 'Distribution.DistributionConfig.Enabled' --output text)
echo "Status  : $STATUS"
echo "Enabled : $ENABLED"
[ "$ENABLED" = "True" ] && echo "✓ Distribution enabled"
echo

echo "3. Checking Origins"
aws cloudfront get-distribution --id "$DIST_ID" \
  --query 'Distribution.DistributionConfig.Origins.Items[].{Id:Id,Domain:DomainName}' \
  --output table
echo

echo "4. Checking WAF Association"
WAF_ID=$(aws cloudfront get-distribution --id "$DIST_ID" --query 'Distribution.DistributionConfig.WebACLId' --output text)
if [ -n "$WAF_ID" ] && [ "$WAF_ID" != "None" ]; then
  echo "✓ WAF attached: $WAF_ID"
else
  echo "✗ No WAF attached"
  exit 1
fi
echo

echo "5. Checking S3 Bucket Policy (only set after step 2 below)"
WEB_BUCKET=$(terraform output -raw web_bucket_name 2>/dev/null || true)
if aws s3api get-bucket-policy --bucket "$WEB_BUCKET" --query 'Policy' --output text >/tmp/cf_policy.json 2>/dev/null; then
  echo "✓ Bucket policy exists"
  cat /tmp/cf_policy.json
else
  echo "⚠ No bucket policy yet - expected until s3-web.tf is wired to the distribution ARN (step 2)"
fi
echo

echo "6. Testing HTTPS via CloudFront domain (deployment can take a few minutes)"
if [ -n "$DOMAIN" ]; then
  curl -sk -o /dev/null -w "HTTP Status: %{http_code}\n" "https://$DOMAIN"
fi

echo
echo "============================================================"
echo "              CLOUDFRONT VALIDATION COMPLETE"
echo "============================================================"