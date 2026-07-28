# Cheat Sheet: Governance and Policy as Code

## Kyverno vs. OPA Gatekeeper
| | Kyverno | OPA Gatekeeper |
|---|---|---|
| Policy language | Native Kubernetes YAML | Rego |
| Mutating support | Yes (native) | Limited |
| Learning curve | Lower for a Kubernetes-focused team | Steeper, but reusable if already using OPA elsewhere (e.g., Terraform/Conftest) |

## `failurePolicy` — the availability/security trade-off
```yaml
failurePolicy: Fail     # webhook down = blocks ALL admission cluster-wide (safe, but availability risk)
failurePolicy: Ignore   # webhook down = silently bypasses ALL enforcement (available, but no protection)
```
Reserve `Fail` for genuinely critical policies; make this decision deliberately, per policy. [`docs/governance-policy.md`](../docs/governance-policy.md) §2

## Rollout discipline: audit before enforce
```yaml
validationFailureAction: Audit    # review real violations first
# then, once validated:
validationFailureAction: Enforce
```
Never flip straight to `Enforce` for a new policy — it will likely block a legitimate, unanticipated operation. [`docs/governance-policy.md`](../docs/governance-policy.md) §3

## Policy needs its own tests
```bash
kyverno test policies/
```
Write fixtures (a resource that should pass, one that should fail) — the same discipline as unit-testing a Terraform OPA policy with Conftest. [`docs/governance-policy.md`](../docs/governance-policy.md) §4

## CI and live cluster must share ONE policy source
If CI's `kyverno test` fixtures are a separately-maintained copy of what's actually deployed, they silently drift apart — CI passes, live cluster rejects. [Question 116](../interview-questions/14-governance-policy.md#question-116-the-policy-that-passed-in-ci-but-failed-in-the-cluster)

## Emergency bypass — never a blanket disable
```yaml
apiVersion: kyverno.io/v2beta1
kind: PolicyException
spec:
  conditions:
    all:
      - { key: "{{ request.object.metadata.labels.incident-exception }}", operator: Equals, value: "true" }
```
A narrow, explicit, opt-in exception — never disabling the whole policy or the whole namespace. [Question 115](../interview-questions/14-governance-policy.md#question-115-the-policy-that-blocked-its-own-emergency-fix)

## Twenty clusters, one policy set
Independently-maintained per-cluster policy copies inevitably drift. Consolidate to a single, centrally-managed, `ApplicationSet`-reconciled source, with an ongoing (not one-time) compliance-consistency check. [Question 117](../interview-questions/14-governance-policy.md#question-117-one-policy-set-twenty-clusters-twenty-opinions)
