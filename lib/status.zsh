#!/usr/bin/env zsh
# verify.zsh — Status and diagnostics

set -euo pipefail

# Show comprehensive status
status_show() {
    log_info "=== HOST ==="
    status_host
    echo ""
    log_info "=== VM ==="
    status_vm
    echo ""
    log_info "=== STORAGE ==="
    status_storage
    echo ""
    log_info "=== STAGES ==="
    status_stages
}

status_host() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log_info "Ubuntu: ${VERSION_ID}"
    fi
    log_info "CPU:     $(nproc) cores"
    log_info "RAM:     $(free -h | awk '/Mem:/{print $2}')"
    log_info "KVM:     $([ -e /dev/kvm ] && echo 'available' || echo 'missing')"
}

status_vm() {
    if virsh dominfo "${VM_NAME}" &>/dev/null; then
        local state ip
        state=$(virsh domstate "${VM_NAME}" 2>/dev/null)
        ip=$(libvirt_get_ip 2>/dev/null || echo "unknown")
        log_info "Name:  ${VM_NAME}"
        log_info "State: ${state}"
        log_info "IP:    ${ip}"
    else
        log_info "VM not found"
    fi
}

status_storage() {
    log_info "Pool: ${LIBVIRT_POOL}"
    log_info "Disk: $([ -f "${VM_DISK}" ] && echo 'exists' || echo 'missing')"
    log_info "Base: $([ -f "${BASE_IMAGE}" ] && echo 'exists' || echo 'missing')"
}

status_stages() {
    mkdir -p "${LAB_STATE_DIR}"
    local stages=(00-preflight 01-create-vm 02-wait 03-configure
                   04-install-kolla 05-generate-config 06-bootstrap
                   07-deploy 08-verify)

    for stage in "${stages[@]}"; do
        if state_ok "${stage}"; then
            log_ok "${stage}  PASS"
        else
            log_info "${stage}  ---"
        fi
    done
}

# Collect diagnostics
diagnose_all() {
    log_info "=== Diagnostics ==="
    uname -a
    lsb_release -a 2>/dev/null || true
    free -h
    df -h
    echo ""
    log_info "=== Libvirt ==="
    virsh version 2>/dev/null || true
    virsh list --all 2>/dev/null || true
    virsh net-list 2>/dev/null || true
    virsh pool-list 2>/dev/null || true
    echo ""
    log_info "=== Docker ==="
    docker ps -a 2>/dev/null || true
}
