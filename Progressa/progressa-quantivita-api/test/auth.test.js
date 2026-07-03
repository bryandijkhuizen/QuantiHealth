import assert from 'node:assert/strict';
import test from 'node:test';
import { authenticatedUser } from '../src/auth.js';

function client(result) {
  return { auth: { getUser: async () => result } };
}

test('returns the verified Supabase user', async () => {
  const user = { id: 'verified-user' };
  assert.equal(await authenticatedUser(client({ data: { user }, error: null }), 'token'), user);
});

test('rejects a missing token without contacting Supabase', async () => {
  let called = false;
  const supabase = { auth: { getUser: async () => { called = true; } } };

  assert.equal(await authenticatedUser(supabase, ''), null);
  assert.equal(called, false);
});

test('rejects invalid or expired tokens reported by Supabase', async () => {
  const result = { data: { user: null }, error: new Error('JWT expired') };
  assert.equal(await authenticatedUser(client(result), 'expired-token'), null);
});

test('rejects responses with an auth error even if user data is present', async () => {
  const result = {
    data: { user: { id: 'unsigned-payload-sub' } },
    error: new Error('Invalid JWT signature'),
  };
  assert.equal(await authenticatedUser(client(result), 'forged-token'), null);
});

test('rejects users without an id and upstream auth failures', async () => {
  assert.equal(
    await authenticatedUser(client({ data: { user: {} }, error: null }), 'token'),
    null,
  );
  const failingClient = { auth: { getUser: async () => { throw new Error('network'); } } };
  assert.equal(await authenticatedUser(failingClient, 'token'), null);
});
