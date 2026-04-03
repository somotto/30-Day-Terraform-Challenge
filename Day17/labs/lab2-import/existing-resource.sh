#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
BUCKET_NAME="day17-import-lab-${ACCOUNT_ID}-${REGION}"

echo "Lab 2: Import Existing Infrastructure"
echo "Account: $ACCOUNT_ID"
echo "Bucket:  $BUCKET_NAME"

# STEP 1: Create the "pre-existing" resource via CLI
echo ""
echo "STEP 1: Creating pre-existing S3 bucket via AWS CLI"
echo "(Simulating a resource created outside of Terraform)"
echo ""
echo "Command: aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Bucket already exists — skipping creation"
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
  echo "Bucket created: $BUCKET_NAME"
fi

# Add a tag to simulate real-world state
aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=CreatedBy,Value=manual},{Key=Environment,Value=dev}]'

echo ""
echo "Bucket exists in AWS but is NOT in any Terraform state file."
echo "Running terraform plan now would show 0 resources (Terraform doesn't know about it)."

# STEP 2: Write the Terraform config for the bucket
echo ""
echo "STEP 2: Writing Terraform configuration for the existing bucket"
echo "File: $LAB_DIR/main.tf"

# Export for use in the heredoc
export BUCKET_NAME

cat > "$LAB_DIR/main.tf" << 'TFEOF'
# Day17 — Lab 2: Import Existing Infrastructure
# This configuration was written AFTER the bucket already existed.
# We use terraform import to bring the existing bucket under management.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# This resource block describes the bucket we want to import.
# The configuration must match the actual state of the resource in AWS,
# otherwise terraform plan will show changes after the import.
resource "aws_s3_bucket" "imported" {
  bucket = "BUCKET_NAME_PLACEHOLDER"

  tags = {
    ManagedBy   = "terraform"
    Environment = "dev"
    Lab         = "day17-import"
    CreatedBy   = "manual"  # preserve the original tag
  }
}

# Block public access — best practice, apply after import
resource "aws_s3_bucket_public_access_block" "imported" {
  bucket                  = aws_s3_bucket.imported.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value       = aws_s3_bucket.imported.bucket
  description = "Imported bucket name."
}

output "bucket_arn" {
  value       = aws_s3_bucket.imported.arn
  description = "Imported bucket ARN."
}
TFEOF

# Replace placeholder with actual bucket name
sed -i "s/BUCKET_NAME_PLACEHOLDER/$BUCKET_NAME/" "$LAB_DIR/main.tf"
echo "Written: $LAB_DIR/main.tf"

# STEP 3: Init
echo ""
echo "STEP 3: terraform init"
terraform -chdir="$LAB_DIR" init -input=false

# STEP 4: Plan BEFORE import — shows resource to add
echo ""
echo "STEP 4: terraform plan BEFORE import"
echo "Expected: Terraform wants to CREATE the bucket (it doesn't know it exists)"
echo ""
terraform -chdir="$LAB_DIR" plan 2>&1 | tail -20

echo ""
echo "Notice: Terraform plans to CREATE the bucket."
echo "If we applied this, it would FAIL because the bucket already exists."
echo "This is exactly the problem terraform import solves."

# STEP 5: Import the existing bucket
echo ""
echo "STEP 5: terraform import"
echo "Command: terraform import aws_s3_bucket.imported $BUCKET_NAME"
echo ""
echo "This reads the current state of the bucket from AWS and writes it"
echo "into the Terraform state file — WITHOUT making any changes to AWS."
echo ""

terraform -chdir="$LAB_DIR" import aws_s3_bucket.imported "$BUCKET_NAME"

echo ""
echo "Import complete. The bucket is now tracked in Terraform state."

# STEP 6: Plan AFTER import — should show minimal changes
echo ""
echo "STEP 6: terraform plan AFTER import"
echo "Expected: Only the public_access_block resource to add (new resource)"
echo "The bucket itself should show no changes (or only tag updates)"
echo ""
terraform -chdir="$LAB_DIR" plan

# STEP 7: Apply to reconcile
echo ""
echo "STEP 7: terraform apply to reconcile configuration with state"
terraform -chdir="$LAB_DIR" apply -auto-approve

# STEP 8: Final plan — should be clean
echo "STEP 8: Final plan — should show No changes"
terraform -chdir="$LAB_DIR" plan

echo "CLEANUP: Run terraform destroy to remove the bucket"
echo "Command: terraform -chdir=$LAB_DIR destroy"
