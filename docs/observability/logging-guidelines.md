# Logging Guidelines

Use structured JSON logs only.

Required fields:

```json
{
  "timestamp": "2026-06-12T12:00:00.000Z",
  "level": "info",
  "app": "progressa",
  "service": "frontend",
  "environment": "production",
  "event": "workout_create_failed",
  "message": "Human-readable explanation",
  "error_code": "PROG-WORKOUT-002",
  "correlation_id": "uuid",
  "user_id_hash": "hash-or-null",
  "duration_ms": 123,
  "metadata": {}
}
```

Safe metadata:

- counts
- durations
- route names
- table names
- operation names
- status codes
- coarse flow names

Never log:

- access tokens
- refresh tokens
- Supabase keys
- passwords
- full health records
- full workout payloads
- request bodies
- names, emails, or personal identifiers in plaintext

Use `correlation_id` for multi-step flows. The frontend creates a correlation id for sync/load/create flows and sends it to the backend where possible.

Performance thresholds:

- startup over `2000 ms`: warn
- tab switch over `500 ms`: warn
- Supabase query over `1000 ms`: warn
- sync job over `10000 ms`: warn

