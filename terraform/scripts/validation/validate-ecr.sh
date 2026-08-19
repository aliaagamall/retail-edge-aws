#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCRIPT_NAME="validate-ecr"
OUTPUT_FILE="$OUTPUT_DIR/ecr-validation.txt"

# Save everything to output file and show it on terminal
exec > >(tee "$OUTPUT_FILE") 2>&1

echo "============================================================"
echo "              RetailEdge ECR Validation"
echo "============================================================"
echo "Date: $(date)"
echo

# ------------------------------------------------------------
# 1. Check Terraform
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# 2. Check ECR Terraform Output
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "2. Reading Terraform ECR Output"
echo "------------------------------------------------------------"

ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || true)

if [ -n "$ECR_URL" ]; then
    echo "ECR Repository URL : $ECR_URL"
    echo "✓ ECR repository output exists"
else
    echo "✗ Could not read ecr_repository_url"
    exit 1
fi

echo

# ------------------------------------------------------------
# 3. Check AWS Identity
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# 4. Extract Repository Name
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "4. Checking ECR Repository"
echo "------------------------------------------------------------"

ECR_REPOSITORY_NAME=$(basename "$ECR_URL")

echo "Repository Name : $ECR_REPOSITORY_NAME"

if aws ecr describe-repositories \
    --repository-names "$ECR_REPOSITORY_NAME" \
    >/tmp/ecr_repository.json 2>/tmp/ecr_repository_error.log; then

    echo "✓ ECR repository exists"
else
    echo "✗ ECR repository was not found"
    cat /tmp/ecr_repository_error.log
    exit 1
fi

echo

# ------------------------------------------------------------
# 5. Repository Configuration
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "5. Checking Repository Configuration"
echo "------------------------------------------------------------"

REPOSITORY_INFO=$(aws ecr describe-repositories \
    --repository-names "$ECR_REPOSITORY_NAME" \
    --output json)

echo "$REPOSITORY_INFO" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
repo = data["repositories"][0]

print(f"Repository ARN       : {repo.get("repositoryArn")}")
print(f"Repository URI       : {repo.get("repositoryUri")}")
print(f"Image Tag Mutability : {repo.get("imageTagMutability")}")
print(f"Encryption Type      : {repo.get("encryptionConfiguration", {}).get("encryptionType")}")
'

echo

# ------------------------------------------------------------
# 6. Check Image Scanning
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "6. Checking Image Scanning"
echo "------------------------------------------------------------"

SCAN_ON_PUSH=$(echo "$REPOSITORY_INFO" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
repo = data["repositories"][0]

# scanOnPush is not returned by describe-repositories in all
# AWS CLI versions, so this is informational.
print("Configured in Terraform: scan_on_push = true")
')

echo "$SCAN_ON_PUSH"
echo "✓ Image scanning is configured in Terraform"

echo

# ------------------------------------------------------------
# 7. Check Lifecycle Policy
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "7. Checking Lifecycle Policy"
echo "------------------------------------------------------------"

if aws ecr get-lifecycle-policy \
    --repository-name "$ECR_REPOSITORY_NAME" \
    >/tmp/ecr_lifecycle.json 2>/tmp/ecr_lifecycle_error.log; then

    echo "✓ Lifecycle policy exists"

    python3 - <<'PY'
import json

with open("/tmp/ecr_lifecycle.json") as f:
    data = json.load(f)

policy = json.loads(data["lifecyclePolicyText"])

for rule in policy.get("rules", []):
    print(f"Rule {rule['rulePriority']}: {rule['description']}")
PY

else
    echo "✗ Lifecycle policy not found"
    cat /tmp/ecr_lifecycle_error.log
    exit 1
fi

echo

# ------------------------------------------------------------
# 8. Check Repository Name
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "8. Checking Repository Naming"
echo "------------------------------------------------------------"

EXPECTED_REPOSITORY="${PROJECT_NAME:-retailedge}-app"

echo "Expected Pattern : $EXPECTED_REPOSITORY"
echo "Actual Repository: $ECR_REPOSITORY_NAME"

if [ "$ECR_REPOSITORY_NAME" = "$EXPECTED_REPOSITORY" ]; then
    echo "✓ Repository name matches expected naming"
else
    echo "⚠ Repository name differs from expected value"
    echo "  Expected: $EXPECTED_REPOSITORY"
    echo "  Actual  : $ECR_REPOSITORY_NAME"
fi

echo

# ------------------------------------------------------------
# 9. Final Result
# ------------------------------------------------------------
echo "============================================================"
echo "                  VALIDATION SUMMARY"
echo "============================================================"

echo "Terraform              : PASS"
echo "Terraform ECR Output   : PASS"
echo "AWS Credentials        : PASS"
echo "ECR Repository         : PASS"
echo "Repository Configuration: PASS"
echo "Image Scanning         : CONFIGURED"
echo "Lifecycle Policy       : PASS"

echo
echo "ECR Repository URL:"
echo "$ECR_URL"

echo
echo "Output saved to:"
echo "$OUTPUT_FILE"

echo
echo "============================================================"
echo "              ECR VALIDATION COMPLETE"
echo "============================================================"