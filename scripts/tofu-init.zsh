#!/usr/bin/env zsh
# scripts/tofu-init.zsh — Initialize OpenTofu
# Usage: ./scripts/tofu-init.zsh

set -euo pipefail

TOFU_DIR="${LAB_PROJECT_ROOT}/tofu"

echo "=== OpenTofu Init ==="

# Check if tofu is installed
if ! command -v tofu &>/dev/null; then
    echo "ERROR: tofu not installed"
    echo "Install: curl -fsSL https://get.opentofu.org/install.sh | sh"
    exit 1
fi

echo "OpenTofu version:"
tofu version

# Check if terraform.tfvars exists
if [[ ! -f "${TOFU_DIR}/terraform.tfvars" ]]; then
    echo ""
    echo "WARNING: terraform.tfvars not found"
    echo "Copy the example and edit:"
    echo "  cp ${TOFU_DIR}/terraform.tfvars.example ${TOFU_DIR}/terraform.tfvars"
    echo "  vim ${TOFU_DIR}/terraform.tfvars"
    exit 1
fi

# Initialize
cd "${TOFU_DIR}"
tofu init

echo ""
echo "=== Init complete ==="
echo "Next: tofu plan"
