output "bucket_name" {
  value       = module.static_website.bucket_name
  description = "Name of the S3 bucket"
}

output "website_endpoint" {
  value       = module.static_website.website_endpoint
  description = "S3 static website endpoint"
}

output "cloudfront_domain_name" {
  value       = module.static_website.cloudfront_domain_name
  description = "CloudFront URL - open this in your browser"
}

output "cloudfront_distribution_id" {
  value       = module.static_website.cloudfront_distribution_id
  description = "CloudFront distribution ID"
}
