"""
RetailEdge deployment Lambda.

Invoked by GitHub Actions with:
    {"image_tag": "<git-sha-or-tag>"}

Flow:
  1. Read the current image tag from SSM for rollback.
  2. Get all InService instances from the ASG.
  3. Deploy the new image through SSM Run Command.
  4. If deployment fails, roll back successful instances.
  5. Update SSM only after all instances succeed.
  6. Alert through SNS if rollback also fails.

The Lambda uses reserved concurrency = 1 to prevent
multiple deployments from running at the same time.
"""

import json
import logging
import os
import time

import boto3


logger = logging.getLogger()
logger.setLevel(logging.INFO)

REGION = os.environ["AWS_REGION"]
ASG_NAME = os.environ["ASG_NAME"]
SSM_PARAMETER_NAME = os.environ["SSM_PARAMETER_NAME"]
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "1"))
COMMAND_TIMEOUT_SECONDS = int(os.environ.get("COMMAND_TIMEOUT_SECONDS", "180"))
POLL_INTERVAL_SECONDS = 5

autoscaling = boto3.client("autoscaling", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)


class DeploymentError(Exception):
    """Raised when a deployment cannot continue."""


def get_in_service_instance_ids():
    resp = autoscaling.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_NAME]
    )

    groups = resp.get("AutoScalingGroups", [])

    if not groups:
        raise DeploymentError(f"Auto Scaling Group '{ASG_NAME}' not found")

    # Only deploy to instances currently serving traffic.
    instances = [
        i["InstanceId"]
        for i in groups[0].get("Instances", [])
        if i.get("LifecycleState") == "InService"
    ]

    if not instances:
        raise DeploymentError(
            f"No InService instances found in '{ASG_NAME}'"
        )

    return instances


def get_current_tag():
    resp = ssm.get_parameter(Name=SSM_PARAMETER_NAME)
    return resp["Parameter"]["Value"]


def set_current_tag(tag):
    ssm.put_parameter(
        Name=SSM_PARAMETER_NAME,
        Value=tag,
        Type="String",
        Overwrite=True,
    )


def run_deploy_on_instance(instance_id, image_tag):
    """
    Run deploy.sh on one instance through SSM.

    Returns True when deploy.sh exits successfully.
    Returns False when the command or deployment fails.
    """
    logger.info("Deploying %s to %s", image_tag, instance_id)

    try:
        send_resp = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={
                "commands": [
                    f"/opt/retailedge/deploy.sh {image_tag}"
                ]
            },
            TimeoutSeconds=COMMAND_TIMEOUT_SECONDS,
        )
    except Exception:
        logger.exception(
            "Failed to send SSM command to %s",
            instance_id,
        )
        return False

    command_id = send_resp["Command"]["CommandId"]

    deadline = time.time() + COMMAND_TIMEOUT_SECONDS + 30

    # Poll SSM until the command finishes.
    while time.time() < deadline:
        time.sleep(POLL_INTERVAL_SECONDS)

        try:
            invocation = ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id,
            )
        except ssm.exceptions.InvocationDoesNotExist:
            continue

        status = invocation["Status"]

        if status in ("Pending", "InProgress", "Delayed"):
            continue

        if status == "Success" and invocation.get("ResponseCode") == 0:
            logger.info(
                "Deploy of %s on %s succeeded",
                image_tag,
                instance_id,
            )
            return True

        logger.error(
            "Deploy of %s on %s failed - status=%s response_code=%s output=%s",
            image_tag,
            instance_id,
            status,
            invocation.get("ResponseCode"),
            invocation.get("StandardOutputContent", "")[-2000:],
        )
        return False

    logger.error(
        "Timed out waiting for deploy of %s on %s",
        image_tag,
        instance_id,
    )
    return False


def rollback(instances_to_rollback, previous_tag):
    """
    Roll back each instance and verify the result.
    """
    failed = []

    for instance_id in instances_to_rollback:
        logger.warning(
            "Rolling back %s to %s",
            instance_id,
            previous_tag,
        )

        ok = run_deploy_on_instance(instance_id, previous_tag)

        if not ok:
            failed.append(instance_id)

    return len(failed) == 0, failed


def publish_mixed_state_alert(
    failed_instances,
    new_tag,
    previous_tag,
):
    if not SNS_TOPIC_ARN:
        logger.error(
            "No SNS_TOPIC_ARN configured - cannot alert on mixed state. "
            "Failed instances: %s",
            failed_instances,
        )
        return

    message = (
        "CRITICAL: RetailEdge deployment rollback failed.\n\n"
        f"Failed instances:\n{json.dumps(failed_instances, indent=2)}\n\n"
        f"Attempted rollback from {new_tag} to {previous_tag}.\n"
        "Manual intervention is required."
    )

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="RetailEdge deployment: fleet in mixed state",
            Message=message,
        )
    except Exception:
        logger.exception("Failed to publish mixed-state SNS alert")


def chunk(items, size):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def handler(event, context):
    image_tag = event.get("image_tag")

    if not image_tag:
        return {
            "success": False,
            "reason": "event must include 'image_tag'",
        }

    # Save the current tag before starting so it can be used for rollback.
    instances = get_in_service_instance_ids()
    previous_tag = get_current_tag()

    logger.info(
        "Starting deployment: %s -> %s across %d instance(s), batch_size=%d",
        previous_tag,
        image_tag,
        len(instances),
        BATCH_SIZE,
    )

    deployed_instances = []

    for batch in chunk(instances, BATCH_SIZE):
        batch_results = {
            instance_id: run_deploy_on_instance(
                instance_id,
                image_tag,
            )
            for instance_id in batch
        }

        succeeded = [
            instance_id
            for instance_id, ok in batch_results.items()
            if ok
        ]

        failed = [
            instance_id
            for instance_id, ok in batch_results.items()
            if not ok
        ]

        deployed_instances.extend(succeeded)

        if failed:
            logger.error(
                "Batch failed on %s - rolling back %d instance(s) to %s",
                failed,
                len(deployed_instances),
                previous_tag,
            )

            rollback_ok, rollback_failed = rollback(
                deployed_instances,
                previous_tag,
            )

            if not rollback_ok:
                publish_mixed_state_alert(
                    rollback_failed,
                    image_tag,
                    previous_tag,
                )

                return {
                    "success": False,
                    "mixed_state": True,
                    "reason": (
                        f"Deployment of {image_tag} failed on {failed}, "
                        f"and rollback to {previous_tag} also failed on "
                        f"{rollback_failed}. Manual intervention required."
                    ),
                }

            return {
                "success": False,
                "mixed_state": False,
                "reason": (
                    f"Deployment of {image_tag} failed on {failed}. "
                    f"All updated instances were rolled back to "
                    f"{previous_tag}."
                ),
            }

    # Only mark the new image as deployed after the whole fleet succeeds.
    set_current_tag(image_tag)

    logger.info(
        "Deployment of %s succeeded on all %d instance(s)",
        image_tag,
        len(instances),
    )

    return {
        "success": True,
        "reason": (
            f"Deployed {image_tag} to "
            f"{len(instances)} instance(s)."
        ),
    }