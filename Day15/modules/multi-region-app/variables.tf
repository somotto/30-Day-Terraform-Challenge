variable "app_name" {
  description = "Base name for the S3 buckets (must be globally unique when combined with suffix)"
  type        = string
}

variable "suffix" {
  description = "Random suffix appended to bucket names to ensure global uniqueness"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
