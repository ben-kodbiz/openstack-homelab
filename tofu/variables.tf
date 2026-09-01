# ============================================================================
# variables.tf — Input variables
# ============================================================================

# ----------------------------------------------------------------------------
# Authentication variables
# These match the env vars from: source /etc/kolla/admin-openrc.sh
# ----------------------------------------------------------------------------

variable "auth_url" {
  description = "OpenStack Keystone authentication URL"
  type        = string
  default     = "http://192.168.122.17:5000/v3"
}

variable "region" {
  description = "OpenStack region name"
  type        = string
  default     = "RegionOne"
}

variable "project_name" {
  description = "OpenStack project/tenant name"
  type        = string
  default     = "admin"
}

variable "username" {
  description = "OpenStack username"
  type        = string
  default     = "admin"
}

variable "password" {
  description = "OpenStack password (from passwords.yml)"
  type        = string
  sensitive   = true # Won't show in plan output
}

variable "domain_name" {
  description = "OpenStack domain name"
  type        = string
  default     = "Default"
}

variable "service_host" {
  description = "OpenStack service host IP (used to override service catalog endpoints)"
  type        = string
  default     = "192.168.122.17"
}

# ----------------------------------------------------------------------------
# Network variables
# ----------------------------------------------------------------------------

variable "external_network_name" {
  description = "Name of the external provider network"
  type        = string
  default     = "external-net"
}

variable "external_subnet_name" {
  description = "Name of the external subnet"
  type        = string
  default     = "external-subnet"
}

variable "internal_network_cidr" {
  description = "CIDR block for the internal network"
  type        = string
  default     = "10.0.0.0/24"
}

variable "internal_network_gateway" {
  description = "Gateway IP for the internal network"
  type        = string
  default     = "10.0.0.1"
}

variable "internal_dns" {
  description = "DNS server for internal network"
  type        = string
  default     = "8.8.8.8"
}

# ----------------------------------------------------------------------------
# Compute variables
# ----------------------------------------------------------------------------

variable "keyPair" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "default"
}

variable "ssh_public_key" {
  description = "SSH public key content (for key pair creation)"
  type        = string
  default     = ""
}

variable "image_name" {
  description = "Name of the OS image to use"
  type        = string
  default     = "cirros"
}

variable "flavor_name" {
  description = "Flavor name for VMs"
  type        = string
  default     = "m1.tiny"
}

# ----------------------------------------------------------------------------
# Instance variables
# ----------------------------------------------------------------------------

variable "instance_count" {
  description = "Number of instances to create"
  type        = number
  default     = 1
}

variable "instance_prefix" {
  description = "Prefix for instance names (e.g., 'web' creates web-1, web-2, etc.)"
  type        = string
  default     = "vm"
}

variable "instance_names" {
  description = "Explicit list of instance names (overrides prefix+count)"
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------
# Optional: Floating IP assignment
# ----------------------------------------------------------------------------

variable "assign_floating_ip" {
  description = "Whether to assign a floating IP to instances"
  type        = bool
  default     = false
}

variable "floating_ip_pool" {
  description = "Name of the external network for floating IPs"
  type        = string
  default     = "external-net"
}

# ----------------------------------------------------------------------------
# Security group variables
# ----------------------------------------------------------------------------

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH (default: all)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_http" {
  description = "Allow HTTP traffic (port 80)"
  type        = bool
  default     = false
}

variable "enable_https" {
  description = "Allow HTTPS traffic (port 443)"
  type        = bool
  default     = false
}
