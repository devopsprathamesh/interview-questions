# Cheat Sheet: The Interview Response Framework

The ten-step structure every strong answer in this repository follows — memorize this, then apply it to any scenario you haven't seen before.

1. **Clarify blast radius** — one pod, one node, one namespace, one AZ, or cluster-wide?
2. **Protect production** — is there an active incident risk right now?
3. **Gather evidence** — `kubectl describe`, `kubectl logs`, `kubectl get events`, Container Insights/Prometheus, before changing anything.
4. **Inspect actual state** — desired state (Git/manifest) vs. live cluster state vs. actual AWS-side state (ASG, ENI, security group).
5. **Root cause, not symptom** — why did this happen, not just what broke.
6. **Safest remediation path** — least invasive, most reversible fix first.
7. **Validate the fix** — prove it worked (a positive-control test), don't assume.
8. **Rollback plan** — what if the fix makes things worse.
9. **Preventive controls** — an admission policy, alert, or guardrail so this class of failure can't recur silently.
10. **Document and communicate** — postmortem, runbook update, team knowledge-share.

## The recurring meta-lessons across this entire repository
- **The control-plane/data-plane split is the first thing to check for any "is this our fault" question.** AWS manages the control plane; you own everything about node/workload placement, autoscaling, and security policy. (Category 1)
- **A passing check only proves what it actually checks** — check-mode's command/shell blindness (companion Ansible repo), a shallow readiness probe, a NetworkPolicy object with no active enforcement, a "successful" backup with no volume snapshot — none of these prove more than their own narrow scope. (Categories 2, 5, 7, 11)
- **Silent gaps are the most dangerous failure mode** — a zero-endpoint Service, an untagged instance invisible to automation, a cluster never registered with an ApplicationSet — all fail with no error, discoverable only by deliberate, active verification. (Categories 2, 10)
- **Never trust a rarely-exercised recovery path you haven't tested** — a break-glass credential, a DR drill run only by its own author, a Velero backup never restore-tested. (Category 12)
- **Least privilege applies to the automation identity itself, not just what it manages** — the CI runner's own IAM role deserves the same scrutiny as the target cluster's IRSA roles. (Categories 3, 7)
- **Shared, organization-wide artifacts (a policy set, a CI template, an observability platform) deserve the *highest* testing/governance rigor, not the lowest** — their blast radius spans every consumer simultaneously. (Categories 9, 13, 14)
- **Configuration parity is not data parity** — GitOps, Ansible convergence, and every configuration-management tool in this repository series solves the *shape* problem, never the *data* problem. Every stateful dependency needs its own explicit answer. (Category 12)

## Five questions that separate Senior from Staff
1. Can you draw the full IRSA trust chain from memory, including exactly which fields the trust policy condition must check to prevent any-ServiceAccount-can-assume-this-role?
2. Can you explain why a `NetworkPolicy` object might do absolutely nothing, and how you'd verify enforcement is actually active before trusting it?
3. Can you articulate the correct cluster upgrade sequencing (control plane → EKS add-ons → self-managed add-ons → node groups) and why doing it out of order causes incidents?
4. Can you explain what GitOps's continuous reconciliation gives you that a traditional CI/CD push-based pipeline doesn't, and what it still doesn't solve (data, DNS cutover, controller availability during a regional incident)?
5. Can you distinguish what EKS's managed control plane genuinely removes from your operational burden (etcd backup, control-plane HA) from what remains entirely your responsibility (workload placement, node/pod HA design, data backup)?
