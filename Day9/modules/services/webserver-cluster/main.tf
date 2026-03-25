# webserver-cluster module (v0.0.2)
#
# Packages an ALB + ASG + Launch Template into a reusable component.
# All resource names are prefixed with var.cluster_name so the module
# can be instantiated multiple times in the same AWS account without
# name collisions.
#
# Gotcha fixes applied in this version:
#   1. File paths  — user-data.sh is referenced via path.module, not a bare
#      relative path, so it resolves correctly regardless of where Terraform
#      is invoked from.
#   2. Inline blocks — security group rules are defined as standalone
#      aws_security_group_rule resources instead of inline ingress/egress
#      blocks. This lets callers add extra rules without touching the module.
#   3. Granular outputs — individual resource attributes are exported so
#      callers never need a depends_on on the whole module.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Data sources

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

# Security Groups — shells only, rules are separate resources (Gotcha 2 fix)

resource "aws_security_group" "alb_sg" {
  name        = "${var.cluster_name}-alb-sg"
  description = "ALB security group for ${var.cluster_name}"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    { Name = "${var.cluster_name}-alb-sg", Cluster = var.cluster_name },
    var.custom_tags
  )
}

# Separate rule resources — callers can add more rules without modifying the module
resource "aws_security_group_rule" "alb_inbound_http" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  description       = "HTTP from internet"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
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

  tags = merge(
    { Name = "${var.cluster_name}-web-sg", Cluster = var.cluster_name },
    var.custom_tags
  )
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

# Launch Template
# path.module resolves relative to the module directory, not the caller (Gotcha 1 fix)

resource "aws_launch_template" "web_lt" {
  name_prefix            = "${var.cluster_name}-lt-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port  = var.server_port
    cluster_name = var.cluster_name
    environment  = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      { Name = "${var.cluster_name}-instance", Cluster = var.cluster_name },
      var.custom_tags
    )
  }
}

# Application Load Balancer

resource "aws_lb" "example" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = merge(
    { Name = "${var.cluster_name}-alb", Cluster = var.cluster_name },
    var.custom_tags
  )
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

  tags = merge(
    { Cluster = var.cluster_name },
    var.custom_tags
  )
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

# Auto Scaling Group

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

  tag {
    key                 = "Cluster"
    value               = var.cluster_name
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.custom_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
