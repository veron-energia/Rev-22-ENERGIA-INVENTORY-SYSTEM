// New Invoice saves racing with one request id (416, INVOICES-CREATE-15).
//
// A cashier whose reply was lost presses Create again, perhaps more than once,
// while the first save is still running. Four sessions send the same request
// at the same instant: one invoice is made and every session gets its id. The
// same request id with other contents is refused. A single session cannot
// show this, since it never interleaves.
//
// Used by concurrency.mjs. `sql(query)` runs one psql session against a
// disposable database and resolves to { code, out, error }. Fixtures are
// invented and are committed there (the race needs separate sessions).
import { randomUUID } from 'node:crypto';

const GATE = 416416;
const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function createRequestRace(sql, assert) {
  const o = randomUUID(), st = randomUUID(), c = randomUUID(), p = randomUUID();
  const tag = st.slice(0, 6);
  const setup = await sql(`begin;
insert into auth.users(id,email) values('${o}','race416-${o}@tests.invalid');
insert into profiles(id,full_name,email,role) values('${o}','Race Owner','race416-${o}@tests.invalid','owner');
select set_config('request.jwt.claim.sub','${o}',true);
insert into stores(id,name,code,country_code) values('${st}','Race ${tag}','R416${tag}','SG');
insert into customers(id,full_name,phone) values('${c}','Race Buyer','+61491572549');
insert into products(id,name,sku,product_type) values('${p}','Race Socks','RS416-${tag}','own');
insert into store_inventory(store_id,product_id,current_qty) values('${st}','${p}',100);
select set_product_prices('${st}','${p}',100,100,'available');
commit;`);
  assert.equal(setup.code, 0, setup.error);

  const rid = randomUUID();
  // Every worker waits on a shared lock the gate holds, so they start together.
  const create = qty => `begin;
select set_config('request.jwt.claim.sub','${o}',true);
select pg_advisory_xact_lock_shared(${GATE});
select create_invoice_with_details('${st}','${c}',
  '[{"kind":"product","product_id":"${p}","quantity":${qty}}]'::jsonb,
  jsonb_build_object('business_date', sg_today()::text, 'request_id', '${rid}'));
commit;`;
  const gate = sql(`select pg_advisory_lock(${GATE}); select pg_sleep(1.5); select pg_advisory_unlock(${GATE});`);
  await sleep(400);
  const results = await Promise.all(Array.from({ length: 4 }, () => sql(create(1))));
  const gated = await gate;
  assert.equal(gated.code, 0, gated.error);
  for (const r of results) assert.equal(r.code, 0, r.error);
  const ids = results.map(r => r.out.split('\n').filter(Boolean).at(-1));
  assert.equal(new Set(ids).size, 1, `four racing saves returned ${JSON.stringify(ids)}`);

  const count = await sql(`select count(*) from invoices where create_request_id = '${rid}';
select count(*) from invoices where customer_id = '${c}';`);
  assert.equal(count.code, 0, count.error);
  assert.deepEqual(count.out.split('\n'), ['1', '1'], 'four racing saves with one request id made more than one invoice');

  const other = await sql(create(2));
  assert.notEqual(other.code, 0, 'the same request id with two pairs instead of one was accepted');
  assert.match(other.error, /This form already made .+\. Open that invoice to change it, instead of creating another\./);
  console.log('PASS: four New Invoice saves racing with one request id make one invoice and all get its id; the same id with other contents is refused');
}
