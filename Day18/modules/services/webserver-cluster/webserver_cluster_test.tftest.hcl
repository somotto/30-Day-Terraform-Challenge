variables {
  cluster_name        = "test-cluster"
  instance_type       = "t2.micro"
  min_size            = 1
  max_size            = 2
  environment         = "dev"
  app_version         = "v1-test"
  cpu_alarm_threshold = 90
  log_retention_days  = 7
}

# run "validate_cluster_name"
#
# The ASG name includes a random_id suffix — unknown at plan time.
# We assert on the launch template name_prefix instead, which IS static.
# This still catches regressions in the naming convention without needing apply.
run "validate_cluster_name" {
  command = plan

  assert {
    condition     = aws_launch_template.example.name_prefix == "test-cluster-lt-"
    error_message = "Launch template name_prefix must be '<cluster_name>-lt-'. Got: ${aws_launch_template.example.name_prefix}"
  }

  assert {
    condition     = aws_iam_role.instance.name == "test-cluster-instance-role"
    error_message = "IAM role name must be '<cluster_name>-instance-role'. Got: ${aws_iam_role.instance.name}"
  }

  assert {
    condition     = aws_iam_instance_profile.instance.name == "test-cluster-instance-profile"
    error_message = "Instance profile name must be '<cluster_name>-instance-profile'. Got: ${aws_iam_instance_profile.instance.name}"
  }
}

# run "validate_instance_type"

# instance_type flows through local.effective_instance_type into the launch
# template. A wrong default would silently deploy the wrong instance size.
run "validate_instance_type" {
  command = plan

  assert {
    condition     = aws_launch_template.example.instance_type == "t2.micro"
    error_message = "Launch template instance_type must match the instance_type variable. Got: ${aws_launch_template.example.instance_type}"
  }
}

# run "validate_server_port"

# The target group port and the security group ingress rule must both equal
# server_port. A mismatch causes ALB health checks to fail silently.
run "validate_server_port" {
  command = plan

  assert {
    condition     = aws_lb_target_group.asg.port == 8080
    error_message = "Target group port must equal server_port (8080). Got: ${aws_lb_target_group.asg.port}"
  }

  assert {
    condition     = aws_security_group_rule.web_in_from_alb.from_port == 8080
    error_message = "Security group ingress from_port must equal server_port (8080). Got: ${aws_security_group_rule.web_in_from_alb.from_port}"
  }

  assert {
    condition     = aws_security_group_rule.web_in_from_alb.to_port == 8080
    error_message = "Security group ingress to_port must equal server_port (8080). Got: ${aws_security_group_rule.web_in_from_alb.to_port}"
  }
}

# run "validate_asg_sizing"

# min_size = 0 lets the cluster scale to zero. max_size < min_size prevents
# any instance from launching. Both are silent production killers.
run "validate_asg_sizing" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.example.min_size == 1
    error_message = "ASG min_size must match the min_size variable (1). Got: ${aws_autoscaling_group.example.min_size}"
  }

  assert {
    condition     = aws_autoscaling_group.example.max_size == 2
    error_message = "ASG max_size must match the max_size variable (2). Got: ${aws_autoscaling_group.example.max_size}"
  }

  assert {
    condition     = aws_autoscaling_group.example.min_elb_capacity == 1
    error_message = "min_elb_capacity must equal min_size so apply waits for healthy instances. Got: ${aws_autoscaling_group.example.min_elb_capacity}"
  }
}

# run "validate_environment_tag"

# Assert tags on the ALB — its tags are fully static (no computed values).
# The ASG name tag is computed (contains random_id), so we skip that here.
run "validate_environment_tag" {
  command = plan

  assert {
    condition     = aws_lb.example.tags["Environment"] == "dev"
    error_message = "ALB must carry the Environment tag matching the environment variable. Got: ${aws_lb.example.tags["Environment"]}"
  }

  assert {
    condition     = aws_lb.example.tags["Cluster"] == "test-cluster"
    error_message = "ALB must carry the Cluster tag matching cluster_name. Got: ${aws_lb.example.tags["Cluster"]}"
  }

  assert {
    condition     = aws_lb.example.tags["ManagedBy"] == "terraform"
    error_message = "ALB must carry ManagedBy = terraform tag. Got: ${aws_lb.example.tags["ManagedBy"]}"
  }
}

# run "validate_log_retention"

# CloudWatch log retention defaults to "never expire" if not set.
# Asserting here ensures we never accidentally deploy an unbounded log group.
run "validate_log_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 7
    error_message = "Log group retention must match log_retention_days (7). Got: ${aws_cloudwatch_log_group.app.retention_in_days}"
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.name == "/aws/ec2/test-cluster"
    error_message = "Log group name must be '/aws/ec2/<cluster_name>'. Got: ${aws_cloudwatch_log_group.app.name}"
  }
}

# run "validate_alb_listener"

# The ALB listener must be port 80 HTTP with a forward action.
# Wrong port or action type drops all traffic at the load balancer.
run "validate_alb_listener" {
  command = plan

  assert {
    condition     = aws_lb_listener.http.port == 80
    error_message = "ALB listener must be on port 80. Got: ${aws_lb_listener.http.port}"
  }

  assert {
    condition     = aws_lb_listener.http.protocol == "HTTP"
    error_message = "ALB listener protocol must be HTTP. Got: ${aws_lb_listener.http.protocol}"
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "forward"
    error_message = "ALB listener default action must be 'forward'. Got: ${aws_lb_listener.http.default_action[0].type}"
  }
}

# run "validate_cpu_alarm"

# Threshold of 0 means the alarm is always firing.
# Threshold of 100 means it never fires. Both make it useless.
# evaluation_periods = 1 causes flapping on brief CPU spikes.
run "validate_cpu_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.threshold == 90
    error_message = "CPU alarm threshold must match cpu_alarm_threshold (90). Got: ${aws_cloudwatch_metric_alarm.high_cpu.threshold}"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.evaluation_periods == 2
    error_message = "CPU alarm must evaluate over 2 periods to avoid flapping. Got: ${aws_cloudwatch_metric_alarm.high_cpu.evaluation_periods}"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.metric_name == "CPUUtilization"
    error_message = "CPU alarm must monitor CPUUtilization metric. Got: ${aws_cloudwatch_metric_alarm.high_cpu.metric_name}"
  }
}
