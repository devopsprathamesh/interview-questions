# Lab 15: Enterprise Capstone

## Objective
Integrate every module and pattern built across this repository into one complete, layered, three-tier AWS platform — networking, load balancing, compute, and database — demonstrating state isolation, module reuse, environment promotion, security, HA, and operational documentation as a single coherent system rather than fifteen separate exercises.

## Scenario
You're the platform engineer responsible for standing up a new customer-facing application's complete infrastructure from scratch, following every standard this repository has established: layered state (`foundation` → `platform` → `application`), cross-layer references via SSM Parameter Store (never shared state), least-privilege IAM, mandatory encryption, and full operational documentation a new on-call engineer could actually use.

## Skills Practised
- Composing seven reusable modules (`vpc`, `security-groups`, `alb`, `rds`, `iam`, `observability`, and optionally `eks` per [Lab 9](../lab-09-eks-infrastructure/)) into one coherent platform
- Layered state architecture with cross-layer SSM Parameter Store references
- Environment-aware sizing (dev vs. production trade-offs) applied consistently across every layer
- Writing genuine operational documentation, not just Terraform code

## Architecture
See [`OPERATIONS.md`](OPERATIONS.md) for the full architecture diagram and operational reference. Summary: `foundation/` (VPC, subnets, security groups) → `platform/` (ALB, observability) → `application/` (RDS, IAM, Auto Scaling Group), each with independent state, connected via SSM Parameter Store, never `terraform_remote_state`.

## Prerequisites
- [Lab 2](../lab-02-remote-state/) (remote backend), [Lab 4](../lab-04-module-design/) (`vpc`/`security-groups`), [Lab 8](../lab-08-aws-networking/) (networking patterns), and ideally [Lab 12](../lab-12-cicd-pipeline/)/[Lab 13](../lab-13-policy-as-code/) (to wire this capstone into the same pipeline/policy gates) completed
- **A real, budgeted willingness to incur meaningful AWS cost** for anything beyond a scaled-down `dev` run — see [`OPERATIONS.md`](OPERATIONS.md#cost-considerations) before applying `production`-shaped settings

## Directory Structure
```text
lab-15-enterprise-capstone/
├── README.md
├── OPERATIONS.md            # the operational documentation deliverable
├── foundation/               # own state - VPC, subnets, security groups
│   ├── versions.tf, variables.tf, main.tf, outputs.tf
│   ├── backend.hcl.example, terraform.tfvars.example
├── platform/                 # own state - ALB, observability
│   └── (same file pattern)
└── application/              # own state - RDS, IAM, Auto Scaling Group
    ├── (same file pattern)
    └── user_data.sh.tftpl

modules/{vpc,security-groups,alb,rds,iam,observability}/   # every module this capstone composes
```

## Step-by-Step Tasks
1. **Start small**: apply with `dev`-shaped settings first (2 AZs, `nat_strategy = "single"`, `db_multi_az = false`, `desired_capacity = 1`) to validate the whole three-layer chain works before committing to production-scale cost.
2. Copy each layer's `backend.hcl.example` and `terraform.tfvars.example`, filling in real values (Lab 2's bucket/table, a real AMI ID for `application`).
3. Apply in strict order: `foundation` → `platform` → `application`. Confirm each layer's SSM parameters exist (`aws ssm get-parameters-by-path --path /capstone/dev/`) before proceeding to the next.
4. `curl http://$(cd platform && terraform output -raw alb_dns_name)/healthz` — expect a connection (even if the demo `user_data.sh.tftpl` doesn't run a real health-check-passing app; this proves the network path, not application correctness — see the Troubleshooting Exercise).
5. Read [`OPERATIONS.md`](OPERATIONS.md) in full and confirm you understand every cross-layer dependency before considering the capstone complete.
6. Once `dev` is fully validated, decide deliberately whether to also apply `staging`/`production`-shaped settings, given the cost implications in [`OPERATIONS.md`](OPERATIONS.md#cost-considerations).

## Terraform Configuration
See [`foundation/main.tf`](foundation/main.tf), [`platform/main.tf`](platform/main.tf), and [`application/main.tf`](application/main.tf).

## Commands to Execute
```bash
# Layer 1
cd foundation
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars   # edit both
terraform init -backend-config=backend.hcl && terraform apply

# Layer 2
cd ../platform
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl && terraform apply

# Layer 3
cd ../application
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars   # set a real ami_id
terraform init -backend-config=backend.hcl && terraform apply
```

## Expected Output
Three independently-applied states, each `terraform plan` afterward reporting zero changes. `platform`'s `alb_dns_name` output resolves and the ALB is reachable (though the demo app tier doesn't run a real HTTP server, so health checks will show unhealthy targets — see Troubleshooting Exercise below for what a real deployment would need).

## Validation
```bash
# Confirm state isolation: application's plan/apply never requires foundation's
# or platform's state, only their published SSM parameters
aws ssm get-parameters-by-path --path "/capstone/dev/" --recursive

# Confirm the RDS security group only accepts connections from the app tier,
# never a CIDR range
aws ec2 describe-security-groups --group-ids "$(cd application && terraform output -json | jq -r ...)" \
  --query 'SecurityGroups[0].IpPermissions'
```

## Failure Injection
Destroy the `foundation` layer's state (do **not** actually run this against a real environment you care about — use a throwaway `dev` apply specifically for this exercise) and attempt to apply `application` — observe it fails cleanly with an SSM parameter-not-found error, rather than silently proceeding with stale or wrong values. This proves the cross-layer coupling is at least fail-fast, even though (per [`OPERATIONS.md`](OPERATIONS.md#why-three-states-not-one)) it doesn't eliminate the dependency entirely.

## Troubleshooting Exercise
The `application` layer's `user_data.sh.tftpl` is deliberately a stub (it logs a message, it doesn't run a real HTTP server on port 8080) — meaning the ALB target group will show unhealthy targets and the health check will never pass. This is intentional: extend the launch template's `user_data` to install and start a minimal HTTP server (even a one-line Python `http.server` bound to 8080 with a `/healthz` route) and confirm targets become healthy — a hands-on exercise in closing the gap between "Terraform applied successfully" and "the application actually works," exactly the theme of [Question 81](../../interview-questions/09-testing.md#question-81-choosing-the-right-tool-for-does-this-actually-work).

## Cleanup
```bash
# Reverse order: application first, then platform, then foundation
cd application && terraform destroy
cd ../platform && terraform destroy
cd ../foundation && terraform destroy
```
**Chargeable resources — read [`OPERATIONS.md`](OPERATIONS.md#cost-considerations) in full before applying.** At minimum: NAT gateway(s), ALB, RDS instance, EC2 instances. **Verify current AWS pricing yourself.** Do not leave a production-shaped capstone running unattended; destroy promptly after completing your validation.

## Interview Questions Connected to This Lab
This capstone is the hands-on companion to the entire repository, but especially:
- [Question 43: A hundred accounts, several regions, one Terraform estate](../../interview-questions/05-aws-architecture.md#question-43-a-hundred-accounts-several-regions-one-terraform-estate)
- [Question 15: The plan that took twenty minutes](../../interview-questions/02-state-management.md#question-15-the-plan-that-took-twenty-minutes) (the layered-state motivation)
- [Question 16: The outage that started in someone else's state](../../interview-questions/02-state-management.md#question-16-the-outage-that-started-in-someone-elses-state) (why SSM parameters, not `terraform_remote_state`)
- [Question 99 through 104 across `11-ha-dr.md`](../../interview-questions/11-ha-dr.md)
- [Question 118 through 120 across `15-leadership-design.md`](../../interview-questions/15-leadership-design.md)

## Production Considerations
See [`OPERATIONS.md`](OPERATIONS.md) in full — it is written as the production operational reference for exactly this platform, not just a lab appendix.

## Advanced Challenge
1. Wire this capstone's three layers into the [Lab 12](../lab-12-cicd-pipeline/) pipeline and [Lab 13](../lab-13-policy-as-code/) policy gates as three additional matrixed environments, applying the same PR-validation-then-approved-apply discipline used for `environments/dev|staging|production`.
2. Implement the full cross-region DR extension described in [`OPERATIONS.md`](OPERATIONS.md#disaster-recovery-design-as-currently-built-vs-what-would-be-needed) — a second region's `foundation`/`platform`/`application` layers, an RDS cross-region read replica, and a real, timed failover drill measuring actual RTO against a target you set in advance.
