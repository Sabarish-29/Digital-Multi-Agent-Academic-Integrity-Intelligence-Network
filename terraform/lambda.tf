# ============================================================================
# AWS Lambda - Serverless Functions & Supporting Resources
# ============================================================================

# ----------------------------------------------------------------------------
# SQS Dead Letter Queue
# Captures failed Lambda invocations for later inspection and replay.
# ----------------------------------------------------------------------------

resource "aws_sqs_queue" "lambda_dlq" {
  name                       = "${var.project_name}-lambda-dlq"
  message_retention_seconds  = 1209600 # 14 days
  kms_master_key_id          = aws_kms_key.main.arn
  kms_data_key_reuse_period_seconds = 300

  tags = {
    Name        = "${var.project_name}-lambda-dlq"
    Environment = var.environment
  }
}

# ============================================================================
# Archive Data Sources - Package Lambda code automatically
# ============================================================================

data "archive_file" "intake_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/intake-handler/"
  output_path = "${path.module}/../lambda/intake-handler/package.zip"

  excludes = [
    "package.zip",
    "__pycache__",
    "*.pyc",
    "tests",
    "test_*.py",
    "*_test.py",
  ]
}

data "archive_file" "get_submission_metadata" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/get-submission-metadata/"
  output_path = "${path.module}/../lambda/get-submission-metadata/package.zip"

  excludes = [
    "package.zip",
    "__pycache__",
    "*.pyc",
    "tests",
    "test_*.py",
    "*_test.py",
  ]
}

data "archive_file" "get_submission_status" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/get-submission-status/"
  output_path = "${path.module}/../lambda/get-submission-status/package.zip"

  excludes = [
    "package.zip",
    "__pycache__",
    "*.pyc",
    "tests",
    "test_*.py",
    "*_test.py",
  ]
}

data "archive_file" "audit_logger" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/audit-logger/"
  output_path = "${path.module}/../lambda/audit-logger/package.zip"

  excludes = [
    "package.zip",
    "__pycache__",
    "*.pyc",
    "tests",
    "test_*.py",
    "*_test.py",
  ]
}

# ============================================================================
# Lambda Functions
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Intake Handler
# Receives new document submissions, validates them, stores in S3 and records
# metadata in DynamoDB.
# ----------------------------------------------------------------------------

resource "aws_lambda_function" "intake_handler" {
  function_name    = "${var.project_name}-intake-handler"
  description      = "Receives and validates new document submissions"
  runtime          = "python3.11"
  handler          = "lambda_function.lambda_handler"
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds
  role             = aws_iam_role.lambda_execution.arn
  filename         = data.archive_file.intake_handler.output_path
  source_code_hash = data.archive_file.intake_handler.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      RAW_BUCKET          = aws_s3_bucket.raw.id
      SUBMISSIONS_TABLE   = aws_dynamodb_table.submissions.name
      AUDIT_TABLE         = aws_dynamodb_table.audit_log.name
      MAX_FILE_SIZE       = var.max_upload_size_bytes
      AUDIT_FUNCTION_NAME = aws_lambda_function.audit_logger.function_name
    }
  }

  tags = {
    Name        = "${var.project_name}-intake-handler"
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.intake_handler]
}

resource "aws_cloudwatch_log_group" "intake_handler" {
  name              = "/aws/lambda/${var.project_name}-intake-handler"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-intake-handler-logs"
    Environment = var.environment
  }
}

# ----------------------------------------------------------------------------
# 2. Get Submission Metadata
# Returns full metadata for a given submission, including analysis results.
# ----------------------------------------------------------------------------

resource "aws_lambda_function" "get_submission_metadata" {
  function_name    = "${var.project_name}-get-submission-metadata"
  description      = "Returns full metadata for a given submission"
  runtime          = "python3.11"
  handler          = "lambda_function.lambda_handler"
  memory_size      = 256
  timeout          = 10
  role             = aws_iam_role.lambda_execution.arn
  filename         = data.archive_file.get_submission_metadata.output_path
  source_code_hash = data.archive_file.get_submission_metadata.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      SUBMISSIONS_TABLE   = aws_dynamodb_table.submissions.name
      AUDIT_TABLE         = aws_dynamodb_table.audit_log.name
      AUDIT_FUNCTION_NAME = aws_lambda_function.audit_logger.function_name
    }
  }

  tags = {
    Name        = "${var.project_name}-get-submission-metadata"
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.get_submission_metadata]
}

resource "aws_cloudwatch_log_group" "get_submission_metadata" {
  name              = "/aws/lambda/${var.project_name}-get-submission-metadata"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-get-submission-metadata-logs"
    Environment = var.environment
  }
}

# ----------------------------------------------------------------------------
# 3. Get Submission Status
# Lightweight status check endpoint for polling submission progress.
# ----------------------------------------------------------------------------

resource "aws_lambda_function" "get_submission_status" {
  function_name    = "${var.project_name}-get-submission-status"
  description      = "Lightweight status check for submission progress"
  runtime          = "python3.11"
  handler          = "lambda_function.lambda_handler"
  memory_size      = 256
  timeout          = 10
  role             = aws_iam_role.lambda_execution.arn
  filename         = data.archive_file.get_submission_status.output_path
  source_code_hash = data.archive_file.get_submission_status.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      SUBMISSIONS_TABLE = aws_dynamodb_table.submissions.name
    }
  }

  tags = {
    Name        = "${var.project_name}-get-submission-status"
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.get_submission_status]
}

resource "aws_cloudwatch_log_group" "get_submission_status" {
  name              = "/aws/lambda/${var.project_name}-get-submission-status"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-get-submission-status-logs"
    Environment = var.environment
  }
}

# ----------------------------------------------------------------------------
# 4. Audit Logger
# Central audit logging function invoked by other Lambdas to record actions
# in the audit-log DynamoDB table.
# ----------------------------------------------------------------------------

resource "aws_lambda_function" "audit_logger" {
  function_name    = "${var.project_name}-audit-logger"
  description      = "Records audit trail entries for all system actions"
  runtime          = "python3.11"
  handler          = "lambda_function.lambda_handler"
  memory_size      = 256
  timeout          = 10
  role             = aws_iam_role.lambda_execution.arn
  filename         = data.archive_file.audit_logger.output_path
  source_code_hash = data.archive_file.audit_logger.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      AUDIT_TABLE = aws_dynamodb_table.audit_log.name
    }
  }

  tags = {
    Name        = "${var.project_name}-audit-logger"
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.audit_logger]
}

resource "aws_cloudwatch_log_group" "audit_logger" {
  name              = "/aws/lambda/${var.project_name}-audit-logger"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-audit-logger-logs"
    Environment = var.environment
  }
}
