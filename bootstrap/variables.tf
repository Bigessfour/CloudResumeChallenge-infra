variable "aws_region" {
  description = "AWS region for bootstrap resources (us-east-1 recommended for global services)"
  type        = string
  default     = "us-east-1"
}

variable "tfstate_bucket_name" {
  description = "Globally unique name for the Terraform state S3 bucket (include account id or random suffix)"
  type        = string

  validation {
    condition     = length(var.tfstate_bucket_name) > 3 && length(var.tfstate_bucket_name) < 63
    error_message = "Bucket name must be between 4 and 62 characters."
  }
}

variable "tfstate_lock_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "cloudresume-tf-locks"
}

variable "github_role_name" {
  description = "Name of the IAM role that GitHub Actions will assume via OIDC"
  type        = string
  default     = "github-actions-cloudresume-terraform"
}

variable "website_bucket_name" {
  description = "The S3 bucket name you plan to use for the website (used to scope IAM permissions)"
  type        = string
}

variable "create_oidc_provider" {
  description = "Set to true to create the GitHub OIDC provider (set to false if it already exists in the account)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project    = "CloudResumeChallenge"
    ManagedBy  = "Terraform"
    Repository = "CloudResumeChallenge-infra"
  }
}
