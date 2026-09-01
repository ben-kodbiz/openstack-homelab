# OpenStack KVM Lab

A Zsh-based, idempotent OpenStack laboratory deployment system. Single host → KVM/libvirt VM → Kolla-Ansible → OpenStack 2026.1.

## Architecture

```
Ubuntu 26.04 Host (AMD Ryzen 5 5600G, 64GB RAM)
├── KVM / QEMU / libvirt
└── OpenStack Lab VM (Ubuntu 24.04 Noble)
    ├── Docker
    ├── Kolla-Ansible 22.1.0
    └── OpenStack 2026.1 Services
        ├── Keystone (Identity)        → http://192.168.122.17:5000/v3
        ├── Glance (Image)             → http://192.168.122.17:9292
        ├── Nova (Compute)             → http://192.168.122.17:8774/v2.1
        ├── Neutron (Network)          → http://192.168.122.17:9696
        ├── Placement (Resource)       → http://192.168.122.17:8778
        ├── Horizon (Dashboard)        → http://192.168.122.17/dashboard
        ├── MariaDB                   → 192.168.122.17:3306
        ├── RabbitMQ                  → 192.168.122.17:5672
        └── Memcached                 → 192.168.122.17:11211
```

## Prerequisites

### Host Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores with AMD-V/VT-x | 6+ cores |
| RAM | 16 GB | 32+ GB |
| Disk | 100 GB free | 200+ GB free |
| OS | Ubuntu 24.04 LTS | Ubuntu 26.04 LTS |
| Network | libvirt NAT | libvirt NAT |

### Required Host Packages

```bash
sudo apt update
sudo apt install -y \
  zsh curl wget git \
  qemu-kvm libvirt-daemon-system libvirt-clients \
  virtinst cloud-image-utils \
  bridge-utils
```

### Verify Host Readiness

```bash
ls -la /dev/kvm
virt-host-validate qemu
virsh uri          # Should show: qemu:///system
virsh net-list     # Should show: default network
```

## Quick Start

```bash
# 1. Clone the repository
git clone <repo-url> ~/homelab
cd ~/homelab

# 2. Run preflight checks
./openstack-lab.zsh preflight

# 3. Deploy everything (takes 30-60 minutes)
./openstack-lab.zsh build

# 4. Verify deployment
./openstack-lab.zsh verify

# 5. Check status
./openstack-lab.zsh status
```

## Configuration

All configuration lives in `config/lab.conf`. Edit this file before first deployment.

### Key Settings

```zsh
# VM Resources
VM_NAME="openstack-lab-01"
VM_VCPU=8          # Number of virtual CPUs
VM_RAM_MB=24576    # RAM in MB (24 GB)
VM_DISK_GB=100     # Disk size in GB

# Storage Paths
LAB_ROOT="/mnt/AI/homelab"    # Where VMs and images are stored
LIBVIRT_POOL="homelab"        # Libvirt storage pool name

# OpenStack Version
KOLLA_OS_VERSION="2026.1"
KOLLA_BASE_DISTRO="ubuntu"
KOLLA_BASE_TAG="ubuntu-noble"

# Behavior
AUTO_APPROVE_DESTROY="false"  # Require confirmation for destroy
SSH_TIMEOUT=300               # Seconds to wait for SSH
MIN_FREE_GB=150               # Minimum free space required
```

### Network Configuration

The VM uses libvirt's default NAT network (192.168.122.0/24). The guest IP is discovered dynamically:

```bash
virsh net-dhcp-leases default
```

**Never hard-code the guest IP.** The system always discovers it at runtime.

### Secrets

Copy `config/secrets.conf.example` to `config/secrets.conf` and set real passwords:

```bash
cp config/secrets.conf.example config/secrets.conf
chmod 600 config/secrets.conf
# Edit with your passwords
```

Secrets are never committed to git.

## Commands

### Deployment Commands

| Command | Description | Time |
|---------|-------------|------|
| `preflight` | Check host readiness | 5s |
| `create-vm` | Create KVM VM with cloud-init | 2-5 min |
| `wait` | Wait for SSH + cloud-init | 2-5 min |
| `configure` | Install Docker, dependencies | 5-10 min |
| `install-kolla` | Install Kolla-Ansible in venv | 5-10 min |
| `generate-config` | Generate globals.yml, run prechecks | 2-5 min |
| `bootstrap` | Kolla bootstrap (Docker config) | 5-10 min |
| `deploy` | Kolla deploy (pulls images, starts services) | 20-40 min |
| `verify` | Full smoke test + VM boot test | 5-10 min |

### Management Commands

| Command | Description |
|---------|-------------|
| `build` | Run all deployment stages sequentially |
| `post-fix` | Fix passwords, networking, restart all containers |
| `status` | Show host, VM, Docker, OpenStack state |
| `logs` | Show latest log file |
| `destroy` | Remove all lab resources (interactive) |
| `rebuild` | Destroy + full rebuild |
| `help` | Show usage information |

### Examples

```bash
# Full deployment
./openstack-lab.zsh build

# Run a specific stage
./openstack-lab.zsh preflight
./openstack-lab.zsh create-vm

# Force re-run a completed stage
./openstack-lab.zsh create-vm --force

# Check what's deployed
./openstack-lab.zsh status

# Fix issues after deploy
./openstack-lab.zsh post-fix

# Destroy everything
sudo ./openstack-lab.zsh destroy

# Rebuild from scratch
sudo ./openstack-lab.zsh rebuild
```

## Accessing OpenStack

### SSH to the Lab VM

```bash
ssh stack@192.168.122.17
```

### Source Admin Credentials

```bash
source /etc/kolla/admin-openrc.sh
```

All `openstack` commands below assume you have sourced this file.

### Dashboard (Horizon)

```
http://192.168.122.17/dashboard
```

Login: `admin` / password from `/etc/kolla/passwords.yml` → `keystone_admin_password`

### API Endpoints

```bash
openstack endpoint list --interface public
```

| Service | Endpoint |
|---------|----------|
| Keystone | http://192.168.122.17:5000/v3 |
| Glance | http://192.168.122.17:9292 |
| Nova | http://192.168.122.17:8774/v2.1 |
| Neutron | http://192.168.122.17:9696 |
| Placement | http://192.168.122.17:8778 |

---

## How To: Upload Images

### Upload a CirrOS Image (Small, for testing)

```bash
wget https://download.cirros-cloud.net/0.6.3/cirros-0.6.3-x86_64-disk.img

openstack image create cirros \
  --file cirros-0.6.3-x86_64-disk.img \
  --disk-format qcow2 \
  --container-format bare \
  --public

openstack image list
```

### Upload an Ubuntu Noble Image (Full server)

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

openstack image create ubuntu-noble \
  --file noble-server-cloudimg-amd64.img \
  --disk-format qcow2 \
  --container-format bare \
  --public

openstack image list
```

### Upload a Fedora Image

```bash
wget https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2

openstack image create fedora-40 \
  --file Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  --public
```

### Manage Images

```bash
# List all images
openstack image list

# Show image details
openstack image show cirros

# Delete an image
openstack image delete cirros

# Set image properties
openstack image set cirros --min-disk 1 --min-ram 128
```

---

## How To: Create Flavors

Flavors define VM sizing (CPU, RAM, disk).

### Standard Flavors

```bash
openstack flavor create m1.tiny   --vcpus 1 --ram 512   --disk 1
openstack flavor create m1.small  --vcpus 1 --ram 1024  --disk 10
openstack flavor create m1.medium --vcpus 2 --ram 2048  --disk 20
openstack flavor create m1.large  --vcpus 4 --ram 4096  --disk 40
openstack flavor create m1.xlarge --vcpus 4 --ram 8192  --disk 80
```

### Custom Flavor

```bash
# Create a flavor with specific specs
openstack flavor create gpu-small \
  --vcpus 2 \
  --ram 4096 \
  --disk 20 \
  --property gpu=true

# List flavors
openstack flavor list

# Show flavor details
openstack flavor show m1.tiny

# Delete a flavor
openstack flavor delete m1.tiny
```

---

## How To: Create Networks

### Architecture Overview

```
External Network (provider)        Internal Networks (project)
┌─────────────────────┐           ┌─────────────────────────┐
│ external-net        │           │ mynet                   │
│ 192.168.122.0/24    │◄──router──┤ 10.0.0.0/24             │
│ (flat, physnet1)    │  gateway  │ (VXLAN)                 │
│                     │           │                         │
│ VMs get floating    │           │ VMs get fixed IPs       │
│ IPs from this pool  │           │ via DHCP                │
└─────────────────────┘           └─────────────────────────┘
```

### Create an External (Provider) Network

The external network connects VMs to the outside world. It uses a flat network mapped to `enp2s0` on the host.

```bash
# Create the external network (admin only)
openstack network create external-net \
  --external \
  --provider-network-type flat \
  --provider-physical-network physnet1 \
  --share

# Create subnet for external network
openstack subnet create external-subnet \
  --network external-net \
  --subnet-range 192.168.122.0/24 \
  --allocation-pool start=192.168.122.200,end=192.168.122.250 \
  --gateway 192.168.122.1 \
  --dns-nameserver 8.8.8.8 \
  --no-dhcp
```

> **Note:** `--no-dhcp` is important for the external network. Floating IPs are assigned manually, not via DHCP.

### Create an Internal (Project) Network

Internal networks use VXLAN overlay and provide isolated connectivity for VMs within a project.

```bash
# Create the internal network
openstack network create mynet

# Create subnet with DHCP
openstack subnet create mynet-subnet \
  --network mynet \
  --subnet-range 10.0.0.0/24 \
  --gateway 10.0.0.1 \
  --dns-nameserver 8.8.8.8

# Create a second internal network (for multi-tier)
openstack network create backend-net

openstack subnet create backend-subnet \
  --network backend-net \
  --subnet-range 10.1.0.0/24 \
  --gateway 10.1.0.1 \
  --dns-nameserver 8.8.8.8
```

### Create a Router (Connect Internal to External)

A router connects internal networks to the external network, enabling floating IP assignment and internet access.

```bash
# Create router
openstack router create router1

# Set the external gateway
openstack router set router1 --external-gateway external-net

# Connect internal network to router
openstack router add subnet router1 mynet-subnet

# Verify
openstack router show router1
openstack router port list router1
```

### Create a Shared Network (All Projects)

```bash
openstack network create shared-net --share --shared
openstack subnet create shared-subnet \
  --network shared-net \
  --subnet-range 10.2.0.0/24 \
  --allocation-pool start=10.2.0.10,end=10.2.0.200
```

### Manage Networks

```bash
# List all networks
openstack network list

# Show network details
openstack network show mynet

# Delete a network
openstack network delete mynet

# List subnets
openstack subnet list

# List routers
openstack router list

# Remove a subnet from a router
openstack router remove subnet router1 mynet-subnet
```

---

## How To: Create Security Groups

Security groups act as virtual firewalls controlling inbound/outbound traffic to VMs.

### Default Behavior

By default, a security group allows ALL outbound traffic but NO inbound traffic.

### Create a Basic Security Group (SSH + ICMP)

```bash
openstack security group create basic

# Allow SSH
openstack security group rule create basic \
  --protocol tcp \
  --dst-port 22 \
  --remote-ip 0.0.0.0/0

# Allow ICMP (ping)
openstack security group rule create basic \
  --protocol icmp \
  --remote-ip 0.0.0.0/0
```

### Create a Web Server Security Group

```bash
openstack security group create web-server

# Allow HTTP
openstack security group rule create web-server \
  --protocol tcp \
  --dst-port 80 \
  --remote-ip 0.0.0.0/0

# Allow HTTPS
openstack security group rule create web-server \
  --protocol tcp \
  --dst-port 443 \
  --remote-ip 0.0.0.0/0

# Allow SSH
openstack security group rule create web-server \
  --protocol tcp \
  --dst-port 22 \
  --remote-ip 0.0.0.0/0

# Allow ICMP
openstack security group rule create web-server \
  --protocol icmp \
  --remote-ip 0.0.0.0/0
```

### Create a Database Security Group (Restricted)

```bash
openstack security group create db-server

# Allow MySQL from internal network only
openstack security group rule create db-server \
  --protocol tcp \
  --dst-port 3306 \
  --remote-ip 10.0.0.0/24

# Allow SSH from specific IP
openstack security group rule create db-server \
  --protocol tcp \
  --dst-port 22 \
  --remote-ip 192.168.122.17
```

### Create an All-Open Security Group (Lab Only)

```bash
openstack security group create open

# Allow all IPv4 traffic
openstack security group rule create open \
  --protocol any \
  --remote-ip 0.0.0.0/0
```

### Manage Security Groups

```bash
# List all security groups
openstack security group list

# Show security group rules
openstack security group rule list basic

# Add a rule
openstack security group rule create basic \
  --protocol tcp --dst-port 8080 --remote-ip 0.0.0.0/0

# Delete a rule (use the rule ID from rule list)
openstack security group rule delete <rule-id>

# Delete a security group
openstack security group delete open
```

---

## How To: Create Key Pairs

Key pairs provide SSH access to VMs without passwords.

### Create a Key Pair

```bash
# Generate and import in one step
openstack keypair create mykey > ~/.ssh/mykey.pem
chmod 600 ~/.ssh/mykey.pem

# Use with: openstack server create --key-name mykey ...
```

### Import an Existing Public Key

```bash
openstack keypair create --public-key ~/.ssh/id_ed25519.pub mykey
```

### Manage Key Pairs

```bash
# List key pairs
openstack key pair list

# Delete a key pair
openstack key pair delete mykey

# Show key pair details
openstack key pair show mykey
```

---

## How To: Create VMs (Servers)

### Boot a Basic VM

```bash
openstack server create my-vm \
  --flavor m1.tiny \
  --image cirros \
  --network mynet \
  --key-name mykey \
  --security-group basic
```

### Boot a VM with Floating IP

```bash
# Create the VM
openstack server create web-vm \
  --flavor m1.small \
  --image ubuntu-noble \
  --network mynet \
  --key-name mykey \
  --security-group web-server

# Wait for it to boot
openstack server show web-vm -f value -c status
sleep 30

# Create and assign a floating IP
openstack floating ip create external-net
FLOAT_IP=$(openstack floating ip list -c "Floating IP Address" -f value | head -1)
openstack server add floating ip web-vm "$FLOAT_IP"

# Test connectivity
ping $FLOAT_IP
ssh -i ~/.ssh/mykey.pem ubuntu@$FLOAT_IP
```

### Boot a VM with Multiple Networks

```bash
openstack server create multi-net-vm \
  --flavor m1.medium \
  --image ubuntu-noble \
  --network mynet \
  --network backend-net \
  --key-name mykey \
  --security-group basic
```

### Boot a VM with User Data (Cloud-Init)

```bash
# Create a cloud-init script
cat > /tmp/userdata.txt << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx
echo "<h1>Hello from OpenStack!</h1>" > /var/www/html/index.html
EOF

# Boot with user data
openstack server create web-server \
  --flavor m1.small \
  --image ubuntu-noble \
  --network mynet \
  --key-name mykey \
  --security-group web-server \
  --user-data /tmp/userdata.txt
```

### Boot a VM with Block Storage

```bash
# Create a volume
openstack volume create --size 10 --image ubuntu-noble my-volume

# Boot from volume
openstack server create vm-with-volume \
  --flavor m1.small \
  --volume my-volume \
  --network mynet \
  --key-name mykey \
  --security-group basic
```

### Boot a VM from a Volume Snapshot

```bash
# Snapshot an existing volume
openstack volume snapshot create my-snap --volume my-volume

# Boot from snapshot
openstack server create vm-from-snap \
  --flavor m1.small \
  --image my-snap \
  --network mynet \
  --key-name mykey
```

### Manage VMs

```bash
# List all VMs
openstack server list

# List VMs across all projects
openstack server list --all-projects

# Show VM details
openstack server show my-vm

# Start / Stop / Reboot
openstack server start my-vm
openstack server stop my-vm
openstack server reboot my-vm
openstack server reboot --hard my-vm   # Hard reboot

# Delete a VM
openstack server delete my-vm

# Force delete a stuck VM
openstack server delete my-vm --wait

# Delete all VMs in a project
openstack server purge --all

# Rebuild a VM (re-install OS from image)
openstack server rebuild my-vm --image ubuntu-nable --key-name mykey

# Resize a VM
openstack server resize my-vm m1.medium
openstack server resize confirm my-vm    # After verifying
openstack server resize revert my-vm     # If something went wrong

# SSH into a VM
ssh -i ~/.ssh/mykey.pem ubuntu@$FLOAT_IP

# Get VM console log
openstack console log show my-vm
```

---

## How To: Assign Floating IPs

Floating IPs provide external access to VMs.

### Create and Assign

```bash
# Create a floating IP
openstack floating ip create external-net

# List floating IPs
openstack floating ip list

# Assign to a VM
openstack floating ip add floating ip my-vm <FLOAT_IP>

# Remove from a VM
openstack floating ip remove floating ip my-vm <FLOAT_IP>

# Delete a floating IP
openstack floating ip delete <FLOAT_IP>
```

### Map Floating IP to Port (Advanced)

```bash
# Find the VM's port
PORT_ID=$(openstack port list --server my-vm -c ID -f value | head -1)

# Assign floating IP to specific port
openstack floating ip set <FLOAT_IP> --port $PORT_ID
```

---

## How To: Create Volumes (Block Storage)

Volumes provide persistent block storage that survives VM deletion.

### Create Volumes

```bash
# Create an empty volume
openstack volume create --size 10 my-volume

# Create a volume from an image
openstack volume create --size 20 --image ubuntu-noble boot-volume

# Create a volume from a snapshot
openstack volume create --size 10 --snapshot my-snapshot restored-volume

# Create a bootable volume
openstack volume create --size 20 --image ubuntu-noble --bootable boot-vol
```

### Attach Volumes to VMs

```bash
# Attach
openstack server add volume my-vm my-volume

# Detach
openstack server remove volume my-vm my-volume
```

### Create Volume Snapshots

```bash
# Create snapshot
openstack volume snapshot create my-snapshot --volume my-volume

# List snapshots
openstack volume snapshot list

# Delete snapshot
openstack volume snapshot delete my-snapshot
```

### Manage Volumes

```bash
# List volumes
openstack volume list

# Show volume details
openstack volume show my-volume

# Delete a volume
openstack volume delete my-volume

# Extend a volume (online, no downtime)
openstack volume set my-volume --size 20

# Set volume properties
openstack volume set my-volume --property type=ssd
```

---

## How To: Create and Use Databases

OpenStack doesn't provide a managed database service by default. Here's how to run databases inside VMs.

### Option 1: Install MySQL in a VM

```bash
# Boot a VM
openstack server create db-server \
  --flavor m1.medium \
  --image ubuntu-noble \
  --network mynet \
  --key-name mykey \
  --security-group db-server

# SSH in and install MySQL
ssh -i ~/.ssh/mykey.pem ubuntu@$FLOAT_IP

sudo apt update
sudo apt install -y mysql-server mysql-client

# Secure installation
sudo mysql_secure_installation

# Create a database
sudo mysql -u root -p
CREATE DATABASE myapp;
CREATE USER 'myapp'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON myapp.* TO 'myapp'@'%';
FLUSH PRIVILEGES;
EXIT;

# Enable remote access
sudo sed -i 's/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql
```

### Option 2: Install PostgreSQL in a VM

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib

# Create database and user
sudo -u postgres psql
CREATE USER myapp WITH PASSWORD 'password';
CREATE DATABASE myapp OWNER myapp;
GRANT ALL PRIVILEGES ON DATABASE myapp TO myapp;
\q

# Enable remote access
sudo sed -i "s/listen_addresses\s*=\s'localhost'/listen_addresses = '*'/" /etc/postgresql/16/main/postgresql.conf
echo "host myapp all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
sudo systemctl restart postgresql
```

### Option 3: Use Docker for Database

```bash
# Install Docker in the VM
sudo apt install -y docker.io

# Run MySQL in a container
sudo docker run -d \
  --name mysql \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=myapp \
  -e MYSQL_USER=myapp \
  -e MYSQL_PASSWORD=password \
  -p 3306:3306 \
  -v mysql-data:/var/lib/mysql \
  --restart unless-stopped \
  mysql:8.0

# Run PostgreSQL in a container
sudo docker run -d \
  --name postgres \
  -e POSTGRES_USER=myapp \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=myapp \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:16-alpine

# Run Redis in a container
sudo docker run -d \
  --name redis \
  -p 6379:6379 \
  --restart unless-stopped \
  redis:7-alpine
```

### Option 4: Use OpenStack DBaaS (Trove) — Advanced

Trove is OpenStack's database-as-a-service. It requires additional setup:

```bash
# This is NOT included in the default deployment
# To enable it, add to globals.yml:
# enable_trove: "yes"
# enable_trove_nova: "yes"
# enable_trove_neutron: "yes"

# After deploying Trove:
openstack database flavor create db.tiny --vcpus 1 --ram 1024 --volume 10
openstack database instance create my-db \
  --flavor db.tiny \
  --size 10 \
  --datastore mysql \
  --databases myapp \
  --users myapp:password \
  --network mynet
```

---

## How To: Use Horizon Dashboard

### Access Horizon

```
http://192.168.122.17/dashboard
```

- **Username:** `admin`
- **Password:** From `/etc/kolla/passwords.yml` → `keystone_admin_password`

### What You Can Do in Horizon

| Tab | Function |
|-----|----------|
| **Project → Compute → Instances** | Create, start, stop, resize VMs |
| **Project → Compute → Images** | Upload and manage OS images |
| **Project → Compute → Flavors** | Create VM sizing profiles |
| **Project → Network → Networks** | Create internal networks |
| **Project → Network → Routers** | Connect networks to external |
| **Project → Network → Security Groups** | Configure firewall rules |
| **Project → Compute → Key Pairs** | Manage SSH keys |
| **Project → Volumes → Volumes** | Create and manage block storage |
| **Admin → System → Hosts** | View infrastructure |
| **Admin → System → Services** | Check service health |

---

## How To: Complete LAMP Stack Example

This example sets up a full web server with database:

```bash
# 1. Create network infrastructure
openstack network create web-net
openstack subnet create web-subnet --network web-net --subnet-range 10.0.0.0/24
openstack router create web-router
openstack router set web-router --external-gateway external-net
openstack router add subnet web-router web-subnet

# 2. Create security groups
openstack security group create lamp
openstack security group rule create lamp --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0
openstack security group rule create lamp --protocol tcp --dst-port 80 --remote-ip 0.0.0.0/0
openstack security group rule create lamp --protocol tcp --dst-port 443 --remote-ip 0.0.0.0/0
openstack security group rule create lamp --protocol icmp --remote-ip 0.0.0.0/0

# 3. Create key pair
openstack keypair create lamp-key > ~/.ssh/lamp-key.pem
chmod 600 ~/.ssh/lamp-key.pem

# 4. Boot web server
cat > /tmp/web-init.sh << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y apache2 php php-mysql libapache2-mod-php
cat > /var/www/html/info.php << PHP
<?php phpinfo(); ?>
PHP
systemctl restart apache2
EOF

openstack server create web \
  --flavor m1.small \
  --image ubuntu-noble \
  --network web-net \
  --key-name lamp-key \
  --security-group lamp \
  --user-data /tmp/web-init.sh

# 5. Boot database server
cat > /tmp/db-init.sh << 'EOF'
#!/bin/bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
mysql -u root -e "CREATE USER 'webapp'@'%' IDENTIFIED BY 'secretpass';"
mysql -u root -e "CREATE DATABASE webapp;"
mysql -u root -e "GRANT ALL ON webapp.* TO 'webapp'@'%';"
sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql
EOF

openstack server create db \
  --flavor m1.small \
  --image ubuntu-noble \
  --network web-net \
  --key-name lamp-key \
  --security-group db-server \
  --user-data /tmp/db-init.sh

# 6. Assign floating IPs
openstack floating ip create external-net
WEB_IP=$(openstack floating ip list -c "Floating IP Address" -f value | head -1)
openstack server add floating ip web "$WEB_IP"

openstack floating ip create external-net
DB_IP=$(openstack floating ip list -c "Floating IP Address" -f value | tail -1)
openstack server add floating ip db "$DB_IP"

echo "Web: http://$WEB_IP/info.php"
echo "DB:  mysql -h $DB_IP -u webapp -p"
```

---

## How To: Kubernetes Cluster (kubeadm)

### Boot 3 VMs for Kubernetes

```bash
# Create security group
openstack security group create k8s
openstack security group rule create k8s --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0
openstack security group rule create k8s --protocol tcp --dst-port 6443 --remote-ip 0.0.0.0/0
openstack security group rule create k8s --protocol icmp --remote-ip 0.0.0.0/0
openstack security group rule create k8s --protocol tcp --dst-port 10250:10255 --remote-ip 0.0.0.0/0
openstack security group rule create k8s --protocol tcp --dst-port 30000:32767 --remote-ip 0.0.0.0/0

# Create key pair
openstack keypair create k8s-key > ~/.ssh/k8s-key.pem
chmod 600 ~/.ssh/k8s-key.pem

# Create network
openstack network create k8s-net
openstack subnet create k8s-subnet --network k8s-net --subnet-range 10.0.0.0/24
openstack router create k8s-router
openstack router set k8s-router --external-gateway external-net
openstack router add subnet k8s-router k8s-subnet

# Boot nodes
for i in 1 2 3; do
  openstack server create k8s-node-$i \
    --flavor m1.medium \
    --image ubuntu-noble \
    --network k8s-net \
    --key-name k8s-key \
    --security-group k8s
done

# Assign floating IPs to all nodes
for i in 1 2 3; do
  openstack floating ip create external-net
  IP=$(openstack floating ip list -c "Floating IP Address" -f value | tail -1)
  openstack server add floating ip k8s-node-$i $IP
done

# Install Kubernetes on all nodes (run on each)
# See: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
```

---

## How To: Troubleshooting

### Services Down

```bash
# Check all services
openstack service list
openstack compute service list
openstack network agent list

# Check specific container
docker ps -a | grep nova
docker logs nova-api --tail 50

# Restart a service
docker restart nova-api

# Nuclear restart (fixes most issues)
./openstack-lab.zsh post-fix
```

### VM Stuck in BUILD

```bash
# Check compute host
openstack compute service list

# Check nova-scheduler logs
docker logs nova-scheduler --tail 50

# Check nova-conductor logs
docker logs nova-conductor --tail 50

# Force delete stuck VM
openstack server delete <vm-id> --wait
```

### Network Unreachable

```bash
# Check neutron agents
openstack network agent list

# Check OVS bridges
sudo ovs-vsctl show

# Bring up external interface
sudo ip link set enp2s0 up

# Check router namespace
sudo ip netns list
sudo ip netns exec qrouter-<id> ip addr show
sudo ip netns exec qrouter-<id> ip route

# Check security groups
openstack security group rule list basic
```

### Floating IP Not Working

```bash
# Verify floating IP is assigned
openstack floating ip list

# Check router external gateway
openstack router show router1

# Check OVS bridges
sudo ovs-vsctl show

# Bring up enp2s0
sudo ip link set enp2s0 up

# Check iptables in router namespace
sudo ip netns exec qrouter-<id> iptables -t nat -L -n
```

### Password/Auth Errors

```bash
# Fix passwords (run on guest)
./openstack-lab.zsh post-fix

# Or manually:
# 1. Read passwords from /etc/kolla/passwords.yml
# 2. Reset RabbitMQ users
docker exec rabbitmq rabbitmqctl change_password openstack <password>
# 3. Reset MariaDB users
docker exec mariadb mysql -u root -p<root-pass> -e "ALTER USER 'nova'@'%' IDENTIFIED BY '<new-pass>';"
# 4. Fix config files
find /etc/kolla -name "*.conf" -exec grep -l "rabbit" {} \; | xargs sed -i "s/rabbit:[^@]*@/rabbit:<pass>@/g"
# 5. Restart containers
docker restart $(docker ps -q)
```

### VM Cannot SSH

```bash
# Check if VM is running
openstack server list

# Check security group rules
openstack security group rule list basic

# Check if key pair is correct
openstack key pair list

# Get console log
openstack console log show my-vm

# Try console access
openstack console url show my-vm
```

### MariaDB Connection Refused

```bash
# Check MariaDB container
docker ps | grep mariadb
docker logs mariadb --tail 50

# Test connection
docker exec mariadb mysql -u root -p<password> -e "SHOW DATABASES;"

# Reset root password
docker exec mariadb mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'newpassword';"
```

### RabbitMQ Authentication Failed

```bash
# Check RabbitMQ status
docker exec rabbitmq rabbitmqctl status

# List users
docker exec rabbitmq rabbitmqctl list_users

# Reset user password
docker exec rabbitmq rabbitmqctl change_password openstack <new-password>

# Fix all configs
find /etc/kolla -name "*.conf" -exec grep -l "rabbit" {} \; | \
  xargs sed -i "s|rabbit://openstack:[^@]*@|rabbit://openstack:<password>@|g"
```

---

## How To: Backup and Restore

### Backup OpenStack Config

```bash
# Backup Kolla configs
ssh stack@192.168.122.17 'sudo tar czf /tmp/kolla-backup.tar.gz /etc/kolla/'
scp stack@192.168.122.17:/tmp/kolla-backup.tar.gz ./kolla-backup.tar.gz

# Backup databases
ssh stack@192.168.122.17 'bash -s' << 'EOF'
docker exec mariadb mysqldump -u root -p$(grep database_password /etc/kolla/passwords.yml | awk '{print $2}') \
  --all-databases > /tmp/all-databases.sql
EOF
scp stack@192.168.122.17:/tmp/all-databases.sql ./all-databases.sql

# Backup VM images
virsh dumpxml openstack-lab-01 > ./vm-backup.xml
cp /mnt/AI/homelab/openstack-lab-01.qcow2 ./vm-disk-backup.qcow2
```

### Restore from Backup

```bash
# Restore Kolla configs
scp ./kolla-backup.tar.gz stack@192.168.122.17:/tmp/
ssh stack@192.168.122.17 'sudo tar xzf /tmp/kolla-backup.tar.gz -C /'

# Restore databases
scp ./all-databases.sql stack@192.168.122.17:/tmp/
ssh stack@192.168.122.17 'bash -s' << 'EOF'
docker exec -i mariadb mysql -u root -p$(grep database_password /etc/kolla/passwords.yml | awk '{print $2}') \
  < /tmp/all-databases.sql
EOF

# Restart all containers
ssh stack@192.168.122.17 'docker restart $(docker ps -q)'
```

---

## How To: Monitor and Metrics

### Check System Health

```bash
# Host resources
free -h
df -h
uptime

# Docker stats
docker stats --no-stream

# OpenStack resource usage
openstack quota show
openstack usage list --start $(date -d '1 month ago' +%Y-%m-%d) --end $(date +%Y-%m-%d)
```

### Service Status

```bash
# All OpenStack services
openstack service list

# Compute services
openstack compute service list

# Network agents
openstack network agent list

# Volume services
openstack volume service list

# Hypervisor stats
openstack hypervisor stats show
openstack hypervisor list
```

---

## File Structure

```
openstack-kvm-lab/
├── openstack-lab.zsh          # Main CLI entry point
├── AGENTS.md                  # Agent instructions
├── README.md                  # This file
├── .gitignore
│
├── config/
│   ├── lab.conf               # All configuration
│   ├── lab.conf.example       # Example config
│   ├── secrets.conf           # Passwords (not in git)
│   └── secrets.conf.example   # Password template
│
├── lib/                       # Modular functions
│   ├── common.zsh             # Constants, utilities
│   ├── logging.zsh            # Timestamped logging
│   ├── config.zsh             # Config loading/validation
│   ├── preflight.zsh          # Host readiness checks
│   ├── libvirt.zsh            # VM management
│   ├── cloudinit.zsh          # Cloud-init templates
│   ├── guest.zsh              # Guest preparation
│   ├── kolla.zsh              # Kolla-Ansible management
│   ├── verify.zsh             # Post-deploy verification
│   ├── cleanup.zsh            # Destroy resources
│   └── status.zsh             # Status and diagnostics
│
├── stages/                    # Stage scripts (future)
├── cloud-init/
│   ├── user-data              # Cloud-init user data
│   └── meta-data              # Cloud-init metadata
├── templates/
│   └── multinode              # Kolla inventory template
├── state/                     # *.ok stage markers
├── logs/                      # Timestamped operation logs
└── tests/
    ├── test-config.zsh        # Config validation tests
    ├── test-preflight.zsh     # Preflight check tests
    └── test-destroy-safety.zsh # Destroy safety tests
```

## Design Principles

### Idempotent

Every stage checks if it's already completed. Running `build` twice is safe.

### Modular

Each concern is a separate file in `lib/`. Never create one giant script.

### Fail Fast

Errors include: stage, command, reason, suggested action, and log file location.

### No Host Damage

Never modifies host network configuration. Uses libvirt NAT only.

### No Hard-Coded Values

All paths, IPs, and settings come from `config/lab.conf`.

## Known Issues

### enp2s0 DOWN After Restart

The external network interface (`enp2s0`) may be DOWN after VM restart. Fix:

```bash
sudo ip link set enp2s0 up
```

Or run the post-fix command:

```bash
./openstack-lab.zsh post-fix
```

### kolla-genpwd Password Regeneration

`kolla-ansible deploy` regenerates some passwords in config files even when `passwords.yml` has values. The `post-fix` command handles this automatically.

### Nova Cell Mapping Stale

After password changes, Nova cell mappings contain old DB credentials. The `post-fix` command updates them.

## How To: Deploy Octavia LBaaS

Octavia is enabled and deployable, but requires several manual steps documented in [`OCTAVIA.md`](./OCTAVIA.md). Key points:

1. Build amphora image with the official `diskimage-create.sh` (4GB disk)
2. Create `lb-mgmt-net` as VLAN 100 on physnet1
3. Create `veth-mgmt` OVS internal port on br-ex with tag 100 (IP 10.1.0.10)
4. Delete the duplicate `enp2s0.100` VLAN interface that shadows `veth-mgmt`
5. Add port 5555 (TCP+UDP) to the lb-mgmt security group
6. Fix `health_manager bind_ip` and `controller_ip_port_list` to `10.1.0.10`
7. Fix `max_pool_size = 10` in all four octavia configs
8. Always edit `/etc/kolla/octavia-*/octavia.conf` (source), not container config

See `OCTAVIA.md` for the full deployment walkthrough and troubleshooting guide.

## Contributing

1. Test changes on a fresh deployment
2. Run `zsh tests/test-config.zsh` and `zsh tests/test-preflight.zsh`
3. Verify `./openstack-lab.zsh preflight` passes
4. Commit after each successful phase for rollback points

## License

[Add your license here]
