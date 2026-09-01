# ARCHITECTURE.md — Technical Design

## Layered Responsibility Model

Each layer uses one tool and owns one responsibility. Layers never duplicate each other's work.

```text
┌─────────────────────────────────────────────────────────┐
│ Layer 0: Host / Bootstrap      [Zsh + KVM + cloud-init]  │
│   Prepare host, create control VM, deploy OpenStack      │
├─────────────────────────────────────────────────────────┤
│ Layer 1: Infrastructure        [OpenTofu + OS provider]  │
│   Networks, subnets, routers, SGs, ports, images,       │
│   volumes, instances, fleet sizing                       │
├─────────────────────────────────────────────────────────┤
│ Layer 2: Configuration        [Ansible / AWX — future]  │
│   Users, SSH, packages, baseline, agents, services       │
├─────────────────────────────────────────────────────────┤
│ Layer 3: Inventory / SoT      [NetBox — future]         │
│   Devices, IPAM, roles, environments, metadata          │
├─────────────────────────────────────────────────────────┤
│ Layer 4: Security              [Wazuh — future]          │
│   FIM, vuln visibility, security events, compliance     │
├─────────────────────────────────────────────────────────┤
│ Layer 5: GitOps / CI           [Git + CI scripts]        │
│   Desired-state record + validation gates               │
└─────────────────────────────────────────────────────────┘
```

**Rule:** Zsh does not manage OpenStack tenant resources. OpenTofu does not configure guest OSes. Ansible (future) does not create infrastructure.

## Physical Topology

```text
Physical host (Ubuntu 26.04, Ryzen 5 5600G, 64 GB RAM)
 │
 └─ libvirt NAT (virbr0, 192.168.122.0/24)
     │
     └─ openstack-lab-01 VM (8 vCPU / ~33 GB / 145 GB)
         │
         ├─ enp1s0 → 192.168.122.17  (management: Kolla API, SSH)
         └─ enp2s0 → br-ex (OVS)     (Neutron provider: external-net,
                                       lb-mgmt-net VLAN 100)
```

## OpenStack Tenant Layout

| Network | Type | CIDR / Pool | Purpose |
|---------|------|-------------|---------|
| external-net | flat (physnet1) | 192.168.122.0/24, FIP pool 192.168.122.100–199 | North-south, floating IPs |
| internal-net | VXLAN | 10.0.0.0/24 | Tenant workloads, fleet VMs |
| lb-mgmt-net | VLAN 100 (physnet1) | 10.1.0.0/24, pool .100–.200 | Octavia amphora management |

Routers: `internal-net ↔ external-net` (one tenant router).

## Resource Reality

**Never trust a single free-space number.** Nova's reported disk is not filesystem free space.

| Source | Value (measured) |
|--------|------------------|
| Host NVMe free | ~421 GiB |
| Guest filesystem `/` | 145 GB total, ~90 GB available |
| Nova free_disk_gb | 139 GB (includes overestimate) |
| Nova vCPUs / used | 8 / 2 |
| Nova RAM / used | 33,825 MB / 2,048 MB |

Fleet sizing target: 20 × (1 vCPU, 1 GB RAM, 5 GB disk) = 20 vCPU / 20 GB / 100 GB — fits with RAM held 1:1 (no overcommit) and disk under the ~90 GB filesystem reality (see Capacity section).

## Capacity Policy

- **CPU:** conservative overcommit (target ratio 4:1 → 8 physical cores schedule up to 32 vCPUs; fleet of 20 × 1 vCPU sits well inside this)
- **RAM:** 1:1 — never overcommit initially. Fleet RAM total must stay below free RAM
- **Disk:** fleet virtual disk total must stay below **min(Nova free, filesystem available) − safety margin**

Preflight and `labctl fleet` recompute these dynamically; no hard-coded `MIN_FREE_GB` style assumptions.

## OpenTofu Layout

```text
tofu/
├── environments/lab/     # lab environment root (what you deploy)
├── modules/
│   ├── network/          # network + subnet + router wiring
│   ├── security/         # fleet security groups
│   └── fleet/            # N instances via for_each/count iteration
```

- Provider pinned in `versions.tf`, lock file (`.terraform.lock.hcl`) committed
- `tofu plan` is safe to repeat; `tofu destroy` is never automated
- Fleet VMs: `fleet-001 … fleet-0NN`, named by formatstring, zero per-VM resource blocks

## Cloud-Init Bootstrap Contract

Every fleet VM receives (via `fleet/cloud-init/fleet.yaml` template):

- hostname (per-instance)
- SSH key
- timezone (UTC default)
- package update
- qemu-guest-agent
- boot-complete marker (`/tmp/fleet-ready`)

Future additions (node_exporter, Wazuh agent, Ansible bootstrap hook) extend the same template — cloud-init stays idempotent (runcmd + write_files, no imperative one-shot scripts that break on re-run).

## CI Gates (GitOps)

`gitops/ci/validate.sh` runs on every PR. Fails on:

- `tofu fmt -check` / `tofu validate` drift or errors
- zsh syntax errors (`zsh -n`)
- shellcheck errors (lib/, scripts/, stages/)
- secret patterns (passwords, keys, tokens)

Pass requires merge — deployment never runs from an unvalidated branch.
