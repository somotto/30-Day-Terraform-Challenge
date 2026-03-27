terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  is_production           = var.environment == "production"
  effective_instance_type = local.is_production ? "t3.small" : "t3.micro"

  base_tags = merge(
    {
      Cluster     = var.cluster_name
      Environment = var.environment
      ManagedBy   = "terraform"
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

resource "random_id" "server" {
  keepers = {
    ami_id      = var.ami != "" ? var.ami : data.aws_ami.amazon_linux.id
    app_version = var.app_version
  }
  byte_length = 4
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.cluster_name}-alb-sg"
  description = "ALB security group"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.base_tags, { Name = "${var.cluster_name}-alb-sg" })
}

resource "aws_security_group_rule" "alb_http_in" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_out" {
  type              = "egress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "web_sg" {
  name        = "${var.cluster_name}-web-sg"
  description = "Instance security group"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.base_tags, { Name = "${var.cluster_name}-web-sg" })
}

resource "aws_security_group_rule" "web_in_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.web_sg.id
  from_port                = var.server_port
  to_port                  = var.server_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group_rule" "web_out" {
  type              = "egress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_lb" "example" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
  tags               = merge(local.base_tags, { Name = "${var.cluster_name}-alb" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  # Default action: forward to the standard TG (rolling-update path).
  # In blue/green mode the listener rule at priority 100 overrides this.
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

  tags = local.base_tags
}

resource "aws_launch_template" "example" {
  name_prefix            = "${var.cluster_name}-lt-"
  image_id               = var.ami != "" ? var.ami : data.aws_ami.amazon_linux.id
  instance_type          = local.effective_instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port  = var.server_port
    cluster_name = var.cluster_name
    environment  = var.environment
    app_version  = var.app_version
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.base_tags, { Name = "${var.cluster_name}-instance" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  count                     = var.enable_blue_green ? 0 : 1
  name                      = "${var.cluster_name}-${random_id.server.hex}"
  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.asg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120
  min_size                  = var.min_size
  max_size                  = var.max_size
  min_elb_capacity          = var.min_size

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
    for_each = local.base_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_lb_target_group" "blue" {
  count    = var.enable_blue_green ? 1 : 0
  name     = "${var.cluster_name}-blue-tg"
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

  tags = merge(local.base_tags, { Slot = "blue" })
}

resource "aws_lb_target_group" "green" {
  count    = var.enable_blue_green ? 1 : 0
  name     = "${var.cluster_name}-green-tg"
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

  tags = merge(local.base_tags, { Slot = "green" })
}

resource "aws_launch_template" "blue" {
  count                  = var.enable_blue_green ? 1 : 0
  name_prefix            = "${var.cluster_name}-blue-lt-"
  image_id               = var.ami != "" ? var.ami : data.aws_ami.amazon_linux.id
  instance_type          = local.effective_instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port  = var.server_port
    cluster_name = var.cluster_name
    environment  = var.environment
    app_version  = var.blue_app_version
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.base_tags, { Name = "${var.cluster_name}-blue", Slot = "blue" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "green" {
  count                  = var.enable_blue_green ? 1 : 0
  name_prefix            = "${var.cluster_name}-green-lt-"
  image_id               = var.ami != "" ? var.ami : data.aws_ami.amazon_linux.id
  instance_type          = local.effective_instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port  = var.server_port
    cluster_name = var.cluster_name
    environment  = var.environment
    app_version  = var.green_app_version
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.base_tags, { Name = "${var.cluster_name}-green", Slot = "green" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "blue" {
  count                     = var.enable_blue_green ? 1 : 0
  name                      = "${var.cluster_name}-blue-asg"
  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.blue[0].arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120
  min_size                  = var.min_size
  max_size                  = var.max_size

  launch_template {
    id      = aws_launch_template.blue[0].id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-blue"
    propagate_at_launch = true
  }

  tag {
    key                 = "Slot"
    value               = "blue"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.base_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_group" "green" {
  count                     = var.enable_blue_green ? 1 : 0
  name                      = "${var.cluster_name}-green-asg"
  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.green[0].arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120
  min_size                  = var.min_size
  max_size                  = var.max_size

  launch_template {
    id      = aws_launch_template.green[0].id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-green"
    propagate_at_launch = true
  }

  tag {
    key                 = "Slot"
    value               = "green"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.base_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}


resource "aws_lb_listener_rule" "blue_green" {
  count        = var.enable_blue_green ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type = "forward"
    target_group_arn = (
      var.active_environment == "blue"
      ? aws_lb_target_group.blue[0].arn
      : aws_lb_target_group.green[0].arn
    )
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}
