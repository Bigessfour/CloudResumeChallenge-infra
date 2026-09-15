# Visitor Counter — Reset & Bot Protection

Stephen McKitrick · [Live site](https://stephenmckitrick.com) · [Infra repo](https://github.com/Bigessfour/CloudResumeChallenge-infra)

## Overview

The visitor counter is a serverless stack:

`Browser (stephenmckitrick.com)` → `GET /visitors` → API Gateway HTTP API → Lambda → DynamoDB

The frontend expects JSON: `{"count": N}` (see `CloudResumeChallenge-frontend/js/app.js`).

## Bot protections (deployed with this stack)

| Layer | Control |
|-------|---------|
| **CORS** | Allowlist only: `https://stephenmckitrick.com`, `https://www.stephenmckitrick.com`, plus localhost dev origins. No `*`, no CloudFront default domain. |
| **API Gateway throttling** | Stage defaults: **2 req/s** steady, **5** burst (429 when exceeded). Tunable via `visitor_counter_throttle_rate` / `visitor_counter_throttle_burst` in `terraform.tfvars`. |
| **Lambda validation** | Rejects empty/bot User-Agents (curl, scrapers, HeadlessChrome / DevTools agents), missing allowlisted `Origin`/`Referer`, and requests without browser `Sec-Fetch-Site` / `Sec-Fetch-Mode`. Rejected calls return **403** and **do not increment**. |
| **OPTIONS preflight** | Still returns 200 and never increments. |
| **CloudWatch alarms** | Daily invocation threshold + error alarm (see `security.tf`). |
| **Reserved concurrency** | **Not set** — account quota is 10 unreserved minimum; see comment in `visitor_counter.tf`. |

WAF / Shield Advanced are intentionally not used (free-tier personal portfolio).

## Reset the counter (production)

Inflated counts from scrapers can be cleared to a baseline of **0**. The next legitimate visit from the portfolio page shows **1** (atomic `ADD` increment).

### Option A — Makefile + AWS CLI (recommended)

Use your own AWS credentials (profile, SSO, or exported session). **Do not commit keys.**

```bash
# From repo root — defaults match prod table name
make reset-visitor-counter

# Or override region / table / baseline
AWS_REGION=us-east-1 TABLE_NAME=cloudresume-visitor-counts RESET_HITS=0 make reset-visitor-counter
```

Equivalent script:

```bash
chmod +x scripts/reset-visitor-counter.sh   # once
AWS_REGION=us-east-1 ./scripts/reset-visitor-counter.sh --hits 0
```

Resolve table name from Terraform if needed:

```bash
cd environments/prod
terraform output -raw visitor_counter_table_name
```

### Option B — first deploy only

If the table is empty, the first legitimate `GET /visitors` from the site creates the item via `UpdateItem ADD`. Do not seed the live item from Terraform — a create-if-missing PutItem fails when the row already exists.

## Verify after deploy

1. Merge infra PR → GitHub Actions applies Lambda + API changes.
2. Reset counter (Option A) if scrapers inflated the count.
3. Open [https://stephenmckitrick.com](https://stephenmckitrick.com) — pill should show live count (not demo fallback).
4. Direct curl without browser headers should **not** increment:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$(cd environments/prod && terraform output -raw visitor_api_url)"
# Expect 403
```

## Local development

- Frontend local origins: `http://127.0.0.1:8000`, `http://localhost:8000` (in `visitor_counter_local_dev_origins`).
- Run Lambda tests: `make test-visitor-counter`
