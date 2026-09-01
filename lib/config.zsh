#!/usr/bin/env zsh
# config.zsh — Configuration loading and validation

set -euo pipefail

LAB_CONF="${LAB_PROJECT_ROOT}/config/lab.conf"

# Load configuration
config_load() {
    if [[ ! -f "${LAB_CONF}" ]]; then
        log_fatal "Configuration not found: ${LAB_CONF}"
    fi
    source "${LAB_CONF}"
}

# Validate required configuration variables
config_validate() {
    local required=(
        LAB_NAME
        LAB_ROOT
        VM_NAME
        VM_VCPU
        VM_RAM_MB
        VM_DISK_GB
        GUEST_OS
        GUEST_HOSTNAME
        LIBVIRT_POOL
        BASE_IMAGE
        VM_DISK
        SEED_ISO
        LIBVIRT_NETWORK
        KOLLA_OS_VERSION
        KOLLA_BASE_DISTRO
        KOLLA_VENV
    )

    local missing=0
    for var in "${required[@]}"; do
        if [[ -z "${(P)var:-}" ]]; then
            log_error "Missing required config: ${var}"
            missing=1
        fi
    done

    if [[ ${missing} -eq 1 ]]; then
        log_fatal "Configuration validation failed. Fix missing values in ${LAB_CONF}"
    fi

    # Validate numeric values
    if (( VM_VCPU < 1 || VM_VCPU > 64 )); then
        log_fatal "VM_VCPU must be 1-64, got: ${VM_VCPU}"
    fi
    if (( VM_RAM_MB < 1024 )); then
        log_fatal "VM_RAM_MB must be >= 1024, got: ${VM_RAM_MB}"
    fi
    if (( VM_DISK_GB < 20 )); then
        log_fatal "VM_DISK_GB must be >= 20, got: ${VM_DISK_GB}"
    fi
}

# Print current configuration (no secrets)
config_dump() {
    log_info "=== Configuration ==="
    log_info "LAB_NAME:       ${LAB_NAME}"
    log_info "LAB_ROOT:       ${LAB_ROOT}"
    log_info "VM_NAME:        ${VM_NAME}"
    log_info "VM_VCPU:        ${VM_VCPU}"
    log_info "VM_RAM_MB:      ${VM_RAM_MB}"
    log_info "VM_DISK_GB:     ${VM_DISK_GB}"
    log_info "GUEST_OS:       ${GUEST_OS}"
    log_info "GUEST_HOSTNAME: ${GUEST_HOSTNAME}"
    log_info "LIBVIRT_POOL:   ${LIBVIRT_POOL}"
    log_info "LIBVIRT_NETWORK:${LIBVIRT_NETWORK}"
    log_info "KOLLA_VERSION:  ${KOLLA_OS_VERSION}"
    log_info "KOLLA_VENV:     ${KOLLA_VENV}"
}
