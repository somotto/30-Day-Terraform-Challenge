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
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_west"
  region = "us-west-2"
}

resource "random_id" "suffix" {
  byte_length = 4
}


module "primary_bucket" {
  source = "../../modules/s3-bucket"

  bucket_name        = "day14-primary-${random_id.suffix.hex}"
  environment        = "demo"
  versioning_enabled = true   # versioning is required on the replication source

  tags = { Role = "replication-source" }
}


module "replica_bucket" {
  source = "../../modules/s3-bucket"

  providers = {
    aws = aws.us_west   # <-- routes all resources inside this module to us-west-2
  }

  bucket_name        = "day14-replica-${random_id.suffix.hex}"
  environment        = "demo"
  versioning_enabled = true   # versioning must also be enabled on the destination

  tags = { Role = "replication-destination" }
}

data "aws_iam_policy_document" "s3_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  name               = "day14-s3-replication-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.s3_assume_role.json

  tags = {
    ManagedBy   = "terraform"
    Environment = "demo"
  }
}

data "aws_iam_policy_document" "replication_permissions" {
  # Read from the source bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [module.primary_bucket.bucket_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${module.primary_bucket.bucket_arn}/*"]
  }

  # Write to the destination bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${module.replica_bucket.bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "day14-replication-policy"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication_permissions.json
}

resource "aws_s3_bucket_replication_configuration" "replication" {
  # Replication requires versioning to be enabled first
  depends_on = [module.primary_bucket, module.replica_bucket]

  role   = aws_iam_role.replication.arn
  bucket = module.primary_bucket.bucket_id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = module.replica_bucket.bucket_arn
      storage_class = "STANDARD"
    }
  }
}
