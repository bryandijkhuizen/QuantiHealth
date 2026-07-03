import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import test from 'node:test';

test('account deletion removes the account record and user data, and requires authorization', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-deletion-'));
  const port = await availablePort();
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      QUANTIVITA_DATA_DIR: dataDir,
      QUANTIVITA_SESSION_SECRET: 'deletion-test-secret',
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
  const accountId = 'native-delete-1';
  const syncToken = 'delete-native-token';

  const created = await postJson(`${endpoint}/api/accounts/register`, { accountId, syncToken });
  assert.equal(created.status, 202);

  // Simulate persisted user data so we can confirm it is removed.
  const userDataFile = path.join(dataDir, `${accountId}.json`);
  await writeFile(userDataFile, JSON.stringify({ daily: [] }));

  const unauthorized = await fetch(`${endpoint}/api/users/${accountId}`, { method: 'DELETE' });
  assert.equal(unauthorized.status, 401);

  const deleted = await fetch(`${endpoint}/api/users/${accountId}`, {
    method: 'DELETE',
    headers: { authorization: `Bearer ${syncToken}` },
  });
  assert.equal(deleted.status, 204);

  const accounts = JSON.parse(await readFile(path.join(dataDir, 'accounts.json'), 'utf8'));
  assert.equal(accounts[accountId], undefined);
  await assert.rejects(readFile(userDataFile, 'utf8'));

  const loginAfterDelete = await postJson(`${endpoint}/api/accounts/login`, { accountId, syncToken });
  assert.equal(loginAfterDelete.status, 401);
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
