# Category 9: Testing and Validation

Questions 79–86 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/testing.md`](../docs/testing.md).

---

## Question 79: The validation block nobody proved actually validates

### Scenario
A module's `variables.tf` includes a `validation` block intended to reject any CIDR block overlapping with a reserved internal range. Months later, someone discovers the regex in the condition has a subtle bug that makes it never actually reject anything — every input, including deliberately-overlapping ones, has always passed.

### Interview Question
How would native `terraform test` have caught this before it shipped, and how do you retrofit this kind of test coverage across an existing module library?

### Strong Senior-Level Answer
**Initial assessment:** a `validation` block with no corresponding test asserting it actually rejects bad input is an unverified guardrail — it looks like protection in the code but nobody has ever proven it functions, exactly the gap that let a regex bug ship silently.

**Technical reasoning:** `terraform test`'s `expect_failures` mechanism exists specifically to assert that a given variable's validation correctly rejects a specific bad value — writing this test would have caught the regex bug immediately, since the test run would show the plan *unexpectedly succeeding* instead of failing as asserted.

**Investigation process:** audit the module for every `validation` block currently lacking a corresponding `expect_failures` test case — this is mechanically checkable (grep for `validation {` blocks, cross-reference against test files covering that variable) and likely reveals this isn't an isolated incident.

**Recommended solution:** for this specific module, fix the regex and add a `terraform test` case using `expect_failures` for the exact overlapping-CIDR case that should have been rejected, plus a companion "valid input passes" test so the fix doesn't overcorrect into rejecting legitimate values.

**Risk controls:** treat "every validation/precondition block has both a passing and a failing test case" as a required checklist item for any new module PR going forward, not just an aspiration.

**Validation steps:** confirm the new test fails against the *old* (buggy) regex (proving the test would have caught the original bug) before confirming it passes against the corrected regex — a test that would have passed either way isn't actually testing anything.

**Rollback or recovery strategy:** audit any existing infrastructure that may have been provisioned with an overlapping CIDR during the window this bug was live, since the validation's entire purpose (preventing that specific misconfiguration) failed silently for however long the bug existed.

**Long-term prevention:** retrofit this pattern (a failing-case test for every existing validation/precondition block) across the whole module library as a tracked backlog item, prioritizing security-relevant validations (like this CIDR-overlap check) first, and make it a standard part of the module-authoring checklist for every future module.

### Step-by-Step Implementation
```hcl
variable "cidr_block" {
  type = string
  validation {
    # Buggy: this condition never actually returns false for genuinely overlapping input
    condition     = !can(regex("^10\\.0\\.", var.cidr_block))
    error_message = "CIDR must not overlap the reserved 10.0.0.0/8 range."
  }
}
```
```hcl
# tests/cidr_validation.tftest.hcl
run "overlapping_cidr_is_rejected" {
  command = plan
  variables {
    cidr_block = "10.0.5.0/24"   # deliberately overlapping - should be rejected
  }
  expect_failures = [
    var.cidr_block,
  ]
}

run "non_overlapping_cidr_is_accepted" {
  command = plan
  variables {
    cidr_block = "172.16.0.0/24"
  }
  # no expect_failures - this should plan cleanly
}
```
```bash
# Confirm the test actually catches the bug: run against the old regex first
terraform test   # "overlapping_cidr_is_rejected" should FAIL here, proving detection works
# Then fix the regex and re-run
terraform test   # now passes
```

### Under-the-Hood Explanation
`expect_failures` tells the `terraform test` runner that a specific variable's `validation` (or a resource's `precondition`) is expected to produce a plan-time error for the given input — if the plan instead succeeds (as it did with the buggy regex), the test itself fails, loudly reporting that the expected validation failure never occurred; this inverts the usual test-writing instinct of "assert success" into "assert the guardrail actually guards," which is precisely the missing verification in the original scenario.

### Common Weak Answer
"Code review should have caught the regex bug."

### Why the Weak Answer Fails
A subtle regex bug is exactly the kind of mistake human review reliably misses — regexes are notoriously hard to verify correct by eye, which is precisely why an automated test asserting the actual behavior (does this specific bad input get rejected) is the reliable control, not a reviewer's visual inspection of pattern syntax.

### Follow-Up Questions
1. How would you prioritize which existing validation blocks to retrofit tests for first, across a large module library?
2. What's the difference between testing a `validation` block this way versus testing a `precondition` inside a `lifecycle` block?
3. How would you extend this testing discipline to catch a similar bug in a policy-as-code (Conftest/OPA) rule instead of a Terraform-native validation block?

### Key Interview Signals
Confirms the candidate treats an unverified guardrail as equivalent to no guardrail at all, and knows the specific `expect_failures` mechanism for proving validation logic actually works, not just that it exists.

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 80: The test that left the lights on

### Scenario
Your module's integration test suite (`terraform test` with `command = apply`, provisioning real AWS resources in a sandbox account) is interrupted when the CI runner crashes mid-test. Native `terraform test`'s automatic cleanup doesn't run, because the process never reached that point. Three days later, someone notices the sandbox account's bill is unexpectedly high.

### Interview Question
Design a cleanup mechanism that doesn't depend on the test process completing successfully.

### Strong Senior-Level Answer
**Initial assessment:** relying solely on `terraform test`'s own end-of-run cleanup is exactly the single point of failure this incident demonstrates — any interrupted test process (crashed runner, killed job, network partition) skips that cleanup entirely, identical in kind to the interrupted-apply problem for regular applies (see [`terraform-internals.md` §12](../docs/terraform-internals.md#12-interrupted-and-partial-applies)).

**Technical reasoning:** the fix needs a cleanup mechanism that's independent of whether the test process itself completes — a scheduled sweep that identifies and destroys any resource tagged as test-origin and older than a reasonable test-duration threshold, regardless of what happened to the test run that created it.

**Investigation process:** confirm every resource the integration test suite creates is tagged distinctly (e.g., `Purpose = "automated-test", TestRunId = "..."`) — if tagging isn't consistent today, that's the first gap to fix, since a sweep can't identify what it can't distinguish from real infrastructure.

**Recommended solution:** add a scheduled cleanup job (a Lambda or a simple scheduled CI job) that queries the sandbox account for any resource tagged `Purpose = automated-test` with a creation timestamp older than, say, two hours (well beyond any legitimate test's expected runtime), and destroys it — this acts as a backstop independent of the test framework's own teardown logic, catching exactly the crashed-runner scenario in this incident.

**Risk controls:** scope the sweep tightly to the sandbox account and the specific tag, never touching anything without that exact tag, to avoid any risk of the cleanup job accidentally destroying real infrastructure.

**Validation steps:** deliberately test the sweep by creating a tagged resource, artificially backdating its creation timestamp (or waiting past the threshold), and confirming the sweep correctly identifies and destroys it without touching anything else in the account.

**Rollback or recovery strategy:** not applicable — the sweep is itself a cleanup mechanism; for the specific incident, manually identify and destroy the orphaned resources from the crashed test run immediately, and audit the resulting cost impact.

**Long-term prevention:** make the scheduled sweep a standard, permanent part of every sandbox/test account's baseline configuration (part of the account-vending pipeline, per [Question 45 in category 5](05-aws-architecture.md#question-45-account-creation-shouldnt-be-a-ticket)), not a one-off fix for this specific module's test suite.

### Step-by-Step Implementation
```hcl
# Every resource created by the integration test suite tagged distinctly
resource "aws_instance" "test_fixture" {
  # ...
  tags = {
    Purpose   = "automated-test"
    TestRunId = var.test_run_id
    CreatedAt = timestamp()
  }
}
```
```python
# Scheduled Lambda sweep, independent of the test framework's own teardown
import boto3, datetime

def handler(event, context):
    ec2 = boto3.client('ec2')
    cutoff = datetime.datetime.utcnow() - datetime.timedelta(hours=2)
    instances = ec2.describe_instances(Filters=[
        {'Name': 'tag:Purpose', 'Values': ['automated-test']}
    ])
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            launch_time = instance['LaunchTime'].replace(tzinfo=None)
            if launch_time < cutoff:
                ec2.terminate_instances(InstanceIds=[instance['InstanceId']])
```

### Under-the-Hood Explanation
Native `terraform test`'s automatic cleanup works by tracking every resource created during `apply`-mode `run` blocks within that test execution and issuing the equivalent of a `terraform destroy` at the end of the test file's run, or when a later `run` block fails — this cleanup logic executes as part of the same test process, meaning it shares fate with that process: if the process is killed externally (CI runner crash, OOM, network partition), the cleanup code never gets a chance to execute at all, identical in mechanism to why a killed `terraform apply` can leave a stale lock (see [Question 12 in category 2](02-state-management.md#question-12-the-lock-that-would-not-die)) — the fix in both cases is an external, independent recovery mechanism that doesn't depend on the interrupted process's own cleanup code running.

### Common Weak Answer
"Just tell the team to manually check the sandbox account after test runs."

### Why the Weak Answer Fails
Manual, human-remembered checking is exactly the kind of control that already failed here — nobody noticed for three days; an automated, scheduled, tag-based sweep provides a guaranteed backstop independent of anyone remembering to look, which is the actual fix for a failure mode that is, by definition, unpredictable in when it occurs.

### Follow-Up Questions
1. How would you tune the two-hour threshold to avoid the sweep destroying a resource from a test that's still legitimately running (a longer-than-usual integration test)?
2. How would you extend this sweep to cover resource types that don't support tagging (if any exist in your test fixtures)?
3. What's the cost/complexity trade-off of running this sweep every few minutes versus once a day?

### Key Interview Signals
Confirms the candidate recognizes that any cleanup mechanism sharing fate with the process it's cleaning up after is fundamentally unreliable, and designs an independent, tag-based, scheduled backstop instead.

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 81: Choosing the right tool for "does this actually work"

### Scenario
Your team needs to verify that a newly-built ALB module actually routes traffic correctly to a target group and returns a healthy HTTP response — not just that Terraform's plan/apply succeeded, but that the resulting infrastructure functions as intended end-to-end.

### Interview Question
Would native `terraform test` or Terratest be the better fit here, and why?

### Strong Senior-Level Answer
**Initial assessment:** this specific need — asserting on a real HTTP response from a live endpoint, not just on Terraform's own resource attributes — is closer to Terratest's strength than native `terraform test`'s.

**Technical reasoning:** native `terraform test`'s `assert` blocks can check resource attributes (e.g., the ALB's `dns_name` is non-empty, a target group's health check path is correctly configured) but have no built-in mechanism to make an actual HTTP request to the resulting endpoint and assert on the response — that requires genuine general-purpose programming logic (an HTTP client, retry/backoff for eventual-consistency delays, response-body assertions), which is exactly what Terratest (a Go library) is designed for.

**Investigation process:** confirm whether the team already has Go tooling/CI infrastructure in place (Terratest requires it) versus would need to introduce it fresh — if introducing an entirely new language/toolchain just for this one test is a significant cost, weigh that against writing a lighter-weight custom script (any language) that runs after a native `terraform test` or regular `apply`, making the same kind of real HTTP assertion without adopting the full Terratest framework.

**Recommended solution:** use native `terraform test` for the module's structural/configuration-level assertions (attribute checks, validation/precondition testing per [Question 79](#question-79-the-validation-block-nobody-proved-actually-validates)), and layer Terratest (or an equivalent real-HTTP-assertion script) on top specifically for the end-to-end "does traffic actually flow and get a healthy response" verification — these aren't competing choices, they're complementary layers of the testing pyramid (see [`testing.md` §1](../docs/testing.md#1-the-testing-pyramid-applied-to-terraform)).

**Risk controls:** build in retry/backoff logic for the HTTP assertion, since DNS propagation and target-group health-check registration have real eventual-consistency delays — a naive immediate HTTP request right after apply completes is a common source of test flakiness here (see [Question 84](#question-84-the-test-that-passed-on-tuesday-and-failed-on-wednesday)).

**Validation steps:** confirm the Terratest-based check actually fails when the ALB is deliberately misconfigured (e.g., pointing at the wrong target group) in a test run, proving it catches real functional issues, not just that it passes on a correct configuration.

**Rollback or recovery strategy:** not applicable — this is a testing-tool choice; ensure whichever framework is used has guaranteed teardown (see [Question 80](#question-80-the-test-that-left-the-lights-on)) regardless of which one you choose.

**Long-term prevention:** document this layered testing approach (native `terraform test` for structural checks, Terratest/equivalent for real end-to-end functional checks) as the standard pattern for any module where "does it actually work end-to-end" matters beyond "did the resources get created."

### Step-by-Step Implementation
```hcl
# Native terraform test: structural assertions
run "alb_has_healthy_target_group_config" {
  command = apply
  assert {
    condition     = aws_lb_target_group.app.health_check[0].path == "/healthz"
    error_message = "Target group health check path must be /healthz"
  }
}
```
```go
// Terratest: real end-to-end HTTP assertion
func TestALBServesTraffic(t *testing.T) {
	terraformOptions := &terraform.Options{TerraformDir: "../modules/alb"}
	defer terraform.Destroy(t, terraformOptions)   // guaranteed teardown, even on assertion failure
	terraform.InitAndApply(t, terraformOptions)

	albDNS := terraform.Output(t, terraformOptions, "alb_dns_name")
	url := fmt.Sprintf("http://%s/healthz", albDNS)

	http_helper.HttpGetWithRetryWithCustomValidation(
		t, url, nil, 30, 10*time.Second,
		func(statusCode int, body string) bool {
			return statusCode == 200
		},
	)
}
```

### Under-the-Hood Explanation
Native `terraform test`'s `assert` blocks evaluate expressions against the plan/apply's own resource state — they have no HTTP client or general-purpose programming capability, by design (they're an HCL-native, declarative testing DSL). Terratest, being a Go library, runs Terraform via subprocess calls (`terraform.InitAndApply`) and then uses ordinary Go code — including full HTTP client libraries with retry/backoff helpers purpose-built for exactly this kind of eventual-consistency-aware endpoint testing — to make real assertions against the live infrastructure the apply produced, which is precisely the capability gap native `terraform test` doesn't fill.

### Common Weak Answer
"Just use whichever one your team is already familiar with."

### Why the Weak Answer Fails
Familiarity is a reasonable secondary factor, but the question specifically asks about a capability gap (real HTTP assertions against live infrastructure) that one tool has and the other doesn't — recommending a tool choice based purely on familiarity while ignoring that native `terraform test` structurally cannot make an HTTP request misses the actual technical decision criterion.

### Follow-Up Questions
1. How would you structure a test suite that uses both tools without duplicating the same Terraform apply/destroy cycle unnecessarily?
2. What's the cost implication of running Terratest-based end-to-end tests on every PR versus only on a scheduled/release-gated basis?
3. How would you handle testing a module where the "does it work" verification requires assertions against a non-HTTP protocol (e.g., a database connection, a message queue)?

### Key Interview Signals
Confirms the candidate understands the specific capability boundary between native `terraform test` and Terratest, and treats them as complementary layers rather than competing, mutually-exclusive choices.

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 82: Testing the tests that test your infrastructure

### Scenario
Your organization's Conftest policy library has grown to over fifty Rego rules enforcing security and tagging standards. A recent incident revealed one rule intended to block public S3 buckets had a logic error that made it always pass, regardless of the bucket's actual configuration — identical in spirit to the validation-block bug from [Question 79](#question-79-the-validation-block-nobody-proved-actually-validates), but in your policy layer instead of your Terraform modules.

### Interview Question
How do you test policy-as-code rules themselves, and how would this specific bug have been caught?

### Strong Senior-Level Answer
**Initial assessment:** the same principle from [Question 79](#question-79-the-validation-block-nobody-proved-actually-validates) applies one layer up — an untested policy rule is an unverified guardrail, and a logic error making a `deny` rule never actually deny anything is exactly the failure mode that a policy-specific test suite exists to catch.

**Technical reasoning:** Conftest/OPA policies can and should be tested with their own dedicated test cases (using `conftest test` against fixture plan JSON files, or Rego's own built-in test framework via `opa test`) asserting both that a genuinely non-compliant configuration is correctly denied, and that a genuinely compliant one is correctly allowed — mirroring the "both a failing and a passing case" discipline from Terraform-native validation testing.

**Investigation process:** audit the full fifty-rule policy library for which rules currently have any test coverage at all — this incident strongly suggests the answer is "few to none," since an untested `deny` rule with a logic bug making it never fire would produce zero visible symptoms (no false-positive complaints, since it never blocks anything) until an actual incident surfaces the gap, exactly as happened here.

**Recommended solution:** for every rule in the policy library, add at least two fixture-based test cases: one deliberately-non-compliant plan JSON that the rule should deny, and one compliant plan JSON it should allow — run these via `conftest test` (or `opa test` against Rego unit tests) as part of the policy library's own CI pipeline, gating any change to the Rego rules themselves.

**Risk controls:** treat the policy library as its own tested software artifact with its own release/versioning discipline, not just a folder of `.rego` files trusted to work correctly by inspection.

**Validation steps:** for the specific buggy public-S3 rule, write the fixture test first (confirming it currently incorrectly passes against a known-public-bucket fixture), fix the Rego logic, and confirm the test now correctly fails the fixture — proving the fix, not just assuming it from reading the corrected code.

**Rollback or recovery strategy:** audit any infrastructure that was actually deployed while this specific rule was silently non-functional, since its entire purpose (blocking public S3 buckets) failed for however long the bug was live — this is a real, retroactive security exposure check, not just a testing-process fix.

**Long-term prevention:** make "every new or modified Rego rule ships with both a failing-case and passing-case fixture test" a mandatory part of the policy library's own contribution process, exactly mirroring the Terraform-module validation-testing discipline from Question 79.

### Step-by-Step Implementation
```rego
# policies/s3_public_access.rego
package main

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket_public_access_block"
  resource.change.after.block_public_acls == false   # buggy: should also check other fields
  msg := sprintf("%s: public access block must be enabled", [resource.address])
}
```
```rego
# policies/s3_public_access_test.rego (opa test / conftest test fixture-based)
package main

test_denies_public_bucket {
  deny["aws_s3_bucket_public_access_block.bad: public access block must be enabled"] with input as {
    "resource_changes": [{
      "address": "aws_s3_bucket_public_access_block.bad",
      "type": "aws_s3_bucket_public_access_block",
      "change": {"after": {"block_public_acls": false, "block_public_policy": true, ...}}
    }]
  }
}

test_allows_private_bucket {
  count(deny) == 0 with input as {
    "resource_changes": [{
      "address": "aws_s3_bucket_public_access_block.good",
      "type": "aws_s3_bucket_public_access_block",
      "change": {"after": {"block_public_acls": true, "block_public_policy": true, ...}}
    }]
  }
}
```
```bash
opa test policies/ -v
```

### Under-the-Hood Explanation
Rego's built-in test framework (`opa test`) recognizes functions prefixed `test_` within a policy package and evaluates their assertions (typically checking whether a `deny`/`allow` rule produces the expected result against a supplied fixture `input`) — this runs entirely independently of any real Terraform plan, using hand-crafted JSON fixtures shaped like `terraform show -json` output, which is precisely what makes it possible to test both the "should deny" and "should allow" cases deterministically and repeatably, without needing an actual cloud resource or Terraform run at all.

### Common Weak Answer
"Review the Rego code more carefully before merging changes to policies."

### Why the Weak Answer Fails
This is the exact same "code review should have caught it" failure mode from Question 79, applied to Rego instead of HCL — Rego logic errors (like a condition checking the wrong field, or an inverted boolean) are just as easy to miss by visual inspection as the regex bug in Question 79, and just as reliably caught by an automated fixture test asserting actual behavior.

### Follow-Up Questions
1. How would you prioritize which of the fifty existing rules to retrofit tests for first?
2. How does testing a `deny`-style Rego rule differ from testing an `allow`-style one, in terms of what "both cases" means?
3. How would you integrate policy-rule testing into the same CI pipeline that tests your Terraform modules, without conflating the two test suites?

### Key Interview Signals
Confirms the candidate applies the same untested-guardrail-is-no-guardrail principle consistently across both Terraform-native validation and policy-as-code layers, recognizing this as a general testing-discipline gap, not something unique to one specific rule.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 83: The test suite that couldn't fail

### Scenario
A module's `terraform test` suite has been passing on every PR for months. During an unrelated debugging session, an engineer notices the tests are asserting against a hardcoded local value in the test file itself, not against the actual resource attribute the module produces — meaning the tests would pass even if the module's logic were completely broken.

### Interview Question
How did this happen, and how do you audit a test suite for this specific failure mode?

### Strong Senior-Level Answer
**Initial assessment:** this is a "tautological test" — one that asserts a condition guaranteed to be true regardless of whether the code under test is correct, providing zero actual verification while giving every appearance (a green CI check) of doing so; it's arguably worse than no test at all, since it actively creates false confidence.

**Technical reasoning:** the specific bug pattern (asserting against a hardcoded local rather than the actual resource attribute) likely arose from a copy-paste-and-modify test-writing process where the assertion's right-hand side was never actually updated to reference the real output being tested — an easy mistake to make and, critically, one that produces no visible symptom (the test simply always passes), unlike a typo that would cause an immediate test failure demanding attention.

**Investigation process:** audit every `assert` block in the test suite specifically checking whether both sides of each condition reference genuinely independent sources — a healthy assertion compares a resource's actual computed attribute against an expected value derived independently (a literal, or a different resource's output), while a tautological one compares a value against itself or a hardcoded copy of what the test author expected the value to already be.

**Recommended solution:** for every existing test, deliberately introduce a known-bad module change (a mutation test — e.g., temporarily break the actual logic being tested) and confirm the test suite correctly fails; any test that continues passing despite the deliberate break is tautological or otherwise not testing what it claims to, and needs rewriting.

**Risk controls:** for any new test going forward, apply this same "does it fail when it should" verification as part of writing the test itself — a test that has never been observed to fail (even deliberately, during its own authoring) shouldn't be trusted as functioning.

**Validation steps:** after rewriting the tautological tests, re-run the mutation-testing check (deliberately break the module logic again) and confirm the corrected tests now correctly fail, proving the fix.

**Rollback or recovery strategy:** not applicable — this is a test-suite quality fix; separately, given months of false confidence, do a broader review of the module's actual behavior in production to confirm nothing has silently regressed during the period these tests provided no real coverage.

**Long-term prevention:** adopt mutation testing (or at minimum, a periodic manual "deliberately break something and confirm tests catch it" exercise) as a standing practice for critical module test suites, not just a one-time audit triggered by this discovery.

### Step-by-Step Implementation
```hcl
# Tautological (broken) test - compares the computed value against itself
locals {
  expected_tag = aws_instance.app.tags["Environment"]   # not independent of what's being tested!
}
run "instance_has_correct_environment_tag" {
  command = plan
  assert {
    condition     = aws_instance.app.tags["Environment"] == local.expected_tag   # always true
    error_message = "..."
  }
}
```
```hcl
# Corrected: assert against an independently-derived expected value
run "instance_has_correct_environment_tag" {
  command = plan
  variables {
    environment = "production"
  }
  assert {
    condition     = aws_instance.app.tags["Environment"] == "production"   # literal, independent
    error_message = "Expected Environment tag to be 'production'"
  }
}
```
```bash
# Mutation-test verification: deliberately break the module, confirm the test now fails
sed -i 's/var.environment/"wrong-value"/' main.tf
terraform test   # should FAIL now; if it still passes, the test is still not testing anything real
git checkout main.tf   # revert the deliberate break
```

### Under-the-Hood Explanation
`terraform test`'s `assert` block evaluates its `condition` expression exactly as written — it has no awareness of whether both sides of a comparison are genuinely independent or whether one side was derived directly from the same computation being tested; this is purely a test-authoring correctness issue, not a Terraform limitation, which is precisely why the practical detection method (mutation testing — deliberately breaking the underlying logic and confirming the test notices) is itself independent of the test framework and applies to any testing approach, Terraform-native or otherwise.

### Common Weak Answer
"Since the tests are passing, the module is probably fine."

### Why the Weak Answer Fails
This is the exact false confidence the scenario is warning against — "tests are passing" and "the module works correctly" are only the same claim if the tests are actually exercising real, independent verification, which this incident demonstrates cannot be assumed just because a test suite shows green.

### Follow-Up Questions
1. How would you build mutation testing into a CI pipeline systematically, rather than as an occasional manual audit?
2. What other patterns, besides comparing a value against itself, produce tautological tests in Terraform test suites?
3. How would you communicate this finding to the team without it feeling like blame, given that the original test author likely didn't realize the mistake?

### Key Interview Signals
Confirms the candidate can identify a subtle test-quality anti-pattern (not just whether tests exist, but whether they're actually testing anything) and proposes a concrete verification method (mutation testing) rather than just "review tests more carefully."

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 84: The test that passed on Tuesday and failed on Wednesday

### Scenario
Your integration test suite for a module provisioning an RDS instance and an application server that connects to it fails intermittently — roughly one run in eight — with a connection-timeout error from the application server, even though the underlying Terraform apply itself always succeeds without error.

### Interview Question
Diagnose this flakiness and stabilize the test suite.

### Strong Senior-Level Answer
**Initial assessment:** an intermittent failure with a successful Terraform apply strongly suggests a timing/eventual-consistency issue at the *infrastructure* level (DNS propagation, RDS instance not yet fully accepting connections despite the API reporting it as "available," security group rule propagation delay) rather than a bug in the test's assertions or the module's configuration itself.

**Technical reasoning:** AWS's own API often reports a resource as "available" slightly before it's genuinely ready to serve all traffic (RDS instances specifically can report `available` status while still completing internal initialization) — a test that immediately attempts a connection the moment Terraform's apply completes is racing this internal readiness window, which is exactly the kind of one-in-eight flakiness described.

**Investigation process:** examine the specific failure's timing — does it correlate with anything (time of day suggesting regional API load, or a consistent short delay after apply completes) — and check whether the test currently makes an immediate, single connection attempt with no retry logic at all.

**Recommended solution:** add explicit retry-with-backoff logic to the connection assertion (attempt the connection, and on failure, wait and retry several times over a reasonable window, e.g., up to two minutes) rather than a single immediate attempt — this is standard practice for any test asserting against real cloud infrastructure's eventual-consistency behavior, and directly addresses the timing-race root cause rather than the symptom.

**Risk controls:** distinguish "the connection eventually succeeds within a reasonable retry window" (a healthy test outcome, proving the infrastructure works, just with expected propagation delay) from "the connection never succeeds even after generous retries" (a genuine failure worth failing the test over) — the retry logic needs a sensible upper bound, not infinite patience that would mask an actually-broken configuration.

**Validation steps:** run the updated test suite significantly more times than the original one-in-eight failure rate would statistically require to catch (e.g., 30+ consecutive runs) to confirm the retry logic has genuinely eliminated the flakiness, not just reduced its observed frequency by chance.

**Rollback or recovery strategy:** not applicable — this is a test-suite reliability fix with no infrastructure impact of its own.

**Long-term prevention:** apply retry-with-backoff as a standard pattern for every integration test asserting against real cloud infrastructure's runtime behavior (not just this one RDS/app-server case), since eventual-consistency delays are a general characteristic of cloud APIs, not specific to this one resource type.

### Step-by-Step Implementation
```go
// Terratest-style retry logic replacing a naive single connection attempt
func TestAppConnectsToDatabase(t *testing.T) {
	terraformOptions := &terraform.Options{TerraformDir: "../modules/app-with-db"}
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	appEndpoint := terraform.Output(t, terraformOptions, "app_endpoint")

	retry.DoWithRetry(t, "wait for app to connect to database", 12, 10*time.Second, func() (string, error) {
		resp, err := http.Get(fmt.Sprintf("http://%s/health/db", appEndpoint))
		if err != nil || resp.StatusCode != 200 {
			return "", fmt.Errorf("app not yet connected to database")
		}
		return "connected", nil
	})
}
```

### Under-the-Hood Explanation
RDS (and many other managed AWS services) transition through internal initialization steps after their API-reported status first becomes `available` — Terraform's `aws_db_instance` resource considers its create operation complete once the API confirms `available` status, which is the correct and only signal Terraform's provider RPC model has access to; it has no visibility into finer-grained internal readiness beyond what the API reports, which is precisely why a test asserting real connectivity immediately after apply can race this gap, and why retry-with-backoff at the *test* level (not a Terraform-level change, since Terraform did its job correctly) is the appropriate fix.

### Common Weak Answer
"Add a fixed 30-second sleep before the connection test to give it time."

### Why the Weak Answer Fails
A fixed sleep is a guess at the actual delay, which can vary (load-dependent, region-dependent) — it might still be too short under some conditions (reintroducing flakiness) while unnecessarily slowing down every test run under normal conditions where the delay is much shorter; retry-with-backoff adapts to the actual delay each run experiences, which is strictly more robust than any fixed wait duration.

### Follow-Up Questions
1. How would you distinguish "genuine eventual-consistency flakiness" from "a real, intermittent bug in the module" if you weren't sure which this was?
2. What retry/backoff parameters (interval, max attempts) would you choose, and how would you justify that choice?
3. How does this same class of flakiness show up differently for a resource type with a much longer typical propagation delay, like a newly-created ACM certificate validation?

### Key Interview Signals
Confirms the candidate diagnoses intermittent test failures as an eventual-consistency timing issue (a very common real pattern) rather than assuming a fixed sleep is an adequate fix, and applies retry-with-backoff as the principled solution.

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 85: Testing three regions without paying for three regions

### Scenario
Your `rds-with-dr` module (from [Question 36 in category 4](04-providers.md#question-36-one-module-two-regions-at-the-same-time)) needs test coverage confirming its multi-region provider-aliasing logic is wired correctly — specifically, that the primary and replica resources really do route to their respective distinct provider configurations. Actually provisioning real RDS instances and cross-region replicas for every test run would be slow and expensive.

### Interview Question
Design a cost-conscious test strategy for this module's multi-region logic.

### Strong Senior-Level Answer
**Initial assessment:** the specific thing needing verification here — "does resource X route to provider alias A and resource Y route to provider alias B" — is a structural/configuration-correctness question, not a question requiring real infrastructure to answer, which makes this a strong candidate for plan-mode testing with mocked providers rather than expensive real `apply`-mode integration tests.

**Technical reasoning:** `command = plan` tests (optionally combined with `mock_provider` where your Terraform version supports it) can confirm the *planned* resource configuration correctly references the intended provider alias and produces the expected region-specific arguments, without ever actually calling AWS — since the question being tested is entirely about Terraform's own graph/provider-routing logic, not about whether AWS's actual replication mechanism works (which is AWS's own tested behavior, not something your module's test suite needs to re-verify).

**Investigation process:** separate what genuinely needs a real, `apply`-mode, cost-incurring integration test (e.g., confirming an actual replica genuinely receives replicated data — a real AWS behavior worth verifying at least once, perhaps in a less-frequent scheduled test rather than every PR) from what's purely a Terraform-configuration-correctness question answerable via plan-mode/mocked tests (which provider alias each resource references, which region argument gets set).

**Recommended solution:** use `command = plan` tests asserting on the plan's resource-level details (which provider each resource is configured against, correct region-specific arguments) for the bulk of the module's test coverage, run on every PR at zero cost; reserve a real `apply`-mode integration test (provisioning actual primary + replica) for a much less frequent cadence (e.g., before a major release, or a nightly scheduled run) specifically to catch anything a mocked/plan-only test couldn't (genuine AWS-side replication behavior).

**Risk controls:** the plan-mode tests should specifically assert the provider-routing logic, not just "the plan doesn't error" — check that `aws_db_instance.replica`'s plan explicitly shows it configured against the `aws.dr` provider alias's region, not just that the resource block exists.

**Validation steps:** confirm the plan-mode tests actually catch a deliberately-introduced routing bug (e.g., temporarily wire the replica to the wrong provider alias and confirm the test fails) before trusting them as adequate coverage for this specific concern.

**Rollback or recovery strategy:** not applicable — this is a test-strategy design; the infrequent real integration test still needs guaranteed cleanup (per [Question 80](#question-80-the-test-that-left-the-lights-on)) given it does provision real, billable resources.

**Long-term prevention:** apply this "separate configuration-correctness testing (cheap, frequent) from genuine-cloud-behavior testing (expensive, infrequent)" split as the standard cost-control strategy for testing every multi-region/multi-account module, not just this one.

### Step-by-Step Implementation
```hcl
# tests/provider_routing.tftest.hcl - plan-mode, zero cost, runs on every PR
run "replica_uses_dr_region_provider" {
  command = plan

  assert {
    condition     = aws_db_instance.replica.provider == "aws.dr"
    error_message = "Replica must use the aws.dr provider configuration"
  }
}
```
```bash
# Real integration test - apply-mode, cost-incurring, scheduled infrequently (e.g., nightly)
# separate CI job, not run on every PR
terraform test -filter=tests/real_replication_integration.tftest.hcl
```

### Under-the-Hood Explanation
`command = plan` mode never invokes a provider's `ApplyResourceChange` RPC (see [`terraform-internals.md` §9](../docs/terraform-internals.md#9-provider-rpc-communication)) — it only constructs the plan, meaning provider-routing/graph-construction logic is fully exercised and verifiable without ever making a real AWS API call that would incur cost or require actual multi-region access; this is precisely why questions purely about Terraform's own configuration/graph correctness (which provider does this resource use) are answerable at zero cost, while questions about genuine AWS-side behavior (does data actually replicate across regions) inherently require a real `apply` against real infrastructure.

### Common Weak Answer
"Just run the full integration test on every PR — correctness is more important than cost."

### Why the Weak Answer Fails
This conflates two different things needing verification: Terraform's own configuration-routing logic (cheaply, thoroughly testable via plan-mode) and AWS's actual replication behavior (expensive, and not really a property of *your* module's code at all, but of AWS's own service — no amount of your testing changes whether AWS's replication works correctly). Running the expensive test on every PR doesn't actually improve confidence in the routing logic specifically, and wastes cost/time better spent elsewhere.

### Follow-Up Questions
1. How would you decide the right cadence for the real integration test — nightly, weekly, only before releases?
2. What would you do if your Terraform version doesn't yet support `mock_provider` — does the plan-mode-only approach still work without it?
3. How would you extend this cost-conscious split to a module with even more provider configurations (e.g., five regions instead of two)?

### Key Interview Signals
Confirms the candidate can decompose "what actually needs real infrastructure to verify" from "what's purely a Terraform-configuration question," applying cost-conscious testing judgment rather than defaulting to either extreme (always-expensive-integration-tests or never-testing-real-behavior-at-all).

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 86: The test suite frozen in time

### Scenario
A module's `terraform test` suite was written thoroughly eighteen months ago and hasn't been updated since, even though the module itself has had several feature additions in that time. The CI gate requires all tests to pass, and they do — but purely because none of the new features have any test coverage at all, so nothing exercises the new code paths.

### Interview Question
How does a CI gate requiring "100% test pass" coexist with a test suite that's silently stopped covering new functionality? How do you fix this systemically?

### Strong Senior-Level Answer
**Initial assessment:** "100% of existing tests pass" and "the module is adequately tested" are different claims that have quietly diverged here — the CI gate is enforcing the former (a necessary but insufficient condition) while everyone likely assumed it guaranteed the latter.

**Technical reasoning:** a test suite's coverage is a point-in-time snapshot of what someone thought to test when it was written — without an explicit process ensuring new functionality gets new test coverage, the suite naturally becomes proportionally less comprehensive as the module grows, all while continuing to show a reassuring "100% passing" status that says nothing about the newly-uncovered code.

**Investigation process:** enumerate every feature/variable/output added to the module in the last eighteen months and cross-reference against the test suite's actual `run` blocks — this concretely quantifies the coverage gap (e.g., "3 of the last 5 added variables have zero test coverage") rather than leaving it as a vague concern.

**Recommended solution:** add test coverage for every currently-uncovered feature identified in the audit, and — more importantly — establish a structural process ensuring this doesn't recur: require any PR adding a new variable, output, or resource to the module to also include a corresponding test case, enforced via a lightweight CI check (e.g., a script that flags a PR modifying `variables.tf`/`outputs.tf` without any corresponding change to the `tests/` directory) rather than relying on contributors remembering.

**Risk controls:** consider adding a rough coverage-tracking metric (even an approximate one — e.g., "percentage of variables referenced somewhere in a test's `variables` block") to make coverage gaps visible over time rather than invisible until an audit like this one surfaces them.

**Validation steps:** after adding the missing tests, confirm each one actually exercises the intended new functionality (not accidentally another tautological test per [Question 83](#question-83-the-test-suite-that-couldnt-fail)) by deliberately breaking the corresponding feature and confirming the new test catches it.

**Rollback or recovery strategy:** not applicable — this is a test-coverage and process fix; separately, given eighteen months of untested new functionality, consider whether any of those features have quietly shipped with undiscovered bugs, similar in spirit to the audits triggered by Questions 79 and 82.

**Long-term prevention:** the "new variable/output/resource requires a corresponding test" CI check is the actual long-term fix — without it, this exact gap will recur for the *next* eighteen months of feature additions regardless of how thoroughly this one audit closes the current gap.

### Step-by-Step Implementation
```bash
# Audit: features added vs. test coverage, by diffing variables.tf history against tests/
git log --oneline --follow -- modules/vpc/variables.tf | head -20
grep -o 'variable "[a-z_]*"' modules/vpc/variables.tf | sort > /tmp/all-vars.txt
grep -rho '[a-z_]* =' modules/vpc/tests/*.tftest.hcl | sort -u > /tmp/tested-vars.txt
comm -23 /tmp/all-vars.txt /tmp/tested-vars.txt   # variables with no apparent test coverage
```
```yaml
# CI check: flag PRs adding module interface without corresponding test changes
- name: Check test coverage for interface changes
  run: |
    if git diff --name-only origin/main | grep -q 'variables.tf\|outputs.tf'; then
      if ! git diff --name-only origin/main | grep -q 'tests/'; then
        echo "::error::PR modifies module interface but adds no test coverage"
        exit 1
      fi
    fi
```

### Under-the-Hood Explanation
`terraform test`'s pass/fail signal is scoped entirely to whatever `run` blocks exist in the test files at the time it's executed — it has no inherent awareness of the module's full interface surface or whether every variable/output/resource has corresponding coverage; "100% passing" is a true but narrow statement about the existing test set, not a claim about coverage completeness, which is exactly the gap between what the CI gate enforces and what it was implicitly assumed to guarantee.

### Common Weak Answer
"Just tell contributors to remember to add tests when they add features."

### Why the Weak Answer Fails
This is the same "remember next time" non-control pattern that already failed for eighteen months — the actual fix needs to be a structural CI check that can't be silently skipped by an contributor forgetting, exactly analogous to the fixes for the untested-validation-block and tautological-test problems in this same category.

### Follow-Up Questions
1. How would you build a more precise test-coverage metric than the rough grep-based approach shown here?
2. How would you handle a legitimate case where a new variable genuinely doesn't need its own dedicated test (e.g., a purely cosmetic naming override)?
3. How would you retrofit this same "interface change requires test change" discipline across every module in your registry, not just this one?

### Key Interview Signals
Confirms the candidate distinguishes "100% of existing tests pass" from "the module is adequately tested," and designs a structural CI enforcement mechanism rather than relying on contributor memory — the same pattern of thinking that should show up consistently across this whole testing category.

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).
