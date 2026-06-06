# =============================================================================
# Production Environment - Main Configuration
# =============================================================================

locals {
  common_tags = merge(
    {
      Project     = "CloudResumeChallenge"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "CloudResumeChallenge-infra"
    },
    var.tags
  )
}

# Visitor counter resources: visitor_counter.tf
# Security monitoring: security.tf, budgets.tf
