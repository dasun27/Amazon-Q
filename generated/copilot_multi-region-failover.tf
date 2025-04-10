# Primary Region Configuration (Existing)
provider "aws" {
  region = var.primary_region
}

# Secondary Region Configuration
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Replicate the VPC in the Secondary Region
resource "aws_vpc" "secondary_vpc" {
  provider    = aws.secondary
  cidr_block  = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Replicate Subnets in the Secondary Region
resource "aws_subnet" "secondary_public_subnets" {
  provider          = aws.secondary
  count             = length(local.public_subnet_cidrs)
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = element(local.public_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.secondary.names, count.index)
}

resource "aws_subnet" "secondary_private_subnets" {
  provider          = aws.secondary
  count             = length(local.private_subnet_cidrs)
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = element(local.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.secondary.names, count.index)
}

# Replicate ECS Cluster in the Secondary Region
resource "aws_ecs_cluster" "secondary_ecs_cluster" {
  provider = aws.secondary
  name     = "archesys-web-cluster-secondary"
}

# Replicate Task Definitions and ECS Service in the Secondary Region
resource "aws_ecs_task_definition" "secondary_task_definition" {
  provider                   = aws.secondary
  family                     = "archesys-web-app-secondary"
  network_mode               = "awsvpc"
  requires_compatibilities   = ["FARGATE"]
  cpu                        = 512
  memory                     = 1024
  container_definitions      = aws_ecs_task_definition.ecs_task_definition.container_definitions
}

resource "aws_ecs_service" "secondary_ecs_service" {
  provider          = aws.secondary
  name              = "archesys-web-service-secondary"
  cluster           = aws_ecs_cluster.secondary_ecs_cluster.id
  task_definition   = aws_ecs_task_definition.secondary_task_definition.arn
  desired_count     = var.ecs_desired_task_count
  launch_type       = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.secondary_private_subnets.*.id
    security_groups = [aws_security_group.secondary_app_sg.id]
  }
}

# Multi-Region Database Replication with RDS
resource "aws_rds_cluster" "secondary_rds_cluster" {
  provider              = aws.secondary
  cluster_identifier    = "archesys-web-app-db-secondary"
  engine                = "aurora-mysql"
  master_username       = var.db_username
  master_password       = var.db_password
  vpc_security_group_ids = [aws_security_group.secondary_db_sg.id]
  db_subnet_group_name  = aws_db_subnet_group.secondary_subnets.name
}

# Route 53 Health Checks and DNS Failover
resource "aws_route53_health_check" "primary_health_check" {
  type                        = "HTTPS"
  resource_path               = "/health"
  fqdn                        = aws_lb.primary_alb.dns_name
  port                        = 443
  request_interval            = 30
  failure_threshold           = 3
}

resource "aws_route53_health_check" "secondary_health_check" {
  type                        = "HTTPS"
  resource_path               = "/health"
  fqdn                        = aws_lb.secondary_alb.dns_name
  port                        = 443
  request_interval            = 30
  failure_threshold           = 3
}

resource "aws_route53_record" "failover_dns" {
  zone_id = var.route53_zone_id
  name    = "web-app.example.com"
  type    = "A"

  set_identifier = "Primary"
  alias {
    name                   = aws_lb.primary_alb.dns_name
    zone_id                = aws_lb.primary_alb.zone_id
    evaluate_target_health = true
  }
  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier = "Secondary"
  alias {
    name                   = aws_lb.secondary_alb.dns_name
    zone_id                = aws_lb.secondary_alb.zone_id
    evaluate_target_health = true
  }
  failover_routing_policy {
    type = "SECONDARY"
  }
}