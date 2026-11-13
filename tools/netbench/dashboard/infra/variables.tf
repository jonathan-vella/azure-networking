variable "subscription_id" {
  description = "Optional Azure subscription ID where dashboard resources will be deployed (defaults to ARM_SUBSCRIPTION_ID when null)"
  type        = string
  default     = null
  nullable    = true
}

variable "environment_name" {
  description = "The name of the azd environment"
  type        = string
}

variable "location" {
  description = "The Azure location where all resources will be deployed"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the existing Azure Storage Account containing benchmark Table Storage data"
  type        = string
}

variable "storage_account_resource_group" {
  description = "Resource group of the existing Azure Storage Account containing benchmark Table Storage data"
  type        = string
}

variable "storage_table_name" {
  description = "Name of the Azure Table Storage table containing performance metrics"
  type        = string
  default     = "perf"
}
