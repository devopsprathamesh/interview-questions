# Cheat Sheet: Common Production Failure Patterns

| Symptom | Root cause | Fix | Reference |
|---|---|---|---|
| Pod stuck `Pending` | Insufficient capacity, unsatisfiable affinity/taint, NodePool mismatch | Systematic elimination checklist — never jump to "scheduler bug" | [Q103](../interview-questions/11-troubleshooting.md#question-103-the-postmortem-that-blamed-the-wrong-layer) |
| Pod stuck `ContainerCreating` | CNI IP exhaustion, image pull failure, volume AZ mismatch | Check `kubectl describe pod` Events for the specific cause | [Q11](../interview-questions/02-networking.md#question-11-the-subnet-that-ran-out-of-room), [Q43](../interview-questions/05-storage-stateful.md#question-43-the-pod-that-couldnt-follow-its-volume) |
| `CrashLoopBackOff` | Application-level failure | `kubectl logs --previous` (the crashed instance, not the new one) | `docs/troubleshooting.md` §3 |
| `OOMKilled`, recurs after limit increase | Genuine memory leak, not a one-time undersized limit | Check the usage TREND (unbounded climb vs. plateau), not just the event | [Q101](../interview-questions/11-troubleshooting.md#question-101-the-fix-that-fixed-it-until-it-didnt) |
| Node `NotReady` | Kubelet crash, disk pressure, or expected lifecycle event (Spot/scale-in) | Check node Conditions; cross-check EC2 instance status | `docs/troubleshooting.md` §5 |
| Service has endpoints but traffic fails | Security group blocking LB→target path, or `instance`-mode health-check blindness | Compare `kubectl get endpoints` vs. actual ALB target-group health | [Q12](../interview-questions/02-networking.md#question-12-the-health-check-that-lied) |
| Readiness probe passes but pod isn't really ready | Probe too shallow (TCP port only, not real dependency health) | Deepen the probe to reflect genuine functional health | [Q99](../interview-questions/11-troubleshooting.md#question-99-the-pod-that-was-healthy-right-up-until-it-wasnt) |
| Service matches zero endpoints | Label-selector typo or drifted pod-template labels | `kubectl get pods --show-labels` vs. Service's `spec.selector` | `docs/troubleshooting.md` §9 |
| Helm/Kustomize apply "succeeds" but nothing changed | Typo'd values key silently ignored, or no rollout trigger for a ConfigMap change | Diff actual rendered output, don't trust exit code alone | `docs/troubleshooting.md` §10 |
| Karpenter/CA not scaling when it should | IRSA gap on the autoscaler's own ServiceAccount, or NodePool constraint mismatch | Check the autoscaler's OWN pod logs first — a commonly-skipped step | `docs/troubleshooting.md` §11 |
| GitOps app stuck `OutOfSync` | Controller lacks permission, invalid manifest, or sync-wave/hook ordering issue | Read the controller's own specific sync error — don't just force-sync repeatedly | `docs/troubleshooting.md` §12 |
| Multiple confusing symptoms at once | Could be one shared cause OR several coincidental independent ones | Investigate each independently in parallel; don't assume a shared cause | [Q100](../interview-questions/11-troubleshooting.md#question-100-the-incident-that-was-actually-three-incidents) |
| Intermittent (~2%) failure, retry always "fixes" it | Race condition or transient resource contention — evidence discarded by immediate retry | Capture full evidence BEFORE retrying, across several occurrences | (companion Ansible repo Q98 — identical diagnostic discipline) |
