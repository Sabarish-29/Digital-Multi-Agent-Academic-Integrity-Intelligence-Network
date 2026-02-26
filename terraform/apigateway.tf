# ============================================================================
# Amazon API Gateway - REST API
# ============================================================================

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "DMAIIN REST API for academic integrity analysis"

  binary_media_types = [
    "multipart/form-data",
    "*/*",
  ]

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.environment
  }
}

# ============================================================================
# Cognito Authorizer
# ============================================================================

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.project_name}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"

  provider_arns = [
    aws_cognito_user_pool.main.arn,
  ]
}

# ============================================================================
# Resources
# ============================================================================

# /submissions
resource "aws_api_gateway_resource" "submissions" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "submissions"
}

# /submissions/upload
resource "aws_api_gateway_resource" "submissions_upload" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.submissions.id
  path_part   = "upload"
}

# /submissions/{id}
resource "aws_api_gateway_resource" "submissions_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.submissions.id
  path_part   = "{id}"
}

# /submissions/{id}/status
resource "aws_api_gateway_resource" "submissions_id_status" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.submissions_id.id
  path_part   = "status"
}

# ============================================================================
# POST /submissions/upload -> intake-handler Lambda
# ============================================================================

resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submissions_upload.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "upload_post" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.submissions_upload.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.intake_handler.invoke_arn
}

# ============================================================================
# OPTIONS /submissions/upload (CORS preflight)
# ============================================================================

resource "aws_api_gateway_method" "upload_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submissions_upload.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "upload_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "upload_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = aws_api_gateway_method_response.upload_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.frontend_origin}'"
  }
}

# ============================================================================
# GET /submissions/{id} -> get-submission-metadata Lambda
# ============================================================================

resource "aws_api_gateway_method" "submissions_id_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submissions_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "submissions_id_get" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.submissions_id.id
  http_method             = aws_api_gateway_method.submissions_id_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.get_submission_metadata.invoke_arn
}

# ============================================================================
# OPTIONS /submissions/{id} (CORS preflight)
# ============================================================================

resource "aws_api_gateway_method" "submissions_id_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submissions_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "submissions_id_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_id.id
  http_method = aws_api_gateway_method.submissions_id_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "submissions_id_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_id.id
  http_method = aws_api_gateway_method.submissions_id_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "submissions_id_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_id.id
  http_method = aws_api_gateway_method.submissions_id_options.http_method
  status_code = aws_api_gateway_method_response.submissions_id_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.frontend_origin}'"
  }
}

# ============================================================================
# GET /submissions/{id}/status -> get-submission-status Lambda
# ============================================================================

resource "aws_api_gateway_method" "submissions_id_status_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submissions_id_status.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "submissions_id_status_get" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.submissions_id_status.id
  http_method             = aws_api_gateway_method.submissions_id_status_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.get_submission_status.invoke_arn
}

# ============================================================================
# OPTIONS /submissions/{id}/status (CORS preflight)
# ============================================================================

resource "aws_api_gateway_method" "submissions_id_status_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submissions_id_status.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "submissions_id_status_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_id_status.id
  http_method = aws_api_gateway_method.submissions_id_status_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "submissions_id_status_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_id_status.id
  http_method = aws_api_gateway_method.submissions_id_status_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "submissions_id_status_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submissions_id_status.id
  http_method = aws_api_gateway_method.submissions_id_status_options.http_method
  status_code = aws_api_gateway_method_response.submissions_id_status_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.frontend_origin}'"
  }
}

# ============================================================================
# Deployment & Stage
# ============================================================================

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.submissions,
      aws_api_gateway_resource.submissions_upload,
      aws_api_gateway_resource.submissions_id,
      aws_api_gateway_resource.submissions_id_status,
      aws_api_gateway_method.upload_post,
      aws_api_gateway_integration.upload_post,
      aws_api_gateway_method.upload_options,
      aws_api_gateway_integration.upload_options,
      aws_api_gateway_method.submissions_id_get,
      aws_api_gateway_integration.submissions_id_get,
      aws_api_gateway_method.submissions_id_options,
      aws_api_gateway_integration.submissions_id_options,
      aws_api_gateway_method.submissions_id_status_get,
      aws_api_gateway_integration.submissions_id_status_get,
      aws_api_gateway_method.submissions_id_status_options,
      aws_api_gateway_integration.submissions_id_status_options,
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.upload_post,
    aws_api_gateway_integration.upload_options,
    aws_api_gateway_integration.submissions_id_get,
    aws_api_gateway_integration.submissions_id_options,
    aws_api_gateway_integration.submissions_id_status_get,
    aws_api_gateway_integration.submissions_id_status_options,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.project_name}-api-prod"
    Environment = var.environment
  }
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    metrics_enabled    = true
    data_trace_enabled = true
  }
}

# ============================================================================
# CloudWatch Log Group for API Gateway Access Logs
# ============================================================================

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "${var.project_name}-api-access-logs"
  retention_in_days = 90

  tags = {
    Name        = "${var.project_name}-api-access-logs"
    Environment = var.environment
  }
}

# ============================================================================
# Lambda Permissions for API Gateway Invocation
# ============================================================================

resource "aws_lambda_permission" "apigw_intake_handler" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.intake_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_submission_metadata" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_submission_metadata.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_submission_status" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_submission_status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
