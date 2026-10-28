variable "aws_account_id" {
  description = "AWS account hosting this environment. Applying against any other account fails."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region for this environment. Must match the backend region."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR for this environment. Must not overlap the other environment."
  type        = string
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway instead of one per AZ."
  type        = bool
}

variable "zone_name" {
  description = "Domain this environment's public hosted zone serves. Empty means no domain yet: no hosted zone or certificate is created."
  type        = string
  default     = ""
}

variable "wait_for_certificate_validation" {
  description = "Wait for ACM to issue the certificate. Set true only after the parent domain delegates to this zone."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version; the add-on versions pinned in modules/eks must support it."
  type        = string
}

variable "node_instance_types" {
  description = "x86 instance types for the node group (the workspace image is amd64 only)."
  type        = list(string)
}

variable "node_ami_release_version" {
  description = "EKS optimized AMI release for the nodes; bump it to patch them."
  type        = string
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
}

variable "node_az_count" {
  description = "How many of the private subnets' AZs nodes use. One keeps EBS volumes reattachable."
  type        = number
}

variable "node_min_size" {
  description = "Minimum nodes."
  type        = number
}

variable "node_desired_size" {
  description = "Nodes to run; no cluster autoscaler runs."
  type        = number
}

variable "node_max_size" {
  description = "Maximum nodes."
  type        = number
}

variable "eks_log_retention_days" {
  description = "Retention of the EKS control plane log group."
  type        = number
}

variable "nat_mode" {
  description = "Private subnet egress: \"gateway\" (managed NAT gateway) or \"instance\" (one t4g.nano NAT instance, no failover)."
  type        = string
}

variable "alb_az_count" {
  description = "AZs whose public subnets ALBs may use; each adds a public IPv4 address per ALB."
  type        = number
}

variable "node_schedule" {
  description = "Off-hours schedule for the node group (stop_cron, start_cron, timezone), or null to run it all the time. Needs node_min_size = 0."
  type = object({
    stop_cron  = string
    start_cron = string
    timezone   = string
  })
  default = null
}
