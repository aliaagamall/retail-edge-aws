#!/bin/bash

set -e

REGION="us-east-1"
BUCKET_NAME="retailedge-tfstate"

echo "======================================"
echo "RetailEdge Terraform Backend Setup"
echo "======================================"

echo "Region : $REGION"
echo "Bucket : $BUCKET_NAME"
echo ""

echo "Creating S3 bucket..."

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION"

echo "Enabling versioning..."

aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "Enabling encryption..."

aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

echo "Blocking public access..."

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ""
echo "======================================"
echo "Backend created"
echo "======================================"
echo "Bucket : $BUCKET_NAME"
echo "Region : $REGION"
echo ""
echo "Terraform S3 native locking:"
echo "use_lockfile = true"
echo "======================================"
