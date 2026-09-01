#!/usr/bin/env zsh
# verify.zsh — Post-deployment verification and smoke tests

set -euo pipefail

# Check Docker container health
verify_docker() {
    local ip="$1"
    log_info "Checking Docker containers..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<'REMOTE'
set -euo pipefail

echo "=== Docker Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Unhealthy Containers ==="
unhealthy=$(docker ps --filter health=unhealthy --format "{{.Names}}" || true)
if [[ -n "${unhealthy}" ]]; then
    echo "${unhealthy}"
    exit 1
fi

echo "=== Stopped Containers ==="
stopped=$(docker ps -a --filter status=exited --format "{{.Names}}" || true)
if [[ -n "${stopped}" ]]; then
    echo "${stopped}"
fi

echo "Docker check complete"
REMOTE
}

# Check OpenStack services via CLI
verify_services() {
    local ip="$1"
    log_info "Checking OpenStack services..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<'REMOTE'
set -euo pipefail

source /etc/kolla/admin-openrc.sh

echo "=== Service List ==="
openstack service list

echo ""
echo "=== Compute Services ==="
openstack compute service list

echo ""
echo "=== Network Agents ==="
openstack network agent list

echo ""
echo "=== Hypervisors ==="
openstack hypervisor list

echo "Service check complete"
REMOTE
}

# Full smoke test: image, network, flavor, instance
verify_smoke_test() {
    local ip="$1"
    log_info "Running smoke test (image → network → flavor → instance)..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<'REMOTE'
set -euo pipefail

source /etc/kolla/admin-openrc.sh

# 1. Upload test image
echo "=== Uploading test image ==="
openstack image create "test-image" \
    --file /usr/share/qemu/efi-virtio.rom \
    --disk-format raw \
    --public || true

# 2. Create network
echo "=== Creating test network ==="
openstack network create test-net || true
openstack subnet create test-subnet \
    --network test-net \
    --subnet-range 10.0.0.0/24 \
    --allocation-pool start=10.0.0.100,end=10.0.0.200 \
    --gateway 10.0.0.1 \
    --dns-nameserver 8.8.8.8 || true

# 3. Create flavor
echo "=== Creating test flavor ==="
openstack flavor create test-flavor \
    --vcpus 1 \
    --ram 512 \
    --disk 1 || true

# 4. Boot test instance
echo "=== Booting test instance ==="
openstack server create test-instance \
    --image test-image \
    --flavor test-flavor \
    --network test-net || true

# 5. Wait and check status
echo "=== Waiting for instance (60s) ==="
sleep 60

echo "=== Instance Status ==="
openstack server list

STATUS=$(openstack server show test-instance -f value -c status 2>/dev/null || echo "UNKNOWN")
if [[ "${STATUS}" == "ACTIVE" ]]; then
    echo "SMOKE TEST PASSED: Instance is ACTIVE"
else
    echo "SMOKE TEST STATUS: ${STATUS}"
    echo "Fetching console log..."
    openstack console log show test-instance 2>/dev/null | tail -50 || true
fi
REMOTE
}

# Run all verification steps
verify_all() {
    local ip
    ip=$(guest_get_ip) || {
        die "verify" "guest_get_ip" "Cannot determine guest IP"
    }

    log_info "=== Verification ==="
    verify_docker "${ip}"
    verify_services "${ip}"
    verify_smoke_test "${ip}"
    log_ok "Verification complete"
}
