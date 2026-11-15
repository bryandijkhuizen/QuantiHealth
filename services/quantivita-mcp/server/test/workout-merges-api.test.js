import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import test from 'node:test';

test('merge API is account-scoped, idempotent, reversible and keeps raw sources after reimport', async t => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'quantivita-merges-'));
  const port = await availablePort();
  const server = spawn(process.execPath, ['src/server.js'], {
    cwd: path.resolve(import.meta.dirname, '..'),
    env: { ...process.env, PORT: String(port), QUANTIVITA_DATA_DIR: dataDir, QUANTIVITA_SESSION_SECRET: 'test-secret', QUANTIVITA_MCP_TOKENS: 'merge-mcp-token:alice' },
    stdio: ['ignore','pipe','pipe'],
  });
  let output = ''; server.stdout.on('data', c => output += c); server.stderr.on('data', c => output += c);
  t.after(async () => { server.kill(); if (server.exitCode === null) await once(server, 'exit'); await rm(dataDir, {recursive:true,force:true}); });
  await waitUntilHealthy(port, server, () => output);
  const base = `http://127.0.0.1:${port}`;
  await postJson(`${base}/api/accounts/register`, {accountId:'alice',syncToken:'alice-token'});
  await postJson(`${base}/api/accounts/register`, {accountId:'bob',syncToken:'bob-token'});
  await writeFile(path.join(dataDir,'alice.json'), JSON.stringify({daily:[],workouts:[]}));
  const call = (suffix, body, token = 'alice-token') => fetch(`${base}/api/users/alice/${suffix}`, {
    method: body ? 'POST' : 'GET', headers: {'content-type':'application/json', authorization:`Bearer ${token}`}, body: body ? JSON.stringify(body) : undefined,
  });
  const rows = ['a','b'].map((id,i) => ({id,title:'Cycling',typeCode:3,startTime:new Date(Date.now()-3600000+i*1800000).toISOString(),durationMinutes:20,distanceMeters:8000,energyKcal:200}));
  assert.equal((await call('ingest',{workouts:rows})).status,202);
  assert.equal((await call('workout-merges',{workoutIds:['a','b']},'bob-token')).status,401);
  const preview = await call('workout-merges/preview',{workoutIds:['a','b']});
  assert.equal(preview.status,200);
  assert.equal((await preview.json()).workout.distanceMeters,16000);
  const [first, repeated] = await Promise.all([call('workout-merges',{workoutIds:['a','b']}),call('workout-merges',{workoutIds:['a','b']})]);
  const state = await first.json();
  assert.equal(first.status,200);
  assert.deepEqual(await repeated.json(),state);
  assert.equal(state.workouts.length,1);
  const mergeId = state.workouts[0].merge.id;
  assert.equal((await call('ingest',{workouts:rows})).status,202);
  const health = await (await call('health')).json();
  assert.equal(health.workouts.length,1);
  assert.equal(health.workouts[0].distanceMeters,16000);
  const mcp = await fetch(`${base}/mcp`, {
    method:'POST', headers:{authorization:'Bearer merge-mcp-token','content-type':'application/json',accept:'application/json, text/event-stream'},
    body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'get_workout_details',arguments:{workoutId:`merge:${mergeId}`}}}),
  });
  assert.equal(mcp.status,200);
  const mcpText = await mcp.text();
  assert.ok(mcpText.includes(mergeId));
  assert.match(mcpText, /16000/);
  assert.match(mcpText, /sourceWorkoutIds/);
  const raw = JSON.parse(await readFile(path.join(dataDir,'alice.json'),'utf8'));
  assert.equal(raw.workouts.length,2);
  const undone = await call(`workout-merges/${mergeId}/undo`,{});
  assert.equal(undone.status,200);
  assert.equal((await undone.json()).workouts.length,2);
  assert.equal((await call(`workout-merges/${mergeId}/undo`,{})).status,200);
  assert.equal((await (await call('health')).json()).workouts.length,2);
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
