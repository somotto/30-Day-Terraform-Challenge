variable "secret_name" {
  description = "Name/path of the secret in Secrets Manager (e.g. prod/myapp/db_password)"
  type        = string
}

variable "description" {
  description = "Human-readable description of the secret"
  type        = string
  default     = ""
}

variable "secret_value" {
  description = "Initial secret value (JSON string). Marked sensitive — never shown in plan output."
  type        = string
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = "Days before a deleted secret is permanently removed (0 = force delete)"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
