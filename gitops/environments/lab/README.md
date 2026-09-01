# Environment: lab

## Context

- OpenStack: `http://192.168.122.17:5000/v3` (control VM `openstack-lab-01`)
- Deployment root: `tofu/environments/lab/`
- Networks: adopts existing `internal-net` / `external-net` / `router1`
- Fleet: `fleet-001 … fleet-0NN` on `internal-net`, SG `fleet`

## Credentials

Never committed. Source from the guest before running tofu:

```bash
ssh stack@192.168.122.17 cat /etc/kolla/admin-openrc.sh > /tmp/lab-openrc.sh
source /tmp/lab-openrc.sh
```

## Operations

```bash
tofu -chdir=tofu/environments/lab init
tofu -chdir=tofu/environments/lab plan   # safe, repeatable
tofu -chdir=tofu/environments/lab apply  # manual, reviewed
```

Destroy: interactive confirmation only (see `policies/destroy-policy.md`).
