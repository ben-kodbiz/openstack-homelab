# ============================================================================
# network.tf — Networking: networks, subnets, routers
# ============================================================================
#
# This creates:
#   1. An internal network for VMs
#   2. A subnet with DHCP
#   3. A router connecting internal ↔ external
#
# Network topology:
#
#   External (192.168.122.0/24)    Internal (10.0.0.0/24)
#   ┌─────────────────────┐       ┌─────────────────────┐
#   │ external-net        │       │ internal-net         │
#   │ (flat, provider)    │◄─RT──►│ (VXLAN overlay)      │
#   │                     │       │                      │
#   │ VMs get floating    │       │ VMs get fixed IPs    │
#   │ IPs from this pool  │       │ via DHCP             │
#   └─────────────────────┘       └─────────────────────┘

# ----------------------------------------------------------------------------
# Internal Network
# VXLAN overlay network for VM-to-VM communication
# ----------------------------------------------------------------------------
resource "openstack_networking_network_v2" "internal" {
  name           = var.instance_prefix != "vm" ? "${var.instance_prefix}-net" : "internal-net"
  admin_state_up = true

  tags = ["managed-by-opentofu"]
}

# ----------------------------------------------------------------------------
# Internal Subnet
# Provides DHCP and gateway for VMs
# ----------------------------------------------------------------------------
resource "openstack_networking_subnet_v2" "internal" {
  name       = var.instance_prefix != "vm" ? "${var.instance_prefix}-subnet" : "internal-subnet"
  network_id = openstack_networking_network_v2.internal.id
  cidr       = var.internal_network_cidr
  ip_version = 4

  # DHCP pool range (optional — OpenStack allocates from full CIDR by default)
  allocation_pool {
    start = cidrhost(var.internal_network_cidr, 10)
    end   = cidrhost(var.internal_network_cidr, -2)
  }

  gateway_ip = var.internal_network_gateway
  dns_nameservers = [var.internal_dns]

  tags = ["managed-by-opentofu"]
}

# ----------------------------------------------------------------------------
# Router
# Connects internal network to external network
# Enables floating IP assignment and internet access
# ----------------------------------------------------------------------------
resource "openstack_networking_router_v2" "main" {
  name                = var.instance_prefix != "vm" ? "${var.instance_prefix}-router" : "router1"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id

  tags = ["managed-by-opentofu"]
}

# ----------------------------------------------------------------------------
# Router Interface
# Attaches the internal subnet to the router
# This creates the gateway (10.0.0.1) that VMs use
# ----------------------------------------------------------------------------
resource "openstack_networking_router_interface_v2" "main" {
  router_id = openstack_networking_router_v2.main.id
  subnet_id = openstack_networking_subnet_v2.internal.id
}
