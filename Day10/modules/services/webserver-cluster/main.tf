terraform {
  required_version = ">= 1.0"
}

locals {
  instance_type = var.instance_type != null ? var.instance_type : (
    var.environment == "production" ? "t3.small" : "t3.micro"
  )

  base_tags = merge(
    {
      Cluster     = var.cluster_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Day         = "10"
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
    name   = "availabilityZone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
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


resource "aws_security_group" "alb_sg" {
  name        = "${var.cluster_name}-alb-sg"
  description = "ALB security group for ${var.cluster_name}"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.base_tags, { Name = "${var.cluster_name}-alb-sg" })
}

resource "aws_security_group_rule" "alb_inbound_http" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  description       = "HTTP from internet"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_extra_ingress" {
  for_each          = var.extra_alb_ingress_rules
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  description       = "Extra rule: ${each.key}"
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
}

resource "aws_security_group_rule" "alb_outbound_all" {
  type              = "egress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "web_sg" {
  name        = "${var.cluster_name}-web-sg"
  description = "Instance security group for ${var.cluster_name}"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.base_tags, { Name = "${var.cluster_name}-web-sg" })
}

resource "aws_security_group_rule" "web_inbound_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.web_sg.id
  description              = "HTTP from ALB only"
  from_port                = var.server_port
  to_port                  = var.server_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group_rule" "web_outbound_all" {
  type              = "egress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Launch Template — uses local.instance_type (conditional logic centralised)

resource "aws_launch_template" "web_lt" {
  name_prefix            = "${var.cluster_name}-lt-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = local.instance_type   
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port  = var.server_port
    cluster_name = var.cluster_name
    environment  = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.base_tags, { Name = "${var.cluster_name}-instance" })
  }
}


resource "aws_lb" "example" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
  tags               = merge(local.base_tags, { Name = "${var.cluster_name}-alb" })
}

resource "aws_lb_target_group" "web_tg" {
  name     = "${var.cluster_name}-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.base_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}


resource "aws_autoscaling_group" "example" {
  name                = "${var.cluster_name}-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.min_size
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.web_tg.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-instance"
    propagate_at_launch = true
  }

  # for_each inside dynamic block — collapses repeated tag{} blocks into one
  dynamic "tag" {
    for_each = local.base_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}


resource "aws_autoscaling_policy" "scale_out" {
  count = var.enable_autoscaling ? 1 : 0

  name                   = "${var.cluster_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.example.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  count = var.enable_autoscaling ? 1 : 0

  name                   = "${var.cluster_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.example.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

# CloudWatch alarms only make sense when autoscaling is enabled
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = var.enable_autoscaling ? 1 : 0

  alarm_name          = "${var.cluster_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when average CPU > 70% for 4 minutes"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  count = var.enable_autoscaling ? 1 : 0

  alarm_name          = "${var.cluster_name}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in when average CPU < 30% for 4 minutes"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_in[0].arn]
}
