# =============================================================================
# KMS — Customer-managed key for encrypting S3 objects and DynamoDB tables
# =============================================================================

resource "aws_kms_key" "main" {
  description             = "DMAIIN encryption key for S3 and DynamoDB"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "dmaiin-key-policy"
    Statement = [
      {
        Sid    = "EnableRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Project = "DMAIIN"
    Phase   = "1"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/dmaiin-encryption-key"
  target_key_id = aws_kms_key.main.key_id
}
