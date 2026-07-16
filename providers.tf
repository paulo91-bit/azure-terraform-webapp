terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # ADD THIS NEW BLOCK:
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstate26" # Update this!
    container_name       = "tfstate"
    key                  = "demo.terraform.tfstate"  # The name of the file it will save in Azure
  }
}

provider "azurerm" {
  features {
    # ... your existing features block ...
  }
}

data "azurerm_client_config" "current" {}