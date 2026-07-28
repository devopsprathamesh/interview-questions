# Pointing the Ansible repo at Floci

This covers how to redirect [`ansible/`](../../../ansible/) at a local Floci endpoint. Read the caveat in the next section before investing time in this — it's the single most important thing to understand about using an AWS emulator with Ansible specifically.

## The core limitation: Ansible needs a real host to configure

Terraform and the AWS CLI only need an API that answers HTTP requests correctly — that's exactly what an emulator provides. Ansible's actual job, in most of this repo's labs, is different: it opens an SSH connection to a host and mutates its running state (installs packages, writes config, restarts services). Floci's own quickstart page describes real backing containers for stateful services like RDS and Redis, but says nothing about whether its EC2 emulation produces an instance you can actually SSH into.

Practically, that puts this repo's Ansible labs into two very different buckets:

| Bucket | Labs | Floci outlook |
|---|---|---|
| Pure AWS API calls (tag, describe, create/destroy metadata) | [Lab 3: Dynamic Inventory](../../../ansible/labs/lab-03-dynamic-inventory/) (the *enumeration* half) | Plausible — this is exactly what an API emulator is for |
| Real SSH-based configuration management | [Lab 1: Core Workflow](../../../ansible/labs/lab-01-core-workflow/), [Lab 6: Error Handling](../../../ansible/labs/lab-06-error-handling-and-refactoring/), [Lab 7: AWS Configuration Management](../../../ansible/labs/lab-07-aws-configuration-management/), [Lab 8: Packer AMI Baking](../../../ansible/labs/lab-08-packer-ami-baking/), [Lab 10: Security Hardening](../../../ansible/labs/lab-10-security-hardening/) | Untested and, for AMI baking specifically, unlikely — baking an AMI is inherently an operation against a real EC2 instance lifecycle |

Before assuming any configuration-management lab works, test the smallest possible case: point the dynamic inventory at Floci, see what it enumerates, and check whether `ansible -m ping` against one of those hosts actually connects. If it doesn't, those labs still need either a real (even if minimal, single-instance) EC2 target or a substitute like a local Docker container/Vagrant box reached over SSH — which is a reasonable fallback and is what [Lab 11: Molecule Testing](../../../ansible/labs/lab-11-molecule-testing/) already does for role testing independent of any cloud provider.

## Environment variables

`amazon.aws` collection modules are built on `boto3`/`botocore`, which respect `AWS_ENDPOINT_URL` directly — the same variables `floci env` exports are sufficient for the AWS-calling parts of any playbook:

```bash
eval $(floci env)
ansible-playbook site.yml -i inventory/aws_ec2.yml
```

## Dynamic inventory

The repo's inventory files (e.g. [`labs/lab-03-dynamic-inventory/inventory/aws_ec2.yml`](../../../ansible/labs/lab-03-dynamic-inventory/inventory/aws_ec2.yml)) use the `amazon.aws.aws_ec2` plugin, which also reads `AWS_ENDPOINT_URL` from the environment — no changes to the YAML are strictly required once the env vars are exported. If your installed collection version exposes an explicit `endpoint_url` inventory-plugin option (check with `ansible-doc -t inventory amazon.aws.aws_ec2`), setting it directly in the inventory file is more explicit and doesn't depend on the calling shell's environment:

```yaml
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
filters:
  instance-state-name: running
  tag:Project: ansible-senior-interview-prep
```

(unchanged from the existing file — the environment variable approach above is the one that doesn't require editing tracked inventory files at all).

## Module-level override

For a single task rather than a whole run, `amazon.aws` modules accept `endpoint_url` directly:

```yaml
- name: Tag an emulated instance
  amazon.aws.ec2_tag:
    resource: "{{ instance_id }}"
    endpoint_url: "http://localhost:4566"
    tags:
      Environment: floci-local
```

Or set it once for every AWS task in a play via `module_defaults`:

```yaml
- hosts: localhost
  module_defaults:
    group/amazon.aws.aws:
      endpoint_url: "http://localhost:4566"
  tasks:
    - ...
```

## What to validate first

1. `aws ec2 describe-instances --endpoint-url $AWS_ENDPOINT_URL` — confirms Floci's EC2 emulation returns something at all.
2. Point [Lab 3](../../../ansible/labs/lab-03-dynamic-inventory/)'s inventory at Floci and run `ansible-inventory -i inventory/aws_ec2.yml --graph` — confirms enumeration works.
3. `ansible -i inventory/aws_ec2.yml all -m ping` — the real test of whether Floci's EC2 emulation is SSH-reachable, which determines whether Buckets 2 above is usable at all.

Only after step 3 succeeds is it worth adapting the configuration-management labs themselves.
