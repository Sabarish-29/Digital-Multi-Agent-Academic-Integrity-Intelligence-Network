# ============================================================================
# Amazon DynamoDB - Submissions & Audit Log Tables
# ============================================================================

# ----------------------------------------------------------------------------
# Submissions Table
# Stores metadata for every document submitted for integrity analysis.
# ----------------------------------------------------------------------------

resource "aws_dynamodb_table" "submissions" {
  name         = "${var.project_name}-submissions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "submission_id"

  attribute {
    name = "submission_id"
    type = "S"
  }

  attribute {
    name = "student_id"
    type = "S"
  }

  attribute {
    name = "course_id"
    type = "S"
  }

  attribute {
    name = "upload_timestamp"
    type = "S"
  }

  # GSI: Query submissions by student
  global_secondary_index {
    name            = "student-index"
    hash_key        = "student_id"
    range_key       = "upload_timestamp"
    projection_type = "ALL"
  }

  # GSI: Query submissions by course
  global_secondary_index {
    name            = "course-index"
    hash_key        = "course_id"
    range_key       = "upload_timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  tags = {
    Name        = "${var.project_name}-submissions"
    Environment = var.environment
  }
}

# ----------------------------------------------------------------------------
# Audit Log Table
# Immutable record of every significant action taken within the system.
# ----------------------------------------------------------------------------

resource "aws_dynamodb_table" "audit_log" {
  name         = "${var.project_name}-audit-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "audit_id"

  attribute {
    name = "audit_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "submission_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  # GSI: Query audit entries by user
  global_secondary_index {
    name            = "user-index"
    hash_key        = "user_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # GSI: Query audit entries by submission
  global_secondary_index {
    name            = "submission-index"
    hash_key        = "submission_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  tags = {
    Name        = "${var.project_name}-audit-log"
    Environment = var.environment
  }
}
