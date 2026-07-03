import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import net from 'node:net';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

test('protects and constructs the Strava connect flow', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-strava-flow-'));
  const port = await availablePort();
  const stravaPort = await availablePort();
  let statusChecks = 0;
  const strava = http.createServer(async (request, response) => {
    if (request.url === '/oauth/token' && request.method === 'POST') {
      response.setHeader('content-type', 'application/json');
      response.end(JSON.stringify({ access_token: 'access', refresh_token: 'refresh', expires_at: Math.floor(Date.now() / 1000) + 3600, athlete: { id: 42 } }));
      return;
    }
    if (request.url === '/api/v3/uploads' && request.method === 'POST') {
      assert.equal(request.headers.authorization, 'Bearer access');
      assert.match(request.headers['content-type'], /^multipart\/form-data; boundary=/);
      let body = '';
      for await (const chunk of request) body += chunk;
      assert.match(body, /TrainingCenterDatabase/);
      assert.match(body, /name="data_type"/);
      response.setHeader('content-type', 'application/json');
      response.end(JSON.stringify({ id: 777, status: 'Your activity is still being processed.' }));
      return;
    }
    if (request.url === '/api/v3/uploads/777') {
      statusChecks += 1;
      response.setHeader('content-type', 'application/json');
      if (statusChecks === 1) { response.statusCode = 404; response.end('{}'); }
      else response.end(JSON.stringify({ id: 777, activity_id: 888, status: 'Your activity is ready.' }));
      return;
    }
    response.statusCode = 404; response.end('{}');
  });
  strava.listen(stravaPort, '127.0.0.1');
  await once(strava, 'listening');
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      QUANTIVITA_DATA_DIR: dataDir,
      QUANTIVITA_SESSION_SECRET: 'strava-flow-test-secret',
      STRAVA_CLIENT_ID: '12345',
      STRAVA_CLIENT_SECRET: 'test-secret',
      STRAVA_REDIRECT_URI: 'quantivita://quantivita.app/strava-auth',
      STRAVA_API_BASE_URL: `http://127.0.0.1:${stravaPort}`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  server.stdout.on('data', (chunk) => { output += chunk; });
  server.stderr.on('data', (chunk) => { output += chunk; });

  t.after(async () => {
    server.kill('SIGTERM');
    if (server.exitCode === null) await once(server, 'exit');
    await rm(dataDir, { recursive: true, force: true });
    strava.close();
    await once(strava, 'close');
  });

  await waitUntilHealthy(port, server, () => output);
  const endpoint = `http://127.0.0.1:${port}`;
  const accountId = 'strava-flow-account';
  const syncToken = 'quantivita-sync-token';
  const auth = { authorization: `Bearer ${syncToken}` };
  await postJson(`${endpoint}/api/accounts/register`, { accountId, syncToken });

  assert.equal((await fetch(`${endpoint}/api/users/${accountId}/integrations/strava?state=x`)).status, 401);
  assert.equal((await fetch(`${endpoint}/api/users/${accountId}/integrations/strava/authorize-url`, { headers: auth })).status, 400);

  const authorization = await fetch(
    `${endpoint}/api/users/${accountId}/integrations/strava/authorize-url?state=secure-state`,
    { headers: auth },
  );
  assert.equal(authorization.status, 200);
  const url = new URL((await authorization.json()).url);
  assert.equal(url.origin, `http://127.0.0.1:${stravaPort}`);
  assert.equal(url.pathname, '/oauth/authorize');
  assert.equal(url.searchParams.get('client_id'), '12345');
  assert.equal(url.searchParams.get('redirect_uri'), 'quantivita://quantivita.app/strava-auth');
  assert.equal(url.searchParams.get('scope'), 'read,activity:write');
  assert.equal(url.searchParams.get('approval_prompt'), 'force');
  assert.equal(url.searchParams.get('state'), 'secure-state');

  const upload = await postJson(
    `${endpoint}/api/users/${accountId}/integrations/strava/upload`,
    { name: 'Merged workout', externalId: 'merged.tcx', tcx: '<TrainingCenterDatabase />' },
    auth,
  );
  assert.equal(upload.status, 403);

  const missingScope = await postJson(
    `${endpoint}/api/users/${accountId}/integrations/strava/exchange`,
    { code: 'oauth-code', scope: 'read' }, auth,
  );
  assert.equal(missingScope.status, 403);

  const exchange = await postJson(
    `${endpoint}/api/users/${accountId}/integrations/strava/exchange`,
    { code: 'oauth-code', scope: 'read,activity:write' }, auth,
  );
  assert.equal(exchange.status, 202);
  const connected = await fetch(`${endpoint}/api/users/${accountId}/integrations/strava`, { headers: auth });
  assert.deepEqual(await connected.json(), { connected: true, canUpload: true, needsReauthorization: false, scopes: ['activity:write', 'read'] });

  const accepted = await postJson(
    `${endpoint}/api/users/${accountId}/integrations/strava/upload`,
    { name: 'Merged workout', externalId: 'merged.tcx', tcx: '<TrainingCenterDatabase />' }, auth,
  );
  assert.equal(accepted.status, 202);
  assert.equal((await accepted.json()).uploadId, '777');
  const processing = await fetch(`${endpoint}/api/users/${accountId}/integrations/strava/uploads/777`, { headers: auth });
  assert.equal((await processing.json()).state, 'processing');
  const ready = await fetch(`${endpoint}/api/users/${accountId}/integrations/strava/uploads/777`, { headers: auth });
  assert.deepEqual(await ready.json(), { state: 'ready', activityId: '888', error: null });
});

function postJson(url, body, headers = {}) {
  return fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

async function availablePort() {
  const socket = net.createServer();
  socket.listen(0, '127.0.0.1');
  await once(socket, 'listening');
  const { port } = socket.address();
  socket.close();
  await once(socket, 'close');
  return port;
}

async function waitUntilHealthy(port, server, output) {
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) throw new Error(`Server exited early:\n${output()}`);
    try {
      const response = await fetch(`http://127.0.0.1:${port}/healthz`);
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`Server did not become healthy:\n${output()}`);
}
