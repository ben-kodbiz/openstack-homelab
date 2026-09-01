#!/usr/bin/env zsh
# ============================================================================
# gitops/ci/ansible-check.sh — Ansible gate (future — placeholder)
# ============================================================================
# Activates when fleet/ansible/ exists. Until then: pass with a note.
set -euo pipefail
REPO_ROOT="${0:A:h:h:h}"
if [[ -d "$REPO_ROOT/fleet/ansible" ]]; then
  command -v ansible-lint >/dev/null 2>&1 || { print -u2 "ansible-lint required"; exit 1; }
  ansible-lint "$REPO_ROOT/fleet/ansible"
else
  print -r -- "no fleet/ansible yet — skipping (future phase)"
fi
