locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

# EC2 Instance Role

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_app" {
  name               = "${local.name_prefix}-app-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${local.name_prefix}-app-instance-role"
  }
}

resource "aws_iam_instance_profile" "ec2_app" {
  name = "${local.name_prefix}-app-instance-profile"
  role = aws_iam_role.ec2_app.name
}

# --- Secrets Manager: read-only, scoped to project secrets only ---
# Used both by the application code itself (config/secrets.js at
# container startup) and, if needed, by the bootstrap script.
data "aws_iam_policy_document" "secrets_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secrets_arns
  }
}

resource "aws_iam_policy" "secrets_read" {
  name   = "${local.name_prefix}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = aws_iam_role.ec2_app.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

# ECR: pull permissions only 
data "aws_iam_policy_document" "ecr_pull" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"] # GetAuthorizationToken does not support resource-level scoping
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${var.project_name}-*"
    ]
  }
}

resource "aws_iam_policy" "ecr_pull" {
  name   = "${local.name_prefix}-ecr-pull"
  policy = data.aws_iam_policy_document.ecr_pull.json
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.ec2_app.name
  policy_arn = aws_iam_policy.ecr_pull.arn
}

# SSM: managed instance core (Session Manager, no SSH needed).
# Also grants ssm:GetParameter used by the bootstrap script to read
# /retailedge/<env>/current-image, and allows Lambda to
# reach the instance via SSM Run Command for deployment orchestration.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# GitHub Actions OIDC Role
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${local.name_prefix}-github-oidc"
  }
}

data "aws_iam_policy_document" "github_oidc_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restricted to the exact repo + branch only - not the whole org
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${local.name_prefix}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json

  tags = {
    Name = "${local.name_prefix}-github-deploy-role"
  }
}

# Deploy permissions: push to ECR + record the new image in SSM 
# Lambda, which GitHub Actions will invoke
# once that Lambda exists.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${var.project_name}-*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/retailedge/*"
    ]
  }
}

resource "aws_iam_policy" "github_deploy" {
  name   = "${local.name_prefix}-github-deploy-policy"
  policy = data.aws_iam_policy_document.github_deploy.json
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.github_deploy.arn
}