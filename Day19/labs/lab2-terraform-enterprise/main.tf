terraform {
  required_version = ">= 1.0"
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.51"
    }
  }
}

variable "tfe_organization" {
  description = "Enterprise organisation name."
  type        = string
  default     = "Stephen-Limited"
}

# Create a workspace for the dev environment
resource "tfe_workspace" "dev" {
  name         = "day19-webserver-dev"
  organization = var.tfe_organization
  description  = "Day19 dev webserver cluster — managed by tfe provider"

  # Trigger runs automatically when VCS changes are detected
  auto_apply = false

  terraform_version = "1.6.0"

  tag_names = ["day19", "dev", "webserver"]
}

# Create a workspace for the production environment
resource "tfe_workspace" "production" {
  name         = "day19-webserver-production"
  organization = var.tfe_organization
  description  = "Day19 production webserver cluster — managed by tfe provider"

  # Production requires manual approval before apply
  auto_apply = false

  terraform_version = "1.6.0"

  tag_names = ["day19", "production", "webserver"]
}

resource "tfe_variable_set" "aws_config" {
  name         = "day19-aws-config"
  description  = "Shared AWS configuration variables for Day19 workspaces"
  organization = var.tfe_organization
}

resource "tfe_variable" "aws_region" {
  key             = "aws_region"
  value           = "us-east-1"
  category        = "terraform"
  description     = "AWS region for all Day19 workspaces"
  variable_set_id = tfe_variable_set.aws_config.id
}

# Attach the variable set to both workspaces
resource "tfe_workspace_variable_set" "dev" {
  variable_set_id = tfe_variable_set.aws_config.id
  workspace_id    = tfe_workspace.dev.id
}

resource "tfe_workspace_variable_set" "production" {
  variable_set_id = tfe_variable_set.aws_config.id
  workspace_id    = tfe_workspace.production.id
}

output "dev_workspace_id" {
  value       = tfe_workspace.dev.id
  description = "Terraform Cloud workspace ID for dev environment."
}

output "production_workspace_id" {
  value       = tfe_workspace.production.id
  description = "Terraform Cloud workspace ID for production environment."
}

output "variable_set_id" {
  value       = tfe_variable_set.aws_config.id
  description = "Shared variable set ID."
}
