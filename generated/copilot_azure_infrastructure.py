from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.applicationgateway import ApplicationGatewayManagementClient
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.rdbms.mysql_flexibleservers import MySQLManagementClient

# Azure credentials and configuration
subscription_id = "your_subscription_id"
resource_group_name = "web-app-rg"
location = "eastus"
vnet_name = "web-app-vnet"
subnet_names = ["public-subnet", "private-subnet", "db-subnet"]
application_gateway_name = "web-app-gateway"
aks_cluster_name = "web-app-aks"
mysql_server_name = "web-app-db"

# Authenticate with Azure
credential = DefaultAzureCredential()

# Resource Management Client
resource_client = ResourceManagementClient(credential, subscription_id)

# 1. Create Resource Group
resource_client.resource_groups.create_or_update(
    resource_group_name,
    {"location": location}
)

# Network Management Client
network_client = NetworkManagementClient(credential, subscription_id)

# 2. Create Virtual Network and Subnets
vnet_params = {
    "location": location,
    "address_space": {"address_prefixes": ["10.0.0.0/16"]}
}
vnet = network_client.virtual_networks.begin_create_or_update(
    resource_group_name, vnet_name, vnet_params).result()

subnet_addresses = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
subnets = {}
for i, subnet_name in enumerate(subnet_names):
    subnet = network_client.subnets.begin_create_or_update(
        resource_group_name,
        vnet_name,
        subnet_name,
        {"address_prefix": subnet_addresses[i]}
    ).result()
    subnets[subnet_name] = subnet

# Application Gateway Management Client
application_gateway_client = ApplicationGatewayManagementClient(credential, subscription_id)

# 3. Create Public IP for Application Gateway
public_ip_params = {
    "location": location,
    "sku": {"name": "Standard"},
    "public_ip_allocation_method": "Static"
}
public_ip = network_client.public_ip_addresses.begin_create_or_update(
    resource_group_name, "web-app-public-ip", public_ip_params).result()

# 4. Create Application Gateway
app_gateway_params = {
    "location": location,
    "sku": {"name": "Standard_v2", "tier": "Standard_v2", "capacity": 2},
    "gateway_ip_configurations": [{
        "name": "appgateway-ipconfig",
        "subnet": {"id": subnets["public-subnet"].id}
    }],
    "frontend_ip_configurations": [{
        "name": "frontend-ip",
        "public_ip_address": {"id": public_ip.id}
    }],
    "frontend_ports": [{"name": "http-port", "port": 80},
                       {"name": "https-port", "port": 443}],
    "backend_address_pools": [{"name": "backend-pool"}],
    "http_listeners": [{
        "name": "http-listener",
        "frontend_ip_configuration": {"id": "frontend-ip"},
        "frontend_port": {"id": "http-port"},
        "protocol": "Http"
    }],
    "ssl_certificates": [{
        "name": "appgateway-ssl-cert",
        "data": "<base64_encoded_cert_data>",
        "password": "your_ssl_password"
    }]
}
application_gateway = application_gateway_client.application_gateways.begin_create_or_update(
    resource_group_name, application_gateway_name, app_gateway_params).result()

# Container Service Client
container_service_client = ContainerServiceClient(credential, subscription_id)

# 5. Create AKS Cluster
aks_params = {
    "location": location,
    "dns_prefix": "webappdns",
    "agent_pool_profiles": [{
        "name": "default",
        "count": 2,
        "vm_size": "Standard_DS2_v2"
    }],
    "service_principal_profile": {
        "client_id": "your_client_id",
        "secret": "your_client_secret"
    },
    "network_profile": {
        "network_plugin": "azure",
        "service_cidr": "10.1.0.0/16",
        "dns_service_ip": "10.1.0.10",
        "docker_bridge_cidr": "172.17.0.1/16"
    }
}
aks_cluster = container_service_client.managed_clusters.begin_create_or_update(
    resource_group_name, aks_cluster_name, aks_params).result()

# MySQL Flexible Server Client
mysql_client = MySQLManagementClient(credential, subscription_id)

# 6. Create Azure Database for MySQL
mysql_params = {
    "location": location,
    "administrator_login": "db_admin",
    "administrator_login_password": "your_secure_password",
    "sku": {"name": "Standard_D2s_v3"},
    "storage": {"storage_mb": 51200},
    "version": "8.0",
    "backup": {"backup_retention_days": 7, "geo_redundant_backup": "Enabled"},
    "network": {"delegated_subnet_resource_id": subnets["db-subnet"].id}
}
mysql_server = mysql_client.servers.begin_create(
    resource_group_name, mysql_server_name, mysql_params).result()

print("Azure Infrastructure Deployed Successfully!")