# Cheat Sheet: Performance and Scale

## The five levers, composed together
| Lever | Setting | Effect |
|---|---|---|
| Concurrency | `forks` (default 5) | The primary lever — increase substantially for large fleets, validated against control-node capacity. [Question 105](../interview-questions/12-performance-scale.md#question-105-the-forty-minute-patch-that-should-have-taken-four) |
| Execution ordering | `strategy: linear` (default) vs `free` | `free` removes the per-task synchronization barrier — but is capped by `forks`, and risky for tasks with implicit cross-host ordering assumptions. [Question 106](../interview-questions/12-performance-scale.md#question-106-the-free-strategy-that-freed-nothing) |
| Fact-gathering | `gather_facts: false` + filtered `setup` | Full fact-gathering is expensive at scale if only a few facts are actually used. [Question 107](../interview-questions/12-performance-scale.md#question-107-the-fact-gathering-that-gathered-too-much) |
| Connection overhead | `pipelining = True` | Eliminates a separate SFTP/SCP module-transfer step per task. Requires `requiretty` NOT set in sudoers. [Question 108](../interview-questions/12-performance-scale.md#question-108-the-pipeline-connection-setting-nobody-had-heard-of) |
| Inventory resolution | `cache: true` + scoped `regions`/`filters` | Without caching, every invocation re-queries every account/region combination fresh. [Question 109](../interview-questions/12-performance-scale.md#question-109-the-inventory-that-took-longer-to-resolve-than-the-playbook-took-to-run) |

## `ansible.cfg` performance block
```ini
[defaults]
forks = 50
strategy = free   # only if task ordering genuinely doesn't matter across hosts
gathering = smart

[ssh_connection]
pipelining = True
```

## At genuinely large scale (thousands of hosts)
- **Profile first** — benchmark a representative subset to see where time is actually spent before tuning blindly.
- Consider **partitioning** a single, monolithic inventory/pipeline into per-application or per-team units once management genuinely becomes unwieldy. [Question 18](../interview-questions/02-inventory-variables.md#question-18-the-inventory-that-grew-too-large-to-plan-around)
- Tune `forks` and `strategy` **together** — addressing only one often produces disappointing results, since the untouched lever remains the bottleneck. [Question 106](../interview-questions/12-performance-scale.md#question-106-the-free-strategy-that-freed-nothing)
- API server-equivalent (control-plane) load applies to AWX too — a shared automation platform serving many teams needs the same profiling discipline as a Kubernetes control plane at scale.

## Fact-gathering timeout stalling the whole fleet
- `linear` strategy's synchronization barrier means a dozen slow-to-connect hosts stall the entire fleet's fact-gathering phase. Tune `timeout`/`connect_timeout`, or switch to `free`/`serial` with `max_fail_percentage`. [Question 19](../interview-questions/02-inventory-variables.md#question-19-the-fact-gathering-timeout-that-stalled-the-whole-fleet)
