#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUTPUT_FILE="$OUTPUT_DIR/networking-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "========================================"
echo " RetailEdge Networking Validation"
echo "========================================"
echo "Date: $(date)"
echo

echo "===== 1. TERRAFORM VALIDATE ====="
terraform validate || exit 1
echo

echo "===== 2. TERRAFORM STATE ====="
terraform state list || exit 1
echo

echo "===== 3. TERRAFORM OUTPUTS ====="
terraform output || exit 1
echo

VPC_ID=$(terraform output -raw vpc_id) || exit 1

echo "===== 4. VPC ====="
aws ec2 describe-vpcs \
  --vpc-ids "$VPC_ID" \
  --query "Vpcs[0].{VpcId:VpcId,Cidr:CidrBlock,State:State,DNS_Support:EnableDnsSupport,DNS_Hostnames:EnableDnsHostnames}" \
  --output table || exit 1
echo

echo "===== 5. SUBNETS ====="
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[].{Name:Tags[?Key=='Name']|[0].Value,Tier:Tags[?Key=='Tier']|[0].Value,CIDR:CidrBlock,AZ:AvailabilityZone,PublicIP:MapPublicIpOnLaunch}" \
  --output table || exit 1
echo

echo "===== 6. INTERNET GATEWAY ====="
aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query "InternetGateways[].{IGW:InternetGatewayId,State:Attachments[0].State}" \
  --output table || exit 1
echo

echo "===== 7. ROUTE TABLES ====="
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[].{RouteTableId:RouteTableId,Name:Tags[?Key=='Name']|[0].Value,Routes:Routes[].{CIDR:CidrBlock,Gateway:GatewayId}}" \
  --output json || exit 1
echo

echo "===== 8. FINAL TERRAFORM PLAN ====="
terraform plan || exit 1
echo

echo "========================================"
echo " VALIDATION COMPLETED"
echo "========================================"