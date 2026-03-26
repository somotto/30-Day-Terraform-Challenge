output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "Name of the Auto Scaling Group"
}

output "instance_type_used" {
  value       = local.instance_type
  description = "EC2 instance type selected by the environment conditional"
}

output "scale_out_policy_arn" {
  value       = local.enable_autoscaling ? aws_autoscaling_policy.scale_out[0].arn : null
  description = "Scale-out policy ARN. null when autoscaling is disabled."
}

output "scale_in_policy_arn" {
  value       = local.enable_autoscaling ? aws_autoscaling_policy.scale_in[0].arn : null
  description = "Scale-in policy ARN. null when autoscaling is disabled."
}

output "high_cpu_alert_arn" {
  value       = local.enable_monitoring ? aws_cloudwatch_metric_alarm.high_cpu_alert[0].arn : null
  description = "High-CPU alert alarm ARN. null when detailed monitoring is disabled."
}
