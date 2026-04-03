variable "bucket_name" {
  description = "Globally unique S3 bucket name for Terraform remote state."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 lowercase alphanumeric characters or hyphens, starting and ending with a letter or number."
  }
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
  default     = "terraform-state-lock"
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "project_name" {
  description = "Project name applied to all resource tags."
  type        = string
  default     = "terraform-challenge"
}

variable "team_name" {
  description = "Owning team name applied to all resource tags."
  type        = string
  default     = "platform-team"
}
