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

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs."
  type        = number
  default     = 90
}
