# Scenario: patch-day

## Objective

Simulate enterprise patch operations across the fleet.

## Flow

```text
pick maintenance window
   ↓
AWX patch job (staged: canary group first)
   ↓
verify canary group (fleet-001..005)
   ↓
roll to remaining groups
   ↓
verify fleet (all healthy, versions correct)
```

## Preconditions

AWX playbook phase (roadmap). Fleet stable.

## Notes

- Always stage: never patch 20 machines simultaneously
- Canary = first 5 by index; success gate before continuing
- Rollback plan required before starting (snapshot or reinstall via tofu taint)
