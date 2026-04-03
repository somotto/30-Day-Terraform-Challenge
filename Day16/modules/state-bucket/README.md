# state-bucket module

Creates an S3 bucket and DynamoDB table for Terraform remote state with locking.
Both resources have `prevent_destroy = true`.

## Usage

```hcl
module "state_bucket" {
  source = "../../modules/state-bucket"

  bucket_name         = "my-org-terraform-state"
  dynamodb_table_name = "terraform-state-lock"
  environment         = "production"
  project_name        = "my-project"
  team_name           = "platform-team"
}
```

Then reference the outputs in your backend blocks:

```hcl
terraform {
  backend "s3" {
    bucket         = "<state_bucket_name output>"
    key            = "production/services/webserver-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "<dynamodb_table_name output>"
    encrypt        = true
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `bucket_name` | `string` | required | Globally unique S3 bucket name. |
| `dynamodb_table_name` | `string` | `"terraform-state-lock"` | DynamoDB table name. |
| `environment` | `string` | required | `dev`, `staging`, or `production`. |
| `project_name` | `string` | `"terraform-challenge"` | Applied to all resource tags. |
| `team_name` | `string` | `"platform-team"` | Applied to all resource tags. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | S3 bucket name for backend config. |
| `bucket_arn` | S3 bucket ARN. |
| `dynamodb_table_name` | DynamoDB table name for backend config. |
