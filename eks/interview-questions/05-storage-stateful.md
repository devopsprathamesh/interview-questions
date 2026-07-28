# Category 5: Storage (EBS/EFS CSI) and Stateful Workloads

Questions 43–52 of 120. Category weight: 10 questions. Deep-dive reference: [`docs/storage.md`](../docs/storage.md).

---

## Question 43: The pod that couldn't follow its volume

### Scenario
A StatefulSet's pod is evicted from a node in `us-east-1a` and the scheduler places its replacement in `us-east-1b`. The pod gets stuck in `ContainerCreating` indefinitely, with CSI attach errors in its events.

### Interview Question
Diagnose the root cause and design a fix that prevents recurrence.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/storage.md`](../docs/storage.md) §2, EBS volumes are zonal — the pod's existing PV, created in `us-east-1a`, cannot be attached to a node in `us-east-1b` at all, regardless of how much capacity that node has; this is a hard AWS-level constraint, not a Kubernetes scheduling bug.

**Technical reasoning:** the scheduler, without additional constraints, has no inherent awareness that this specific pod's PVC is zonally pinned — it can freely place the pod on any node satisfying CPU/memory requirements, including one in the wrong AZ for its existing volume, unless something explicitly constrains scheduling to match the volume's AZ.

**Investigation process:** confirm via `kubectl describe pv <name>` the volume's actual AZ (from its `topology.kubernetes.io/zone` node affinity, which the EBS CSI driver sets automatically on PV creation) and confirm it doesn't match the node the pod was placed on — settling that this is the AZ-mismatch scenario, not a genuine CSI driver malfunction.

**Recommended solution:** modern EBS CSI-provisioned PVs already include node affinity constraints matching their AZ (`WaitForFirstConsumer` binding mode on the StorageClass ensures the PV is even created in the correct AZ relative to where the pod is first scheduled) — if this protection isn't in place, ensure the StorageClass uses `volumeBindingMode: WaitForFirstConsumer` (not `Immediate`) so volume creation is deferred until a node is chosen, and the resulting PV's node affinity then correctly constrains future rescheduling to the same AZ.

**Risk controls:** for genuinely AZ-resilient stateful workloads, consider whether the application-level replication (e.g., a database's own multi-AZ replica mechanism) is a better fit than relying on a single EBS volume surviving AZ-level events at all — EBS's own zonal nature means a full AZ outage affecting that specific AZ makes the volume itself unavailable regardless of scheduling.

**Validation steps:** confirm `volumeBindingMode: WaitForFirstConsumer` is set on the relevant StorageClass, and confirm a deliberate pod-rescheduling test correctly keeps the pod pinned to the same AZ as its existing PV rather than attempting a cross-AZ placement.

**Rollback or recovery strategy:** for the immediate stuck pod, either force it to reschedule onto a node in the correct AZ (if the affinity is now correctly set) or, if the volume itself needs to move AZs (a genuine migration), use an EBS snapshot to recreate the volume in the target AZ — not something Kubernetes handles automatically.

**Long-term prevention:** standardize on `WaitForFirstConsumer` binding mode for every EBS-backed StorageClass in the fleet, and document the zonal nature of EBS-backed PVs explicitly for any team designing a new stateful workload, so this class of mismatch is anticipated at design time rather than discovered via a stuck pod.

### Step-by-Step Implementation
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer   # defers PV creation until a node is chosen
parameters:
  type: gp3
  encrypted: "true"
```

### Under-the-Hood Explanation
`WaitForFirstConsumer` binding mode delays actual volume provisioning until a pod using the PVC is scheduled, allowing the EBS CSI driver to create the volume in the exact AZ the scheduler has already chosen — and the resulting PV includes a `nodeAffinity` field constraining any *future* scheduling of pods using that PVC to nodes in the matching AZ, which the scheduler then respects as a hard constraint going forward.

### Common Weak Answer
"Just manually delete and recreate the stuck pod."

### Why the Weak Answer Fails
Without the underlying binding-mode/affinity fix, recreating the pod doesn't guarantee the scheduler places it in the correct AZ relative to its existing PV — the same stuck-attach failure can recur on the next reschedule unless the actual root constraint (AZ mismatch) is addressed structurally.

### Follow-Up Questions
1. How would application-level replication (rather than relying on a single EBS volume) change this workload's actual AZ-resilience?
2. What's the trade-off of `Immediate` vs. `WaitForFirstConsumer` binding mode for a workload with no zonal storage constraint?
3. How would you migrate an existing volume's data to a different AZ if a genuine cross-AZ move is needed?

### Key Interview Signals
Correctly identifies EBS's zonal nature as a hard AWS-level constraint (not a Kubernetes bug) and fixes it via the correct binding-mode/affinity mechanism rather than treating it as a one-off pod issue.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

---

## Question 44: The scale-down that quietly kept costing money

### Scenario
A StatefulSet running a caching layer is scaled from 10 replicas down to 3 as part of a cost-optimization pass. Three months later, a billing review finds 10 EBS volumes still provisioned and billed, not 3.

### Interview Question
Explain why scaling down didn't reduce storage cost, and design the correct process.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/storage.md`](../docs/storage.md) §6, scaling a StatefulSet down does not delete the PVCs (and therefore the underlying PVs/EBS volumes) associated with the removed replica indices — this is a deliberate Kubernetes safety choice (avoiding accidental data loss on scale-down), but it means storage cost silently persists unless explicitly cleaned up.

**Technical reasoning:** each StatefulSet replica's PVC (created via `volumeClaimTemplates`) is independently retained even after its corresponding pod is removed on scale-down — Kubernetes has no automatic "also delete the PVC" behavior tied to replica-count reduction, since the PVC might represent data the team wants to keep even if the replica count is temporarily or permanently reduced.

**Investigation process:** confirm via `kubectl get pvc -n <namespace>` that indeed 10 PVCs still exist despite only 3 active replicas, and confirm (via billing data correlated with EBS volume IDs) that these orphaned PVCs are indeed the source of the unexpected cost.

**Recommended solution:** if the data in the now-unused replicas' volumes is genuinely no longer needed (confirm this deliberately, not by assumption), delete the specific orphaned PVCs explicitly; if there's any chance the data might be needed again (e.g., planning to scale back up later), that's a legitimate reason to retain them, but it should be a deliberate, cost-aware decision, not an unnoticed default.

**Risk controls:** before deleting any PVC, confirm definitively it's not still needed — a cache layer's data might be safely disposable, but the same "scale-down doesn't delete storage" behavior applied to a database StatefulSet would warrant much more caution before any deletion.

**Validation steps:** after cleanup, confirm the billing trend reflects the expected reduction, and confirm the retained/active replicas' PVCs are unaffected.

**Rollback or recovery strategy:** if a PVC is deleted prematurely and its data turns out to still be needed, recovery depends entirely on whether a separate backup (Velero, per [`docs/storage.md`](../docs/storage.md) §7) exists — another reason to confirm disposability before deleting, since PVC deletion (with `Delete` reclaim policy) is generally not itself reversible.

**Long-term prevention:** add scale-down cost impact (orphaned PVC accumulation) as an explicit, checked step in any StatefulSet scaling-down runbook, and consider a periodic automated audit flagging PVCs with no corresponding active pod for cost review — catching this class of silent cost accumulation proactively rather than via a billing-review surprise three months later.

### Step-by-Step Implementation
```bash
# Find PVCs with no corresponding active pod (orphaned by scale-down)
kubectl get pvc -n caching -o json | jq -r '.items[].metadata.name' > all-pvcs.txt
kubectl get pods -n caching -o json | jq -r '.items[].spec.volumes[]?.persistentVolumeClaim.claimName' > in-use-pvcs.txt
comm -23 <(sort all-pvcs.txt) <(sort in-use-pvcs.txt)   # orphaned PVCs

# After confirming data is genuinely disposable
kubectl delete pvc <orphaned-pvc-name> -n caching
```

### Under-the-Hood Explanation
`volumeClaimTemplates` in a StatefulSet spec cause the StatefulSet controller to create one PVC per replica index at first scale-up, but the controller's scale-down logic only removes the corresponding *pod*, deliberately leaving the PVC (and its bound PV/EBS volume) intact — a design choice prioritizing data safety over automatic cleanup, which shifts the cost-awareness responsibility explicitly onto whoever manages the scaling operation.

### Common Weak Answer
"Kubernetes must have a bug leaving these volumes around."

### Why the Weak Answer Fails
This is documented, intentional StatefulSet behavior, not a bug — treating it as a defect misses the actual lesson (scale-down cost impact requires an explicit, deliberate cleanup step) and risks the same mistake recurring on the next scale-down operation.

### Follow-Up Questions
1. How would you build a standing, automated cost-audit process catching orphaned PVCs across the whole fleet, not just this one incident?
2. What's the risk calculus difference between cleaning up a cache layer's orphaned PVCs versus a database StatefulSet's?
3. How would you document this behavior so future scale-down operations account for it proactively?

### Key Interview Signals
Recognizes this as documented, intentional Kubernetes behavior (not a bug) and designs a deliberate, cost-aware cleanup process rather than treating the discovery as a platform defect.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

---

## Question 45: `Delete` versus `Retain`, chosen wrong in both directions

### Scenario
Two incidents in the same quarter: (1) a StorageClass with `reclaimPolicy: Delete` backing a critical database had its PVC accidentally deleted during a namespace cleanup script, permanently destroying the underlying EBS volume and its data with no backup; (2) an unrelated StorageClass with `reclaimPolicy: Retain` backing ephemeral build-cache volumes has accumulated hundreds of orphaned, still-billed EBS volumes over the past year with nobody cleaning them up.

### Interview Question
Diagnose both misconfigurations and design the correct policy for each use case.

### Strong Senior-Level Answer
**Initial assessment:** both incidents stem from the same root cause in opposite directions — per [`docs/storage.md`](../docs/storage.md) §4, `reclaimPolicy` should be chosen deliberately based on whether a separate backup strategy exists and whether the data is genuinely critical, not defaulted uniformly across every StorageClass regardless of the data's actual importance.

**Technical reasoning:** `Delete` permanently destroys the underlying volume the moment its PVC is deleted, with no recovery path unless a separate, independent backup (Velero snapshot, database-level backup) exists — appropriate only when either the data is genuinely disposable, or a robust separate backup strategy is already in place. `Retain` preserves the volume indefinitely after PVC deletion, requiring manual intervention to actually reclaim it — appropriate for genuinely critical data needing a safety net against accidental deletion, but requiring an active cleanup process to avoid indefinite cost accumulation for anything that doesn't actually need permanent retention.

**Investigation process:** for the database incident, confirm no separate backup existed at all (making `Delete` an inappropriate choice for this specific critical workload); for the build-cache incident, confirm the retained volumes are indeed genuinely disposable (ephemeral cache data with no need for the `Retain` safety net at all).

**Recommended solution:** for the database's StorageClass, switch to `Retain` (or, better, keep `Delete` but pair it with a robust, independently-verified Velero-based backup strategy so `Delete`'s convenience doesn't come at the cost of unrecoverable data loss) — a deliberate choice informed by the data's actual criticality. For the build-cache StorageClass, switch to `Delete` (since the data is genuinely disposable and doesn't need a manual-cleanup safety net) and clean up the existing orphaned volumes.

**Risk controls:** never choose `reclaimPolicy` as a copy-pasted default from an unrelated StorageClass — treat it as a deliberate decision per workload, explicitly informed by (a) whether a separate backup exists and (b) how critical/disposable the data actually is.

**Validation steps:** for the database, confirm the Velero backup (if that's the chosen mitigation) actually successfully restores a test volume before trusting it as the compensating control for `Delete`'s finality; for the build cache, confirm the newly-set `Delete` policy correctly cleans up volumes on future PVC deletion.

**Rollback or recovery strategy:** for the already-lost database data, recovery depends entirely on whatever backup (if any) exists elsewhere (application-level replication, a database-native backup outside Kubernetes) — this is precisely the unrecoverable-data-loss scenario `Retain` (or a proper backup strategy) exists to prevent. For the build cache's accumulated orphaned volumes, straightforward manual cleanup once confirmed disposable.

**Long-term prevention:** establish an explicit, reviewed `reclaimPolicy` decision (documented with its reasoning) as a required part of any new StorageClass's creation process, and add a periodic automated audit for orphaned `Retain`-policy volumes to prevent unbounded cost accumulation even for legitimately-retained data that's since become genuinely unneeded.

### Step-by-Step Implementation
```yaml
# Critical database StorageClass - Retain, paired with Velero backup as the actual safety net
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: database-critical
reclaimPolicy: Retain
provisioner: ebs.csi.aws.com

---
# Ephemeral build-cache StorageClass - Delete, since data is genuinely disposable
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: build-cache-ephemeral
reclaimPolicy: Delete
provisioner: ebs.csi.aws.com
```

### Under-the-Hood Explanation
`reclaimPolicy` is evaluated purely mechanically by the CSI driver at PV-deletion time — it has no awareness of the data's actual importance or whether a backup exists elsewhere; it simply either destroys or preserves the underlying storage exactly as configured, meaning the *human* decision of matching this configuration to the data's actual criticality is the real control point, not anything Kubernetes enforces automatically.

### Common Weak Answer
"Just set Retain everywhere to be safe."

### Why the Weak Answer Fails
This is exactly the build-cache incident's root cause — blanket `Retain` without a corresponding cleanup process for genuinely disposable data produces unbounded cost accumulation; the correct answer is a deliberate, per-workload decision, not a uniform default in either direction.

### Follow-Up Questions
1. How would you design a periodic audit catching orphaned `Retain`-policy volumes across the fleet before they accumulate for a year unnoticed?
2. What's the actual backup/recovery time objective for the database, and how does that inform whether `Delete`+Velero or `Retain` is the better fit?
3. How would you communicate this reclaim-policy decision framework to teams creating new StorageClasses so it's applied consistently going forward?

### Key Interview Signals
Diagnoses both incidents as the same root cause (undeliberate reclaim-policy choice) manifesting in opposite directions, and designs a workload-criticality-informed decision process rather than a uniform default.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

---

## Question 46: EFS under concurrent load

### Scenario
A team migrates a multi-pod, shared-config-directory workload from a single EBS volume (which required an awkward single-writer workaround) to EFS for genuine multi-pod concurrent access. Performance testing afterward shows notably higher per-operation latency than the team expected, and they ask whether EFS is "just slower" or if something's misconfigured.

### Interview Question
Explain the actual performance characteristics at play and how you'd validate whether this is expected or a misconfiguration.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/storage.md`](../docs/storage.md) §3, EFS's NFS-based, network-attached architecture inherently has a different (generally higher per-operation) latency profile than EBS's block storage — some increase versus the previous EBS-based setup is expected and not automatically a misconfiguration, but the *magnitude* of the increase should still be validated against EFS's documented performance characteristics and the specific throughput/performance mode configured.

**Technical reasoning:** EFS supports different performance modes (General Purpose vs. Max I/O, trading lower latency for higher aggregate throughput/parallelism) and throughput modes (Bursting vs. Provisioned, where Bursting's throughput scales with the filesystem's size and can throttle under sustained demand if the filesystem is small) — an inappropriately-chosen mode for the workload's actual access pattern can produce materially worse performance than EFS is actually capable of for this use case.

**Investigation process:** confirm which performance/throughput mode is currently configured, and correlate the observed latency with EFS's own CloudWatch metrics (`PercentIOLimit` for Bursting-mode throughput exhaustion specifically) — this distinguishes "EFS is inherently this much slower for this access pattern" from "the filesystem is being throttled due to an undersized Bursting-mode allocation."

**Recommended solution:** if throughput throttling is confirmed (via `PercentIOLimit` approaching 100%), switch to Provisioned Throughput mode (paying for a guaranteed throughput level independent of filesystem size) or, if the access pattern is genuinely highly parallel across many pods, evaluate Max I/O performance mode; if the latency is simply EFS's inherent, expected profile for this general access pattern and it's still acceptable for the application's actual requirements, no further action is needed beyond confirming the team's expectations were miscalibrated rather than the configuration being wrong.

**Risk controls:** Provisioned Throughput has its own explicit cost (paying for guaranteed throughput regardless of actual usage) — validate the actual required throughput level via real usage data before over-provisioning.

**Validation steps:** after any mode change, re-run the same performance test and compare against both the previous EBS baseline and EFS's documented expected performance for the newly-configured mode, confirming the change achieves a genuine, expected improvement rather than assuming it will.

**Rollback or recovery strategy:** if EFS's performance profile, even correctly configured, proves fundamentally unsuitable for this specific workload's latency requirements, reconsider the original single-writer EBS workaround (or a different architecture entirely, like a proper distributed cache) rather than forcing EFS to fit a workload shape it's not well-suited for.

**Long-term prevention:** establish EFS performance/throughput mode selection as an explicit, workload-informed decision (not a default) whenever EFS is chosen for a new use case, and monitor `PercentIOLimit` proactively for any Bursting-mode EFS filesystem as a standing signal for approaching throughput exhaustion.

### Step-by-Step Implementation
```bash
# Check for throughput throttling
aws cloudwatch get-metric-statistics --namespace AWS/EFS --metric-name PercentIOLimit \
  --dimensions Name=FileSystemId,Value=fs-0123456789abcdef0 \
  --start-time 2026-07-20T00:00:00Z --end-time 2026-07-27T00:00:00Z --period 3600 --statistics Maximum
```
```yaml
# If throttling confirmed, switch to Provisioned Throughput via the EFS filesystem's own configuration
# (managed via Terraform's aws_efs_file_system throughput_mode/provisioned_throughput_in_mibps)
```

### Under-the-Hood Explanation
EFS's Bursting throughput mode allocates a baseline throughput proportional to the filesystem's total stored size, with burst credits accumulated during low-usage periods and consumed during high-usage periods — a relatively small filesystem under sustained heavy access can exhaust its burst credits and be throttled to its low baseline rate, producing exactly the kind of unexpectedly poor performance this scenario describes, distinct from EFS's inherent per-operation latency profile which is a separate, architectural characteristic of its NFS-based design.

### Common Weak Answer
"EFS is just slower than EBS, that's expected, nothing to check."

### Why the Weak Answer Fails
This dismisses a real, checkable, and often fixable throughput-throttling condition (via `PercentIOLimit`) as an inherent, unavoidable characteristic — while EFS does have a genuinely different latency profile than EBS, the magnitude observed here may well be a fixable throttling issue rather than simply "EFS being EFS."

### Follow-Up Questions
1. How would you decide between Bursting and Provisioned Throughput mode for a new EFS-backed workload before it's even deployed?
2. What's the cost trade-off of Provisioned Throughput versus accepting Bursting-mode throttling risk?
3. How would General Purpose versus Max I/O performance mode affect this specific multi-pod concurrent access pattern?

### Key Interview Signals
Distinguishes EFS's inherent architectural latency characteristics from a genuinely fixable throughput-throttling misconfiguration, using the specific `PercentIOLimit` metric to settle which is actually occurring rather than assuming either explanation.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

---

## Question 47: The Velero restore that came back empty

### Scenario
During a DR test, a team restores a Velero backup of their production namespace to a fresh cluster. All the Kubernetes resources (Deployments, Services, ConfigMaps) restore correctly, but the StatefulSet's pods come up with completely empty data directories — the application behaves as if freshly installed, with none of the original data.

### Interview Question
Diagnose why the resource manifests restored correctly but the actual data didn't, and fix the backup configuration.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/ha-dr.md`](../docs/ha-dr.md) §5 and [`docs/storage.md`](../docs/storage.md) §7, Velero's default behavior backs up Kubernetes *resource manifests* — restoring the PVC/PV objects' definitions gives you new, empty volumes matching the original specification, not the actual data, unless Velero's volume-snapshot capability (via a plugin integrating with the EBS CSI driver's snapshot functionality) was also configured and actually triggered during backup.

**Technical reasoning:** a PVC/PV manifest describes *how* a volume should be provisioned (size, storage class, access mode) — it contains no reference to the actual data blocks unless the backup process specifically also captured a storage-level snapshot and the restore process specifically also restores *from* that snapshot rather than just recreating an empty volume matching the same specification.

**Investigation process:** confirm via the Velero backup's own configuration and logs whether volume snapshotting (the `--snapshot-volumes` flag, or the CSI plugin integration) was actually enabled and successfully executed during the backup that was restored — this settles definitively whether the backup itself was incomplete (never captured the data) versus the restore process failing to use an actually-present snapshot.

**Recommended solution:** reconfigure Velero with the CSI plugin (`velero-plugin-for-csi`) properly installed and volume snapshotting explicitly enabled for any backup covering stateful workloads, and re-run the backup — then re-test the restore, confirming this time that the restored PVCs are populated from the corresponding snapshots rather than freshly empty.

**Risk controls:** treat "manifests restore successfully" and "data restores successfully" as two entirely separate things to verify independently — a successful-looking restore (no errors, all resources present) can still represent a data-loss event if volume snapshotting wasn't actually part of the backup, exactly as happened here.

**Validation steps:** the only real validation is what this DR test already (fortunately) did — attempt an actual restore to a separate cluster and verify the *application*, not just the Kubernetes resources, functions correctly with its expected data present; this is precisely why DR tests exist and why "we have backups configured" is not sufficient without periodic restore verification.

**Rollback or recovery strategy:** if this gap had been discovered during a genuine production DR event rather than a test, the data would be genuinely, permanently lost (assuming no other backup existed) — this is exactly why the DR test running now, catching the gap before it matters, is valuable; reconfigure and re-verify before relying on this backup strategy for anything real.

**Long-term prevention:** make periodic, actual restore-testing (not just backup-job-success monitoring) a standing, scheduled practice — a backup job reporting "success" only confirms the backup process ran without erroring, not that a subsequent restore would actually recover the data correctly, exactly the gap this DR test exposed.

### Step-by-Step Implementation
```bash
# Install the CSI plugin for Velero (enables actual volume snapshotting)
velero plugin add velero/velero-plugin-for-csi:v0.7.0

# Re-run backup with volume snapshotting explicitly enabled
velero backup create production-backup-v2 --include-namespaces production --snapshot-volumes=true

# Re-test restore to a fresh cluster and verify actual DATA, not just resource presence
velero restore create --from-backup production-backup-v2
kubectl exec -n production my-app-0 -- ls /data   # confirm actual data files present, not empty
```

### Under-the-Hood Explanation
Velero's CSI plugin integrates with the EBS CSI driver's `VolumeSnapshot`/`VolumeSnapshotContent` mechanism, triggering an actual point-in-time EBS snapshot during backup and referencing it in the backup's metadata — on restore, this plugin provisions new volumes *from* those snapshots rather than fresh, empty ones matching only the PVC's specification; without this plugin/configuration, Velero backs up only the Kubernetes API object definitions, which is sufficient to recreate the *shape* of the storage but carries no reference to the actual underlying data blocks at all.

### Common Weak Answer
"The backup must be corrupted, restore it again."

### Why the Weak Answer Fails
Retrying the same restore process produces the identical result — the backup never contained the actual data in the first place (a configuration gap, not corruption), and no number of retries changes that; the fix is reconfiguring the backup process itself to include volume snapshots, not repeating an already-fundamentally-incomplete restore.

### Follow-Up Questions
1. How would you schedule and enforce periodic, actual restore-testing (not just backup-success monitoring) as a standing DR-readiness practice?
2. What's the storage/cost overhead of enabling volume snapshotting for every scheduled backup?
3. How does this scenario connect to the companion repositories' "an untested recovery mechanism is equivalent to no recovery mechanism" theme?

### Key Interview Signals
Distinguishes Kubernetes-manifest backup from actual data backup precisely, and treats a DR test's discovery of this gap as validating exactly why periodic restore-testing (not just backup-job monitoring) is essential.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 48: Encrypted at rest, except for the one nobody checked

### Scenario
A security audit finds that 47 of 50 StorageClasses in a shared cluster have `encrypted: "true"` set, but 3 (created early in the cluster's history, before an encryption-by-default policy was established) don't — and one of those 3 backs a workload storing customer PII.

### Interview Question
Diagnose the gap and design a prevention mechanism, not just a one-time fix.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/storage.md`](../docs/storage.md) §5, an unencrypted-by-default StorageClass silently provisions unencrypted volumes with no error or warning anywhere — this is exactly the kind of gap that persists indefinitely once created, since nothing about ongoing cluster operation surfaces "this StorageClass lacks encryption" unless someone deliberately audits for it.

**Technical reasoning:** the `encrypted` parameter is opt-in at the StorageClass level — its absence doesn't fail closed (default to encrypted) or produce any warning; PVs provisioned through an unencrypted StorageClass are simply, silently unencrypted at rest, exactly as configured.

**Investigation process:** confirm via `kubectl get storageclass -o yaml` across all 50 StorageClasses exactly which lack the `encrypted: "true"` parameter, and confirm which workloads/PVCs actually use each of the 3 non-compliant ones — identifying the PII-storing workload's specific exposure as the highest-priority remediation.

**Recommended solution:** create new, encrypted-equivalent StorageClasses to replace the 3 non-compliant ones, and migrate affected workloads' data to newly-provisioned encrypted volumes (since encryption cannot be enabled retroactively on an already-existing unencrypted EBS volume — it requires creating a new, encrypted volume and copying data, typically via a snapshot-copy-with-encryption operation) — prioritizing the PII-storing workload first given its heightened sensitivity.

**Risk controls:** the migration itself (copying data to a new encrypted volume) is a genuine data-handling operation — perform it with the same care as any other data migration (verified copy completeness, a maintenance window if the workload can't tolerate a brief cutover disruption).

**Validation steps:** after migration, confirm the new volumes are indeed encrypted (via `aws ec2 describe-volumes` showing `Encrypted: true`) and confirm the application functions correctly against the new, encrypted storage with no data loss from the migration.

**Rollback or recovery strategy:** retain the original unencrypted volumes (don't delete immediately) until the migration to encrypted volumes is fully validated, in case the cutover reveals an unexpected issue requiring temporary reversion.

**Long-term prevention:** enforce encryption via an admission policy (Kyverno/Gatekeeper, per [`docs/governance-policy.md`](../docs/governance-policy.md)) rejecting any new StorageClass creation lacking the `encrypted: "true"` parameter — a structural guardrail preventing this exact gap from being reintroduced, rather than relying on periodic manual audits alone to catch it after the fact.

### Step-by-Step Implementation
```bash
# Audit: find every StorageClass lacking encryption
kubectl get storageclass -o json | jq -r '.items[] | select(.parameters.encrypted != "true") | .metadata.name'
```
```yaml
# Kyverno policy preventing recurrence
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-encrypted-storageclass
spec:
  validationFailureAction: Enforce
  rules:
    - name: storageclass-must-be-encrypted
      match:
        any:
          - resources: { kinds: [StorageClass] }
      validate:
        message: "StorageClass must set parameters.encrypted: 'true'"
        pattern:
          parameters:
            encrypted: "true"
```

### Under-the-Hood Explanation
EBS encryption is applied at volume-creation time via the KMS key referenced (explicitly or via the account's default EBS encryption key) in the CSI driver's provisioning call — it cannot be toggled on for an already-existing volume in place; the only path to "encrypt" existing unencrypted data is creating a new encrypted volume (via a snapshot-copy operation that supports specifying a KMS key during the copy) and migrating the workload to it, which is why remediation here requires an actual data migration, not a simple configuration flip.

### Common Weak Answer
"Just add `encrypted: true` to the existing StorageClass definition."

### Why the Weak Answer Fails
Editing the StorageClass only affects *future* volumes provisioned through it — it does nothing to the already-existing, already-unencrypted volumes currently in use, which require an actual data migration to genuinely become encrypted; this response would leave the actual current PII exposure completely unaddressed.

### Follow-Up Questions
1. How would you prioritize and sequence the migration of all 3 non-compliant StorageClasses' workloads, given real production impact considerations?
2. What's the actual mechanism for creating an encrypted copy of an existing unencrypted EBS volume?
3. How would you extend this admission-policy-based prevention to catch other, similarly silent security-relevant StorageClass parameters?

### Key Interview Signals
Recognizes that fixing the StorageClass definition alone doesn't remediate already-existing unencrypted data, correctly identifies the need for an actual migration, and designs a structural admission-policy guardrail to prevent recurrence.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/) and [Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).

---

## Question 49: The StatefulSet upgrade that ate its own volume

### Scenario
A team, migrating a StatefulSet's `volumeClaimTemplates` to a new StorageClass (for improved IOPS), edits the StatefulSet manifest directly, changing the `storageClassName` field, and applies it via their GitOps controller. The apply fails with an immutability error, and, confused, an engineer deletes and recreates the entire StatefulSet to "force" the change — which succeeds, but destroys all existing PVCs and their data in the process.

### Interview Question
Explain the immutability constraint that caused the initial failure, and design the correct migration process.

### Strong Senior-Level Answer
**Initial assessment:** `volumeClaimTemplates` in a StatefulSet spec is immutable after creation — Kubernetes deliberately disallows changing it in place, specifically *because* altering it could have exactly the ambiguous-or-destructive implications for already-existing PVCs that this scenario's delete-and-recreate workaround then triggered for real.

**Technical reasoning:** the delete-and-recreate approach recreates the StatefulSet object itself, but critically, does *not* automatically preserve the existing PVCs' association unless done very carefully — depending on the exact recreation method and any cascading delete behavior, existing PVCs can be deleted along with the StatefulSet (if owner references and reclaim policy align that way) or orphaned in a way that the newly-created StatefulSet doesn't correctly re-adopt, either way resulting in the observed data loss.

**Investigation process:** confirm exactly what happened to the original PVCs during the delete-recreate sequence (were they explicitly deleted as part of a cascading delete, or orphaned and then not correctly re-referenced by the new StatefulSet) — this determines whether any data-recovery path (an orphaned-but-still-existing PV, if `reclaimPolicy: Retain` was set) might still be available.

**Recommended solution:** the correct process for changing a StatefulSet's storage configuration is: create a *new* StatefulSet with the new `volumeClaimTemplates`/StorageClass, migrate data explicitly (via an application-level replication/backup-restore mechanism, or a manual volume-copy process), cut traffic over once the new StatefulSet's data is verified complete, and only then decommission the old StatefulSet and its now-redundant PVCs — never a direct in-place field edit or a destructive delete-and-recreate.

**Risk controls:** before any StatefulSet-related destructive-seeming operation, confirm the `reclaimPolicy` on the relevant StorageClass — `Retain` would have preserved the underlying volumes even through the accidental deletion, giving a recovery path that `Delete` (if that's what was configured) would not.

**Validation steps:** for the recovery path (if any PVs survived via `Retain`), confirm data integrity before attempting to re-associate them with any new StatefulSet; for the correct forward migration process, verify the new StatefulSet's data matches the old one's before cutting over and decommissioning.

**Rollback or recovery strategy:** if `reclaimPolicy: Retain` was set, the underlying EBS volumes likely still exist (orphaned) and can potentially be manually re-associated with new PVs/PVCs — a recovery path worth checking immediately, before assuming total data loss; if `Delete` was set, recovery depends entirely on whatever separate backup (Velero, application-level) might exist.

**Long-term prevention:** document the immutability of `volumeClaimTemplates` and the correct migration process (new StatefulSet + explicit data migration + cutover) explicitly for the team, and treat any "immutability error, let's just delete and recreate to force it" instinct as a hard stop requiring senior review before proceeding — this exact shortcut is what caused the data loss here.

### Step-by-Step Implementation
```text
Correct storage-migration process for a StatefulSet:
1. Create a NEW StatefulSet (new name) with the desired new StorageClass in
   volumeClaimTemplates.
2. Migrate data explicitly - application-level replication, or a manual
   volume-copy/restore process (e.g., via Velero backup-then-restore into
   the new StatefulSet's PVCs).
3. Verify the new StatefulSet's data is complete and correct.
4. Cut traffic over to the new StatefulSet.
5. Only then, decommission the old StatefulSet and its now-redundant PVCs.
```

### Under-the-Hood Explanation
Kubernetes enforces `volumeClaimTemplates` immutability at the API validation level specifically because the relationship between a StatefulSet's pod-identity-indexed replicas and their correspondingly-indexed PVCs is foundational to the StatefulSet model — allowing an in-place change would create ambiguity about what should happen to already-existing, already-bound PVCs, which is exactly the kind of destructive ambiguity that manifested when the team worked around the restriction via delete-and-recreate instead of a proper, explicit migration.

### Common Weak Answer
"The immutability error is just Kubernetes being overly strict, force it through."

### Why the Weak Answer Fails
The immutability restriction exists precisely because there's no safe, unambiguous way to change this field in place — "forcing it through" via delete-and-recreate is exactly what caused the actual data loss; the restriction was correctly protecting against this outcome, and the correct response is the explicit new-StatefulSet-plus-migration process, not bypassing the protection.

### Follow-Up Questions
1. What would you check immediately after discovering this kind of accidental deletion to assess any possible recovery path?
2. How would you design a safer, more automated version of this new-StatefulSet-plus-migration process for future storage changes?
3. How does this incident reinforce the value of the `Retain` reclaim policy discussed in Question 45, even for accidental-deletion scenarios beyond deliberate cleanup mistakes?

### Key Interview Signals
Understands why `volumeClaimTemplates` immutability exists as a genuine safety protection (not arbitrary strictness) and designs the correct, non-destructive migration process rather than treating the restriction as an obstacle to force past.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

---

## Question 50: One StorageClass to rule them all?

### Scenario
A platform team, aiming to simplify developer experience, proposes providing exactly one default StorageClass for the entire shared cluster, used by every workload regardless of its actual storage needs (a database, a build cache, a shared-config directory).

### Interview Question
Evaluate this proposal.

### Strong Senior-Level Answer
**Initial assessment:** a single, one-size-fits-all StorageClass conflates fundamentally different storage requirements (access mode, performance profile, reclaim policy, encryption needs) that, per [`docs/storage.md`](../docs/storage.md), genuinely differ across workload types — simplicity for developers is a real, legitimate goal, but a single StorageClass can't correctly serve both a `ReadWriteOnce` database needing `Retain` and a `ReadWriteMany` shared-config directory that's genuinely disposable, without compromising one or the other.

**Technical reasoning:** access mode alone (EBS's `ReadWriteOnce` vs. EFS's `ReadWriteMany`) requires different underlying CSI drivers entirely — a single StorageClass can't satisfy both a workload needing genuine multi-pod concurrent write access and one needing high-performance, single-writer block storage, since these map to fundamentally different AWS storage services (EBS vs. EFS), not just different parameters on the same one.

**Investigation process:** categorize the cluster's actual workload storage needs by their real requirements (access mode, criticality/reclaim-policy needs, performance profile) rather than assuming uniformity — this reveals the genuine diversity a single StorageClass would need to paper over.

**Recommended solution:** provide a small, curated set of StorageClasses (e.g., `ebs-general-purpose` for typical `ReadWriteOnce` workloads, `ebs-high-performance` for latency-sensitive databases, `efs-shared` for `ReadWriteMany` needs, each with an appropriately-set reclaim policy) rather than either a single one-size-fits-all class or an unbounded, unstructured proliferation of ad hoc classes — capturing most of the developer-experience simplicity (a small, well-documented menu, not fifty options) while still correctly matching genuinely different storage requirements.

**Risk controls:** document each StorageClass's intended use case clearly so developers can self-select correctly without needing deep storage expertise — the actual simplicity goal (developers not needing to understand EBS-vs-EFS-vs-reclaim-policy minutiae) is better served by clear, well-labeled options than by a single class that's secretly wrong for some subset of workloads.

**Validation steps:** confirm the curated set actually covers the real diversity of workload needs identified in the investigation step, without leaving any workload category genuinely unserved by an appropriate option.

**Rollback or recovery strategy:** if a single-StorageClass approach is already in place and causing issues (e.g., a database workload using an inappropriately-configured shared class), migrate it to a purpose-appropriate class via the explicit migration process from Question 49, not an in-place field edit.

**Long-term prevention:** treat the StorageClass menu as a deliberately curated, periodically-reviewed platform offering (similar to how compute/instance-type offerings might be curated) rather than either a single default or an unstructured free-for-all.

### Step-by-Step Implementation
```yaml
# A small, curated menu instead of one universal default
# ebs-general-purpose, ebs-high-performance (Retain), efs-shared (ReadWriteMany)
# each clearly documented for developers to self-select correctly
```

### Under-the-Hood Explanation
StorageClasses map directly to distinct provisioner/CSI-driver combinations and their own parameter sets — EBS-backed classes fundamentally cannot provide `ReadWriteMany` semantics (a structural limitation of block storage, not a configuration choice), and EFS-backed classes have a different performance profile entirely; no single StorageClass definition can paper over these structural, driver-level differences regardless of how its parameters are tuned.

### Common Weak Answer
"One StorageClass is simpler for developers, just make it work for everyone."

### Why the Weak Answer Fails
This ignores genuine, structural differences in storage requirements (access mode alone makes some workloads simply incompatible with a single class) — the actual developer-experience goal is better served by a small, clearly-documented set of purpose-fit options than by forcing every workload into an inevitably-compromised single default.

### Follow-Up Questions
1. How would you design the documentation/self-service tooling helping developers choose correctly among a curated set of StorageClasses?
2. What's the risk of an unstructured proliferation of StorageClasses in the opposite direction (too many, with no clear guidance)?
3. How would you handle a workload with genuinely novel storage requirements not covered by the existing curated menu?

### Key Interview Signals
Recognizes that storage requirements genuinely differ by workload type at a structural level (not just preference), and proposes a curated middle ground rather than either extreme (one-size-fits-all or unstructured proliferation).

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

---

## Question 51: The snapshot lifecycle nobody managed

### Scenario
A team has been taking manual EBS snapshots of critical volumes "just in case" for two years, with no automated lifecycle policy. A cost review finds thousands of snapshots accumulated, most representing point-in-time states that are now redundant or no longer relevant, costing significantly more than the actual current volumes they were snapshotted from.

### Interview Question
Design a proper snapshot lifecycle management strategy.

### Strong Senior-Level Answer
**Initial assessment:** manual, ad hoc snapshotting with no lifecycle policy is the storage-layer equivalent of any other "we'll clean it up eventually" resource-accumulation pattern this repository series consistently flags — snapshots have real, ongoing cost, and without an automated retention/expiration policy, they accumulate indefinitely since nothing naturally prompts their removal.

**Technical reasoning:** AWS **Data Lifecycle Manager (DLM)** (or, for Kubernetes-native workflows, Velero's own backup-retention/TTL settings if snapshots are being created via Velero rather than manually) automates snapshot creation *and* expiration/deletion according to a defined retention policy (e.g., "keep daily snapshots for 7 days, weekly for a month, monthly for a year") — replacing manual, unbounded snapshot creation with a policy-driven, self-cleaning process.

**Investigation process:** confirm the actual recovery-point-objective/recovery-time-objective requirements for each class of critical data (how far back might you genuinely need to restore from, realistically) — this determines the appropriate retention policy tiers rather than defaulting to "keep everything forever, just in case."

**Recommended solution:** implement a DLM (or Velero-native) lifecycle policy with tiered retention matching actual RPO/RTO needs, and perform a one-time cleanup of the existing, unmanaged snapshot backlog (after confirming which, if any, represent genuinely still-needed historical states, which is unlikely for the vast majority given the described accumulation pattern).

**Risk controls:** before bulk-deleting the existing unmanaged snapshot backlog, do a sanity check for any snapshot that might correspond to a still-relevant historical need (e.g., a specific pre-migration state still referenced by an active investigation) — but treat this as an exception-review process, not a blanket reason to avoid cleanup.

**Validation steps:** after implementing the lifecycle policy, confirm new snapshots are automatically created and expired according to the defined schedule, and confirm the cost trend reflects the expected reduction after the backlog cleanup.

**Rollback or recovery strategy:** not applicable to the lifecycle-policy implementation itself; for the backlog cleanup, retain a brief grace period/review window before permanent deletion in case any snapshot's continued relevance is identified after the fact.

**Long-term prevention:** treat snapshot lifecycle management as a standing, automated, policy-driven process from the outset for any new backup/snapshot strategy, never manual ad hoc creation with no corresponding expiration plan — exactly the same "if it's not automated it's not maintained" discipline applied to log retention, add-on versioning, and other accumulating-resource patterns throughout this repository series.

### Step-by-Step Implementation
```json
// AWS DLM lifecycle policy
{
  "ResourceTypes": ["VOLUME"],
  "TargetTags": [{"Key": "Backup", "Value": "critical"}],
  "Schedules": [{
    "Name": "DailyWithTieredRetention",
    "CreateRule": {"Interval": 24, "IntervalUnit": "HOURS"},
    "RetainRule": {"Count": 7}
  }]
}
```

### Under-the-Hood Explanation
DLM (or Velero's own backup-TTL mechanism) operates as a continuously-running, policy-driven process that both creates snapshots on schedule and automatically deletes them once they age past the defined retention window — replacing a human-dependent "remember to create and eventually clean up snapshots" process with a fully automated one that inherently can't accumulate indefinitely, since expiration is a built-in, enforced part of the policy rather than a separate manual task nobody gets around to.

### Common Weak Answer
"Just manually delete the old snapshots periodically when someone remembers."

### Why the Weak Answer Fails
This is the exact process (or lack thereof) that produced the two-year, thousands-of-snapshots accumulation in the first place — a durable fix requires an automated, policy-driven lifecycle, not a renewed commitment to more diligent manual cleanup.

### Follow-Up Questions
1. How would you determine the appropriate retention tiers (daily/weekly/monthly counts) based on actual business RPO/RTO requirements?
2. What's the cost/safety trade-off of a more aggressive versus more conservative retention policy?
3. How would you handle the one-time backlog cleanup safely, given uncertainty about whether any specific old snapshot might still be needed?

### Key Interview Signals
Recognizes unmanaged snapshot accumulation as a predictable, preventable resource-lifecycle gap, and designs an automated, policy-driven replacement rather than relying on renewed manual diligence.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 52: Storage for a workload that shouldn't need any

### Scenario
A stateless web application's Helm chart, inherited from a previous team, includes a `PersistentVolumeClaim` mounted for `/tmp` "just in case the app writes temp files it needs to persist." The application is fully stateless by design and doesn't actually need persistent temp storage.

### Interview Question
Evaluate whether this PVC should exist at all, and what it's actually costing the platform beyond the obvious storage bill.

### Strong Senior-Level Answer
**Initial assessment:** an unnecessary PVC on a genuinely stateless workload isn't just wasted storage cost — per [`docs/storage.md`](../docs/storage.md) §2, if this is an EBS-backed PVC, it also introduces an unnecessary AZ-scheduling constraint (per Question 43) on a workload that would otherwise be freely schedulable across any AZ, and (per Question 44) risks the exact orphaned-volume-on-scale-down accumulation if this were ever part of a StatefulSet's `volumeClaimTemplates` instead of a simple Deployment-level PVC.

**Technical reasoning:** a genuinely stateless application has no actual requirement for its `/tmp` contents to survive a pod restart/rescheduling — using `emptyDir` (ephemeral, node-local, no AWS-level provisioning or AZ constraint at all) is both architecturally correct for this use case and removes every one of the unnecessary costs/constraints a PVC introduces.

**Investigation process:** confirm definitively (via code review or the application's own documentation) that nothing genuinely relies on this data surviving a pod restart — "just in case" is not the same as an actual, confirmed requirement, and this exact kind of unexamined inherited configuration is worth challenging explicitly rather than perpetuating indefinitely.

**Recommended solution:** replace the PVC-backed volume mount with a simple `emptyDir` volume — functionally equivalent for genuinely temporary/disposable data, with none of the AWS-level provisioning cost, AZ-scheduling constraint, or storage-lifecycle management overhead a PVC introduces.

**Risk controls:** before removing the PVC, do confirm (not assume) that the application genuinely never needs this data to survive a restart — a quick investigation now is cheaper than discovering a genuine, if unlikely, dependency after the change.

**Validation steps:** after switching to `emptyDir`, confirm the application continues functioning correctly across normal pod restarts/rescheduling, with no behavior change from the storage-mechanism switch.

**Rollback or recovery strategy:** reverting to a PVC-backed mount is straightforward if the investigation reveals an actual, previously-undocumented dependency on data persistence — a low-risk, easily-reversible change either direction.

**Long-term prevention:** treat "does this workload actually need a PersistentVolumeClaim, or would `emptyDir` (or no volume at all) suffice" as a standing question during any Helm chart/manifest review, especially for inherited configuration nobody has recently re-examined — unnecessary PVCs are a quiet, easy-to-overlook source of both cost and unnecessary scheduling constraints across a fleet.

### Step-by-Step Implementation
```yaml
# Before - unnecessary PVC on a stateless workload
volumes:
  - name: tmp
    persistentVolumeClaim:
      claimName: my-app-tmp-pvc

# After - emptyDir, correct for genuinely ephemeral data
volumes:
  - name: tmp
    emptyDir: {}
```

### Under-the-Hood Explanation
`emptyDir` is provisioned directly from the node's own local storage (or optionally memory, via `emptyDir.medium: Memory`), created fresh when the pod starts and deleted when the pod is removed from the node — no AWS-level EBS provisioning, no AZ affinity constraint, and no separate storage-cost billing beyond the node's own existing storage, making it strictly cheaper and less constraining than a PVC for any workload that genuinely doesn't need data to survive beyond the pod's own lifetime.

### Common Weak Answer
"Leave it as-is, it's not causing any obvious problems right now."

### Why the Weak Answer Fails
This misses the compounding, if individually small, costs an unnecessary PVC introduces (storage billing, AZ scheduling constraint, potential future orphaned-volume risk if the workload's structure ever changes to a StatefulSet) — "not causing obvious problems" isn't the same as "not costing anything," and this exact kind of unexamined inherited configuration is worth actively challenging rather than perpetuating by default.

### Follow-Up Questions
1. How would you audit an entire fleet for similarly unnecessary PVCs on genuinely stateless workloads?
2. What's the difference in behavior between `emptyDir` backed by node disk versus `emptyDir.medium: Memory`, and when would each be appropriate?
3. How would you build this kind of "does this really need what it's asking for" review into a standard Helm chart review checklist?

### Key Interview Signals
Questions inherited "just in case" configuration rather than perpetuating it by default, and correctly identifies the compounding costs (billing, scheduling constraints) an unnecessary PVC introduces beyond the obvious storage bill.

### Hands-On Connection
[Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).
