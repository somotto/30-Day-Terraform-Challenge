variable "cluster_name" {
  description = "Name prefix for all cluster resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev or production"
  type        = string

  validation {
    condition     = contains(["dev", "production"], var.environment)
    error_message = "Environment must be dev or production."
  }
}

variable "server_port" {
  description = "Port the web server listens on"
  type        = number
  default     = 8080
}

variable "ami" {
  description = "AMI ID for the launch configuration. Changing this triggers a new random_id and a zero-downtime replacement."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 4
}

variable "app_version" {
  description = "Application version string rendered into the HTML response (e.g. v1, v2)"
  type        = string
  default     = "v1"
}

variable "enable_blue_green" {
  description = "When true, provision separate blue and green target groups and a switchable listener rule"
  type        = bool
  default     = false
}

variable "active_environment" {
  description = "Which environment is live when blue/green is enabled: blue or green"
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.active_environment)
    error_message = "active_environment must be blue or green."
  }
}

variable "blue_app_version" {
  description = "App version string for the blue target group"
  type        = string
  default     = "v1"
}

variable "green_app_version" {
  description = "App version string for the green target group"
  type        = string
  default     = "v2"
}

variable "custom_tags" {
  description = "Extra tags merged onto all resources"
  type        = map(string)
  default     = {}
}
