output "resource_group_name" {
  description = "The name of the resource group where the resources are deployed."
  value       = values(module.netperf)[0].resource_group_name
}

output "deployed_benchmarks" {
  description = "Map of deployed Azure regions to resolved VM SKUs."
  value       = local.benchmarks
}