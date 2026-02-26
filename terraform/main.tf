# =============================================================================
# DMAIIN Phase 1 - Main Terraform Entry Point
# =============================================================================
#
# This file serves as the conventional entry point for the DMAIIN Phase 1
# Terraform configuration. Terraform loads all .tf files in this directory
# automatically; the actual resource definitions are split across focused files:
#
#   provider.tf      - AWS provider, backend config, data sources
#   variables.tf     - Input variable declarations
#   outputs.tf       - Output value exports
#   kms.tf           - Customer-managed encryption key
#   iam.tf           - IAM roles and least-privilege policies
#   cognito.tf       - Cognito User Pool, client, and groups
#   s3.tf            - S3 buckets (raw, processed, reports, frontend)
#   dynamodb.tf      - DynamoDB tables (submissions, audit_log)
#   lambda.tf        - Lambda functions, SQS DLQ, log groups
#   apigateway.tf    - REST API, Cognito authorizer, CORS, stage
#   waf.tf           - WAF v2 WebACL with rate limiting
#   cloudtrail.tf    - CloudTrail with S3 data event logging
#   cloudwatch.tf    - CloudWatch dashboard and error alarms
#
# Deployment:
#   terraform init
#   terraform plan  -out=tfplan
#   terraform apply tfplan
#
# Or use the provided script:
#   ./scripts/deploy-phase1.sh apply
# =============================================================================

locals {
  # Common name prefix used across all resources
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags merged with provider default_tags
  common_tags = {
    Project     = "DMAIIN"
    Phase       = "1"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
