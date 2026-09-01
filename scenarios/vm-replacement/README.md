# Scenario: vm-replacement

## Objective

Validate full lifecycle: destroy → detect → recreate → bootstrap → re-register everywhere → healthy.

## Flow

```text
destroy fleet-012
   ↓
detect missing node (labctl fleet status / monitoring)
   ↓
recreate (tofu apply — OpenTofu replaces missing resource)
   ↓
bootstrap via cloud-init
   ↓
NetBox re-register (future)
   ↓
AWX baseline (future)
   ↓
Wazuh agent (future)
   ↓
monitoring picks it up
   ↓
verify healthy
```

## Preconditions

Fleet reproducible via OpenTofu (Phase 3). This scenario is runnable **today** up to the "recreate + bootstrap + verify cloud-init" steps; NetBox/AWX/Wazuh steps activate with their phases.

## Notes

- This is the core reproducibility proof: `tofu apply` after a single-VM destroy must recreate exactly one VM with the same name and metadata
- Test both single replacement and `create 10 → destroy 5 → recreate 5 → verify 10` (AGENT_FIX §21)
