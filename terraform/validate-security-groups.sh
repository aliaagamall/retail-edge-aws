#!/bin/bash

set -e

echo "========================================="
echo "   Security Groups Validation"
echo "========================================="

# Get Security Group IDs from Terraform outputs
ALB_SG=$(terraform output -raw alb_sg_id)
APP_SG=$(terraform output -raw app_sg_id)
RDS_SG=$(terraform output -raw rds_sg_id)
REDIS_SG=$(terraform output -raw redis_sg_id)
ENDPOINTS_SG=$(terraform output -raw endpoints_sg_id)

echo
echo "ALB SG:       $ALB_SG"
echo "App SG:       $APP_SG"
echo "RDS SG:       $RDS_SG"
echo "Redis SG:     $REDIS_SG"
echo "Endpoints SG: $ENDPOINTS_SG"

echo
echo "-----------------------------------------"
echo "1. Checking Security Groups exist"
echo "-----------------------------------------"

for SG in "$ALB_SG" "$APP_SG" "$RDS_SG" "$REDIS_SG" "$ENDPOINTS_SG"; do
  aws ec2 describe-security-groups \
    --group-ids "$SG" \
    --query "SecurityGroups[0].GroupId" \
    --output text > /dev/null

  echo "✓ $SG exists"
done


echo
echo "-----------------------------------------"
echo "2. ALB Security Group"
echo "-----------------------------------------"

ALB_RULES=$(aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$ALB_SG" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,IpProtocol,CidrIpv4]' \
  --output text)

echo "$ALB_RULES"

echo "$ALB_RULES" | grep -q $'443\t443\ttcp\t0.0.0.0/0'
echo "✓ HTTPS 443 allowed from internet"

echo "$ALB_RULES" | grep -q $'80\t80\ttcp\t0.0.0.0/0'
echo "✓ HTTP 80 allowed from internet"


echo
echo "-----------------------------------------"
echo "3. App Security Group"
echo "-----------------------------------------"

APP_RULES=$(aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$APP_SG" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,IpProtocol,ReferencedGroupInfo.GroupId,CidrIpv4]' \
  --output text)

echo "$APP_RULES"

echo "$APP_RULES" | grep -q $'8080\t8080\ttcp\t'"$ALB_SG"
echo "✓ App allows TCP 8080 from ALB SG"

if echo "$APP_RULES" | grep -q "0.0.0.0/0"; then
  echo "✗ App SG is publicly accessible"
  exit 1
fi

echo "✓ App SG is not publicly accessible"


echo
echo "-----------------------------------------"
echo "4. RDS Security Group"
echo "-----------------------------------------"

RDS_RULES=$(aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$RDS_SG" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,IpProtocol,ReferencedGroupInfo.GroupId,CidrIpv4]' \
  --output text)

echo "$RDS_RULES"

echo "$RDS_RULES" | grep -q $'3306\t3306\ttcp\t'"$APP_SG"
echo "✓ RDS allows MySQL 3306 from App SG"

if echo "$RDS_RULES" | grep -q "0.0.0.0/0"; then
  echo "✗ RDS SG is publicly accessible"
  exit 1
fi

echo "✓ RDS SG is not publicly accessible"


echo
echo "-----------------------------------------"
echo "5. Redis Security Group"
echo "-----------------------------------------"

REDIS_RULES=$(aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$REDIS_SG" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,IpProtocol,ReferencedGroupInfo.GroupId,CidrIpv4]' \
  --output text)

echo "$REDIS_RULES"

echo "$REDIS_RULES" | grep -q $'6379\t6379\ttcp\t'"$APP_SG"
echo "✓ Redis allows 6379 from App SG"

if echo "$REDIS_RULES" | grep -q "0.0.0.0/0"; then
  echo "✗ Redis SG is publicly accessible"
  exit 1
fi

echo "✓ Redis SG is not publicly accessible"


echo
echo "-----------------------------------------"
echo "6. VPC Endpoint Security Group"
echo "-----------------------------------------"

ENDPOINT_RULES=$(aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$ENDPOINTS_SG" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,IpProtocol,ReferencedGroupInfo.GroupId,CidrIpv4]' \
  --output text)

echo "$ENDPOINT_RULES"

echo "$ENDPOINT_RULES" | grep -q $'443\t443\ttcp\t'"$APP_SG"
echo "✓ VPC Endpoints allow HTTPS 443 from App SG"


echo
echo "========================================="
echo "   Security Groups validation passed"
echo "========================================="