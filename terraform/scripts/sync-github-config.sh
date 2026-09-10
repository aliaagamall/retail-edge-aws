#!/usr/bin/env bash

set -euo pipefail

APP_REPO="${APP_REPO:-aliaagamall/retailedge-app}"
AWS_REGION="${AWS_REGION:-us-east-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/.."

echo "== RetailEdge GitHub Configuration Sync =="

if ! command -v terraform >/dev/null 2>&1; then
  echo "ERROR: terraform is not installed."
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is not installed."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI is not authenticated."
  echo "Run: gh auth login"
  exit 1
fi

if [[ ! -d "$TERRAFORM_DIR" ]]; then
  echo "ERROR: Terraform directory not found: $TERRAFORM_DIR"
  exit 1
fi

cd "$TERRAFORM_DIR"

echo
echo "Target repository:"
echo "  $APP_REPO"

echo
echo "Reading Terraform outputs..."

GITHUB_DEPLOY_ROLE_ARN="$(terraform output -raw github_deploy_role_arn)"
ECR_REPOSITORY_URL="$(terraform output -raw ecr_repository_url)"
WEB_BUCKET_NAME="$(terraform output -raw web_bucket_name)"
CLOUDFRONT_DISTRIBUTION_ID="$(terraform output -raw distribution_id)"
DEPLOY_LAMBDA_FUNCTION_NAME="$(terraform output -raw deploy_lambda_function_name)"

if [[ -z "$GITHUB_DEPLOY_ROLE_ARN" ]]; then
  echo "ERROR: github_deploy_role_arn is empty."
  exit 1
fi

if [[ -z "$ECR_REPOSITORY_URL" ]]; then
  echo "ERROR: ecr_repository_url is empty."
  exit 1
fi

if [[ -z "$WEB_BUCKET_NAME" ]]; then
  echo "ERROR: web_bucket_name is empty."
  exit 1
fi

if [[ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
  echo "ERROR: distribution_id is empty."
  exit 1
fi

if [[ -z "$DEPLOY_LAMBDA_FUNCTION_NAME" ]]; then
  echo "ERROR: deploy_lambda_function_name is empty."
  exit 1
fi

echo
echo "Terraform outputs loaded successfully."

echo
echo "Updating GitHub Secret..."

gh secret set AWS_DEPLOY_ROLE_ARN \
  --repo "$APP_REPO" \
  --body "$GITHUB_DEPLOY_ROLE_ARN"

echo "  AWS_DEPLOY_ROLE_ARN"

echo
echo "Updating GitHub Variables..."

gh variable set AWS_REGION \
  --repo "$APP_REPO" \
  --body "$AWS_REGION"

gh variable set ECR_REPOSITORY_URL \
  --repo "$APP_REPO" \
  --body "$ECR_REPOSITORY_URL"

gh variable set WEB_BUCKET_NAME \
  --repo "$APP_REPO" \
  --body "$WEB_BUCKET_NAME"

gh variable set CLOUDFRONT_DISTRIBUTION_ID \
  --repo "$APP_REPO" \
  --body "$CLOUDFRONT_DISTRIBUTION_ID"

gh variable set DEPLOY_LAMBDA_FUNCTION_NAME \
  --repo "$APP_REPO" \
  --body "$DEPLOY_LAMBDA_FUNCTION_NAME"

echo "  AWS_REGION"
echo "  ECR_REPOSITORY_URL"
echo "  WEB_BUCKET_NAME"
echo "  CLOUDFRONT_DISTRIBUTION_ID"
echo "  DEPLOY_LAMBDA_FUNCTION_NAME"

echo
echo "GitHub configuration sync completed successfully."