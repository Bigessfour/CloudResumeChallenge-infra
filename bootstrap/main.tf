# =============================================================================
# BOOTSTRAP - One-time infrastructure for Terraform remote state + GitHub OIDC
# =============================================================================
# Run this directory with local AWS credentials (aws configure or environment).
# After this succeeds, all future Terraform operations (including this repo's
# GitHub Actions) will use the remote S3 backend and OIDC role.
# =============================================================================

# ------------------------------------------------------------------------------
# Terraform State S3 Bucket
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = var.tfstate_bucket_name

  tags = merge(var.tags, {
    Name    = "Terraform State Bucket"
    Purpose = "Remote Terraform State"
  })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ------------------------------------------------------------------------------
# DynamoDB Table for State Locking
# ------------------------------------------------------------------------------
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.tfstate_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "Terraform State Lock Table"
  })
}

# ------------------------------------------------------------------------------
# GitHub OIDC Identity Provider (idempotent - safe to run multiple times)
# ------------------------------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # GitHub's current OIDC thumbprints (as of 2025/2026)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = merge(var.tags, {
    Name = "GitHub OIDC Provider"
  })
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ------------------------------------------------------------------------------
# IAM Role for GitHub Actions (assumable via OIDC from both repos)
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Allow both repos on main branch only (AWS OIDC best practice)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:Bigessfour/CloudResumeChallenge-infra:ref:refs/heads/main",
        "repo:Bigessfour/CloudResumeChallenge-frontend:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.github_role_name
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json

  tags = merge(var.tags, {
    Name = "GitHub Actions CloudResume Deployer"
  })
}

# ------------------------------------------------------------------------------
# IAM Policy A — Terraform state plane (small, ~1 KB)
# Split out from the main service policy because IAM customer-managed policy
# documents are capped at 6144 bytes each and the combined doc exceeded that.
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "github_state_policy" {
  statement {
    sid    = "TerraformStateBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid    = "TerraformStateObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }

  statement {
    sid    = "TerraformStateLocking"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }

  statement {
    sid    = "ReadAccountInfo"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }
}

# ------------------------------------------------------------------------------
# IAM Policy B — AWS service plane (larger, all production resources)
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "github_policy" {
  # Website S3 bucket — full control bounded to the single bucket ARN.
  # Action wildcard is safe because resources are scoped to one bucket name.
  statement {
    sid     = "WebsiteBucket"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.website_bucket_name}",
      "arn:aws:s3:::${var.website_bucket_name}/*",
    ]
  }

  # CloudFront — distributions, OAC, response headers policies, functions,
  # invalidations, and tags. Global resource so we keep tight action wildcards.
  statement {
    sid    = "CloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:*Distribution*",
      "cloudfront:*Invalidation*",
      "cloudfront:*OriginAccessControl*",
      "cloudfront:*ResponseHeadersPolic*",
      "cloudfront:*Function*",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # ACM (us-east-1 cert for CloudFront)
  statement {
    sid    = "ACM"
    effect = "Allow"
    actions = [
      "acm:*Certificate*",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:ListTagsForCertificate",
    ]
    resources = ["*"]
  }

  # Route 53 DNS records (only used when zone is in AWS; harmless otherwise)
  statement {
    sid    = "Route53"
    effect = "Allow"
    actions = [
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:GetChange",
    ]
    resources = ["*"]
  }

  # DynamoDB — bounded to cloudresume-* tables
  statement {
    sid       = "DynamoDB"
    effect    = "Allow"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:*:*:table/cloudresume-*"]
  }

  # Lambda — bounded to cloudresume-* functions
  statement {
    sid       = "Lambda"
    effect    = "Allow"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:*:*:function:cloudresume-*"]
  }

  # IAM PassRole — only Lambda execution roles
  statement {
    sid       = "LambdaPassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::*:role/cloudresume-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  # IAM role lifecycle — bounded to cloudresume-* roles
  statement {
    sid       = "LambdaExecutionRoles"
    effect    = "Allow"
    actions   = ["iam:*Role*"]
    resources = ["arn:aws:iam::*:role/cloudresume-*"]
  }

  # API Gateway HTTP API
  statement {
    sid       = "APIGateway"
    effect    = "Allow"
    actions   = ["apigateway:*"]
    resources = ["*"]
  }

  # CloudWatch Logs — scoped writes on Lambda log groups
  statement {
    sid       = "LogsScoped"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/cloudresume-*:*"]
  }

  # DescribeLogGroups must use "*" per AWS contract
  statement {
    sid       = "LogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # IAM Access Analyzer (free-tier security monitoring)
  statement {
    sid    = "AccessAnalyzer"
    effect = "Allow"
    actions = [
      "accessanalyzer:*Analyzer*",
      "accessanalyzer:TagResource",
      "accessanalyzer:UntagResource",
    ]
    resources = ["*"]
  }

  # AWS Budgets (cost alerts)
  statement {
    sid       = "Budgets"
    effect    = "Allow"
    actions   = ["budgets:*Budget*"]
    resources = ["*"]
  }

  # CloudWatch Alarms (abuse/cost guards)
  statement {
    sid    = "CloudWatchAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_actions" {
  name   = "${var.github_role_name}-policy"
  policy = data.aws_iam_policy_document.github_policy.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

# Second policy holds Terraform state plane perms (see comment on
# data.aws_iam_policy_document.github_state_policy for why we split).
resource "aws_iam_policy" "github_actions_state" {
  name   = "${var.github_role_name}-state-policy"
  policy = data.aws_iam_policy_document.github_state_policy.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_state" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_state.arn
}
