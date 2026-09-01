#!/usr/bin/env zsh
# scripts/start-openstack.zsh — Start OpenStack services in correct order
# Usage: ./scripts/start-openstack.zsh [--start-vm]

set -euo pipefail

START_VM="${1:-}"
GUEST_IP="192.168.122.17"
MAX_WAIT=30

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { log "OK    $*"; }
fail() { log "FAIL  $*"; return 1; }
warn() { log "WARN  $*"; }

# --- Start VM if requested ---
if [[ "${START_VM}" == "--start-vm" ]]; then
    log "=== Starting VM ==="
    STATE=$(virsh domstate openstack-lab-01 2>/dev/null || echo "not found")
    if [[ "${STATE}" == "shut off" ]] || [[ "${STATE}" == "paused" ]]; then
        virsh start openstack-lab-01 2>/dev/null
        ok "VM start signal sent"
    elif [[ "${STATE}" == "running" ]]; then
        ok "VM already running"
    else
        fail "VM in unexpected state: ${STATE}"
    fi

    # Wait for SSH
    log "Waiting for SSH..."
    for i in $(seq 1 ${MAX_WAIT}); do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 "stack@${GUEST_IP}" 'true' 2>/dev/null; then
            ok "SSH ready after ${i}s"
            break
        fi
        sleep 2
    done

    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 "stack@${GUEST_IP}" 'true' 2>/dev/null; then
        fail "SSH not available after ${MAX_WAIT}s"
        exit 1
    fi
fi

# Check if guest is reachable
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 "stack@${GUEST_IP}" 'true' 2>/dev/null; then
    fail "Guest ${GUEST_IP} unreachable — use --start-vm or start VM manually"
    exit 1
fi
ok "Guest reachable"

# Bring up enp2s0 (known issue: interface down after restart)
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'sudo ip link set enp2s0 up 2>/dev/null || true'
ok "enp2s0 ensured UP"

run() {
    local desc="$1"
    shift
    if ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" "$@" 2>/dev/null; then
        ok "${desc}"
        return 0
    else
        fail "${desc}"
        return 1
    fi
}

wait_healthy() {
    local container="$1"
    local max="${2:-30}"
    for i in $(seq 1 ${max}); do
        STATUS=$(ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" \
            "docker inspect --format '{{.State.Health.Status}}' ${container} 2>/dev/null || echo 'missing'")
        if [[ "${STATUS}" == "healthy" ]]; then
            ok "${container} healthy (${i}s)"
            return 0
        elif [[ "${STATUS}" == "missing" ]]; then
            # Container without healthcheck — just check if running
            RUNNING=$(ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" \
                "docker inspect --format '{{.State.Running}}' ${container} 2>/dev/null || echo 'false'")
            if [[ "${RUNNING}" == "true" ]]; then
                ok "${container} running (${i}s)"
                return 0
            fi
        fi
        sleep 2
    done
    warn "${container} not healthy after ${max}s"
    return 1
}

# --- Phase 1: Data stores first (must be ready before services) ---
log "=== Phase 1: Data Stores ==="
run "Start Memcached" "docker start memcached"
run "Start RabbitMQ"  "docker start rabbitmq"
run "Start MariaDB"   "docker start mariadb"

log "Waiting for data stores to initialize..."
sleep 10

# Verify data stores
for svc in mariadb rabbitmq memcached; do
    STATUS=$(ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" \
        "docker inspect --format '{{.State.Status}}' ${svc} 2>/dev/null || echo 'missing'")
    if [[ "${STATUS}" != "running" ]]; then
        fail "${svc} failed to start (status: ${STATUS})"
        ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" "docker logs ${svc} --tail 10 2>&1"
        exit 1
    fi
done
ok "Data stores running"

# Verify MariaDB accepts connections
for i in $(seq 1 15); do
    if ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" \
        "docker exec mariadb mysqladmin ping 2>/dev/null" | grep -q "alive"; then
        ok "MariaDB accepting connections"
        break
    fi
    sleep 2
done

# Verify RabbitMQ accepts connections
for i in $(seq 1 15); do
    if ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" \
        "docker exec rabbitmq rabbitmqctl status 2>/dev/null" | grep -q "running_applications"; then
        ok "RabbitMQ accepting connections"
        break
    fi
    sleep 2
done

# --- Phase 2: Identity (must be up before any service authenticates) ---
log "=== Phase 2: Identity ==="
run "Start Keystone"        "docker start keystone"
run "Start Keystone Fernet" "docker start keystone_fernet"
run "Start Keystone SSH"    "docker start keystone_ssh"

log "Waiting for Keystone..."
sleep 10

# Verify Keystone responds
for i in $(seq 1 15); do
    if ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" \
        "curl -s http://192.168.122.17:5000/health 2>/dev/null" | grep -q -i "up\|ok\|true"; then
        ok "Keystone responding"
        break
    fi
    sleep 2
done

# --- Phase 3: Image service ---
log "=== Phase 3: Image ==="
run "Start Glance API" "docker start glance_api"
sleep 5

# --- Phase 4: Placement ---
log "=== Phase 4: Placement ==="
run "Start Placement API" "docker start placement_api"
sleep 5

# --- Phase 5: Networking (OVS must start before agents) ---
log "=== Phase 5: Networking ==="
run "Start OVS db-server"    "docker start openvswitch_db"
run "Start OVS vswitchd"     "docker start openvswitch_vswitchd"
log "Waiting for OVS to initialize..."
sleep 15

# Ensure enp2s0 is added to br-ex and up
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'bash -s' << 'OVSFIX'
docker exec openvswitch_db ovs-vsctl --if-exists add-port br-ex enp2s0 2>/dev/null || true
sudo ip link set enp2s0 up 2>/dev/null || true
OVSFIX
ok "enp2s0 ensured on br-ex"

run "Start Neutron Server"   "docker start neutron_server"
sleep 5
run "Start Neutron L3 Agent"       "docker start neutron_l3_agent"
run "Start Neutron DHCP Agent"     "docker start neutron_dhcp_agent"
run "Start Neutron Metadata Agent" "docker start neutron_metadata_agent"
run "Start Neutron OVS Agent"      "docker start neutron_openvswitch_agent"

log "Waiting for neutron OVS agent to program flows..."
sleep 15

# Restart OVS agent to ensure flows are re-programmed after OVS restart
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'docker restart neutron_openvswitch_agent 2>/dev/null || true'
sleep 10
# Ensure enp2s0 stays up after OVS agent restart
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'sudo ip link set enp2s0 up 2>/dev/null || true'
ok "Neutron OVS agent restarted for flow programming"

# --- Phase 6: Compute ---
log "=== Phase 6: Compute ==="
run "Start Nova API"         "docker start nova_api"
run "Start Nova API Metadata" "docker start nova_api"
sleep 5
run "Start Nova Scheduler"   "docker start nova_scheduler"
run "Start Nova Conductor"   "docker start nova_conductor"
run "Start Nova Compute"     "docker start nova_compute"
run "Start Nova Metadata"    "docker start nova_metadata"
run "Start Nova NoVNCProxy"  "docker start nova_novncproxy"
run "Start Nova SSH"         "docker start nova_ssh"

# --- Phase 7: Dashboard + Misc ---
log "=== Phase 7: Dashboard + Misc ==="
run "Start Horizon" "docker start horizon"
run "Start Cron"    "docker start cron"

# --- Phase 8: Verify services ---
log "=== Phase 8: Verification ==="
sleep 10

# Check running containers
TOTAL=$(ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'docker ps -q 2>/dev/null | wc -l')
log "Running containers: ${TOTAL}"

# Check OpenStack services
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'bash -s' << 'CHECK'
export PATH=/home/stack/.local/bin:$PATH
source /etc/kolla/admin-openrc.sh 2>/dev/null

echo "--- Nova services ---"
openstack compute service list 2>/dev/null || echo "FAIL: Nova API unreachable"

echo "--- Network agents ---"
openstack network agent list 2>/dev/null || echo "FAIL: Neutron API unreachable"

echo "--- Keystone ---"
openstack token issue 2>/dev/null | head -1 || echo "FAIL: Keystone unreachable"
CHECK

# Check enp2s0
ENP2S0=$(ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'cat /sys/class/net/enp2s0/operstate 2>/dev/null || echo "missing"')
if [[ "${ENP2S0}" == "up" ]]; then
    ok "enp2s0 is UP"
else
    warn "enp2s0 is ${ENP2S0} — floating IPs may not work"
    ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'sudo ip link set enp2s0 up 2>/dev/null || true'
fi

# --- Phase 9: Fix password mismatches (kolla-genpwd regenerates on container start) ---
log "=== Phase 9: Post-fix passwords ==="
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'bash -s' << 'FIXPASS'
set -euo pipefail

CONFIG_DIR="/etc/kolla"
PASSWORDS="${CONFIG_DIR}/passwords.yml"

RABBIT_PASS=$(python3 -c "import yaml; print(yaml.safe_load(open('${PASSWORDS}'))['rabbitmq_password'])")

# Fix RabbitMQ users
docker exec rabbitmq rabbitmqctl change_password openstack "${RABBIT_PASS}" 2>/dev/null || true
docker exec rabbitmq rabbitmqctl change_password nova "${RABBIT_PASS}" 2>/dev/null || true

# Fix all config files
find ${CONFIG_DIR} -name "*.conf" -exec grep -l "rabbit://openstack:" {} \; 2>/dev/null | while read conf; do
    sed -i "s|rabbit://openstack:[^@]*@|rabbit://openstack:${RABBIT_PASS}@|g" "$conf"
done

echo "Passwords fixed"
FIXPASS

# Restart services that had wrong passwords
log "Restarting services with fixed passwords..."
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'bash -s' << 'RESTART'
docker restart nova_scheduler nova_conductor nova_compute neutron_server neutron_l3_agent neutron_dhcp_agent neutron_metadata_agent neutron_openvswitch_agent 2>/dev/null || true
sleep 20
RESTART

# --- Final: ensure OVS agent is healthy and enp2s0 is up ---
log "=== Final: OVS + Network check ==="
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'bash -s' << 'FINALFIX'
sudo ip link set enp2s0 up 2>/dev/null || true
docker restart neutron_openvswitch_agent 2>/dev/null || true
sleep 30
sudo ip link set enp2s0 up 2>/dev/null || true
# Verify OVS agent is alive
docker logs neutron_openvswitch_agent --tail 3 2>&1 | tail -1
FINALFIX
ok "Final OVS + network check done"

# --- Start any SHUTOFF VMs (after all services are healthy) ---
log "=== Starting SHUTOFF VMs ==="
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'bash -s' << 'STARTVMS'
export PATH=/home/stack/.local/bin:$PATH
source /etc/kolla/admin-openrc.sh 2>/dev/null
SHUTOFF=$(openstack server list --all-projects -c Status -f value 2>/dev/null | grep -c "SHUTOFF" || echo "0")
if [[ "${SHUTOFF}" -gt "0" ]]; then
    echo "Starting ${SHUTOFF} SHUTOFF VM(s)..."
    openstack server list --all-projects -c Name -f value 2>/dev/null | while read vm; do
        STATUS=$(openstack server show "$vm" -c status -f value 2>/dev/null)
        if [[ "${STATUS}" == "SHUTOFF" ]]; then
            openstack server start "$vm" 2>/dev/null && echo "Started: ${vm}"
        fi
    done
    sleep 15
fi
STARTVMS

log "=== Startup complete ==="
