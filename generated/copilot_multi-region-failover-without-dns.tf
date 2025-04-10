# Primary Region Configuration
provider "aws" {
  region = var.primary_region
}

# Secondary Region Configuration
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Primary Application Load Balancer
resource "aws_lb" "primary_alb" {
  name               = "primary-archesys-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.primary_alb_sg.id]
  subnets            = aws_subnet.primary_public_subnets.*.id
}

# Secondary Application Load Balancer
resource "aws_lb" "secondary_alb" {
  provider           = aws.secondary
  name               = "secondary-archesys-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.secondary_alb_sg.id]
  subnets            = aws_subnet.secondary_public_subnets.*.id
}

# AWS Global Accelerator
resource "aws_globalaccelerator_accelerator" "web_app_accelerator" {
  name               = "archesys-web-app-accelerator"
  enabled            = true
  ip_address_type    = "IPV4"
}

# Primary Region Listener Endpoint Group
resource "aws_globalaccelerator_listener" "web_app_listener" {
  accelerator_arn = aws_globalaccelerator_accelerator.web_app_accelerator.id
  protocol        = "TCP"
  port_ranges {
    from_port = 80
    to_port   = 80
  }
  port_ranges {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_globalaccelerator_endpoint_group" "primary_endpoint_group" {
  listener_arn        = aws_globalaccelerator_listener.web_app_listener.id
  endpoint_group_region = var.primary_region
  health_check_path   = "/health"
  health_check_port   = 443
  health_check_protocol = "HTTPS"

  endpoint_configuration {
    endpoint_id = aws_lb.primary_alb.arn
    weight      = 100
  }
}

# Secondary Region Listener Endpoint Group
resource "aws_globalaccelerator_endpoint_group" "secondary_endpoint_group" {
  listener_arn        = aws_globalaccelerator_listener.web_app_listener.id
  endpoint_group_region = var.secondary_region
  health_check_path   = "/health"
  health_check_port   = 443
  health_check_protocol = "HTTPS"

  endpoint_configuration {
    endpoint_id = aws_lb.secondary_alb.arn
    weight      = 50
  }
}

# Security Groups for ALBs
resource "aws_security_group" "primary_alb_sg" {
  name   = "primary-archesys-alb-sg"
  vpc_id = aws_vpc.primary_vpc.id

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
}

resource "aws_security_group" "secondary_alb_sg" {
  provider = aws.secondary
  name     = "secondary-archesys-alb-sg"
  vpc_id   = aws_vpc.secondary_vpc.id

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
}