provider "aws" {
  region = "us-east-1"
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name  = "webservers-production"
  instance_type = "t3.micro"
  min_size      = 4
  max_size      = 10
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "Hit this URL to reach the production cluster"
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "Production ASG name"
}
