#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUTPUT_FILE="$OUTPUT_DIR/iam-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "========================================="
echo "       RetailEdge IAM Validation"
echo "========================================="
echo "Date: $(date)"
echo


ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)

echo "AWS Account ID: $ACCOUNT_ID"
echo


echo "-----------------------------------------"
echo "1. Checking Terraform"
echo "-----------------------------------------"

terraform validate

echo "✓ Terraform configuration is valid"
echo


echo "-----------------------------------------"
echo "2. Reading Terraform IAM Outputs"
echo "-----------------------------------------"

INSTANCE_PROFILE=$(terraform output -raw ec2_instance_profile_name)

GITHUB_ROLE_ARN=$(terraform output -raw github_deploy_role_arn)

GITHUB_ROLE="${GITHUB_ROLE_ARN##*/}"

echo "EC2 Instance Profile : $INSTANCE_PROFILE"
echo "GitHub Deploy Role   : $GITHUB_ROLE"
echo


echo "-----------------------------------------"
echo "3. Checking EC2 Instance Profile"
echo "-----------------------------------------"

if aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --output json > /dev/null 2>&1; then

    echo "✓ Instance Profile exists: $INSTANCE_PROFILE"

else
    echo "✗ Instance Profile NOT found: $INSTANCE_PROFILE"
    exit 1
fi

# Get EC2 Role attached to Instance Profile

EC2_ROLE=$(aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --query 'InstanceProfile.Roles[0].RoleName' \
    --output text)

if [ -z "$EC2_ROLE" ] || [ "$EC2_ROLE" = "None" ]; then
    echo "✗ No IAM Role attached to Instance Profile"
    exit 1
fi

echo "✓ EC2 Role: $EC2_ROLE"
echo


echo "-----------------------------------------"
echo "4. Checking EC2 IAM Role"
echo "-----------------------------------------"

if aws iam get-role \
    --role-name "$EC2_ROLE" \
    --output json > /dev/null 2>&1; then

    echo "✓ EC2 Role exists: $EC2_ROLE"

else
    echo "✗ EC2 Role NOT found: $EC2_ROLE"
    exit 1
fi

echo

echo "-----------------------------------------"
echo "5. Checking EC2 Role Policies"
echo "-----------------------------------------"

echo "Attached policies:"

aws iam list-attached-role-policies \
    --role-name "$EC2_ROLE" \
    --query 'AttachedPolicies[].PolicyName' \
    --output table

echo

echo "Checking required EC2 policies..."

REQUIRED_EC2_POLICIES=(
    "AmazonSSMManagedInstanceCore"
    "retailedge-dev-secrets-read"
    "retailedge-dev-ecr-pull"
)

for POLICY in "${REQUIRED_EC2_POLICIES[@]}"; do

    if aws iam list-attached-role-policies \
        --role-name "$EC2_ROLE" \
        --query "AttachedPolicies[?PolicyName=='$POLICY'].PolicyName" \
        --output text | grep -q "$POLICY"; then

        echo "✓ $POLICY"

    else
        echo "✗ Missing policy: $POLICY"
        exit 1
    fi

done

echo

echo "-----------------------------------------"
echo "6. Checking EC2 Trust Policy"
echo "-----------------------------------------"

EC2_TRUST=$(aws iam get-role \
    --role-name "$EC2_ROLE" \
    --query 'Role.AssumeRolePolicyDocument.Statement[?Effect==`Allow`].Principal.Service' \
    --output text)

if echo "$EC2_TRUST" | grep -q "ec2.amazonaws.com"; then

    echo "✓ EC2 is trusted by the IAM Role"

else

    echo "✗ EC2 trust relationship is incorrect"
    echo "Current principal: $EC2_TRUST"
    exit 1

fi

echo


echo "-----------------------------------------"
echo "7. Checking GitHub OIDC Provider"
echo "-----------------------------------------"

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$OIDC_ARN" \
    --output json > /dev/null 2>&1; then

    echo "✓ GitHub OIDC Provider exists"

else

    echo "✗ GitHub OIDC Provider NOT found"
    exit 1

fi

echo


echo "-----------------------------------------"
echo "8. Checking GitHub Deploy Role"
echo "-----------------------------------------"

if aws iam get-role \
    --role-name "$GITHUB_ROLE" \
    --output json > /dev/null 2>&1; then

    echo "✓ GitHub Deploy Role exists: $GITHUB_ROLE"

else

    echo "✗ GitHub Deploy Role NOT found: $GITHUB_ROLE"
    exit 1

fi

echo


echo "-----------------------------------------"
echo "9. Checking GitHub Role Policies"
echo "-----------------------------------------"

aws iam list-attached-role-policies \
    --role-name "$GITHUB_ROLE" \
    --query 'AttachedPolicies[].PolicyName' \
    --output table

echo

echo "-----------------------------------------"
echo "10. Checking GitHub OIDC Trust Policy"
echo "-----------------------------------------"

GITHUB_TRUST=$(aws iam get-role \
    --role-name "$GITHUB_ROLE" \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json)

echo "$GITHUB_TRUST" | jq .

echo

if echo "$GITHUB_TRUST" | jq -e \
    '.Statement[] |
     select(.Effect == "Allow") |
     .Principal.Federated |
     contains("token.actions.githubusercontent.com")' \
    > /dev/null; then

    echo "✓ GitHub OIDC is trusted"

else

    echo "✗ GitHub OIDC trust relationship NOT found"
    exit 1

fi

echo


echo "-----------------------------------------"
echo "11. Checking GitHub Repository Restriction"
echo "-----------------------------------------"

if echo "$GITHUB_TRUST" | grep -q "aliaagamall/retailedge-app"; then

    echo "✓ GitHub repository restriction found"
    echo "  Repository: aliaagamall/retailedge-app"

else

    echo "⚠ GitHub repository restriction not detected"
    echo "  Check the trust policy manually"
fi

echo

echo "-----------------------------------------"
echo "12. Checking GitHub Deploy Policy"
echo "-----------------------------------------"

GITHUB_POLICY_ARN=$(aws iam list-attached-role-policies \
    --role-name "$GITHUB_ROLE" \
    --query "AttachedPolicies[?PolicyName=='retailedge-dev-github-deploy-policy'].PolicyArn" \
    --output text)

if [ -z "$GITHUB_POLICY_ARN" ] || [ "$GITHUB_POLICY_ARN" = "None" ]; then

    echo "✗ GitHub deploy policy NOT found"
    exit 1

fi

echo "✓ GitHub deploy policy found"
echo "  Policy ARN: $GITHUB_POLICY_ARN"
echo

# Get default policy version

POLICY_VERSION=$(aws iam get-policy \
    --policy-arn "$GITHUB_POLICY_ARN" \
    --query 'Policy.DefaultVersionId' \
    --output text)

GITHUB_POLICY=$(aws iam get-policy-version \
    --policy-arn "$GITHUB_POLICY_ARN" \
    --version-id "$POLICY_VERSION" \
    --query 'PolicyVersion.Document' \
    --output json)

echo "Checking required permissions..."

# --------------------------------------------------
# SSM permissions
# --------------------------------------------------

if echo "$GITHUB_POLICY" | jq -e '
    .Statement[] |
    select(.Effect == "Allow") |
    .Action |
    if type == "array"
    then index("ssm:PutParameter") != null
    else . == "ssm:PutParameter"
    end
' > /dev/null; then

    echo "✓ ssm:PutParameter"

else

    echo "✗ Missing ssm:PutParameter"
    exit 1

fi

if echo "$GITHUB_POLICY" | jq -e '
    .Statement[] |
    select(.Effect == "Allow") |
    .Action |
    if type == "array"
    then index("ssm:GetParameter") != null
    else . == "ssm:GetParameter"
    end
' > /dev/null; then

    echo "✓ ssm:GetParameter"

else

    echo "✗ Missing ssm:GetParameter"
    exit 1

fi

# --------------------------------------------------
# ECR permissions
# --------------------------------------------------

REQUIRED_ECR_ACTIONS=(
    "ecr:GetAuthorizationToken"
    "ecr:BatchCheckLayerAvailability"
    "ecr:PutImage"
    "ecr:InitiateLayerUpload"
    "ecr:UploadLayerPart"
    "ecr:CompleteLayerUpload"
)

echo
echo "Checking required ECR permissions..."

for ACTION in "${REQUIRED_ECR_ACTIONS[@]}"; do

    if echo "$GITHUB_POLICY" | jq -e \
        --arg ACTION "$ACTION" '
        [.Statement[].Action]
        | flatten
        | index($ACTION) != null
        ' > /dev/null; then

        echo "✓ $ACTION"

    else

        echo "✗ Missing $ACTION"
        exit 1

    fi

done

# --------------------------------------------------
# CodeDeploy must NOT exist
# --------------------------------------------------

echo
echo "Checking that CodeDeploy permissions were removed..."

if echo "$GITHUB_POLICY" | jq -e '
    [.Statement[].Action] |
    flatten |
    map(select(type == "string" and startswith("codedeploy:"))) |
    length == 0
' > /dev/null; then

    echo "✓ No CodeDeploy permissions found"

else

    echo "✗ CodeDeploy permissions still exist"
    echo "$GITHUB_POLICY" | jq '
        [.Statement[].Action] |
        flatten |
        map(select(type == "string" and startswith("codedeploy:")))
    '
    exit 1

fi

echo
echo "✓ GitHub Deploy Policy validation passed"
echo

# --------------------------------------------------
# 13. IAM Role Summary
# --------------------------------------------------

echo "-----------------------------------------"
echo "13. IAM Summary"
echo "-----------------------------------------"

echo
echo "EC2 Role:"
echo "  $EC2_ROLE"

echo
echo "EC2 Instance Profile:"
echo "  $INSTANCE_PROFILE"

echo
echo "GitHub Deploy Role:"
echo "  $GITHUB_ROLE"

echo
echo "GitHub Deploy Role ARN:"
echo "  $GITHUB_ROLE_ARN"

echo
echo "GitHub OIDC Provider:"
echo "  $OIDC_ARN"

echo

echo "========================================="
echo "       IAM Validation Complete 😋"
echo "========================================="