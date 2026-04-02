output "primary_bucket_name" {
  description = "Primary S3 bucket name (us-east-1)"
  value       = module.primary_bucket.bucket_id
}

output "primary_bucket_arn" {
  description = "Primary S3 bucket ARN"
  value       = module.primary_bucket.bucket_arn
}

output "replica_bucket_name" {
  description = "Replica S3 bucket name (us-west-2)"
  value       = module.replica_bucket.bucket_id
}

output "replica_bucket_arn" {
  description = "Replica S3 bucket ARN"
  value       = module.replica_bucket.bucket_arn
}

output "replication_role_arn" {
  description = "IAM role ARN used by S3 to perform replication"
  value       = aws_iam_role.replication.arn
}
