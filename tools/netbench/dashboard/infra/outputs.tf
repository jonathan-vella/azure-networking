output "RESOURCE_GROUP_ID" {
  value = azurerm_resource_group.main.id
}

output "STATIC_WEB_APP_NAME" {
  value = azurerm_static_web_app.main.name
}

output "STATIC_WEB_APP_URL" {
  value = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "FUNCTION_APP_NAME" {
  value = azurerm_linux_function_app.main.name
}

output "FUNCTION_APP_URL" {
  value = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "STORAGE_ACCOUNT_NAME" {
  value = data.azurerm_storage_account.netbench.name
}
