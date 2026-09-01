#!/usr/bin/env zsh
# test-destroy-safety.zsh — Verify destroy only targets lab resources

set -euo pipefail

LAB_PROJECT_ROOT="${0:A:h}/.."
export LAB_PROJECT_ROOT

source "${LAB_PROJECT_ROOT}/lib/common.zsh"
source "${LAB_PROJECT_ROOT}/lib/config.zsh"
source "${LAB_PROJECT_ROOT}/lib/cleanup.zsh"

config_load

echo "=== Test: Destroy Safety ==="

# Verify destroy_preview only mentions lab resources
echo "Checking destroy scope..."
cleanup_preview

echo ""
echo "MANUAL CHECK: Verify no unrelated resources listed above"
echo "The destroy command should ONLY mention:"
echo "  - VM: ${VM_NAME}"
echo "  - Disk: ${VM_DISK}"
echo "  - Seed: ${SEED_ISO}"
echo "  - State: ${LAB_STATE_DIR}"
echo "  - Logs: ${LAB_LOG_DIR}"
