provider "aws" {
  region = var.region
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

resource "aws_security_group" "web_sg" {
  name_prefix = "web-sg-${var.environment}-"
  description = "Allow HTTP inbound for ${var.environment}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "web-sg-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]

  user_data = <<-EOF
    #!/bin/bash
    set -e
    mkdir -p /var/www/html
    echo "Hello from ${var.environment} environment" > /var/www/html/index.html
    cd /var/www/html
    nohup python3 -m http.server ${var.server_port} &
  EOF

  tags = {
    Name        = "web-${var.environment}"
    Environment = var.environment
  }
}
