# Observability on EKS

Deep-dive reference for [`interview-questions/09-observability.md`](../interview-questions/09-observability.md) and [Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

## 1. The three pillars, mapped to EKS-specific tooling

- **Logs:** container stdout/stderr, collected by a node-level agent (Fluent Bit as a DaemonSet is the standard choice) and shipped to CloudWatch Logs, OpenSearch, or a third-party sink.
- **Metrics:** resource-usage metrics (CPU/memory) via `metrics-server` (needed for HPA — see [`docs/autoscaling.md`](../interview-questions/06-autoscaling-scheduling.md)) and richer, longer-retention metrics via a Prometheus stack (`kube-prometheus-stack` Helm chart) or CloudWatch Container Insights.
- **Traces:** distributed request tracing via OpenTelemetry (vendor-neutral instrumentation) exported to AWS X-Ray, Jaeger, or a third-party APM backend — needed to actually see a request's path across multiple microservices, which logs and metrics alone can't reconstruct.

## 2. Container Insights vs. a self-managed Prometheus/Grafana stack

**CloudWatch Container Insights** (an EKS-integrable, largely managed observability layer using the CloudWatch agent/Fluent Bit) gives fast time-to-value with minimal operational overhead, at CloudWatch's own cost model (which scales with metric/log volume and can become significant at high cardinality/fleet size). A **self-managed Prometheus/Grafana stack** (via `kube-prometheus-stack`) gives more control, richer query capability (PromQL), and often lower cost at scale, at the price of operating the stack itself (storage retention/scaling for Prometheus's TSDB, Grafana dashboard maintenance) as its own workload with its own HA/resource considerations. Many organizations run both: Container Insights for fast, low-effort baseline coverage, Prometheus/Grafana for deeper, cost-optimized, longer-term operational dashboards.

## 3. `metrics-server` is not the same as full observability

`metrics-server` exists specifically to feed the Horizontal Pod Autoscaler and `kubectl top` with current CPU/memory usage — it retains no history and is not a substitute for a real metrics/observability pipeline. A cluster with only `metrics-server` installed has autoscaling working but effectively no historical dashboards, alerting, or trend analysis — a common gap that surfaces only during a postmortem ("we have no historical data on what memory usage looked like before this OOM cascade started").

## 4. Log volume and cost at scale

At fleet scale, raw container log volume can become a genuine cost and performance concern (CloudWatch Logs ingestion cost scales with volume; Fluent Bit itself can become resource-constrained on busy nodes) — the standard mitigations mirror cost-governance patterns seen elsewhere in this repository: sampling/filtering non-essential log lines at the Fluent Bit level before shipping, setting sane log retention policies, and ensuring genuinely noisy debug-level logging isn't left enabled in production by default.

## 5. Alerting design — actionable, not noisy

An alert should map to something a human can and should act on — the standard failure mode (mirrored from the companion repositories' incident-response guidance) is alerting on every metric anomaly rather than on symptoms that actually indicate user-facing or business impact (e.g., alert on elevated error rate/latency at the ingress/service level, not on every individual pod restart, since Kubernetes' own self-healing already handles isolated pod restarts without needing a human in the loop for each one).

## 6. Correlating logs, metrics, and traces during an incident

A senior-level incident-response answer for EKS explicitly walks the correlation chain: an alert fires on elevated latency (metrics) → check the affected service's logs for errors around that time window → use a trace ID (if present in logs, propagated via OpenTelemetry) to see exactly which downstream dependency the slow requests are stalling on — rather than treating logs, metrics, and traces as three separate, uncorrelated tools consulted independently.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "We have metrics-server so we have observability" | Distinguishes metrics-server's narrow autoscaling-feed purpose from a real observability pipeline |
| "Alert on every pod restart" | Alerts on user-facing/business-impact symptoms, trusting Kubernetes' own self-healing for isolated restarts |
| "Just use CloudWatch for everything" | Weighs Container Insights' cost-at-scale against a self-managed Prometheus stack's operational overhead, choosing per actual needs |
| "Logs, metrics, and traces are three separate tools" | Explicitly correlates across all three during incident diagnosis |

## Related material

- [`docs/troubleshooting.md`](troubleshooting.md), [`docs/ha-dr.md`](ha-dr.md)
- [Lab 9 — Observability Stack](../labs/lab-09-observability-stack/)
