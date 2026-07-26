# Lab 7: Refactoring Without Recreation

## Objective
Prove — with a real, applied configuration — that `count` → `for_each` migrations and root-to-module restructuring can both be done with **zero resource recreation**, using `moved` blocks.

## Scenario
A configuration manages one SSM parameter per environment using `count`, indexed positionally. The team wants to migrate to `for_each` (to avoid the index-shifting risk from [Question 1](../../interview-questions/01-terraform-core.md#question-1-the-subnet-that-shifted)), and later wants to move the resource into a proper child module as the codebase grows. Both refactors must happen without destroying and recreating a single parameter.

## Skills Practised
- `moved` blocks for `count` → `for_each` migration
- `moved` blocks for root-resource → child-module restructuring
- Verifying a zero-diff plan as the definitive proof of a safe refactor
- Reading `terraform plan` output to distinguish "no changes" from "replace"

## Architecture
```mermaid
flowchart LR
    Phase1["Phase 1: count-based\naws_ssm_parameter.environment_marker[0..2]"] -->|moved blocks| Phase2["Phase 2: for_each-based\naws_ssm_parameter.environment_marker[\"dev\"|\"staging\"|\"production\"]"]
    Phase2 -->|moved block| Phase3["Phase 3: module-restructured\nmodule.marker.aws_ssm_parameter.environment_marker[...]"]
```
Each arrow represents an `apply` that changes **zero** real AWS resources — only Terraform's internal state addressing changes.

## Prerequisites
- [Lab 2](../lab-02-remote-state/) completed
- Completion of [Question 1](../../interview-questions/01-terraform-core.md#question-1-the-subnet-that-shifted) and [Question 9](../../interview-questions/01-terraform-core.md#question-9-converting-a-legacy-count-fleet-to-for_each-without-downtime) reading, since this lab is their hands-on companion

## Directory Structure
```text
lab-07-refactoring-state/
├── README.md
├── versions.tf                          # shared across all 3 phases
├── main.tf.phase1-before                 # copy to main.tf first
├── main.tf.phase2-after                  # copy to main.tf second
├── main.tf.phase3-module-restructure     # copy to main.tf third
└── modules/marker/
    └── main.tf                            # the child module Phase 3 moves into
```

## Step-by-Step Tasks
1. `cp main.tf.phase1-before main.tf`, then `terraform init` and `terraform apply` — this is your fragile, `count`-based starting point.
2. Run `terraform state list` and note the addresses: `aws_ssm_parameter.environment_marker[0]`, `[1]`, `[2]`.
3. `cp main.tf.phase2-after main.tf` (overwriting Phase 1's file) and run `terraform plan`.
4. **Read the plan output carefully** — it must show **0 to add, 0 to change, 0 to destroy**, with the `moved` blocks reported as address changes only.
5. Run `terraform apply` and confirm `terraform state list` now shows `["dev"]`, `["staging"]`, `["production"]` instead of `[0]`, `[1]`, `[2]`.
6. `cp main.tf.phase3-module-restructure main.tf` and repeat the same zero-diff verification for the module restructuring.
7. Confirm `terraform state list` now shows `module.marker.aws_ssm_parameter.environment_marker["dev"]` etc.

## Terraform Configuration
See [`main.tf.phase1-before`](main.tf.phase1-before), [`main.tf.phase2-after`](main.tf.phase2-after), [`main.tf.phase3-module-restructure`](main.tf.phase3-module-restructure), and [`modules/marker/main.tf`](modules/marker/main.tf).

## Commands to Execute
```bash
terraform init -backend-config=../lab-02-remote-state/environment/backend.hcl

# Phase 1
cp main.tf.phase1-before main.tf
terraform apply -auto-approve
terraform state list

# Phase 2 - THE CRITICAL CHECK
cp main.tf.phase2-after main.tf
terraform plan   # MUST show: 0 to add, 0 to change, 0 to destroy
terraform apply -auto-approve
terraform state list

# Phase 3 - THE CRITICAL CHECK AGAIN
cp main.tf.phase3-module-restructure main.tf
terraform plan   # MUST show: 0 to add, 0 to change, 0 to destroy
terraform apply -auto-approve
terraform state list
```

## Expected Output
Both Phase 2 and Phase 3's `terraform plan` output should explicitly show lines like:
```
# aws_ssm_parameter.environment_marker[0] has moved to aws_ssm_parameter.environment_marker["dev"]
Plan: 0 to add, 0 to change, 0 to destroy.
```
Any `+`/`-` (create/destroy) appearing here means the `moved` block mapping is wrong — stop and re-check the addresses before applying.

## Validation
```bash
# Confirm the same 3 SSM parameters exist throughout, untouched, across all 3 phases
aws ssm get-parameters-by-path --path /lab-07 --recursive --query 'Parameters[].{Name:Name,LastModifiedDate:LastModifiedDate}'
# LastModifiedDate should NOT change between Phase 1's apply and Phase 3's apply -
# proving these are the SAME parameter objects throughout, never recreated.
```

## Failure Injection
Delete the `moved` blocks from `main.tf.phase2-after` (comment them out), copy it over `main.tf`, and run `terraform plan` again. Observe the plan now proposes destroying all 3 `count`-indexed parameters and creating 3 new `for_each`-keyed ones — this is the exact "count → for_each without moved blocks" mistake from [Question 9](../../interview-questions/01-terraform-core.md#question-9-converting-a-legacy-count-fleet-to-for_each-without-downtime), made visible in a real plan.

## Troubleshooting Exercise
Intentionally get one `moved` block's `from`/`to` mapping wrong (e.g., map index `0` to `"staging"` instead of `"dev"`) and observe what the resulting plan shows. Determine from the plan output alone whether this specific mistake would have caused a replacement or just an attribute update, and explain why.

## Cleanup
```bash
terraform destroy
```
**Chargeable resources:** none — SSM Standard parameters are free.

## Interview Questions Connected to This Lab
- [Question 1: The subnet that shifted](../../interview-questions/01-terraform-core.md#question-1-the-subnet-that-shifted)
- [Question 9: Converting a legacy count fleet to for_each without downtime](../../interview-questions/01-terraform-core.md#question-9-converting-a-legacy-count-fleet-to-for_each-without-downtime)
- [Question 26: Four modules deep](../../interview-questions/03-modules.md#question-26-four-modules-deep)
- [Question 21: Splitting one state for two teams](../../interview-questions/02-state-management.md#question-21-splitting-one-state-for-two-teams)

## Production Considerations
- In a real production migration, perform each phase as its own separate, reviewed PR with the zero-diff plan output attached as evidence in the PR description — never bundle a refactor with unrelated functional changes in the same apply.
- For a reusable module (not a root configuration like this lab), `moved` blocks are especially valuable because they apply automatically for every consumer on upgrade, without each consumer needing to run manual `state mv` commands themselves.

## Advanced Challenge
Perform the equivalent of Phase 2's migration using `terraform state mv` commands instead of `moved` blocks (comment out the `moved` blocks and use the CLI command directly), and compare the two approaches: what does each require the operator to remember, and which is safer for a module consumed by many other teams?
