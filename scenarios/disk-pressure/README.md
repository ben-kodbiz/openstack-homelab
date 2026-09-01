# Scenario: disk-pressure

## Flow

```text
fleet-004
   ↓
disk usage > threshold
   ↓
alert
   ↓
remediation (cleanup or volume grow)
   ↓
verification
```

## Preconditions

Fleet stable. Monitoring with disk usage metric (future Prometheus/node_exporter phase — bootstrap template already reserves the hook).

## Notes

- Threshold alerting happens in monitoring, not on the VM itself
- Remediation options must be safe: cleanup jobs first, volume growth second
- This scenario validates that alert→action wiring works end-to-end
