
# provider

provider "aws" {
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
    region     = var.aws_region
}

# data

data "aws_region" "current" {}

# locals

locals {
    public_subnet_cidrs = [format("%s%s",var.cidr_prefix,".1.0/24"), format("%s%s",var.cidr_prefix,".2.0/24"), format("%s%s",var.cidr_prefix,".3.0/24")]
    private_subnet_cidrs = [format("%s%s",var.cidr_prefix,".4.0/24"), format("%s%s",var.cidr_prefix,".5.0/24"), format("%s%s",var.cidr_prefix,".6.0/24")]
    db_subnet_cidrs = [format("%s%s",var.cidr_prefix,".7.0/24"), format("%s%s",var.cidr_prefix,".8.0/24"), format("%s%s",var.cidr_prefix,".9.0/24")]
    azs = [format("%s%s",data.aws_region.current.name,"a"), format("%s%s",data.aws_region.current.name,"b"), format("%s%s",data.aws_region.current.name,"c")]
}

# resources

resource "aws_vpc" "archesys-web-app-vpc" {
    cidr_block = format("%s%s",var.cidr_prefix,".0.0/16")
    enable_dns_support = true
    enable_dns_hostnames = true
}

resource "aws_subnet" "public_subnets" {
    count             = length(local.public_subnet_cidrs)
    vpc_id            = aws_vpc.archesys-web-app-vpc.id
    cidr_block        = element(local.public_subnet_cidrs, count.index)
    availability_zone = element(local.azs, count.index)
    map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnets" {
    count             = length(local.private_subnet_cidrs)
    vpc_id            = aws_vpc.archesys-web-app-vpc.id
    cidr_block        = element(local.private_subnet_cidrs, count.index)
    availability_zone = element(local.azs, count.index)
}

resource "aws_subnet" "db_subnets" {
    count             = length(local.db_subnet_cidrs)
    vpc_id            = aws_vpc.archesys-web-app-vpc.id
    cidr_block        = element(local.db_subnet_cidrs, count.index)
    availability_zone = element(local.azs, count.index)
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.archesys-web-app-vpc.id
}

resource "aws_eip" "nat_gateway" {
    domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway" {
    allocation_id = aws_eip.nat_gateway.id
    subnet_id = aws_subnet.public_subnets[0].id
}

resource "aws_route_table" "pub_rt" {
    vpc_id = aws_vpc.archesys-web-app-vpc.id
    
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
}

resource "aws_route_table_association" "pub_sub_association" {
    count = length(local.public_subnet_cidrs)
    subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
    route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table" "pri_rt" {
    vpc_id = aws_vpc.archesys-web-app-vpc.id
    
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.nat_gateway.id
    }
}

resource "aws_route_table_association" "pri_sub_association" {
    count = length(local.private_subnet_cidrs)
    subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
    route_table_id = aws_route_table.pri_rt.id
}

resource "aws_route_table" "db_rt" {
    vpc_id = aws_vpc.archesys-web-app-vpc.id
}

resource "aws_route_table_association" "db_sub_association" {
    count = length(local.db_subnet_cidrs)
    subnet_id      = element(aws_subnet.db_subnets[*].id, count.index)
    route_table_id = aws_route_table.db_rt.id
}

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

resource "aws_lb" "archesys-web-app-lb" {
    name        = "archesys-web-app-lb"
    internal           = false
    load_balancer_type = "application"
    subnets         = aws_subnet.public_subnets.*.id
    security_groups = [aws_security_group.archesys-web-alb-sg.id]
}

resource "aws_lb_listener" "archesys-web-app-lb-listener" {
  load_balancer_arn = aws_lb.archesys-web-app-lb.arn
  port              = var.lb_port
  protocol          = var.lb_protocol

  default_action {
    target_group_arn = aws_lb_target_group.archesys-web-app-tg.arn
    type             = "forward"
  }
}

resource "aws_security_group" "archesys-web-app-sg" {
    name   = "archesys-web-app-sg"
    vpc_id = aws_vpc.archesys-web-app-vpc.id

    ingress {
        from_port   = var.Web_server_port
        to_port     = var.Web_server_port
        protocol    = 6
        security_groups = [aws_security_group.archesys-web-alb-sg.id]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "archesys-web-alb-sg" {
    name   = "archesys-web-alb-sg"
    vpc_id = aws_vpc.archesys-web-app-vpc.id

    ingress {
        from_port   = var.lb_port
        to_port     = var.lb_port
        protocol    = 6
        self        = "false"
        cidr_blocks = ["0.0.0.0/0"]
        description = "any"
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "archesys-web-db-sg" {
    name   = "archesys-web-db-sg"
    vpc_id = aws_vpc.archesys-web-app-vpc.id

    ingress {
        from_port   = var.db_port
        to_port     = var.db_port
        protocol    = 6
        security_groups = [aws_security_group.archesys-web-app-sg.id]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        security_groups = [aws_security_group.archesys-web-app-sg.id]
    }
}

resource "aws_ecs_cluster" "ecs_cluster" {
    name = "archesys-web-cluster"
    
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
    family                      = "archesys-web-app"
    network_mode                = "awsvpc"
    requires_compatibilities    = ["FARGATE"]
    cpu                         = 512
    memory                      = 1024
    tags = {
        AppName = "archesys-web-app"
    }
    runtime_platform {
        operating_system_family = "LINUX"
        cpu_architecture        = "X86_64"
    }
    container_definitions = jsonencode([
    {
        name      = "archesys-web-container"
        image     = var.container_image
        command = var.container_command
        essential = true
        portMappings = [
        {
            containerPort = var.Web_server_port
            hostPort      = var.Web_server_port
            protocol      = "tcp"
        }
        ]
    }
    
    ])
}

resource "aws_ecs_service" "ecs_service" {
    name            = "archesys-web-service"
    cluster         = aws_ecs_cluster.ecs_cluster.id
    task_definition = aws_ecs_task_definition.ecs_task_definition.arn
    desired_count   = var.ecs_desired_task_count
    // deployment_minimum_healthy_percent = 100
    // deployment_maximum_percent         = 200
    launch_type     = "FARGATE"
    propagate_tags = "TASK_DEFINITION"
    force_new_deployment = true

    network_configuration {
        subnets             = aws_subnet.private_subnets.*.id
        security_groups     = [aws_security_group.archesys-web-app-sg.id]
    }

    load_balancer {
        target_group_arn = aws_lb_target_group.archesys-web-app-tg.arn
        container_name   = "archesys-web-container"
        container_port   = var.Web_server_port
    }
}

resource "aws_db_subnet_group" "archesys-db-subnets" {
  name       = "archesys-db-subnets"
  subnet_ids = aws_subnet.db_subnets.*.id
}

resource "aws_rds_cluster" "archesys-web-app-db" {
    cluster_identifier        = "archesys-web-app-db"
    vpc_security_group_ids    = [aws_security_group.archesys-web-db-sg.id]
    db_subnet_group_name      = "archesys-db-subnets"
    engine                    = "mysql"
    db_cluster_instance_class = "db.m5d.large"
    storage_type              = "gp3"
    allocated_storage         = 100
    master_username           = var.db_username
    master_password           = var.db_password
    skip_final_snapshot       = true
}