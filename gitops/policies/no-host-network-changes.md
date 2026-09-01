# Policy: No Host Network Changes

## Rule

The lab never modifies the physical host's network configuration. This includes:

- `enp4s0` (or whatever the host's primary NIC is)
- NetworkManager / netplan configuration
- Host routes, DNS, firewall (outside libvirt NAT)
- Bridges on the physical NIC

## Why

The host is a shared development machine. A bad bridge or route change can
sever the operator's access and require console recovery.

## Enforcement

- All lab networking uses the existing libvirt NAT (`virbr0`, 192.168.122.0/24)
- Guest-internal changes (OVS bridges inside the VM) are allowed — they are lab scope
- CI rejects commits that touch host network tooling outside `lib/` lab scope
- The one permitted host-side artifact: the `/etc/hosts` entry for `openstack-lab-01`

## Violations

Any commit attempting to modify host network config outside the lab VM is
rejected. Operators must never run commands like `ip route add` on the host.
