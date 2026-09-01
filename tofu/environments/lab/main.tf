# ============================================================================
# environments/lab — The lab fleet environment (what you actually deploy)
# ============================================================================
# Usage:
#   tofu -chdir=tofu/environments/lab init
#   tofu -chdir=tofu/environments/lab plan
#   tofu -chdir=tofu/environments/lab apply
#
# Credentials: read from OS_* environment variables
# (source the guest admin-openrc.sh or export them here untracked).

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

provider "openstack" {
  # auth from OS_* env vars
}

# ----------------------------------------------------------------------------
# Modules
# ----------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  network_name          = "internal-net"
  subnet_name           = "internal-subnet"
  external_network_name = "external-net"
  create_network        = false # adopt existing deployment networks
}

module "security" {
  source = "../../modules/security"

  security_group_name = "fleet"
  ssh_cidr            = "192.168.122.0/24"
  icmp_cidr           = "0.0.0.0/0"
}

module "fleet" {
  source = "../../modules/fleet"

  fleet_size        = var.fleet_size
  fleet_name_prefix = "fleet"

  network_id         = module.network.network_id
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.security.security_group_id]

  image_name  = var.fleet_image_name
  flavor_name = var.fleet_flavor_name
  disk_gb     = var.fleet_disk_gb
  key_pair    = var.fleet_key_pair

  user_data_template = "${path.module}/../../../fleet/cloud-init/fleet.yaml.tmpl"
  user_data_vars = {
    domain              = var.fleet_domain
    timezone            = var.fleet_timezone
    ssh_public_key      = var.fleet_ssh_public_key
    package_update      = var.fleet_package_update ? "true" : "false"
    packages            = join("\n", [for p in var.fleet_packages : "  - ${p}"])
    install_guest_agent = var.fleet_install_guest_agent ? "true" : "false"
  }

  environment        = "lab"
  assign_floating_ip = false
}
