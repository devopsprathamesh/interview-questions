# Category 10: Troubleshooting and Production Incidents

Questions 87–98 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/troubleshooting.md`](../docs/troubleshooting.md).

---

## Question 87: The provider that wouldn't verify

### Scenario
`terraform init` suddenly starts failing across every CI runner with a checksum mismatch error for the AWS provider, even though nothing in `required_providers` or the lock file was intentionally changed.

### Interview Question
Walk through your diagnostic process.

### Strong Senior-Level Answer
**Initial assessment:** a checksum mismatch means the provider binary actually being served right now doesn't match what the lock file recorded and trusted at the time it was generated — this is either a corrupted download, a mirror serving something unexpected, or (rare, but the reason this check exists at all) a genuinely tampered artifact; treat it as a potential integrity issue, not just a flaky network error, until proven otherwise.

**Technical reasoning:** the lock file's checksums were computed once, against a specific known-good binary — if every CI runner suddenly fails identically, the most likely explanation is something changed at the *source* (registry, or an internal mirror/cache) being served, not something wrong on the CI-runner side, since CI runners are typically identical, ephemeral environments unlikely to have all independently developed the same corruption simultaneously.

**Investigation process:** check whether your organization uses a provider mirror (network or filesystem, per [`terraform-architecture.md` §6](../docs/terraform-architecture.md#6-provider-installation-mirrors-and-air-gapped-environments)) — if so, check the mirror's own sync history for a recent, possibly-incomplete sync of this provider version. If no mirror is in play and this is hitting the public registry directly, check HashiCorp's status page for any registry incident, and check whether a shared CI-runner-level provider plugin cache (`TF_PLUGIN_CACHE_DIR`) might be serving a corrupted cached copy across every runner that shares it.

**Recommended solution:** clear any shared provider plugin cache and force a fresh download (`rm -rf $TF_PLUGIN_CACHE_DIR` or the runner-image-level cache, then `terraform init`) to rule out a corrupted cache as the cause; if using an internal mirror, re-sync the specific provider version from a verified-good source and re-run.

**Risk controls:** never work around a checksum mismatch by disabling verification (there is no supported flag to simply ignore it, and that's intentional) — the fix must address why the served binary doesn't match the trusted checksum, not suppress the check.

**Validation steps:** after clearing the cache/re-syncing the mirror, confirm `terraform init` succeeds cleanly on a single runner first before assuming the fix applies fleet-wide, then confirm across a sample of other runners.

**Rollback or recovery strategy:** not applicable — this is a diagnostic/environment fix with no infrastructure state impact; no plan/apply can have occurred if `init` itself is failing.

**Long-term prevention:** if a shared plugin cache across CI runners was the cause, consider whether that shared-cache architecture needs better integrity checks of its own (e.g., periodic validation that cached binaries still match expected checksums), and if using an internal mirror, add monitoring for sync failures/incompleteness rather than discovering them via a fleet-wide CI failure.

### Step-by-Step Implementation
```bash
# Rule out a corrupted shared plugin cache
echo $TF_PLUGIN_CACHE_DIR
rm -rf "$TF_PLUGIN_CACHE_DIR"/registry.terraform.io/hashicorp/aws
terraform init   # forces a fresh download

# If using an internal mirror, check its sync state for this specific version
curl -s https://internal-mirror.corp.example/providers/hashicorp/aws/5.45.0/ | jq .

# Confirm the lock file's recorded checksum against what's actually being served
grep -A5 'hashicorp/aws' .terraform.lock.hcl
```

### Under-the-Hood Explanation
`terraform init` verifies every downloaded provider package's SHA-256 hash against the value recorded in `.terraform.lock.hcl` before allowing it to be used — this check exists specifically to detect exactly this class of discrepancy (corrupted download, tampered mirror, unexpected substitution) and is deliberately not bypassable via a casual flag, since weakening it would undermine the entire supply-chain trust model the lock file provides (see [`security.md` §11](../docs/security.md#11-supply-chain-risk-provider-and-module-trust)).

### Common Weak Answer
"Delete the lock file and let it regenerate to fix the checksum error."

### Why the Weak Answer Fails
This is the exact anti-pattern from [Question 42 in category 4](04-providers.md#question-42-the-lock-file-three-people-disagreed-about) — regenerating the lock file blind doesn't investigate *why* the served binary no longer matches what was previously trusted, and could simply re-trust whatever corrupted/tampered artifact is currently being served, silently accepting a supply-chain risk rather than identifying and fixing its actual source.

### Follow-Up Questions
1. How would you distinguish a genuinely malicious tampering event from a benign corrupted-cache/incomplete-sync explanation, and does your response differ?
2. What monitoring would give you visibility into this class of issue before it causes a fleet-wide CI failure?
3. How does this diagnostic process change in a fully air-gapped environment with no public registry fallback at all?

### Key Interview Signals
Confirms the candidate treats a checksum mismatch as a genuine integrity signal requiring investigation (not an annoyance to bypass) and systematically narrows down source (mirror, cache, registry) rather than guessing.

### Hands-On Connection
[Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 88: The merge that duplicated a resource

### Scenario
After resolving a merge conflict between two feature branches (both adding new security group rules to the same file), `terraform validate` fails with a duplicate resource address error — two `aws_security_group_rule` blocks now share the same name.

### Interview Question
Fix this and explain how you'd prevent it from reaching this point in the future.

### Strong Senior-Level Answer
**Initial assessment:** a straightforward merge-conflict-resolution mistake — two originally-independent additions, each individually valid, ended up with a naming collision once combined, most likely because both branches independently used a similar/generic resource name (e.g., both named their new rule `app_ingress`).

**Technical reasoning:** this is caught by `terraform validate` before any plan/apply is attempted, since duplicate resource addresses are a configuration-level error Terraform can detect purely from parsing, with no need to contact any provider or backend.

**Investigation process:** confirm which of the two rules is genuinely a duplicate versus which is a distinct, intentional addition that merely happens to share a name — read both branches' original intent from their respective commits/PRs to avoid accidentally deleting a legitimate rule while fixing the naming collision.

**Recommended solution:** rename one (or both, if warranted) of the conflicting resource blocks to distinct, descriptive names reflecting their actual distinct purposes, run `terraform validate` to confirm the collision is resolved, then `terraform plan` to confirm the resulting diff reflects exactly the two intended additions with no unexpected side effects from the rename (a rename of a resource *block's local name* — not its `for_each`/`count` key — does not by itself force replacement, but does change the address, so treat it with the same `moved`-block-awareness as any other resource-address change if either rule already exists in state from one of the two branches having been partially applied already).

**Risk controls:** if either branch had already been independently applied to any environment before the merge (e.g., one was already in staging), use a `moved` block for that one specifically, so the rename doesn't destroy/recreate an already-existing security group rule.

**Validation steps:** `terraform validate` succeeding is the immediate proof the duplicate is resolved; `terraform plan` showing the expected two-rule diff (or zero diff, if one was already applied and correctly `moved`) is the complete proof.

**Rollback or recovery strategy:** not applicable if caught at `validate`/`plan` time, before any apply — the fix is purely a configuration correction.

**Long-term prevention:** require `terraform validate` as a mandatory, fast PR check (see [`cicd.md` §1](../docs/cicd.md#1-the-pull-request-validation-chain)) so this class of error is caught automatically on every PR, including ones with merge conflicts, before a human even needs to notice it manually; additionally, encourage more specific, less generic resource naming conventions (reflecting the rule's actual purpose rather than a generic term like `app_ingress`) to reduce the odds of two independent additions colliding in the first place.

### Step-by-Step Implementation
```hcl
# Before merge resolution: duplicate address
resource "aws_security_group_rule" "app_ingress" {  # from branch A
  # ... allows port 443 from ALB ...
}
resource "aws_security_group_rule" "app_ingress" {  # from branch B - COLLISION
  # ... allows port 8080 from internal monitoring ...
}
```
```hcl
# After: distinct, descriptive names
resource "aws_security_group_rule" "app_ingress_https_from_alb" {
  # ... allows port 443 from ALB ...
}
resource "aws_security_group_rule" "app_ingress_metrics_from_monitoring" {
  # ... allows port 8080 from internal monitoring ...
}
```
```bash
terraform validate   # confirms the collision is resolved
terraform plan       # confirms the expected two-rule diff
```

### Under-the-Hood Explanation
Terraform parses all resource blocks in a configuration into a flat namespace of addresses (`<type>.<local_name>[<index/key>]`) before any graph construction begins — two resource blocks sharing an identical type and local name (with no differentiating `count`/`for_each` index) collide in this namespace, which `terraform validate` detects purely through static configuration parsing, entirely independent of state or provider communication, which is exactly why this class of error surfaces immediately and cheaply rather than requiring a full plan cycle to discover.

### Common Weak Answer
"Just delete one of the two conflicting resource blocks."

### Why the Weak Answer Fails
Without first confirming which rule (if either) represents a genuinely redundant duplicate versus two distinct, both-needed additions that merely share a name, deleting one risks silently dropping a legitimate change one of the two branches intended — the correct fix is renaming to resolve the collision while preserving both pieces of intended functionality, not assuming one is disposable.

### Follow-Up Questions
1. How would you catch this kind of naming collision risk before it even reaches a merge conflict, at PR-creation time?
2. How does this scenario change if the collision were in a `for_each` key rather than a static resource name?
3. What convention would you establish for resource naming to reduce the likelihood of two independent contributors choosing the same generic name?

### Key Interview Signals
Confirms the candidate investigates intent before resolving a collision (not just picking one side arbitrarily) and treats `terraform validate` as a mandatory, automatic PR gate rather than a manual step someone might forget to run locally.

### Hands-On Connection
[Lab 1 — Terraform Core Workflow](../labs/lab-01-core-workflow/).

---

## Question 89: The apply that hit the wrong account

### Scenario
An engineer, working locally with a stale AWS CLI profile still pointing at the staging account (having recently switched their default profile back for unrelated debugging), runs `terraform apply` against what they believe is production. The apply succeeds — creating several resources in the staging account instead, since credentials — not the Terraform configuration itself — determined the target.

### Interview Question
This wasn't caught at plan review because the engineer applied locally without going through the reviewed pipeline. What's your recovery process, and what structural changes prevent this specific failure mode?

### Strong Senior-Level Answer
**Initial assessment:** this succeeded (not just a caught-at-plan-review near-miss) precisely because it was run outside the normal CI/CD pipeline, locally, with ambient credentials that didn't match the engineer's intent — a strong argument for why production applies should never be a locally-runnable action at all, regardless of how careful any individual engineer tries to be.

**Technical reasoning:** the actual target account is determined entirely by whatever credentials/assumed-role session Terraform's provider configuration resolves to at run time — the `.tf` files and workspace name don't change based on which account the engineer *intended*; a stale local profile silently redirects everything.

**Investigation process:** identify exactly what was created in staging (via `terraform state list` in that environment's state, cross-referenced with the intended production change) and confirm none of it caused any actual disruption to staging's legitimate, already-running resources (a set of newly-created resources with no naming collision is a much easier cleanup than one that overwrote/replaced something staging already depended on).

**Recommended solution:** destroy the accidentally-created staging resources (via a proper, reviewed `terraform destroy -target` or full plan/apply cycle in staging's own state — not a manual console cleanup) and then apply the actually-intended change to production through the normal, correct pipeline. Separately and more importantly, treat this incident as confirming that production applies should be **structurally impossible to run locally** — enforced via a backend/role configuration that only the CI pipeline's OIDC-federated identity can assume, so no individual engineer's local credentials, however configured, could ever apply to production even if they tried.

**Risk controls:** audit whether any other environment's apply is currently runnable by a locally-authenticated engineer at all, and close that gap universally, not just for this one incident's specific account.

**Validation steps:** confirm the corrected production apply (via the pipeline) succeeds and matches the originally-intended plan, and confirm the staging cleanup leaves that environment in a clean, verified state via its own `plan` showing zero unexpected diff afterward.

**Rollback or recovery strategy:** the staging cleanup via reviewed destroy is itself the recovery; there's no production-side rollback needed since production was never actually touched — the "incident" is entirely contained to an accidental staging change.

**Long-term prevention:** restrict the IAM role used for production applies to only be assumable via the CI platform's OIDC federation (see [Question 37 in category 4](04-providers.md#question-37-the-assume-role-trust-policy-that-trusted-too-much)), with no human-assumable path to it at all — this makes "wrong account" mistakes for production structurally impossible, not just less likely, regardless of any individual's local credential hygiene.

### Step-by-Step Implementation
```bash
# Staging cleanup: identify what was accidentally created
terraform -chdir=environments/staging state list
# Cross-reference against the intended production plan's resource list to confirm scope

# Reviewed destroy of the accidental resources in staging
terraform -chdir=environments/staging plan -destroy -target=aws_instance.accidental
terraform -chdir=environments/staging apply -destroy -target=aws_instance.accidental
```
```json
// Production role trust policy: no human-assumable path, OIDC only
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::...:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:sub": "repo:my-org/infra:environment:production" }
  }
  // Note: no corresponding trust statement allowing any IAM user/human-assumable role
}
```

### Under-the-Hood Explanation
Terraform's provider configuration resolves its actual AWS credentials from whatever the ambient environment provides at run time (environment variables, an AWS CLI profile's default credential chain, an assumed-role session) — Terraform itself has no independent concept of "which account did the engineer mean to target"; it simply uses whatever the resolved credentials grant access to. This is precisely why the only structural fix (not just a procedural reminder) is making the target account's role unreachable via any locally-available credential path at all — removing the possibility of ambient-credential mismatches by removing the ambient-credential path to production entirely.

### Common Weak Answer
"Remind engineers to double-check their AWS profile before running Terraform locally."

### Why the Weak Answer Fails
This is a procedural reminder addressing a problem that a structural fix (making production applies impossible to run locally, only reachable via the OIDC-federated CI pipeline) eliminates entirely — reminders rely on every engineer remembering correctly every time, which this incident just demonstrated doesn't reliably happen.

### Follow-Up Questions
1. How would you handle legitimate cases where an engineer genuinely needs local, interactive access to production for a specific debugging task (e.g., a `terraform console` session)?
2. What would you check for immediately after this incident to make sure no other production-adjacent role has a similar human-assumable gap?
3. How does this risk change in an organization using Terraform Cloud/Enterprise instead of a self-managed backend plus local CLI usage?

### Key Interview Signals
Confirms the candidate proposes a structural, credential-architecture fix (making the mistake impossible) rather than a procedural reminder (making the mistake merely less likely), which is the recurring theme distinguishing senior from mid-level troubleshooting answers throughout this repository.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/) and [Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 90: The apply that AWS said "slow down" to

### Scenario
An apply creating 200 nearly-identical IAM roles (one per microservice, as part of a platform migration) fails partway through with a mix of successes and `Throttling: Rate exceeded` errors from the IAM API, at unpredictable points depending on run timing.

### Interview Question
Fix the immediate failure and redesign the apply to avoid it going forward.

### Strong Senior-Level Answer
**Initial assessment:** IAM (and several other AWS services) enforce relatively low API rate limits compared to Terraform's default parallelism (10 concurrent operations) — 200 near-simultaneous `CreateRole`/`PutRolePolicy` calls at default parallelism is a plausible way to exceed IAM's specific rate limits, especially if this account has done a lot of other recent IAM activity contributing to the same rate-limit bucket.

**Technical reasoning:** state was written incrementally for every role that succeeded before the throttling errors began (see [`terraform-internals.md` §10](../docs/terraform-internals.md#10-state-serial-and-lineage-and-reconciliation-during-apply)), so this is a partial-apply situation, not a total failure — a straightforward `terraform plan` will show exactly which roles are still pending.

**Investigation process:** confirm via the plan (not assumption) exactly which roles succeeded and which remain, and check whether the AWS provider's own built-in retry/backoff for throttling is already engaged (many AWS SDK-based providers have some automatic retry behavior for throttling responses, but it can still be exhausted under sustained heavy load) versus this being a case needing external mitigation.

**Recommended solution:** reduce `-parallelism` for this specific apply (e.g., from the default 10 down to 3-4) to stay under IAM's practical rate limit, and re-run `terraform apply` — the incremental state means this resumes cleanly, only creating the roles that don't already exist. For a longer-term structural fix given this is a recurring migration pattern (200 more roles might be needed again later), consider whether AWS's own IAM service quotas can be raised via a support request, or whether the roles can be batched into smaller sequential applies rather than one giant one.

**Risk controls:** avoid simply cranking parallelism to the maximum default or higher for large applies without considering the specific target service's rate limits — different AWS services have very different practical throughput before throttling, and a one-size-fits-all parallelism setting isn't appropriate for every kind of large-scale apply.

**Validation steps:** confirm the resumed apply, with reduced parallelism, completes all 200 roles without further throttling errors, and spot-check several of the created roles for correct configuration.

**Rollback or recovery strategy:** since state accurately reflects what succeeded, no destructive rollback is needed — this is purely a "resume with adjusted parallelism" recovery, not a scenario requiring undoing anything.

**Long-term prevention:** document the appropriate `-parallelism` setting for large-scale applies against rate-limit-sensitive services (IAM specifically, but also others like Route 53) as institutional knowledge, and consider whether future similar migrations should be batched (e.g., 50 roles per apply, run sequentially) rather than one large apply straining a single service's rate limits.

### Step-by-Step Implementation
```bash
# Confirm exactly what succeeded before the throttling errors
terraform state list | grep aws_iam_role | wc -l   # e.g., 140 of 200 succeeded

# Resume with reduced parallelism to stay under IAM's practical rate limit
terraform apply -parallelism=3
```
```bash
# If throttling persists even at reduced parallelism, check for other concurrent IAM activity
# contributing to the same account-wide rate-limit bucket
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=iam.amazonaws.com \
  --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
```

### Under-the-Hood Explanation
Terraform's `-parallelism` flag controls how many resource operations (RPC calls to the provider) it will have in flight simultaneously during apply — AWS services implement their own independent, service-specific API rate limits (IAM's are notably lower than many other services') that are entirely outside Terraform's knowledge; when the number of concurrent `CreateRole`/`PutRolePolicy` calls Terraform issues exceeds what IAM's rate limiter allows, some calls receive a `Throttling` error response, which most AWS-SDK-based providers will retry a limited number of times internally before surfacing the error to Terraform if retries are exhausted — reducing `-parallelism` directly reduces how many concurrent calls are ever attempted, avoiding triggering the rate limit in the first place rather than relying on retry exhaustion recovery.

### Common Weak Answer
"Just keep re-running `terraform apply` until it eventually gets through all 200 roles."

### Why the Weak Answer Fails
Repeatedly re-running at the same (too-high) parallelism setting doesn't address the actual cause — it might eventually succeed through luck (varying load conditions), but it's an unreliable, slow way to work around a rate-limit problem that a straightforward `-parallelism` reduction solves deterministically and immediately.

### Follow-Up Questions
1. How would you determine the right `-parallelism` value for a given AWS service without just trial-and-error guessing?
2. How does this problem manifest differently for a service with a *per-second* rate limit versus one with a *burst-then-sustained* rate limit model?
3. How would you design the Terraform configuration itself (not just the CLI flag) to make this large-scale role creation more resilient to rate limiting in the future?

### Key Interview Signals
Confirms the candidate understands `-parallelism` as a direct lever for exactly this class of problem, and recognizes state's incremental-write nature means a throttled partial apply is safely resumable, not something requiring anxious manual reconciliation.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 91: The plan that ate the CI runner's memory

### Scenario
A `terraform plan` against your organization's largest remaining monolithic state (several thousand resources, not yet split per the redesign from [Question 15 in category 2](02-state-management.md#question-15-the-plan-that-took-twenty-minutes)) starts failing in CI with the runner being OOM-killed partway through, on a runner size that worked fine a few months ago.

### Interview Question
Diagnose this and provide both an immediate fix and the real long-term answer.

### Strong Senior-Level Answer
**Initial assessment:** memory usage during plan scales with the size of the state and configuration being processed (every resource's refreshed attributes, the full dependency graph, and the rendered diff all need to be held in memory during the plan cycle) — a state that's grown large enough, combined with a fixed-size CI runner, has crossed a threshold where the runner's available memory is no longer sufficient, likely gradually, as the state grew over "a few months."

**Technical reasoning:** the *immediate* fix (a larger CI runner) buys time but doesn't address the root cause — this state's growth trajectory means it will likely exceed whatever new runner size is chosen too, eventually, unless the actual resource-count/blast-radius problem (identical to Question 15) is addressed.

**Investigation process:** confirm the OOM is genuinely correlated with state size growth (check the state's resource count over the past several months against when runner memory started becoming an issue) rather than some unrelated regression (a provider version bump that increased per-resource memory overhead, for instance, is also worth ruling out).

**Recommended solution:** immediately, increase the CI runner's memory allocation to unblock current work (a straightforward, low-risk mitigation). Simultaneously, treat this OOM failure as the forcing function to finally execute the state-splitting redesign from Question 15 that had been deferred — the memory-exhaustion symptom is just a more dramatic version of the same underlying problem (a monolithic state too large for efficient, safe operation) already identified previously.

**Risk controls:** while planning the state split, avoid repeatedly bumping the runner size as a recurring "fix" each time it happens again — treat runner-size increases as a strictly temporary bridge to the actual architectural fix, with a committed timeline, not an indefinitely-repeatable patch.

**Validation steps:** after the state split, confirm each resulting smaller state's plan runs comfortably within a normal-sized CI runner's memory budget, with meaningful headroom for continued organic growth.

**Rollback or recovery strategy:** not applicable — this is a resource-sizing and architecture fix; no infrastructure state is at risk from the OOM failure itself (a killed plan process, unlike a killed apply, never wrote any state changes at all, since plan is read-only with respect to state).

**Long-term prevention:** track state size (resource count, plan duration, and now plan memory usage) as an ongoing operational metric with an alert threshold well before it becomes a hard failure, so the next monolithic state approaching this same limit is caught and addressed proactively, not discovered via a CI outage.

### Step-by-Step Implementation
```yaml
# Immediate bridge: larger CI runner
runs-on: ubuntu-latest-8-core   # or equivalent larger memory tier, temporarily
```
```bash
# Confirm state size growth correlation
terraform state list | wc -l   # check current count
git log --oneline -- environments/production/ | wc -l   # rough proxy for growth over time
```
```text
# Long-term: execute the deferred state-splitting redesign from Question 15,
# using the OOM incident as the forcing function/priority justification
```

### Under-the-Hood Explanation
During plan, Terraform holds the full refreshed state, the complete dependency graph, and the computed diff for every resource in the configuration in memory simultaneously (there's no resource-by-resource streaming/discard during a single plan operation) — as resource count grows, this memory footprint grows correspondingly, and a CI runner with a fixed memory allocation will eventually be OOM-killed once the state's actual memory requirement exceeds what's available, which is exactly the mechanism connecting "state grew over several months" to "a runner size that worked fine before now fails."

### Common Weak Answer
"Just give the CI runner more memory and move on."

### Why the Weak Answer Fails
This addresses only the immediate symptom without acknowledging that a monolithic, ever-growing state will very likely exceed whatever new runner size is chosen too, at some future point — the question specifically asks for the long-term answer as well, which requires connecting this back to the state-splitting architectural fix, not just resizing infrastructure indefinitely as the state keeps growing.

### Follow-Up Questions
1. How would you estimate the memory requirement for a given state size in advance, to set proactive alert thresholds?
2. What's the relationship between plan-time memory usage and plan-time duration — are they always correlated, or can one be high while the other is low?
3. How would you prioritize which parts of this monolithic state to split off first, if the OOM incident creates urgency but full-scope splitting will still take real time?

### Key Interview Signals
Confirms the candidate doesn't treat "add more runner memory" as a complete answer, and connects an acute operational failure (OOM) back to the underlying architectural debt (monolithic state) it's actually a symptom of.

### Hands-On Connection
[Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/) and [Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 92: The import that needed three tries to get the ID right

### Scenario
An engineer attempting to import an existing `aws_lb_listener_rule` resource into Terraform management tries several ID formats based on educated guesses (the rule's ARN, then a combination of listener ARN and priority) before finding the one the provider actually expects, wasting significant time in the process.

### Interview Question
How would you approach import ID discovery systematically, rather than guessing?

### Strong Senior-Level Answer
**Initial assessment:** import ID format is entirely provider-and-resource-type-specific — there's no universal convention (some resources use the raw AWS ID, some use a composite of multiple fields separated by a specific delimiter, some use the full ARN) — guessing is unreliable specifically because there's no way to infer the correct format from general AWS knowledge alone; it has to come from the provider's own documentation for that exact resource type.

**Technical reasoning:** the authoritative source for any resource type's expected import ID format is that resource's page in the Terraform provider registry documentation (every resource that supports import documents its exact expected ID format and shows a worked example) — checking this first, before attempting any import, avoids the guess-and-check cycle entirely.

**Investigation process:** for `aws_lb_listener_rule` specifically, check the resource's registry documentation for its documented import ID format before attempting anything — most well-documented resources show the exact expected format (in this case as it happens, `aws_lb_listener_rule` uses the rule's own ARN as the import ID, which matches one of the engineer's guesses, but the more important lesson is checking first, not guessing until something works).

**Recommended solution:** for resources with generated configuration support (Terraform >= 1.5), use `terraform plan -generate-config-out=` alongside an `import` block, which handles the ID format according to the provider's own implementation and additionally drafts the matching configuration, removing the guesswork from both the import ID and the subsequent manual configuration-writing step.

**Risk controls:** for resource types where the documentation is ambiguous or the ID format seems unclear, test the import against a non-production copy of the resource (or a deliberately-created throwaway test resource of the same type) first, rather than iterating trial-and-error directly against a production resource's import.

**Validation steps:** after a successful import, always run `terraform plan` immediately and confirm it shows no unexpected diff (or, if using `-generate-config-out`, review the generated configuration carefully against the resource's actual real-world attributes) before considering the import complete.

**Rollback or recovery strategy:** a failed import attempt (wrong ID format) simply produces an error and doesn't modify state at all — there's no cleanup needed from an unsuccessful `import` block/command; the only "cost" of a wrong guess is wasted time, which is exactly what checking the documentation first avoids.

**Long-term prevention:** build a habit (and, ideally, a quick internal reference doc covering your most commonly-imported resource types' ID formats) of checking provider documentation for the exact import ID format before attempting any import, rather than relying on trial and error or generalized AWS-ID intuition.

### Step-by-Step Implementation
```bash
# Check the provider registry documentation FIRST (illustrative — actual lookup is via
# registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule
# under the "Import" section) rather than guessing
```
```hcl
# Using import blocks with generated configuration (Terraform >= 1.5) —
# removes guesswork from both ID format and configuration writing
import {
  to = aws_lb_listener_rule.app_routing
  id = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/my-alb/.../..." 
}
```
```bash
terraform plan -generate-config-out=generated_lb_rule.tf
# Review the generated configuration carefully before applying
terraform apply
terraform plan   # must show zero changes after the import is complete
```

### Under-the-Hood Explanation
Each resource type's `ImportResourceState` provider RPC implementation (see [`terraform-internals.md` §9](../docs/terraform-internals.md#9-provider-rpc-communication)) defines exactly how to parse the supplied import ID string into the resource's actual attributes — this parsing logic is entirely provider-specific and resource-type-specific, which is precisely why there's no universal ID format convention to rely on, and why the provider's own documentation (which describes exactly what that specific `ImportResourceState` implementation expects) is the only reliable source of truth, rather than pattern-matching from other resource types' conventions.

### Common Weak Answer
"Just keep trying different ID formats until one works."

### Why the Weak Answer Fails
Trial-and-error against a real (potentially production) resource wastes time and, for some resource types, a wrong-format import attempt can produce a confusing partial state entry or an ambiguous error rather than a clean rejection — checking the documented format first is faster, safer, and available for essentially every resource type that supports import.

### Follow-Up Questions
1. How would you handle a resource type where the import ID format genuinely isn't well-documented or is ambiguous?
2. What's the value of `-generate-config-out` beyond just solving the ID-format guessing problem?
3. How would you batch-import many resources of the same type efficiently, once you know the correct ID format pattern?

### Key Interview Signals
Confirms the candidate defaults to checking authoritative documentation rather than trial-and-error, and knows about `-generate-config-out` as the modern, lower-risk import workflow.

### Hands-On Connection
[Lab 6 — Import Existing Infrastructure](../labs/lab-06-import-existing-infrastructure/).

---

## Question 93: The provider stuck in the past

### Scenario
Your organization upgrades its Terraform CLI version as part of routine maintenance. One specific, older third-party provider (used for a niche internal tool integration, last updated by its maintainer over two years ago) fails to initialize against the new CLI version with a protocol-version incompatibility error.

### Interview Question
Diagnose and resolve this, including how you'd decide whether to keep using this provider at all.

### Strong Senior-Level Answer
**Initial assessment:** Terraform's provider protocol (the gRPC-based interface between Core and provider plugins, currently protocol version 5 or 6 depending on when a provider was built) has evolved over time — a provider that hasn't been updated in over two years may predate support for whatever protocol version the new CLI requires, which is a genuine compatibility ceiling, not a configuration mistake to simply fix.

**Technical reasoning:** Terraform CLI versions typically maintain compatibility with a range of provider protocol versions for some time, but an abandoned provider that was already old when this range last shifted can eventually fall entirely outside what any supported CLI version can talk to.

**Investigation process:** confirm the exact protocol version this specific provider implements (checking its source/release notes if available) against what your new CLI version requires, and check whether the provider has *any* more recent (even if not actively maintained) release that might support a newer protocol version despite the maintainer being largely inactive.

**Recommended solution:** if a compatible provider version exists (even an old one you hadn't picked up yet), pin to it and confirm compatibility. If genuinely no compatible version exists at all, you're facing a real decision: pin your entire organization's Terraform CLI version back to remain compatible with this one abandoned provider (a broad, undesirable constraint affecting every other configuration in the organization), fork and maintain the provider yourselves (a real but significant undertaking), or find/build an alternative way to manage this niche integration (potentially outside Terraform entirely, if it's genuinely small in scope, or via a community fork if one exists).

**Risk controls:** whichever path is chosen, don't let one abandoned, niche provider hold back Terraform CLI upgrades for every other configuration in the organization indefinitely — if pinning back is chosen as a stopgap, set an explicit deadline to resolve the dependency (fork, replace, or deprecate the integration) rather than treating the pin-back as a permanent state.

**Validation steps:** whatever path is chosen, confirm the resolution doesn't reintroduce the original problem for the *next* routine Terraform CLI upgrade — a temporary pin-back with no plan is just deferring the same decision to next time.

**Rollback or recovery strategy:** if the CLI upgrade needs to be rolled back organization-wide to unblock this one provider's dependent configuration, scope that rollback narrowly and communicate clearly that it's temporary, with a tracked plan to resolve the underlying dependency.

**Long-term prevention:** treat any provider with no update in a long time as a flagged risk during any dependency audit — not necessarily requiring immediate action, but tracked as technical debt that will eventually force exactly this kind of forced-decision moment during a future CLI upgrade, ideally addressed proactively rather than reactively.

### Step-by-Step Implementation
```bash
# Check the provider's protocol version support
terraform providers schema -json | jq '.provider_schemas | keys'
# Check the provider's release history for any more recent compatible version
```
```hcl
# Stopgap: pin CLI version organization-wide (undesirable long-term, but unblocks immediately)
terraform {
  required_version = "~> 1.7.0"   # pinned back specifically for this abandoned-provider dependency
}
```
```markdown
<!-- Tracked technical debt item, with an explicit deadline -->
- [ ] Resolve niche-tool-provider compatibility by 2026-10-01: fork, replace, or deprecate
      the integration so the org's Terraform CLI version isn't held back indefinitely.
```

### Under-the-Hood Explanation
Terraform's provider plugin protocol (gRPC-based, versioned as protocol 5 or 6) defines the RPC contract between Core and any provider plugin — Core negotiates the protocol version during the initial handshake with a provider binary, and a provider built against a protocol version no longer supported by the current CLI simply cannot complete that handshake, producing exactly the incompatibility error described; this is a genuine architectural compatibility boundary, not a configuration issue fixable via a flag, which is precisely why the resolution options are all fairly significant (pin back, fork, replace) rather than a quick fix.

### Common Weak Answer
"Just find a workaround to force the provider to work with the new version."

### Why the Weak Answer Fails
There's no supported flag or configuration workaround to bridge a genuine provider-protocol-version incompatibility — this is a real compatibility ceiling requiring one of the substantive decisions (pin back with a deadline, fork, replace) described, not a quick technical fix to search for.

### Follow-Up Questions
1. How would you evaluate whether forking and maintaining this provider yourselves is worth the ongoing maintenance burden, versus finding an alternative integration approach?
2. How would you audit your organization's full provider dependency list for other similarly-abandoned providers before they cause the same forced decision during a future upgrade?
3. What would you do differently if this provider were used by a single, low-priority internal tool versus a business-critical integration?

### Key Interview Signals
Confirms the candidate recognizes a genuine architectural compatibility boundary (not a configuration bug) and can reason through the real, non-trivial trade-offs of the available resolution paths rather than searching for a nonexistent quick fix.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 94: The destroy that left something behind

### Scenario
A Terraform-managed VPC peering connection is destroyed as part of decommissioning a legacy environment. Weeks later, a different team reports their application (in a third, unrelated account) has lost connectivity to a resource — it turns out their team had manually added a route table entry, outside of any Terraform configuration, that depended on the now-destroyed peering connection, and nobody had any record of that dependency.

### Interview Question
How do you handle the immediate incident, and how would you prevent this class of hidden cross-team dependency from causing surprise outages in the future?

### Strong Senior-Level Answer
**Initial assessment:** the destroyed peering connection was, from your Terraform configuration's perspective, entirely unused and safe to remove — the actual dependency existed only in a different team's manually-created, undocumented route table entry, invisible to any tooling or review process scoped to the decommissioning team's own configuration.

**Technical reasoning:** this is fundamentally a cross-team dependency visibility problem — Terraform (or any single team's tooling) can only see dependencies expressed within its own managed scope; a manually-created resource in a third account referencing your resource is invisible to your plan, your state, and any pre-decommission review you might have done.

**Investigation process:** work with the affected team to understand exactly what they'd manually configured and why it was never captured in any Terraform configuration (a legitimate historical gap, or evidence of a broader pattern of manual, untracked cross-account networking changes worth auditing more broadly).

**Recommended solution:** immediately, recreate the peering connection (via Terraform, properly, so it's now tracked) to restore the affected team's connectivity while a more permanent fix is designed — or, if recreating exactly isn't feasible/desirable, work with the affected team to migrate their dependency onto a supported, documented connectivity path instead. For the systemic fix: before decommissioning any shared networking resource (peering connections, Transit Gateway attachments, shared security groups) going forward, require an active cross-account dependency check — querying route tables, security group references, and DNS records across the *entire organization* (not just your own account) for any reference to the resource being decommissioned, not relying on your own Terraform state's view alone, since it structurally cannot see dependencies created outside itself.

**Risk controls:** for any organization-wide shared resource (this exact class of thing — peering connections, shared VPC endpoints, shared KMS keys), maintain a dependency registry or at minimum a required "who else might depend on this" check as part of any decommissioning runbook, rather than trusting that Terraform's own visibility is complete.

**Validation steps:** after recreating the peering connection, confirm the affected team's connectivity is fully restored, and after establishing the pre-decommission dependency-check process, test it against a known cross-account dependency in a controlled scenario to confirm it actually surfaces what your own state alone would have missed.

**Rollback or recovery strategy:** the peering-connection recreation is itself the recovery for this specific incident; there's no "undo" needed for the original destroy since the fix is simply restoring the needed connectivity.

**Long-term prevention:** this incident is a strong argument for reducing ad hoc, per-need manual networking changes generally (in favor of centralized, Terraform-managed connectivity per [Question 44 in category 5](05-aws-architecture.md#question-44-the-mesh-nobody-could-keep-in-their-head)) — a properly centralized, fully-Terraform-managed networking architecture makes this exact class of invisible cross-account dependency far less likely to exist in the first place, since manual, undocumented route table entries wouldn't be the normal way connectivity gets established.

### Step-by-Step Implementation
```bash
# Cross-account dependency check before any future shared-resource decommission
# (conceptual - actual implementation depends on your org's account-scanning tooling)
for account in $(cat all-account-ids.txt); do
  aws ec2 describe-route-tables --profile "account-${account}" \
    --filters "Name=route.vpc-peering-connection-id,Values=pcx-0abc123" 
done
```
```hcl
# Immediate recovery: recreate the peering connection, now properly Terraform-managed
resource "aws_vpc_peering_connection" "restored" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = var.peer_vpc_id
  peer_owner_id = var.peer_account_id
}
```

### Under-the-Hood Explanation
Terraform's dependency graph and state are scoped entirely to the resources declared within that specific configuration — there is no mechanism (and no way there could be one, given Terraform's architecture) for a decommissioning team's `terraform plan`/`destroy` to discover that a manually-created resource in an entirely separate AWS account and Terraform state references the resource being destroyed, since that reference exists purely at the AWS API level (a route table entry pointing at a peering connection ID) with no corresponding entry in any Terraform configuration or state that the decommissioning team has visibility into.

### Common Weak Answer
"Terraform should have warned us this resource was still in use before letting us destroy it."

### Why the Weak Answer Fails
This isn't something Terraform can structurally provide — it has no visibility into infrastructure or dependencies outside the specific state/configuration being operated on, especially not a manually-created resource in a completely separate account's route table; the fix has to be an organizational/process one (a cross-account dependency check as part of the decommissioning runbook), not an expectation that Terraform itself will somehow catch this.

### Follow-Up Questions
1. How would you build tooling to make cross-account dependency checks for shared networking resources a routine, low-effort part of any decommissioning process?
2. What's the argument for centralizing shared connectivity (Transit Gateway, per Question 44) specifically as a way to reduce this class of invisible-dependency risk?
3. How would you handle a similar hidden-dependency discovery for a shared IAM role or KMS key instead of network connectivity?

### Key Interview Signals
Confirms the candidate correctly identifies this as a fundamental visibility limitation of any single team's Terraform state (not a Terraform bug to complain about) and designs an organizational process fix (cross-account dependency checking) rather than expecting tooling to solve an inherently cross-boundary problem on its own.

### Hands-On Connection
[Lab 8 — AWS Networking Platform](../labs/lab-08-aws-networking/) and [Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 95: The plan that disagreed with itself

### Scenario
Two engineers, running `terraform plan` against the same commit and the same state within minutes of each other on two different CI runners, get different plan output — one shows a particular resource needing an update, the other shows no change at all for that same resource.

### Interview Question
What would cause two plans against identical inputs to disagree, and how would you investigate?

### Strong Senior-Level Answer
**Initial assessment:** identical configuration and identical state should, in principle, produce identical plans — a genuine disagreement points to something differing between the two runners' environments, most likely a provider plugin version/cache inconsistency (one runner has a stale or corrupted cached provider binary that behaves differently than the other's correctly-resolved one) or, less commonly, a data source producing genuinely different results between the two plan runs due to real-world state changing in between them.

**Technical reasoning:** if both runners are supposed to use identical provider versions (per the committed lock file), but one has a corrupted or outdated cached copy that wasn't properly refreshed, its plan could reflect subtly different schema/behavior than the other runner's correctly-resolved provider — this is a caching/consistency problem, not a Terraform Core bug.

**Investigation process:** compare the actual provider version and checksum each runner resolved (`terraform version` output includes provider versions; check each runner's `.terraform/providers` directory or plugin cache contents) — a mismatch here immediately explains the disagreement. If provider versions genuinely match on both runners, consider whether the resource's plan depends on a data source or `timestamp()`-like function that could legitimately produce different results at slightly different moments (some resources' "no changes" vs. "needs update" diff can hinge on a data source that changed between the two plan invocations, if real-world state changed in the intervening minutes).

**Recommended solution:** if it's a provider cache inconsistency, clear the stale/corrupted cache on the affected runner and force a fresh resolution, then re-run both plans and confirm they now agree. If it's a genuine data-source timing difference, that's actually expected behavior (not a bug) — the fix is understanding which data source is time-sensitive and, if its volatility is a problem for review purposes, considering whether it should be pinned/cached at plan-artifact-save time rather than re-evaluated at every plan invocation.

**Risk controls:** ensure your CI runner fleet's provider plugin cache (if shared) has some integrity verification, similar to [Question 87](#question-87-the-provider-that-wouldnt-verify), so a corrupted cache entry doesn't silently produce inconsistent behavior across runners without an obvious error.

**Validation steps:** after resolving the cache inconsistency, re-run the plan on both runners simultaneously and confirm identical output — this is the concrete proof the disagreement is resolved, not just a theory about the cause.

**Rollback or recovery strategy:** not applicable — this is a diagnostic/environment-consistency fix; no infrastructure was affected since no apply occurred based on the disagreeing plans yet (and this disagreement is exactly why relying on a specific, saved plan artifact — not a freshly regenerated one per [Question 69 in category 8](08-cicd.md#question-69-the-apply-that-wasnt-quite-what-was-reviewed) — matters even more once you know plan output can genuinely vary between environments).

**Long-term prevention:** ensure CI runner images/caches are built and refreshed consistently (ideally from a single, versioned base image or a verified, integrity-checked shared cache) so "which specific runner happened to execute this job" never introduces this kind of environment-dependent variability into what should be a deterministic operation given identical configuration and state inputs.

### Step-by-Step Implementation
```bash
# Compare provider versions/checksums resolved on each runner
terraform version   # shows resolved provider versions
sha256sum .terraform/providers/registry.terraform.io/hashicorp/aws/*/linux_amd64/terraform-provider-aws_v*

# If mismatched or corrupted, clear and force fresh resolution
rm -rf .terraform/providers
terraform init
terraform plan   # re-run and compare against the other runner's output
```

### Under-the-Hood Explanation
Given byte-identical configuration, an identical state, and byte-identical provider plugin binaries, Terraform's plan computation is deterministic — the graph construction, diff calculation, and RPC calls to the provider should produce identical results every time. Any observed divergence between two runs against the same inputs therefore points to something *not* actually identical between the two executions: most commonly a provider binary difference (corrupted cache, different resolved version despite an apparently-matching lock file, e.g., if the lock file's platform-specific checksum entries don't cover both runners' architectures correctly), or a genuinely time-varying data source producing different real-world results at two different moments.

### Common Weak Answer
"Terraform plans can just be a bit inconsistent sometimes, it's probably nothing to worry about."

### Why the Weak Answer Fails
Dismissing a genuine plan disagreement as expected noise ignores that Terraform's plan computation is meant to be deterministic given identical inputs — treating this as normal rather than investigating risks missing either a real environment-consistency bug (corrupted cache) or a genuinely time-sensitive data source that could cause exactly the "reviewed plan doesn't match applied reality" problem this whole category of concern (see [Question 69](08-cicd.md#question-69-the-apply-that-wasnt-quite-what-was-reviewed)) is designed to prevent.

### Follow-Up Questions
1. How would you design your lock file / CI runner architecture to make this class of provider-cache inconsistency structurally less likely?
2. If the cause turns out to be a time-sensitive data source, how would you decide whether that's a design problem with the configuration itself?
3. How does this investigation change if the two "runners" are actually the same runner, run twice, rather than two different machines?

### Key Interview Signals
Confirms the candidate treats non-deterministic plan output as a genuine anomaly worth root-causing (provider cache consistency, or data-source volatility) rather than dismissing it as acceptable noise, reinforcing the broader theme that Terraform's plan should be a reliable, reproducible signal.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 96: The apply that Terraform itself didn't survive

### Scenario
Midway through a large `terraform apply`, the Terraform process itself crashes — not a provider error, but a `crash.log` file is written and the process exits with a Go panic trace, leaving the apply incomplete.

### Interview Question
How do you distinguish this from a normal apply failure, and what's your process?

### Strong Senior-Level Answer
**Initial assessment:** a `crash.log` with a Go panic trace indicates Terraform Core itself hit an unexpected internal error (a genuine bug, as opposed to a well-formed error from a provider or a normal validation failure) — this is a different category of failure requiring different handling: state was still written incrementally for whatever completed before the crash, but the crash itself is worth reporting upstream, not just working around silently.

**Technical reasoning:** treat the immediate operational recovery (what's the actual state of applied infrastructure, and how to safely resume) exactly like any other interrupted/partial apply (see [Question 7 in category 1](01-terraform-core.md#question-7-the-apply-that-died-halfway-through-a-data-migration)) — the crash's *cause* is a separate, secondary investigation from the *recovery*, and shouldn't block getting infrastructure into a known-good state first.

**Investigation process:** first, recovery: run `terraform state list` to confirm what succeeded, and `terraform plan` to see what Terraform now believes remains — a Core crash, like any interrupted apply, still benefits from the incremental state-write guarantee. Second, root-cause: read the `crash.log` for the panic trace's specifics — does it reference a specific resource type/provider interaction, a specific Terraform Core internal function, or a specific configuration construct (an unusual `for_each` expression, a complex nested data structure) that might be triggering an edge case?

**Recommended solution:** for the immediate recovery, proceed with the standard partial-apply plan-then-apply process. For the crash itself, check HashiCorp's GitHub issues for a matching report against your specific Terraform version — Core panics are bugs and are usually eventually fixed in a subsequent release; if no existing report matches, file one with the crash log and a minimal reproduction if you can construct one, since this is exactly the kind of report that helps HashiCorp fix genuine Core defects.

**Risk controls:** if the crash seems correlated with a specific, unusual configuration pattern (e.g., an extremely large `for_each` map, or deeply nested dynamic blocks), consider whether that pattern can be simplified/restructured to avoid triggering the same edge case again, as a practical workaround while awaiting an upstream fix.

**Validation steps:** after resuming the apply successfully (post-crash), confirm the complete, intended infrastructure state is correctly in place, exactly as you would for any other interrupted-apply recovery.

**Rollback or recovery strategy:** identical to the standard interrupted/partial apply recovery process — the crash doesn't change the fundamental recovery approach, just adds a secondary "should this be reported upstream" step.

**Long-term prevention:** if a specific Terraform version is confirmed to have a reproducible crash bug for a pattern your organization relies on, consider pinning back to a known-stable version until a fix is released, and track the upstream issue for when to safely upgrade again.

### Step-by-Step Implementation
```bash
# Standard interrupted-apply recovery process, regardless of crash vs. normal interruption
terraform state list   # confirm what succeeded
terraform plan -out=resume.tfplan
terraform show resume.tfplan   # review carefully
terraform apply resume.tfplan

# Separately: investigate and report the crash itself
cat crash.log | head -50   # examine the panic trace
# Check https://github.com/hashicorp/terraform/issues for a matching report
# If none found, file a new issue with crash.log attached and a minimal repro if possible
```

### Under-the-Hood Explanation
A `crash.log` with a Go panic trace indicates an unrecovered runtime panic within Terraform Core's own Go code — distinct from a well-formed error returned by a provider RPC call or a configuration validation failure, both of which Terraform handles gracefully as expected error conditions. A panic represents Core hitting a code path its own error handling didn't anticipate; state writes that completed *before* the panic are unaffected (they were already durably written), but Terraform's structured, standard error-handling and messaging is bypassed for whatever was in-flight at the moment of the crash, which is why the recovery approach still relies on independently verifying actual state via `state list`/`plan` rather than trusting any specific error message from the crash itself.

### Common Weak Answer
"Just re-run the apply and see if it crashes again."

### Why the Weak Answer Fails
This skips both the deliberate partial-apply investigation (confirming exactly what succeeded before blindly retrying) and the valuable step of examining and potentially reporting the crash itself — a reflexive retry might work by luck if the crash was a rare timing-dependent edge case, but doesn't provide the same confidence as an explicit `plan`-first verification, and misses the opportunity to help identify and fix a genuine upstream bug.

### Follow-Up Questions
1. How would you construct a minimal reproduction case for a crash that seems related to a specific, complex configuration pattern?
2. How does your recovery process differ if the crash log indicates the panic happened during the *plan* phase versus the *apply* phase?
3. What would you do if the same crash recurred reliably every time you tried to resume the apply — would you still proceed with the same recovery steps?

### Key Interview Signals
Confirms the candidate distinguishes a genuine Core defect (crash/panic) from a normal error, treats the recovery process consistently with any other interrupted apply, and takes the extra step of investigating/reporting the underlying bug rather than just retrying blindly.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 97: The data source that changed its mind mid-apply

### Scenario
A configuration uses a `data "aws_ami" "latest"` lookup (filtering for the most recent AMI matching a pattern) to determine which AMI an `aws_launch_template` should use. Between the `plan` step (run in the morning) and the `apply` step (run that afternoon, using a saved plan file, per your standard pipeline design), a new AMI matching the same filter pattern is published. The apply proceeds using the AMI ID that was resolved at plan time, but a team member is confused why a "new" AMI published since the plan won't be used until the *next* apply.

### Interview Question
Is this the correct behavior? Explain what's actually happening and whether it's a gap in your pipeline.

### Strong Senior-Level Answer
**Initial assessment:** this is correct and expected behavior, not a gap — a saved plan file locks in the resolved value of every data source at the moment the plan was generated (part of the same "the applied plan is provably identical to the reviewed plan" guarantee from [Question 69 in category 8](08-cicd.md#question-69-the-apply-that-wasnt-quite-what-was-reviewed)); applying that saved plan later must use the AMI ID it already resolved and that a human reviewed, not silently re-resolve the data source to whatever's newest at apply time.

**Technical reasoning:** if `apply` silently re-resolved data sources to their current real-world values instead of using what the saved plan recorded, the applied outcome could diverge from what was actually reviewed — exactly the guarantee-breaking scenario the saved-plan-artifact pattern exists to prevent, just manifesting via a data source rather than a resource attribute.

**Investigation process:** confirm this is indeed what happened by inspecting the saved plan file's contents (`terraform show <plan-file>`) and confirming the AMI ID it references matches what was actually applied, and predates the newly-published AMI the team member is asking about — this confirms the behavior is working exactly as designed, not a bug.

**Recommended solution:** no fix is needed for the mechanism itself — it's correct. The actual gap, if any, is a **process/cadence** question: if your organization wants newly-published AMIs to be picked up faster than "whenever the next scheduled plan happens to run," that's a cadence decision (e.g., trigger a fresh plan/PR whenever a new golden AMI is published, rather than relying on incidental periodic plans) — not a Terraform behavior to change.

**Risk controls:** communicate this behavior clearly to teams relying on "latest AMI" data sources — the "latest" is always "latest as of plan generation time," never "latest as of apply time," which is an important operational expectation to set explicitly rather than let people be surprised by it, as happened here.

**Validation steps:** if a faster AMI-adoption cadence is genuinely desired, implement it (e.g., a webhook/scheduled trigger from your AMI-publishing pipeline that opens a fresh plan/PR) and confirm the new cadence actually produces plans incorporating newly-published AMIs within the desired timeframe.

**Rollback or recovery strategy:** not applicable — no incorrect behavior occurred; if the team specifically wanted the newer AMI applied sooner, the "fix" is simply re-running plan now (any fresh `terraform plan` will pick up the newly-published AMI, since a *new* plan re-evaluates data sources against current real-world values) and going through the normal review/apply cycle for that fresh plan.

**Long-term prevention:** document this "data sources resolve at plan time, not apply time, when using saved plan artifacts" behavior clearly in your organization's Terraform onboarding material, since it's a common point of confusion (and a direct, necessary consequence of the plan-artifact-integrity guarantee this whole pipeline design is built around) that's worth setting expectations for proactively.

### Step-by-Step Implementation
```bash
# Confirm the saved plan's resolved AMI ID matches what was applied
terraform show tfplan | grep -A3 'ami ='
# Compare against the newly-published AMI's ID and creation date
aws ec2 describe-images --owners self --filters "Name=name,Values=golden-ami-*" \
  --query 'Images | sort_by(@, &CreationDate)[-1]'
```
```bash
# If faster adoption cadence is desired: trigger a fresh plan on new AMI publication,
# rather than relying on the next incidental scheduled plan
# (e.g., a webhook from the AMI-baking pipeline opening a PR/triggering a plan job)
```

### Under-the-Hood Explanation
When `terraform plan -out=tfplan` runs, every data source in the configuration is evaluated against real-world state *at that moment*, and its resolved result is embedded directly into the saved plan file — `terraform apply tfplan` does not re-invoke the data source's `ReadDataSource` RPC at all; it uses the value already captured in the plan file, exactly as it uses the captured resource diff rather than recomputing it. This is precisely the same mechanism (and the same reason) as the state serial/lineage staleness check discussed in [Question 10 of category 1](01-terraform-core.md#question-10-the-workflow-gap-between-plan--out-and-a-later-apply) — the saved plan file is a complete, frozen snapshot of everything needed to apply exactly what was reviewed, data sources included.

### Common Weak Answer
"That's a bug — the apply should always use the latest AMI available."

### Why the Weak Answer Fails
This misunderstands the entire purpose of the saved-plan-artifact pattern — "always use the latest at apply time" is precisely the behavior that would break the guarantee that what was reviewed is what gets applied, reintroducing the exact risk the plan-then-apply-the-same-artifact design exists to prevent, just via a data source instead of a resource attribute.

### Follow-Up Questions
1. How would you design a pipeline that wants both the plan-artifact-integrity guarantee *and* fast adoption of newly-published AMIs — are these actually in tension, or can both be satisfied?
2. What would happen differently if this configuration didn't use a saved plan file at all, and instead ran `plan` and `apply` back-to-back in the same pipeline step?
3. How does this same "resolved at plan time" behavior apply to other commonly-used "latest"-style data sources, like `aws_ssm_parameter` fetching a dynamic value?

### Key Interview Signals
Confirms the candidate recognizes this as correct, intentional behavior (not a bug) directly tied to the plan-artifact-integrity guarantee, and can explain the underlying mechanism clearly enough to resolve a teammate's genuine confusion without introducing an unnecessary "fix."

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 98: The resource Terraform swore didn't exist yet

### Scenario
A configuration creates an S3 bucket and, in the same apply, a bucket policy referencing it. The apply intermittently fails with a `NoSuchBucket` error on the bucket-policy step, despite the bucket resource showing as successfully created moments earlier in the same apply's output, and despite an explicit `depends_on` already being present between the two resources.

### Interview Question
Given that ordering is already correct (`depends_on` exists), what else could cause this, and how would you fix it?

### Strong Senior-Level Answer
**Initial assessment:** with correct ordering already confirmed via `depends_on`, the most likely remaining explanation is genuine AWS-side eventual consistency — S3's control plane occasionally exhibits a brief propagation delay between a bucket's creation being confirmed via the API and that bucket being consistently visible to *all* subsequent API calls (including from a different service's perspective, like the bucket-policy-setting call), especially under certain conditions (cross-region considerations, or specific API call patterns).

**Technical reasoning:** this is a genuine, if infrequent, AWS API-level consistency gap — not a Terraform graph/ordering bug, since ordering is already correctly established; it manifests as intermittent, not constant, exactly matching this scenario's description.

**Investigation process:** confirm this is genuinely intermittent (re-running the identical apply sometimes succeeds without any code change) rather than a deterministic, always-reproducing failure, which would point to a real configuration bug instead; check whether the specific AWS region/account has any unusual characteristics that might make this particular consistency gap more pronounced (rare, but worth ruling out).

**Recommended solution:** since Terraform Core itself has no built-in retry-with-backoff specifically for this kind of downstream-consistency gap between two related-but-distinct resources, and this isn't a `depends_on` fix (ordering is already correct), the practical mitigation is a `time_sleep` resource between the two — one of the few genuinely legitimate uses of `time_sleep`, specifically for a known, narrow eventual-consistency gap that correct dependency ordering alone can't eliminate (as opposed to using it as a substitute for `depends_on`, which is the anti-pattern called out in [Question 8 of category 1](01-terraform-core.md#question-8-the-intermittent-iam-race)).

**Risk controls:** keep the sleep duration modest and specifically scoped to this known gap (a few seconds), not a large, blanket delay — and document clearly in the configuration *why* this sleep exists (a specific, known AWS eventual-consistency behavior), so a future engineer doesn't mistake it for an accidental leftover or, worse, remove it without understanding why it was needed.

**Validation steps:** after adding the sleep, run the apply repeatedly (ideally from a clean destroy/recreate cycle several times) to confirm the intermittent failure no longer reproduces — a single successful run isn't sufficient proof for an intermittent issue.

**Rollback or recovery strategy:** if the intermittent failure recurs despite the sleep, that's a signal the sleep duration is insufficient or the actual cause is something else entirely (worth re-investigating rather than just increasing the sleep duration indefinitely).

**Long-term prevention:** document this specific AWS S3-bucket-then-bucket-policy consistency behavior (and the `time_sleep` mitigation) as a known pattern in your organization's Terraform troubleshooting notes, since it's a specific, recurring class of issue that will likely resurface in other configurations creating a bucket and its policy together.

### Step-by-Step Implementation
```hcl
resource "aws_s3_bucket" "app" {
  bucket = "my-app-data-bucket"
}

# Legitimate use of time_sleep: known AWS eventual-consistency gap,
# NOT a substitute for the depends_on ordering guarantee (which is also present)
resource "time_sleep" "wait_for_bucket_consistency" {
  depends_on      = [aws_s3_bucket.app]
  create_duration = "10s"
}

resource "aws_s3_bucket_policy" "app" {
  bucket     = aws_s3_bucket.app.id
  policy     = data.aws_iam_policy_document.app_bucket_policy.json
  depends_on = [time_sleep.wait_for_bucket_consistency]   # ordering AND propagation delay both handled
}
```

### Under-the-Hood Explanation
`depends_on` guarantees Terraform *sequences* the two API calls correctly (bucket creation's RPC completes before the bucket-policy RPC is issued) — but it cannot guarantee that AWS's own backend has fully propagated the bucket's existence across every internal system that a subsequent, related API call might touch, since that's a property of AWS's own infrastructure, entirely outside Terraform's visibility or control. This is the specific, narrow case where `time_sleep` is legitimately the right tool — not because ordering is wrong (it's already correct), but because a fixed, brief delay is genuinely needed to work around a real, if infrequent, propagation gap that no amount of correct Terraform-level sequencing can eliminate.

### Common Weak Answer
"Add more `depends_on` references to fix the ordering."

### Why the Weak Answer Fails
The scenario explicitly states `depends_on` is already correctly present — the failure isn't an ordering problem Terraform's graph can fix with more dependency edges; it's a genuine downstream AWS consistency gap that exists *after* correct ordering is already guaranteed, which is exactly why this is one of the rare, legitimate cases for `time_sleep` rather than a sign that more `depends_on` edges are needed.

### Follow-Up Questions
1. How would you distinguish this genuine eventual-consistency case from a scenario where `time_sleep` is being used to mask an actual missing `depends_on`, as in Question 8?
2. What's the risk of setting the `time_sleep` duration too short versus too long, and how would you tune it appropriately?
3. Are there AWS-provider-level alternatives to a blanket sleep for this specific kind of consistency gap (e.g., built-in retry logic in a newer provider version)?

### Key Interview Signals
Confirms the candidate can distinguish a genuine ordering problem (fixed via `depends_on`, as in Question 8) from a genuine eventual-consistency problem occurring *despite* correct ordering (one of the few legitimate uses of `time_sleep`), rather than treating every intermittent apply issue identically.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).
