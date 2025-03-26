
output "ALB_DNS" {
  value = aws_lb.archesys-web-app-lb.dns_name
}

output "DB_Write_DNS" {
  value = aws_rds_cluster.archesys-web-app-db.endpoint
}

output "DB_Read_DNS" {
  value = aws_rds_cluster.archesys-web-app-db.reader_endpoint
}

