# Scenario: configuration-drift

## Flow

```text
Git desired state ≠ actual host state
   ↓
detect (AWX check mode / Ansible drift report)
   ↓
report
   ↓
remediate (re-apply playbook) or accept (update Git)
   ↓
verify convergence
```

## Preconditions

Configuration management via Ansible/AWX (roadmap). Git contains desired state (already true — GitOps from Phase 6).

## Notes

- Drift is expected in a lab — the value is the *detection and report*
- Never auto-remediate silently: report first, remediate via explicit job
