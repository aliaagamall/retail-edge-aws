locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Latest Amazon Linux 2023 AMI 
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_region" "current" {}

# User data: base AMI setup + conditional application bootstrap.
# CodeDeploy is no longer part of this architecture - deployment
# orchestration happens via Lambda + SSM (added separately).
# This script only handles the initial container start on boot, reading
# the current image tag from SSM Parameter Store.
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    dnf update -y

    # Docker
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # SSM Agent (pre-installed on AL2023, ensure it's running)
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # ---------------------------------------------------------------
    # Conditional application bootstrap
    # ---------------------------------------------------------------
    # The application reads its own DB/Redis secrets from Secrets
    # Manager at container startup (see config/secrets.js), so no
    # secrets are injected here - only the image reference is needed.

    REGION="${data.aws_region.current.name}"
    ECR_REPO="${var.ecr_repository_url}"
    SSM_PARAM="${var.ssm_parameter_name}"

    IMAGE_TAG=$(aws ssm get-parameter \
      --name "$SSM_PARAM" \
      --region "$REGION" \
      --query "Parameter.Value" \
      --output text 2>/dev/null || echo "none")

    if [ "$IMAGE_TAG" = "none" ] || [ -z "$IMAGE_TAG" ]; then
      echo "[BOOTSTRAP] No image recorded yet in $SSM_PARAM - instance ready, waiting for first deployment."
      exit 0
    fi

    echo "[BOOTSTRAP] Found image tag: $IMAGE_TAG - pulling and starting container."

    aws ecr get-login-password --region "$REGION" \
      | docker login --username AWS --password-stdin "$ECR_REPO"

    docker pull "$ECR_REPO:$IMAGE_TAG"

    docker run -d \
     --name retailedge-app \
     --restart unless-stopped \
     -p 8080:8080 \
     -e AWS_REGION="$REGION" \
     -e DB_SECRET_NAME="${var.db_secret_name}" \
     -e REDIS_SECRET_NAME="${var.redis_secret_name}" \
     "$ECR_REPO:$IMAGE_TAG"

    echo "[BOOTSTRAP] Container started successfully."
  EOF
}

# Launch Template 
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-app-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.app_sg_id]

  user_data = base64encode(local.user_data)

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-app-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group 
resource "aws_autoscaling_group" "app" {
  name                = "${local.name_prefix}-app-asg"
  vpc_zone_identifier = var.app_subnet_ids
  target_group_arns   = [var.target_group_arn]

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.name_prefix}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60.0
  }
}

locals {
  black_friday_scale_up_cron = "0 ${var.scale_up_hour} ${var.scale_up_day} ${var.scale_up_month} *"

  black_friday_scale_down_cron = "0 ${var.scale_down_hour} ${var.scale_down_day} ${var.scale_down_month} *"
}

resource "aws_autoscaling_schedule" "black_friday_scale_up" {
  count = var.enable_scheduled_scaling ? 1 : 0

  scheduled_action_name  = "${local.name_prefix}-black-friday-scale-up"
  autoscaling_group_name = aws_autoscaling_group.app.name

  min_size         = var.scheduled_min_size
  max_size         = var.scheduled_max_size
  desired_capacity = var.scheduled_desired_capacity

  recurrence = local.black_friday_scale_up_cron
  time_zone  = "UTC"
}

resource "aws_autoscaling_schedule" "black_friday_scale_down" {
  count = var.enable_scheduled_scaling ? 1 : 0

  scheduled_action_name  = "${local.name_prefix}-black-friday-scale-down"
  autoscaling_group_name = aws_autoscaling_group.app.name

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  recurrence = local.black_friday_scale_down_cron
  time_zone  = "UTC"
}