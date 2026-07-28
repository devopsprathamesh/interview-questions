# Floci — Local AWS Setup

A guide for running the [`terraform/`](../../terraform/terraform-senior-interview-preparation/README.md), [`ansible/`](../../ansible/ansible-senior-interview-preparation/README.md), and [`eks/`](../../eks/eks-senior-interview-preparation/README.md) labs against a **local AWS emulator** ([Floci](https://floci.io/aws/#quickstart)) instead of a real, chargeable AWS account.

This directory is not another interview-question bank. It is a practical setup layer: install Floci once, point the three companion repos at it, and work through whichever of their labs actually function against an emulator — for zero AWS cost.

## What Floci is

Per its own site (claims below are the vendor's, not independently verified by this repo — see [Honesty and unverified claims](#honesty-and-unverified-claims)):

- A local AWS emulator built on Quarkus Native, positioned as a drop-in LocalStack-style replacement.
- Claims support for 68 AWS services, including S3, DynamoDB, Lambda, EC2, ECS, EKS, RDS, ElastiCache, IAM, KMS, Secrets Manager, Route 53, API Gateway, Step Functions, Athena, OpenSearch, and more.
- Claims to orchestrate **real** backing containers for stateful services (actual Postgres/MySQL for RDS, actual Redis for ElastiCache, actual Kafka for MSK) rather than only mocking API responses — and, notably for the EKS repo, claims EKS support "spins up a real k3s node" rather than stubbing the Kubernetes API.
- No AWS account or auth token required. Default fake credentials (`test` / `test`) work out of the box.

## Install

Pick one (from the vendor's quickstart page):

```bash
# Homebrew (macOS/Linux)
brew install floci-io/floci/floci

# curl installer
curl -fsSL https://floci.io/install.sh | sh

# PowerShell (Windows)
iwr https://floci.io/install.ps1 | iex

# Docker, if you'd rather not install a binary
docker run -d --name floci \
  -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:latest
```

This repo does not install or run Floci on your behalf — the scripts in [`scripts/`](scripts/) are meant for you to read and run yourself, not something executed as part of building this documentation.

## Quickstart

```bash
floci start                 # starts the emulator, default endpoint http://localhost:4566
eval $(floci env)           # exports AWS_ENDPOINT_URL, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION
```

Or set the environment manually (equivalent to what `floci env` exports):

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Verify it's up before touching any of the companion repos:

```bash
./scripts/verify-floci.sh
```

Other useful commands the vendor documents: `floci status`, `floci logs --follow`, `floci stop`, `floci doctor`, `floci snapshot save <name>` / `floci snapshot restore <name>` (the snapshot commands are particularly useful for resetting state between labs).

## Capability matrix

The honest question isn't "does Floci work" — it's "which parts of *these specific labs* can actually run against an emulator." None of this has been executed against a real Floci instance by the authors of this repo (see [Honesty and unverified claims](#honesty-and-unverified-claims)); treat the table below as a starting hypothesis to validate lab-by-lab, not a guarantee.

| Companion repo | Likely to work | Likely degraded or won't work | Details |
|---|---|---|---|
| [Terraform](docs/terraform-integration.md) | S3 backend state, DynamoDB lock table, S3/DynamoDB/IAM/EC2/RDS resource CRUD | Multi-AZ networking realism, NAT gateway egress behavior, ALB DNS/health-check behavior, anything depending on real routing | [docs/terraform-integration.md](docs/terraform-integration.md) |
| [Ansible](docs/ansible-integration.md) | `amazon.aws` API calls (describe/tag/create against the emulated control plane), dynamic inventory enumeration | Anything requiring SSH into an emulated EC2 "instance" (most of the configuration-management labs), Packer AMI baking | [docs/ansible-integration.md](docs/ansible-integration.md) |
| [EKS](docs/eks-integration.md) | Core Kubernetes primitives via `kubectl` against the real k3s node Floci provisions — Deployments, Services, most manifest/Helm labs | IRSA/OIDC federation with real IAM, AWS Load Balancer Controller provisioning real ALBs, EBS/EFS CSI dynamic provisioning, Karpenter's real EC2 Fleet calls | [docs/eks-integration.md](docs/eks-integration.md) |

## Honesty and unverified claims

This repo collection's established discipline (see the root [README's "Validation and honesty" section](../../README.md#validation-and-honesty)) is to never claim something works when it hasn't actually been run. That discipline applies especially hard here:

- The performance and compatibility figures on Floci's marketing page (startup time, memory footprint, "100% pass rate" test suite claims) are the vendor's own claims, summarized from their website. They are not repeated here as fact.
- Floci's own quickstart page does **not** document Terraform- or Ansible-specific configuration. Everything in [`docs/terraform-integration.md`](docs/terraform-integration.md) and [`docs/ansible-integration.md`](docs/ansible-integration.md) is derived from standard LocalStack-style integration patterns (endpoint overrides, `AWS_ENDPOINT_URL`) applied to this repo's actual Terraform/Ansible code — not copied from Floci's docs, because those specifics aren't there.
- The EKS page states Floci "spins up a real k3s node" for EKS support, which is a meaningfully stronger claim than most local AWS emulators make for EKS (many just stub the API). Even taking that at face value, a real k3s control plane is still not a real multi-AZ, IAM-integrated EKS control plane — see [docs/eks-integration.md](docs/eks-integration.md) for exactly where that distinction matters.
- No `terraform`, `ansible`, `kubectl`, or `floci` binary was available when this documentation was written, so none of the commands below have been mechanically executed. You will be the first to run them — expect the same minor friction as any hands-on material nobody has executed yet, and please treat the capability matrix above as something to correct once you've actually tried it.

## Cleanup

```bash
floci stop
```

Since nothing here touches a real AWS account, there is no billing cleanup required — that's the entire point of this directory. See the root [README's cost warning](../../README.md#cost-warning) for which labs in the companion repos still need real AWS (and therefore still need real cleanup) if you choose to run them against a real account instead.
