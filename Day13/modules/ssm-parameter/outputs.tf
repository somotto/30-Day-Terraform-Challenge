output "parameter_arn" {
  value       = aws_ssm_parameter.this.arn
  description = "ARN of the SSM parameter — pass this to instances, not the value"
}

output "parameter_name" {
  value       = aws_ssm_parameter.this.name
  description = "Name/path of the SSM parameter"
}

output "kms_key_arn" {
  value       = aws_kms_key.param.arn
  description = "ARN of the KMS key used to encrypt the parameter"
}

output "read_policy_arn" {
  value       = aws_iam_policy.read_param.arn
  description = "IAM policy ARN — attach to any role that needs to read this parameter"
}
