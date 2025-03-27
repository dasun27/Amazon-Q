
variable "aws_session_token" {
  description = "aws session token"
  default     = ""
  type        = string
}

variable "aws_access_key" {
  description = "aws access key"
  default     = ""
  type        = string
}

variable "aws_secret_key" {
  description = "aws secret key"
  default     = ""
  type        = string
}

variable "aws_region" {
  description = "default AWS region"
  default     = "us-east-1"
  type        = string
}

variable "cidr_prefix" {
  description = "supernet prefix"
  default     = "10.255"
  type        = string
}

variable "lb_port" {
  description = "load balancer listening port"
  default     = 80
  type        = number
}

variable "lb_protocol" {
  description = "load balancer protocol e.g.- HTTP/HTTPS"
  default     = "HTTP"
  type        = string
}

variable "Web_server_port" {
  description = "web server listening port"
  default     = 80
  type        = number
}

variable "Web_server_protocol" {
  description = "web server protocol e.g.- HTTP/HTTPS"
  default     = "HTTP"
  type        = string
}

variable "db_port" {
  description = "database server port"
  default     = 3306
  type        = number
}

variable "container_image" {
  description = "URL for the docker image on ECR"
  default     = "public.ecr.aws/ubuntu/apache2:latest"
  type        = string
}

variable "container_command" {
  description = "command to start the Apache web server"
  default     = ["apachectl", "-D", "FOREGROUND"]
  type        = list(string)
}

variable "ecs_desired_task_count" {
  description = "number of ECS tasks to run"
  default     = 3
  type        = number
}

variable "db_username" {
  description = "username for the database"
  default     = ""
  type        = string
}

variable "db_password" {
  description = "password for the database"
  default     = ""
  type        = string
}
