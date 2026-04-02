output "primary_bucket_id" {
  description = "Name of the primary-region S3 bucket"
  value       = aws_s3_bucket.primary.id
}

output "primary_bucket_arn" {
  description = "ARN of the primary-region S3 bucket"
  value       = aws_s3_bucket.primary.arn
}

output "replica_bucket_id" {
  description = "Name of the replica-region S3 bucket"
  value       = aws_s3_bucket.replica.id
}

output "replica_bucket_arn" {
  description = "ARN of the replica-region S3 bucket"
  value       = aws_s3_bucket.replica.arn
}
