#!/usr/bin/env zsh
# ============================================================================
# fleet/verify.zsh — Health check: all fleet VMs ACTIVE + reachable
# ============================================================================
# Exit 0 = all healthy; exit 1 = any failure. Read-only.
# Runs against the guest (where the OpenStack CLI + qrouter live).
set -uo pipefail

GUEST="${LAB_GUEST:-stack@192.168.122.17}"
GUEST_RC="source /opt/kolla-venv/bin/activate && source /etc/kolla/admin-openrc.sh"

print -r -- "== fleet health =="

SERVERS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$GUEST" \
  "$GUEST_RC && openstack server list --name 'fleet-' -f json" 2>/dev/null)
[[ -n "$SERVERS" ]] || { print -u2 "no fleet VMs found"; exit 1; }

FAIL=0
while IFS= read -r line; do
  vm_name=$(print -r -- "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Name"])')
  vm_state=$(print -r -- "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Status"])')
  ip=$(print -r -- "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Networks"]["internal-net"][0])')
  [[ -n "$vm_name" ]] || continue
  if [[ "$vm_state" != "ACTIVE" ]]; then
    print -u2 -- "FAIL: $vm_name status=$vm_state"
    FAIL=1
    continue
  fi
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "$GUEST" \
      "sudo ip netns exec qrouter-e8ad9b85-c22f-4f70-a0a8-fdd86380a80d ping -c1 -W3 $ip" </dev/null >/dev/null 2>&1; then
    print -r -- "ok: $vm_name ($ip) ACTIVE + pingable"
  else
    print -u2 -- "warn: $vm_name ($ip) ACTIVE but not pingable (booting?)"
    FAIL=1
  fi
done <<< "$(print -r -- "$SERVERS" | python3 -c 'import json,sys
for s in json.load(sys.stdin): print(json.dumps(s))')"

if (( FAIL )); then
  print -u2 -- "== fleet verify: FAIL =="; exit 1
else
  print -r -- "== fleet verify: ALL HEALTHY =="; exit 0
fi
