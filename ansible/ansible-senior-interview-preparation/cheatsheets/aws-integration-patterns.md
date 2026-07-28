# Cheat Sheet: AWS and Cloud Integration Patterns

## Where Terraform ends and Ansible begins
- **Terraform**: infrastructure shape and lifecycle (instances, security groups, IAM roles, VPCs).
- **Ansible**: configuration of what's inside/on top of already-provisioned infrastructure.
- Never let Ansible directly create/modify/destroy infrastructure Terraform also tracks — cross-reference via a read/data lookup only. [Question 43](../interview-questions/05-aws-cloud-integration.md#question-43-where-terraform-ends-and-ansible-begins)

## Multi-account cross-account automation
- Central hub-account identity's permissions scoped to `sts:AssumeRole` against an **explicit allowlist** of target-account role ARNs — never a wildcard.
- Each target account's role trusts only that specific hub role ARN, scoped to that account's actual needs. [Question 42](../interview-questions/04-modules-plugins.md#question-42-one-playbook-five-aws-accounts), [Question 29](../interview-questions/03-roles-collections.md#question-29-retiring-the-ad-hoc-git-tag-roles)

## Least privilege for the automation identity itself
- Derive the actual required IAM policy from **CloudTrail history**, not a guess — the same process regardless of whether the caller is Terraform or Ansible. [Question 47](../interview-questions/05-aws-cloud-integration.md#question-47-the-role-that-could-do-anything-in-every-account)
- Audit the **CI runner's own** IAM permissions and credential storage as a separate layer from Ansible's own configuration (Vault, become) — a security review that stops at "Ansible is configured correctly" misses this entirely. [Question 68](../interview-questions/07-security-vault.md#question-68-the-security-review-that-only-checked-half-the-pipeline)

## Credential rotation
- Prefer AWS-native credential management (Secrets Manager-integrated RDS passwords, etc.) with Ansible **fetching** the current value at deploy time, rather than Ansible generating/rotating credentials itself. [Question 48](../interview-questions/05-aws-cloud-integration.md#question-48-who-rotates-the-password)

## Node lifecycle races (ASG/Spot)
- Scale-in/Spot-interruption during a mid-run patch is an **expected, tolerable** failure mode for cost-optimized fleets — design for it (`any_errors_fatal: false`), don't treat it as an anomaly. [Question 44](../interview-questions/05-aws-cloud-integration.md#question-44-the-patch-that-raced-the-auto-scaler)
- New instances launched mid-run are invisible to that run's already-resolved inventory — the durable fix is golden-AMI-baked baseline configuration (Lab 8), not more frequent push-based runs.

## Tagging as a control plane
- Tag-based automation targeting has a structural blind spot: an instance created outside the normal, tag-enforcing provisioning path is **entirely invisible**, with zero error. Defense requires both prevention (an SCP requiring the tag at launch) **and** independent detection (a periodic full-inventory-vs-tag-filtered-inventory diff). [Question 52](../interview-questions/05-aws-cloud-integration.md#question-52-the-tag-that-decided-everything)

## Testing without paying for AWS
- No `mock_provider`-equivalent exists in Ansible — lean on structural/logic-level testing (mocked or `moto`-based unit tests) for the bulk of coverage, reserving real, cost-controlled sandbox-account testing for a less-frequent tier. [Question 45](../interview-questions/05-aws-cloud-integration.md#question-45-testing-against-aws-without-paying-for-aws), [Question 83](../interview-questions/09-testing-validation.md#question-83-the-mock-that-mocked-away-the-actual-bug)

## Golden AMI (Packer + Ansible)
- Bake configuration at build time (Packer's `ansible` provisioner reusing the same roles as push-based automation) rather than applying it at boot via user-data — eliminates per-boot runtime dependency on Ansible/network reachability. See [Lab 8](../labs/lab-08-packer-ami-baking/).
- Keep the baked kubelet/package versions in sync with the target environment's own version lifecycle — a stale AMI can fail to join a since-upgraded cluster. [Question 59](../interview-questions/06-kubernetes-containers.md#question-59-the-ami-that-ansible-baked-but-kubernetes-wouldnt-boot-correctly)
