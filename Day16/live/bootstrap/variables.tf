variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform remote state. Must be globally unique across all AWS accounts."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be 3-63 lowercase alphanumeric characters or hyphens."
  }
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for state locking."
  type        = string
  default     = "terraform-state-lock"
}
