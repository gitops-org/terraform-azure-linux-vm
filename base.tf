# Microsoft Azure Provider
provider "azurerm" {
  # If using a service principal, fill in details here
}

variable "ssh_key" {
  type = "string"
}

variable "admin_username" {
  type    = "string"
  default = "azureuser"
}

variable "prefix" {
  default = "paas"
}

variable "ssh_port" {
  default = "22"
}

variable "location" {
  default = "Central US"
}

variable "standard_vm_size" {
  default = "Standard_B1s"
}

variable "storage_type" {
  default = "Premium_LRS"
}

locals {
  resource_group_name = "${var.prefix}-rg"

  tags = {
    environment = "production"
    serviceType = "compute"
    solution    = "${var.prefix}"
  }

  vnet_name             = "${var.prefix}-vnet"
  vnet_address_space    = "10.0.0.0/16"
  subnet_name           = "default"
  subnet_address_prefix = "10.0.0.0/24"
}

# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "${local.resource_group_name}"
  location = "${var.location}"
  tags     = "${merge(local.tags, map("ProvisionedVia", "Terraform"))}"
}

# Networking
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.vnet_name}"
  location            = "${azurerm_resource_group.rg.location}"
  address_space       = ["${local.vnet_address_space}"]
  resource_group_name = "${azurerm_resource_group.rg.name}"
  tags                = "${local.tags}"
}

resource "azurerm_subnet" "default" {
  name                 = "${local.subnet_name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  address_prefix       = "${local.subnet_address_prefix}"
}

# Generate random text for a unique storage account name
resource "random_id" "pseudo" {
  keepers = {
    resource_group = "${azurerm_resource_group.rg.name}"
    location       = "${azurerm_resource_group.rg.location}"
  }

  byte_length = 4
}

resource "azurerm_storage_account" "diagnostics" {
  name                     = "${var.prefix}diag${random_id.pseudo.hex}"
  location                 = "${azurerm_resource_group.rg.location}"
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  account_replication_type = "LRS"
  account_tier             = "Standard"
  tags                     = "${local.tags}"
}

resource "azurerm_availability_set" "machines" {
  name                = "${var.prefix}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  managed             = true
  tags                = "${local.tags}"
}

module "linux" {
  source = "./linux"

  name                = "${var.prefix}"
  vm_size             = "${var.standard_vm_size}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  admin_username      = "${var.admin_username}"
  ssh_key             = "${var.ssh_key}"

  // this is something that annoys me - passing the resource would be nicer
  diag_storage_name                  = "${azurerm_storage_account.diagnostics.name}"
  diag_storage_primary_blob_endpoint = "${azurerm_storage_account.diagnostics.primary_blob_endpoint}"
  diag_storage_primary_access_key    = "${azurerm_storage_account.diagnostics.primary_access_key}"
  availability_set_id                = "${azurerm_availability_set.machines.id}"
  subnet_id                          = "${azurerm_subnet.default.id}"
  storage_type                       = "${var.storage_type}"
  tags                               = "${local.tags}"
  cloud_init                         = ""
}
