output "state_bucket_name" {
  description = "Name of the S3 bucket — use this in all backend.tf files"
  value       = aws_s3_bucket.terraform_state.id
}
