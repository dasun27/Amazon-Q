# CloudWatch Alarms for ECS Service
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "ecs-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name        = "CPUUtilization"
  namespace          = "AWS/ECS"
  period             = var.alarm_period
  statistic          = "Average"
  threshold          = var.cpu_utilization_threshold
  alarm_description  = "ECS CPU utilization is too high"
  alarm_actions      = []  # Add SNS topic ARN here if needed

  dimensions = {
    ClusterName = aws_ecs_cluster.ecs_cluster.name
    ServiceName = aws_ecs_service.ecs_service.name
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "ecs-memory-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name        = "MemoryUtilization"
  namespace          = "AWS/ECS"
  period             = var.alarm_period
  statistic          = "Average"
  threshold          = var.memory_utilization_threshold
  alarm_description  = "ECS memory utilization is too high"
  alarm_actions      = []  # Add SNS topic ARN here if needed

  dimensions = {
    ClusterName = aws_ecs_cluster.ecs_cluster.name
    ServiceName = aws_ecs_service.ecs_service.name
  }
}

# CloudWatch Alarms for Application Load Balancer
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "alb-5xx-errors-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name        = "HTTPCode_Target_5XX_Count"
  namespace          = "AWS/ApplicationELB"
  period             = var.alarm_period
  statistic          = "Sum"
  threshold          = 10
  alarm_description  = "ALB 5XX errors are too high"
  alarm_actions      = []  # Add SNS topic ARN here if needed

  dimensions = {
    LoadBalancer = aws_lb.archesys-web-app-lb.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_latency_high" {
  alarm_name          = "alb-target-response-time-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name        = "TargetResponseTime"
  namespace          = "AWS/ApplicationELB"
  period             = var.alarm_period
  statistic          = "Average"
  threshold          = 5
  alarm_description  = "ALB target response time is too high"
  alarm_actions      = []  # Add SNS topic ARN here if needed

  dimensions = {
    LoadBalancer = aws_lb.archesys-web-app-lb.arn_suffix
  }
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "rds-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name        = "CPUUtilization"
  namespace          = "AWS/RDS"
  period             = var.alarm_period
  statistic          = "Average"
  threshold          = 80
  alarm_description  = "RDS CPU utilization is too high"
  alarm_actions      = []  # Add SNS topic ARN here if needed

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.archesys-web-app-db.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_freeable_memory_low" {
  alarm_name          = "rds-freeable-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name        = "FreeableMemory"
  namespace          = "AWS/RDS"
  period             = var.alarm_period
  statistic          = "Average"
  threshold          = 1000000000  # 1GB in bytes
  alarm_description  = "RDS freeable memory is too low"
  alarm_actions      = []  # Add SNS topic ARN here if needed

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.archesys-web-app-db.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  alarm_name          = "rds-free-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name        = "FreeStorageSpace"
  namespace          = "AWS/RDS"
  period             = var.alarm_period
  statistic          = "Average"
  threshold          = 10737418240  # 10GB in bytes
  alarm_description  = "RDS free storage space is too low"
  alarm_actions      = []  # Add SNS topic ARN here if needed

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.archesys-web-app-db.cluster_identifier
  }
}