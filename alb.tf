# Application Load Balancer
resource "aws_lb" "archesys-web-app-lb" {
    name               = "archesys-web-app-lb"
    internal           = false
    load_balancer_type = "application"
    subnets           = aws_subnet.public_subnets.*.id
    security_groups    = [aws_security_group.archesys-web-alb-sg.id]
}

# ALB Security Group
resource "aws_security_group" "archesys-web-alb-sg" {
    name   = "archesys-web-alb-sg"
    vpc_id = aws_vpc.archesys-web-app-vpc.id

    # Allow HTTP
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = 6
        self        = "false"
        cidr_blocks = ["0.0.0.0/0"]
        description = "HTTP"
    }

    # Allow HTTPS
    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = 6
        self        = "false"
        cidr_blocks = ["0.0.0.0/0"]
        description = "HTTPS"
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# HTTP Listener (redirects to HTTPS)
resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.archesys-web-app-lb.arn
    port              = 80
    protocol          = "HTTP"

    default_action {
        type = "redirect"

        redirect {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301"
        }
    }
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
    load_balancer_arn = aws_lb.archesys-web-app-lb.arn
    port              = 443
    protocol          = "HTTPS"
    ssl_policy        = "ELBSecurityPolicy-2016-08"
    certificate_arn   = aws_acm_certificate.cert.arn

    default_action {
        target_group_arn = aws_lb_target_group.archesys-web-app-tg.arn
        type             = "forward"
    }
}

# Target Group
resource "aws_lb_target_group" "archesys-web-app-tg" {
    name        = "archesys-web-app-tg"
    port        = var.Web_server_port
    protocol    = var.Web_server_protocol
    vpc_id      = aws_vpc.archesys-web-app-vpc.id
    target_type = "ip"

    health_check {
        healthy_threshold   = "3"
        interval            = "5"
        protocol            = var.Web_server_protocol
        matcher             = "200"
        timeout             = "3"
        path                = "/"
        unhealthy_threshold = "2"
    }
}