import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const env = { ...process.env, PGHOST: '/tmp', PGPORT: '55445', PGUSER: 'postgres', PGDATABASE: 'energia_invoice_date_test' };
function run(sql, onData) { return new Promise(resolveResult => {
  const child = spawn('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], { env }); let out = '', err = '';
  child.stdout.on('data', x => { out += x; onData?.(String(x)); }); child.stderr.on('data', x => err += x);
  child.on('close', code => resolveResult({ code, out: out.trim(), err })); child.stdin.end(sql);
}); }
async function ok(sql) { const r = await run(sql); assert.equal(r.code, 0, r.err); return r.out.split('\n').at(-1); }
assert.equal(await ok('show data_directory'), resolve('.invoice-date-test/data'));
assert.equal(await ok('select current_database()'), 'energia_invoice_date_test');
const owner = randomUUID(), store = randomUUID(), customer = randomUUID();
const ids = Array.from({ length: 5 }, randomUUID);
const auth = `select set_config('request.jwt.claim.sub','${owner}',true);`;
await ok(`begin; insert into auth.users(id,email) values('${owner}','${owner}@tests.invalid');
insert into profiles(id,full_name,email,role) values('${owner}','Date concurrency owner','${owner}@tests.invalid','owner');${auth}
insert into stores(id,name,code,country_code) values('${store}','Date concurrency','${store.slice(0,8)}','SG');
insert into customers(id,full_name,phone) values('${customer}','Date concurrency buyer','+6591188890');
${ids.map(id => `insert into invoices(id,invoice_no,store_id,customer_id,created_by,business_date,created_at) values('${id}','${id}','${store}','${customer}','${owner}',null,'2020-01-31T16:00:00Z');`).join('\n')}commit;`);
const preview = async id => JSON.parse(await ok(`begin;${auth}select jsonb_agg(x) from preview_invoice_date_recovery(array['${id}'::uuid]) x;commit;`));
const call = (rows, batch = randomUUID()) => `select apply_invoice_date_recovery('${batch}','${JSON.stringify(rows)}'::jsonb,'Concurrent review');`;
async function compete(id, sqls, gateAction = '') {
  let ready; const locked = new Promise(r => ready = r);
  const gate = run(`begin;${auth}select id from invoices where id='${id}' for update;${gateAction}select 'LOCKED';select pg_sleep(0.8);commit;`, s => { if (s.includes('LOCKED')) ready(); });
  await locked;
  const results = await Promise.all(sqls.map(sql => run(`begin;${auth}${sql}commit;`)));
  assert.equal((await gate).code, 0);return results;
}
let rows = await preview(ids[0]);
let results = await compete(ids[0], Array.from({ length: 5 }, () => call(rows)));
assert.ok(results.every(r => r.code === 0), JSON.stringify(results));
assert.equal(await ok(`select count(*) from invoice_date_recovery_events where invoice_id='${ids[0]}'`), '1');
console.log('PASS: five overlapping batches recover the invoice exactly once');
rows = await preview(ids[1]);const batch = randomUUID();
results = await compete(ids[1], [call(rows, batch), call(rows, batch)]);
assert.ok(results.every(r => r.code === 0), JSON.stringify(results));
assert.equal(await ok(`select count(*) from invoice_revisions where invoice_id='${ids[1]}'`), '1');
console.log('PASS: simultaneous retry of one batch creates one revision/event');
rows = await preview(ids[2]);
results = await compete(ids[2], [call(rows)], `update invoices set business_date='2018-01-01' where id='${ids[2]}';`);
assert.equal(results[0].code, 0, results[0].err);
assert.match(results[0].out, /already_has_date/);
assert.equal(await ok(`select business_date from invoices where id='${ids[2]}'`), '2018-01-01');
console.log('PASS: committed manual date wins while recovery waits for the row lock');
rows = await preview(ids[3]);
results = await compete(ids[3], [call(rows)], `insert into audit_logs(table_name,record_id,action,new_data,changed_by) values('invoices','${ids[3]}','invoice_imported','{}','${owner}');`);
assert.equal(results[0].code, 0, results[0].err);assert.match(results[0].out, /evidence_changed/);
assert.equal(await ok(`select business_date is null from invoices where id='${ids[3]}'`), 't');
console.log('PASS: evidence committed while recovery waits is re-read and skipped');
// Current UI submits expected_edit_count. Recovery must invalidate an editor
// opened while the date was NULL; otherwise it could clear the recovered date.
rows = await preview(ids[4]);
await ok(`begin;${auth}${call(rows)}commit;`);
const stale = await run(`begin;${auth}select correct_invoice('${ids[4]}','[]','{"expected_edit_count":0,"business_date":null,"notes":"Old editor"}','Stale correction','${randomUUID()}');commit;`);
assert.notEqual(stale.code, 0);assert.match(stale.err, /changed|reload/i);
console.log('PASS: stale normal editor cannot clear a recovered date');
// Test fixtures intentionally retained in the exclusive local cluster.
