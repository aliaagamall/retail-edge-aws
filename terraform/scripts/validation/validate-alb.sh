#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUTPUT_FILE="$OUTPUT_DIR/alb-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "========================================="
echo "       RetailEdge ALB Validation"
echo "========================================="
echo "Date: $(date)"
echo ""

echo "-----------------------------------------"
echo "1. Checking Terraform"
echo "-----------------------------------------"

terraform validate

echo ""
echo "✓ Terraform configuration is valid"
echo ""

echo "-----------------------------------------"
echo "2. Reading Terraform ALB Outputs"
echo "-----------------------------------------"

ALB_ARN=$(terraform output -raw alb_arn 2>/dev/null || true)
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || true)
TARGET_GROUP_ARN=$(terraform output -raw target_group_arn 2>/dev/null || true)

echo "ALB ARN          : ${ALB_ARN:-Not found}"
echo "ALB DNS Name     : ${ALB_DNS:-Not found}"
echo "Target Group ARN : ${TARGET_GROUP_ARN:-Not found}"
echo ""

echo "-----------------------------------------"
echo "3. Checking ALB"
echo "-----------------------------------------"

if [[ -z "$ALB_ARN" ]]; then
    echo "✗ ALB ARN not found in Terraform outputs"
    exit 1
fi

ALB_STATE=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].State.Code' \
    --output text)

ALB_TYPE=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].Type' \
    --output text)

ALB_SCHEME=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].Scheme' \
    --output text)

echo "State  : $ALB_STATE"
echo "Type   : $ALB_TYPE"
echo "Scheme : $ALB_SCHEME"

if [[ "$ALB_STATE" == "active" ]]; then
    echo "✓ ALB is active"
else
    echo "✗ ALB is not active"
    exit 1
fi

echo ""

echo "-----------------------------------------"
echo "4. Checking ALB Listeners"
echo "-----------------------------------------"

LISTENERS=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --query 'Listeners[*].[ListenerArn,Port,Protocol]' \
    --output text)

if [[ -z "$LISTENERS" ]]; then
    echo "✗ No listeners found"
    exit 1
fi

echo "$LISTENERS"
echo ""
echo "✓ ALB listeners found"

echo ""

echo "-----------------------------------------"
echo "5. Checking Target Group"
echo "-----------------------------------------"

if [[ -z "$TARGET_GROUP_ARN" ]]; then
    echo "✗ Target Group ARN not found"
    exit 1
fi

TARGET_GROUP_NAME=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --query 'TargetGroups[0].TargetGroupName' \
    --output text)

TARGET_TYPE=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --query 'TargetGroups[0].TargetType' \
    --output text)

TARGET_PORT=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --query 'TargetGroups[0].Port' \
    --output text)

TARGET_PROTOCOL=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --query 'TargetGroups[0].Protocol' \
    --output text)

echo "Name     : $TARGET_GROUP_NAME"
echo "Type     : $TARGET_TYPE"
echo "Port     : $TARGET_PORT"
echo "Protocol : $TARGET_PROTOCOL"
echo ""

echo "✓ Target group found"

echo ""

echo "-----------------------------------------"
echo "6. Checking Target Health"
echo "-----------------------------------------"

TARGET_HEALTH=$(aws elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --query 'TargetHealthDescriptions[*].[Target.Id,Target.Port,TargetHealth.State]' \
    --output table)

echo "$TARGET_HEALTH"

echo ""

HEALTHY_COUNT=$(aws elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
    --output text)

TOTAL_COUNT=$(aws elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --query 'length(TargetHealthDescriptions)' \
    --output text)

echo "Healthy Targets : $HEALTHY_COUNT"
echo "Total Targets   : $TOTAL_COUNT"

if [[ "$HEALTHY_COUNT" -gt 0 ]]; then
    echo "✓ At least one target is healthy"
else
    echo "⚠ No healthy targets currently"
fi

echo ""

echo "-----------------------------------------"
echo "7. Checking ALB Security Groups"
echo "-----------------------------------------"

ALB_SG=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].SecurityGroups[*]' \
    --output text)

echo "Security Groups:"
echo "$ALB_SG"

if [[ -n "$ALB_SG" ]]; then
    echo "✓ ALB security group attached"
else
    echo "✗ No security group attached"
    exit 1
fi

echo ""

echo "-----------------------------------------"
echo "8. Testing ALB DNS"
echo "-----------------------------------------"

if [[ -n "$ALB_DNS" && "$ALB_DNS" != "Not found" ]]; then

    echo "ALB DNS: $ALB_DNS"
    echo ""

    HTTP_STATUS=$(curl \
        -k \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        --connect-timeout 10 \
        "https://$ALB_DNS" || true)

    echo "HTTPS Status Code: $HTTP_STATUS"

    if [[ "$HTTP_STATUS" =~ ^[23][0-9][0-9]$ ]]; then
        echo "✓ ALB HTTPS endpoint is responding"
    elif [[ "$HTTP_STATUS" == "000" ]]; then
        echo "⚠ Could not connect to ALB"
    else
        echo "⚠ ALB responded with HTTP status $HTTP_STATUS"
    fi

else
    echo "⚠ ALB DNS output not available"
fi

echo ""

echo "========================================="
echo "       ALB Validation Completed"
echo "========================================="
echo ""
echo "Validation report:"
echo "$OUTPUT_FILE"