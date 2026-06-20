# =============================================================================
# Production Environment Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the website"
  value       = aws_s3_bucket.website.id
}

output "s3_bucket_arn" {
  description = "ARN of the website S3 bucket"
  value       = aws_s3_bucket.website.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID (use for cache invalidation from CI/CD)"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name - use this as your website URL for now"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "cloudfront_arn" {
  description = "Full ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.arn
}

output "cloudfront_oac_id" {
  description = "Origin Access Control ID (useful for debugging)"
  value       = aws_cloudfront_origin_access_control.website.id
}

output "frontend_deploy_instructions" {
  description = "Quick reference for your frontend CI pipeline"
  value       = <<-EOT
    After deploying the frontend build:

    aws s3 sync ./dist s3://${aws_s3_bucket.website.id} --delete
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website.id} --paths "/*"
  EOT
}

# =============================================================================
# Custom Domain Outputs (only populated when domain_name is set)
# =============================================================================

output "custom_domain_name" {
  description = "Your primary custom domain (if configured)"
  value       = var.domain_name != "" ? var.domain_name : null
}

output "website_url" {
  description = "Final URL of your website (custom domain if configured, otherwise CloudFront)"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "acm_certificate_arn" {
  description = "ACM Certificate ARN (use this if you need it for other services later)"
  value = var.domain_name != "" ? (
    local.manage_route53_records ? aws_acm_certificate_validation.website[0].certificate_arn : aws_acm_certificate.website[0].arn
  ) : null
}

output "route53_zone_id" {
  description = "Route 53 Hosted Zone ID (useful for adding more records manually)"
  value       = var.domain_name != "" ? local.route53_zone_id : null
}

output "nameservers" {
  description = "Route 53 nameservers for your domain. Point your registrar to these to complete the move to Route 53."
  value       = var.create_route53_zone ? aws_route53_zone.main[0].name_servers : null
}

# =============================================================================
# Visitor Counter Outputs
# =============================================================================

output "visitor_api_url" {
  description = "Public URL for the visitor counter API (set as VISITOR_API_URL in frontend repo)."
  value       = var.enable_visitor_counter ? "${aws_apigatewayv2_api.visitor_counter[0].api_endpoint}/visitors" : null
}

output "visitor_counter_table_name" {
  description = "DynamoDB table storing visitor counts."
  value       = var.enable_visitor_counter ? aws_dynamodb_table.visitor_counter[0].name : null
}

output "visitor_counter_function_name" {
  description = "Lambda function that increments the visitor counter."
  value       = var.enable_visitor_counter ? aws_lambda_function.visitor_counter[0].function_name : null
}
