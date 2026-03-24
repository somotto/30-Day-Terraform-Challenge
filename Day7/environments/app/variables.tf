variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Which environment's network state to read from"
  type        = string
  default     = "dev"
}

variable "server_port" {
  description = "Port the web server listens on"
  type        = number
  default     = 8080
}
