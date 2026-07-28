# Cheat Sheet: Observability

## `metrics-server` is not observability
- Feeds HPA and `kubectl top` **only** — retains zero history.
- No time-range query is even possible against its API.
- For genuine observability: `kube-prometheus-stack` (self-managed) or CloudWatch Container Insights.
[Question 79](../interview-questions/09-observability.md#question-79-the-autoscaling-that-had-no-history)

## P50 vs. P99 — the statistics trap
P50 (median) is mathematically insensitive to a severe issue affecting a **minority** of traffic — the median request is still one of the unaffected majority.
```promql
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))  # catches what P50 masks
```
[Question 83](../interview-questions/09-observability.md#question-83-the-dashboard-that-lied-by-omission)

## Alert on symptoms, not every event
```yaml
# BAD - fires on every routine pod restart during a normal rollout
- alert: PodRestarted
  expr: increase(kube_pod_container_status_restarts_total[5m]) > 0

# GOOD - business-impact symptom
- alert: ElevatedErrorRate
  expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
```
[Question 80](../interview-questions/09-observability.md#question-80-the-alert-that-fired-four-hundred-times-before-anyone-looked)

## Trace gaps = missing instrumentation, not a broken collector
A gap in a distributed trace almost always means the request crossed a boundary with no context propagation (an un-instrumented service, a third-party API) — check the specific service's own logs/code at that boundary first. [Question 81](../interview-questions/09-observability.md#question-81-the-trace-that-stopped-at-the-cluster-boundary)

## Log volume is a real, controllable cost
CloudWatch Logs bills on **ingestion volume**, not retention. Reduce routine verbosity (method/path/status/latency, not full request/response bodies) at INFO; reserve full-body logging for DEBUG, enabled only during active troubleshooting. [Question 82](../interview-questions/09-observability.md#question-82-the-log-line-that-cost-more-than-the-server)

## The metrics → logs → traces correlation sequence
1. **Metrics** (the alert) — confirms *that* something's wrong, roughly *when*.
2. **Logs** for the affected service/window — the specific error pattern.
3. **Traces** for a slow/failed request in that window — exactly *where* in the call graph.
[Question 84](../interview-questions/09-observability.md#question-84-correlating-three-signals-during-a-live-incident)

## "Who watches the watcher" — dead man's switch
```yaml
- alert: Watchdog
  expr: vector(1)   # always true - external system alerts if this EVER stops firing
```
No additional Prometheus rule can catch Prometheus's own silent failure — only an externally, independently-running heartbeat monitor can. [Question 85](../interview-questions/09-observability.md#question-85-monitoring-the-monitors)

## Shared observability platform = shared risk
A single tenant's high-cardinality metric (a label with unbounded values, like a request ID) can degrade a shared Prometheus instance for **every** tenant. Enforce metric-design guidelines + consider a multi-tenant backend (Mimir/Thanos/Cortex) at scale. [Question 86](../interview-questions/09-observability.md#question-86-one-observability-stack-twenty-teams-one-shared-bill)
