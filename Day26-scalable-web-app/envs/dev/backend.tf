terraform {
  backend "s3" {
    bucket  = "tfstate-day26-scalable-web-app-eveops"
    key     = "day26/scalable-web-app/dev/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
