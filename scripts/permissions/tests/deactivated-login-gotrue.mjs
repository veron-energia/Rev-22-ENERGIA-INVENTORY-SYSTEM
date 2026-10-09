// 412 against a real Supabase Auth (GoTrue): a closed staff profile's login is
// signed out and cannot sign in; reopening the profile lets it sign in again.
//
// The SQL suite (deactivated-login-blocked.sql) proves what 412 writes. This
// proves that what it writes is what Supabase Auth obeys, over HTTP, the way
// the app and the Edge Functions talk to it:
//   * a made-up login signs in with a password on two devices and refreshes;
//   * its profile is switched off: both refresh tokens stop working, the
//     access tokens are refused by Supabase Auth (/user, the password change
//     auth-change-password makes), a password sign-in, a recovery link and a
//     magic link are refused, and reading the login (admin API) still works:
//     the ban is a finite time, not 'infinity'. The old tokens are refused
//     because their session is gone (refresh_token_not_found,
//     session_not_found), not only because of the ban: with the ban lifted
//     by hand for a moment they are still refused;
//   * Active is ticked again: it signs in and refreshes again;
//   * a ban placed through Supabase Auth's admin API before the profile was
//     switched off is still there after it is switched on again;
//   * a pending invitee is not blocked; cancelling the invitation blocks them;
//   * a login made for an invitation cancelled during set-up (413 gives it a
//     cancelled profile) cannot open its invitation link;
//   * a login with no profile (an affiliate's) is never touched;
//   * control: 'infinity' in banned_until breaks Supabase Auth's reads of the
//     login, which is why 412 never writes it.
//
// It installs 412's own staff_login_sync and trigger function, read from the
// migration file, into a scratch schema (ban412_proof) of the auth database,
// beside a minimal profiles table, so nothing of the application schema there
// is touched. Every login it makes is @sig.invalid; at the end it deletes them,
// their rows in Supabase Auth's audit log and the schema, pass or fail.
//
// LOCAL STACK ONLY. It refuses any URL that is not 127.0.0.1 or localhost.
//   SUPABASE_URL               the API gateway, e.g. http://127.0.0.1:54321
//   SUPABASE_ANON_KEY          the publishable (anon) key
//   SUPABASE_SERVICE_ROLE_KEY  the secret (service role) key
//   DATABASE_URL               the database Supabase Auth uses, as its owner
//                              (postgres), e.g. postgresql://...@127.0.0.1:54322/postgres
// Keys come from the environment only (supabase status), never from a file,
// and are never printed. Needs psql on PATH.
//
//   node scripts/permissions/tests/deactivated-login-gotrue.mjs

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = path.join(here, '../../../supabase/412_deactivated_staff_signed_out_and_blocked.sql');
const { SUPABASE_URL: API, SUPABASE_ANON_KEY: ANON, SUPABASE_SERVICE_ROLE_KEY: SERVICE, DATABASE_URL: DB } = process.env;
for (const [k, v] of Object.entries({ SUPABASE_URL: API, SUPABASE_ANON_KEY: ANON, SUPABASE_SERVICE_ROLE_KEY: SERVICE, DATABASE_URL: DB })) {
  if (!v) { console.error(`Set ${k}.`); process.exit(2); }
}
const local = (u) => { try { return ['127.0.0.1', 'localhost', '[::1]'].includes(new URL(u).hostname); } catch { return false; } };
if (!local(API) || !local(DB)) {
  console.error('Refusing: SUPABASE_URL and DATABASE_URL must point at a local stack (127.0.0.1 or localhost).');
  process.exit(2);
}

const S = 'ban412_proof';
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
const signIn = (email, password) => call('POST', '/auth/v1/token?grant_type=password', { body: { email, password } });
const refresh = (rt) => call('POST', '/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: rt } });
const me = (at) => call('GET', '/auth/v1/user', { token: at });
const admin = (method, route, body) => call(method, `/auth/v1/admin${route}`, { key: SERVICE, token: SERVICE.startsWith('sb_') ? undefined : SERVICE, body });
const brief = (r) => `${r.status} ${r.code ?? ''}`.trim();

// ── 412's helper logic, from the migration file, in a scratch schema ────────
function install() {
  const m = readFileSync(MIGRATION, 'utf8');
  const defs = [...m.matchAll(/\$def\$([\s\S]*?)\$def\$/g)].map((x) => x[1]);
  const syncDef = defs.find((d) => d.startsWith('CREATE OR REPLACE FUNCTION public.staff_login_sync(p_user_id uuid)'));
  const trgDef = defs.find((d) => d.startsWith('CREATE OR REPLACE FUNCTION public.trg_staff_login_follows_profile()'));
  const table = /create table public\.staff_login_blocks \(([\s\S]*?)\);\n/.exec(m)?.[1];
  if (!syncDef || !trgDef || !table) throw new Error('could not read the two functions and the table from the migration');
  const move = (t) => t.replaceAll('public.', `${S}.`).replace("SET search_path TO 'public'", `SET search_path TO '${S}'`);
  const sync = move(syncDef), trg = move(trgDef);
  // Only public.* (now the scratch schema) and auth.* were named: nothing else moves.
  for (const t of [sync, trg]) if (/\bpublic\./.test(t)) throw new Error('a public name survived the move');
  sql(`begin;
create schema ${S};
create table ${S}.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text not null default '',
  email text, role text not null default 'staff', is_active boolean not null default true, deleted_at timestamptz,
  invitation_status text);
create table ${S}.audit_logs (id uuid primary key default gen_random_uuid(), table_name text not null, record_id uuid,
  action text not null, old_data jsonb, new_data jsonb, changed_by uuid, created_at timestamptz not null default now());
create table ${S}.staff_login_blocks (${table});
${sync};
${trg};
create trigger staff_login_follows_profile after insert or update of is_active, deleted_at, invitation_status
  on ${S}.profiles for each row execute function ${S}.trg_staff_login_follows_profile();
commit;`);
}

const users = [], emails = [];
async function makeLogin(tag) {
  const email = `412-proof-${tag}-${randomUUID().slice(0, 8)}@sig.invalid`;
  const password = `P412-${randomUUID()}`;
  const r = await admin('POST', '/users', { email, password, email_confirm: true });
  if (r.status !== 200 || !r.json?.id) throw new Error(`could not make a login (${brief(r)})`);
  users.push(r.json.id); emails.push(email);
  return { id: r.json.id, email, password };
}
const profile = (id, active, inv = null) =>
  sql(`insert into ${S}.profiles (id, is_active, invitation_status) values (${lit(id)}, ${active}, ${inv ? lit(inv) : 'null'})`);
const setProfile = (id, set) => sql(`update ${S}.profiles set ${set} where id = ${lit(id)}`);
const sessions = (id) => Number(sql(`select count(*) from auth.sessions where user_id = ${lit(id)}`));
const tokens = (id) => Number(sql(`select count(*) from auth.refresh_tokens where user_id = ${lit(id)}`));
const ban = (id) => sql(`select coalesce(banned_until::text, '') from auth.users where id = ${lit(id)}`);
const banYears = (id) => Number(sql(`select coalesce(extract(epoch from banned_until - now()) / 31557600, 0)::int from auth.users where id = ${lit(id)}`));

async function main() {
  const health = await call('GET', '/auth/v1/health');
  if (health.status !== 200) throw new Error(`Supabase Auth is not answering (${brief(health)})`);
  if (sql(`select count(*) from pg_namespace where nspname = ${lit(S)}`) !== '0') throw new Error(`schema ${S} already exists; remove it first`);
  install();
  ok(true, 'setup: 412\'s staff_login_sync and trigger function installed from the migration file into a scratch schema');

  // ── A member of staff, signed in on two devices ─────────────────────────
  const a = await makeLogin('staff');
  profile(a.id, true);
  const d1 = await signIn(a.email, a.password);
  const d2 = await signIn(a.email, a.password);
  ok(d1.status === 200 && d2.status === 200 && d1.json?.refresh_token && d2.json?.refresh_token,
    'open: the login signs in with its password on two devices', `${brief(d1)}, ${brief(d2)}`);
  const d2r = await refresh(d2.json.refresh_token);
  ok(d2r.status === 200 && (await me(d1.json.access_token)).status === 200,
    'open: a refresh token works and Supabase Auth answers for the access token', brief(d2r));
  ok(sessions(a.id) === 2 && ban(a.id) === '', 'open: two sessions, no ban');

  // ── Switched off ────────────────────────────────────────────────────────
  setProfile(a.id, 'is_active = false');
  ok(sessions(a.id) === 0 && tokens(a.id) === 0, 'closed: switching the profile off deletes both sessions and their refresh tokens');
  ok(banYears(a.id) >= 99 && banYears(a.id) <= 101 && !/infinity/i.test(ban(a.id)),
    'closed: the login is banned about a hundred years ahead, a finite time', ban(a.id));
  const pw = await signIn(a.email, a.password);
  ok(pw.status === 400 && pw.code === 'user_banned', 'closed: a password sign-in is refused (user_banned)', brief(pw));
  const r1 = await refresh(d1.json.refresh_token);
  const r2 = await refresh(d2r.json.refresh_token);
  // The codes name the cause: the session and its tokens are gone. A login
  // that was only banned answers user_banned to these instead.
  ok(r1.status === 400 && r1.code === 'refresh_token_not_found' && !r1.json?.access_token
     && r2.status === 400 && r2.code === 'refresh_token_not_found' && !r2.json?.access_token,
    'closed: neither device\'s refresh token works any more (refresh_token_not_found)', `${brief(r1)}, ${brief(r2)}`);
  const u1 = await me(d1.json.access_token);
  ok(u1.status === 403 && u1.code === 'session_not_found',
    'closed: Supabase Auth refuses an access token issued before (session_not_found: its session is gone)', brief(u1));
  const pwc = await call('PUT', '/auth/v1/user', { token: d2r.json.access_token, body: { password: `${a.password}x` } });
  ok(pwc.status === 403 && pwc.code === 'session_not_found',
    'closed: so the password change auth-change-password makes is refused (session_not_found)', brief(pwc));
  const rec = await admin('POST', '/generate_link', { type: 'recovery', email: a.email });
  const recv = rec.status === 200 ? await call('POST', '/auth/v1/verify', { body: { type: 'recovery', token_hash: rec.json.hashed_token } }) : rec;
  ok(recv.status === 403 && recv.code === 'user_banned' && !recv.json?.access_token,
    'closed: a password-recovery link gives no session (user_banned)', brief(recv));
  const ml = await admin('POST', '/generate_link', { type: 'magiclink', email: a.email });
  const mlv = ml.status === 200 ? await call('POST', '/auth/v1/verify', { body: { type: 'magiclink', token_hash: ml.json.hashed_token } }) : ml;
  ok(mlv.status === 403 && mlv.code === 'user_banned' && !mlv.json?.access_token,
    'closed: a magic link gives no session (user_banned)', brief(mlv));
  const read = await admin('GET', `/users/${a.id}`);
  ok(read.status === 200 && /^2[0-9]{3}-/.test(read.json?.banned_until ?? ''),
    'closed: Supabase Auth still reads the login (admin API), with the ban as a date', brief(read));
  const list = await admin('GET', '/users?per_page=200');
  ok(list.status === 200, 'closed: and still lists logins', brief(list));
  ok(sessions(a.id) === 0, 'closed: none of those attempts left a session');
  // The sign-out does not lean on the ban: lift the ban by hand for a moment
  // and the old tokens are still refused; then put back exactly the ban 412
  // wrote, so reopening below lifts it as its own.
  const kept = ban(a.id);
  sql(`update auth.users set banned_until = null where id = ${lit(a.id)}`);
  const o1 = await refresh(d1.json.refresh_token);
  const o2 = await refresh(d2r.json.refresh_token);
  const ou = await me(d1.json.access_token);
  sql(`update auth.users set banned_until = ${lit(kept)}::timestamptz where id = ${lit(a.id)}`);
  ok(o1.code === 'refresh_token_not_found' && o2.code === 'refresh_token_not_found' && ou.status === 403 && ou.code === 'session_not_found'
     && !o1.json?.access_token && !o2.json?.access_token && sessions(a.id) === 0 && ban(a.id) === kept,
    'closed: with the ban lifted by hand, the old refresh tokens and access token are still refused (signed out, not only banned)',
    `${brief(o1)}, ${brief(o2)}, ${brief(ou)}`);

  // ── Active again ────────────────────────────────────────────────────────
  setProfile(a.id, 'is_active = true');
  ok(ban(a.id) === '' && sql(`select count(*) from ${S}.staff_login_blocks where user_id = ${lit(a.id)}`) === '0',
    'reopened: ticking Active again lifts the ban and the record');
  const back = await signIn(a.email, a.password);
  ok(back.status === 200, 'reopened: the password signs in again', brief(back));
  const backR = back.status === 200 ? await refresh(back.json.refresh_token) : back;
  ok(backR.status === 200 && (await me(backR.json?.access_token)).status === 200,
    'reopened: and the new session refreshes and is answered', brief(backR));

  // ── A ban placed through Supabase Auth, before 412 acted ────────────────
  const banned = await admin('PUT', `/users/${a.id}`, { ban_duration: '24h' });
  const before = ban(a.id);
  ok(banned.status === 200 && before !== '', 'other ban: the admin API bans the login for a day', brief(banned));
  setProfile(a.id, 'is_active = false');
  ok(banYears(a.id) >= 99, 'other ban: switching the profile off replaces it with 412\'s while closed');
  setProfile(a.id, 'is_active = true');
  ok(ban(a.id) === before, 'other ban: ticking Active again puts the day\'s ban back, not nothing');
  const still = await signIn(a.email, a.password);
  ok(still.status === 400 && still.code === 'user_banned', 'other ban: so the login is still refused (412 lifted only its own)', brief(still));
  await admin('PUT', `/users/${a.id}`, { ban_duration: 'none' });
  ok((await signIn(a.email, a.password)).status === 200, 'other ban: once the admin lifts it, the login signs in');

  // ── A pending invitee, then the invitation cancelled ────────────────────
  const p = await makeLogin('invitee');
  profile(p.id, false, 'pending');
  const pIn = await signIn(p.email, p.password);
  ok(pIn.status === 200 && ban(p.id) === '', 'pending: an invitee who has not accepted yet is not blocked (they sign in from the link)', brief(pIn));
  setProfile(p.id, "invitation_status = 'cancelled'");
  const pOut = await signIn(p.email, p.password);
  const pRef = await refresh(pIn.json.refresh_token);
  ok(pOut.status === 400 && pOut.code === 'user_banned' && pRef.status >= 400 && sessions(p.id) === 0,
    'cancelled: cancelling the invitation signs them out and blocks them', `${brief(pOut)}, ${brief(pRef)}`);

  // ── An invitation cancelled during set-up (413) ─────────────────────────
  // Supabase Auth makes the login and its invitation link (as admin-invite-user
  // asks it); the invitation was cancelled meanwhile, so 413 gives the login a
  // cancelled profile, which 412 blocks. The link must not open.
  const raceEmail = `412-proof-race-${randomUUID().slice(0, 8)}@sig.invalid`;
  const inv = await admin('POST', '/generate_link', { type: 'invite', email: raceEmail });
  if (inv.status === 200 && inv.json?.id) { users.push(inv.json.id); emails.push(raceEmail); }
  ok(inv.status === 200 && inv.json?.id && inv.json?.hashed_token, 'race: Supabase Auth makes an invited login and its link', brief(inv));
  profile(inv.json.id, false, 'cancelled');
  ok(banYears(inv.json.id) >= 99 && sql(`select reason from ${S}.staff_login_blocks where user_id = ${lit(inv.json.id)}`) === 'invitation_cancelled',
    'race: the cancelled profile 413 writes blocks that login at once');
  const invv = await call('POST', '/auth/v1/verify', { body: { type: 'invite', token_hash: inv.json.hashed_token } });
  ok(invv.status === 403 && invv.code === 'user_banned' && !invv.json?.access_token && sessions(inv.json.id) === 0,
    'race: its invitation link gives no session (user_banned), so no password can be set from it', brief(invv));

  // ── A login with no profile (an affiliate's) ────────────────────────────
  const f = await makeLogin('affiliate');
  const fIn = await signIn(f.email, f.password);
  ok(sql(`select ${S}.staff_login_sync(${lit(f.id)})`) === 'no_profile' && ban(f.id) === '' && sessions(f.id) === 1,
    'affiliate: a login with no profile is never touched');
  ok(fIn.status === 200 && (await refresh(fIn.json.refresh_token)).status === 200, 'affiliate: it signs in and refreshes as before');

  // ── Control: why never 'infinity' ───────────────────────────────────────
  sql(`update auth.users set banned_until = 'infinity' where id = ${lit(f.id)}`);
  const inf = await admin('GET', `/users/${f.id}`);
  const infIn = await signIn(f.email, f.password);
  sql(`update auth.users set banned_until = null where id = ${lit(f.id)}`);
  ok(inf.status >= 500 && infIn.status >= 500,
    'control: with \'infinity\' Supabase Auth cannot even read the login (so 412 writes a date)', `${brief(inf)}, ${brief(infIn)}`);
}

async function cleanup() {
  for (const id of users) {
    const r = await admin('DELETE', `/users/${id}`);
    if (r.status !== 200) { try { sql(`delete from auth.users where id = ${lit(id)}`); } catch { /* reported below */ } }
  }
  try { sql(`set client_min_messages = warning; drop schema if exists ${S} cascade`); } catch { /* reported below */ }
  // Supabase Auth's own audit trail of these logins (sign-ins, refreshes, the
  // admin calls) goes too: this run leaves no row behind.
  const mine = [...users, ...emails].map((v) => lit(`%${v}%`)).join(',');
  if (mine) { try { sql(`delete from auth.audit_log_entries where payload::text like any (array[${mine}])`); } catch { /* reported below */ } }
  const leftUsers = users.length
    ? Number(sql(`select count(*) from auth.users where id in (${users.map(lit).join(',')})`)) : 0;
  const leftAudit = mine ? Number(sql(`select count(*) from auth.audit_log_entries where payload::text like any (array[${mine}])`)) : 0;
  const leftSchema = Number(sql(`select count(*) from pg_namespace where nspname = ${lit(S)}`));
  ok(leftUsers === 0 && leftAudit === 0 && leftSchema === 0,
    `cleanup: the ${users.length} made-up logins, their Supabase Auth audit rows and the scratch schema are gone`,
    `logins left ${leftUsers}, audit rows left ${leftAudit}, schema left ${leftSchema}`);
}

try {
  await main();
} catch (e) {
  failures++;
  console.log(`FAIL  ${e.message}`);
} finally {
  await cleanup();
}
console.log(`${failures ? 'FAILED' : 'PASSED'}: ${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
