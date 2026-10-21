// 423: two presses of "Create invoices" for one split sale, at the same time.
//
// split-replay.sql sends the same request twice from one session, which
// proves the replay but never interleaves. Here two separate psql sessions
// send the same request id while the first is still open: the second waits
// for the first (one call at a time per id), then answers with the sale the
// first made. One group and two invoices, never two groups.
//
// It needs a disposable database with production's schema and 423 applied,
// and it commits its made-up rows (T423C, +65 9123 47xx, @sig.invalid), so
// it is never pointed at production. By default it uses the integration
// database; to use another disposable copy, set PGHOST, PGPORT, PGUSER,
// PGDATABASE (and PGPASSWORD) and SPLIT_REPLAY_DISPOSABLE=yes.
//   node scripts/therapy/tests/split-replay-concurrency.mjs
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const custom = process.env.SPLIT_REPLAY_DISPOSABLE === 'yes';
const env = custom
  ? { ...process.env }
  : { ...process.env, PGHOST: '/tmp', PGPORT: '55441', PGUSER: 'postgres', PGDATABASE: 'energia_integration_test' };
if (custom && /jknfhpgryywsrzdstqzy|supabase\.co/.test(`${env.PGHOST} ${env.DATABASE_URL ?? ''}`)) {
  throw new Error('Refusing: this test commits rows and is for a disposable database only.');
}

function run(sql) {
  return new Promise(done => {
    const p = spawn('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], { env });
    let out = '', err = '';
    p.stdout.on('data', x => out += x);
    p.stderr.on('data', x => err += x);
    p.on('close', code => done({ code, out: out.trim(), err: err.trim() }));
    p.stdin.end(sql);
  });
}
async function ok(sql) { const r = await run(sql); assert.equal(r.code, 0, r.err); return r.out.split('\n').at(-1); }
const sleep = ms => new Promise(r => setTimeout(r, ms));

let failures = 0;
const check = (label, cond, detail = '') => {
  if (cond) console.log(`  ok   ${label}`);
  else { failures++; console.log(`  FAIL ${label}${detail ? ' — ' + detail : ''}`); }
};

// Only a database that has 423 (one split function of each name, with the request id).
assert.equal(await ok(`select count(*) from pg_proc where pronamespace = 'public'::regnamespace
  and proname = 'create_split_credit_package_invoices'
  and oid::regprocedure::text = 'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)'`), '1',
  'This database does not have 423 applied.');

const t = randomUUID().slice(0, 6).toUpperCase();
const staff = randomUUID(), store = randomUUID(), c1 = randomUUID(), c2 = randomUUID(), cp = randomUUID();
const phone = () => `+65912347${String(Math.floor(Math.random() * 100)).padStart(2, '0')}`;
await ok(`begin;
  insert into auth.users(id, email) values ('${staff}', 't423c-${t}@sig.invalid');
  insert into public.profiles(id, full_name, email, role, is_active) values ('${staff}', 'T423C Staff ${t}', 't423c-${t}@sig.invalid', 'staff', true);
  insert into public.stores(id, name, code) values ('${store}', 'T423C Store ${t}', 'T423C${t}');
  insert into public.user_store_assignments(user_id, store_id) values ('${staff}', '${store}');
  insert into public.customers(id, full_name, phone) values ('${c1}', 'T423C One ${t}', '${phone()}'), ('${c2}', 'T423C Two ${t}', '${phone()}');
  insert into public.credit_packages(id, name, customer_price, paid_credit_amount, is_active, grants_reward)
  values ('${cp}', 'T423C Credit ${t}', 1000, 1000, true, false);
  commit;`);

const asStaff = `select set_config('request.jwt.claims', '{"sub":"${staff}","role":"authenticated"}', false); set role authenticated;`;
const alloc = `'[{"customer_id":"${c1}","payment_amount":600,"reward_voucher_qty":0},{"customer_id":"${c2}","payment_amount":400,"reward_voucher_qty":0}]'::jsonb`;
const req = randomUUID();
const call = `select public.create_split_credit_package_invoices('${store}', '${cp}', ${alloc}, null, null, null, '${req}')::text;`;

// The first press holds its transaction open for a moment after the sale is
// made; the second arrives while it is still open.
const first = run(`${asStaff} begin; ${call} select pg_sleep(1.5); commit;`);
await sleep(400);
const second = run(`${asStaff} ${call}`);
const [a, b] = await Promise.all([first, second]);
check('both presses are answered', a.code === 0 && b.code === 0, `${a.err} ${b.err}`);
const ra = JSON.parse(a.out.split('\n').find(l => l.includes('split_group_id')) ?? '{}');
const rb = JSON.parse(b.out.split('\n').find(l => l.includes('split_group_id')) ?? '{}');
check('the first makes the sale', ra.split_group_id && !ra.replayed, a.out);
check('the second waited and answers with the same sale, replayed',
  rb.replayed === true && rb.split_group_id === ra.split_group_id, b.out);
const groups = await ok(`select count(*) from public.credit_package_split_groups where request_id = '${req}'`);
const invoices = await ok(`select count(*) from public.invoices where store_id = '${store}'`);
check('one group for the request', groups === '1', groups);
check('two invoices, not four', invoices === '2', invoices);

if (failures) { console.log(`${failures} failed`); process.exit(1); }
console.log('PASS: two presses at the same time make one split sale');
