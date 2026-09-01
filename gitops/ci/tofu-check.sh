#!/usr/bin/env zsh
# ============================================================================
# gitops/ci/tofu-check.sh — OpenTofu-only gate (fmt + validate)
# ============================================================================
set -euo pipefail
REPO_ROOT="${0:A:h:h:h}"
cd "$REPO_ROOT"

fail=0
tofu -chdir=tofu fmt -check -recursive || fail=1
tofu -chdir=tofu/environments/lab init -input=false >/dev/null 2>&1 || true
tofu -chdir=tofu/environments/lab validate || fail=1
exit $fail
