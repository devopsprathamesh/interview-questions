# An artificial delay so an apply here takes long enough to give you a real
# window to attempt a second, concurrent operation against the same state -
# this is a deliberate lab technique, not a production pattern (see docs on
# time_sleep's legitimate vs. illegitimate uses in interview-questions/01-terraform-core.md
# Question 98).
resource "time_sleep" "simulate_long_apply" {
  create_duration = "${var.apply_delay_seconds}s"

  triggers = {
    # forces a new sleep (and thus a new lock-held window) each time this changes
    run_marker = var.run_marker
  }
}

resource "aws_ssm_parameter" "marker" {
  name       = "/${var.project_name}/lock-test-marker"
  type       = "String"
  value      = "run-${var.run_marker}"
  depends_on = [time_sleep.simulate_long_apply]
}
