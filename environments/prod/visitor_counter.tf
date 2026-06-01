# =============================================================================
# Serverless Visitor Counter — API Gateway + Lambda + DynamoDB
# =============================================================================

locals {
  visitor_counter_enabled = var.enable_visitor_counter

  visitor_cors_origins = local.visitor_counter_enabled ? compact([
    var.domain_name != "" ? "https://${var.domain_name}" : null,
    var.domain_name != "" && contains(var.subject_alternative_names, "www.${var.domain_name}") ? "https://www.${var.domain_name}" : null,
    "https://${aws_cloudfront_distribution.website.domain_name}",
    "http://127.0.0.1:8000",
    "http://localhost:8000",
  ]) : []
}

# ------------------------------------------------------------------------------
# DynamoDB — atomic counter storage
# ------------------------------------------------------------------------------
resource "aws_dynamodb_table" "visitor_counter" {
  count = local.visitor_counter_enabled ? 1 : 0

  name         = var.visitor_counter_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name    = "CloudResumeChallenge Visitor Counter"
    Purpose = "Visitor count storage"
  })
}

# ------------------------------------------------------------------------------
# Lambda — increment counter on each GET
# ------------------------------------------------------------------------------
data "archive_file" "visitor_counter" {
  count = local.visitor_counter_enabled ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/../../lambda/visitor_counter/handler.py"
  output_path = "${path.module}/../../lambda/visitor_counter/handler.zip"
}

resource "aws_iam_role" "visitor_counter_lambda" {
  count = local.visitor_counter_enabled ? 1 : 0

  name = "${var.visitor_counter_function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "visitor_counter_lambda_basic" {
  count = local.visitor_counter_enabled ? 1 : 0

  role       = aws_iam_role.visitor_counter_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "visitor_counter_lambda" {
  count = local.visitor_counter_enabled ? 1 : 0

  statement {
    sid    = "DynamoDBUpdateCounter"
    effect = "Allow"
    actions = [
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
    ]
    resources = [aws_dynamodb_table.visitor_counter[0].arn]
  }
}

resource "aws_iam_role_policy" "visitor_counter_lambda" {
  count = local.visitor_counter_enabled ? 1 : 0

  name   = "${var.visitor_counter_function_name}-dynamodb"
  role   = aws_iam_role.visitor_counter_lambda[0].id
  policy = data.aws_iam_policy_document.visitor_counter_lambda[0].json
}

resource "aws_lambda_function" "visitor_counter" {
  count = local.visitor_counter_enabled ? 1 : 0

  function_name = var.visitor_counter_function_name
  role          = aws_iam_role.visitor_counter_lambda[0].arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.visitor_counter[0].output_path
  source_code_hash = data.archive_file.visitor_counter[0].output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.visitor_counter[0].name
      COUNTER_KEY = "visitor-counter"
    }
  }

  tags = merge(local.common_tags, {
    Name = "CloudResumeChallenge Visitor Counter"
  })
}

resource "aws_cloudwatch_log_group" "visitor_counter" {
  count = local.visitor_counter_enabled ? 1 : 0

  name              = "/aws/lambda/${var.visitor_counter_function_name}"
  retention_in_days = 14

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# HTTP API (API Gateway v2)
# ------------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "visitor_counter" {
  count = local.visitor_counter_enabled ? 1 : 0

  name          = "${var.environment}-cloudresume-visitor-api"
  protocol_type = "HTTP"
  description   = "Cloud Resume Challenge visitor counter API"

  cors_configuration {
    allow_origins = local.visitor_cors_origins
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "visitor_counter" {
  count = local.visitor_counter_enabled ? 1 : 0

  api_id                 = aws_apigatewayv2_api.visitor_counter[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "visitor_counter_get" {
  count = local.visitor_counter_enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.visitor_counter[0].id
  route_key = "GET /visitors"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_counter[0].id}"
}

resource "aws_apigatewayv2_route" "visitor_counter_options" {
  count = local.visitor_counter_enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.visitor_counter[0].id
  route_key = "OPTIONS /visitors"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_counter[0].id}"
}

resource "aws_apigatewayv2_stage" "visitor_counter" {
  count = local.visitor_counter_enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.visitor_counter[0].id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 25
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "visitor_counter_api" {
  count = local.visitor_counter_enabled ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_counter[0].execution_arn}/*/*"
}
