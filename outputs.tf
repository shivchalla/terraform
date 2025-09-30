# Outputs for the generated keys and VM IP
output "vm1_private_key" {
  value     = tls_private_key.vm1.private_key_pem
  sensitive = true  # Keep private
}

output "vm1_public_key" {
  value = tls_private_key.vm1.public_key_openssh
}

output "vm1_public_ip" {
  value = azurerm_public_ip.main.ip_address
}
terraform {
  backend "azurerm" {
    resource_group_name   = "rg-shivblog-dev"               # Replace with your RG name
    storage_account_name  = ""                # Replace with your storage account name
    container_name        = "tfstate"               # Must be created beforehand
    key                   = "terraform.tfstate"     # Name of the state file
  }
}