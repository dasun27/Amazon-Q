# Provider Configuration
- The `provider "aws"` block configures the AWS provider with credentials and the region to be used.

# Data Sources
- `data "aws_region" "current"` retrieves the current AWS region.

# Locals
- Defines reusable CIDR blocks for public, private, and database subnets.
- Availability zones are generated based on the AWS region.

# Resources
1. **VPC and Subnets**:
   - `aws_vpc` creates the Virtual Private Cloud.
   - `aws_subnet` creates public, private, and database subnets.

2. **Networking Components**:
   - `aws_internet_gateway` enables internet access for public subnets.
   - `aws_nat_gateway` facilitates internet access for private resources.
   - `aws_route_table` and `aws_route_table_association` manage routing for subnets.

3. **Load Balancer**:
   - `aws_lb` creates an Application Load Balancer (ALB).
   - `aws_lb_listener` defines HTTP and HTTPS listeners for the ALB.

4. **Security Groups**:
   - Security groups define access rules for ALB, ECS, and RDS components.

5. **ECS Cluster and Services**:
   - `aws_ecs_cluster` creates an ECS cluster with container insights enabled.
   - `aws_ecs_task_definition` defines the Docker container for the web application.
   - `aws_ecs_service` deploys the ECS service using the task definition.

6. **Database**:
   - `aws_db_subnet_group` groups the database subnets.
   - `aws_rds_cluster` creates an RDS database cluster with MySQL.

# Notes:
- Variables like `var.aws_access_key`, `var.Web_server_port`, etc., are placeholders for user-provided values.
- Some resources are tagged for better resource management.
- The configuration sets up a three-tier architecture: ALB -> ECS (Web Layer) -> RDS (Database Layer).

If you'd like a deeper explanation of a specific resource or variable, let me know!