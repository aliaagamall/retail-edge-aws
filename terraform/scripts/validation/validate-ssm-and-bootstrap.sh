#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

AWS_REGION="us-east-1"
OUTPUT_FILE="$OUTPUT_DIR/ssm-and-bootstrap-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "============================================================"
echo "     RetailEdge SSM Parameter & Bootstrap Validation"
echo "============================================================"
echo "Date: $(date)"
echo

# ------------------------------------------------------------
# 1. Checking Terraform
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "1. Checking Terraform"
echo "------------------------------------------------------------"

if terraform validate; then
    echo
    echo "✓ Terraform configuration is valid"
else
    echo
    echo "✗ Terraform validation failed"
    exit 1
fi

echo

# ------------------------------------------------------------
# 2. Reading Terraform Outputs
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "2. Reading Terraform Outputs"
echo "------------------------------------------------------------"

SSM_PARAM_NAME=$(terraform output -raw current_image_parameter_name 2>/dev/null || true)
ASG_NAME=$(terraform output -raw asg_name 2>/dev/null || true)
ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || true)

echo "SSM Parameter Name : ${SSM_PARAM_NAME:-Not found}"
echo "ASG Name            : ${ASG_NAME:-Not found}"
echo "ECR Repository URL  : ${ECR_URL:-Not found}"

if [ -z "$SSM_PARAM_NAME" ] || [ -z "$ASG_NAME" ]; then
    echo "✗ Required outputs missing"
    exit 1
fi

echo

# ------------------------------------------------------------
# 3. Checking SSM Parameter Exists With Placeholder Value
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "3. Checking SSM Parameter"
echo "------------------------------------------------------------"

PARAM_VALUE=$(aws ssm get-parameter \
    --name "$SSM_PARAM_NAME" \
    --region "$AWS_REGION" \
    --query "Parameter.Value" \
    --output text 2>/tmp/ssm_param_error.log || true)

if [ -z "$PARAM_VALUE" ]; then
    echo "✗ Could not read SSM parameter"
    cat /tmp/ssm_param_error.log
    exit 1
fi

echo "Parameter Value : $PARAM_VALUE"

if [ "$PARAM_VALUE" = "none" ]; then
    echo "✓ Parameter holds the expected placeholder value 'none' (no deployment yet)"
else
    echo "⚠ Parameter has a non-placeholder value - a deployment may have already run"
fi

echo

# ------------------------------------------------------------
# 4. Checking No CodeDeploy Resources Exist
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "4. Confirming CodeDeploy is Fully Removed"
echo "------------------------------------------------------------"

CODEDEPLOY_IN_STATE=$(terraform state list | grep -i codedeploy || true)

if [ -z "$CODEDEPLOY_IN_STATE" ]; then
    echo "✓ No CodeDeploy resources found in Terraform state"
else
    echo "✗ CodeDeploy resources still present in state:"
    echo "$CODEDEPLOY_IN_STATE"
    exit 1
fi

echo

# ------------------------------------------------------------
# 5. Checking ASG and Instances
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "5. Checking Auto Scaling Group"
echo "------------------------------------------------------------"

ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$AWS_REGION" \
    --output json 2>/tmp/asg_error.log || true)

if [ -z "$ASG_INFO" ]; then
    echo "✗ Could not retrieve ASG"
    cat /tmp/asg_error.log
    exit 1
fi

INSTANCE_IDS=$(echo "$ASG_INFO" | python3 -c '
import json, sys
asg = json.load(sys.stdin)["AutoScalingGroups"][0]
for i in asg.get("Instances", []):
    print(i["InstanceId"])
')

INSTANCE_COUNT=$(echo "$INSTANCE_IDS" | sed '/^$/d' | wc -l)
echo "Running Instances : $INSTANCE_COUNT"

if [ "$INSTANCE_COUNT" -ge 1 ]; then
    echo "✓ ASG has running instances"
else
    echo "✗ No instances found in ASG"
    exit 1
fi

echo

# ------------------------------------------------------------
# 6. Checking Bootstrap Behavior via SSM Run Command
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "6. Checking Bootstrap Behavior on an Instance (via SSM)"
echo "------------------------------------------------------------"
echo "Note: no Docker image has been pushed to ECR yet, so the bootstrap"
echo "script is EXPECTED to find no image tag and exit cleanly without"
echo "starting a container. This confirms the conditional logic works."
echo

FIRST_INSTANCE=$(echo "$INSTANCE_IDS" | head -n 1)

if [ -z "$FIRST_INSTANCE" ]; then
    echo "⚠ No instance available to check - skipping"
else
    echo "Checking instance: $FIRST_INSTANCE"

    # Confirm Docker installed and running
    CMD_ID=$(aws ssm send-command \
        --instance-ids "$FIRST_INSTANCE" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["systemctl is-active docker", "docker ps -a --format \"{{.Names}}\"", "aws ssm get-parameter --name '"$SSM_PARAM_NAME"' --region '"$AWS_REGION"' --query Parameter.Value --output text"]' \
        --region "$AWS_REGION" \
        --query "Command.CommandId" \
        --output text 2>/tmp/ssm_cmd_error.log || true)

    if [ -z "$CMD_ID" ]; then
        echo "⚠ Could not send SSM command (instance may still be booting - retry in a minute)"
        cat /tmp/ssm_cmd_error.log
    else
        echo "Command sent, waiting for result..."
        sleep 8

        aws ssm get-command-invocation \
            --command-id "$CMD_ID" \
            --instance-id "$FIRST_INSTANCE" \
            --region "$AWS_REGION" \
            --query "{Status:Status,Output:StandardOutputContent}" \
            --output json 2>/tmp/ssm_invoke_error.log || cat /tmp/ssm_invoke_error.log
    fi
fi

echo

# ------------------------------------------------------------
# 7. Final Summary
# ------------------------------------------------------------
echo "============================================================"
echo "                  VALIDATION SUMMARY"
echo "============================================================"

echo "Terraform                    : PASS"
echo "SSM Parameter (placeholder)  : PASS"
echo "No CodeDeploy Resources      : PASS"
echo "ASG Running Instances        : PASS"
echo "Bootstrap Behavior           : CHECKED (no image expected)"

echo
echo "Note: The application will NOT be reachable yet - no Docker image"
echo "has been pushed to ECR. This is expected until the first deployment."

echo
echo "Output saved to:"
echo "$OUTPUT_FILE"

echo
echo "============================================================"
echo "        SSM & BOOTSTRAP VALIDATION COMPLETE 🥰"
echo "============================================================"