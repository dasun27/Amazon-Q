from aws_cdk import (
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_ecs_patterns as ecs_patterns,
    aws_rds as rds,
    aws_elasticloadbalancingv2 as elbv2,
    aws_wafv2 as wafv2,
    aws_kms as kms,
    aws_logs as logs,
    aws_guardduty as guardduty,
    aws_backup as backup,
    aws_secretsmanager as secretsmanager,
    Stack, CfnOutput, Duration, Tags
)
from constructs import Construct

class SecureWebAppStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # VPC Configuration
        self.vpc = ec2.Vpc(
            self, "WebAppVPC",
            max_azs=3,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Database",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ],
            flow_logs={
                "flowlog": ec2.FlowLogOptions(
                    destination=ec2.FlowLogDestination.to_cloud_watch_logs(),
                    traffic_type=ec2.FlowLogTrafficType.ALL
                )
            }
        )

        # Security Groups
        alb_security_group = ec2.SecurityGroup(
            self, "ALBSecurityGroup",
            vpc=self.vpc,
            description="Security group for ALB",
            allow_all_outbound=False
        )
        
        app_security_group = ec2.SecurityGroup(
            self, "AppSecurityGroup",
            vpc=self.vpc,
            description="Security group for application",
            allow_all_outbound=False
        )
        
        db_security_group = ec2.SecurityGroup(
            self, "DBSecurityGroup",
            vpc=self.vpc,
            description="Security group for database",
            allow_all_outbound=False
        )

        # Security Group Rules
        alb_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(443),
            "Allow HTTPS inbound"
        )

        app_security_group.add_ingress_rule(
            alb_security_group,
            ec2.Port.tcp(80),
            "Allow traffic from ALB"
        )

        db_security_group.add_ingress_rule(
            app_security_group,
            ec2.Port.tcp(3306),
            "Allow traffic from application"
        )

        # KMS Keys
        rds_encryption_key = kms.Key(
            self, "RDSEncryptionKey",
            enable_key_rotation=True,
            description="KMS key for RDS encryption"
        )

        # Secrets Manager for Database Credentials
        database_credentials = secretsmanager.Secret(
            self, "DBCredentials",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "admin"}',
                generate_string_key="password",
                exclude_characters="\"@/\\"
            )
        )

        # RDS Cluster
        database = rds.DatabaseCluster(
            self, "Database",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_3_02_0
            ),
            credentials=rds.Credentials.from_secret(database_credentials),
            instance_props=rds.InstanceProps(
                vpc=self.vpc,
                vpc_subnets=ec2.SubnetSelection(
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
                ),
                security_groups=[db_security_group],
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.BURSTABLE3,
                    ec2.InstanceSize.MEDIUM
                )
            ),
            storage_encrypted=True,
            encryption_key=rds_encryption_key,
            backup_retention=Duration.days(7),
            deletion_protection=True
        )

        # ECS Cluster
        cluster = ecs.Cluster(
            self, "WebAppCluster",
            vpc=self.vpc,
            container_insights=True
        )

        # Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self, "WebAppALB",
            vpc=self.vpc,
            internet_facing=True,
            security_group=alb_security_group
        )

        # HTTPS Listener
        https_listener = alb.add_listener(
            "HTTPSListener",
            port=443,
            ssl_policy=elbv2.SslPolicy.TLS12,
            certificates=[certificate]  # Add your ACM certificate here
        )

        # WAF Configuration
        waf_acl = wafv2.CfnWebACL(
            self, "WebAppWAF",
            default_action=wafv2.CfnWebACL.DefaultActionProperty(allow={}),
            scope="REGIONAL",
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                cloud_watch_metrics_enabled=True,
                metric_name="WebAppWAFMetrics",
                sampled_requests_enabled=True
            ),
            rules=[
                wafv2.CfnWebACL.RuleProperty(
                    name="AWSManagedRulesCommonRuleSet",
                    priority=1,
                    override_action=wafv2.CfnWebACL.OverrideActionProperty(none={}),
                    statement=wafv2.CfnWebACL.StatementProperty(
                        managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                            name="AWSManagedRulesCommonRuleSet",
                            vendor_name="AWS"
                        )
                    ),
                    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                        cloud_watch_metrics_enabled=True,
                        metric_name="AWSManagedRulesCommonRuleSetMetrics",
                        sampled_requests_enabled=True
                    )
                )
            ]
        )

        # ECS Fargate Service
        fargate_service = ecs_patterns.ApplicationLoadBalancedFargateService(
            self, "WebAppService",
            cluster=cluster,
            cpu=512,
            memory_limit_mib=1024,
            desired_count=2,
            listener=https_listener,
            security_groups=[app_security_group],
            task_image_options=ecs_patterns.ApplicationLoadBalancedTaskImageOptions(
                image=ecs.ContainerImage.from_registry("your-container-image"),
                container_port=80,
                enable_logging=True,
                environment={
                    "DB_HOST": database.cluster_endpoint.hostname
                },
                secrets={
                    "DB_CREDENTIALS": ecs.Secret.from_secrets_manager(database_credentials)
                }
            ),
            platform_version=ecs.FargatePlatformVersion.VERSION1_4
        )

        # GuardDuty
        guardduty.Detector(
            self, "GuardDutyDetector",
            enable_kubernetes=True,
            enable_container=True
        )

        # Backup
        backup_vault = backup.BackupVault(
            self, "BackupVault",
            encryption_key=kms.Key(
                self, "BackupKey",
                enable_key_rotation=True
            )
        )

        backup_plan = backup.BackupPlan(
            self, "BackupPlan",
            backup_vault=backup_vault
        )

        backup_plan.add_selection("BackupSelection",
            resources=[
                backup.BackupResource.from_ecs_service(fargate_service.service),
                backup.BackupResource.from_rds_cluster(database)
            ]
        )

        # Add tags
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("SecurityZone", "Protected")
        Tags.of(self).add("DataSensitivity", "High")

        # Outputs
        CfnOutput(
            self, "LoadBalancerDNS",
            value=alb.load_balancer_dns_name
        )
