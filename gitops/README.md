# GitOps

Git is the desired-state record. Nothing deploys from an unvalidated branch.

## CI Gates

Run `gitops/ci/validate.sh` on every PR. It enforces:

| Gate | Tool |
|------|------|
| Zsh syntax | `zsh -n` on all `*.zsh` |
| OpenTofu formatting | `tofu fmt -check -recursive` |
| OpenTofu validity | `tofu validate` (environments/lab) |
| Lock file presence | `.terraform.lock.hcl` committed |
| Secret scanning | pattern scan for credentials |
| Gitignore guards | secrets/state/images excluded |
| Test executability | `tests/*.zsh` runnable |

Standalone gates: `tofu-check.sh` (tofu only), `ansible-check.sh` (activates when `fleet/ansible` exists).

## Workflow

```text
branch → PR → CI validation → review → merge → tofu plan/apply (manual) → fleet
```

- CI validates; it never applies and never destroys
- Deployment (`tofu apply`) is a manual, reviewed step
- `tofu destroy` requires interactive confirmation (see policies/destroy-policy.md)

## Environments

`gitops/environments/lab/` documents the lab deployment context (credentials via `OS_*` env vars, never committed).

## Policies

- `policies/no-host-network-changes.md`
- `policies/no-secret-commits.md`
- `policies/destroy-policy.md`
