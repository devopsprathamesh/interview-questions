# Module: vpc

Provisions a VPC with public and private subnets spread across the given availability zones, an Internet Gateway, a cost-aware NAT strategy, and an optional free S3 Gateway endpoint.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-dev"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  nat_strategy       = "single" # cost-conscious default; use "per_az" for production HA

  tags = {
    Environment = "dev"
  }
}
```

## Design notes

- **`for_each`, never `count`**, for every AZ-indexed resource (subnets, NAT gateways, route tables) — see [`docs/terraform-internals.md` §4](../../docs/terraform-internals.md#4-count-vs-for_each--and-the-index-shifting-failure-mode). Removing one AZ from `availability_zones` only affects that AZ's resources.
- **`nat_strategy` is an explicit, named trade-off**, not a boolean — `"none"` (no egress, lowest cost), `"single"` (one shared NAT, cost-conscious, single point of failure), `"per_az"` (one NAT per AZ, full HA, highest cost). See [`docs/`](../../docs/) HA/DR and networking guidance before choosing for a production workload.
- **Outputs are grouped by AZ as maps**, not flat lists, so consumers can reliably associate a subnet with its AZ without a fragile positional-index assumption.
- **`precondition` blocks on subnet outputs** assert the module actually produced one subnet per requested AZ — a cheap, high-value sanity check against a subtle `for_each`/count-mismatch bug.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Name prefix for every resource |
| `cidr_block` | `string` | — (required) | VPC CIDR, e.g. `10.0.0.0/16` |
| `availability_zones` | `list(string)` | — (required) | At least 2 AZs |
| `nat_strategy` | `string` | `"single"` | `none` \| `single` \| `per_az` |
| `enable_s3_endpoint` | `bool` | `true` | Free Gateway endpoint for S3 |
| `tags` | `map(string)` | `{}` | Additional tags |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR |
| `public_subnet_ids` | Map of AZ → public subnet ID |
| `private_subnet_ids` | Map of AZ → private subnet ID |
| `public_route_table_id` | Single shared public route table ID |
| `private_route_table_ids` | Map of AZ → private route table ID |
| `nat_gateway_ids` | Map of AZ → NAT gateway ID (empty if `nat_strategy = "none"`) |

## Versioning

This module follows semantic versioning once published to a registry (see [`docs/module-design.md` §5](../../docs/module-design.md#5-module-versioning-and-semantic-versioning)). Within this repository it's consumed via a relative path for teaching simplicity; a real deployment should pin an explicit registry version with a `~>` constraint.

## Testing

See [`tests/vpc_basic.tftest.hcl`](tests/vpc_basic.tftest.hcl) and [Lab 4](../../labs/lab-04-module-design/) and [Lab 11](../../labs/lab-11-testing/) for hands-on test-writing exercises against this module.
