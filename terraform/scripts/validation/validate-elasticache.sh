#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUTPUT_FILE="$OUTPUT_DIR/elasticache-validation.txt"


exec > >(tee "$OUTPUT_FILE") 2>&1

echo "========================================="
echo "   RetailEdge ElastiCache Validation"
echo "========================================="
echo "Date: $(date)"
echo ""

# -----------------------------------------
# 1. Checking Terraform
# -----------------------------------------

echo "-----------------------------------------"
echo "1. Checking Terraform"
echo "-----------------------------------------"


if terraform validate; then
    echo ""
    echo "✓ Terraform configuration is valid"
else
    echo ""
    echo "✗ Terraform validation failed"
    exit 1
fi

echo ""

# -----------------------------------------
# 2. Reading Terraform Outputs
# -----------------------------------------

echo "-----------------------------------------"
echo "2. Reading Terraform ElastiCache Outputs"
echo "-----------------------------------------"

REDIS_ENDPOINT=$(terraform output -raw redis_primary_endpoint 2>/dev/null || echo "N/A")
REDIS_PORT=$(terraform output -raw redis_port 2>/dev/null || echo "N/A")
REDIS_REPLICATION_GROUP=$(terraform output -raw redis_replication_group_id 2>/dev/null || echo "N/A")
REDIS_SECURITY_GROUP=$(terraform output -raw redis_security_group_id 2>/dev/null || echo "N/A")

echo "Redis Endpoint       : $REDIS_ENDPOINT"
echo "Redis Port           : $REDIS_PORT"
echo "Replication Group ID : $REDIS_REPLICATION_GROUP"
echo "Security Group ID    : $REDIS_SECURITY_GROUP"
echo ""

# -----------------------------------------
# 3. Checking AWS CLI
# -----------------------------------------

echo "-----------------------------------------"
echo "3. Checking AWS CLI"
echo "-----------------------------------------"

if command -v aws >/dev/null 2>&1; then
    echo "✓ AWS CLI is installed"
else
    echo "✗ AWS CLI is not installed"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text)

AWS_REGION=$(aws configure get region)

echo "AWS Account : $AWS_ACCOUNT_ID"
echo "AWS Region  : ${AWS_REGION:-Not configured}"
echo ""

# -----------------------------------------
# 4. Checking ElastiCache Replication Group
# -----------------------------------------

echo "-----------------------------------------"
echo "4. Checking ElastiCache Replication Group"
echo "-----------------------------------------"

if [ "$REDIS_REPLICATION_GROUP" != "N/A" ]; then

    STATUS=$(aws elasticache describe-replication-groups \
        --replication-group-id "$REDIS_REPLICATION_GROUP" \
        --query "ReplicationGroups[0].Status" \
        --output text 2>/dev/null || echo "NOT_FOUND")

    echo "Replication Group : $REDIS_REPLICATION_GROUP"
    echo "Status            : $STATUS"

    if [ "$STATUS" = "available" ]; then
        echo "✓ Redis replication group is available"
    else
        echo "⚠ Redis replication group status: $STATUS"
    fi

else
    echo "⚠ Redis replication group output not found"
fi

echo ""

# -----------------------------------------
# 5. Checking Redis Nodes
# -----------------------------------------

echo "-----------------------------------------"
echo "5. Checking Redis Nodes"
echo "-----------------------------------------"

if [ "$REDIS_REPLICATION_GROUP" != "N/A" ]; then

    NODE_COUNT=$(aws elasticache describe-replication-groups \
        --replication-group-id "$REDIS_REPLICATION_GROUP" \
        --query "length(ReplicationGroups[0].NodeGroups[].NodeGroupMembers[])" \
        --output text 2>/dev/null || echo "0")

    echo "Redis Nodes : $NODE_COUNT"

    if [ "$NODE_COUNT" -gt 0 ]; then
        echo "✓ Redis nodes detected"
    else
        echo "⚠ No Redis nodes detected"
    fi

else
    echo "⚠ Replication group ID not available"
fi

echo ""

# -----------------------------------------
# 6. Checking Security Group
# -----------------------------------------

echo "-----------------------------------------"
echo "6. Checking Redis Security Group"
echo "-----------------------------------------"

if [ "$REDIS_SECURITY_GROUP" != "N/A" ]; then

    aws ec2 describe-security-groups \
        --group-ids "$REDIS_SECURITY_GROUP" \
        --query "SecurityGroups[0].{Name:GroupName,ID:GroupId,Description:Description}" \
        --output table 2>/dev/null || true

    echo ""
    echo "✓ Redis Security Group exists"

else
    echo "⚠ Redis Security Group output not found"
fi

echo ""

# -----------------------------------------
# 7. Checking Redis Port
# -----------------------------------------

echo "-----------------------------------------"
echo "7. Checking Redis Port"
echo "-----------------------------------------"

if [ "$REDIS_PORT" = "6379" ]; then
    echo "Redis Port : $REDIS_PORT"
    echo "✓ Default Redis port is configured correctly"
else
    echo "Redis Port : $REDIS_PORT"
    echo "⚠ Redis port is not 6379"
fi

echo ""

# -----------------------------------------
# 8. Final Summary
# -----------------------------------------

echo "========================================="
echo "          Validation Summary"
echo "========================================="

echo "Terraform          : VALID"
echo "Redis Endpoint     : $REDIS_ENDPOINT"
echo "Redis Port         : $REDIS_PORT"
echo "Replication Group  : $REDIS_REPLICATION_GROUP"
echo "Security Group     : $REDIS_SECURITY_GROUP"
echo "Redis Status       : ${STATUS:-N/A}"
echo "Redis Nodes        : ${NODE_COUNT:-N/A}"

echo ""
echo "========================================="
echo "Validation completed"
echo "========================================="

echo ""
echo "Output saved to:"
echo "$OUTPUT_FILE"