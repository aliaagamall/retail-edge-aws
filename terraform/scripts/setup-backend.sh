#!/bin/bash

set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

BUCKET_NAME="retailedge-tfstate"
LOCK_TABLE="retailedge-tf-lock"

echo "======================================"
echo "RetailEdge Terraform Backend Setup"
echo "======================================"

echo "Region     : $REGION"
echo "Bucket     : $BUCKET_NAME"
echo "Lock Table : $LOCK_TABLE"
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

echo "Creating DynamoDB lock table..."

aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo ""
echo "======================================"
echo "Backend created"
echo "======================================"
echo "Bucket     : $BUCKET_NAME"
echo "Lock Table : $LOCK_TABLE"
echo "Region     : $REGION"