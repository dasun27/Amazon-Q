import boto3
import time
from typing import List
import os

class AWSInfrastructure:
    def __init__(self):
        # Initialize AWS clients
        self.ec2 = boto3.client('ec2')
        self.ecs = boto3.client('ecs')
        self.rds = boto3.client('rds')
        self.elbv2 = boto3.client('elbv2')

    def create_vpc(self, cidr_prefix: str) -> dict:
        # Create VPC
        vpc = self.ec2.create_vpc(
            CidrBlock=f"{cidr_prefix}.0.0/16",
            EnableDnsHostnames=True,
            EnableDnsSupport=True
        )
        vpc_id = vpc['Vpc']['VpcId']

        # Wait for VPC to be available
        self.ec2.get_waiter('vpc_available').wait(VpcIds=[vpc_id])

        return vpc

    def create_subnets(self, vpc_id: str, cidr_prefix: str) -> tuple:
        # Get availability zones
        azs = self.ec2.describe_availability_zones()['AvailabilityZones']
        az_names = [az['ZoneName'] for az in azs[:3]]

        # Create public subnets
        public_subnets = []
        for i, az in enumerate(az_names):
            subnet = self.ec2.create_subnet(
                VpcId=vpc_id,
                CidrBlock=f"{cidr_prefix}.{i+1}.0/24",
                AvailabilityZone=az
            )
            public_subnets.append(subnet['Subnet']['SubnetId'])

        # Create private subnets
        private_subnets = []
        for i, az in enumerate(az_names):
            subnet = self.ec2.create_subnet(
                VpcId=vpc_id,
                CidrBlock=f"{cidr_prefix}.{i+4}.0/24",
                AvailabilityZone=az
            )
            private_subnets.append(subnet['Subnet']['SubnetId'])

        # Create DB subnets
        db_subnets = []
        for i, az in enumerate(az_names):
            subnet = self.ec2.create_subnet(
                VpcId=vpc_id,
                CidrBlock=f"{cidr_prefix}.{i+7}.0/24",
                AvailabilityZone=az
            )
            db_subnets.append(subnet['Subnet']['SubnetId'])

        return public_subnets, private_subnets, db_subnets

    def create_internet_gateway(self, vpc_id: str) -> str:
        # Create Internet Gateway
        igw = self.ec2.create_internet_gateway()
        igw_id = igw['InternetGateway']['InternetGatewayId']

        # Attach to VPC
        self.ec2.attach_internet_gateway(
            InternetGatewayId=igw_id,
            VpcId=vpc_id
        )

        return igw_id

    def create_nat_gateway(self, public_subnet_id: str) -> str:
        # Create Elastic IP
        eip = self.ec2.allocate_address(Domain='vpc')
        
        # Create NAT Gateway
        nat_gateway = self.ec2.create_nat_gateway(
            SubnetId=public_subnet_id,
            AllocationId=eip['AllocationId']
        )
        
        # Wait for NAT Gateway to be available
        self.ec2.get_waiter('nat_gateway_available').wait(
            NatGatewayIds=[nat_gateway['NatGateway']['NatGatewayId']]
        )

        return nat_gateway['NatGateway']['NatGatewayId']

    def create_security_groups(self, vpc_id: str) -> tuple:
        # ALB Security Group
        alb_sg = self.ec2.create_security_group(
            GroupName='archesys-web-alb-sg',
            Description='Security group for ALB',
            VpcId=vpc_id
        )
        
        self.ec2.authorize_security_group_ingress(
            GroupId=alb_sg['GroupId'],
            IpPermissions=[
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 80,
                    'ToPort': 80,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                },
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 443,
                    'ToPort': 443,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                }
            ]
        )

        # App Security Group
        app_sg = self.ec2.create_security_group(
            GroupName='archesys-web-app-sg',
            Description='Security group for ECS tasks',
            VpcId=vpc_id
        )

        self.ec2.authorize_security_group_ingress(
            GroupId=app_sg['GroupId'],
            IpPermissions=[
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 80,
                    'ToPort': 80,
                    'UserIdGroupPairs': [{'GroupId': alb_sg['GroupId']}]
                }
            ]
        )

        # DB Security Group
        db_sg = self.ec2.create_security_group(
            GroupName='archesys-web-db-sg',
            Description='Security group for RDS',
            VpcId=vpc_id
        )

        self.ec2.authorize_security_group_ingress(
            GroupId=db_sg['GroupId'],
            IpPermissions=[
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 3306,
                    'ToPort': 3306,
                    'UserIdGroupPairs': [{'GroupId': app_sg['GroupId']}]
                }
            ]
        )

        return alb_sg['GroupId'], app_sg['GroupId'], db_sg['GroupId']

    def create_load_balancer(self, name: str, subnets: List[str], security_group_id: str):
        # Create ALB
        load_balancer = self.elbv2.create_load_balancer(
            Name=name,
            Subnets=subnets,
            SecurityGroups=[security_group_id],
            Scheme='internet-facing',
            Type='application',
            IpAddressType='ipv4'
        )

        # Create Target Group
        target_group = self.elbv2.create_target_group(
            Name=f"{name}-tg",
            Protocol='HTTP',
            Port=80,
            VpcId=vpc_id,
            TargetType='ip',
            HealthCheckProtocol='HTTP',
            HealthCheckPort='80',
            HealthCheckPath='/',
            HealthCheckIntervalSeconds=5,
            HealthCheckTimeoutSeconds=3,
            HealthyThresholdCount=3,
            UnhealthyThresholdCount=2
        )

        return load_balancer, target_group

    def create_ecs_cluster(self, cluster_name: str):
        # Create ECS Cluster
        cluster = self.ecs.create_cluster(
            clusterName=cluster_name,
            settings=[
                {
                    'name': 'containerInsights',
                    'value': 'enabled'
                }
            ]
        )

        return cluster

    def create_rds_cluster(self, 
                          cluster_identifier: str, 
                          db_subnet_group_name: str,
                          security_group_id: str,
                          master_username: str,
                          master_password: str):
        # Create DB Subnet Group
        self.rds.create_db_subnet_group(
            DBSubnetGroupName=db_subnet_group_name,
            DBSubnetGroupDescription='Subnet group for RDS cluster',
            SubnetIds=db_subnets
        )

        # Create RDS Cluster
        cluster = self.rds.create_db_cluster(
            DBClusterIdentifier=cluster_identifier,
            Engine='mysql',
            MasterUsername=master_username,
            MasterUserPassword=master_password,
            VpcSecurityGroupIds=[security_group_id],
            DBSubnetGroupName=db_subnet_group_name,
            StorageEncrypted=True,
            DeletionProtection=True
        )

        return cluster

def main():
    # Initialize infrastructure
    infra = AWSInfrastructure()

    # Create VPC
    vpc = infra.create_vpc("10.255")
    vpc_id = vpc['Vpc']['VpcId']

    # Create Subnets
    public_subnets, private_subnets, db_subnets = infra.create_subnets(vpc_id, "10.255")

    # Create Internet Gateway
    igw_id = infra.create_internet_gateway(vpc_id)

    # Create NAT Gateway
    nat_gw_id = infra.create_nat_gateway(public_subnets[0])

    # Create Security Groups
    alb_sg_id, app_sg_id, db_sg_id = infra.create_security_groups(vpc_id)

    # Create Load Balancer
    lb, tg = infra.create_load_balancer(
        "archesys-web-app-lb",
        public_subnets,
        alb_sg_id
    )

    # Create ECS Cluster
    cluster = infra.create_ecs_cluster("archesys-web-cluster")

    # Create RDS Cluster
    db_cluster = infra.create_rds_cluster(
        "archesys-web-app-db",
        "archesys-db-subnets",
        db_sg_id,
        os.environ.get('DB_USERNAME'),
        os.environ.get('DB_PASSWORD')
    )

if __name__ == "__main__":
    main()
