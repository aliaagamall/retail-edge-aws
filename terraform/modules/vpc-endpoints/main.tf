locals {
  name_prefix = "${var.project_name}-${var.environment}"

  interface_services = {
    ecr_api        = "com.amazonaws.${var.aws_region}.ecr.api"
    ecr_dkr        = "com.amazonaws.${var.aws_region}.ecr.dkr"
    secretsmanager = "com.amazonaws.${var.aws_region}.secretsmanager"
    ssm            = "com.amazonaws.${var.aws_region}.ssm"
    ssmmessages    = "com.amazonaws.${var.aws_region}.ssmmessages"
    ec2messages    = "com.amazonaws.${var.aws_region}.ec2messages"
  }
}

# Interface Endpoints 
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_services

  vpc_id              = var.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.app_subnet_ids
  security_group_ids  = [var.endpoints_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-vpce-${replace(each.key, "_", "-")}"
  }
}

# Gateway Endpoint (S3) 
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.app_route_table_id]

  tags = {
    Name = "${local.name_prefix}-vpce-s3"
  }
}