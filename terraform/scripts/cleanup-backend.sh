#!/bin/bash

set -e

REGION="us-east-1"
BUCKET_NAME="retailedge-tfstate"

echo "======================================"
echo "RetailEdge Terraform Backend Cleanup"
echo "======================================"

echo "Region : $REGION"
echo "Bucket : $BUCKET_NAME"
echo ""

echo "WARNING: This will permanently delete"
echo "the Terraform backend bucket and all"
echo "its contents, including object versions."
echo ""

read -p "Are you sure? Type 'DELETE' to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo ""
echo "Checking if bucket exists..."

if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Bucket does not exist."
  exit 0
fi

echo "Deleting all object versions and delete markers..."

aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --output json |
python3 -c '
import json
import sys

data = json.load(sys.stdin)

objects = []

for obj in data.get("Versions", []):
    objects.append({
        "Key": obj["Key"],
        "VersionId": obj["VersionId"]
    })

for marker in data.get("DeleteMarkers", []):
    objects.append({
        "Key": marker["Key"],
        "VersionId": marker["VersionId"]
    })

if objects:
    print(json.dumps({"Objects": objects, "Quiet": True}))
'

OBJECTS=$(aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --output json |
python3 -c '
import json
import sys

data = json.load(sys.stdin)

objects = []

for obj in data.get("Versions", []):
    objects.append({
        "Key": obj["Key"],
        "VersionId": obj["VersionId"]
    })

for marker in data.get("DeleteMarkers", []):
    objects.append({
        "Key": marker["Key"],
        "VersionId": marker["VersionId"]
    })

print(json.dumps({"Objects": objects, "Quiet": True}))
')

if [ "$OBJECTS" != '{"Objects": [], "Quiet": true}' ]; then
  echo "$OBJECTS" | aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete file:///dev/stdin
else
  echo "Bucket is already empty."
fi

echo "Deleting S3 bucket..."

aws s3api delete-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION"

echo ""
echo "======================================"
echo "Backend cleanup completed"
echo "======================================"
echo "Bucket deleted : $BUCKET_NAME"
echo "Region         : $REGION"
echo "======================================"
