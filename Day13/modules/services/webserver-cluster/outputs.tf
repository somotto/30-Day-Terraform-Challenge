output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "ASG name (includes random_id suffix)"
}

output "instance_role_name" {
  value       = aws_iam_role.instance.name
  description = "IAM role name attached to instances — attach additional policies here"
}

output "instance_profile_name" {
  value       = aws_iam_instance_profile.instance.name
  description = "IAM instance profile name"
}
