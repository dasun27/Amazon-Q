
output "ecs_cluster_id" {
  value = aws_ecs_cluster.ecs_cluster.id
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.ecs_cluster.arn
}


output "cloudwatch_log_group_name" {
  value = aws_cloudwatch_log_group.ecs_cloudwatch_logs.name
}

output "kms_key_arn" {
  value = aws_kms_key.kms_key.arn
}

