variable "cluster_name" {
  description = "Name prefix for all cluster resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, staging, or production"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "server_port" {
  description = "Port the web server listens on"
  type        = number
  default     = 8080
}

variable "enable_detailed_monitoring" {
  description = "Enable CloudWatch detailed monitoring (incurs additional cost)"
  type        = bool
  default     = false
}

variable "enable_autoscaling" {
  description = "Create scale-out/in autoscaling policies and CloudWatch alarms"
  type        = bool
  default     = true
}

variable "use_existing_vpc" {
  description = "Look up an existing VPC tagged Name=existing-vpc instead of using the default VPC"
  type        = bool
  default     = false
}

variable "extra_alb_ingress_rules" {
  description = "Additional ingress rules to attach to the ALB security group"
  type = map(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = {}
}

variable "custom_tags" {
  description = "Extra tags merged onto all resources"
  type        = map(string)
  default     = {}
}
