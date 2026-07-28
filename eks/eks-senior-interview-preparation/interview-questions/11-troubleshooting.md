# Category 11: Troubleshooting and Production Incidents

Questions 99–104 of 120. Category weight: 6 questions. Deep-dive reference: [`docs/troubleshooting.md`](../docs/troubleshooting.md).

---

## Question 99: The pod that was healthy right up until it wasn't

### Scenario
A pod passes its readiness probe and serves traffic normally for hours, then abruptly starts returning 500 errors for every request, while `kubectl get pods` continues to show it as `Running` and `Ready`.

### Interview Question
Walk through your diagnostic process for a pod that's infrastructure-healthy but application-broken.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/troubleshooting.md`](../docs/troubleshooting.md) §7, a passing readiness probe only confirms whatever the probe itself checks — if the probe checks something shallow (a TCP port, or a health endpoint that doesn't reflect genuine downstream dependency health), a pod can be infrastructure-"ready" while being functionally broken at the application layer, exactly the gap this scenario describes.

**Technical reasoning:** the abrupt transition (hours of normal operation, then a sudden, complete failure) suggests either a downstream dependency failure the application doesn't handle gracefully (a database connection pool exhausted, a downstream service becoming unavailable) or an internal application state issue (a memory leak reaching a critical threshold, a cache becoming corrupted) — neither of which a shallow readiness probe would detect.

**Investigation process:** check the application's own logs immediately preceding and during the failure onset for any error pattern (database connection errors, downstream timeout messages, out-of-memory warnings short of an actual OOMKill), and correlate against any recent, unrelated event (a downstream dependency's own incident, a traffic pattern change) that might explain the sudden onset.

**Recommended solution:** based on what the logs reveal — if a downstream dependency failure, address that dependency directly and consider adding circuit-breaker/timeout logic to the application so a future similar failure degrades gracefully rather than serving 500s indefinitely; if an internal application-state issue, this may require a pod restart as an immediate mitigation while the underlying application bug is fixed.

**Risk controls:** if restarting the pod is used as an immediate mitigation, also improve the readiness/liveness probe to actually detect this specific failure mode going forward (deepening the check to reflect genuine functional health, not just process/port liveness, per [`docs/troubleshooting.md`](../docs/troubleshooting.md) §7) — so a recurrence is caught automatically rather than requiring another manual investigation.

**Validation steps:** after remediation, confirm the specific failure pattern doesn't recur under similar conditions (replaying the same downstream-dependency-failure scenario in a test environment, if feasible), and confirm the improved probe correctly detects and removes an unhealthy pod from rotation if this happens again.

**Rollback or recovery strategy:** an immediate pod restart is the fastest mitigation for restoring service, with the deeper application-level fix (circuit breakers, improved probes) following as the durable remediation.

**Long-term prevention:** treat "does our readiness/liveness probe genuinely reflect functional health" as a standing review question for every workload, especially after any incident where infrastructure-level health checks passed despite genuine application-level failure.

### Step-by-Step Implementation
```yaml
# Before - shallow probe, doesn't reflect genuine functional health
readinessProbe:
  tcpSocket: { port: 8080 }

# After - deeper probe reflecting actual dependency health
readinessProbe:
  httpGet: { path: /healthz/deep, port: 8080 }   # checks DB connectivity, downstream dependencies
  periodSeconds: 10
  failureThreshold: 3
```

### Under-the-Hood Explanation
Kubernetes' readiness probe mechanism only knows what the configured check tells it — a `tcpSocket` check merely confirms a port is accepting connections, entirely blind to whether the application behind that port can actually process requests correctly; only a probe specifically designed to exercise genuine application logic (a `/healthz/deep` endpoint the application itself implements, checking its real dependencies) can catch this class of "alive but broken" failure.

### Common Weak Answer
"Since kubectl shows it as Ready, the pod itself must be fine, the problem must be elsewhere."

### Why the Weak Answer Fails
This trusts a shallow readiness signal as proof of genuine health, missing that "Ready" only reflects whatever the configured probe actually checks — exactly the gap causing this incident, where a passing (shallow) probe coexisted with a genuinely broken application.

### Follow-Up Questions
1. How would you design a readiness probe that's deep enough to catch real issues without being so heavy it becomes its own performance/reliability concern?
2. What's the risk of a readiness probe that's too aggressive (removing pods from rotation for transient, self-recovering issues)?
9. How would you add circuit-breaker logic to gracefully degrade rather than serve 500s when a downstream dependency fails?

### Key Interview Signals
Correctly identifies that a passing readiness probe only confirms what it specifically checks, and both investigates the actual application-level cause and improves the probe to catch this failure mode automatically going forward.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 100: The incident that was actually three incidents

### Scenario
During a single stressful hour, three separate teams report seemingly-related issues: elevated latency (team A), a Service showing zero endpoints (team B), and pods failing to schedule (team C). Initial assumption is one root cause affecting the whole cluster.

### Interview Question
How would you approach investigating whether this is genuinely one incident or several coincidentally-overlapping ones?

### Strong Senior-Level Answer
**Initial assessment:** assuming a single root cause without verifying it can send investigation in the wrong direction entirely — per the diagnostic principle threaded throughout [`docs/troubleshooting.md`](../docs/troubleshooting.md), each reported symptom has its own specific, checkable diagnostic path (elevated latency per Question 84's correlation sequence, zero endpoints per [`docs/troubleshooting.md`](../docs/troubleshooting.md) §9, scheduling failures per §1), and the first step is determining whether these three symptoms genuinely share a common cause or are coincidentally concurrent, unrelated issues.

**Technical reasoning:** a genuine common cause (e.g., a control-plane-level issue, per Question 4 in Category 1, or a cluster-wide capacity exhaustion event) would typically show a consistent timing correlation and a plausible causal mechanism connecting all three symptoms; three unrelated issues happening to surface in the same hour (team A's own application bug, team B's own label-selector mistake per Question 9's zero-endpoints scenario, team C's own NodePool/taint misconfiguration per Category 6) is also entirely plausible, especially in a shared, busy platform with many independent teams.

**Investigation process:** investigate each symptom's specific root cause independently and in parallel (assigning each to whoever has the relevant context, rather than one person trying to solve all three as a single mystery), explicitly looking for a shared underlying event (a recent cluster-wide change, an add-on upgrade, a control-plane issue) that would connect them — but not assuming one exists before checking.

**Recommended solution:** based on parallel investigation, either confirm a genuine shared root cause (if the timing/mechanism connects clearly) and remediate it once for all three symptoms, or confirm three independent causes and remediate each separately via its own specific fix — the actual investigation process is nearly identical either way (each symptom needs its own specific diagnostic path regardless), but the conclusion materially changes the remediation and communication approach.

**Risk controls:** avoid the trap of forcing a single, oversimplified narrative onto genuinely independent issues just because they're temporally concurrent — this can lead to chasing a plausible-sounding but incorrect "one common cause" theory while the actual, independent causes go unaddressed.

**Validation steps:** confirm each symptom is actually resolved by its own specific remediation — if all three are genuinely independent, fixing only the "common cause" theory's target would leave two of the three symptoms unresolved, itself a signal the single-root-cause theory was incorrect.

**Rollback or recovery strategy:** depends entirely on each confirmed root cause — this scenario is about the investigation approach, not a specific fix.

**Long-term prevention:** train incident responders to explicitly consider and test the "are these genuinely related" question early in any multi-symptom incident, rather than defaulting to a single-root-cause assumption, especially in a large, shared, multi-tenant platform where independent, coincidental failures across different teams are a realistic, common occurrence, not a rare edge case.

### Step-by-Step Implementation
```text
1. Assign each symptom to a separate investigator (or investigate sequentially, but treat
   each as a fully separate root-cause question) rather than assuming one shared cause.
2. Team A (latency): follow the metrics-logs-traces correlation sequence (Question 84).
3. Team B (zero endpoints): check label-selector/pod-label mismatch (Question 9 pattern).
4. Team C (scheduling failures): check NodePool/taint/capacity constraints (Category 6 patterns).
5. Compare timing and any shared recent change across all three findings -
   only THEN conclude whether there's a genuine common cause.
```

### Under-the-Hood Explanation
A large, shared, multi-tenant cluster hosts many independent teams' workloads, each with their own deployment cadence, configuration changes, and potential mistakes — the base rate of multiple, genuinely unrelated issues coincidentally surfacing in the same time window is not actually low in a sufficiently large and active shared platform, which is precisely why an investigation shouldn't default to assuming a single shared cause without explicit verification.

### Common Weak Answer
"Since all three happened around the same time, there must be one common cause — find it."

### Why the Weak Answer Fails
This assumes correlation implies a shared cause without verification, risking significant wasted investigation time chasing a single unifying theory that may not exist, while potentially delaying the correct, independent fixes each genuinely separate issue actually needs.

### Follow-Up Questions
1. How would you structure incident communication if it turns out to be three independent issues rather than one, given initial reports suggested otherwise?
2. What signals would most quickly confirm or rule out a genuine shared root cause (a recent cluster-wide change, an add-on upgrade)?
3. How would you staff/coordinate a multi-team incident response when the symptoms initially appear related but may not be?

### Key Interview Signals
Resists the natural pull toward a single, unifying explanation without verification, and designs a parallel, symptom-specific investigation approach that correctly handles either a genuine shared cause or several independent ones.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 101: The fix that fixed it, until it didn't

### Scenario
A pod experiencing `CrashLoopBackOff` is fixed by increasing its memory limit. It runs stably for two weeks, then starts crash-looping again with the identical `OOMKilled` reason, despite no code or configuration change in the interim.

### Interview Question
Diagnose why a fix that worked for two weeks stopped working, with no apparent change.

### Strong Senior-Level Answer
**Initial assessment:** per Question 4 in Category 1's OOMKilled diagnostic framing (raised again here at Question 60's memory-leak-vs-legitimate-peak distinction), a fix that works temporarily before recurring at the same failure mode is a strong signal of a genuine, slow memory leak rather than a one-time undersized limit — the increased limit simply gave the leak more room to grow into before hitting the ceiling again, rather than addressing why memory usage grows unboundedly over time in the first place.

**Technical reasoning:** if the original issue were genuinely just "the limit was too low for legitimate peak usage," raising it would have resolved the issue durably, since legitimate usage should plateau at some steady, bounded level — recurrence after a consistent two-week interval (suggesting a roughly linear, ongoing growth rate reaching the new, higher ceiling on a predictable schedule) is a specific, recognizable signature of an actual memory leak, not a one-time miscalibration.

**Investigation process:** review the application's memory usage trend over the full two-week period (via the observability pipeline from Category 9) — a genuine leak shows a steady, roughly linear or gradually-accelerating climb with no plateau, distinct from legitimate usage that would level off at some bounded steady-state value.

**Recommended solution:** treat this as an application-level memory-leak investigation (heap profiling, dependency version review for a known leak in a specific library, connection/resource cleanup review) rather than repeatedly raising the memory limit as a recurring stopgap — raising the limit again would only delay, not prevent, the next recurrence at a predictably later date.

**Risk controls:** while the actual leak is being diagnosed and fixed (which may take real engineering time), consider a scheduled, proactive pod restart (a "leak mitigation" cron-triggered rolling restart) as an explicit, temporary, and clearly-labeled stopgap — never a permanent substitute for actually fixing the leak, but a reasonable bridge while root-cause work is underway.

**Validation steps:** after identifying and fixing the actual leak (e.g., a specific unclosed resource or a known-buggy library version), confirm memory usage now genuinely plateaus at a steady-state level over an extended observation period, rather than continuing to climb.

**Rollback or recovery strategy:** if a specific code fix for the suspected leak doesn't resolve the growth pattern, that's a signal the actual leak source was misidentified — continue investigating rather than assuming the fix worked without confirming the usage trend genuinely plateaus.

**Long-term prevention:** treat "does memory usage plateau, or does it show unbounded growth" as the standard diagnostic question for any OOMKilled incident recurring after a limit increase, and add memory-trend monitoring/alerting (a slow, sustained climb pattern, not just an absolute threshold) as a proactive signal catching a leak before it causes an actual OOMKill.

### Step-by-Step Implementation
```promql
# Distinguish a genuine leak (unbounded climb) from legitimate peak usage (plateau)
# by reviewing the full trend, not just the current value at time of OOMKill
container_memory_working_set_bytes{pod=~"my-app-.*"}
```

### Under-the-Hood Explanation
A memory limit is a fixed ceiling — if the underlying application genuinely leaks memory at some roughly constant rate, raising the ceiling only changes *when* the leak's accumulated usage reaches it, not *whether* it will; the growth continues at the same underlying rate regardless of the limit's value, meaning the "fix" (raising the limit) only ever provides a predictable delay before the identical failure mode recurs, exactly as observed here.

### Common Weak Answer
"Just raise the memory limit again, that worked last time."

### Why the Weak Answer Fails
This repeats exactly the stopgap that already proved to only delay (not resolve) the underlying issue — the pattern of recurrence at a consistent interval is itself diagnostic evidence pointing toward a genuine leak, which repeatedly raising the limit does nothing to actually address, guaranteeing a third recurrence down the line.

### Follow-Up Questions
1. How would you use heap profiling or similar tooling to pinpoint the exact source of a suspected memory leak in a running application?
2. What's an appropriate interim mitigation (scheduled restarts) while the actual leak is being diagnosed, and how would you make sure it's not mistaken for a permanent fix?
3. How would you design alerting specifically for a "memory usage climbing without plateauing" pattern, distinct from a simple threshold-based OOMKilled alert?

### Key Interview Signals
Recognizes the specific diagnostic signature of a recurring, interval-consistent OOMKilled failure as indicating a genuine leak rather than a one-time undersized limit, and pursues the actual root-cause fix rather than repeating an already-proven-temporary stopgap.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 102: The incident where the runbook was wrong

### Scenario
During an active incident, an on-call engineer follows the documented runbook for "Service X unreachable" step by step. The runbook's prescribed fix (restart the Service's Deployment) doesn't resolve the issue, and the engineer isn't sure whether to keep trying the runbook's remaining steps or deviate from it.

### Interview Question
How would you think about this decision point during a live incident?

### Strong Senior-Level Answer
**Initial assessment:** a runbook is a starting hypothesis based on previously-seen failure patterns, not a guaranteed, exhaustive diagnostic procedure — if its prescribed fix doesn't resolve the issue, that's itself valuable diagnostic information (this incident's actual cause likely differs from what the runbook was written for), and the correct response is to treat this as a signal to broaden the investigation, not necessarily to blindly continue through the runbook's remaining steps hoping one eventually works.

**Technical reasoning:** a runbook's steps are typically ordered by the likelihood/frequency of the failure modes it was written to address — a step failing to resolve the issue after a genuinely correct execution is meaningful evidence *against* the runbook's assumed root cause, and continuing further down a runbook built around an incorrect premise risks wasting time on remaining steps unlikely to help either, if they all stem from the same underlying (and apparently wrong) assumption about the failure mode.

**Investigation process:** step back and apply the general diagnostic framework (per [`docs/troubleshooting.md`](../docs/troubleshooting.md) and the Interview Response Framework's "gather evidence, inspect actual state, root cause" steps) fresh, informed by the new evidence that the runbook's assumed cause wasn't correct — checking events, logs, and actual current state rather than continuing to follow a script that's already shown itself to not match this specific incident.

**Recommended solution:** don't mechanically exhaust the remaining runbook steps out of process-adherence alone — use the runbook-failure as a pivot point to broaden investigation using first-principles diagnostic technique, while keeping the runbook's remaining steps in mind as one input, not the sole guide, going forward.

**Risk controls:** document, in real time or immediately after, exactly which runbook step failed and why the actual cause diverged from the runbook's assumption — this is valuable information for correcting the runbook afterward, regardless of how the current incident resolves.

**Validation steps:** whatever the actual root cause turns out to be, once resolved, confirm the specific incident's timeline and cause are captured accurately for the post-incident runbook update.

**Rollback or recovery strategy:** not applicable to this meta-question about incident-response decision-making.

**Long-term prevention:** treat every incident where a runbook's prescribed fix fails as a mandatory input for updating that runbook — either adding the newly-discovered failure mode and its correct diagnostic path as an additional branch, or correcting an assumption the runbook had wrong; a runbook that's never updated based on real incident feedback gradually becomes less useful over time, exactly the risk this specific incident is surfacing.

### Step-by-Step Implementation
```text
1. Runbook's prescribed fix (restart Deployment) doesn't resolve the issue.
2. Treat this as evidence the runbook's assumed root cause is likely wrong for THIS incident.
3. Pivot to first-principles diagnosis: kubectl describe/logs/events on the actual
   current state, following the standard 10-step Interview Response Framework fresh.
4. Post-incident: update the runbook with this newly-discovered failure mode/branch.
```

### Under-the-Hood Explanation
A runbook encodes institutional knowledge from *previously observed* incidents — it's inherently a pattern-matching shortcut, not an exhaustive decision tree covering every possible failure mode a service could ever exhibit; when live evidence (the prescribed fix failing) contradicts the runbook's implicit assumption, that contradiction is itself diagnostic signal that should redirect investigation, rather than being overridden by continued mechanical adherence to a document that's already shown a mismatch with the current reality.

### Common Weak Answer
"Keep following the runbook exactly as written until every step has been tried."

### Why the Weak Answer Fails
This treats the runbook as an infallible, exhaustive procedure rather than a best-guess pattern-matching tool — a runbook step failing is itself meaningful evidence the underlying assumption may not apply to this specific incident, and mechanically continuing through remaining steps built on the same likely-wrong assumption risks wasting critical incident-response time.

### Follow-Up Questions
1. How would you balance following established process (for consistency/auditability) against pivoting quickly when evidence suggests the process doesn't fit the current situation?
2. How would you structure a runbook to make this kind of "if this step doesn't work, here's how to pivot" guidance more explicit, rather than a purely linear script?
3. How would you ensure runbooks are actually updated based on real incident learnings, rather than becoming stale over time?

### Key Interview Signals
Treats a runbook as a starting hypothesis informed by prior patterns rather than an infallible script, and correctly uses a failed prescribed fix as diagnostic evidence redirecting the investigation, while also planning to feed the learning back into the runbook itself.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 103: The postmortem that blamed the wrong layer

### Scenario
A postmortem for a production incident concludes "root cause: Kubernetes scheduler bug," based on a pod remaining unschedulable for an extended period. A more thorough follow-up review finds the actual cause was a NodePool with an overly narrow instance-family constraint (per Category 6's patterns), correctly behaving exactly as configured.

### Interview Question
What does this postmortem's initial (incorrect) conclusion reveal about the investigation process, and how would you prevent it recurring?

### Strong Senior-Level Answer
**Initial assessment:** concluding "the platform/tool has a bug" without first exhaustively ruling out configuration/design causes is a common but avoidable postmortem mistake — per the pattern established throughout Category 6 (NodePool/taint/topology-constraint gaps), the vast majority of "the scheduler won't place this pod" incidents trace back to a specific, checkable configuration constraint the scheduler is correctly respecting, not a genuine defect in the scheduler's own logic.

**Technical reasoning:** the Kubernetes scheduler is one of the most heavily-used, well-tested components in the entire ecosystem — a genuine scheduler bug causing an unschedulable pod is possible but statistically far less likely than a configuration mismatch (NodePool constraints, taints, topology spread, resource requests exceeding available capacity), meaning the investigation should exhaust the configuration-level explanations thoroughly before concluding the scheduler itself is at fault.

**Investigation process:** for any "pod won't schedule" postmortem, systematically check (in order of likelihood): resource requests vs. available capacity, node selector/affinity constraints vs. actual node labels, taints vs. tolerations, topology spread constraints vs. actual AZ/capacity distribution — only after all of these are confirmed *not* to explain the behavior does "possible scheduler defect" become a reasonable working theory, and even then, cross-referencing against the Kubernetes project's own issue tracker for a matching known bug is a more rigorous next step than simply asserting it.

**Recommended solution:** correct the postmortem's root cause to reflect the actual, confirmed cause (the NodePool constraint), and use this as a teaching moment for the team's postmortem-writing process — specifically flagging "blame the underlying platform/tool" as a conclusion requiring a higher bar of evidence than "blame our own configuration," given the relative likelihood of each.

**Risk controls:** a postmortem that incorrectly attributes root cause to "a scheduler bug" risks the team not fixing the actual, still-present configuration issue (the narrow NodePool constraint), leaving the real problem unaddressed and likely to recur under similar conditions.

**Validation steps:** confirm the corrected postmortem's identified root cause (the NodePool constraint) is now actually remediated (per the fix pattern from Question 36), and confirm the specific failure mode doesn't recur.

**Rollback or recovery strategy:** not applicable — this is a postmortem-accuracy correction, not an infrastructure change requiring rollback.

**Long-term prevention:** establish a postmortem-review standard requiring any conclusion attributing root cause to a platform/tool defect (rather than configuration/design) to be supported by exhaustive elimination of the more common, more likely configuration-level explanations first — treating "it's a bug in the underlying platform" as a conclusion of last resort, not a first guess when the actual cause isn't immediately obvious.

### Step-by-Step Implementation
```text
Before concluding "scheduler bug," systematically rule out (in order):
1. Resource requests vs. available cluster capacity
2. Node selector / affinity vs. actual node labels
3. Taints vs. tolerations (Question 55's pattern)
4. Topology spread constraints vs. actual AZ/capacity distribution (Question 56's pattern)
5. NodePool/EC2NodeClass instance-family constraints (Question 36's pattern)
Only after all of these are confirmed NOT to explain the behavior,
consider a genuine scheduler defect as the working theory.
```

### Under-the-Hood Explanation
The scheduler's placement decision is a deterministic function of a pod's declared constraints (resources, affinity, tolerations, topology spread) against the actual current state of every node (labels, taints, available capacity) — in the overwhelming majority of "won't schedule" cases, the scheduler is correctly and faithfully applying this logic against a configuration that, once fully traced through, explains the outcome completely; concluding a "bug" without having traced through this full logic chain skips the step most likely to actually explain the behavior.

### Common Weak Answer
"If we can't immediately see why it's not scheduling, it's probably a Kubernetes bug."

### Why the Weak Answer Fails
This treats "I don't immediately understand it" as equivalent to "it's a platform defect," skipping the systematic elimination of far-more-likely configuration causes that a proper investigation would have found, exactly as the follow-up review in this scenario demonstrated.

### Follow-Up Questions
1. How would you build a standard, systematic checklist (like the one above) into the team's incident-response and postmortem process to prevent this kind of premature conclusion?
2. How would you differentiate a genuine platform bug from a configuration issue when the two might look superficially similar?
3. What's the cost, in terms of unaddressed real risk, of an incorrect postmortem conclusion like this one, if left uncorrected?

### Key Interview Signals
Recognizes that "the platform has a bug" is a low-probability, last-resort conclusion requiring exhaustive elimination of far more common configuration-level explanations first, and treats postmortem accuracy itself as something requiring the same rigor as the original incident investigation.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/) and [Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 104: The incident that revealed the team didn't know their own dependencies

### Scenario
During an outage of a shared internal "platform" service (an internal authentication proxy every application depends on), the incident-response team can't quickly answer "which of our 60 application workloads are actually affected" — there's no existing dependency map, and the answer has to be reconstructed live, under pressure, during the incident itself.

### Interview Question
Diagnose this gap and design a solution.

### Strong Senior-Level Answer
**Initial assessment:** the absence of a pre-existing, queryable dependency map means the team is doing first-principles discovery (which of 60 workloads actually depend on this specific shared service) *during* the incident, under time pressure, exactly when that time would be far better spent on remediation — this is a preventable, structural gap in incident-response readiness, not something that should need reconstructing live every time a shared dependency has an issue.

**Technical reasoning:** dependency information (which workloads call which shared services) is, in principle, derivable from several existing sources — NetworkPolicy definitions (if used with specific, workload-scoped rules rather than broad allow-alls), service mesh/tracing data (if distributed tracing per Category 9 is in place, actual call graphs are directly observable), or simply application-level configuration/documentation — but if none of these are aggregated into a single, incident-ready reference, the team is stuck reconstructing this picture from scratch under pressure.

**Investigation process:** for this specific incident, the fastest available path is likely querying actual observed traffic (via tracing data, if available, per [`docs/observability.md`](../docs/observability.md) §6) showing which services have actually called the affected authentication proxy recently — a live, empirical answer, if the tooling exists to query it quickly.

**Recommended solution:** for the immediate incident, use whatever empirical signal is fastest to query (tracing data showing actual recent callers, or NetworkPolicy definitions if they're workload-specific) to determine actual impact; going forward, build and maintain an actual, queryable service-dependency map (derived from tracing data automatically, ideally, rather than manually maintained documentation that risks becoming stale) so this exact question ("what depends on X") has a fast, reliable answer before the next incident involving a shared dependency.

**Risk controls:** whatever dependency-mapping mechanism is built, validate it periodically against actual observed traffic to confirm it stays accurate — a documentation-based dependency map that isn't automatically derived from real traffic risks becoming stale exactly like any other manually-maintained artifact this repository series has flagged as a recurring risk pattern.

**Validation steps:** after building the dependency map, run a tabletop exercise simulating a similar shared-dependency outage and confirm the team can now answer "who's affected" quickly, using the new tooling, rather than reconstructing it live.

**Rollback or recovery strategy:** not applicable — this is a readiness-capability gap, not an infrastructure change with its own rollback consideration.

**Long-term prevention:** treat "can we quickly answer which workloads depend on any given shared service" as a standing incident-readiness capability, built once (ideally auto-derived from tracing/observability data to avoid staleness) and periodically validated, rather than something reconstructed painfully during every incident involving a shared dependency — directly analogous to the break-glass-path testing discipline from the companion Ansible/IRSA questions: an incident-response capability that's never been built or tested is effectively unavailable exactly when it's needed most.

### Step-by-Step Implementation
```text
Immediate (during incident): query distributed tracing data for recent callers
of the authentication proxy service - fastest empirical answer available.

Long-term: build an automated service-dependency map derived from tracing
data (e.g., via a tool that aggregates observed service-to-service call
graphs from OpenTelemetry data into a queryable, regularly-refreshed map),
validated periodically against real traffic, and made available as a
standing incident-response reference - not reconstructed from scratch
during the next incident.
```

### Under-the-Hood Explanation
Distributed tracing data (per [`docs/observability.md`](../docs/observability.md) §1 and §6), when aggregated across many requests over time, inherently encodes the real, empirical call graph between services — which services actually call which others, and how often — making it a naturally-accurate, continuously-updated source for exactly this kind of dependency-mapping question, in contrast to manually-maintained documentation that reflects only what someone remembered to write down and update.

### Common Weak Answer
"We'll just ask each of the 60 teams during the incident whether they depend on this service."

### Why the Weak Answer Fails
This is slow (requiring real-time coordination across 60 teams during an active incident), unreliable (depends on each team's own accurate, complete self-knowledge of their own dependencies), and exactly the kind of reactive, under-pressure reconstruction this scenario is highlighting as a preventable gap — the durable fix builds this capability once, in advance, from empirical data.

### Follow-Up Questions
1. How would you validate that an auto-derived dependency map from tracing data is genuinely complete, not missing any real dependencies that happen to be low-traffic or intermittent?
2. How would you structure a tabletop exercise to test this capability before a real incident reveals the gap?
3. What other "we had to reconstruct this live during the incident" gaps might exist elsewhere in this platform's incident-readiness posture?

### Key Interview Signals
Recognizes the absence of a pre-built, queryable dependency map as a genuine, preventable incident-readiness gap, and designs a durable, empirically-derived (not manually-maintained) solution rather than accepting live reconstruction as an acceptable ongoing practice.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).
