# SAFETY.md — Non-Negotiable Lab Safety Rules

These rules exist to protect the physical host and the working OpenStack deployment. Violating them can destroy the host network, delete unrelated VMs, or break a deployment that took hours to build.

## The Physical Host Is Off-Limits

NEVER:

- Modify the physical host's primary network configuration (`enp4s0`, NetworkManager, netplan)
- Create a bridge on the physical NIC
- Alter host routes or DNS outside the lab scope
- Modify libvirt networks other than the lab `default` NAT network
- Modify libvirt storage pools other than the lab `homelab` pool
- Touch VMs other than `openstack-lab-01` (libvirt domain) and lab fleet instances
- Automatically destroy the OpenStack VM

All lab networking stays behind the existing KVM/libvirt NAT design (`virbr0`, 192.168.122.0/24).

## Destruction Is Never Automatic

- `tofu destroy` requires explicit typed user confirmation
- `./openstack-lab.zsh destroy` requires `AUTO_APPROVE_DESTROY=true` in `config/lab.conf` **plus** interactive confirmation
- CI never runs destroy. CI validates only (fmt/validate/plan)
- Failed operations STOP and preserve state for diagnosis — no auto-destroy-and-retry

## Reproducibility Over Cleverness

- Idempotency: running any stage twice must be safe
- The lab must be fully rebuildable from Git + `config/lab.conf` (minus secrets)
- Never change working deployment code without a verified defect or explicit request

## Secrets

Git must never contain:

- Passwords, API tokens, private keys
- `terraform.tfvars`, `*.tfstate` (see `tofu/.gitignore`)
- `config/secrets.conf`, `*.pem`, `*.key` (see `.gitignore`)
- Wazuh agent keys, OpenBao credentials (future)

Use `*.example` templates with `CHANGEME` placeholders.

## Config Overwrite Pattern (Kolla COPY_ALWAYS)

Kolla containers copy config from `/etc/kolla/<service>/` into the container at every start. **Never** edit config inside a running container — changes are lost on restart. Always edit `/etc/kolla/<service>/<config>` on the guest, then `docker restart` the container.

## Known Fragile State (must be restored after any host/VM restart)

These items are NOT yet automated by `start-openstack.zsh` and must be checked after restart:

1. `enp2s0` link on the guest: `sudo ip link set enp2s0 up`
2. `veth-mgmt` (Octavia mgmt): `sudo ip link set veth-mgmt up && sudo ip addr add 10.1.0.10/24 dev veth-mgmt`
3. Redis + Sentinel containers (Octavia jobboard): see `OCTAVIA.md`
4. Guest host routes: `10.1.0.0/24` must route via `veth-mgmt` only (delete `enp2s0.100` if it reappears)
