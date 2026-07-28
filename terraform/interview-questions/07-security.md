# Category 7: Security and Secrets Management

Questions 61–68 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/security.md`](../docs/security.md).

---

## Question 61: The finding that got a skip comment instead of a fix

### Scenario
A Checkov scan in CI flags a new RDS instance for missing `deletion_protection`. Rather than fixing it, the engineer adds a `#checkov:skip=CKV_AWS_293:not needed for this dev database` comment directly in the PR, which merges without further review of that specific line, since the overall CI check now passes.

### Interview Question
Is this an acceptable use of a scanner suppression, and how would you govern this pattern going forward?

### Strong Senior-Level Answer
**Initial assessment:** inline suppressions are a legitimate, necessary escape hatch — not every finding applies to every resource, and a dev database genuinely might not need `deletion_protection` — but an *unreviewed* suppression defeats the entire purpose of the scanning gate, since it lets anyone silence any finding unilaterally with a one-line comment.

**Technical reasoning:** the scanning gate's value depends on suppressions themselves being subject to the same review rigor as the code they're suppressing checks on — otherwise the gate degrades over time into "whatever findings people didn't bother to suppress," which is a much weaker guarantee than it appears to provide.

**Investigation process:** audit how many `#checkov:skip` (or equivalent tfsec/Trivy ignore) comments currently exist across the codebase, when they were added, whether they still apply to their original justification, and whether any reviewer actually engaged with the suppression versus just seeing "CI passing" and approving.

**Recommended solution:** require every inline suppression to include a mandatory, structured justification (ticket reference, expiration/review date) and add a CI check that specifically flags any suppression *comment* for the reviewer's attention in the PR diff (most scanners' suppression syntax is visible in a normal diff, but a policy-as-code or lightweight script can specifically call out "this PR adds a new scanner suppression" as a distinct, highlighted review item, not just a passing check). For anything security-critical (deletion protection, encryption, public exposure), consider requiring a second, security-team-specific approval specifically for PRs introducing a new suppression of that class of finding.

**Risk controls:** periodically audit all existing suppressions (a scheduled job, not a one-time cleanup) to catch ones whose original justification has expired or no longer applies — a dev database's `deletion_protection` suppression, for instance, becomes a problem if that database is later promoted to handle production traffic without anyone revisiting the suppression.

**Validation steps:** confirm the CI enhancement actually surfaces new suppressions distinctly (test by adding one in a sample PR and confirming it's flagged, not just passed silently).

**Rollback or recovery strategy:** not applicable — this is a process/tooling fix; for the specific RDS instance in this scenario, confirm the suppression's justification is still accurate today, and add `deletion_protection` if it turns out this database has since become more critical than originally assumed.

**Long-term prevention:** track suppression debt as its own visible metric (count of active suppressions, oldest unreviewed one) reported to the platform/security team periodically, so suppressions don't become a permanent, invisible accumulation of unreviewed risk exceptions.

### Step-by-Step Implementation
```hcl
# Required suppression format: ticket reference + review date, enforced by convention/linter
#checkov:skip=CKV_AWS_293: Dev-only database, no deletion protection needed. Ticket: INFRA-4821. Review-by: 2026-10-01
resource "aws_db_instance" "dev_db" {
  # ...
}
```
```bash
# CI step: flag any new suppression in this PR's diff for explicit reviewer attention
git diff origin/main...HEAD | grep -E '^\+.*#checkov:skip|^\+.*#tfsec:ignore' && \
  echo "::warning::This PR introduces a new scanner suppression - requires explicit review"
```
```bash
# Scheduled audit: find suppressions past their review date
grep -rn 'Review-by:' --include='*.tf' . | awk -F'Review-by: ' '{print $2, $0}' | sort
```

### Under-the-Hood Explanation
Scanner suppressions (Checkov `#checkov:skip`, tfsec `#tfsec:ignore`, Trivy equivalents) work by the scanner's parser recognizing the specially-formatted comment adjacent to a resource block and excluding that specific check ID for that specific resource from the pass/fail result — this is a scanner-level mechanism entirely independent of Terraform itself, meaning the suppression has zero visibility to anyone not specifically looking for that comment syntax in the diff, which is exactly why a distinct, structured review process must be layered on top rather than relying on the scanner's own pass/fail output alone.

### Common Weak Answer
"Suppressions are fine as long as the CI check still passes overall."

### Why the Weak Answer Fails
"CI passes" is exactly the state that both a legitimately-justified suppression and an unreviewed, unjustified one produce identically — the pass/fail signal alone cannot distinguish a governed exception from an ungoverned one, which is precisely the gap this question is testing for.

### Follow-Up Questions
1. How would you handle a legacy codebase with hundreds of pre-existing, undocumented suppressions accumulated before this governance process existed?
2. Should some categories of finding (e.g., public exposure) never be suppressible at all, regardless of justification?
3. How does this suppression-governance problem differ for policy-as-code (Conftest/OPA) exceptions versus static-scanner suppressions?

### Key Interview Signals
Confirms the candidate treats suppressions as a governed exception process requiring their own review discipline, not an acceptable-by-default escape hatch as long as the overall CI check is green.

### Hands-On Connection
[Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 62: The module that wasn't what it claimed to be

### Scenario
A security researcher publicly discloses that a popular community Terraform module (used by your organization for S3 bucket provisioning) contained, for several versions, a subtly backdoored default bucket policy that granted read access to an unexpected external AWS account, introduced by a compromised maintainer account.

### Interview Question
Walk through your incident response, and how you'd prevent this class of supply-chain risk in the future.

### Strong Senior-Level Answer
**Initial assessment:** treat this exactly like any other supply-chain compromise — a dependency you trusted turned out to be malicious for some period of time, and the response needs both immediate containment (identify and fix affected infrastructure) and forward-looking prevention (reduce reliance on unvetted third-party modules for security-relevant resources).

**Technical reasoning:** the first priority is determining actual impact — which of your S3 buckets were provisioned or last applied using an affected module version, and whether the backdoored policy actually reached real, applied infrastructure (not just sat in an unreleased/unapplied configuration).

**Investigation process:** identify every consumer of this module across your organization (search for the module source string across all repositories) and cross-reference each against which specific version was in use at the time of any apply during the compromised window (the lock file/version pin history, if properly committed, gives you this precisely). For each affected bucket, check its actual current bucket policy against what the backdoored default would have set, and check CloudTrail for any access from the unexpected external account during the exposure window.

**Recommended solution:** immediately correct the bucket policy on every affected bucket (via a corrected module version or a direct override), rotate/audit anything potentially exposed to the external account during the window, and pin every consumer to a confirmed-clean module version (or, more conservatively, fork the module internally and audit the forked copy fully before trusting it again).

**Risk controls:** treat this as the trigger to establish (if not already in place) an internal vetting/allowlist process for any third-party community module used for security-relevant resources — require a security review before adoption, and pin to specific, audited commit hashes/versions rather than floating tags for anything from an unverified source.

**Validation steps:** confirm via CloudTrail and bucket policy inspection that every affected bucket is now corrected and that no residual access from the external account remains.

**Rollback or recovery strategy:** if data may have actually been accessed by the unauthorized external account during the exposure window, treat this as a genuine data-exposure incident requiring your organization's standard breach-assessment/notification process, not just an infrastructure fix — the infrastructure correction alone doesn't address potential data already exfiltrated.

**Long-term prevention:** for security-critical resource types (anything touching bucket policies, IAM, network exposure), prefer HashiCorp-verified or well-known partner-maintained providers, and either avoid unvetted community modules entirely or maintain internally-forked, audited copies pinned to specific reviewed commits rather than trusting an upstream community maintainer's account security indefinitely.

### Step-by-Step Implementation
```bash
# Identify every consumer of the affected module across the organization
grep -rl 'source.*community-s3-module' --include='*.tf' ~/repos/*/

# Cross-reference against lock-file-recorded / pinned versions during the exposure window
git log -p --all -- '**/main.tf' | grep -B2 -A2 'community-s3-module'

# Check actual current bucket policy against the known-backdoored default
aws s3api get-bucket-policy --bucket affected-bucket-name

# Check CloudTrail for access from the unexpected external account
aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=<external-account-id>
```
```hcl
# Pin to an internally-audited fork/commit rather than the floating upstream source
module "s3_bucket" {
  source = "git::https://github.com/my-org/s3-module-fork.git?ref=a1b2c3d4"  # audited commit, not upstream tag
}
```

### Under-the-Hood Explanation
A Terraform module is executed with exactly the same trust and privilege as any hand-written configuration in the same apply — there is no sandboxing or privilege reduction for third-party module code, so a malicious default in a module's resource arguments is applied with the full permissions of whatever credentials your Terraform execution has, identical in effect to if you'd hand-written the same malicious configuration yourself. This is precisely why module provenance/vetting matters as much as any other supply-chain dependency, and why the dependency lock file's version pinning (when actually enforced via `~>` constraints rather than floating) limits exposure to only the specific compromised version window rather than every future apply automatically inheriting new upstream changes.

### Common Weak Answer
"Switch to a different community module going forward."

### Why the Weak Answer Fails
This addresses only the forward-looking symptom (stop using this specific module) without addressing the actual incident response needed (assessing and remediating already-affected infrastructure and potential data exposure) or the systemic gap (no vetting process existed for third-party modules used in security-critical contexts, which would just recur with the next unvetted module choice).

### Follow-Up Questions
1. How would you design an internal module-vetting process that doesn't create so much friction that teams route around it?
2. What's the difference in risk profile between a compromised community module and a compromised provider — does your response process differ?
3. How would you detect a similar backdoor proactively, before public disclosure, across modules you already depend on?

### Key Interview Signals
Confirms the candidate treats a compromised dependency as a genuine security incident requiring impact assessment and potential breach handling, not just a "switch dependencies" fix, and thinks about systemic vetting process improvements.

### Hands-On Connection
[Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 63: The CI role that could do almost anything

### Scenario
A security audit of your Terraform CI execution role finds it has `AdministratorAccess` attached, justified originally as "we didn't know exactly what permissions Terraform would need across all our modules, so we granted everything to unblock the team."

### Interview Question
How would you remediate this to least privilege without breaking every pipeline in the process?

### Strong Senior-Level Answer
**Initial assessment:** `AdministratorAccess` on a CI role is one of the highest-leverage single points of failure in the entire estate — any compromise of this one role (a leaked credential, a supply-chain-compromised module per [Question 62](#question-62-the-module-that-wasnt-what-it-claimed-to-be), a misconfigured trust policy per [Question 37](04-providers.md#question-37-the-assume-role-trust-policy-that-trusted-too-much)) grants an attacker complete control of the account, which is precisely why this needs remediation, but remediation must be done carefully to avoid breaking legitimate pipelines mid-fix.

**Technical reasoning:** the correct approach is deriving the *actual* required permission set empirically from real usage, not guessing a smaller policy from scratch and hoping it's sufficient.

**Investigation process:** enable IAM Access Analyzer's policy-generation feature (or review CloudTrail history for this role's actual API call history over a representative period — ideally several full deployment cycles, including any infrequent-but-legitimate operations like a rare disaster-recovery drill or an annual certificate rotation) to build an accurate picture of what this role has actually used, not just what it's authorized to do.

**Recommended solution:** generate a least-privilege policy from the actual usage data, review it for completeness against every known Terraform configuration this role serves (not just what happened to run during the observation window — a role that hasn't yet needed a permission because a particular resource type has never been touched could still legitimately need it soon), and roll it out in **monitor-then-enforce** mode if your tooling supports it (IAM Access Analyzer supports generating a policy and validating it before switching to enforcement) — or, if not, roll it out to a non-production account's equivalent role first, running every pipeline there before touching production.

**Risk controls:** keep `AdministratorAccess` attached but with an added explicit deny for a short buffer period is not a valid strategy (deny statements would need constant hand-maintenance and don't provide genuine least privilege) — instead, do the cutover as a single, well-tested, reversible policy swap with a fast rollback path (revert to the previous policy attachment) if something breaks.

**Validation steps:** run the full suite of your organization's Terraform configurations' plans (and, in a non-prod dry run, applies) against the new least-privilege policy before attaching it in production, specifically looking for any `AccessDenied` errors that reveal a missed permission.

**Rollback or recovery strategy:** keep the previous `AdministratorAccess`-based policy available (detached, not deleted) for a defined grace period after the cutover, so a fast re-attach is possible if an unexpected, rarely-used Terraform operation surfaces a gap the observation window didn't capture.

**Long-term prevention:** re-run the access-analyzer-based least-privilege review periodically (e.g., quarterly) as new resource types are adopted, rather than treating this as a one-time fix — and establish a policy that no new CI role is ever provisioned with a broad managed policy like `AdministratorAccess` "to unblock the team" in the first place, even temporarily, given how easily temporary becomes permanent.

### Step-by-Step Implementation
```bash
# Generate a least-privilege policy from actual CloudTrail usage via IAM Access Analyzer
aws accessanalyzer start-policy-generation \
  --policy-generation-details principalArn=arn:aws:iam::...:role/terraform-ci \
  --cloud-trail-details '{"trails":[{"cloudTrailArn":"...","allRegions":true}],"startTime":"2026-04-01T00:00:00Z","endTime":"2026-07-01T00:00:00Z"}'

aws accessanalyzer get-generated-policy --job-id <job-id>
```
```bash
# Non-prod dry run of the generated policy before production cutover
aws iam attach-role-policy --role-name terraform-ci-nonprod --policy-arn arn:aws:iam::...:policy/tf-ci-least-privilege
# Run every configuration's plan (and apply, in non-prod) against this role
```
```bash
# Production cutover, with fast rollback available
aws iam detach-role-policy --role-name terraform-ci --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam attach-role-policy --role-name terraform-ci --policy-arn arn:aws:iam::...:policy/tf-ci-least-privilege
# Previous policy left detached (not deleted) for a defined rollback window
```

### Under-the-Hood Explanation
IAM Access Analyzer's policy generation feature works by parsing CloudTrail event history for the specified principal and time range, extracting every distinct API action actually invoked, and synthesizing a policy document granting exactly those actions (optionally scoped to the specific resources observed) — this is fundamentally an empirical, usage-derived approach rather than a theoretical one, which is precisely why the *observation window* must be representative of the role's full range of legitimate activity, including infrequent operations, or the generated policy will be too narrow and break something the window didn't happen to capture.

### Common Weak Answer
"Just write a policy with the permissions you think Terraform needs and swap it in."

### Why the Weak Answer Fails
Guessing the required permission set from first principles (rather than deriving it empirically from actual usage) is exactly how the original `AdministratorAccess` grant likely came to exist in the first place ("we didn't know exactly what permissions were needed") — repeating the same guessing approach, just aiming for a smaller guess, risks the same unblock-by-over-granting cycle recurring, or alternatively breaking legitimate pipelines that need a permission the guess missed.

### Follow-Up Questions
1. How would you handle a legitimate but rare operation (like an annual DR drill) that your CloudTrail observation window didn't happen to capture?
2. How would you extend this least-privilege remediation across dozens of similarly over-permissioned roles without repeating this entire manual process for each one?
3. What ongoing process would prevent CI roles from drifting back toward broad permissions over time as new Terraform configurations are added?

### Key Interview Signals
Confirms the candidate reaches for an empirical, usage-derived least-privilege methodology (not a guess) and plans a careful, reversible cutover rather than a risky big-bang policy swap on a critical CI role.

### Hands-On Connection
[Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 64: The KMS key that only trusted itself

### Scenario
Your team shares an encrypted AMI from a central "golden image" account to dozens of application accounts via Terraform. A newly-provisioned application account's `terraform apply` fails when trying to launch an instance from the shared AMI, with an access-denied error referencing the KMS key used to encrypt it — even though the AMI's launch permissions were correctly shared to that account.

### Interview Question
Diagnose the KMS-specific part of this failure and fix it.

### Strong Senior-Level Answer
**Initial assessment:** sharing an AMI's launch permissions and sharing access to the KMS key used to encrypt its underlying snapshot are two entirely separate grants — this failure is almost certainly the KMS key policy not authorizing the new application account to use the key for decryption, even though the AMI-level share is correct.

**Technical reasoning:** an encrypted AMI's snapshot can only be used by an account that both (a) has AMI launch permissions and (b) has permission to use the specific KMS key (or a re-encryption with a key the target account does have access to) — AWS deliberately doesn't let AMI-sharing alone bypass KMS's own access control, since that would undermine the entire point of key-based encryption.

**Investigation process:** check the KMS key's key policy (not just IAM policies in the target account) for a statement granting the new application account's role `kms:CreateGrant`/`kms:Decrint`-equivalent permissions — most likely, the key policy was written to trust only the accounts that existed at the time it was created, and the newly-vended application account was never added.

**Recommended solution:** update the KMS key's policy (in the golden-image account, where the key lives) to grant the necessary permissions to every application account that needs to launch instances from AMIs encrypted with it — ideally scoped via a condition to your organization (e.g., `aws:PrincipalOrgID`) so any newly-vended account is automatically covered without needing a per-account key policy update every time, rather than hand-listing account IDs that need to be remembered and updated for every new account.

**Risk controls:** scoping via `aws:PrincipalOrgID` (or a specific OU-based condition) rather than allowing account-by-account additions avoids this exact class of "we forgot to grant KMS access to the newest account" gap recurring every time a new account is vended.

**Validation steps:** after updating the key policy, confirm the specific failing `terraform apply` in the new application account now succeeds, and confirm (in a non-prod test) that a genuinely unauthorized account (outside the org/condition) is still correctly denied.

**Rollback or recovery strategy:** not applicable — this is a permissions correction with no destructive risk; if the broadened condition turns out to be too permissive for some compliance reason, tighten the condition and re-test against the specific accounts that legitimately need access.

**Long-term prevention:** make KMS key policy grants for any shared, cross-account encrypted resource (golden AMIs, shared encrypted snapshots, shared encrypted S3 data) a standard part of the account-vending pipeline (see [Question 45](05-aws-architecture.md#question-45-account-creation-shouldnt-be-a-ticket)) — using an org-ID-scoped condition specifically so this never needs a manual per-account update again.

### Step-by-Step Implementation
```json
// KMS key policy, golden-image account, scoped to the whole org rather than per-account
{
  "Sid": "AllowOrgAccountsToUseKeyForAMILaunch",
  "Effect": "Allow",
  "Principal": { "AWS": "*" },
  "Action": ["kms:Decrypt", "kms:CreateGrant", "kms:DescribeKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": { "aws:PrincipalOrgID": "o-abc123xyz" }
  }
}
```
```hcl
resource "aws_kms_key" "golden_ami" {
  policy = data.aws_iam_policy_document.golden_ami_key_policy.json
}

data "aws_iam_policy_document" "golden_ami_key_policy" {
  statement {
    sid       = "AllowOrgAccountsToUseKeyForAMILaunch"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:CreateGrant", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}
```

### Under-the-Hood Explanation
Launching an EC2 instance from an encrypted AMI requires the launching account's role to have permission both to use the AMI (a separate, EC2-level launch-permission share) and to call `kms:Decrypt`/`kms:CreateGrant` against the specific KMS key protecting the AMI's underlying EBS snapshot — this is enforced at the KMS key-policy level independently of EC2's own AMI-sharing permissions, precisely because AWS's security model treats "who can use this AMI" and "who can decrypt data encrypted with this key" as separate authorization questions, even when one clearly depends on the other for a specific real-world use case like this one.

### Common Weak Answer
"Just make the AMI unencrypted to avoid the KMS complexity."

### Why the Weak Answer Fails
Removing encryption to work around an access-control misconfiguration trades away a genuine security control (encryption at rest for golden images, which likely contain sensitive baseline configuration) to avoid correctly configuring the KMS key policy — the actual fix (a properly-scoped key policy) is not meaningfully harder and doesn't require sacrificing encryption.

### Follow-Up Questions
1. How would you handle this same problem for cross-account RDS snapshot sharing instead of AMIs — is the KMS mechanism identical?
2. What's the security trade-off of scoping the KMS key policy via `aws:PrincipalOrgID` versus explicitly listing only the specific accounts that should have access?
3. How would you detect this class of "new account missing a needed cross-account grant" proactively, before a team's first apply fails on it?

### Key Interview Signals
Confirms the candidate understands that AMI-sharing and KMS key access are independently-enforced authorization layers, not automatically linked, and designs a scalable (org-ID-scoped) fix rather than a per-account hand-maintained list.

### Hands-On Connection
[Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 65: Auditing sixty accounts for one bad habit

### Scenario
Following an incident in one account where a security group briefly exposed a database port (5432) to `0.0.0.0/0`, leadership wants confidence this isn't happening anywhere else across your organization's sixty AWS accounts, today and on an ongoing basis.

### Interview Question
Design a fleet-wide detection and prevention mechanism for this pattern, not just a fix for the one incident.

### Strong Senior-Level Answer
**Initial assessment:** this needs both a one-time retroactive sweep (find every currently-existing instance of this pattern across sixty accounts) and an ongoing, structural prevention mechanism (stop it from recurring anywhere, in any account, going forward) — a single incident fix addresses neither.

**Technical reasoning:** retroactive detection is best done via a cloud-native, account-spanning tool (AWS Config aggregated across the organization, or a direct API sweep) since it doesn't depend on infrastructure being Terraform-managed at all (a manually-created security group with this issue wouldn't show up in a Terraform-code-only scan); ongoing prevention is best enforced via policy-as-code in every Terraform pipeline (catching it before apply) plus an AWS Config rule as a continuous, Terraform-independent backstop (catching manual changes too).

**Investigation process:** run an organization-wide API sweep (or AWS Config aggregator query) across all sixty accounts checking every security group for ingress rules matching `0.0.0.0/0` on database-class ports (5432, 3306, 1433, 27017, etc.), producing a definitive current-state inventory rather than assuming the one known incident is the only instance.

**Recommended solution:** for the retroactive sweep, remediate every finding (working with each account's owning team to confirm the rule is genuinely unintended, then correcting it via Terraform if managed, or importing-then-correcting if it was a manual, out-of-band change). For ongoing prevention: add an OPA/Conftest policy-as-code rule to every Terraform pipeline across the organization denying any plan introducing this pattern, and separately enable an AWS Config managed rule (`restricted-common-ports` or a custom rule) aggregated across the organization via AWS Config's multi-account aggregator, alerting (and optionally auto-remediating via SSM Automation) on any occurrence regardless of whether it originated from Terraform or a manual change.

**Risk controls:** the AWS Config layer is the genuinely load-bearing control here, since it catches manual/non-Terraform-originated instances that a Terraform-pipeline-only policy check would completely miss — don't rely on policy-as-code alone for a fleet-wide guarantee.

**Validation steps:** after remediation, re-run the organization-wide sweep and confirm zero findings; separately, deliberately create a test violation in a non-prod account and confirm both the Terraform-pipeline policy check and the AWS Config rule each independently catch it.

**Rollback or recovery strategy:** not applicable to the detection/prevention mechanism itself; for each remediated security group, confirm the affected application's actual required access pattern is preserved via a correctly-scoped replacement rule (specific source CIDR/security-group reference), not just a deletion that might break legitimate access.

**Long-term prevention:** report the AWS Config aggregated finding count for this rule (and similar high-risk patterns) as a standing organizational security metric, not just a one-time incident closure — visibility over time is what prevents this from silently recurring across sixty accounts again.

### Step-by-Step Implementation
```bash
# Organization-wide sweep via AWS Config aggregator (assuming one is set up)
aws configservice select-aggregate-resource-config \
  --configuration-aggregator-name org-aggregator \
  --expression "SELECT accountId, resourceId, configuration.ipPermissions \
                WHERE resourceType = 'AWS::EC2::SecurityGroup'"
```
```rego
# Conftest/OPA policy, added to every Terraform pipeline
deny[msg] {
  sg := input.resource_changes[_]
  sg.type == "aws_security_group_rule"
  sg.change.after.cidr_blocks[_] == "0.0.0.0/0"
  db_ports := {5432, 3306, 1433, 27017}
  db_ports[sg.change.after.from_port]
  msg := sprintf("%s: database port %d must not be open to 0.0.0.0/0", [sg.address, sg.change.after.from_port])
}
```
```hcl
# AWS Config rule, deployed once, aggregated across the org, catches manual changes too
resource "aws_config_config_rule" "restricted_db_ports" {
  name = "restricted-common-ports"
  source {
    owner             = "AWS"
    source_identifier = "RESTRICTED_INCOMING_TRAFFIC"
  }
  input_parameters = jsonencode({ blockedPort1 = "5432", blockedPort2 = "3306" })
}
```

### Under-the-Hood Explanation
AWS Config continuously records configuration snapshots and change events for supported resource types across every account it's enabled in, independent of how those resources were created (Terraform, console, CLI, or any other tool) — an aggregator collects this across every account in the organization into one queryable view, which is precisely why it's the correct backstop for catching non-Terraform-originated instances of a misconfiguration pattern that a Terraform-pipeline-only policy check structurally cannot see, since that check only ever runs against Terraform plans, never against out-of-band manual changes.

### Common Weak Answer
"Add a Conftest rule to the pipeline that created the original incident's configuration."

### Why the Weak Answer Fails
This only prevents recurrence in the *one* pipeline/repository where the incident happened, leaving fifty-nine other accounts (and any manually-created security groups anywhere) completely uncovered — the question specifically asks for a fleet-wide mechanism, which requires both a retroactive sweep and an account-spanning, Terraform-independent ongoing control (AWS Config), not a single pipeline's policy check.

### Follow-Up Questions
1. How would you handle auto-remediation (automatically closing the offending rule) versus alert-only, and what are the risks of each for a database port specifically?
2. How would you extend this pattern to catch other high-risk configurations (public S3 buckets, overly permissive IAM policies) using the same dual retroactive-sweep-plus-ongoing-Config-rule approach?
3. What's your process for handling a legitimate exception (a genuine, reviewed need for broader access) without permanently weakening the fleet-wide rule?

### Key Interview Signals
Confirms the candidate designs for fleet-wide, Terraform-independent coverage (recognizing that policy-as-code alone only covers Terraform-originated changes) and treats this as requiring both retroactive remediation and an ongoing, continuously-monitored control.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 66: The workspace variable that looked protected but wasn't

### Scenario
In Terraform Cloud, a workspace variable holding a third-party API key is set as a Terraform variable (not an environment variable) and marked "sensitive" in the TFC UI. A teammate points out that this value still appears in plaintext in the resulting Terraform state, and asks whether the "sensitive" checkbox in TFC actually protects it.

### Interview Question
Explain exactly what TFC's "sensitive" variable marking does and doesn't protect, and how you'd actually secure this API key properly.

### Strong Senior-Level Answer
**Initial assessment:** the teammate's instinct is correct to question this — Terraform Cloud's "sensitive" checkbox on a variable controls whether the value is displayed/redacted in the TFC UI and API responses, similar in spirit to Terraform's own `sensitive = true` variable marking (see [Question 17 in category 2](02-state-management.md#question-17-the-password-in-the-state-export)) — it does not prevent the value from being written into state if it flows into a resource attribute, and it does not encrypt the value differently within TFC's own storage beyond TFC's standard at-rest encryption for all workspace data.

**Technical reasoning:** if this API key is consumed by a resource argument (e.g., a provider configuration or a resource attribute that stores it), it will appear in state in whatever form the provider returns/stores it, exactly as with any other secret value — TFC's sensitive marking is a UI/API display control layered on top of, not a replacement for, the same state-content reality as self-managed Terraform.

**Investigation process:** confirm exactly where this API key is actually used — is it only ever passed to a provider's authentication configuration (which may not persist it into any resource's state attributes at all, depending on the provider), or does it flow into an actual resource argument that gets stored?

**Recommended solution:** if the API key must flow into a resource attribute that will be stored in state, the real protections are the same as any other Terraform secret: ensure TFC's state storage encryption is relied upon (TFC encrypts state at rest by default, but access control — who can view state/run details for this workspace — is the actual gate), scope workspace access (team permissions in TFC) tightly to only those who genuinely need it, and rotate the key if you have any reason to believe workspace access has been broader than intended. Where possible, prefer having the underlying provider/resource fetch the secret dynamically from a dedicated secrets manager at apply time (via a data source) rather than passing it as a Terraform variable at all, reducing how much of it ever needs to persist in Terraform's own state.

**Risk controls:** audit TFC team/workspace access permissions for this specific workspace — "sensitive" marking gives a false sense of security if workspace access itself is broader than the value's actual sensitivity warrants.

**Validation steps:** pull the workspace's state (via the TFC API, with appropriate permissions) and confirm directly whether the key appears in plaintext, settling the question empirically rather than relying on assumption either way.

**Rollback or recovery strategy:** not applicable — this is a configuration/access-control hardening exercise, not an infrastructure change with a rollback path; if the audit reveals the key has been visible to more people/systems than intended, rotate it.

**Long-term prevention:** document clearly, for every team using Terraform Cloud, that "sensitive" variable marking is a UI-display control only — exactly the same clarification needed for Terraform's own `sensitive = true`, generalized to the TFC-specific UI feature, since teams frequently and reasonably assume a checkbox labeled "sensitive" implies stronger protection than it actually provides.

### Step-by-Step Implementation
```bash
# Empirically confirm whether the value persists in state
curl -H "Authorization: Bearer $TFC_TOKEN" \
  "https://app.terraform.io/api/v2/workspaces/$WS_ID/current-state-version" | jq .
# Fetch the referenced state file and check whether the API key appears in plaintext
```
```hcl
# Preferred: fetch the secret dynamically at apply time rather than storing as a TFC variable
data "vault_generic_secret" "third_party_api_key" {
  path = "secret/third-party-api"
}

resource "example_resource" "this" {
  api_key = data.vault_generic_secret.third_party_api_key.data["key"]
}
```

### Under-the-Hood Explanation
Terraform Cloud's variable "sensitive" flag is metadata stored alongside the variable's value in TFC's own database, consulted by the TFC UI/API to decide whether to redact the value in run logs, variable listings, and API responses — this is entirely orthogonal to what Terraform Core itself does with that value once it's passed into a run: if the value flows into a resource argument, it's serialized into the resulting state file exactly as it would be for any other value, subject only to TFC's standard at-rest encryption and access-control model for state storage generally, not any additional protection specific to variables marked sensitive.

### Common Weak Answer
"It's marked sensitive in Terraform Cloud, so it's protected."

### Why the Weak Answer Fails
This is precisely the misconception the scenario is testing for — conflating a UI-display redaction feature with actual encryption/access-control protection of the underlying value, when the real protections (state encryption at rest, workspace access scoping, secrets-manager-based dynamic fetching) are what actually matter and exist independently of the sensitive checkbox.

### Follow-Up Questions
1. How does TFC's dynamic provider credentials (workload identity) feature reduce this class of risk for cloud provider authentication specifically, compared to a manually-supplied secret variable?
2. How would you audit which TFC team members/workspaces currently hold secrets as plain Terraform variables versus fetching them dynamically, across your whole TFC organization?
3. What's the difference in risk between a "Terraform" type sensitive variable and an "Environment Variable" type sensitive variable in TFC?

### Key Interview Signals
Confirms the candidate doesn't conflate a platform-specific UI convenience feature (TFC's sensitive checkbox) with genuine security controls, and can articulate the actual protections (encryption at rest, access control, dynamic secret fetching) precisely.

### Hands-On Connection
[Lab 2 — Secure Remote State](../labs/lab-02-remote-state/) and [Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 67: Choosing a policy engine before you have a platform for it

### Scenario
Your organization is standardizing on policy-as-code for the first time, using self-managed Terraform (open-source CLI, S3 backend, GitHub Actions) rather than Terraform Cloud/Enterprise. A vendor pitch suggests Sentinel is "the" HashiCorp-native standard and your team should adopt it regardless.

### Interview Question
Would you choose Sentinel or OPA/Conftest for this organization, and why?

### Strong Senior-Level Answer
**Initial assessment:** for an organization on self-managed, open-source Terraform (no Terraform Cloud/Enterprise), OPA/Conftest is almost certainly the correct choice — Sentinel's primary integration path is natively built into Terraform Cloud/Enterprise workspaces; using it outside that context requires significantly more custom integration work than Conftest, which is designed to evaluate a plan JSON file in any CI environment with no platform dependency at all.

**Technical reasoning:** Conftest operates on `terraform show -json` output directly, runnable from any CI system (GitHub Actions, GitLab CI, Jenkins) with zero dependency on which Terraform execution platform you use — this matches the organization's actual stack (GitHub Actions, self-managed backend) far more naturally than Sentinel, whose tooling and typical usage patterns assume the TFC/TFE run pipeline.

**Investigation process:** confirm this understanding against the vendor's actual claim — is there a genuine technical reason Sentinel would integrate as smoothly outside TFC/TFE, or is the pitch conflating "HashiCorp-native" with "the right choice regardless of platform"? (It's the latter, unless the organization is also planning to adopt Terraform Cloud/Enterprise, which isn't stated in this scenario.)

**Recommended solution:** adopt OPA/Conftest, writing policies in Rego, integrated as a CI step evaluating each `terraform plan`'s JSON output before apply — matching the existing GitHub Actions pipeline architecture with no additional platform dependency.

**Risk controls:** if the organization later migrates to Terraform Cloud/Enterprise (a legitimate future possibility), re-evaluate then — Sentinel's tighter TFC/TFE integration (policy sets attached directly to workspaces, built-in enforcement levels) becomes genuinely more compelling in that context, so this isn't a permanent, irreversible choice, just the right one for the current platform.

**Validation steps:** confirm the chosen policy engine actually integrates cleanly with the existing plan-artifact-based pipeline (see [`cicd.md` §2](../docs/cicd.md#2-plan-generation-plan-artifacts-and-plan-integrity)) without requiring a parallel, redundant plan generation step just to feed the policy engine.

**Rollback or recovery strategy:** not applicable — this is a tooling adoption decision, reversible in principle (policies can be reauthored for a different engine later) but with real migration cost, which is exactly why the platform-fit assessment matters now rather than choosing based on vendor branding alone.

**Long-term prevention:** document the actual decision criteria used here (platform fit, not vendor "native-ness" claims) so future tooling decisions in the organization follow the same evidence-based evaluation rather than defaulting to whichever vendor pitches hardest.

### Step-by-Step Implementation
```bash
# Conftest integrated into the existing GitHub Actions pipeline, no platform dependency
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test plan.json --policy policies/
```
```rego
# policies/s3_encryption.rego
package main

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket"
  not resource.change.after.server_side_encryption_configuration
  msg := sprintf("%s: S3 bucket must have encryption configured", [resource.address])
}
```

### Under-the-Hood Explanation
Sentinel policies are evaluated by HashiCorp's Sentinel runtime as an integrated step within a Terraform Cloud/Enterprise run — the platform itself invokes the policy check at a specific point in the managed run lifecycle (between plan and apply), with policy sets, enforcement levels (advisory/soft-mandatory/hard-mandatory), and results surfaced natively in the TFC/TFE UI. Conftest, by contrast, is a completely standalone CLI tool that evaluates any JSON/YAML input (including `terraform show -json` output) against Rego policies, with zero awareness of or dependency on any specific Terraform execution platform — this is precisely why it fits a self-managed, open-source-CLI-plus-GitHub-Actions stack with no additional platform lock-in, while Sentinel's value proposition specifically depends on already being inside the TFC/TFE ecosystem.

### Common Weak Answer
"Sentinel is HashiCorp's own tool, so it must be the best choice for Terraform."

### Why the Weak Answer Fails
This conflates vendor affiliation with technical fit — Sentinel's design and primary integration path assume Terraform Cloud/Enterprise specifically, which this organization doesn't use; choosing it anyway would mean building substantial custom integration work to approximate what Conftest already does natively for this exact stack, for no corresponding benefit.

### Follow-Up Questions
1. What would change your recommendation if this organization migrated to Terraform Cloud/Enterprise in the future?
2. How would you structure a Rego policy library so it stays maintainable as the number of rules grows into the dozens or hundreds?
3. How do you handle testing Rego policies themselves for false positives/negatives before they gate real pipelines (see also [`testing.md` §7](../docs/testing.md#7-policy-tests))?

### Key Interview Signals
Confirms the candidate evaluates tooling decisions on actual platform fit and integration cost, not vendor branding, and understands the concrete architectural difference between Sentinel's platform-integrated model and Conftest's standalone model.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 68: The debug rule nobody remembered to close

### Scenario
Six weeks ago, during a production incident, an engineer temporarily opened a security group rule allowing `0.0.0.0/0` access to a database port to rule out a network-connectivity hypothesis while debugging under pressure. The hypothesis was wrong, the real cause was found elsewhere, and the incident was resolved — but the temporary rule was applied via a direct `terraform apply` with a manually-edited `.tf` file that was never reverted, and nobody circled back to it afterward.

### Interview Question
Run the postmortem on this specific gap, and design controls that would have caught it regardless of the pressure of the moment.

### Strong Senior-Level Answer
**Initial assessment:** the actual failure here isn't that a temporary debug change was made under incident pressure (that's sometimes a legitimate, fast diagnostic action) — it's that the temporary change had no mechanism forcing it to be reverted, reviewed, or even remembered once the incident resolved.

**Technical reasoning:** any change made outside the normal reviewed-PR pipeline during an incident (a deliberate, reasonable trade-off in the moment — speed over process during active firefighting) creates exactly this kind of residual-risk gap unless there's an explicit, structural mechanism ensuring it gets revisited afterward.

**Investigation process:** confirm via your incident-response tooling/process whether this change was ever logged as part of the incident timeline at all — if it wasn't, that's the first gap (any out-of-band change during an incident should be recorded, even if applied outside the normal pipeline for speed).

**Recommended solution:** immediately close the exposed port. Establish (going forward) a mandatory "incident-time out-of-band change" tracking step: any direct `apply` made during an active incident, bypassing normal PR review for speed, must be logged in the incident ticket with an explicit "temporary changes to revert" checklist item, and the incident's postmortem/closure process must include verifying every such item was actually reverted before the incident is marked fully closed — not just that the customer-facing symptom was resolved.

**Risk controls:** pair this process control with the same fleet-wide detection mechanism from [Question 65](#question-65-auditing-sixty-accounts-for-one-bad-habit) (AWS Config rule for restricted ports) as a backstop — even if the process step is missed again in some future incident, the continuous Config-rule monitoring should catch the residual exposure within its own alerting cadence, rather than depending entirely on human process discipline.

**Validation steps:** after closing this specific rule, confirm via the AWS Config rule (or a direct check) that no other database ports remain exposed to `0.0.0.0/0` anywhere, in case this wasn't the only unremembered incident-time change.

**Rollback or recovery strategy:** the fix here (closing the port) is itself the recovery — check CloudTrail/VPC Flow Logs for the six-week exposure window to determine whether any actual unauthorized access occurred that needs its own incident response, since a six-week window of public exposure to a database port is a genuine, separate concern beyond just closing the hole.

**Long-term prevention:** make "verify all incident-time out-of-band changes are reverted or intentionally retained via a reviewed follow-up PR" a mandatory, checked item in your incident postmortem template going forward, and rely on the AWS Config continuous-monitoring backstop as defense-in-depth for exactly this kind of process gap.

### Step-by-Step Implementation
```bash
# Immediate: close the exposed rule
terraform plan   # confirm this shows the rule being removed, nothing else
terraform apply

# Investigate the exposure window for any actual unauthorized access
aws cloudtrail lookup-events --start-time 2026-06-10 --end-time 2026-07-24 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeSecurityGroupIngress
# Check VPC Flow Logs for actual connection attempts to the database port from unexpected sources
```
```markdown
<!-- Incident postmortem template addition -->
## Out-of-band changes made during this incident
- [ ] List every direct `apply`/console change made outside normal PR review during the incident
- [ ] For each: has it been reverted, or intentionally retained via a reviewed follow-up PR?
- [ ] Incident is not closed until every item above is checked
```

### Under-the-Hood Explanation
There's no Terraform mechanism that automatically expires or flags a manually-applied change as "temporary" — a direct `apply` outside the normal reviewed pipeline is, from Terraform's perspective, exactly as permanent as any other apply; the six-week persistence isn't a tooling failure, it's the natural, expected consequence of a change with no explicit tracking or reversion mechanism attached to it, which is exactly the process gap this postmortem needs to close.

### Common Weak Answer
"Tell engineers not to make direct, unreviewed changes during incidents."

### Why the Weak Answer Fails
This ignores that fast, unreviewed changes are sometimes a legitimate and necessary trade-off during active incident response — the fix isn't eliminating that flexibility, it's ensuring any such change is explicitly tracked and its reversion verified as part of incident closure, plus a continuous-monitoring backstop that doesn't depend on the process step being followed correctly every time.

### Follow-Up Questions
1. How would you balance the need for speed during an active incident against the desire for reviewed, tracked changes?
2. What would you do if the exposure window investigation revealed actual unauthorized access occurred?
3. How would you extend this "track and verify reversion of incident-time changes" process to cover IAM permission changes made during an incident, not just security groups?

### Key Interview Signals
Confirms the candidate doesn't respond with an unrealistic "never bypass process, even during incidents" answer, and instead designs a tracking/verification mechanism that accommodates necessary incident-time speed while closing the actual gap (nothing forced anyone to remember or revert the change).

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).
