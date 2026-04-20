output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "ALB DNS name — open this URL in your browser to verify the deployment"
}

output "asg_name" {
  value       = module.asg.asg_name
  description = "Name of the Auto Scaling Group"
}

output "launch_template_id" {
  value       = module.ec2.launch_template_id
  description = "EC2 Launch Template ID"
}

output "target_group_arn" {
  value       = module.alb.target_group_arn
  description = "ALB Target Group ARN"
}

output "scale_out_policy_arn" {
  value       = module.asg.scale_out_policy_arn
  description = "ARN of the CPU scale-out policy"
}

output "scale_in_policy_arn" {
  value       = module.asg.scale_in_policy_arn
  description = "ARN of the CPU scale-in policy"
}

output "cloudwatch_dashboard_name" {
  value       = module.asg.cloudwatch_dashboard_name
  description = "CloudWatch dashboard name for ASG metrics"
}
