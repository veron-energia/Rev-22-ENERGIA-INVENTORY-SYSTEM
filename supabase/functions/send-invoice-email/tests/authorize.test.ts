// Who may email a customer their document (the send-invoice-email boundary).
//
// The function used to make no authorization decision at all, so "holds the
// publishable key" was the only barrier — and that key ships in the browser
// bundle. These drive the real decision against a stub database.
import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { authorizeSend, bearerToken, type CallerClient } from '../authorize.ts';

type Stub = {
  user?: { id: string } | null;
  userError?: unknown;
  profile?: { is_active?: boolean } | null;
  storeAccess?: unknown;
  accessError?: unknown;
};

const client = (s: Stub): CallerClient => ({
  auth: { getUser: () => Promise.resolve({ data: { user: s.user ?? null }, error: s.userError ?? null }) },
  from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: s.profile ?? null, error: null }) }) }) }),
  rpc: () => Promise.resolve({ data: s.storeAccess ?? null, error: s.accessError ?? null }),
});

const STAFF = { user: { id: 'u1' }, profile: { is_active: true } };

Deno.test('a request with no bearer token carries no identity', () => {
  assertEquals(bearerToken(null), '');
  assertEquals(bearerToken('apikey abc'), '');
  assertEquals(bearerToken('Bearer  tok  '), 'tok');
  assertEquals(bearerToken('bearer tok'), 'tok', 'the scheme is case-insensitive');
});

Deno.test('a token that resolves to nobody is refused', async () => {
  const d = await authorizeSend(client({ user: null }), null);
  assertEquals(d.ok, false);
  assertEquals(d.ok === false && d.status, 401);
});

Deno.test('a signed-in caller with no staff profile is refused — this is an affiliate login', async () => {
  // The profiles read policy requires a staff role, so an affiliate reads
  // nothing here and the lookup comes back empty.
  const d = await authorizeSend(client({ user: { id: 'aff' }, profile: null }), null);
  assertEquals(d.ok, false);
  assertEquals(d.ok === false && d.status, 403);
});

Deno.test('a staff account that has been deactivated is refused', async () => {
  const d = await authorizeSend(client({ user: { id: 'u1' }, profile: { is_active: false } }), null);
  assertEquals(d.ok, false);
  assertEquals(d.ok === false && d.status, 403);
});

Deno.test('staff may send when no store is named', async () => {
  const d = await authorizeSend(client(STAFF), null);
  assertEquals(d.ok, true);
  assertEquals(d.ok === true && d.userId, 'u1');
});

Deno.test('staff may not send a document from a store they cannot see', async () => {
  const d = await authorizeSend(client({ ...STAFF, storeAccess: false }), 'store-b');
  assertEquals(d.ok, false);
  assertEquals(d.ok === false && d.status, 403);
});

Deno.test('a store-access check that errors is a refusal, not a pass', async () => {
  const d = await authorizeSend(client({ ...STAFF, accessError: new Error('down') }), 'store-b');
  assertEquals(d.ok, false);
  assertEquals(d.ok === false && d.status, 403);
});

Deno.test('anything other than a plain true is a refusal', async () => {
  for (const value of [null, undefined, 'true', 1, {}]) {
    const d = await authorizeSend(client({ ...STAFF, storeAccess: value }), 'store-b');
    assertEquals(d.ok, false, `store access ${JSON.stringify(value)} should not pass`);
  }
});

Deno.test('staff may send from a store they can see', async () => {
  const d = await authorizeSend(client({ ...STAFF, storeAccess: true }), 'store-a');
  assertEquals(d.ok, true);
});
