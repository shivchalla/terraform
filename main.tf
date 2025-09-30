resource "azurerm_resource_group" "main" {
  name     = "rg-${var.application_name}-${var.environment_name}"
  location = var.primary_location
}

resource "random_string" "suffix" {
  length  = 10
  upper   = false
  special = false
}

resource "azurerm_storage_account" "main" {
  name                     = "st${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.application_name}-${var.environment_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

data "azurerm_client_config" "current" {} #This is usful to avouid hard coding this input variable values 

resource "azurerm_key_vault" "main" {
  name                = "kv-${random_string.suffix.result}" #Key vault must globaly unique all azure subscription
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id #hard code values 
  sku_name            = "standard"
}

resource "azurerm_role_assignment" "terraform_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

#virtuval network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.application_name}-${var.environment_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.39.0.0/22"]
}

# locals are used to define local values – basically variables you can reuse in your configuration
locals {
  subnets = {
    alpha = "10.39.0.0/24"
    beta  = "10.39.1.0/24"
    gamma = "10.39.2.0/24"
    delta = "10.39.3.0/24"
  }
}

# 4 subnets at once in a single resource block using for_each

resource "azurerm_subnet" "subnets" {
  for_each             = local.subnets
  name                 = "subnet-${each.key}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value] #each.value = CIDR block (Classless Inter-Domain Routing)
}

#creat network security group
# Create Network Security Group with inline rule (only works in older provider versions!)
resource "azurerm_network_security_group" "remote_access" {
  name                = "nsg-${var.application_name}-${var.environment_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with alpha subnet
resource "azurerm_subnet_network_security_group_association" "alpha_remote_access" {
  subnet_id                 = azurerm_subnet.subnets["alpha"].id
  network_security_group_id = azurerm_network_security_group.remote_access.id
}

#Public- IP
resource "azurerm_public_ip" "main" {
  name                = "pip-${var.application_name}-${var.environment_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
}

#creat NIC- Network interface Card
resource "azurerm_network_interface" "vm1" {
  name                = "nic-${var.application_name}-${var.environment_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "public"
    subnet_id                     = azurerm_subnet.subnets["alpha"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Generate TLS Private Key (RSA 4096 bits)
resource "tls_private_key" "vm1" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key locally
resource "local_file" "vm1_private_key" {
  filename        = "D:/privatekey/vm1_id_rsa.pem"  # Windows path
  content         = tls_private_key.vm1.private_key_pem
  file_permission = "0600"
}

## Linux VM with SSH key authentication Vertuval meshine linux

resource "azurerm_linux_virtual_machine" "vm1" {
  name                            = "vm1-${var.application_name}-${var.environment_name}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = "Standard_B1s"
  admin_username                  = "adminuser"

  network_interface_ids = [
    azurerm_network_interface.vm1.id,
  ]

admin_ssh_key {
  username   = "adminuser"
  public_key = tls_private_key.vm1.public_key_openssh # Use the generated public key
}

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

