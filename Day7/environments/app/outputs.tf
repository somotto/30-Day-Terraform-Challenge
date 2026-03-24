output "app_instance_id" {
  description = "App layer EC2 instance ID"
  value       = aws_instance.app.id
}

output "app_public_ip" {
  description = "Public IP of the app instance"
  value       = aws_instance.app.public_ip
}

# Surfacing the values we consumed from remote state — useful for debugging
output "network_vpc_id" {
  description = "VPC ID read from network layer remote state"
  value       = data.terraform_remote_state.network.outputs.vpc_id
}

output "network_subnet_id" {
  description = "Subnet ID read from network layer remote state"
  value       = data.terraform_remote_state.network.outputs.subnet_id
}
