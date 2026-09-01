# AGENTS.md — OpenStack KVM Lab

## What This Is

Zsh-based idempotent OpenStack lab: Ubuntu 26.04 host → KVM/libvirt VM → Kolla-Ansible → OpenStack 2026.1.

Single entry point: `./openstack-lab.zsh <command>`

## Critical Constraints

- **Zsh only** — not bash. Use `#!/usr/bin/env zsh` everywhere.
- **No host network modification** — never touch `enp4s0`, NetworkManager, or host routes. Use libvirt NAT only.
- **No Vagrant** — libvirt + QEMU + KVM + cloud-init directly.
- **No hard-coded paths or IPs** — everything from `config/lab.conf`. Discover guest IP via `virsh net-dhcp-leases`.
- **Idempotent stages** — check `state/*.ok` markers before running. Skip or repair, never corrupt.
- **No secrets in git** — passwords, SSH keys, tokens stay out of version control.

## Commands

```zsh
./openstack-lab.zsh help          # Show all commands
./openstack-lab.zsh preflight     # Check host readiness (PASS/WARN/FAIL)
./openstack-lab.zsh create-vm     # Create KVM VM with cloud-init
./openstack-lab.zsh wait          # Wait for SSH + cloud-init
./openstack-lab.zsh configure     # Configure guest packages
./openstack-lab.zsh install-kolla # Install Kolla-Ansible in venv
./openstack-lab.zsh generate-config # Generate globals.yml, multinode
./openstack-lab.zsh bootstrap     # Kolla bootstrap
./openstack-lab.zsh deploy        # Kolla deploy
./openstack-lab.zsh verify        # Full smoke test (including VM boot)
./openstack-lab.zsh status        # Show host/VM/Docker/OpenStack state
./openstack-lab.zsh logs          # Show latest logs
./openstack-lab.zsh destroy       # Remove all lab resources
./openstack-lab.zsh rebuild       # destroy → full rebuild
./openstack-lab.zsh build         # Run all stages sequentially
```

## Implementation Order

**Must follow this sequence.** Each phase builds on the previous:

1. Directory structure + `config/lab.conf` + logging + common functions + CLI dispatcher
2. Preflight checks
3. Libvirt VM creation
4. Cloud-init + SSH wait
5. Guest preparation (no OpenStack yet)
6. Kolla-Ansible install in venv
7. Kolla config generation + prechecks
8. Bootstrap
9. Deploy
10. Smoke test (must boot an OpenStack instance)

## Directory Layout

```
config/lab.conf          # Single source of truth for all config
lib/*.zsh                # Shared functions (one per concern)
stages/00-preflight.zsh  # Stage scripts (numbered)
cloud-init/              # user-data, meta-data templates
templates/multinode      # Kolla inventory template
state/                   # *.ok stage markers
logs/                    # Timestamped operation logs
tests/                   # Zsh test scripts
```

## Error Handling

- Every stage: `set -eeuo pipefail`
- Errors print: STAGE, COMMAND, REASON, SUGGESTED ACTION, LOG FILE
- On failure: STOP, collect logs, report. **Never auto-destroy.** Preserve state for diagnosis.
- Max 1 retry per command unless explicitly transient.

## Nova/Libvirt Gotcha

Do NOT assume `/var/lib/nova/instances` is shared between nova-compute and nova-libvirt containers. Verify mounts explicitly. This is the most common deployment failure.

## Octavia LBaaS

For Octavia with the Amphora provider, see `OCTAVIA.md` — it documents 8 specific failures we hit and their fixes (amphora image rebuild, duplicate route, health_manager bind_ip, max_pool_size, security group rules, amp_image_owner_id, COPY_ALWAYS overwrite pattern).

## Testing

Run tests after each phase:
```zsh
# Manual verification
./openstack-lab.zsh preflight
./openstack-lab.zsh status

# Test scripts
zsh tests/test-config.zsh
zsh tests/test-preflight.zsh
```

## Secret Handling

- `passwords.yml`, SSH keys, tokens: never committed
- `.gitignore` must exclude sensitive files
- `config/secrets.conf.example` for reference only

## Development Workflow

Commit after each successful phase for rollback points:
```
01-foundation, 02-vm-working, 03-ssh-working, 04-kolla-installed,
05-kolla-prechecks, 06-bootstrap, 07-openstack-running, 08-smoke-test-passed
```
