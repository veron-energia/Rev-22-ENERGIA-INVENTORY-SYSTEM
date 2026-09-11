// Real independent PostgreSQL sessions; refuses any non-fixture database.
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const env = { ...process.env, PGHOST: '/tmp', PGPORT: '55444', PGUSER: 'postgres', PGDATABASE: 'energia_commission_test' };
function run(sql, onData) { return new Promise(resolveResult => {
  const p = spawn('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], { env }); let out = '', err = '';
  p.stdout.on('data', x => { out += x; onData?.(String(x)); }); p.stderr.on('data', x => err += x);
  p.on('close', code => resolveResult({ code, out: out.trim(), err })); p.stdin.end(sql);
}); }
async function ok(sql) { const r = await run(sql); assert.equal(r.code, 0, r.err); return r.out.split('\n').at(-1); }
assert.equal(await ok('show data_directory'), resolve('.commission-test/data'));
assert.equal(await ok('select current_database()'), 'energia_commission_test');
const owner = randomUUID(), ref = randomUUID(), buyer = randomUUID(), store = randomUUID(), method = randomUUID(), invoice = randomUUID();
const auth = `select set_config('request.jwt.claim.sub','${owner}',true);`;
await ok(`begin; insert into auth.users(id,email) values('${owner}','${owner}@tests.invalid');
insert into profiles(id,full_name,email,role) values('${owner}','Concurrency Owner','${owner}@tests.invalid','owner');${auth}
insert into stores(id,name,code,country_code) values('${store}','Concurrency','${store.slice(0,8)}','SG');
insert into customers(id,full_name,phone) values('${ref}','Concurrency Ref','+6591118851'),('${buyer}','Concurrency Buyer','+6591118852');
insert into payment_methods(id,name) values('${method}','Concurrency ${method}');
insert into invoices(id,invoice_no,store_id,customer_id,created_by,status) values('${invoice}','${invoice}','${store}','${buyer}','${owner}','paid');
insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,line_amount,rate,commission_amount,invoice_paid_date)
select '${invoice}','${buyer}','${ref}','tier1','own',2000,15,300,day from unnest(array['2020-06-02'::date,'2020-07-02'::date,'2020-08-02'::date]) day;commit;`);
const record = (month, amount, request = randomUUID()) => `select record_affiliate_payout('${ref}','2020-${month}-01',${amount},'${method}','2020-09-01',null,null,'${request}');`;
const correct = (p, amount, request = randomUUID()) => `select correct_affiliate_payout('${p}',1,${amount},'${method}','2020-09-01',null,null,'Receipt correction','${request}');`;
async function overlap(statements) {
  // Hold the same DB lock briefly so all workers compete for it at once.
  let ready; const lockReady = new Promise(r => ready = r);
  const gate = run("begin; select affiliate_payout_lock(); select 'LOCKED'; select pg_sleep(1); commit;", s => { if (s.includes('LOCKED')) ready(); });
  await lockReady;
  const jobs = statements.map(s => run(`begin;${auth}${s}commit;`));
  const results = await Promise.all(jobs); assert.equal((await gate).code, 0); return results;
}
let results = await overlap(Array.from({ length: 6 }, () => record('06', 100)));
assert.equal(results.filter(r => r.code === 0).length, 3, JSON.stringify(results));
assert.equal(await ok(`select paid||'/'||balance from affiliate_month_balances() where referrer='${ref}' and month='2020-06-01'`), '300.00/0.00');
const key = randomUUID(); results = await overlap([record('07', 100, key), record('07', 100, key)]);
assert.ok(results.every(r => r.code === 0), JSON.stringify(results));
assert.equal(await ok(`select count(*) from commission_payouts where referrer_customer_id='${ref}' and payout_month='2020-07-01'`), '1');
const payout = await ok(`select id from commission_payouts where referrer_customer_id='${ref}' and payout_month='2020-07-01'`);
results = await overlap([correct(payout, 200), correct(payout, 250)]);
assert.equal(results.filter(r => r.code === 0).length, 1, JSON.stringify(results));
assert.match(results.find(r => r.code !== 0).err, /changed by another user/);
assert.equal(await ok(`select count(*) from commission_payout_changes where payout_id='${payout}'`), '2');
const p8 = JSON.parse(await ok(`begin;${auth}${record('08', 100)}commit;`)).id;
const editKey = randomUUID(); results = await overlap([correct(p8, 200, editKey), correct(p8, 200, editKey)]);
assert.ok(results.every(r => r.code === 0), JSON.stringify(results));
assert.equal(await ok(`select sum(amount) from commission_payout_allocations where payout_id='${p8}'`), '200.00');
assert.equal(await ok(`select count(*) from commission_payout_changes where payout_id='${p8}'`), '2');
// Invoice-driven adjustment races a payout: it either wins the lock and blocks
// payment, or follows a historically traceable payment. No lost update.
results = await overlap([
  record('08', 100),
  `insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,line_amount,rate,commission_amount,invoice_paid_date) values('${invoice}','${buyer}','${ref}','tier1','own',-100,15,-100,'2020-08-02');`,
]);
assert.equal(results[1].code, 0, results[1].err);
const final = JSON.parse(await ok(`select jsonb_build_object('paid',paid,'balance',balance) from affiliate_month_balances() where referrer='${ref}' and month='2020-08-01'`));
assert.ok((final.paid === 200 && final.balance === 0) || (final.paid === 300 && final.balance === -100));
console.log('PASS: 6 concurrent requests cap at 300; duplicate payment/edit; conflicting versions; commission adjustment serialization');
// Deliberately retain local synthetic history for inspection. Bootstrap removes
// it on the next isolated run; no deletion of real ledger records is performed.
