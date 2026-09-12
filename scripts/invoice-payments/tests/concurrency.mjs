// Two settlement submissions racing on the same invoice, in real sessions.
//
// The unique index on (request_id, portion_key) is what makes a retry safe.
// Single-session tests never interleave, so they cannot show that it holds
// when two clients submit at the same instant.
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const env = { ...process.env, PGHOST: '/tmp', PGPORT: '55441', PGUSER: 'postgres', PGDATABASE: 'energia_integration_test' };
function run(sql, onData) {
  return new Promise(done => {
    const p = spawn('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], { env });
    let out = '', err = '';
    p.stdout.on('data', x => { out += x; onData?.(String(x)); });
    p.stderr.on('data', x => err += x);
    p.on('close', code => done({ code, out: out.trim(), err: err.trim() }));
    p.stdin.end(sql);
  });
}
async function ok(sql) { const r = await run(sql); assert.equal(r.code, 0, r.err); return r.out.split('\n').at(-1); }

assert.equal(await ok('select current_database()'), 'energia_integration_test');
assert.equal(await ok('show data_directory'), resolve('.invoice-test/data'));

const owner = randomUUID();
const auth = `select set_config('request.jwt.claim.sub','${owner}',false);`;
await ok(`begin;
  insert into auth.users(id,email) values('${owner}','sc-${owner}@tests.invalid');
  insert into profiles(id,full_name,email,role) values('${owner}','SC Owner','sc-${owner}@tests.invalid','owner');
  commit;`);

async function fixture(total) {
  const store = randomUUID(), cust = randomUUID(), method = randomUUID(), product = randomUUID();
  const tag = store.slice(0, 6);
  await ok(`${auth} begin;
    insert into stores(id,name,code,country_code) values('${store}','SC ${tag}','${tag.toUpperCase()}','SG');
    insert into customers(id,full_name,phone) values('${cust}','SC ${tag}','+65${Math.floor(80000000 + Math.random() * 9999999)}');
    insert into payment_methods(id,name,is_active) values('${method}','SC ${tag}',true);
    insert into products(id,name,sku,product_type) values('${product}','SC ${tag}','${tag}','own');
    insert into store_inventory(store_id,product_id,current_qty) values('${store}','${product}',100);
    select set_product_prices('${store}','${product}',${total},${total},'available');
    commit;`);
  const invoice = await ok(`${auth} select create_invoice_with_details('${store}','${cust}',
    jsonb_build_array(jsonb_build_object('kind','product','product_id','${product}','quantity',1)),
    jsonb_build_object('business_date',sg_today()::text));`);
  return { invoice, method };
}

// Release the workers together by queuing them behind one row lock.
async function together(lockInvoice, statements) {
  let open; const held = new Promise(r => open = r);
  const gate = run(`begin; select id from invoices where id='${lockInvoice}' for update;
                    select 'HELD'; select pg_sleep(1.2); commit;`,
                   s => { if (s.includes('HELD')) open(); });
  await held;
  const results = await Promise.all(statements.map(s => run(s)));
  await gate;
  return results;
}

let failures = 0;
const check = (name, cond, detail) => {
  if (cond) console.log(`  ok   ${name}`);
  else { failures++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`); }
};

// ---------------------------------------------------------------------
// 1. The SAME request submitted twice at once: one arrangement, one receipt.
// ---------------------------------------------------------------------
{
  const f = await fixture(1000);
  const rid = randomUUID();
  const sql = `${auth} select record_invoice_settlement('${f.invoice}', jsonb_build_object(
    'receipts', jsonb_build_array(jsonb_build_object('key','r1','payment_method_id','${f.method}','amount',100)),
    'arrangements', jsonb_build_array(jsonb_build_object('key','p1','category','in_house',
      'method_id','${f.method}','months',12,'covered_amount',900))), '${rid}');`;
  const r = await together(f.invoice, [sql, sql, sql]);
  check('no worker deadlocked', !r.some(x => /deadlock/i.test(x.err)),
        r.map(x => x.err.split('\n')[0]).filter(Boolean).join(' | '));
  const arr = Number(await ok(`select count(*) from invoice_payment_arrangements where invoice_id='${f.invoice}';`));
  check('one arrangement, however many submitted it', arr === 1, String(arr));
  const pays = Number(await ok(`select coalesce(sum(amount),0) from invoice_payments where invoice_id='${f.invoice}';`));
  check('the receipt is taken once', pays === 100, String(pays));
  const cov = Number(await ok(`select coalesce(sum(covered_amount),0) from invoice_payment_arrangements where invoice_id='${f.invoice}';`));
  check('coverage is not multiplied by the retries', cov === 900, String(cov));
  const status = await ok(`select status from invoices where id='${f.invoice}';`);
  check('the invoice is partially paid, not settled by a promise', status === 'partially_paid', status);
}

// ---------------------------------------------------------------------
// 2. Two DIFFERENT requests racing: coverage must not exceed what is owed.
// ---------------------------------------------------------------------
{
  const f = await fixture(1000);
  const mk = (k, amount) => `${auth} select record_invoice_settlement('${f.invoice}', jsonb_build_object(
    'arrangements', jsonb_build_array(jsonb_build_object('key','${k}','category','in_house',
      'method_id','${f.method}','months',6,'covered_amount',${amount}))), '${randomUUID()}');`;
  const r = await together(f.invoice, [mk('a', 700), mk('b', 700)]);
  check('neither session deadlocked', !r.some(x => /deadlock/i.test(x.err)),
        r.map(x => x.err.split('\n')[0]).filter(Boolean).join(' | '));
  const cov = Number(await ok(`select coalesce(sum(covered_amount),0) from invoice_payment_arrangements where invoice_id='${f.invoice}';`));
  check('combined coverage never exceeds what is owed', cov <= 1000, `${cov} of 1000`);
  check('at least one of the two was accepted', cov >= 700, String(cov));
}

// ---------------------------------------------------------------------
// 3. A later receipt racing a cancellation of the same invoice.
// ---------------------------------------------------------------------
{
  const f = await fixture(1000);
  await ok(`${auth} select record_invoice_settlement('${f.invoice}', jsonb_build_object(
    'receipts', jsonb_build_array(jsonb_build_object('key','d','payment_method_id','${f.method}','amount',100)),
    'arrangements', jsonb_build_array(jsonb_build_object('key','p','category','in_house',
      'method_id','${f.method}','months',12,'covered_amount',900))), '${randomUUID()}');`);
  const arr = await ok(`select id from invoice_payment_arrangements where invoice_id='${f.invoice}' limit 1;`);
  const r = await together(f.invoice, [
    `${auth} select record_invoice_settlement('${f.invoice}', jsonb_build_object(
       'receipts', jsonb_build_array(jsonb_build_object('key','later','payment_method_id','${f.method}','amount',200)),
       'arrangements', jsonb_build_array(jsonb_build_object('arrangement_id','${arr}','receipt_key','later'))), '${randomUUID()}');`,
    `${auth} select cancel_invoice_recorded('${f.invoice}','Raced cancellation','${randomUUID()}');`,
  ]);
  check('neither session deadlocked', !r.some(x => /deadlock/i.test(x.err)),
        r.map(x => x.err.split('\n')[0]).filter(Boolean).join(' | '));
  const held = Number(await ok(`select invoice_net_received('${f.invoice}');`));
  check('money received never exceeds what was actually taken', held <= 300, String(held));
  const cov = Number(await ok(`select coalesce(sum(covered_amount),0) from invoice_payment_arrangements where invoice_id='${f.invoice}';`));
  check('the race created no extra arrangement', cov === 900, String(cov));
}

console.log(failures === 0
  ? '\nPASS: concurrent identical submissions settle once, competing coverage never exceeds what is owed, and a later receipt racing a cancellation leaves the money and the terms consistent — with no deadlocks'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
