provider "aws" {
  region = var.region
}

# Remote State Data Source
# Reads outputs published by the environments/dev (or staging/production)
# layer without duplicating resource definitions or hard-coding IDs.

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "day7-terraform-state-2026"
    key    = "environments/${var.environment}/terraform.tfstate"
    region = "us-east-1"
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

# Security group for the app-layer instance
resource "aws_security_group" "app_sg" {
  name_prefix = "app-sg-${var.environment}-"
  description = "App layer SG for ${var.environment}"

  # vpc_id is pulled directly from the network layer's remote state output
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

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
    Name        = "app-sg-${var.environment}"
    Environment = var.environment
  }
}

# App instance placed into the subnet published by the network layer
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  # subnet_id is read from the remote state of the network/env layer
  subnet_id              = data.terraform_remote_state.network.outputs.subnet_id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    set -e
    mkdir -p /var/www/html
    echo "App layer — ${var.environment} environment" > /var/www/html/index.html
    cd /var/www/html
    nohup python3 -m http.server ${var.server_port} &
  EOF

  tags = {
    Name        = "app-${var.environment}"
    Environment = var.environment
    Layer       = "app"
  }
}
