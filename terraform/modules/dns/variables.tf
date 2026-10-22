variable "environment" {
  description = "Environment name, used in the zone comment and the Environment tag."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "zone_name" {
  description = "Domain this environment owns, for example the product domain for production and a staging subdomain for staging."
  type        = string
}

variable "wait_for_certificate_validation" {
  description = "Block the apply until ACM issues the certificate. Leave false until the parent domain delegates to this zone's name servers, or the apply waits until it times out."
  type        = bool
  default     = false
}
