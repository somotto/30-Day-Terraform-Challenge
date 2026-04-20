variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name prefix used across all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | staging | production)"
  type        = string
  default     = "dev"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID for the target region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where all resources will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB (at least two AZs)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ASG instances (at least two AZs)"
  type        = list(string)
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired instance count at launch"
  type        = number
  default     = 2
}
