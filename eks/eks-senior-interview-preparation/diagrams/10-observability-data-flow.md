# Diagram 10: Observability Data Flow

```mermaid
flowchart TB
    subgraph Node
        POD[Pods - stdout/stderr]
        FLUENTBIT[Fluent Bit DaemonSet]
        METRICSSERVER[metrics-server]
        NODEEXPORTER[node-exporter / kube-state-metrics]
    end

    POD --> FLUENTBIT
    FLUENTBIT --> CWLOGS[CloudWatch Logs / OpenSearch]
    METRICSSERVER --> HPA[HPA - CPU/memory scaling decisions]
    NODEEXPORTER --> PROM[Prometheus - kube-prometheus-stack]
    PROM --> GRAFANA[Grafana Dashboards]
    PROM --> ALERTMGR[Alertmanager]
    POD -->|OpenTelemetry SDK| OTEL[OTel Collector]
    OTEL --> XRAY[AWS X-Ray / Jaeger]

    CWAGENT[CloudWatch Agent] --> INSIGHTS[Container Insights]
```

## Key points
- `metrics-server` exists only to feed HPA/`kubectl top` — it has no history and is not a substitute for a real observability pipeline (Prometheus or Container Insights).
- Logs, metrics, and traces are three separate pipelines that must be deliberately correlated (e.g., via trace IDs in logs) during incident diagnosis, not three isolated tools.
- See [`docs/observability.md`](../docs/observability.md) for the Container-Insights-vs-Prometheus trade-off and alerting design guidance.
