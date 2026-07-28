# Lab 15: Enterprise Capstone

## Objective
Integrate every pattern built across this repository into one complete, layered automation platform — dynamic inventory, Vault-protected secrets, a validated role library, golden-AMI baking, Kubernetes-adjacent bootstrapping, security hardening, Molecule testing, CI/CD, and policy-as-code — composed as a single, coherent system with genuine operational documentation, rather than fifteen separate exercises.

## Scenario
You're the platform engineer responsible for standing up complete configuration-management automation for a new, multi-environment application fleet, following every standard this repository has established: per-environment inventory and vault isolation, validated role interfaces, tested idempotency, a CI/CD pipeline with a genuine review gate, and a documented, tested DR/recovery process — the full platform, not a demo.

## Skills Practised
- Composing every role from Labs 2, 7, 8, 10 (`webserver`, `security_baseline`, `harden_sudo`) into one coherent, multi-environment platform
- Per-environment dynamic inventory + vault isolation (Labs 3, 4, 5)
- CI/CD with lint, Molecule test, and a reviewed-approval gate (Labs 11, 12, 13)
- Writing genuine operational documentation (`OPERATIONS.md`), not just playbooks
- A tested, documented DR/recovery process for the automation platform itself (Category 11's synthesis)

## Architecture
See [`OPERATIONS.md`](OPERATIONS.md) for the full architecture diagram and operational reference. Summary: `environments/{dev,staging,production}/` (per-environment inventory + vault, per Lab 5) → shared `roles/` library (validated via `argument_specs` and Molecule, per Labs 2/11) → a CI/CD pipeline (lint → Molecule → review → apply, per Lab 12) → a documented, periodically-tested DR process.

## Prerequisites
- Labs 2 (roles/structure), 4 (Vault), 5 (multi-environment), 11 (Molecule), 12 (CI/CD), and 13 (policy-as-code) completed
- Docker for local target containers (per Lab 1's pattern) — this capstone is designed to run entirely locally, at zero cloud cost, using the same `geerlingguy/docker-ubuntu2204-ansible` pattern as earlier labs

## Directory Structure
```text
lab-15-enterprise-capstone/
├── README.md
├── OPERATIONS.md              # the operational documentation deliverable
├── ansible.cfg
├── environments/
│   ├── dev/{hosts.ini, group_vars/all.yml}
│   ├── staging/{hosts.ini, group_vars/all.yml}
│   └── production/{hosts.ini, group_vars/all/main.yml, group_vars/all/vault.yml}
├── roles/
│   ├── security_baseline/
│   ├── webserver/
│   └── harden_sudo/
├── scripts/vault-password-production.sh
├── site.yml
├── dr-recovery.yml            # the tested, documented DR/recovery playbook
└── .github/workflows/ci.yml
```

## Step-by-Step Tasks
1. Start three target containers (dev, staging, production), per Lab 1's pattern.
2. Review `site.yml` — note it composes `security_baseline` + `harden_sudo` + `webserver` for every environment, with production additionally requiring `-e target_env_confirm=yes-production` (Lab 5's guard).
3. Create `environments/production/group_vars/all/vault.yml` per Lab 4's pattern: `ansible-vault create --vault-id production@scripts/vault-password-production.sh environments/production/group_vars/all/vault.yml`.
4. Run the full platform against dev, then staging, confirming success without confirmation friction.
5. Run against production and confirm the guard blocks an unconfirmed attempt, then succeeds once confirmed.
6. Review `dr-recovery.yml` — a playbook specifically designed to be run by someone who has *never* run it before, using only this README and the playbook's own inline comments (per Category 11's Question 108 bus-factor lesson) — actually hand this file to a colleague (or re-read it yourself after a week) and see if it's genuinely self-sufficient.
7. Review `.github/workflows/ci.yml` — the same lint → Molecule → review-gate pipeline from Lab 12, now covering the full role library.
8. Read [`OPERATIONS.md`](OPERATIONS.md) in full and confirm you understand every cross-component dependency before considering the capstone complete.

## Ansible Configuration
See [`site.yml`](site.yml), [`dr-recovery.yml`](dr-recovery.yml), [`roles/`](roles/), and [`environments/`](environments/).

## Commands to Execute
```bash
for env in dev staging production; do
  docker run -d --name "capstone-${env}" --privileged \
    --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    geerlingguy/docker-ubuntu2204-ansible:latest
done
ansible-playbook site.yml -i environments/dev/hosts.ini
ansible-playbook site.yml -i environments/staging/hosts.ini
ansible-playbook site.yml -i environments/production/hosts.ini -e target_env_confirm=yes-production \
  --vault-id production@scripts/vault-password-production.sh
ansible-playbook site.yml -i environments/dev/hosts.ini   # re-run - expect changed=0 (idempotency)
```

## Expected Output
- All three environments configure successfully, each with correct per-environment values.
- Production requires explicit confirmation, exactly per Lab 5's guard.
- A second run against any environment reports zero changes — full-platform idempotency, proven not assumed.

## Validation
```bash
for env in dev staging production; do
  echo "=== $env ==="
  docker exec "capstone-${env}" sudo -l -U automation_user
  docker exec "capstone-${env}" grep listen /etc/nginx/sites-available/default
done
```
Confirms security hardening (scoped sudoers), the security baseline, and the correct per-environment web server configuration are all genuinely present across the fleet.

## Failure Injection
Deliberately corrupt `environments/production/group_vars/all/vault.yml` (edit one byte inside the encrypted content) and confirm the production run fails immediately with a clear decryption error — never partially applying with a corrupted secret.

## Troubleshooting Exercise
Hand `dr-recovery.yml` to someone unfamiliar with this lab (or simulate this by not looking at it for a week) and have them attempt to run it using only its own inline documentation — record every point of confusion or missing context, exactly the exercise from Category 11's Question 108, and update the playbook's comments to close every gap found.

## Cleanup
```bash
docker rm -f capstone-dev capstone-staging capstone-production
```
**Chargeable resources:** none (local Docker only).

## Interview Questions Connected to This Lab
This capstone integrates concepts from every category — see in particular:
- [Question 104: Designing DR from a blank page](../../interview-questions/11-ha-dr.md#question-104-designing-dr-from-a-blank-page--the-ansible-capstone-synthesis)
- [Question 110: Designing Ansible for 10,000 hosts](../../interview-questions/12-performance-scale.md#question-110-designing-ansible-for-10000-hosts--the-performance-capstone-synthesis)
- [Question 119: Building a platform team's Ansible standards from scratch](../../interview-questions/15-leadership-design.md#question-119-building-a-platform-teams-ansible-standards-from-scratch)

## Production Considerations
See [`OPERATIONS.md`](OPERATIONS.md) in full — it covers cost, security, scaling, and DR considerations for taking this pattern to a genuinely production-scale (thousands of hosts, real AWS/Kubernetes targets) fleet.

## Advanced Challenge
Extend this capstone with a genuine multi-region DR setup (per Category 11's Question 99's coordinated-pipeline fix): a second, "DR-region" set of environments reconciled by the *same* coordinated pipeline run as primary, plus a standing drift-detection check confirming both never silently diverge.
