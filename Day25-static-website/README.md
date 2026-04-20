# Day 25 — Deploy a Static Website on AWS S3 with Terraform

Deploy a globally distributed static website using S3 + CloudFront, fully managed by Terraform with modular code, remote state, and environment isolation.

## Project Structure

```
Day25-static-website/
├── modules/
│   └── s3-static-website/
│       ├── main.tf        # S3 bucket, website config, public access, CloudFront, HTML objects
│       ├── variables.tf   # All module inputs
│       └── outputs.tf     # Bucket name, S3 endpoint, CloudFront domain
├── envs/
│   └── dev/
│       ├── main.tf        # Module call with dev-specific values
│       ├── variables.tf   # Input declarations for the dev root
│       ├── outputs.tf     # Passes module outputs up to the CLI
│       ├── terraform.tfvars  # Actual values (bucket name, env, etc.)
│       └── provider.tf    # AWS provider + S3 remote backend
├── backend.tf             # Reference template for backend config
├── provider.tf            # Reference template for provider config
└── .gitignore
```

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured (`aws configure`)
- An existing S3 bucket for remote state (e.g. `Day25-s7a73-buck3t`)
- An existing DynamoDB table for state locking (`terraform-state-locks`)

## Deploy

```bash
cd Day25-static-website/envs/dev

terraform init
terraform validate
terraform plan
terraform apply
```

After apply, get your CloudFront URL:

```bash
terraform output cloudfront_domain_name
```

Open the URL in your browser. CloudFront takes 5–15 minutes to propagate globally on first deploy.

## Clean Up

```bash
terraform destroy
```

The S3 bucket has `force_destroy = true` in dev/staging so Terraform can delete it even with objects inside.

## Key Design Decisions

- **Module** — all S3 + CloudFront logic lives in `modules/s3-static-website`. The `envs/dev` caller stays clean, just passing variables.
- **Remote state** — S3 backend with DynamoDB locking prevents concurrent apply conflicts.
- **force_destroy** — enabled for non-production environments so `terraform destroy` works cleanly.
- **PriceClass_100** — CloudFront uses only US/EU/Asia edge locations, keeping Free Tier costs minimal.
- **price_class** — `PriceClass_100` is the cheapest CloudFront option, suitable for Free Tier.
- **No hardcoded values** — bucket name, environment, and document names all flow through variables.
