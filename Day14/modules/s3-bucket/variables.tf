variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
}

variable "environment" {
  description = "Environment label (dev, staging, production)"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable S3 versioning — required for replication source buckets"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
