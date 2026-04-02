resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = "${var.app_name}-primary-${var.suffix}"
  force_destroy = true

  tags = merge(var.tags, {
    Name   = "${var.app_name}-primary"
    Region = "primary"
  })
}

resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "replica" {
  provider      = aws.replica
  bucket        = "${var.app_name}-replica-${var.suffix}"
  force_destroy = true

  tags = merge(var.tags, {
    Name   = "${var.app_name}-replica"
    Region = "replica"
  })
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
