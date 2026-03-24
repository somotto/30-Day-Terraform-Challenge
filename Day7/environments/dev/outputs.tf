output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP of the web instance"
  value       = aws_instance.web.public_ip
}

output "subnet_id" {
  description = "Subnet the instance was deployed into — consumed by app layer via remote state"
  value       = tolist(data.aws_subnets.default.ids)[0]
}

output "vpc_id" {
  description = "VPC ID — consumed by app layer via remote state"
  value       = data.aws_vpc.default.id
}
