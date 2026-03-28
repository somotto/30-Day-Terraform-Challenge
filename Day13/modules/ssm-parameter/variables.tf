variable "parameter_name" {
  description = "SSM parameter path (e.g. /webservers-dev/db_password)"
  type        = string
}

variable "description" {
  description = "Human-readable description of the parameter"
  type        = string
  default     = ""
}

variable "parameter_value" {
  description = "The secret value. Marked sensitive — never shown in plan output."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
