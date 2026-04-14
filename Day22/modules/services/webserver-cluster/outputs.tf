output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "DNS name of the Application Load Balancer."
}

output "alb_arn" {
  value       = aws_lb.example.arn
  description = "ARN of the Application Load Balancer."
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "Auto Scaling Group name (includes random suffix for zero-downtime replacement)."
}

output "instance_role_name" {
  value       = aws_iam_role.instance.name
  description = "IAM role name attached to instances."
}

output "instance_profile_name" {
  value       = aws_iam_instance_profile.instance.name
  description = "IAM instance profile name."
}

output "sns_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "SNS topic ARN for CloudWatch alarm notifications."
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.app.name
  description = "CloudWatch log group name for application logs."
}

output "web_sg_id" {
  value       = aws_security_group.web_sg.id
  description = "Security group ID attached to EC2 instances."
}

output "alb_sg_id" {
  value       = aws_security_group.alb_sg.id
  description = "Security group ID attached to the ALB."
}

output "high_cpu_alarm_arn" {
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
  description = "ARN of the high-CPU CloudWatch alarm."
}

output "unhealthy_hosts_alarm_arn" {
  value       = aws_cloudwatch_metric_alarm.unhealthy_hosts.arn
  description = "ARN of the unhealthy-hosts CloudWatch alarm."
}

output "alb_5xx_alarm_arn" {
  value       = aws_cloudwatch_metric_alarm.alb_5xx.arn
  description = "ARN of the ALB 5xx CloudWatch alarm."
}

output "request_count_alarm_arn" {
  value       = aws_cloudwatch_metric_alarm.high_request_count.arn
  description = "ARN of the high request-count CloudWatch alarm."
}
