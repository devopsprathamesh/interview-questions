# Cheat Sheet: Dynamic Inventory

## Minimal `amazon.aws.aws_ec2` plugin config
```yaml
plugin: amazon.aws.aws_ec2
regions: [us-east-1]
filters:
  instance-state-name: running
  tag:Project: myproject
keyed_groups:
  - key: tags.Environment
    prefix: tag_Environment
  - key: tags.Role
    prefix: tag_Role
compose:
  ansible_host: private_ip_address
cache: true
cache_plugin: jsonfile
cache_timeout: 300
```

## Key mechanisms
- `filters` — scopes which instances are even considered. An overly narrow filter produces a **silent zero-host match**, not an error. [Question 11](../interview-questions/02-inventory-variables.md#question-11-the-play-that-matched-zero-hosts)
- `keyed_groups` — derives inventory groups automatically from tag values.
- `compose` — derives `ansible_host` or custom hostvars from instance attributes.
- `cache` — without it, every invocation re-queries every configured account/region combination fresh. At scale, this becomes the dominant runtime cost, and can trigger API throttling. [Question 49](../interview-questions/05-aws-cloud-integration.md#question-49-the-inventory-query-that-got-throttled)

## Standing diagnostic commands
```bash
ansible-inventory -i inventory/aws_ec2.yml --graph     # definitive check: what does this pattern actually resolve to
ansible-inventory -i inventory/aws_ec2.yml --list | jq '._meta.hostvars'
```

## Common failure patterns
| Symptom | Likely cause | Reference |
|---|---|---|
| Zero hosts matched, no error | Tag/filter mismatch, tag rename | [Question 11](../interview-questions/02-inventory-variables.md#question-11-the-play-that-matched-zero-hosts) |
| Same host appears with conflicting facts | Two overlapping inventory sources (static + dynamic) both matching it | [Question 15](../interview-questions/02-inventory-variables.md#question-15-two-inventories-one-confused-host) |
| A specific instance never targeted by security automation | Instance launched without the expected tag at all | [Question 52](../interview-questions/05-aws-cloud-integration.md#question-52-the-tag-that-decided-everything) |
| Inventory resolution alone takes 90+ seconds | No caching, many account/region combinations queried fresh every run | [Question 49](../interview-questions/05-aws-cloud-integration.md#question-49-the-inventory-query-that-got-throttled), [Question 109](../interview-questions/12-performance-scale.md#question-109-the-inventory-that-took-longer-to-resolve-than-the-playbook-took-to-run) |
| Inventory cache directory committed to git | Cache location inside the repo, no `.gitignore` entry | Category 2, Question 21 |

## Guardrail pattern (always include for pattern-targeted plays)
```yaml
- name: Fail fast if the target group is empty
  ansible.builtin.assert:
    that: groups['tag_Role_webserver'] | default([]) | length > 0
    fail_msg: "tag_Role_webserver matched zero hosts - check tags/filters before proceeding"
```
