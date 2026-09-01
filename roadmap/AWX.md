# AWX Roadmap — Configuration Management

**Status: near-future. Do not install AWX before basic fleet provisioning works.**

## Role

AWX/Ansible configures systems. OpenTofu creates them. Keep the boundary strict.

```text
OpenTofu → 20 Linux VMs → cloud-init → AWX → Ansible → configuration
```

## Target Management Domains

bootstrap, baseline, users, SSH, packages, security, monitoring agents, patching, service remediation.

## Integration Options (evaluate at phase start)

1. AWX containerized on the lab VM (Kolla already provides Docker)
2. Plain Ansible first (`fleet/ansible/`), AWX layered on top once playbooks stabilize

## Non-Goals

- AWX never creates OpenStack resources
- No manual per-host configuration — everything via playbook + inventory
- NetBox dynamic inventory is a later optimization, not a prerequisite
