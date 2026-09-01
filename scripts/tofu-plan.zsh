#!/usr/bin/env zsh
# scripts/tofu-plan.zsh — Preview changes
# Usage: ./scripts/tofu-plan.zsh [target]
# Examples:
#   ./scripts/tofu-plan.zsh                  # Plan everything
#   ./scripts/tofu-plan.zsh module.compute   # Plan only VMs
#   ./scripts/tofu-plan.zsh module.networking # Plan only networks

set -euo pipefail

TOFU_DIR="${LAB_PROJECT_ROOT}/tofu"
TARGET="${1:-}"

echo "=== OpenTofu Plan ==="

cd "${TOFU_DIR}"

if [[ -n "${TARGET}" ]]; then
    echo "Target: ${TARGET}"
    tofu plan -target="${TARGET}"
else
    echo "Planning all resources..."
    tofu plan
fi
