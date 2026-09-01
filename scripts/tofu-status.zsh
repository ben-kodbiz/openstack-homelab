#!/usr/bin/env zsh
# scripts/tofu-status.zsh — Show current state
# Usage: ./scripts/tofu-status.zsh

set -euo pipefail

TOFU_DIR="${LAB_PROJECT_ROOT}/tofu"

echo "=== OpenTofu Status ==="

cd "${TOFU_DIR}"

echo ""
echo "--- Resources in state ---"
tofu state list 2>/dev/null || echo "  (no resources)"

echo ""
echo "--- Outputs ---"
tofu output 2>/dev/null || echo "  (no outputs)"

echo ""
echo "--- Current plan ---"
tofu plan -detailed-exitcode 2>/dev/null
EXIT=$?
case ${EXIT} in
    0) echo "No changes needed" ;;
    1) echo "Error during plan" ;;
    2) echo "Changes detected — run: tofu plan" ;;
esac
