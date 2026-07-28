# Pointing the Terraform repo at Floci

This covers how to redirect [`terraform/`](../../../terraform/) at a local Floci endpoint instead of real AWS. It assumes Floci is already running (`floci start` + `eval $(floci env)` — see the [top-level README](../README.md)).

## Why the existing config needs an override, not an edit

`environments/dev/versions.tf` in the Terraform repo already defines a real `provider "aws" {}` block and an S3 backend (see [environments/dev/versions.tf](../../../terraform/environments/dev/versions.tf)). Don't hand-edit that file to hardcode `localhost` — you'd have to remember to revert it before ever pointing at real AWS again, and it invites accidentally committing a `localhost` endpoint.

Instead, use Terraform's [override file mechanism](https://developer.hashicorp.com/terraform/language/files/override): any file ending in `_override.tf` is loaded last and merges into (and can override attributes of) a `provider` block with the same label. This lets you keep a `floci_override.tf` in `.gitignore` and never touch the real config.

## `provider` override

Create `environments/dev/floci_override.tf` (not committed):

```hcl
provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3       = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
    iam      = "http://localhost:4566"
    ec2      = "http://localhost:4566"
    eks      = "http://localhost:4566"
    rds      = "http://localhost:4566"
    sts      = "http://localhost:4566"
  }
}
```

Add whichever other services a given lab's module actually calls (e.g. `elasticache`, `kms`, `elb` for the `alb` module) — the AWS provider's `endpoints` block accepts one key per service.

## Backend override

The S3 backend (state storage) needs its own endpoint override — it's configured independently of the `provider "aws"` block and is not affected by the override above. Terraform >= 1.6's S3 backend takes an `endpoints` map:

```hcl
terraform {
  backend "s3" {
    bucket                      = "floci-local-tfstate"
    key                         = "environments/dev/terraform.tfstate"
    region                      = "us-east-1"
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true

    endpoints = {
      s3       = "http://localhost:4566"
      dynamodb = "http://localhost:4566"
    }
  }
}
```

Backend configuration blocks cannot be overridden by `_override.tf` files the way resource/provider blocks can (Terraform requires backend config to be fully known before it reads overrides). The practical workaround used throughout the Terraform repo's labs is `-backend-config` on `terraform init` (see [`environments/dev/backend.hcl.example`](../../../terraform/environments/dev/backend.hcl.example) for the pattern this repo already uses for per-environment backend values) — write a `floci-backend.hcl` with the block above's keys and run:

```bash
terraform init -backend-config=floci-backend.hcl -reconfigure
```

Before first use, create the bucket and lock table through the emulator itself (mirrors [Lab 2: Remote State](../../../terraform/labs/lab-02-remote-state/)'s real bootstrap step, just against Floci):

```bash
aws s3 mb s3://floci-local-tfstate
aws dynamodb create-table \
  --table-name floci-local-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

## Module-by-module expectations

| Module | Expectation against Floci | Why |
|---|---|---|
| [`modules/vpc`](../../../terraform/modules/vpc/) | API objects (VPC/subnet/route table IDs) should create and read back fine | Pure control-plane CRUD, which is exactly what an API emulator is built to handle |
| [`modules/security-groups`](../../../terraform/modules/security-groups/) | Same as VPC | Control-plane only, no real traffic enforcement either way |
| [`modules/iam`](../../../terraform/modules/iam/) | Object creation should work; don't expect real STS federation semantics | See [eks-integration.md](eks-integration.md) for why IRSA specifically breaks down |
| [`modules/eks`](../../../terraform/modules/eks/) | Cluster object creation plausible; whether it actually provisions the same k3s node the EKS repo's `kubectl` commands can reach is untested | This is the one module worth validating first, since the EKS repo depends on its output |
| [`modules/rds`](../../../terraform/modules/rds/) | Per the vendor's claim of real backing Postgres/MySQL containers, this is one of the more plausible modules to actually work end-to-end | Unlike pure API objects, RDS needs a real reachable database to be useful, and that's specifically what Floci claims to provide |
| [`modules/alb`](../../../terraform/modules/alb/) | Object creation plausible; a resolvable DNS name backed by real load-balancing is not | Local emulators generally don't stand up real network load balancers |
| [`modules/observability`](../../../terraform/modules/observability/) | Depends which AWS service it targets (CloudWatch vs. others) — check per-resource | Not covered explicitly on Floci's quickstart page |

Validate starting from [Lab 1](../../../terraform/labs/lab-01-core-workflow/) and [Lab 2](../../../terraform/labs/lab-02-remote-state/) before assuming later labs (especially [Lab 9: EKS Infrastructure](../../../terraform/labs/lab-09-eks-infrastructure/)) work unmodified.
