#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUTPUT_FILE="$OUTPUT_DIR/vpc-endpoints-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "========================================="
echo "    VPC Endpoints Validation"
echo "========================================="

VPC_ID=$(terraform output -raw vpc_id)
ENDPOINTS_SG=$(terraform output -raw endpoints_sg_id)

if [[ -z "$VPC_ID" || -z "$ENDPOINTS_SG" ]]; then
  echo "✗ ERROR: Required Terraform outputs are empty."
  echo "Make sure you are running this script from the Terraform root directory."
  exit 1
fi

echo
echo "VPC ID:       $VPC_ID"
echo "Endpoints SG: $ENDPOINTS_SG"

echo
echo "-----------------------------------------"
echo "1. Checking VPC Endpoints"
echo "-----------------------------------------"

ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[].{ID:VpcEndpointId,Name:Tags[?Key==`Name`]|[0].Value,Type:VpcEndpointType,Service:ServiceName,State:State}' \
  --output json)

echo "$ENDPOINTS"

COUNT=$(echo "$ENDPOINTS" | python3 -c '
import json
import sys
data = json.load(sys.stdin)
print(len(data))
')

if [[ "$COUNT" -ne 7 ]]; then
  echo
  echo "✗ Expected 7 VPC Endpoints, found $COUNT"
  exit 1
else
  echo "✓ Found exactly 7 VPC Endpoints"
fi

echo
echo "-----------------------------------------"
echo "2. Checking Endpoint States"
echo "-----------------------------------------"

UNAVAILABLE=$(echo "$ENDPOINTS" | python3 -c '
import json
import sys
data = json.load(sys.stdin)

bad = [x for x in data if x["State"] != "available"]

for x in bad:
    print(f"{x['Name']}: {x['State']}")

sys.exit(1 if bad else 0)
') || {
  echo "✗ One or more endpoints are not available:"
  echo "$UNAVAILABLE"
  exit 1
}

echo "✓ All 7 endpoints are available"

echo
echo "-----------------------------------------"
echo "3. Checking Interface Endpoints"
echo "-----------------------------------------"

INTERFACE_SERVICES=(
  "ecr.api"
  "ecr.dkr"
  "secretsmanager"
  "ssm"
  "ssmmessages"
  "ec2messages"
)

for SERVICE in "${INTERFACE_SERVICES[@]}"; do

  FOUND=$(aws ec2 describe-vpc-endpoints \
    --filters \
      "Name=vpc-id,Values=$VPC_ID" \
      "Name=vpc-endpoint-type,Values=Interface" \
    --query "VpcEndpoints[?contains(ServiceName, '$SERVICE')].VpcEndpointId" \
    --output text)

  if [[ -n "$FOUND" && "$FOUND" != "None" ]]; then
    echo "✓ Interface endpoint exists: $SERVICE"
  else
    echo "✗ Missing interface endpoint: $SERVICE"
    exit 1
  fi

done

echo
echo "-----------------------------------------"
echo "4. Checking Interface Endpoint SG"
echo "-----------------------------------------"

INTERFACE_ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
  --filters \
    "Name=vpc-id,Values=$VPC_ID" \
    "Name=vpc-endpoint-type,Values=Interface" \
  --query 'VpcEndpoints[].VpcEndpointId' \
  --output text)

for ENDPOINT_ID in $INTERFACE_ENDPOINTS; do

  SG_FOUND=$(aws ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids "$ENDPOINT_ID" \
    --query "VpcEndpoints[0].Groups[?GroupId=='$ENDPOINTS_SG'].GroupId" \
    --output text)

  if [[ -n "$SG_FOUND" && "$SG_FOUND" != "None" ]]; then
    echo "✓ $ENDPOINT_ID uses correct Endpoints SG"
  else
    echo "✗ $ENDPOINT_ID does NOT use $ENDPOINTS_SG"
    exit 1
  fi

done

echo
echo "-----------------------------------------"
echo "5. Checking Private DNS"
echo "-----------------------------------------"

PRIVATE_DNS_DISABLED=$(aws ec2 describe-vpc-endpoints \
  --filters \
    "Name=vpc-id,Values=$VPC_ID" \
    "Name=vpc-endpoint-type,Values=Interface" \
  --query 'VpcEndpoints[?PrivateDnsEnabled==`false`].VpcEndpointId' \
  --output text)

if [[ -n "$PRIVATE_DNS_DISABLED" && "$PRIVATE_DNS_DISABLED" != "None" ]]; then
  echo "✗ Private DNS is disabled on:"
  echo "$PRIVATE_DNS_DISABLED"
  exit 1
else
  echo "✓ Private DNS enabled on all Interface Endpoints"
fi

echo
echo "-----------------------------------------"
echo "6. Checking S3 Gateway Endpoint"
echo "-----------------------------------------"

S3_ENDPOINT=$(aws ec2 describe-vpc-endpoints \
  --filters \
    "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[?VpcEndpointType==`Gateway` && contains(ServiceName, `.s3`)].VpcEndpointId' \
  --output text)

if [[ -n "$S3_ENDPOINT" && "$S3_ENDPOINT" != "None" ]]; then
  echo "✓ S3 Gateway Endpoint exists: $S3_ENDPOINT"
else
  echo "✗ S3 Gateway Endpoint is missing"
  exit 1
fi

echo
echo "-----------------------------------------"
echo "7. Final Summary"
echo "-----------------------------------------"

aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[].{Name:Tags[?Key==`Name`]|[0].Value,Type:VpcEndpointType,State:State,Service:ServiceName}' \
  --output table

echo
echo "========================================="
echo "   VPC Endpoints validation passed"
echo "========================================="