# EKS Troubleshooting Runbook

Deep-dive, runbook-style reference for [`interview-questions/11-troubleshooting.md`](../interview-questions/11-troubleshooting.md) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/). Each entry: symptom → likely cause → diagnostic command → fix direction.

## 1. Pod stuck in `Pending`

**Likely causes:** insufficient node resources (CPU/memory) cluster-wide, no node matches a required node selector/taint-toleration/affinity rule, or (if using Karpenter/Cluster Autoscaler) the autoscaler itself is stalled.
**Diagnose:** `kubectl describe pod <pod>` — the `Events` section names the exact scheduling failure reason.
**Fix direction:** if genuinely out of capacity, verify the autoscaler (Karpenter/Cluster Autoscaler) is running and has permission to provision nodes; if a scheduling constraint (affinity/taint) is the cause, verify it's actually satisfiable by some node in the cluster.

## 2. Pod stuck in `ContainerCreating`

**Likely causes:** CNI plugin failure (commonly IP exhaustion — see [`docs/networking.md`](networking.md) §2), image pull failure, or a volume mount failure (CSI driver issue, or the underlying EBS volume stuck in a different AZ than the node).
**Diagnose:** `kubectl describe pod <pod>` — distinguishes a CNI error from an image-pull error from a volume-mount error in the Events section; `kubectl get events --field-selector involvedObject.name=<pod>` for a focused view.
**Fix direction:** for CNI/IP-exhaustion, check node's available IP count (`ipamd` metrics) and consider prefix delegation; for image-pull failures, verify registry credentials/network path to ECR; for volume issues, confirm the PV's AZ matches the node's AZ (a common EBS-CSI trap — EBS volumes are AZ-scoped).

## 3. `CrashLoopBackOff`

**Likely causes:** the application itself is failing on startup (bad config, missing dependency, unhandled exception) — this is an application-level failure surfaced through Kubernetes' restart mechanism, not a Kubernetes-level bug.
**Diagnose:** `kubectl logs <pod> --previous` (the *previous* crashed instance's logs, since the current instance is likely brand new and hasn't logged anything relevant yet) — this is the single most-forgotten flag in this exact scenario.
**Fix direction:** fix the underlying application issue; if the crash is due to a failed readiness/liveness probe misconfiguration rather than a genuine app failure, fix the probe definition instead.

## 4. `OOMKilled`

**Likely causes:** the container exceeded its memory **limit** (not request) and was killed by the kernel's cgroup OOM mechanism — distinct from the *node* running out of memory generally.
**Diagnose:** `kubectl describe pod` shows `Last State: Terminated, Reason: OOMKilled`; correlate with actual memory usage trend via Container Insights/Prometheus leading up to the kill.
**Fix direction:** either the limit is genuinely too low for legitimate usage (raise it, informed by actual usage data, not a guess) or the application has a real memory leak (raising the limit only delays the eventual kill) — distinguish these via the usage trend shape (a slow, unbounded climb suggests a leak; a sudden spike at a specific operation suggests a legitimately higher peak need).

## 5. Node `NotReady`

**Likely causes:** kubelet has stopped reporting node status — could be the kubelet process itself crashed, the node ran out of disk (`DiskPressure` condition), lost network connectivity to the control plane, or the node is genuinely being terminated (a Spot interruption, an ASG scale-in, a Karpenter consolidation decision).
**Diagnose:** `kubectl describe node <node>` — the `Conditions` section shows exactly which condition (Ready/DiskPressure/MemoryPressure/PIDPressure) is failing and why; cross-check the underlying EC2 instance's own status checks in the AWS console/CLI.
**Fix direction:** if it's an expected lifecycle event (Spot interruption, scale-in), no action needed — the scheduler reschedules affected pods elsewhere automatically (assuming sufficient capacity); if it's a genuine node-level fault, cordon/drain and replace rather than attempting in-place recovery on a production node.

## 6. Service has endpoints but traffic still fails

**Likely causes:** a security group blocking traffic between the load balancer and target pods/nodes, a misconfigured health check causing targets to be marked unhealthy at the target-group level (even though the pod itself is fine), or a NetworkPolicy unexpectedly blocking the traffic path.
**Diagnose:** `kubectl get endpoints <service>` (confirms Kubernetes-level endpoint population is correct) then check the AWS Load Balancer Controller's target-group health in the AWS console — a mismatch between "Kubernetes says the endpoint is ready" and "the target group says it's unhealthy" points squarely at the AWS-side health check configuration or a security-group path issue, not the application itself.
**Fix direction:** align the target group's health-check path/port with what the pod actually serves, and verify security group rules allow the load balancer's security group to reach the target port on the node/pod security group.

## 7. Handler-equivalent surprises: readiness probe passes but pod isn't actually ready to serve

**Likely causes:** a readiness probe checking something too shallow (e.g., "the TCP port is open") rather than something that reflects genuine readiness (e.g., "the app has finished loading its cache and can serve real requests") — traffic gets routed to a technically-alive-but-not-actually-ready pod.
**Diagnose:** review the readiness probe's actual check against what "genuinely ready to serve" means for this specific application; correlate early-lifetime error rates for newly-started pods against the probe's pass timing.
**Fix direction:** deepen the readiness probe to reflect actual application-level readiness, not just process/port liveness.

## 8. Cascading failure from a single misbehaving dependency

**Likely causes:** one downstream dependency (a database, an external API) becomes slow/unavailable, and every pod calling it without a timeout/circuit-breaker pattern piles up in-flight requests, exhausting its own resource limits and getting OOMKilled or becoming unresponsive itself — the failure spreads upstream through the call graph.
**Diagnose:** trace-based correlation (§ in `docs/observability.md`) showing elevated latency/errors originating from one specific downstream dependency, fanning out to every upstream caller.
**Fix direction:** application-level timeouts and circuit breakers are the actual fix (not a Kubernetes-level control) — Kubernetes' own health checks/restarts only address the symptom (a crashed pod gets restarted) not the cascading root cause (every restarted pod immediately hits the same slow dependency again).

## 9. Dynamic inventory/label-selector equivalent: a Service silently matching zero pods

**Likely causes:** a label selector typo or a rollout that changed a Deployment's pod-template labels without updating the Service's selector to match — mirrors the companion Ansible repository's [Question 11](../../../ansible/ansible-senior-interview-preparation/interview-questions/02-inventory-variables.md#question-11-the-play-that-matched-zero-hosts) "zero hosts matched" silent-gap pattern, here at the Service/label-selector level.
**Diagnose:** `kubectl get endpoints <service>` showing an empty endpoint list despite pods appearing to run fine; compare the Service's `spec.selector` against the actual pods' labels (`kubectl get pods --show-labels`).
**Fix direction:** correct the mismatched selector/labels; consider an alert on any Service with zero endpoints for more than a brief grace period as a standing guardrail against this exact silent-gap failure mode recurring.

## 10. Helm/Kustomize apply succeeds but nothing actually changed

**Likely causes:** a values/overlay change that doesn't actually affect the rendered manifest (a typo'd key that doesn't match the chart's actual values schema, silently ignored rather than erroring), or a resource whose change requires a pod restart that didn't happen because nothing in the Deployment's pod template itself changed (e.g., an underlying ConfigMap changed, but nothing forces a rollout without a checksum annotation or similar).
**Diagnose:** `helm get values` / `kustomize build` and diff the actual rendered output against expectation, rather than trusting that "the command exited successfully" means "the intended change took effect."
**Fix direction:** for ConfigMap/Secret changes needing to trigger a rollout, use a checksum annotation pattern (hashing the ConfigMap's content into a pod-template annotation) so a content change forces a new ReplicaSet even though the Deployment's own spec otherwise looks unchanged.

## 11. Karpenter/Cluster Autoscaler not scaling when it should

**Likely causes:** IRSA permissions gap on the autoscaler's own ServiceAccount, a `NodePool`/`Provisioner` (Karpenter) or ASG (Cluster Autoscaler) configuration that doesn't actually cover the pending pod's requirements (wrong instance-type constraints, wrong AZ/subnet), or the autoscaler pod itself crashed/is unhealthy.
**Diagnose:** check the autoscaler's own pod logs first (a surprisingly common miss — engineers debug the *application's* pending state extensively before checking whether the autoscaler component itself is even healthy).
**Fix direction:** fix the IRSA role/NodePool constraints/ASG config as the diagnostic reveals; treat the autoscaler's own health as a standing observability signal (§ in `docs/observability.md`), not something checked only reactively.

## 12. GitOps controller shows `OutOfSync` indefinitely, never reconciling

**Likely causes:** the controller lacks permission (its own IRSA/RBAC) to apply the specific resource type/change, a genuinely invalid manifest that fails server-side validation on every attempted apply, or a sync-wave/hook ordering issue where a dependency never becomes healthy so a later-wave resource never gets its turn.
**Diagnose:** the GitOps controller's own UI/CLI (`argocd app get <app>` or equivalent) surfaces the specific sync error, not just "OutOfSync" as a generic status.
**Fix direction:** address the specific surfaced error (permission, validation, ordering) directly — resist the urge to force-sync repeatedly without first reading why the previous attempts failed.

## Related material

- [`docs/networking.md`](networking.md), [`docs/observability.md`](observability.md), [`docs/ha-dr.md`](ha-dr.md)
- [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/)
