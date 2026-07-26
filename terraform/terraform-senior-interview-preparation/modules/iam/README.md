# Module: iam

A least-privilege application execution role: an assume-role trust policy scoped to one AWS service principal, plus narrow, additive policy statements only for the specific access an application actually needs (Secrets Manager read, S3 read-only) — never a wildcard grant.

## Usage
```hcl
module "app_role" {
  source = "../../modules/iam"

  name                        = "my-app"
  trusted_service             = "ec2.amazonaws.com"
  secrets_manager_secret_arns = [module.rds.master_user_secret_arn]
}
```

## Design notes
- No statement in this module ever uses `"Resource": "*"` — every grant is scoped to the specific ARNs passed in.
- `secrets_manager_secret_arns` and `s3_read_only_bucket_arns` both default to empty lists — this module grants **nothing** beyond the ability to assume the role until you explicitly pass something, following the principle from [Question 63](../../interview-questions/07-security.md#question-63-the-ci-role-that-could-do-almost-anything): derive and grant exactly what's needed, never a broad default "to unblock the team."

## Inputs
`name`, `trusted_service` (default `ec2.amazonaws.com`), `secrets_manager_secret_arns` (default `[]`), `s3_read_only_bucket_arns` (default `[]`), `create_instance_profile` (default true — set false for ECS/EKS task roles), `tags`.

## Outputs
`role_arn`, `role_name`, `instance_profile_name` (null if `create_instance_profile = false`).
