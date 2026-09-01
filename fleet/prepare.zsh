#!/usr/bin/env zsh
# ============================================================================
# fleet/prepare.zsh — One-time fleet prerequisites on OpenStack
# ============================================================================
# Idempotent. Creates/verifies:
#   - flavor fleet.tiny (1 vCPU / 1 GB / 5 GB) if missing
#   - key pair 'default' imported from FLEET_SSH_PUBLIC_KEY env or existing
# Raises project quotas to fleet-safe values (lab only).
set -euo pipefail

# OpenStack CLI access: local if available, else via the guest venv over SSH
GUEST="${LAB_GUEST:-stack@192.168.122.17}"
GUEST_RC="source /opt/kolla-venv/bin/activate && source /etc/kolla/admin-openrc.sh"
if command -v openstack >/dev/null 2>&1; then
  OS() { openstack "$@"; }
else
  OS() { ssh -o BatchMode=yes "$GUEST" "$GUEST_RC && openstack $*" ; }
fi

print -r -- "== fleet prerequisites =="

# Flavor: 1 vCPU, 1024 MB, 5 GB (matches fleet.tfvars defaults)
FLAVOR="fleet.tiny"
if OS flavor show "$FLAVOR" >/dev/null 2>&1; then
  print -r -- "ok: flavor $FLAVOR exists"
else
  OS flavor create "$FLAVOR" --id auto --vcpus 1 --ram 1024 --disk 5 >/dev/null
  print -r -- "created: flavor $FLAVOR (1 vCPU / 1024 MB / 5 GB)"
fi

# Key pair: reuse 'default'; create from env var if missing
KEYPAIR="default"
if OS keypair show "$KEYPAIR" >/dev/null 2>&1; then
  print -r -- "ok: key pair $KEYPAIR exists"
elif [[ -n "${FLEET_SSH_PUBLIC_KEY_FILE:-}" && -f "$FLEET_SSH_PUBLIC_KEY_FILE" ]]; then
  KEY_CONTENT=$(cat "$FLEET_SSH_PUBLIC_KEY_FILE")
  OS keypair create "$KEYPAIR" --public-key <(echo "$KEY_CONTENT") >/dev/null 2>/dev/null || \
    ssh -o BatchMode=yes "$GUEST" "$GUEST_RC && openstack keypair create $KEYPAIR --public-key '$KEY_CONTENT'" >/dev/null
  print -r -- "created: key pair $KEYPAIR"
else
  print -u2 -- "warn: key pair '$KEYPAIR' missing and FLEET_SSH_PUBLIC_KEY_FILE not set"
fi

# Quotas (lab: generous, documented in ARCHITECTURE.md)
PROJECT="${OS_PROJECT_NAME:-admin}"
ssh -o BatchMode=yes "$GUEST" "$GUEST_RC && openstack quota set $PROJECT \
  --secgroups 100 --secgroup-rules 1000 \
  --networks 50 --ports 500 --routers 20 --floating-ips 100 \
  --instances 50 --cores 100 --ram 102400 \
  --volumes 100 --gigabytes 1000" >/dev/null 2>&1 || print -u2 -- "warn: quota set failed"
print -r -- "ok: quotas raised for project '$PROJECT' (lab sizing)"

print -r -- "== done =="
