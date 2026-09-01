# Policy: No Secret Commits

## Rule

Git must never contain passwords, tokens, private keys, or real credential values.

## Enforced by

- `.gitignore`: `config/secrets.conf`, `*.pem`, `*.key`, `*.qcow2`, `state/`, `logs/`
- `tofu/.gitignore`: `*.tfstate`, `terraform.tfvars`, `.terraform/`
- `gitops/ci/validate.sh` step 5: pattern scan for `password|secret|token|api_key = <long-value>`

## Allowed patterns

- `*.example` files with `CHANGEME` placeholders
- Documentation referencing *where* secrets live (e.g., `/etc/kolla/passwords.yml` on the guest)
- Variable *names* (e.g., `variable "password"`) with no real values

## If a secret leaks

1. Rotate the credential immediately (it is burned)
2. Remove from history (`git filter-repo`) — deleting the file in one commit is NOT enough
3. Post-mortem: how did CI miss it? Extend the pattern list
