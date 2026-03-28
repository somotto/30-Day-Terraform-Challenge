# KMS key for encrypting the secret
resource "aws_kms_key" "secret" {
  description             = "KMS key for ${var.secret_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "secret" {
  name          = "alias/${replace(var.secret_name, "/", "-")}"
  target_key_id = aws_kms_key.secret.key_id
}

# The secret container — value is set outside Terraform (CLI / rotation lambda)
resource "aws_secretsmanager_secret" "this" {
  name                    = var.secret_name
  description             = var.description
  kms_key_id              = aws_kms_key.secret.arn
  recovery_window_in_days = var.recovery_window_in_days
  tags                    = var.tags
}

# Initial secret value — marked sensitive so it never appears in plan output.
# In production, prefer setting this via CLI or a rotation Lambda instead.
resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.secret_value
}

# IAM policy that allows reading this specific secret
resource "aws_iam_policy" "read_secret" {
  name        = "${replace(var.secret_name, "/", "-")}-read"
  description = "Allow reading ${var.secret_name} from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.this.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.secret.arn
      }
    ]
  })
}
