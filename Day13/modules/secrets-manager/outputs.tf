output "secret_arn" {
  value       = aws_secretsmanager_secret.this.arn
  description = "ARN of the Secrets Manager secret — pass this to instances, not the value"
}

output "secret_name" {
  value       = aws_secretsmanager_secret.this.name
  description = "Name of the secret"
}

output "kms_key_arn" {
  value       = aws_kms_key.secret.arn
  description = "ARN of the KMS key used to encrypt the secret"
}

output "read_policy_arn" {
  value       = aws_iam_policy.read_secret.arn
  description = "IAM policy ARN — attach to any role that needs to read this secret"
}
