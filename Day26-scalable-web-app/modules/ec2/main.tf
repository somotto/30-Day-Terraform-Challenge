locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "scalable-web-app"
  })
}

resource "aws_security_group" "instance" {
  name        = "web-instance-sg-${var.environment}"
  description = "Allow HTTP/HTTPS inbound to EC2 instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_launch_template" "web" {
  name_prefix   = "web-lt-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Deployed with Terraform — environment: ${var.environment}</h1>" \
      > /var/www/html/index.html
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "web-${var.environment}" })
  }

  lifecycle {
    create_before_destroy = true
  }
}