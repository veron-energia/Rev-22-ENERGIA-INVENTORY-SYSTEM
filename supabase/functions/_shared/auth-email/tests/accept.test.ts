// Accepting an invitation (auth-accept-invitation), without a Supabase project.
//
// 429: a login must have a pending invitation before any password is set. A
// session from an emailed link is not enough on its own: a member of staff or
// an affiliate who opened a reset link has one too.
// 18 Oct 2026 (the Owner): "30 minutes, like reset links". With a pending
// invitation, the password is set only in the 30 minutes after the link was
// opened; after that "This invitation link has expired. Ask for a new
// invitation." The pending-invitation refusals still come first.
// Every name and address is made up.

import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  acceptInvitationRequest, invitationsOfLogin, isInvitationCheck, LINK_EXPIRED_REASON, NOT_INVITED_MESSAGE,
  pendingInvitation, profileStateOf, type AcceptDeps, type InvitationRow, type ProfileState, type TableReader,
} from '../accept.ts';
import {
  cameFromEmailLink, EMAIL_LINK_METHODS, INVITATION_LINK_EXPIRED_MESSAGE, type OwnAccount, type PasswordChange,
} from '../password.ts';

const b64url = (v: unknown) => btoa(JSON.stringify(v)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenWith = (claims: Record<string, unknown>) => `${b64url({ alg: 'ES256' })}.${b64url(claims)}.signature`;
const NOW = 1_791_000_000;
const MINUTE = 60;
const DAY = 86_400;
const linkSession = (method = 'recovery', ago = 60) => tokenWith({ sub: 'auth-1', amr: [{ method, timestamp: NOW - ago }] });

const EMAIL = 'invited.person@example.com';
const PASSWORD = { password: 'a-new-password-429' };

interface World {
  account?: OwnAccount;
  invitations?: InvitationRow[];
  profile?: ProfileState | null;
  change?: PasswordChange;
  accept?: { data: unknown; error: { message: string } | null };
  failInvitations?: boolean;
  failProfile?: boolean;
}

/** Fake collaborators. `seen` records every call, so a test can say nothing was set. */
function world(w: World = {}) {
  const seen: string[] = [];
  const notices: string[] = [];
  const deps: AcceptDeps = {
    readAccount: () => { seen.push('readAccount'); return Promise.resolve(w.account ?? { status: 'ok', userId: 'auth-1', email: EMAIL }); },
    invitationsFor: (id) => {
      seen.push(`invitationsFor:${id}`);
      return w.failInvitations ? Promise.reject(new Error('db down')) : Promise.resolve(w.invitations ?? []);
    },
    profileOf: (id) => {
      seen.push(`profileOf:${id}`);
      return w.failProfile ? Promise.reject(new Error('db down'))
        : Promise.resolve(w.profile === undefined ? { invitationStatus: 'pending', deleted: false } : w.profile);
    },
    changePassword: (password) => {
      seen.push(`changePassword:${password}`);
      return Promise.resolve(w.change ?? {
        status: 'ok', userId: 'auth-1', email: EMAIL, displayName: 'Invited Person', changedAt: '2026-10-10T02:00:00Z',
      });
    },
    acceptInDatabase: (id, email) => {
      seen.push(`acceptInDatabase:${id}:${email}`);
      return Promise.resolve(w.accept ?? { data: { activated: true, role: 'staff' }, error: null });
    },
    notifyPasswordChanged: (change) => { notices.push(change.status === 'ok' ? change.email : ''); return Promise.resolve(); },
    log: () => {},
  };
  const passwordSet = () => seen.some(s => s.startsWith('changePassword'));
  const switchedOn = () => seen.some(s => s.startsWith('acceptInDatabase'));
  return { deps, seen, notices, passwordSet, switchedOn };
}

const pending = (email = EMAIL): InvitationRow => ({ status: 'pending', email });

// ── refused before any password is set ──────────────────────────────────────

Deno.test('a login with no invitation is refused, and its password is not changed', async () => {
  // A member of staff who opened a reset link three days ago and stayed signed
  // in on a shared device: before 429 anyone there could set a new password.
  // The link is long past 30 minutes, and they are still told there is no
  // invitation: that refusal comes first.
  const w = world({ invitations: [] });
  const answer = await acceptInvitationRequest(linkSession('recovery', 3 * DAY), PASSWORD, w.deps, NOW);
  assertEquals(answer.status, 403);
  assertEquals(answer.body.error, 'not_activated');
  assertEquals(answer.body.reason, 'not_invited');
  assertEquals(answer.body.message, NOT_INVITED_MESSAGE);
  assert(!w.passwordSet(), 'no password was set');
  assert(!w.switchedOn(), 'nothing was switched on');
  assertEquals(w.notices, []);
  assertEquals(w.seen, ['readAccount', 'invitationsFor:auth-1'], 'looked up by the login the token belongs to');
});

Deno.test('a fresh reset link without an invitation is refused too (the reset page is the way)', async () => {
  for (const method of ['recovery', 'otp', 'magiclink', 'invite']) {
    const w = world({ invitations: [] });
    const answer = await acceptInvitationRequest(linkSession(method, 30), PASSWORD, w.deps, NOW);
    assertEquals(answer.body.reason, 'not_invited', method);
    assert(!w.passwordSet(), method);
  }
});

Deno.test('an affiliate signed in from a reset link is refused, and their password is not changed', async () => {
  // An affiliate's login has no invitation and no staff profile.
  const w = world({
    account: { status: 'ok', userId: 'affiliate-1', email: 'an.affiliate@example.com' },
    invitations: [], profile: null,
  });
  const answer = await acceptInvitationRequest(linkSession('recovery', 2 * 3600), PASSWORD, w.deps, NOW);
  assertEquals(answer.status, 403);
  assertEquals(answer.body.reason, 'not_invited');
  assert(!w.passwordSet() && !w.switchedOn());
  assertEquals(w.seen, ['readAccount', 'invitationsFor:affiliate-1']);
});

Deno.test('a cancelled invitation is refused before any password is set', async () => {
  const w = world({ invitations: [{ status: 'cancelled', email: EMAIL }] });
  const answer = await acceptInvitationRequest(linkSession('invite'), PASSWORD, w.deps, NOW);
  assertEquals(answer.status, 403);
  assertEquals(answer.body.reason, 'cancelled');
  assertStringIncludes(String(answer.body.message), 'cancelled');
  assert(!w.passwordSet() && !w.switchedOn());
});

Deno.test('an invitation already accepted is refused before any password is set', async () => {
  const w = world({ invitations: [{ status: 'accepted', email: EMAIL }] });
  const answer = await acceptInvitationRequest(linkSession('recovery', 10 * DAY), PASSWORD, w.deps, NOW);
  assertEquals(answer.status, 403);
  assertEquals(answer.body.reason, 'already_accepted');
  assertStringIncludes(String(answer.body.message), 'Sign in with your password');
  assert(!w.passwordSet() && !w.switchedOn());
});

Deno.test('an expired invitation, another address, or an unfinished set-up is refused before any password is set', async () => {
  const cases: [World, string][] = [
    [{ invitations: [{ status: 'expired', email: EMAIL }] }, 'expired'],
    [{ invitations: [pending('someone.else@example.com')] }, 'wrong_account'],
    [{ invitations: [pending()], profile: null }, 'not_set_up'],
    [{ invitations: [pending()], profile: { invitationStatus: 'accepted', deleted: false } }, 'not_set_up'],
    [{ invitations: [pending()], profile: { invitationStatus: 'pending', deleted: true } }, 'not_set_up'],
  ];
  for (const [given, reason] of cases) {
    const w = world(given);
    const answer = await acceptInvitationRequest(linkSession('invite'), PASSWORD, w.deps, NOW);
    assertEquals(answer.status, 403, reason);
    assertEquals(answer.body.reason, reason);
    assert(!w.passwordSet() && !w.switchedOn(), reason);
  }
});

Deno.test('if the invitation cannot be checked, nothing is set', async () => {
  const cases: World[] = [
    { failInvitations: true },
    { invitations: [pending()], failProfile: true },
    { account: { status: 'error', message: 'auth down' } },
  ];
  for (const given of cases) {
    const w = world(given);
    const answer = await acceptInvitationRequest(linkSession('invite'), PASSWORD, w.deps, NOW);
    assertEquals(answer.status, 503);
    assertEquals(answer.body.error, 'temporarily_unavailable');
    assert(!w.passwordSet());
  }
  const expired = world({ account: { status: 'unauthorized' } });
  const answer = await acceptInvitationRequest(linkSession('invite'), PASSWORD, expired.deps, NOW);
  assertEquals(answer.status, 401);
  assert(!expired.passwordSet());
});

Deno.test('a password sign-in is refused before anything is read', async () => {
  const w = world({ invitations: [pending()] });
  const answer = await acceptInvitationRequest(tokenWith({ amr: [{ method: 'password', timestamp: NOW - 10 }] }), PASSWORD, w.deps, NOW);
  assertEquals(answer.status, 401);
  assertEquals(answer.body.reason, 'not_from_link');
  assertEquals(w.seen, []);
});

// ── a real invitation still works ───────────────────────────────────────────

Deno.test('a real pending invitation sets the password, then switches the account on', async () => {
  const w = world({ invitations: [pending()] });
  const answer = await acceptInvitationRequest(linkSession('invite', 29 * MINUTE), PASSWORD, w.deps, NOW);
  assertEquals(answer, { status: 200, body: { ok: true, role: 'staff' } });
  assertEquals(w.seen, [
    'readAccount', 'invitationsFor:auth-1', 'profileOf:auth-1',
    'changePassword:a-new-password-429', `acceptInDatabase:auth-1:${EMAIL}`,
  ], 'checked first, then the password, then the database');
  assertEquals(w.notices, [EMAIL], 'the "password changed" email is sent');
});

Deno.test('the address is compared without case or spaces', async () => {
  const w = world({ invitations: [pending(EMAIL)], account: { status: 'ok', userId: 'auth-1', email: ' Invited.Person@Example.com' } });
  assertEquals((await acceptInvitationRequest(linkSession('invite'), PASSWORD, w.deps, NOW)).status, 200);
});

Deno.test('a removed member of staff invited again sets up from their recovery link', async () => {
  // Their old login: an accepted invitation from when they first joined, and
  // the new pending one. The pending one is the one accepted, whichever order
  // the rows come in, as in invite_user_accept.
  for (const invitations of [
    [pending(), { status: 'accepted', email: EMAIL }],
    [{ status: 'accepted', email: EMAIL }, pending()],
    [pending(), { status: 'cancelled', email: EMAIL }, { status: 'accepted', email: EMAIL }],
  ]) {
    const w = world({ invitations, profile: { invitationStatus: 'pending', deleted: false } });
    const answer = await acceptInvitationRequest(linkSession('recovery', 10 * MINUTE), PASSWORD, w.deps, NOW);
    assertEquals(answer.status, 200, JSON.stringify(invitations));
    assert(w.passwordSet() && w.switchedOn());
  }
});

Deno.test('the database still has the last word after the password is set', async () => {
  const w = world({
    invitations: [pending()],
    accept: { data: { activated: false, reason: 'cancelled', message: 'This invitation was cancelled and can no longer be used.' }, error: null },
  });
  const answer = await acceptInvitationRequest(linkSession('invite'), PASSWORD, w.deps, NOW);
  assertEquals(answer.status, 403);
  assertEquals(answer.body.reason, 'cancelled');
  assertEquals(w.notices, [], 'no "password changed" email for a refused activation');
});

Deno.test('a password Supabase refuses leaves the invitation pending', async () => {
  const w = world({ invitations: [pending()], change: { status: 'rejected', message: 'Password is too weak.' } });
  const answer = await acceptInvitationRequest(linkSession('invite'), PASSWORD, w.deps, NOW);
  assertEquals(answer, { status: 400, body: { error: 'password_rejected', message: 'Password is too weak.' } });
  assert(!w.switchedOn());
});

// ── 30 minutes, like reset links (the Owner, 18 Oct 2026) ──────────────────

const LINK_EXPIRED_ANSWER = {
  status: 403,
  body: { error: 'not_activated', reason: 'link_expired', message: 'This invitation link has expired. Ask for a new invitation.' },
};

Deno.test('a pending invitation from a link opened more than 30 minutes ago is refused, and its password is not changed', async () => {
  for (const method of EMAIL_LINK_METHODS) {
    for (const ago of [30 * MINUTE + 1, 31 * MINUTE, 3 * 3600, 3 * DAY]) {
      const w = world({ invitations: [pending()] });
      const answer = await acceptInvitationRequest(linkSession(method, ago), PASSWORD, w.deps, NOW);
      assertEquals(answer, LINK_EXPIRED_ANSWER, `${method}, ${ago}s ago`);
      assert(!w.passwordSet() && !w.switchedOn(), `${method}, ${ago}s ago: nothing set`);
      assertEquals(w.notices, []);
      assertEquals(w.seen, ['readAccount', 'invitationsFor:auth-1', 'profileOf:auth-1'],
        'the invitation was checked first, then the age of the link');
    }
  }
  assertEquals(LINK_EXPIRED_REASON, 'link_expired');
  assertEquals(INVITATION_LINK_EXPIRED_MESSAGE, LINK_EXPIRED_ANSWER.body.message);
});

Deno.test('up to 30 minutes after the link was opened, the password is set', async () => {
  for (const method of EMAIL_LINK_METHODS) {
    for (const ago of [0, MINUTE, 29 * MINUTE, 30 * MINUTE]) {
      const w = world({ invitations: [pending()] });
      const answer = await acceptInvitationRequest(linkSession(method, ago), PASSWORD, w.deps, NOW);
      assertEquals(answer, { status: 200, body: { ok: true, role: 'staff' } }, `${method}, ${ago}s ago`);
      assert(w.passwordSet() && w.switchedOn());
    }
  }
});

Deno.test('the 30 minutes are the reset window of auth-change-password, from the same code', async () => {
  for (const ago of [-61, -60, 0, 29 * MINUTE, 30 * MINUTE, 30 * MINUTE + 1, 2 * 3600]) {
    const token = linkSession('invite', ago);
    const w = world({ invitations: [pending()] });
    const answer = await acceptInvitationRequest(token, PASSWORD, w.deps, NOW);
    const opened = cameFromEmailLink(token, NOW);
    assertEquals(answer.status === 200, opened, `${ago}s ago`);
    assertEquals(w.passwordSet(), opened, `${ago}s ago`);
  }
});

Deno.test('the pending-invitation refusals of 10 Oct still come first for a link opened long ago', async () => {
  const cases: [World, string][] = [
    [{ invitations: [] }, 'not_invited'],
    [{ invitations: [{ status: 'cancelled', email: EMAIL }] }, 'cancelled'],
    [{ invitations: [{ status: 'accepted', email: EMAIL }] }, 'already_accepted'],
    [{ invitations: [{ status: 'expired', email: EMAIL }] }, 'expired'],
    [{ invitations: [pending('someone.else@example.com')] }, 'wrong_account'],
    [{ invitations: [pending()], profile: null }, 'not_set_up'],
    [{ invitations: [pending()], profile: { invitationStatus: 'pending', deleted: true } }, 'not_set_up'],
  ];
  for (const [given, reason] of cases) {
    for (const body of [PASSWORD, { check: true }]) {
      const w = world(given);
      const answer = await acceptInvitationRequest(linkSession('invite', 2 * DAY), body, w.deps, NOW);
      assertEquals(answer.status, 403, reason);
      assertEquals(answer.body.reason, reason, `${reason} is told, not that the link expired`);
      assert(!w.passwordSet() && !w.switchedOn(), reason);
    }
  }
  // Could not check: the same answer as for a fresh link, and nothing set.
  const down = world({ failInvitations: true });
  const answer = await acceptInvitationRequest(linkSession('invite', 2 * DAY), PASSWORD, down.deps, NOW);
  assertEquals(answer.status, 503);
  assert(!down.passwordSet());
});

Deno.test('a password sign-in is refused before anything is read, however recent, with or without an old link', async () => {
  for (const amr of [
    [{ method: 'password', timestamp: NOW - 1 }],
    [{ method: 'password', timestamp: NOW - 2 * DAY }],
  ]) {
    const w = world({ invitations: [pending()] });
    const answer = await acceptInvitationRequest(tokenWith({ sub: 'auth-1', amr }), PASSWORD, w.deps, NOW);
    assertEquals(answer.body.reason, 'not_from_link');
    assertEquals(w.seen, []);
  }
  // A fresh password sign-in beside a link opened long ago: the link is what
  // counts, and it is too old.
  const w = world({ invitations: [pending()] });
  const answer = await acceptInvitationRequest(tokenWith({ sub: 'auth-1', amr: [
    { method: 'password', timestamp: NOW - 5 }, { method: 'recovery', timestamp: NOW - 2 * 3600 },
  ] }), PASSWORD, w.deps, NOW);
  assertEquals(answer, LINK_EXPIRED_ANSWER);
  assert(!w.passwordSet());
});

Deno.test('a removed member of staff invited again whose recovery link was opened over 30 minutes ago is refused', async () => {
  const w = world({ invitations: [pending(), { status: 'accepted', email: EMAIL }] });
  const answer = await acceptInvitationRequest(linkSession('recovery', 2 * DAY), PASSWORD, w.deps, NOW);
  assertEquals(answer, LINK_EXPIRED_ANSWER);
  assert(!w.passwordSet() && !w.switchedOn());
});

// ── the page's question ─────────────────────────────────────────────────────

Deno.test('{ check: true } answers whether there is a pending invitation and sets nothing', async () => {
  const yes = world({ invitations: [pending()] });
  assertEquals(await acceptInvitationRequest(linkSession('invite'), { check: true }, yes.deps, NOW),
    { status: 200, body: { ok: true, pending: true } });
  assert(!yes.passwordSet() && !yes.switchedOn());

  const no = world({ invitations: [] });
  const answer = await acceptInvitationRequest(linkSession('recovery', 5 * DAY), { check: true }, no.deps, NOW);
  assertEquals(answer.status, 403);
  assertEquals(answer.body.reason, 'not_invited');
  assert(!no.passwordSet());

  // A pending invitation, but the link was opened over 30 minutes ago: the
  // page is told so before it would show the form.
  const old = world({ invitations: [pending()] });
  assertEquals(await acceptInvitationRequest(linkSession('invite', 31 * MINUTE), { check: true }, old.deps, NOW),
    LINK_EXPIRED_ANSWER);
  assert(!old.passwordSet() && !old.switchedOn());
  const fresh = world({ invitations: [pending()] });
  assertEquals(await acceptInvitationRequest(linkSession('invite', 30 * MINUTE), { check: true }, fresh.deps, NOW),
    { status: 200, body: { ok: true, pending: true } });
});

Deno.test('a check carries nothing else; a password request is still validated', async () => {
  assert(isInvitationCheck({ check: true }));
  assert(!isInvitationCheck({ check: 'yes' }));
  assert(!isInvitationCheck({ check: true, password: 'a-new-password-429' }));
  assert(!isInvitationCheck({}));
  const w = world({ invitations: [pending()] });
  const answer = await acceptInvitationRequest(linkSession('invite'), { check: true, password: 'a-new-password-429' }, w.deps, NOW);
  assertEquals(answer.status, 400);
  assert(!w.passwordSet());
  const short = await acceptInvitationRequest(linkSession('invite'), { password: 'short' }, w.deps, NOW);
  assertEquals(short.status, 400);
});

Deno.test('pendingInvitation on its own: a pending row wins over a newer closed one, as in the database', async () => {
  const ok = await pendingInvitation(world({ invitations: [{ status: 'cancelled', email: EMAIL }, pending()] }).deps);
  assertEquals(ok, { ok: true, userId: 'auth-1', email: EMAIL });
});

// ── The two reads auth-accept-invitation makes, against a fake client ──────

/** A fake Supabase client: records the query, answers `rows`. */
function fakeTables(answer: { data: unknown; error: { message: string } | null }) {
  const calls: unknown[][] = [];
  const query = {
    eq: (column: string, value: string) => { calls.push(['eq', column, value]); return query; },
    order: (column: string, options: { ascending: boolean }) => { calls.push(['order', column, options]); return query; },
    limit: (count: number) => { calls.push(['limit', count]); return Promise.resolve(answer); },
    maybeSingle: () => { calls.push(['maybeSingle']); return Promise.resolve(answer); },
  };
  const db: TableReader = {
    from: (table: string) => {
      calls.push(['from', table]);
      return { select: (columns: string) => { calls.push(['select', columns]); return query; } };
    },
  };
  return { db, calls };
}

Deno.test("a login's invitations: user_invitations by auth_user_id, newest first, the last 50", async () => {
  const { db, calls } = fakeTables({ data: [
    { status: 'pending', email_normalized: EMAIL },
    { status: 'cancelled', email_normalized: EMAIL },
    { status: 42, email_normalized: null },
  ], error: null });
  assertEquals(await invitationsOfLogin(db, 'auth-1'), [
    { status: 'pending', email: EMAIL }, { status: 'cancelled', email: EMAIL }, { status: '', email: '' },
  ]);
  assertEquals(calls, [
    ['from', 'user_invitations'], ['select', 'status, email_normalized'], ['eq', 'auth_user_id', 'auth-1'],
    ['order', 'invited_at', { ascending: false }], ['limit', 50],
  ]);
  assertEquals(await invitationsOfLogin(fakeTables({ data: null, error: null }).db, 'auth-1'), []);
  let thrown = false;
  try {
    await invitationsOfLogin(fakeTables({ data: null, error: { message: 'db down' } }).db, 'auth-1');
  } catch {
    thrown = true;
  }
  assert(thrown, 'a failed read throws, so the request is refused as "cannot check"');
});

Deno.test("a login's profile: profiles by id, its invitation state and whether it was removed", async () => {
  const { db, calls } = fakeTables({ data: { invitation_status: 'pending', deleted_at: null }, error: null });
  assertEquals(await profileStateOf(db, 'auth-1'), { invitationStatus: 'pending', deleted: false });
  assertEquals(calls, [['from', 'profiles'], ['select', 'invitation_status, deleted_at'], ['eq', 'id', 'auth-1'], ['maybeSingle']]);
  assertEquals(await profileStateOf(fakeTables({ data: { invitation_status: null, deleted_at: '2026-10-01T00:00:00Z' }, error: null }).db, 'auth-1'),
    { invitationStatus: null, deleted: true });
  assertEquals(await profileStateOf(fakeTables({ data: null, error: null }).db, 'auth-1'), null);
  let thrown = false;
  try {
    await profileStateOf(fakeTables({ data: null, error: { message: 'db down' } }).db, 'auth-1');
  } catch {
    thrown = true;
  }
  assert(thrown);
});

Deno.test('what a login with no invitation is told is invite_user_accept\'s own words', () => {
  assertEquals(NOT_INVITED_MESSAGE, 'There is no invitation for this account.');
});
