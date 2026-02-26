# ============================================================================
# Amazon CloudWatch - Monitoring Dashboard & Alarms
# ============================================================================

# ============================================================================
# 1. CloudWatch Dashboard
# ============================================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ---- Row 1: Upload throughput & Lambda errors ----
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Uploads Per Hour"
          region = data.aws_region.current.name
          period = 3600
          stat   = "Sum"
          metrics = [
            [
              "AWS/Lambda",
              "Invocations",
              "FunctionName",
              aws_lambda_function.intake_handler.function_name,
            ],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = data.aws_region.current.name
          period = 300
          stat   = "Sum"
          metrics = [
            [
              "AWS/Lambda",
              "Errors",
              "FunctionName",
              aws_lambda_function.intake_handler.function_name,
            ],
            [
              "AWS/Lambda",
              "Errors",
              "FunctionName",
              aws_lambda_function.get_submission_metadata.function_name,
            ],
            [
              "AWS/Lambda",
              "Errors",
              "FunctionName",
              aws_lambda_function.get_submission_status.function_name,
            ],
            [
              "AWS/Lambda",
              "Errors",
              "FunctionName",
              aws_lambda_function.audit_logger.function_name,
            ],
          ]
        }
      },

      # ---- Row 2: S3 bucket metrics ----
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "S3 Bucket Size"
          region = data.aws_region.current.name
          period = 86400
          stat   = "Average"
          metrics = [
            [
              "AWS/S3",
              "BucketSizeBytes",
              "BucketName",
              aws_s3_bucket.raw.id,
              "StorageType",
              "StandardStorage",
            ],
            [
              "AWS/S3",
              "NumberOfObjects",
              "BucketName",
              aws_s3_bucket.raw.id,
              "StorageType",
              "AllStorageTypes",
            ],
          ]
        }
      },

      # ---- Row 2: DynamoDB capacity ----
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB Read/Write"
          region = data.aws_region.current.name
          period = 300
          stat   = "Sum"
          metrics = [
            [
              "AWS/DynamoDB",
              "ConsumedReadCapacityUnits",
              "TableName",
              aws_dynamodb_table.submissions.name,
            ],
            [
              "AWS/DynamoDB",
              "ConsumedWriteCapacityUnits",
              "TableName",
              aws_dynamodb_table.submissions.name,
            ],
          ]
        }
      },

      # ---- Row 3: API Gateway errors ----
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway 4xx/5xx"
          region = data.aws_region.current.name
          period = 300
          stat   = "Sum"
          metrics = [
            [
              "AWS/ApiGateway",
              "4XXError",
              "ApiName",
              "${var.project_name}-api",
            ],
            [
              "AWS/ApiGateway",
              "5XXError",
              "ApiName",
              "${var.project_name}-api",
            ],
          ]
        }
      },
    ]
  })
}

# ============================================================================
# 2. CloudWatch Alarms
# ============================================================================

# ----------------------------------------------------------------------------
# Lambda Error Alarm - Intake Handler
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "intake_handler_errors" {
  alarm_name          = "${var.project_name}-intake-handler-error-alarm"
  alarm_description   = "Triggers when the intake-handler Lambda function exceeds 5 errors within 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.intake_handler.function_name
  }

  tags = {
    Name        = "${var.project_name}-intake-handler-error-alarm"
    Environment = var.environment
  }
}
