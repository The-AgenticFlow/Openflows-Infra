variable "environment" {
  description = "Environment name; the cluster is named openflows-<environment>."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Add-on versions below must support it."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "control_plane_subnet_ids" {
  description = "Private subnets for the control plane ENIs, at least two AZs."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Private subnets for nodes. One AZ keeps EBS volumes reattachable after a node is replaced."
  type        = list(string)
}

variable "iam_path" {
  description = "IAM path for every role this module creates, /openflows/<environment>/."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary every role this module creates must carry."
  type        = string
}

variable "tags" {
  description = "Tags set at creation on everything the cluster launches (instances, volumes, ENIs, load balancers). The guard rails require Project and Environment."
  type        = map(string)

  validation {
    condition     = contains(keys(var.tags), "Project") && contains(keys(var.tags), "Environment")
    error_message = "tags must include Project and Environment, or the guard rails deny changes to what the cluster creates."
  }
}

variable "admin_role_arns" {
  description = "IAM roles granted cluster-admin through EKS access entries."
  type        = list(string)
}

variable "viewer_role_arns" {
  description = "IAM roles granted read-only cluster access through EKS access entries."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "x86 instance types for the node group; several types make Spot capacity easier to get."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum nodes."
  type        = number
}

variable "node_desired_size" {
  description = "Nodes to run. No cluster autoscaler runs, so this is the node count."
  type        = number
}

variable "node_max_size" {
  description = "Maximum nodes."
  type        = number
}

variable "node_ami_release_version" {
  description = "EKS optimized AL2023 AMI release for the nodes; changing it rolls them. Latest: the release_version SSM parameter for the Kubernetes version."
  type        = string
}

variable "node_disk_size_gb" {
  description = "Encrypted gp3 root volume per node; holds container images, including the large workspace image."
  type        = number
  default     = 50
}

variable "control_plane_log_types" {
  description = "Control plane log types sent to CloudWatch Logs."
  type        = list(string)
  default     = ["audit", "authenticator"]
}

variable "log_retention_days" {
  description = "Retention of the control plane log group."
  type        = number
}

variable "zone_id" {
  description = "Route 53 zone ExternalDNS manages; set together with zone_name."
  type        = string
  default     = ""
}

variable "zone_name" {
  description = "Domain of zone_id, used as ExternalDNS's domain filter. Empty skips ExternalDNS."
  type        = string
  default     = ""
}
