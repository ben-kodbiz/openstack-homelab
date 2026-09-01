# NETBOX Roadmap — Inventory / Source-of-Truth

**Status: near-future. Do not implement until 10–20 fleet VMs provision reliably via OpenTofu.**

## Role

NetBox records infrastructure. It does NOT create infrastructure.

```text
OpenTofu → OpenStack VM → IP assigned → NetBox API → device registered
```

## Integration Target

- Provisioning writes device records: hostname, IP, OS, role, environment, region, project, owner, status
- Optional: dynamic inventory source for AWX/Ansible

## Non-Goals

- NetBox never drives VM creation (OpenTofu owns that)
- No manual device entries — records come from provisioning automation

## Implementation Sketch (when phase starts)

1. NetBox container/service on the lab VM (or a second control VM)
2. OpenTofu `null_resource` + local_exec (or a small Zsh hook in `labctl fleet create`) that POSTs device records after apply
3. Fleet metadata in `fleet/` carries role/environment fields consumed by both OpenTofu tags and NetBox records
