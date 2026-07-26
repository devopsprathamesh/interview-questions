# Category 5: AWS Infrastructure Design

Questions 43–52 of 120. Category weight: 10 questions. Deep-dive reference: [`docs/terraform-architecture.md`](../docs/terraform-architecture.md).

---

## Question 43: A hundred accounts, several regions, one Terraform estate

### Scenario
Your company operates roughly 100 AWS accounts (organized by business unit and environment) across three regions, all managed by a central platform team of six engineers, with dozens of application teams consuming shared platform modules.

### Interview Question
Design the complete Terraform architecture: provider strategy, state separation, pipeline design, and governance.

### Strong Senior-Level Answer
**Initial assessment:** this is fundamentally a scale problem requiring every architectural pattern in the enterprise playbook working together — no single mechanism solves it; it's the composition that matters.

**Technical reasoning:** provider aliasing/assume-role handles *targeting* the right account+region; state separation handles *blast radius*; pipeline parameterization handles *repeatability without hand-maintained duplication*; policy-as-code handles *governance at scale without a six-person team manually reviewing every change*.

**Investigation process:** map the actual ownership structure — which teams own which accounts, what's genuinely shared (networking, IAM baseline, logging) versus application-specific, and what regions genuinely need active infrastructure versus DR-only.

**Recommended solution:** a landing-zone-based account structure (Control Tower or custom-built account vending, see [`terraform-architecture.md` §8](../docs/terraform-architecture.md#8-multi-account-strategies-landing-zones-and-account-vending)) with a layered state architecture — a foundation layer (per-account baseline: IAM, core networking, security tooling) deployed via a pipeline matrix parameterized by account ID and region, a platform layer for genuinely shared services, and per-application-team states for everything else. Provider configuration uses one central CI identity assuming narrowly-scoped roles per account+region (see [Question 36](04-providers.md#question-36-one-module-two-regions-at-the-same-time) and [Diagram 8](../diagrams/08-multi-account.md)). Governance is enforced two ways: SCPs at the AWS Organizations level (non-negotiable, can't be bypassed by any Terraform misconfiguration) and policy-as-code (OPA/Conftest) in every pipeline as a pre-apply gate — six platform engineers cannot manually review changes across 100 accounts, so guardrails must be structural, not review-based.

**Risk controls:** every application team's pipeline can only assume into their own account(s); cross-account access for anything shared routes through explicit, narrowly-scoped roles, never a single god-mode credential.

**Validation steps:** a new account, once vended, should pass automated conformance checks (SCPs applied, baseline logging/security tooling present, state backend correctly bootstrapped) before any application team is handed access — this is itself a Terraform-driven, testable pipeline step.

**Rollback or recovery strategy:** because state is separated by account/layer, a bad change in one application team's state cannot affect another's; foundation-layer changes (rarer, higher-impact) get their own stricter approval gate and more conservative rollout (e.g., one region/account at a time, not all 100 simultaneously).

**Long-term prevention:** the six-person platform team's actual leverage comes from owning the shared modules, the account-vending pipeline, and the policy set — not from manually reviewing every one of the potentially hundreds of weekly changes across 100 accounts; the entire design should be evaluated against "does this scale platform-team effort sub-linearly with the number of accounts/teams."

### Step-by-Step Implementation
```hcl
# Pipeline matrix parameterizing account + region against one tested module set
# (conceptual GitHub Actions matrix)
strategy:
  matrix:
    account: [business-unit-a-prod, business-unit-a-staging, business-unit-b-prod, ...]
    region: [us-east-1, eu-west-1, ap-southeast-1]
```
```hcl
provider "aws" {
  alias  = "target"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/terraform-execution"
  }
}

module "foundation" {
  source    = "app.terraform.io/my-org/foundation/aws"
  version   = "~> 2.0"
  providers = { aws = aws.target }
  account_id = var.account_id
  region     = var.region
}
```

### Under-the-Hood Explanation
Nothing here is a new Terraform mechanism — it's the composition of provider aliasing (§2 of `terraform-architecture.md`), state-per-layer-per-account separation (§7), and CI matrix execution (§ of `cicd.md`) applied at genuine scale. The graph/plan/apply mechanics for any single account+region combination are identical to a single-account setup; the architecture's job is ensuring each combination gets its own independent graph/plan/apply/state, never a shared one.

### Common Weak Answer
"Use a `for_each` loop over a list of accounts in one big configuration."

### Why the Weak Answer Fails
A single configuration looping over 100 accounts in one state produces exactly the monolithic-state blast-radius problem from [Question 15](02-state-management.md#question-15-the-plan-that-took-twenty-minutes) at even worse scale — one typo threatens all 100 accounts' foundational infrastructure simultaneously, and the plan/lock/blast-radius properties are the opposite of what's needed here.

### Follow-Up Questions
1. How would you roll out a foundation-layer change (e.g., a new mandatory security tool) across all 100 accounts safely, given they're in separate states?
2. How does your design change if one specific business unit has materially different compliance requirements (e.g., FedRAMP) than the rest?
3. How do you handle a scenario where an application team needs a genuinely new AWS service enabled that SCPs currently block — what's the exception process?

### Key Interview Signals
Tests whether the candidate can compose multiple architectural patterns coherently at real scale, and specifically recognizes that a six-person platform team's model must scale via structure (guardrails, automation) rather than manual effort (review, tribal knowledge).

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 44: The mesh nobody could keep in their head

### Scenario
As your account count grew from 10 to 40 over two years, cross-account networking was built incrementally via direct VPC peering connections, added one pair at a time whenever a new need arose. There are now 68 peering connections, several route tables with dozens of entries, and no one is fully confident they understand the complete connectivity picture anymore.

### Interview Question
Would you migrate this to AWS Transit Gateway, and how would you plan that migration without a network outage?

### Strong Senior-Level Answer
**Initial assessment:** yes — VPC peering doesn't transit (no "hub" routing), so N accounts needing full connectivity requires up to N(N-1)/2 peering connections, which is exactly the unmanageable growth curve described; Transit Gateway centralizes routing through one hub, turning an O(N²) connection problem into an O(N) one.

**Technical reasoning:** the migration itself is additive and reversible if sequenced correctly — Transit Gateway attachments can be added alongside existing peering connections, with route tables gradually shifted from peering-based routes to TGW-based routes account by account, rather than a single cutover.

**Investigation process:** first, actually document the current state programmatically — enumerate every peering connection and every route table entry via the AWS API (not tribal knowledge) to build the authoritative "what actually needs to keep working" baseline before touching anything.

**Recommended solution:** provision the Transit Gateway and attach accounts incrementally (starting with the least-critical/most-isolated accounts as a proof of the migration pattern), adding TGW routes alongside (not replacing) existing peering routes initially, verifying connectivity still works via both paths, then removing the now-redundant peering connection and its routes for that account pair once TGW routing is confirmed working — repeating account by account until all 68 peering connections are retired.

**Risk controls:** never remove a peering connection until its TGW-based replacement route has been actively verified (a real connectivity test, not just "the route table looks right") for that specific account pair's actual traffic patterns.

**Validation steps:** for each migrated account, run actual connectivity tests (not just route table inspection) between it and every account it's supposed to reach, both before and after removing the old peering route, to catch any traffic pattern the route-table review missed.

**Rollback or recovery strategy:** since old peering connections remain in place until explicitly removed, any account's migration can be rolled back trivially by re-adding its removed route (or simply not yet removing it) if TGW routing shows an unexpected issue — this incremental, dual-path approach is the rollback strategy, not a separate plan.

**Long-term prevention:** once fully migrated, enforce (via policy-as-code) that no new direct peering connections are created going forward — all new account connectivity goes through the Transit Gateway by default, preventing the mesh from regrowing.

### Step-by-Step Implementation
```hcl
resource "aws_ec2_transit_gateway" "main" {
  description = "Central hub for inter-account connectivity"
}

resource "aws_ec2_transit_gateway_vpc_attachment" "account_a" {
  provider           = aws.account_a
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.account_a.id
  subnet_ids         = data.aws_subnets.account_a_tgw.ids
}

# Add TGW route alongside existing peering route (both active during migration)
resource "aws_route" "via_tgw" {
  route_table_id         = data.aws_route_table.account_a_private.id
  destination_cidr_block = "10.20.0.0/16"   # account_b's CIDR
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}
# Only after verified: remove the corresponding peering route and connection
```

### Under-the-Hood Explanation
VPC peering connections are point-to-point and non-transitive by design (AWS explicitly does not route through a peering connection to reach a third VPC) — this is exactly why full mesh connectivity for N accounts requires pairwise connections. Transit Gateway is itself a managed routing device each VPC attaches to once; route tables at the TGW level (separate from each VPC's own route tables) determine which attachments can reach which, centralizing what was previously N² independent route-table configurations into one hub's routing policy.

### Common Weak Answer
"Just add a network diagram tool to keep track of the peering connections better."

### Why the Weak Answer Fails
Better documentation doesn't fix the underlying architectural scaling problem (O(N²) connections) — it only makes an already-unmanageable structure slightly easier to look at; the actual fix is architectural (hub-and-spoke via Transit Gateway), not observational.

### Follow-Up Questions
1. How would you handle overlapping CIDR ranges discovered during this migration, between accounts that were never expected to need to talk to each other?
2. What's the cost trade-off between Transit Gateway data-processing charges and the peering connections it replaces — how would you model that before migrating?
3. How would you extend this to multi-region connectivity, where Transit Gateway peering between regions is itself a distinct concept?

### Key Interview Signals
Tests architectural judgment about when to invest in a hub-and-spoke redesign, and whether the candidate can plan a genuinely safe, incremental, dual-path migration rather than proposing a risky simultaneous cutover.

### Hands-On Connection
[Lab 8 — AWS Networking Platform](../labs/lab-08-aws-networking/).

---

## Question 45: Account creation shouldn't be a ticket

### Scenario
Currently, provisioning a new AWS account for an application team takes roughly three weeks: a platform engineer manually creates the account, manually applies a baseline set of IAM roles and SCP attachments, manually sets up the Terraform state bucket, and manually grants the requesting team access — with inconsistent results between accounts because the manual steps aren't always followed identically.

### Interview Question
Design an automated account-vending pipeline to fix this.

### Strong Senior-Level Answer
**Initial assessment:** the three-week timeline and inconsistency are both symptoms of the same root cause — an entirely manual, non-repeatable process standing in for what should be a deterministic, Terraform-driven pipeline.

**Technical reasoning:** account vending should itself be a Terraform-managed process (or, for the actual account-creation API call, AWS Organizations/Control Tower Account Factory, wrapped by Terraform for everything else) producing every new account with an identical, guaranteed baseline — no manual step that can be skipped or done slightly differently each time.

**Investigation process:** enumerate every manual step currently performed and classify each as either genuinely one-time/human-judgment (approving the request, choosing the business unit) or mechanical/repeatable (creating the account, attaching SCPs, bootstrapping the state bucket, creating baseline IAM roles) — the mechanical ones are the automation target.

**Recommended solution:** build a pipeline triggered by a lightweight request (a PR against an "accounts" repository adding one new account definition, reviewed and approved by a human for the judgment-call parts) that then automatically: creates the account via AWS Organizations, attaches the correct OU/SCPs, bootstraps that account's Terraform state backend (see [Question 18 in category 2](02-state-management.md#question-18-bootstrapping-the-backend-that-doesnt-exist-yet)), applies baseline IAM roles (including the OIDC-federated CI execution role), and grants the requesting team's CI identity access to assume into it — all via one deterministic Terraform apply per new account.

**Risk controls:** run automated conformance checks against every newly-vended account (SCPs present, baseline logging/security tooling active, state backend correctly configured) before marking it ready for handoff — catching any pipeline failure or partial-provisioning issue before a team starts building on top of an incomplete account.

**Validation steps:** the conformance check suite itself should be the acceptance criteria for "this account is ready" — not a human eyeballing it.

**Rollback or recovery strategy:** if account vending fails partway (e.g., SCP attachment succeeds but state bucket bootstrap fails), the pipeline should be idempotent/resumable — re-running it should complete the remaining steps rather than requiring manual cleanup, exactly like any other Terraform apply's partial-failure handling.

**Long-term prevention:** treat the account-vending pipeline itself as a Tier-1 piece of infrastructure with its own tests, monitoring, and change-review discipline — since every future account's baseline security posture depends entirely on this pipeline behaving correctly and consistently.

### Step-by-Step Implementation
```hcl
# accounts/business-unit-c-prod.tf — the lightweight request, reviewed via PR
module "account" {
  source        = "app.terraform.io/my-org/account-vending/aws"
  version       = "~> 3.0"
  account_name  = "business-unit-c-prod"
  business_unit = "business-unit-c"
  environment   = "production"
  ou            = "Workloads/Production"
}
```
```hcl
# Inside the account-vending module: deterministic baseline for every account
resource "aws_organizations_account" "this" { /* ... */ }
resource "aws_organizations_policy_attachment" "scp" { /* baseline SCPs */ }
module "state_backend_bootstrap" { /* per Question 18 pattern */ }
module "baseline_iam" { /* CI execution role, OIDC trust, break-glass role */ }
```
```bash
# Post-vending conformance check (part of the same pipeline)
./scripts/conformance-check.sh business-unit-c-prod
```

### Under-the-Hood Explanation
This is entirely an orchestration/automation architecture question rather than a new Terraform mechanism — the interesting internal detail is that the account-vending module's own state (tracking which accounts have been vended and their configuration) is itself a foundation-layer state (see [`terraform-architecture.md` §7](../docs/terraform-architecture.md#7-layered-deployment-architecture)), meaning adding a new account is a normal, reviewable `terraform apply` against the vending pipeline's own state, not a special out-of-band process.

### Common Weak Answer
"Write a detailed runbook so the manual steps are followed more consistently."

### Why the Weak Answer Fails
A better runbook still requires a human to correctly execute every step every time — it reduces but doesn't eliminate the inconsistency risk, and does nothing for the three-week timeline; the actual fix is removing the human from the mechanical, repeatable steps entirely.

### Follow-Up Questions
1. How would you handle a business unit that needs a materially different baseline (different SCPs, different compliance tooling) than the standard template?
2. What conformance checks specifically would you run before marking a new account "ready," and how would you automate them?
3. How does this pipeline change if you need to support both AWS Control Tower's native Account Factory and a fully custom Terraform-only approach?

### Key Interview Signals
Confirms the candidate identifies manual, inconsistent processes as an automation target and designs the vending pipeline itself as real, tested, Tier-1 infrastructure, not a one-off script.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 46: The SCP that saved an accidental account-wide S3 policy

### Scenario
A newly onboarded application team's Terraform configuration, still finding its footing, includes a bug that would have set an S3 bucket policy allowing public read access. The apply fails — not from a Terraform error, but from an AWS API-level `AccessDenied` referencing an Organizations Service Control Policy.

### Interview Question
Explain what just happened and why this is a feature, not an obstacle for the team to work around.

### Strong Senior-Level Answer
**Initial assessment:** an SCP attached at the Organizational Unit level is blocking the specific API action (likely `s3:PutBucketPolicy` with a public-access condition, or the account's S3 Block Public Access settings are enforced and can't be disabled) — this is the account-level guardrail working exactly as designed, catching a mistake that any single application team's own review process might have missed.

**Technical reasoning:** SCPs are evaluated by AWS IAM as an additional, non-bypassable permission boundary on top of whatever IAM policies the calling role has — even a role with full `s3:*` permissions cannot perform an action an SCP explicitly denies, which is precisely why this control doesn't depend on the application team's own Terraform code, module, or CI pipeline being correctly configured.

**Investigation process:** confirm from the error message exactly which SCP and which specific action/condition is being denied, and confirm this genuinely reflects an unintended configuration (public bucket access) rather than a legitimate, if rare, need that the SCP is incorrectly blocking.

**Recommended solution:** since this is confirmed to be an actual mistake (not a legitimate exception), the fix is simply correcting the application team's Terraform configuration — remove whatever was granting public access — and let the corrected plan apply cleanly. No SCP change needed, since it did its job correctly.

**Risk controls:** this incident is a good opportunity to add the same check as a *pre-apply* signal too (a policy-as-code/Conftest rule catching public-bucket-policy patterns at plan-review time, per [`security.md` §9](../docs/security.md#9-policy-as-code)) so the team gets fast feedback in their PR rather than discovering the mistake only at apply time via an AWS-level denial — SCPs are the last line of defense, not the primary feedback mechanism.

**Validation steps:** after correcting the configuration, confirm the plan/apply succeeds and, separately, confirm (in a non-prod test) that a deliberately-reintroduced public-access attempt is still blocked by the SCP, proving the guardrail remains active.

**Rollback or recovery strategy:** not applicable — nothing was actually created; the SCP prevented the mistake from ever reaching a real, applied state.

**Long-term prevention:** treat this as validating the layered-defense design (§10 in `security.md`) rather than an obstacle — the correct organizational response is congratulating the guardrail for working, adding the earlier-feedback policy-as-code check, and using the incident as a training moment for the new team about what patterns SCPs in this org block and why.

### Step-by-Step Implementation
```bash
# The actual AWS-level error the apply produces
# Error: error putting S3 policy: AccessDenied: User: arn:aws:sts::.../terraform-execution
#   is not authorized to perform: s3:PutBucketPolicy with an explicit deny in a service control policy
```
```hcl
# Corrected application configuration (remove the unintended public grant)
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```
```rego
# Earlier-feedback Conftest policy, catching the same class of mistake at plan-review time
deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket_policy"
  contains(resource.change.after.policy, "\"Principal\": \"*\"")
  msg := sprintf("%s: public bucket policy is not allowed", [resource.address])
}
```

### Under-the-Hood Explanation
SCPs operate at the AWS Organizations layer, evaluated *before* any IAM policy evaluation for the calling principal — even an administrator-equivalent role in the account is subject to an SCP's explicit deny, because SCPs define the maximum possible permissions available within an account/OU, with IAM policies only able to grant a subset of that ceiling, never exceed it. This is precisely why SCPs function as a guardrail independent of any individual team's Terraform code quality, module choice, or IAM policy correctness — the constraint is enforced at the account boundary itself, not at the resource-configuration layer.

### Common Weak Answer
"The SCP is blocking our deployment — we need to get it loosened so we can proceed."

### Why the Weak Answer Fails
This treats the guardrail catching a real mistake as an obstacle to route around rather than recognizing it did exactly its job; the correct response is fixing the underlying misconfiguration, not requesting a broader SCP exception to bypass a control that just prevented a legitimate security incident.

### Follow-Up Questions
1. How would you distinguish a case where an SCP is genuinely blocking a legitimate, needed action from a case like this one where it's correctly blocking a mistake?
2. What's the exception process for a genuinely legitimate need that an org-wide SCP currently blocks?
3. How would you design a policy-as-code check to catch this class of mistake even earlier, before the pipeline ever attempts the apply?

### Key Interview Signals
Confirms the candidate treats SCP denials as a signal to investigate and likely fix their own configuration first, not as friction to escalate around, and understands the layered-defense reasoning behind having both SCPs and policy-as-code.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 47: The NAT gateway bill nobody explained

### Scenario
A monthly cost review shows NAT gateway data-processing charges have tripled over two months, spread unevenly across a dozen accounts, with no corresponding increase in reported application traffic that anyone can point to.

### Interview Question
How would you investigate this using your Terraform-managed infrastructure as a starting point, and how would you prevent this class of cost surprise going forward?

### Strong Senior-Level Answer
**Initial assessment:** NAT gateway costs scale with both hourly uptime (fixed per-NAT charge) and data processed through it (variable) — a tripling with no application-traffic increase points either to a new source of NAT-routed traffic (a new service, a misconfigured route sending traffic through NAT that shouldn't need to), or a change in how many NAT gateways exist/are used.

**Investigation process:** first, use Terraform's own configuration as an audit trail — `terraform state list` across the affected accounts to check whether the *number* of NAT gateways increased (e.g., a module change accidentally moved from one-NAT-per-VPC to one-NAT-per-AZ, tripling gateway count in multi-AZ VPCs) — this is directly checkable from state/config history via `git log` on the networking module. Separately, check AWS Cost Explorer / VPC Flow Logs for the actual traffic composition through the NAT gateways to identify what's actually driving data-processing charges (e.g., unexpected large data transfers, container image pulls that could instead go through a VPC endpoint).

**Recommended solution:** if the cause is a new source of legitimate but avoidable NAT-routed traffic (a common one: ECR/S3 pulls from private subnets routing through NAT instead of VPC endpoints), add the relevant Gateway/Interface VPC endpoints (S3 and DynamoDB use free Gateway endpoints; ECR, CloudWatch Logs, etc. use paid-but-usually-cheaper Interface endpoints) to route that traffic off the NAT gateway entirely. If the cause is an accidental gateway-count increase from a module change, revert to the correct one-per-AZ-only-where-needed pattern and confirm cost normalizes.

**Risk controls:** for any environment where cost sensitivity is high (dev/staging especially), consider a cost-conscious alternative to per-AZ NAT gateways — a single shared NAT gateway (accepting the AZ cross-traffic/availability trade-off explicitly) or NAT instances for genuinely low-traffic environments, documented as a deliberate cost/availability trade-off, not an oversight.

**Validation steps:** after adding VPC endpoints, compare NAT gateway data-processing charges for the following billing cycle against the baseline to confirm the fix actually reduced cost as predicted, not just theoretically should have.

**Rollback or recovery strategy:** VPC endpoint additions are non-disruptive and additive (routes prefer the endpoint automatically for supported services once created) — no rollback risk; a gateway-count revert (from per-AZ back to shared) needs the standard careful multi-AZ networking change review given the availability trade-off it reintroduces.

**Long-term prevention:** add a cost-anomaly alert (AWS Cost Anomaly Detection or a custom CloudWatch billing alarm) scoped to NAT gateway data-processing specifically, so a tripling like this triggers investigation within days, not at the next monthly review; and add VPC endpoints for S3/ECR/CloudWatch as a standard, default part of your networking module for every new environment, rather than an afterthought added reactively.

### Step-by-Step Implementation
```bash
# Check for a gateway-count change via git history on the networking module
git log --oneline -p -- modules/vpc/nat.tf | grep -A5 'resource "aws_nat_gateway"'

# Check actual traffic composition via VPC Flow Logs / Cost Explorer
aws ce get-cost-and-usage --time-period Start=2026-05-01,End=2026-07-01 \
  --granularity MONTHLY --metrics "UsageQuantity" \
  --filter '{"Dimensions":{"Key":"USAGE_TYPE","Values":["NatGateway-Bytes"]}}'
```
```hcl
# Add VPC endpoints to route common services off NAT entirely
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type  = "Gateway"
  route_table_ids    = aws_route_table.private[*].id
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}
```

### Under-the-Hood Explanation
NAT gateways bill on both a fixed hourly rate and per-GB data processed; VPC Gateway endpoints (S3, DynamoDB) and Interface endpoints (most other AWS services) provide a route directly to the AWS service's API from within the VPC without traversing the NAT gateway at all — Terraform's role here is straightforward resource creation, but the cost-architecture insight (which traffic *should* be routable via an endpoint versus what genuinely needs general internet egress through NAT) is what actually drives the fix, verifiable by inspecting the route tables Terraform manages.

### Common Weak Answer
"Add more NAT gateways to spread out the load and reduce the per-gateway cost."

### Why the Weak Answer Fails
NAT gateway cost is driven by total data processed and gateway-hours, not per-gateway congestion — adding more gateways doesn't reduce total data-processing charges (it may increase the fixed hourly component) and does nothing to address the actual root cause, whether that's excess non-essential traffic or an accidental gateway-count increase.

### Follow-Up Questions
1. How would you weigh the cost savings of VPC endpoints against the added complexity (DNS resolution behavior, security group configuration) they introduce?
2. What's your approach to cost allocation/tagging so a future cost spike can be attributed to a specific team/account faster than this investigation took?
3. How would this investigation differ if the cost increase were concentrated in a single account versus spread across a dozen, as in this scenario?

### Key Interview Signals
Confirms the candidate can connect Terraform-managed infrastructure (state, git history, route tables) to a cost investigation methodically, and knows concrete AWS cost-reduction mechanisms (VPC endpoints) rather than generic "optimize costs" hand-waving.

### Hands-On Connection
[Lab 8 — AWS Networking Platform](../labs/lab-08-aws-networking/).

---

## Question 48: Egress for everyone, managed by no one team twice

### Scenario
Forty application accounts each currently provision their own NAT gateways, their own DNS resolver configuration, and their own security tooling VPC endpoints independently — meaning forty near-identical, independently-maintained copies of what is fundamentally shared, non-differentiated infrastructure.

### Interview Question
Design a shared-services architecture to centralize this.

### Strong Senior-Level Answer
**Initial assessment:** this is exactly the kind of non-differentiated, purely-infrastructural concern that belongs in a shared-services account, not replicated forty times — the duplication provides no actual isolation benefit (these aren't security-sensitive per-application concerns) while multiplying maintenance burden and cost by forty.

**Technical reasoning:** centralize NAT/egress and shared endpoint access in a dedicated shared-services (or "network") account, with application accounts' private subnets routing egress traffic to the shared account via Transit Gateway, rather than each account maintaining its own NAT gateways.

**Investigation process:** confirm which of the forty accounts' current NAT/DNS/endpoint configurations are genuinely identical (the expected common case) versus have some special per-account variation (rare, but worth identifying before assuming a one-size-fits-all centralization works for literally every account).

**Recommended solution:** provision NAT gateways once in a shared-services account's VPC, attach every application account's VPC to the same Transit Gateway, and route each application account's private-subnet egress traffic through the TGW to the shared account's NAT gateways. Centralize Route 53 Resolver rules and commonly-needed Interface VPC endpoints (ECR, CloudWatch Logs, Secrets Manager) in the shared account as well, exposed to application accounts via Resolver rule association and TGW-routed endpoint access respectively, rather than each account provisioning its own copies.

**Risk controls:** the shared-services account/VPC becomes a genuine single point of failure for egress across all forty accounts — size and monitor it accordingly (NAT gateway bandwidth limits, health checks, potentially redundant NAT gateways per AZ within the shared account) since its blast radius is now organization-wide for this specific concern.

**Validation steps:** after migrating each account, confirm egress connectivity and DNS resolution work correctly, and confirm the account's own now-redundant NAT gateways/endpoints can be safely decommissioned (cost savings realized) only after traffic is confirmed flowing through the shared path.

**Rollback or recovery strategy:** migrate one account at a time, keeping its own NAT gateway in place (unused, on standby) until the shared-path routing is verified working, so a single account's routing issue doesn't require an emergency shared-services change — it can just revert that one account's route back to its own NAT gateway.

**Long-term prevention:** once centralized, prevent regression by ensuring the standard application-account Terraform module template no longer includes NAT gateway provisioning at all — egress becomes something new accounts get automatically via the account-vending pipeline's TGW attachment, not something individual teams configure themselves.

### Step-by-Step Implementation
```hcl
# Shared-services account: centralized NAT + TGW
resource "aws_nat_gateway" "shared" {
  count         = length(var.availability_zones)
  subnet_id     = aws_subnet.shared_public[count.index].id
  allocation_id = aws_eip.nat[count.index].id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.shared.id
  subnet_ids         = aws_subnet.shared_tgw[*].id
}
```
```hcl
# Application account: route private-subnet egress via TGW to shared NAT
resource "aws_route" "egress_via_shared" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = data.aws_ec2_transit_gateway.main.id
}
# Application account's own NAT gateway resource removed from the module entirely
# once migration for this account is confirmed
```

### Under-the-Hood Explanation
Transit Gateway routing lets an application account's default route point at the TGW instead of a local NAT gateway; the TGW then forwards that traffic to the shared-services account's attachment, where it exits via the centrally-managed NAT gateways — from each application VPC's perspective, egress "just works" identically to before, but the actual NAT infrastructure (and its cost/maintenance) exists once, centrally, rather than forty times.

### Common Weak Answer
"Just write better documentation so all forty teams configure their NAT gateways consistently."

### Why the Weak Answer Fails
Even perfectly consistent configuration across forty accounts still means forty times the cost and forty independent things to patch/monitor/upgrade — documentation doesn't address the actual duplication of genuinely non-differentiated infrastructure; centralization is the structural fix.

### Follow-Up Questions
1. How do you size the shared-services NAT gateways' bandwidth capacity to handle aggregate traffic from forty accounts without becoming a bottleneck?
2. What's your monitoring/alerting strategy given this account is now a single point of failure for egress across the organization?
3. How would you handle an application account that has a genuine, unusual need to bypass the shared egress path (e.g., a dedicated, isolated compliance requirement)?

### Key Interview Signals
Confirms the candidate recognizes non-differentiated infrastructure duplicated across many accounts as a centralization opportunity, and thinks concretely about the availability/blast-radius trade-off that centralizing introduces.

### Hands-On Connection
[Lab 8 — AWS Networking Platform](../labs/lab-08-aws-networking/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 49: One application, two regions, zero downtime during a regional event

### Scenario
A customer-facing application currently runs only in `us-east-1`. Leadership requires it to survive a full regional outage with near-zero downtime and near-zero data loss, given its revenue criticality.

### Interview Question
Design the multi-region Terraform architecture and deployment approach — not just the AWS services involved, but how Terraform manages it.

### Strong Senior-Level Answer
**Initial assessment:** near-zero RTO/RPO requirements point to an active/active (or at minimum hot warm-standby) architecture, not backup/restore or pilot light (see [`ha-dr.md` §2](../docs/ha-dr.md#2-dr-strategies-and-their-terraform-deployment-implications)) — the Terraform-architecture implication is that both regions need continuously-applied, live infrastructure, not a "deploy when needed" runbook.

**Technical reasoning:** the same module set (application compute, ALB, data layer) is parameterized by region via provider aliasing and deployed to both regions continuously through a pipeline matrix (see [Question 36](04-providers.md#question-36-one-module-two-regions-at-the-same-time) and [Diagram 9](../diagrams/09-multi-region.md)), each region maintaining its own independent state so a bad deploy or outage in one region cannot affect the other.

**Investigation process:** identify the data layer's actual replication mechanism and its real RPO — this is usually the limiting factor, not the compute/networking layer, which can be made stateless and multi-region relatively easily; a database using asynchronous cross-region replication (RDS cross-region read replica, DynamoDB Global Tables) has a real (if small) replication lag that constrains your actual achievable RPO regardless of how well the infrastructure layer is designed.

**Recommended solution:** stateless application tiers deployed identically to both regions via the same module set; DynamoDB Global Tables (near-zero RPO, multi-master) or RDS with cross-region read replicas (promoted during failover, with the associated RPO gap and promotion time factored into the design) for the data layer, depending on the actual database engine constraints; Route 53 with health-check-based failover routing (or latency-based routing for genuine active/active traffic distribution) to direct traffic to healthy regions automatically. Crucially: the **state backend** itself must not be a single-region dependency — replicate the state bucket cross-region (S3 Cross-Region Replication) so Terraform itself remains operable against either region during a regional event affecting the primary state bucket's region.

**Risk controls:** run scheduled failover drills (not just architecture reviews) actually shifting production traffic to the secondary region on a controlled schedule, measuring real RTO/RPO against targets — an untested failover path is a hypothesis, not a capability (see [`ha-dr.md` §4](../docs/ha-dr.md#4-hadr-testing--the-gap-between-designed-and-proven)).

**Validation steps:** during a drill, confirm actual application functionality (not just infrastructure health checks) in the secondary region under real traffic, and confirm the state backend replication has kept Terraform itself usable throughout.

**Rollback or recovery strategy:** failback (returning to primary once restored) is its own deliberate, drilled process — including reconciling any data written to the secondary region during the incident window back to primary, which can involve genuine conflict resolution depending on the data layer's replication model.

**Long-term prevention:** treat the DR architecture and its drill cadence as an ongoing operational commitment, not a one-time build — revisit RTO/RPO targets and the architecture's ability to meet them as traffic/data volume grows.

### Step-by-Step Implementation
```hcl
# Same module, two regions, via provider aliasing and a pipeline matrix
module "app_stack" {
  source    = "app.terraform.io/my-org/app-stack/aws"
  version   = "~> 3.0"
  providers = { aws = aws.us_east_1 }
  region    = "us-east-1"
}

module "app_stack_dr" {
  source    = "app.terraform.io/my-org/app-stack/aws"
  version   = "~> 3.0"
  providers = { aws = aws.us_west_2 }
  region    = "us-west-2"
}
```
```hcl
resource "aws_route53_health_check" "primary" { /* ... */ }
resource "aws_route53_record" "app" {
  name    = "app.example.com"
  type    = "A"
  set_identifier = "primary"
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary.id
  # ...
}
```
```bash
# Cross-region state backend replication (part of Lab 2's bootstrap, extended)
aws s3api put-bucket-replication --bucket tf-state-us-east-1 --replication-configuration file://replication.json
```

### Under-the-Hood Explanation
There is no Terraform-native "multi-region" primitive — every resource in every region is created via its own regionally-scoped provider configuration and RPC calls (see [`terraform-internals.md` §9](../docs/terraform-internals.md#9-provider-rpc-communication)), fully independent of the other region's resources at the Terraform-execution level. The actual cross-region behavior (data replication, failover routing) is implemented entirely by the AWS services themselves (DynamoDB Global Tables, Route 53 health checks); Terraform's role is purely declarative provisioning of the resources that make that AWS-native behavior possible, in both regions, kept in sync by using the same module set rather than hand-duplicated configuration.

### Common Weak Answer
"Just deploy the same Terraform to a second region as a backup."

### Why the Weak Answer Fails
"Deploy as a backup" doesn't specify whether the secondary region is actively running (needed for near-zero RTO) or dormant (which would require a slow scale-up, failing the near-zero-downtime requirement), and entirely ignores the data-layer replication/RPO question, which is almost always the actual bottleneck for a near-zero-data-loss requirement.

### Follow-Up Questions
1. How would you handle a database engine that doesn't support the cross-region replication mechanism your near-zero-RPO requirement needs?
2. What's your plan if a failover drill reveals the actual RTO is much higher than the target — what would you investigate first?
3. How does the state-backend cross-region replication interact with locking — could you end up with two regions both believing they can lock/apply during a partition?

### Key Interview Signals
Confirms the candidate connects the business requirement (near-zero RTO/RPO) to concrete architectural choices (active/active vs. warm standby, specific AWS replication mechanisms) and doesn't overlook the state-backend-itself-needs-DR detail that's frequently missed.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 50: Trading NAT gateways for VPC endpoints

### Scenario
A newly-designed VPC architecture is being reviewed before rollout to fifteen new application accounts. The current design has all private-subnet traffic to AWS services (S3, ECR, Secrets Manager, CloudWatch Logs) routing through NAT gateways to reach public AWS API endpoints over the internet gateway.

### Interview Question
Evaluate this design and propose improvements, covering availability, cost, and security trade-offs explicitly.

### Strong Senior-Level Answer
**Initial assessment:** routing AWS-service-bound traffic through NAT/internet gateway when it never needs to leave the AWS network at all is both a cost and security miss — VPC endpoints address both simultaneously for supported services.

**Technical reasoning:** **Cost**: NAT gateway data-processing charges apply to this traffic today; Gateway endpoints (S3, DynamoDB) are free, and Interface endpoints (most other services), while not free, are typically cheaper than the equivalent NAT data-processing charge at any meaningful volume, especially across fifteen accounts. **Security**: traffic to VPC endpoints never traverses the public internet at all, and endpoint policies allow scoping exactly which AWS resources (e.g., only specific S3 buckets, only your organization's ECR repositories) are reachable through the endpoint — a materially tighter security posture than "anything reachable via the internet gateway." **Availability**: Interface endpoints are provisioned per-AZ, so with proper multi-AZ endpoint placement, this design has no worse (and arguably better, since it removes a NAT gateway dependency for this traffic class) availability characteristics than the NAT-routed alternative.

**Investigation process:** enumerate which AWS services this workload actually calls (S3, ECR, Secrets Manager, CloudWatch Logs per the scenario, likely also STS and KMS) and confirm VPC endpoint availability/support for each in the target region.

**Recommended solution:** add a Gateway endpoint for S3 (and DynamoDB if used) at zero additional cost, and Interface endpoints for ECR (both `ecr.api` and `ecr.dkr`), Secrets Manager, CloudWatch Logs, STS, and KMS, each with an endpoint policy scoped to only the resources this workload actually needs; retain NAT gateways only for genuine internet-bound egress that has no AWS-service equivalent (e.g., calling a third-party API).

**Risk controls:** endpoint policies should be scoped restrictively from the start (not left as the default allow-all), since an overly permissive endpoint policy provides the cost/availability benefit without the intended security tightening.

**Validation steps:** after adding endpoints, verify via VPC Flow Logs that the intended traffic actually routes through the endpoints (not still through NAT) and confirm NAT gateway data-processing charges drop correspondingly the following billing cycle.

**Rollback or recovery strategy:** endpoint additions are non-disruptive; if an endpoint policy is scoped too restrictively and blocks legitimate traffic, the fix is loosening that specific policy statement, verified via plan/apply, with no infrastructure recreation involved.

**Long-term prevention:** make this endpoint set (S3, ECR, Secrets Manager, CloudWatch Logs, STS, KMS at minimum) a standard, default part of the shared networking module for every new account, rather than something each of the fifteen new accounts has to independently discover and add.

### Step-by-Step Implementation
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "secretsmanager:GetSecretValue"
      Resource  = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:app/*"
    }]
  })
}
```

### Under-the-Hood Explanation
VPC endpoints work via either route-table entries pointing at the AWS service's backbone (Gateway endpoints, for S3/DynamoDB) or ENIs placed directly in your subnets with private DNS resolving the service's standard hostname to the endpoint's private IP (Interface endpoints, for most other services) — in both cases, traffic to the endpoint never traverses the internet gateway or NAT gateway at all, which is the direct mechanism behind both the cost reduction (no NAT data-processing charge for this traffic) and the security improvement (no public-internet transit, plus endpoint-policy-scoped access).

### Common Weak Answer
"Add VPC endpoints for everything to save money."

### Why the Weak Answer Fails
Too vague — it doesn't distinguish Gateway (free) from Interface (billed per-hour plus data processed, though usually still cheaper than NAT at volume) endpoints, doesn't address the security dimension (endpoint policy scoping) the question explicitly asks for, and doesn't address which services genuinely need internet-bound NAT access versus which have an AWS-native endpoint alternative.

### Follow-Up Questions
1. How would you decide whether an Interface endpoint is actually cheaper than NAT data-processing for a given service, given Interface endpoints also have their own hourly + data charges?
2. What's the availability implication of an Interface endpoint's ENIs being AZ-specific — how do you ensure this doesn't create an AZ-affinity issue?
3. How would you handle a service that doesn't yet have VPC endpoint support in your target region?

### Key Interview Signals
Confirms the candidate can evaluate a networking design across all three requested dimensions (availability, cost, security) concretely, not just recite "VPC endpoints are good practice."

### Hands-On Connection
[Lab 8 — AWS Networking Platform](../labs/lab-08-aws-networking/).

---

## Question 51: The SCP that blocked Terraform itself

### Scenario
After tightening an SCP to restrict which AWS regions can be used (per a new compliance requirement), the platform team's own Terraform CI pipeline starts failing across every account — not because of any resource being created in a disallowed region, but because the pipeline's own `aws sts get-caller-identity`/assume-role calls are being denied.

### Interview Question
Diagnose why a region-restriction SCP would block an operation that isn't even regional in the way you'd expect, and fix it without reopening the compliance gap it was meant to close.

### Strong Senior-Level Answer
**Initial assessment:** some AWS API actions are global/non-regional in nature (IAM, STS, Organizations) but are still evaluated against SCP region-restriction conditions if the SCP's condition logic doesn't correctly account for this — a common, specific mistake when writing region-restriction SCPs is not exempting the handful of inherently-global service calls that legitimate operations (including Terraform's own auth flow) depend on everywhere.

**Technical reasoning:** the SCP's `aws:RequestedRegion` condition likely denies any request not matching the approved region list, but `sts:AssumeRoleWithWebIdentity` (used by OIDC federation) and similar global-service calls may be getting caught by an overly broad deny statement that doesn't carve out the necessary exceptions.

**Investigation process:** read the exact denied action from the CI error message and cross-reference it against the SCP's statements — confirm whether the SCP is missing a `NotAction` exclusion (or an explicit allow) for STS/IAM/Organizations global actions, which several AWS-published SCP examples for region restriction explicitly call out as necessary exceptions.

**Recommended solution:** correct the SCP to exclude the necessary global service actions from the region-restriction deny (following AWS's own documented guidance for region-restriction SCPs, which explicitly lists global services needing exemption), re-test in a non-production OU first, and only then re-apply to the production OU.

**Risk controls:** any SCP change, especially one already once found to have unintended side effects, should be tested against a representative non-production account/OU before being rolled out organization-wide again — this incident is itself the argument for that discipline going forward.

**Validation steps:** confirm the corrected SCP still blocks a deliberate test attempt to create a resource in a disallowed region (proving the actual compliance intent still holds) while allowing the CI pipeline's OIDC/STS flow to succeed again.

**Rollback or recovery strategy:** if the corrected SCP can't be validated quickly enough and CI is fully blocked organization-wide, temporarily roll back to the pre-tightening SCP version while the corrected version is properly tested, rather than leaving every pipeline broken for an extended period — but treat this as genuinely temporary, with a committed timeline to re-apply the corrected, tested version.

**Long-term prevention:** maintain a tested, version-controlled SCP change process (SCPs as code, reviewed via PR, tested in a non-prod OU) exactly like any other high-blast-radius Terraform change, rather than applying SCP edits directly in the AWS Organizations console.

### Step-by-Step Implementation
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "NotAction": [
      "iam:*", "organizations:*", "route53:*", "sts:*",
      "support:*", "trustedadvisor:*", "waf-regional:*"
    ],
    "Resource": "*",
    "Condition": {
      "StringNotEquals": {
        "aws:RequestedRegion": ["us-east-1", "eu-west-1"]
      }
    }
  }]
}
```
```bash
# Test in a non-prod OU first
terraform -chdir=test-account/ plan   # confirm CI auth succeeds
# Deliberately attempt an out-of-region resource to confirm the restriction still holds
```

### Under-the-Hood Explanation
SCP condition evaluation applies to every API call made under an account in the affected OU, including calls to inherently-global AWS services (IAM, STS, Organizations, Route 53) that don't have a "true" region in the way EC2/S3/RDS calls do — a region-restriction SCP using a blunt `"Action": "*"` deny (rather than a scoped `NotAction` exemption list) will catch these global-service calls too, because AWS still tags them with *some* region value (often the request's originating endpoint region) that the condition then evaluates against, producing exactly this class of unintended, hard-to-predict denial.

### Common Weak Answer
"Remove the region-restriction SCP since it's breaking things."

### Why the Weak Answer Fails
This abandons the actual compliance requirement the SCP was introduced to satisfy, reopening the exact gap it was meant to close, in order to fix a scoping mistake that has a well-documented, narrow correction (exempting global services) without needing to remove the control entirely.

### Follow-Up Questions
1. How would you have caught this scoping issue before rolling the SCP out to every production account?
2. What other global AWS services might need similar exemptions that aren't obvious until something breaks?
3. How would you design a test suite specifically for SCP changes, analogous to policy tests for OPA/Conftest rules?

### Key Interview Signals
Confirms the candidate can reason precisely about SCP condition evaluation against global vs. regional service calls, and defaults to fixing the scoping mistake rather than abandoning the compliance control.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 52: Splitting the account that did everything

### Scenario
A three-year-old startup-turned-scale-up has a single flat AWS account containing every environment (dev, staging, production) and every application, all managed by one enormous Terraform state, with no SCPs, no account-level isolation, and no landing zone at all — the natural result of moving fast early on. Leadership now wants a proper multi-account structure.

### Interview Question
Design the migration from this single flat account to a proper landing-zone architecture, with minimal disruption to the still-operating production system.

### Strong Senior-Level Answer
**Initial assessment:** this combines two of the hardest problems already covered individually — state splitting (Question 15) and multi-account architecture (Question 43) — but now with the added constraint that production is live and cannot be disrupted during the migration.

**Technical reasoning:** AWS resources cannot be moved between accounts directly for most resource types (there's no "move this EC2 instance to another account" API) — the practical approach for most compute/application resources is provisioning fresh in the new target accounts and cutting traffic over, not a live migration of the same resource IDs; a smaller subset of resources (some S3 buckets, IAM-independent data) may support account-to-account transfer via snapshotting/copying.

**Investigation process:** inventory the current single account's resources by intended environment/application, identifying which are genuinely production-critical (needing careful, low-disruption handling) versus dev/staging (which can tolerate a faster, more disruptive migration since they're not customer-facing).

**Recommended solution:** stand up the new landing zone (management account, OUs, SCPs) and account-vending pipeline first, entirely separate from the existing flat account — this has zero impact on current production. Migrate dev and staging environments first (lower risk, validates the whole migration pattern) by provisioning fresh infrastructure in new dev/staging accounts via the same Terraform modules, redirecting non-production traffic/DNS once validated, and decommissioning the old dev/staging resources in the flat account. For production, use a blue-green approach at the account level: provision the full production stack fresh in a new production account (parallel to, not replacing, the existing one), validate it thoroughly (including a real data-layer cutover plan — likely the hardest part, requiring database replication/migration strategy specific to the data layer in use), and only then perform a deliberate, monitored traffic cutover (DNS/load balancer level) from the old flat-account production resources to the new dedicated production account, keeping the old resources on standby for a defined rollback window before finally decommissioning them.

**Risk controls:** never attempt an in-place "convert this account into part of the landing zone" approach for production — always provision fresh in a properly-isolated new account and cut over deliberately, since the entire point is escaping the flat account's lack of isolation, which an in-place conversion wouldn't actually achieve.

**Validation steps:** for the production cutover specifically, validate the new production account's full stack under realistic load (not just a smoke test) before cutting real traffic over, and confirm monitoring/alerting is fully operational in the new account before the old one is decommissioned.

**Rollback or recovery strategy:** keep the old flat-account production resources running, unmodified, for a defined grace period after cutover specifically as the rollback path — a DNS/traffic shift back to the old resources should be the fast, low-risk rollback mechanism if the new production account reveals an issue post-cutover.

**Long-term prevention:** once fully migrated, the account-vending pipeline and SCPs prevent this "everything in one flat account" pattern from ever recurring, since all future environments/applications get properly isolated accounts by default from creation.

### Step-by-Step Implementation
```text
Phase 1: Build landing zone (zero impact on existing production)
  - Management account, OUs, SCPs, account-vending pipeline

Phase 2: Migrate dev/staging (lower risk, validates the pattern)
  - Provision fresh dev/staging accounts via standard modules
  - Cut over non-critical traffic, decommission old dev/staging resources

Phase 3: Migrate production (blue-green at account level)
  - Provision fresh production account, full stack, in parallel
  - Validate under real load
  - Plan data-layer cutover specifically (replication/migration strategy per data store)
  - Deliberate, monitored traffic cutover (DNS/LB level)
  - Retain old account's resources on standby for defined rollback window
  - Decommission old flat account only after rollback window passes uneventfully
```

### Under-the-Hood Explanation
This migration is architecturally identical in kind to the state-splitting and blue-green patterns already covered ([Question 15](02-state-management.md#question-15-the-plan-that-took-twenty-minutes), [`terraform-architecture.md` §11](../docs/terraform-architecture.md#11-immutable-infrastructure-and-blue-green-patterns)) — the added complexity is purely that the "blue" and "green" environments now live in genuinely separate AWS accounts rather than the same account, meaning cross-account data replication (rather than just Terraform state relocation) becomes the hard, resource-type-specific part of the migration, since Terraform itself has no account-to-account resource migration primitive for most services.

### Common Weak Answer
"Move all the resources into new accounts using `terraform state mv` across the account boundary."

### Why the Weak Answer Fails
`state mv` relocates Terraform's *bookkeeping* about a resource — it cannot and does not move the actual underlying cloud resource between AWS accounts, since most resource types have no "transfer ownership to another account" API at all; the resource must be recreated in the new account and cut over to, not "moved" via a state operation.

### Follow-Up Questions
1. How would you handle a specific data store (e.g., a large RDS database) that has no straightforward cross-account replication mechanism for its specific engine?
2. What's your fallback if the new production account reveals a subtle issue only after the rollback window has already passed?
3. How would you sequence which application migrates to the new landing zone first, given there are likely several applications sharing the current flat account?

### Key Interview Signals
Confirms the candidate recognizes this as a provision-fresh-and-cutover problem (not a mechanical state-move problem) given AWS's lack of cross-account resource transfer for most services, and designs a genuinely low-risk, staged migration for the production-critical path specifically.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
