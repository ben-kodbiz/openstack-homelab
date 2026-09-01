# ============================================================================
# security.tf — Security groups and firewall rules
# ============================================================================
#
# Security groups act as virtual firewalls for VMs.
# Each VM gets one or more security groups attached.
#
# Default behavior:
#   - ALL outbound traffic: ALLOWED
#   - ALL inbound traffic: BLOCKED
#
# Common patterns:
#   - Allow SSH from your IP
#   - Allow HTTP/HTTPS from anywhere
#   - Allow ICMP (ping) for debugging

# ----------------------------------------------------------------------------
# Security Group: basic (SSH + ICMP)
# Allows SSH access and ping from anywhere
# ----------------------------------------------------------------------------
resource "openstack_networking_secgroup_v2" "basic" {
  name        = "basic"
  description = "Allow SSH and ICMP (ping)"

  tags = ["managed-by-opentofu"]
}

# Allow SSH (port 22)
resource "openstack_networking_secgroup_rule_v2" "basic_ssh" {
  security_group_id = openstack_networking_secgroup_v2.basic.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.allowed_ssh_cidr  # Restrict to your IP for security
}

# Allow ICMP (ping)
resource "openstack_networking_secgroup_rule_v2" "basic_icmp" {
  security_group_id = openstack_networking_secgroup_v2.basic.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
}

# ----------------------------------------------------------------------------
# Security Group: web-server (SSH + HTTP + HTTPS)
# For web servers that need public access
# ----------------------------------------------------------------------------
resource "openstack_networking_secgroup_v2" "web_server" {
  name        = "web-server"
  description = "Allow SSH, HTTP, HTTPS"

  tags = ["managed-by-opentofu"]
}

resource "openstack_networking_secgroup_rule_v2" "web_ssh" {
  security_group_id = openstack_networking_secgroup_v2.web_server.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.allowed_ssh_cidr
}

resource "openstack_networking_secgroup_rule_v2" "web_http" {
  count             = var.enable_http ? 1 : 0  # Only if enabled
  security_group_id = openstack_networking_secgroup_v2.web_server.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "web_https" {
  count             = var.enable_https ? 1 : 0  # Only if enabled
  security_group_id = openstack_networking_secgroup_v2.web_server.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "web_icmp" {
  security_group_id = openstack_networking_secgroup_v2.web_server.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
}

# ----------------------------------------------------------------------------
# Security Group: db-server (restricted access)
# Only allows MySQL from internal network
# ----------------------------------------------------------------------------
resource "openstack_networking_secgroup_v2" "db_server" {
  name        = "db-server"
  description = "Allow MySQL from internal network only"

  tags = ["managed-by-opentofu"]
}

resource "openstack_networking_secgroup_rule_v2" "db_ssh" {
  security_group_id = openstack_networking_secgroup_v2.db_server.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.allowed_ssh_cidr
}

resource "openstack_networking_secgroup_rule_v2" "db_mysql" {
  security_group_id = openstack_networking_secgroup_v2.db_server.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3306
  port_range_max    = 3306
  remote_ip_prefix  = var.internal_network_cidr  # Only from internal network
}

# ----------------------------------------------------------------------------
# Security Group: open (all traffic — lab only!)
# WARNING: Only use in isolated lab environments
# ----------------------------------------------------------------------------
resource "openstack_networking_secgroup_v2" "open" {
  name        = "open"
  description = "Allow ALL traffic (lab only — NOT for production)"

  tags = ["managed-by-opentofu"]
}

resource "openstack_networking_secgroup_rule_v2" "open_all" {
  security_group_id = openstack_networking_secgroup_v2.open.id
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}
