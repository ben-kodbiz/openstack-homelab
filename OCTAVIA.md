# Octavia LBaaS Deployment Guide

Complete reference for deploying and troubleshooting Octavia with the Amphora provider in this Kolla-Ansible lab.

## Overview

Octavia provides Load Balancer as a Service (LBaaS) on top of OpenStack Neutron. The Amphora provider runs HAProxy inside a dedicated Nova VM (the "amphora") per load balancer. Getting this working in a nested KVM lab requires overcoming several non-obvious obstacles.

## Final Working Configuration

| Component | Value |
|-----------|-------|
| Amphora image | `amphora-x64-haproxy` (built with official `diskimage-create.sh`) |
| Image size | 382 MB qcow2 (4 GB virtual) |
| Image tag | `amphora` |
| Image owner | `admin` project |
| mgmt network | `lb-mgmt-net` (VLAN 100 on physnet1) |
| mgmt subnet | `lb-mgmt-subnet` (10.1.0.0/24) |
| Host mgmt interface | `veth-mgmt` (OVS internal port on br-ex, IP 10.1.0.10) |
| Health manager bind | `10.1.0.10:5555` (UDP) |
| m1.tiny flavor | vcpus=1, ram=1024, disk=4 |

## Architecture

```
                                +-----------+
                                |  Client   |
                                +-----+-----+
                                      |
                              VIP: 10.0.0.X
                                      |
+-------------------------------------+-----------------------------------+
|  Host (192.168.122.17)                                                    |
|                                                                          |
|  +--[ enp1s0 virbr0 ]-- management                                       |
|  +--[ enp2s0 br-ex ]---- provider network physnet1                       |
|         |                                                                 |
|         +--[ veth-mgmt tag=100 ]-- 10.1.0.10/24 (host mgmt endpoint)     |
|         |                                                                 |
|         +--[ enp2s0 (untagged) ]-- external-net                          |
|                                                                          |
|  +---[ br-int ]                                                           |
|         |                                                                 |
|         +--[ int-br-ex <-> phy-br-ex ]-- patch to br-ex                  |
|         |                                                                 |
|         +--[ qvo-XXX tag=6 ]-- amphora mgmt port (lb-mgmt-net)           |
|         +--[ qvo-YYY tag=4 ]-- amphora VRRP port (internal-net)          |
|         +--[ qvo-ZZZ tag=4 ]-- vm-1 port (internal-net)                  |
+-------------------------------------+-----------------------------------+
                                      |
                              +-------v-------+
                              |   Amphora     |
                              |   (HAProxy +  |
                              |   keepalived) |
                              +-------+-------+
                                      |
                              +-------v-------+
                              |    vm-1       |
                              |  10.0.0.102   |
                              +---------------+
```

## Deployment Steps

### 1. Enable Octavia in globals.yml

```yaml
enable_octavia: "yes"
enable_neutron_provider_networks: "yes"
```

### 2. Add Octavia Amphora config to globals.yml

```yaml
octavia_amp_image: "amphora-x64-haproxy"
octavia_amp_image_owner_id: "<admin-project-uuid>"
octavia_amp_flavor:
  - name: m1.tiny
    vcpus: 1
    ram: 1024
    disk: 4
octavia_amp_network:
  - name: lb-mgmt-net
    provider_physical_network: physnet1
    provider_network_type: vlan
    provider_segmentation_id: 100
    subnet_cidr: 10.1.0.0/24
    subnet_gateway: 10.1.0.1
    subnet_allocation_pools:
      - 10.1.0.100-10.1.0.200
    subnet_dns_nameservers:
      - 8.8.8.8
```

### 3. Generate certificates

```bash
sudo /opt/kolla-venv/bin/kolla-ansible octavia-certificates \
  -i /etc/kolla/all-in-one
```

### 4. Build the Amphora image (CRITICAL)

**Do NOT use manual `diskimage-create` element selections.** The official script pulls in all required elements (including `openstack-data` for config-drive networking) automatically.

```bash
# Install DIB
pip3 install --break-system-packages diskimage-builder

# Build with 4GB disk (3GB amphora image won't fit in 2GB default)
cd /tmp/octavia/diskimage-create
PATH=$HOME/.local/bin:$PATH ./diskimage-create.sh \
  -s 4 \
  -o /tmp/amphora-x64-haproxy.qcow2
```

### 5. Upload image and set ownership

```bash
# Get admin project ID
ADMIN_ID=$(openstack project show admin -f value -c id)

# Upload (note: --project sets ownership; --tag must be added AFTER)
openstack image create amphora-x64-haproxy \
  --disk-format qcow2 \
  --container-format bare \
  --file /tmp/amphora-x64-haproxy.qcow2 \
  --private \
  --project admin

# Add tag
openstack image set amphora-x64-haproxy --tag amphora
```

**Why owner matters:** The octavia config uses `amp_image_owner_id` for tag-based image lookup. If the image is owned by the service project but `amp_image_owner_id` is set to the admin project, the lookup fails silently.

### 6. Create the management network

```bash
# Create VLAN provider network for mgmt traffic
openstack network create lb-mgmt-net \
  --provider-network-type vlan \
  --provider-physical-network physnet1 \
  --provider-segmentation 100 \
  --share

openstack subnet create lb-mgmt-subnet \
  --network lb-mgmt-net \
  --subnet-range 10.1.0.0/24 \
  --allocation-pool start=10.1.0.100,end=10.1.0.200 \
  --gateway 10.1.0.1 \
  --dhcp
```

### 7. Create the OVS host port

```bash
# Create OVS internal port on br-ex with VLAN 100 tag
sudo ovs-vsctl add-port br-ex veth-mgmt \
  -- set interface veth-mgmt type=internal
sudo ovs-vsctl set port veth-mgmt tag=100

# Assign IP (required: veth-mgmt needs an IP for routing)
sudo ip addr add 10.1.0.10/24 dev veth-mgmt
sudo ip link set veth-mgmt up
```

**Why this is needed:** The health_manager and octavia_worker run on the host with host networking. They need a routed path to reach amphorae on the management network. The OVS internal port provides this path through the br-ex ↔ br-int patch.

### 8. Add security group rules for amphora

The default `lb-mgmt-sg` only allows SSH and ICMP. The amphora agent communicates on port 5555 (UDP) for health heartbeats:

```bash
# Get the lb-mgmt security group ID
LB_SG=$(openstack security group list -f value -c ID -c Name | grep lb-mgmt | awk '{print $1}')

# Add port 5555 (both TCP and UDP - some deployments use TCP, some UDP)
openstack security group rule create --proto udp --dst-port 5555 $LB_SG
openstack security group rule create --proto tcp --dst-port 5555 $LB_SG
```

**Why both:** The octavia-worker talks to amphora on TCP 5555. The health_manager listens on UDP 5555 for amphora heartbeats.

### 9. Fix health_manager configuration (CRITICAL)

The health_manager defaults to binding on the management network IP (`192.168.122.17`). But amphorae are on `10.1.0.0/24` and cannot route to that address. Fix in `/etc/kolla/octavia-{api,worker,health-manager,housekeeping}/octavia.conf`:

```ini
[health_manager]
bind_ip = 10.1.0.10
controller_ip_port_list = 10.1.0.10:5555
```

**Where these files live:**
- `config_files` mount source: `/etc/kolla/octavia-<service>/`
- Running config (overwritten on restart): `/etc/octavia/octavia.conf`

The Kolla `COPY_ALWAYS` strategy copies `config_files` → `/etc/octavia/` on every container restart. So edits inside the container are lost.

### 10. Fix max_pool_size (CRITICAL)

The default `max_pool_size = 1` causes alembic migration deadlocks when Octavia boots. Fix in all four `octavia.conf` files:

```ini
[database]
max_pool_size = 10
```

### 11. Restart all octavia containers

```bash
sudo docker restart octavia_api octavia_worker octavia_health_manager octavia_housekeeping
```

### 12. Create the load balancer

```bash
# Create LB with VIP on a routable subnet (e.g., internal-net)
openstack loadbalancer create --name test-lb --vip-subnet internal-subnet

# Wait for ACTIVE status
openstack loadbalancer show test-lb

# Create listener, pool, member, health monitor
openstack loadbalancer listener create \
  --name lb-listener --protocol HTTP --protocol-port 80 test-lb

openstack loadbalancer pool create \
  --name lb-pool --lb-algorithm ROUND_ROBIN \
  --listener lb-listener --protocol HTTP

openstack loadbalancer member create \
  --name lb-member --address 10.0.0.102 \
  --subnet-id internal-subnet --protocol-port 80 lb-pool

openstack loadbalancer healthmonitor create \
  --name lb-hm --delay 5 --timeout 5 --max-retries 3 --type PING lb-pool
```

### 13. Verify

```bash
openstack loadbalancer show test-lb
# operating_status: ONLINE
# provisioning_status: ACTIVE

openstack loadbalancer member list lb-pool
# operating_status: ONLINE
# provisioning_status: ACTIVE
```

---

## Troubleshooting: What Went Wrong and Why

This deployment hit 8 distinct failures. Each one blocked the next. Understanding them prevents repetition.

### Failure 1: Amphora has no network (0 IPs, 0 bytes console.log)

**Symptom:** Amphora VM is ACTIVE in Nova, but `virsh domifaddr` shows nothing. Console.log is 0 bytes. DHCP namespace can't reach the amphora.

**Root cause:** The manually-built amphora image (using only `DIB_OCTAVIA_AMP_USE_SSH=true` + `DIB_OCTAVIA_AMP_USE_NFTABLES=false`) was missing the DIB elements that enable config-drive networking (`openstack-data`, cloud-init datasource, etc.). The VM booted but its NIC was never configured.

**Fix:** Rebuild using the official `diskimage-create.sh` from the Octavia repository, which includes all required elements automatically.

**Detection:** Always check `virsh domifaddr` and console.log on a newly-created amphora before debugging anything else.

### Failure 2: Flavor disk too small

**Symptom:** `nova.exception.FlavorDiskTooSmall: Flavor disk is 2147483648 bytes, image is 3251765248 bytes`

**Root cause:** The DIB default disk size is 2 GB. The amphora image is 3.25 GB.

**Fix:** Build with `-s 4` (4 GB virtual disk).

### Failure 3: Duplicate route for 10.1.0.0/24

**Symptom:** Host ARP to amphora goes out on `enp2s0` (untagged) instead of through `veth-mgmt` (VLAN 100). "Destination Host Unreachable" on pings to amphora.

**Root cause:** Two interfaces claimed the 10.1.0.0/24 subnet:
- `enp2s0.100` (VLAN sub-interface on enp2s0, IP 10.1.0.10/24)
- `veth-mgmt` (OVS internal port, IP 10.1.0.10/24)

The kernel preferred `enp2s0.100`, sending traffic to the physical NIC untagged. On br-ex, the untagged frame hit the br-int flow `in_port=1,vlan_tci=0x0000/0x1fff actions=mod_vlan_vid:3` which tagged it as VLAN 3 (internal-net) instead of VLAN 6 (lb-mgmt-net).

**Fix:** Delete the spurious VLAN sub-interface:
```bash
sudo ip link set enp2s0.100 down
sudo ip link delete enp2s0.100
```

**Detection:** `ip route show | grep 10.1.0` showing duplicate routes.

### Failure 4: health_manager bind_ip unreachable

**Symptom:** Health monitor shows ONLINE, but member stays in NO_MONITOR. Port 5555 TCP/UDP connection times out (or gets "Connection refused" after SG fix).

**Root cause:** Default `bind_ip = 192.168.122.17` (the management network). Amphorae are on 10.1.0.0/24 and have no route to 192.168.122.17. The amphora agent tries to send heartbeats to an unreachable address.

**Fix:** Change `bind_ip` and `controller_ip_port_list` in all 4 octavia configs to `10.1.0.10` (the veth-mgmt IP).

**Detection:** `ss -ulnp | grep 5555` inside the health_manager container — it should show binding on 10.1.0.10, not 192.168.122.17.

### Failure 5: max_pool_size = 1 causes deadlock

**Symptom:** Octavia worker hangs at alembic migration. Worker container crashes or stays unresponsive.

**Root cause:** Default SQLAlchemy pool size is 1. Multiple concurrent DB connections deadlock during schema migration.

**Fix:** Set `max_pool_size = 10` in the `[database]` section of all octavia configs.

**Detection:** Worker logs hanging at `alembic` migration step.

### Failure 6: amp_image_owner_id mismatch

**Symptom:** Worker boots amphora but immediately fails. Log shows image lookup errors.

**Root cause:** Image was uploaded to service project, but `amp_image_owner_id` in config points to admin project. Octavia's tag-based image search is scoped to owner.

**Fix:** Either:
1. Change `amp_image_owner_id` in octavia.conf to match image owner
2. Change image owner: `openstack image set <name> --project admin`

Option 2 is simpler since Kolla defaults to admin project.

**Gotcha:** Changing project clears all tags. Must re-add tag after.

### Failure 7: COPY_ALWAYS overwrites container config

**Symptom:** You edit `/etc/octavia/octavia.conf` inside a running container, restart, and changes are gone.

**Root cause:** Kolla's `COPY_ALWAYS` config strategy copies from `/var/lib/kolla/config_files/` (a read-only bind mount from `/etc/kolla/<service>/`) to `/etc/octavia/` on every container start.

**Fix:** Always edit the source files in `/etc/kolla/octavia-<service>/octavia.conf`, not inside the container.

**Detection:** `docker inspect <container>` shows the mount source.

### Failure 8: Port 5555 blocked by security group

**Symptom:** `nc -zv <amphora> 5555` times out, then shows "Connection refused" after removing SG rules.

**Root cause:** The `lb-mgmt-sg` default rules only allow SSH (22) and ICMP. Port 5555 is not in the default ruleset.

**Fix:** Add ingress rules for TCP and UDP port 5555.

**Detection:** `openstack security group rule list <lb-mgmt-sg>`

---

## Key Files and Their Roles

| File | Purpose |
|------|---------|
| `/etc/kolla/globals.yml` | Kolla configuration (image name, flavor, network) |
| `/etc/kolla/octavia-api/octavia.conf` | Octavia API config (mounted into container) |
| `/etc/kolla/octavia-worker/octavia.conf` | Octavia worker config (mounted into container) |
| `/etc/kolla/octavia-health-manager/octavia.conf` | Health manager config (mounted into container) |
| `/etc/kolla/octavia-housekeeping/octavia.conf` | Housekeeping config (mounted into container) |
| `/etc/kolla/config/octavia/*.pem` | TLS certificates (server CA, client cert) |
| `/etc/kolla/config/neutron/ml2_conf.ini` | ML2 VLAN range override (adds `physnet1:100:200`) |
| `/tmp/amphora-x64-haproxy.qcow2` | Built amphora image |
| `openstack/content/0000` in config-drive | Contains `controller_ip_port_list` baked into amphora |

## Verification Checklist

After deployment, verify each item:

- [ ] Amphora VM boots and gets an IP on lb-mgmt-net
- [ ] Host can ping amphora management IP from `veth-mgmt`
- [ ] Port 9443 (TCP) reachable on amphora from host
- [ ] Port 5555 (UDP) reachable on health_manager from amphora subnet
- [ ] `openstack loadbalancer create` transitions to ACTIVE
- [ ] Member transitions from NO_MONITOR to ONLINE after health monitor
- [ ] `openstack loadbalancer show` shows operating_status: ONLINE

## Quick Diagnostic Commands

```bash
# Check health_manager is listening
sudo docker exec octavia_health_manager ss -ulnp | grep 5555

# Check amphora management interface
openstack server list --all-projects --network lb-mgmt-net

# Check security group rules for port 5555
openstack security group rule list <lb-mgmt-sg-id>

# Check OVS flows for VLAN 100
sudo docker exec -u root neutron_openvswitch_agent ovs-ofctl dump-flows br-int | grep 'vlan=100\|mod_vlan_vid:6'
sudo docker exec -u root neutron_openvswitch_agent ovs-ofctl dump-flows br-ex | grep 'mod_vlan_vid:100'

# Check host routes to lb-mgmt-net
ip route show | grep 10.1.0

# Check config in container matches source
diff <(sudo grep "bind_ip\|controller_ip" /etc/kolla/octavia-health-manager/octavia.conf) \
     <(sudo docker exec octavia_health_manager grep "bind_ip\|controller_ip" /etc/octavia/octavia.conf)
```
