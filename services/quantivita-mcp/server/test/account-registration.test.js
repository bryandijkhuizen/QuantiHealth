import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { once } from 'node:events';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import test from 'node:test';

test('registration is idempotent and rejects token replacement', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-registration-'));
  const port = await availablePort();
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      QUANTIVITA_PUBLIC_BASE_URL: `http://127.0.0.1:${port}`,
      QUANTIVITA_DATA_DIR: dataDir,
      QUANTIVITA_SESSION_SECRET: 'registration-test-secret',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let serverOutput = '';
  server.stdout.on('data', (chunk) => { serverOutput += chunk; });
  server.stderr.on('data', (chunk) => { serverOutput += chunk; });

  t.after(async () => {
    server.kill('SIGTERM');
    if (server.exitCode === null) await once(server, 'exit');
    await rm(dataDir, { recursive: true, force: true });
  });

  await waitUntilHealthy(port, server, () => serverOutput);
  const endpoint = `http://127.0.0.1:${port}`;
  const accountId = 'native-account-1';
  const originalToken = 'original-native-token';

  const openapiResponse = await fetch(`${endpoint}/openapi.json`);
  assert.equal(openapiResponse.status, 200);
  const openapi = await openapiResponse.json();
  assert.equal(openapi.openapi, '3.1.0');
  assert.equal(openapi.servers[0].url, endpoint);
  assert.ok(openapi.paths['/api/users/{accountId}/workouts'].get);

  const docsResponse = await fetch(`${endpoint}/docs`);
  assert.equal(docsResponse.status, 200);
  assert.match(await docsResponse.text(), /SwaggerUIBundle/);

  const created = await postJson(`${endpoint}/api/accounts/register`, {
    accountId,
    syncToken: originalToken,
    appleLinked: false,
  });
  assert.equal(created.status, 202);

  const retried = await postJson(`${endpoint}/api/accounts/register`, {
    accountId,
    syncToken: originalToken,
    appleLinked: true,
  });
  assert.equal(retried.status, 202);
  assert.equal((await retried.json()).appleLinked, true);

  const beforeConflict = await storedAccount(dataDir, accountId);
  assert.equal(beforeConflict.tokenHash, hashToken(originalToken));
  assert.equal(beforeConflict.appleLinked, true);

  const conflict = await postJson(`${endpoint}/api/accounts/register`, {
    accountId,
    syncToken: 'replacement-token',
    appleLinked: false,
  });
  assert.equal(conflict.status, 409);

  const afterConflict = await storedAccount(dataDir, accountId);
  assert.deepEqual(afterConflict, beforeConflict);

  const originalLogin = await postJson(`${endpoint}/api/accounts/login`, {
    accountId,
    syncToken: originalToken,
  });
  assert.equal(originalLogin.status, 200);

  const replacementLogin = await postJson(`${endpoint}/api/accounts/login`, {
    accountId,
    syncToken: 'replacement-token',
  });
  assert.equal(replacementLogin.status, 401);
});

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
    } catch {
      // The child process may still be binding its socket.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`Server did not become healthy:\n${output()}`);
}

function postJson(url, body) {
  return fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

async function storedAccount(dataDir, accountId) {
  const accounts = JSON.parse(await readFile(path.join(dataDir, 'accounts.json'), 'utf8'));
  return accounts[accountId];
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}
