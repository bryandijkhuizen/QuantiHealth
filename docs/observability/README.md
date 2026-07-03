# Progressa / Quantivita Observability

## Stack

Chosen stack:

- Grafana: dashboard UI.
- Loki: structured app/API logs.
- Promtail: Docker log collector.
- Prometheus: metrics and alerts.
- node-exporter: host CPU/memory/disk metrics.
- cAdvisor: Docker container metrics.

Tempo/tracing is intentionally not included yet. Logs, metrics, correlation ids, and dashboards cover the current debugging need with lower homeserver overhead.

## Start Locally Or On Homeserver

```sh
cd monitoring
cp .env.example .env
# Change GRAFANA_ADMIN_PASSWORD before exposing Grafana.
docker compose up -d
```

Grafana default URL:

```text
http://<homeserver>:3030
```

Prometheus:

```text
http://<homeserver>:9090
```

Loki:

```text
http://<homeserver>:3100
```

## Logs

Logs are collected from Docker containers:

- `quantivita`
- `progressa-api`
- `monitoring-*`

Mobile frontend logs are sent to:

- Quantivita: `POST /api/users/:accountId/observability/logs`
- Progressa: `POST /api/observability/logs`

Both endpoints sanitize metadata and write JSON to stdout so Promtail can send it to Loki.

## Metrics

Backends expose:

- Quantivita: `http://host.docker.internal:8088/metrics`
- Progressa API: `http://host.docker.internal:3002/metrics`

Prometheus also scrapes node-exporter and cAdvisor.

## Searching

By app:

```logql
{app="progressa"} | json
{app="quantivita"} | json
```

By error code:

```logql
{error_code="PROG-WORKOUT-002"} | json
{error_code="QV-SYNC-001"} | json
```

By correlation id:

```logql
{app="progressa"} | json | correlation_id="..."
```

## Adding Error Codes

1. Add the code to `docs/observability/error-codes.md`.
2. Include severity, likely cause, action, and example event.
3. Use it in frontend/backend structured logs.
4. Verify it appears in Grafana with `{error_code="CODE"}`.

## Security

- Do not expose Grafana publicly without reverse proxy auth.
- Change `GRAFANA_ADMIN_PASSWORD`.
- Do not log tokens, Supabase keys, request bodies, full health records, full workout data, or plaintext user ids.
- User ids are hashed before logging.

