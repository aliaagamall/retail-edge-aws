#!/bin/bash

set -euo pipefail

OUTPUT_DIR="validation-results"
OUTPUT_FILE="$OUTPUT_DIR/rds-validation.txt"

mkdir -p "$OUTPUT_DIR"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "========================================="
echo "       RetailEdge RDS Validation"
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
echo "2. Reading Terraform RDS Outputs"
echo "-----------------------------------------"

DB_INSTANCE_ID=$(terraform output -raw db_instance_id 2>/dev/null || true)
DB_ENDPOINT=$(terraform output -raw db_endpoint 2>/dev/null || true)
DB_SECRET_ARN=$(terraform output -raw db_secret_arn 2>/dev/null || true)
DB_SECRET_NAME=$(terraform output -raw db_secret_name 2>/dev/null || true)

echo "DB Instance ID : ${DB_INSTANCE_ID:-Not found}"
echo "DB Endpoint    : ${DB_ENDPOINT:-Not found}"
echo "Secret ARN     : ${DB_SECRET_ARN:-Not found}"
echo "Secret Name    : ${DB_SECRET_NAME:-Not found}"
echo ""

echo "-----------------------------------------"
echo "3. Checking RDS Instance"
echo "-----------------------------------------"

if [[ -z "$DB_INSTANCE_ID" ]]; then
    echo "✗ RDS instance ID not found in Terraform outputs"
    exit 1
fi

RDS_INFO=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].[DBInstanceStatus,Engine,EngineVersion,DBInstanceClass,MultiAZ,StorageEncrypted,PubliclyAccessible,Port]' \
    --output text)

read -r RDS_STATUS RDS_ENGINE RDS_VERSION RDS_CLASS RDS_MULTI_AZ RDS_ENCRYPTED RDS_PUBLIC RDS_PORT <<< "$RDS_INFO"

echo "Status             : $RDS_STATUS"
echo "Engine             : $RDS_ENGINE"
echo "Engine Version     : $RDS_VERSION"
echo "Instance Class     : $RDS_CLASS"
echo "Multi-AZ           : $RDS_MULTI_AZ"
echo "Storage Encrypted  : $RDS_ENCRYPTED"
echo "Publicly Accessible: $RDS_PUBLIC"
echo "Port               : $RDS_PORT"
echo ""

if [[ "$RDS_STATUS" == "available" ]]; then
    echo "✓ RDS instance is available"
else
    echo "⚠ RDS instance status is: $RDS_STATUS"
fi

if [[ "$RDS_ENGINE" == "mysql" ]]; then
    echo "✓ MySQL engine confirmed"
else
    echo "✗ Expected MySQL engine"
    exit 1
fi

if [[ "$RDS_ENCRYPTED" == "True" ]]; then
    echo "✓ Storage encryption enabled"
else
    echo "✗ Storage encryption is not enabled"
fi

if [[ "$RDS_PUBLIC" == "False" ]]; then
    echo "✓ RDS is not publicly accessible"
else
    echo "✗ RDS is publicly accessible"
fi

echo ""

echo "-----------------------------------------"
echo "4. Checking RDS Endpoint"
echo "-----------------------------------------"

ACTUAL_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

ACTUAL_PORT=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Port' \
    --output text)

echo "Endpoint : $ACTUAL_ENDPOINT"
echo "Port     : $ACTUAL_PORT"

if [[ "$ACTUAL_PORT" == "3306" ]]; then
    echo "✓ MySQL port 3306 confirmed"
else
    echo "⚠ Unexpected database port: $ACTUAL_PORT"
fi

echo ""

echo "-----------------------------------------"
echo "5. Checking RDS Subnet Group"
echo "-----------------------------------------"

SUBNET_GROUP=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].DBSubnetGroup.DBSubnetGroupName' \
    --output text)

SUBNET_COUNT=$(aws rds describe-db-subnet-groups \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --query 'length(DBSubnetGroups[0].Subnets)' \
    --output text)

echo "Subnet Group : $SUBNET_GROUP"
echo "Subnet Count : $SUBNET_COUNT"

if [[ "$SUBNET_COUNT" -ge 2 ]]; then
    echo "✓ RDS subnet group spans multiple subnets"
else
    echo "⚠ RDS subnet group has fewer than 2 subnets"
fi

echo ""

echo "-----------------------------------------"
echo "6. Checking RDS Security Groups"
echo "-----------------------------------------"

RDS_SG=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].VpcSecurityGroups[*].VpcSecurityGroupId' \
    --output text)

echo "Security Groups:"
echo "$RDS_SG"

if [[ -n "$RDS_SG" ]]; then
    echo "✓ RDS security group attached"
else
    echo "✗ No RDS security group attached"
    exit 1
fi

echo ""

echo "-----------------------------------------"
echo "7. Checking Secrets Manager"
echo "-----------------------------------------"

if [[ -z "$DB_SECRET_ARN" ]]; then
    echo "✗ Database secret ARN not found"
    exit 1
fi

SECRET_INFO=$(aws secretsmanager describe-secret \
    --secret-id "$DB_SECRET_ARN" \
    --query '[Name,ARN]' \
    --output text)

read -r SECRET_NAME SECRET_ARN <<< "$SECRET_INFO"

echo "Secret Name : $SECRET_NAME"
echo "Secret ARN  : $SECRET_ARN"

echo "✓ Secret exists"

echo ""

echo "-----------------------------------------"
echo "8. Checking Secret Fields"
echo "-----------------------------------------"

SECRET_STRING=$(aws secretsmanager get-secret-value \
    --secret-id "$DB_SECRET_ARN" \
    --query 'SecretString' \
    --output text)

if [[ -z "$SECRET_STRING" || "$SECRET_STRING" == "None" ]]; then
    echo "✗ SecretString is empty"
    exit 1
fi

echo "$SECRET_STRING" | python3 -c '
import json
import sys

data = json.load(sys.stdin)

required = [
    "DB_HOST",
    "DB_USER",
    "DB_PWD",
    "DB_DATABASE",
    "DB_PORT"
]

print("Secret fields:")

missing = []

for key in required:
    if key in data:
        if key == "DB_PWD":
            print(f"  {key}: ********")
        else:
            print(f"  {key}: {data[key]}")
    else:
        missing.append(key)

if missing:
    print("")
    print("Missing fields:")
    for key in missing:
        print(f"  - {key}")
    sys.exit(1)

print("")
print("✓ All required database secret fields exist")
'

echo ""

echo "-----------------------------------------"
echo "9. Checking Secret Values"
echo "-----------------------------------------"

SECRET_DB_HOST=$(echo "$SECRET_STRING" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("DB_HOST",""))')
SECRET_DB_USER=$(echo "$SECRET_STRING" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("DB_USER",""))')
SECRET_DB_NAME=$(echo "$SECRET_STRING" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("DB_DATABASE",""))')
SECRET_DB_PORT=$(echo "$SECRET_STRING" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("DB_PORT",""))')

if [[ "$SECRET_DB_HOST" == "$ACTUAL_ENDPOINT" ]]; then
    echo "✓ DB_HOST matches RDS endpoint"
else
    echo "⚠ DB_HOST does not match RDS endpoint"
fi

if [[ -n "$SECRET_DB_USER" ]]; then
    echo "✓ DB_USER is configured"
else
    echo "✗ DB_USER is empty"
fi

if [[ -n "$SECRET_DB_NAME" ]]; then
    echo "✓ DB_DATABASE is configured"
else
    echo "✗ DB_DATABASE is empty"
fi

if [[ "$SECRET_DB_PORT" == "3306" ]]; then
    echo "✓ DB_PORT is 3306"
else
    echo "⚠ DB_PORT is: $SECRET_DB_PORT"
fi

echo ""

echo "-----------------------------------------"
echo "10. Checking Backup Configuration"
echo "-----------------------------------------"

BACKUP_RETENTION=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].BackupRetentionPeriod' \
    --output text)

echo "Backup Retention : $BACKUP_RETENTION days"

if [[ "$BACKUP_RETENTION" -gt 0 ]]; then
    echo "✓ Automated backups enabled"
else
    echo "⚠ Automated backups disabled"
fi

echo ""

echo "-----------------------------------------"
echo "11. Checking Deletion Protection"
echo "-----------------------------------------"

DELETION_PROTECTION=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].DeletionProtection' \
    --output text)

echo "Deletion Protection : $DELETION_PROTECTION"

if [[ "$DELETION_PROTECTION" == "True" ]]; then
    echo "✓ Deletion protection enabled"
else
    echo "⚠ Deletion protection disabled"
fi

echo ""

echo "========================================="
echo "       RDS Validation Completed"
echo "========================================="
echo ""
echo "Validation report:"
echo "$OUTPUT_FILE"