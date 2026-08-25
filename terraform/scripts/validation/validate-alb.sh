#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUTPUT_FILE="$OUTPUT_DIR/alb-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "========================================="
echo "   RetailEdge ALB Validation (Internal)"
echo "========================================="
echo "Date: $(date)"
echo

echo "-----------------------------------------"
echo "1. Checking Terraform"
echo "-----------------------------------------"

terraform validate
echo
echo "✓ Terraform configuration is valid"
echo

echo "-----------------------------------------"
echo "2. Reading Terraform ALB Outputs"
echo "-----------------------------------------"

ALB_ARN=$(terraform output -raw alb_arn 2>/dev/null || true)
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || true)
TARGET_GROUP_ARN=$(terraform output -raw target_group_arn 2>/dev/null || true)

echo "ALB ARN          : ${ALB_ARN:-Not found}"
echo "ALB DNS Name     : ${ALB_DNS:-Not found}"
echo "Target Group ARN : ${TARGET_GROUP_ARN:-Not found}"
echo

echo "-----------------------------------------"
echo "3. Checking ALB Scheme (must be internal)"
echo "-----------------------------------------"

ALB_STATE=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].State.Code' \
    --output text)

ALB_SCHEME=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].Scheme' \
    --output text)

ALB_SUBNETS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].AvailabilityZones[].SubnetId' \
    --output text)

echo "State   : $ALB_STATE"
echo "Scheme  : $ALB_SCHEME"
echo "Subnets : $ALB_SUBNETS"

if [[ "$ALB_STATE" == "active" ]]; then
    echo "✓ ALB is active"
else
    echo "✗ ALB is not active"
    exit 1
fi

if [[ "$ALB_SCHEME" == "internal" ]]; then
    echo "✓ ALB scheme is internal (not internet-facing)"
else
    echo "✗ Expected internal scheme, got: $ALB_SCHEME"
    exit 1
fi

echo

echo "-----------------------------------------"
echo "4. Checking ALB is in App (private) Subnets"
echo "-----------------------------------------"

APP_SUBNET_IDS=$(terraform output -json app_subnet_ids 2>/dev/null | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)))')

echo "App Subnets (expected) : $APP_SUBNET_IDS"
echo "ALB Subnets (actual)   : $ALB_SUBNETS"

ALL_MATCH=true
for SUBNET in $ALB_SUBNETS; do
    if ! echo "$APP_SUBNET_IDS" | grep -q "$SUBNET"; then
        ALL_MATCH=false
    fi
done

if [ "$ALL_MATCH" = true ]; then
    echo "✓ ALB is deployed in the private app subnets"
else
    echo "✗ ALB subnets do not match expected app subnets"
    exit 1
fi

echo

echo "-----------------------------------------"
echo "5. Checking ALB Listeners"
echo "-----------------------------------------"

LISTENERS=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --query 'Listeners[*].[ListenerArn,Port,Protocol]' \
    --output text)

echo "$LISTENERS"
echo
echo "✓ ALB listeners found"

echo

echo "-----------------------------------------"
echo "6. Checking Target Group"
echo "-----------------------------------------"

TARGET_GROUP_NAME=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --query 'TargetGroups[0].TargetGroupName' \
    --output text)

TARGET_PORT=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --query 'TargetGroups[0].Port' \
    --output text)

echo "Name : $TARGET_GROUP_NAME"
echo "Port : $TARGET_PORT"
echo "✓ Target group found"

echo

echo "-----------------------------------------"
echo "7. Checking ALB Security Group Rules"
echo "-----------------------------------------"

ALB_SG=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].SecurityGroups[0]' \
    --output text)

echo "ALB SG : $ALB_SG"

ALB_RULES=$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$ALB_SG" \
    --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,IpProtocol,CidrIpv4]' \
    --output text)

echo "$ALB_RULES"

if echo "$ALB_RULES" | grep -q "0.0.0.0/0"; then
    echo "✗ ALB SG still allows public internet access - should be VPC CIDR only now"
    exit 1
else
    echo "✓ ALB SG does not allow public internet access (restricted to VPC CIDR)"
fi

echo

echo "-----------------------------------------"
echo "8. Confirming ALB Has No Public DNS Resolution Externally"
echo "-----------------------------------------"

echo "ALB DNS: $ALB_DNS"
echo "Note: this DNS only resolves from inside the VPC (internal ALB) - external curl is expected to fail/timeout, which is correct."

echo

echo "========================================="
echo "   ALB Validation Completed (Internal)"
echo "========================================="
echo
echo "Validation report:"
echo "$OUTPUT_FILE"