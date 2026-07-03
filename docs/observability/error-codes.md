# Observability Error Codes

## HTTP Status Interpretation

API request logs include `status_code`, `http_status_class`, and `http_status_meaning`.

The status classes follow the standard HTTP grouping:

- `informational`: 100-199
- `success`: 200-299
- `redirection`: 300-399
- `client_error`: 400-499
- `server_error`: 500-599
- `non_standard`: anything outside those ranges

Common meanings used in dashboards:

- `401`: client must authenticate.
- `403`: identity is known, but access is denied.
- `404`: endpoint or resource not found.
- `409`: request conflicts with current server state.
- `429`: rate limit exceeded.
- `500`: unexpected server failure.
- `502`: invalid upstream response.
- `503`: service unavailable or overloaded.
- `504`: upstream timed out.

## Progressa

| Code | Service | Severity | Meaning | Likely Cause | Recommended Action | Example Event |
|---|---|---:|---|---|---|---|
| `PROG-APP-001` | frontend | error | Uncaught app error | Flutter/platform exception | Inspect `event`, route, recent user flow | `uncaught_flutter_error` |
| `PROG-AUTH-001` | frontend/api | error | Session could not be loaded | Expired session, callback issue | Re-authenticate, inspect auth callback logs | `auth_session_failed` |
| `PROG-SUPABASE-001` | supabase-client | error | Generic Supabase query failed | RLS/schema/network | Check table, operation, status | `supabase_query_failed` |
| `PROG-WORKOUT-001` | frontend/api | error | Workout load failed | Supabase select, RLS, API upstream | Check `supabase_table`, `supabase_operation`, HTTP status | `supabase_select_failed` |
| `PROG-WORKOUT-002` | frontend | error | Workout or set create failed | Supabase insert/update, missing column, RLS | Check insert payload shape and RLS policy | `workout_create_failed` |
| `PROG-WORKOUT-003` | frontend/api | warn | Workout aggregation inconsistent | Sets not grouped under workout/exercise | Inspect counts and aggregator logs | `workout_aggregation_inconsistent` |
| `PROG-SYNC-001` | frontend/api | error | Workout sync failed | Network, auth, Supabase upstream | Check correlation id across app/API | `workout_sync_failed` |
| `PROG-PERF-001` | frontend | warn | Slow startup/load/query | Large local state or slow Supabase | Inspect duration and affected flow | `workout_load_slow` |
| `PROG-PERF-002` | frontend | warn | Slow tab switch | Expensive rebuild or refetch | Inspect tab and duration metadata | `tab_switch_slow` |
| `PROG-API-001` | api | error | API request failed with 5xx | Unhandled API/backend error | Inspect request route and server logs | `api_request_failed` |

## Quantivita

| Code | Service | Severity | Meaning | Likely Cause | Recommended Action | Example Event |
|---|---|---:|---|---|---|---|
| `QV-APP-001` | frontend | error | Uncaught app error | Flutter/platform exception | Inspect event, screen, flow | `uncaught_flutter_error` |
| `QV-AUTH-001` | frontend/api | error | Session could not be loaded | Apple/session mismatch | Re-authenticate, check callback logs | `auth_session_failed` |
| `QV-SUPABASE-001` | supabase-client | error | Supabase query failed | RLS/schema/network | Check table/operation metadata | `supabase_query_failed` |
| `QV-SYNC-001` | frontend/api | error | Health/API sync failed | Network, homeserver, Progressa upstream | Search by correlation id | `sync_job_failed` |
| `QV-SYNC-002` | frontend | warn | Stale data detected | No recent health sync | Re-run sync, inspect freshness metadata | `stale_data_detected` |
| `QV-READINESS-001` | frontend | error | Readiness calculation failed | Bad input/calculation exception | Inspect missing metric metadata | `readiness_calculation_failed` |
| `QV-READINESS-002` | frontend | warn | Required readiness input missing | Missing HRV/sleep/RHR | Check Apple Health permissions | `readiness_input_missing` |
| `QV-IMPORT-001` | frontend | error | Health metric import failed | Apple Health permission/query error | Check import flow logs | `health_metric_import_failed` |
| `QV-PERF-001` | frontend/api | warn | Slow calculation/sync/startup | Large input or slow endpoint | Inspect duration and event metadata | `workout_sync_slow` |
| `QV-API-001` | api | error | API request failed with 5xx | Unhandled backend error | Inspect route/status/correlation id | `api_request_failed` |

## Infrastructure

| Code | Service | Severity | Meaning | Likely Cause | Recommended Action | Example |
|---|---|---:|---|---|---|---|
| `INFRA-CONTAINER-001` | docker | critical | Container unhealthy/down | Crash loop, image issue | Check cAdvisor/Grafana logs | `ContainerDown` |
| `INFRA-DB-001` | supabase/db | critical | Database unavailable | Supabase container/db down | Check Supabase containers | `database_unavailable` |
| `INFRA-NETWORK-001` | network | warning | Network timeout | DNS/reverse proxy/upstream | Check route and gateway logs | `network_timeout` |
| `INFRA-DISK-001` | node | warning | Disk usage high | Logs/data growth | Clean volumes or expand disk | `DiskUsageHigh` |
| `INFRA-MEMORY-001` | node | warning | Memory usage high | Container leak/load spike | Inspect container memory dashboard | `MemoryUsageHigh` |
| `INFRA-CPU-001` | node | warning | CPU usage high | Expensive query/job | Inspect container CPU dashboard | `cpu_usage_high` |

