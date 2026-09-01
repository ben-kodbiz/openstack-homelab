#!/usr/bin/env zsh
# test-config.zsh — Validate configuration loading and validation

set -euo pipefail

LAB_PROJECT_ROOT="${0:A:h}/.."
export LAB_PROJECT_ROOT

source "${LAB_PROJECT_ROOT}/lib/common.zsh"
source "${LAB_PROJECT_ROOT}/lib/config.zsh"

echo "=== Test: Config Loading ==="

# Test loading
config_load
echo "OK: Config loaded"

# Test validation
config_validate
echo "OK: Config validated"

# Test variable presence
require_var LAB_NAME
require_var VM_NAME
require_var VM_VCPU
echo "OK: Required variables present"

# Test numeric validation
if (( VM_VCPU >= 1 && VM_VCPU <= 64 )); then
    echo "OK: VM_VCPU in range (${VM_VCPU})"
else
    echo "FAIL: VM_VCPU out of range (${VM_VCPU})"
    exit 1
fi

if (( VM_RAM_MB >= 1024 )); then
    echo "OK: VM_RAM_MB valid (${VM_RAM_MB})"
else
    echo "FAIL: VM_RAM_MB too small (${VM_RAM_MB})"
    exit 1
fi

echo ""
echo "All config tests passed"
