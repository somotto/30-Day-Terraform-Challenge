output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The domain name of the load balancer — use this to reach the cluster"
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "The name of the Auto Scaling Group"
}

output "alb_arn" {
  value       = aws_lb.example.arn
  description = "ARN of the Application Load Balancer"
}

output "target_group_arn" {
  value       = aws_lb_target_group.web_tg.arn
  description = "ARN of the ALB target group — useful for attaching additional scaling policies"
}

output "web_sg_id" {
  value       = aws_security_group.web_sg.id
  description = "ID of the instance security group — useful if a caller needs to add extra rules"
}
