// Real independent PostgreSQL sessions competing on the same invoice.
//
// Single-session repeat calls prove idempotency but not locking: they never
// interleave. These workers are separate psql processes released at the same
// instant, so the row locks in resolve_invoice_action_v2 and the refund engine
// are actually exercised.
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

// Refuse anything that is not the disposable fixture.
assert.equal(await ok('select current_database()'), 'energia_integration_test');
assert.equal(await ok('show data_directory'), resolve('.invoice-test/data'));

const owner = randomUUID(), staff = randomUUID();
// Session scope, not transaction scope: each worker is its own psql session
// and runs several statements, so a transaction-local setting would be gone by
// the second one.
const auth = u => `select set_config('request.jwt.claim.sub','${u}',false);`;

// The two people in these races: one who may approve, one who may only ask.
await ok(`begin;
  insert into auth.users(id,email) values('${owner}','cx-owner-${owner}@tests.invalid'),('${staff}','cx-staff-${staff}@tests.invalid');
  insert into profiles(id,full_name,email,role) values
    ('${owner}','CX Owner','cx-owner-${owner}@tests.invalid','owner'),
    ('${staff}','CX Staff','cx-staff-${staff}@tests.invalid','staff');
  commit;`);

async function fixture(qty, price) {
  const store = randomUUID(), cust = randomUUID(), method = randomUUID(), product = randomUUID();
  const tag = store.slice(0, 6);
  await ok(`${auth(owner)} begin;
    insert into stores(id,name,code,country_code) values('${store}','CX ${tag}','${tag.toUpperCase()}','SG');
    insert into user_store_assignments(user_id,store_id) values('${staff}','${store}');
    insert into customers(id,full_name,phone) values('${cust}','CX ${tag}','+65${Math.floor(80000000 + Math.random() * 9999999)}');
    insert into payment_methods(id,name,is_active) values('${method}','CX ${tag}',true);
    insert into products(id,name,sku,product_type) values('${product}','CX ${tag}','${tag}','own');
    insert into store_inventory(store_id,product_id,current_qty) values('${store}','${product}',500);
    select set_product_prices('${store}','${product}',${price},${price},'available');
    commit;`);
  const invoice = await ok(`${auth(owner)} select create_invoice_with_details('${store}','${cust}',
    jsonb_build_array(jsonb_build_object('kind','product','product_id','${product}','quantity',${qty})),
    jsonb_build_object('business_date',sg_today()::text));`);
  await ok(`${auth(owner)} select record_invoice_payment('${invoice}',
    jsonb_build_array(jsonb_build_object('payment_method_id','${method}','amount',${qty * price})),'${randomUUID()}');`);
  return { invoice, store, product, method };
}

// Release every worker at the same moment by making them queue behind one lock.
async function together(statements) {
  let open; const held = new Promise(r => open = r);
  const gate = run(`begin; select id from invoices where id='${statements.lockInvoice}' for update;
                    select 'HELD'; select pg_sleep(1.2); commit;`,
                   s => { if (s.includes('HELD')) open(); });
  await held;
  const workers = statements.sql.map(s => run(s));
  const results = await Promise.all(workers);
  await gate;
  return results;
}

let failures = 0;
const check = (name, condition, detail) => {
  if (condition) { console.log(`  ok   ${name}`); }
  else { failures++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`); }
};

// ---------------------------------------------------------------------
// 1. Two approvals of the same request, at the same instant.
// ---------------------------------------------------------------------
{
  const f = await fixture(3, 100);
  const req = JSON.parse(await ok(`${auth(staff)} select request_invoice_action_v2('${f.invoice}','refund_full',
    '[]'::jsonb,'Race: double approval',null,'${randomUUID()}');`)).request_id;
  const mv = await ok(`${auth(owner)} select movement_id from jsonb_to_recordset(
    invoice_action_plan('${f.invoice}','refund_full')->'stock') as t(movement_id uuid) limit 1;`);
  const approve = `${auth(owner)} select resolve_invoice_action_v2('${req}',true,'Race',null,'[]'::jsonb,
    jsonb_build_array(jsonb_build_object('movement_id','${mv}','sellable_quantity',3,'damaged_quantity',0,'not_returned_quantity',0)),false);`;
  const r = await together({ lockInvoice: f.invoice, sql: [approve, approve, approve] });
  check('no worker deadlocked or crashed', r.every(x => x.code === 0 || /already|Invoice request|nothing left/i.test(x.err)),
        r.map(x => x.err.split('\n')[0]).filter(Boolean).join(' | '));
  const refunds = await ok(`select coalesce(sum(amount),0) from invoice_refunds where invoice_id='${f.invoice}';`);
  check('refunded exactly once, within the payment ceiling', Number(refunds) === 300, `got ${refunds}`);
  const qty = await ok(`select current_qty from store_inventory where store_id='${f.store}' and product_id='${f.product}';`);
  check('stock returned at most once', Number(qty) === 500, `got ${qty}`);
  const approved = await ok(`select count(*) from approval_requests where id='${req}' and status='approved';`);
  check('the request reports one accurate outcome', Number(approved) === 1);
  const audits = await ok(`select count(*) from audit_logs where record_id='${req}' and action='invoice_action_approved';`);
  check('the approval is traceable in the audit log exactly once', Number(audits) === 1, `got ${audits}`);
}

// ---------------------------------------------------------------------
// 2. Approving a request while somebody refunds the same invoice directly.
// ---------------------------------------------------------------------
{
  const f = await fixture(4, 100);
  const req = JSON.parse(await ok(`${auth(staff)} select request_invoice_action_v2('${f.invoice}','refund_full',
    '[]'::jsonb,'Race: approval vs direct refund',null,'${randomUUID()}');`)).request_id;
  const plan = JSON.parse(await ok(`${auth(owner)} select invoice_action_plan('${f.invoice}','refund_full');`));
  const mv = plan.stock[0].movement_id;
  const item = await ok(`select id from invoice_items where invoice_id='${f.invoice}' limit 1;`);
  const pay = await ok(`select id from invoice_payments where invoice_id='${f.invoice}' limit 1;`);
  const r = await together({ lockInvoice: f.invoice, sql: [
    `${auth(owner)} select resolve_invoice_action_v2('${req}',true,'Race','${plan.plan_hash}','[]'::jsonb,
      jsonb_build_array(jsonb_build_object('movement_id','${mv}','sellable_quantity',4,'damaged_quantity',0,'not_returned_quantity',0)),false);`,
    `${auth(owner)} select refund_invoice_recorded('${f.invoice}',
      jsonb_build_array(jsonb_build_object('invoice_item_id','${item}','amount',100)),
      jsonb_build_array(jsonb_build_object('payment_id','${pay}','amount',100)),
      jsonb_build_array(jsonb_build_object('movement_id','${mv}','sellable_quantity',1)),'Direct','${randomUUID()}');`,
  ] });
  check('neither session deadlocked', !r.some(x => /deadlock/i.test(x.err)), r.map(x => x.err.split('\n')[0]).join(' | '));
  const total = Number(await ok(`select coalesce(sum(amount),0) from invoice_refunds where invoice_id='${f.invoice}';`));
  check('refunds never exceed the money held', total <= 400, `refunded ${total} of 400`);
  const resolved = Number(await ok(`select coalesce(sum(sellable_quantity+damaged_quantity+not_returned_quantity),0)
    from invoice_stock_dispositions where invoice_id='${f.invoice}';`));
  check('goods are never resolved beyond what was sold', resolved <= 4, `resolved ${resolved} of 4`);
  const qty = Number(await ok(`select current_qty from store_inventory where store_id='${f.store}' and product_id='${f.product}';`));
  check('stock never exceeds what was there to begin with', qty <= 500, `got ${qty}`);
}

// ---------------------------------------------------------------------
// 3. A refund and a cancellation of the same invoice at once.
// ---------------------------------------------------------------------
{
  const f = await fixture(2, 100);
  const req = JSON.parse(await ok(`${auth(staff)} select request_invoice_action_v2('${f.invoice}','cancel',
    '[]'::jsonb,'Race: cancel vs refund',null,'${randomUUID()}');`)).request_id;
  const plan = JSON.parse(await ok(`${auth(owner)} select invoice_action_plan('${f.invoice}','cancel');`));
  const mv = plan.stock[0].movement_id;
  const item = await ok(`select id from invoice_items where invoice_id='${f.invoice}' limit 1;`);
  const pay = await ok(`select id from invoice_payments where invoice_id='${f.invoice}' limit 1;`);
  const r = await together({ lockInvoice: f.invoice, sql: [
    `${auth(owner)} select resolve_invoice_action_v2('${req}',true,'Cancel','${plan.plan_hash}','[]'::jsonb,
      jsonb_build_array(jsonb_build_object('movement_id','${mv}','sellable_quantity',2,'damaged_quantity',0,'not_returned_quantity',0)),true);`,
    `${auth(owner)} select refund_invoice_recorded('${f.invoice}',
      jsonb_build_array(jsonb_build_object('invoice_item_id','${item}','amount',200)),
      jsonb_build_array(jsonb_build_object('payment_id','${pay}','amount',200)),
      jsonb_build_array(jsonb_build_object('movement_id','${mv}','sellable_quantity',2)),'Direct','${randomUUID()}');`,
  ] });
  check('neither session deadlocked', !r.some(x => /deadlock/i.test(x.err)), r.map(x => x.err.split('\n')[0]).join(' | '));
  const total = Number(await ok(`select coalesce(sum(amount),0) from invoice_refunds where invoice_id='${f.invoice}';`));
  check('the invoice is never refunded beyond what was paid', total <= 200, `refunded ${total} of 200`);
  const qty = Number(await ok(`select current_qty from store_inventory where store_id='${f.store}' and product_id='${f.product}';`));
  check('the two units come back at most once', qty <= 500, `got ${qty}`);
}

// ---------------------------------------------------------------------
// 4. The same request submitted repeatedly, at the same instant.
// ---------------------------------------------------------------------
{
  const f = await fixture(1, 100);
  const rid = randomUUID();
  const submit = `${auth(staff)} select request_invoice_action_v2('${f.invoice}','refund_full','[]'::jsonb,
    'Race: repeat submit',null,'${rid}');`;
  const r = await together({ lockInvoice: f.invoice, sql: [submit, submit, submit, submit] });
  check('no submission deadlocked', !r.some(x => /deadlock/i.test(x.err)), r.map(x => x.err.split('\n')[0]).join(' | '));
  const n = Number(await ok(`select count(*) from approval_requests where related_record_id='${f.invoice}';`));
  check('one request row, however many times it was sent', n === 1, `got ${n}`);
  const status = await ok(`select status from invoices where id='${f.invoice}';`);
  check('the invoice is still untouched by a request', status === 'paid', `got ${status}`);
}

// ---------------------------------------------------------------------
// 5. Credit spent between the preview and the approval.
// ---------------------------------------------------------------------
{
  const f = await fixture(3, 100);
  const req = JSON.parse(await ok(`${auth(staff)} select request_invoice_action_v2('${f.invoice}','refund_full',
    '[]'::jsonb,'Race: changed plan',null,'${randomUUID()}');`)).request_id;
  const plan = JSON.parse(await ok(`${auth(owner)} select invoice_action_plan('${f.invoice}','refund_full');`));
  const mv = plan.stock[0].movement_id;
  const item = await ok(`select id from invoice_items where invoice_id='${f.invoice}' limit 1;`);
  const pay = await ok(`select id from invoice_payments where invoice_id='${f.invoice}' limit 1;`);
  // A refund lands first, so the approver's stale hash no longer describes reality.
  await ok(`${auth(owner)} select refund_invoice_recorded('${f.invoice}',
    jsonb_build_array(jsonb_build_object('invoice_item_id','${item}','amount',100)),
    jsonb_build_array(jsonb_build_object('payment_id','${pay}','amount',100)),
    jsonb_build_array(jsonb_build_object('movement_id','${mv}','sellable_quantity',1)),'Earlier','${randomUUID()}');`);
  const out = JSON.parse(await ok(`${auth(owner)} select resolve_invoice_action_v2('${req}',true,'Stale',
    '${plan.plan_hash}','[]'::jsonb,
    jsonb_build_array(jsonb_build_object('movement_id','${mv}','sellable_quantity',2,'damaged_quantity',0,'not_returned_quantity',0)),false);`));
  check('a stale confirmation is refused, not executed', out.confirmation_required === true, JSON.stringify(out).slice(0, 120));
  const total = Number(await ok(`select coalesce(sum(amount),0) from invoice_refunds where invoice_id='${f.invoice}';`));
  check('nothing further was refunded on the stale plan', total === 100, `got ${total}`);
}

console.log(failures === 0
  ? '\nPASS: concurrent approvals, approval versus direct refund, refund versus cancellation, repeated submission and stale confirmations all hold their invariants with no deadlocks'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
