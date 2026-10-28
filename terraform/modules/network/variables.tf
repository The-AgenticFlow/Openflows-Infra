variable "environment" {
  description = "Environment name, used in resource names and the Environment tag."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR. Must be a /16 so the subnet math leaves room for EKS pod IPs, and must not overlap the other environment."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 CIDR."
  }
}

variable "az_count" {
  description = "Number of availability zones to span. EKS needs at least two."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway instead of one per AZ. Cheaper, but an AZ outage cuts egress for every private subnet."
  type        = bool
}

variable "iam_path" {
  description = "IAM path for roles this module creates. Must be the environment's path under /openflows/."
  type        = string

  validation {
    condition     = startswith(var.iam_path, "/openflows/") && endswith(var.iam_path, "/")
    error_message = "iam_path must start with /openflows/ and end with /."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary every OpenFlows role must carry."
  type        = string
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs."
  type        = number
  default     = 90
}

variable "nat_mode" {
  description = "Egress for private subnets: \"gateway\" (managed NAT gateway, single or per AZ) or \"instance\" (one self-patching t4g.nano NAT instance in the first public subnet; about $8/month instead of $35 plus $0.048/GB, but a single instance with no failover)."
  type        = string
  default     = "gateway"

  validation {
    condition     = contains(["gateway", "instance"], var.nat_mode)
    error_message = "nat_mode must be \"gateway\" or \"instance\"."
  }
}

variable "alb_az_count" {
  description = "How many AZs' public subnets the Load Balancer Controller may place ALBs in (2 to az_count). Each AZ adds a public IPv4 address per ALB."
  type        = number
  default     = 3

  validation {
    condition     = var.alb_az_count >= 2
    error_message = "An ALB needs at least two AZs."
  }
}
