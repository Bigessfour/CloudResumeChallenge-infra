# =============================================================================
# Free-tier security monitoring (AWS documentation–aligned)
# =============================================================================
# - IAM Access Analyzer (external access) — no additional charge
# - CloudWatch alarms on standard Lambda metrics — within free tier allowance
# =============================================================================

resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = "cloudresume-external-access"
  type          = "ACCOUNT"

  tags = merge(local.common_tags, {
    Name    = "CloudResume External Access Analyzer"
    Purpose = "Detect unintended public or cross-account resource access"
  })
}

resource "aws_cloudwatch_metric_alarm" "visitor_counter_errors" {
  count = local.visitor_counter_enabled ? 1 : 0

  alarm_name          = "${var.visitor_counter_function_name}-errors"
  alarm_description   = "Visitor counter Lambda reported one or more errors in 5 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.visitor_counter[0].function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "visitor_counter_invocations_high" {
  count = local.visitor_counter_enabled ? 1 : 0

  alarm_name          = "${var.visitor_counter_function_name}-high-invocations"
  alarm_description   = "Visitor counter Lambda daily invocations exceeded expected traffic — possible abuse."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = 86400
  statistic           = "Sum"
  threshold           = var.lambda_invocation_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.visitor_counter[0].function_name
  }

  tags = local.common_tags
}
