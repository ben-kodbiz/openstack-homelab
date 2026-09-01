#!/usr/bin/env zsh
# scripts/stop-openstack.zsh — Gracefully shut down OpenStack services
# Usage: ./scripts/stop-openstack.zsh [--shutdown-vm]

set -euo pipefail

SHUTDOWN_VM="${1:-}"
GUEST_IP="192.168.122.17"

log()  { echo "[$(date '+%H:%M:%S')] $*" }
ok()   { log "OK    $*"; }
fail() { log "FAIL  $*"; }
warn() { log "WARN  $*"; }

# Check if guest is reachable
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 "stack@${GUEST_IP}" 'true' 2>/dev/null; then
    fail "Guest ${GUEST_IP} unreachable"
    exit 1
fi
ok "Guest reachable"

run() {
    local desc="$1"
    shift
    if ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" "$@" 2>/dev/null; then
        ok "${desc}"
        return 0
    else
        warn "${desc} (may already be stopped)"
        return 0
    fi
}

# --- Phase 1: Stop API layer (stop accepting new requests) ---
log "=== Phase 1: API Layer ==="
run "Stop Horizon"          "docker stop horizon 2>/dev/null || true"
run "Stop Nova API"         "docker stop nova_api 2>/dev/null || true"
run "Stop Neutron Server"   "docker stop neutron_server 2>/dev/null || true"
run "Stop Placement API"    "docker stop placement_api 2>/dev/null || true"

# --- Phase 2: Stop compute/network workers (drain in-flight tasks) ---
log "=== Phase 2: Workers ==="
run "Stop Nova Scheduler"   "docker stop nova_scheduler 2>/dev/null || true"
run "Stop Nova Conductor"   "docker stop nova_conductor 2>/dev/null || true"
run "Stop Nova Compute"     "docker stop nova_compute 2>/dev/null || true"
run "Stop Nova Metadata"    "docker stop nova_metadata 2>/dev/null || true"
run "Stop Nova NoVNCProxy"  "docker stop nova_novncproxy 2>/dev/null || true"

# --- Phase 3: Stop networking agents ---
log "=== Phase 3: Networking ==="
run "Stop Neutron L3 Agent"       "docker stop neutron_l3_agent 2>/dev/null || true"
run "Stop Neutron DHCP Agent"     "docker stop neutron_dhcp_agent 2>/dev/null || true"
run "Stop Neutron Metadata Agent" "docker stop neutron_metadata_agent 2>/dev/null || true"
run "Stop Neutron OVS Agent"      "docker stop neutron_openvswitch_agent 2>/dev/null || true"
run "Stop OVS vswitchd"           "docker stop openvswitch_vswitchd 2>/dev/null || true"
run "Stop OVS db-server"          "docker stop openvswitch_db 2>/dev/null || true"

# --- Phase 4: Stop supporting services ---
log "=== Phase 4: Support ==="
run "Stop Keystone"         "docker stop keystone 2>/dev/null || true"
run "Stop Glance API"       "docker stop glance_api 2>/dev/null || true"
run "Stop Nova SSH"         "docker stop nova_ssh 2>/dev/null || true"
run "Stop Keystone Fernet"  "docker stop keystone_fernet 2>/dev/null || true"
run "Stop Keystone SSH"     "docker stop keystone_ssh 2>/dev/null || true"

# --- Phase 5: Stop data stores LAST (prevent data loss) ---
log "=== Phase 5: Data Stores ==="
run "Stop MariaDB"   "docker stop mariadb 2>/dev/null || true"
run "Stop RabbitMQ"  "docker stop rabbitmq 2>/dev/null || true"
run "Stop Memcached" "docker stop memcached 2>/dev/null || true"

# --- Phase 6: Stop cron ---
log "=== Phase 6: Misc ==="
run "Stop Cron" "docker stop cron 2>/dev/null || true"

# --- Stop any remaining containers (force kill) ---
log "=== Force stop remaining containers ==="
ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'bash -s' << 'STOPALL'
# Disable restart policy first
docker ps -aq 2>/dev/null | xargs -r docker update --restart=no 2>/dev/null
# Force kill all running containers
docker ps -q 2>/dev/null | xargs -r docker kill 2>/dev/null
sleep 2
STOPALL

# --- Verify all stopped ---
log "=== Verification ==="
RUNNING=$(ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'docker ps -q 2>/dev/null | wc -l')
if [[ "${RUNNING}" == "0" ]]; then
    ok "All containers stopped"
else
    warn "${RUNNING} container(s) still running"
    ssh -o StrictHostKeyChecking=no "stack@${GUEST_IP}" 'docker ps --format "{{.Names}}: {{.Status}}"'
fi

# --- Shutdown VM if requested ---
if [[ "${SHUTDOWN_VM}" == "--shutdown-vm" ]]; then
    log "=== Shutting down VM ==="
    virsh shutdown openstack-lab-01 2>/dev/null
    ok "Shutdown signal sent to VM"

    # Wait for VM to stop
    for i in $(seq 1 30); do
        STATE=$(virsh domstate openstack-lab-01 2>/dev/null || echo "unknown")
        if [[ "${STATE}" == "shut off" ]] || [[ "${STATE}" == "shut off" ]]; then
            ok "VM stopped"
            break
        fi
        sleep 2
    done

    STATE=$(virsh domstate openstack-lab-01 2>/dev/null || echo "unknown")
    if [[ "${STATE}" != "shut off" ]]; then
        warn "VM still running (state: ${STATE}), forcing off..."
        virsh destroy openstack-lab-01 2>/dev/null || true
        ok "VM forced off"
    fi
fi

log "=== Shutdown complete ==="
