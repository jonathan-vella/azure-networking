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
  default     = "sanetprdfrc001"
}

variable "storage_account_resource_group" {
  description = "Resource group of the existing Azure Storage Account containing benchmark Table Storage data"
  type        = string
  default     = "rg-net-prd-frc-001"
}

variable "storage_table_name" {
  description = "Name of the Azure Table Storage table containing performance metrics"
  type        = string
  default     = "perf"
}
