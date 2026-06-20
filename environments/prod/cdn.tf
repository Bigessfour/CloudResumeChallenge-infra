# =============================================================================
# CloudFront Distribution with Origin Access Control (OAC)
# =============================================================================
# This is the modern secure pattern:
# - S3 bucket has zero public access
# - CloudFront uses OAC to privately fetch objects from S3
# - All traffic is HTTPS only
# =============================================================================

# Origin Access Control - preferred over legacy Origin Access Identity (OAI)
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.website_bucket_name}-oac"
  description                       = "OAC for CloudResumeChallenge S3 website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Response Headers Policy for security best practices
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name    = "${var.environment}-security-headers"
  comment = "Security headers for CloudResumeChallenge"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000 # 1 year
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }
}

# =============================================================================
# Optional: CloudFront Function for www → apex redirect (edge redirect, very cheap)
# =============================================================================
resource "aws_cloudfront_function" "www_redirect" {
  count = var.enable_www_redirect && var.domain_name != "" ? 1 : 0

  name    = "${replace(var.domain_name, ".", "-")}-www-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect www.${var.domain_name} to ${var.domain_name}"
  publish = true

  code = <<-EOT
function handler(event) {
  var request = event.request;
  var host = request.headers.host.value.toLowerCase();

  if (host.startsWith('www.')) {
    var newHost = host.substring(4);
    var location = 'https://' + newHost + request.uri;

    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: {
        'location': { value: location },
        'cache-control': { value: 'max-age=3600' }
      }
    };
  }

  return request;
}
EOT
}

# Main CloudFront Distribution
resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudResumeChallenge static website - ${var.environment}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  web_acl_id          = null # Add WAF ARN here later if desired (costs money)

  # Use custom domain(s) when provided
  aliases = var.domain_name != "" ? concat([var.domain_name], var.subject_alternative_names) : []

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
    origin_id                = "s3-website"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-website"

    # Use AWS managed optimized cache policy (recommended)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized

    # Attach security headers
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    # Attach www redirect function when enabled
    dynamic "function_association" {
      for_each = var.enable_www_redirect && var.domain_name != "" ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.www_redirect[0].arn
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # Custom error responses for SPA-style routing and friendly 404s
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # When using a custom domain we must use the validated ACM cert.
  # When not using a custom domain we use the default CloudFront certificate.
  # Prefer the explicit validation resource (proves DNS validation completed),
  # but fall back to the cert resource directly when Route 53 isn't managing the
  # zone (e.g. domain currently at Porkbun) — the cert is still ISSUED, it was
  # validated externally.
  dynamic "viewer_certificate" {
    for_each = var.domain_name != "" ? [1] : []
    content {
      acm_certificate_arn      = local.manage_route53_records ? aws_acm_certificate_validation.website[0].certificate_arn : aws_acm_certificate.website[0].arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.domain_name == "" ? [1] : []
    content {
      cloudfront_default_certificate = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "CloudResumeChallenge CloudFront"
  })
}

# ------------------------------------------------------------------------------
# S3 Bucket Policy - Allow ONLY this CloudFront distribution
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "website_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website.arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.website.arn,
      "${aws_s3_bucket.website.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.website_bucket_policy.json

  # Ensure OAC is created before the policy
  depends_on = [aws_cloudfront_origin_access_control.website]
}
