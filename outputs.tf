output "frontend_url" {
  value       = azurerm_linux_web_app.frontend.default_hostname
  description = "The URL for the frontend web app"
}

output "backend_url" {
  value       = azurerm_linux_web_app.backend.default_hostname
  description = "The URL for the backend API"
}


output "database_server_fqdn" {
  value       = azurerm_postgresql_flexible_server.postgres_server.fqdn
  description = "The database connection string address"
}