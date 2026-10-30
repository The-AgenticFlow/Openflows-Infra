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
  description = "Version of the Manager database password. Increase it to rotate it, then follow \"Deploying the Manager\" in the OpenFlows runbook: refresh the Secret, run the database job, restart the Manager."
  type        = number
  default     = 1
}
