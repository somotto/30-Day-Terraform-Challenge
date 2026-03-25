output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "DNS name of the Application Load Balancer"
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
  description = "ARN of the ALB target group"
}

output "alb_sg_id" {
  value       = aws_security_group.alb_sg.id
  description = "ID of the ALB security group"
}

output "web_sg_id" {
  value       = aws_security_group.web_sg.id
  description = "ID of the instance security group"
}

# for expression output: map of policy name → ARN (only populated when autoscaling is enabled)
output "autoscaling_policy_arns" {
  description = "Map of autoscaling policy name to ARN. Empty when enable_autoscaling = false."
  value = {
    for policy in concat(
      aws_autoscaling_policy.scale_out,
      aws_autoscaling_policy.scale_in
    ) : policy.name => policy.arn
  }
}

output "instance_type_used" {
  description = "The EC2 instance type selected (reflects conditional logic)"
  value       = local.instance_type
}
