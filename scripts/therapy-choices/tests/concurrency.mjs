// Two real sessions choosing a benefit on the same unit at the same instant.
//
// Single-session repeat calls prove the request-id guard but not locking: they
// never interleave. These are separate psql processes released together, so the
// row lock in choose_therapy_benefit is actually exercised. One must win and
// the unit must end with exactly one benefit — never both, never two voucher
// allowances.
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const env = { ...process.env, PGHOST: '/tmp', PGPORT: '55441', PGUSER: 'postgres', PGDATABASE: 'energia_integration_test' };
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

assert.equal(await ok('select current_database()'), 'energia_integration_test');
assert.equal(await ok('show data_directory'), resolve('.invoice-test/data'));

let failures = 0;
const check = (label, cond, detail = '') => {
  if (cond) console.log(`  ok   ${label}`);
  else { failures++; console.log(`  FAIL ${label}${detail ? ' — ' + detail : ''}`); }
};

const owner = randomUUID(), tag = randomUUID().slice(0, 6);
const auth = u => `select set_config('request.jwt.claim.sub','${u}',false);`;

await ok(`begin;
  insert into auth.users(id,email) values('${owner}','tc-${owner}@tests.invalid');
  insert into profiles(id,full_name,email,role) values('${owner}','TC Owner','tc-${owner}@tests.invalid','owner');
  commit;`);

async function fixture() {
  const store = randomUUID(), cust = randomUUID(), method = randomUUID(),
        v1 = randomUUID(), v2 = randomUUID(), t = randomUUID().slice(0, 6);
  await ok(`${auth(owner)} begin;
    insert into stores(id,name,code,country_code) values('${store}','TC ${t}','${t.toUpperCase()}','SG');
    insert into customers(id,full_name,phone) values('${cust}','TC ${t}','+65${Math.floor(80000000 + Math.random() * 9999999)}');
    insert into payment_methods(id,name,is_active) values('${method}','TC ${t}',true);
    insert into vouchers(id,name,code,voucher_kind,qty_type,selling_price,is_active)
      values('${v1}','TC F ${t}','TCF${t}','normal','limited',50,true),
            ('${v2}','TC M ${t}','TCM${t}','normal','limited',50,true);
    insert into voucher_store_stock(voucher_id,store_id,current_qty) values('${v1}','${store}',50),('${v2}','${store}',50);
    commit;`);
  const pkg = await ok(`${auth(owner)} select upsert_therapy_package_choice(
    null,'TC Package ${t}','TCP-${t}',null,true,1,10,array['${v1}','${v2}']::uuid[],null);`);
  await ok(`${auth(owner)} insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
    values('${pkg}','${store}',500,true);`);
  const invoice = await ok(`${auth(owner)} select create_invoice('${store}','${cust}',null,
    jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id','${pkg}','quantity',1)));`);
  await ok(`${auth(owner)} select pay_invoice('${invoice}',
    jsonb_build_array(jsonb_build_object('payment_method_id','${method}','amount',500)));`);
  const unit = await ok(`${auth(owner)} select id from purchased_therapy_entitlements where invoice_id='${invoice}';`);
  return { unit, v1, store, invoice };
}

// ---- two different benefits, released together ----------------------------
{
  const f = await fixture();
  const [a, b] = await Promise.all([
    run(`${auth(owner)} select choose_therapy_benefit('${f.unit}','unlimited','${randomUUID()}',null);`),
    run(`${auth(owner)} select choose_therapy_benefit('${f.unit}','voucher','${randomUUID()}',null);`),
  ]);
  const winners = [a, b].filter(r => r.code === 0).length;
  check('exactly one concurrent choice succeeds', winners === 1, `${winners} succeeded`);

  const choice = await ok(`select coalesce(benefit_choice,'(none)') from purchased_therapy_entitlements where id='${f.unit}';`);
  check('the unit ends with one benefit', choice === 'unlimited' || choice === 'voucher', choice);

  const ents = Number(await ok(`select count(*) from therapy_entitlements
    where qualification_group_id = md5('therapy_unit:${f.unit}')::uuid;`));
  check('no more than one voucher allowance exists', ents <= 1, `${ents} allowances`);

  const both = Number(await ok(`select count(*) from purchased_therapy_entitlements
    where id='${f.unit}' and voucher_entitlement_id is not null and benefit_choice='unlimited';`));
  check('a unit never holds both benefits', both === 0);
}

// ---- the same request id twice, released together -------------------------
{
  const f = await fixture();
  const rq = randomUUID();
  const [a, b] = await Promise.all([
    run(`${auth(owner)} select choose_therapy_benefit('${f.unit}','voucher','${rq}',null);`),
    run(`${auth(owner)} select choose_therapy_benefit('${f.unit}','voucher','${rq}',null);`),
  ]);
  const winners = [a, b].filter(r => r.code === 0).length;
  check('a retried request is applied once', winners === 1, `${winners} succeeded`);
  const ents = Number(await ok(`select count(*) from therapy_entitlements
    where qualification_group_id = md5('therapy_unit:${f.unit}')::uuid;`));
  check('a retry creates no second allowance', ents === 1, `${ents} allowances`);
}

// ---- clean up what these committed -----------------------------------------
await ok(`set session_replication_role = replica;
  delete from public.therapy_choice_requests where purchased_entitlement_id in
    (select p.id from public.purchased_therapy_entitlements p
      join public.stores s on s.id=p.store_id where s.name like 'TC %');
  delete from public.purchased_therapy_entitlements where store_id in (select id from stores where name like 'TC %');
  delete from public.therapy_entitlements where store_id in (select id from stores where name like 'TC %');
  delete from public.voucher_store_stock where store_id in (select id from stores where name like 'TC %');
  delete from public.unlimited_therapy_store_prices where store_id in (select id from stores where name like 'TC %');
  delete from public.therapy_package_vouchers where package_id in (select id from unlimited_therapy_packages where name like 'TC Package %');
  delete from public.invoice_items where invoice_id in (select id from invoices where store_id in (select id from stores where name like 'TC %'));
  delete from public.invoice_payments where invoice_id in (select id from invoices where store_id in (select id from stores where name like 'TC %'));
  delete from public.invoices where store_id in (select id from stores where name like 'TC %');
  delete from public.unlimited_therapy_packages where name like 'TC Package %';
  delete from public.vouchers where name like 'TC F %' or name like 'TC M %';
  delete from public.payment_methods where name like 'TC %';
  delete from public.customers where full_name like 'TC %';
  delete from public.stores where name like 'TC %';
  delete from public.profiles where email like 'tc-%@tests.invalid';
  delete from auth.users where email like 'tc-%@tests.invalid';
  set session_replication_role = origin;`);

console.log(failures === 0
  ? '\nPASS: concurrent choices settle on exactly one benefit, a retried request is applied once, and no unit ends with two allowances'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
