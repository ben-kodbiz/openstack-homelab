# ============================================================================
# modules/network — Internal network + subnet + router wiring
# ============================================================================
# Adopts existing resources by name (created manually or by the legacy root
# config) OR creates them if absent. The fleet environment must not fight the
# existing deployment: we reference by name and leave ownership untouched.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

variable "network_name" {
  type    = string
  default = "internal-net"
}

variable "subnet_name" {
  type    = string
  default = "internal-subnet"
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "gateway_ip" {
  type    = string
  default = "10.0.0.1"
}

variable "dns_nameservers" {
  type    = list(string)
  default = ["8.8.8.8"]
}

variable "external_network_name" {
  type    = string
  default = "external-net"
}

variable "router_name" {
  type    = string
  default = "router1"
}

variable "create_network" {
  description = "If false, only data sources are used (adopt existing)."
  type        = bool
  default     = false
}

# Existing external provider network (created by Kolla / manual setup)
data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

# Adopt an existing internal network by name, or create it
data "openstack_networking_network_v2" "existing_internal" {
  count = var.create_network ? 0 : 1
  name  = var.network_name
}

data "openstack_networking_subnet_v2" "existing_internal" {
  count = var.create_network ? 0 : 1
  name  = var.subnet_name
}

resource "openstack_networking_network_v2" "internal" {
  count          = var.create_network ? 1 : 0
  name           = var.network_name
  admin_state_up = true
  tags           = ["managed-by-opentofu"]
}

resource "openstack_networking_subnet_v2" "internal" {
  count           = var.create_network ? 1 : 0
  name            = var.subnet_name
  network_id      = openstack_networking_network_v2.internal[0].id
  cidr            = var.cidr
  ip_version      = 4
  gateway_ip      = var.gateway_ip
  dns_nameservers = var.dns_nameservers
  tags            = ["managed-by-opentofu"]
}

locals {
  network_id = var.create_network ? openstack_networking_network_v2.internal[0].id : data.openstack_networking_network_v2.existing_internal[0].id
  subnet_id  = var.create_network ? openstack_networking_subnet_v2.internal[0].id : data.openstack_networking_subnet_v2.existing_internal[0].id
}

# Router is created by the legacy root config (router1). We only reference it
# so the fleet environment never duplicates or destroys tenant routing.
data "openstack_networking_router_v2" "existing" {
  count = var.create_network ? 0 : 1
  name  = var.router_name
}

output "network_id" {
  value = local.network_id
}

output "subnet_id" {
  value = local.subnet_id
}

output "external_network_id" {
  value = data.openstack_networking_network_v2.external.id
}
