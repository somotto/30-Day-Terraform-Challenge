# KMS key for SecureString encryption
resource "aws_kms_key" "param" {
  description             = "KMS key for SSM parameter ${var.parameter_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "param" {
  name          = "alias/ssm${replace(var.parameter_name, "/", "-")}"
  target_key_id = aws_kms_key.param.key_id
}

# SecureString parameter — value is sensitive, never shown in plan output
resource "aws_ssm_parameter" "this" {
  name        = var.parameter_name
  description = var.description
  type        = "SecureString"
  key_id      = aws_kms_key.param.arn
  value       = var.parameter_value
  tags        = var.tags
}

# IAM policy that allows reading this specific parameter
resource "aws_iam_policy" "read_param" {
  name        = "ssm${replace(var.parameter_name, "/", "-")}-read"
  description = "Allow reading SSM parameter ${var.parameter_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = aws_ssm_parameter.this.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.param.arn
      }
    ]
  })
}
