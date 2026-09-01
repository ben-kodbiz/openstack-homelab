# ============================================================================
# outputs.tf — Output values displayed after apply
# ============================================================================
#
# These values are shown after `tofu apply` and can be referenced:
#   tofu output instance_ips
#   tofu output -json  # All outputs as JSON

# ----------------------------------------------------------------------------
# Network outputs
# ----------------------------------------------------------------------------

output "internal_network_id" {
  description = "ID of the internal network"
  value       = openstack_networking_network_v2.internal.id
}

output "internal_network_name" {
  description = "Name of the internal network"
  value       = openstack_networking_network_v2.internal.name
}

output "internal_subnet_id" {
  description = "ID of the internal subnet"
  value       = openstack_networking_subnet_v2.internal.id
}

output "router_id" {
  description = "ID of the router"
  value       = openstack_networking_router_v2.main.id
}

# ----------------------------------------------------------------------------
# Instance outputs
# ----------------------------------------------------------------------------

output "instance_names" {
  description = "Names of created instances"
  value       = openstack_compute_instance_v2.vm[*].name
}

output "instance_ids" {
  description = "IDs of created instances"
  value       = openstack_compute_instance_v2.vm[*].id
}

output "instance_ips" {
  description = "Private IP addresses of instances"
  value       = openstack_compute_instance_v2.vm[*].access_ip_v4
}

output "instance_status" {
  description = "Current status of instances"
  value       = openstack_compute_instance_v2.vm[*].all_metadata
}

# ----------------------------------------------------------------------------
# Floating IP outputs
# ----------------------------------------------------------------------------

output "floating_ips" {
  description = "Floating IP addresses (if enabled)"
  value       = var.assign_floating_ip ? openstack_networking_floatingip_v2.vm[*].address : []
}

# ----------------------------------------------------------------------------
# Connection commands
# ----------------------------------------------------------------------------

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = [
    for i, vm in openstack_compute_instance_v2.vm :
    "ssh cirros@${var.assign_floating_ip ? openstack_networking_floatingip_v2.vm[i].address : vm.access_ip_v4}"
  ]
}

# ----------------------------------------------------------------------------
# Security group IDs
# ----------------------------------------------------------------------------

output "security_groups" {
  description = "Security group names and IDs"
  value = {
    basic = {
      id   = openstack_networking_secgroup_v2.basic.id
      name = openstack_networking_secgroup_v2.basic.name
    }
    web_server = {
      id   = openstack_networking_secgroup_v2.web_server.id
      name = openstack_networking_secgroup_v2.web_server.name
    }
    db_server = {
      id   = openstack_networking_secgroup_v2.db_server.id
      name = openstack_networking_secgroup_v2.db_server.name
    }
  }
}
