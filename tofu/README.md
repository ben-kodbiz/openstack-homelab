# OpenTofu/OpenStack Lab

OpenTofu scripts to manage OpenStack resources (VMs, networks, routers, security groups).

## Prerequisites

- OpenTofu installed: `curl -fsSL https://get.opentofu.org/install.sh | sh`
- OpenStack credentials sourced: `source /etc/kolla/admin-openrc.sh`

## Quick Start

```bash
cd tofu

# Initialize OpenTofu
tofu init

# Plan changes (preview what will be created)
tofu plan

# Apply changes (create resources)
tofu apply

# Destroy all resources
tofu destroy
```

## Files

| File | Description |
|------|-------------|
| `main.tf` | Provider config, variables, outputs |
| `network.tf` | Networks, subnets, routers |
| `security.tf` | Security groups and rules |
| `compute.tf` | VM instances |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |
| `terraform.tfvars` | Your values (not in git) |

## Usage Examples

```bash
# Create only networks
tofu apply -target=module.networking

# Create only VMs
tofu apply -target=module.compute

# Show current state
tofu state list

# Import existing resource
tofu import openstack_networking_network_v2.mynet <network-id>
```
