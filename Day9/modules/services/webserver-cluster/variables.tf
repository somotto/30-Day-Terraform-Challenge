variable "cluster_name" {
  description = "The name to use for all cluster resources (used in resource names and tags)"
  type        = string
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, staging, production). Shown on the web page."
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type for the cluster instances"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
}

variable "max_size" {
  description = "Maximum number of EC2 instances in the ASG"
  type        = number
}

variable "server_port" {
  description = "Port the web server listens on for HTTP traffic"
  type        = number
  default     = 8080
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

# v0.0.2 addition — allows callers to attach arbitrary tags to all resources
# without modifying the module itself.
variable "custom_tags" {
  description = "A map of extra tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}
