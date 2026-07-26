# Module: security-groups

Creates a security group with ingress/egress rules as **standalone, `for_each`-keyed resources**, not inline blocks — so adding or removing one rule never produces a diff touching any other rule.

## Usage

```hcl
module "app_sg" {
  source = "../../modules/security-groups"

  name   = "app"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    https_from_alb = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
    }
    health_check_public = {
      from_port    = 80
      to_port      = 80
      protocol     = "tcp"
      cidr_blocks  = ["0.0.0.0/0"]
      allow_public = true # required whenever cidr_blocks includes 0.0.0.0/0
    }
  }

  egress_rules = {
    all_outbound = {
      from_port = 0
      to_port   = 0
      protocol  = "-1"
    }
  }
}
```

## Design notes

- **`allow_public` is a mandatory, explicit flag** for any rule using `0.0.0.0/0` — the module's `validation` block rejects an unqualified public CIDR outright. This is deliberate friction against the exact accidental-public-exposure scenario in [Question 2](../../interview-questions/01-terraform-core.md#question-2-the-security-group-nobody-could-safely-resize).
- **No default egress-allow-all** — `egress_rules` defaults to an empty map, meaning a security group with no egress rules specified has *no* egress at all, requiring a conscious, explicit choice rather than inheriting AWS's historical default-allow-all security group behavior implicitly.
- **`create_before_destroy`** on the security group itself, since other resources (ALB listeners, instances) commonly reference it — replacing it destroy-first would briefly break every dependent resource's association.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Security group name |
| `vpc_id` | `string` | — (required) | VPC ID |
| `description` | `string` | `"Managed by Terraform"` | Security group description |
| `ingress_rules` | `map(object(...))` | `{}` | Keyed ingress rules; `allow_public` required for `0.0.0.0/0` |
| `egress_rules` | `map(object(...))` | `{}` | Keyed egress rules; no implicit allow-all |
| `tags` | `map(string)` | `{}` | Additional tags |

## Outputs

| Name | Description |
|---|---|
| `security_group_id` | Security group ID |
| `security_group_arn` | Security group ARN |
