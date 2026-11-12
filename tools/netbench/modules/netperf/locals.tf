locals {
  availabilityZoneMappings = jsondecode(file("${path.module}/../../availabilityZoneMappings.json"))

  locationMappings = {
    for location in local.availabilityZoneMappings :
    location.name => {
      for mapping in location.availabilityZoneMappings :
      split("-", mapping.physicalZone)[1] => mapping.logicalZone
    }
  }

  client_cloud_init = base64encode(templatefile("${path.module}/cloud-init-client.txt", {
    storage_account_name       = var.storage_account_name
    storage_table_name         = var.storage_table_name
    managed_identity_client_id = azurerm_user_assigned_identity.this.client_id
  }))
}
