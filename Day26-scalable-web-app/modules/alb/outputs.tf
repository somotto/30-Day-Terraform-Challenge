output "alb_dns_name" {
  value       = aws_lb.web.dns_name
  description = "DNS name of the Application Load Balancer — use this URL to access your application"
}

output "target_group_arn" {
  value       = aws_lb_target_group.web.arn
  description = "ARN of the ALB target group, consumed by the ASG module"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "Security group ID of the ALB"
}