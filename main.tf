data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical (Ubuntu)
}

#data "aws_vpc" "default" {
#  default = true
#}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"
  name    = "blog_new"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules = {
    http = {
      from_port   = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP access to demo webpage"
    }
    https = {
      from_port   = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "10.0.0.0/16"
      description = "HTTPS from internal"
    }
    self-all = {
      ip_protocol                  = "-1"
      referenced_security_group_id = "self"
      description                  = "All traffic from members of this SG"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}

module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.blog_sg.security_group_id]

  listeners = {
    blog-http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_arn = aws_lb_target_group.blog.arn
      }
    }
  }

  tags = {
    Environment = "dev"
  }
}

resource "aws_lb_target_group" "blog" {
  name     = "blog"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.blog_vpc.vpc_id
}

resource "aws_lb_target_group_attachment" "blog" {
  target_group_arn = aws_lb_target_group.blog.arn
  target_id        = aws_instance.blog.id
  port             = 80
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.3.2"

  name = "blog"

  min_size = 1
  max_size = 2

  vpc_zone_identifier = module.blog.vpc.public_subnets

  launch_template_name = "blog"
  security_groups      = [module.blog_sg.security_group_id]
  instance_type        = var.instance_type
  image_id             = data.aws_ami.app_ami.id

  traffic_source_attachements = {
    blog-alb = {
      traffic_source_identifier = aws_lb_target_group.blog.arn
    }
  }
}



#resource "aws_security_group" "blog" {
#  name        = "blog"
#  description = "Allow http and https in. Allow everything out"
#
#  vpc_id = data.aws_vpc.default.id
#}

#resource "aws_security_group_rule" "blog_http_in" {
#  type        = "ingress"
#  from_port   = 80
#  to_port     = 80
#  protocol    = "tcp"
#  cidr_blocks = ["0.0.0.0/0"]
#
#  security_group_id = aws_security_group.blog.id
#} 

#resource "aws_security_group_rule" "blog_https_in" {
#  type        = "ingress"
#  from_port   = 443
#  to_port     = 443
#  protocol    = "tcp"
#  cidr_blocks = ["0.0.0.0/0"]
#
#  security_group_id = aws_security_group.blog.id
#}

#resource "aws_security_group_rule" "blog_everything_out" {
#  type        = "egress"
#  from_port   = 0
#  to_port     = 0
#  protocol    = "-1"
#  cidr_blocks = ["0.0.0.0/0"]
#
#  security_group_id = aws_security_group.blog.id
#}