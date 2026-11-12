locals {
  region_vm_skus  = jsondecode(file("${path.module}/regions.json"))
  resolved_vm_sku = coalesce(var.vm_sku, lookup(local.region_vm_skus, var.location, "Standard_D4als_v5"))

  benchmarks = length(var.benchmark) > 0 ? var.benchmark : {
    (var.location) = local.resolved_vm_sku
  }
}
