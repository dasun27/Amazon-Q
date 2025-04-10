# providers.tf
provider "aws" {
    alias  = "primary"
    region = var.primary_region
    # ... other provider configs
}

provider "aws" {
    alias  = "secondary"
    region = var.secondary_region
    # ... other provider configs
}

# variables.tf
variable "primary_region" {
    default = "us-east-1"
}

variable "secondary_region" {
    default = "us-west-2"
}

# main.tf - Primary Region Resources
resource "aws_vpc" "primary_vpc" {
    provider = aws.primary
    cidr_block = format("%s%s", var.primary_cidr_prefix, ".0.0/16")
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = {
        Name = "primary-vpc"
    }
}

# Similar VPC setup for secondary region
resource "aws_vpc" "secondary_vpc" {
    provider = aws.secondary
    cidr_block = format("%s%s", var.secondary_cidr_prefix, ".0.0/16")
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = {
        Name = "secondary-vpc"
    }
}

# VPC Peering between regions
resource "aws_vpc_peering_connection" "primary_to_secondary" {
    provider = aws.primary
    vpc_id = aws_vpc.primary_vpc.id
    peer_vpc_id = aws_vpc.secondary_vpc.id
    peer_region = var.secondary_region
    auto_accept = false

    tags = {
        Name = "Primary to Secondary VPC Peering"
    }
}

resource "aws_vpc_peering_connection_accepter" "secondary_accepter" {
    provider = aws.secondary
    vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
    auto_accept = true
}

# Route53 Health Checks and DNS Failover
resource "aws_route53_health_check" "primary" {
    provider = aws.primary
    fqdn = aws_lb.primary_alb.dns_name
    port = 443
    type = "HTTPS"
    resource_path = "/health"
    failure_threshold = "3"
    request_interval = "30"

    tags = {
        Name = "Primary-Health-Check"
    }
}

resource "aws_route53_zone" "main" {
    provider = aws.primary
    name = var.domain_name
}

resource "aws_route53_record" "primary" {
    provider = aws.primary
    zone_id = aws_route53_zone.main.zone_id
    name    = var.domain_name
    type    = "A"

    failover_routing_policy {
        type = "PRIMARY"
    }

    set_identifier = "primary"
    health_check_id = aws_route53_health_check.primary.id

    alias {
        name                   = aws_lb.primary_alb.dns_name
        zone_id               = aws_lb.primary_alb.zone_id
        evaluate_target_health = true
    }
}

resource "aws_route53_record" "secondary" {
    provider = aws.secondary
    zone_id = aws_route53_zone.main.zone_id
    name    = var.domain_name
    type    = "A"

    failover_routing_policy {
        type = "SECONDARY"
    }

    set_identifier = "secondary"

    alias {
        name                   = aws_lb.secondary_alb.dns_name
        zone_id               = aws_lb.secondary_alb.zone_id
        evaluate_target_health = true
    }
}

# Global Aurora Database
resource "aws_rds_global_cluster" "global" {
    provider = aws.primary
    global_cluster_identifier = "global-aurora-cluster"
    engine                   = "aurora-mysql"
    engine_version           = "5.7.mysql_aurora.2.10.2"
    database_name           = "appdb"
}

resource "aws_rds_cluster" "primary" {
    provider = aws.primary
    cluster_identifier     = "aurora-cluster-primary"
    engine                = "aurora-mysql"
    engine_version        = "5.7.mysql_aurora.2.10.2"
    global_cluster_identifier = aws_rds_global_cluster.global.id
    database_name         = "appdb"
    master_username       = var.db_username
    master_password       = var.db_password
    skip_final_snapshot   = true
    db_subnet_group_name = aws_db_subnet_group.primary.name
    vpc_security_group_ids = [aws_security_group.primary_db_sg.id]
}

resource "aws_rds_cluster" "secondary" {
    provider = aws.secondary
    cluster_identifier     = "aurora-cluster-secondary"
    engine                = "aurora-mysql"
    engine_version        = "5.7.mysql_aurora.2.10.2"
    global_cluster_identifier = aws_rds_global_cluster.global.id
    db_subnet_group_name = aws_db_subnet_group.secondary.name
    vpc_security_group_ids = [aws_security_group.secondary_db_sg.id]
    depends_on = [aws_rds_cluster.primary]
}

# DynamoDB Global Tables
resource "aws_dynamodb_table" "primary" {
    provider = aws.primary
    name           = "app-state-table"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "id"
    stream_enabled = true
    stream_view_type = "NEW_AND_OLD_IMAGES"

    attribute {
        name = "id"
        type = "S"
    }

    replica {
        region_name = var.secondary_region
    }
}

# Enhanced ECS Service with Cross-Region Support
resource "aws_ecs_service" "primary_service" {
    provider = aws.primary
    name            = "primary-web-service"
    cluster         = aws_ecs_cluster.primary_cluster.id
    task_definition = aws_ecs_task_definition.primary_task.arn
    desired_count   = var.ecs_desired_task_count
    launch_type     = "FARGATE"

    network_configuration {
        subnets         = aws_subnet.primary_private_subnets[*].id
        security_groups = [aws_security_group.primary_app_sg.id]
    }

    load_balancer {
        target_group_arn = aws_lb_target_group.primary_tg.arn
        container_name   = "web-container"
        container_port   = var.container_port
    }

    deployment_controller {
        type = "ECS"
    }

    deployment_circuit_breaker {
        enable   = true
        rollback = true
    }
}

# Similar ECS service setup for secondary region
resource "aws_ecs_service" "secondary_service" {
    provider = aws.secondary
    # Similar configuration as primary
}

# Backup with Cross-Region Copy
resource "aws_backup_vault" "primary" {
    provider = aws.primary
    name = "primary-backup-vault"
}

resource "aws_backup_vault" "secondary" {
    provider = aws.secondary
    name = "secondary-backup-vault"
}

resource "aws_backup_plan" "cross_region" {
    provider = aws.primary
    name = "cross-region-backup"

    rule {
        rule_name         = "cross_region_backup"
        target_vault_name = aws_backup_vault.primary.name
        schedule          = "cron(0 12 * * ? *)"

        lifecycle {
            delete_after = 14
        }

        copy_action {
            destination_vault_arn = aws_backup_vault.secondary.arn
        }
    }
}

# CloudWatch Cross-Region Monitoring
resource "aws_cloudwatch_metric_alarm" "primary_health" {
    provider = aws.primary
    alarm_name          = "primary-health-alarm"
    comparison_operator = "LessThanThreshold"
    evaluation_periods  = "2"
    metric_name        = "HealthyHostCount"
    namespace          = "AWS/ApplicationELB"
    period            = "60"
    statistic         = "Average"
    threshold         = "1"
    alarm_description = "This metric monitors primary region health"
    alarm_actions     = [aws_sns_topic.alerts.arn]

    dimensions = {
        TargetGroup  = aws_lb_target_group.primary_tg.arn_suffix
        LoadBalancer = aws_lb.primary_alb.arn_suffix
    }
}

# WAF with Cross-Region Replication
resource "aws_wafv2_web_acl" "primary" {
    provider = aws.primary
    name        = "primary-waf"
    description = "Primary WAF ACL"
    scope       = "REGIONAL"

    default_action {
        allow {}
    }

    # Add your WAF rules here
}

resource "aws_wafv2_web_acl" "secondary" {
    provider = aws.secondary
    # Similar configuration as primary
}

# Outputs
output "primary_alb_dns" {
    value = aws_lb.primary_alb.dns_name
}

output "secondary_alb_dns" {
    value = aws_lb.secondary_alb.dns_name
}

output "application_dns" {
    value = aws_route53_zone.main.name
}
