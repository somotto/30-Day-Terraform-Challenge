variable "cluster_name" {
  description = "Name prefix for all cluster resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "cluster_name must be lowercase alphanumeric characters and hyphens only."
  }
}

variable "environment" {
  description = "Deployment environment: dev, staging, or production."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "project_name" {
  description = "Project name applied to all resource tags."
  type        = string
  default     = "terraform-challenge"
}

variable "team_name" {
  description = "Owning team name applied to all resource tags."
  type        = string
  default     = "platform-team"
}

variable "server_port" {
  description = "Port the web server listens on (1024–65535)."
  type        = number
  default     = 8080

  validation {
    condition     = var.server_port >= 1024 && var.server_port <= 65535
    error_message = "server_port must be between 1024 and 65535."
  }
}

variable "instance_type" {
  description = "EC2 instance type. Must be t2 or t3 family."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t[23]\\.", var.instance_type))
    error_message = "Instance type must be a t2 or t3 family type."
  }
}

variable "ami" {
  description = "AMI ID override."
  type        = string
  default     = ""
}

variable "min_size" {
  description = "Minimum number of instances in the ASG."
  type        = number
  default     = 1

  validation {
    condition     = var.min_size >= 1
    error_message = "min_size must be at least 1."
  }
}

variable "max_size" {
  description = "Maximum number of instances in the ASG."
  type        = number
  default     = 2

  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }
}

variable "app_version" {
  description = "Application version string rendered into the HTML response. Day 20 uses v3."
  type        = string
  default     = "v3"
}

variable "cpu_alarm_threshold" {
  description = "CPU utilisation percentage that triggers the high-CPU CloudWatch alarm."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be between 1 and 100."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch log group entries."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value."
  }
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications. Leave empty to skip."
  type        = string
  default     = ""
}

variable "custom_tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

variable "secret_source" {
  description = "Where the instance fetches its secret at boot: ssm, secretsmanager, or none."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["ssm", "secretsmanager", "none"], var.secret_source)
    error_message = "secret_source must be ssm, secretsmanager, or none."
  }
}

variable "secret_ref" {
  description = "SSM parameter name or Secrets Manager secret ARN to fetch at boot."
  type        = string
  default     = ""
}

variable "secret_policy_arns" {
  description = "IAM policy ARNs to attach to the instance role for secret access."
  type        = list(string)
  default     = []
}
