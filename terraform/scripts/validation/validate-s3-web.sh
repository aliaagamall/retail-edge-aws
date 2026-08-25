#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

AWS_REGION="us-east-1"
OUTPUT_FILE="$OUTPUT_DIR/s3-web-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "============================================================"
echo "            RetailEdge S3 Web Bucket Validation"
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
echo "2. Reading Terraform S3 Web Output"
echo "------------------------------------------------------------"

BUCKET_NAME=$(terraform output -raw web_bucket_name 2>/dev/null || true)

if [ -n "$BUCKET_NAME" ]; then
    echo "S3 Web Bucket Name : $BUCKET_NAME"
    echo "✓ S3 web bucket output exists"
else
    echo "✗ Could not read web_bucket_name"
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
echo "4. Checking S3 Bucket"
echo "------------------------------------------------------------"

if aws s3api head-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION" 2>/tmp/s3web_bucket_error.log; then

    echo "Bucket Name : $BUCKET_NAME"
    echo "✓ S3 bucket exists"
else
    echo "✗ S3 bucket was not found"
    cat /tmp/s3web_bucket_error.log
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "5. Checking Versioning"
echo "------------------------------------------------------------"

VERSIONING_STATUS=$(aws s3api get-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --query 'Status' \
    --output text)

echo "Versioning Status : $VERSIONING_STATUS"

if [ "$VERSIONING_STATUS" = "Enabled" ]; then
    echo "✓ Versioning is enabled"
else
    echo "✗ Versioning is not enabled"
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "6. Checking Server-Side Encryption"
echo "------------------------------------------------------------"

ENCRYPTION=$(aws s3api get-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text 2>/dev/null || true)

echo "Encryption : $ENCRYPTION"

if [ "$ENCRYPTION" = "AES256" ]; then
    echo "✓ AES256 encryption is enabled"
else
    echo "✗ AES256 encryption is not configured"
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "7. Checking Public Access Block"
echo "------------------------------------------------------------"

PUBLIC_ACCESS=$(aws s3api get-public-access-block \
    --bucket "$BUCKET_NAME" \
    --output json 2>/tmp/s3web_public_access_error.log || true)

if [ -z "$PUBLIC_ACCESS" ]; then
    echo "✗ Public Access Block configuration not found"
    cat /tmp/s3web_public_access_error.log
    exit 1
fi

echo "$PUBLIC_ACCESS"

BLOCK_PUBLIC_ACLS=$(echo "$PUBLIC_ACCESS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["PublicAccessBlockConfiguration"]["BlockPublicAcls"])')
IGNORE_PUBLIC_ACLS=$(echo "$PUBLIC_ACCESS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["PublicAccessBlockConfiguration"]["IgnorePublicAcls"])')
BLOCK_PUBLIC_POLICY=$(echo "$PUBLIC_ACCESS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["PublicAccessBlockConfiguration"]["BlockPublicPolicy"])')
RESTRICT_PUBLIC_BUCKETS=$(echo "$PUBLIC_ACCESS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["PublicAccessBlockConfiguration"]["RestrictPublicBuckets"])')

if [ "$BLOCK_PUBLIC_ACLS" = "True" ] &&
   [ "$IGNORE_PUBLIC_ACLS" = "True" ] &&
   [ "$BLOCK_PUBLIC_POLICY" = "True" ] &&
   [ "$RESTRICT_PUBLIC_BUCKETS" = "True" ]; then

    echo "✓ All Public Access Block settings are enabled"
else
    echo "✗ Public Access Block configuration is incorrect"
    exit 1
fi

echo

echo "------------------------------------------------------------"
echo "8. Checking Bucket Policy (expected: not set yet)"
echo "------------------------------------------------------------"

if aws s3api get-bucket-policy \
    --bucket "$BUCKET_NAME" \
    --query 'Policy' \
    --output text > /tmp/s3web_policy.json 2>/tmp/s3web_policy_error.log; then

    echo "Bucket policy exists:"
    cat /tmp/s3web_policy.json
    echo
    echo "⚠ Policy already set - only expected after the CloudFront module is applied"
else
    echo "⚠ No bucket policy yet (expected at this stage - CloudFront module not applied yet)"
fi

echo

echo "------------------------------------------------------------"
echo "9. Checking Bucket Region"
echo "------------------------------------------------------------"

BUCKET_REGION=$(aws s3api get-bucket-location \
    --bucket "$BUCKET_NAME" \
    --query 'LocationConstraint' \
    --output text)

if [ "$BUCKET_REGION" = "None" ]; then
    BUCKET_REGION="us-east-1"
fi

echo "Bucket Region : $BUCKET_REGION"

if [ "$BUCKET_REGION" = "$AWS_REGION" ]; then
    echo "✓ Bucket is in $AWS_REGION"
else
    echo "✗ Bucket region mismatch"
    exit 1
fi

echo

echo "============================================================"
echo "                  VALIDATION SUMMARY"
echo "============================================================"

echo "Terraform               : PASS"
echo "S3 Web Bucket           : PASS"
echo "Versioning              : PASS"
echo "Encryption (AES256)     : PASS"
echo "Public Access Block     : PASS"
echo "Bucket Policy           : PENDING (expected until CloudFront module is applied)"
echo "Bucket Region           : PASS"

echo
echo "S3 Web Bucket:"
echo "$BUCKET_NAME"

echo
echo "Output saved to:"
echo "$OUTPUT_FILE"

echo
echo "============================================================"
echo "            S3 WEB BUCKET VALIDATION COMPLETE"
echo "============================================================"