output "launch_template_id" {
  value       = aws_launch_template.web.id
  description = "ID of the Launch Template"
}

output "launch_template_version" {
  value       = aws_launch_template.web.latest_version
  description = "Latest version of the Launch Template"
}

output "security_group_id" {
  value       = aws_security_group.instance.id
  description = "Security group ID attached to EC2 instances"
}