#!/usr/bin/env zsh
# cleanup.zsh — Destroy lab resources safely

set -euo pipefail

# Show what will be destroyed
cleanup_preview() {
    log_info "=== Resources to be destroyed ==="
    log_info "VM:     ${VM_NAME}"
    log_info "Disk:   ${VM_DISK}"
    log_info "Seed:   ${SEED_ISO}"
    log_info "State:  ${LAB_STATE_DIR}"
    log_info "Logs:   ${LAB_LOG_DIR}"
    echo ""
}

# Destroy the VM
cleanup_destroy_vm() {
    log_info "Destroying VM..."
    if virsh dominfo "${VM_NAME}" &>/dev/null; then
        local state
        state=$(virsh domstate "${VM_NAME}" 2>/dev/null || echo "unknown")
        if [[ "${state}" != "shut off" ]]; then
            virsh destroy "${VM_NAME}" 2>/dev/null || true
        fi
        virsh undefine "${VM_NAME}" --remove-all-storage 2>/dev/null || true
        log_ok "VM destroyed"
    else
        log_info "VM does not exist, skipping"
    fi
}

# Remove disk and seed
cleanup_destroy_files() {
    log_info "Removing files..."
    rm -f "${VM_DISK}" "${SEED_ISO}"
    log_ok "Files removed"
}

# Clear state markers
cleanup_destroy_state() {
    log_info "Clearing state..."
    rm -rf "${LAB_STATE_DIR}"
    log_ok "State cleared"
}

# Full destroy with confirmation
cleanup_destroy() {
    cleanup_preview

    if [[ "${AUTO_APPROVE_DESTROY}" != "true" ]]; then
        echo -n "Type DESTROY to continue: "
        read -r confirm
        if [[ "${confirm}" != "DESTROY" ]]; then
            log_info "Destroy cancelled"
            return 0
        fi
    fi

    cleanup_destroy_vm
    cleanup_destroy_files
    cleanup_destroy_state
    log_ok "All lab resources destroyed"
}
