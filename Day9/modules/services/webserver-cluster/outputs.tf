# Granular outputs — callers reference specific attributes rather than
# depending on the whole module (Gotcha 3 fix).

output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The DNS name of the ALB — use this to reach the cluster"
}

output "alb_arn" {
  value       = aws_lb.example.arn
  description = "ARN of the Application Load Balancer"
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "Name of the Auto Scaling Group"
}

output "target_group_arn" {
  value       = aws_lb_target_group.web_tg.arn
  description = "ARN of the ALB target group — useful for attaching scaling policies"
}

output "alb_sg_id" {
  value       = aws_security_group.alb_sg.id
  description = "ID of the ALB security group — callers can attach extra rules to this"
}

output "web_sg_id" {
  value       = aws_security_group.web_sg.id
  description = "ID of the instance security group — callers can attach extra rules to this"
}
