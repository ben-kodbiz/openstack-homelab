# ============================================================================
# modules/fleet — N identical Linux VMs via count iteration
# ============================================================================
# fleet-001 … fleet-0NN, each: 1 port (explicit) + 1 instance + cloud-init.
# Scales 1..30+ by changing fleet_size only. No per-VM resource blocks.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

# ----------------------------------------------------------------------------
# Variables
# ----------------------------------------------------------------------------

variable "fleet_name_prefix" {
  type    = string
  default = "fleet"
}

variable "fleet_size" {
  description = "Number of VMs. Supports 1, 5, 10, 20, 30 without module changes."
  type        = number
  default     = 20

  validation {
    condition     = var.fleet_size >= 1 && var.fleet_size <= 30
    error_message = "fleet_size must be between 1 and 30."
  }
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "image_name" {
  type    = string
  default = "cirros"
}

variable "flavor_name" {
  type    = string
  default = "m1.tiny"
}

variable "key_pair" {
  type    = string
  default = "default"
}

variable "disk_gb" {
  description = "Boot volume size in GB"
  type        = number
  default     = 5
}

variable "user_data_template" {
  description = "Path to cloud-init template (templatefile). Optional — falls back to user_data."
  type        = string
  default     = ""
}

variable "user_data_vars" {
  description = "Vars passed to user_data_template. 'hostname' is injected per-VM automatically. All values must be strings."
  type        = map(string)
  default     = {}
}

variable "user_data" {
  description = "Direct cloud-init payload (used when user_data_template is empty)."
  type        = string
  default     = ""
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "assign_floating_ip" {
  description = "Attach a floating IP to every fleet VM (normally false — lab access is via lab network)."
  type        = bool
  default     = false
}

variable "floating_ip_pool" {
  type    = string
  default = "external-net"
}

# ----------------------------------------------------------------------------
# Data: image
# ----------------------------------------------------------------------------
data "openstack_images_image_v2" "fleet_image" {
  name        = var.image_name
  most_recent = true
}

# ----------------------------------------------------------------------------
# Derived values
# ----------------------------------------------------------------------------
locals {
  vm_names = [for i in range(var.fleet_size) : format("%s-%03d", var.fleet_name_prefix, i + 1)]

  # Render cloud-init per instance: template wins, hostname injected per-VM
  user_datas = var.user_data_template != "" ? [
    for name in local.vm_names : templatefile(
      var.user_data_template,
      merge(var.user_data_vars, { hostname = name })
    )
  ] : [for name in local.vm_names : var.user_data != "" ? var.user_data : "#cloud-config\nhostname: ${name}\n"]
}

# ----------------------------------------------------------------------------
# Explicit ports (stable port_id, DHCP fixed addresses from subnet pool)
# ----------------------------------------------------------------------------
resource "openstack_networking_port_v2" "fleet" {
  count              = var.fleet_size
  name               = "${local.vm_names[count.index]}-port"
  network_id         = var.network_id
  admin_state_up     = true
  security_group_ids = var.security_group_ids

  tags = ["managed-by-opentofu", "fleet"]
}

# ----------------------------------------------------------------------------
# Instances
# ----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "fleet" {
  count       = var.fleet_size
  name        = local.vm_names[count.index]
  flavor_name = var.flavor_name
  key_pair    = var.key_pair

  network {
    port = openstack_networking_port_v2.fleet[count.index].id
  }

  user_data = base64encode(local.user_datas[count.index])

  metadata = {
    environment = var.environment
    managed-by  = "opentofu"
    role        = "fleet"
    fleet-index = format("%03d", count.index + 1)
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.fleet_image.id
    source_type           = "image"
    volume_size           = var.disk_gb
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  tags = ["managed-by-opentofu", "fleet"]

  depends_on = [openstack_networking_port_v2.fleet]
}

# ----------------------------------------------------------------------------
# Optional floating IPs
# ----------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "fleet" {
  count = var.assign_floating_ip ? var.fleet_size : 0
  pool  = var.floating_ip_pool
  tags  = ["managed-by-opentofu", "fleet"]
}

resource "openstack_networking_floatingip_associate_v2" "fleet" {
  count       = var.assign_floating_ip ? var.fleet_size : 0
  floating_ip = openstack_networking_floatingip_v2.fleet[count.index].address
  port_id     = openstack_networking_port_v2.fleet[count.index].id

  depends_on = [openstack_compute_instance_v2.fleet]
}

# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------
output "instance_names" {
  value = openstack_compute_instance_v2.fleet[*].name
}

output "instance_ids" {
  value = openstack_compute_instance_v2.fleet[*].id
}

output "fixed_ips" {
  description = "Fixed IP per fleet VM, in fleet order"
  value       = [for addr in openstack_networking_port_v2.fleet[*].all_fixed_ips : addr[0]]
}

output "floating_ips" {
  value = var.assign_floating_ip ? openstack_networking_floatingip_v2.fleet[*].address : []
}
