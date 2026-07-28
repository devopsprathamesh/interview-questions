# Cheat Sheet: Testing and Molecule

## The testing pyramid
| Layer | Tool | What it actually proves |
|---|---|---|
| Syntax | `ansible-playbook --syntax-check` | YAML/structural validity only — no logic evaluation. [Question 85](../interview-questions/09-testing-validation.md#question-85-the-syntax-check-that-checked-nothing-meaningful) |
| Style/best-practice | `ansible-lint` | Idiomatic patterns, common mistakes — **not** organizational security policy. [Question 111](../interview-questions/13-governance-policy.md#question-111-the-lint-pass-that-let-a-policy-violation-through) |
| Functional/idempotency | Molecule (`create→converge→idempotence→verify→destroy`) | Actual role behavior against a real target |
| Contract | Custom multi-scenario Molecule matrix | Whether a shared role breaks a *specific* real downstream consumer |
| Integration | Real cloud calls (sandboxed account) | Genuine AWS-side behavior — no `mock_provider` equivalent exists in Ansible |

## Molecule stage-by-stage
1. **create** — launches the test target (Docker/cloud instance)
2. **converge** — runs the role
3. **idempotence** — runs converge again, asserts **zero** changes. This is the enforced, mechanical proof of idempotency — not eyeballing a second run. [Question 80](../interview-questions/09-testing-validation.md#question-80-the-idempotence-stage-that-lied-about-idempotency)
4. **verify** — asserts real, observable state (a functional check — an actual HTTP request — not just "service is running"). [Question 79](../interview-questions/09-testing-validation.md#question-79-the-molecule-test-that-passed-on-a-lie)
5. **destroy** — tears down the test target

## Minimal `molecule.yml` (Docker driver)
```yaml
driver:
  name: docker
platforms:
  - name: instance
    image: geerlingguy/docker-ubuntu2204-ansible:latest
    privileged: true
    cgroupns_mode: host
    volumes: ["/sys/fs/cgroup:/sys/fs/cgroup:rw"]
provisioner:
  name: ansible
verifier:
  name: ansible
```

## What Molecule can't tell you
- **Fidelity to production**: a pristine, fresh test container ≠ a years-aged production host with accumulated state. A change can pass Molecule cleanly and still fail against real, drift-accumulated hosts. [Question 84](../interview-questions/09-testing-validation.md#question-84-the-test-environment-that-was-too-clean-to-be-useful)
- **Downstream consumer diversity**: a role's own Molecule scenario only covers what its maintainer thought to test — not every real consumer's actual variable configuration. Use a contract-test matrix for widely-shared roles. [Question 82](../interview-questions/09-testing-validation.md#question-82-the-role-that-had-no-idea-it-broke-someone-else)

## The honest capability gap vs. Terraform
Ansible has **no saved-plan-artifact equivalent** and **no `mock_provider`-equivalent** for free, cloud-call-free unit testing. `--check --diff` re-evaluates live each time — it is a genuine preview, but not a frozen, guaranteed-identical artifact. Mitigate by minimizing the check-to-apply time gap and pinning the exact commit/Execution Environment image for both. [Question 72](../interview-questions/08-cicd-automation.md#question-72-the-plan-ansible-never-had)
