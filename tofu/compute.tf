# ============================================================================
# compute.tf — Compute: VM instances, key pairs, floating IPs
# ============================================================================
#
# This creates:
#   1. An SSH key pair (or imports existing)
#   2. VM instances on the internal network
#   3. Optional floating IPs for external access

# ----------------------------------------------------------------------------
# SSH Key Pair
# Create a new key pair OR use an existing one
# ----------------------------------------------------------------------------
resource "openstack_compute_keypair_v2" "default" {
  count      = var.ssh_public_key != "" ? 1 : 0  # Only create if key provided
  name       = var.keyPair
  public_key = var.ssh_public_key
}

# Use existing key pair (created manually via CLI)
data "openstack_compute_keypair_v2" "existing" {
  count = var.ssh_public_key == "" ? 1 : 0
  name  = var.keyPair
}

# ----------------------------------------------------------------------------
# User Data — Cloud-init script for VM initialization
# Runs once on first boot
# ----------------------------------------------------------------------------
locals {
  # Default user data: simple setup
  default_user_data = <<-USERDATA
#!/bin/bash
# Update system
apt-get update -qq
apt-get install -y -qq curl wget

# Set hostname
hostnamectl set-hostname ${var.instance_prefix}

# Signal completion
echo "Cloud-init complete" > /tmp/opentofu-ready
USERDATA

  # Key pair name to use
  keypair_name = var.ssh_public_key != "" ? openstack_compute_keypair_v2.default[0].name : data.openstack_compute_keypair_v2.existing[0].name
}

# ----------------------------------------------------------------------------
# VM Ports — explicit ports so FIP association has a stable port_id
# ----------------------------------------------------------------------------
resource "openstack_networking_port_v2" "vm" {
  count = length(var.instance_names) > 0 ? length(var.instance_names) : var.instance_count

  name           = length(var.instance_names) > 0 ? "${var.instance_names[count.index]}-port" : "${var.instance_prefix}-${count.index + 1}-port"
  network_id     = openstack_networking_network_v2.internal.id
  admin_state_up = true

  security_group_ids = [
    openstack_networking_secgroup_v2.basic.id,
  ]

  tags = ["managed-by-opentofu"]
}

# ----------------------------------------------------------------------------
# VM Instances
# Creates one or more identical VMs
# ----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "vm" {
  count = length(var.instance_names) > 0 ? length(var.instance_names) : var.instance_count

  # Instance name: use explicit list or generate from prefix
  name = length(var.instance_names) > 0 ? var.instance_names[count.index] : "${var.instance_prefix}-${count.index + 1}"

  # Flavor (VM sizing)
  flavor_name = var.flavor_name

  # Image (OS)
  image_name = var.image_name

  # Key pair for SSH access
  key_pair = local.keypair_name

  # Network attachment — use explicit port
  network {
    port = openstack_networking_port_v2.vm[count.index].id
  }

  # Cloud-init user data
  user_data = base64encode(local.default_user_data)

  # Metadata (key-value pairs stored with the instance)
  metadata = {
    environment = "lab"
    managed-by  = "opentofu"
    role        = var.instance_prefix
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.cirros.id
    source_type           = "image"
    volume_size           = 2
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  tags = ["managed-by-opentofu"]

  depends_on = [openstack_networking_port_v2.vm]

  # Wait for SSH to be available
  provisioner "remote-exec" {
    inline = ["echo 'SSH ready'"]

    connection {
      type        = "ssh"
      user        = "cirros"  # Default user for CirrOS
      private_key = file("~/.ssh/id_ed25519")
      host        = self.access_ip_v4
      timeout     = "60s"
    }

    # Only provision if we can reach the instance
    # This prevents errors during creation
    on_failure = continue
  }
}

# ----------------------------------------------------------------------------
# Floating IP (optional)
# Assigns an external IP for internet access
# ----------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "vm" {
  count  = var.assign_floating_ip ? (length(var.instance_names) > 0 ? length(var.instance_names) : var.instance_count) : 0
  pool   = var.floating_ip_pool

  tags = ["managed-by-opentofu"]
}

# Associate floating IP with the explicit port (not the auto-created one)
resource "openstack_networking_floatingip_associate_v2" "vm" {
  count       = var.assign_floating_ip ? (length(var.instance_names) > 0 ? length(var.instance_names) : var.instance_count) : 0
  floating_ip = openstack_networking_floatingip_v2.vm[count.index].address
  port_id     = openstack_networking_port_v2.vm[count.index].id

  depends_on = [openstack_compute_instance_v2.vm]
}

# ----------------------------------------------------------------------------
# Example: Named instances with specific roles
# Uncomment and modify as needed
# ----------------------------------------------------------------------------

# # Web server
# resource "openstack_compute_instance_v2" "web" {
#   name        = "web-1"
#   flavor_name = "m1.small"
#   image_name  = "ubuntu-noble"
#   key_pair    = local.keypair_name
#
#   network {
#     name = openstack_networking_network_v2.internal.name
#   }
#
#   security_groups = [
#     openstack_networking_secgroup_v2.web_server.name,
#   ]
#
#   metadata = {
#     role = "web"
#   }
# }
#
# # Database server
# resource "openstack_compute_instance_v2" "db" {
#   name        = "db-1"
#   flavor_name = "m1.medium"
#   image_name  = "ubuntu-noble"
#   key_pair    = local.keypair_name
#
#   network {
#     name = openstack_networking_network_v2.internal.name
#   }
#
#   security_groups = [
#     openstack_networking_secgroup_v2.db_server.name,
#   ]
#
#   metadata = {
#     role = "database"
#   }
# }
