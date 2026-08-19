#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

AWS_REGION="us-east-1"
OUTPUT_FILE="$OUTPUT_DIR/compute-validation.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "============================================================"
echo "              RetailEdge Compute Validation"
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
echo "2. Reading Terraform Compute Outputs"
echo "------------------------------------------------------------"

ASG_NAME=$(terraform output -raw asg_name 2>/dev/null || true)

if [ -n "$ASG_NAME" ]; then
    echo "ASG Name : $ASG_NAME"
    echo "✓ ASG Terraform output exists"
else
    echo "✗ Could not read asg_name"
    echo "Make sure the compute module has been applied."
    exit 1
fi

LAUNCH_TEMPLATE_ID=$(terraform output -raw launch_template_id 2>/dev/null || true)

if [ -n "$LAUNCH_TEMPLATE_ID" ]; then
    echo "Launch Template ID : $LAUNCH_TEMPLATE_ID"
    echo "✓ Launch Template output exists"
else
    echo "⚠ Launch Template output is not available from root outputs"
fi

echo

# ------------------------------------------------------------
# 3. Checking AWS Identity
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "3. Checking AWS Identity"
echo "------------------------------------------------------------"

if aws sts get-caller-identity; then
    echo "✓ AWS credentials are working"
else
    echo "✗ AWS credentials check failed"
    exit 1
fi

echo

# ------------------------------------------------------------
# 4. Checking Auto Scaling Group
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "4. Checking Auto Scaling Group"
echo "------------------------------------------------------------"

ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$AWS_REGION" \
    --output json 2>/tmp/compute_asg_error.log || true)

if [ -z "$ASG_INFO" ]; then
    echo "✗ Could not retrieve Auto Scaling Group"
    cat /tmp/compute_asg_error.log
    exit 1
fi

ASG_COUNT=$(echo "$ASG_INFO" | python3 -c '
import json
import sys

groups = json.load(sys.stdin).get("AutoScalingGroups", [])
print(len(groups))
')

if [ "$ASG_COUNT" -ne 1 ]; then
    echo "✗ Expected 1 ASG, found $ASG_COUNT"
    exit 1
fi

echo "✓ Auto Scaling Group exists"

echo "$ASG_INFO" | python3 -c '
import json
import sys

asg = json.load(sys.stdin)["AutoScalingGroups"][0]

print("Name                :", asg.get("AutoScalingGroupName"))
print("Min Size            :", asg.get("MinSize"))
print("Desired Capacity    :", asg.get("DesiredCapacity"))
print("Max Size            :", asg.get("MaxSize"))
print("Health Check Type    :", asg.get("HealthCheckType"))
print("Grace Period         :", asg.get("HealthCheckGracePeriod"))
'

echo

# ------------------------------------------------------------
# 5. Checking ASG Capacity
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "5. Checking ASG Capacity"
echo "------------------------------------------------------------"

ASG_VALUES=$(echo "$ASG_INFO" | python3 -c '
import json
import sys

asg = json.load(sys.stdin)["AutoScalingGroups"][0]

print(asg["MinSize"])
print(asg["DesiredCapacity"])
print(asg["MaxSize"])
')

MIN_SIZE=$(echo "$ASG_VALUES" | sed -n '1p')
DESIRED_SIZE=$(echo "$ASG_VALUES" | sed -n '2p')
MAX_SIZE=$(echo "$ASG_VALUES" | sed -n '3p')

if [ "$MIN_SIZE" -eq 2 ]; then
    echo "✓ Minimum size = 2"
else
    echo "✗ Expected minimum size 2, found $MIN_SIZE"
    exit 1
fi

if [ "$DESIRED_SIZE" -eq 2 ]; then
    echo "✓ Desired capacity = 2"
else
    echo "✗ Expected desired capacity 2, found $DESIRED_SIZE"
    exit 1
fi

if [ "$MAX_SIZE" -eq 4 ]; then
    echo "✓ Maximum size = 4"
else
    echo "✗ Expected maximum size 4, found $MAX_SIZE"
    exit 1
fi

echo

# ------------------------------------------------------------
# 6. Checking ASG Health Configuration
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "6. Checking ASG Health Configuration"
echo "------------------------------------------------------------"

HEALTH_CONFIG=$(echo "$ASG_INFO" | python3 -c '
import json
import sys

asg = json.load(sys.stdin)["AutoScalingGroups"][0]

print(asg["HealthCheckType"])
print(asg["HealthCheckGracePeriod"])
')

HEALTH_TYPE=$(echo "$HEALTH_CONFIG" | sed -n '1p')
GRACE_PERIOD=$(echo "$HEALTH_CONFIG" | sed -n '2p')

echo "Health Check Type : $HEALTH_TYPE"
echo "Grace Period      : ${GRACE_PERIOD}s"

if [ "$HEALTH_TYPE" = "ELB" ]; then
    echo "✓ ELB health check configured"
else
    echo "✗ Expected ELB health check"
    exit 1
fi

if [ "$GRACE_PERIOD" -eq 120 ]; then
    echo "✓ Health check grace period = 120 seconds"
else
    echo "✗ Expected grace period 120 seconds"
    exit 1
fi

echo

# ------------------------------------------------------------
# 7. Checking Launch Template
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "7. Checking Launch Template"
echo "------------------------------------------------------------"

LT_ID_FROM_ASG=$(echo "$ASG_INFO" | python3 -c '
import json
import sys

asg = json.load(sys.stdin)["AutoScalingGroups"][0]
lt = asg.get("LaunchTemplate", {})

print(lt.get("LaunchTemplateId", ""))
')

if [ -z "$LT_ID_FROM_ASG" ]; then
    echo "✗ Launch Template is not attached to ASG"
    exit 1
fi

echo "Launch Template ID : $LT_ID_FROM_ASG"
echo "✓ Launch Template is attached"

LT_INFO=$(aws ec2 describe-launch-templates \
    --launch-template-ids "$LT_ID_FROM_ASG" \
    --region "$AWS_REGION" \
    --output json 2>/tmp/compute_lt_error.log || true)

if [ -z "$LT_INFO" ]; then
    echo "✗ Could not retrieve Launch Template"
    cat /tmp/compute_lt_error.log
    exit 1
fi

echo "$LT_INFO" | python3 -c '
import json
import sys

lt = json.load(sys.stdin)["LaunchTemplates"][0]

print("Launch Template Name :", lt.get("LaunchTemplateName"))
print("Latest Version       :", lt.get("LatestVersionNumber"))
print("Default Version      :", lt.get("DefaultVersionNumber"))
'

echo

# ------------------------------------------------------------
# 8. Checking Launch Template Configuration
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "8. Checking Launch Template Configuration"
echo "------------------------------------------------------------"

LT_VERSION=$(echo "$LT_INFO" | python3 -c '
import json
import sys

lt = json.load(sys.stdin)["LaunchTemplates"][0]
print(lt["LatestVersionNumber"])
')

LT_VERSION_INFO=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "$LT_ID_FROM_ASG" \
    --versions "$LT_VERSION" \
    --region "$AWS_REGION" \
    --output json)

echo "$LT_VERSION_INFO" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
v = data["LaunchTemplateVersions"][0]
d = v["LaunchTemplateData"]

print("Instance Type :", d.get("InstanceType"))
print("AMI ID        :", d.get("ImageId"))
print("Security Groups:", ", ".join(d.get("SecurityGroupIds", [])))

metadata = d.get("MetadataOptions", {})
print("IMDSv2        :", metadata.get("HttpTokens"))

for mapping in d.get("BlockDeviceMappings", []):
    ebs = mapping.get("Ebs", {})
    print("Root Volume   :", mapping.get("DeviceName"))
    print("Volume Size   :", ebs.get("VolumeSize"), "GB")
    print("Volume Type   :", ebs.get("VolumeType"))
    print("Encrypted     :", ebs.get("Encrypted"))
'

echo

# ------------------------------------------------------------
# 9. Checking IMDSv2
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "9. Checking IMDSv2"
echo "------------------------------------------------------------"

IMDS_TOKENS=$(echo "$LT_VERSION_INFO" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
d = data["LaunchTemplateVersions"][0]["LaunchTemplateData"]

print(d.get("MetadataOptions", {}).get("HttpTokens", ""))
')

if [ "$IMDS_TOKENS" = "required" ]; then
    echo "✓ IMDSv2 is required"
else
    echo "✗ IMDSv2 is not required"
    exit 1
fi

echo

# ------------------------------------------------------------
# 10. Checking Root Volume
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "10. Checking Root Volume"
echo "------------------------------------------------------------"

VOLUME_CONFIG=$(echo "$LT_VERSION_INFO" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
mappings = data["LaunchTemplateVersions"][0]["LaunchTemplateData"]["BlockDeviceMappings"]

for mapping in mappings:
    if mapping.get("DeviceName") == "/dev/xvda":
        ebs = mapping["Ebs"]
        print(ebs.get("VolumeSize"))
        print(ebs.get("VolumeType"))
        print(ebs.get("Encrypted"))
        print(ebs.get("DeleteOnTermination"))
        break
')

VOLUME_SIZE=$(echo "$VOLUME_CONFIG" | sed -n '1p')
VOLUME_TYPE=$(echo "$VOLUME_CONFIG" | sed -n '2p')
VOLUME_ENCRYPTED=$(echo "$VOLUME_CONFIG" | sed -n '3p')
DELETE_ON_TERMINATION=$(echo "$VOLUME_CONFIG" | sed -n '4p')

echo "Volume Size          : ${VOLUME_SIZE} GB"
echo "Volume Type          : $VOLUME_TYPE"
echo "Encrypted            : $VOLUME_ENCRYPTED"
echo "Delete on Termination: $DELETE_ON_TERMINATION"

if [ "$VOLUME_SIZE" -eq 30 ]; then
    echo "✓ Root volume size = 30 GB"
else
    echo "✗ Expected root volume size 30 GB"
    exit 1
fi

if [ "$VOLUME_TYPE" = "gp3" ]; then
    echo "✓ Root volume type = gp3"
else
    echo "✗ Expected gp3 root volume"
    exit 1
fi

if [ "$VOLUME_ENCRYPTED" = "True" ]; then
    echo "✓ Root volume encryption enabled"
else
    echo "✗ Root volume is not encrypted"
    exit 1
fi

if [ "$DELETE_ON_TERMINATION" = "True" ]; then
    echo "✓ Delete on termination enabled"
else
    echo "✗ Delete on termination is not enabled"
    exit 1
fi

echo

# ------------------------------------------------------------
# 11. Checking Running Instances
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "11. Checking Running Instances"
echo "------------------------------------------------------------"

INSTANCE_IDS=$(echo "$ASG_INFO" | python3 -c '
import json
import sys

asg = json.load(sys.stdin)["AutoScalingGroups"][0]

for instance in asg.get("Instances", []):
    print(instance["InstanceId"])
')

INSTANCE_COUNT=$(echo "$INSTANCE_IDS" | sed '/^$/d' | wc -l)

echo "Running/Registered Instances : $INSTANCE_COUNT"

if [ "$INSTANCE_COUNT" -ge 2 ]; then
    echo "✓ At least 2 instances are registered"
else
    echo "⚠ Less than 2 instances are currently registered"
fi

if [ "$INSTANCE_COUNT" -gt 0 ]; then

    INSTANCE_INFO=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_IDS \
        --region "$AWS_REGION" \
        --output json)

    echo "$INSTANCE_INFO" | python3 -c '
import json
import sys

data = json.load(sys.stdin)

for reservation in data.get("Reservations", []):
    for instance in reservation.get("Instances", []):
        print(
            instance["InstanceId"],
            "|",
            instance.get("InstanceType"),
            "|",
            instance.get("State", {}).get("Name"),
            "|",
            instance.get("PrivateIpAddress", "N/A")
        )
    '

fi

echo

# ------------------------------------------------------------
# 12. Checking Target Group Health
# ------------------------------------------------------------
echo "------------------------------------------------------------"
echo "12. Checking Target Group Health"
echo "------------------------------------------------------------"

TARGET_GROUP_ARN=$(terraform output -raw target_group_arn 2>/dev/null || true)

if [ -z "$TARGET_GROUP_ARN" ]; then
    echo "⚠ target_group_arn root output not available"
    echo "Skipping Target Group health check"
else

    echo "Target Group ARN : $TARGET_GROUP_ARN"

    TARGET_HEALTH=$(aws elbv2 describe-target-health \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" \
        --output json 2>/tmp/compute_tg_error.log || true)

    if [ -z "$TARGET_HEALTH" ]; then
        echo "✗ Could not retrieve Target Group health"
        cat /tmp/compute_tg_error.log
        exit 1
    fi

    echo "$TARGET_HEALTH" | python3 -c '
import json
import sys

data = json.load(sys.stdin)

targets = data.get("TargetHealthDescriptions", [])

print("Registered Targets :", len(targets))

for target in targets:
    health = target.get("TargetHealth", {})
    print(
        "Target :",
        target.get("Target", {}).get("Id"),
        "| State :",
        health.get("State"),
        "| Reason :",
        health.get("Reason", "N/A")
    )
    '

    HEALTHY_COUNT=$(echo "$TARGET_HEALTH" | python3 -c '
import json
import sys

data = json.load(sys.stdin)

count = 0

for target in data.get("TargetHealthDescriptions", []):
    if target.get("TargetHealth", {}).get("State") == "healthy":
        count += 1

print(count)
')

    if [ "$HEALTHY_COUNT" -ge 1 ]; then
        echo
        echo "✓ At least one target is healthy"
    else
        echo
        echo "⚠ No healthy targets currently"
        echo "Instances may still be starting or CodeDeploy may not have deployed the application yet."
    fi

fi

echo

# ------------------------------------------------------------
# 13. Final Summary
# ------------------------------------------------------------
echo "============================================================"
echo "                  VALIDATION SUMMARY"
echo "============================================================"

echo "Terraform                 : PASS"
echo "Auto Scaling Group        : PASS"
echo "ASG Capacity              : PASS (2 / 2 / 4)"
echo "ELB Health Check          : PASS"
echo "Launch Template           : PASS"
echo "IMDSv2                    : PASS"
echo "Root Volume               : PASS (30GB gp3 encrypted)"
echo "Instances                 : CHECKED"
echo "Target Group Health       : CHECKED"

echo
echo "ASG Name:"
echo "$ASG_NAME"

echo
echo "Launch Template ID:"
echo "$LT_ID_FROM_ASG"

echo
echo "Output saved to:"
echo "$OUTPUT_FILE"

echo
echo "============================================================"
echo "            COMPUTE VALIDATION COMPLETE"
echo "============================================================"