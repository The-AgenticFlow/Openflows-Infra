variable "environment" {
  description = "Environment name; secrets are named openflows/<environment>/..."
  type        = string
}

variable "generated_version" {
  description = "Version of the generated secrets. Increase it to rotate them; External Secrets then updates the cluster."
  type        = number
  default     = 1
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can still be restored."
  type        = number
  default     = 7
}

variable "manager_db_version" {
  description = "Version of the Manager database password. Increase it to rotate it, then rerun the Manager's database job."
  type        = number
  default     = 1
}
