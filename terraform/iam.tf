# =============================================================================
# IAM — Roles and policies for Lambda execution and Cognito user-pool groups
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Lambda Execution Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaAssume"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = "DMAIIN"
    Phase   = "1"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_custom" {
  name = "${var.project_name}-lambda-custom-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ------ S3: read/write raw, processed, and reports buckets ------
      {
        Sid    = "S3ReadWriteBuckets"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-raw-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::${var.project_name}-processed-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::${var.project_name}-reports-${data.aws_caller_identity.current.account_id}/*"
        ]
      },

      # ------ DynamoDB: CRUD on submissions and audit_log tables ------
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions/index/*",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-audit-log",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-audit-log/index/*"
        ]
      },

      # ------ KMS: encrypt / decrypt via the project key ------
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.main.arn
        ]
      },

      # ------ X-Ray: tracing ------
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = [
          "arn:aws:xray:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/${var.project_name}-*",
          "arn:aws:xray:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:sampling-rule/*"
        ]
      },

      # ------ SQS: send to dead-letter queue ------
      {
        Sid    = "SQSSendDeadLetter"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.project_name}-dlq"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 2. Cognito – Student Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cognito_student" {
  name = "${var.project_name}-student-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCognitoAssume"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          "StringEquals" = {
            "cognito-identity.amazonaws.com:aud" = "us-east-1:*"
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = {
    Project = "DMAIIN"
    Phase   = "1"
  }
}

resource "aws_iam_role_policy" "cognito_student" {
  name = "${var.project_name}-student-policy"
  role = aws_iam_role.cognito_student.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Students may upload to their own prefix in the raw bucket
      {
        Sid    = "S3PutOwnPrefix"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-raw-${data.aws_caller_identity.current.account_id}/$${cognito-identity.amazonaws.com:sub}/*"
        ]
      },
      # Students may read their own submissions
      {
        Sid    = "DynamoDBReadOwnSubmissions"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions/index/*"
        ]
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:LeadingKeys" = "$${cognito-identity.amazonaws.com:sub}"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 3. Cognito – Faculty Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cognito_faculty" {
  name = "${var.project_name}-faculty-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCognitoAssume"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          "StringEquals" = {
            "cognito-identity.amazonaws.com:aud" = "us-east-1:*"
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = {
    Project = "DMAIIN"
    Phase   = "1"
  }
}

resource "aws_iam_role_policy" "cognito_faculty" {
  name = "${var.project_name}-faculty-policy"
  role = aws_iam_role.cognito_faculty.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Faculty may read objects in raw, processed, and reports buckets
      {
        Sid    = "S3ReadBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-raw-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::${var.project_name}-processed-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::${var.project_name}-reports-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      # Faculty may read and list submissions
      {
        Sid    = "DynamoDBReadSubmissions"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions/index/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 4. Cognito – Admin Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cognito_admin" {
  name = "${var.project_name}-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCognitoAssume"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          "StringEquals" = {
            "cognito-identity.amazonaws.com:aud" = "us-east-1:*"
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = {
    Project = "DMAIIN"
    Phase   = "1"
  }
}

resource "aws_iam_role_policy" "cognito_admin" {
  name = "${var.project_name}-admin-policy"
  role = aws_iam_role.cognito_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Admins have broad S3 access across project buckets
      {
        Sid    = "S3BroadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-raw-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::${var.project_name}-raw-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::${var.project_name}-processed-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::${var.project_name}-processed-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::${var.project_name}-reports-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::${var.project_name}-reports-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      # Admins have broad DynamoDB access on both tables
      {
        Sid    = "DynamoDBBroadAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-submissions/index/*",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-audit-log",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-audit-log/index/*"
        ]
      },
      # Admins may perform Cognito user-management actions
      {
        Sid    = "CognitoAdminActions"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:AdminEnableUser",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminListGroupsForUser",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminRemoveUserFromGroup",
          "cognito-idp:ListUsers",
          "cognito-idp:ListGroups"
        ]
        Resource = [
          "arn:aws:cognito-idp:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:userpool/${var.project_name}-*"
        ]
      }
    ]
  })
}
