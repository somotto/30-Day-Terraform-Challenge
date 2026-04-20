output "asg_name" {
  value       = aws_autoscaling_group.web.name
  description = "Name of the Auto Scaling Group"
}

output "asg_arn" {
  value       = aws_autoscaling_group.web.arn
  description = "ARN of the Auto Scaling Group"
}

output "scale_out_policy_arn" {
  value       = aws_autoscaling_policy.scale_out.arn
  description = "ARN of the CPU scale-out policy"
}

output "scale_in_policy_arn" {
  value       = aws_autoscaling_policy.scale_in.arn
  description = "ARN of the CPU scale-in policy"
}

output "cloudwatch_dashboard_name" {
  value       = aws_cloudwatch_dashboard.web.dashboard_name
  description = "Name of the CloudWatch dashboard for this ASG"
}
