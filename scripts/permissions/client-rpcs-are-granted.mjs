/**
 * Every RPC the application calls must still be callable by a signed-in user.
 *
 * 339 turned function EXECUTE from "granted to everyone by default" into an
 * allowlist. The danger in that trade is the opposite of the one it fixes: a
 * function the staff screens depend on that nobody remembered to grant, which
 * shows up as a permission error in front of a customer rather than as a
 * failing test.
 *
 * So this does not read the allowlist. It reads the CALLS — every
 * supabase.rpc('name') in the frontend and the edge functions — and asks the
 * database whether `authenticated` may execute each one. Run it against a
 * database BEFORE applying 339 there, and again afterwards.
 *
 *   ENERGIA_INVOICE_DB=energia_integration_test node scripts/permissions/client-rpcs-are-granted.mjs
 *   ENERGIA_PERMISSIONS_DSN=postgresql://postgres:postgres@127.0.0.1:54322/postgres node scripts/permissions/client-rpcs-are-granted.mjs
 *
 * Local databases only. Without a DSN it goes through
 * scripts/invoices/local-sql.sh, which allows only the disposable databases;
 * with one, the host must be a loopback address, so this script has no way to
 * reach a hosted project.
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const ROOTS = ['src', 'supabase/functions'];
// Two ways this codebase calls a function, and they have different answers.
//
// CALLER: supabase.rpc('x') from the browser, and callerRpc('x') inside the
// edge functions — both run as the signed-in user, so both MUST stay granted to
// authenticated. The callerRpc spelling is the one a plain `.rpc(` grep misses,
// and missing it is how migration 339 nearly shipped revoking the three
// invitation functions an administrator calls as themselves.
//
// SERVICE: adminRpc('x') runs on the service-role key, which keeps its grant
// whatever happens to authenticated. Those names are reported, not required.
// The repository names the two clients apart: `admin` is the service role,
// anything else carries the caller's own token. That naming is the signal.
const RPC_CALLER = /(?:(?<!\badmin)\.rpc|\bcallerRpc)\(\s*'([a-z0-9_]+)'/g;
const RPC_SERVICE = /(?:\badmin\.rpc|\badminRpc)\(\s*'([a-z0-9_]+)'/g;

function walk(dir, out = []) {
  let entries;
  try { entries = readdirSync(dir); } catch { return out; }
  for (const e of entries) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) { if (e !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx|mts|mjs|js|jsx)$/.test(e)) out.push(p);
  }
  return out;
}

const called = new Map();          // rpc name -> the files that call it, as the caller
const serviceOnly = new Map();     // rpc name -> the files that call it on the service role
for (const root of ROOTS) {
  for (const file of walk(root)) {
    const text = readFileSync(file, 'utf8');
    for (const [re, sink] of [[RPC_CALLER, called], [RPC_SERVICE, serviceOnly]]) {
      for (const m of text.matchAll(re)) {
        if (!sink.has(m[1])) sink.set(m[1], []);
        if (!sink.get(m[1]).includes(file)) sink.get(m[1]).push(file);
      }
    }
  }
}
// A name called both ways is a caller name: the stricter requirement wins.
for (const n of called.keys()) serviceOnly.delete(n);
if (called.size === 0) { console.error('Found no caller-side rpc() calls — the scan is wrong, not the database.'); process.exit(2); }

const names = [...called.keys()].sort();
const sql = `
  with wanted(name) as (select unnest($$${names.join(',')}$$::text[] ))
  select w.name,
         coalesce(count(p.oid), 0) as overloads,
         coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'execute')), false) as staff_may_call,
         coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute')), false) as anon_may_call
    from wanted w
    left join pg_proc p on p.proname = w.name
     and p.pronamespace = 'public'::regnamespace
   group by w.name order by w.name;`;

const query = sql.replace(`$$${names.join(',')}$$::text[]`, `string_to_array('${names.join(',')}', ',')`);
const dsn = process.env.ENERGIA_PERMISSIONS_DSN;
let out;
if (dsn) {
  const host = (dsn.match(/@([^:/?]+)/) || [])[1];
  if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)) {
    console.error(`Refusing ENERGIA_PERMISSIONS_DSN host '${host}': this check runs against a local database only.`);
    process.exit(2);
  }
  out = execFileSync('psql', ['-X', '-q', '-A', '-F', '\t', '-t', '-c', query, dsn], { encoding: 'utf8', env: process.env });
} else {
  out = execFileSync('sh', ['scripts/invoices/local-sql.sh', '-q', '-A', '-F', '\t', '-t', '-c', query],
    { encoding: 'utf8', env: process.env });
}

const rows = out.trim().split('\n').filter(Boolean).map(l => {
  const [name, overloads, staff, anon] = l.split('\t');
  return { name, overloads: Number(overloads), staff: staff === 't' || staff === 'true', anon: anon === 't' || anon === 'true' };
});

const absent = rows.filter(r => r.overloads === 0);
const ungranted = rows.filter(r => r.overloads > 0 && !r.staff);
const anonCallable = rows.filter(r => r.anon);

for (const r of ungranted) console.error(`NOT CALLABLE BY STAFF: ${r.name}  (called from ${called.get(r.name).join(', ')})`);
for (const r of absent) console.error(`NOT IN THIS DATABASE:   ${r.name}  (called from ${called.get(r.name).join(', ')})`);

console.log(`${rows.length} RPC names called as the signed-in user; ${rows.length - ungranted.length - absent.length} callable by one.`);
if (serviceOnly.size) {
  console.log(`${serviceOnly.size} more are called only on the service role, which keeps its grant either way: ${[...serviceOnly.keys()].sort().join(', ')}`);
}
if (anonCallable.length) {
  console.log(`Reachable without signing in (expected: the public endpoints only): ${anonCallable.map(r => r.name).join(', ')}`);
}
if (absent.length) {
  console.log(`\n${absent.length} not present in this database. On a database that is not a full replica this is expected; against production it means the application calls something that does not exist.`);
}
if (ungranted.length) {
  console.error(`\nFAIL: ${ungranted.length} function(s) the application calls are not callable by a signed-in user.`);
  process.exit(1);
}
console.log('PASS: every RPC the application calls is callable by a signed-in user.');
