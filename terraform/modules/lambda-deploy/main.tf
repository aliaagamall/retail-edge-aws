locals {
  name_prefix   = "${var.project_name}-${var.environment}"
  function_name = "${local.name_prefix}-deploy"
}

data "aws_caller_identity" "current" {}

# Package the Lambda handler into a ZIP.
data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.root}/lambda/deploy/handler.py"
  output_path = "${path.module}/build/deploy-handler.zip"
}

# IAM role assumed by the Lambda function.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-deploy-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Name = "${local.name_prefix}-deploy-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permissions required for deployment, SSM, SSM Parameter Store, and SNS.
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "DescribeASG"
    effect    = "Allow"
    actions   = ["autoscaling:DescribeAutoScalingGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "SendSSMCommand"
    effect = "Allow"

    actions = [
      "ssm:SendCommand",
    ]

    resources = [
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
    ]
  }

  statement {
    sid    = "ReadSSMCommandResults"
    effect = "Allow"

    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ReadWriteCurrentImageParameter"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]

    resources = [var.ssm_parameter_arn]
  }

  statement {
    sid       = "PublishMixedStateAlert"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_policy" "lambda_permissions" {
  name   = "${local.name_prefix}-deploy-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_permissions" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}

# Lambda deployment function.
resource "aws_lambda_function" "deploy" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256

  handler = "handler.handler"
  runtime = "python3.12"
  timeout = var.lambda_timeout_seconds

  environment {
    variables = {
      ASG_NAME                = var.asg_name
      SSM_PARAMETER_NAME      = var.ssm_parameter_name
      SNS_TOPIC_ARN           = var.sns_topic_arn
      BATCH_SIZE              = tostring(var.batch_size)
      COMMAND_TIMEOUT_SECONDS = tostring(var.command_timeout_seconds)
    }
  }

  tags = {
    Name = local.function_name
  }
}