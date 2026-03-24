variable "cluster_name" {
  description = "The name to use for all cluster resources (used in resource names and tags)"
  type        = string
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
