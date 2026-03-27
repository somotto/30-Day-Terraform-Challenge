output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "asg_name" {
  value       = var.enable_blue_green ? null : aws_autoscaling_group.example[0].name
  description = "Rolling-update ASG name. null when blue/green is enabled."
}

output "launch_template_name" {
  value       = var.enable_blue_green ? null : aws_launch_template.example.name
  description = "Rolling-update Launch Template name. null when blue/green is enabled."
}

output "active_target_group_arn" {
  value = (
    var.enable_blue_green
    ? (var.active_environment == "blue"
      ? aws_lb_target_group.blue[0].arn
      : aws_lb_target_group.green[0].arn)
    : aws_lb_target_group.asg.arn
  )
  description = "ARN of the currently active target group"
}

output "blue_target_group_arn" {
  value       = var.enable_blue_green ? aws_lb_target_group.blue[0].arn : null
  description = "Blue target group ARN. null when blue/green is disabled."
}

output "green_target_group_arn" {
  value       = var.enable_blue_green ? aws_lb_target_group.green[0].arn : null
  description = "Green target group ARN. null when blue/green is disabled."
}

output "blue_asg_name" {
  value       = var.enable_blue_green ? aws_autoscaling_group.blue[0].name : null
  description = "Blue ASG name. null when blue/green is disabled."
}

output "green_asg_name" {
  value       = var.enable_blue_green ? aws_autoscaling_group.green[0].name : null
  description = "Green ASG name. null when blue/green is disabled."
}
