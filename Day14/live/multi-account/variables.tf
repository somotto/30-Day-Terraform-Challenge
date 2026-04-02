variable "production_role_arn" {
  description = "IAM role ARN in the production account for Terraform to assume"
  type        = string
}

variable "staging_role_arn" {
  description = "IAM role ARN in the staging account for Terraform to assume"
  type        = string
}
