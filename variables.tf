variable "deletion_window_in_days" {
  description = "deletion window in days"
  default     = 7
  type        = number
}

variable "ecs_cloudwatch_log_group_name" {
  description = "ecs cloudwatch log group name"
  default     = "ecs-logs"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ecs cluster name"
  default     = "ecs-cluster"
  type        = string
}

variable "logging" {
  description = "logging"
  default     = "OVERRIDE"
  type        = string
}

variable "cloud_watch_encryption_enabled" {
  description = "cloud watch encryption enabled"
  default     = true
  type        = bool
}

variable "capacity_providers" {
  description = "capacity providers"
  default     = ["FARGATE"]
  type        = list(string)
}

variable "default_capacity_provider_strategy_base" {
  description = "default capacity provider strategy base"
  default     = 1
  type        = number
}

variable "default_capacity_provider_strategy_weight" {
  description = "default capacity provider strategy weight"
  default     = 100
  type        = number
}

variable "capacity_provider" {
  description = "capacity provider"
  default     = "FARGATE"
  type        = string
}

variable "common_tags" {
  description = "Dummy variable to silence warnings"
  type        = map(string)
  default     = {}
}

variable "cluster_type" {
  description = "The type of ECS cluster (e.g., FARGATE)"
  type        = string
}


#########variables for EC2


variable "image_id" {
  type        = string
  description = "image_id"
  default = "ami-0fbd8b868941357fa" 
}

variable "instance_type" {
  type        = string
  description = "instance_type"
  default = ""
}

variable "instance_key" {
  type        = string
  description = "instance_key"
  default = ""
}

variable "security_groups_ids" {
  type        = list(string)
  description = "security_groups_ids"
  default = []
}

variable "aws_autoscaling_group_name" {
  type        = string
  description = "aws_autoscaling_group_name"
  default = ""
}


variable "subnet_ids" {
  type        = list(string)
  description = "subnet_ids"
  default = []
}

variable "autoscaling_max_size" {
  type        = string
  description = "autoscaling_max_size"
  default = ""
}

variable "autoscaling_desired_capacity" {
  type        = string
  description = "autoscaling_desired_capacity"
  default = ""
}

variable "autoscaling_min_size" {
  type        = string
  description = "autoscaling_min_size"
  default = ""
}

variable "capacity_provider_name" {
  type        = string
  description = "capacity_provider_name"
  default = ""
}

variable "maximum_scaling_step_size" {
  type        = number
  description = "maximum_scaling_step_size"
  default = 5
}

variable "minimum_scaling_step_size" {
  type        = number
  description = "minimum_scaling_step_size"
  default = 1
}

variable "auto_scaling_group_arn1" {
  type        = string
  description = "auto_scaling_group_arn"
  default = null
}

