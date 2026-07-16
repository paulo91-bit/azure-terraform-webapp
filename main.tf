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

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
}

resource "azurerm_storage_account" "storage" {
  name                     = "st${var.project_name}${var.environment}${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "app_plan" {
  name                = "asp-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1" 
}

resource "azurerm_linux_web_app" "frontend" {
  name                = "app-frontend-${var.project_name}-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.app_plan.location
  service_plan_id     = azurerm_service_plan.app_plan.id
  site_config { always_on = true }
}

resource "azurerm_linux_web_app" "backend" {
  name                = "app-backend-${var.project_name}-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.app_plan.location
  service_plan_id     = azurerm_service_plan.app_plan.id
  
  site_config { always_on = true }

  # This gives your Web App a System Assigned Identity (its "ID Card")
  identity {
    type = "SystemAssigned"
  }

  # Inject environment variables into the running container
  app_settings = {
    "DB_HOST"      = azurerm_postgresql_flexible_server.postgres_server.fqdn
    "DB_DATABASE"  = azurerm_postgresql_flexible_server_database.postgres_db.name
    "DB_USERNAME"  = azurerm_postgresql_flexible_server.postgres_server.administrator_login
    
    # --- TEMPORARILY HIDDEN FOR STEP 1 ---
     "DATABASE_URL" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.backend_db_url.versionless_id})"
  }
}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-${var.environment}-${random_string.unique.result}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"

  # This policy gives YOU (the deployment user/pipeline) permission to create secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
  }
}

# --- TEMPORARILY HIDDEN FOR STEP 1 ---

resource "azurerm_key_vault_access_policy" "backend_app_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id 
  object_id    = azurerm_linux_web_app.backend.identity[0].principal_id

  secret_permissions = ["Get"] 
}


# Your existing raw password secret
resource "azurerm_key_vault_secret" "db_password_secret" {
  name         = "sql-admin-password"
  value        = random_password.db_password.result
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv] 
}

# Store the fully constructed PostgreSQL URL
resource "azurerm_key_vault_secret" "backend_db_url" {
  name         = "backend-database-url"
  key_vault_id = azurerm_key_vault.kv.id
  
  value = "postgresql://${azurerm_postgresql_flexible_server.postgres_server.administrator_login}:${random_password.db_password.result}@${azurerm_postgresql_flexible_server.postgres_server.fqdn}:5432/${azurerm_postgresql_flexible_server_database.postgres_db.name}"
  
  depends_on = [azurerm_key_vault.kv] 
}

# 11. Azure PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "postgres_server" {
  name                   = "pg-${var.project_name}-${var.environment}-${random_string.unique.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "14"
  administrator_login    = "pgadmin"
  administrator_password = random_password.db_password.result
  zone                   = "1"
  storage_mb             = 32768 # 32 GB is the minimum for Flexible Server
  sku_name               = "B_Standard_B1ms" # Burstable paid tier
}

# 12. PostgreSQL Database inside the server
resource "azurerm_postgresql_flexible_server_database" "postgres_db" {
  name      = "db-${var.project_name}-${var.environment}"
  server_id = azurerm_postgresql_flexible_server.postgres_server.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# 13. Firewall Rule: Allow your Azure Web Apps to talk to the database
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureIPs"
  server_id        = azurerm_postgresql_flexible_server.postgres_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}