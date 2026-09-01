#!/usr/bin/env zsh
# preflight.zsh — Host readiness checks

set -euo pipefail

# Check OS
preflight_os() {
    log_info "Checking OS..."
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "${ID}" == "ubuntu" ]]; then
            log_ok "Ubuntu ${VERSION_ID}"
        else
            log_warn "Expected Ubuntu, got: ${ID} ${VERSION_ID}"
            return 1
        fi
    else
        log_error "Cannot detect OS: /etc/os-release not found"
        return 1
    fi
}

# Check CPU virtualization
preflight_cpu() {
    log_info "Checking CPU virtualization..."
    if lscpu | grep -qiE 'VIRTUALIZATION|svm|vmx'; then
        log_ok "Hardware virtualization supported"
    else
        log_error "No hardware virtualization (AMD-V/VT-x) detected"
        return 1
    fi
}

# Check KVM
preflight_kvm() {
    log_info "Checking KVM..."
    if [[ -e /dev/kvm ]]; then
        log_ok "/dev/kvm exists"
    else
        log_error "/dev/kvm not found"
        return 1
    fi

    if command -v virt-host-validate &>/dev/null; then
        local result
        result=$(virt-host-validate qemu 2>&1 || true)
        if echo "${result}" | grep -q "FAIL"; then
            log_warn "virt-host-validate reports FAIL (may still work):"
            echo "${result}" | grep "FAIL"
        else
            log_ok "virt-host-validate passed"
        fi
    fi
}

# Check libvirt
preflight_libvirt() {
    log_info "Checking libvirt..."
    require_cmd virsh || return 1

    local uri
    uri=$(virsh uri 2>/dev/null || echo "unknown")
    if [[ "${uri}" == "qemu:///system" ]]; then
        log_ok "libvirt connected: ${uri}"
    else
        log_error "Unexpected libvirt URI: ${uri}"
        return 1
    fi
}

# Check storage
preflight_storage() {
    log_info "Checking storage..."
    require_cmd qemu-img || return 1
    require_cmd cloud-localds || return 1

    local avail_gb
    avail_gb=$(get_free_gb "${LAB_ROOT}")
    log_info "Available space at ${LAB_ROOT}: ${avail_gb} GiB"

    if (( avail_gb < MIN_FREE_GB )); then
        log_error "Insufficient space: need ${MIN_FREE_GB} GiB, have ${avail_gb} GiB"
        return 1
    fi
    log_ok "Storage OK"
}

# Check required commands
preflight_commands() {
    log_info "Checking required commands..."
    local cmds=(zsh curl wget git virsh virt-install cloud-localds qemu-img ssh scp)
    local missing=0
    for cmd in "${cmds[@]}"; do
        if command -v "${cmd}" &>/dev/null; then
            log_ok "${cmd}"
        else
            log_error "Missing: ${cmd}"
            missing=1
        fi
    done
    return ${missing}
}

# Check network
preflight_network() {
    log_info "Checking libvirt network..."
    if virsh net-info "${LIBVIRT_NETWORK}" &>/dev/null; then
        log_ok "Network '${LIBVIRT_NETWORK}' exists"
    else
        log_error "Network '${LIBVIRT_NETWORK}' not found"
        return 1
    fi
}

# Run all preflight checks
preflight_all() {
    log_info "=== Preflight Checks ==="
    local failures=0

    preflight_os      || ((failures++))
    preflight_cpu     || ((failures++))
    preflight_kvm     || ((failures++))
    preflight_libvirt || ((failures++))
    preflight_storage || ((failures++))
    preflight_commands|| ((failures++))
    preflight_network || ((failures++))

    echo ""
    if (( failures == 0 )); then
        log_ok "All preflight checks passed"
        return 0
    else
        log_error "${failures} preflight check(s) failed"
        return 1
    fi
}
