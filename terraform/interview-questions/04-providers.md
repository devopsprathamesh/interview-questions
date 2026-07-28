# Category 4: Providers, Resources, and Data Sources

Questions 35–42 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/terraform-architecture.md`](../docs/terraform-architecture.md).

---

## Question 35: The module that could only ever talk to one account

### Scenario
A `dns-record` module hardcodes its own `provider "aws" { region = "us-east-1" }` block internally. It worked fine when only one team used it, but a second team, needing to create records in a different AWS account's Route 53 zone via an assumed role, finds the module simply ignores whatever provider configuration they try to pass in.

### Interview Question
Why does this happen, and how do you fix the module?

### Strong Senior-Level Answer
**Initial assessment:** a module that declares its own `provider` block is not consumer-configurable for that provider — Terraform requires a module's provider requirements to come from its caller (inherited or explicitly passed), and a module with a hardcoded internal provider block cannot receive an externally-supplied one for that same provider.

**Technical reasoning:** Terraform's module provider model is: either a child module implicitly inherits the caller's default (unaliased) provider configuration, or the caller explicitly passes an aliased configuration via the module's `providers = {}` map — a module authoring its own `provider` block internally opts out of both mechanisms for that provider.

**Investigation process:** confirm via `terraform init`/`plan` that Terraform is in fact using the module's hardcoded configuration by checking which account/region the actual API calls are targeting, versus what the second team is attempting to pass in — this confirms the hardcoded block is winning, not a caller-side mistake.

**Recommended solution:** remove the internal `provider` block entirely from the module; declare the module's provider *requirement* (if it needs an aliased configuration explicitly, e.g. requiring the caller to pass a specific alias) via `required_providers` with a `configuration_aliases` entry, and have every caller pass their own provider configuration — the default inherited one for simple cases, or an explicit aliased one for cross-account/region cases.

**Risk controls:** audit other internal modules for the same anti-pattern — a hardcoded provider block is invisible until a second, differently-configured consumer appears, exactly as happened here.

**Validation steps:** confirm both teams' calls to the fixed module now correctly target their respective accounts/regions via `terraform plan` showing the expected account ID / region in resource ARNs or via `aws sts get-caller-identity` under each team's actual assumed credentials.

**Rollback or recovery strategy:** this is a module fix with no infrastructure impact — existing resources aren't affected, only how future consumers configure the module going forward; the first team's existing usage needs a minor update to explicitly pass their (previously implicit, now-required) provider configuration.

**Long-term prevention:** establish as a firm module-authoring rule: reusable modules never declare their own `provider` blocks; they only declare requirements and rely on callers to supply configuration, inherited or explicit.

### Step-by-Step Implementation
```hcl
# modules/dns-record/main.tf — before (broken for multi-account reuse)
provider "aws" {
  region = "us-east-1"
}
resource "aws_route53_record" "this" { /* ... */ }
```
```hcl
# modules/dns-record/main.tf — after
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.dns_account]
    }
  }
}
resource "aws_route53_record" "this" {
  provider = aws.dns_account
  # ...
}
```
```hcl
# Consumer (second team, cross-account)
provider "aws" {
  alias  = "dns_account"
  region = "us-east-1"
  assume_role { role_arn = "arn:aws:iam::222222222222:role/terraform-dns" }
}

module "dns_record" {
  source = "./modules/dns-record"
  providers = {
    aws.dns_account = aws.dns_account
  }
}
```

### Under-the-Hood Explanation
Terraform resolves each resource's provider configuration during graph construction by looking at the module's `providers` map (explicitly passed by the caller) or, absent that, inheriting the caller's default configuration for that provider type — a module with its own internal `provider` block short-circuits this resolution entirely, permanently binding every resource in that module to whatever the hardcoded block specifies, regardless of anything a caller attempts to pass via `providers = {}`.

### Common Weak Answer
"Have the second team fork the module and change the hardcoded region/account."

### Why the Weak Answer Fails
Forking creates an immediate maintenance-divergence problem — two copies of logically the same module now drift independently, defeating the entire purpose of module reuse; the actual fix is making the original module properly provider-agnostic so both teams (and any future team) can configure it correctly without forking.

### Follow-Up Questions
1. How would you handle a module that legitimately needs to operate against *two* provider configurations simultaneously (e.g., replicating a record to two accounts)?
2. What's the difference between `configuration_aliases` and simply relying on default provider inheritance — when do you need the former?
3. How would you catch this anti-pattern (a reusable module declaring its own provider block) automatically in CI before it's merged?

### Key Interview Signals
Confirms the candidate understands Terraform's module provider inheritance/passing model precisely enough to diagnose and fix this without guessing, and defaults to fixing the shared module rather than forking.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/) and [Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/).

---

## Question 36: One module, two regions, at the same time

### Scenario
Your `rds` module needs to provision a primary database in `us-east-1` and, in the same apply, a cross-region read replica in `us-west-2`, for disaster-recovery purposes.

### Interview Question
How do you architect the provider configuration for this?

### Strong Senior-Level Answer
**Initial assessment:** this requires the module to accept two distinct AWS provider configurations (one per region) explicitly, since no single provider configuration can target two regions simultaneously — every AWS resource is created via one specific regional provider.

**Technical reasoning:** the module declares two `configuration_aliases` (or the caller passes both explicitly-aliased providers in), and internally routes the primary instance's resource to one aliased provider and the replica's resource to the other.

**Investigation process:** confirm which specific resource(s) within the module need which region — typically the primary `aws_db_instance` in the primary-region provider, and the `aws_db_instance` with `replicate_source_db` set, using the secondary-region provider.

**Recommended solution:** define both provider aliases at the root, pass both into the module via `providers = {}`, and reference each aliased provider explicitly on its corresponding resource inside the module.

**Risk controls:** validate that the module's `required_providers.configuration_aliases` list matches exactly what callers are expected to pass — a mismatch here surfaces as a clear `init`-time error, not a silent misconfiguration, provided the module correctly declares its requirements.

**Validation steps:** `terraform plan` should show the primary instance's ARN referencing `us-east-1` and the replica's referencing `us-west-2`; confirm via `aws rds describe-db-instances --region us-west-2` post-apply that the replica genuinely landed in the correct region.

**Rollback or recovery strategy:** if the wrong provider alias is wired to the wrong resource internally, the fix is a module code correction — no state corruption risk, since this is caught at plan/apply time via the region mismatch being immediately visible.

**Long-term prevention:** document the module's two-provider requirement clearly in its README/generated docs (see [Question 31](03-modules.md#question-31-the-readme-that-lied)), since a consumer forgetting to pass the second aliased provider will hit an `init`-time error but benefits from a clear explanation of why two providers are needed.

### Step-by-Step Implementation
```hcl
# modules/rds-with-dr/main.tf
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases  = [aws.primary, aws.dr]
    }
  }
}

resource "aws_db_instance" "primary" {
  provider = aws.primary
  # ...
}

resource "aws_db_instance" "replica" {
  provider            = aws.dr
  replicate_source_db = aws_db_instance.primary.arn
  # ...
}
```
```hcl
# Root module
provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}
provider "aws" {
  alias  = "dr"
  region = "us-west-2"
}

module "rds" {
  source = "./modules/rds-with-dr"
  providers = {
    aws.primary = aws.primary
    aws.dr      = aws.dr
  }
}
```

### Under-the-Hood Explanation
Each `provider` argument on a resource resolves to a fully independent provider plugin instance (a separate configured connection, potentially with a different region and even different assumed-role credentials) — Terraform Core dispatches RPC calls for `aws_db_instance.primary` to the `aws.primary`-configured plugin instance and calls for `aws_db_instance.replica` to the `aws.dr`-configured instance entirely independently; there is no cross-provider coordination beyond the resource graph's own dependency edge (`replicate_source_db` referencing the primary's ARN) sequencing their creation correctly.

### Common Weak Answer
"Just set the region as a variable and let the module figure out which resource goes where."

### Why the Weak Answer Fails
A single region variable can't route two different resources to two different regions simultaneously in the same apply — actual multi-region resource creation requires two distinct provider configurations, not a single parameterized one; this answer misses the core provider-aliasing mechanism entirely.

### Follow-Up Questions
1. How would this design extend to three or more regions (e.g., a globally-replicated read scaling pattern)?
2. What happens to this module's state if the DR region's replica needs to be promoted to a standalone primary during an actual failover?
3. How do you handle credentials/assume-role differences if the DR region lives in a genuinely separate AWS account, not just a different region in the same account?

### Key Interview Signals
Confirms the candidate can design and wire multi-provider modules correctly using `configuration_aliases`, not just describe provider aliasing abstractly.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 37: The assume-role trust policy that trusted too much

### Scenario
A security review discovers the CI execution role's trust policy in the production AWS account only checks that the OIDC token comes from `token.actions.githubusercontent.com`, with no condition on repository, branch, or environment. Any GitHub Actions workflow in the entire GitHub organization — not just the platform team's specific repository — can currently assume this production-scoped role.

### Interview Question
How would you fix this, and how would you verify the fix without breaking legitimate CI usage?

### Strong Senior-Level Answer
**Initial assessment:** a critical, if common, OIDC trust-policy misconfiguration — checking the identity provider alone (not the token's subject claim) means the trust boundary is effectively "anyone in the GitHub org," not "this specific repository's production deployment workflow," which is a significant privilege-escalation exposure.

**Technical reasoning:** the OIDC token issued by GitHub's provider contains a `sub` claim encoding the repository, and optionally the branch/environment/workflow, in a specific format (`repo:ORG/REPO:environment:NAME` or `repo:ORG/REPO:ref:refs/heads/BRANCH`); the trust policy must condition on this exact claim value, not just verify the token issuer.

**Investigation process:** confirm exactly which repository/environment combination should legitimately be allowed to assume this role (the platform team's specific infrastructure repository, specifically its `production` GitHub Environment, which itself enforces manual approval — see [`cicd.md` §7](../docs/cicd.md#7-oidc-based-cloud-authentication-in-pipelines)), and audit CloudTrail for any historical `AssumeRoleWithWebIdentity` calls against this role from unexpected repositories, to determine if this gap was ever actually exploited (even unintentionally, by an unrelated repo's workflow).

**Recommended solution:** add a `StringEquals` condition on `token.actions.githubusercontent.com:sub` scoped to the exact expected value, and ideally also condition on `token.actions.githubusercontent.com:aud` (audience) matching your AWS account, as defense-in-depth against token replay across accounts.

**Risk controls:** test the corrected trust policy against the legitimate pipeline in a non-production account/role copy first, confirming the exact `sub` claim format your CI produces before rolling the tightened policy into production — a too-strict condition (wrong exact string) would lock out legitimate CI entirely, so verify precisely.

**Validation steps:** after tightening, attempt (in a controlled, authorized test) an assume-role call from a deliberately different repository/workflow and confirm it's now denied, while the legitimate pipeline continues to work.

**Rollback or recovery strategy:** keep the previous trust policy version documented/backed up before changing it, so a rollback is immediate if the tightened condition unexpectedly blocks legitimate CI due to a claim-format mismatch you didn't anticipate.

**Long-term prevention:** add a policy-as-code or periodic IAM-audit check specifically scanning for OIDC trust policies lacking a `sub`/`aud` condition, across every role in every account, since this is exactly the kind of misconfiguration that's easy to introduce once and then forget to replicate correctly for every subsequent role.

### Step-by-Step Implementation
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::333333333333:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:sub": "repo:my-org/platform-infra:environment:production",
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```
```bash
# Audit for prior unexpected assumption before/after the fix
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time 2026-01-01 | jq '.Events[] | select(.CloudTrailEvent | fromjson | .userIdentity.principalId | contains("prod-terraform-role"))'
```

### Under-the-Hood Explanation
AWS STS validates the presented OIDC token's signature against the registered identity provider and then evaluates the role's trust policy `Condition` block against the token's claims (`sub`, `aud`, and others) exactly like any other IAM policy condition evaluation — if no condition references `sub`, any validly-signed token from that issuer (i.e., from *any* workflow anywhere in the GitHub organization, since GitHub is the token issuer for the whole org) satisfies the trust policy, regardless of which specific repository or workflow actually generated it.

### Common Weak Answer
"Rotate the role's ARN so the old, overly-trusting configuration can't be used anymore."

### Why the Weak Answer Fails
Rotating the ARN doesn't fix anything if the new role's trust policy has the same gap — it just moves the problem to a new identifier; the actual fix is correcting the trust policy's `Condition` block, which can be done in place without any ARN change at all.

### Follow-Up Questions
1. How would you extend this scoping for a monorepo with multiple environments/workflows, each needing to assume different roles?
2. What's the risk of scoping the condition to `ref:refs/heads/main` instead of a GitHub Environment claim, and why might one be preferable to the other?
3. How would you detect this class of misconfiguration proactively across dozens of roles, rather than relying on a manual security review to find it?

### Key Interview Signals
Confirms the candidate understands OIDC trust conditions at the claim level (not just "OIDC is more secure than static keys" abstractly) and can write and validate a correctly-scoped trust policy.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 38: The upgrade that arrived at the worst possible time

### Scenario
Two days before a scheduled release freeze, a routine `terraform init -upgrade` (run as part of standard monthly maintenance) picks up a new patch version of the AWS provider. The resulting plan against a staging environment shows several `aws_lb_target_group` resources being replaced, with no corresponding configuration change.

### Interview Question
How do you handle this given the timing, and what's your actual technical investigation?

### Strong Senior-Level Answer
**Initial assessment:** timing pressure doesn't change the correct process — an unexpected replacement from a provider bump must be understood before it's allowed anywhere near production, freeze or no freeze; the freeze is actually a good reason to *not* rush this into production, not a reason to skip investigation.

**Technical reasoning:** the most likely cause is a schema or `ForceNew` change in the new provider patch version for `aws_lb_target_group` specifically — patch versions are supposed to be backward-compatible, but provider patch releases have, in practice, occasionally included corrections to attribute behavior that has this kind of side effect.

**Investigation process:** read the `terraform plan` output's `# forces replacement` annotation to identify exactly which attribute triggered it; cross-reference the AWS provider's CHANGELOG for the specific version jump for any mention of `aws_lb_target_group` changes; if unclear from the CHANGELOG, check the provider's GitHub issues/PRs around that version for related reports.

**Recommended solution:** given the freeze, pin the provider version back to the last known-good version in `required_providers`/lock file immediately (`terraform init -upgrade=false` after correcting the constraint, or explicitly re-locking to the prior version) — do not let an unplanned provider bump ride into a frozen release window. File/track the finding for proper investigation and testing after the freeze, in a non-production environment, before deliberately adopting the new version.

**Risk controls:** treat this as a reminder that provider upgrades should never happen via routine, unreviewed `init -upgrade` maintenance close to a freeze — provider version bumps should be their own reviewed, scheduled activity with plan-diff review, ideally scheduled well outside freeze windows.

**Validation steps:** after pinning back, confirm `terraform plan` against staging returns to showing no unexpected changes, confirming the provider version was indeed the cause and not some unrelated concurrent configuration drift.

**Rollback or recovery strategy:** the "rollback" here is simply the version pin-back — since this was caught in staging before any production apply, there's no cloud-side rollback needed.

**Long-term prevention:** move provider upgrades to their own deliberate, scheduled process (not bundled into generic "monthly maintenance") with mandatory non-prod plan review before ever reaching a production-track branch, and explicitly exclude provider version changes from any change window close to a release freeze.

### Step-by-Step Implementation
```bash
# Diagnose
terraform plan
# aws_lb_target_group.app must be replaced
# -/+ resource "aws_lb_target_group" "app" {
#     ~ target_type = "instance" -> "ip" # forces replacement (was previously defaulted differently)

# Pin back immediately given the freeze
```
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.42.0"   # explicit pin back to last known-good, not a floating ~> range for now
    }
  }
}
```
```bash
terraform init -upgrade
terraform plan   # confirm no unexpected changes with the pinned-back version
```

### Under-the-Hood Explanation
Every provider version's schema is fetched fresh via the `GetProviderSchema` RPC at `init` time (see [`terraform-internals.md` §9](../docs/terraform-internals.md#9-provider-rpc-communication)) — a provider version bump can change which attributes are marked `ForceNew`, change a default value's computed representation, or change how an existing value is normalized, any of which can produce a diff (including a replacement) with zero change to your own `.tf` files, since the diff is computed against the *new* schema's interpretation of your unchanged configuration.

### Common Weak Answer
"We're close to the freeze, let's just apply it to staging and see what happens — if it looks okay we'll let it ride."

### Why the Weak Answer Fails
"See what happens" on a replacement operation for a load-balancer target group risks an availability gap in staging with no root-cause understanding, and "let it ride" into a freeze window is precisely the undisciplined provider-upgrade handling that causes production incidents — proximity to a freeze is a reason for *more* caution, not less.

### Follow-Up Questions
1. How would you distinguish a genuine provider bug from an intentional (if surprising) behavior correction that's actually fixing a previously-incorrect default?
2. What would your provider-upgrade cadence/policy look like to prevent this timing collision from recurring?
3. If the replacement turned out to be unavoidable (a genuine, intentional provider change with no workaround), how would you plan the eventual production rollout to minimize risk?

### Key Interview Signals
Confirms the candidate doesn't let deadline pressure short-circuit the investigation-before-action discipline, and treats provider upgrades as their own reviewed change category, not routine background maintenance.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 39: The tag that wouldn't stay put

### Scenario
`default_tags` on the AWS provider sets `Environment = "production"` organization-wide. One specific `aws_instance` resource also sets its own `tags = { Environment = "staging-mirror" }` for a legitimate reason (it's a production-hosted staging mirror). Every plan now shows a perpetual, unresolvable-looking diff on this one resource's tags.

### Interview Question
Explain what's happening and how you'd resolve it cleanly.

### Strong Senior-Level Answer
**Initial assessment:** `default_tags` and resource-level `tags` merge, with resource-level values taking precedence for any overlapping key — the "perpetual diff" is very likely a normalization or provider-version-specific merge-behavior detail rather than a genuine conflict, so the first step is confirming exactly what the diff shows on each plan, not assuming it's unresolvable.

**Technical reasoning:** in correctly-behaving provider versions, an explicit resource-level tag should cleanly override the same key from `default_tags` with no repeated diff — a perpetual diff suggests either a provider version with a known default_tags interaction bug, or a subtler issue like `ignore_changes` on `tags` interacting unexpectedly with the merged result.

**Investigation process:** run `terraform plan` twice in a row with no changes in between — if the diff is genuinely identical and repeats every time, check the specific AWS provider version against its GitHub issues for known `default_tags` merge-behavior bugs (this has had real historical issues in some versions); also check whether the resource has `ignore_changes = ["tags"]` or `ignore_changes = ["tags_all"]` set, and whether that's interacting with the computed `tags_all` attribute (which represents the fully-merged tag set) in a way that's fighting the explicit override.

**Recommended solution:** if it's a known provider bug for a specific version, upgrade/pin to a version where it's fixed. If it's an `ignore_changes` interaction, correct the `ignore_changes` target — often the issue is ignoring `tags` while the actual computed diff shows on `tags_all`, or vice versa; align which attribute is actually being ignored with which one the provider computes as authoritative for diffing.

**Risk controls:** for resources that legitimately need to violate an org-wide default (like this staging-mirror case), verify the override is real and not itself masking a mistake made once and now permanently perpetuated — confirm with whoever owns this resource that it's still intentional.

**Validation steps:** after the fix, run `terraform plan` three or four times consecutively with zero manual changes and confirm the diff is gone for good, not just suppressed for one run.

**Rollback or recovery strategy:** not applicable — a diagnostic/config fix with no infrastructure impact of its own; the resource's actual tag value is unaffected regardless of the diff-noise issue.

**Long-term prevention:** whenever `default_tags` is adopted at the provider level, add a `terraform test` case explicitly verifying that a resource-level tag override produces a stable, zero-perpetual-diff plan — this is a subtle enough interaction that it deserves explicit test coverage rather than relying on incidental discovery.

### Step-by-Step Implementation
```hcl
provider "aws" {
  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

resource "aws_instance" "staging_mirror" {
  # ...
  tags = {
    Environment = "staging-mirror"   # explicit override of the provider default for this one key
  }
  # If a perpetual diff appears, check this is not simultaneously ignored:
  # lifecycle { ignore_changes = [tags_all] }  <- verify this isn't fighting the override
}
```
```bash
terraform plan   # run 2-3 times consecutively with no changes to confirm the diff is truly resolved
```

### Under-the-Hood Explanation
The AWS provider computes a `tags_all` attribute representing the fully merged result of `default_tags` plus resource-level `tags` (resource-level winning on key collisions) — the diff engine compares against this computed, merged value, not against `tags`/`default_tags` independently; a perpetual diff typically indicates the provider's merge computation and Terraform's cached/refreshed understanding of `tags_all` are disagreeing on each plan, which is either a genuine provider defect in a specific version or a misapplied `ignore_changes` targeting the wrong one of the two attributes.

### Common Weak Answer
"Just remove `default_tags` from the provider and set every tag explicitly on every resource instead."

### Why the Weak Answer Fails
This abandons the entire organizational benefit of `default_tags` (consistent tagging without repeating it everywhere) to work around what is very likely a narrow, specific, diagnosable bug or misconfiguration affecting one resource — a much larger change than the actual problem warrants.

### Follow-Up Questions
1. How would you design a `terraform test` case to catch this exact class of `default_tags`/resource-tag interaction bug before it reaches any real environment?
2. What's the difference in behavior between overriding a `default_tags` key at the resource level versus trying to *remove* a default-applied tag entirely for one resource — is the latter even possible?
3. How would you audit your entire estate for other resources that might be silently experiencing the same perpetual-diff issue without anyone noticing?

### Key Interview Signals
Tests whether the candidate diagnoses a genuinely subtle provider-mechanics interaction methodically (multiple plan runs, checking `tags_all`, checking provider version) rather than jumping to a disproportionate structural change.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 40: The access key in the provider block

### Scenario
A code review catches a `provider "aws" { access_key = "AKIA..." secret_key = "..." }` block committed to a feature branch (not yet merged) by a new team member unfamiliar with the org's OIDC-only policy.

### Interview Question
What's your immediate response, and how do you migrate this person's workflow to the correct pattern?

### Strong Senior-Level Answer
**Initial assessment:** treat the committed credential as compromised the moment it's pushed to any remote branch, even unmerged and even if the repository is private — git history retains it, and depending on hosting/CI configuration, it may already have been scanned/cached/indexed by tooling before anyone caught it in review.

**Technical reasoning:** the fix has two parts: immediate credential rotation (a security response) and correcting the underlying workflow so the next new team member doesn't repeat this (a process/tooling response) — fixing only the visible symptom (removing the block from the branch) without rotating the key leaves the exposed credential live.

**Investigation process:** identify exactly which IAM user/access key this belongs to, confirm via CloudTrail whether it's been used from anywhere unexpected since the commit, and confirm whether this access key should exist at all — in an OIDC-only organization, a long-lived IAM user access key being available for a new hire to even use in the first place is itself a gap worth investigating (why did they have one to put in a provider block?).

**Recommended solution:** deactivate and delete the exposed IAM access key immediately, regardless of whether it appears to have been misused. Rewrite the feature branch's git history to remove the credential (`git filter-repo` or equivalent) if it hasn't been merged/widely fetched yet, understanding this doesn't guarantee complete eradication from every clone/cache — rotation is the actual control, history-scrubbing is a secondary cleanup. Set the new team member up with the organization's actual pattern (local SSO-based profile for interactive work, OIDC for CI) and, ideally, ensure no standing IAM user access keys exist for them to have used in the first place.

**Risk controls:** add automated secret-scanning (gitleaks/truffleHog or your CI platform's native secret-detection) as a required PR check, so this class of mistake is caught automatically before human review even happens, not dependent on a reviewer noticing.

**Validation steps:** confirm the deactivated key can no longer authenticate (`aws sts get-caller-identity` with the old key fails), and confirm the new team member can successfully run Terraform via the correct SSO/assume-role pattern.

**Rollback or recovery strategy:** not applicable in the traditional infrastructure sense — the "recovery" is the rotation and workflow correction described above.

**Long-term prevention:** eliminate standing IAM user access keys for human engineers entirely where feasible (SSO/assumed-role sessions only), and make secret-scanning a mandatory, automatic PR gate rather than relying on manual review to catch this pattern.

### Step-by-Step Implementation
```bash
# 1. Immediately deactivate and delete the exposed key
aws iam update-access-key --access-key-id AKIA... --status Inactive --user-name newhire
aws iam delete-access-key --access-key-id AKIA... --user-name newhire

# 2. Confirm no suspicious usage since exposure
aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=AKIA...

# 3. Clean git history on the unmerged branch (best-effort, not the primary control)
git filter-repo --path provider.tf --invert-paths --force   # or targeted redaction

# 4. Add secret scanning as a required CI check going forward
```
```yaml
# .github/workflows/secret-scan.yml
- uses: gitleaks/gitleaks-action@v2
```

### Under-the-Hood Explanation
Hard-coded `access_key`/`secret_key` arguments on a `provider` block are read directly by the AWS provider plugin at `init`/plan/apply time and used for every subsequent API call for that provider configuration — nothing about this differs mechanically from any other AWS SDK credential usage; the risk is purely that the credential now exists in plaintext in a location (version control) designed for permanent, widely-replicated history, unlike an environment variable or SSO session token that exists only transiently on one machine.

### Common Weak Answer
"Just remove the provider block from the branch before merging and we're fine."

### Why the Weak Answer Fails
Removing it from the branch's current state doesn't remove it from git history or undo any exposure that already occurred the moment it was pushed — the credential must be rotated regardless of whether the branch is cleaned up or merged.

### Follow-Up Questions
1. How would you design onboarding so new team members never have a standing IAM access key to accidentally use in the first place?
2. What's your process if this had been pushed to a public (not private) repository instead?
3. How would you verify secret-scanning would actually have caught this specific pattern before relying on it as your primary control going forward?

### Key Interview Signals
Confirms the candidate treats any committed credential as compromised regardless of merge status or repo visibility, and prioritizes rotation over history cleanup as the actual control.

### Hands-On Connection
[Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 41: Terraform behind the wire

### Scenario
Your organization is deploying Terraform-managed infrastructure into an air-gapped government/regulated environment with no outbound internet access at all. `terraform init` needs to resolve both providers and modules without ever reaching registry.terraform.io.

### Interview Question
Design the provider and module distribution architecture for this environment.

### Strong Senior-Level Answer
**Initial assessment:** both provider and module resolution need an internal substitute for the public registry — a network or filesystem mirror for providers, and an internal Git server or artifact repository for modules — with no code changes needed to the Terraform configurations themselves beyond CLI-level configuration.

**Technical reasoning:** Terraform's provider installation method is configurable via CLI config (`provider_installation` block) independent of any `.tf` file content, supporting `network_mirror` (an internal HTTPS endpoint implementing the provider mirror protocol) or `filesystem_mirror` (a local/shared-filesystem directory of pre-downloaded provider packages) — either lets `init` resolve providers entirely without reaching the public internet.

**Investigation process:** determine which providers/versions are actually needed across the organization's configurations, and whether an existing internal artifact tool (Artifactory, Nexus) already supports acting as a Terraform provider mirror, versus needing a dedicated internal mirror service stood up specifically for this.

**Recommended solution:** stand up an internal network mirror populated by a controlled, periodic sync process (pulling approved provider versions from the public registry in a separate, internet-connected environment, then transferring the vetted artifacts across the air gap through your organization's approved one-way transfer process) and configure every Terraform CLI installation in the air-gapped environment to use it via `provider_installation`. For modules, host an internal Git server (already common in regulated environments) and reference modules via internal Git URLs with `?ref=` tags, or an internal registry if available.

**Risk controls:** the cross-air-gap transfer process for new/updated provider versions is itself a security control point — treat it with the same checksum-verification rigor as the public registry's own trust model (verify published checksums match what's transferred, don't just copy files across trustingly).

**Validation steps:** confirm `terraform init` succeeds with zero outbound network calls in the air-gapped environment (verifiable via network monitoring/firewall logs showing no attempted egress), and confirm the resulting `.terraform.lock.hcl` checksums match what the mirror actually serves.

**Rollback or recovery strategy:** if a mirror sync introduces a bad/incompatible provider version, the fix is re-syncing the previous known-good version and correcting `required_providers` constraints — no different in principle from any other provider version issue, just constrained by the air-gap's slower update cycle.

**Long-term prevention:** document and automate the mirror-sync process (rather than ad hoc manual transfers) so keeping the air-gapped environment's provider/module set current doesn't become an entirely manual, error-prone, infrequent chore.

### Step-by-Step Implementation
```hcl
# CLI config (~/.terraformrc or equivalent), inside the air-gapped environment
provider_installation {
  network_mirror {
    url = "https://internal-mirror.corp.example/providers/"
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```
```hcl
# Module sourcing via internal Git server, no public registry dependency
module "vpc" {
  source = "git::https://git.internal.corp.example/platform/tf-modules.git//vpc?ref=v4.2.0"
}
```
```bash
# Verify no outbound internet calls during init (in the air-gapped environment)
terraform init   # should succeed purely against internal-mirror.corp.example
```

### Under-the-Hood Explanation
`terraform init` normally resolves providers by querying `registry.terraform.io`'s discovery API for download URLs and checksums, then downloading and verifying the binary against the checksums recorded in (or newly written to) `.terraform.lock.hcl`. A configured `network_mirror` simply redirects this discovery/download step to an internal HTTPS endpoint implementing the same mirror protocol — the checksum-verification step against the lock file behaves identically regardless of source, which is why lock-file integrity remains a meaningful trust boundary even when the binaries themselves come from an internal, not public, source.

### Common Weak Answer
"Just download the provider binaries manually and put them in the plugins directory."

### Why the Weak Answer Fails
This describes a legacy, ad hoc, per-machine workaround that doesn't scale, isn't centrally auditable, and bypasses the lock-file checksum verification model that gives the mirror-based approach its integrity guarantees — a proper network/filesystem mirror is the supported, auditable, team-wide solution.

### Follow-Up Questions
1. How would you keep the internal mirror's provider version set current without constant manual intervention, given the air gap?
2. What's your process for vetting a brand-new provider or module before it's allowed into the internal mirror/Git server at all?
3. How does this architecture change if different teams within the air-gapped environment need genuinely different, possibly conflicting, sets of approved provider versions?

### Key Interview Signals
Confirms the candidate knows the specific CLI-level mechanisms (`provider_installation`, network/filesystem mirrors) rather than proposing ad hoc manual workarounds, and thinks about the sync/vetting process as an ongoing operational concern, not a one-time setup.

### Hands-On Connection
[Lab 2 — Secure Remote State](../labs/lab-02-remote-state/) (backend/provider configuration patterns extend directly to mirror configuration).

---

## Question 42: The lock file three people disagreed about

### Scenario
Three engineers, working on different feature branches, each ran `terraform init -upgrade` independently over the course of a week (against team convention, but it happened), producing three different, mutually incompatible versions of `.terraform.lock.hcl`. Merging their branches produces repeated, confusing lock-file merge conflicts, and one engineer, frustrated, considers just deleting the lock file and regenerating it fresh to "make the conflicts go away."

### Interview Question
Is deleting and regenerating the lock file a reasonable fix here? What's the actual right process?

### Strong Senior-Level Answer
**Initial assessment:** deleting and blindly regenerating the lock file "to make conflicts go away" would silently pick up whatever provider versions happen to be resolvable *at that moment*, potentially different from what any of the three engineers were actually testing against — trading a visible, if annoying, merge conflict for an invisible, unreviewed version change.

**Technical reasoning:** the actual issue is that three people independently ran `-upgrade`, which the team's convention (correctly) discourages as an ad hoc, individual action — provider version bumps should be one deliberate, reviewed change, not something that happens incidentally three times in a week across unrelated feature work.

**Investigation process:** determine what provider version each of the three branches actually needs (do any of them require a genuinely newer provider feature/fix, or did they all run `-upgrade` incidentally without actually needing a new version)?

**Recommended solution:** pick one deliberate target provider version (the latest one that's actually been reviewed/tested, or the one a specific branch genuinely requires), have all three engineers re-run `init -upgrade` (or manually align `required_providers` constraints) against that single agreed version, resolving the merge conflict by convergence rather than by regenerating blind. If none of the three actually needed a version bump, the simplest fix is having all three revert their lock file changes back to the pre-upgrade committed version and rebase.

**Risk controls:** reinforce the team convention that `-upgrade` is a deliberate, reviewed, team-wide action (see [`terraform-architecture.md` §3](../docs/terraform-architecture.md#3-provider-version-constraints-and-the-dependency-lock-file)) — not something any individual branch does incidentally — ideally enforced by having the lock file only get touched intentionally as its own PR.

**Validation steps:** after converging on one version, `terraform plan` on each of the three branches (rebased against the agreed lock file) should show no unexpected diffs attributable to the provider version itself.

**Rollback or recovery strategy:** if the agreed-upon version turns out to have an issue for one of the three branches specifically, that's a signal to investigate that specific interaction (see [Question 38](#question-38-the-upgrade-that-arrived-at-the-worst-possible-time)) rather than reflexively reverting for everyone.

**Long-term prevention:** make lock-file changes their own dedicated PR type (never bundled incidentally with unrelated feature work), reviewed specifically for the resulting plan diff across the team's key environments before merging — this removes the "three people did it independently without coordinating" failure mode entirely.

### Step-by-Step Implementation
```bash
# Wrong instinct: regenerate blind
rm .terraform.lock.hcl && terraform init   # picks up whatever is currently resolvable - unreviewed

# Correct: converge deliberately
terraform init -upgrade   # once, deliberately, by whoever owns this decision
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64   # record for all needed platforms
git add .terraform.lock.hcl
git commit -m "Deliberate provider version bump to aws ~> 5.45, reviewed plan diff attached"
# Every other branch rebases onto this single commit rather than each regenerating independently
```

### Under-the-Hood Explanation
`.terraform.lock.hcl` records exact resolved versions and per-platform checksums for every provider a configuration uses — since it's a plain text file under version control, Git merges/conflicts on it exactly like any other text file, with no special Terraform-aware merge logic; three independent, uncoordinated `-upgrade` runs producing three different resolved-version sets is precisely the kind of divergence that shows up as a textual merge conflict, because the underlying *intent* (what version should this team actually be on) was never coordinated in the first place.

### Common Weak Answer
"Delete the lock file, it'll just regenerate and the conflicts will go away."

### Why the Weak Answer Fails
This is exactly the instinct the scenario warns against — it resolves the surface-level merge-conflict annoyance by discarding the actual information (which versions were tested/intended) and replacing it with whatever happens to resolve at regeneration time, which could reintroduce the very provider-upgrade risks (see [Question 38](#question-38-the-upgrade-that-arrived-at-the-worst-possible-time)) that pinning and deliberate review are meant to prevent.

### Follow-Up Questions
1. How would you structure CI to prevent an individual feature branch from silently modifying the lock file at all, requiring it to be its own reviewed change?
2. What's the difference in risk between three engineers all landing on the *same* new version via independent `-upgrade` runs versus three different versions, as in this scenario?
3. How would `terraform providers lock -platform=...` help avoid a related but different problem — team members on different OSes producing different checksums?

### Key Interview Signals
Confirms the candidate treats the lock file as meaningful, reviewed information (not disposable boilerplate to regenerate when inconvenient) and identifies the real process gap (uncoordinated individual upgrades) rather than just resolving the immediate merge-conflict symptom.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).
