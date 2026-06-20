# CloudResumeChallenge-infra

Production-ready Terraform infrastructure for the **Cloud Resume Challenge** (AWS Free Tier).

This repo manages the AWS resources for hosting a static resume website using S3 + CloudFront with Origin Access Control (OAC) for maximum security.

## Architecture (Current)

- **S3 bucket** (private, no public access) — stores the static website files
- **CloudFront distribution** with Origin Access Control (OAC) — serves content securely over HTTPS
- **Terraform remote state** in S3 with DynamoDB locking (created in bootstrap)
- **GitHub Actions OIDC** — zero long-lived AWS credentials
- **Visitor counter** — API Gateway HTTP API + Lambda + DynamoDB
- **Custom domain** — ACM certificate, Route 53 records, www → apex redirect

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for diagrams, CI/CD, and runbooks.

### Optional future extensions

- WAF
- Multi-environment (staging)

## Repository Structure

```
CloudResumeChallenge-infra/
├── bootstrap/                  # One-time setup (run locally)
│   ├── main.tf                 # State bucket, DynamoDB lock, GitHub OIDC role
│   ├── providers.tf
│   └── outputs.tf
├── environments/prod/          # Production website infrastructure
│   ├── main.tf
│   ├── storage.tf              # S3 static website bucket + security
│   ├── cdn.tf                  # CloudFront + OAC
│   ├── visitor_counter.tf      # API Gateway + Lambda + DynamoDB
│   ├── dns.tf                  # ACM + Route 53
│   ├── providers.tf            # Backend + AWS provider
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── .github/workflows/
│   ├── terraform-plan.yml      # Runs on PRs
│   └── terraform-apply.yml     # Runs on merge to main (via OIDC)
├── versions.tf
├── .gitignore
└── README.md
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.9
- AWS CLI v2
- An AWS account (Free Tier eligible)
- GitHub repository (this one + your frontend repo)

## Step-by-Step Setup

### 1. Bootstrap the Terraform Backend & IAM Role (One Time)

The bootstrap creates:
- S3 bucket for Terraform state
- DynamoDB table for state locking
- GitHub OIDC Identity Provider
- IAM Role that GitHub Actions can assume (no secrets needed)

```bash
cd bootstrap

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

**Important**: After `apply`, copy the outputs (especially `github_actions_role_arn`, `tfstate_bucket`, and `tfstate_lock_table`). You will need them in the next step.

### 2. Configure the Production Environment

```bash
cd environments/prod

# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars:
# - Set website_bucket_name (must be globally unique!)
# - Set aws_region (us-east-1 recommended for CloudFront)
# - Update tags if desired
```

Edit `providers.tf` and replace the backend configuration with the values from bootstrap:

```hcl
terraform {
  backend "s3" {
    bucket         = "YOUR_TFSTATE_BUCKET_NAME"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "YOUR_LOCK_TABLE_NAME"
    encrypt        = true
  }
}
```

### 3. Deploy the Website Infrastructure

```bash
cd environments/prod

terraform init
terraform plan
terraform apply
```

After successful apply, note the outputs:
- `cloudfront_domain_name` — this is the URL of your website
- `s3_bucket_name` — your website bucket
- `cloudfront_distribution_id` — needed for cache invalidations

### 4. Connect Your Frontend Repository

Your frontend repo (https://github.com/Bigessfour/CloudResumeChallenge-frontend) should:

1. Build the static site (HTML/CSS/JS + Syncfusion)
2. Sync the built files to the S3 bucket created above
3. Invalidate the CloudFront distribution

Example GitHub Actions step in your frontend repo (after adding the same OIDC role):

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::YOUR_ACCOUNT:role/github-actions-cloudresume-terraform
    aws-region: us-east-1

- name: Sync to S3
  run: aws s3 sync ./dist s3://YOUR_WEBSITE_BUCKET_NAME --delete

- name: Invalidate CloudFront
  run: aws cloudfront create-invalidation --distribution-id YOUR_DISTRIBUTION_ID --paths "/*"
```

Update your frontend workflow to use the values from the Terraform outputs.

### 5. GitHub Actions OIDC Configuration (This Repo)

After bootstrap, add the following **Repository Variables** in GitHub:

Go to: `Settings → Secrets and variables → Actions → Variables`

| Variable Name     | Value                                      |
|-------------------|--------------------------------------------|
| `AWS_ROLE_ARN`    | (from bootstrap output)                    |
| `AWS_REGION`      | `us-east-1` (or your region)               |

The workflows already reference these variables.

### 6. Test the Full Pipeline

1. Make a small change to any Terraform file
2. Open a Pull Request → `terraform-plan.yml` runs automatically
3. Merge to `main` → `terraform-apply.yml` runs and updates infrastructure

## Common Commands

```bash
# Bootstrap (first time only)
cd bootstrap && terraform init && terraform apply

# Production changes
cd environments/prod
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply

# Destroy everything (careful!)
terraform destroy
```

## Security Features

- S3 bucket has **all public access blocked**
- CloudFront uses **Origin Access Control (OAC)** — no public S3 bucket policy
- All traffic forced to HTTPS
- Security headers via CloudFront managed policy
- GitHub Actions uses **OIDC federation** (no IAM user keys)
- Least-privilege IAM role created for deployments
- State is encrypted at rest in S3

## Free Tier Considerations

All resources in this starter are Free Tier eligible:
- S3 Standard storage (first 5 GB)
- CloudFront (1 TB transfer + 10M requests/month free)
- DynamoDB (25 GB + 25 WCUs/RCUs free)
- No NAT Gateways, Load Balancers, or WAF

## Setting Up Your Custom Domain (stephenmckitrick.com)

This starter fully supports attaching a real domain using **Route 53 + ACM + CloudFront aliases**.

### Step 1: Decide How to Move Your Domain

You have two main options:

**Option A – Recommended (Easiest & Cheapest)**
- Keep the domain registered at your current registrar (Namecheap, GoDaddy, Google, etc.)
- Create a hosted zone in Route 53 (Terraform can do this)
- Copy the 4 nameservers Route 53 gives you
- Change the nameservers **at your current registrar** to the Route 53 ones
- This usually takes 15 minutes to 48 hours to propagate

**Option B – Full Transfer**
- Transfer the domain registration itself into Route 53
- More expensive and slower (can take days)
- Only do this if you specifically want Route 53 as registrar

### Step 2: Configure Terraform for Your Domain

Edit `environments/prod/terraform.tfvars`:

```hcl
domain_name               = "stephenmckitrick.com"
subject_alternative_names = ["www.stephenmckitrick.com"]

# First time only - let Terraform create the hosted zone
create_route53_zone = true

enable_www_redirect = true   # www → apex redirect at the edge (recommended)
```

### Step 3: Apply the DNS Changes

```bash
cd environments/prod
terraform plan
terraform apply
```

After apply you will get important outputs:

- `nameservers` — the 4 Route 53 nameservers you must set at your registrar
- `website_url` — `https://stephenmckitrick.com`
- `acm_certificate_arn`

### Step 4: Point Your Registrar to Route 53 Nameservers

At your current domain registrar:

1. Find the "Nameservers" or "DNS" section for `stephenmckitrick.com`
2. **Replace** the existing nameservers with the 4 values from the Terraform `nameservers` output
3. Save changes

**Do NOT** add Route 53 records as a "DNS provider" while keeping the old nameservers — that will not work.

Wait for propagation (use `dig stephenmckitrick.com NS` or whatsmy dns.net).

### Step 5: ACM Certificate Validation

Terraform will automatically create the required CNAME records in Route 53 for ACM validation. The `terraform apply` will wait up to 30 minutes for the certificate to validate.

Once complete, CloudFront will be updated to use your real domain with a proper certificate.

### Important Notes

- The first time you enable a custom domain, CloudFront will take 5–20 minutes to deploy the new configuration.
- After the domain is working, you can set `create_route53_zone = false` and put the zone ID in `route53_zone_id` for future applies.
- The www → apex redirect is handled by a **CloudFront Function** (free, runs at the edge, no Lambda@Edge cost).

## Extending for the Full Cloud Resume Challenge

The folder structure is designed for easy extension:

1. Add `database.tf` in `environments/prod/` for the DynamoDB visitor counter table
2. Add `compute.tf` for the Lambda function + API Gateway
3. Add `api.tf` or combine into one file
4. Update the IAM policy in bootstrap if the Lambda needs extra permissions
5. Add custom domain + ACM in a new `dns.tf`

## Troubleshooting

**"Bucket name already exists"**  
S3 bucket names are global. Change `website_bucket_name` to something more unique.

**GitHub Actions fails with "AccessDenied"**

- Make sure `AWS_ROLE_ARN` repository variable is set correctly
- The role trust policy may need a few minutes to propagate after creation
- The IAM policy attached to the OIDC role lives in `bootstrap/main.tf`. **The CI
  workflow does NOT apply `bootstrap/`** (chicken-and-egg: bootstrap creates the
  role the workflow uses). When `terraform apply` reports new `AccessDenied`
  errors, edit `bootstrap/main.tf`, commit, then run `terraform apply` inside
  `bootstrap/` locally with your own AWS credentials so the policy update lands.

**Domain still at previous registrar (Porkbun, Namecheap, etc.)**

- The Route 53 records in `environments/prod/dns.tf` only deploy when a hosted
  zone is available (`create_route53_zone = true` or `route53_zone_id` set).
- When DNS is still at the original registrar (e.g. during the 60-day ICANN
  registrar-transfer lock), leave both unset — `local.manage_route53_records`
  resolves to `false` and every Route 53 record short-circuits with `count = 0`.
- The ACM certificate stays in state and the CloudFront distribution keeps
  using it; validation CNAMEs must be added manually at the current registrar
  if the cert ever needs to be re-issued.
- After the registrar lock expires, change nameservers, set
  `create_route53_zone = true`, and re-apply.

**CloudFront shows old content**  
Run an invalidation:
```bash
aws cloudfront create-invalidation --distribution-id <ID> --paths "/*"
```

**Terraform wants to destroy the S3 bucket on every apply**  
Never manually delete objects outside of Terraform. Use `lifecycle { prevent_destroy = true }` on the bucket if needed.

## License

MIT — see [LICENSE](LICENSE) file.

---

**Next milestone**: Add the Lambda + API Gateway + DynamoDB visitor counter.

Happy building! 🚀
