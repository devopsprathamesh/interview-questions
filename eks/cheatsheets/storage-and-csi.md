# Cheat Sheet: Storage and CSI

## EBS vs. EFS
| | EBS | EFS |
|---|---|---|
| Scope | Zonal — AZ-locked | Multi-AZ natively |
| Access mode | `ReadWriteOnce` | `ReadWriteMany` |
| Performance | High, block-level | Higher latency, NFS-based |
| Use case | Databases, single-pod high-perf | Genuinely shared, multi-pod concurrent access |

## `volumeBindingMode` — the AZ-mismatch trap
```yaml
volumeBindingMode: WaitForFirstConsumer   # ALWAYS use this for EBS, not Immediate
```
`Immediate` can create the PV before the pod is scheduled, in a mismatched AZ — the pod then can't attach. [Question 43](../interview-questions/05-storage-stateful.md#question-43-the-pod-that-couldnt-follow-its-volume)

## `reclaimPolicy` — a deliberate, per-workload decision
| | `Delete` | `Retain` |
|---|---|---|
| On PVC deletion | Volume destroyed | Volume orphaned, survives |
| Right for | Disposable data, or paired with a real backup strategy | Genuinely critical data needing a safety net |
| Wrong default | Losing critical data with no backup | Unbounded cost from forgotten orphaned volumes |
[Question 45](../interview-questions/05-storage-stateful.md#question-45-delete-versus-retain-chosen-wrong-in-both-directions)

## Velero: manifests ≠ data
Backup **without** the CSI snapshot plugin (`--snapshot-volumes=true`) restores only Kubernetes object definitions — a "restored" PVC gets a fresh, **empty** volume, not real data.
```bash
velero backup create NAME --include-namespaces X --snapshot-volumes=true
```
"The backup job reported success" only proves the *process* ran — only an actual, periodic **restore test** proves data recoverability. [Question 47](../interview-questions/05-storage-stateful.md#question-47-the-velero-restore-that-came-back-empty)

## StatefulSet gotchas
- `volumeClaimTemplates` is **immutable** after creation — never edit in place; migrate via a new StatefulSet + explicit data migration + cutover. [Question 49](../interview-questions/05-storage-stateful.md#question-49-the-statefulset-upgrade-that-ate-its-own-volume)
- Scaling **down** does NOT delete PVCs by design — orphaned volumes silently accumulate cost. [Question 44](../interview-questions/05-storage-stateful.md#question-44-the-scale-down-that-quietly-kept-costing-money)

## Encryption at rest
```yaml
parameters:
  encrypted: "true"   # must be explicit per StorageClass - no cluster-wide default
```
Cannot be retrofitted onto an existing volume — requires a snapshot-copy migration to a new encrypted volume. [Question 48](../interview-questions/05-storage-stateful.md#question-48-encrypted-at-rest-except-for-the-one-nobody-checked)

## Don't over-provision
A genuinely stateless workload should use `emptyDir`, not a PVC — no AZ constraint, no AWS provisioning cost, no orphaned-volume risk. [Question 52](../interview-questions/05-storage-stateful.md#question-52-storage-for-a-workload-that-shouldnt-need-any)
