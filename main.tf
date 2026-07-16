# 1. Random Generators for unique naming & passwords
resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 2. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
}

# 3. Network Infrastructure (VNet, Subnets & Private DNS)
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.project_name}-${var.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "app_subnet" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "app-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "db_subnet" {
  name                 = "snet-db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "db-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres_dns" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_vnet_link" {
  name                  = "postgres-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

# 4. Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "st${var.project_name}${var.environment}${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# 5. App Service Plan (Upgraded to B2)
resource "azurerm_service_plan" "app_plan" {
  name                = "asp-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B2" # Upgraded production/test tier SKU
}

# 6. Frontend Linux Web App
resource "azurerm_linux_web_app" "frontend" {
  name                = "app-frontend-${var.project_name}-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.app_plan.location
  service_plan_id     = azurerm_service_plan.app_plan.id
  site_config { always_on = true }
}

# 7. Backend Linux Web App (With VNet Integration & Managed Identity)
resource "azurerm_linux_web_app" "backend" {
  name                      = "app-backend-${var.project_name}-${random_string.unique.result}"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_service_plan.app_plan.location
  service_plan_id           = azurerm_service_plan.app_plan.id
  virtual_network_subnet_id = azurerm_subnet.app_subnet.id

  site_config { always_on = true }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "DB_HOST"      = azurerm_postgresql_flexible_server.postgres_server.fqdn
    "DB_DATABASE"  = azurerm_postgresql_flexible_server_database.postgres_db.name
    "DB_USERNAME"  = azurerm_postgresql_flexible_server.postgres_server.administrator_login
    "DATABASE_URL" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.backend_db_url.versionless_id})"
  }
}

# 8. Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = "kv-${var.environment}-${random_string.unique.result}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
  }
}

# 9. Key Vault Access Policy for Backend App Identity
resource "azurerm_key_vault_access_policy" "backend_app_policy" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.current.tenant_id 
  object_id          = azurerm_linux_web_app.backend.identity[0].principal_id
  secret_permissions = ["Get"] 
}

# 10. Key Vault Secrets
resource "azurerm_key_vault_secret" "db_password_secret" {
  name         = "sql-admin-password"
  value        = random_password.db_password.result
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv] 
}

resource "azurerm_key_vault_secret" "backend_db_url" {
  name         = "backend-database-url"
  key_vault_id = azurerm_key_vault.kv.id
  value        = "postgresql://${azurerm_postgresql_flexible_server.postgres_server.administrator_login}:${random_password.db_password.result}@${azurerm_postgresql_flexible_server.postgres_server.fqdn}:5432/${azurerm_postgresql_flexible_server_database.postgres_db.name}"
  depends_on   = [azurerm_key_vault.kv] 
}

# 11. Azure PostgreSQL Flexible Server (Private VNet Injected)
resource "azurerm_postgresql_flexible_server" "postgres_server" {
  name                   = "pg-${var.project_name}-${var.environment}-${random_string.unique.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "14"
  administrator_login    = "pgadmin"
  administrator_password = random_password.db_password.result
  zone                   = "1"
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  
  delegated_subnet_id    = azurerm_subnet.db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres_dns.id

  # Completely disables public endpoint to resolve API conflicts with VNets
  public_network_access_enabled = false

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres_vnet_link]
}

# 12. PostgreSQL Private Database
resource "azurerm_postgresql_flexible_server_database" "postgres_db" {
  name      = "db-${var.project_name}-${var.environment}"
  server_id = azurerm_postgresql_flexible_server.postgres_server.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}