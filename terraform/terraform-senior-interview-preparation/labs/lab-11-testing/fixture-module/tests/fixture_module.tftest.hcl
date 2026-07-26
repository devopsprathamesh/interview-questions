# Zero-cost native test suite: random/local providers only, no AWS credentials
# or cloud resources involved at all. Mixes plan-mode (fast, free) and
# apply-mode (still free here, but demonstrates the real create-then-destroy
# cycle and guaranteed cleanup behavior described in docs/testing.md §3.

variables {
  environment = "dev"
  report_dir  = "${path.module}/output"
}

# --- Plan-mode: fast, no resources actually created ---
run "valid_environment_plans_cleanly" {
  command = plan

  assert {
    condition     = var.environment == "dev"
    error_message = "Sanity check on the input variable itself"
  }
}

run "invalid_environment_is_rejected" {
  command = plan

  variables {
    environment = "not-a-real-environment"
  }

  expect_failures = [
    var.environment,
  ]
}

# --- Apply-mode: resources are genuinely created, then automatically
#     destroyed at the end of this test file's run - see docs/testing.md §3.
#     This is real proof the module works, not just that its plan looks right. ---
run "apply_creates_a_real_report_file" {
  command = apply

  assert {
    condition     = fileexists(local_file.report.filename)
    error_message = "Expected the report file to actually exist on disk after apply"
  }

  assert {
    # CORRECT assertion: compares the file's real content against an
    # independently-derived expected value (the literal "dev"), NOT against
    # var.environment itself, which would be tautological - see
    # interview-questions/09-testing.md Question 83 for why that anti-pattern
    # is worse than no test at all.
    condition     = jsondecode(file(local_file.report.filename)).environment == "dev"
    error_message = "Expected the report's environment field to be 'dev'"
  }
}
