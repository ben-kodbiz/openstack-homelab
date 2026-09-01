#!/usr/bin/env zsh
# test-preflight.zsh — Test preflight checks (dry run, no modifications)

set -euo pipefail

LAB_PROJECT_ROOT="${0:A:h}/.."
export LAB_PROJECT_ROOT

source "${LAB_PROJECT_ROOT}/lib/common.zsh"
source "${LAB_PROJECT_ROOT}/lib/logging.zsh"
source "${LAB_PROJECT_ROOT}/lib/config.zsh"
source "${LAB_PROJECT_ROOT}/lib/preflight.zsh"

config_load

echo "=== Test: Preflight Checks ==="

preflight_os
preflight_cpu
preflight_kvm
preflight_libvirt
preflight_storage
preflight_commands
preflight_network

echo ""
echo "All preflight tests passed"
