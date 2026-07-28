# Category 1: EKS Cluster Architecture and Control Plane

Questions 1–10 of 120. Category weight: 10 questions. Deep-dive reference: [`docs/eks-architecture.md`](../docs/eks-architecture.md).

---

## Question 1: The playbook that tried to configure Kubernetes

### Scenario
A new engineer, coming from a pre-Kubernetes infrastructure background, proposes writing an Ansible role to deploy and update the team's application on the newly-provisioned EKS cluster — templating a systemd-style deployment script that SSHes into... something, and runs `kubectl apply`.

### Interview Question
Is Ansible the right tool for deploying and updating application workloads on EKS? What should replace each piece of what the engineer is trying to do?

### Strong Senior-Level Answer
**Initial assessment:** no — once workloads run on Kubernetes, the platform's own native mechanisms (Deployments, GitOps controllers, Helm/Kustomize) supersede push-based configuration management for *what runs inside the cluster*, exactly the boundary discussed in the companion Ansible repository's [`docs/eks-architecture.md`](../docs/eks-architecture.md) §6 material and mirrored here.

**Technical reasoning:** a `Deployment`'s rolling update already provides paced, health-checked replacement of pod replicas — the exact problem a push-based Ansible playbook with `serial`/handler discipline solves for non-containerized fleets, but here it's a first-class Kubernetes primitive with no external orchestration needed. Similarly, a `ConfigMap`/`Secret` replaces a templated config file deployed by a role, and a GitOps controller's continuous reconciliation (see [`docs/cicd-gitops.md`](../docs/cicd-gitops.md)) replaces any notion of "run a playbook to push the latest state."

**Investigation process:** clarify exactly what the engineer's proposed playbook would actually do step by step — if it's fundamentally "apply a manifest," that's a solved problem via `kubectl apply`/Helm/Kustomize, ideally triggered by a GitOps controller, not a playbook; if it's addressing something genuinely outside Kubernetes' scope (see the next point), that's a different conversation.

**Recommended solution:** replace the proposed playbook with: application manifests/Helm charts describing desired state, committed to a Git repository; a GitOps controller (ArgoCD/Flux) running in-cluster reconciling that desired state continuously; CI pipeline responsibility narrowed to build/test/scan/sign the image and update the Git-declared image tag (see [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §6) — no SSH, no playbook, no push-based deployment step at all.

**Risk controls:** if any genuinely non-Kubernetes-native step remains (e.g., bootstrapping a CI runner's own EC2 instance, or a bastion host used to reach a private cluster endpoint), that step is legitimately Ansible's domain — the risk to control for is scope creep in the *other* direction, someone trying to route genuinely Kubernetes-native concerns back through Ansible out of pre-existing habit.

**Validation steps:** confirm the GitOps controller's sync status accurately reflects what's actually running (`argocd app get` or equivalent), and confirm no lingering out-of-band deployment mechanism (a forgotten cron job, an old CI step) is still directly modifying cluster state outside the GitOps flow.

**Rollback or recovery strategy:** GitOps-managed rollback is a Git revert (reverting the commit that introduced a bad change), which the controller then reconciles automatically — a materially simpler, more auditable rollback path than reconstructing what a playbook run did and reversing it manually.

**Long-term prevention:** document this boundary explicitly for any team transitioning from traditional infrastructure to Kubernetes — Kubernetes-native workload management is not "the same problem, different syntax," it's a different, more automated model that supersedes push-based configuration management for in-cluster concerns.

### Step-by-Step Implementation
```yaml
# What replaces the proposed Ansible role:
# 1. Application manifest (or Helm chart) describing desired state, in Git
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
  template:
    spec:
      containers:
        - name: my-app
          image: my-registry/my-app:v1.2.3
```
```bash
# 2. ArgoCD (or Flux) reconciles this automatically from Git - no manual apply, no playbook
argocd app sync my-app   # only needed manually if auto-sync is disabled
```

### Under-the-Hood Explanation
A `Deployment`'s controller, running as part of the control plane's controller-manager, continuously compares the desired replica count/pod template against actual `ReplicaSet`/`Pod` state and reconciles automatically — this is architecturally the same reconciliation-loop pattern Ansible achieves only when a playbook happens to be run, but built into the platform and running continuously. Layering a push-based playbook on top adds an external, less-integrated, less-observable path to the same state a native mechanism already manages better.

### Common Weak Answer
"Ansible can call `kubectl apply` in a task, so it should work fine."

### Why the Weak Answer Fails
Technically true but misses the point — wrapping `kubectl apply` in a playbook adds an external, uncoordinated trigger for state changes the platform already manages via continuous reconciliation, loses GitOps's audit trail and drift-correction, and reintroduces exactly the push-based, run-it-and-hope model Kubernetes-native tooling was built to replace.

### Follow-Up Questions
1. Where does a legitimate role for Ansible still exist in an EKS-based platform (hint: think about what's *not* Kubernetes-native)?
2. How would you explain this transition to a team with years of Ansible-based configuration management experience without dismissing their existing expertise?
3. What Kubernetes-native mechanism replaces a playbook's `handlers` (deferred, batched restart-on-change behavior)?

### Key Interview Signals
Recognizes Kubernetes-native mechanisms as a genuinely different, more automated model rather than "the same job, different tool," and can articulate specifically what replaces each piece of a traditional configuration-management workflow.

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/) and [Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/).

---

## Question 2: The public endpoint nobody meant to leave open

### Scenario
A security review finds a production EKS cluster's API server endpoint is configured for public access with no CIDR restriction (`0.0.0.0/0` effectively allowed) — "for convenience," since the team's CI runners and engineers connect from varying, unpredictable IP addresses.

### Interview Question
Is this an acceptable configuration? Design the correct endpoint access architecture.

### Strong Senior-Level Answer
**Initial assessment:** an unrestricted public endpoint is a real, unnecessary attack-surface exposure — the API server is the single most powerful control point in the entire cluster, and exposing it broadly for convenience is the same category of mistake as the companion Terraform repository's overly-broad security-group guidance, just applied to Kubernetes' own control-plane API.

**Technical reasoning:** EKS supports private-only, public-with-CIDR-restriction, or public-and-private endpoint access modes (see [`docs/eks-architecture.md`](../docs/eks-architecture.md) §3) — "engineers connect from varying IPs" is a real, legitimate constraint, but it's solved by routing access through a stable network path, not by leaving the endpoint globally open.

**Investigation process:** confirm exactly who/what needs API server access and from where — CI runners (ideally routed through the VPC, not the public internet), engineers (via VPN or a bastion), and any cross-account/cross-cluster automation — this inventory determines the actual correct access design.

**Recommended solution:** switch to private (or public-and-private with a tight CIDR allowlist limited to a VPN's egress IP) endpoint access; route CI runner access through the VPC (self-hosted runners with VPC connectivity, or a VPC-connected CI service); route engineer access through the organization's existing VPN or bastion pattern, exactly as any other sensitive internal service would be reached.

**Risk controls:** during the cutover from public-open to private/restricted, verify every legitimate access path is validated *before* closing the old one — an untested cutover risks locking out CI or on-call engineers during an actual incident, the worst possible time to discover a gap.

**Validation steps:** attempt access from an out-of-VPC, non-allowlisted IP after the change and confirm it's rejected; confirm every previously-working legitimate path (CI, VPN-connected engineers) still functions correctly.

**Rollback or recovery strategy:** EKS endpoint access configuration is quickly reversible (a single API/Terraform-managed setting) if the cutover reveals an unanticipated legitimate access path was missed — revert to the previous mode temporarily while the missed path is properly incorporated into the new design, then re-attempt the tightened configuration.

**Long-term prevention:** treat "is our API server endpoint access appropriately restricted" as a standing item in periodic security reviews, and bake private/restricted endpoint access into the default cluster-provisioning Terraform module (see the companion Terraform repository) so new clusters don't start out over-exposed by default.

### Step-by-Step Implementation
```hcl
# Terraform (companion repo) - tightened endpoint access
resource "aws_eks_cluster" "main" {
  # ...
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["203.0.113.0/24"]  # VPN egress CIDR only, not 0.0.0.0/0
  }
}
```

### Under-the-Hood Explanation
EKS provisions the API server's network reachability according to this configuration — public access (optionally CIDR-restricted) adds an internet-facing listener path, while private access provisions ENIs into your VPC subnets so in-VPC traffic reaches the API server without traversing the internet at all. Restricting public CIDRs doesn't change the control plane's own security, but it dramatically reduces who can even attempt to reach it, the same defense-in-depth logic as restricting a security group's ingress rule.

### Common Weak Answer
"It's fine, the API server still requires authentication, so being publicly reachable isn't a real risk."

### Why the Weak Answer Fails
Authentication is one layer, but reducing exposed attack surface is a separate, complementary layer — an unrestricted public endpoint is reachable by anyone attempting credential-stuffing, exploiting a future API-server vulnerability, or simply probing for information, none of which requires bypassing authentication to be a meaningful risk; least-exposure and authentication are both needed, not one instead of the other.

### Follow-Up Questions
1. How would you design CI runner access for a fully private-endpoint cluster?
2. What's the operational cost/trade-off of private-only access for a distributed team with unpredictable IPs?
3. How would you detect if this misconfiguration recurs on a future cluster (a policy-as-code or Terraform-level guardrail)?

### Key Interview Signals
Treats API server exposure with the same least-privilege, least-exposure discipline applied to any other sensitive infrastructure component, and designs a concrete, validated cutover rather than an abstract recommendation.

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/).

---

## Question 3: The CoreDNS nobody remembered installing twice

### Scenario
DNS resolution inside a cluster becomes intermittently unreliable. Investigation reveals two separate CoreDNS deployments running simultaneously — the EKS-managed add-on version, and a second, manually Helm-installed CoreDNS a previous engineer added "for more configuration control," both attempting to serve the same `kube-dns` Service.

### Interview Question
Diagnose the actual conflict and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** this is the add-on-ownership conflict named explicitly in [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md) §4 — two independently-managed CoreDNS installations both trying to own the same DNS-serving role creates unpredictable behavior (which one actually answers a given query depends on Service/endpoint selection details neither installation is aware the other exists), and neither the EKS-managed add-on's reconciliation nor the self-managed Helm release's own upgrade process accounts for the other's existence.

**Technical reasoning:** the EKS-managed `coredns` add-on and a self-managed Helm-installed CoreDNS both ultimately create Deployment/Service objects serving cluster DNS — if both exist, DNS queries may be answered inconsistently (depending on load-balancing across whichever pods are actually behind the resolved Service's endpoints), and an EKS-managed add-on update could conflict with or be silently undone by the self-managed installation's own reconciliation, or vice versa.

**Investigation process:** confirm via `kubectl get deployments -n kube-system` and `kubectl get pods -n kube-system -l k8s-app=kube-dns` (or equivalent labels) exactly how many CoreDNS-serving Deployments exist and which Service(s) route to which — this settles the diagnosis concretely rather than guessing from symptom reports alone.

**Recommended solution:** consolidate to exactly one CoreDNS installation — given the configuration-control need that motivated the second installation, evaluate whether the EKS-managed add-on's `configurationValues` (allowing meaningful Corefile customization without abandoning the managed add-on entirely) actually covers the team's real requirement before defaulting to a fully self-managed installation; if genuinely custom configuration beyond what the managed add-on supports is required, remove the EKS-managed add-on entirely and standardize on the self-managed installation as the sole owner, never both.

**Risk controls:** removing either installation is itself a DNS-availability-affecting change — perform it during a low-traffic window with the other installation already confirmed healthy and fully serving before decommissioning the redundant one, to avoid a gap where neither is fully functional.

**Validation steps:** after consolidation, confirm DNS resolution is consistently reliable under load (no intermittent failures), and confirm only one CoreDNS-serving Deployment exists going forward.

**Rollback or recovery strategy:** keep the removed installation's manifests/Helm values available for a defined window in case the remaining installation reveals a functional gap the removed one was actually covering.

**Long-term prevention:** before installing any component via Helm/self-managed means, check whether an EKS-managed add-on for that exact component already exists — a standing pre-installation check to prevent this specific dual-ownership conflict from recurring for CoreDNS or any other EKS-manageable component (`vpc-cni`, `kube-proxy`, CSI drivers).

### Step-by-Step Implementation
```bash
# Diagnose: how many CoreDNS Deployments actually exist
kubectl get deployments -n kube-system -l k8s-app=kube-dns
kubectl get deployments -n kube-system --all-labels | grep -i coredns

# Consolidate: remove the redundant self-managed installation
helm uninstall coredns-custom -n kube-system

# Confirm the EKS-managed add-on covers the needed configuration
aws eks describe-addon --cluster-name my-cluster --addon-name coredns \
  --query 'addon.configurationValues'
```

### Under-the-Hood Explanation
Both a self-managed Helm release and the EKS-managed add-on ultimately just create standard Kubernetes objects (Deployment, Service, ConfigMap for the Corefile) — Kubernetes itself has no inherent awareness that "these two Deployments are conceptually the same logical component" and enforces no exclusivity between them; whichever Service's endpoints happen to be queried determines behavior, with load-balancing across whatever pods match the selector, regardless of which installation created them, which is exactly why the resulting behavior is confusing and inconsistent rather than a clean, obvious failure.

### Common Weak Answer
"Just delete one of the Deployments directly."

### Why the Weak Answer Fails
Deleting the Deployment object alone doesn't address the underlying add-on/Helm-release ownership — the EKS-managed add-on's own reconciliation (or the Helm release's next `helm upgrade`) would simply recreate whichever one wasn't properly uninstalled through its actual management mechanism, right back into the same conflict.

### Follow-Up Questions
1. How would you detect this exact class of dual-ownership conflict for other add-ons before it causes an incident?
2. What's the trade-off of the EKS-managed add-on's `configurationValues` flexibility versus a fully self-managed CoreDNS installation?
3. How does this scenario relate to the companion repositories' "two tools believe they own the same resource" pattern (Terraform/Ansible boundary, or Terraform/Kubernetes-native boundary from Question 1)?

### Key Interview Signals
Diagnoses a dual-ownership conflict precisely (not just "DNS is broken, restart it") and designs a deliberate consolidation rather than a quick, incomplete patch.

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/) and [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) (add-on lifecycle).

---

## Question 4: The latency spike nobody could explain

### Scenario
`kubectl` commands and application deployments across the entire cluster become noticeably slow (multi-second latency for simple operations) for about fifteen minutes, then resolve on their own. No node, pod, or application-level change correlates with the timing.

### Interview Question
Walk through how you'd diagnose this, including how you'd determine whether this is even something you can fix.

### Strong Senior-Level Answer
**Initial assessment:** cluster-wide latency affecting *every* `kubectl`/API operation, with no workload-level correlation, points toward the control plane itself (API server or etcd) rather than anything in the data plane — and per [`docs/eks-architecture.md`](../docs/eks-architecture.md) §1, the control plane is entirely AWS-managed, meaning the actual remediation, if any is needed beyond waiting it out, may not be something you can directly perform.

**Technical reasoning:** distinguishing "every API operation is slow" from "one specific workload/node is having trouble" is the key diagnostic branch — the former implicates the API server/etcd (AWS-managed), the latter implicates something node/workload-specific (your responsibility). A brief, self-resolving, cluster-wide slowdown with no correlating change on your side is consistent with a transient AWS-side control-plane event (increased API server load from another tenant sharing the underlying infrastructure, a control-plane scaling event, or an AWS-side issue) rather than anything caused by your own actions.

**Investigation process:** check AWS's own Personal Health Dashboard and the EKS service health status for the account/region during the affected window — this is the first, fastest way to confirm or rule out a known AWS-side event; separately, check whether your own API request volume spiked during that window (a sudden burst of `kubectl`/controller API calls from your side, e.g., from a runaway reconciliation loop or a CI pipeline gone wrong) as an alternative, self-inflicted explanation before assuming it's purely AWS-side.

**Recommended solution:** if AWS's health dashboard confirms a control-plane-side event, the correct action is monitoring for resolution and, if genuinely business-impacting, opening an AWS Support case (with your account's support tier) referencing the observed timestamps — not attempting to "fix" something you have no access to. If your own request volume was the cause, the fix is on your side: identify and throttle whatever generated the excessive API load.

**Risk controls:** during any control-plane latency event, avoid making the situation worse by retrying failed operations aggressively in a tight loop (compounding an already-elevated API server load) — back off and let the situation stabilize rather than hammering the API server with retries.

**Validation steps:** confirm latency has genuinely returned to baseline (not just "the specific command I tried worked once") across multiple operation types before considering the incident resolved.

**Rollback or recovery strategy:** not directly applicable for a control-plane-side event — there's nothing to roll back on your end; for a self-inflicted excessive-request-volume cause, the "rollback" is stopping/fixing whatever generated the load.

**Long-term prevention:** for AWS-side events, none available beyond AWS's own infrastructure improvements over time; for self-inflicted causes, add monitoring/alerting on your own API request rate against the API server so a runaway reconciliation loop or misbehaving controller is caught before it causes a cluster-wide slowdown, and consider client-side rate limiting/backoff configuration in any custom controllers.

### Step-by-Step Implementation
```bash
# Check AWS-side health first
aws health describe-events --filter services=EKS --region us-east-1

# Check your own API server request volume/latency via API server metrics
# (if API server metrics are exported to your observability stack)
kubectl get --raw /metrics | grep apiserver_request_duration_seconds
```

### Under-the-Hood Explanation
The EKS API server is AWS-managed infrastructure, potentially subject to control-plane scaling events, underlying infrastructure maintenance, or (rarely) broader regional service issues — none of which are directly observable or actionable from your side beyond AWS's own published health status. A self-inflicted cause (excessive client-side request volume) is directly observable via API server request-rate metrics if your observability stack captures them, distinguishing this from a genuinely external cause.

### Common Weak Answer
"Restart the nodes/pods to fix it."

### Why the Weak Answer Fails
If the actual cause is control-plane-side (API server/etcd), restarting data-plane components (nodes, pods) does nothing to address it — this response reflects not having correctly diagnosed which side of the control-plane/data-plane boundary the problem actually lives on, per [`docs/eks-architecture.md`](../docs/eks-architecture.md) §1.

### Follow-Up Questions
1. What would change about your diagnosis if the latency correlated with a specific namespace's activity rather than being truly cluster-wide?
2. How would you design alerting to catch a self-inflicted excessive-API-request-volume cause before it becomes cluster-wide latency?
3. What's an appropriate AWS Support engagement path for a genuinely business-impacting control-plane event, and what information would you include?

### Key Interview Signals
Correctly attributes a symptom to the control-plane/data-plane boundary before proposing remediation, and recognizes when the honest answer is "this isn't something I can directly fix" rather than taking ineffective action for the sake of appearing to do something.

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 5: The upgrade that skipped a step

### Scenario
A team upgrades their EKS cluster's control plane from 1.27 to 1.29 in one action (skipping 1.28), then immediately upgrades all node groups to match. Several workloads immediately start failing with API-version-not-found errors, and the AWS Load Balancer Controller stops reconciling ALB target groups correctly.

### Interview Question
What went wrong here, and how should this upgrade have been performed?

### Strong Senior-Level Answer
**Initial assessment:** two separate mistakes compounded here: EKS does not support skipping minor versions (1.27 → 1.29 directly is not a supported upgrade path in the first place — this should have failed or been blocked, but if it was somehow forced through automation bypassing that guardrail, it's now in an unsupported, undocumented state), and the upgrade sequencing itself (control plane and nodes together, without checking add-on compatibility in between) violates the order established in [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md) §2.

**Technical reasoning:** skipping a minor version means any API removed *in the skipped version* (1.28) was never surfaced as a distinct, isolated concern — both 1.28's and 1.29's changes hit simultaneously, making it far harder to isolate which specific version bump caused which specific failure. Separately, the AWS Load Balancer Controller (a self-managed add-on) has its own compatibility matrix against the Kubernetes API version — upgrading nodes (and therefore the effective API surface workloads run against) without first confirming the Load Balancer Controller's version supports the new control-plane version is exactly the "self-managed add-ons checked before node upgrade" step that was skipped.

**Investigation process:** confirm the exact sequence of what was upgraded and when (control plane version history via `aws eks describe-cluster`, node group launch template history, Load Balancer Controller's deployed image tag) — this reconstructs exactly which step was skipped and correlates it with when each specific failure started appearing.

**Recommended solution:** roll the process back to a supported sequence: if still possible, downgrade is generally not supported for EKS control planes, so remediation here means moving *forward* correctly — upgrade the Load Balancer Controller (and any other self-managed add-on) to a version confirmed compatible with 1.29 immediately, and separately audit and fix every API-version-not-found error by updating the affected manifests to the current, non-removed API versions.

**Risk controls:** for any future upgrade, enforce the one-minor-version-at-a-time constraint explicitly (EKS itself blocks skipping via its own API validation under normal circumstances — if this was bypassed, investigate how, since that itself is a process gap) and require a documented pre-upgrade deprecated-API scan (`pluto`/`kubent`) as a gating step before any control-plane version bump.

**Validation steps:** after remediation, confirm every previously-failing workload now runs correctly, confirm the Load Balancer Controller is successfully reconciling target groups again, and run a full deprecated-API scan against the now-current state to catch any remaining latent issues.

**Rollback or recovery strategy:** for the immediate incident, prioritize fixing the Load Balancer Controller version mismatch and the specific broken API references over attempting any control-plane downgrade (generally unsupported/impractical) — moving forward correctly is the realistic recovery path here.

**Long-term prevention:** institutionalize the full upgrade sequence (deprecated-API scan → control plane, one minor version at a time → EKS-managed add-ons → self-managed add-ons, version-matrix-checked → node groups last) as a documented, checklist-enforced runbook for every future upgrade, per [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md) §2.

### Step-by-Step Implementation
See the upgrade sequencing diagram: [`diagrams/09-cluster-upgrade-sequencing.md`](../diagrams/09-cluster-upgrade-sequencing.md).

### Under-the-Hood Explanation
Kubernetes' API deprecation policy removes APIs across specific version boundaries with advance notice, but only if you actually observe each intermediate version's changes — skipping directly from 1.27 to 1.29 means you experience both 1.28's and 1.29's changes at once, with no isolated signal of which version introduced which specific breaking change, and no opportunity to catch and fix a 1.28-specific issue before also taking on 1.29's changes.

### Common Weak Answer
"Just upgrade everything to the latest version each time to stay current."

### Why the Weak Answer Fails
"Latest" isn't a safe upgrade target without respecting the one-minor-version-at-a-time constraint and the add-on compatibility checks at each step — this is precisely the mistake that caused this incident, treating version currency as more important than sequenced, verified compatibility at each step.

### Follow-Up Questions
1. How would you build automated tooling to enforce the correct upgrade sequence and prevent this from being bypassed again?
2. What's your incident-communication approach when an upgrade breaks production workloads mid-sequence?
3. How would you use a non-production cluster to validate an upgrade path before applying it to production?

### Key Interview Signals
Diagnoses the compounding of two distinct mistakes (version-skipping and sequencing) rather than treating this as one generic "the upgrade broke things" incident, and proposes forward-moving remediation grounded in the correct sequence rather than an impractical rollback.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).

---

## Question 6: "Can we just look at etcd directly?"

### Scenario
During a confusing incident where cluster state seems inconsistent with what's expected, a teammate suggests: "let's just check etcd directly to see what's really stored."

### Interview Question
How do you respond, and what do you do instead?

### Strong Senior-Level Answer
**Initial assessment:** on EKS, there is no direct etcd access available at all — it's part of the AWS-managed control plane, with no customer-facing API, SSH path, or credential that grants direct etcd access, a firm architectural boundary rather than a permissions issue that could be worked around.

**Technical reasoning:** everything etcd stores is already fully observable through the Kubernetes API server itself (`kubectl get <resource> -o yaml` returns exactly what's persisted, since the API server is etcd's only interface) — there's no category of information "in etcd" that isn't equally inspectable via the API server, so the desire to check etcd directly is almost always actually a desire to see the full, raw object state, which `kubectl get -o yaml` (or `-o json`) already provides completely.

**Investigation process:** clarify what specifically the teammate believes might differ between "what the API server reports" and "what's really in etcd" — in nearly every case, this turns out to be a misunderstanding of what's actually being observed (e.g., a caching layer like `kubectl`'s client-side cache, or a controller's own stale in-memory view, rather than etcd itself being out of sync with the API server, which would indicate a genuinely serious control-plane bug that's exceptionally rare and would be an AWS-side incident, not something to investigate by hand).

**Recommended solution:** use `kubectl get <resource> -o yaml --show-managed-fields` for the fullest possible view of a resource's actual stored state via the API server, and if genuinely suspicious of an API-server-vs-etcd inconsistency (extremely rare), that's an AWS Support engagement, not a customer-side debugging task, since there's no customer-facing tool to inspect etcd independently of the API server in the first place.

**Risk controls:** redirect the debugging effort toward what's actually inspectable and actionable (API server state, controller logs, events) rather than pursuing an access path that doesn't exist on EKS, which would waste incident-response time.

**Validation steps:** confirm the actual inconsistency by comparing what different clients observe via the API server (e.g., is `kubectl` showing stale data due to a caching issue, versus a fresh `kubectl get --raw` API call) before concluding anything is genuinely wrong at the storage layer.

**Rollback or recovery strategy:** not applicable — this is a diagnostic-approach correction, not an infrastructure change.

**Long-term prevention:** ensure the team's shared mental model of "the control plane is AWS-managed, etcd is not customer-accessible" is established well before an incident, so this exact detour doesn't consume time during a real, time-pressured investigation.

### Step-by-Step Implementation
```bash
# The full, complete view of a resource's actual stored state - via the API server, not etcd directly
kubectl get deployment my-app -o yaml --show-managed-fields

# A genuinely fresh, uncached read
kubectl get --raw /apis/apps/v1/namespaces/default/deployments/my-app
```

### Under-the-Hood Explanation
etcd is the API server's private, internal storage backend on EKS — there is no other component, credential, or network path that reaches it directly in a managed EKS cluster (unlike a self-managed Kubernetes cluster, where cluster operators typically do have direct etcd access for backup/restore and genuinely can inspect it independently). Every "what's really stored" question is fully answerable through the API server, which is the sole reader/writer of etcd's contents.

### Common Weak Answer
"Let's try to SSH into the control plane nodes to check etcd."

### Why the Weak Answer Fails
There are no customer-accessible control-plane nodes on EKS at all — this response reflects a fundamental misunderstanding of EKS's managed control-plane model, attempting an access path that doesn't exist rather than recognizing the API server already provides complete visibility into everything etcd stores.

### Follow-Up Questions
1. How would this answer differ for a self-managed (non-EKS) Kubernetes cluster where you do have etcd access?
2. What's the correct way to escalate to AWS Support if you genuinely suspect a control-plane-level inconsistency?
3. How would you explain the API-server-as-sole-etcd-interface model to a teammate new to Kubernetes?

### Key Interview Signals
Correctly identifies the firm architectural boundary (no customer etcd access on EKS) rather than searching for a workaround, and redirects debugging effort toward what's actually observable and actionable.

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 7: One cluster, every environment

### Scenario
A cost-conscious team proposes running dev, staging, and production workloads all in a single shared EKS cluster, separated only by Kubernetes namespaces, to avoid paying for three separate clusters' control-plane costs and to simplify operations.

### Interview Question
Evaluate this proposal. What are the real trade-offs, and what would you recommend?

### Strong Senior-Level Answer
**Initial assessment:** this is a genuine, legitimate trade-off worth reasoning through carefully rather than a clear yes/no — namespace isolation (per [`diagrams/15-multi-tenant-isolation-model.md`](../diagrams/15-multi-tenant-isolation-model.md)) provides real but bounded isolation, and whether that's sufficient depends heavily on what's actually at stake for production specifically.

**Technical reasoning:** namespace-level isolation covers RBAC, ResourceQuota, NetworkPolicy, and (with care) node-pool separation via taints/tolerations — meaningful, but blast radius for anything affecting the *entire cluster* (a bad cluster-wide policy rollout, an add-on misconfiguration, a control-plane-level incident, a node group-wide issue) is shared across dev/staging/production regardless of namespace boundaries. A dev-environment mistake that somehow affects cluster-wide resources (a misconfigured cluster-wide admission policy, a runaway workload exhausting shared node capacity) can directly impact production in a fully-shared cluster in a way that's structurally impossible in a separate-clusters design.

**Investigation process:** assess what specifically drives the cost concern (EKS control-plane cost is relatively modest — roughly $0.10/hour per cluster — so for most organizations the *real* cost driver is compute/node costs, which are shared regardless of cluster-count architecture) and what the actual risk tolerance is for a dev/staging mistake affecting production (regulatory/compliance requirements often mandate hard separation for production specifically, independent of cost reasoning).

**Recommended solution:** the common, pragmatic middle ground: separate clusters for production specifically (isolating your highest-stakes environment from any possibility of dev/staging cross-contamination), while dev and staging (lower-stakes, more cost-sensitive) can reasonably share a cluster with strong namespace isolation (RBAC, ResourceQuota, NetworkPolicy, and ideally separate node pools) — capturing most of the cost savings while keeping production's blast radius fully isolated.

**Risk controls:** if a fully-shared cluster is chosen despite the trade-offs (a legitimate choice for some organizations, particularly smaller teams with lower risk tolerance concerns), compensate with the strongest possible namespace isolation (dedicated node pools per environment via taints/tolerations, strict NetworkPolicy default-deny between namespaces, ResourceQuota preventing any one environment from starving others) rather than relying on namespace boundaries alone.

**Validation steps:** for whichever design is chosen, deliberately test the actual isolation boundary — attempt a cross-namespace network connection that should be blocked, attempt to exceed a ResourceQuota, confirm production's node pool is genuinely unreachable by dev/staging workloads if node-pool separation is part of the design.

**Rollback or recovery strategy:** migrating from a shared-cluster to a separate-clusters design later (if the shared approach proves insufficient) is a genuine, non-trivial migration project — a reason to make this decision deliberately upfront rather than treating cluster topology as an easily-reversible choice.

**Long-term prevention:** document the actual reasoning behind whichever cluster topology is chosen (not just "we did this for cost reasons") so a future team revisiting the decision understands the real trade-offs that were weighed, not just the conclusion.

### Step-by-Step Implementation
Recommended: separate production cluster; shared dev/staging cluster with per-namespace `ResourceQuota`, `NetworkPolicy` default-deny, and dedicated node pools per environment via taints/tolerations (see [`diagrams/15-multi-tenant-isolation-model.md`](../diagrams/15-multi-tenant-isolation-model.md)).

### Under-the-Hood Explanation
Namespace boundaries are a Kubernetes-API-level organizational construct enforced by RBAC/quota/network-policy objects scoped to them — they do not create any inherent compute or control-plane isolation on their own; a cluster-wide resource (a CRD, a cluster-scoped admission policy, the node pool itself if shared) exists outside any single namespace's boundary and can affect every namespace simultaneously, which is precisely the shared blast-radius risk namespace-only isolation cannot address.

### Common Weak Answer
"Namespaces provide full isolation, so this is totally safe."

### Why the Weak Answer Fails
This overstates namespace isolation's actual guarantees — cluster-wide concerns (control-plane incidents, cluster-scoped policy misconfigurations, shared node-pool exhaustion) cross namespace boundaries entirely, a real and non-trivial risk this answer dismisses rather than reasoning through.

### Follow-Up Questions
1. How would you quantify the actual cost savings of a shared cluster versus the risk being accepted, to help leadership make an informed trade-off decision?
2. What specific compliance/regulatory requirements (if any) might mandate hard cluster separation regardless of cost reasoning?
3. How would you design a migration path from a shared cluster to separate clusters if the risk profile later changes?

### Key Interview Signals
Reasons through the actual, bounded nature of namespace isolation rather than treating it as complete isolation, and lands on a pragmatic, risk-appropriate recommendation (production separated, lower environments shared) rather than an absolute position in either direction.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 8: Fargate for everything?

### Scenario
A team, impressed by Fargate's "no nodes to manage" pitch, proposes running their entire workload fleet — including a DaemonSet-based log-shipping agent and a latency-sensitive, steady-state high-throughput service — entirely on Fargate.

### Interview Question
Evaluate this plan for each specific workload type mentioned.

### Strong Senior-Level Answer
**Initial assessment:** Fargate is an excellent fit for some workload shapes and a poor fit for others named in this exact scenario — a blanket "everything on Fargate" plan misses real, workload-specific constraints and cost trade-offs covered in [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §1.

**Technical reasoning:** Fargate does not support DaemonSets at all — a DaemonSet requires one pod per node, and Fargate has no persistent "node" concept in the traditional sense (each pod gets its own isolated compute), making the log-shipping DaemonSet fundamentally incompatible with Fargate as designed; it needs to run on EC2-backed nodes (or be redesigned as a sidecar-per-pod pattern instead of a DaemonSet, a more invasive application-level change). For the steady-state, high-throughput, latency-sensitive service, Fargate's per-pod pricing model is generally more expensive than well-utilized EC2 capacity at steady, predictable, high utilization — Fargate's value proposition is strongest for variable, bursty, or operationally-simple workloads where the premium for zero node management is worth paying, not for steady-state high-throughput services where EC2's better cost-at-utilization economics dominate.

**Investigation process:** categorize the fleet's actual workloads by shape (steady vs. bursty, DaemonSet-dependent vs. not, latency-sensitive vs. tolerant) rather than evaluating Fargate as a single yes/no decision for the whole fleet.

**Recommended solution:** run the DaemonSet-dependent log-shipping agent on EC2-backed node groups (it structurally requires this); run the steady-state, high-throughput service on EC2-backed nodes (managed node groups or Karpenter) for better cost efficiency at its predictable, sustained utilization; reserve Fargate for workloads that genuinely benefit from its trade-offs — bursty/spiky workloads, batch jobs, low-traffic services where operational simplicity outweighs the per-pod cost premium, or contexts (like some multi-tenant/regulated environments) valuing Fargate's stronger per-pod isolation.

**Risk controls:** if application-level logging is redesigned as a sidecar to accommodate Fargate for some services, verify the sidecar pattern doesn't meaningfully increase per-pod resource cost/complexity in a way that erodes Fargate's own value proposition for that workload.

**Validation steps:** run a cost comparison (actual observed EC2 utilization vs. Fargate's per-pod pricing) for the high-throughput service specifically, using real usage data rather than a generic assumption in either direction.

**Rollback or recovery strategy:** migrating a workload between Fargate and EC2-backed node groups is a relatively contained change (adjusting the Fargate profile/node-selector and redeploying) — not a high-risk, hard-to-reverse decision, which somewhat lowers the stakes of getting the initial choice slightly wrong for any individual workload.

**Long-term prevention:** establish a lightweight, workload-shape-based decision framework (DaemonSet-dependent → EC2; steady-state high-throughput → EC2; bursty/simple/isolation-sensitive → Fargate) so future workload-placement decisions aren't made on a single, appealing marketing pitch alone.

### Step-by-Step Implementation
```yaml
# Fargate profile - selects which namespaces/labels run on Fargate
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
fargateProfiles:
  - name: batch-jobs
    selectors:
      - namespace: batch
        labels:
          compute: fargate
# The DaemonSet-based log agent and the steady-state high-throughput
# service are deliberately NOT included in any Fargate profile selector -
# they run on EC2-backed node groups instead.
```

### Under-the-Hood Explanation
Fargate provisions isolated, right-sized micro-VMs per pod on demand rather than scheduling pods onto a shared, persistent node — this is precisely why DaemonSets (which require a stable, addressable "one pod per node" relationship to actual, persistent nodes) don't map onto Fargate's model, and why Fargate's per-pod pricing (covering the full isolated compute allocation for that pod specifically) doesn't benefit from the same bin-packing/utilization efficiency a well-tuned EC2 node group achieves for many pods sharing one node's resources.

### Common Weak Answer
"Fargate removes node management overhead, so it's strictly better for everything."

### Why the Weak Answer Fails
This ignores Fargate's structural incompatibility with DaemonSets and its generally worse cost-at-utilization economics for steady-state, high-throughput workloads — "removes operational overhead" is a real benefit for the right workload shapes, but doesn't make Fargate universally superior regardless of workload characteristics.

### Follow-Up Questions
1. How would you redesign the log-shipping requirement if the team insisted on an all-Fargate fleet despite the DaemonSet incompatibility?
2. What's the actual cost crossover point (in terms of utilization) where EC2 becomes cheaper than Fargate for a given workload?
3. How does Fargate's per-pod isolation model change your security/multi-tenancy posture compared to shared EC2 nodes?

### Key Interview Signals
Evaluates Fargate per actual workload shape and structural constraints (DaemonSet incompatibility, cost-at-utilization) rather than accepting a blanket "no nodes to manage" pitch at face value.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).

---

## Question 9: Where the Terraform apply ends

### Scenario
An engineer asks: "Once Terraform has run `apply` and the EKS cluster shows as `ACTIVE`, what's actually left to do before this cluster can run production workloads?"

### Interview Question
Answer this directly — what does Terraform's `apply` completing actually leave you with, and what's the gap to a genuinely production-ready cluster?

### Strong Senior-Level Answer
**Initial assessment:** a `terraform apply` completing and the cluster showing `ACTIVE` means the control plane exists and is reachable — it says nothing about whether any of the operational capabilities a real workload needs (ingress, autoscaling, observability, security policy, GitOps) are yet in place, per the Terraform/this-repo boundary in [`docs/eks-architecture.md`](../docs/eks-architecture.md) §5.

**Technical reasoning:** an `ACTIVE` cluster from Terraform typically includes the control plane, node groups (or Fargate profiles), core networking (VPC, subnets), and whatever EKS-managed add-ons the Terraform module explicitly installs (`vpc-cni`, `coredns`, `kube-proxy` are often bootstrapped automatically or via the module) — but self-managed components (Load Balancer Controller, an autoscaler, a GitOps controller, an observability stack, admission policy) are a separate, subsequent installation step, not something `terraform apply` on the cluster resource itself provides.

**Investigation process:** enumerate exactly what's present immediately post-`apply` by checking `kubectl get pods -A` against a fresh cluster — this concretely shows what's already running (typically just the EKS-managed add-ons and nothing else) versus what's still needed.

**Recommended solution:** the concrete remaining checklist before genuine production-readiness: install and configure the AWS Load Balancer Controller (for any Ingress/Service-type-LoadBalancer workload), install an autoscaler (Karpenter or Cluster Autoscaler), install and configure IRSA/Pod Identity for any workload needing AWS API access, apply baseline security policy (Pod Security Standards at minimum, ideally Kyverno/Gatekeeper for custom policy), stand up observability (logging, metrics, alerting), and establish the GitOps controller and repository structure that will actually manage ongoing workload deployment — each of these is covered by a specific lab in this repository (Labs 2–3, 5, 8–10).

**Risk controls:** treat "cluster is `ACTIVE`" and "cluster is production-ready" as two explicitly distinct milestones in any project plan or runbook — conflating them risks a team believing infrastructure work is complete when substantial operational setup remains.

**Validation steps:** before declaring a cluster genuinely production-ready, confirm each of the above capabilities is not just installed but actually verified working (an Ingress successfully provisions a real ALB and routes traffic; the autoscaler successfully provisions a node in response to a test pending pod; IRSA successfully vends credentials to a test pod; a deliberately-malformed manifest is actually rejected by admission policy).

**Rollback or recovery strategy:** not directly applicable — this is a readiness-checklist framing, not an infrastructure change with its own rollback path.

**Long-term prevention:** maintain this checklist as a living, versioned artifact (this repository's own lab sequence serves this purpose) so every new cluster's path to production-readiness is consistent and nothing gets silently skipped.

### Step-by-Step Implementation
```bash
# Immediately after terraform apply - what's actually there
kubectl get pods -A
# Typically shows only: coredns, kube-proxy, aws-node (vpc-cni) - and nothing else

# The remaining checklist (each is a separate lab in this repository):
# - AWS Load Balancer Controller  (Lab 7)
# - Karpenter or Cluster Autoscaler (Lab 5)
# - IRSA / Pod Identity setup for workloads (Lab 3)
# - Pod Security Standards + Kyverno/Gatekeeper (Lab 8, Lab 13)
# - Observability stack (Lab 9)
# - GitOps controller + repo structure (Lab 10)
```

### Under-the-Hood Explanation
Terraform's `aws_eks_cluster` (and associated node group/add-on resources) resource model covers exactly what AWS's EKS API itself provisions — the control plane, node infrastructure, and EKS-managed add-ons explicitly declared in the Terraform configuration. Everything self-managed (installed via Helm/manifests rather than the EKS API) is, by definition, outside that resource's scope — it requires its own separate provisioning step, whether via additional Terraform (Helm provider resources) or a subsequent GitOps-managed bootstrap.

### Common Weak Answer
"Once `terraform apply` finishes, the cluster is ready to use."

### Why the Weak Answer Fails
This conflates "the control plane exists and is reachable" with "a production-grade operational platform is in place" — a materially large gap covering ingress, autoscaling, security policy, observability, and deployment tooling that a bare `ACTIVE` cluster provides none of by default.

### Follow-Up Questions
1. How would you automate this entire post-provisioning bootstrap sequence so it's not a manual checklist each time?
2. Which of these capabilities would you consider truly non-negotiable before any workload runs, versus nice-to-have?
3. How does this checklist change for a cluster dedicated to a single, simple workload versus a shared multi-tenant platform?

### Key Interview Signals
Draws a precise, concrete line between what Terraform's `apply` actually delivers and what's still needed for genuine production-readiness, naming each specific remaining capability rather than a vague "some more setup."

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/) through [Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/) collectively.

---

## Question 10: The add-on that updated itself into an outage

### Scenario
An EKS-managed add-on (`vpc-cni`) was configured with automatic version updates enabled ("so we never fall behind"). During a routine AWS-initiated update window, the add-on updates to a new version with a behavior change that's incompatible with a custom `ENABLE_PREFIX_DELEGATION` setting the team had configured — causing new pod scheduling to fail cluster-wide until discovered and fixed.

### Interview Question
What's the actual trade-off with automatic add-on updates, and how would you configure this going forward?

### Strong Senior-Level Answer
**Initial assessment:** automatic updates for a foundational, cluster-critical add-on like the VPC CNI trade update-currency convenience for a genuine, if infrequent, risk of an unreviewed change interacting badly with existing custom configuration — exactly the kind of unpinned, "we'll always get the latest" choice the companion Terraform and Ansible repositories consistently caution against for anything where reproducibility and reviewed change matters.

**Technical reasoning:** EKS-managed add-ons support configurable update policies — automatic (AWS applies new versions during its own maintenance windows without your explicit action) versus manual (you explicitly choose when to update, reviewing release notes/compatibility first). For a component as foundational as the VPC CNI (governing pod networking cluster-wide), an unreviewed automatic update is a large blast-radius risk for the convenience it buys.

**Investigation process:** confirm via the add-on's own version history (`aws eks describe-addon`) exactly when the automatic update occurred and correlate it with the onset of the scheduling failures — and review the new version's release notes/changelog for the specific behavior change affecting `ENABLE_PREFIX_DELEGATION` interaction.

**Recommended solution:** switch foundational, cluster-critical add-ons (VPC CNI, CoreDNS, kube-proxy, CSI drivers) to manual update mode, incorporating their version bumps into the same reviewed, sequenced upgrade process described in [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md) §2 — reviewing release notes and testing in a non-production cluster before applying, exactly like any other version-sensitive component in this repository's guidance.

**Risk controls:** for the immediate incident, roll back to the previous, known-working add-on version (`aws eks update-addon` targeting the prior version) as the fastest path to restoring normal pod scheduling, then plan the version bump (with the custom configuration compatibility fix) deliberately rather than reactively.

**Validation steps:** after switching to manual updates, confirm no further unplanned/unreviewed version changes occur, and confirm any future planned update is validated in non-production first.

**Rollback or recovery strategy:** `aws eks update-addon` supports targeting a specific previous version directly — use this for the immediate rollback rather than attempting to manually patch the new version's behavior to accommodate the old configuration.

**Long-term prevention:** treat "automatic vs. manual update policy" as a deliberate, per-add-on decision made explicitly during initial cluster setup (documented in the companion Terraform module's configuration) rather than an unreviewed default — reserving automatic updates, if used at all, for genuinely low-blast-radius add-ons where the convenience clearly outweighs the risk.

### Step-by-Step Implementation
```hcl
# Terraform - explicit, reviewed add-on version management, not automatic
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  addon_version            = "v1.18.1-eksbuild.1"  # explicitly pinned, reviewed before bumping
  resolve_conflicts_on_update = "PRESERVE"           # don't silently overwrite custom config like ENABLE_PREFIX_DELEGATION
}
```

### Under-the-Hood Explanation
EKS-managed add-ons with automatic update policy enabled are updated by AWS during a maintenance window according to AWS's own update cadence for that add-on, independent of your own change-review process — any custom configuration you've applied on top of the add-on's defaults (like `ENABLE_PREFIX_DELEGATION`) is only preserved across an update if the update mechanism's conflict-resolution setting (`resolve_conflicts_on_update`) is configured to preserve it, and even then, a new version's *behavior* (not just its configuration surface) can change in ways that interact badly with an existing custom setting regardless of configuration preservation.

### Common Weak Answer
"Automatic updates are good because you never fall behind on security patches."

### Why the Weak Answer Fails
This is true as far as it goes, but ignores the real trade-off — for a foundational, cluster-critical component, an unreviewed automatic update carries genuine risk of an incompatible behavior change, and the correct mitigation (staying current via a deliberate, reviewed, tested manual process) achieves the security-currency goal without accepting the unreviewed-change risk.

### Follow-Up Questions
1. Which specific add-ons, if any, would you consider low-risk enough for automatic updates, and why?
2. How would you design a non-production cluster's add-on-version testing process to catch this kind of incompatibility before it reaches production?
3. What monitoring would have caught this issue faster than "pods started failing to schedule cluster-wide"?

### Key Interview Signals
Recognizes automatic-update convenience as a genuine trade-off against reviewed-change safety for foundational components, and applies the same pin-and-review discipline established elsewhere in this repository series to EKS add-on versioning specifically.

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/) and [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).
