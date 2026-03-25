variable "cluster_name" {
  description = "Name prefix for all cluster resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
}

variable "server_port" {
  description = "Port the web server listens on"
  type        = number
  default     = 8080
}

# Conditional: toggles autoscaling policies on/off
# count = var.enable_autoscaling ? 1 : 0
variable "enable_autoscaling" {
  description = "Set to true to create scale-out/in autoscaling policies"
  type        = bool
  default     = true
}

# Conditional: drives instance type via local — keeps ternary out of resource blocks
variable "instance_type" {
  description = "Override instance type. Leave null to auto-select based on environment."
  type        = string
  default     = null
}

# for_each: map of extra security group rules callers want opened on the ALB
# e.g. { "https" = { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] } }
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
  description = "Extra tags applied to all resources"
  type        = map(string)
  default     = {}
}
