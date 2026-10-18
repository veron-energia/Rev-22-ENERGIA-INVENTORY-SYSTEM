// 429 against a real Supabase Auth (GoTrue): a cancelled invitee invited
// again, and who may change a password without the current one.
//
// The SQL suite (invitations-start-again.sql) proves what 429 writes. This
// proves that Supabase Auth behaves the way admin-invite-user and
// auth-change-password now rely on, over HTTP:
//   * an invited login whose invitation is cancelled is blocked (412), and its
//     links give no session;
//   * inviting the same address again: an 'invite' link is made for the same
//     login (its address is not confirmed), but it gives no session while the
//     block stands; once the profile is pending again (invite_user_provisioned)
//     429's staff_login_sync lifts the block and the link gives a session;
//   * once the address is confirmed (a link was opened), an 'invite' link is
//     refused (email_exists) and a recovery link for that login works: the
//     Resend path of 429;
//   * a member of staff who was removed (the Owner, 10 Oct 2026: they may be
//     invited again with their old email): their confirmed login is blocked
//     and its password and links refused; an 'invite' link is refused for
//     it, a recovery link is made for the same login but gives no session
//     until their profile is pending again, when 429's staff_login_sync lifts
//     the block; then the link gives a session, a new password is set, and
//     once accepted they sign in to the same login (their history); while
//     the invitation waits their old password signs in again, but that
//     session may not accept it (auth-accept-invitation), only the link's;
//   * a session opened from any of these links carries the sign-in method the
//     server accepts without the current password ("otp", recent), and a
//     password sign-in does not; checkCurrentPassword tells a right password
//     from a wrong one and closes the session it opens.
//
// It installs 429's staff_login_sync (built from 412's text with 429's own
// anchors, checked against 429's AFTER md5) and 412's trigger function into a
// scratch schema (reinvite429_proof) of the auth database, beside a minimal
// profiles table, so nothing of the application schema there is touched.
// Every login it makes is @sig.invalid; at the end it deletes them, their
// rows in Supabase Auth's audit log and the schema, pass or fail.
//
// LOCAL STACK ONLY. It refuses any URL that is not 127.0.0.1 or localhost.
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, DATABASE_URL
// as for deactivated-login-gotrue.mjs (keys from the environment only, never
// printed). Needs psql on PATH and Node 22.18+ (it imports a .ts file).
//
//   node scripts/permissions/tests/reinvite-gotrue.mjs

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID, createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const M412 = path.join(here, '../../../supabase/412_deactivated_staff_signed_out_and_blocked.sql');
const M429 = path.join(here, '../../../supabase/429_users_invitations_and_payment_methods.sql');
const { SUPABASE_URL: API, SUPABASE_ANON_KEY: ANON, SUPABASE_SERVICE_ROLE_KEY: SERVICE, DATABASE_URL: DB } = process.env;
for (const [k, v] of Object.entries({ SUPABASE_URL: API, SUPABASE_ANON_KEY: ANON, SUPABASE_SERVICE_ROLE_KEY: SERVICE, DATABASE_URL: DB })) {
  if (!v) { console.error(`Set ${k}.`); process.exit(2); }
}
const local = (u) => { try { return ['127.0.0.1', 'localhost', '[::1]'].includes(new URL(u).hostname); } catch { return false; } };
if (!local(API) || !local(DB)) {
  console.error('Refusing: SUPABASE_URL and DATABASE_URL must point at a local stack (127.0.0.1 or localhost).');
  process.exit(2);
}
const { cameFromEmailLink, checkCurrentPassword, changeOwnPassword, mayAcceptInvitation, tokenClaims } =
  await import('../../../supabase/functions/_shared/auth-email/password.ts');

const S = 'reinvite429_proof';
const sql = (q) => execFileSync('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', DB, '-c', q], { encoding: 'utf8' }).trim();
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;

let failures = 0, passes = 0;
const ok = (cond, label, detail = '') => {
  if (cond) { passes++; console.log(`PASS  ${label}`); }
  else { failures++; console.log(`FAIL  ${label}${detail ? ` (${detail})` : ''}`); }
};

async function call(method, route, { key = ANON, token, body } = {}) {
  const headers = { apikey: key, 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API}${route}`, { method, headers, body: body ? JSON.stringify(body) : undefined, redirect: 'manual' });
  const text = await res.text();
  let json = null; try { json = JSON.parse(text); } catch { /* not json */ }
  return { status: res.status, json, code: json?.error_code ?? json?.code ?? null };
}
const admin = (method, route, body) => call(method, `/auth/v1/admin${route}`, { key: SERVICE, token: SERVICE.startsWith('sb_') ? undefined : SERVICE, body });
const verify = (type, hash) => call('POST', '/auth/v1/verify', { body: { type, token_hash: hash } });
const brief = (r) => `${r.status} ${r.code ?? ''}`.trim();

// ── 429's staff_login_sync, built as the migration builds it ────────────────
function install() {
  const m412 = readFileSync(M412, 'utf8');
  const m429 = readFileSync(M429, 'utf8');
  const defs = [...m412.matchAll(/\$def\$([\s\S]*?)\$def\$/g)].map((x) => x[1]);
  let sync = defs.find((d) => d.startsWith('CREATE OR REPLACE FUNCTION public.staff_login_sync(p_user_id uuid)'));
  const trgDef = defs.find((d) => d.startsWith('CREATE OR REPLACE FUNCTION public.trg_staff_login_follows_profile()'));
  const table = /create table public\.staff_login_blocks \(([\s\S]*?)\);\n/.exec(m412)?.[1];
  if (!sync || !trgDef || !table) throw new Error('could not read 412\'s functions and table');
  for (const n of [0, 1, 2]) {
    const anchor = new RegExp(`c_sync_anchor${n} constant text := \\$a\\$([\\s\\S]*?)\\$a\\$;`).exec(m429)?.[1];
    const repl = new RegExp(`c_sync_repl${n}\\s+constant text := \\$r\\$([\\s\\S]*?)\\$r\\$;`).exec(m429)?.[1];
    if (!anchor || !repl || sync.split(anchor).length !== 2) throw new Error(`429's anchor ${n} does not occur once`);
    sync = sync.replace(anchor, () => repl);
  }
  const after = /c_sync_after\s+constant text := '([0-9a-f]{32})'/.exec(m429)?.[1];
  const md5 = createHash('md5').update(sync).digest('hex');
  if (md5 !== after) throw new Error(`the staff_login_sync built here is not 429's (md5 ${md5}, 429 says ${after})`);
  const move = (t) => t.replaceAll('public.', `${S}.`).replace("SET search_path TO 'public'", `SET search_path TO '${S}'`);
  const s = move(sync), trg = move(trgDef);
  for (const t of [s, trg]) if (/\bpublic\./.test(t)) throw new Error('a public name survived the move');
  sql(`begin;
create schema ${S};
create table ${S}.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text not null default '',
  email text, role text not null default 'staff', is_active boolean not null default false, deleted_at timestamptz,
  invitation_status text);
create table ${S}.audit_logs (id uuid primary key default gen_random_uuid(), table_name text not null, record_id uuid,
  action text not null, old_data jsonb, new_data jsonb, changed_by uuid, created_at timestamptz not null default now());
create table ${S}.staff_login_blocks (${table});
${s};
${trg};
create trigger staff_login_follows_profile after insert or update of is_active, deleted_at, invitation_status
  on ${S}.profiles for each row execute function ${S}.trg_staff_login_follows_profile();
commit;`);
}

const users = [], emails = [];
const banYears = (id) => Number(sql(`select coalesce(extract(epoch from banned_until - now()) / 31557600, 0)::int from auth.users where id = ${lit(id)}`));
const reason = (id) => sql(`select coalesce(reason, '') from ${S}.staff_login_blocks where user_id = ${lit(id)}`);
const methods = (token) => (tokenClaims(token)?.amr ?? []).map((e) => e.method).join(',');

async function main() {
  const health = await call('GET', '/auth/v1/health');
  if (health.status !== 200) throw new Error(`Supabase Auth is not answering (${brief(health)})`);
  if (sql(`select count(*) from pg_namespace where nspname = ${lit(S)}`) !== '0') throw new Error(`schema ${S} already exists; remove it first`);
  install();
  ok(true, 'setup: 429\'s staff_login_sync (412\'s text with 429\'s anchors, at 429\'s AFTER md5) and 412\'s trigger installed in a scratch schema');

  // ── An invitee, cancelled ───────────────────────────────────────────────
  const email = `429-proof-${randomUUID().slice(0, 8)}@sig.invalid`;
  emails.push(email);
  const first = await admin('POST', '/generate_link', { type: 'invite', email, data: { invited_to: 'energia_internal' } });
  if (first.json?.id) users.push(first.json.id);
  ok(first.status === 200 && first.json?.id && first.json?.hashed_token, 'invite: Supabase Auth makes the login and its link', brief(first));
  const id = first.json.id;
  sql(`insert into ${S}.profiles (id, email, invitation_status) values (${lit(id)}, ${lit(email)}, 'pending')`);
  ok(banYears(id) === 0, 'invite: a pending invitee is not blocked');
  // invite_user_cancel (429): cancelled and removed.
  sql(`update ${S}.profiles set invitation_status = 'cancelled', deleted_at = now() where id = ${lit(id)}`);
  ok(banYears(id) >= 99 && reason(id) === 'invitation_cancelled',
    'cancel: the login is blocked, recorded as a cancelled invitation although the profile is removed too', `${banYears(id)} ${reason(id)}`);
  const old = await verify('invite', first.json.hashed_token);
  ok(old.status === 403 && old.code === 'user_banned' && !old.json?.access_token, 'cancel: the old link gives no session', brief(old));

  // ── Invited again ───────────────────────────────────────────────────────
  const again = await admin('POST', '/generate_link', { type: 'invite', email });
  ok(again.status === 200 && again.json?.id === id,
    'again: an \'invite\' link is made for the same login (its address is not confirmed), even while it is blocked', brief(again));
  const blocked = await verify('invite', again.json.hashed_token);
  ok(blocked.status === 403 && blocked.code === 'user_banned',
    'again: while the block stands the new link gives no session (so the block must be lifted first)', brief(blocked));
  // invite_user_provisioned (429): the profile is put back as pending.
  sql(`update ${S}.profiles set invitation_status = 'pending', deleted_at = null, is_active = false where id = ${lit(id)}`);
  ok(banYears(id) === 0 && reason(id) === '' && sql(`select count(*) from ${S}.audit_logs where record_id = ${lit(id)} and action = 'staff_login_unblocked'`) === '1',
    'again: back to pending, 429\'s staff_login_sync lifts the block 412 placed');
  const fresh = await admin('POST', '/generate_link', { type: 'invite', email });
  const opened = await verify('invite', fresh.json?.hashed_token);
  ok(opened.status === 200 && opened.json?.access_token, 'again: the new link gives a session', brief(opened));
  ok(cameFromEmailLink(opened.json.access_token),
    'again: that session counts as just from an email link for auth-change-password', methods(opened.json.access_token));

  // ── The address is confirmed now: Resend uses a recovery link ───────────
  const confirmedInvite = await admin('POST', '/generate_link', { type: 'invite', email });
  ok(confirmedInvite.status === 422 && confirmedInvite.code === 'email_exists',
    'resend: an \'invite\' link is refused once the address is confirmed (admin.ts reads this as already_confirmed)', brief(confirmedInvite));
  const signupAgain = await admin('POST', '/generate_link', { type: 'signup', email, password: '' });
  ok(signupAgain.status >= 400, 'resend: so is the signup link the old Resend fell back to', brief(signupAgain));
  const recovery = await admin('POST', '/generate_link', { type: 'recovery', email });
  ok(recovery.status === 200 && recovery.json?.id === id, 'resend: a recovery link is made for the same login', brief(recovery));
  const recOpened = await verify('recovery', recovery.json?.hashed_token);
  ok(recOpened.status === 200 && recOpened.json?.access_token && cameFromEmailLink(recOpened.json.access_token),
    'resend: it gives a session, just from an email link', `${brief(recOpened)} ${recOpened.json?.access_token ? methods(recOpened.json.access_token) : ''}`);

  // ── Passwords ───────────────────────────────────────────────────────────
  const password = `P429-${randomUUID()}`;
  const set = await changeOwnPassword({ supabaseUrl: API, apiKey: ANON, accessToken: recOpened.json.access_token, password });
  ok(set.status === 'ok' && set.userId === id, 'password: set with the session from the link (as auth-change-password does)', set.status);
  const signedIn = await call('POST', '/auth/v1/token?grant_type=password', { body: { email, password } });
  ok(signedIn.status === 200 && !cameFromEmailLink(signedIn.json.access_token),
    'password: a password sign-in is not "just from an email link", so the current password is needed', methods(signedIn.json?.access_token ?? ''));
  const sessionsBefore = Number(sql(`select count(*) from auth.sessions where user_id = ${lit(id)}`));
  const right = await checkCurrentPassword({ supabaseUrl: API, apiKey: ANON, email, password });
  const wrong = await checkCurrentPassword({ supabaseUrl: API, apiKey: ANON, email, password: `${password}-not` });
  const sessionsAfter = Number(sql(`select count(*) from auth.sessions where user_id = ${lit(id)}`));
  ok(right.status === 'ok' && wrong.status === 'wrong', 'password: the current password is told from a wrong one', `${right.status} ${wrong.status}`);
  ok(sessionsAfter === sessionsBefore, 'password: the check closes the session it opened', `${sessionsBefore} -> ${sessionsAfter}`);
}

async function removedStaffInvitedAgain() {
  // ── A member of staff who was removed, invited again ────────────────────
  const email = `429-proof-${randomUUID().slice(0, 8)}@sig.invalid`;
  emails.push(email);
  const oldPassword = `P429-${randomUUID()}`;
  const made = await admin('POST', '/users', { email, password: oldPassword, email_confirm: true });
  if (made.json?.id) users.push(made.json.id);
  ok(made.status === 200 && made.json?.id, 'removed: a member of staff\'s confirmed login, with a password', brief(made));
  const id = made.json.id;
  sql(`insert into ${S}.profiles (id, email, role, is_active, invitation_status) values (${lit(id)}, ${lit(email)}, 'staff', true, 'accepted')`);
  const worked = await call('POST', '/auth/v1/token?grant_type=password', { body: { email, password: oldPassword } });
  ok(worked.status === 200 && banYears(id) === 0, 'removed: they signed in while they worked here', brief(worked));
  // Users & Roles removes them (a deleted date).
  sql(`update ${S}.profiles set is_active = false, deleted_at = now() where id = ${lit(id)}`);
  ok(banYears(id) >= 99 && reason(id) === 'removed', 'removed: their login is blocked (412), as removed', `${banYears(id)} ${reason(id)}`);
  const refused = await call('POST', '/auth/v1/token?grant_type=password', { body: { email, password: oldPassword } });
  ok(refused.status === 400 && refused.code === 'user_banned', 'removed: their old password no longer signs in', brief(refused));

  // Invited again: their address is confirmed, so admin-invite-user uses a
  // recovery link for the same login (invitationLink).
  const invite = await admin('POST', '/generate_link', { type: 'invite', email });
  ok(invite.status === 422 && invite.code === 'email_exists',
    'back: an \'invite\' link is refused for their confirmed login (read as already_confirmed)', brief(invite));
  const early = await admin('POST', '/generate_link', { type: 'recovery', email });
  ok(early.status === 200 && early.json?.id === id, 'back: a recovery link is made for their own login', brief(early));
  const blocked = await verify('recovery', early.json?.hashed_token);
  ok(blocked.status === 403 && blocked.code === 'user_banned' && !blocked.json?.access_token,
    'back: while the block stands it gives no session (so the profile is set up first)', brief(blocked));
  // invite_user_provisioned (429): their profile is the new invitation's, pending.
  sql(`update ${S}.profiles set invitation_status = 'pending', deleted_at = null, is_active = false where id = ${lit(id)}`);
  ok(banYears(id) === 0 && reason(id) === ''
     && sql(`select count(*) from ${S}.audit_logs where record_id = ${lit(id)} and action = 'staff_login_unblocked' and old_data->>'reason' = 'removed'`) === '1',
    'back: pending again, 429\'s staff_login_sync lifts the block 412 placed when they were removed');
  // With the block lifted, their old password signs in again while the
  // invitation waits. auth-accept-invitation refuses that session: only one
  // opened from the emailed link may accept, so the old password alone does
  // not switch them back on.
  const oldAgain = await call('POST', '/auth/v1/token?grant_type=password', { body: { email, password: oldPassword } });
  ok(oldAgain.status === 200 && oldAgain.json?.access_token
     && !mayAcceptInvitation(oldAgain.json.access_token)
     && !cameFromEmailLink(oldAgain.json.access_token, Date.now() / 1000, Number.POSITIVE_INFINITY),
    'back: their old password signs in again while the invitation waits, but that session may not accept it',
    `${brief(oldAgain)} ${oldAgain.json?.access_token ? methods(oldAgain.json.access_token) : ''}`);
  const link = await admin('POST', '/generate_link', { type: 'recovery', email });
  const opened = await verify('recovery', link.json?.hashed_token);
  ok(opened.status === 200 && opened.json?.access_token && opened.json?.user?.id === id && cameFromEmailLink(opened.json.access_token),
    'back: the recovery link gives a session for their own login, just from an email link', brief(opened));
  ok(mayAcceptInvitation(opened.json.access_token),
    'back: that session may accept the invitation (auth-accept-invitation)', methods(opened.json.access_token));
  // auth-accept-invitation: a new password with that session, then invite_user_accept.
  const newPassword = `P429-${randomUUID()}`;
  const set = await changeOwnPassword({ supabaseUrl: API, apiKey: ANON, accessToken: opened.json.access_token, password: newPassword });
  sql(`update ${S}.profiles set is_active = true, invitation_status = 'accepted' where id = ${lit(id)}`);
  ok(set.status === 'ok' && set.userId === id && banYears(id) === 0 && reason(id) === '',
    'accept: a new password is set and they are switched on; the login stays open', set.status);
  const back = await call('POST', '/auth/v1/token?grant_type=password', { body: { email, password: newPassword } });
  const stale = await call('POST', '/auth/v1/token?grant_type=password', { body: { email, password: oldPassword } });
  ok(back.status === 200 && back.json?.user?.id === id && stale.status === 400,
    'accept: they sign in with the new password to the same login (their history stays linked); the old one is gone',
    `${brief(back)} / old ${brief(stale)}`);
}

async function cleanup() {
  for (const uid of users) {
    const r = await admin('DELETE', `/users/${uid}`);
    if (r.status !== 200) { try { sql(`delete from auth.users where id = ${lit(uid)}`); } catch { /* reported below */ } }
  }
  try { sql(`set client_min_messages = warning; drop schema if exists ${S} cascade`); } catch { /* reported below */ }
  const mine = [...users, ...emails].map((v) => lit(`%${v}%`)).join(',');
  if (mine) { try { sql(`delete from auth.audit_log_entries where payload::text like any (array[${mine}])`); } catch { /* reported below */ } }
  const leftUsers = users.length ? Number(sql(`select count(*) from auth.users where id in (${users.map(lit).join(',')})`)) : 0;
  const leftAudit = mine ? Number(sql(`select count(*) from auth.audit_log_entries where payload::text like any (array[${mine}])`)) : 0;
  const leftSchema = Number(sql(`select count(*) from pg_namespace where nspname = ${lit(S)}`));
  ok(leftUsers === 0 && leftAudit === 0 && leftSchema === 0,
    `cleanup: the ${users.length} made-up logins, their Supabase Auth audit rows and the scratch schema are gone`,
    `logins left ${leftUsers}, audit rows left ${leftAudit}, schema left ${leftSchema}`);
}

try {
  await main();
  await removedStaffInvitedAgain();
} catch (e) {
  failures++;
  console.log(`FAIL  ${e.message}`);
} finally {
  await cleanup();
}
console.log(`${failures ? 'FAILED' : 'PASSED'}: ${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
