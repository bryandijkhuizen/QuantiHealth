import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

// Use a date within the default 30-day lookback window so this test does not
// silently start failing as real time passes a hardcoded calendar date.
const baseDate = new Date(Date.now() - 5 * 24 * 60 * 60 * 1000);
baseDate.setUTCHours(18, 0, 0, 0);
const isoAt = (offsetMinutes = 0) => new Date(baseDate.getTime() + offsetMinutes * 60000).toISOString();


test('connects, syncs, stores and exposes Progressa exercise details through MCP', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-progressa-flow-'));
  let workoutRequests = 0;
  const upstream = http.createServer((request, response) => {
    if (request.url === '/api/quantivita/refresh-token') {
      response.setHeader('content-type', 'application/json');
      response.end(JSON.stringify({ accessToken: 'progressa-refreshed-token', refreshToken: 'rotated-refresh-token' }));
      return;
    }
    assert.match(request.url, /^\/api\/users\/progressa-user\/workouts/);
    const params = new URL(request.url, 'http://localhost').searchParams;
    if (params.get('metric') === 'progress-index') {
      assert.equal(params.get('from'), '2026-09-21');
      assert.equal(request.headers.authorization, 'Bearer progressa-refreshed-token');
      response.end(JSON.stringify({loggedDates: ['2026-09-21','2026-11-11'], exercises: [{id:'leg',index:1.26}]}));
      return;
    }
    assert.equal(params.get('linkedOnly'), 'true');
    workoutRequests += 1;
    if (workoutRequests === 1) {
      assert.equal(request.headers.authorization, 'Bearer progressa-access-token');
      response.statusCode = 401;
      response.end(JSON.stringify({ error: 'Invalid or expired access token' }));
      return;
    }
    assert.equal(request.headers.authorization, 'Bearer progressa-refreshed-token');
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify([
      {
        workout_id: 'workout-1',
        exercise_id: 'bench-press',
        weight_kg: 20,
        reps: 10,
        rir: 4,
        is_warmup: true,
        created_at: isoAt(0),
        workouts: { id: 'workout-1', title: 'Push day', created_at: isoAt(0) },
        exercises: { id: 'bench-press', name: 'Bench Press', default_muscles: 'Chest' },
        health_activity: {
          activity_type: 'Traditional Strength Training',
          health_start: isoAt(0), health_end: isoAt(60), duration_secs: 3600,
        },
      },
      {
        workout_id: 'workout-1',
        exercise_id: 'bench-press',
        weight_kg: 60, base_weight_kg: 10, added_weight_kg: 50,
        reps: 8,
        rir: 2,
        side: 'both',
        is_warmup: false,
        created_at: isoAt(3),
        workouts: { id: 'workout-1', title: 'Push day', created_at: isoAt(0) },
        exercises: { id: 'bench-press', name: 'Bench Press', default_muscles: 'Chest' },
        health_activity: {
          activity_type: 'Traditional Strength Training',
          health_start: isoAt(0), health_end: isoAt(60), duration_secs: 3600,
        },
      },
    ]));
  });
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');

  const port = await availablePort();
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      QUANTIVITA_DATA_DIR: dataDir,
      QUANTIVITA_SESSION_SECRET: 'progressa-flow-test-secret',
      QUANTIVITA_MCP_TOKENS: 'mcp-test-token:progressa-flow-account',
      PROGRESSA_API_BASE_URL: `http://127.0.0.1:${upstream.address().port}`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  server.stdout.on('data', (chunk) => { output += chunk; });
  server.stderr.on('data', (chunk) => { output += chunk; });

  t.after(async () => {
    server.kill('SIGTERM');
    if (server.exitCode === null) await once(server, 'exit');
    upstream.close();
    await once(upstream, 'close');
    await rm(dataDir, { recursive: true, force: true });
  });

  await waitUntilHealthy(port, server, () => output);
  const endpoint = `http://127.0.0.1:${port}`;
  const accountId = 'progressa-flow-account';
  const syncToken = 'quantivita-sync-token';
  const auth = { authorization: `Bearer ${syncToken}` };

  assert.equal((await postJson(`${endpoint}/api/accounts/register`, { accountId, syncToken })).status, 202);
  assert.equal((await postJson(
    `${endpoint}/api/users/${accountId}/integrations/progressa/connect`,
    { progressaUserId: 'progressa-user', accessToken: 'progressa-access-token', refreshToken: 'progressa-refresh-token' },
    auth,
  )).status, 202);
  assert.equal((await postJson(
    `${endpoint}/api/users/${accountId}/ingest`,
    {
      profile: {}, daily: [],
      workouts: [{
        id: 'health-activity-1', source: 'healthkit', title: 'Strength Training',
        startTime: isoAt(0), durationMinutes: 60, energyKcal: 300,
      }],
    },
    auth,
  )).status, 202);

  const status = await fetch(`${endpoint}/api/users/${accountId}/integrations/progressa`, { headers: auth });
  assert.equal(status.status, 200);
  assert.equal((await status.json()).connected, true);

  const synced = await fetch(`${endpoint}/api/users/${accountId}/integrations/progressa/workouts?limit=50`, { headers: auth });
  assert.equal(synced.status, 200);
  const workout = (await synced.json()).workouts[0];
  assert.equal(workoutRequests, 2);
  assert.equal(workout.title, 'Push day');
  assert.equal(workout.progressaDetails.exerciseCount, 1);
  assert.equal(workout.progressaDetails.totalSets, 2);
  assert.equal(workout.progressaDetails.exercises[0].name, 'Bench Press');
  assert.equal(workout.progressaDetails.exercises[0].muscleGroup, 'Chest');
  assert.equal(workout.progressaDetails.exercises[0].sets[1].weightKg, 60);
  assert.equal(workout.progressaDetails.exercises[0].sets[1].reps, 8);

  const stored = await fetch(`${endpoint}/api/users/${accountId}/workouts`, { headers: auth });
  const storedWorkouts = await stored.json();
  assert.equal(storedWorkouts.some((item) => item.source === 'progressa'), false);
  const storedHealthActivity = storedWorkouts.find((item) => item.id === 'health-activity-1');
  assert.equal(storedHealthActivity.externalWorkoutId, 'workout-1');
  assert.equal(storedHealthActivity.progressaDetails.totalSets, 2);

  const mcp = await fetch(`${endpoint}/mcp`, {
    method: 'POST',
    headers: { authorization: 'Bearer mcp-test-token', 'content-type': 'application/json', accept: 'application/json, text/event-stream' },
    body: JSON.stringify({
      jsonrpc: '2.0', id: 1, method: 'tools/call',
      params: { name: 'get_workout_details', arguments: { workoutId: 'workout-1' } },
    }),
  });
  assert.equal(mcp.status, 200);
  const mcpText = await mcp.text();
  assert.match(mcpText, /Bench Press/);
  assert.match(mcpText, /"baseWeightKg":10/);
  assert.match(mcpText, /"addedWeightKg":50/);
  assert.match(mcpText, /"totalWeightKg":60/);
  assert.equal(workout.progressaDetails.totalVolumeKg, 680);
  const index = await fetch(`${endpoint}/api/users/${accountId}/integrations/progressa/progress-index?from=2026-09-21`, {headers: auth});
  assert.equal((await index.json()).exercises[0].index, 1.26);
  const mcpIndex = await fetch(`${endpoint}/mcp`, {
    method: 'POST', headers: {authorization:'Bearer mcp-test-token','content-type':'application/json',accept:'application/json, text/event-stream'},
    body: JSON.stringify({jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'get_progress_index',arguments:{from:'2026-09-21'}}}),
  });
  assert.match(await mcpIndex.text(), /"index":1.26/);
  assert.match(mcpText, /"totalSets":2/);
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
