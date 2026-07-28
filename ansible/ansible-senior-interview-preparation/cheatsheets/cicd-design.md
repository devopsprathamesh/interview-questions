# Cheat Sheet: CI/CD Design for Ansible

## The reference pipeline
```text
syntax-check (fast, structural only)
  -> lint (ansible-lint + yamllint)
  -> molecule-test (functional + idempotency)
  -> [merge]
  -> review (--check --diff, human-reviewed)
  -> apply (SAME pinned commit/EE image, immediately after approval)
```

## Non-negotiables
- **Concurrency control**: `concurrency: {group: deploy-production, cancel-in-progress: false}` — never allow two runs to target the same environment simultaneously. Ansible has no automatic state-locking equivalent to Terraform's. [Question 77](../interview-questions/08-cicd-automation.md#question-77-the-concurrent-awx-runs-that-collided)
- **Pinned Execution Environment**: local development and CI must use the *same* EE image (`ansible-navigator`), never independently-installed local Ansible/collection versions. [Question 73](../interview-questions/08-cicd-automation.md#question-73-the-execution-environment-that-drifted-from-every-developers-laptop)
- **Structured output**: use a JSON callback plugin for anything CI needs to parse programmatically — never regex human-readable output. [Question 37](../interview-questions/04-modules-plugins.md#question-37-the-output-nobody-could-parse)
- **Complete-coverage verification**: exit code 0 only means "no task failed for the hosts that were included" — it says nothing about whether the *intended, full* host set was actually covered. Verify actual host count against an independent expected count for any dynamic-inventory-driven pipeline. [Question 76](../interview-questions/08-cicd-automation.md#question-76-the-pipeline-that-couldnt-tell-success-from-silence)

## AWX/Automation Platform specifics
- **Prevent Simultaneous Job Runs**: enable per-Job-Template, the AWX-native concurrency control.
- **Surveys**: use constrained `multiplechoice` types for consequential inputs (target environment, destructive-action toggles) — never free text. [Question 70](../interview-questions/08-cicd-automation.md#question-70-the-survey-that-let-anyone-target-production)
- **Workflow Templates**: explicitly configure every node's "on failure" edge — don't rely on default behavior for what happens when an intermediate step fails. [Question 74](../interview-questions/08-cicd-automation.md#question-74-the-workflow-template-that-half-succeeded)
- **Credentials**: scope per-Job-Template to actual need — never one broad credential shared across every template regardless of risk. [Question 69](../interview-questions/08-cicd-automation.md#question-69-the-job-template-that-ran-with-too-much-power)
- **HA**: a single-node AWX instance is a single point of failure for the *entire organization's automation capability*, including incident remediation. Multi-node HA + a tested break-glass fallback (direct `ansible-playbook` execution bypassing AWX). [Question 78](../interview-questions/08-cicd-automation.md#question-78-the-awx-instance-that-was-a-single-point-of-failure-for-everything)

## Notification / failure visibility
- Every scheduled Job Template needs an explicit failure notification, routed somewhere someone will actually see it — job history logging alone provides no active alerting. [Question 71](../interview-questions/08-cicd-automation.md#question-71-the-scheduled-job-template-nobody-remembered-existed)
