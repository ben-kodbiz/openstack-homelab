Yes — **your coding agent can absolutely build this**, and honestly I think that's the better route now.

Instead of giving the agent a giant script and hoping it works, give it a **contract + staged implementation plan + safety rules + hardware-aware defaults**. The agent can then build, test, and iterate on the actual machine.

Below is a complete `agentodo.md` you can put into the project root. It is deliberately designed so the deployment isn't tied to this one OpenStack installation.

# OpenStack KVM Lab — `agentodo.md`

## Mission

Build a **reusable, modular, idempotent OpenStack laboratory deployment system** using:

```text
Ubuntu 26.04 LTS Host
        │
        ├── KVM / QEMU
        ├── libvirt
        │
        └── OpenStack Lab VM
                │
                ├── Ubuntu 24.04 LTS (Noble)
                ├── Kolla-Ansible
                └── Docker
                        └── OpenStack 2026.1
```

The deployment must be controlled through a **single Zsh entry point** and must be safe to destroy/rebuild.

The system must be designed for **future enhancement** rather than being a one-off installation script.

---

# 1. Target Hardware

The implementation must use these defaults unless overridden through configuration.

## Host

```text
CPU:       AMD Ryzen 5 5600G
CPU cores: 6 physical / 12 threads
RAM:       64 GiB
Disk:      ~901 GiB usable NVMe
Free:      ~582 GiB
GPU:       NVIDIA RTX 3060 12 GiB
OS:        Ubuntu 26.04 LTS
Kernel:    7.x
```

Virtualization:

```text
AMD-V: enabled
/dev/kvm: available
IOMMU: enabled
libvirt: available
QEMU: available
```

## Guest

Default OpenStack VM:

```text
Name:       openstack-lab-01
OS:         Ubuntu 24.04 LTS Noble
vCPU:       8
RAM:        24 GiB
Disk:       100 GiB
Firmware:   UEFI or BIOS, configurable
Network:    libvirt NAT initially
```

The values MUST NOT be hard-coded throughout the project.

They belong in one configuration file.

---

# 2. Core Design Principles

## 2.1 Modular

Never create one giant 1,000-line shell script.

Separate functionality into modules:

```text
preflight
libvirt
cloud-init
guest
kolla
deployment
verification
cleanup
logging
configuration
```

---

## 2.2 Idempotent

Running:

```bash
./openstack-lab.zsh build
```

twice must NOT destroy or corrupt an existing deployment.

Every stage must determine:

```text
already exists?
already configured?
already running?
already completed?
```

and either skip or repair safely.

---

## 2.3 Fail Fast

Every stage must:

```zsh
set -e
set -u
set -o pipefail
```

or equivalent robust Zsh error handling.

Errors must include:

```text
STAGE
COMMAND
REASON
SUGGESTED NEXT ACTION
LOG FILE
```

---

## 2.4 No Host Network Damage

This is extremely important.

The deployment MUST NOT automatically modify:

```text
enp4s0
NetworkManager configuration
host default route
host DNS
host LAN IP
```

The initial implementation MUST use an isolated libvirt NAT network.

Do NOT create a bridge on the physical NIC unless explicitly enabled in configuration.

---

## 2.5 No Vagrant

Do not use Vagrant.

Use:

```text
libvirt
QEMU
KVM
cloud-init
```

directly.

---

# 3. Universal Configuration

Create:

```text
config/lab.conf
```

This is the ONLY place where normal deployment parameters should be changed.

Example:

```zsh
# Host / project
LAB_NAME="openstack-lab-01"
LAB_ROOT="/mnt/dev/homelab"

# VM
VM_NAME="openstack-lab-01"
VM_VCPU=8
VM_RAM_MB=24576
VM_DISK_GB=100

# Guest
GUEST_OS="ubuntu24.04"
GUEST_HOSTNAME="openstack-lab-01"

# Storage
LIBVIRT_POOL="homelab"
BASE_IMAGE="${LAB_ROOT}/noble-server-cloudimg-amd64.img"
VM_DISK="${LAB_ROOT}/${VM_NAME}.qcow2"
SEED_ISO="${LAB_ROOT}/${VM_NAME}-seed.iso"

# Network
LIBVIRT_NETWORK="default"
GUEST_IP_MODE="dhcp"

# OpenStack
KOLLA_OS_VERSION="2026.1"
KOLLA_BASE_DISTRO="ubuntu"
KOLLA_BASE_TAG="ubuntu-noble"

# Kolla
KOLLA_CONFIG_DIR="/etc/kolla"
KOLLA_VENV="/opt/kolla-venv"

# Behaviour
AUTO_APPROVE_DESTROY="false"
REBUILD_ON_FAILURE="false"
```

The implementation must validate every configuration variable before use.

---

# 4. CLI Design

Create:

```text
openstack-lab.zsh
```

It is the ONLY script the user normally executes.

Supported commands:

```bash
./openstack-lab.zsh help

./openstack-lab.zsh preflight

./openstack-lab.zsh create-vm

./openstack-lab.zsh wait

./openstack-lab.zsh configure

./openstack-lab.zsh install-kolla

./openstack-lab.zsh generate-config

./openstack-lab.zsh bootstrap

./openstack-lab.zsh deploy

./openstack-lab.zsh verify

./openstack-lab.zsh status

./openstack-lab.zsh logs

./openstack-lab.zsh destroy

./openstack-lab.zsh rebuild

./openstack-lab.zsh build
```

`build` executes the stages sequentially.

---

# 5. Directory Structure

Create:

```text
openstack-kvm-lab/
│
├── openstack-lab.zsh
│
├── agentodo.md
├── README.md
├── ARCHITECTURE.md
├── DESTROY.md
├── TROUBLESHOOTING.md
│
├── config/
│   ├── lab.conf
│   └── lab.conf.example
│
├── lib/
│   ├── common.zsh
│   ├── logging.zsh
│   ├── config.zsh
│   ├── preflight.zsh
│   ├── libvirt.zsh
│   ├── cloudinit.zsh
│   ├── guest.zsh
│   ├── kolla.zsh
│   ├── deployment.zsh
│   ├── verify.zsh
│   └── cleanup.zsh
│
├── stages/
│   ├── 00-preflight.zsh
│   ├── 01-create-vm.zsh
│   ├── 02-wait-for-ssh.zsh
│   ├── 03-configure-guest.zsh
│   ├── 04-install-kolla.zsh
│   ├── 05-generate-config.zsh
│   ├── 06-bootstrap.zsh
│   ├── 07-deploy.zsh
│   └── 08-verify.zsh
│
├── cloud-init/
│   ├── user-data
│   └── meta-data
│
├── templates/
│   └── multinode
│
├── state/
│
├── logs/
│
└── tests/
    ├── test-config.zsh
    ├── test-preflight.zsh
    ├── test-libvirt.zsh
    └── test-destroy.zsh
```

---

# 6. Stage 00 — Preflight

File:

```text
stages/00-preflight.zsh
```

Verify:

### OS

```bash
/etc/os-release
```

Expected:

```text
Ubuntu
26.04
```

Do NOT blindly reject another Ubuntu version if configuration explicitly permits it.

---

### CPU

Verify:

```bash
lscpu
```

Check:

```text
AMD-V / SVM
```

---

### KVM

Verify:

```bash
test -e /dev/kvm
```

and:

```bash
virt-host-validate qemu
```

The script should distinguish:

```text
PASS
WARN
FAIL
```

A secure-guest warning must not automatically fail the lab.

---

### libvirt

Verify:

```bash
virsh uri
```

Expected:

```text
qemu:///system
```

Verify:

```bash
virsh version
```

---

### Storage

Verify:

```bash
df -h "${LAB_ROOT}"
```

Ensure enough free space for:

```text
base image
guest disk
cloud-init
future VM images
Docker/OpenStack data
```

Configurable minimum:

```zsh
MIN_FREE_GB=150
```

---

### Required commands

Check:

```text
zsh
curl
wget
git
virsh
virt-install
cloud-localds
qemu-img
ssh
scp
```

Do not silently install packages during preflight.

Instead report missing dependencies.

Provide:

```bash
./openstack-lab.zsh install-host-deps
```

as an optional future enhancement.

---

# 7. Stage 01 — Create VM

File:

```text
stages/01-create-vm.zsh
```

Use the existing libvirt storage pool:

```text
homelab
```

Expected path:

```text
/mnt/dev/homelab
```

Verify pool exists.

Do NOT create a duplicate pool if it already exists.

---

## Base Image

Use:

```text
Ubuntu 24.04 Noble cloud image
```

Download only if missing.

Validate:

```text
file
qemu-img info
```

Do not overwrite a valid existing base image.

---

## VM Disk

Create:

```text
${VM_DISK}
```

using qcow2 with the Noble base image as backing file.

Example conceptual command:

```bash
qemu-img create \
    -f qcow2 \
    -F qcow2 \
    -b "${BASE_IMAGE}" \
    "${VM_DISK}" \
    "${VM_DISK_SIZE}"
```

The script must verify the result using:

```bash
qemu-img info
```

---

# 8. Cloud-Init

Create:

```text
cloud-init/user-data
cloud-init/meta-data
```

The guest must contain:

```text
stack user
sudo without password
SSH enabled
qemu-guest-agent
curl
git
python3
```

Do NOT place secrets in Git.

Passwords must eventually become configurable through environment variables or generated credentials.

The initial lab may use a temporary development password, but mark it clearly as unsafe for production.

---

# 9. VM Network

Initial implementation:

```text
libvirt default network
```

Guest should receive:

```text
192.168.122.x
```

through DHCP.

The script must discover the actual address using:

```bash
virsh net-dhcp-leases default
```

Do NOT assume:

```text
192.168.122.183
```

is permanent.

---

# 10. Stage 02 — Wait for SSH

Wait until:

```text
VM running
network available
SSH available
cloud-init complete
```

Check using:

```bash
virsh domstate
```

then:

```bash
ssh
```

and preferably:

```bash
cloud-init status --wait
```

Timeout must be configurable.

Example:

```zsh
SSH_TIMEOUT=300
```

On timeout print:

```text
VM status
IP address
virsh console hint
journal hint
cloud-init status
```

---

# 11. Stage 03 — Configure Guest

After SSH works:

Update guest.

Install only required dependencies.

Verify:

```text
Python
Git
Docker prerequisites
Kolla prerequisites
```

Do not blindly install random packages.

Keep guest configuration in:

```text
lib/guest.zsh
```

---

# 12. Stage 04 — Install Kolla-Ansible

Install Kolla-Ansible in a dedicated virtual environment.

Default:

```text
/opt/kolla-venv
```

Do NOT pollute system Python.

Verify:

```bash
kolla-ansible --version
```

Pin versions where appropriate.

Do not blindly install `latest`.

The selected Kolla-Ansible version must correspond to the configured OpenStack release.

---

# 13. Stage 05 — Generate Kolla Configuration

Create:

```text
/etc/kolla
```

Generate:

```text
globals.yml
passwords.yml
multinode
```

Do not manually duplicate configuration in multiple files.

Use templates.

---

# 14. Kolla Network Design

For the first successful build use the simplest architecture possible.

Avoid unnecessary:

```text
HA
VIP
multiple controllers
external bridge
GPU passthrough
OVS complexity
```

The goal is:

```text
ONE VM
ONE Kolla deployment
ONE OpenStack node
```

Enable only services required for the lab.

Suggested initial services:

```text
Keystone
Glance
Nova
Neutron
Placement
Horizon
MariaDB
RabbitMQ
Memcached
OVN
```

Do not add optional services until the base deployment works.

---

# 15. Critical Nova/Libvirt Design

This is specifically intended to avoid repeating the previous failure.

Before deployment verify:

```text
nova_compute
nova_libvirt
libvirt socket
/var/lib/nova
instance directory
permissions
SELinux/AppArmor
```

Verify the Nova/libvirt containers share the required filesystem paths.

Do NOT assume that:

```text
/var/lib/nova
```

inside one container is automatically the same filesystem visible to another container.

Add a dedicated verification test for:

```text
/var/lib/nova/instances
```

and:

```text
console.log
```

creation.

Before attempting an OpenStack VM boot, run a lower-level libvirt test if possible.

---

# 16. Stage 06 — Bootstrap

Run Kolla bootstrap.

Capture complete output:

```text
logs/bootstrap-YYYYMMDD-HHMMSS.log
```

If failure occurs:

```text
STOP
DO NOT automatically destroy
DO NOT retry endlessly
```

Print the exact failed task.

---

# 17. Stage 07 — Deploy

Run Kolla deployment.

Before deployment:

```text
validate config
validate inventory
validate passwords
validate Docker
validate libvirt
validate networking
```

After deployment verify:

```bash
docker ps
```

Expected services should be healthy.

Do not consider deployment successful merely because containers are "running".

Check health where available.

---

# 18. Stage 08 — Verify

Verification must be comprehensive but lightweight.

Check:

```text
Keystone
Glance
Nova
Neutron
Placement
Horizon
OVN
RabbitMQ
MariaDB
```

Run:

```bash
openstack service list
openstack compute service list
openstack network agent list
openstack hypervisor list
```

Then perform a real smoke test:

```text
upload image
create network
create subnet
create flavor
create instance
```

The VM boot test is mandatory.

---

# 19. Nova Smoke Test

The final verification must test:

```text
OpenStack
   ↓
Nova
   ↓
libvirt
   ↓
QEMU
   ↓
guest VM
```

Use a tiny test instance.

Verify:

```text
BUILD
ACTIVE
console
network
```

If the instance fails:

Immediately collect:

```text
nova-compute log
nova-libvirt log
libvirt XML
instance directory
file permissions
mounts
Docker mounts
qemu command line
```

Store everything under:

```text
logs/failure/<timestamp>/
```

This is mandatory.

---

# 20. State Management

Create:

```text
state/
```

Store stage completion markers:

```text
state/00-preflight.ok
state/01-create-vm.ok
state/02-wait.ok
...
```

A stage may be rerun explicitly.

Example:

```bash
./openstack-lab.zsh create-vm --force
```

But destructive operations require confirmation.

---

# 21. Destroy

Destroy must be predictable.

Command:

```bash
sudo ./openstack-lab.zsh destroy
```

Before doing anything destructive:

```text
show exactly what will be removed
```

Example:

```text
VM:
  openstack-lab-01

Disk:
  /mnt/dev/homelab/openstack-lab-01.qcow2

Seed:
  /mnt/dev/homelab/openstack-lab-01-seed.iso

Cloud-init:
  ...

Kolla:
  ...

Docker containers:
  ...
```

Require:

```text
Type DESTROY to continue
```

unless:

```zsh
AUTO_APPROVE_DESTROY=true
```

---

# 22. Destroy Safety

The destroy operation MUST NOT remove unrelated resources.

Never automatically delete:

```text
default libvirt network
staging0
vagrant-libvirt
unrelated VMs
unrelated storage pools
unrelated Docker volumes
host LAN configuration
```

Only delete resources created by this project.

Maintain a resource manifest:

```text
state/resources.manifest
```

Example:

```text
VM=openstack-lab-01
DISK=/mnt/dev/homelab/openstack-lab-01.qcow2
SEED=/mnt/dev/homelab/openstack-lab-01-seed.iso
```

---

# 23. Rebuild

Command:

```bash
sudo ./openstack-lab.zsh rebuild
```

Should perform:

```text
destroy
↓
preflight
↓
create VM
↓
configure
↓
Kolla
↓
deploy
↓
verify
```

But it must refuse to run automatically if unrelated resources appear to be affected.

---

# 24. Logging

Every operation must log to:

```text
logs/
```

Example:

```text
logs/
├── build-20260828-203000.log
├── preflight-20260828-203000.log
├── bootstrap-20260828-204500.log
└── verify-20260828-210000.log
```

Also provide:

```bash
./openstack-lab.zsh logs
```

to show the latest logs.

---

# 25. Status

Implement:

```bash
./openstack-lab.zsh status
```

Output:

```text
=== HOST ===
Ubuntu:
CPU:
RAM:
KVM:

=== VM ===
Name:
State:
IP:
vCPU:
RAM:

=== STORAGE ===
Pool:
Disk:
Base image:

=== KOLLA ===
Version:
Status:

=== DOCKER ===
Healthy:
Unhealthy:
Stopped:

=== OPENSTACK ===
Keystone:
Nova:
Neutron:
Glance:
Placement:

=== STAGES ===
00 preflight     PASS
01 create-vm     PASS
02 wait          PASS
03 configure     PASS
04 kolla         PASS
05 config        PASS
06 bootstrap     PASS
07 deploy        PASS
08 verify        PASS
```

---

# 26. Diagnostics

Implement:

```bash
./openstack-lab.zsh diagnose
```

Collect:

```text
uname
lsb_release
lscpu
free
df
ip addr
ip route
virsh version
virsh list
virsh net-list
virsh pool-list
virsh vol-list
docker ps
docker volume ls
```

For OpenStack:

```text
openstack service list
openstack compute service list
openstack network agent list
openstack hypervisor list
```

For failure:

```text
docker inspect
docker logs
libvirt XML
mount information
permissions
AppArmor status
```

Do not dump secrets.

---

# 27. Secret Handling

Never commit:

```text
passwords.yml
SSH private keys
tokens
API credentials
```

Add:

```text
.gitignore
```

with appropriate entries.

Provide:

```text
config/secrets.conf.example
```

but never real secrets.

---

# 28. Tests

Before calling the project complete, implement tests for:

### Configuration

```text
valid config
missing config
invalid RAM
invalid CPU
invalid paths
```

### Preflight

```text
KVM available
libvirt available
storage available
required commands available
```

### Libvirt

```text
pool exists
network exists
VM creation
VM detection
VM deletion
```

### Cloud-init

Validate generated files.

### Destroy

Critical:

```text
destroy lab VM
DO NOT destroy unrelated VM
DO NOT destroy unrelated network
DO NOT destroy unrelated storage
```

---

# 29. Development Sequence

The coding agent MUST implement in this order.

## Phase 1

Create:

```text
directory structure
config
logging
common functions
CLI dispatcher
```

Test:

```bash
./openstack-lab.zsh help
./openstack-lab.zsh status
```

---

## Phase 2

Implement preflight.

Test:

```bash
./openstack-lab.zsh preflight
```

Must produce a clear PASS/WARN/FAIL report.

Do NOT continue automatically if mandatory checks fail.

---

## Phase 3

Implement libvirt VM creation.

Test:

```bash
./openstack-lab.zsh create-vm
```

Verify manually:

```bash
virsh list --all
virsh dominfo openstack-lab-01
virsh domiflist openstack-lab-01
```

---

## Phase 4

Implement cloud-init + SSH.

Test:

```bash
./openstack-lab.zsh wait
```

Then:

```bash
ssh stack@<detected-ip>
```

Verify:

```bash
python3 --version
git --version
systemctl status qemu-guest-agent
```

---

## Phase 5

Implement guest preparation.

Do NOT install OpenStack yet.

Verify the guest is clean and reachable.

---

## Phase 6

Install Kolla-Ansible.

Verify:

```bash
kolla-ansible --version
```

---

## Phase 7

Generate Kolla configuration.

Do NOT deploy yet.

Run:

```bash
kolla-ansible -i multinode prechecks
```

Fix every real failure before deployment.

Warnings should be classified rather than blindly ignored.

---

## Phase 8

Bootstrap.

If bootstrap fails:

```text
STOP
COLLECT LOGS
REPORT FAILED TASK
```

Do not destroy the environment.

---

## Phase 9

Deploy.

If deployment succeeds:

```text
docker ps
openstack service list
```

---

## Phase 10

Run smoke tests.

The deployment is NOT complete until Nova successfully creates a test VM.

---

# 30. Future Enhancements

The architecture must allow future additions without rewriting the core.

Potential modules:

```text
GPU passthrough
multiple OpenStack nodes
external provider network
OVS bridge
OVN tuning
Ceph
Cinder
Swift
Octavia
Heat
Magnum
Terraform
Ansible external inventory
Prometheus
Grafana
Loki
backup
snapshot
restore
multiple lab profiles
```

Future profiles could be:

```text
config/profiles/
├── minimal.conf
├── default.conf
├── gpu.conf
├── network-lab.conf
└── production-like.conf
```

---

# 31. Profile Concept

Eventually support:

```bash
./openstack-lab.zsh build --profile minimal
```

and:

```bash
./openstack-lab.zsh build --profile gpu
```

But DO NOT implement profiles until the basic deployment works.

First:

```text
ONE VM
ONE NODE
ONE SUCCESSFUL OPENSTACK INSTANCE
```

Then enhance.

---

# 32. Agent Rules

The coding agent MUST follow these rules.

### Rule 1

Never guess.

If a command behaves differently from expected:

```text
inspect
diagnose
then modify
```

---

### Rule 2

Never repeatedly retry the same failing command.

Maximum:

```text
1 retry
```

unless the failure is explicitly transient.

---

### Rule 3

Never hide errors.

Bad:

```bash
command >/dev/null 2>&1 || true
```

Do not use this for meaningful operations.

---

### Rule 4

Never destroy automatically after failure.

Preserve the failed state for diagnosis.

---

### Rule 5

Never modify the host's physical network unless explicitly configured.

---

### Rule 6

Never hard-code the guest IP.

Discover it.

---

### Rule 7

Never hard-code paths outside configuration.

---

### Rule 8

Never assume Docker container filesystem paths are shared.

Explicitly verify mounts.

---

### Rule 9

Never declare success because containers are merely `Up`.

Perform functional OpenStack tests.

---

### Rule 10

Document every non-obvious workaround.

Add it to:

```text
TROUBLESHOOTING.md
```

---

# 33. Definition of Done

The project is considered successful only when:

```text
[PASS] Host preflight
[PASS] KVM
[PASS] libvirt
[PASS] storage
[PASS] VM creation
[PASS] cloud-init
[PASS] SSH
[PASS] qemu guest agent
[PASS] Kolla-Ansible
[PASS] Kolla prechecks
[PASS] Kolla bootstrap
[PASS] Kolla deployment
[PASS] Keystone
[PASS] Glance
[PASS] Nova
[PASS] Neutron
[PASS] OVN
[PASS] Placement
[PASS] Horizon
[PASS] OpenStack CLI
[PASS] Test image
[PASS] Test network
[PASS] Test instance reaches ACTIVE
```

Finally:

```bash
./openstack-lab.zsh status
```

must report:

```text
OPENSTACK LAB: HEALTHY
```

---

# 34. Final Requirement

Do not optimize prematurely.

The first milestone is NOT:

```text
fast
feature-rich
HA
GPU-enabled
production-like
```

The first milestone is:

```text
BORING
REPEATABLE
DEBUGGABLE
SUCCESSFUL
```

Once a clean deployment can be destroyed and recreated reliably, enhancements can be added one at a time.

The final user experience should be:

```bash
./openstack-lab.zsh preflight
./openstack-lab.zsh build
./openstack-lab.zsh verify
```

and later:

```bash
sudo ./openstack-lab.zsh destroy
```

with no manual reconstruction of the environment.

**One extra recommendation:** have your agent commit after each successful phase. That gives you checkpoints like:

```text
01-foundation
02-vm-working
03-ssh-working
04-kolla-installed
05-kolla-prechecks
06-bootstrap
07-openstack-running
08-smoke-test-passed
```

If the agent breaks something in phase 7, you can roll back to phase 6 instead of spending another three hours debugging a moving target.
