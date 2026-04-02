output "production_bucket_name" {
  description = "S3 bucket name in the production account"
  value       = module.production_bucket.bucket_id
}

output "production_bucket_arn" {
  description = "S3 bucket ARN in the production account"
  value       = module.production_bucket.bucket_arn
}

output "staging_bucket_name" {
  description = "S3 bucket name in the staging account"
  value       = module.staging_bucket.bucket_id
}

output "staging_bucket_arn" {
  description = "S3 bucket ARN in the staging account"
  value       = module.staging_bucket.bucket_arn
}
