# ============================================================================
# modules/security — Fleet security group
# ============================================================================
# One security group for all fleet VMs: SSH + ICMP from the lab (and admin)
# plus full egress. Keeps rule count minimal and predictable.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

variable "security_group_name" {
  type    = string
  default = "fleet"
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH to fleet VMs"
  type        = string
  default     = "192.168.122.0/24"
}

variable "icmp_cidr" {
  description = "CIDR allowed to ping fleet VMs (health checks, debugging)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "extra_ingress_tcp_ports" {
  description = "Extra TCP ingress ports open to the lab subnet (e.g. node_exporter 9100)"
  type        = list(number)
  default     = [9100]
}

resource "openstack_networking_secgroup_v2" "fleet" {
  name        = var.security_group_name
  description = "Fleet VMs: SSH from lab, ICMP for health, full egress"
  tags        = ["managed-by-opentofu", "fleet"]
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  security_group_id = openstack_networking_secgroup_v2.fleet.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_cidr
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  security_group_id = openstack_networking_secgroup_v2.fleet.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.icmp_cidr
}

# NOTE: egress (IPv4/IPv6 allow-all) rules are auto-created by Neutron when the
# security group is created. We do NOT define them — doing so causes 409
# SecurityGroupRuleExists on apply.

resource "openstack_networking_secgroup_rule_v2" "extra_tcp" {
  count             = length(var.extra_ingress_tcp_ports)
  security_group_id = openstack_networking_secgroup_v2.fleet.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = var.extra_ingress_tcp_ports[count.index]
  port_range_max    = var.extra_ingress_tcp_ports[count.index]
  remote_ip_prefix  = var.ssh_cidr
}

output "security_group_id" {
  value = openstack_networking_secgroup_v2.fleet.id
}

output "security_group_name" {
  value = openstack_networking_secgroup_v2.fleet.name
}
