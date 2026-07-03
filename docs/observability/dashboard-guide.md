# Dashboard Guide

Grafana contains one provisioned dashboard:

`Progressa / Quantivita Observability`

Sections:

- Overview: total errors/warnings, latest critical logs.
- Progressa: `PROG-*` logs and error trends.
- Quantivita: `QV-*` logs and error trends.
- Infra: container CPU/memory from cAdvisor.

Useful Loki queries:

```logql
{app="progressa"} | json
{app="quantivita"} | json
{error_code="PROG-WORKOUT-002"} | json
{error_code="QV-SYNC-001"} | json
{app="progressa"} | json | correlation_id="PASTE_ID"
{level=~"error|fatal"} | json
```

Useful Prometheus queries:

```promql
sum by (app) (increase(observability_log_events_total{level=~"error|fatal"}[1h]))
sum by (error_code) (increase(observability_log_events_total[24h]))
sum by (route,status) (increase(http_requests_total[1h]))
http_request_duration_ms_sum / http_request_duration_ms_count
container_memory_usage_bytes{name=~"quantivita|progressa-api|monitoring-.*"}
```

Alerts are configured in Prometheus and visible through Grafana alerting pages after datasource sync.

