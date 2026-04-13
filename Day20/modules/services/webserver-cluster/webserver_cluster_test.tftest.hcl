variables {
  cluster_name        = "test-cluster"
  instance_type       = "t3.micro"
  min_size            = 1
  max_size            = 2
  environment         = "dev"
  app_version         = "v3"
  cpu_alarm_threshold = 80
  log_retention_days  = 7
}

run "validate_cluster_name" {
  command = plan

  assert {
    condition     = startswith(aws_launch_template.example.name_prefix, "test-cluster-lt-")
    error_message = "Launch template name_prefix must start with '<cluster_name>-lt-'"
  }

  assert {
    condition     = startswith(aws_security_group.web_sg.name_prefix, "test-cluster-web-sg-")
    error_message = "Web SG name_prefix must start with '<cluster_name>-web-sg-'"
  }
}

run "validate_instance_type" {
  command = plan

  assert {
    condition     = aws_launch_template.example.instance_type == var.instance_type
    error_message = "Launch template instance_type must match var.instance_type"
  }
}

run "validate_server_port" {
  command = plan

  assert {
    condition     = aws_lb_target_group.asg.port == var.server_port
    error_message = "Target group port must match var.server_port"
  }
}

run "validate_asg_sizing" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.example.min_size == var.min_size
    error_message = "ASG min_size must match var.min_size"
  }

  assert {
    condition     = aws_autoscaling_group.example.max_size == var.max_size
    error_message = "ASG max_size must match var.max_size"
  }

  assert {
    condition     = aws_autoscaling_group.example.min_elb_capacity == var.min_size
    error_message = "min_elb_capacity must equal min_size for zero-downtime deploys"
  }
}

run "validate_environment_tag" {
  command = plan

  assert {
    condition     = aws_lb.example.tags["Environment"] == var.environment
    error_message = "ALB must carry the Environment tag matching var.environment"
  }
}

run "validate_log_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == var.log_retention_days
    error_message = "Log group retention must match var.log_retention_days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.name == "/aws/ec2/${var.cluster_name}"
    error_message = "Log group name must follow /aws/ec2/<cluster_name> convention"
  }
}

run "validate_alb_listener" {
  command = plan

  assert {
    condition     = aws_lb_listener.http.port == 80
    error_message = "ALB listener must be on port 80"
  }

  assert {
    condition     = aws_lb_listener.http.protocol == "HTTP"
    error_message = "ALB listener protocol must be HTTP"
  }
}

run "validate_cpu_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.threshold == var.cpu_alarm_threshold
    error_message = "CPU alarm threshold must match var.cpu_alarm_threshold"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.evaluation_periods == 2
    error_message = "CPU alarm evaluation_periods must be 2 to avoid flapping"
  }
}

run "validate_app_version_v3" {
  command = plan

  assert {
    condition     = var.app_version == "v3"
    error_message = "Day 20 module default app_version must be v3"
  }
}
