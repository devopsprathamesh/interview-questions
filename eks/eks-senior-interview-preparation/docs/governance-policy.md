# Governance and Policy as Code on EKS

Deep-dive reference for [`interview-questions/14-governance-policy.md`](../interview-questions/14-governance-policy.md) and [Lab 13 — Policy as Code (OPA/Gatekeeper)](../labs/lab-13-policy-as-code-opa/).

## 1. Two competing policy engines — OPA/Gatekeeper and Kyverno

**OPA Gatekeeper** enforces policy written in **Rego** (a general-purpose policy language, more expressive but with a steeper learning curve) via `ConstraintTemplate`/`Constraint` custom resources. **Kyverno** enforces policy written directly in Kubernetes-native YAML (no separate policy language to learn), and additionally supports **mutating** policies (auto-injecting defaults, e.g., adding a default resource limit if one is missing) alongside validating ones — a capability Gatekeeper's Rego-based validation doesn't natively provide in the same form. The senior-level trade-off: Kyverno's YAML-native policies are generally faster for a Kubernetes-focused team to adopt and read; Gatekeeper's Rego is more powerful for complex, cross-resource policy logic and is more likely to already be familiar to a team also using OPA/Rego elsewhere (e.g., the companion Terraform repository's Conftest-based policy-as-code for Terraform plans).

## 2. Admission webhooks are a genuine availability dependency, not a free control

Both engines operate as `ValidatingWebhookConfiguration`/`MutatingWebhookConfiguration` resources in the API server's admission chain (see [`docs/security.md`](security.md) §4) — meaning every policy-controlled resource creation/update *depends on* the policy engine's own webhook being reachable and healthy. A common, serious incident pattern: the policy engine's own pods crash or become unresponsive, and depending on the webhook's configured `failurePolicy` (`Fail` vs. `Ignore`), this either blocks *all* affected resource operations cluster-wide (`Fail` — safe from a policy-bypass perspective, but a real availability risk) or silently allows everything through unchecked (`Ignore` — available, but the policy enforcement is effectively off during the outage). Senior-level design explicitly reasons about this trade-off per policy criticality, and treats the policy engine's own health as a standing, monitored signal — not an implicit assumption.

## 3. Policy testing before enforcement — audit mode first

Both Gatekeeper and Kyverno support an audit/dry-run mode (reporting policy violations without blocking anything) — the standard, safe rollout discipline for any new policy is: write the policy, run it in audit-only mode against real cluster traffic for a representative period, review what it *would have* blocked, fix any unintended false-positive matches, and only then flip to enforcing mode. Enforcing a brand-new, untested policy directly in blocking mode risks the same "guardrail blocks a legitimate, unanticipated operation" failure mode discussed throughout the companion repositories' policy-as-code guidance (e.g., the companion Terraform repository's OPA/Conftest rollout discipline).

## 4. Policy-as-code testing — unit tests for policies themselves

Just as the companion Terraform repository tests OPA policies with Conftest test fixtures, Kubernetes admission policies should have their own test suite — both Gatekeeper (via `gator test`) and Kyverno (via `kyverno test`) support exactly this: a set of example resources (some that should pass, some that should be rejected) run against the policy definition in CI, catching a policy regression before it's ever applied to a real cluster. This is the same "policy needs its own tested contract, not just a hopeful deployment" discipline established elsewhere in this repository series.

## 5. Common governance policies worth having by default

- Every image must come from an approved registry (prevents pulling arbitrary, unscanned images from the public internet).
- Every container must set resource requests/limits (prevents a single misconfigured workload from starving the node/cluster).
- No `:latest` image tag in production (ensures a specific, traceable, reproducible image version is always what's actually running).
- No privileged containers/host-namespace access outside explicitly-approved system namespaces (overlaps with Pod Security Standards, see [`docs/security.md`](security.md) §1, but Kyverno/Gatekeeper allow finer-grained exceptions than PSA's three fixed levels).

## 6. Governance as a cross-cutting concern, not a single lab's isolated topic

Policy-as-code enforcement intersects directly with CI/CD (policies should ideally be checked pre-merge via `kyverno test`/`gator test` in CI, not discovered only at admission time in a live cluster — see [`docs/cicd-gitops.md`](cicd-gitops.md)), security (§2 above), and cost governance (a resource-limit-enforcing policy is as much a cost control as a stability one). A senior-level answer connects governance policy to these adjacent concerns rather than treating it as an isolated checkbox.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "Just enable the policy in blocking mode immediately" | Rolls out in audit mode first, reviews real violations, then enforces |
| "The policy engine is just another add-on, if it's down we lose policy enforcement, that's fine" | Explicitly reasons about `failurePolicy: Fail` vs. `Ignore` trade-offs per policy criticality |
| "We don't test our admission policies, we just apply them" | Writes `gator test`/`kyverno test` fixtures for every policy, run in CI |
| "OPA/Gatekeeper and Kyverno are basically the same, pick either" | Names the concrete trade-offs (Rego vs. native YAML, mutating support) relevant to the team's actual needs |

## Related material

- [`docs/security.md`](security.md), [`docs/cicd-gitops.md`](cicd-gitops.md)
- [Lab 13 — Policy as Code (OPA/Gatekeeper)](../labs/lab-13-policy-as-code-opa/)
- Companion: [Terraform OPA/Conftest policy-as-code guidance](../../../terraform/terraform-senior-interview-preparation/)
