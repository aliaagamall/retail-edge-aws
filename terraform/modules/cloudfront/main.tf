locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# OAC lets CloudFront sign requests to the private S3 bucket
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${local.name_prefix}-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# VPC Origin lets CloudFront reach the internal ALB without a public IP
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name       = "${local.name_prefix}-alb-vpc-origin"
    arn        = var.alb_arn
    http_port  = 80
    https_port = 443
    # No ACM certificate yet, so the ALB only has an HTTP listener
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = {
    Name = "${local.name_prefix}-alb-vpc-origin"
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled      = true
  comment      = "${local.name_prefix} distribution"
  price_class  = var.price_class
  web_acl_id   = var.waf_web_acl_arn
  http_version = "http2and3"

  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_id                = "s3-web"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-api"

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.alb.id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  # Default behavior: static site from S3
  default_cache_behavior {
    target_origin_id       = "s3-web"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # /api/* goes to the internal ALB
  ordered_cache_behavior {
    path_pattern             = var.api_path_pattern
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = false
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # No custom domain yet, use CloudFront's default certificate
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }
}
