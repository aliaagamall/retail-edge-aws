locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------
# Deployment version tracking.
#
# GitHub Actions writes the newly pushed image tag here after a successful ECR push. 
# EC2 instances read it to know which image to pull and run.
# Terraform creates this parameter once with a placeholder value.
# After that, GitHub Actions owns its content - ignore_changes
# prevents Terraform from ever overwriting a real deployed tag back
# to the placeholder on a later apply.
# ---------------------------------------------------------------------
resource "aws_ssm_parameter" "current_image" {
  name        = "/retailedge/${var.environment}/current-image"
  description = "Current deployed application image tag for ${var.environment}"
  type        = "String"
  value       = "none"

  tags = {
    Name = "${local.name_prefix}-current-image"
  }

  lifecycle {
    ignore_changes = [value]
  }
}