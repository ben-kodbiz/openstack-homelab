# ============================================================================
# main.tf — Provider configuration and data sources
# ============================================================================

# OpenTofu required providers
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
# Provider: connects to OpenStack using environment variables
# Credentials come from: source /etc/kolla/admin-openrc.sh
# Variables: OS_AUTH_URL, OS_USERNAME, OS_PASSWORD, OS_TENANT_NAME, etc.
#
# NOTE: The OpenStack service catalog returns hostnames (openstack-lab-01)
#       which may not resolve from the host. Set /etc/hosts entry:
#       echo "192.168.122.17 openstack-lab-01" | sudo tee -a /etc/hosts
# ----------------------------------------------------------------------------
provider "openstack" {
  auth_url    = var.auth_url
  region      = var.region
  tenant_name = var.project_name
  user_name   = var.username
  password    = var.password
  domain_name = var.domain_name
}

# ----------------------------------------------------------------------------
# Data Sources: fetch existing resources by name/ID
# These reference resources created manually or by Kolla-Ansible
# ----------------------------------------------------------------------------

# External network (provider network created by Kolla)
data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

# External subnet
data "openstack_networking_subnet_v2" "external" {
  name = var.external_subnet_name
}

# Flavor for VMs (created manually or by this config)
data "openstack_compute_flavor_v2" "tiny" {
  name = "m1.tiny"
}

# Uncomment when m1.small exists:
# openstack flavor create m1.small --vcpus 1 --ram 1024 --disk 10
# data "openstack_compute_flavor_v2" "small" {
#   name = "m1.small"
# }

# CirrOS image (uploaded manually)
data "openstack_images_image_v2" "cirros" {
  name        = "cirros"
  most_recent = true
}

# Uncomment when ubuntu-noble exists:
# openstack image create ubuntu-noble --file noble-server-cloudimg-amd64.img --disk-format qcow2 --container-format bare --public
# data "openstack_images_image_v2" "ubuntu" {
#   name        = "ubuntu-noble"
#   most_recent = true
# }
