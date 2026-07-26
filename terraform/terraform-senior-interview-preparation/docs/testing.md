# Testing and Validation

"We don't really test our Terraform" is one of the most common honest answers senior candidates give — and one of the clearest signals an interviewer is listening for, because untested modules are exactly how one team's change breaks forty consumers (see [`module-design.md`](module-design.md#5-module-versioning-and-semantic-versioning)). This document backs [`interview-questions/09-testing.md`](../interview-questions/09-testing.md) and is exercised in [Lab 11](../labs/lab-11-testing/).

## 1. The testing pyramid, applied to Terraform

| Layer | What it checks | Terraform-native tool | Speed / cost |
|---|---|---|---|
| Static | Syntax, internal consistency, formatting | `terraform fmt -check`, `terraform validate`, TFLint | Seconds, free |
| Policy | Organizational rules against a plan | OPA/Conftest, Sentinel (see [`security.md`](security.md#9-policy-as-code)) | Seconds, free |
| Unit | A module's logic (conditionals, validation, computed locals) in isolation | `terraform test` with mocked providers | Seconds–minutes, free |
| Integration | A module actually provisions real (or realistically emulated) infrastructure correctly | `terraform test` against a real provider in a sandbox account, or Terratest | Minutes, **costs money** |
| Contract | A module's interface doesn't break real consumers | Custom (apply a matrix of representative consumer configs against a new module version) | Minutes, costs money |
| End-to-end | The whole environment behaves correctly post-apply | Smoke tests / health checks outside Terraform itself | Minutes, costs money |

Static and policy layers should run on every PR. Unit tests should run on every PR against every module. Integration/contract/E2E tests are more expensive and are typically gated to module-release events or scheduled runs rather than every commit — see [Lab 11](../labs/lab-11-testing/) and [`cicd.md`](cicd.md).

## 2. `terraform validate` — what it does and doesn't catch

`terraform validate` checks internal configuration consistency: correct syntax, referenced resources/variables exist, type constraints are satisfiable, required arguments are present. It does **not** contact any provider API, so it cannot catch: an invalid AMI ID, an IAM policy that will be rejected by AWS, a CIDR block that collides with an existing VPC, or any condition that depends on real cloud state. Treat it as a fast pre-check, not a correctness guarantee — it is a necessary, not sufficient, gate.

## 3. Native `terraform test` (`.tftest.hcl` / `.tftest.json`)

Terraform's built-in test framework (stable since Terraform 1.6, with mocking capabilities added in later 1.x releases — verify exact version gates for the mocking features you rely on) runs one or more `run` blocks against a module, each able to assert on plan or apply output.

```hcl
# tests/vpc_valid.tftest.hcl
variables {
  cidr_block           = "10.0.0.0/16"
  availability_zones    = ["us-east-1a", "us-east-1b"]
  name                  = "test-vpc"
}

run "valid_configuration_plans_cleanly" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Expected one private subnet per AZ"
  }
}

run "invalid_cidr_is_rejected" {
  command = plan
  variables {
    cidr_block = "not-a-cidr"
  }
  expect_failures = [
    var.cidr_block,
  ]
}

run "apply_creates_expected_tags" {
  command = apply

  assert {
    condition     = aws_vpc.this.tags["ManagedBy"] == "terraform"
    error_message = "VPC must be tagged ManagedBy=terraform"
  }
}
```

**Key mechanics:**
- `command = plan` tests are fast and free — no real infrastructure is created, making them appropriate for unit-testing conditionals, validation blocks, and computed locals on every PR.
- `command = apply` tests provision real resources against whatever provider configuration is active — appropriate for integration-level checks, but they cost money and need a real (ideally sandboxed, auto-cleaned-up) provider target; Terraform automatically destroys resources created by `apply`-mode test runs at the end of the test file's execution.
- `expect_failures` asserts that a `validation` block (or similar) correctly rejects bad input — this is how you unit-test your own module's input guards.

## 4. Mock providers

Where your installed Terraform version supports it, `mock_provider` blocks let `command = plan` test runs execute against **simulated provider responses** instead of a real API — useful for testing module logic (conditionals, `for_each` expansion, output computation) with zero cloud dependency and zero cost, at the cost of not actually validating real API behavior. Treat mocked tests as a fast unit-test layer, and reserve real-provider `apply` tests for genuine integration coverage — mocking every test gives you confidence in your HCL logic but zero confidence the module actually provisions working infrastructure.

```hcl
mock_provider "aws" {
  mock_resource "aws_vpc" {
    defaults = {
      id = "vpc-mock12345"
    }
  }
}
```

Verify the exact mocking syntax and capability set against your installed Terraform version's documentation — this feature has evolved across releases.

## 5. Third-party frameworks: Terratest and Kitchen-Terraform

- **Terratest** (Go library): applies real Terraform configurations, makes real assertions against the live cloud/API/HTTP endpoints the infrastructure produces (e.g., "the ALB actually returns 200"), then destroys. Strength: full real-world integration/E2E testing with a real general-purpose programming language for complex assertions. Cost: real infrastructure spend per test run, Go tooling/CI dependency, and test suites that can be slow (minutes per run).
- **Kitchen-Terraform** (Test Kitchen plugin, Ruby ecosystem): similar apply → verify → destroy lifecycle, historically popular in organizations already using Chef/InSpec tooling; less actively adopted for new Terraform-only projects compared to Terratest or native `terraform test` — verify current ecosystem activity before asserting it as the default choice.

**When to reach for a third-party framework vs. native `terraform test`:** native tests are now sufficient for the large majority of module unit/integration testing needs and have the advantage of no extra language/toolchain dependency. Terratest remains valuable when you need assertions that go beyond what HCL `assert` blocks can express — genuine HTTP/API-level verification, complex multi-step scenarios, or integration with a broader Go-based test suite your organization already maintains.

## 6. Contract testing for modules

The specific defense against the "changed a module interface, broke 40 consumers" failure (see [`module-design.md`](module-design.md#5-module-versioning-and-semantic-versioning)): before publishing a new module version, run its test suite (or, more rigorously, a representative sample of **real consumer configurations** pinned against the *new* version in a CI matrix) and confirm every one still produces a clean plan with no unexpected replacements. This turns "did we break anyone" from a post-release support-ticket discovery into a pre-release, automated gate.

## 7. Policy tests

Policies (OPA/Conftest rules, Sentinel policies) are code and should be tested like code: both "this plan violates the policy and is correctly rejected" and "this compliant plan is correctly allowed" cases, so a policy change can't silently become either too permissive (a real gap slips through) or too restrictive (legitimate infrastructure changes start failing for the wrong reason). See [Lab 13](../labs/lab-13-policy-as-code/) for concrete Conftest test cases.

## 8. Test environments and cost-controlled testing

- Run integration/apply-mode tests against a **dedicated, isolated sandbox account/project**, never directly against shared dev/staging, so a test failure or leaked resource can't affect real work.
- Favor cheap resource types in test fixtures — smallest instance sizes, minimal storage allocations, avoid provisioning things like NAT gateways or large database instances purely for a test run unless the test specifically needs to validate that resource.
- Time-bound/tag test-created resources distinctly (e.g., `Purpose = "automated-test"`, a short TTL tag) so a cleanup sweep can catch anything a failed test run left behind.
- Consider a scheduled cleanup job (a small script or Lambda) that destroys any resource tagged as test-origin and older than a threshold, as a safety net independent of the test framework's own teardown — test teardown failures do happen (a crashed CI runner mid-test leaves orphaned resources exactly like a crashed real apply does — see [`terraform-internals.md`](terraform-internals.md#12-interrupted-and-partial-applies)).

## 9. Destructive test cleanup

Every `apply`-mode test must have a guaranteed teardown path. Native `terraform test` handles this automatically at the end of the test file's run blocks; Terratest-style tests must explicitly `defer terraform.Destroy(...)` (or equivalent) immediately after apply, before any assertions, so a failing assertion still triggers cleanup rather than leaving real infrastructure running. **Never rely solely on "the test passed so it cleaned up after itself"** — assume CI runners get killed, network calls time out, and design cleanup to run independently of whether the test's own logic succeeded.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "How do you test Terraform?" | "We run `terraform validate`" | `validate` only checks internal syntax consistency; real testing needs unit tests (mocked or plan-mode), integration tests against a sandboxed real provider, and contract tests before publishing module changes |
| Releasing a new module major version | "Update the version and changelog" | Run the full test suite plus a consumer-representative contract test matrix before publishing, to catch breaking changes pre-release, not post-incident |
| Test creates real AWS resources | "That's fine, we'll clean it up manually after" | Automated, guaranteed teardown (native test auto-destroy, or an explicit deferred destroy) plus a scheduled sweep as a backstop for failed cleanups |

## Related material
- Interview questions: [`interview-questions/09-testing.md`](../interview-questions/09-testing.md)
- Hands-on: [Lab 11 — Native Terraform Testing](../labs/lab-11-testing/)
