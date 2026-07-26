# Module: alb

Public Application Load Balancer with an HTTP listener (redirects to HTTPS if a certificate is provided) and an HTTPS listener with a modern TLS policy.

## Usage
```hcl
module "alb" {
  source = "../../modules/alb"

  name              = "my-app"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = values(module.vpc.public_subnet_ids)
  security_group_id = module.alb_security_group.security_group_id
  certificate_arn   = aws_acm_certificate.app.arn
}
```

## Inputs
`name`, `vpc_id`, `public_subnet_ids` (min 2), `security_group_id`, `target_port` (default 8080), `health_check_path` (default `/healthz`), `certificate_arn` (null = HTTP-only, lab convenience), `enable_deletion_protection` (default false), `tags`.

## Outputs
`alb_arn`, `alb_dns_name`, `target_group_arn`.

## Production considerations
Always supply `certificate_arn` in production — an HTTP-only ALB is a lab convenience, never a real deployment pattern. Set `enable_deletion_protection = true` for production, and follow the two-step decommission process ([Question 3](../../interview-questions/01-terraform-core.md#question-3-decommissioning-a-prevent_destroy-protected-resource)) if it ever needs to be torn down.
