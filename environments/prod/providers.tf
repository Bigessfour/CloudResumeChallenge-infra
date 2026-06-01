# =============================================================================
# Production Environment - Providers + Remote Backend
# =============================================================================

terraform {
  required_version = ">= 1.9"

  # ----------------------------------------------------------------------------
  # REMOTE BACKEND - Replace values after running bootstrap
  # ----------------------------------------------------------------------------
  # After `terraform apply` in bootstrap/, copy the output values here.
  #
  # Example (replace with your real values):
  # backend "s3" {
  #   bucket         = "bigessfour-cloudresume-tfstate-123456789012"
  #   key            = "environments/prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "cloudresume-tf-locks"
  #   encrypt        = true
  # }
  # ----------------------------------------------------------------------------
  backend "s3" {
    bucket         = "cloudresume-tfstate-570912405222"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudresume-tf-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
