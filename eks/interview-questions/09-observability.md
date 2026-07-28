# Category 9: Observability (Logging, Metrics, Tracing)

Questions 79–86 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/observability.md`](../docs/observability.md).

---

## Question 79: The autoscaling that had no history

### Scenario
A postmortem for an incident three weeks ago needs to answer "what did memory usage across the fleet look like in the hour before the cascading OOM kills started?" The team discovers they have no way to answer this — `metrics-server` (their only metrics component) retains no history at all.

### Interview Question
Explain the gap and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/observability.md`](../docs/observability.md) §3, `metrics-server` exists specifically to feed HPA and `kubectl top` with current resource usage — it retains zero historical data by design, and mistaking its presence for "we have observability" is exactly the gap this scenario exposes during a postmortem that genuinely needs historical data.

**Technical reasoning:** `metrics-server` polls kubelets for current resource usage and serves it via the `metrics.k8s.io` API for immediate consumption (HPA's scaling decisions, `kubectl top`'s live display) — it has no storage/time-series component at all, meaning the moment a data point is superseded by the next poll, the previous value is simply gone, with no way to query "what was memory usage an hour ago" after the fact.

**Investigation process:** confirm definitively that `metrics-server` is indeed the only metrics component currently deployed — this settles that the postmortem's data gap is structural and expected, not a configuration issue with an otherwise-capable tool.

**Recommended solution:** deploy a real metrics pipeline with actual retention — `kube-prometheus-stack` (self-managed Prometheus/Grafana) or CloudWatch Container Insights (per [`docs/observability.md`](../docs/observability.md) §2), either of which retains historical time-series data queryable well after the fact, unlike `metrics-server`.

**Risk controls:** choose retention duration deliberately based on how far back postmortems/trend-analysis genuinely need to reach (a common choice: detailed retention for a few weeks, downsampled/aggregated retention for longer), balancing storage cost against investigative usefulness.

**Validation steps:** after deployment, confirm historical queries (e.g., "show memory usage across the fleet for a specific past hour") actually work and return meaningful data, and confirm this data would have been sufficient to answer the original postmortem question had it been available at the time.

**Rollback or recovery strategy:** not applicable — this is additive observability capability, not a change requiring rollback consideration.

**Long-term prevention:** treat "do we have actual historical metrics retention, or just `metrics-server`'s live-only view" as a standing, explicitly-checked platform-readiness question for every cluster, never assuming autoscaling-feed metrics constitute genuine observability.

### Step-by-Step Implementation
```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=30d
```

### Under-the-Hood Explanation
`metrics-server` implements the Kubernetes Metrics API purely as a thin, current-value-only aggregation layer over kubelet's own Summary API — it was explicitly designed to be lightweight and low-overhead specifically *because* it doesn't need to solve the storage/query problem a real time-series database does; that's an intentional scope limitation, not an oversight, and a real observability pipeline is an entirely separate, additional component.

### Common Weak Answer
"We have metrics-server running, so we have monitoring covered."

### Why the Weak Answer Fails
This conflates a narrow, autoscaling-feed component with genuine observability — `metrics-server`'s complete lack of history means it provides zero value for any retrospective analysis, exactly the gap this postmortem ran into.

### Follow-Up Questions
1. How would you choose retention duration/granularity trade-offs for a Prometheus deployment at this cluster's scale?
2. What's the cost comparison between Container Insights and a self-managed Prometheus stack for this specific retention need?
3. How would you retroactively reconstruct at least partial historical context for a past incident when no real metrics history exists?

### Key Interview Signals
Precisely distinguishes `metrics-server`'s narrow, history-free purpose from genuine observability, and designs an actual retained-metrics pipeline as the fix.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 80: The alert that fired four hundred times before anyone looked

### Scenario
An alerting rule fires on every individual pod restart across the fleet. During a routine, expected rolling deployment, on-call receives over 400 alert notifications in twenty minutes — and, exhausted, mutes the entire alert channel, missing a genuinely unrelated, serious alert that fired during the same window.

### Interview Question
Diagnose the alerting-design failure and redesign it.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/observability.md`](../docs/observability.md) §5, alerting on every individual pod restart conflates expected, self-healing Kubernetes behavior (a routine rolling deployment restarting pods is normal, not an incident) with genuinely actionable signal — this is precisely the alert-noise pattern that leads to exactly what happened here: alert fatigue causing a genuinely important, unrelated alert to be missed.

**Technical reasoning:** Kubernetes' own self-healing (rolling updates, normal rescheduling) is expected to restart pods routinely — an alert with no distinction between "this restart is part of an expected, healthy process" and "this restart indicates a genuine problem" will always fire far more often than is actionable, training on-call to ignore or mute the channel exactly as happened.

**Investigation process:** review the alert's actual definition — confirm it triggers on raw pod-restart-count with no correlation to deployment/rollout events, and no threshold distinguishing "occasional restarts" from "a genuinely elevated restart rate outside of an active rollout."

**Recommended solution:** redesign the alert to fire on symptom-level, business-impact signals instead — elevated error rate or latency at the Service/ingress level, or a restart-rate threshold specifically excluding time windows correlated with an active, intentional rollout (checkable via the GitOps controller's own sync-status events) — reserving pod-restart-count alerting, if kept at all, for a much higher, clearly-abnormal threshold outside of active rollout windows specifically.

**Risk controls:** validate the redesigned alert against historical data (would it have correctly stayed silent during this routine rollout, while still firing for a genuinely elevated, non-rollout-correlated restart pattern) before relying on it going forward.

**Validation steps:** after redesign, monitor the alert's firing pattern during the next several routine deployments, confirming it stays appropriately quiet, and confirm it still fires correctly for a deliberately-injected genuine failure scenario.

**Rollback or recovery strategy:** if the redesigned alert misses a genuine issue it should have caught, adjust its threshold/correlation logic based on the specific gap revealed, rather than reverting to the original noisy, per-restart design.

**Long-term prevention:** apply the "alert on symptoms, not every individual event" principle established in [`docs/observability.md`](../docs/observability.md) §5 as a standing review criterion for every alert in the system, explicitly auditing existing alerts for this same noise-generating pattern, not just the one that caused this incident.

### Step-by-Step Implementation
```yaml
# Before: fires on every restart, indiscriminate of context
- alert: PodRestarted
  expr: increase(kube_pod_container_status_restarts_total[5m]) > 0

# After: symptom-level, business-impact signal
- alert: ElevatedErrorRate
  expr: |
    sum(rate(http_requests_total{status=~"5.."}[5m]))
    / sum(rate(http_requests_total[5m])) > 0.05
  for: 5m
```

### Under-the-Hood Explanation
Prometheus (or any metrics-based alerting system) fires purely mechanically based on whatever expression and threshold is configured — it has no inherent understanding of "this restart is part of an expected rollout" unless the alert's own logic is explicitly designed to account for that context (e.g., correlating against deployment/rollout metadata, or choosing a fundamentally different, symptom-level signal that doesn't fire during expected, healthy restart activity in the first place).

### Common Weak Answer
"Just increase the alert's threshold slightly so it fires less often."

### Why the Weak Answer Fails
A slightly higher threshold on the same fundamentally noisy signal (raw restart count with no context) still fires excessively during any sufficiently large rolling deployment — the actual fix changes *what* is being alerted on (symptom-level business impact) rather than just tuning a threshold on an inherently poorly-chosen underlying signal.

### Follow-Up Questions
1. How would you audit the entire existing alert set for this same per-event, non-symptom-level pattern?
2. What's the risk of over-correcting toward too few, too-high-threshold alerts, potentially missing genuine early warning signs?
3. How would you design an alert specifically for "restart rate elevated even accounting for an active rollout" as a middle ground?

### Key Interview Signals
Diagnoses alert fatigue as a direct, foreseeable consequence of alerting on expected, self-healing events rather than genuine symptoms, and redesigns around business-impact signals rather than just adjusting a threshold on the same flawed underlying signal.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 81: The trace that stopped at the cluster boundary

### Scenario
A distributed trace for a slow user request shows the request entering the cluster, passing through three internal microservices quickly, then a long, unexplained gap before the response returns — with no trace spans covering that gap at all.

### Interview Question
Diagnose where the trace's visibility likely ends and why.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/observability.md`](../docs/observability.md) §1 and §6, a trace's visibility is only as complete as the instrumentation propagating context across every hop — an unexplained gap almost always indicates the request left a boundary where OpenTelemetry instrumentation/context-propagation isn't present (a call to an external, non-instrumented dependency — a third-party API, an un-instrumented legacy system, or a managed AWS service call not wrapped with tracing instrumentation).

**Technical reasoning:** distributed tracing works by propagating a trace context (trace ID, span ID) across service boundaries via request headers, with each instrumented service creating its own span referencing that context — if a request passes through *any* component that doesn't participate in this propagation (doesn't read the incoming trace context and doesn't create/forward a span), the trace simply has a gap for that portion of the request's actual journey, with no indication of what happened during it beyond "time passed."

**Investigation process:** identify exactly which of the three internal microservices' spans immediately precedes the gap, and investigate what that specific service actually calls next in its own code/logs during that request — this is the most direct way to identify the actual un-instrumented dependency causing the gap.

**Recommended solution:** if the gap corresponds to a call the team controls (e.g., a call to an internal but currently-un-instrumented legacy component), add OpenTelemetry instrumentation to it, closing the visibility gap for future traces. If it corresponds to a genuinely external, third-party dependency outside the team's control, the gap can't be closed at the tracing level — instead, correlate via that specific service's own logs (timestamps around the call) to at least approximate what happened during the gap, and consider this specific dependency's latency as a standing, separately-monitored signal.

**Risk controls:** for any critical-path dependency that can't be traced end-to-end (a genuinely external service), ensure its latency/error rate is monitored independently (even without full trace integration), so a systemic slowdown in that dependency is still detectable, just via a different signal than tracing.

**Validation steps:** after adding instrumentation (if the gap was closeable), confirm subsequent traces for the same request path now show a continuous span sequence with no unexplained gap.

**Rollback or recovery strategy:** not applicable — this is an observability-coverage improvement, not a change with its own rollback consideration.

**Long-term prevention:** treat "does every internal service call propagate trace context and create spans" as a standard requirement for any new internal service, and maintain an explicit inventory of genuinely un-instrumentable external dependencies with compensating, separate monitoring for each.

### Step-by-Step Implementation
```python
# Ensure every outbound call propagates trace context (conceptual example)
from opentelemetry import trace
from opentelemetry.propagate import inject

headers = {}
inject(headers)   # propagates trace context into the outbound request
response = requests.get(downstream_url, headers=headers)
```

### Under-the-Hood Explanation
OpenTelemetry's context propagation relies on every hop in a request's path actively reading an incoming trace context (from headers like `traceparent`) and creating a child span referencing it before making its own outbound calls — any component that doesn't do this (an un-instrumented library, a third-party service with no visibility into your tracing setup) simply doesn't emit a span, leaving a gap in the collected trace exactly proportional to how long that un-instrumented portion of the request actually took.

### Common Weak Answer
"The tracing system must be dropping spans somewhere, check the collector's configuration."

### Why the Weak Answer Fails
This assumes a tracing-infrastructure malfunction before considering the much more common and likely explanation — a genuine gap in instrumentation coverage at a specific service boundary — which is both easier to diagnose (checking that specific service's own code/logs) and a more actionable, permanent fix than troubleshooting an otherwise-functioning collector.

### Follow-Up Questions
1. How would you build an inventory of instrumentation coverage across all internal services to proactively find gaps before they show up in an incident trace?
2. What's the correlation strategy for approximating what happened during a gap corresponding to a genuinely un-instrumentable external dependency?
3. How would you balance the engineering cost of instrumenting every internal call against the diagnostic value it provides?

### Key Interview Signals
Correctly attributes a trace gap to a missing-instrumentation boundary rather than assuming a tracing-infrastructure malfunction, and designs both a closing fix (where possible) and a compensating monitoring strategy (where not).

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 82: The log line that cost more than the server

### Scenario
A cost review finds that CloudWatch Logs ingestion charges for one particular application exceed its entire EC2/Fargate compute cost for the month. Investigation reveals the application logs a full request/response body, including headers, at INFO level for every single request.

### Interview Question
Diagnose this cost driver and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/observability.md`](../docs/observability.md) §4, verbose, high-volume logging (especially full request/response bodies at a routinely-active log level) is a genuine, easily-overlooked cost driver at scale — CloudWatch Logs ingestion cost scales directly with volume, and this application's logging practice is generating far more volume than is operationally useful for routine operation.

**Technical reasoning:** logging full request/response bodies at INFO level (a level that's active in normal production operation, not just during active debugging) means every single request generates a large log entry regardless of whether anything noteworthy actually happened — the vast majority of this volume provides no additional diagnostic value over a much smaller, more targeted log entry for the same request.

**Investigation process:** confirm exactly what's being logged (full bodies, full headers, at what level) and assess how much of it is actually consulted during real troubleshooting versus simply accumulating unused — this determines what can be safely reduced without losing genuine diagnostic capability.

**Recommended solution:** reduce routine log verbosity to what's actually operationally useful (request method/path/status/latency, not full bodies) at INFO level, reserving full request/response body logging for a DEBUG level enabled only temporarily during active troubleshooting (or sampled at a low rate, if some ongoing visibility into full payloads is genuinely needed) — dramatically reducing steady-state volume while preserving the ability to get detailed visibility when actually needed.

**Risk controls:** before reducing logging, confirm no compliance/audit requirement actually mandates the current full-body logging practice (some regulated contexts do require this) — if such a requirement exists, the cost is a legitimate, necessary one, and the focus shifts to optimizing cost within that constraint (e.g., a cheaper long-term storage tier for compliance-required logs, separate from the operational logging pipeline).

**Validation steps:** after reducing verbosity, confirm the reduced log volume still provides sufficient information for typical troubleshooting scenarios (test against a recent, real past issue and confirm the reduced logs would still have been sufficient to diagnose it), and confirm the cost trend reflects the expected reduction.

**Rollback or recovery strategy:** if the reduced logging proves insufficient for a specific troubleshooting need, temporarily enable DEBUG-level full-body logging for the specific affected component/time window, rather than reverting the global INFO-level reduction.

**Long-term prevention:** establish logging-verbosity review as a standard part of any application's production-readiness checklist, and consider periodic cost-per-application log-volume review as a standing operational practice, catching this class of cost driver before it silently accumulates to the scale seen here.

### Step-by-Step Implementation
```text
Before: INFO-level logs every request's full body/headers - high, indiscriminate volume
After:  INFO-level logs method/path/status/latency only;
        DEBUG-level (normally disabled) full body/headers, enabled only
        temporarily during active troubleshooting via a runtime log-level change
```

### Under-the-Hood Explanation
CloudWatch Logs bills based on ingested data volume — every byte logged, regardless of whether it's ever queried or consulted afterward, contributes directly to cost; there's no automatic distinction CloudWatch makes between "genuinely useful diagnostic content" and "verbose data logged out of caution that nobody ends up needing," meaning the actual verbosity decision made in application code is the real cost-control lever, not anything CloudWatch itself manages automatically.

### Common Weak Answer
"Just reduce the CloudWatch Logs retention period to save cost."

### Why the Weak Answer Fails
Retention period affects *storage* cost for logs already ingested — it does nothing about the *ingestion* cost, which is driven by volume and charged regardless of how long the data is subsequently retained; the actual fix addresses the root cause (excessive logging verbosity) rather than a downstream cost lever that doesn't address ingestion cost at all.

### Follow-Up Questions
1. How would you audit other applications across the fleet for this same excessive-verbosity cost pattern?
2. What's the trade-off of sampled (rather than fully disabled) verbose logging for ongoing, lower-cost visibility into full payloads?
3. How would you handle a genuine compliance requirement mandating full-body logging, while still managing its cost impact?

### Key Interview Signals
Correctly identifies ingestion volume (not retention) as the actual cost driver, and designs a verbosity reduction that preserves genuine diagnostic capability while eliminating cost from data that provides little operational value.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 83: The dashboard that lied by omission

### Scenario
A Grafana dashboard shows aggregate, cluster-wide P50 latency looking healthy throughout an incident later found to have severely affected a specific, smaller subset of customers routed to a particular subset of pods. The aggregate metric never crossed any alerting threshold.

### Interview Question
Explain why an aggregate metric missed a real, severe issue, and redesign the observability approach.

### Strong Senior-Level Answer
**Initial assessment:** aggregate, cluster-wide metrics (especially P50, the median) can easily mask a severe issue affecting a *minority* of traffic — if the affected subset is small relative to total traffic volume, its impact on the overall aggregate can be diluted below any noticeable threshold, even though for the affected customers specifically, the impact was severe.

**Technical reasoning:** P50 latency, by definition, reflects the *median* request — a severe issue affecting, say, 5% of traffic can leave the P50 completely unaffected (the median request is still one of the unaffected 95%), while P99 (or better, per-segment breakdowns) would have shown the issue clearly, since it specifically reflects tail behavior rather than typical-case behavior.

**Investigation process:** review what percentile/aggregation the dashboard actually displayed (confirmed here as P50, cluster-wide) and cross-reference against the actual affected subset's characteristics (were they served by a specific subset of pods, a specific AZ, a specific customer segment) — this determines what dimension of segmentation would have surfaced the issue.

**Recommended solution:** redesign observability to include P99 (and ideally P95/P90 as intermediate signals) alongside P50, and add segmentation/breakdown capability (by pod, by AZ, by customer tier, whatever dimension is operationally meaningful) rather than relying solely on a single cluster-wide aggregate metric — a P99-based alert specifically would likely have caught this issue given its outsized impact on a smaller but real subset of requests.

**Risk controls:** avoid over-correcting into alerting on every possible segmentation dimension simultaneously (reintroducing the alert-fatigue problem from Question 80) — choose a small number of genuinely meaningful percentiles/segments based on how the business/product actually experiences and cares about performance, not an exhaustive combinatorial breakdown.

**Validation steps:** after adding P99 monitoring/alerting, confirm it would have caught this specific past incident by replaying the historical data (if retained) against the new alert definition, and confirm the new percentile-based alert doesn't introduce excessive noise during genuinely healthy periods.

**Rollback or recovery strategy:** not applicable — this is an observability-coverage improvement.

**Long-term prevention:** treat "does our aggregate metric adequately represent tail/minority-segment behavior" as a standing design question for any dashboard/alert relying on a central-tendency statistic (mean, median) — P50/mean-based monitoring alone is a well-known, recurring blind spot for exactly this class of "severe for a minority" incident.

### Step-by-Step Implementation
```promql
# Before: only P50 monitored
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))

# After: P99 alerting added, catching tail-latency issues P50 masks
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
```

### Under-the-Hood Explanation
A percentile metric summarizes a distribution's shape at one specific point — P50 reflects the value below which 50% of observations fall, meaning it's mathematically insensitive to how bad the *worst* portion of the distribution gets, as long as the majority remains unaffected; P99 (or higher) specifically surfaces tail behavior, which is exactly where a severe issue affecting a real but numerically smaller subset of traffic would actually show up clearly.

### Common Weak Answer
"P50 is the standard metric everyone uses, this was just an unusual edge case."

### Why the Weak Answer Fails
This is a well-known, well-documented limitation of median/mean-based monitoring, not an unusual edge case — any issue affecting a minority of traffic severely while leaving the majority unaffected will be masked by P50 as a matter of basic statistics, which is exactly why P99 (and segmentation) monitoring is standard practice for genuinely comprehensive observability, not an exotic addition.

### Follow-Up Questions
1. How would you choose which percentiles (P90, P95, P99, P99.9) are worth actively monitoring/alerting on for a given service?
2. How would you design segmentation (by pod/AZ/customer tier) without creating an unmanageable proliferation of dashboards/alerts?
3. How would you retroactively investigate whether other past incidents were similarly masked by aggregate-only monitoring?

### Key Interview Signals
Understands the specific statistical reason P50 masks minority-affecting severe issues, and redesigns toward tail-percentile and segmented monitoring rather than dismissing the gap as an unusual, unavoidable edge case.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 84: Correlating three signals during a live incident

### Scenario
During an active incident, an alert fires on elevated P99 latency for the checkout service. The on-call engineer has access to logs, metrics, and traces but isn't sure what order to check them in or how to connect findings across the three.

### Interview Question
Walk through the correct correlation sequence for this specific incident.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/observability.md`](../docs/observability.md) §6, the correct approach explicitly walks the correlation chain across all three signal types in sequence, rather than treating them as three independent tools to check in no particular order — each signal narrows the investigation for the next.

**Technical reasoning:** metrics (the alert itself) tell you *that* something's wrong and roughly *when* it started — they don't tell you *why*. Logs from the affected service around that time window can reveal specific error messages or slow-operation indicators. Traces for specific slow requests during that window reveal exactly *where* in the request's full path across services the time is actually being spent — often the most direct path to root cause for a latency-specific issue like this one.

**Investigation process:** (1) confirm from the metric alert the exact time window and specific affected service/endpoint; (2) pull logs for the checkout service specifically during that window, looking for elevated error rates, timeout messages, or any anomalous log pattern; (3) pull a sample of actual slow traces from that window (ideally already correlated via a trace ID present in the logs) and examine each trace's span breakdown to see exactly which downstream call/operation is consuming the excess time.

**Recommended solution:** based on what the trace reveals (e.g., a specific downstream dependency call taking unusually long), the recommended remediation follows directly — if it's a database query, investigate the database itself; if it's a downstream service call, investigate that service's own health; if it's within the checkout service's own processing (not a downstream call), investigate its own resource constraints (CPU throttling, GC pauses) via its own metrics.

**Risk controls:** while investigating, keep monitoring the alert's own metric to track whether the issue is worsening, stable, or already resolving — informing urgency, not just root-cause investigation.

**Validation steps:** once a specific root cause is identified and addressed, confirm the P99 latency metric returns to baseline, and confirm new traces during the post-fix window no longer show the same specific slow span.

**Rollback or recovery strategy:** depends entirely on the identified root cause — if a recent deployment correlates with the incident's onset, a rollback of that specific change is the fastest mitigation while the deeper root cause is investigated further.

**Long-term prevention:** ensure trace IDs are consistently included in log output (closing the logs-to-traces correlation gap) and that this three-signal correlation sequence (metrics → logs → traces) is documented as the standard incident-response runbook pattern, so on-call doesn't need to rediscover the right approach during a live, time-pressured incident.

### Step-by-Step Implementation
```text
1. Alert fires: P99 latency elevated for checkout-service, since 14:32 UTC
2. Logs: kubectl logs -l app=checkout-service --since-time=14:30 | grep -i "error\|timeout\|slow"
3. Traces: pull sample slow traces from 14:32+ window, examine span breakdown
   -> reveals: 80% of the elevated latency is in a call to the inventory-service
4. Root cause narrowed to inventory-service - investigate ITS metrics/logs next
```

### Under-the-Hood Explanation
Each signal type captures a fundamentally different dimension of the same underlying event — metrics are pre-aggregated numerical summaries (fast to query, coarse-grained), logs are discrete, timestamped textual events (rich detail, but not inherently structured across service boundaries), and traces are structured, causally-linked records of a single request's actual path across every service it touched — correlating all three, in the metrics-then-logs-then-traces order, moves from "something is wrong" to "specifically why" efficiently, since each step narrows the investigation using information the previous step provided.

### Common Weak Answer
"Just look at whichever dashboard is open and see if anything looks unusual."

### Why the Weak Answer Fails
This has no structured approach connecting the three signal types deliberately — it risks missing the specific, efficient correlation path (metrics narrow the time window, logs narrow the specific error pattern, traces pinpoint the exact slow operation) that a deliberate, sequenced investigation provides, especially under the time pressure of a live incident.

### Follow-Up Questions
1. How would you ensure trace IDs are consistently propagated into log output across every service, closing the logs-to-traces correlation gap?
2. What would you do differently if the trace breakdown showed the delay was within the checkout service's own processing, not a downstream call?
3. How would you build this correlation sequence into a standard, documented incident-response runbook for the team?

### Key Interview Signals
Walks the deliberate metrics-then-logs-then-traces correlation sequence explicitly, explaining what each step narrows down for the next, rather than describing an unstructured, ad hoc investigation approach.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 85: Monitoring the monitors

### Scenario
A cluster's Prometheus instance silently stops scraping targets for six hours (due to an unrelated resource-exhaustion issue on its own pod) during which a genuine, unrelated production incident occurs completely undetected, since no alerts fired — there was simply no data to evaluate alert rules against.

### Interview Question
Design a solution ensuring an observability-pipeline failure itself doesn't create a blind spot.

### Strong Senior-Level Answer
**Initial assessment:** this is the observability-pipeline equivalent of the admission-webhook-availability dependency (Question 33) and the break-glass-path staleness issue (companion Ansible/IRSA Question 32) — a monitoring system's own failure mode (silently stopping, rather than loudly erroring) creates a blind spot precisely when it's most needed, and nothing in this setup was watching the monitoring system's own health independently.

**Technical reasoning:** if every alert rule depends entirely on the same Prometheus instance actually being healthy and actively scraping, a failure of that instance itself doesn't trigger any of its own alerts (since it's not evaluating rules against fresh data, or evaluating anything at all) — the monitoring system has no external, independent watchdog checking "is monitoring itself still working," so its own outage is invisible by default.

**Investigation process:** confirm exactly what caused Prometheus's own resource exhaustion (a legitimate capacity/configuration issue in the monitoring stack itself, worth fixing on its own merits) and confirm no external, independent health check existed for the monitoring pipeline itself during this six-hour window.

**Recommended solution:** implement a **dead man's switch** pattern — an external, independent service (outside the primary monitoring stack's own infrastructure, ideally in a genuinely separate failure domain) that expects to receive a regular heartbeat/check-in from the monitoring pipeline, and alerts (via a completely separate notification path) if that heartbeat stops arriving — this is specifically designed to catch exactly this class of "the thing that's supposed to alert you has itself gone silent" failure.

**Risk controls:** ensure the dead-man's-switch service and its own alerting path are genuinely independent of the primary monitoring stack's infrastructure (different failure domain — ideally not even in the same cluster/account, if practical) so a shared underlying cause can't take down both the primary monitoring and its own watchdog simultaneously.

**Validation steps:** deliberately stop the primary monitoring stack (in a controlled test) and confirm the dead-man's-switch correctly detects the missing heartbeat and fires its own, independent alert.

**Rollback or recovery strategy:** for the immediate resource-exhaustion issue, fix Prometheus's own capacity/configuration (the proximate cause of this specific six-hour outage) — separately, retroactively review logs/any available signal from during the gap to assess whether the undetected production incident's actual impact can still be characterized after the fact.

**Long-term prevention:** treat "who watches the watcher" as a standing architectural question for the entire observability pipeline — the same "recovery tool can't share fate with what it's recovering" principle from [`docs/ha-dr.md`](../docs/ha-dr.md) §7, applied here to monitoring infrastructure's own availability rather than a GitOps controller's.

### Step-by-Step Implementation
```yaml
# Prometheus rule pushing a heartbeat to an external dead-man's-switch service
- alert: Watchdog
  expr: vector(1)
  labels:
    severity: none
  annotations:
    description: "This is a constant alert used as a dead man's switch"
# Configured to route to an external service (e.g., a third-party uptime/heartbeat monitor)
# that alerts via a SEPARATE notification path if this alert ever stops firing
```

### Under-the-Hood Explanation
A dead-man's-switch alert is deliberately configured to *always* be firing under normal, healthy conditions (e.g., `vector(1)`, a constant expression that's always true) — its entire purpose is that an external system expects to continuously receive this "everything is fine, I'm alive" signal, and specifically alerts when that signal *stops*, which is the only way to detect "the monitoring system itself has gone silent," since a silent monitoring system can't be relied upon to alert on its own silence through its normal alerting path.

### Common Weak Answer
"Just add more alerting rules to Prometheus to catch this kind of issue."

### Why the Weak Answer Fails
Any additional alert rule still depends on the same Prometheus instance being healthy enough to evaluate it — this doesn't address the actual gap, which is detecting when Prometheus *itself* stops functioning entirely; only an external, independently-operating watchdog can catch that specific failure mode.

### Follow-Up Questions
1. How would you choose where to run the external dead-man's-switch service to ensure genuine failure-domain independence from the primary monitoring stack?
2. What other critical infrastructure components in this platform (besides monitoring) might benefit from this same "external watchdog" pattern?
3. How would you retroactively characterize the impact of an incident that occurred during a monitoring blind spot, after the fact?

### Key Interview Signals
Recognizes that a monitoring system's own silent failure is a distinct, genuinely dangerous blind spot requiring an externally-independent detection mechanism, connecting this to the same "who watches the watcher" principle established elsewhere in this repository series.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 86: One observability stack, twenty teams, one shared bill

### Scenario
A shared Prometheus/Grafana stack serves 20 application teams on the platform from Question 74/78. One team's poorly-designed, extremely high-cardinality metric (a label containing a unique request ID, generating millions of unique time series) causes Prometheus's memory usage to spike, degrading query performance for all 19 other teams simultaneously.

### Interview Question
Diagnose the cardinality issue and design both an immediate fix and a prevention mechanism for a shared, multi-tenant observability platform.

### Strong Senior-Level Answer
**Initial assessment:** this is a noisy-neighbor problem in the observability layer specifically — Prometheus's memory usage scales directly with the number of unique time series (cardinality), and a single team's metric design mistake (using a high-cardinality label like a unique request ID) can degrade the shared instance for every other tenant, exactly the same shared-resource blast-radius concern as an unconstrained workload starving shared compute capacity, but here affecting the monitoring layer itself.

**Technical reasoning:** every unique combination of a metric name and its label values creates a distinct time series in Prometheus's in-memory storage — a label like a request ID (unique per request, essentially unbounded cardinality) multiplies the number of stored series by the number of unique requests ever seen, causing memory usage to grow unboundedly rather than staying proportional to the actual number of meaningfully-distinct measurement dimensions.

**Investigation process:** identify the specific offending metric via Prometheus's own cardinality-analysis tooling (`prometheus_tsdb_symbol_table_size_bytes`, or querying `count by (__name__)(...)` grouped by metric name to find the highest-cardinality culprits) — this pinpoints exactly which team's metric is responsible.

**Recommended solution:** immediately, work with the offending team to remove the high-cardinality label (request IDs belong in traces/logs, which are designed for high-cardinality, per-request granularity, not in metrics, which are meant for aggregation across bounded dimensions) — restoring healthy memory usage for the shared instance; going forward, implement per-tenant cardinality limits (Prometheus's own `--storage.tsdb.max-exemplars` and label-cardinality-limiting relabeling rules, or, more robustly, moving to a multi-tenant metrics backend like Cortex/Mimir/Thanos with genuine per-tenant resource isolation) so one team's mistake can't degrade the shared platform for everyone else.

**Risk controls:** establish and document clear metric-design guidelines (never put unbounded-cardinality values like request IDs, user IDs, or timestamps in metric labels) as onboarding material for any team joining the shared observability platform, and consider an admission-time check (a metric-relabeling/dropping rule catching known-bad label patterns) as a structural guardrail.

**Validation steps:** after the fix, confirm Prometheus memory usage and query performance return to baseline for all 20 teams, and confirm the offending team's legitimate monitoring needs are still met via an appropriately-redesigned, bounded-cardinality metric.

**Rollback or recovery strategy:** if the immediate fix (removing the label) breaks something the offending team was relying on, help them redesign toward a bounded-cardinality alternative (e.g., a bucketed/binned dimension instead of the raw unique ID) rather than reverting to the high-cardinality version.

**Long-term prevention:** consider migrating the shared platform to a genuinely multi-tenant-aware metrics backend (Cortex/Mimir/Thanos) providing per-tenant resource quotas and isolation, so cardinality mistakes are contained to their originating tenant rather than able to affect the entire shared platform — the observability-layer equivalent of the namespace-level ResourceQuota isolation discussed in [`diagrams/15-multi-tenant-isolation-model.md`](../diagrams/15-multi-tenant-isolation-model.md).

### Step-by-Step Implementation
```promql
# Identify the highest-cardinality metric
topk(10, count by (__name__)({__name__=~".+"}))
```
```yaml
# Relabeling rule dropping a known-problematic high-cardinality label at scrape time
metric_relabel_configs:
  - regex: request_id
    action: labeldrop
```

### Under-the-Hood Explanation
Prometheus stores each unique time series (a unique combination of metric name and label value set) as a separate entry in its in-memory index and on-disk chunks — a label with effectively unbounded unique values (a request ID) means every single request generates a brand-new time series rather than contributing to an existing, bounded one, causing memory usage tied to the *index* itself (not just the data volume) to grow without bound, exactly the mechanism causing the described memory spike and resulting query-performance degradation for every tenant sharing that same Prometheus instance's memory space.

### Common Weak Answer
"Just give Prometheus more memory to handle the load."

### Why the Weak Answer Fails
Unbounded-cardinality metrics grow without any natural ceiling — throwing more memory at the problem only delays the same degradation recurring at a larger scale, and does nothing to protect the other 19 teams from a *future* cardinality mistake by any team; the actual fix addresses the root metric-design issue and, ideally, the shared platform's lack of per-tenant isolation.

### Follow-Up Questions
1. How would you design onboarding documentation/tooling helping new teams avoid this exact cardinality mistake before it happens?
2. What's the migration cost/complexity of moving from a single shared Prometheus instance to a multi-tenant backend like Mimir or Thanos?
3. How would you detect a cardinality problem proactively, before it degrades performance for other tenants, rather than reactively?

### Key Interview Signals
Correctly diagnoses the cardinality-driven memory-scaling mechanism as the root cause, and designs both an immediate metric-design fix and a structural, multi-tenant-isolation-oriented long-term prevention rather than simply scaling up shared resources.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
