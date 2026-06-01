# Bootstrap providers - run this with local AWS credentials (not OIDC)
# This is the only place you should use long-lived credentials during initial setup.

terraform {
  required_version = ">= 1.9"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
