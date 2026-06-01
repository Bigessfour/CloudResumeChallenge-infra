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

# Future extension points — visitor counter lives in visitor_counter.tf
