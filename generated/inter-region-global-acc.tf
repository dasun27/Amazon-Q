# providers.tf
provider "aws" {
    alias  = "primary"
    region = var.primary_region
    # ... existing provider configs
}

provider "aws" {
    alias  = "secondary"
    region = var.secondary_region
    # ... existing provider configs
}

# Global Accelerator Configuration
resource "aws_globalaccelerator_accelerator" "app_accelerator" {
    provider = aws.primary
    name            = "webapp-accelerator"
    ip_address_type = "IPV4"
    enabled         = true

    attributes {
        flow_logs_enabled   = true
        flow_logs_s3_bucket = aws_s3_bucket.flow_logs.id
        flow_logs_s3_prefix = "flow-logs/"
    }
}

resource "aws_globalaccelerator_listener" "app_listener" {
    accelerator_arn = aws_globalaccelerator_accelerator.app_accelerator.id
    client_affinity = "SOURCE_IP"
    protocol        = "TCP"

    port_range {
        from_port = 80
        to_port   = 80
    }

    port_range {
        from_port = 443
        to_port   = 443
    }
}

resource "aws_globalaccelerator_endpoint_group" "primary" {
    provider = aws.primary
    listener_arn = aws_globalaccelerator_listener.app_listener.id
    endpoint_group_region = var.primary_region
    health_check_port = 80
    health_check_protocol = "HTTP"
    health_check_path = "/health"
    threshold_count = 3
    traffic_dial_percentage = 100

    endpoint_configuration {
        endpoint_id = aws_lb.archesys-web-app-lb.arn
        weight     = 100
    }
}

resource "aws_globalaccelerator_endpoint_group" "secondary" {
    provider = aws.secondary
    listener_arn = aws_globalaccelerator_listener.app_listener.id
    endpoint_group_region = var.secondary_region
    health_check_port = 80
    health_check_protocol = "HTTP"
    health_check_path = "/health"
    threshold_count = 3
    traffic_dial_percentage = 0  # Initially set to 0, will be adjusted by health checks

    endpoint_configuration {
        endpoint_id = aws_lb.secondary_alb.arn
        weight     = 100
    }
}

# Cross-Region VPC Peering
resource "aws_vpc_peering_connection" "primary_to_secondary" {
    provider = aws.primary
    vpc_id = aws_vpc.archesys-web-app-vpc.id
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

# Global Aurora Database
resource "aws_rds_global_cluster" "global" {
    provider = aws.primary
    global_cluster_identifier = "archesys-global-cluster"
    engine                   = "aurora-mysql"
    engine_version           = "5.7.mysql_aurora.2.10.2"
    database_name           = "archesysdb"
    deletion_protection     = true
}

resource "aws_rds_cluster" "primary" {
    provider = aws.primary
    cluster_identifier     = "archesys-primary-cluster"
    engine                = "aurora-mysql"
    engine_version        = "5.7.mysql_aurora.2.10.2"
    global_cluster_identifier = aws_rds_global_cluster.global.id
    database_name         = "archesysdb"
    master_username       = var.db_username
    master_password       = var.db_password
    skip_final_snapshot   = true
    db_subnet_group_name = aws_db_subnet_group.archesys-db-subnets.name
    vpc_security_group_ids = [aws_security_group.archesys-web-db-sg.id]
}

resource "aws_rds_cluster" "secondary" {
    provider = aws.secondary
    cluster_identifier     = "archesys-secondary-cluster"
    engine                = "aurora-mysql"
    engine_version        = "5.7.mysql_aurora.2.10.2"
    global_cluster_identifier = aws_rds_global_cluster.global.id
    db_subnet_group_name = aws_db_subnet_group.secondary_db_subnets.name
    vpc_security_group_ids = [aws_security_group.secondary_db_sg.id]
    depends_on = [aws_rds_cluster.primary]
}

# DynamoDB Global Tables for Session Management
resource "aws_dynamodb_table" "sessions" {
    provider = aws.primary
    name           = "archesys-sessions"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "session_id"
    stream_enabled = true
    stream_view_type = "NEW_AND_OLD_IMAGES"

    attribute {
        name = "session_id"
        type = "S"
    }

    replica {
        region_name = var.secondary_region
    }

    ttl {
        attribute_name = "expiry"
        enabled = true
    }
}

# Enhanced ECS Service with Health Checks
resource "aws_ecs_service" "ecs_service" {
    # Existing configuration...

    health_check_grace_period_seconds = 60

    deployment_circuit_breaker {
        enable   = true
        rollback = true
    }

    deployment_controller {
        type = "ECS"
    }

    network_configuration {
        subnets         = aws_subnet.private_subnets[*].id
        security_groups = [aws_security_group.archesys-web-app-sg.id]
    }
}

# CloudWatch Cross-Region Monitoring
resource "aws_cloudwatch_metric_alarm" "service_health" {
    provider = aws.primary
    alarm_name          = "service-health"
    comparison_operator = "LessThanThreshold"
    evaluation_periods  = "2"
    metric_name        = "HealthyHostCount"
    namespace          = "AWS/ApplicationELB"
    period            = "60"
    statistic         = "Average"
    threshold         = "1"
    alarm_description = "Monitor service health"
    alarm_actions     = [aws_sns_topic.alerts.arn]

    dimensions = {
        TargetGroup  = aws_lb_target_group.archesys-web-app-tg.arn_suffix
        LoadBalancer = aws_lb.archesys-web-app-lb.arn_suffix
    }
}

# Cross-Region Backup
resource "aws_backup_vault" "cross_region" {
    provider = aws.primary
    name = "archesys-cross-region-backup"
}

resource "aws_backup_plan" "cross_region" {
    provider = aws.primary
    name = "archesys-cross-region-backup"

    rule {
        rule_name         = "cross_region_backup"
        target_vault_name = aws_backup_vault.cross_region.name
        schedule          = "cron(0 12 * * ? *)"

        lifecycle {
            delete_after = 14
        }

        copy_action {
            destination_vault_arn = aws_backup_vault.secondary.arn
        }
    }
}

# Enhanced Security Groups for Cross-Region Communication
resource "aws_security_group_rule" "cross_region_communication" {
    provider = aws.primary
    type              = "ingress"
    from_port         = 0
    to_port           = 65535
    protocol          = "tcp"
    cidr_blocks       = [aws_vpc.secondary_vpc.cidr_block]
    security_group_id = aws_security_group.archesys-web-app-sg.id
}

# CloudWatch Synthetics for Cross-Region Monitoring
resource "aws_synthetics_canary" "health_check" {
    provider = aws.primary
    name                 = "archesys-health-check"
    artifact_s3_location = "s3://${aws_s3_bucket.monitoring.id}/canary/"
    execution_role_arn   = aws_iam_role.canary_role.arn
    runtime_version      = "syn-nodejs-puppeteer-3.9"
    schedule {
        expression = "rate(5 minutes)"
    }
    handler = "index.handler"
    # Add your monitoring script here
}

# Outputs
output "global_accelerator_dns" {
    value = aws_globalaccelerator_accelerator.app_accelerator.dns_name
}

output "global_accelerator_ips" {
    value = aws_globalaccelerator_accelerator.app_accelerator.ip_sets[0].ip_addresses
}
