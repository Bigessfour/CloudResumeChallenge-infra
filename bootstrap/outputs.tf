output "tfstate_bucket" {
  description = "S3 bucket name for Terraform remote state"
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.tfstate.arn
}

output "tfstate_lock_table" {
  description = "DynamoDB table name used for Terraform state locking"
  value       = aws_dynamodb_table.tf_lock.name
}

output "github_actions_role_arn" {
  description = "IAM Role ARN that GitHub Actions assumes via OIDC (use this in workflows and frontend repo)"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC Identity Provider"
  value       = local.oidc_provider_arn
}

output "next_steps" {
  description = "What to do after bootstrap completes"
  value       = <<-EOT
    1. Copy the github_actions_role_arn value above into GitHub repo variables as AWS_ROLE_ARN
    2. Go to environments/prod/
    3. Copy terraform.tfvars.example → terraform.tfvars and fill in values
    4. Update the S3 backend block in environments/prod/providers.tf with the tfstate_bucket and tfstate_lock_table values
    5. Run: cd environments/prod && terraform init && terraform apply
  EOT
}
