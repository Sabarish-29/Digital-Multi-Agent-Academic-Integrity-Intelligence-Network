output "api_gateway_url" {
  value       = aws_api_gateway_stage.prod.invoke_url
  description = "API Gateway base URL"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.frontend.id
  description = "Cognito User Pool Client ID for the frontend"
}

output "raw_bucket_name" {
  value       = aws_s3_bucket.raw.id
  description = "S3 bucket for raw submissions"
}

output "processed_bucket_name" {
  value       = aws_s3_bucket.processed.id
  description = "S3 bucket for processed submissions"
}

output "reports_bucket_name" {
  value       = aws_s3_bucket.reports.id
  description = "S3 bucket for reports"
}

output "frontend_bucket_name" {
  value       = aws_s3_bucket.frontend.id
  description = "S3 bucket for frontend static hosting"
}

output "frontend_url" {
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
  description = "Frontend website URL"
}

output "submissions_table_name" {
  value       = aws_dynamodb_table.submissions.name
  description = "DynamoDB submissions table name"
}

output "audit_log_table_name" {
  value       = aws_dynamodb_table.audit_log.name
  description = "DynamoDB audit log table name"
}

output "kms_key_arn" {
  value       = aws_kms_key.main.arn
  description = "KMS encryption key ARN"
}

output "aws_region" {
  value       = var.aws_region
  description = "AWS region"
}
