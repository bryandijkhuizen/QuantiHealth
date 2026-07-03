import crypto from 'node:crypto';

const startedAt = Date.now();
const counters = new Map();
const durations = new Map();

export function createObservability({ app, service, environment }) {
  function log(level, event, message, fields = {}) {
    const entry = sanitize({
      timestamp: new Date().toISOString(),
      level,
      app,
      service,
      environment,
      event,
      message,
      error_code: fields.error_code || null,
      correlation_id: fields.correlation_id || randomId(),
      user_id_hash: fields.user_id_hash || null,
      duration_ms: Number.isFinite(fields.duration_ms) ? Math.round(fields.duration_ms) : null,
      route: fields.route,
      method: fields.method,
      status_code: fields.status_code,
      metadata: fields.metadata || {},
    });
    increment('observability_log_events_total', {
      app,
      service,
      level,
      event,
      error_code: entry.error_code || 'none',
    });
    if (entry.duration_ms != null) observe('observability_event_duration_ms', { app, service, event }, entry.duration_ms);
    const line = JSON.stringify(entry);
    if (level === 'error' || level === 'fatal') console.error(line);
    else if (level === 'warn') console.warn(line);
    else console.log(line);
  }

  function requestMiddleware(request, response, next) {
    const started = performance.now();
    const correlationId = request.get('x-correlation-id') || randomId();
    request.correlationId = correlationId;
    response.setHeader('x-correlation-id', correlationId);
    log('info', 'api_request_started', 'API request started', {
      correlation_id: correlationId,
      method: request.method,
      route: routeFor(request),
      metadata: { path: request.path },
    });
    response.on('finish', () => {
      const duration = performance.now() - started;
      const level = response.statusCode >= 500 ? 'error' : response.statusCode >= 400 ? 'warn' : 'info';
      const event = response.statusCode >= 400 ? 'api_request_failed' : 'api_request_completed';
      increment('http_requests_total', {
        app,
        service,
        method: request.method,
        route: routeFor(request),
        status: String(response.statusCode),
      });
      observe('http_request_duration_ms', { app, service, method: request.method, route: routeFor(request) }, duration);
      log(level, event, `API request completed with ${response.statusCode}`, {
        correlation_id: correlationId,
        duration_ms: duration,
        method: request.method,
        route: routeFor(request),
        status_code: response.statusCode,
        error_code: response.statusCode >= 500 ? 'PROG-API-001' : null,
        metadata: httpStatusMetadata(response.statusCode),
      });
    });
    next();
  }

  function frontendLogHandler(request, response) {
    const body = request.body && typeof request.body === 'object' ? request.body : {};
    log(normalizeLevel(body.level), String(body.event || 'frontend_event'), String(body.message || 'Frontend event'), {
      correlation_id: String(body.correlation_id || request.correlationId || randomId()),
      error_code: body.error_code ? String(body.error_code) : null,
      user_id_hash: body.user_id_hash ? String(body.user_id_hash) : null,
      duration_ms: Number(body.duration_ms),
      metadata: safeMetadata(body.metadata),
    });
    response.status(202).json({ ok: true });
  }

  function metricsHandler(_request, response) {
    response.type('text/plain').send(metricsText());
  }

  return { log, requestMiddleware, frontendLogHandler, metricsHandler, increment, observe };
}

export function userHash(value) {
  if (!value) return null;
  return crypto.createHash('sha256').update(String(value)).digest('hex').slice(0, 24);
}

function increment(name, labels = {}, value = 1) {
  const key = metricKey(name, labels);
  counters.set(key, { name, labels, value: (counters.get(key)?.value || 0) + value });
}

function observe(name, labels = {}, value = 0) {
  const key = metricKey(name, labels);
  const current = durations.get(key) || { name, labels, count: 0, sum: 0, max: 0 };
  current.count += 1;
  current.sum += value;
  current.max = Math.max(current.max, value);
  durations.set(key, current);
}

function metricsText() {
  const lines = [
    '# HELP observability_uptime_seconds Process uptime in seconds.',
    '# TYPE observability_uptime_seconds gauge',
    `observability_uptime_seconds ${Math.round((Date.now() - startedAt) / 1000)}`,
  ];
  for (const item of counters.values()) lines.push(`${item.name}${labelsText(item.labels)} ${item.value}`);
  for (const item of durations.values()) {
    lines.push(`${item.name}_count${labelsText(item.labels)} ${item.count}`);
    lines.push(`${item.name}_sum${labelsText(item.labels)} ${Math.round(item.sum)}`);
    lines.push(`${item.name}_max${labelsText(item.labels)} ${Math.round(item.max)}`);
  }
  return `${lines.join('\n')}\n`;
}

function httpStatusMetadata(statusCode) {
  return {
    http_status_class: httpStatusClass(statusCode),
    http_status_meaning: httpStatusMeaning(statusCode),
  };
}

function httpStatusClass(statusCode) {
  if (statusCode >= 100 && statusCode <= 199) return 'informational';
  if (statusCode >= 200 && statusCode <= 299) return 'success';
  if (statusCode >= 300 && statusCode <= 399) return 'redirection';
  if (statusCode >= 400 && statusCode <= 499) return 'client_error';
  if (statusCode >= 500 && statusCode <= 599) return 'server_error';
  return 'non_standard';
}

function httpStatusMeaning(statusCode) {
  const meanings = {
    400: 'Bad Request: malformed or invalid client request',
    401: 'Unauthorized: client must authenticate',
    403: 'Forbidden: identity known but access denied',
    404: 'Not Found: endpoint or resource not found',
    409: 'Conflict: request conflicts with current state',
    413: 'Content Too Large: request body exceeded limit',
    429: 'Too Many Requests: rate limit exceeded',
    500: 'Internal Server Error: unexpected server failure',
    502: 'Bad Gateway: invalid upstream response',
    503: 'Service Unavailable: service overloaded or unavailable',
    504: 'Gateway Timeout: upstream timed out',
  };
  return meanings[statusCode] || httpStatusClass(statusCode);
}

function metricKey(name, labels) {
  return `${name}:${JSON.stringify(Object.keys(labels).sort().map((key) => [key, labels[key]]))}`;
}

function labelsText(labels) {
  const entries = Object.entries(labels || {});
  if (entries.length === 0) return '';
  return `{${entries.map(([key, value]) => `${key}="${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`).join(',')}}`;
}

function routeFor(request) {
  return request.route?.path || request.baseUrl || request.path || 'unknown';
}

function randomId() {
  return crypto.randomUUID();
}

function normalizeLevel(level) {
  return ['info', 'warn', 'error', 'fatal'].includes(level) ? level : 'info';
}

function safeMetadata(metadata) {
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return {};
  const output = {};
  for (const [key, value] of Object.entries(metadata)) {
    if (/token|secret|password|key|authorization|health|payload|body/i.test(key)) continue;
    if (value == null || ['string', 'number', 'boolean'].includes(typeof value)) output[key] = String(value).slice(0, 240);
  }
  return output;
}

function sanitize(entry) {
  const text = JSON.stringify(entry).replace(/Bearer\s+[A-Za-z0-9._~+/-]+=*/gi, 'Bearer [redacted]');
  return JSON.parse(text);
}
