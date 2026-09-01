#!/usr/bin/env zsh
# libvirt.zsh — Libvirt VM management

set -euo pipefail

# Verify storage pool exists
libvirt_pool_check() {
    log_info "Checking storage pool '${LIBVIRT_POOL}'..."
    if virsh pool-info "${LIBVIRT_POOL}" &>/dev/null; then
        log_ok "Pool '${LIBVIRT_POOL}' active"
    else
        log_error "Pool '${LIBVIRT_POOL}' not found or inactive"
        return 1
    fi
}

# Download Ubuntu Noble cloud image if missing
libvirt_base_image() {
    log_info "Checking base image..."
    if [[ -f "${BASE_IMAGE}" ]]; then
        if qemu-img info "${BASE_IMAGE}" &>/dev/null; then
            log_ok "Base image exists: ${BASE_IMAGE}"
            return 0
        fi
        log_warn "Base image exists but appears corrupt, re-downloading"
    fi

    local url="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    log_info "Downloading Noble cloud image..."
    mkdir -p "${LAB_ROOT}"
    wget -O "${BASE_IMAGE}" "${url}" || {
        die "create-vm" "wget" "Failed to download base image" \
            "Check network connectivity and URL: ${url}"
    }
    log_ok "Base image downloaded"
}

# Create VM disk using qcow2 overlay
libvirt_create_disk() {
    log_info "Creating VM disk..."
    if [[ -f "${VM_DISK}" ]]; then
        log_ok "VM disk already exists: ${VM_DISK}"
        return 0
    fi

    qemu-img create \
        -f qcow2 \
        -F qcow2 \
        -b "${BASE_IMAGE}" \
        "${VM_DISK}" \
        "${VM_DISK_GB}G" || {
        die "create-vm" "qemu-img create" "Failed to create VM disk" \
            "Check disk space and image path"
    }

    # Verify
    if ! qemu-img info "${VM_DISK}" &>/dev/null; then
        die "create-vm" "qemu-img info" "Created disk is invalid" \
            "Check backing file and permissions"
    fi
    log_ok "VM disk created: ${VM_DISK}"
}

# Generate cloud-init seed ISO
libvirt_create_seed() {
    log_info "Creating cloud-init seed ISO..."
    if [[ -f "${SEED_ISO}" ]]; then
        log_ok "Seed ISO already exists: ${SEED_ISO}"
        return 0
    fi

    local meta_data
    meta_data=$(cat <<EOF
instance-id: ${VM_NAME}
local-hostname: ${GUEST_HOSTNAME}
EOF
)

    local user_data="${LAB_PROJECT_ROOT}/cloud-init/user-data"
    if [[ ! -f "${user_data}" ]]; then
        die "create-vm" "cloud-init" "user-data template not found" \
            "Create cloud-init/user-data"
    fi

    # Create temporary meta-data
    local tmp_meta
    tmp_meta=$(mktemp)
    echo "${meta_data}" > "${tmp_meta}"

    cloud-localds "${SEED_ISO}" "${user_data}" "${tmp_meta}" || {
        rm -f "${tmp_meta}"
        die "create-vm" "cloud-localds" "Failed to create seed ISO"
    }
    rm -f "${tmp_meta}"
    log_ok "Seed ISO created: ${SEED_ISO}"
}

# Create VM using virt-install
libvirt_create_vm() {
    log_info "Creating VM '${VM_NAME}'..."

    # Check if VM already exists
    if virsh dominfo "${VM_NAME}" &>/dev/null; then
        local state
        state=$(virsh domstate "${VM_NAME}" 2>/dev/null || echo "unknown")
        log_ok "VM '${VM_NAME}' already exists (state: ${state})"
        return 0
    fi

    # Find network bridge
    local bridge
    bridge=$(virsh net-info "${LIBVIRT_NETWORK}" 2>/dev/null \
        | grep "Bridge:" | awk '{print $2}')
    if [[ -z "${bridge}" ]]; then
        die "create-vm" "virsh" "Cannot determine network bridge" \
            "Verify libvirt network '${LIBVIRT_NETWORK}' is active"
    fi

    virt-install \
        --name "${VM_NAME}" \
        --vcpus "${VM_VCPU}" \
        --memory "${VM_RAM_MB}" \
        --disk "path=${VM_DISK},format=qcow2,bus=virtio" \
        --disk "path=${SEED_ISO},device=cdrom" \
        --os-variant "${GUEST_OS}" \
        --network "bridge=${bridge}" \
        --network "bridge=${bridge}" \
        --graphics vnc,listen=0.0.0.0 \
        --import \
        --noautoconsole \
        --wait 0 || {
        die "create-vm" "virt-install" "Failed to create VM" \
            "Check libvirt logs: journalctl -u libvirtd"
    }

    log_ok "VM '${VM_NAME}' created"
}

# Get VM IP from DHCP leases
libvirt_get_ip() {
    virsh net-dhcp-leases "${LIBVIRT_NETWORK}" 2>/dev/null \
        | awk -v name="${VM_NAME}" '$0 ~ name {print $5}' \
        | sed 's|/.*||' \
        | head -1
}
