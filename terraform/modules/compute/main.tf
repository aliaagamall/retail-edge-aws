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

# User data: base AMI setup only - Docker + CodeDeploy Agent + SSM Agent 
# releases are handled entirely by CodeDeploy.
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

    # CodeDeploy Agent
    dnf install -y ruby wget
    cd /home/ec2-user
    wget https://aws-codedeploy-${data.aws_region.current.name}.s3.${data.aws_region.current.name}.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    systemctl enable codedeploy-agent
    systemctl start codedeploy-agent

    # SSM Agent (pre-installed on AL2023, ensure it's running)
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
}

data "aws_region" "current" {}

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