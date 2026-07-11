import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

test('MCP always reports advanced metric coverage and missing daily rows', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-mcp-coverage-'));
  const port = await availablePort();
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      QUANTIVITA_DATA_DIR: dataDir,
      QUANTIVITA_SESSION_SECRET: 'mcp-coverage-test-secret',
      QUANTIVITA_MCP_TOKENS: 'mcp-coverage-token:mcp-coverage-account',
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
  const accountId = 'mcp-coverage-account';
  const syncToken = 'mcp-coverage-sync-token';
  const auth = { authorization: `Bearer ${syncToken}` };
  const recentWorkoutStart = new Date(Date.now() - 86_400_000).toISOString();

  assert.equal((await postJson(`${endpoint}/api/accounts/register`, { accountId, syncToken })).status, 202);
  assert.equal((await postJson(
    `${endpoint}/api/users/${accountId}/ingest`,
    {
      profile: {},
      daily: [
        {
          date: '2026-06-01',
          recoveryScore: 70,
          sleepMinutes: 430,
          hrvMs: 48,
          restingHeartBpm: 57,
          activeEnergyKcal: 300,
          steps: 7000,
          dietaryEnergyKcal: 0,
          dietaryWaterMl: 0,
        },
        {
          date: '2026-06-03',
          recoveryScore: 78,
          sleepMinutes: 455,
          hrvMs: 52,
          restingHeartBpm: 55,
          activeEnergyKcal: 420,
          steps: 8200,
        },
      ],
      workouts: [{
        id: 'climb-1',
        title: 'Workout',
        startTime: recentWorkoutStart,
        durationMinutes: 50,
        energyKcal: 530,
        distanceMeters: 0,
        averageHeartRate: 152,
        hasRoute: true,
        typeCode: 11,
      }, {
        id: 'old-workout',
        title: 'Old ride',
        startTime: '2025-01-03T07:30:00Z',
        durationMinutes: 40,
        energyKcal: 400,
      }],
    },
    auth,
  )).status, 202);

  const workouts = await fetch(`${endpoint}/api/users/${accountId}/workouts`, { headers: auth });
  assert.equal(workouts.status, 200);
  const recentRestWorkouts = await workouts.json();
  assert.equal(recentRestWorkouts.find((item) => item.id === 'climb-1').title, 'Rock Climbing');
  assert.equal(recentRestWorkouts.some((item) => item.id === 'old-workout'), false);

  const recentWorkouts = await callMcpTool(endpoint, 'get_workouts', {});
  const recentPayload = JSON.parse(recentWorkouts.content[0].text);
  assert.equal(recentPayload.workouts.some((item) => item.id === 'workout:climb-1'), true);
  assert.equal(recentPayload.workouts.some((item) => item.id === 'workout:old-workout'), false);

  const allWorkouts = await callMcpTool(endpoint, 'get_workouts', { all: true });
  const allPayload = JSON.parse(allWorkouts.content[0].text);
  assert.equal(allPayload.workouts.some((item) => item.id === 'workout:climb-1'), true);
  assert.equal(allPayload.workouts.some((item) => item.id === 'workout:old-workout'), true);

  const summary = await callMcpTool(endpoint, 'get_latest_summary', {});
  const summaryText = JSON.parse(summary.content[0].text);
  const summaryDoc = JSON.parse(summaryText.text);
  assert.equal(summaryDoc.quantivitaCoverage.missingDays.dates.includes('2026-06-02'), true);
  assert.equal(summaryDoc.quantivitaCoverage.vo2Max.available, false);
  assert.equal(summaryDoc.quantivitaCoverage.bodyBattery.available, true);
  assert.equal(summaryDoc.quantivitaCoverage.bodyBattery.source, 'estimated');
  assert.equal(summaryDoc.quantivitaCoverage.kilometerSplits.available, false);
  assert.equal(summaryDoc.quantivitaCoverage.nutrition.available, false);
  assert.equal(summaryDoc.quantivitaCoverage.hydration.available, false);
  assert.equal(summaryDoc.recentWorkouts.find((item) => item.id === 'climb-1').title, 'Rock Climbing');

  const missingDay = await callMcpTool(endpoint, 'get_daily_health', { date: '2026-06-02' });
  const missingText = JSON.parse(missingDay.content[0].text);
  const missingDoc = JSON.parse(missingText.text);
  assert.equal(missingDoc.day.available, false);
  assert.equal(missingDoc.quantivitaCoverage.missingDays.dates.includes('2026-06-02'), true);
});

test('MCP summary includes up to 365 daily rows', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-mcp-history-'));
  const port = await availablePort();
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      QUANTIVITA_DATA_DIR: dataDir,
      QUANTIVITA_SESSION_SECRET: 'mcp-history-test-secret',
      QUANTIVITA_MCP_TOKENS: 'mcp-history-token:mcp-history-account',
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
  const accountId = 'mcp-history-account';
  const syncToken = 'mcp-history-sync-token';
  const auth = { authorization: `Bearer ${syncToken}` };
  const latest = new Date();
  latest.setUTCHours(0, 0, 0, 0);
  const daily = Array.from({ length: 400 }, (_, index) => {
    const date = new Date(latest);
    date.setUTCDate(latest.getUTCDate() - (399 - index));
    return { date: date.toISOString().slice(0, 10), recoveryScore: 60 + (index % 20) };
  });

  assert.equal((await postJson(`${endpoint}/api/accounts/register`, { accountId, syncToken })).status, 202);
  assert.equal((await postJson(`${endpoint}/api/users/${accountId}/ingest`, { profile: {}, daily, workouts: [] }, auth)).status, 202);

  const summary = await callMcpTool(endpoint, 'get_latest_summary', {}, 'mcp-history-token');
  const summaryText = JSON.parse(summary.content[0].text);
  const summaryDoc = JSON.parse(summaryText.text);
  assert.equal(summaryDoc.recentDaily.length, 365);
  assert.equal(summaryDoc.recentDaily.at(0).date, latest.toISOString().slice(0, 10));
  const oldestExpected = new Date(latest);
  oldestExpected.setUTCDate(latest.getUTCDate() - 364);
  assert.equal(summaryDoc.recentDaily.at(-1).date, oldestExpected.toISOString().slice(0, 10));
  assert.equal(summaryText.metadata.historyDays, '365');
});

async function callMcpTool(endpoint, name, args, token = 'mcp-coverage-token') {
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
