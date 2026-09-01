#!/usr/bin/env zsh
# scripts/tofu-destroy.zsh — Destroy all resources
# Usage: ./scripts/tofu-destroy.zsh

set -euo pipefail

TOFU_DIR="${LAB_PROJECT_ROOT}/tofu"

echo "=== OpenTofu Destroy ==="
echo ""
echo "WARNING: This will destroy ALL OpenTofu-managed resources!"
echo ""
echo "Resources to be destroyed:"
cd "${TOFU_DIR}"
tofu state list 2>/dev/null || echo "  (no resources in state)"
echo ""

# Confirm
echo -n "Type 'yes' to destroy: "
read -r CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo "Destroying..."
tofu destroy -auto-approve

echo ""
echo "=== Destroy complete ==="
