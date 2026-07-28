# Module: rds

An RDS instance with mandatory encryption at rest (its own KMS key), an AWS-managed master credential (never a Terraform-supplied plaintext password — see [`docs/security.md` §1](../../docs/security.md#1-secrets-in-state--the-fact-every-senior-engineer-must-internalize)), a dedicated security group accepting connections only from explicitly-listed other security groups, and `deletion_protection = true` by default.

## Usage
```hcl
module "rds" {
  source = "../../modules/rds"

  name                       = "my-app-db"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = values(module.vpc.private_subnet_ids)
  allowed_security_group_ids = [module.app_security_group.security_group_id]
  multi_az                   = true # production
}
```

## Design notes
- **No `password` argument at all** — `manage_master_user_password = true` delegates credential generation and rotation entirely to AWS Secrets Manager, so no plaintext secret ever passes through Terraform state.
- **`deletion_protection = true` by default** — decommissioning requires the deliberate two-step process from [Question 3](../../interview-questions/01-terraform-core.md#question-3-decommissioning-a-prevent_destroy-protected-resource), not an accidental `terraform destroy`.
- **`multi_az` is HA, not DR** — see [Question 103](../../interview-questions/11-ha-dr.md#question-103-multi-az-isnt-multi-region) for why this doesn't protect against a full regional outage.
- **Security group accepts references, not CIDRs** — `allowed_security_group_ids` wires up `referenced_security_group_id`-based rules, so access is scoped to specific security groups (e.g., the app tier) rather than a CIDR range.

## Inputs
`name`, `vpc_id`, `subnet_ids` (min 2), `allowed_security_group_ids`, `engine` (default `postgres`), `engine_version`, `instance_class` (default `db.t3.small` — deliberately not oversized), `allocated_storage`, `multi_az` (default false), `deletion_protection` (default true), `backup_retention_period` (default 7), `tags`.

## Outputs
`db_instance_id`, `db_endpoint`, `db_security_group_id`, `master_user_secret_arn`.

## Cost warning
RDS instances bill hourly regardless of `instance_class`, plus storage and (if `multi_az = true`) a second instance's worth of compute. **Verify current RDS pricing** before applying, especially with `multi_az = true`.
