variable "subscription_id" {
  description = "The ID of the Azure subscription where the resources will be created. Defaults to ARM_SUBSCRIPTION_ID when null."
  type        = string
  default     = null
  nullable    = true
}

variable "location" {
  description = "Azure region to benchmark (automatically selects the regional VM SKU from regions.json unless vm_sku is specified)."
  type        = string
  default     = "westeurope"

  validation {
    condition     = contains(keys(jsondecode(file("${path.module}/regions.json"))), var.location) || var.vm_sku != null
    error_message = "Region must exist in regions.json, or vm_sku must be explicitly provided via -var=\"vm_sku=...\"."
  }
}

variable "vm_sku" {
  description = "Optional VM SKU override for var.location. When null, the default SKU for var.location in regions.json is used."
  type        = string
  default     = null
  nullable    = true
}

variable "benchmark" {
  description = "Optional explicit map of Azure region => VM SKU for multi-region runs. When empty, var.location and var.vm_sku (or regions.json) are used."
  type        = map(string)
  default     = {}
}

variable "storage_account_name" {
  description = "The name of the Azure Storage Account hosting the Table Storage benchmark results."
  type        = string
}

variable "storage_account_resource_group" {
  description = "The resource group where the benchmark Storage Account is located."
  type        = string
}

variable "storage_table_name" {
  description = "The Azure Table Storage table name where latency and throughput results are stored."
  type        = string
  default     = "perf"
}
