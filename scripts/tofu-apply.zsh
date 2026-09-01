#!/usr/bin/env zsh
# scripts/tofu-apply.zsh — Create/update resources
# Usage: ./scripts/tofu-apply.zsh [target]
# Examples:
#   ./scripts/tofu-apply.zsh                  # Apply everything
#   ./scripts/tofu-apply.zsh module.compute   # Apply only VMs
#   ./scripts/tofu-apply.zsh module.networking # Apply only networks

set -euo pipefail

TOFU_DIR="${LAB_PROJECT_ROOT}/tofu"
TARGET="${1:-}"

echo "=== OpenTofu Apply ==="

cd "${TOFU_DIR}"

if [[ -n "${TARGET}" ]]; then
    echo "Target: ${TARGET}"
    tofu apply -target="${TARGET}" -auto-approve
else
    echo "Applying all resources..."
    tofu apply -auto-approve
fi

echo ""
echo "=== Apply complete ==="
echo "Show outputs: tofu output"
echo "SSH to VMs: tofu output -raw ssh_commands"
