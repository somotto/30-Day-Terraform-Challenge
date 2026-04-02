terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

provider "aws" {
  alias  = "replica"
  region = var.replica_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

module "multi_region_app" {
  source = "../../modules/multi-region-app"

  app_name = var.app_name
  suffix   = random_id.suffix.hex

  tags = {
    Environment = "demo"
    Challenge   = "30DayTerraform"
    Day         = "15"
  }

  providers = {
    aws.primary = aws.primary
    aws.replica = aws.replica
  }
}
