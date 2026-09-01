# ============================================================================
# environments/lab — outputs
# ============================================================================

output "fleet_instance_names" {
  value = module.fleet.instance_names
}

output "fleet_instance_ids" {
  value = module.fleet.instance_ids
}

output "fleet_fixed_ips" {
  value = module.fleet.fixed_ips
}

output "fleet_security_group" {
  value = module.security.security_group_name
}

output "internal_network_id" {
  value = module.network.network_id
}

output "internal_subnet_id" {
  value = module.network.subnet_id
}
