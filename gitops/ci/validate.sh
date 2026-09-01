#!/usr/bin/env zsh
# ============================================================================
# gitops/ci/validate.sh — CI gate: runs all validation checks
# ============================================================================
# Fails (exit 1) on any error. Never deploys. Never destroys.
# Usage: ./gitops/ci/validate.sh

set -euo pipefail

REPO_ROOT="${0:A:h:h:h}"
FAIL=0
FAILED_STEPS=()

step() { print -r -- "\n== $1 ==" }
fail() { FAILED_STEPS+=("$1"); FAIL=1; print -u2 -- "FAIL: $1"; }
ok()   { print -r -- "ok: $1" }

# ---------------------------------------------------------------------------
# 1. Zsh syntax — every .zsh file
# ---------------------------------------------------------------------------
step "zsh syntax check"
ZSH_ERR=0
setopt extended_glob null_glob
for f in "$REPO_ROOT"/**/*.zsh; do
  if ! zsh -n "$f" >/dev/null 2>&1; then
    fail "zsh syntax: $f"
    ZSH_ERR=1
  fi
done
unsetopt null_glob
ZSH_COUNT=$(find "$REPO_ROOT" -name '*.zsh' -not -path '*/.git/*' | wc -l)
(( ZSH_ERR == 0 )) && ok "zsh syntax ($ZSH_COUNT files)"

# ---------------------------------------------------------------------------
# 2. shellcheck (if available) on zsh-adjacent bash? Skip: project is zsh-only.
#    Instead validate zsh tests are executable.
# ---------------------------------------------------------------------------
step "tests executable"
[[ -x "$REPO_ROOT/tests/test-config.zsh" ]] && ok "test-config executable" || fail "test-config not executable"
[[ -x "$REPO_ROOT/tests/test-preflight.zsh" ]] && ok "test-preflight executable" || fail "test-preflight not executable"
[[ -x "$REPO_ROOT/tests/test-destroy-safety.zsh" ]] && ok "test-destroy-safety executable" || fail "test-destroy-safety not executable"

# ---------------------------------------------------------------------------
# 3. OpenTofu fmt + validate — legacy root + lab environment
# ---------------------------------------------------------------------------
step "tofu fmt + validate"
if command -v tofu >/dev/null 2>&1; then
  if tofu -chdir="$REPO_ROOT/tofu" fmt -check -recursive >/dev/null 2>&1; then
    ok "tofu fmt (tofu/)"
  else
    fail "tofu fmt (run: tofu -chdir=tofu fmt -recursive)"
  fi
  if tofu -chdir="$REPO_ROOT/tofu/environments/lab" validate >/dev/null 2>&1; then
    ok "tofu validate (environments/lab)"
  else
    fail "tofu validate environments/lab"
  fi
  if tofu -chdir="$REPO_ROOT/tofu" validate >/dev/null 2>&1; then
    ok "tofu validate (legacy root — informational)"
  else
    print -u2 -- "warn: legacy root tofu/ does not validate (pre-existing; not blocking)"
  fi
else
  print -u2 -- "warn: tofu not installed — skipping tofu checks"
fi

# ---------------------------------------------------------------------------
# 4. Lock file present (reproducibility)
# ---------------------------------------------------------------------------
step "lock file"
[[ -f "$REPO_ROOT/tofu/.terraform.lock.hcl" ]] && ok ".terraform.lock.hcl present" || fail "missing tofu/.terraform.lock.hcl"

# ---------------------------------------------------------------------------
# 5. Secret scan — common secret patterns must not appear in tracked files
# ---------------------------------------------------------------------------
step "secret scan"
SECRET_HITS=0
# gather tracked text files
if git -C "$REPO_ROOT" rev-parse >/dev/null 2>&1; then
  FILES=$(git -C "$REPO_ROOT" ls-files)
else
  FILES=$(print -r -- "$REPO_ROOT"/**/*.zsh(N) "$REPO_ROOT"/**/*.tf(N) "$REPO_ROOT"/**/*.md(N) "$REPO_ROOT"/**/*.yaml(N))
fi
for f in ${(f)FILES}; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  if command -v rg >/dev/null 2>&1; then
    SCAN="rg -l"
  else
    SCAN="grep -l"
  fi
  if $SCAN -iE '(password|secret|token|api[_-]?key)[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{16,}' "$REPO_ROOT/$f" 2>/dev/null | grep -q .; then
    print -u2 -- "secret pattern in: $f"
    SECRET_HITS=1
  fi
done
# Known-safe exceptions: example files with CHANGEME
if (( SECRET_HITS )); then
  fail "secret scan — review hits above; use CHANGEME placeholders"
else
  ok "secret scan clean"
fi

# ---------------------------------------------------------------------------
# 6. Gitignore guards
# ---------------------------------------------------------------------------
step "gitignore guards"
GITIGNORE=$(cat "$REPO_ROOT/.gitignore")
print -r -- "$GITIGNORE" | grep -q "config/secrets.conf" && ok "secrets.conf ignored" || fail "secrets.conf not ignored"
print -r -- "$GITIGNORE" | grep -q "\*.pem" && ok "*.pem ignored" || fail "*.pem not ignored"
print -r -- "$GITIGNORE" | grep -q "\*.qcow2" && ok "*.qcow2 ignored" || fail "*.qcow2 not ignored"

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
print -u1 -- "\n===================="
if (( FAIL )); then
  print -u2 -- "CI FAILED — steps: ${FAILED_STEPS[*]}"
  exit 1
else
  print -r -- "CI PASSED"
  exit 0
fi
