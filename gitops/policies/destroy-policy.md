# Policy: Destroy

## Rule

Destruction is never automatic, never silent, and never in CI.

| Operation | Guard |
|-----------|-------|
| `tofu destroy` | Requires typed confirmation `yes` (interactive) |
| `./openstack-lab.zsh destroy` | Requires `AUTO_APPROVE_DESTROY=true` in config **plus** interactive confirm |
| CI (`validate.sh`, `tofu-check.sh`) | Never plans destroy, never applies, never deletes |
| `labctl fleet destroy` | Interactive confirmation listing exact resources first |

## Scope boundaries

- Fleet destroy (`tofu -chdir=tofu/environments/lab destroy`) touches only `fleet-*` resources + `fleet` SG
- The OpenStack control VM is NEVER destroyed by fleet tooling
- `openstack-lab.zsh destroy` (full lab teardown) is a separate, explicit operation

## Failure behavior

Failed operations STOP and preserve state for diagnosis. No destroy-and-retry loops.
