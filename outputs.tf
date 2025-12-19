# Outputs for generated SSH keys and VM public IP

output "vm1_private_key" {
  value     = tls_private_key.vm1.private_key_pem
  sensitive = true
}

output "vm1_public_key" {
  value = tls_private_key.vm1.public_key_openssh
}

output "vm1_public_ip" {
  value = azurerm_public_ip.main.ip_address
}
