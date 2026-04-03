output "bucket_name" {
  value       = aws_s3_bucket.state.bucket
  description = "S3 bucket name for use in backend configuration blocks."
}

output "bucket_arn" {
  value       = aws_s3_bucket.state.arn
  description = "S3 bucket ARN."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.state_lock.name
  description = "DynamoDB table name for use in backend configuration blocks."
}
