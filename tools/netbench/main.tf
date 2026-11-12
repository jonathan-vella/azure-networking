module "netperf" {
  source                         = "./modules/netperf"
  for_each                       = local.benchmarks
  location                       = each.key
  size                           = each.value
  storage_account_resource_group = var.storage_account_resource_group
  storage_account_name           = var.storage_account_name
  storage_table_name             = var.storage_table_name
}
