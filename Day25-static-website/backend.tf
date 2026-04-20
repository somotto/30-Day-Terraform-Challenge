# terraform {
#   backend "s3" {
#     bucket         = "day25-s7a73-buck3t"
#     key            = "day25/static-website/<env>/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-state-locks"
#     encrypt        = true
#   }
# }
