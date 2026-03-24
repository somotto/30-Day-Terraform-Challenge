variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "server_port" {
  description = "Port the web server listens on"
  type        = number
  default     = 8080
}

# Each workspace maps to a different instance type — cost scales with environment
variable "instance_type" {
  description = "EC2 instance type per environment"
  type        = map(string)
  default = {
    dev        = "t3.micro"
    staging    = "t3.micro"
    production = "t3.micro"
  }
}
