# Category 14: Migration, Import, and Upgrades

Questions 115–117 of 120. Category weight: 3 questions. Deep-dive reference: [`docs/state-management.md` §9](../docs/state-management.md#9-terraform-state-subcommands--what-each-is-actually-for) and [`docs/module-design.md` §9](../docs/module-design.md#9-upgrade-and-deprecation-strategies).

---

## Question 115: Retiring a CloudFormation stack without retiring the infrastructure

### Scenario
A production application's infrastructure — VPC, RDS instance, ALB, EC2 Auto Scaling Group — was originally provisioned via a CloudFormation stack, predating your organization's adoption of Terraform. Leadership wants this migrated to Terraform management so it fits your standard tooling, without any downtime or resource recreation.

### Interview Question
Design this migration end to end.

### Strong Senior-Level Answer
**Initial assessment:** the actual AWS resources (VPC, RDS instance, etc.) are identical regardless of which tool created them — CloudFormation and Terraform are both just clients calling the same AWS APIs; the migration is about bringing existing, running resources under Terraform's state tracking without touching them, and separately deciding what to do with the now-redundant CloudFormation stack.

**Technical reasoning:** `import` blocks (Terraform >= 1.5, ideally with `-generate-config-out` to draft matching configuration) are the correct mechanism, applied resource by resource, in dependency order (VPC first, then subnets/security groups, then RDS/ALB/ASG) — no resource needs to be destroyed or recreated at any point.

**Investigation process:** enumerate every resource the CloudFormation stack manages (`aws cloudformation describe-stack-resources`) to build the complete import checklist, and note the CloudFormation stack's current resource attributes as the "ground truth" to validate the imported Terraform configuration against.

**Recommended solution:** for each resource, write an `import` block with the correct ID (per the provider's documented import ID format for that resource type — see [Question 92 in category 10](10-troubleshooting.md#question-92-the-import-that-needed-three-tries-to-get-the-ide-right)) and use `-generate-config-out` to draft the corresponding Terraform configuration; review and refine the generated configuration carefully against the resource's actual real-world settings; apply the import (which only writes state, not any resource change) and confirm via `terraform plan` that the result is a **zero-diff** plan for every imported resource — proving the drafted configuration exactly matches reality. Once every resource is imported and validated, the CloudFormation stack itself needs to be handled: use CloudFormation's "retain resources" deletion mode (which deletes the stack's own tracking metadata without touching the underlying resources) so CloudFormation stops considering itself the owner, leaving Terraform as the sole manager going forward.

**Risk controls:** perform this resource-by-resource, validating zero-diff at each step before moving to the next, rather than attempting to import the entire stack's resources in one large batch — a mistake caught early (one resource's config slightly wrong) is much easier to fix than discovering an error after twenty resources have all been imported with the same subtle mistake repeated.

**Validation steps:** the zero-diff plan after each import is the concrete proof; additionally, confirm the application itself continues functioning normally throughout the migration (since no resource is ever touched, there should be zero customer-visible impact at any point).

**Rollback or recovery strategy:** since imports only affect Terraform's own state (never the underlying resources) until you explicitly apply a *subsequent* change, the "rollback" for any import gone wrong is simply not proceeding with that resource's import (or removing its state entry via `state rm` if already imported incorrectly) — the actual infrastructure is never at risk during this phase.

**Long-term prevention:** once fully migrated, ensure the CloudFormation stack is genuinely retired (not just "retained resources" deleted but forgotten about) so nobody accidentally re-applies a CloudFormation update to a resource Terraform now manages, which would create exactly the dual-tool-ownership confusion this migration is meant to resolve.

### Step-by-Step Implementation
```bash
# Enumerate every resource the CloudFormation stack manages
aws cloudformation describe-stack-resources --stack-name legacy-app-stack
```
```hcl
# Import block per resource, dependency order: VPC first
import {
  to = aws_vpc.main
  id = "vpc-0abc123def456"
}
```
```bash
terraform plan -generate-config-out=generated_vpc.tf
# Review generated_vpc.tf carefully against the VPC's actual settings
terraform apply   # writes state only, touches nothing in AWS
terraform plan     # MUST show zero changes - proof the import is correct
# Repeat for subnets, security groups, RDS, ALB, ASG, in dependency order
```
```bash
# Once every resource is imported and validated:
aws cloudformation delete-stack --stack-name legacy-app-stack --retain-resources <list-of-all-resource-logical-ids>
```

### Under-the-Hood Explanation
CloudFormation and Terraform both operate purely by making standard AWS API calls (`CreateVpc`, `CreateDBInstance`, etc.) and separately tracking, in their own respective state formats, what they believe they created — neither tool has any special ownership marker on the actual AWS resources themselves beyond what each tool's own bookkeeping records. `import` blocks populate Terraform's state with the real, current attributes of an existing resource (via the same `ImportResourceState` provider RPC used for any import), entirely independent of and without needing to notify CloudFormation at all — the resources themselves are completely unaware of which tool is "managing" them; only each tool's separate state/stack metadata reflects that ownership.

### Common Weak Answer
"Delete the CloudFormation stack and recreate everything in Terraform."

### Why the Weak Answer Fails
Deleting a CloudFormation stack normally (without the "retain resources" option) deletes the underlying AWS resources along with the stack's tracking metadata — this would destroy the running production VPC, RDS instance, and everything else, causing exactly the outage and data loss the migration is explicitly required to avoid; the "retain resources" deletion mode is specifically designed for exactly this migration scenario.

### Follow-Up Questions
1. How would you handle a CloudFormation stack using nested stacks or stack sets, adding complexity to the resource enumeration?
2. What's your validation process if `-generate-config-out` produces a configuration that's subtly different from what CloudFormation's own template specified (e.g., a default value CloudFormation didn't set explicitly but Terraform's generated config does)?
3. How would you handle CloudFormation-specific features (like `DependsOn` at the stack level, or CloudFormation custom resources backed by Lambda) that don't have a direct Terraform equivalent?

### Key Interview Signals
Confirms the candidate knows the specific "retain resources" CloudFormation deletion mode (a frequently-missed detail critical to this migration's safety) and executes the import methodically, resource by resource, with zero-diff validation at each step rather than attempting a risky bulk migration.

### Hands-On Connection
[Lab 6 — Import Existing Infrastructure](../labs/lab-06-import-existing-infrastructure/).

---

## Question 116: The upgrade that touched sixty repositories

### Scenario
Your organization needs to upgrade from Terraform 1.5 to a current 1.x release across sixty separate repositories, several using slightly different module versions and provider constraints, with no coordinated release process currently in place for an organization-wide Terraform version bump.

### Interview Question
Design the rollout plan.

### Strong Senior-Level Answer
**Initial assessment:** this is fundamentally a coordinated, incremental rollout problem across a large, heterogeneous set of repositories — the risk isn't any single repository's upgrade (which is usually low-risk, testable in isolation) but the *coordination* challenge of doing this safely and trackably across sixty independently-owned configurations without a big-bang, all-at-once change.

**Technical reasoning:** each repository's Terraform CLI version constraint (`required_version`) can be bumped independently — there's no requirement that every repository upgrade simultaneously, which is exactly the property that makes an incremental, repository-by-repository rollout both possible and much lower-risk than attempting to coordinate sixty simultaneous changes.

**Investigation process:** categorize the sixty repositories by risk (how critical is the infrastructure, how complex is the configuration, does it use any language features/providers with known version-specific behavior changes between 1.5 and the target version) to sequence the rollout from lowest-risk to highest-risk, and identify any repository with an unusual or legacy pattern (e.g., still using deprecated syntax that a newer Terraform version might handle differently or warn about) needing special attention.

**Recommended solution:** start with a small number of low-risk, non-production repositories, running `terraform plan` under the new version and confirming a clean, expected diff (ideally zero, for a pure CLI version bump with no corresponding provider/module changes) before bumping their `required_version` and merging. Use these initial repositories to catch any organization-wide issues (a commonly-used module pattern that behaves differently, a provider version incompatibility) before they affect the remaining fifty-plus repositories. Roll out progressively (a batch per week, say, rather than all sixty at once), tracking completion via a simple checklist/dashboard, prioritizing lower-risk repositories earlier and higher-risk/production-critical ones later, once confidence is established from the earlier batches.

**Risk controls:** for any repository showing an unexpected diff under the new version (not just a clean, informational upgrade), pause that specific repository's rollout and investigate before proceeding — don't let rollout-schedule pressure override the standard "unexpected plan diff means stop and investigate" discipline from earlier categories.

**Validation steps:** for every repository, confirm `terraform plan` under the new version shows the expected (ideally zero) diff before merging the version bump, exactly matching the discipline applied to any other configuration change.

**Rollback or recovery strategy:** since `required_version` constraints are just configuration, a repository can revert to the prior constraint if the new version causes an issue specific to that configuration, without affecting any other already-migrated or not-yet-migrated repository — the per-repository independence is exactly what makes rollback low-risk and localized.

**Long-term prevention:** establish a standing, lightweight process for future Terraform version upgrades (a similar staged rollout, rather than reinventing this coordination approach each time), and consider whether centralizing more shared modules/patterns (reducing the sixty repositories' actual configuration diversity) would make future upgrades faster to roll out with more confidence.

### Step-by-Step Implementation
```hcl
# Per-repository, independent version constraint bump
terraform {
  required_version = "~> 1.9.0"   # bumped from ~> 1.5.0
}
```
```bash
# Per-repository validation before merging the bump
terraform init -upgrade
terraform plan   # confirm expected (ideally zero) diff under the new CLI version
```
```markdown
<!-- Rollout tracking -->
## Terraform 1.9 rollout (60 repositories)
Batch 1 (low-risk, non-prod) - Week 1: [x] repo-a [x] repo-b [x] repo-c ...
Batch 2 (medium-risk) - Week 2-3: [ ] repo-x [ ] repo-y ...
Batch 3 (production-critical) - Week 4+: [ ] repo-z ...
```

### Under-the-Hood Explanation
`required_version` is a per-configuration constraint checked by `terraform init`/every command — it doesn't require organization-wide coordination at the tooling level at all; each repository independently resolves against whatever CLI version is actually installed in its CI runner/local environment, meaning a staged, repository-by-repository rollout is fully supported by Terraform's own design, not something requiring a workaround — the coordination challenge here is entirely a process/tracking one, not a technical constraint Terraform itself imposes.

### Common Weak Answer
"Just bump the version in all sixty repositories at once since it's a routine minor upgrade."

### Why the Weak Answer Fails
A simultaneous, uncoordinated bump across sixty independently-owned, heterogeneous repositories means any organization-wide issue (an incompatibility with a commonly-used module pattern, an unexpected behavior change) affects all sixty at once with no early-warning batch to catch it first — a staged rollout specifically exists to catch such issues cheaply, in a small number of repositories, before they'd otherwise affect the whole estate simultaneously.

### Follow-Up Questions
1. How would you handle a repository that's blocked from upgrading due to a genuinely incompatible dependency (similar to [Question 93 in category 10](10-troubleshooting.md#question-93-the-provider-stuck-in-the-past))?
2. How would you decide the right batch size and cadence for the rollout, balancing thoroughness against how long sixty repositories realistically takes to fully migrate?
3. How would you communicate this rollout plan to the sixty repositories' owning teams to set expectations and get their buy-in on timing?

### Key Interview Signals
Confirms the candidate designs a genuinely staged, risk-ordered rollout (not a risky simultaneous bump) and recognizes that Terraform's per-configuration version constraints make incremental rollout both possible and low-risk by design.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 117: Bringing five years of ClickOps under management

### Scenario
A business unit's AWS account has been managed entirely through the AWS console for five years — no Terraform, no CloudFormation, nothing. It contains roughly 300 resources across networking, compute, and data services. Leadership wants this brought under Terraform management, but with essentially zero tolerance for any disruption to the currently-running (and currently working) production systems.

### Interview Question
Design the adoption plan for bringing manually-managed infrastructure under Terraform at this scale.

### Strong Senior-Level Answer
**Initial assessment:** unlike the CloudFormation migration (Question 115), there's no existing infrastructure-as-code source of truth here at all — every resource's configuration needs to be discovered directly from the live AWS environment, making this a larger, more discovery-intensive undertaking, but the underlying safety principle is identical: import, never recreate.

**Technical reasoning:** the practical approach for 300 resources with no existing IaC source combines automated discovery tooling (to enumerate and generate a starting inventory) with the same careful, resource-by-resource `import` block plus `-generate-config-out` workflow from Question 115 — but at this scale, tooling to accelerate the initial discovery/scaffolding is worth the investment, since hand-enumerating 300 resources manually would be slow and error-prone.

**Investigation process:** use an AWS resource discovery/export tool (several exist — some commercial, some open-source, that scan an account and produce either a resource inventory or draft Terraform configuration) to generate a starting point, understanding that generated output from any such tool needs careful human review, not blind trust — automated scanners can miss non-obvious configuration details or misclassify resource relationships.

**Recommended solution:** sequence the adoption in dependency-order layers, mirroring the layered architecture principle from enterprise questions: import foundational networking (VPC, subnets, route tables, security groups) first, validate thoroughly, then IAM, then compute, then data services — at each layer, use `import` blocks with `-generate-config-out` and validate every single resource with a zero-diff plan before moving to the next layer. Given 300 resources, do this in batches (e.g., 20-30 resources per batch) with a dedicated validation window between batches, rather than attempting all 300 in one continuous effort.

**Risk controls:** for any resource where the generated configuration doesn't cleanly produce a zero-diff plan, stop and investigate that specific resource before continuing — don't accumulate "close enough" imports that could hide a real misconfiguration or drift that gets baked into the adopted configuration incorrectly.

**Validation steps:** the zero-diff plan per resource (or per small batch) is the primary validation; additionally, given the "zero tolerance for disruption" requirement, consider running the entire import process initially in **plan-only** mode with no `apply` at all until every single resource across all 300 has been validated to produce a clean, correct generated configuration — only then apply the imports as a final, confirmed-safe step (or in the same incremental batches, once each batch is independently confirmed correct).

**Rollback or recovery strategy:** since imports only write Terraform state (never touch the actual resources) until a subsequent apply changes something, this entire process carries zero risk to the running production systems as long as no accidental non-import changes are introduced — the "zero tolerance for disruption" requirement is fundamentally satisfiable by this approach, since nothing about the real infrastructure changes during the entire adoption process.

**Long-term prevention:** once fully imported and validated, treat this account exactly like any other Terraform-managed environment going forward — established change process, CI/CD pipeline, policy-as-code enforcement — since the point of this whole exercise is graduating the account out of ClickOps permanently, not just performing a one-time import exercise that then reverts to manual management.

### Step-by-Step Implementation
```bash
# Automated discovery as a starting point (illustrative - actual tool choice varies)
# Several tools can scan an AWS account and generate an initial resource inventory
# or draft Terraform configuration - treat output as a draft requiring review, not final truth

# Layered import sequence, in batches, dependency order first
```
```hcl
# Batch 1: foundational networking
import { to = aws_vpc.main         id = "vpc-0abc123" }
import { to = aws_subnet.private_a id = "subnet-0def456" }
# ... 20-30 resources per batch ...
```
```bash
terraform plan -generate-config-out=batch1_generated.tf
# Careful manual review of every generated resource against actual AWS console settings
terraform apply    # state-only, no resource impact
terraform plan      # MUST be zero-diff before proceeding to batch 2
```

### Under-the-Hood Explanation
Every resource being imported is entirely unaffected by the import process itself — `import` blocks populate state via the `ImportResourceState` provider RPC, which is a read-only operation from the perspective of the actual AWS resource; nothing about the resource's real configuration changes until a subsequent `terraform apply` proposes an actual create/update/destroy operation. This is precisely why the "zero tolerance for disruption" requirement is achievable here: the entire multi-week, 300-resource adoption process can proceed with zero risk to running production systems, since no resource is ever modified, only observed and recorded into Terraform's state.

### Common Weak Answer
"Write Terraform configuration from scratch based on what the team remembers about the setup, then import to match."

### Why the Weak Answer Fails
Relying on team memory for 300 resources' worth of configuration across five years is unreliable and slow compared to discovering the actual, current configuration directly from AWS via automated scanning plus `-generate-config-out`, which reflects ground truth rather than potentially-outdated or incomplete institutional memory — the generated-then-reviewed approach is both faster and more accurate for a system this large with no existing documentation.

### Follow-Up Questions
1. How would you handle resources that were created five years ago using settings/API versions that are now deprecated or behave differently under current provider versions?
2. How would you prioritize the 300 resources into batches — by dependency order alone, or also factoring in business criticality?
3. What governance changes would you put in place after this adoption to actually prevent the business unit from reverting to ClickOps for future changes?

### Key Interview Signals
Confirms the candidate designs a methodical, safety-first (import-only, zero-diff-validated), appropriately-tooled approach for a large-scale, no-existing-IaC adoption, and thinks about the post-migration governance needed to make the change durable rather than treating this as a one-time technical exercise.

### Hands-On Connection
[Lab 6 — Import Existing Infrastructure](../labs/lab-06-import-existing-infrastructure/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
