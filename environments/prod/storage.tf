# =============================================================================
# S3 Static Website Bucket (Private + Secured via CloudFront OAC)
# =============================================================================

resource "aws_s3_bucket" "website" {
  bucket = var.website_bucket_name

  tags = merge(local.common_tags, {
    Name    = "CloudResumeChallenge Website"
    Purpose = "Static Website Hosting"
  })
}

# Block ALL public access - security requirement
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Bucket policy will be attached after CloudFront distribution is created
# (see cdn.tf for the policy that allows the specific CloudFront distribution)
