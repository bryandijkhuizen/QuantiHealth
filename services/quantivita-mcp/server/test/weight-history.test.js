import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

test('MCP get_weight_history returns and filters body weight entries', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-mcp-weight-'));
  const port = await availablePort();
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      QUANTIVITA_DATA_DIR: dataDir,
      QUANTIVITA_SESSION_SECRET: 'mcp-weight-test-secret',
      QUANTIVITA_MCP_TOKENS: 'mcp-weight-token:mcp-weight-account',
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
  });

  await waitUntilHealthy(port, server, () => output);
  const endpoint = `http://127.0.0.1:${port}`;
  const accountId = 'mcp-weight-account';
  const syncToken = 'mcp-weight-sync-token';
  const auth = { authorization: `Bearer ${syncToken}` };

  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  const isoDaysAgo = (days) => {
    const date = new Date(today);
    date.setUTCDate(today.getUTCDate() - days);
    return date.toISOString().slice(0, 10);
  };

  const oldDate = isoDaysAgo(400);
  const midDate = isoDaysAgo(200);
  const recentDate = isoDaysAgo(10);
  const todayDate = isoDaysAgo(0);

  assert.equal((await postJson(`${endpoint}/api/accounts/register`, { accountId, syncToken })).status, 202);
  assert.equal((await postJson(
    `${endpoint}/api/users/${accountId}/ingest`,
    {
      profile: {},
      daily: [
        { date: oldDate, bodyMassKg: 82.5 },
        { date: midDate, bodyMassKg: 80.1 },
        { date: recentDate, recoveryScore: 70 },
        { date: todayDate, bodyMassKg: 78.4 },
      ],
      workouts: [],
    },
    auth,
  )).status, 202);

  const all = await callMcpTool(endpoint, 'get_weight_history', {}, 'mcp-weight-token');
  const allPayload = JSON.parse(all.content[0].text);
  assert.equal(allPayload.count, 3);
  assert.deepEqual(allPayload.entries.map((entry) => entry.date), [oldDate, midDate, todayDate]);
  assert.equal(allPayload.unit, 'kg');
  assert.equal(allPayload.latestKg, 78.4);
  assert.equal(allPayload.changeKg, Math.round((78.4 - 82.5) * 10) / 10);

  const recent = await callMcpTool(endpoint, 'get_weight_history', { range: '30d' }, 'mcp-weight-token');
  const recentPayload = JSON.parse(recent.content[0].text);
  assert.deepEqual(recentPayload.entries.map((entry) => entry.date), [todayDate]);
  assert.equal(recentPayload.changeKg, null);

  const explicitRange = await callMcpTool(
    endpoint, 'get_weight_history', { from: midDate, to: midDate }, 'mcp-weight-token',
  );
  const explicitPayload = JSON.parse(explicitRange.content[0].text);
  assert.deepEqual(explicitPayload.entries.map((entry) => entry.date), [midDate]);
});

async function callMcpTool(endpoint, name, args, token = 'mcp-weight-token') {
  const response = await fetch(`${endpoint}/mcp`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      accept: 'application/json, text/event-stream',
    },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: cryptoRandomId(),
      method: 'tools/call',
      params: { name, arguments: args },
    }),
  });
  assert.equal(response.status, 200);
  const text = await response.text();
  const payload = text.startsWith('event:')
    ? JSON.parse(text.split('\n').find((line) => line.startsWith('data: ')).slice(6))
    : JSON.parse(text);
  return payload.result;
}

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

function cryptoRandomId() {
  return Math.floor(Math.random() * 1_000_000);
}
