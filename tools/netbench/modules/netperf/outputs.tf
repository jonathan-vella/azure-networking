output "resource_group_name" {
  description = "The name of the resource group where the resources are deployed."
  value       = azurerm_resource_group.this.name
}