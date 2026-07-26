# Cheat Sheet: Provider Aliases

## Basic alias
```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "dns_account"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::111111111111:role/terraform-dns-admin"
  }
}

resource "aws_route53_record" "app" {
  provider = aws.dns_account   # explicit alias reference
  # ...
}
```

## Passing providers into modules
- **Default (unaliased) provider**: inherited automatically by child modules — no `providers = {}` needed.
- **Aliased provider**: must be explicitly passed via the module's `providers` argument.

```hcl
module "dns_records" {
  source = "./modules/dns"
  providers = {
    aws = aws.dns_account
  }
}
```

## Reusable modules needing an aliased provider
```hcl
# inside the module
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.dr]
    }
  }
}
```
```hcl
# consumer
module "rds_with_dr" {
  source = "./modules/rds-with-dr"
  providers = {
    aws.primary = aws.us_east
    aws.dr      = aws.us_west
  }
}
```

## Rules
- A **reusable module should never declare its own `provider` block** — it permanently binds to whatever that block specifies, ignoring anything a caller tries to pass. See [Question 35](../interview-questions/04-providers.md#question-35-the-module-that-could-only-ever-talk-to-one-account).
- Each `provider` alias is a fully independent plugin instance/connection — no cross-alias coordination beyond the resource graph's own dependency edges.
- Multi-region/multi-account modules need one alias per target — there is no single provider configuration that can target two regions/accounts simultaneously.

## Authentication pattern
Local dev: SSO-backed named profile. CI/CD: OIDC federation, short-lived, trust policy scoped to `sub`/`aud` claims (repo + environment). Never long-lived IAM user keys in either context. See [`docs/terraform-architecture.md` §5](../docs/terraform-architecture.md#5-authentication--avoiding-credentials-in-code).
