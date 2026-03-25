provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "user_count" {
  description = "How many numbered IAM users to create with count"
  type        = number
  default     = 3
}

resource "aws_iam_user" "count_example" {
  count = var.user_count
  name  = "day10-count-user-${count.index}"

  tags = {
    ManagedBy = "terraform"
    Day       = "10"
    Method    = "count"
  }
}

variable "user_names_list" {
  description = "List-based users — demonstrates the count index fragility"
  type        = list(string)
  default     = ["alice", "bob", "charlie"]
}

resource "aws_iam_user" "list_example" {
  count = length(var.user_names_list)
  name  = "day10-list-${var.user_names_list[count.index]}"

  tags = {
    ManagedBy = "terraform"
    Day       = "10"
    Method    = "count-list"
  }
}

variable "user_names_set" {
  description = "Set-based users — safe to remove any entry without side effects"
  type        = set(string)
  default     = ["alice", "bob", "charlie"]
}

resource "aws_iam_user" "set_example" {
  for_each = var.user_names_set
  name     = "day10-set-${each.value}"

  tags = {
    ManagedBy = "terraform"
    Day       = "10"
    Method    = "for_each-set"
  }
}

variable "users" {
  description = "Map of users with per-user configuration"
  type = map(object({
    department = string
    admin      = bool
  }))
  default = {
    alice   = { department = "engineering", admin = true }
    bob     = { department = "marketing", admin = false }
    charlie = { department = "devops", admin = true }
  }
}

resource "aws_iam_user" "map_example" {
  for_each = var.users
  name     = "day10-map-${each.key}"

  tags = {
    ManagedBy  = "terraform"
    Day        = "10"
    Method     = "for_each-map"
    Department = each.value.department
    Admin      = tostring(each.value.admin)
  }
}

# List of uppercase names from the set variable
output "upper_names" {
  description = "Uppercase version of all set-based user names"
  value       = [for name in var.user_names_set : upper(name)]
}

# Map of username → ARN for all map-based IAM users
output "user_arns" {
  description = "Map of username to IAM user ARN — useful for policy attachments"
  value       = { for name, user in aws_iam_user.map_example : name => user.arn }
}

# Filter: only admin users
output "admin_users" {
  description = "Names of users with admin = true"
  value       = [for name, cfg in var.users : name if cfg.admin]
}

# Map of count-based users: name → ARN
output "count_user_arns" {
  description = "Map of count-based user names to their ARNs"
  value       = { for user in aws_iam_user.count_example : user.name => user.arn }
}
