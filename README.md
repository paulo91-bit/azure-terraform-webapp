# Azure Terraform Web App Infrastructure

A production-grade Terraform configuration to provision a secure, three-tier web application architecture on Microsoft Azure. 

This project automates the deployment of a frontend web app, a backend web app, and a PostgreSQL database. It implements enterprise security best practices by utilizing Azure Key Vault and Managed Identities to ensure no passwords or connection strings are ever hardcoded or exposed.

## 🏗️ Architecture & Resources

This Terraform configuration deploys the following Azure resources:

* **Resource Group:** Logical container for all infrastructure components.
* **Storage Account:** Standard LRS storage for application data and future remote state locking.
* **App Service Plan:** Linux compute resources (B1 tier) for hosting the web apps.
* **Frontend Web App:** Azure Linux Web App configured for 24/7 availability.
* **Backend Web App:** Azure Linux Web App with a **System Assigned Managed Identity**.
* **PostgreSQL Flexible Server:** Fully managed relational database (B_Standard_B1ms, Version 14) with customized firewall rules to allow Azure internal traffic.
* **Azure Key Vault:** Centralized secret management. Stores the randomly generated PostgreSQL admin password and the fully constructed database connection string.

## 🔒 Security Highlights

* **Zero-Touch Secrets:** Database passwords are dynamically generated using Terraform's `random_password` provider and immediately injected into Azure Key Vault.
* **Managed Identity:** The Backend Web App authenticates to the Key Vault using Azure Active Directory (System Assigned Identity) rather than using API keys or passwords.
* **Key Vault References:** The backend application accesses its database connection string securely at runtime via `@Microsoft.KeyVault()` environment variable references.

## 📋 Prerequisites

To deploy this infrastructure locally, you will need:
1. [Terraform](https://www.terraform.io/downloads) installed (v1.0+).
2. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed.
3. An active Azure Subscription.

## 🚀 Deployment Instructions (Local)

1. **Authenticate with Azure:**
   ```bash
   az login
