module "locations" {
  source   = "azurerm/locations/azure"
  version  = "0.2.10"
  location = var.location
}

resource "azurerm_resource_group" "this" {
  name     = "rg-netperf-tst-${module.locations.short_name}-001"
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-netperf-tst-${module.locations.short_name}-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.200.0.0/24"]
}

resource "azurerm_subnet" "this" {
  name                 = "snet-netperf-tst-${module.locations.short_name}-001"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.200.0.0/25"]
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-netperf-tst-${module.locations.short_name}-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowQperfIntraVnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "19765-19766"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowIperf3IntraVnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "5201"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowPrivateEndpointHttpsIntraVnet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_network_interface" "server" {
  count                          = 3
  name                           = "lx-srv-${module.locations.short_name}-az${count.index + 1}-nic"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.this.name
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "server" {
  count                 = 3
  name                  = "lx-srv-${module.locations.short_name}-az${count.index + 1}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = var.size
  zone                  = lookup(local.locationMappings[var.location], "az${count.index + 1}")
  network_interface_ids = [azurerm_network_interface.server[count.index].id]
  admin_username        = "azureuser"
  priority              = "Spot"
  eviction_policy       = "Deallocate"
  max_bid_price         = -1
  custom_data           = base64encode(file("${path.module}/cloud-init-server.txt"))

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    name                 = "lx-srv-${module.locations.short_name}-az${count.index + 1}-dsk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    "logical-zone"  = lookup(local.locationMappings[var.location], "az${count.index + 1}")
    "physical-zone" = "az${count.index + 1}"
  }

  depends_on = [azurerm_subnet_network_security_group_association.this]
}

resource "azurerm_network_interface" "client" {
  for_each                       = toset(["az1", "az2", "az3"])
  name                           = "lx-cli-${module.locations.short_name}-${each.key}-nic"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.this.name
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "client_1" {
  name                  = "lx-cli-${module.locations.short_name}-az1"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = var.size
  zone                  = lookup(local.locationMappings[var.location], "az1")
  network_interface_ids = [azurerm_network_interface.client["az1"].id]
  admin_username        = "azureuser"
  priority              = "Spot"
  eviction_policy       = "Deallocate"
  max_bid_price         = -1
  custom_data           = local.client_cloud_init

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    name                 = "lx-cli-${module.locations.short_name}-az1-dsk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    "logical-zone"  = lookup(local.locationMappings[var.location], "az1")
    "physical-zone" = "az1"
  }

  depends_on = [
    azurerm_linux_virtual_machine.server,
    azurerm_subnet_network_security_group_association.this,
    azurerm_private_endpoint.this,
    azurerm_private_dns_zone_virtual_network_link.this,
    azurerm_role_assignment.this
  ]
}

resource "time_sleep" "wait_client_2" {
  create_duration = "60s"
  depends_on      = [azurerm_linux_virtual_machine.client_1]
}

resource "azurerm_linux_virtual_machine" "client_2" {
  name                  = "lx-cli-${module.locations.short_name}-az2"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = var.size
  zone                  = lookup(local.locationMappings[var.location], "az2")
  network_interface_ids = [azurerm_network_interface.client["az2"].id]
  admin_username        = "azureuser"
  priority              = "Spot"
  eviction_policy       = "Deallocate"
  max_bid_price         = -1
  custom_data           = local.client_cloud_init

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    name                 = "lx-cli-${module.locations.short_name}-az2-dsk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    "logical-zone"  = lookup(local.locationMappings[var.location], "az2")
    "physical-zone" = "az2"
  }

  depends_on = [time_sleep.wait_client_2]
}

resource "time_sleep" "wait_client_3" {
  create_duration = "60s"
  depends_on      = [azurerm_linux_virtual_machine.client_2]
}

resource "azurerm_linux_virtual_machine" "client_3" {
  name                  = "lx-cli-${module.locations.short_name}-az3"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = var.size
  zone                  = lookup(local.locationMappings[var.location], "az3")
  network_interface_ids = [azurerm_network_interface.client["az3"].id]
  admin_username        = "azureuser"
  priority              = "Spot"
  eviction_policy       = "Deallocate"
  max_bid_price         = -1
  custom_data           = local.client_cloud_init

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    name                 = "lx-cli-${module.locations.short_name}-az3-dsk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    "logical-zone"  = lookup(local.locationMappings[var.location], "az3")
    "physical-zone" = "az3"
  }

  depends_on = [time_sleep.wait_client_3]
}

resource "azurerm_user_assigned_identity" "this" {
  location            = var.location
  name                = "mi-net-tst-${module.locations.short_name}-001"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_role_assignment" "this" {
  scope                = data.azurerm_storage_account.this.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_private_endpoint" "this" {
  name                = "${data.azurerm_storage_account.this.name}-${module.locations.short_name}-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.this.id

  private_service_connection {
    name                           = "${data.azurerm_storage_account.this.name}-${module.locations.short_name}-psc"
    private_connection_resource_id = data.azurerm_storage_account.this.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "terraform-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.this.id]
  }
}

resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                = "${module.locations.short_name}-link"
  private_dns_zone_id = azurerm_private_dns_zone.this.id
  virtual_network_id  = azurerm_virtual_network.this.id
}