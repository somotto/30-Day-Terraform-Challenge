variable "primary_region" {
  description = "AWS region for the primary bucket"
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "AWS region for the replica bucket"
  type        = string
  default     = "us-west-2"
}

variable "app_name" {
  description = "Base name used for all resources"
  type        = string
  default     = "day15-multiregion"
}
