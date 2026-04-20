variable "launch_template_id" {
  description = "ID of the EC2 launch template"
  type        = string
}

variable "launch_template_version" {
  description = "Version of the EC2 launch template"
  type        = string
  default     = "$Latest"
}

variable "subnet_ids" {
  description = "List of private subnet IDs where ASG instances will launch"
  type        = list(string)
}

variable "target_group_arns" {
  description = "List of ALB target group ARNs to attach to the ASG"
  type        = list(string)
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired number of instances at launch"
  type        = number
  default     = 2
}

variable "cpu_scale_out_threshold" {
  description = "Average CPU % at which to add one instance"
  type        = number
  default     = 70
}

variable "cpu_scale_in_threshold" {
  description = "Average CPU % at which to remove one instance"
  type        = number
  default     = 30
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "force_delete" {
  description = "Force delete the ASG without waiting for instances to drain — safe for dev, never use in production"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}