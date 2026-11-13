import crypto from 'node:crypto';
import express from 'express';
import { createClient } from '@supabase/supabase-js';
import { authenticatedUser } from './auth.js';
import { createObservability, userHash } from './observability.js';

const app = express();
const port = Number(process.env.PORT || 3000);
const publicBaseUrl = process.env.PROGRESSA_PUBLIC_BASE_URL || 'https://api.progressa.bryandijkh.com';
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || '';
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const linkSecret =
  process.env.PROGRESSA_QUANTIVITA_LINK_SECRET ||
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  'dev-change-me';
if (process.env.NODE_ENV === 'production' && linkSecret === 'dev-change-me') {
  throw new Error('PROGRESSA_QUANTIVITA_LINK_SECRET must be configured in production');
}
const upstreamTimeoutMs = Number(process.env.PROGRESSA_UPSTREAM_TIMEOUT_MS || 15000);
const consumedLinkCodes = new Map();

const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});
const observability = createObservability({
  app: 'progressa',
  service: 'api',
  environment: process.env.NODE_ENV || 'production',
});

app.use(express.json({ limit: '1mb' }));
app.use(observability.requestMiddleware);

app.get('/', (_request, response) => {
  response.type('html').send(`<!doctype html>
<html lang="nl">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Progressa API</title>
    <style>
      :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif; }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: linear-gradient(135deg, #f7fbff, #eef8f1); color: #111827; }
      main { width: min(440px, calc(100vw - 32px)); padding: 28px; border-radius: 28px; border: 1px solid rgba(255,255,255,.72); background: rgba(255,255,255,.74); box-shadow: 0 24px 80px rgba(17,24,39,.12); backdrop-filter: blur(28px); }
      h1 { margin: 0 0 8px; font-size: 28px; }
      p { margin: 0 0 18px; color: #4b5563; line-height: 1.45; }
      code { display: inline-block; padding: 4px 8px; border-radius: 999px; background: rgba(17,24,39,.08); }
    </style>
  </head>
  <body>
    <main>
      <h1>Progressa API</h1>
      <p>Deze service is actief en klaar voor de beveiligde Quantivita-koppeling.</p>
      <code>GET /healthz</code>
    </main>
  </body>
</html>`);
});

app.get('/healthz', (_request, response) => {
  response.json({
    ok: true,
    service: 'progressa-quantivita-api',
    publicBaseUrl,
    supabaseConfigured: Boolean(supabaseUrl && serviceRoleKey && supabaseAnonKey),
  });
});
app.get('/metrics', observability.metricsHandler);

app.get('/healthz/upstream', async (_request, response) => {
  if (!supabaseUrl || !serviceRoleKey) {
    response.status(500).json({ ok: false, error: 'Supabase is not configured' });
    return;
  }

  try {
    const healthResponse = await withTimeout(
      fetch(`${supabaseUrl}/auth/v1/health`, {
        headers: {
          apikey: supabaseAnonKey,
          accept: 'application/json',
        },
      }),
      upstreamTimeoutMs,
      'Supabase upstream timed out',
    );
    response.json({
      ok: healthResponse.ok,
      upstream: 'supabase',
      status: healthResponse.status,
    });
  } catch (error) {
    response.status(502).json({
      ok: false,
      upstream: 'supabase',
      error: safeError(error),
    });
  }
});

app.get('/quantivita/connect', (request, response) => {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(request.query || {})) {
    if (Array.isArray(value)) {
      for (const item of value) query.append(key, String(item));
    } else if (value != null) {
      query.set(key, String(value));
    }
  }
  const deepLink = `progressa://quantivita-connect?${query.toString()}`;
  response.type('html').send(`<!doctype html>
<html lang="nl">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Progressa koppelen</title>
    <style>
      :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif; }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: linear-gradient(135deg, #f6fbff, #eef7f1); color: #101822; }
      main { width: min(420px, calc(100vw - 32px)); padding: 28px; border: 1px solid rgba(255,255,255,.68); border-radius: 28px; background: rgba(255,255,255,.72); box-shadow: 0 24px 80px rgba(17, 24, 39, .12); backdrop-filter: blur(28px); }
      h1 { margin: 0 0 10px; font-size: 28px; letter-spacing: 0; }
      p { margin: 0 0 22px; color: #4b5563; line-height: 1.45; }
      a { display: block; padding: 15px 18px; border-radius: 18px; background: #111827; color: white; text-align: center; text-decoration: none; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <h1>Progressa koppelen</h1>
      <p>Open Progressa om Quantivita toestemming te geven je workouts veilig te lezen.</p>
      <a href="${escapeHtml(deepLink)}">Open Progressa</a>
    </main>
  </body>
</html>`);
});

app.post('/api/quantivita/mobile-code', async (request, response) => {
  const token = bearerToken(request);
  const user = await authenticatedUser(supabaseAdmin, token);
  if (!user) {
    response.status(401).json({ error: 'Invalid or expired access token' });
    return;
  }
  const userId = user.id;

  const scope = String(request.body?.scope || 'workouts:read');
  const refreshToken = String(request.body?.refreshToken || '');
  const code = createLinkCode({
    userId,
    accessToken: token,
    refreshToken,
    scope,
  });

  response.json({
    code,
    progressaUserId: userId,
    scope,
    expiresIn: 300,
  });
});

app.post('/api/observability/logs', (request, response) => {
  const userId = jwtSubject(bearerToken(request));
  request.body = {
    ...(request.body || {}),
    user_id_hash: userHash(userId),
  };
  observability.frontendLogHandler(request, response);
});

app.post('/api/quantivita/exchange-code', (request, response) => {
  try {
    const payload = readLinkCode(String(request.body?.code || ''));
    response.json({
      progressaUserId: payload.userId,
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken || null,
      scope: payload.scope,
      expiresAt: payload.expiresAt,
    });
  } catch {
    response.status(400).json({ error: 'Invalid or expired code' });
  }
});

app.post('/api/quantivita/refresh-token', async (request, response) => {
  const refreshToken = String(request.body?.refreshToken || '');
  if (!refreshToken) {
    response.status(400).json({ error: 'refreshToken is required' });
    return;
  }

  try {
    const remoteResponse = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST',
      signal: AbortSignal.timeout(upstreamTimeoutMs),
      headers: {
        apikey: supabaseAnonKey,
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
    const body = await remoteResponse.json().catch(() => ({}));
    if (!remoteResponse.ok || !body.access_token) {
      response.status(remoteResponse.status || 400).json({
        error: body.error_description || body.error || 'Token refresh failed',
      });
      return;
    }
    response.json({
      accessToken: body.access_token,
      refreshToken: body.refresh_token || refreshToken,
      expiresAt: body.expires_at || null,
    });
  } catch (error) {
    response.status(502).json({ error: `Token refresh failed: ${error.message}` });
  }
});

app.get('/api/users/:userId/workouts', async (request, response) => {
  const started = performance.now();
  const token = bearerToken(request);
  const user = await authenticatedUser(supabaseAdmin, token);
  if (!user) {
    response.status(401).json({ error: 'Invalid or expired access token' });
    return;
  }
  const tokenUserId = user.id;
  if (tokenUserId !== request.params.userId) {
    response.status(403).json({ error: 'Forbidden' });
    return;
  }

  if (request.query.metric === 'progress-index') {
    const { from, to } = request.query;
    if ([from, to].some(day => day != null && !/^\d{4}-\d{2}-\d{2}$/.test(day)) || (from && to && from > to)) {
      return response.status(400).json({ error: 'Invalid date range' });
    }
    const { data, error } = await supabaseAdmin.rpc('progress_index', {
      p_user_id: user.id, p_from: from || null, p_to: to || null,
    });
    if (error) return response.status(500).json({ error: 'Could not read Progress Index' });
    return response.json(data);
  }

  const limit = clampNumber(Number(request.query.limit || 50), 1, 200);
  const from = request.query.from ? String(request.query.from) : '';
  const to = request.query.to ? String(request.query.to) : '';
  const workoutId = request.query.workoutId ? String(request.query.workoutId) : '';
  const linkedOnly = String(request.query.linkedOnly || '').toLowerCase() === 'true';

  let workoutQuery = supabaseAdmin
    .from('workouts')
    .select('id, user_id, title, created_at, source, location')
    .eq('user_id', request.params.userId)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (workoutId) workoutQuery = workoutQuery.eq('id', workoutId);
  if (from) workoutQuery = workoutQuery.gte('created_at', from);
  if (to) workoutQuery = workoutQuery.lte('created_at', to);

  let workoutResult;
  try {
    workoutResult = await withTimeout(
      workoutQuery,
      upstreamTimeoutMs,
      'Supabase workout query timed out',
    );
  } catch (error) {
    response.status(504).json({ error: safeError(error) });
    return;
  }

  const { data: workouts, error: workoutError } = workoutResult;
  if (workoutError) {
    const details = safeError(workoutError);
    observability.log('error', 'supabase_query_failed', 'Progressa workout query failed', {
      correlation_id: request.correlationId,
      error_code: 'PROG-WORKOUT-001',
      user_id_hash: userHash(request.params.userId),
      metadata: {
        supabase_table: 'workouts',
        supabase_operation: 'select',
        cause: details,
      },
    });
    response.status(isAuthUpstreamError(workoutError) ? 401 : 500).json({
      error: 'Could not load Progressa workouts',
      details,
    });
    return;
  }

  const workoutIds = (workouts || []).map((workout) => String(workout.id));
  if (workoutIds.length === 0) {
    response.json({ workouts: [] });
    return;
  }

  let metadataResult;
  try {
    metadataResult = await withTimeout(
      supabaseAdmin
        .from('workout_health_metadata')
        .select('workout_id, activity_type, health_start, health_end, duration_secs, calories, distance_m, avg_heart_rate, max_heart_rate')
        .in('workout_id', workoutIds),
      upstreamTimeoutMs,
      'Supabase workout health-link query timed out',
    );
  } catch (error) {
    response.status(504).json({ error: safeError(error) });
    return;
  }
  if (metadataResult.error) {
    response.status(500).json({ error: 'Could not load Progressa health links', details: safeError(metadataResult.error) });
    return;
  }
  const healthLinks = new Map((metadataResult.data || []).map((row) => [String(row.workout_id), row]));
  const selectedWorkouts = linkedOnly
    ? (workouts || []).filter((workout) => healthLinks.has(String(workout.id)))
    : (workouts || []);
  const selectedWorkoutIds = selectedWorkouts.map((workout) => String(workout.id));
  if (selectedWorkoutIds.length === 0) {
    response.json({ workouts: [] });
    return;
  }

  let setResult;
  try {
    setResult = await withTimeout(
      supabaseAdmin
        .from('sets')
        .select(`
          id,
          user_id,
          workout_id,
          exercise_id,
          weight_kg,
          base_weight_kg,
          added_weight_kg,
          reps,
          rir,
          side,
          is_warmup,
          created_at,
          exercises:exercise_id ( id, name, weight_type, default_muscles ),
          workouts:workout_id ( id, title, created_at )
        `)
        .eq('user_id', request.params.userId)
        .in('workout_id', selectedWorkoutIds)
        .order('created_at', { ascending: true }),
      upstreamTimeoutMs,
      'Supabase set query timed out',
    );
  } catch (error) {
    response.status(504).json({ error: safeError(error) });
    return;
  }

  const { data: sets, error: setError } = setResult;

  if (setError) {
    const details = safeError(setError);
    observability.log('error', 'supabase_query_failed', 'Progressa workout detail query failed', {
      correlation_id: request.correlationId,
      error_code: 'PROG-WORKOUT-001',
      user_id_hash: userHash(request.params.userId),
      metadata: {
        supabase_table: 'sets',
        supabase_operation: 'select',
        cause: details,
      },
    });
    response.status(isAuthUpstreamError(setError) ? 401 : 500).json({
      error: 'Could not load Progressa workout details',
      details,
    });
    return;
  }

  const rows = (sets || []).map((row) => ({
    ...row,
    total_weight_kg: row.weight_kg,
    health_activity: healthLinks.get(String(row.workout_id)) || null,
  }));
  const workoutsWithoutSets = selectedWorkouts
    .filter((workout) => !rows.some((row) => row.workout_id === workout.id))
    .map((workout) => ({
      workouts: workout,
      workout_id: workout.id,
      health_activity: healthLinks.get(String(workout.id)) || null,
    }));

  observability.log('info', 'workout_sync_completed', 'Progressa workouts loaded for Quantivita', {
    correlation_id: request.correlationId,
    error_code: null,
    user_id_hash: userHash(request.params.userId),
    duration_ms: performance.now() - started,
    metadata: {
      workout_count: selectedWorkoutIds.length,
      set_row_count: rows.length,
    },
  });
  response.json({ workouts: [...rows, ...workoutsWithoutSets] });
});

app.listen(port, '0.0.0.0', () => {
  observability.log('info', 'service_started', `Progressa Quantivita API listening on ${port}`, {
    error_code: null,
    metadata: { port },
  });
});

function bearerToken(request) {
  const header = request.get('authorization') || '';
  const [scheme, token] = header.split(' ');
  return scheme?.toLowerCase() === 'bearer' ? token : '';
}

function jwtSubject(token) {
  return jwtPayload(token).sub || '';
}

function jwtPayload(token) {
  try {
    const [, payloadText] = String(token || '').split('.');
    if (!payloadText) return {};
    const payload = JSON.parse(Buffer.from(payloadText, 'base64url').toString('utf8'));
    return payload && typeof payload === 'object' ? payload : {};
  } catch {
    return {};
  }
}

function createLinkCode({ userId, accessToken, refreshToken, scope }) {
  const issuedAt = Date.now();
  const payload = {
    userId,
    accessToken,
    refreshToken,
    scope,
    issuedAt,
    expiresAt: issuedAt + 5 * 60 * 1000,
  };
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(payload), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [
    iv.toString('base64url'),
    tag.toString('base64url'),
    encrypted.toString('base64url'),
  ].join('.');
}

function readLinkCode(code) {
  const fingerprint = crypto.createHash('sha256').update(String(code || '')).digest('hex');
  const now = Date.now();
  for (const [hash, expiresAt] of consumedLinkCodes) {
    if (expiresAt < now) consumedLinkCodes.delete(hash);
  }
  if (consumedLinkCodes.has(fingerprint)) throw new Error('Link code already used');
  const [ivText, tagText, encryptedText] = String(code || '').split('.');
  if (!ivText || !tagText || !encryptedText) throw new Error('Invalid link code');
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    key(),
    Buffer.from(ivText, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
  const payload = JSON.parse(
    Buffer.concat([
      decipher.update(Buffer.from(encryptedText, 'base64url')),
      decipher.final(),
    ]).toString('utf8'),
  );
  if (!payload.userId || !payload.accessToken || payload.expiresAt < Date.now()) {
    throw new Error('Expired link code');
  }
  consumedLinkCodes.set(fingerprint, payload.expiresAt);
  return payload;
}

function key() {
  return crypto.createHash('sha256').update(linkSecret).digest();
}

function clampNumber(value, min, max) {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, Math.round(value)));
}

function withTimeout(promise, timeoutMs, message) {
  let timeout;
  const timer = new Promise((_, reject) => {
    timeout = setTimeout(() => reject(new Error(message)), timeoutMs);
  });
  return Promise.race([promise, timer]).finally(() => clearTimeout(timeout));
}

function safeError(error) {
  const message =
    error instanceof Error
      ? error.message
      : error && typeof error === 'object'
        ? [error.message, error.details, error.hint, error.code].filter(Boolean).join(' ')
        : String(error || '');
  if (!message) return 'Upstream request failed';
  return message.replace(/Bearer\s+[A-Za-z0-9._~+/-]+=*/gi, 'Bearer [redacted]');
}

function isAuthUpstreamError(error) {
  const message = safeError(error).toLowerCase();
  const status = Number(error?.status || error?.statusCode || 0);
  const code = String(error?.code || '').toLowerCase();
  return (
    status === 401 ||
    code === 'pgrst301' ||
    message.includes('jwt') ||
    message.includes('token') ||
    message.includes('unauthorized')
  );
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
