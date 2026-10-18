// Changing your own password (auth-change-password), without a Supabase project.
//
// 429: a session alone does not change a password. A session from an email
// link opened in the last 30 minutes may; any other session must give the
// current password, which Supabase Auth checks first. In every refusal
// nothing is changed and no email is sent. Every name and address is made up.

import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { changeOwnPasswordRequest, type ChangeDeps } from '../change.ts';
import type { CurrentPasswordCheck, OwnAccount, PasswordChange } from '../password.ts';

const b64url = (v: unknown) => btoa(JSON.stringify(v)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenWith = (claims: Record<string, unknown>) => `${b64url({ alg: 'ES256' })}.${b64url(claims)}.signature`;
const NOW = 1_791_000_000;
const MINUTE = 60;
const session = (method: string, ago: number) => tokenWith({ sub: 'auth-1', amr: [{ method, timestamp: NOW - ago }] });
const PASSWORD_SESSION = session('password', 5 * MINUTE);
const FRESH_LINK = session('recovery', 5 * MINUTE);
const OLD_LINK = session('recovery', 31 * MINUTE);

const EMAIL = 'staff.member@example.com';
const NEW = { password: 'a-new-password-429' };
const WITH_CURRENT = { password: 'a-new-password-429', current_password: 'the-old-password' };

interface World {
  account?: OwnAccount;
  check?: CurrentPasswordCheck;
  change?: PasswordChange;
  notified?: boolean;
  failNotify?: boolean;
  throwIn?: 'readAccount' | 'checkCurrentPassword' | 'changePassword';
}

/** Fake collaborators. `seen` records every call in order. */
function world(w: World = {}) {
  const seen: string[] = [];
  const logs: string[] = [];
  const deps: ChangeDeps = {
    readAccount: () => {
      seen.push('readAccount');
      if (w.throwIn === 'readAccount') return Promise.reject(new Error('down'));
      return Promise.resolve(w.account ?? { status: 'ok', userId: 'auth-1', email: EMAIL });
    },
    checkCurrentPassword: (email, password) => {
      seen.push(`checkCurrentPassword:${email}:${password}`);
      if (w.throwIn === 'checkCurrentPassword') return Promise.reject(new Error('down'));
      return Promise.resolve(w.check ?? { status: 'ok' });
    },
    changePassword: (password, current) => {
      seen.push(`changePassword:${password}:${current ?? ''}`);
      if (w.throwIn === 'changePassword') return Promise.reject(new Error('down'));
      return Promise.resolve(w.change ?? {
        status: 'ok', userId: 'auth-1', email: EMAIL, displayName: 'Staff Member', changedAt: '2026-10-10T02:00:00Z',
      });
    },
    notify: (change) => {
      seen.push(`notify:${change.email}`);
      return w.failNotify ? Promise.reject(new Error('pabbly down')) : Promise.resolve(w.notified ?? true);
    },
    log: (event, fields) => { logs.push(`${event} ${JSON.stringify(fields)}`); },
  };
  const changed = () => seen.some(s => s.startsWith('changePassword'));
  const emailed = () => seen.some(s => s.startsWith('notify'));
  return { deps, seen, logs, changed, emailed };
}

Deno.test('no session: 401, and nothing is read, checked or changed', async () => {
  const w = world();
  const answer = await changeOwnPasswordRequest(null, NEW, w.deps, NOW);
  assertEquals(answer.status, 401);
  assertEquals(answer.body.error, 'unauthorized');
  assertEquals(w.seen, []);
});

Deno.test('a body that is not a password change: 400, and nothing is called', async () => {
  for (const body of [{}, { password: 'short' }, { password: 'a-new-password-429', email: 'victim@example.com' }]) {
    const w = world();
    const answer = await changeOwnPasswordRequest(FRESH_LINK, body, w.deps, NOW);
    assertEquals(answer.status, 400, JSON.stringify(body));
    assertEquals(answer.body.error, 'invalid_request');
    assertEquals(w.seen, []);
  }
});

Deno.test('a password session with no current password: 400 current_password_required, nothing read or changed', async () => {
  const w = world();
  const answer = await changeOwnPasswordRequest(PASSWORD_SESSION, NEW, w.deps, NOW);
  assertEquals(answer.status, 400);
  assertEquals(answer.body.error, 'current_password_required');
  assertEquals(answer.body.message, 'Enter your current password to change it.');
  assertEquals(w.seen, [], 'readAccount, checkCurrentPassword and changePassword not called');
});

Deno.test('a link opened more than 30 minutes ago, with no current password: told so, nothing changed', async () => {
  for (const method of ['recovery', 'otp', 'magiclink', 'invite']) {
    const w = world();
    const answer = await changeOwnPasswordRequest(session(method, 31 * MINUTE), NEW, w.deps, NOW);
    assertEquals(answer.status, 400, method);
    assertEquals(answer.body.error, 'current_password_required');
    assertStringIncludes(String(answer.body.message), 'more than 30 minutes ago');
    assertStringIncludes(String(answer.body.message), 'request a new link');
    assertEquals(w.seen, [], method);
  }
});

Deno.test('a link opened within 30 minutes, with no current password: changed once, no check', async () => {
  for (const [method, ago] of [['recovery', 60], ['otp', 29 * MINUTE], ['magiclink', 0], ['invite', 10 * MINUTE]] as const) {
    const w = world();
    const answer = await changeOwnPasswordRequest(session(method, ago), NEW, w.deps, NOW);
    assertEquals(answer.status, 200, `${method} ${ago}`);
    assertEquals(answer.body, { ok: true, password_changed: true, notified: true });
    assertEquals(w.seen, ['changePassword:a-new-password-429:', 'notify:staff.member@example.com'], `${method} ${ago}`);
  }
});

Deno.test('the right current password: checked, then changed, in that order; it goes to Supabase too', async () => {
  for (const token of [PASSWORD_SESSION, OLD_LINK]) {
    const w = world();
    const answer = await changeOwnPasswordRequest(token, WITH_CURRENT, w.deps, NOW);
    assertEquals(answer.status, 200);
    assertEquals(answer.body.password_changed, true);
    assertEquals(w.seen, [
      'readAccount',
      'checkCurrentPassword:staff.member@example.com:the-old-password',
      'changePassword:a-new-password-429:the-old-password',
      'notify:staff.member@example.com',
    ]);
  }
});

Deno.test('a fresh link that also gives the current password: no check, but it still goes to Supabase', async () => {
  const w = world();
  const answer = await changeOwnPasswordRequest(FRESH_LINK, WITH_CURRENT, w.deps, NOW);
  assertEquals(answer.status, 200);
  assertEquals(w.seen, ['changePassword:a-new-password-429:the-old-password', 'notify:staff.member@example.com']);
});

Deno.test('a wrong current password: 400 current_password_wrong, nothing changed', async () => {
  const w = world({ check: { status: 'wrong' } });
  const answer = await changeOwnPasswordRequest(PASSWORD_SESSION, WITH_CURRENT, w.deps, NOW);
  assertEquals(answer.status, 400);
  assertEquals(answer.body.error, 'current_password_wrong');
  assert(!w.changed() && !w.emailed());
  assert(w.logs.some(l => l.startsWith('auth_email.password_change_refused')));
});

Deno.test('the current-password check rate limited: 429; failed or thrown: 503; nothing changed', async () => {
  const cases: [World, number, string][] = [
    [{ check: { status: 'rate_limited' } }, 429, 'rate_limited'],
    [{ check: { status: 'error', message: 'auth answered 500' } }, 503, 'temporarily_unavailable'],
    [{ throwIn: 'checkCurrentPassword' }, 503, 'temporarily_unavailable'],
  ];
  for (const [w0, status, error] of cases) {
    const w = world(w0);
    const answer = await changeOwnPasswordRequest(PASSWORD_SESSION, WITH_CURRENT, w.deps, NOW);
    assertEquals(answer.status, status, JSON.stringify(w0));
    assertEquals(answer.body.error, error);
    assert(!w.changed() && !w.emailed(), JSON.stringify(w0));
  }
});

Deno.test('the account cannot be read: unauthorized is 401; an error, no address or a throw is 503; nothing checked or changed', async () => {
  const cases: [World, number][] = [
    [{ account: { status: 'unauthorized' } }, 401],
    [{ account: { status: 'error', message: 'auth answered 500' } }, 503],
    [{ account: { status: 'ok', userId: 'auth-1', email: '' } }, 503],
    [{ throwIn: 'readAccount' }, 503],
  ];
  for (const [w0, status] of cases) {
    const w = world(w0);
    const answer = await changeOwnPasswordRequest(PASSWORD_SESSION, WITH_CURRENT, w.deps, NOW);
    assertEquals(answer.status, status, JSON.stringify(w0));
    assertEquals(w.seen, ['readAccount'], JSON.stringify(w0));
  }
});

Deno.test('Supabase refusing the change: unauthorized 401, its own words 400, an outage 503; no email', async () => {
  const cases: [World, number, string][] = [
    [{ change: { status: 'unauthorized' } }, 401, 'unauthorized'],
    [{ change: { status: 'rejected', message: 'New password should be different from the old password.' } }, 400, 'password_rejected'],
    [{ change: { status: 'error', message: 'auth request failed' } }, 503, 'temporarily_unavailable'],
    [{ throwIn: 'changePassword' }, 503, 'temporarily_unavailable'],
  ];
  for (const [w0, status, error] of cases) {
    const w = world(w0);
    const answer = await changeOwnPasswordRequest(FRESH_LINK, NEW, w.deps, NOW);
    assertEquals(answer.status, status, JSON.stringify(w0));
    assertEquals(answer.body.error, error);
    assert(!w.emailed(), 'no "password changed" email for a change that did not happen');
  }
  const w = world({ change: { status: 'rejected', message: 'New password should be different from the old password.' } });
  const answer = await changeOwnPasswordRequest(FRESH_LINK, NEW, w.deps, NOW);
  assertEquals(answer.body.message, 'New password should be different from the old password.');
});

Deno.test('the email failing does not undo the change: still 200, notified false', async () => {
  for (const w0 of [{ failNotify: true }, { notified: false }]) {
    const w = world(w0);
    const answer = await changeOwnPasswordRequest(FRESH_LINK, NEW, w.deps, NOW);
    assertEquals(answer.status, 200, JSON.stringify(w0));
    assertEquals(answer.body, { ok: true, password_changed: true, notified: false });
  }
});
