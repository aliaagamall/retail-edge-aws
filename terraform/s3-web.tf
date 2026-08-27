module "s3_web" {
  source = "./modules/s3-web"

  project_name = var.project_name
  environment  = var.environment
}

data "aws_iam_policy_document" "cloudfront_s3_access" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${module.s3_web.bucket_arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values = [
        module.cloudfront.distribution_arn
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = module.s3_web.bucket_name
  policy = data.aws_iam_policy_document.cloudfront_s3_access.json
}
