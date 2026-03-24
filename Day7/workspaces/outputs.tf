output "instance_id" {
  description = "ID of the EC2 instance in this workspace"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "workspace" {
  description = "Current Terraform workspace"
  value       = terraform.workspace
}

output "instance_type_used" {
  description = "Instance type deployed in this workspace"
  value       = aws_instance.web.instance_type
}
