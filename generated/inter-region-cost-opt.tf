# Cost optimization variables
variable "enable_secondary_region" {
    description = "Enable secondary region resources only in production"
    default     = false
}

variable "environment" {
    description = "Environment (dev, staging, prod)"
    default     = "dev"
}

# Conditional secondary region provider
provider "aws" {
    alias  = "secondary"
    region = var.secondary_region
    # Only create secondary region resources if enabled
    count = var.enable_secondary_region ? 1 : 0
}

# Cost-optimized Global Accelerator
resource "aws_globalaccelerator_accelerator" "app_accelerator" {
    provider        = aws.primary
    name            = "webapp-accelerator"
    ip_address_type = "IPV4"
    enabled         = true

    # Enable flow logs only in production
    dynamic "attributes" {
        for_each = var.environment == "prod" ? [1] : []
        content {
            flow_logs_enabled   = true
            flow_logs_s3_bucket = aws_s3_bucket.flow_logs[0].id
            flow_logs_s3_prefix = "flow-logs/"
        }
    }
}

# Optimize RDS costs
resource "aws_rds_global_cluster" "global" {
    count = var.enable_secondary_region ? 1 : 0
    provider = aws.primary
    global_cluster_identifier = "archesys-global-cluster"
    engine                   = "aurora-mysql"
    engine_version           = "5.7.mysql_aurora.2.10.2"
    database_name           = "archesysdb"
    deletion_protection     = var.environment == "prod"
}

resource "aws_rds_cluster" "primary" {
    cluster_identifier     = "archesys-primary-cluster"
    engine                = "aurora-mysql"
    engine_version        = "5.7.mysql_aurora.2.10.2"
    global_cluster_identifier = var.enable_secondary_region ? aws_rds_global_cluster.global[0].id : null
    database_name         = "archesysdb"
    master_username       = var.db_username
    master_password       = var.db_password
    skip_final_snapshot   = var.environment != "prod"
    deletion_protection   = var.environment == "prod"
    
    # Cost optimization for non-prod environments
    serverlessv2_scaling_configuration {
        count = var.environment != "prod" ? 1 : 0
        min_capacity = 0.5
        max_capacity = 1
    }
    
    # Production settings
    dynamic "cluster_instance_class" {
        for_each = var.environment == "prod" ? [1] : []
        content {
            instance_class = "db.r6g.large"  # Using Graviton instances for better price/performance
        }
    }
}

# Optimize ECS costs
resource "aws_ecs_service" "ecs_service" {
    name            = "archesys-web-service"
    cluster         = aws_ecs_cluster.ecs_cluster.id
    task_definition = aws_ecs_task_definition.ecs_task_definition.arn
    
    # Adjust desired count based on environment
    desired_count   = var.environment == "prod" ? var.ecs_desired_task_count : 1

    # Use Fargate Spot for non-production environments
    capacity_provider_strategy {
        capacity_provider = var.environment == "prod" ? "FARGATE" : "FARGATE_SPOT"
        weight          = 1
    }

    # Enable auto scaling only in production
    dynamic "autoscaling_policy" {
        for_each = var.environment == "prod" ? [1] : []
        content {
            target_tracking_scaling_policy_configuration {
                target_value = 70
                predefined_metric_specification {
                    predefined_metric_type = "ECSServiceAverageCPUUtilization"
                }
            }
        }
    }
}

# Optimize backup costs
resource "aws_backup_plan" "cross_region" {
    count = var.environment == "prod" ? 1 : 0
    provider = aws.primary
    name = "archesys-cross-region-backup"

    rule {
        rule_name         = "cross_region_backup"
        target_vault_name = aws_backup_vault.cross_region[0].name
        schedule          = "cron(0 12 * * ? *)"

        lifecycle {
            delete_after = var.environment == "prod" ? 30 : 7
        }

        # Cross-region copy only in production
        dynamic "copy_action" {
            for_each = var.enable_secondary_region ? [1] : []
            content {
                destination_vault_arn = aws_backup_vault.secondary[0].arn
            }
        }
    }
}

# Optimize monitoring costs
resource "aws_cloudwatch_metric_alarm" "service_health" {
    count = var.environment == "prod" ? 1 : 0
    provider = aws.primary
    alarm_name          = "service-health"
    period             = var.environment == "prod" ? 60 : 300  # Longer intervals for non-prod
    evaluation_periods = var.environment == "prod" ? 2 : 1
}

# Cost-effective DynamoDB configuration
resource "aws_dynamodb_table" "sessions" {
    provider = aws.primary
    name           = "archesys-sessions"
    billing_mode   = var.environment == "prod" ? "PROVISIONED" : "PAY_PER_REQUEST"
    
    dynamic "read_capacity" {
        for_each = var.environment == "prod" ? [1] : []
        content {
            read_capacity  = 5
            write_capacity = 5
        }
    }

    # Global tables only in production with secondary region
    dynamic "replica" {
        for_each = var.enable_secondary_region && var.environment == "prod" ? [1] : []
        content {
            region_name = var.secondary_region
        }
    }

    ttl {
        attribute_name = "expiry"
        enabled = true
    }
}

# Optimize ALB costs
resource "aws_lb" "archesys-web-app-lb" {
    # Existing configuration...
    
    # Enable deletion protection only in production
    enable_deletion_protection = var.environment == "prod"

    # Optimize idle timeout
    idle_timeout = var.environment == "prod" ? 60 : 30
}

# Cost-effective security group rules
resource "aws_security_group" "archesys-web-app-sg" {
    # Existing configuration...
    
    # Restrict CIDR blocks based on environment
    ingress {
        from_port   = var.Web_server_port
        to_port     = var.Web_server_port
        protocol    = "tcp"
        cidr_blocks = var.environment == "prod" ? ["0.0.0.0/0"] : [var.vpc_cidr]
    }
}

# Locals for cost optimization
locals {
    # Use smaller subnets for non-prod environments
    subnet_count = var.environment == "prod" ? 3 : 2
    
    # Adjust instance sizes based on environment
    instance_type = {
        "dev"     = "t4g.micro"    # Graviton for cost savings
        "staging" = "t4g.small"
        "prod"    = "t4g.medium"
    }
}

# Cost optimization tags
locals {
    common_tags = {
        Environment = var.environment
        CostCenter  = "archesys-${var.environment}"
        Terraform   = "true"
    }
}

# Add cost allocation tags to all resources
resource "null_resource" "tags" {
    provisioner "local-exec" {
        command = "aws resourcegroupstaggingapi tag-resources --tags ${jsonencode(local.common_tags)}"
    }
}


----------

Key Cost Optimization Strategies:

Conditional Secondary Region:

Only deploy secondary region in production

Reduce redundant infrastructure costs in dev/staging

RDS Optimizations:

Use Aurora Serverless v2 in non-prod environments

Graviton instances in production for better price/performance

Skip final snapshots in non-prod

Optimize backup retention periods

ECS Optimizations:

Use Fargate Spot in non-prod environments

Reduce desired count in non-prod

Optimize auto-scaling settings

Monitoring Optimizations:

Reduce CloudWatch metric frequency in non-prod

Limit number of alarms in non-prod

Optimize log retention periods

DynamoDB Optimizations:

Use on-demand capacity in non-prod

Global tables only in production

Optimize TTL settings

