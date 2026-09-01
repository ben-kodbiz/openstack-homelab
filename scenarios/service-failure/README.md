# Scenario: service-failure

## Objective

Validate detection → alert → automated remediation → verification loop.

## Flow

```text
stop service on fleet-007
      ↓
monitoring detects failure
      ↓
alert
      ↓
AWX remediation job
      ↓
service restored
      ↓
verify (service running, alert cleared)
```

## Implementation Status

- [ ] fleet-007 provisioned with a managed service (future — AWX phase)
- [ ] monitoring watch on the service (future — Prometheus phase)
- [ ] AWX remediation playbook (future)
- [ ] verification step (future)

## Preconditions

Fleet stable (Phase 3), configuration management in place (AWX roadmap), monitoring (future).
