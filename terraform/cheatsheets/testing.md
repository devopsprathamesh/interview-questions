# Cheat Sheet: Terraform Testing

## The pyramid
| Layer | Tool | Cost | Runs on |
|---|---|---|---|
| Static | `fmt`, `validate`, TFLint | Free, seconds | Every PR |
| Policy | OPA/Conftest, Sentinel | Free, seconds | Every PR |
| Unit | `terraform test`, `command = plan`, `mock_provider` | Free, seconds | Every PR, every module |
| Integration | `terraform test`, `command = apply`, or Terratest | Real cost, minutes | Module release / scheduled |
| Contract | New module version's plan against real consumer configs | Real cost, minutes | Before any major version release |
| E2E | Smoke tests post-deploy | Real cost, minutes | Post-deploy |

## Native `terraform test` essentials
```hcl
run "valid_config_plans_cleanly" {
  command = plan
  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "..."
  }
}

run "invalid_input_is_rejected" {
  command = plan
  variables { cidr_block = "not-a-cidr" }
  expect_failures = [var.cidr_block]
}
```
- `command = plan`: fast, free, no real resources.
- `command = apply`: real resources, automatic teardown at end of the test file's run — but teardown shares fate with the test process, so a killed CI runner can skip it. Pair with a scheduled, tag-based sweep as a backstop.
- `mock_provider`: zero-cost, zero-credential unit testing — verify version/feature support for your Terraform release.

## The two anti-patterns to know by name
1. **Untested guardrail** — a `validation`/`precondition`/Rego `deny` rule with no test proving it actually rejects bad input. Fix: `expect_failures` (Terraform) or a fixture test asserting `deny` fires (Rego).
2. **Tautological test** — an assertion comparing a value against itself or a hardcoded copy of what the module already computed, rather than an independently-derived expected value. Passes even if the underlying logic is completely broken. Fix: mutation testing — deliberately break the logic and confirm the test *fails*.

## Mutation testing (proving a test suite works)
1. Deliberately break the code/policy under test (e.g., invert a validation condition).
2. Re-run the test suite.
3. Confirm it now fails. If it still passes, the test wasn't testing what you thought.
4. Revert the deliberate break.

## Contract testing (preventing the "40 broken consumers" incident)
Before a major module version release: run the new version's plan against a representative sample of real consumer configurations, specifically checking for **unexpected replacement** operations (`["delete","create"]` in plan JSON `resource_changes`), not just "did it apply."

## Cost control for integration tests
- Dedicated sandbox account, never shared dev/staging.
- Tag every test-created resource distinctly (`Purpose = automated-test`).
- Scheduled sweep destroying tagged resources past a TTL threshold, independent of the test framework's own teardown.

Full reference: [`docs/testing.md`](../docs/testing.md), [`interview-questions/09-testing.md`](../interview-questions/09-testing.md), [Lab 11](../labs/lab-11-testing/).
