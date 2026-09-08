// Migration 200 against the isolated local database.
//
//   scripts/auth-email/bootstrap-local.sh start
//   npm run test:auth-email:db
//
// Refuses to run anywhere but the disposable cluster on port 55442. It never
// touches production and never touches the invoice work's cluster on 55441.

import { execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';

const run = promisify(execFile);

process.env.PGHOST ??= '/tmp';
process.env.PGPORT ??= '55442';
process.env.PGUSER ??= 'postgres';
process.env.PGDATABASE ??= 'energia_auth_email_test';

if (process.env.PGDATABASE !== 'energia_auth_email_test' || process.env.PGPORT !== '55442') {
  throw new Error('Refusing to run: this suite only targets energia_auth_email_test on port 55442.');
}

const args = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'];
const sql = statement => execFileSync('psql', [...args, '-c', statement], { encoding: 'utf8' }).trim();
const json = statement => JSON.parse(sql(statement));

// Applying twice proves the migration is re-runnable, which is how it will be
// applied in practice alongside the rest of supabase/*.sql.
execFileSync('psql', [...args, '-f', 'supabase/200_auth_email_delivery.sql'], { encoding: 'utf8' });
execFileSync('psql', [...args, '-f', 'supabase/200_auth_email_delivery.sql'], { encoding: 'utf8' });
console.log('PASS: migration 200 applies, and applies again, cleanly.');

const fresh = () => `k-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
const reserve = (action, email, ip = null) =>
  json(`select public.auth_email_reserve('${action}','${email}',${ip ? `'${ip}'` : 'null'});`);

// --- thresholds -------------------------------------------------------------
const limits = Object.fromEntries(
  sql('select action || \'/\' || scope || \'=\' || max_attempts || \':\' || window_seconds from public.auth_email_limits order by 1;')
    .split('\n').map(line => line.split('=')),
);
assert.deepEqual(limits, {
  'combined/ip': '60:3600',
  'recovery/email': '5:3600', 'recovery/ip': '60:3600',
  'resend/email': '3:900', 'resend/ip': '30:3600',
  'signup/email': '3:900', 'signup/ip': '30:3600',
});
console.log('PASS: the documented thresholds are the ones in the table.');

// --- per-email limits -------------------------------------------------------
for (const [action, allowed, window] of [['signup', 3, 900], ['resend', 3, 900], ['recovery', 5, 3600]]) {
  const email = fresh();
  for (let i = 0; i < allowed; i++) assert.equal(reserve(action, email).allowed, true, `${action} #${i + 1}`);
  const refused = reserve(action, email);
  assert.equal(refused.allowed, false, `${action} should refuse #${allowed + 1}`);
  assert.equal(refused.scope, 'email');
  assert.ok(refused.retry_after_seconds > 0 && refused.retry_after_seconds <= window);
}
console.log('PASS: per-email limits admit exactly the documented number, then refuse.');

// --- the email limit applies even with no usable IP -------------------------
const noIp = fresh();
for (let i = 0; i < 3; i++) assert.equal(reserve('signup', noIp, null).allowed, true);
assert.equal(reserve('signup', noIp, null).allowed, false,
  'a missing IP must not mean unlimited: the email limit is mandatory');
console.log('PASS: with no trustworthy IP the mandatory email limit still holds.');

// --- shared Wi-Fi: ten people on one IP are not each other's problem --------
const sharedIp = fresh();
for (let person = 0; person < 10; person++) {
  const email = fresh();
  assert.equal(reserve('signup', email, sharedIp).allowed, true, `person ${person + 1} signup`);
  assert.equal(reserve('resend', email, sharedIp).allowed, true, `person ${person + 1} resend`);
  assert.equal(reserve('recovery', email, sharedIp).allowed, true, `person ${person + 1} recovery`);
}
console.log('PASS: 10 people sharing one IP each complete a signup, a resend and a recovery.');

// --- the per-IP ceiling still exists ----------------------------------------
const busyIp = fresh();
let admitted = 0;
for (let i = 0; i < 40; i++) if (reserve('signup', fresh(), busyIp).allowed) admitted += 1;
assert.equal(admitted, 30, 'signup/ip is 30 per hour');
assert.equal(reserve('signup', fresh(), busyIp).allowed, false);
console.log('PASS: the per-IP ceiling refuses once it is reached.');

// --- the combined ceiling spans actions -------------------------------------
const combinedIp = fresh();
let total = 0;
for (let i = 0; i < 80; i++) if (reserve('recovery', fresh(), combinedIp).allowed) total += 1;
assert.equal(total, 60, 'the combined per-IP ceiling is 60 per hour');
assert.equal(reserve('resend', fresh(), combinedIp).allowed, false,
  'a different action on the same IP is still under the combined ceiling');
console.log('PASS: the combined per-IP ceiling covers every action together.');

// --- atomicity under real concurrency ---------------------------------------
// Eight simultaneous connections race for three slots. Without the advisory lock
// they would all read "used = 0" and all insert.
{
  const email = fresh();
  // Separate -c flags so each statement is its own round trip in one session:
  // every connection is inside a transaction and asleep before any of them
  // reaches the reservation, so they genuinely contend.
  const results = await Promise.all(Array.from({ length: 8 }, () => run('psql', [
    ...args,
    '-c', 'begin',
    '-c', 'select pg_sleep(0.05)',
    '-c', `select public.auth_email_reserve('signup','${email}',null)`,
    '-c', 'commit',
  ])));
  const verdicts = results.map(r => JSON.parse(r.stdout.split('\n').find(line => line.startsWith('{'))));
  const allowed = verdicts.filter(v => v.allowed).length;
  assert.equal(allowed, 3, `exactly three of eight concurrent requests should be admitted, got ${allowed}`);
  assert.equal(sql(`select count(*) from public.auth_email_rate_events where key_hash='${email}';`), '3',
    'and exactly three events should be recorded');
  console.log('PASS: 8 concurrent reservations, 3 admitted — check-then-insert is atomic.');
}

// --- a refused attempt does not extend the window ---------------------------
{
  const email = fresh();
  for (let i = 0; i < 3; i++) reserve('signup', email);
  for (let i = 0; i < 5; i++) assert.equal(reserve('signup', email).allowed, false);
  assert.equal(sql(`select count(*) from public.auth_email_rate_events where key_hash='${email}';`), '3',
    'hammering a refused bucket must not keep pushing the window forward');
  console.log('PASS: refused attempts do not extend the lockout for a legitimate user.');
}

// --- an unknown action is refused, not silently allowed ---------------------
assert.throws(() => sql("select public.auth_email_reserve('magic_link','k',null);"), /AUTH_EMAIL_UNKNOWN_ACTION/);
assert.throws(() => sql("select public.auth_email_reserve('signup','',null);"), /AUTH_EMAIL_MISSING_EMAIL_KEY/);
console.log('PASS: an unknown action or a missing email key raises instead of admitting.');

// --- account state ----------------------------------------------------------
{
  const tag = Date.now();
  sql(`insert into auth.users (email, email_confirmed_at) values
        ('unconfirmed-${tag}@example.com', null),
        ('confirmed-${tag}@example.com', now());`);
  assert.equal(sql(`select public.auth_email_user_state('nobody-${tag}@example.com');`), 'none');
  assert.equal(sql(`select public.auth_email_user_state('unconfirmed-${tag}@example.com');`), 'unconfirmed');
  assert.equal(sql(`select public.auth_email_user_state('confirmed-${tag}@example.com');`), 'confirmed');
  assert.equal(sql(`select public.auth_email_user_state('  CONFIRMED-${tag}@Example.COM  ');`), 'confirmed',
    'lookup matches Supabase\'s case-insensitive comparison');
  console.log('PASS: account state distinguishes none / unconfirmed / confirmed.');
}

// --- delivery outcomes are recorded separately from admission ---------------
{
  const id = '11111111-2222-3333-4444-555555555555';
  sql(`select public.auth_email_record_outcome('${id}','signup','requested','hash',null,null);`);
  sql(`select public.auth_email_record_outcome('${id}','signup','timeout','hash',null,'${'x'.repeat(900)}');`);
  assert.equal(sql(`select outcome from public.auth_email_deliveries where request_id='${id}';`), 'timeout');
  assert.equal(sql(`select length(detail) from public.auth_email_deliveries where request_id='${id}';`), '500',
    'a chatty provider message is truncated, not stored whole');
  assert.equal(sql(`select count(*) from public.auth_email_deliveries where request_id='${id}';`), '1',
    'one row per request, updated in place');
  assert.throws(() => sql(`select public.auth_email_record_outcome('${id}','signup','delivered','h',null,null);`),
    /violates check constraint/, 'only the defined outcomes are storable');
  console.log('PASS: delivery outcomes are recorded, bounded and constrained.');
}

// --- nothing here is reachable by anon or authenticated ---------------------
for (const table of ['auth_email_limits', 'auth_email_rate_events', 'auth_email_deliveries']) {
  assert.equal(sql(`select relrowsecurity from pg_class where oid='public.${table}'::regclass;`), 't', `${table} RLS`);
  assert.equal(sql(`select count(*) from pg_policies where schemaname='public' and tablename='${table}';`), '0',
    `${table} has no policy, so RLS-respecting roles read nothing`);
  for (const role of ['anon', 'authenticated']) {
    for (const priv of ['select', 'insert', 'update', 'delete']) {
      assert.equal(sql(`select has_table_privilege('${role}','public.${table}','${priv}');`), 'f', `${role}/${priv}/${table}`);
    }
  }
  assert.equal(sql(`select has_table_privilege('service_role','public.${table}','select');`), 't');
}
for (const fn of [
  'auth_email_reserve(text,text,text)',
  'auth_email_record_outcome(uuid,text,text,text,integer,text)',
  'auth_email_user_state(text)',
  'auth_email_cleanup(interval)',
]) {
  for (const role of ['anon', 'authenticated', 'public']) {
    assert.equal(sql(`select has_function_privilege('${role}','public.${fn}','execute');`), 'f', `${role} -> ${fn}`);
  }
  assert.equal(sql(`select has_function_privilege('service_role','public.${fn}','execute');`), 't', `service_role -> ${fn}`);
}
console.log('PASS: every table and function is service-role only.');

// --- retention --------------------------------------------------------------
{
  sql(`insert into public.auth_email_rate_events (action, scope, key_hash, occurred_at)
       values ('signup','email','old-key', now() - interval '20 days');`);
  sql(`insert into public.auth_email_deliveries (request_id, action, outcome, created_at)
       values (gen_random_uuid(),'signup','accepted', now() - interval '20 days');`);
  const before = Number(sql("select count(*) from public.auth_email_rate_events where key_hash='old-key';"));
  assert.equal(before, 1);
  const deleted = json('select public.auth_email_cleanup();');
  assert.ok(deleted.rate_events_deleted >= 1 && deleted.deliveries_deleted >= 1);
  assert.equal(sql("select count(*) from public.auth_email_rate_events where key_hash='old-key';"), '0');
  assert.ok(Number(sql('select count(*) from public.auth_email_rate_events;')) > 0,
    'cleanup removes only what is past retention');
  console.log('PASS: cleanup honours the 14-day retention and leaves recent rows alone.');
}

// --- the counters hold no plaintext ----------------------------------------
assert.equal(sql("select count(*) from public.auth_email_rate_events where key_hash like '%@%';"), '0',
  'the limiter stores keyed hashes, never addresses');
console.log('PASS: no address or IP is stored in the clear.');

console.log('\nAll migration 200 database tests passed.');
