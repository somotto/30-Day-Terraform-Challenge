module "ec2" {
  source      = "../../modules/ec2"
  ami_id      = var.ami_id
  vpc_id      = var.vpc_id
  environment = var.environment

  tags = {
    Owner = "terraform-challenge"
    Day   = "26"
  }
}

module "alb" {
  source      = "../../modules/alb"
  name        = var.app_name
  vpc_id      = var.vpc_id
  subnet_ids  = var.public_subnet_ids
  environment = var.environment

  tags = {
    Owner = "terraform-challenge"
    Day   = "26"
  }
}

module "asg" {
  source                  = "../../modules/asg"
  launch_template_id      = module.ec2.launch_template_id
  launch_template_version = module.ec2.launch_template_version
  subnet_ids              = var.private_subnet_ids
  target_group_arns       = [module.alb.target_group_arn]
  min_size                = var.min_size
  max_size                = var.max_size
  desired_capacity        = var.desired_capacity
  environment             = var.environment
  force_delete            = var.environment != "production"

  tags = {
    Owner = "terraform-challenge"
    Day   = "26"
  }
}