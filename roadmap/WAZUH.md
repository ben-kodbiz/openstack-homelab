# WAZUH Roadmap — Security Visibility

**Status: near-future. First deploy the fleet, then security monitoring.**

## Role

Wazuh provides endpoint security: events, file integrity, vulnerability visibility, compliance checks.

```text
Wazuh manager ← agents (fleet-001 … fleet-0NN)
```

## Target Capabilities

- Security event detection across the fleet
- File integrity monitoring
- Vulnerability visibility
- Compliance/security reporting

## Implementation Sketch (when phase starts)

1. Wazuh manager (container or VM) on lab infrastructure
2. Agent deployment automated — via cloud-init bootstrap hook or AWX playbook
3. Agent enrollment keys distributed via secure injection (never committed to Git)

## Hard Rule

Never manually install agents on 20 machines. Automation is the objective — if agent rollout can't be automated, fix the automation before scaling the fleet.

## Future Scenario Enabled

`scenarios/security-event/`: trigger event on fleet-009 → Wazuh alert → investigation → remediation → verify.
