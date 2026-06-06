# =============================================================================
# AWS Budgets — free cost/forecast alerts (notifications are free)
# =============================================================================
# Set budget_alert_email in terraform.tfvars (gitignored). Budget is skipped when empty.
# Budgets API is available in us-east-1; prod stack uses us-east-1 by default.
# =============================================================================

resource "aws_budgets_budget" "monthly_cost" {
  count = var.budget_alert_email != "" ? 1 : 0

  name         = "cloudresume-${var.environment}-monthly-cost"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"

  time_unit         = "MONTHLY"
  time_period_start = var.budget_time_period_start

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
