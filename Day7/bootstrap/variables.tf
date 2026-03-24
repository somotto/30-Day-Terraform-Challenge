variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Day7 Terraform state S3 bucket"
  type        = string
}
