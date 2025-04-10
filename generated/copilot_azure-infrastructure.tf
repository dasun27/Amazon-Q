# Configure the Azure Provider
provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "web-app-rg"
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "web-app-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnets
resource "azurerm_subnet" "public_subnet" {
  name                 = "public-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private_subnet" {
  name                 = "private-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "db_subnet" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "public_ip" {
  name                = "web-app-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Application Gateway
resource "azurerm_application_gateway" "app_gateway" {
  name                = "web-app-gateway"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgateway-ipconfig"
    subnet_id = azurerm_subnet.public_subnet.id
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  backend_address_pool {
    name = "backend-pool"
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "https-port"
    protocol                       = "Https"
    ssl_certificate_name           = "appgateway-ssl-cert"
  }

  ssl_certificate {
    name     = "appgateway-ssl-cert"
    data     = filebase64("${path.module}/certs/certificate.pfx")
    password = var.ssl_password
  }

  request_routing_rule {
    name                       = "http-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "backend-http-settings"
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 20
  }
}

# Azure Kubernetes Service (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "web-app-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "webappdns"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }
}

# Azure Database for MySQL
resource "azurerm_mysql_flexible_server" "mysql" {
  name                = "web-app-db"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  administrator_login = var.db_username
  administrator_password = var.db_password
  sku_name            = "Standard_D2s_v3"

  storage_mb = 51200
  version    = "8.0"
  zone       = "1"

  backup {
    retention_days = 7
    geo_redundant  = "Enabled"
  }

  network {
    delegated_subnet_id = azurerm_subnet.db_subnet.id
  }
}

# Output Public IP of Application Gateway
output "app_gateway_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}