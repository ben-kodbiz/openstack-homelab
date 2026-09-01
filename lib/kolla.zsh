#!/usr/bin/env zsh
# kolla.zsh — Kolla-Ansible installation and management

set -euo pipefail

# Install Kolla-Ansible in a virtual environment on the guest
kolla_install() {
    local ip="$1"
    log_info "Installing Kolla-Ansible on guest..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<REMOTE
set -euo pipefail

# Build deps for dbus-python
sudo apt-get install -y python3-dev libdbus-1-dev libdbus-glib-1-dev pkg-config meson >/dev/null 2>&1

# Create virtual environment
sudo python3 -m venv ${KOLLA_VENV}
sudo chown -R stack:stack ${KOLLA_VENV}

# Install kolla-ansible for the configured OpenStack version
${KOLLA_VENV}/bin/pip install --upgrade pip >/dev/null 2>&1
${KOLLA_VENV}/bin/pip install \
    'kolla-ansible==${KOLLA_OS_VERSION}.*' \
    docker dbus-python >/dev/null 2>&1

# Pin ansible-core to compatible version
${KOLLA_VENV}/bin/pip install 'ansible-core>=2.19,<2.20' >/dev/null 2>&1

# Install required Ansible Galaxy collections
${KOLLA_VENV}/bin/ansible-galaxy collection install \
    ansible.utils community.general openstack.cloud >/dev/null 2>&1

# Verify installation
${KOLLA_VENV}/bin/kolla-ansible --version

# Create /etc/kolla directory
sudo mkdir -p ${KOLLA_CONFIG_DIR}
sudo chown stack:stack ${KOLLA_CONFIG_DIR}

echo "Kolla-Ansible installed"
REMOTE

    log_ok "Kolla-Ansible installed"
}

# Generate globals.yml and multinode inventory
kolla_generate_config() {
    local ip="$1"
    log_info "Generating Kolla configuration..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<REMOTE
set -euo pipefail

# Create passwords.yml skeleton with ONLY password-like keys
python3 -c "
import yaml, os, re, subprocess

result = subprocess.run(
    ['grep', '-rohP', r'\{\{\s*([a-z_]+)\s*\}\}',
     '/opt/kolla-venv/share/kolla-ansible/ansible/'],
    capture_output=True, text=True, errors='ignore'
)
all_vars = set()
for line in result.stdout.split('\n'):
    m = re.match(r'\{\{\s*([a-z_]+)\s*\}\}', line)
    if m:
        all_vars.add(m.group(1))

# Only keep actual password/key/secret/uuid/token/salt entries
valid_re = re.compile(r'(password|secret|_key\$|cookie|uuid|token|salt|hmac|fernet|bcrypt|crypto|rndc|cluster_cookie|master_password|db_admin_password)\$')
ssh_keys = {'kolla_ssh_key','nova_ssh_key','keystone_ssh_key','bifrost_ssh_key',
            'octavia_amp_ssh_key','neutron_ssh_key','haproxy_ssh_key'}
uuid_keys = {'rbd_secret_uuid','cinder_rbd_secret_uuid','gnocchi_project_id',
             'gnocchi_resource_id','gnocchi_user_id','designate_pool_id'}

passwords = {}
for v in sorted(all_vars):
    if v in ssh_keys or v in uuid_keys or valid_re.search(v):
        passwords[v] = None

with open('/etc/kolla/passwords.yml', 'w') as f:
    yaml.safe_dump(passwords, f, default_flow_style=False)
os.chmod('/etc/kolla/passwords.yml', 0o600)
print(f'Skeleton: {len(passwords)} entries')
"

# Fill in the passwords
${KOLLA_VENV}/bin/kolla-genpwd
echo "Passwords: \$(wc -l < /etc/kolla/passwords.yml) lines"
echo "enable_ keys: \$(grep -c 'enable_' /etc/kolla/passwords.yml || echo 0)"

# Generate globals.yml
cat > ${KOLLA_CONFIG_DIR}/globals.yml <<GLOBALS
---
kolla_base_distro: "${KOLLA_BASE_DISTRO}"
kolla_base_tag: "${KOLLA_BASE_TAG}"
kolla_internal_vip_address: ""
kolla_external_vip_address: ""

# Networking
kolla_internal_fqdn: "${GUEST_HOSTNAME}"
network_interface: "${MGMT_INTERFACE}"
neutron_external_interface: "${EXTERNAL_INTERFACE}"
docker_registry: "quay.io"

# Enable core services
enable_haproxy: "no"
enable_nginx: "no"
enable_proxysql: "no"

# Services
enable_keystone: "yes"
enable_glance: "yes"
enable_nova: "yes"
enable_neutron: "yes"
enable_placement: "yes"
enable_horizon: "yes"

# Infrastructure
enable_mariadb: "yes"
enable_rabbitmq: "yes"
enable_memcached: "yes"

# Disable non-essential
enable_cinder: "no"
enable_swift: "no"
enable_heat: "no"
enable_octavia: "no"
enable_barbican: "no"
enable_designate: "no"
enable_magnum: "no"
enable_opensearch: "no"
enable_opensearch_dashboards: "no"
enable_prometheus: "no"
enable_grafana: "no"
enable_fluentd: "no"
enable_cron: "yes"
GLOBALS

# Copy all-in-one inventory
cp /opt/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one ${KOLLA_CONFIG_DIR}/all-in-one

echo "Kolla configuration generated"
REMOTE

    log_ok "Kolla configuration generated"
}

# Run Kolla prechecks
kolla_prechecks() {
    local ip="$1"
    log_info "Running Kolla prechecks..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" \
        "${KOLLA_VENV}/bin/kolla-ansible -i ${KOLLA_CONFIG_DIR}/all-in-one prechecks" || {
        die "prechecks" "kolla-ansible prechecks" "Prechecks failed" \
            "Fix reported issues before deployment"
    }
    log_ok "Kolla prechecks passed"
}

# Run Kolla bootstrap
kolla_bootstrap() {
    local ip="$1"
    log_info "Running Kolla bootstrap..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" \
        "${KOLLA_VENV}/bin/kolla-ansible -i ${KOLLA_CONFIG_DIR}/all-in-one bootstrap-servers" || {
        die "bootstrap" "kolla-ansible bootstrap" "Bootstrap failed" \
            "Check logs on guest: journalctl -u docker"
    }
    log_ok "Kolla bootstrap complete"
}

# Run Kolla deployment
kolla_deploy() {
    local ip="$1"
    log_info "Running Kolla deployment..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" \
        "${KOLLA_VENV}/bin/kolla-ansible -i ${KOLLA_CONFIG_DIR}/all-in-one deploy" || {
        die "deploy" "kolla-ansible deploy" "Deployment failed" \
            "Check logs on guest: docker ps -a"
    }
    log_ok "Kolla deployment complete"
}

# Generate admin credentials
kolla_create_admin_creds() {
    local ip="$1"
    log_info "Generating admin credentials..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<'REMOTE'
set -euo pipefail

# Create admin-openrc.sh
cat > ${KOLLA_CONFIG_DIR}/admin-openrc.sh <<'EOF'
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$(grep ^keystone_admin_password ${KOLLA_CONFIG_DIR}/passwords.yml | cut -d: -f2 | tr -d ' ')
export OS_AUTH_URL=http://localhost:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_TYPE=password
export OS_CACERT=
export OS_REGION_NAME=RegionOne
EOF

source ${KOLLA_CONFIG_DIR}/admin-openrc.sh
echo "Admin credentials configured"
REMOTE

    log_ok "Admin credentials ready"
}

# Post-deploy fix: reconcile passwords and networking
# Called after deploy to fix kolla-genpwd mismatches and enp2s0 DOWN issue
kolla_post_deploy_fix() {
    local ip="$1"
    log_info "Running post-deploy fixes..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<'REMOTE'
set -euo pipefail

CONFIG_DIR="/etc/kolla"
PASSWORDS="${CONFIG_DIR}/passwords.yml"

# --- Step 1: Read all passwords from passwords.yml ---
RABBIT_PASS=$(python3 -c "import yaml; print(yaml.safe_load(open('${PASSWORDS}'))['rabbitmq_password'])")
NOVA_DB_PASS=$(python3 -c "import yaml; print(yaml.safe_load(open('${PASSWORDS}'))['nova_database_password'])")
NOVA_API_DB_PASS=$(python3 -c "import yaml; print(yaml.safe_load(open('${PASSWORDS}'))['nova_api_database_password'])")
DB_ROOT_PASS=$(python3 -c "import yaml; print(yaml.safe_load(open('${PASSWORDS}'))['database_password'])")

echo "Passwords read from passwords.yml"

# --- Step 2: Fix RabbitMQ users ---
docker exec rabbitmq rabbitmqctl change_password openstack "${RABBIT_PASS}" 2>&1 || true
docker exec rabbitmq rabbitmqctl change_password nova "${RABBIT_PASS}" 2>&1 || true
echo "RabbitMQ users reset"

# --- Step 3: Fix MariaDB users for all host patterns ---
HOSTS=("%" "localhost" "openstack-lab-01")
USERS=("nova:${NOVA_DB_PASS}" "nova_api:${NOVA_API_DB_PASS}" "nova:${NOVA_DB_PASS}" "placement:${NOVA_DB_PASS}" "glance:${NOVA_DB_PASS}" "neutron:${NOVA_DB_PASS}" "keystone:${DB_ROOT_PASS}")

for entry in "${USERS[@]}"; do
    USER="${entry%%:*}"
    PASS="${entry##*:}"
    for H in "${HOSTS[@]}"; do
        docker exec mariadb mysql -u root -p"${DB_ROOT_PASS}" \
            -e "ALTER USER '${USER}'@'${H}' IDENTIFIED BY '${PASS}';" 2>/dev/null || true
    done
done
echo "MariaDB users reset"

# --- Step 4: Fix Nova cell mappings ---
docker exec mariadb mysql -u root -p"${DB_ROOT_PASS}" nova_api \
    -e "UPDATE cell_mappings SET json_contains(CAST(json_unquote(json_extract(json, '$.database_connection')) AS CHAR), '${NOVA_DB_PASS}') WHERE type='cell';" 2>/dev/null || \
docker exec mariadb mysql -u root -p"${DB_ROOT_PASS}" nova_api \
    -e "UPDATE cell_mappings SET json_set(json, '$.database_connection', REPLACE(json_unquote(json_extract(json, '$.database_connection')), SUBSTRING_INDEX(SUBSTRING_INDEX(json_unquote(json_extract(json, '$.database_connection')), '@', 1), '://', -1), 'nova:${NOVA_DB_PASS}@192.168.122.17/nova_cell0?null&%26read_default_transaction_isolation_level=READ-COMMITTED&unix_socket=/var/lib/kolla/share/volumes/mariadb/mysqld.sock')) WHERE type='cell';" 2>/dev/null || true
echo "Cell mappings updated"

# --- Step 5: Fix all config files with correct transport_url ---
find ${CONFIG_DIR} -name "*.conf" -exec grep -l "rabbit://openstack:" {} \; 2>/dev/null | while read conf; do
    sed -i "s|rabbit://openstack:[^@]*@|rabbit://openstack:${RABBIT_PASS}@|g" "$conf"
done
echo "Config files updated"

# --- Step 6: Bring up enp2s0 ---
ip link set enp2s0 up 2>/dev/null || true
echo "enp2s0 brought up"

# --- Step 7: Restart all services ---
docker restart $(docker ps -q) 2>/dev/null || true
sleep 30
echo "All containers restarted"

# --- Step 8: Verify ---
source /etc/kolla/admin-openrc.sh 2>/dev/null
NOVA_OK=$(openstack compute service list 2>/dev/null | grep -c " up " || echo "0")
echo "Nova services up: ${NOVA_OK}"
REMOTE

    log_ok "Post-deploy fixes applied"
}
