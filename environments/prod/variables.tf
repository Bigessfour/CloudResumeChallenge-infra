variable "aws_region" {
  description = "AWS region to deploy resources into (us-east-1 is best for CloudFront + Free Tier)"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (used for tagging and naming)"
  type        = string
  default     = "prod"
}

variable "website_bucket_name" {
  description = "Globally unique S3 bucket name for the static website. Must be available."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.website_bucket_name))
    error_message = "Bucket name must be a valid S3 bucket name (lowercase, 3-63 chars)."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_100 = cheapest (US + Europe)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Must be one of PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "tags" {
  description = "Additional tags to merge with common tags"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Custom Domain + Route 53 + ACM Variables
# =============================================================================

variable "domain_name" {
  description = "Primary custom domain name for the site (e.g. stephenmckitrick.com). Leave empty to use only the default CloudFront domain."
  type        = string
  default     = ""
}

variable "subject_alternative_names" {
  description = "Additional domain names for the certificate (e.g. [\"www.stephenmckitrick.com\"]). Usually includes www version of your domain."
  type        = list(string)
  default     = []
}

variable "create_route53_zone" {
  description = "Whether Terraform should create the Route 53 hosted zone. Set to false if you already manage the zone or created it manually."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Existing Route 53 Hosted Zone ID (use this if create_route53_zone = false and you already have the zone)."
  type        = string
  default     = ""
}

variable "enable_www_redirect" {
  description = "Create a CloudFront Function that redirects www.example.com → example.com (recommended)."
  type        = bool
  default     = true
}

# =============================================================================
# Visitor Counter (API Gateway + Lambda + DynamoDB)
# =============================================================================

variable "enable_visitor_counter" {
  description = "Deploy the serverless visitor counter API (Cloud Resume Challenge requirement)."
  type        = bool
  default     = true
}

variable "visitor_counter_table_name" {
  description = "DynamoDB table name for visitor counts."
  type        = string
  default     = "cloudresume-visitor-counts"
}

variable "visitor_counter_function_name" {
  description = "Lambda function name for the visitor counter."
  type        = string
  default     = "cloudresume-visitor-counter"
}

# =============================================================================
# Security monitoring (free tier)
# =============================================================================

variable "budget_alert_email" {
  description = "Email for AWS Budgets cost alerts. Leave empty to skip budget creation. Never commit — set in terraform.tfvars only."
  type        = string
  default     = ""
  sensitive   = true
}

variable "budget_limit_usd" {
  description = "Monthly AWS cost budget limit in USD for alert notifications."
  type        = string
  default     = "10"
}

variable "budget_time_period_start" {
  description = "Budget start time in YYYY-MM-DD_HH:MM format (UTC). Use the first day of the month when enabling budgets."
  type        = string
  default     = "2026-06-01_00:00"
}

variable "lambda_invocation_alarm_threshold" {
  description = "Daily Lambda invocation count that triggers a CloudWatch abuse alarm."
  type        = number
  default     = 5000
}
