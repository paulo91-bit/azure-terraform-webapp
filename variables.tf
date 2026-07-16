variable "location" {
  description = "The Azure region to deploy into"
  type        = string
}

variable "environment" {
  description = "The environment name (e.g., dev, prod, demo)"
  type        = string
}

variable "project_name" {
  description = "The base name of the project"
  type        = string
}