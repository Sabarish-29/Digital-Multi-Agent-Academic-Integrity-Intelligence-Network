variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "dmaiin"
}

variable "cognito_callback_urls" {
  description = "Allowed callback URLs for Cognito User Pool Client"
  type        = list(string)
  default     = ["http://localhost:3000/"]
}

variable "cognito_logout_urls" {
  description = "Allowed logout URLs for Cognito User Pool Client"
  type        = list(string)
  default     = ["http://localhost:3000/"]
}

variable "frontend_origin" {
  description = "Frontend origin for CORS (e.g. http://localhost:3000 or CloudFront URL)"
  type        = string
  default     = "*"
}

variable "lambda_memory_mb" {
  description = "Default Lambda memory in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Default Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "max_upload_size_bytes" {
  description = "Maximum file upload size in bytes (50MB)"
  type        = number
  default     = 52428800
}

variable "cloudtrail_retention_days" {
  description = "CloudTrail log retention in days (7 years = 2555)"
  type        = number
  default     = 2555
}
