import express from 'express';
import { canonicalWorkouts, previewMerge, createMerge } from './workout-merges.js';
import crypto from 'node:crypto';
import cookieParser from 'cookie-parser';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';
import { mkdir, readFile, writeFile, rm, rename } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createObservability, userHash } from './observability.js';
import { openapiDocument, swaggerHtml } from './openapi.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const port = Number(process.env.PORT || 8080);
const dataDir = process.env.QUANTIVITA_DATA_DIR || path.join(__dirname, '..', 'data');
const appleClientId = process.env.APPLE_WEB_CLIENT_ID || '';
const publicBaseUrl = process.env.QUANTIVITA_PUBLIC_BASE_URL || `http://localhost:${port}`;
const sessionSecret = process.env.QUANTIVITA_SESSION_SECRET || 'dev-change-me';
if (process.env.NODE_ENV === 'production' && sessionSecret === 'dev-change-me') {
  throw new Error('QUANTIVITA_SESSION_SECRET must be configured in production');
}
const progressaApiBaseUrl = process.env.PROGRESSA_API_BASE_URL || '';
const stravaClientId = process.env.STRAVA_CLIENT_ID || '';
const stravaClientSecret = process.env.STRAVA_CLIENT_SECRET || '';
const stravaRedirectUri = process.env.STRAVA_REDIRECT_URI || 'quantivita://quantivita.app/strava-auth';
const stravaApiBaseUrl = process.env.STRAVA_API_BASE_URL || 'https://www.strava.com';
const mcpSessions = new Map();
const mcpSdkTransports = new Map();
const oauthClients = new Map();
const oauthCodes = new Map();
const MCP_HISTORY_DAYS = 365;
const appleJwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
const appleStates = new Set();
const observability = createObservability({
  app: 'quantivita',
  service: 'api',
  environment: process.env.NODE_ENV || 'production',
});

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(observability.requestMiddleware);
app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/openapi.json', (_request, response) => response.json(openapiDocument(publicBaseUrl)));
app.get('/docs', (_request, response) => response.type('html').send(swaggerHtml()));

app.get('/healthz', (_request, response) => {
  response.json({ ok: true, service: 'quantivita-server' });
});
app.get('/metrics', observability.metricsHandler);

app.all('/progressa/*', proxyProgressaRequest);
app.post('/mcp', handleMcpSdk);
app.get('/mcp', handleMcpSdk);
app.delete('/mcp', handleMcpSdk);
app.post('/mcp-v2', handleMcpSdk);
app.get('/mcp-v2', handleMcpSdk);
app.delete('/mcp-v2', handleMcpSdk);
app.get('/sse', handleMcpSse);
app.post('/mcp/message', handleMcpSseMessage);
app.get('/.well-known/oauth-authorization-server', oauthAuthorizationServerMetadata);
app.get('/.well-known/oauth-protected-resource', oauthProtectedResourceMetadata);
app.get('/.well-known/oauth-protected-resource/mcp', oauthProtectedResourceMetadata);
app.get('/.well-known/oauth-protected-resource/mcp-v2', oauthProtectedResourceMetadata);
app.post('/oauth/register', oauthRegisterClient);
app.get('/oauth/authorize', oauthAuthorizePage);
app.post('/oauth/authorize', oauthAuthorizeSubmit);
app.post('/oauth/token', oauthToken);

app.get('/api/auth/config', (_request, response) => {
  response.json({ appleEnabled: Boolean(appleClientId) });
});

app.get('/auth/apple/start', (_request, response) => {
  if (!appleClientId) {
    response.redirect(`/login.html?error=${encodeURIComponent('Apple web login is not configured on the homeserver.')}`);
    return;
  }

  const state = crypto.randomBytes(16).toString('hex');
  response.cookie('qv_apple_state', state, sessionCookieOptions(10 * 60 * 1000));
  appleStates.add(state);
  setTimeout(() => appleStates.delete(state), 10 * 60 * 1000).unref();

  const url = new URL('https://appleid.apple.com/auth/authorize');
  url.searchParams.set('client_id', appleClientId);
  url.searchParams.set('redirect_uri', `${publicBaseUrl}/auth/apple/callback`);
  url.searchParams.set('response_type', 'code id_token');
  url.searchParams.set('response_mode', 'form_post');
  url.searchParams.set('scope', 'email');
  url.searchParams.set('state', state);
  response.redirect(url.toString());
});

app.post('/auth/apple/callback', async (request, response) => {
  try {
    const state = request.body?.state || '';
    const cookieState = request.cookies?.qv_apple_state;
    const stateIsValid = Boolean(state) && (state === cookieState || appleStates.has(state));
    appleStates.delete(state);
    if (!stateIsValid) {
      response.redirect(`/?error=${encodeURIComponent('Apple login state check failed. Please try again.')}`);
      return;
    }

    const idToken = request.body?.id_token;
    const { payload } = await jwtVerify(idToken, appleJwks, {
      issuer: 'https://appleid.apple.com',
      audience: appleClientId,
    });
    const accountId = accountIdForAppleSubject(payload.sub);
    const accounts = await readAccounts();
    if (!accounts[safeAccountId(accountId)]) {
      response.redirect(`/?error=${encodeURIComponent('No synced Quantivita data found for this Apple ID yet. Open the iPhone app and sync Quantivita API first.')}`);
      return;
    }

    response.clearCookie('qv_apple_state');
    response.cookie('qv_session', signSession(accountId), sessionCookieOptions(30 * 24 * 60 * 60 * 1000));
    const afterLogin = String(request.cookies?.qv_after_login || '');
    response.clearCookie('qv_after_login');
    response.redirect(safeAfterLoginPath(afterLogin) || '/');
  } catch (error) {
    response.redirect(`/?error=${encodeURIComponent(`Apple login failed: ${error.message}`)}`);
  }
});

app.get('/api/me/session', (request, response) => {
  const accountId = accountIdFromSession(request);
  response.json({ signedIn: Boolean(accountId), accountId });
});

app.get('/api/me/health', async (request, response) => {
  const accountId = accountIdFromSession(request);
  if (!accountId) {
    response.status(401).json({ error: 'Unauthorized' });
    return;
  }
  response.json(withCalibratedStrain(await readUserData(accountId)));
});

app.get('/api/me/progressa/workouts', async (request, response) => {
  const accountId = accountIdFromSession(request);
  if (!accountId) {
    response.status(401).json({ error: 'Unauthorized' });
    return;
  }
  await sendProgressaWorkouts(accountId, request, response);
});

app.get('/api/me/export.csv', async (request, response) => {
  const accountId = accountIdFromSession(request);
  if (!accountId) {
    response.status(401).json({ error: 'Unauthorized' });
    return;
  }
  const data = withCalibratedStrain(await readUserData(accountId));
  response.type('text/csv').send(csvFor(data));
});

app.post('/api/logout', (_request, response) => {
  response.clearCookie('qv_session');
  response.json({ ok: true });
});

app.post('/api/accounts/register', async (request, response) => {
  const { accountId, syncToken, appleLinked } = request.body || {};
  if (!accountId || !syncToken) {
    response.status(400).json({ error: 'accountId and syncToken are required' });
    return;
  }

  const accounts = await readAccounts();
  const existing = accounts[safeAccountId(accountId)];
  const tokenHash = hashToken(syncToken);
  if (existing && existing.tokenHash !== tokenHash) {
    response.status(409).json({ error: 'Account is already registered with a different sync token' });
    return;
  }
  accounts[safeAccountId(accountId)] = {
    ...(existing || {}),
    accountId,
    tokenHash,
    appleLinked: Boolean(appleLinked),
    updatedAt: new Date().toISOString(),
  };
  await writeAccounts(accounts);
  response.status(202).json({ ok: true, accountId, appleLinked: Boolean(appleLinked) });
});

app.post('/api/accounts/login', async (request, response) => {
  const { accountId, syncToken } = request.body || {};
  if (!(await isAuthorized(accountId, syncToken))) {
    response.status(401).json({ error: 'Invalid account id or sync token' });
    return;
  }
  response.cookie('qv_session', signSession(accountId), sessionCookieOptions(30 * 24 * 60 * 60 * 1000));
  response.json({ ok: true, accountId });
});

app.use('/api/users/:accountId', async (request, response, next) => {
  const token = bearerToken(request);
  if (!(await isAuthorized(request.params.accountId, token))) {
    response.status(401).json({ error: 'Unauthorized' });
    return;
  }
  next();
});

app.delete('/api/users/:accountId', async (request, response) => {
  const { accountId } = request.params;
  const accounts = await readAccounts();
  delete accounts[safeAccountId(accountId)];
  await writeAccounts(accounts);
  await rm(path.join(dataDir, `${safeAccountId(accountId)}.json`), { force: true });
  await rm(path.join(dataDir, `${safeAccountId(accountId)}.merges.json`), { force: true });
  response.status(204).end();
});

const mergeLocks = new Map();
async function withMergeLock(accountId, operation) {
  const previous = mergeLocks.get(accountId) || Promise.resolve();
  const pending = previous.catch(() => {}).then(operation);
  mergeLocks.set(accountId, pending);
  try { return await pending; }
  finally { if (mergeLocks.get(accountId) === pending) mergeLocks.delete(accountId); }
}
async function readMerges(accountId) {
  try { return JSON.parse(await readFile(path.join(dataDir, `${safeAccountId(accountId)}.merges.json`), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
}
async function writeMerges(accountId, merges) {
  await mkdir(dataDir, { recursive: true });
  const file = path.join(dataDir, `${safeAccountId(accountId)}.merges.json`);
  await writeFile(`${file}.tmp`, JSON.stringify(merges));
  await rename(`${file}.tmp`, file);
}
async function readUserData(accountId) {
  const data = await readRawUserData(accountId);
  return { ...data, workouts: canonicalWorkouts(data.workouts || [], await readMerges(accountId)) };
}
async function mergeState(accountId) {
  const data = await readUserData(accountId);
  const historicParts = new Set((await readMerges(accountId)).flatMap(m => m.sourceWorkoutIds));
  const workouts = data.workouts.filter(w => w.merge || w.duplicateSources?.length > 1 || historicParts.has(w.id));
  return { workouts, hiddenWorkoutIds: workouts.flatMap(w => w.merge?.sourceWorkoutIds || w.duplicateSources.map(s => s.id)) };
}
app.get('/api/users/:accountId/workout-merges', async (req, res) => {
  try { res.json(await mergeState(req.params.accountId)); }
  catch (error) { res.status(500).json({ error: error.message }); }
});
app.post('/api/users/:accountId/workout-merges/preview', async (req, res) => {
  try {
    const data = await readUserData(req.params.accountId);
    res.json(previewMerge(data.workouts, req.body.workoutIds, req.body.strategy));
  } catch (error) { res.status(400).json({ error: error.message }); }
});
app.post('/api/users/:accountId/workout-merges', async (req, res) => {
  try {
    await withMergeLock(req.params.accountId, async () => {
      const data = await readRawUserData(req.params.accountId);
      const merges = await readMerges(req.params.accountId);
      const merge = createMerge(data.workouts, merges, req.body.workoutIds, req.body.strategy || 'concatenate', req.params.accountId);
      if (!merges.some(m => m.id === merge.id)) await writeMerges(req.params.accountId, [...merges, merge]);
    });
    res.json(await mergeState(req.params.accountId));
  } catch (error) { res.status(400).json({ error: error.message }); }
});
app.post('/api/users/:accountId/workout-merges/:mergeId/undo', async (req, res) => {
  try {
    await withMergeLock(req.params.accountId, async () => {
      const merges = await readMerges(req.params.accountId);
      const merge = merges.find(m => m.id === req.params.mergeId);
      if (!merge) throw new Error('Combination not found.');
      if (!merge.undoneAt) { merge.undoneAt = new Date().toISOString(); await writeMerges(req.params.accountId, merges); }
    });
    res.json(await mergeState(req.params.accountId));
  } catch (error) { res.status(400).json({ error: error.message }); }
});

app.get('/api/users/:accountId/health', async (request, response) => {
  response.json(withCalibratedStrain(await readUserData(request.params.accountId)));
});

app.get('/api/users/:accountId/summary', async (request, response) => {
  const data = withCalibratedStrain(await readUserData(request.params.accountId));
  response.json(summaryFor(data));
});

app.get('/api/users/:accountId/health/debug/daily', async (request, response) => {
  const data = withCalibratedStrain(await readUserData(request.params.accountId));
  const date = request.query.date || [...(data.daily || [])].at(-1)?.date;
  response.json(debugDailyFor(data, date));
});

app.get('/api/users/:accountId/workouts', async (request, response) => {
  const data = await readUserData(request.params.accountId);
  response.json(workoutsInRange(data.workouts || [], request.query));
});

app.post('/api/users/:accountId/integrations/progressa/connect', async (request, response) => {
  const { progressaUserId, accessToken, refreshToken } = request.body || {};
  if (!progressaUserId || !accessToken) {
    response.status(400).json({ error: 'progressaUserId and accessToken are required' });
    return;
  }

  const result = await saveProgressaConnection(request.params.accountId, {
    progressaUserId,
    accessToken,
    refreshToken,
  });
  if (!result.ok) {
    response.status(result.status).json({ error: result.error });
    return;
  }

  response.status(202).json({ ok: true, progressa: result.progressa });
});

app.post('/api/users/:accountId/integrations/progressa/exchange', async (request, response) => {
  const { code } = request.body || {};
  if (!code) {
    response.status(400).json({ error: 'code is required' });
    return;
  }
  if (!progressaApiBaseUrl) {
    response.status(503).json({
      error: 'PROGRESSA_API_BASE_URL is not configured on the Quantivita homeserver',
    });
    return;
  }

  try {
    const remoteResponse = await fetch(new URL('/api/quantivita/exchange-code', progressaApiBaseUrl), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: JSON.stringify({ code }),
    });
    const body = await remoteResponse.json().catch(() => ({}));
    if (!remoteResponse.ok || !body.progressaUserId || !body.accessToken) {
      response.status(remoteResponse.status || 400).json({
        error: body.error || 'Progressa code exchange failed',
      });
      return;
    }

    const result = await saveProgressaConnection(request.params.accountId, {
      progressaUserId: body.progressaUserId,
      accessToken: body.accessToken,
      refreshToken: body.refreshToken,
    });
    if (!result.ok) {
      response.status(result.status).json({ error: result.error });
      return;
    }

    response.status(202).json({ ok: true, progressa: result.progressa });
  } catch (error) {
    response.status(502).json({ error: `Progressa code exchange failed: ${error.message}` });
  }
});

app.get('/api/users/:accountId/integrations/progressa', async (request, response) => {
  const accounts = await readAccounts();
  const progressa = accounts[safeAccountId(request.params.accountId)]?.progressa;
  if (!progressa?.accessToken || !progressa?.userId) {
    response.json({ connected: false });
    return;
  }

  const data = await readUserData(request.params.accountId);
  response.json({
    ...publicProgressaIntegration(progressa),
    ...(data.integrations?.progressa || {}),
  });
});

app.delete('/api/users/:accountId/integrations/progressa', async (request, response) => {
  const accounts = await readAccounts();
  const key = safeAccountId(request.params.accountId);
  const account = accounts[key];
  if (account?.progressa) {
    const { progressa: _progressa, ...rest } = account;
    accounts[key] = { ...rest, updatedAt: new Date().toISOString() };
    await writeAccounts(accounts);
  }

  const data = await readRawUserData(request.params.accountId);
  const integrations = { ...(data.integrations || {}) };
  delete integrations.progressa;
  await writeUserData(request.params.accountId, {
    ...data,
    updatedAt: new Date().toISOString(),
    integrations,
  });
  response.json({ ok: true });
});

app.get('/api/users/:accountId/integrations/progressa/progress-index', async (request, response) => {
  try { response.json(await progressIndex(request.params.accountId, request.query)); }
  catch (error) { response.status(error.status || 502).json({error: error.message}); }
});

app.get('/api/users/:accountId/integrations/progressa/workouts', async (request, response) => {
  await sendProgressaWorkouts(request.params.accountId, request, response);
});

app.get('/api/users/:accountId/integrations/strava', async (request, response) => {
  const accounts = await readAccounts();
  const strava = accounts[safeAccountId(request.params.accountId)]?.strava;
  if (!strava?.refreshToken && !strava?.accessToken) {
    response.json({ connected: false, canUpload: false, needsReauthorization: false });
    return;
  }
  const scopes = normalizeStravaScopes(strava.scopes);
  try {
    const tokenValid = Boolean(await validStravaAccessToken(request.params.accountId));
    const canUpload = tokenValid && scopes.includes('activity:write');
    response.json({ connected: tokenValid, canUpload, needsReauthorization: tokenValid && !canUpload, scopes });
  } catch {
    response.json({ connected: false, canUpload: false, needsReauthorization: true, scopes });
  }
});

app.get('/api/users/:accountId/integrations/strava/authorize-url', (request, response) => {
  if (!stravaClientId || !stravaClientSecret) {
    response.status(503).json({ error: 'Strava is not configured' });
    return;
  }
  const state = String(request.query.state || '');
  if (!state) {
    response.status(400).json({ error: 'OAuth state is required' });
    return;
  }
  const url = new URL('/oauth/authorize', stravaApiBaseUrl);
  url.searchParams.set('client_id', stravaClientId);
  url.searchParams.set('redirect_uri', stravaRedirectUri);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('approval_prompt', 'force');
  url.searchParams.set('scope', 'read,activity:write');
  url.searchParams.set('state', state);
  response.json({ url: url.toString() });
});

app.post('/api/users/:accountId/integrations/strava/exchange', async (request, response) => {
  if (!stravaClientId || !stravaClientSecret || !request.body?.code) {
    response.status(400).json({ error: 'Strava exchange is not configured or code is missing' });
    return;
  }
  const scopes = normalizeStravaScopes(request.body?.scope);
  if (!scopes.includes('activity:write')) {
    response.status(403).json({ error: 'Strava activity upload permission was not granted. Reconnect and allow activity access.' });
    return;
  }
  const remote = await fetchWithTimeout(new URL('/oauth/token', stravaApiBaseUrl), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      client_id: stravaClientId,
      client_secret: stravaClientSecret,
      code: String(request.body.code),
      grant_type: 'authorization_code',
    }),
  });
  const body = await remote.json().catch(() => ({}));
  if (!remote.ok || !body.access_token) {
    response.status(remote.status || 502).json({ error: body.message || 'Strava exchange failed' });
    return;
  }
  const accounts = await readAccounts();
  const key = safeAccountId(request.params.accountId);
  accounts[key] = {
    ...accounts[key],
    strava: {
      accessToken: encryptSecret(body.access_token),
      refreshToken: encryptSecret(body.refresh_token || ''),
      expiresAt: Number(body.expires_at || 0),
      athleteId: body.athlete?.id || null,
      scopes,
      connectedAt: new Date().toISOString(),
    },
    updatedAt: new Date().toISOString(),
  };
  await writeAccounts(accounts);
  response.status(202).json({ connected: true });
});

app.delete('/api/users/:accountId/integrations/strava', async (request, response) => {
  const key = safeAccountId(request.params.accountId);
  let remotelyRevoked = true;
  try {
    const accessToken = await validStravaAccessToken(key);
    if (accessToken) {
      const remote = await fetchWithTimeout(new URL('/oauth/deauthorize', stravaApiBaseUrl), {
        method: 'POST',
        headers: { authorization: `Bearer ${accessToken}` },
      });
      remotelyRevoked = remote.ok;
    }
  } catch {
    remotelyRevoked = false;
  }
  const accounts = await readAccounts();
  if (accounts[key]) {
    const { strava: _strava, ...account } = accounts[key];
    accounts[key] = { ...account, updatedAt: new Date().toISOString() };
    await writeAccounts(accounts);
  }
  response.json({ ok: true, remotelyRevoked });
});

app.post('/api/users/:accountId/integrations/strava/upload', async (request, response) => {
  try {
    const accounts = await readAccounts();
    const key = safeAccountId(request.params.accountId);
    if (!normalizeStravaScopes(accounts[key]?.strava?.scopes).includes('activity:write')) {
      response.status(403).json({ error: 'Reconnect Strava and grant activity upload permission' });
      return;
    }
    const accessToken = await validStravaAccessToken(request.params.accountId);
    if (!accessToken) {
      response.status(409).json({ error: 'Connect Strava before uploading' });
      return;
    }
    const tcx = String(request.body?.tcx || '');
    if (!tcx || tcx.length > 2_000_000) {
      response.status(400).json({ error: 'A valid TCX payload is required' });
      return;
    }
    const form = new FormData();
    form.set('name', String(request.body?.name || 'Quantivita merged workout'));
    form.set('description', 'Merged workout uploaded by Quantivita.');
    form.set('data_type', 'tcx');
    form.set('external_id', String(request.body?.externalId || `quantivita-${Date.now()}.tcx`));
    form.set('file', new Blob([tcx], { type: 'application/vnd.garmin.tcx+xml' }), 'quantivita-merged.tcx');
    const remote = await fetchWithTimeout(new URL('/api/v3/uploads', stravaApiBaseUrl), {
      method: 'POST', headers: { authorization: `Bearer ${accessToken}` }, body: form,
    });
    const body = await remote.json().catch(() => ({}));
    if (!remote.ok || body.error) {
      response.status(remote.status || 502).json({ error: body.message || 'Strava upload failed' });
      return;
    }
    const uploadId = body.id == null ? null : String(body.id);
    if (uploadId) {
      const accounts = await readAccounts();
      const key = safeAccountId(request.params.accountId);
      const strava = accounts[key]?.strava;
      if (strava) {
        accounts[key].strava = {
          ...strava,
          uploads: {
            ...(strava.uploads || {}),
            [uploadId]: { createdAt: new Date().toISOString() },
          },
        };
        await writeAccounts(accounts);
      }
    }
    response.status(202).json({ ok: true, uploadId });
  } catch (error) {
    response.status(502).json({ error: `Strava upload failed: ${error.message}` });
  }
});

app.get('/api/users/:accountId/integrations/strava/uploads/:uploadId', async (request, response) => {
  try {
    const accounts = await readAccounts();
    const key = safeAccountId(request.params.accountId);
    const uploadId = String(request.params.uploadId || '');
    if (!accounts[key]?.strava?.uploads?.[uploadId]) {
      response.status(404).json({ error: 'Unknown Strava upload' });
      return;
    }
    const accessToken = await validStravaAccessToken(key);
    if (!accessToken) {
      response.status(409).json({ error: 'Connect Strava before checking an upload' });
      return;
    }
    const remote = await fetchWithTimeout(new URL(`/api/v3/uploads/${encodeURIComponent(uploadId)}`, stravaApiBaseUrl), {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    const body = await remote.json().catch(() => ({}));
    if (remote.status === 404) {
      response.json({ state: 'processing', activityId: null, error: null });
      return;
    }
    if (!remote.ok) {
      response.status(remote.status || 502).json({ error: body.message || 'Strava upload status failed' });
      return;
    }
    const state = body.error ? 'failed' : body.activity_id ? 'ready' : 'processing';
    response.json({ state, activityId: body.activity_id == null ? null : String(body.activity_id), error: body.error || null });
  } catch (error) {
    response.status(502).json({ error: `Strava upload status failed: ${error.message}` });
  }
});

app.get('/api/users/:accountId/export.csv', async (request, response) => {
  const data = withCalibratedStrain(await readUserData(request.params.accountId));
  response.type('text/csv').send(csvFor(data));
});

app.post('/api/users/:accountId/ingest', async (request, response) => {
  const started = performance.now();
  const current = await readRawUserData(request.params.accountId);
  const incoming = normalizePayload(request.body);
  const next = {
    accountId: request.params.accountId,
    updatedAt: new Date().toISOString(),
    profile: { ...current.profile, ...incoming.profile },
    daily: mergeByDate(current.daily, incoming.daily),
    workouts: mergeById(current.workouts, incoming.workouts),
    integrations: { ...current.integrations, ...incoming.integrations },
  };
  await writeUserData(request.params.accountId, next);
  observability.log('info', 'sync_job_completed', 'Quantivita ingest completed', {
    correlation_id: request.correlationId,
    error_code: null,
    user_id_hash: userHash(request.params.accountId),
    duration_ms: performance.now() - started,
    metadata: {
      daily_count: incoming.daily.length,
      workout_count: incoming.workouts.length,
      progressa_workout_count: incoming.workouts.filter((workout) => workout.source === 'progressa').length,
    },
  });
  response.status(202).json({ ok: true, summary: summaryFor(await readUserData(request.params.accountId)) });
});

app.post('/api/users/:accountId/observability/logs', (request, response) => {
  request.body = {
    ...(request.body || {}),
    user_id_hash: userHash(request.params.accountId),
  };
  observability.frontendLogHandler(request, response);
});

app.listen(port, '0.0.0.0', () => {
  observability.log('info', 'service_started', `Quantivita server listening on ${port}`, {
    error_code: null,
    metadata: { port },
  });
});

async function handleMcpSdk(request, response) {
  if (!originAllowed(request)) {
    response.status(403).json({ error: 'Origin is not allowed' });
    return;
  }

  const sessionId = request.get('mcp-session-id') || '';
  let transport = sessionId ? mcpSdkTransports.get(sessionId) : null;
  const message = request.body || {};
  if (!transport && message.method && message.method !== 'initialize') {
    const auth = await authForMcpMessage(request, message);
    if (!auth.ok && mcpMethodRequiresAuth(message.method)) {
      mcpAuthError(response, auth);
      return;
    }
    const result = await handleMcpMessage(message, auth.accountId);
    if (result.sessionId) response.set('Mcp-Session-Id', result.sessionId);
    response
      .type('text/event-stream')
      .send(`event: message\ndata: ${JSON.stringify(result.body)}\n\n`);
    return;
  }
  if (!transport) {
    const auth = await mcpAuthContext(request);
    const server = createQuantivitaMcpServer(auth.ok ? auth.accountId : '');
    transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => crypto.randomUUID(),
      onsessioninitialized: (newSessionId) => {
        mcpSdkTransports.set(newSessionId, transport);
      },
    });
    transport.onclose = () => {
      if (transport.sessionId) mcpSdkTransports.delete(transport.sessionId);
    };
    await server.connect(transport);
  }

  await transport.handleRequest(request, response, request.body);
}

function createQuantivitaMcpServer(accountId) {
  const server = new McpServer(
    { name: 'quantivita-healthdata', version: '0.2.0' },
    { capabilities: { tools: {} } },
  );

  server.registerTool(
    'search',
    {
      title: 'Search Quantivita healthdata',
      description:
        'Search Quantivita health documents by keyword, metric, date, workout, sleep, strain, readiness, recovery, or Progressa exercise details.',
      inputSchema: { query: z.string() },
      outputSchema: searchOutputZodSchema(),
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    async ({ query }) => {
      if (!accountId) return mcpAuthRequiredToolResult();
      return mcpToolOutput(normalizeSearchResult(searchHealthDocuments(
        withCalibratedStrain(await readUserData(accountId)),
        { query },
      )));
    },
  );

  server.registerTool(
    'fetch',
    {
      title: 'Fetch Quantivita health document',
      description: 'Fetch a full Quantivita health document by id returned from search.',
      inputSchema: { id: z.string() },
      outputSchema: fetchOutputZodSchema(),
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    async ({ id }) => {
      if (!accountId) return mcpAuthRequiredToolResult();
      return mcpToolOutput(normalizeFetchDocument(fetchHealthDocument(
        withCalibratedStrain(await readUserData(accountId)),
        id,
      )));
    },
  );

  server.registerTool(
    'get_workouts',
    {
      title: 'Get workouts',
      description: 'Get workouts from the last 30 days by default. Set all=true or provide from/to to retrieve older history.',
      inputSchema: {
        from: z.string().optional(),
        to: z.string().optional(),
        all: z.boolean().optional(),
        limit: z.number().int().positive().optional(),
      },
      outputSchema: { workouts: z.array(z.record(z.string(), z.unknown())) },
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    async (args) => {
      if (!accountId) return mcpAuthRequiredToolResult();
      return mcpToolOutput(workoutsForMcp(withCalibratedStrain(await readUserData(accountId)), args));
    },
  );

  server.registerTool('get_progress_index', {
    title: 'Progress Index',
    description: 'Compare the best estimated 1RM on the first and last logged days per exercise. Dates are inclusive UTC workout dates.',
    inputSchema: { from: z.string().optional(), to: z.string().optional() },
    annotations: { readOnlyHint: true, destructiveHint: false },
  }, async args => accountId ? mcpToolOutput(await progressIndex(accountId, args)) : mcpAuthRequiredToolResult());

  server.registerTool(
    'get_workout_details',
    {
      title: 'Get workout details',
      description:
        'Get one complete Quantivita or Progressa workout, including exercises, sets, reps, weight, RIR, side, warm-up status, and volume.',
      inputSchema: { workoutId: z.string() },
      outputSchema: { workout: z.record(z.string(), z.unknown()) },
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    async ({ workoutId }) => {
      if (!accountId) return mcpAuthRequiredToolResult();
      return mcpToolOutput(workoutDetailsForMcp(
        withCalibratedStrain(await readUserData(accountId)),
        workoutId,
      ));
    },
  );

  server.registerTool(
    'get_weight_history',
    {
      title: 'Get weight history',
      description:
        'Get body weight (kg) history entries by date. Set range to 7d/30d/90d/180d/365d, or provide from/to. Returns all history by default.',
      inputSchema: {
        from: z.string().optional(),
        to: z.string().optional(),
        range: z.enum(['7d', '30d', '90d', '180d', '365d']).optional(),
        limit: z.number().int().positive().optional(),
      },
      outputSchema: weightHistoryOutputZodSchema(),
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    async (args) => {
      if (!accountId) return mcpAuthRequiredToolResult();
      return mcpToolOutput(weightHistoryForMcp(withCalibratedStrain(await readUserData(accountId)), args));
    },
  );

  return server;
}

function mcpAuthRequiredToolResult() {
  return {
    content: [{ type: 'text', text: 'Authentication required.' }],
    _meta: {
      'mcp/www_authenticate': `Bearer realm="Quantivita MCP", resource_metadata="${publicBaseUrl}/.well-known/oauth-protected-resource/mcp"`,
    },
    isError: true,
  };
}

function searchOutputZodSchema() {
  return {
    results: z.array(z.object({
      id: z.string(),
      title: z.string(),
      url: z.string(),
    })),
  };
}

function fetchOutputZodSchema() {
  return {
    id: z.string(),
    title: z.string(),
    text: z.string(),
    url: z.string(),
    metadata: z.record(z.string(), z.string()).optional(),
  };
}

function weightHistoryOutputZodSchema() {
  return {
    entries: z.array(z.object({ date: z.string(), bodyMassKg: z.number() })),
    unit: z.string(),
    count: z.number(),
    latestKg: z.number().nullable(),
    changeKg: z.number().nullable(),
  };
}

async function handleMcpPost(request, response) {
  if (!originAllowed(request)) {
    response.status(403).json({ error: 'Origin is not allowed' });
    return;
  }
  const message = request.body || {};
  if (!message.id && message.method) {
    response.sendStatus(202);
    return;
  }
  const auth = await authForMcpMessage(request, message);
  if (!auth.ok && mcpMethodRequiresAuth(message.method)) {
    mcpAuthError(response, auth);
    return;
  }
  const result = await handleMcpMessage(message, auth.accountId);
  if (result.sessionId) response.set('Mcp-Session-Id', result.sessionId);
  response.type('application/json').json(result.body);
}

async function handleMcpSse(request, response) {
  if (!originAllowed(request)) {
    response.sendStatus(403);
    return;
  }
  const auth = await mcpAuthContext(request);

  const sessionId = crypto.randomUUID();
  response.writeHead(200, {
    'content-type': 'text/event-stream',
    'cache-control': 'no-cache, no-transform',
    connection: 'keep-alive',
  });
  const endpoint = `${publicBaseUrl}/mcp/message?sessionId=${encodeURIComponent(sessionId)}`;
  response.write(`event: endpoint\ndata: ${endpoint}\n\n`);
  mcpSessions.set(sessionId, {
    accountId: auth.ok ? auth.accountId : '',
    response,
    createdAt: Date.now(),
  });
  request.on('close', () => mcpSessions.delete(sessionId));
}

async function handleMcpSseMessage(request, response) {
  const session = mcpSessions.get(String(request.query.sessionId || ''));
  if (!session) {
    response.status(404).json({ error: 'Unknown MCP session' });
    return;
  }
  const auth = await mcpAuthContext(request);
  if (auth.ok && session.accountId && auth.accountId !== session.accountId) {
    mcpAuthError(response, { status: 403, error: 'Forbidden' });
    return;
  }
  if (!auth.ok && bearerToken(request)) {
    mcpAuthError(response, auth);
    return;
  }
  const message = request.body || {};
  if (mcpMethodRequiresAuth(message.method) && !auth.ok && !session.accountId) {
    session.response.write(`event: message\ndata: ${JSON.stringify(mcpError(message.id ?? null, -32001, 'Authentication required'))}\n\n`);
    response.sendStatus(202);
    return;
  }
  if (auth.ok && !session.accountId) session.accountId = auth.accountId;
  if (message.id && message.method) {
    const result = await handleMcpMessage(message, auth.ok ? auth.accountId : session.accountId);
    session.response.write(`event: message\ndata: ${JSON.stringify(result.body)}\n\n`);
  }
  response.sendStatus(202);
}

async function handleMcpMessage(message, accountId) {
  const id = message.id ?? null;
  try {
    if (message.jsonrpc !== '2.0' || !message.method) {
      return { body: mcpError(id, -32600, 'Invalid JSON-RPC request') };
    }

    switch (message.method) {
      case 'initialize': {
        const sessionId = crypto.randomUUID();
        return {
          sessionId,
          body: mcpResult(id, {
            protocolVersion: message.params?.protocolVersion || '2024-11-05',
            capabilities: {
              tools: {},
            },
            serverInfo: {
              name: 'quantivita-healthdata',
              version: '0.2.0',
            },
            instructions:
              'Read-only Quantivita healthdata MCP. Use search to find relevant days or workouts, then fetch by id for full detail.',
          }),
        };
      }
      case 'ping':
        return { body: mcpResult(id, {}) };
      case 'tools/list':
        return { body: mcpResult(id, { tools: mcpTools() }) };
      case 'tools/call':
        return { body: mcpResult(id, await callMcpTool(accountId, message.params || {})) };
      case 'resources/list':
        return { body: mcpResult(id, { resources: await mcpResources(accountId) }) };
      case 'resources/read':
        return {
          body: mcpResult(id, {
            contents: [await readMcpResource(accountId, String(message.params?.uri || ''))],
          }),
        };
      case 'prompts/list':
        return { body: mcpResult(id, { prompts: [] }) };
      default:
        return { body: mcpError(id, -32601, `Unsupported MCP method: ${message.method}`) };
    }
  } catch (error) {
    return { body: mcpError(id, -32000, error.message || 'MCP server error') };
  }
}

async function callMcpTool(accountId, params) {
  const name = String(params.name || '');
  const args = params.arguments || {};
  if (['search', 'quantivita_search', 'search_healthdata'].includes(name)) {
    return mcpToolOutput(normalizeSearchResult(searchHealthDocuments(withCalibratedStrain(await readUserData(accountId)), args)));
  }
  if (['fetch', 'quantivita_fetch', 'fetch_healthdata'].includes(name)) {
    return mcpToolOutput(normalizeFetchDocument(fetchHealthDocument(
      withCalibratedStrain(await readUserData(accountId)),
      String(args.id || ''),
    )));
  }
  if (name === 'get_latest_summary') {
    const data = withCalibratedStrain(await readUserData(accountId));
    return mcpToolOutput(normalizeFetchDocument(healthSummaryDocument(data)));
  }
  if (name === 'get_daily_health') {
    const data = withCalibratedStrain(await readUserData(accountId));
    return mcpToolOutput(normalizeFetchDocument(fetchHealthDocument(data, `daily:${String(args.date || '').slice(0, 10)}`)));
  }
  if (name === 'get_workouts') {
    const data = withCalibratedStrain(await readUserData(accountId));
    return mcpToolOutput(workoutsForMcp(data, args));
  }
  if (name === 'get_progress_index') return mcpToolOutput(await progressIndex(accountId, args));
  if (name === 'get_workout_details') {
    const data = withCalibratedStrain(await readUserData(accountId));
    return mcpToolOutput(workoutDetailsForMcp(data, String(args.workoutId || '')));
  }
  if (name === 'get_weight_history') {
    const data = withCalibratedStrain(await readUserData(accountId));
    return mcpToolOutput(weightHistoryForMcp(data, args));
  }
  throw new Error(`Unknown MCP tool: ${name}`);
}

function mcpTools() {
  return [
    {
      name: 'search',
      title: 'Search Quantivita healthdata',
      description:
        'Search Quantivita health documents by keyword, metric, date, workout, sleep, strain, readiness, recovery, or Progressa exercise details.',
      inputSchema: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Natural language search query.' },
        },
        required: ['query'],
        additionalProperties: false,
      },
      outputSchema: searchOutputSchema(),
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    {
      name: 'fetch',
      title: 'Fetch Quantivita health document',
      description: 'Fetch a full Quantivita health document by id returned from search.',
      inputSchema: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'Document id, such as summary:latest, daily:2026-06-05, or workout:<id>.' },
        },
        required: ['id'],
        additionalProperties: false,
      },
      outputSchema: fetchOutputSchema(),
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    {
      name: 'get_workouts',
      title: 'Get workouts',
      description: 'Get workouts from the last 30 days by default. Set all=true or provide from/to to retrieve older history.',
      inputSchema: {
        type: 'object',
        properties: {
          from: { type: 'string', format: 'date-time' },
          to: { type: 'string', format: 'date-time' },
          all: { type: 'boolean', description: 'Return all stored workouts, regardless of age.' },
          limit: { type: 'integer', minimum: 1 },
        },
        additionalProperties: false,
      },
      outputSchema: {
        type: 'object',
        properties: { workouts: { type: 'array', items: { type: 'object', additionalProperties: true } } },
        required: ['workouts'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    {
      name: 'get_progress_index', title: 'Progress Index',
      description: 'Compare estimated strength by exercise over an inclusive logged date range.',
      inputSchema: {type: 'object', properties: {from: {type: 'string', format: 'date'}, to: {type: 'string', format: 'date'}}, additionalProperties: false},
      annotations: {readOnlyHint: true, destructiveHint: false},
    },
    {
      name: 'get_workout_details',
      title: 'Get workout details',
      description:
        'Get one complete Quantivita or Progressa workout, including exercises, sets, reps, weight, RIR, side, warm-up status, and volume.',
      inputSchema: {
        type: 'object',
        properties: {
          workoutId: {
            type: 'string',
            description: 'Workout id, external Progressa id, or document id such as workout:progressa:<id>.',
          },
        },
        required: ['workoutId'],
        additionalProperties: false,
      },
      outputSchema: {
        type: 'object',
        properties: { workout: { type: 'object', additionalProperties: true } },
        required: ['workout'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    {
      name: 'get_weight_history',
      title: 'Get weight history',
      description:
        'Get body weight (kg) history entries by date. Set range to 7d/30d/90d/180d/365d, or provide from/to. Returns all history by default.',
      inputSchema: {
        type: 'object',
        properties: {
          from: { type: 'string', format: 'date-time' },
          to: { type: 'string', format: 'date-time' },
          range: { type: 'string', enum: ['7d', '30d', '90d', '180d', '365d'] },
          limit: { type: 'integer', minimum: 1 },
        },
        additionalProperties: false,
      },
      outputSchema: {
        type: 'object',
        properties: {
          entries: {
            type: 'array',
            items: {
              type: 'object',
              properties: { date: { type: 'string' }, bodyMassKg: { type: 'number' } },
              required: ['date', 'bodyMassKg'],
              additionalProperties: false,
            },
          },
          unit: { type: 'string' },
          count: { type: 'number' },
          latestKg: { type: ['number', 'null'] },
          changeKg: { type: ['number', 'null'] },
        },
        required: ['entries', 'unit', 'count', 'latestKg', 'changeKg'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
  ];
}

async function mcpResources(accountId) {
  const data = withCalibratedStrain(await readUserData(accountId));
  const latestDate = latestDaily(data)?.date;
  return [
    {
      uri: 'healthdata://summary/latest',
      name: 'Latest Quantivita summary',
      description: 'Latest readiness, sleep, strain, activity, and workout summary.',
      mimeType: 'application/json',
    },
    ...(latestDate
      ? [{
          uri: `healthdata://daily/${latestDate}`,
          name: `Quantivita daily health ${latestDate}`,
          description: 'Latest daily health metrics.',
          mimeType: 'application/json',
        }]
      : []),
  ];
}

async function readMcpResource(accountId, uri) {
  const data = withCalibratedStrain(await readUserData(accountId));
  if (uri === 'healthdata://summary/latest') {
    return {
      uri,
      mimeType: 'application/json',
      text: JSON.stringify(healthSummaryDocument(data), null, 2),
    };
  }
  const dailyMatch = uri.match(/^healthdata:\/\/daily\/(\d{4}-\d{2}-\d{2})$/);
  if (dailyMatch) {
    return {
      uri,
      mimeType: 'application/json',
      text: JSON.stringify(fetchHealthDocument(data, `daily:${dailyMatch[1]}`), null, 2),
    };
  }
  throw new Error(`Unknown resource: ${uri}`);
}

function searchHealthDocuments(data, args) {
  const query = String(args.query || '').trim().toLowerCase();
  const limit = clampNumber(Number(args.limit || 10), 1, 25);
  const docs = [
    healthSummaryDocument(data),
    ...dailyDocuments(data),
    ...workoutDocuments(data, {}),
  ];
  const terms = query.split(/\s+/).filter(Boolean);
  const scored = docs
    .map((doc) => ({ doc, score: scoreHealthDocument(doc, terms, query) }))
    .filter((item) => item.score > 0 || !terms.length)
    .sort((a, b) => b.score - a.score || String(b.doc.metadata?.date || '').localeCompare(String(a.doc.metadata?.date || '')))
    .slice(0, limit)
    .map(({ doc }) => ({ id: doc.id, title: doc.title, url: doc.url }));
  return { results: scored };
}

function fetchHealthDocument(data, id) {
  const docs = [
    healthSummaryDocument(data),
    ...dailyDocuments(data),
    ...workoutDocuments(data, {}),
  ];
  const doc = docs.find((item) => item.id === id);
  const missingDailyMatch = String(id || '').match(/^daily:(\d{4}-\d{2}-\d{2})$/);
  if (!doc && missingDailyMatch) return missingDailyDocument(data, missingDailyMatch[1]);
  if (!doc) throw new Error(`Health document not found: ${id}`);
  return doc;
}

function normalizeSearchResult(result) {
  return {
    results: (result.results || []).map((item) => ({
      id: String(item.id || ''),
      title: String(item.title || ''),
      url: String(item.url || publicBaseUrl),
    })),
  };
}

function normalizeFetchDocument(doc) {
  return {
    id: String(doc.id || ''),
    title: String(doc.title || ''),
    text: String(doc.text || ''),
    url: String(doc.url || publicBaseUrl),
    metadata: stringifyMetadata(doc.metadata || {}),
  };
}

function stringifyMetadata(metadata) {
  return Object.fromEntries(Object.entries(metadata)
    .filter(([key, value]) => key && value !== undefined && value !== null)
    .map(([key, value]) => [String(key), typeof value === 'string' ? value : JSON.stringify(value)]));
}

function healthSummaryDocument(data) {
  const daily = latestDaily(data);
  const recentDaily = [...(data.daily || [])]
    .filter((day) => day?.date)
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, MCP_HISTORY_DAYS);
  const workouts = [...(data.workouts || [])]
    .sort((a, b) => numericTime(b.startTime || b.date) - numericTime(a.startTime || a.date))
    .slice(0, MCP_HISTORY_DAYS);
  return {
    id: 'summary:latest',
    title: 'Latest Quantivita health summary',
    text: JSON.stringify({
      updatedAt: data.updatedAt,
      profile: data.profile || {},
      latestDaily: daily || null,
      recentDaily,
      quantivitaCoverage: quantivitaCoverageFor(data, daily),
      aggregates: healthAggregates(data),
      recentWorkouts: workouts.map(enrichedWorkoutForMcp),
      integrations: data.integrations || {},
    }, null, 2),
    url: `${publicBaseUrl}/mcp/docs/summary/latest`,
    metadata: {
      source: 'quantivita',
      type: 'summary',
      historyDays: MCP_HISTORY_DAYS,
      updatedAt: data.updatedAt || null,
      latestDate: daily?.date || null,
      workoutCount: Array.isArray(data.workouts) ? data.workouts.length : 0,
    },
  };
}

function dailyDocuments(data) {
  const days = [...(data.daily || [])].filter((day) => day?.date);
  return days.map((day, index) => {
    const dayWorkouts = (data.workouts || [])
      .filter((workout) => localDate(workout.startTime || workout.date) === day.date)
      .map(enrichedWorkoutForMcp);
    const previousDays = days.slice(Math.max(0, index - 7), index);
    const nextDays = days.slice(index + 1, index + 4);
    const workoutOverview = workoutAggregate(dayWorkouts);
    return {
      id: `daily:${day.date}`,
      title: `Quantivita daily health ${day.date}`,
      text: JSON.stringify({
        day,
        quantivitaCoverage: quantivitaCoverageFor(data, day),
        missingDays: missingDailyDates(days),
        workoutOverview: {
          ...workoutOverview,
          workoutIdsForFetch: dayWorkouts.map((workout) => `workout:${workout.id}`),
          summary: workoutOverview.count
            ? `${workoutOverview.count} workout(s), ${workoutOverview.totalDurationMinutes} min, ${workoutOverview.totalDistanceKm} km, ${workoutOverview.totalEnergyKcal} kcal`
            : 'No workouts recorded for this date',
        },
        workouts: dayWorkouts,
        trainingLoad: trainingLoadForDay(day, dayWorkouts),
        trends: trendContextForDay(days, index),
        context: {
          previous7Days: previousDays,
          next3Days: nextDays,
          rolling7Day: dailyWindowAggregate(previousDays.concat([day])),
        },
      }, null, 2),
      url: `${publicBaseUrl}/mcp/docs/daily/${encodeURIComponent(day.date)}`,
      metadata: {
        source: 'quantivita',
        type: 'daily',
        date: day.date,
        readiness: day.readinessScore ?? day.recoveryScore ?? day.readiness ?? null,
        sleep: day.sleepScore ?? day.sleep ?? null,
        strain: day.strainScore ?? day.strain ?? null,
        workoutCount: dayWorkouts.length,
      },
    };
  });
}

function missingDailyDocument(data, date) {
  const days = [...(data.daily || [])].filter((day) => day?.date);
  const previousDays = days.filter((day) => day.date < date).slice(-7);
  const nextDays = days.filter((day) => day.date > date).slice(0, 3);
  return {
    id: `daily:${date}`,
    title: `Quantivita daily health ${date} (missing)`,
    text: JSON.stringify({
      day: { date, available: false },
      quantivitaCoverage: quantivitaCoverageFor(data, { date }),
      missingDays: missingDailyDates(days).includes(date)
        ? missingDailyDates(days)
        : [...missingDailyDates(days), date].sort(),
      workoutOverview: {
        count: 0,
        totalDurationMinutes: 0,
        totalEnergyKcal: 0,
        totalDistanceKm: 0,
        workoutIdsForFetch: [],
        summary: 'No daily health row found for this date',
      },
      workouts: [],
      trainingLoad: trainingLoadForDay({ date }, []),
      trends: {
        previous7: dailyWindowAggregate(previousDays),
        previous30: dailyWindowAggregate(days.filter((day) => day.date < date).slice(-30)),
        deltasVsPrevious7: {},
      },
      context: {
        previous7Days: previousDays,
        next3Days: nextDays,
        rolling7Day: dailyWindowAggregate(previousDays),
      },
    }, null, 2),
    url: `${publicBaseUrl}/mcp/docs/daily/${encodeURIComponent(date)}`,
    metadata: {
      source: 'quantivita',
      type: 'daily',
      date,
      available: false,
      workoutCount: 0,
    },
  };
}

function workoutDocuments(data, args) {
  const from = args.from
    ? numericTime(String(args.from))
    : args.all ? Number.NEGATIVE_INFINITY : Date.now() - 30 * 86_400_000;
  const to = args.to ? numericTimeEndOfDay(String(args.to)) : Number.POSITIVE_INFINITY;
  return [...(data.workouts || [])]
    .filter((workout) => {
      const time = numericTime(workout.startTime || workout.date || '');
      return !Number.isFinite(time) || (time >= from && time <= to);
    })
    .map((workout) => ({
      id: `workout:${workout.id}`,
      title: `${workout.source === 'progressa' ? 'Progressa' : 'Quantivita'} ${workoutDisplayTitle(workout)} ${workout.startTime || workout.date || ''}`.trim(),
      text: JSON.stringify(enrichedWorkoutForMcp(workout), null, 2),
      url: `${publicBaseUrl}/mcp/docs/workout/${encodeURIComponent(workout.id)}`,
      metadata: {
        source: workout.source || 'quantivita',
        type: 'workout',
        date: String(workout.startTime || workout.date || '').slice(0, 10),
        workoutType: workout.workoutType || workout.type || workout.typeCode || null,
        durationMinutes: workout.durationMinutes ?? null,
        energyKcal: workout.energyKcal ?? null,
        avgPowerWatts: workout.avgPowerWatts ?? null,
        avgCadenceRpm: workout.avgCadenceRpm ?? null,
        averageHeartRate: Number(workout.averageHeartRate) > 0 ? Number(workout.averageHeartRate) : null,
        combinedSourceCount: workout.merge?.sources.length ?? null,
        progressaSetCount: workout.progressaDetails?.totalSets ?? null,
        progressaVolumeKg: workout.progressaDetails?.totalVolumeKg ?? null,
      },
    }));
}

function workoutsInRange(workouts, args = {}) {
  const from = args.from
    ? numericTime(String(args.from))
    : String(args.all || '') === 'true' ? Number.NEGATIVE_INFINITY : Date.now() - 30 * 86_400_000;
  const to = args.to ? numericTimeEndOfDay(String(args.to)) : Number.POSITIVE_INFINITY;
  return [...workouts]
    .filter((workout) => {
      const time = numericTime(workout.startTime || workout.date || '');
      return !Number.isFinite(time) || (time >= from && time <= to);
    })
    .sort((a, b) => numericTime(b.startTime || b.date || '') - numericTime(a.startTime || a.date || ''));
}

function workoutsForMcp(data, args = {}) {
  const docs = workoutDocuments(data, args);
  const selected = args.limit ? docs.slice(0, Number(args.limit)) : docs;
  return {
    workouts: selected.map((doc) => ({
      id: doc.id,
      title: doc.title,
      url: doc.url,
      metadata: doc.metadata,
    })),
  };
}

const WEIGHT_RANGE_DAYS = { '7d': 7, '30d': 30, '90d': 90, '180d': 180, '365d': 365 };

function weightHistoryForMcp(data, args = {}) {
  const entries = [...(data.daily || [])]
    .filter((day) => day?.date && Number.isFinite(Number(day.bodyMassKg)) && Number(day.bodyMassKg) > 0)
    .map((day) => ({ date: day.date, bodyMassKg: Number(day.bodyMassKg) }))
    .sort((a, b) => a.date.localeCompare(b.date));

  const rangeDays = WEIGHT_RANGE_DAYS[String(args.range || '')];
  const from = args.from
    ? numericTime(String(args.from))
    : rangeDays ? Date.now() - rangeDays * 86_400_000 : Number.NEGATIVE_INFINITY;
  const to = args.to ? numericTimeEndOfDay(String(args.to)) : Number.POSITIVE_INFINITY;

  const filtered = entries.filter((entry) => {
    const time = numericTime(entry.date);
    return !Number.isFinite(time) || (time >= from && time <= to);
  });
  const limited = args.limit ? filtered.slice(-Number(args.limit)) : filtered;

  const first = limited[0] || null;
  const latest = limited[limited.length - 1] || null;
  return {
    entries: limited,
    unit: 'kg',
    count: limited.length,
    latestKg: latest ? latest.bodyMassKg : null,
    changeKg: first && latest && limited.length > 1
      ? roundToOneDecimal(latest.bodyMassKg - first.bodyMassKg)
      : null,
  };
}

function compactWorkout(workout) {
  const progressaSetCount = Number(workout.progressaDetails?.totalSets || 0);
  const progressaExerciseCount = Number(workout.progressaDetails?.exerciseCount || 0);
  const progressaVolumeKg = Number(workout.progressaDetails?.totalVolumeKg || 0);
  const durationMinutes = Number(workout.durationMinutes ?? 0);
  const energyKcal = Number(workout.energyKcal ?? workout.activeEnergyKcal ?? 0);
  const effectiveDurationMinutes = durationMinutes > 0
    ? durationMinutes
    : workout.source === 'progressa'
      ? clamp(progressaSetCount * 2.5 + progressaExerciseCount * 4, 0, 180)
      : 0;
  const effectiveEnergyKcal = energyKcal > 0
    ? energyKcal
    : workout.source === 'progressa'
      ? clamp(effectiveDurationMinutes * 4.5 + progressaVolumeKg / 120, 0, 900)
      : 0;
  return {
    id: workout.id,
    source: workout.source || 'quantivita',
    startTime: workout.startTime || workout.date || null,
    durationMinutes,
    energyKcal: workout.energyAvailable === false || workout.energyKcal == null ? null : energyKcal,
    effectiveDurationMinutes: roundToOneDecimal(effectiveDurationMinutes),
    effectiveEnergyKcal: workout.energyAvailable === false ? null : roundToOneDecimal(effectiveEnergyKcal),
    distanceMeters: workout.distanceAvailable === false || workout.distanceMeters == null ? null : Number(workout.distanceMeters),
    averageHeartRate: Number(workout.averageHeartRate) > 0 ? Number(workout.averageHeartRate) : null,
    maxHeartRate: Number(workout.maxHeartRate) > 0 ? Number(workout.maxHeartRate) : null,
    avgPowerWatts: workout.avgPowerWatts ?? null, maxPowerWatts: workout.maxPowerWatts ?? null,
    avgCadenceRpm: workout.avgCadenceRpm ?? null, maxCadenceRpm: workout.maxCadenceRpm ?? null,
    normalizedPowerWatts: workout.normalizedPowerWatts ?? null,
    merge: workout.merge ?? null, duplicateSources: workout.duplicateSources ?? [],
    metricsNote: workout.metricsNote ?? null, elapsedDurationMinutes: workout.elapsedDurationMinutes ?? null,
    progressaDetails: workout.progressaDetails
      ? {
          exerciseCount: progressaExerciseCount,
          totalSets: progressaSetCount,
          totalVolumeKg: progressaVolumeKg,
        }
      : null,
  };
}

function enrichedWorkoutForMcp(workout) {
  const compact = compactWorkout(workout);
  return {
    ...workout,
    title: workoutDisplayTitle(workout),
    quantivitaDerived: {
      ...compact,
      localDate: localDate(workout.startTime || workout.date),
      startTimestampMs: numericTime(workout.startTime || workout.date),
      estimatedDurationMinutes: compact.effectiveDurationMinutes,
      estimatedEnergyKcal: compact.effectiveEnergyKcal,
      distanceKm: Number(workout.distanceMeters || 0) > 0
        ? roundToOneDecimal(Number(workout.distanceMeters) / 1000)
        : null,
      paceMinPerKm: paceMinPerKm(workout),
      kilometerSplits: kilometerSplitsForWorkout(workout),
      progressaStrength: workout.progressaDetails
        ? {
            exerciseCount: workout.progressaDetails.exerciseCount || 0,
            totalSets: workout.progressaDetails.totalSets || 0,
            totalVolumeKg: workout.progressaDetails.totalVolumeKg || 0,
            exercises: workout.progressaDetails.exercises || [],
          }
        : null,
    },
  };
}

function workoutDetailsForMcp(data, requestedId) {
  const id = String(requestedId || '').replace(/^workout:/, '');
  const comparableId = id.replace(/^progressa:/, '');
  const workout = (data.workouts || []).find((candidate) =>
    String(candidate.id || '') === id ||
    String(candidate.externalWorkoutId || '') === id ||
    String(candidate.id || '').replace(/^progressa:/, '') === comparableId,
  );
  if (!workout) throw new Error(`Workout not found: ${requestedId}`);
  return { workout: enrichedWorkoutForMcp(workout) };
}

function workoutDisplayTitle(workout) {
  const title = String(workout?.title || '').trim();
  if (title && !/^(workout|quantivita workout|healthkit workout|apple health workout)$/i.test(title)) {
    return title;
  }
  return activityTitleForCode(workout?.typeCode ?? workout?.workoutType ?? workout?.type)
    || title
    || 'Workout';
}

function activityTitleForCode(value) {
  switch (Math.round(Number(value || 0))) {
    case 1: return 'Running';
    case 2: return 'Walking';
    case 3: return 'Cycling';
    case 4: return 'Swimming';
    case 5: return 'Strength Training';
    case 6: return 'HIIT';
    case 7: return 'Yoga';
    case 8: return 'Hiking';
    case 9: return 'Elliptical';
    case 10: return 'Rowing';
    case 11: return 'Rock Climbing';
    case 12: return 'Pilates';
    case 13: return 'Dance';
    case 14: return 'Stair Climbing';
    case 15: return 'Tennis';
    case 16: return 'Soccer';
    case 17: return 'Basketball';
    case 18: return 'Core Training';
    case 19: return 'Paddling';
    default: return '';
  }
}

function trainingLoadForDay(day, workouts) {
  const strain = Number(day.strainScore ?? day.strain ?? 0);
  const aggregate = workoutAggregate(workouts);
  const cardiovascularLoad = workouts.reduce((sum, workout) => {
    const compact = compactWorkout(workout);
    const duration = Number(compact.effectiveDurationMinutes || 0);
    const resting = Number(day.restingHeartBpm || 60);
    const maxHr = Number(workout.maxHeartRate || day.maxHeartBpm || 190);
    const reserve = Math.max(maxHr - resting, 1);
    const avg = Number(workout.averageHeartRate || 0);
    const reservePercent = avg > 0
      ? (avg - resting) / reserve
      : estimatedReserveFromEnergy(Number(compact.effectiveEnergyKcal || 0), duration);
    return sum + duration * strainZoneWeight(reservePercent);
  }, 0);
  return {
    strain,
    strainLabel: day.strainLabel || strainBandForPercent(strain),
    strainRawScore: day.strainRawScore ?? null,
    strainLoad: day.strainLoad ?? null,
    cardiovascularLoad: roundToOneDecimal(cardiovascularLoad),
    workoutLoad: aggregate,
    interpretation:
      strain >= 95
        ? 'exceptional daily load'
        : strain >= 80
          ? 'high but not capped-out daily load'
          : strain >= 55
            ? 'moderate training load'
            : 'light training load',
  };
}

function trendContextForDay(days, index) {
  const previous7Days = days.slice(Math.max(0, index - 7), index);
  const previous30Days = days.slice(Math.max(0, index - 30), index);
  const current = days[index] || {};
  const previous7 = dailyWindowAggregate(previous7Days);
  const previous30 = dailyWindowAggregate(previous30Days);
  return {
    previous7,
    previous30,
    deltasVsPrevious7: {
      recovery: delta(Number(current.recoveryScore ?? current.readinessScore ?? current.readiness), previous7.avgRecovery),
      sleepScore: delta(Number(current.sleepScore ?? current.sleep), previous7.avgSleepScore),
      strain: delta(Number(current.strainScore ?? current.strain), previous7.avgStrain),
      hrvMs: delta(Number(current.hrvMs), previous7.avgHrvMs),
      restingHeartBpm: delta(Number(current.restingHeartBpm), previous7.avgRestingHeartBpm),
    },
  };
}

function healthAggregates(data) {
  const daily = [...(data.daily || [])].filter((day) => day?.date);
  const workouts = Array.isArray(data.workouts) ? data.workouts : [];
  return {
    dailyCount: daily.length,
    workoutCount: workouts.length,
    latest7Days: dailyWindowAggregate(daily.slice(-7)),
    latest30Days: dailyWindowAggregate(daily.slice(-30)),
    workoutsLatest30Days: workoutAggregate(workouts.filter((workout) => {
      const time = numericTime(workout.startTime || workout.date);
      return time && time >= Date.now() - 30 * 24 * 60 * 60 * 1000;
    })),
    progressa: {
      workoutCount: workouts.filter((workout) => workout.source === 'progressa').length,
      totalSets: workouts.reduce((sum, workout) => sum + Number(workout.progressaDetails?.totalSets || 0), 0),
      totalVolumeKg: roundToOneDecimal(workouts.reduce(
        (sum, workout) => sum + Number(workout.progressaDetails?.totalVolumeKg || 0),
        0,
      )),
    },
  };
}

function dailyWindowAggregate(days) {
  const rows = days.filter(Boolean);
  return {
    count: rows.length,
    avgRecovery: average(rows.map((day) => day.recoveryScore ?? day.readinessScore ?? day.readiness)),
    avgSleepScore: average(rows.map((day) => day.sleepScore ?? day.sleep)),
    avgStrain: average(rows.map((day) => day.strainScore ?? day.strain)),
    avgHrvMs: average(rows.map((day) => day.hrvMs)),
    avgRestingHeartBpm: average(rows.map((day) => day.restingHeartBpm)),
    totalSleepMinutes: roundToOneDecimal(rows.reduce((sum, day) => sum + Number(day.sleepMinutes || 0), 0)),
    totalSteps: Math.round(rows.reduce((sum, day) => sum + Number(day.steps || 0), 0)),
    totalActiveEnergyKcal: Math.round(rows.reduce((sum, day) => sum + Number(day.activeEnergyKcal || 0), 0)),
  };
}

function workoutAggregate(workouts) {
  return {
    count: workouts.length,
    missingEnergyCount: workouts.filter(w => w.energyAvailable === false || w.energyKcal == null).length,
    missingDistanceCount: workouts.filter(w => w.distanceAvailable === false || w.distanceMeters == null).length,
    totalsNote: 'Totals include available canonical measurements only; missing values are not measured zeroes.',
    totalDurationMinutes: roundToOneDecimal(workouts.reduce((sum, workout) => {
      const compact = compactWorkout(workout);
      return sum + Number(compact.effectiveDurationMinutes || 0);
    }, 0)),
    totalEnergyKcal: Math.round(workouts.reduce((sum, workout) => {
      const compact = compactWorkout(workout);
      return sum + Number(compact.effectiveEnergyKcal || 0);
    }, 0)),
    totalDistanceKm: roundToOneDecimal(workouts.reduce((sum, workout) => sum + Number(workout.distanceMeters || 0), 0) / 1000),
  };
}

function delta(value, baselineValue) {
  if (!Number.isFinite(value) || !Number.isFinite(Number(baselineValue))) return null;
  return roundToOneDecimal(value - Number(baselineValue));
}

function strainBandForPercent(percent) {
  if (percent >= 95) return 'Very high';
  if (percent >= 80) return 'High';
  if (percent >= 55) return 'Moderate';
  if (percent >= 24) return 'Light';
  return 'Restorative';
}

function average(values) {
  const numbers = values.map(Number).filter((value) => Number.isFinite(value) && value > 0);
  if (!numbers.length) return null;
  return roundToOneDecimal(numbers.reduce((sum, value) => sum + value, 0) / numbers.length);
}

function paceMinPerKm(workout) {
  const distanceKm = Number(workout.distanceMeters || 0) / 1000;
  const duration = Number(workout.durationMinutes || 0);
  if (distanceKm <= 0 || duration <= 0) return null;
  return roundToOneDecimal(duration / distanceKm);
}

function numericTimeEndOfDay(value) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(value))) return numericTime(String(value) + 'T23:59:59.999Z');
  return numericTime(value);
}

function numericTime(value) {
  if (!value) return 0;
  if (typeof value === 'number') {
    return value < 1000000000000 ? value * 1000 : value;
  }
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? parsed : 0;
}

function latestDaily(data) {
  return [...(data.daily || [])].filter((day) => day?.date).sort((a, b) => b.date.localeCompare(a.date))[0] || null;
}

function scoreHealthDocument(doc, terms, query) {
  const haystack = `${doc.id} ${doc.title} ${doc.text} ${JSON.stringify(doc.metadata || {})}`.toLowerCase();
  if (!terms.length) return 1;
  let score = 0;
  if (query && haystack.includes(query)) score += 10;
  for (const term of terms) {
    if (haystack.includes(term)) score += 2;
  }
  if (doc.metadata?.type === 'summary') score += 1;
  return score;
}

function quantivitaCoverageFor(data, day = null) {
  const selectedDay = day || latestDaily(data) || {};
  const workouts = Array.isArray(data.workouts) ? data.workouts : [];
  const dayWorkouts = selectedDay?.date
    ? workouts.filter((workout) => localDate(workout.startTime || workout.date) === selectedDay.date)
    : [];
  const nutrition = nutritionHydrationForDay(selectedDay, dayWorkouts);
  return {
    vo2Max: vo2MaxFor(data, selectedDay, dayWorkouts),
    bodyBattery: bodyBatteryForDay(data, selectedDay, dayWorkouts),
    kilometerSplits: kilometerSplitCoverage(dayWorkouts),
    missingDays: missingDayCoverage(data),
    nutrition,
    hydration: nutrition.hydration,
  };
}

function vo2MaxFor(data, day, workouts) {
  const value = firstNumeric(
    day?.vo2Max,
    day?.vo2max,
    day?.vo2MaxMlKgMin,
    day?.cardioFitness,
    data.profile?.vo2Max,
    data.profile?.vo2max,
    ...workouts.flatMap((workout) => [
      workout.vo2Max,
      workout.vo2max,
      workout.vo2MaxMlKgMin,
      workout.cardioFitness,
    ]),
  );
  return {
    value,
    unit: 'ml/kg/min',
    available: value !== null,
    source: value === null ? null : 'synced',
    note: value === null ? 'No explicit VO2max field was found in the synced Quantivita data.' : null,
  };
}

function bodyBatteryForDay(data, day, workouts) {
  const explicit = firstNumeric(day?.bodyBattery, day?.bodyBatteryScore, day?.energyReserveScore);
  if (explicit !== null) {
    return {
      value: Math.round(clamp(explicit, 0, 100)),
      available: true,
      source: 'synced',
      inputs: { explicit: true },
      note: null,
    };
  }

  const daily = Array.isArray(data.daily) ? data.daily : [];
  const hrvValues = daily.map((row) => Number(row.hrvMs || 0)).filter((value) => value > 0);
  const rhrValues = daily.map((row) => Number(row.restingHeartBpm || 0)).filter((value) => value > 0);
  const sleepValues = daily.map((row) => Number(row.sleepMinutes || 0)).filter((value) => value > 0);
  const baselines = {
    hrvMs: baseline(hrvValues),
    restingHeartBpm: baseline(rhrValues),
    sleepMinutes: baseline(sleepValues),
  };
  const sleepScore = sleepScoreFor(day || {}, baselines.sleepMinutes.median);
  const recovery = Number(day?.recoveryScore ?? day?.readinessScore ?? day?.readiness);
  const recoveryScore = Number.isFinite(recovery) && recovery > 0
    ? Math.round(clamp(recovery, 0, 100))
    : recoveryDebugFor(day || {}, baselines, sleepScore, workouts).score;
  const strainPercent = Number((day?.strainScore ?? day?.strain ?? calibratedStrainForDay(day || {}, workouts).percent) || 0);
  const stressScore = Math.round(clamp(Number(day?.stressScore ?? day?.stress ?? day?.stressAverage ?? 20), 0, 100));
  const activeEnergyKcal = Number(day?.activeEnergyKcal || 0);
  const steps = Number(day?.steps || 0);
  const activityDrain = clamp(activeEnergyKcal / 18, 0, 28);
  const stepDrain = clamp((steps / 12000) * 8, 0, 10);
  const strainDrain = clamp(strainPercent * 0.32, 0, 34);
  const stressDrain = clamp(stressScore * 0.22, 0, 24);
  const restCharge = stressScore <= 12 ? 8 : stressScore <= 20 ? 3 : 0;
  const value = Math.round(clamp(
    recoveryScore * 0.7 + sleepScore * 0.3 - activityDrain - stepDrain - strainDrain - stressDrain + restCharge,
    0,
    100,
  ));
  return {
    value,
    available: true,
    source: 'estimated',
    inputs: {
      recoveryScore,
      sleepScore,
      strainPercent: roundToOneDecimal(strainPercent),
      stressScore,
      activeEnergyKcal,
      steps,
    },
    factors: [
      { label: 'Recovery charge', points: roundToOneDecimal(recoveryScore * 0.7) },
      { label: 'Sleep charge', points: roundToOneDecimal(sleepScore * 0.3) },
      { label: 'Active burn drain', points: -roundToOneDecimal(activityDrain) },
      { label: 'Movement drain', points: -roundToOneDecimal(stepDrain) },
      { label: 'Strain drain', points: -roundToOneDecimal(strainDrain) },
      { label: 'Stress drain', points: -roundToOneDecimal(stressDrain) },
      ...(restCharge > 0 ? [{ label: 'Low-stress recharge', points: restCharge }] : []),
    ],
    note: 'Estimated by Quantivita from recovery/readiness, sleep, HRV/RHR-derived recovery, strain, stress, active energy, steps, and workouts; not a Garmin Body Battery field.',
  };
}

function nutritionHydrationForDay(day, workouts) {
  const dietaryEnergyKcal = Number(day?.dietaryEnergyKcal || 0);
  const dietaryWaterMl = Number(day?.dietaryWaterMl || 0);
  const dietaryCarbohydratesG = Number(day?.dietaryCarbohydratesG || 0);
  const dietaryProteinG = Number(day?.dietaryProteinG || 0);
  const dietaryFatG = Number(day?.dietaryFatG || 0);
  const activeEnergyKcal = Number(day?.activeEnergyKcal || 0);
  const workoutMinutes = workouts.reduce((sum, workout) => sum + Number(compactWorkout(workout).effectiveDurationMinutes || 0), 0);
  const waterBaseTargetMl = 2500;
  const waterActivityExtraMl = activeEnergyKcal * 0.35;
  const waterWorkoutExtraMl = workoutMinutes * 8;
  const waterTargetMl = Math.round(clamp(waterBaseTargetMl + waterActivityExtraMl + waterWorkoutExtraMl, 2000, 4500));
  const nutritionAvailable = [dietaryEnergyKcal, dietaryCarbohydratesG, dietaryProteinG, dietaryFatG].some((value) => value > 0);
  const hydrationAvailable = dietaryWaterMl > 0;
  return {
    available: nutritionAvailable,
    dietaryEnergyKcal,
    dietaryCarbohydratesG,
    dietaryProteinG,
    dietaryFatG,
    netEnergyKcal: Math.round(dietaryEnergyKcal - activeEnergyKcal),
    note: nutritionAvailable ? null : 'Nutrition fields are present but empty or zero for this day.',
    hydration: {
      available: hydrationAvailable,
      dietaryWaterMl,
      waterTargetMl,
      waterBaseTargetMl,
      waterActivityExtraMl: Math.round(waterActivityExtraMl),
      waterWorkoutExtraMl: Math.round(waterWorkoutExtraMl),
      note: hydrationAvailable ? null : 'Hydration/water field is present but empty or zero for this day.',
    },
  };
}

function kilometerSplitCoverage(workouts) {
  const workoutSplits = workouts.map(kilometerSplitsForWorkout);
  const availableWorkouts = workoutSplits.filter((split) => split.available).length;
  return {
    available: availableWorkouts > 0,
    workoutCount: workouts.length,
    availableWorkoutCount: availableWorkouts,
    workouts: workoutSplits,
    note: availableWorkouts > 0
      ? null
      : 'No per-kilometer split series was found. Quantivita exposes workout distance/pace and any synced route flags, but cannot reconstruct exact kilometer splits without split or route samples.',
  };
}

function kilometerSplitsForWorkout(workout) {
  const explicit = Array.isArray(workout.kilometerSplits)
    ? workout.kilometerSplits
    : Array.isArray(workout.splits)
      ? workout.splits
      : Array.isArray(workout.laps)
        ? workout.laps
        : [];
  const splits = explicit.map((split, index) => ({
    kilometer: Number(split.kilometer ?? split.km ?? index + 1),
    durationSeconds: numericOrNull(split.durationSeconds ?? split.seconds ?? split.elapsedSeconds),
    paceMinPerKm: numericOrNull(split.paceMinPerKm ?? split.pace),
    distanceMeters: numericOrNull(split.distanceMeters ?? split.distance_m ?? split.distance),
  }));
  const hasRoute = Boolean(workout.hasRoute || workout.routePointCount || workout.routeSegments);
  return {
    workoutId: String(workout.id || ''),
    available: splits.length > 0,
    source: splits.length > 0 ? 'synced' : null,
    splits,
    hasRoute,
    routePointCount: numericOrNull(workout.routePointCount),
    note: splits.length > 0
      ? null
      : 'No kilometer split field was synced for this workout.',
  };
}

function missingDayCoverage(data) {
  const dates = missingDailyDates(data.daily || []);
  return {
    available: true,
    count: dates.length,
    dates,
    note: dates.length ? 'These calendar dates are absent between the first and latest synced daily rows.' : null,
  };
}

function missingDailyDates(days) {
  const dates = [...new Set((days || []).map((day) => day?.date).filter(Boolean))].sort();
  if (dates.length < 2) return [];
  const missing = [];
  const current = new Date(`${dates[0]}T00:00:00Z`);
  const end = new Date(`${dates.at(-1)}T00:00:00Z`);
  const present = new Set(dates);
  while (current < end) {
    current.setUTCDate(current.getUTCDate() + 1);
    const date = current.toISOString().slice(0, 10);
    if (!present.has(date) && date < dates.at(-1)) missing.push(date);
  }
  return missing;
}

function firstNumeric(...values) {
  for (const value of values) {
    const number = numericOrNull(value);
    if (number !== null && number > 0) return number;
  }
  return null;
}

function mcpToolOutput(structuredContent) {
  return {
    structuredContent,
    content: [{ type: 'text', text: JSON.stringify(structuredContent) }],
  };
}

function searchOutputSchema() {
  return {
    type: 'object',
    properties: {
      results: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string' },
            title: { type: 'string' },
            url: { type: 'string' },
          },
          required: ['id', 'title', 'url'],
        },
      },
    },
    required: ['results'],
  };
}

function fetchOutputSchema() {
  return {
    type: 'object',
    properties: {
      id: { type: 'string' },
      title: { type: 'string' },
      text: { type: 'string' },
      url: { type: 'string' },
      metadata: { type: 'object' },
    },
    required: ['id', 'title', 'text', 'url'],
  };
}

async function authForMcpMessage(request, message) {
  if (!mcpMethodRequiresAuth(message.method)) {
    return { ok: true, accountId: '' };
  }
  return mcpAuthContext(request);
}

function mcpMethodRequiresAuth(method) {
  return ['tools/call', 'resources/list', 'resources/read'].includes(String(method || ''));
}

async function mcpAuthContext(request) {
  const token = bearerToken(request);
  const tokenMap = parseMcpTokens();
  const accountId = tokenMap.get(token) || accountIdFromMcpAccessToken(token);
  if (!accountId) {
    return { ok: false, status: 401, error: 'Unauthorized' };
  }
  const accounts = await readAccounts();
  if (!accounts[safeAccountId(accountId)]) {
    return { ok: false, status: 403, error: 'MCP account is not registered' };
  }
  return { ok: true, accountId };
}

function parseMcpTokens() {
  const rows = String(process.env.QUANTIVITA_MCP_TOKENS || '')
    .split(',')
    .map((row) => row.trim())
    .filter(Boolean);
  const tokens = new Map();
  for (const row of rows) {
    const separator = row.indexOf(':');
    if (separator <= 0) continue;
    const token = row.slice(0, separator);
    const accountId = row.slice(separator + 1);
    if (token && accountId) tokens.set(token, accountId);
  }
  return tokens;
}

function mcpAuthError(response, auth) {
  response
    .status(auth.status || 401)
    .set(
      'WWW-Authenticate',
      `Bearer realm="Quantivita MCP", resource_metadata="${publicBaseUrl}/.well-known/oauth-protected-resource/mcp"`,
    )
    .json({ error: auth.error || 'Unauthorized' });
}

function originAllowed(request) {
  const origin = request.get('origin');
  if (!origin) return true;
  try {
    const host = new URL(origin).hostname;
    return [
      'chatgpt.com',
      'chat.openai.com',
      'platform.openai.com',
      'api.openai.com',
      'localhost',
      '127.0.0.1',
    ].some((allowed) => host === allowed || host.endsWith(`.${allowed}`));
  } catch {
    return false;
  }
}

function mcpResult(id, result) {
  return { jsonrpc: '2.0', id, result };
}

function mcpError(id, code, message) {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function oauthAuthorizationServerMetadata(_request, response) {
  response.json({
    issuer: publicBaseUrl,
    authorization_endpoint: `${publicBaseUrl}/oauth/authorize`,
    token_endpoint: `${publicBaseUrl}/oauth/token`,
    registration_endpoint: `${publicBaseUrl}/oauth/register`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code'],
    token_endpoint_auth_methods_supported: ['none'],
    code_challenge_methods_supported: ['S256', 'plain'],
    scopes_supported: ['healthdata:read'],
  });
}

function oauthProtectedResourceMetadata(request, response) {
  const resourcePath = request.path.endsWith('/mcp-v2') ? '/mcp-v2' : '/mcp';
  response.json({
    resource: `${publicBaseUrl}${resourcePath}`,
    authorization_servers: [publicBaseUrl],
    bearer_methods_supported: ['header'],
    scopes_supported: ['healthdata:read'],
  });
}

function oauthRegisterClient(request, response) {
  const clientId = `qv_mcp_${crypto.randomBytes(16).toString('hex')}`;
  const redirectUris = Array.isArray(request.body?.redirect_uris)
    ? request.body.redirect_uris.map(String)
    : [];
  oauthClients.set(clientId, {
    clientId,
    redirectUris,
    name: String(request.body?.client_name || 'ChatGPT'),
    createdAt: Date.now(),
  });
  response.status(201).json({
    client_id: clientId,
    client_id_issued_at: Math.floor(Date.now() / 1000),
    token_endpoint_auth_method: 'none',
    redirect_uris: redirectUris,
    grant_types: ['authorization_code'],
    response_types: ['code'],
    scope: 'healthdata:read',
  });
}

function oauthAuthorizePage(request, response) {
  const error = validateAuthorizeRequest(request.query);
  if (error) {
    response.status(400).send(oauthPage(`Quantivita MCP`, `<p>${escapeHtml(error)}</p>`));
    return;
  }

  const accountId = accountIdFromSession(request);
  if (accountId) {
    issueOauthCodeForAccount(accountId, request.query, response);
    return;
  }

  response.cookie('qv_after_login', safeAfterLoginPath(request.originalUrl) || '/oauth/authorize', sessionCookieOptions(10 * 60 * 1000));
  response.type('html').send(oauthPage(
    'Quantivita MCP toegang',
    `<p>Log in met Apple om ChatGPT read-only toegang te geven tot jouw Quantivita healthdata.</p>
    <p>Na het inloggen sturen we je automatisch terug naar ChatGPT. Er is geen handmatige tokenstap meer.</p>
    <a class="button" href="/auth/apple/start">Log in met Apple</a>`,
  ));
}

async function oauthAuthorizeSubmit(request, response) {
  const params = request.body || {};
  const error = validateAuthorizeRequest(params);
  if (error) {
    response.status(400).send(oauthPage('Quantivita MCP', `<p>${escapeHtml(error)}</p>`));
    return;
  }

  const accountId = accountIdFromSession(request);
  if (!accountId) {
    const query = new URLSearchParams();
    for (const key of ['client_id', 'redirect_uri', 'response_type', 'scope', 'state', 'code_challenge', 'code_challenge_method']) {
      if (params[key]) query.set(key, String(params[key]));
    }
    response.redirect(`/oauth/authorize?${query.toString()}`);
    return;
  }
  issueOauthCodeForAccount(accountId, params, response);
}

function issueOauthCodeForAccount(accountId, params, response) {
  const code = crypto.randomBytes(32).toString('base64url');
  oauthCodes.set(code, {
    accountId,
    clientId: String(params.client_id),
    redirectUri: String(params.redirect_uri),
    codeChallenge: String(params.code_challenge || ''),
    codeChallengeMethod: String(params.code_challenge_method || 'plain'),
    expiresAt: Date.now() + 10 * 60 * 1000,
  });
  const redirectUrl = new URL(String(params.redirect_uri));
  redirectUrl.searchParams.set('code', code);
  if (params.state) redirectUrl.searchParams.set('state', String(params.state));
  response.redirect(redirectUrl.toString());
}

function oauthToken(request, response) {
  const grantType = String(request.body?.grant_type || '');
  const code = String(request.body?.code || '');
  const verifier = String(request.body?.code_verifier || '');
  const redirectUri = String(request.body?.redirect_uri || '');
  const clientId = String(request.body?.client_id || '');
  if (grantType !== 'authorization_code') {
    response.status(400).json({ error: 'unsupported_grant_type' });
    return;
  }
  const entry = oauthCodes.get(code);
  oauthCodes.delete(code);
  if (!entry || entry.expiresAt < Date.now()) {
    response.status(400).json({ error: 'invalid_grant' });
    return;
  }
  if (entry.clientId !== clientId || entry.redirectUri !== redirectUri || !pkceMatches(entry, verifier)) {
    response.status(400).json({ error: 'invalid_grant' });
    return;
  }
  response.json({
    access_token: signMcpAccessToken(entry.accountId),
    token_type: 'Bearer',
    expires_in: 30 * 24 * 60 * 60,
    scope: 'healthdata:read',
  });
}

function validateAuthorizeRequest(params) {
  if (String(params.response_type || '') !== 'code') return 'response_type=code is verplicht.';
  if (!params.client_id) return 'client_id ontbreekt.';
  if (!params.redirect_uri) return 'redirect_uri ontbreekt.';
  const client = oauthClients.get(String(params.client_id));
  if (client?.redirectUris?.length && !client.redirectUris.includes(String(params.redirect_uri))) {
    return 'redirect_uri is niet geregistreerd voor deze client.';
  }
  return '';
}

function hiddenOauthFields(params) {
  return ['client_id', 'redirect_uri', 'response_type', 'scope', 'state', 'code_challenge', 'code_challenge_method']
    .map((key) => `<input type="hidden" name="${key}" value="${escapeHtml(String(params[key] || ''))}">`)
    .join('\n');
}

function safeAfterLoginPath(value) {
  const raw = String(value || '');
  if (!raw.startsWith('/oauth/authorize')) return '';
  try {
    const url = new URL(raw, publicBaseUrl);
    if (url.origin !== publicBaseUrl || url.pathname !== '/oauth/authorize') return '';
    return `${url.pathname}${url.search}`;
  } catch {
    return '';
  }
}

function oauthPage(title, body) {
  return `<!doctype html>
<html lang="nl">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(title)}</title>
    <style>
      :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif; }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: linear-gradient(135deg, #f7fbff, #edf8f3); color: #111827; }
      main { width: min(440px, calc(100vw - 32px)); padding: 28px; border-radius: 28px; background: rgba(255,255,255,.76); border: 1px solid rgba(255,255,255,.72); box-shadow: 0 24px 80px rgba(17,24,39,.12); backdrop-filter: blur(28px); }
      h1 { margin: 0 0 10px; font-size: 28px; }
      p { color: #4b5563; line-height: 1.45; }
      label { display: block; margin: 18px 0 8px; font-weight: 700; }
      input { width: 100%; box-sizing: border-box; padding: 14px 16px; border-radius: 16px; border: 1px solid #d1d5db; font-size: 16px; }
      button, .button { display: block; box-sizing: border-box; width: 100%; margin-top: 18px; padding: 14px 16px; border: 0; border-radius: 16px; background: #111827; color: white; font-weight: 800; font-size: 16px; text-align: center; text-decoration: none; }
    </style>
  </head>
  <body><main><h1>${escapeHtml(title)}</h1>${body}</main></body>
</html>`;
}

function signMcpAccessToken(accountId) {
  const payload = Buffer.from(JSON.stringify({
    sub: accountId,
    scope: 'healthdata:read',
    exp: Date.now() + 30 * 24 * 60 * 60 * 1000,
  })).toString('base64url');
  const signature = crypto.createHmac('sha256', sessionSecret).update(payload).digest('base64url');
  return `qv_mcp.${payload}.${signature}`;
}

function accountIdFromMcpAccessToken(token) {
  const [prefix, payload, signature] = String(token || '').split('.');
  if (prefix !== 'qv_mcp' || !payload || !signature) return '';
  const expected = crypto.createHmac('sha256', sessionSecret).update(payload).digest('base64url');
  if (signature.length !== expected.length) return '';
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return '';
  try {
    const parsed = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (parsed.exp < Date.now() || parsed.scope !== 'healthdata:read') return '';
    return String(parsed.sub || '');
  } catch {
    return '';
  }
}

function pkceMatches(entry, verifier) {
  if (!entry.codeChallenge) return true;
  if (entry.codeChallengeMethod === 'S256') {
    const digest = crypto.createHash('sha256').update(verifier).digest('base64url');
    return digest === entry.codeChallenge;
  }
  return verifier === entry.codeChallenge;
}

function clampNumber(value, min, max) {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, Math.round(value)));
}

async function proxyProgressaRequest(request, response) {
  if (!progressaApiBaseUrl) {
    response.status(503).json({
      error: 'PROGRESSA_API_BASE_URL is not configured on the Quantivita homeserver',
    });
    return;
  }

  try {
    const originalUrl = request.originalUrl || request.url || '';
    const targetPath = originalUrl.replace(/^\/progressa(?=\/)/, '');
    const targetUrl = new URL(targetPath, progressaApiBaseUrl);
    const headers = {
      accept: request.get('accept') || 'application/json',
    };
    const authorization = request.get('authorization');
    if (authorization) headers.authorization = authorization;

    const init = {
      method: request.method,
      headers,
      signal: AbortSignal.timeout(15000),
    };
    if (!['GET', 'HEAD'].includes(request.method)) {
      headers['content-type'] = 'application/json';
      init.body = JSON.stringify(request.body || {});
    }

    const remoteResponse = await fetch(targetUrl, init);
    response.status(remoteResponse.status);
    response.type(remoteResponse.headers.get('content-type') || 'application/json');
    response.send(await remoteResponse.text());
  } catch (error) {
    response.status(502).json({ error: `Progressa proxy failed: ${error.message}` });
  }
}

async function readRawUserData(accountId) {
  await mkdir(dataDir, { recursive: true });
  const file = path.join(dataDir, `${safeAccountId(accountId)}.json`);
  try {
    return JSON.parse(await readFile(file, 'utf8'));
  } catch {
    return seedData(accountId);
  }
}

function withCalibratedStrain(data) {
  const workouts = Array.isArray(data.workouts) ? data.workouts : [];
  if (!Array.isArray(data.daily) || workouts.length === 0) return data;
  const daily = data.daily.map((day) => {
    if (!day?.date) return day;
    const dayWorkouts = workouts.filter((workout) => localDate(workout.startTime || workout.date) === day.date);
    if (dayWorkouts.length === 0) return day;
    const result = calibratedStrainForDay(day, dayWorkouts);
    return {
      ...day,
      strainScore: result.percent,
      strain: result.percent,
      strainRawScore: result.score,
      strainLoad: result.totalLoad,
      strainLabel: result.label,
    };
  });
  return { ...data, daily };
}

function calibratedStrainForDay(day, workouts) {
  let cardioLoad = 0;
  let muscularLoad = 0;
  for (const workout of workouts) {
    const duration = clamp(Number(workout.durationMinutes || workout.effectiveDurationMinutes || 0), 0, 600);
    const resting = Number(day.restingHeartBpm || workout.restingHeartRate || 60);
    const maxHr = Number(workout.maxHeartRate || day.maxHeartBpm || 190);
    const reserve = Math.max(maxHr - resting, 1);
    const averageHeartRate = Number(workout.averageHeartRate || 0);
    const reservePercent = averageHeartRate > 0
      ? (averageHeartRate - resting) / reserve
      : estimatedReserveFromEnergy(Number(workout.energyKcal || workout.activeEnergyKcal || 0), duration);
    cardioLoad += duration * strainZoneWeight(reservePercent);
    muscularLoad += muscularLoadForWorkout(workout, duration);
  }

  const totalLoad = cardioLoad + muscularLoad * 0.35;
  const k = Math.max(120 * 1.45, 110);
  const score = roundToOneDecimal(clamp(21 * (1 - Math.exp(-totalLoad / k)), 0, 21));
  const percent = clamp(Math.round((score / 21) * 100), 0, 100);
  return {
    score,
    percent,
    totalLoad: roundToOneDecimal(totalLoad),
    label: strainLabelForScore(score),
  };
}

function strainZoneWeight(reservePercent) {
  if (reservePercent >= 0.90) return 9.5;
  if (reservePercent >= 0.80) return 6.5;
  if (reservePercent >= 0.70) return 3.4;
  if (reservePercent >= 0.60) return 1.8;
  if (reservePercent >= 0.50) return 0.9;
  return 0;
}

function estimatedReserveFromEnergy(activeEnergyKcal, durationMinutes) {
  if (durationMinutes <= 0 || activeEnergyKcal <= 0) return 0.45;
  return clamp(0.45 + (activeEnergyKcal / durationMinutes) / 32, 0.45, 0.88);
}

function muscularLoadForWorkout(workout, duration) {
  const typeCode = Math.round(Number(workout.typeCode || workout.type || 0));
  const typeMultiplier = typeCode === 5 ? 1.25 : typeCode === 6 ? 1.15 : typeCode === 7 ? 0.45 : 0.25;
  const activeEnergyKcal = Number(workout.energyKcal || workout.activeEnergyKcal || 0);
  const kcalMultiplier = activeEnergyKcal <= 0
    ? 1
    : clamp(activeEnergyKcal / Math.max(duration * 8, 1), 0.65, 1.45);
  return duration * typeMultiplier * kcalMultiplier;
}

function strainLabelForScore(score) {
  if (score >= 20) return 'Very high';
  if (score >= 17) return 'High';
  if (score >= 11) return 'Moderate';
  if (score >= 5) return 'Light';
  return 'Restorative';
}

function roundToOneDecimal(value) {
  return Math.round(value * 10) / 10;
}

async function readAccounts() {
  await mkdir(dataDir, { recursive: true });
  try {
    return JSON.parse(await readFile(path.join(dataDir, 'accounts.json'), 'utf8'));
  } catch {
    return {};
  }
}

async function writeAccounts(accounts) {
  await mkdir(dataDir, { recursive: true });
  await writeFile(path.join(dataDir, 'accounts.json'), `${JSON.stringify(accounts, null, 2)}\n`);
}

async function isAuthorized(accountId, syncToken) {
  if (!accountId || !syncToken) return false;
  const accounts = await readAccounts();
  const account = accounts[safeAccountId(accountId)];
  return account?.tokenHash === hashToken(syncToken);
}

function bearerToken(request) {
  const header = request.get('authorization') || '';
  const [scheme, token] = header.split(' ');
  return scheme?.toLowerCase() === 'bearer' ? token : '';
}

function hashToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function secretKey() {
  return crypto.createHash('sha256').update(sessionSecret).digest();
}

function encryptSecret(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', secretKey(), iv);
  const encrypted = Buffer.concat([cipher.update(String(value), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString('base64url')}.${tag.toString('base64url')}.${encrypted.toString('base64url')}`;
}

function decryptSecret(value) {
  const [ivText, tagText, encryptedText] = String(value || '').split('.');
  if (!ivText || !tagText || !encryptedText) return '';
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    secretKey(),
    Buffer.from(ivText, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedText, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

async function validStravaAccessToken(accountId) {
  const accounts = await readAccounts();
  const key = safeAccountId(accountId);
  const strava = accounts[key]?.strava;
  if (!strava) return '';
  const now = Math.floor(Date.now() / 1000);
  if (strava.accessToken && Number(strava.expiresAt || 0) > now + 60) {
    return decryptSecret(strava.accessToken);
  }
  const refreshToken = decryptSecret(strava.refreshToken);
  if (!refreshToken || !stravaClientId || !stravaClientSecret) return '';
  const remote = await fetchWithTimeout(new URL('/oauth/token', stravaApiBaseUrl), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      client_id: stravaClientId,
      client_secret: stravaClientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });
  const body = await remote.json().catch(() => ({}));
  if (!remote.ok || !body.access_token) throw new Error(body.message || 'Token refresh rejected');
  accounts[key].strava = {
    ...strava,
    accessToken: encryptSecret(body.access_token),
    refreshToken: encryptSecret(body.refresh_token || refreshToken),
    expiresAt: Number(body.expires_at || 0),
  };
  await writeAccounts(accounts);
  return body.access_token;
}

function normalizeStravaScopes(value) {
  const values = Array.isArray(value) ? value : String(value || '').split(',');
  return [...new Set(values.map((scope) => String(scope).trim()).filter(Boolean))].sort();
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 15_000) {
  const signal = AbortSignal.timeout(timeoutMs);
  return fetch(url, { ...options, signal });
}

function publicProgressaIntegration(progressa) {
  return {
    connected: true,
    userId: progressa.userId,
    connectedAt: progressa.connectedAt,
    tokenFingerprint: String(progressa.tokenHash || '').slice(0, 12),
  };
}

async function saveProgressaConnection(accountId, { progressaUserId, accessToken, refreshToken }) {
  const accounts = await readAccounts();
  const key = safeAccountId(accountId);
  const account = accounts[key];
  if (!account) {
    return { ok: false, status: 404, error: 'Account is not registered' };
  }

  const progressa = {
    userId: String(progressaUserId),
    accessToken: encryptSecret(String(accessToken)),
    refreshToken: refreshToken ? encryptSecret(String(refreshToken)) : account.progressa?.refreshToken,
    tokenHash: hashToken(accessToken),
    connectedAt: new Date().toISOString(),
  };
  accounts[key] = { ...account, progressa, updatedAt: new Date().toISOString() };
  await writeAccounts(accounts);

  const data = await readRawUserData(accountId);
  const next = {
    ...data,
    updatedAt: new Date().toISOString(),
    integrations: {
      ...(data.integrations || {}),
      progressa: publicProgressaIntegration(progressa),
    },
  };
  await writeUserData(accountId, next);
  return { ok: true, progressa: next.integrations.progressa };
}

async function fetchProgressa(accountId, query, index = false) {
  const accounts = await readAccounts();
  const progressa = accounts[safeAccountId(accountId)]?.progressa;
  if (!progressa?.accessToken || !progressa?.userId) {
    throw Object.assign(new Error('Progressa is not connected for this Quantivita account'), { status: 409 });
  }
  if (!progressaApiBaseUrl) {
    throw Object.assign(new Error('PROGRESSA_API_BASE_URL is not configured on the Quantivita homeserver'), { status: 503 });
  }

    const remoteUrl = new URL(
      `/api/users/${encodeURIComponent(progressa.userId)}/workouts`,
      progressaApiBaseUrl,
    );
    if (index) remoteUrl.searchParams.set('metric', 'progress-index');
    else remoteUrl.searchParams.set('linkedOnly', 'true');
    for (const key of ['from', 'to', 'limit', 'workoutId']) {
      const value = query[key];
      if (value != null && value !== '') remoteUrl.searchParams.set(key, String(value));
    }

    let accessToken = decryptSecret(progressa.accessToken);
    let remoteResponse = await fetch(remoteUrl, {
      headers: {
        authorization: `Bearer ${accessToken}`,
        accept: 'application/json',
      },
    });
    if (remoteResponse.status === 401 && progressa.refreshToken) {
      const refreshed = await refreshProgressaToken(progressa);
      if (refreshed?.accessToken) {
        accessToken = refreshed.accessToken;
        progressa.accessToken = encryptSecret(refreshed.accessToken);
        if (refreshed.refreshToken) {
          progressa.refreshToken = encryptSecret(refreshed.refreshToken);
        }
        progressa.tokenHash = hashToken(refreshed.accessToken);
        const allAccounts = await readAccounts();
        const key = safeAccountId(accountId);
        allAccounts[key] = {
          ...allAccounts[key],
          progressa,
          updatedAt: new Date().toISOString(),
        };
        await writeAccounts(allAccounts);
        remoteResponse = await fetch(remoteUrl, {
          headers: {
            authorization: `Bearer ${accessToken}`,
            accept: 'application/json',
          },
        });
      }
    }
    const body = await remoteResponse.text();
    if (!remoteResponse.ok) {
      const parsedError = parseJsonObject(body);
      throw Object.assign(new Error(parsedError?.error || 'Progressa workout fetch failed'), { status: remoteResponse.status });
    }
    const parsed = body ? JSON.parse(body) : [];
    if (index && (!Array.isArray(parsed.loggedDates) || !Array.isArray(parsed.exercises))) {
      throw new Error('Progressa API does not support Progress Index');
    }
    return { parsed, progressa };
}

async function progressIndex(accountId, args) {
  return (await fetchProgressa(accountId, args, true)).parsed;
}

async function sendProgressaWorkouts(accountId, request, response) {
  try {
    const { parsed, progressa } = await fetchProgressa(accountId, request.query);
    const workouts = normalizeProgressaWorkouts(parsed);
    const data = await readRawUserData(accountId);
    const next = {
      ...data,
      updatedAt: new Date().toISOString(),
      integrations: {
        ...(data.integrations || {}),
        progressa: {
          ...publicProgressaIntegration(progressa),
          lastWorkoutFetchAt: new Date().toISOString(),
        },
      },
      workouts: attachProgressaToHealthWorkouts(data.workouts, workouts),
    };
    await writeUserData(accountId, next);
    response.json({ workouts, integration: next.integrations.progressa });
  } catch (error) {
    response.status(error.status || 502).json({ error: `Progressa workout fetch failed: ${error.message}` });
  }
}

async function refreshProgressaToken(progressa) {
  const refreshToken = decryptSecret(progressa.refreshToken);
  if (!refreshToken || !progressaApiBaseUrl) return null;
  const remoteResponse = await fetch(new URL('/api/quantivita/refresh-token', progressaApiBaseUrl), {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({ refreshToken }),
  });
  const body = await remoteResponse.json().catch(() => ({}));
  if (!remoteResponse.ok || !body.accessToken) return null;
  return {
    accessToken: String(body.accessToken),
    refreshToken: body.refreshToken ? String(body.refreshToken) : refreshToken,
  };
}

function accountIdForAppleSubject(subject) {
  return `qv_${crypto.createHash('sha256').update(String(subject)).digest('hex').slice(0, 24)}`;
}

function signSession(accountId) {
  const payload = Buffer.from(JSON.stringify({ accountId, iat: Date.now() })).toString('base64url');
  const signature = crypto.createHmac('sha256', sessionSecret).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

function accountIdFromSession(request) {
  const session = request.cookies?.qv_session;
  if (!session) return null;
  const [payload, signature] = session.split('.');
  if (!payload || !signature) return null;
  const expected = crypto.createHmac('sha256', sessionSecret).update(payload).digest('base64url');
  if (signature.length !== expected.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  try {
    return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')).accountId;
  } catch {
    return null;
  }
}

function sessionCookieOptions(maxAge) {
  return {
    httpOnly: true,
    sameSite: 'lax',
    secure: publicBaseUrl.startsWith('https://'),
    maxAge,
  };
}

async function writeUserData(accountId, data) {
  await mkdir(dataDir, { recursive: true });
  const file = path.join(dataDir, `${safeAccountId(accountId)}.json`);
  await writeFile(file, `${JSON.stringify(data, null, 2)}\n`);
}

function normalizePayload(value) {
  return {
    profile: value?.profile || {},
    daily: Array.isArray(value?.daily) ? value.daily : [],
    workouts: Array.isArray(value?.workouts) ? value.workouts.map(normalizeWorkoutLog) : [],
    integrations: value?.integrations || {},
  };
}

function normalizeWorkoutLog(workout) {
  if (!workout || typeof workout !== 'object') return workout;
  return {
    ...workout,
    title: workoutDisplayTitle(workout),
  };
}

function mergeByDate(current = [], incoming = []) {
  const rows = new Map(current.map((row) => [row.date, row]));
  for (const row of incoming) {
    if (row?.date) rows.set(row.date, { ...rows.get(row.date), ...row });
  }
  return [...rows.values()].sort((a, b) => a.date.localeCompare(b.date));
}

function mergeById(current = [], incoming = []) {
  const rows = new Map(current.map((row) => [row.id, row]));
  for (const row of incoming) {
    const id = row?.id || `workout-${row?.startTime || Date.now()}`;
    rows.set(id, normalizeWorkoutLog({ ...rows.get(id), ...row, id }));
  }
  return [...rows.values()].sort((a, b) => String(b.startTime).localeCompare(String(a.startTime)));
}

function normalizeProgressaWorkouts(payload) {
  const rows = Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.workouts)
      ? payload.workouts
      : Array.isArray(payload?.data)
        ? payload.data
        : [];

  if (rows.some((row) => row?.workout_id || row?.exercise_id || row?.workouts)) {
    return normalizeProgressaSetRows(rows);
  }

  return rows.map(normalizeProgressaWorkout).filter(Boolean);
}

function normalizeProgressaWorkout(row) {
  if (!row || typeof row !== 'object') return null;
  const id = String(row.id || row.workoutId || row.workout_id || '');
  if (!id) return null;
  const start = row.created_at || row.createdAt || row.startTime || row.start_time || '';
  const details = row.details || {};
  const exercises = Array.isArray(row.exercises) ? row.exercises.map(e => ({ ...e, sets: (e.sets || []).map(set => ({...set, ...setLoad(set)})) })) : Array.isArray(row.sets) ? groupSets(row.sets) : [];
  const hasVolumeData = exercisesHaveVolumeData(exercises);
  const totalVolumeKg = hasVolumeData ? totalVolumeForExercises(exercises) : 0;
  return {
    id: `progressa:${id}`,
    source: 'progressa',
    externalWorkoutId: id,
    title: progressaWorkoutTitle(row.title, exercises, start),
    startTime: start,
    durationMinutes: Number(row.durationMinutes || row.duration_minutes || details.durationMinutes || 0),
    energyKcal: Number(row.energyKcal || row.energy_kcal || 0),
    distanceMeters: Number(row.distanceMeters || row.distance_meters || 0),
    averageHeartRate: Number(row.averageHeartRate || row.average_heart_rate || 0),
    maxHeartRate: Number(row.maxHeartRate || row.max_heart_rate || 0),
    typeCode: Number(row.typeCode || row.type_code || 5),
    healthActivityLink: normalizeHealthActivityLink(row.healthActivity || row.health_activity || row.healthMetadata),
    progressaDetails: {
      exerciseCount: exercises.length,
      totalSets: exercises.reduce((sum, exercise) => sum + Number(exercise.sets?.length || 0), 0),
      totalVolumeKg,
      hasVolumeData,
      exercises,
    },
  };
}

function normalizeProgressaSetRows(rows) {
  const workouts = new Map();
  for (const row of rows) {
    const workout = objectValue(row.workouts) || objectValue(row['workouts:workout_id']) || {};
    const workoutId = String(row.workout_id || workout.id || '');
    if (!workoutId) continue;
    const current = workouts.get(workoutId) || {
      id: `progressa:${workoutId}`,
      source: 'progressa',
      externalWorkoutId: workoutId,
      rawTitle: String(workout.title || ''),
      title: String(workout.title || 'Progressa workout'),
      startTime: workout.created_at || row.created_at || '',
      durationMinutes: 0,
      energyKcal: 0,
      distanceMeters: 0,
      averageHeartRate: 0,
      maxHeartRate: 0,
      typeCode: 5,
      healthActivityLink: normalizeHealthActivityLink(row.health_activity || row.healthActivity),
      progressaDetails: {
        exerciseCount: 0,
        totalSets: 0,
        totalVolumeKg: 0,
        exercises: [],
      },
    };
    const exercise = objectValue(row.exercises) || objectValue(row['exercises:exercise_id']) || {};
    const exerciseId = String(row.exercise_id || exercise.id || 'unknown');
    let target = current.progressaDetails.exercises.find((item) => item.id === exerciseId);
    if (!target) {
      target = {
        id: exerciseId,
        name: String(exercise.name || 'Exercise'),
        muscleGroup: String(exercise.default_muscles || exercise.muscleGroup || ''),
        sets: [],
      };
      current.progressaDetails.exercises.push(target);
    }
    target.sets.push({
      ...setLoad(row),
      reps: numericOrNull(row.reps),
      rir: numericOrNull(row.rir),
      side: row.side || null,
      isWarmup: row.is_warmup === true,
      createdAt: row.created_at || null,
    });
    workouts.set(workoutId, current);
  }

  return [...workouts.values()].map((workout) => {
    workout.progressaDetails.exerciseCount = workout.progressaDetails.exercises.length;
    workout.progressaDetails.totalSets = workout.progressaDetails.exercises.reduce(
      (sum, exercise) => sum + exercise.sets.length,
      0,
    );
    workout.progressaDetails.hasVolumeData = exercisesHaveVolumeData(workout.progressaDetails.exercises);
    workout.progressaDetails.totalVolumeKg = workout.progressaDetails.hasVolumeData
      ? totalVolumeForExercises(workout.progressaDetails.exercises)
      : 0;
    workout.title = progressaWorkoutTitle(
      workout.rawTitle,
      workout.progressaDetails.exercises,
      workout.startTime,
    );
    delete workout.rawTitle;
    return workout;
  });
}

function normalizeHealthActivityLink(value) {
  const row = objectValue(value) || {};
  const healthStart = String(row.health_start || row.healthStart || '');
  const healthEnd = String(row.health_end || row.healthEnd || '');
  if (!healthStart || !healthEnd) return null;
  return {
    healthStart,
    healthEnd,
    activityType: String(row.activity_type || row.activityType || ''),
    durationSeconds: numericOrNull(row.duration_secs ?? row.durationSeconds),
  };
}

function attachProgressaToHealthWorkouts(current = [], linkedProgressa = []) {
  const healthWorkouts = current
    .filter((workout) => workout?.source !== 'progressa')
    .map((workout) => ({ ...workout }));
  for (const progressaWorkout of linkedProgressa) {
    const link = progressaWorkout?.healthActivityLink;
    if (!link?.healthStart) continue;
    const linkStart = Date.parse(link.healthStart);
    const linkEnd = Date.parse(link.healthEnd);
    if (!Number.isFinite(linkStart)) continue;
    const candidates = healthWorkouts
      .map((workout, index) => {
        const start = Date.parse(workout.startTime || workout.date || '');
        const durationMs = Number(workout.durationMinutes || 0) * 60_000;
        const end = start + durationMs;
        const startDelta = Math.abs(start - linkStart);
        const endDelta = Number.isFinite(linkEnd) ? Math.abs(end - linkEnd) : 0;
        return { workout, index, startDelta, endDelta };
      })
      .filter((candidate) => Number.isFinite(candidate.startDelta) && candidate.startDelta <= 5_000)
      .sort((a, b) => (a.startDelta + a.endDelta) - (b.startDelta + b.endDelta));
    const match = candidates[0];
    if (!match) continue;
    healthWorkouts[match.index] = {
      ...match.workout,
      externalWorkoutId: progressaWorkout.externalWorkoutId,
      progressaWorkoutTitle: progressaWorkout.title,
      progressaDetails: progressaWorkout.progressaDetails,
      progressaLink: link,
    };
  }
  return healthWorkouts.sort((a, b) => String(b.startTime).localeCompare(String(a.startTime)));
}

function setLoad(set) {
  const total = numericOrNull(set.totalWeightKg ?? set.total_weight_kg ?? set.weightKg ?? set.weight_kg);
  const base = numericOrNull(set.baseWeightKg ?? set.base_weight_kg) ?? 0;
  return { weightKg: total, totalWeightKg: total, baseWeightKg: base, addedWeightKg: total == null ? null : total - base };
}

function groupSets(sets) {
  const exercises = new Map();
  for (const set of sets) {
    const exerciseId = String(set.exerciseId || set.exercise_id || set.exercise?.id || 'unknown');
    const exercise = exercises.get(exerciseId) || {
      id: exerciseId,
      name: String(set.exerciseName || set.exercise?.name || 'Exercise'),
      muscleGroup: String(set.muscleGroup || set.exercise?.default_muscles || ''),
      sets: [],
    };
    exercise.sets.push({
      ...setLoad(set),
      reps: numericOrNull(set.reps),
      rir: numericOrNull(set.rir),
      side: set.side || null,
      isWarmup: set.isWarmup === true || set.is_warmup === true,
      createdAt: set.createdAt || set.created_at || null,
    });
    exercises.set(exerciseId, exercise);
  }
  return [...exercises.values()];
}

function totalVolumeForExercises(exercises) {
  return exercises.reduce(
    (sum, exercise) =>
      sum +
      (exercise.sets || []).reduce((setSum, set) => {
        const weight = Number(set.weightKg || 0);
        const reps = Number(set.reps || 0);
        return setSum + weight * reps;
      }, 0),
    0,
  );
}

function exercisesHaveVolumeData(exercises) {
  return exercises.some((exercise) =>
    (exercise.sets || []).some((set) => {
      const weight = Number(set.weightKg);
      const reps = Number(set.reps);
      return Number.isFinite(weight) && weight > 0 && Number.isFinite(reps) && reps > 0;
    }),
  );
}

function progressaWorkoutTitle(rawTitle, exercises, startTime) {
  const title = String(rawTitle || '').trim();
  if (title && !/^(workout|progressa workout|strength)$/i.test(title)) {
    return title;
  }

  const namedExercises = exercises
    .map((exercise) => String(exercise.name || '').trim())
    .filter((name) => name && !/^exercise$/i.test(name));
  if (namedExercises.length > 0) {
    const suffix = namedExercises.length > 1 ? ` + ${namedExercises.length - 1} exercises` : '';
    return `${namedExercises[0]}${suffix}`;
  }

  const date = new Date(startTime);
  if (!Number.isNaN(date.getTime())) {
    return `Strength workout at ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }
  return 'Strength workout';
}

function objectValue(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
}

function parseJsonObject(value) {
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function numericOrNull(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function summaryFor(data) {
  const latest = [...(data.daily || [])].at(-1) || {};
  const workouts = data.workouts || [];
  const totals = workouts.reduce(
    (sum, workout) => ({
      minutes: sum.minutes + Number(workout.durationMinutes || 0),
      energy: sum.energy + Number(workout.energyKcal || 0),
      distance: sum.distance + Number(workout.distanceMeters || 0),
    }),
    { minutes: 0, energy: 0, distance: 0 },
  );
  return {
    accountId: data.accountId,
    updatedAt: data.updatedAt,
    latest,
    workoutCount: workouts.length,
    missingEnergyCount: workouts.filter(w => w.energyAvailable === false || w.energyKcal == null).length,
    missingDistanceCount: workouts.filter(w => w.distanceAvailable === false || w.distanceMeters == null).length,
    totals,
    readinessSignals: {
      hrvMs: latest.hrvMs || 0,
      restingHeartBpm: latest.restingHeartBpm || 0,
      sleepMinutes: latest.sleepMinutes || 0,
      respiratoryRate: latest.respiratoryRate || 0,
      oxygenSaturation: latest.oxygenSaturation || 0,
    },
  };
}

function debugDailyFor(data, date) {
  const daily = data.daily || [];
  const day = daily.find((row) => row.date === date) || daily.at(-1) || {};
  const workouts = (data.workouts || []).filter((workout) => localDate(workout.startTime) === day.date);
  const hrvValues = daily.map((row) => Number(row.hrvMs || 0)).filter((value) => value > 0);
  const rhrValues = daily.map((row) => Number(row.restingHeartBpm || 0)).filter((value) => value > 0);
  const sleepValues = daily.map((row) => Number(row.sleepMinutes || 0)).filter((value) => value > 0);
  const baselines = {
    hrvMs: baseline(hrvValues),
    restingHeartBpm: baseline(rhrValues),
    sleepMinutes: baseline(sleepValues),
  };
  const sleepScore = sleepScoreFor(day, baselines.sleepMinutes.median);
  const recovery = recoveryDebugFor(day, baselines, sleepScore, workouts);
  return {
    date: day.date || date || null,
    raw: {
      daily: day,
      workouts,
    },
    selected: {
      overnightHrv: day.hrvMs || null,
      restingHeartRate: day.restingHeartBpm || null,
      sleepDurationMinutes: day.sleepMinutes || null,
    },
    baselines,
    contributors: recovery.contributors,
    sleepScore,
    recoveryScore: recovery.score,
    confidence: recovery.confidence,
    calibrationStatus: calibrationStatus(baselines.hrvMs.sampleCount),
    capsApplied: recovery.capsApplied,
  };
}

function recoveryDebugFor(day, baselines, sleepScore, workouts) {
  const hrv = Number(day.hrvMs || 0);
  const rhr = Number(day.restingHeartBpm || 0);
  const hrvScore = hrv > 0 ? higherIsBetterScore(robustZ(Math.log(hrv), logBaseline(baselines.hrvMs))) : null;
  const rhrScore = rhr > 0 ? lowerIsBetterScore(robustZ(rhr, baselines.restingHeartBpm)) : null;
  const strainBalance = workouts.length ? 75 : 100;
  const sleepAvailable = Number(day.sleepMinutes || 0) > 0;
  const contributors = {
    hrv: hrvScore,
    rhr: rhrScore,
    sleep: sleepAvailable ? sleepScore : null,
    strainBalance,
    respiratory: day.respiratoryRate ? 85 : null,
    temperature: 85,
  };
  const weights = { hrv: 0.35, rhr: 0.25, sleep: 0.2, strainBalance: 0.1, respiratory: 0.05, temperature: 0.05 };
  let total = 0;
  let weight = 0;
  for (const [key, value] of Object.entries(contributors)) {
    if (value == null) continue;
    total += value * weights[key];
    weight += weights[key];
  }
  let score = weight ? total / weight : 0;
  const capsApplied = [];
  if (!hrvScore || !rhrScore) {
    score = Math.min(score, 58);
    capsApplied.push('missing_physiology_cap');
  }
  if (day.sleepMinutes && day.sleepMinutes < 300) {
    score = Math.min(score, 45);
    capsApplied.push('sleep_under_5h');
  }
  if (rhr && baselines.restingHeartBpm.median && rhr > baselines.restingHeartBpm.median + 5) {
    score -= 10;
    capsApplied.push('rhr_plus_5_penalty');
  }
  return {
    score: clamp(Math.round(score), 0, 100),
    contributors,
    capsApplied,
    confidence: Math.round((Object.values(contributors).filter((value) => value != null).length / 6) * 100) / 100,
  };
}

function sleepScoreFor(day, baselineMinutes) {
  const minutes = Number(day.sleepMinutes || 0);
  if (!minutes) return 0;
  const target = baselineMinutes ? clamp(baselineMinutes, 420, 540) : 480;
  let score = clamp(100 - Math.abs(minutes - target) * 0.35, 0, 100);
  if (minutes < 300) score = Math.min(score, 45);
  if (minutes < 360) score = Math.min(score, 65);
  return Math.round(score);
}

function baseline(values) {
  const clean = values.filter((value) => Number.isFinite(value) && value > 0).sort((a, b) => a - b);
  if (!clean.length) return { median: 0, mad: 0, sampleCount: 0 };
  const median = percentile(clean, 0.5);
  const deviations = clean.map((value) => Math.abs(value - median)).sort((a, b) => a - b);
  return {
    median,
    mad: percentile(deviations, 0.5),
    sampleCount: clean.length,
  };
}

function logBaseline(value) {
  if (!value?.median) return { median: 0, mad: 0, sampleCount: 0 };
  return {
    median: Math.log(value.median),
    mad: value.mad / value.median,
    sampleCount: value.sampleCount,
  };
}

function percentile(values, p) {
  if (!values.length) return 0;
  const index = (values.length - 1) * p;
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return values[lower];
  return values[lower] * (1 - (index - lower)) + values[upper] * (index - lower);
}

function robustZ(value, baselineValue) {
  if (!baselineValue?.mad || baselineValue.mad < 0.0001) return 0;
  return (value - baselineValue.median) / (1.4826 * baselineValue.mad);
}

function sigmoidScore(z) {
  return clamp(Math.round(100 / (1 + Math.exp(-1.15 * z))), 0, 100);
}

function higherIsBetterScore(z) {
  return sigmoidScore(z);
}

function lowerIsBetterScore(z) {
  return sigmoidScore(-z);
}

function calibrationStatus(sampleCount) {
  if (sampleCount < 14) return 'INSUFFICIENT_DATA';
  if (sampleCount < 42) return 'CALIBRATING';
  return 'READY';
}

function localDate(value) {
  if (!value) return '';
  const time = numericTime(value);
  if (!time) return '';
  return new Date(time).toISOString().slice(0, 10);
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function csvFor(data) {
  const rows = [
    ['section', 'date_or_id', 'field', 'value'],
    ...Object.entries(summaryFor(data).readinessSignals).map(([key, value]) => [
      'latest',
      'today',
      key,
      value,
    ]),
    ...(data.daily || []).flatMap((day) =>
      Object.entries(day).map(([key, value]) => ['daily', day.date, key, value]),
    ),
    ...(data.workouts || []).flatMap((workout) =>
      Object.entries(workout).map(([key, value]) => ['workout', workout.id, key, value]),
    ),
  ];
  return rows.map((row) => row.map(csvCell).join(',')).join('\n');
}

function csvCell(value) {
  const text = String(value ?? '');
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function safeAccountId(accountId) {
  return String(accountId).replace(/[^a-zA-Z0-9_-]/g, '_');
}

function seedData(accountId) {
  const today = new Date();
  const daily = Array.from({ length: 14 }, (_, index) => {
    const date = new Date(today);
    date.setDate(today.getDate() - (13 - index));
    return {
      date: date.toISOString().slice(0, 10),
      recoveryScore: 62 + Math.round(Math.sin(index / 2) * 14),
      sleepMinutes: 390 + Math.round(Math.cos(index / 2) * 55),
      hrvMs: 42 + Math.round(Math.sin(index / 3) * 8),
      restingHeartBpm: 57 + Math.round(Math.cos(index / 3) * 5),
      respiratoryRate: 14.5 + Math.sin(index) * 0.7,
      oxygenSaturation: 97 + Math.round(Math.sin(index / 4)),
      activeEnergyKcal: 420 + index * 18,
      steps: 6200 + index * 310,
    };
  });
  return {
    accountId,
    updatedAt: new Date().toISOString(),
    profile: {},
    integrations: {},
    daily,
    workouts: [
      {
        id: 'seed-run',
        title: 'Run',
        startTime: new Date().toISOString(),
        durationMinutes: 42,
        energyKcal: 480,
        distanceMeters: 8200,
        averageHeartRate: 151,
      },
    ],
  };
}
