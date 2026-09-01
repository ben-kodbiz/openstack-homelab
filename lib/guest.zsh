#!/usr/bin/env zsh
# guest.zsh — Guest VM preparation (post-SSH, pre-Kolla)

set -euo pipefail

# Wait for SSH to become available on the guest
guest_wait_ssh() {
    local ip="$1"
    local timeout="${2:-${SSH_TIMEOUT:-300}}"
    local start=$(date +%s)

    log_info "Waiting for SSH on ${ip} (timeout: ${timeout}s)..."
    while true; do
        local elapsed=$(( $(date +%s) - start ))
        if (( elapsed >= timeout )); then
            die "wait" "ssh" "SSH timeout after ${timeout}s" \
                "Check VM console: virsh console ${VM_NAME}"
        fi

        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
               -o BatchMode=yes "stack@${ip}" "echo ok" &>/dev/null; then
            log_ok "SSH available on ${ip}"
            return 0
        fi

        sleep 5
    done
}

# Wait for cloud-init to finish
guest_wait_cloud_init() {
    local ip="$1"
    log_info "Waiting for cloud-init to complete..."
    ssh -o StrictHostKeyChecking=no "stack@${ip}" \
        "cloud-init status --wait" || {
        log_warn "cloud-init status check failed (may still be usable)"
    }
    log_ok "Cloud-init complete"
}

# Install packages on the guest
guest_configure() {
    local ip="$1"
    log_info "Configuring guest..."

    ssh -o StrictHostKeyChecking=no "stack@${ip}" <<'REMOTE'
set -euo pipefail

# Verify basic tools
python3 --version
git --version

# Update package list
sudo apt-get update -qq

# Install Docker prerequisites
sudo apt-get install -y -qq \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https

# Docker GPG key and repo (for Kolla)
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -qq
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io

# Enable Docker
sudo systemctl enable docker
sudo systemctl start docker

# Add stack user to docker group
sudo usermod -aG docker stack

# Install Python venv for Kolla
sudo apt-get install -y -qq python3-venv python3-dev

echo "Guest configuration complete"
REMOTE

    log_ok "Guest configured"
}

# Get guest IP (discover, don't hard-code)
guest_get_ip() {
    local ip
    ip=$(libvirt_get_ip)
    if [[ -z "${ip}" ]]; then
        log_error "Cannot determine guest IP"
        log_info "Check: virsh net-dhcp-leases ${LIBVIRT_NETWORK}"
        return 1
    fi
    echo "${ip}"
}
