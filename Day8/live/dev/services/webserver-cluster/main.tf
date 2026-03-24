provider "aws" {
  region = "us-east-1"
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name  = "webservers-dev"
  instance_type = "t3.micro"
  min_size      = 2
  max_size      = 4
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "Hit this URL to reach the dev cluster"
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "Dev ASG name"
}
