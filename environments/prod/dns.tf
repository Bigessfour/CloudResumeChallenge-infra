# =============================================================================
# Custom Domain, ACM Certificate, and Route 53 Configuration
# =============================================================================
# This file is fully optional. Nothing here runs unless you set
# `domain_name` in your terraform.tfvars.
#
# For stephenmckitrick.com:
#   domain_name               = "stephenmckitrick.com"
#   subject_alternative_names = ["www.stephenmckitrick.com"]
# =============================================================================

locals {
  # All domains that need to be on the certificate
  certificate_domains = var.domain_name != "" ? concat([var.domain_name], var.subject_alternative_names) : []

  # Determine which Route 53 zone ID to use (only meaningful when using custom domain)
  route53_zone_id = var.domain_name != "" ? (
    var.create_route53_zone ? aws_route53_zone.main[0].zone_id : var.route53_zone_id
  ) : ""
}

# ------------------------------------------------------------------------------
# Route 53 Hosted Zone (only created if create_route53_zone = true)
# ------------------------------------------------------------------------------
resource "aws_route53_zone" "main" {
  count = var.create_route53_zone ? 1 : 0

  name = var.domain_name

  tags = merge(local.common_tags, {
    Name = "Hosted zone for ${var.domain_name}"
  })
}

# ------------------------------------------------------------------------------
# ACM Certificate (must be in us-east-1 for CloudFront)
# ------------------------------------------------------------------------------
resource "aws_acm_certificate" "website" {
  count = var.domain_name != "" ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "CloudResumeChallenge Certificate - ${var.domain_name}"
  })
}

# ------------------------------------------------------------------------------
# DNS Validation Records for ACM Certificate
# ------------------------------------------------------------------------------
resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" ? {
    for dvo in aws_acm_certificate.website[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.route53_zone_id
}

# ------------------------------------------------------------------------------
# Wait for ACM Certificate to be validated
# ------------------------------------------------------------------------------
resource "aws_acm_certificate_validation" "website" {
  count = var.domain_name != "" ? 1 : 0

  certificate_arn         = aws_acm_certificate.website[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

# ------------------------------------------------------------------------------
# Route 53 Alias Records - Apex domain (stephenmckitrick.com)
# ------------------------------------------------------------------------------
resource "aws_route53_record" "apex" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = local.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_acm_certificate_validation.website]
}

# IPv6 record for apex
resource "aws_route53_record" "apex_ipv6" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = local.route53_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_acm_certificate_validation.website]
}

# ------------------------------------------------------------------------------
# Route 53 Alias Records - www subdomain (www.stephenmckitrick.com)
# ------------------------------------------------------------------------------
resource "aws_route53_record" "www" {
  count = var.domain_name != "" && contains(var.subject_alternative_names, "www.${var.domain_name}") ? 1 : 0

  zone_id = local.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_acm_certificate_validation.website]
}

resource "aws_route53_record" "www_ipv6" {
  count = var.domain_name != "" && contains(var.subject_alternative_names, "www.${var.domain_name}") ? 1 : 0

  zone_id = local.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_acm_certificate_validation.website]
}

# ------------------------------------------------------------------------------
# Optional: TXT record for domain ownership verification (useful for Google, etc.)
# ------------------------------------------------------------------------------
resource "aws_route53_record" "root_txt" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = local.route53_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = [
    "v=spf1 -all", # Recommended: declare no email sending from this domain
  ]
}
