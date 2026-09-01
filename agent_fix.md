# AGENT_FIX.md

# OpenStack Homelab → Enterprise Linux Fleet Lab

## 0. PURPOSE

This document is an implementation plan for evolving the existing:

`openstack-homelab`

repository from an OpenStack installation project into a reproducible, GitOps-oriented Linux fleet laboratory.

The existing OpenStack deployment is WORKING.

DO NOT rewrite or replace the working KVM/libvirt/Kolla/OpenStack foundation unless a verified defect requires it.

The project should evolve incrementally:

```text
Host
  ↓
KVM/libvirt
  ↓
OpenStack control VM
  ↓
OpenStack
  ↓
OpenTofu
  ↓
Linux fleet
  ↓
GitOps
  ↓
AWX / NetBox / Wazuh
  ↓
Monitoring + Security + Operations
```

The immediate target is:

* 20 small Linux VMs
* 1 vCPU each
* ~1 GB RAM each
* ~5 GB virtual disk each
* CPU overcommit enabled conservatively
* RAM initially NOT overcommitted
* reproducible provisioning
* automated bootstrap
* Git-controlled configuration
* future NetBox/AWX/Wazuh integration

---

# 1. NON-NEGOTIABLE SAFETY RULES

## 1.1 Protect the physical host

NEVER:

* modify the physical host's primary network configuration
* create a bridge on the physical NIC
* alter NetworkManager/netplan configuration outside the lab
* modify unrelated libvirt networks
* modify unrelated storage pools
* modify unrelated VMs
* automatically destroy the existing OpenStack VM

The lab must remain isolated behind the existing KVM/libvirt NAT design.

---

# 2. CURRENT ARCHITECTURE

Current architecture:

```text
Physical Ubuntu host
    │
    └── KVM/QEMU/libvirt
          │
          └── openstack-lab-01
                │
                ├── Docker
                ├── Kolla-Ansible
                └── OpenStack
                      │
                      ├── Keystone
                      ├── Glance
                      ├── Nova
                      ├── Neutron
                      ├── Placement
                      ├── Horizon
                      ├── MariaDB
                      ├── RabbitMQ
                      └── Memcached
```

Keep this architecture.

The repository currently separates:

```text
cloud-init/
config/
lib/
scripts/
templates/
tests/
tofu/
```

Do not unnecessarily flatten or rewrite these directories.

---

# 3. RESOURCE REALITY

The physical machine:

```text
CPU: AMD Ryzen 5 5600G
RAM: 64 GB
```

The OpenStack control VM currently exposes approximately:

```text
CPU: 8 vCPU
RAM: ~33 GB
Disk: ~145 GB
```

Observed OpenStack resources:

```text
vCPUs:             8
vCPUs used:        2
RAM:               33825 MB
RAM used:          2048 MB
RAM apparently free: ~31 GB
Local disk:        ~144 GB
Disk used:         ~5 GB
```

Observed guest filesystem:

```text
/ = ~145 GB
used = ~57 GB
available = ~89 GB
```

IMPORTANT:

Nova's reported free disk MUST NOT be treated as identical to the actual filesystem free space.

Always monitor both:

```text
OpenStack resource availability
+
actual filesystem capacity
```

---

# 4. FIX CURRENT CONFIGURATION DOCUMENTATION

Review `config/lab.conf` and README documentation.

Current configuration contains values similar to:

```text
VM_VCPU=8
VM_RAM_MB=24576
VM_DISK_GB=100
MIN_FREE_GB=150
```

Do not blindly change values.

Instead:

1. Compare configuration against actual deployment.
2. Document intended values.
3. Make preflight calculations dynamic where practical.
4. Avoid hard-coded assumptions about available disk.
5. Ensure the documentation reflects the actual architecture.

`MIN_FREE_GB` MUST NOT make the working environment impossible to operate simply because the host has less free space than an old default threshold.

Calculate required free space from:

```text
required deployment space
+
safety margin
+
expected growth
```

---

# 5. RESPONSIBILITY BOUNDARIES

The project must maintain clear responsibility boundaries.

## Host/bootstrap layer

Use:

```text
Zsh
KVM
QEMU
libvirt
cloud-init
```

Responsibilities:

* prepare the physical host
* create the OpenStack control VM
* configure libvirt resources
* bootstrap the OpenStack control VM
* install/configure Kolla-Ansible
* deploy OpenStack

## OpenStack infrastructure layer

Use:

```text
OpenTofu
OpenStack provider
```

Responsibilities:

* networks
* subnets
* routers
* security groups
* ports
* images
* volumes
* Linux instances
* fleet sizing

OpenTofu should be the infrastructure-as-code engine once OpenStack is running.

Do not duplicate OpenStack resource management in the Zsh layer.

The OpenStack provider supports OpenTofu and provides resources for OpenStack infrastructure.

## Configuration layer

Future:

```text
Ansible
AWX
```

Responsibilities:

* OS configuration
* users
* SSH
* packages
* security baseline
* services
* monitoring agents
* Wazuh agents
* operational jobs

## Inventory/source-of-truth layer

Future:

```text
NetBox
```

Responsibilities:

* device inventory
* IPAM
* roles
* environments
* metadata
* ownership
* topology
* source of infrastructure metadata

## Security layer

Future:

```text
Wazuh
```

Responsibilities:

* endpoint security monitoring
* file integrity
* vulnerability/security visibility
* security events
* compliance/security checks

---

# 6. PHASE 0 — STABILIZE CURRENT OPENSTACK

DO THIS FIRST.

Do not start the fleet expansion until the current OpenStack deployment passes all existing smoke tests.

Required:

```bash
./openstack-lab.zsh preflight
./openstack-lab.zsh status
./openstack-lab.zsh verify
```

Validate:

```text
libvirt
KVM
OpenStack control VM
Kolla containers
Keystone
Glance
Nova
Neutron
Placement
Horizon
```

Validate a test instance:

```text
create
boot
SSH
network
console
delete
```

The previous Nova/libvirt `console.log`/instance-path failure must remain covered by tests.

Do not remove existing regression checks.

---

# 7. PHASE 1 — CLEAN REPOSITORY STRUCTURE

Do not perform a destructive mass rewrite.

Organize documentation and code gradually.

Target structure:

```text
openstack-homelab/
│
├── AGENTS.md
├── README.md
├── AGENT_FIX.md
├── SAFETY.md
├── ARCHITECTURE.md
│
├── openstack-lab.zsh
│
├── config/
│
├── cloud-init/
│
├── lib/
│
├── scripts/
│
├── templates/
│
├── tests/
│
├── tofu/
│
├── fleet/
│   ├── cloud-init/
│   ├── templates/
│   └── tests/
│
├── gitops/
│   ├── ci/
│   ├── policies/
│   └── environments/
│
├── roadmap/
│   ├── NETBOX.md
│   ├── AWX.md
│   └── WAZUH.md
│
└── scenarios/
    ├── service-failure/
    ├── disk-pressure/
    ├── configuration-drift/
    ├── patch-day/
    └── vm-replacement/
```

Do not move files unnecessarily if doing so creates risk.

---

# 8. PHASE 2 — OPEN TOFU FOUNDATION

OpenTofu becomes the authoritative mechanism for managing OpenStack tenant resources.

Create reusable modules where useful:

```text
tofu/
├── main.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── terraform.tfvars.example
├── modules/
│   ├── network/
│   ├── security/
│   ├── linux-vm/
│   └── fleet/
└── environments/
    └── lab/
```

Use the OpenStack provider.

Pin provider versions.

Commit:

```text
.tofu.lock.hcl
```

Do NOT allow uncontrolled provider upgrades.

OpenTofu explicitly recommends constraining provider versions and committing the lock file for reproducibility.

Required commands:

```bash
tofu fmt -check
tofu init
tofu validate
tofu plan
```

Never automatically run:

```bash
tofu destroy
```

without explicit user confirmation.

---

# 9. PHASE 3 — LINUX FLEET

Create a reusable fleet definition.

Example:

```hcl
fleet_size = 20

fleet_vm = {
  vcpu = 1
  ram_mb = 1024
  disk_gb = 5
}
```

The implementation must support:

```text
fleet_size = 1
fleet_size = 5
fleet_size = 10
fleet_size = 20
fleet_size = 30
```

without changing the module design.

Naming:

```text
fleet-001
fleet-002
fleet-003
...
fleet-020
```

Do not hard-code individual VM resources.

Use OpenTofu iteration mechanisms.

---

# 10. PHASE 4 — CLOUD-INIT FLEET BOOTSTRAP

Every Linux VM must automatically bootstrap.

Minimum:

```text
hostname
SSH key
timezone
package update
qemu guest agent where appropriate
basic OS configuration
```

Future bootstrap:

```text
node exporter
Wazuh agent
Ansible bootstrap
Uyuni registration
```

Cloud-init must be idempotent.

Do not put secrets directly into Git.

Use placeholders and secure secret injection.

---

# 11. PHASE 5 — CPU/RAM OVERCOMMIT

Initial policy:

```text
CPU: conservative overcommit
RAM: 1:1
```

Do NOT immediately configure aggressive RAM overcommit.

The goal is:

```text
20 × 1 vCPU
20 × 1 GB RAM
20 × 5 GB virtual disk
```

First measure:

```text
CPU utilization
RAM available
load average
IO wait
disk utilization
disk latency
OpenStack service health
```

Only then experiment with higher allocation ratios.

The fleet consists primarily of low-utilization Linux endpoints, so CPU overcommit is expected to be more useful than aggressive RAM overcommit.

---

# 12. PHASE 6 — GITOPS NOW

GitOps starts NOW.

Do not wait for Kubernetes.

Git becomes the source of desired configuration for:

```text
OpenTofu
Ansible
AWX definitions
monitoring configuration
security policies
fleet scenarios
documentation
```

Git MUST NOT contain:

```text
passwords
API tokens
private keys
OpenStack secrets
OpenBao secrets
Wazuh private credentials
```

---

# 13. GITOPS WORKFLOW

Target workflow:

```text
Developer
   │
   ▼
Git branch
   │
   ▼
Pull Request
   │
   ▼
CI validation
   │
   ├── tofu fmt
   ├── tofu validate
   ├── tofu plan
   ├── shellcheck
   ├── zsh syntax checks
   ├── YAML validation
   ├── Ansible lint
   └── secret scanning
   │
   ▼
Review
   │
   ▼
Merge
   │
   ▼
Deployment
   │
   ├── OpenTofu
   └── AWX/Ansible
   │
   ▼
Linux fleet
```

Do not install Argo CD/Flux merely for the sake of calling the project GitOps.

For this OpenStack/Linux lab, a Git + CI + OpenTofu + AWX model is sufficient initially.

---

# 14. GITOPS DIRECTORY

Create:

```text
gitops/
├── README.md
├── ci/
│   ├── validate.sh
│   ├── tofu-check.sh
│   └── ansible-check.sh
│
├── environments/
│   └── lab/
│
└── policies/
    ├── no-host-network-changes.md
    ├── no-secret-commits.md
    └── destroy-policy.md
```

CI must fail if:

```text
OpenTofu is invalid
shell syntax is invalid
Ansible is invalid
secrets are detected
required tests fail
```

---

# 15. PHASE 7 — LAB CONTROL COMMAND

Eventually introduce:

```text
labctl
```

as the user-facing control interface.

Examples:

```bash
./labctl preflight

./labctl openstack status

./labctl fleet create 20

./labctl fleet status

./labctl fleet destroy

./labctl test

./labctl scenario service-failure
```

Internally it may call:

```text
Zsh
OpenTofu
Ansible
AWX API
OpenStack CLI
```

The user should not need to remember implementation details.

Do NOT rewrite the existing working scripts just to create `labctl`.

Initially `labctl` can be a thin wrapper.

---

# 16. PHASE 8 — NETBOX ROADMAP

NETBOX IS NEAR-FUTURE, NOT PHASE 1.

Once 10–20 Linux VMs can be created reliably:

```text
OpenTofu
   ↓
OpenStack VM
   ↓
IP assigned
   ↓
NetBox API
   ↓
device registered
   ↓
role/environment/tags
```

NetBox becomes the infrastructure metadata/source-of-truth layer.

Target metadata:

```text
hostname
IP
OS
role
environment
region
project
owner
status
```

Do not make NetBox the mechanism that creates the VM.

OpenTofu creates infrastructure.

NetBox records infrastructure.

---

# 17. PHASE 9 — AWX ROADMAP

AWX IS NEAR-FUTURE.

Do not install AWX before the basic fleet provisioning works.

Target:

```text
OpenTofu
   ↓
20 Linux VMs
   ↓
cloud-init
   ↓
AWX
   ↓
Ansible
   ↓
configuration
```

AWX should eventually manage:

```text
bootstrap
baseline
users
SSH
packages
security
monitoring
patching
service remediation
```

Possible future integration:

```text
NetBox
   ↓
dynamic inventory
   ↓
AWX
   ↓
Ansible
```

Keep infrastructure creation and configuration management separate.

OpenTofu should create resources.

AWX/Ansible should configure them.

---

# 18. PHASE 10 — WAZUH ROADMAP

WAZUH IS NEAR-FUTURE.

First deploy the fleet.

Then:

```text
Wazuh manager
      │
      ├── fleet-001
      ├── fleet-002
      ├── fleet-003
      └── ...
```

Install the Wazuh agent automatically during bootstrap/configuration.

Target capabilities:

```text
security events
file integrity
vulnerability visibility
security configuration
compliance/security reporting
```

Do not manually install agents on 20 machines.

Automation is the objective.

---

# 19. FUTURE MANAGEMENT STACK

Future target:

```text
                    Git
                     │
              GitOps / CI
                     │
          ┌──────────┴──────────┐
          │                     │
       OpenTofu                AWX
          │                     │
       OpenStack              Ansible
          │                     │
          └──────────┬──────────┘
                     │
                Linux Fleet
                     │
          ┌──────────┼──────────┐
          │          │          │
        NetBox      Wazuh    Monitoring
          │          │          │
       inventory   security   metrics
```

Future optional components:

```text
Uyuni
OpenBao
Prometheus
Grafana
Alertmanager
Loki
osquery/Fleet
step-ca
```

Do not install all of them at once.

---

# 20. OPERATIONAL SCENARIOS

After fleet provisioning works, create repeatable operational scenarios.

## Scenario: Service failure

```text
stop service on fleet-007
       ↓
Prometheus detects failure
       ↓
alert
       ↓
AWX remediation
       ↓
service restored
       ↓
verify
```

## Scenario: Disk pressure

```text
fleet-004
     ↓
disk usage > threshold
     ↓
alert
     ↓
remediation
     ↓
verification
```

## Scenario: Configuration drift

```text
Git desired state
       ≠
actual host state
       ↓
detect
       ↓
report/remediate
```

## Scenario: Security event

```text
fleet-009
    ↓
Wazuh
    ↓
security alert
    ↓
investigation
    ↓
remediation
```

## Scenario: VM replacement

```text
destroy fleet-012
       ↓
detect missing node
       ↓
recreate
       ↓
bootstrap
       ↓
NetBox
       ↓
AWX
       ↓
Wazuh
       ↓
monitoring
       ↓
healthy
```

---

# 21. TESTING REQUIREMENTS

Every phase must have automated tests.

## Static

```text
zsh syntax
shellcheck
YAML validation
OpenTofu fmt
OpenTofu validate
Ansible lint
```

## Infrastructure

```text
network exists
security groups exist
VM exists
VM has expected resources
cloud-init completed
```

## Functional

```text
SSH works
network works
metadata works
agent registration works
monitoring works
security agent works
```

## Destructive/rebuild

Test:

```text
create 10
destroy 5
recreate 5
verify 10
```

Eventually:

```text
destroy entire fleet
tofu apply
verify fleet
```

The environment must be reproducible.

---

# 22. IDEMPOTENCY

Running the same command twice MUST NOT cause unnecessary damage.

Examples:

```bash
./openstack-lab.zsh preflight
```

multiple times:

SAFE.

```bash
tofu plan
```

multiple times:

SAFE.

Bootstrap multiple times:

SAFE.

Configuration playbook multiple times:

SAFE.

Destruction:

NEVER automatic.

---

# 23. DOCUMENTATION RULE

Keep documentation focused.

`AGENTS.md`:

* permanent agent rules
* safety
* coding standards
* test requirements

`README.md`:

* human quick start
* architecture
* basic usage

`ARCHITECTURE.md`:

* technical design

`AGENT_FIX.md`:

* implementation roadmap

`roadmap/`:

* future NetBox/AWX/Wazuh/etc.

Do NOT put the entire project specification into one enormous agent document.

---

# 24. AGENT EXECUTION RULES

The coding agent MUST work phase-by-phase.

For each phase:

1. Inspect existing implementation.
2. Do not assume files are missing.
3. Make the smallest safe change.
4. Run tests.
5. Verify actual behavior.
6. Update documentation.
7. Report changed files.
8. Report tests executed.
9. Report known limitations.
10. Stop at the phase boundary.

NEVER silently proceed to the next major phase.

---

# 25. DEFINITION OF DONE

## Current OpenStack foundation

```text
[ ] Host remains untouched outside lab scope
[ ] OpenStack deploys
[ ] VM boots
[ ] VM networking works
[ ] VM can be deleted
[ ] Existing Nova/libvirt regression is covered
[ ] Rebuild works
```

## Fleet

```text
[ ] OpenTofu creates 1 VM
[ ] OpenTofu creates 10 VMs
[ ] OpenTofu creates 20 VMs
[ ] cloud-init completes
[ ] all VMs reachable
[ ] fleet can be destroyed
[ ] fleet can be recreated
```

## GitOps

```text
[ ] Git is source of desired configuration
[ ] CI validates OpenTofu
[ ] CI validates shell
[ ] CI validates Ansible
[ ] secret scanning exists
[ ] deployment requires explicit merge
```

## Near future

```text
[ ] NetBox integrated
[ ] AWX integrated
[ ] Wazuh integrated
```

## Operations

```text
[ ] service failure scenario
[ ] disk pressure scenario
[ ] configuration drift scenario
[ ] security event scenario
[ ] VM replacement scenario
[ ] mass rebuild scenario
```

---

# 26. FINAL ARCHITECTURAL PRINCIPLE

Do not optimize this project for:

> "How quickly can we install 10 different tools?"

Optimize it for:

> "Can one person reliably provision, configure, monitor, secure, break, repair, and rebuild a fleet of Linux machines from Git?"

The final system should demonstrate:

```text
Infrastructure as Code
        +
Configuration Management
        +
GitOps
        +
Inventory
        +
Monitoring
        +
Security
        +
Automated Remediation
        +
Reproducibility
```

The OpenStack installation is the foundation.

The Linux fleet is the laboratory.

Git is the desired-state record.

OpenTofu creates infrastructure.

AWX/Ansible configures systems.

NetBox records infrastructure metadata.

Wazuh provides security visibility.

Monitoring provides operational visibility.

The goal is a small but realistic simulation of enterprise Linux operations.
