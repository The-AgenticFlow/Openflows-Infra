# Environment network: one VPC across several AZs, public subnets for the
# ALB and NAT gateways, private subnets for EKS nodes and data services.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # From a /16: private subnets are /20s (4096 addresses, room for EKS pod IPs),
  # public subnets are /24s taken from the top of the range.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 240 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "openflows-${var.environment}"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Nothing public is launched into public subnets except load balancers and NAT.
  map_public_ip_on_launch = false

  # Subnet discovery tags for the AWS Load Balancer Controller.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  # AWS creates the VPC's default security group, NACL and route table without
  # tags, so the permissions boundary forbids adopting them. Nothing uses them.
  manage_default_security_group = false
  manage_default_network_acl    = false
  manage_default_route_table    = false

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = false
  flow_log_cloudwatch_iam_role_arn                = aws_iam_role.flow_logs.arn
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days

  tags = { Environment = var.environment }
}

# Our own flow-log role: the module's role and policy would land outside the
# environment's IAM path, which the permissions boundary refuses.
data "aws_iam_policy_document" "flow_logs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "flow_logs" {
  name                 = "openflows-${var.environment}-vpc-flow-logs"
  path                 = var.iam_path
  assume_role_policy   = data.aws_iam_policy_document.flow_logs_trust.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = { Environment = var.environment }
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream", "logs:PutLogEvents",
      "logs:DescribeLogGroups", "logs:DescribeLogStreams",
    ]
    # The VPC module names its flow-log groups /aws/vpc-flow-log/<vpc-id>.
    resources = [
      "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc-flow-log/*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "vpc-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}
