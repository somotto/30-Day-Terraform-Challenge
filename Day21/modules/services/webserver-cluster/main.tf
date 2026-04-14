locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project_name
      Owner       = var.team_name
      Cluster     = var.cluster_name
      AppVersion  = var.app_version
    },
    var.custom_tags
  )
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "defaultForAz"
    values = ["true"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_iam_role" "instance" {
  name = "${var.cluster_name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-instance-role" })
}

resource "aws_iam_role_policy_attachment" "secret_policies" {
  for_each   = { for idx, arn in var.secret_policy_arns : tostring(idx) => arn }
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "cloudwatch_metrics" {
  name = "${var.cluster_name}-cloudwatch-metrics"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "ec2:DescribeTags"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.cluster_name}-instance-profile"
  role = aws_iam_role.instance.name
}


resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.cluster_name}-alb-sg-"
  description = "ALB: allow HTTP inbound from internet, all outbound"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.common_tags, { Name = "${var.cluster_name}-alb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_http_in" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP from internet to ALB"
}

resource "aws_security_group_rule" "alb_out" {
  type              = "egress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound from ALB"
}

resource "aws_security_group" "web_sg" {
  name_prefix = "${var.cluster_name}-web-sg-"
  description = "Instances: allow traffic only from ALB"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.common_tags, { Name = "${var.cluster_name}-web-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "web_in_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.web_sg.id
  from_port                = var.server_port
  to_port                  = var.server_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "Allow traffic only from ALB"
}

resource "aws_security_group_rule" "web_out" {
  type              = "egress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound from instances"
}

resource "aws_lb" "example" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
  tags               = merge(local.common_tags, { Name = "${var.cluster_name}-alb" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_lb_target_group" "asg" {
  name     = "${var.cluster_name}-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-tg" })
}

resource "random_id" "server" {
  keepers = {
    ami_id      = var.ami != "" ? var.ami : data.aws_ami.amazon_linux.id
    app_version = var.app_version
  }
  byte_length = 4
}

resource "aws_launch_template" "example" {
  name_prefix   = "${var.cluster_name}-lt-"
  image_id      = var.ami != "" ? var.ami : data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port   = var.server_port
    cluster_name  = var.cluster_name
    environment   = var.environment
    app_version   = var.app_version
    secret_source = var.secret_source
    secret_ref    = var.secret_ref
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.cluster_name}-instance" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${var.cluster_name}-volume" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  name                      = "${var.cluster_name}-asg-${random_id.server.hex}"
  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.asg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120
  min_size                  = var.min_size
  max_size                  = var.max_size
  min_elb_capacity          = var.min_size
  force_delete              = true

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${var.cluster_name}"
  retention_in_days = var.log_retention_days
  tags              = merge(local.common_tags, { Name = "${var.cluster_name}-logs" })
}

resource "aws_sns_topic" "alerts" {
  name = "${var.cluster_name}-alerts"
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-alerts" })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.cluster_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "CPU > ${var.cpu_alarm_threshold}% for 4 min on ${var.cluster_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-high-cpu-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.cluster_name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Any unhealthy target in ${var.cluster_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.example.arn_suffix
    TargetGroup  = aws_lb_target_group.asg.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-unhealthy-hosts-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.cluster_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5xx > 10/min on ${var.cluster_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.example.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-alb-5xx-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "high_request_count" {
  alarm_name          = "${var.cluster_name}-high-request-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.request_count_alarm_threshold
  alarm_description   = "ALB request count > ${var.request_count_alarm_threshold}/min on ${var.cluster_name} — possible traffic spike or DDoS"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.example.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-high-request-count-alarm" })
}
