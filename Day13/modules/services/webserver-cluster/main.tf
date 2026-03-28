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

# IAM instance profile — lets instances call SSM / Secrets Manager at runtime

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

  tags = local.base_tags
}

resource "aws_iam_role_policy_attachment" "secret_policies" {
  for_each   = { for idx, arn in var.secret_policy_arns : tostring(idx) => arn }
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.cluster_name}-instance-profile"
  role = aws_iam_role.instance.name
}

# Networking / security groups 

resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.cluster_name}-alb-sg-"
  description = "ALB security group"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.base_tags, { Name = "${var.cluster_name}-alb-sg" })

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
  name_prefix = "${var.cluster_name}-web-sg-"
  description = "Instance security group"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.base_tags, { Name = "${var.cluster_name}-web-sg" })

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

# Launch template — includes instance profile + secret source env vars

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
  instance_type = local.effective_instance_type

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # Attach the instance profile so the instance can call SSM / Secrets Manager
  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port    = var.server_port
    cluster_name   = var.cluster_name
    environment    = var.environment
    app_version    = var.app_version
    secret_source  = var.secret_source  # "ssm" | "secretsmanager" | "none"
    secret_ref     = var.secret_ref     # parameter name or secret ARN
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
