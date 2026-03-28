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
  description = "AMI ID override. Empty string = use latest Amazon Linux 2023."
  type        = string
  default     = ""
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
  description = "Application version string rendered into the HTML response"
  type        = string
  default     = "v1"
}

variable "custom_tags" {
  description = "Extra tags merged onto all resources"
  type        = map(string)
  default     = {}
}

# Secrets

variable "secret_source" {
  description = "Where the instance should fetch its secret: ssm, secretsmanager, or none"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["ssm", "secretsmanager", "none"], var.secret_source)
    error_message = "secret_source must be ssm, secretsmanager, or none."
  }
}

variable "secret_ref" {
  description = "SSM parameter name or Secrets Manager secret ARN to fetch at boot"
  type        = string
  default     = ""
}

variable "secret_policy_arns" {
  description = "List of IAM policy ARNs (from the secrets modules) to attach to the instance role"
  type        = list(string)
  default     = []
}
