#!/usr/bin/env bash

set -euo pipefail

REGION="us-east-1"
ECR_REPOSITORY="retailedge-dev-app"
S3_BUCKET="retailedge-dev-web-631447263037"

echo "Cleaning ECR repository..."
aws ecr delete-repository \
  --repository-name "$ECR_REPOSITORY" \
  --force \
  --region "$REGION"

echo "Cleaning S3 bucket versions and delete markers..."

VERSIONS=$(aws s3api list-object-versions \
  --bucket "$S3_BUCKET" \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json)

if [ "$(echo "$VERSIONS" | jq '.Objects | length')" -gt 0 ]; then
  aws s3api delete-objects \
    --bucket "$S3_BUCKET" \
    --delete "$VERSIONS"
fi

DELETE_MARKERS=$(aws s3api list-object-versions \
  --bucket "$S3_BUCKET" \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json)

if [ "$(echo "$DELETE_MARKERS" | jq '.Objects | length')" -gt 0 ]; then
  aws s3api delete-objects \
    --bucket "$S3_BUCKET" \
    --delete "$DELETE_MARKERS"
fi

echo "Cleanup completed."
echo "Run: terraform destroy"