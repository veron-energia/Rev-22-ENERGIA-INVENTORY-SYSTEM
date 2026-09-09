// Migrations 240-245 against the isolated local database.
//
//   scripts/auth-email/bootstrap-local.sh start
//   npm run test:therapy-services:db
//
// Four things are being checked, and only one of them is "the SQL parses":
//
//   * the service catalogue and its frequency rules, including agreement with
//     src/lib/therapy/frequency.mjs — the rule exists twice and drifts unless
//     something compares them;
//   * what a therapy voucher grants, and that issuing one FREEZES it, so a
//     later catalogue edit cannot change what a customer already holds;
//   * the mandatory credit-spending matrix, exercised through the real
//     allocation function rather than a copy of its rules;
//   * that a credit-package sale commissions at the third-party rate.
//
// The database is shared with sibling suites, so this file creates its own rows,
// names them distinctively, and clears only those.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { checkFrequency, checkServices, describeFrequency } from '../../../src/lib/therapy/frequency.mjs';

process.env.PGHOST ??= '/tmp'; process.env.PGPORT ??= '55442';
process.env.PGUSER ??= 'postgres'; process.env.PGDATABASE ??= 'energia_auth_email_test';
if (process.env.PGDATABASE !== 'energia_auth_email_test' || process.env.PGPORT !== '55442') {
  throw new Error('Refusing to run outside the disposable database on port 55442.');
}

const args = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'];
const sql = s => execFileSync('psql', [...args, '-c', s], { encoding: 'utf8' }).trim();
const json = s => JSON.parse(sql(s));
// Each psql invocation is its own session, so a set_config in one is gone by the
// next. Anything depending on session state has to travel with its query.
let storeAccess = 'all';
const sqlAs = (role, s) =>
  execFileSync('psql', [...args,
    '-c', `select set_config('test.role', '${role}', false),
                  set_config('test.user_id', '${ACTOR}', false),
                  set_config('test.store_access', '${storeAccess}', false);`,
    '-c', s], { encoding: 'utf8' }).trim().split('\n').filter(Boolean).pop();
const fails = (s, run = sql) => {
  try { run(s); return null; } catch (e) { return String(e.stderr ?? e.message); }
};

let pass = 0;
const ok = (label, cond, detail = '') => {
  console.log(`${cond ? 'PASS' : 'FAIL'}: ${label}${detail ? ` — ${detail}` : ''}`);
  if (!cond) process.exitCode = 1; else pass++;
};

const apply = f => execFileSync('psql', [...args, '-f', f], { encoding: 'utf8' });

// Order matters: the prior state restores the pre-240 versions of the functions
// the migrations patch, so it must always run BEFORE them. Running it afterwards
// silently undoes the patch under test.
apply('scripts/therapy-services/tests/prior-state.sql');
for (const f of ['240_therapy_services', '241_therapy_voucher_services',
                 '242_credit_spending_rules', '243_package_commission_classification',
                 '244_therapy_session_sales', '245_therapy_entitlement_read_models']) {
  apply(`supabase/${f}.sql`);
  apply(`supabase/${f}.sql`);            // idempotence is part of the contract
}
ok('migrations 240-245 apply over the pre-240 schema, and apply again, cleanly', true);

// --- this suite's own rows, cleared and rebuilt ----------------------------
const ACTOR = '00000000-0000-4000-8000-0000000000aa';
// Everything this file creates is named 'TS-TEST', and everything named
// 'TS-TEST' is deleted — in dependency order, because the previous run's
// invoice lines still reference its products. Nothing else in the shared
// database is touched.
//
// This runs on the way IN and on the way OUT. Leaving rows behind is not merely
// untidy: a sibling suite clears public.customers as part of its own setup, and
// an invoice of ours still pointing at one of them makes that delete fail and
// breaks a suite that has nothing to do with this one.
const clean = () => sql(`
  create temporary table if not exists ts_test_inv on commit drop as select 1;
  drop table if exists ts_test_inv;
  create temporary table ts_test_inv as
    select i.id from public.invoices i
     where i.invoice_no like 'TS-TEST%'
        or i.customer_id in (select id from public.customers where full_name like 'TS-TEST %');

  delete from public.invoice_line_credit_allocations where invoice_id in (select id from ts_test_inv);
  delete from public.customer_credit_allocations a
   using public.customers c where a.customer_id = c.id and c.full_name like 'TS-TEST %';
  delete from public.customer_credit_ledger l
   using public.customers c where l.customer_id = c.id and c.full_name like 'TS-TEST %';
  delete from public.customer_credit_lots l
   using public.customers c where l.customer_id = c.id and c.full_name like 'TS-TEST %';
  delete from public.customer_credit_wallets w
   using public.customers c where w.customer_id = c.id and c.full_name like 'TS-TEST %';
  delete from public.commissions where invoice_id in (select id from ts_test_inv);
  delete from public.credit_package_sales where invoice_id in (select id from ts_test_inv);
  delete from public.premium_bundle_sales where invoice_id in (select id from ts_test_inv);
  delete from public.customer_therapy_sessions where invoice_id in (select id from ts_test_inv)
     or customer_id in (select id from public.customers where full_name like 'TS-TEST %');
  delete from public.invoice_promotion_selections where invoice_item_id in
    (select id from public.invoice_items where invoice_id in (select id from ts_test_inv));
  delete from public.invoice_items where invoice_id in (select id from ts_test_inv);
  delete from public.invoices where id in (select id from ts_test_inv);
  delete from public.purchased_therapy_entitlements
   where customer_id in (select id from public.customers where full_name like 'TS-TEST %');
  delete from public.unlimited_therapy_packages where name like 'TS-TEST %';
  delete from public.credit_packages where name like 'TS-TEST %';
  delete from public.therapy_voucher_issues where voucher_id in
    (select id from public.vouchers where name like 'TS-TEST %');
  delete from public.customer_reward_vouchers where voucher_id in
    (select id from public.vouchers where name like 'TS-TEST %');
  delete from public.therapy_voucher_definitions where voucher_id in
    (select id from public.vouchers where name like 'TS-TEST %');
  delete from public.vouchers where name like 'TS-TEST %';
  delete from public.therapy_service_stores ss using public.therapy_services s
   where ss.service_id = s.id and s.service_code like 'TSTEST-%';
  delete from public.therapy_services where service_code like 'TSTEST-%';
  delete from public.products where name like 'TS-TEST %';
  delete from public.customers where full_name like 'TS-TEST %';
  delete from public.stores where name like 'TS-TEST %';
  drop table if exists ts_test_inv;
`);
clean();
process.on('exit', () => { try { clean(); } catch { /* nothing left to clean */ } });

sql(`insert into public.profiles (id, full_name, role)
     values ('${ACTOR}', 'TS-TEST Manager', 'manager')
     on conflict (id) do update set role = 'manager';`);

const store = sql(`insert into public.stores (name) values ('TS-TEST Store') returning id;`);

// Two services with different rules, because the interesting cases are about
// one service not constraining another.
const power = sqlAs('manager', `select (public.upsert_therapy_service(
  null, 'TSTEST-PR', 'Power Recharge', 88.00, 30, 'per_hours', 1, 5,
  'Fixture service', true, null)->>'id');`);
const detox = sqlAs('manager', `select (public.upsert_therapy_service(
  null, 'TSTEST-FD', 'Foot Detox', 48.00, 45, 'per_day', 1, null,
  'Fixture service', true, null)->>'id');`);

// =====================================================================
// 1. The catalogue (section 3)
// =====================================================================
{
  const missingDuration = fails(
    `select public.upsert_therapy_service(null,'TSTEST-X','No duration',10,null,'per_day',1,null,null,true,null);`,
    s => sqlAs('manager', s));
  ok('an active service cannot be saved without a duration',
     /duration in minutes/i.test(missingDuration ?? ''));

  const dupCode = fails(
    `select public.upsert_therapy_service(null,'tstest-pr','Clash',10,30,'per_day',1,null,null,false,null);`,
    s => sqlAs('manager', s));
  ok('and the service code is unique, case-insensitively',
     /already uses the code/i.test(dupCode ?? ''));

  const hoursWithoutInterval = fails(
    `select public.upsert_therapy_service(null,'TSTEST-Y','No interval',10,30,'per_hours',1,null,null,false,null);`,
    s => sqlAs('manager', s));
  ok('an hourly rule without an interval is refused, not stored as unusable',
     /hours between sessions/i.test(hoursWithoutInterval ?? ''));

  const asStaff = fails(
    `select public.upsert_therapy_service(null,'TSTEST-Z','Staff',10,30,'per_day',1,null,null,false,null);`,
    s => sqlAs('staff', s));
  ok('a Staff user cannot change the catalogue',
     /Owner or Manager/i.test(asStaff ?? ''));

  sqlAs('manager', `select public.set_therapy_service_store('${power}', '${store}', true, 99.00);`);
  const price = sql(`select public.therapy_service_price('${power}', '${store}');`);
  ok('a store price override is used in place of the standard price', price === '99.00', price);

  const elsewhere = sql(`select coalesce(public.therapy_service_price('${detox}', '${store}')::text, 'null');`);
  ok('and a service with no row for a store falls back to the standard price',
     elsewhere === '48.00', elsewhere);
}

// =====================================================================
// 2. Frequency: SQL and JavaScript, on the same cases (section 4)
// =====================================================================
{
  const base = '2026-03-04T02:00:00Z';                    // 10:00 Singapore
  const cases = [
    { label: 'a 5-hour rule blocks a second session 4 hours later',
      service: power, rule: { kind: 'per_hours', max_per_period: 1, interval_hours: 5 },
      at: '2026-03-04T06:00:00Z', history: [base], expect: false },
    { label: 'and allows it at exactly 5 hours',
      service: power, rule: { kind: 'per_hours', max_per_period: 1, interval_hours: 5 },
      at: '2026-03-04T07:00:00Z', history: [base], expect: true },
    { label: 'a once-a-day rule blocks a second session the same Singapore day',
      service: detox, rule: { kind: 'per_day', max_per_period: 1 },
      at: '2026-03-04T13:00:00Z', history: [base], expect: false },
    { label: 'and allows one after Singapore midnight, not UTC midnight',
      service: detox, rule: { kind: 'per_day', max_per_period: 1 },
      at: '2026-03-04T17:00:00Z', history: [base], expect: true },   // 01:00 the 5th, SGT
    { label: 'an empty history never blocks',
      service: detox, rule: { kind: 'per_day', max_per_period: 1 },
      at: base, history: [], expect: true },
  ];

  let agreed = 0;
  for (const c of cases) {
    const hist = c.history.length
      ? `array[${c.history.map(h => `'${h}'::timestamptz`).join(',')}]`
      : `'{}'::timestamptz[]`;
    const fromSql = json(
      `select public.therapy_service_frequency_ok('${c.service}', '${c.at}'::timestamptz, ${hist});`);
    const fromJs = checkFrequency({ rule: c.rule, at: c.at, history: c.history });
    ok(c.label, fromSql.allowed === c.expect, `sql said ${fromSql.allowed}`);
    if (fromSql.allowed === fromJs.allowed) agreed++;
  }
  ok('the SQL rule and src/lib/therapy/frequency.mjs agree on every case',
     agreed === cases.length, `${agreed}/${cases.length}`);

  // The case that matters most in a shop: two services on the same day.
  const both = checkServices({
    services: [{ id: power, frequency_rule: { kind: 'per_hours', max_per_period: 1, interval_hours: 5 } },
               { id: detox, frequency_rule: { kind: 'per_day', max_per_period: 1 } }],
    at: '2026-03-04T06:00:00Z',
    historyByService: { [power]: [base] },
  });
  const detoxSql = json(
    `select public.therapy_service_frequency_ok('${detox}', '2026-03-04T06:00:00Z'::timestamptz, '{}'::timestamptz[]);`);
  ok('a Power Recharge earlier today does not block a Foot Detox',
     both[detox].allowed === true && detoxSql.allowed === true);
  ok('while it does still block another Power Recharge', both[power].allowed === false);

  const text = sql(`select public.therapy_frequency_description('per_hours', 1, 5);`);
  ok('the description is generated from the same fields, not typed separately',
     text === describeFrequency({ kind: 'per_hours', max_per_period: 1, interval_hours: 5 }),
     text);
}

// =====================================================================
// 3. What a therapy voucher grants (section 5)
// =====================================================================
const voucher = name => sql(
  `insert into public.vouchers (name, code, voucher_kind, selling_price)
   values ('TS-TEST ${name}', 'TST-${name.replace(/\W/g, '').toUpperCase()}', 'normal', 120)
   returning id;`);

const define = (v, components, extra = '') => sqlAs('manager',
  `select public.upsert_therapy_voucher_definition('${v}', '${JSON.stringify(components)}'::jsonb${extra});`);

{
  // The five shapes the task names, each expressed without a special case.
  const shapes = [
    { name: 'Fixed one',
      components: [{ kind: 'fixed', service_id: power, quantity: 1 }],
      sessions: 1, summary: '1 x Power Recharge' },
    { name: 'Choice one',
      components: [{ kind: 'choice', service_ids: [power, detox], quantity: 1 }],
      sessions: 1, summary: '1 x chosen from Foot Detox or Power Recharge' },
    { name: 'Flexible two',
      components: [{ kind: 'choice', service_ids: [power, detox], quantity: 2 }],
      sessions: 2, summary: '2 x chosen from Foot Detox or Power Recharge' },
    { name: 'Fixed pair',
      components: [{ kind: 'fixed', service_id: power, quantity: 1 },
                   { kind: 'fixed', service_id: detox, quantity: 1 }],
      sessions: 2, summary: '1 x Power Recharge, then 1 x Foot Detox' },
    { name: 'Mixed',
      components: [{ kind: 'fixed', service_id: power, quantity: 1 },
                   { kind: 'choice', service_ids: [power, detox], quantity: 2 }],
      sessions: 3, summary: '1 x Power Recharge, then 2 x chosen from Foot Detox or Power Recharge' },
  ];

  let right = 0, described = 0;
  for (const s of shapes) {
    const v = voucher(s.name);
    s.id = v;
    const def = JSON.parse(define(v, s.components));
    if (Number(def.sessions_per_voucher) === s.sessions) right++;
    const text = sql(`select public.therapy_voucher_summary_text(public.therapy_voucher_definition('${v}'));`);
    if (text === s.summary) described++; else console.log(`      (${s.name}) ${text}`);
  }
  ok('all five voucher shapes are expressible, and count their sessions correctly',
     right === shapes.length, `${right}/${shapes.length}`);
  ok('and each describes itself from its own structure', described === shapes.length,
     `${described}/${shapes.length}`);

  globalThis.SHAPES = shapes;

  // Nothing defaults to "any two therapies".
  const empty = fails(`select public.upsert_therapy_voucher_definition('${shapes[0].id}', '[]'::jsonb);`,
    s => sqlAs('manager', s));
  ok('a voucher with no stated contents is refused rather than assumed',
     /at least one fixed session or one choice group/i.test(empty ?? ''));

  const emptyChoice = fails(
    `select public.upsert_therapy_voucher_definition('${shapes[0].id}',
       '[{"kind":"choice","quantity":1,"service_ids":[]}]'::jsonb);`, s => sqlAs('manager', s));
  ok('a choice with nothing to choose from is refused',
     /needs services to choose from/i.test(emptyChoice ?? ''));

  const staffEdit = fails(
    `select public.upsert_therapy_voucher_definition('${shapes[0].id}',
       '[{"kind":"fixed","service_id":"${power}","quantity":1}]'::jsonb);`, s => sqlAs('staff', s));
  ok('and Staff cannot decide what a voucher gives', /Owner or Manager/i.test(staffEdit ?? ''));

  // A failed edit must not leave a half-written definition behind.
  const before = sql(`select count(*) from public.therapy_voucher_components where voucher_id = '${shapes[4].id}';`);
  fails(`select public.upsert_therapy_voucher_definition('${shapes[4].id}',
           '[{"kind":"fixed","service_id":"${power}","quantity":1},
             {"kind":"choice","quantity":1,"service_ids":[]}]'::jsonb);`, s => sqlAs('manager', s));
  const after = sql(`select count(*) from public.therapy_voucher_components where voucher_id = '${shapes[4].id}';`);
  ok('a rejected edit leaves the previous definition intact', before === after, `${before} then ${after}`);

  const guard = fails(`insert into public.therapy_voucher_component_services (component_id, service_id)
    select id, '${detox}' from public.therapy_voucher_components
     where voucher_id = '${shapes[0].id}' and component_kind = 'fixed' limit 1;`);
  ok('a fixed component cannot be given a list of alternatives by a direct insert',
     /Only a choice component/i.test(guard ?? ''));
}

// =====================================================================
// 4. Issuance freezes the terms (section 6)
// =====================================================================
{
  const customer = sql(`insert into public.customers (full_name, phone)
    values ('TS-TEST Voucher Holder', '+6598000241') returning id;`);
  const mixed = globalThis.SHAPES[4].id;

  // Give it a validity so there is something time-based to freeze.
  define(mixed, globalThis.SHAPES[4].components, `, 'months', 6, 'per_week', 1, null, 'Fixture terms'`);

  const rv = sql(`insert into public.customer_reward_vouchers
    (customer_id, voucher_id, store_id, quantity, issued_at)
    values ('${customer}', '${mixed}', '${store}', 2, '2026-03-01T02:00:00Z') returning id;`);

  const issue = json(`select coalesce(to_jsonb(i), 'null'::jsonb) from public.therapy_voucher_issues i
                       where reward_voucher_id = '${rv}';`);
  ok('issuing a therapy voucher snapshots it automatically', issue !== null);
  ok('the snapshot scales by the quantity issued',
     issue && issue.units === 2 && issue.sessions_per_unit === 3 && issue.sessions_total === 6,
     issue && `${issue.units} x ${issue.sessions_per_unit} = ${issue.sessions_total}`);
  ok('a six-month validity expires on the day before the anniversary',
     issue?.valid_until === '2026-08-31', issue?.valid_until);
  ok('and it is not marked as applied after the fact',
     issue?.applied_retrospectively === false);

  const frozenNames = (issue?.definition_snapshot?.components ?? [])
    .flatMap(c => c.services.map(s => s.name)).sort().join(', ');
  ok('the snapshot carries service names, not just ids',
     frozenNames.includes('Power Recharge') && frozenNames.includes('Foot Detox'), frozenNames);

  // THE point of the snapshot: change the catalogue and the voucher afterwards.
  sqlAs('manager', `select public.upsert_therapy_service('${power}', 'TSTEST-PR',
    'Power Recharge Deluxe', 188.00, 60, 'per_day', 1, null, null, true, null);`);
  define(mixed, [{ kind: 'fixed', service_id: detox, quantity: 1 }]);

  const after = json(`select definition_snapshot from public.therapy_voucher_issues
                       where reward_voucher_id = '${rv}';`);
  const stillThere = after.components.flatMap(c => c.services.map(s => s.name));
  ok('renaming the service does not rewrite an already issued voucher',
     stillThere.includes('Power Recharge') && !stillThere.includes('Power Recharge Deluxe'),
     stillThere.join(', '));
  ok('nor does redefining the voucher change what was already given away',
     after.components.length === 2, `${after.components.length} components`);

  // Put the catalogue back. The rename above was a means of proving the
  // snapshot holds, not a state later sections should inherit — leaving it
  // renamed made section 7 assert against this section's internals.
  sqlAs('manager', `select public.upsert_therapy_service('${power}', 'TSTEST-PR',
    'Power Recharge', 88.00, 30, 'per_hours', 1, 5, 'Fixture service', true, null);`);

  const totals = json(`select to_jsonb(r) from
    public.customer_therapy_voucher_rights('${customer}', '2026-06-01'::date) r limit 1;`);
  ok('the customer still reads as holding six sessions',
     totals.sessions_remaining === 6 && totals.rights_recorded === true,
     `${totals.sessions_remaining} remaining`);
  ok('and as usable, because it is held and unexpired',
     totals.is_usable === true && totals.is_expired === false);

  // Re-running the snapshot must never re-freeze.
  const again = sql(`select public.snapshot_therapy_voucher_issue('${rv}', false);`);
  const count = sql(`select count(*) from public.therapy_voucher_issues where reward_voucher_id = '${rv}';`);
  ok('re-snapshotting an issued voucher is a no-op, not a second set of rights',
     count === '1' && again !== '', `${count} row(s)`);

  // Whole-voucher status is the only thing that currently reduces the count.
  sql(`update public.customer_reward_vouchers set status = 'revoked' where id = '${rv}';`);
  const revoked = json(`select to_jsonb(r) from
    public.customer_therapy_voucher_rights('${customer}', '2026-06-01'::date) r limit 1;`);
  ok('a revoked voucher has nothing remaining and is not usable',
     revoked.sessions_remaining === 0 && revoked.is_usable === false);
  sql(`update public.customer_reward_vouchers set status = 'held' where id = '${rv}';`);

  const expired = json(`select to_jsonb(r) from
    public.customer_therapy_voucher_rights('${customer}', '2027-01-01'::date) r limit 1;`);
  ok('and an expired one reads as expired rather than silently usable',
     expired.is_expired === true && expired.is_usable === false);

  // A voucher issued before anyone described it.
  const plain = voucher('Undescribed');
  const oldRv = sql(`insert into public.customer_reward_vouchers
    (customer_id, voucher_id, store_id, quantity) values
    ('${customer}', '${plain}', '${store}', 1) returning id;`);
  const unrecorded = json(`select to_jsonb(r) from public.customer_therapy_voucher_rights('${customer}') r
                            where r.reward_voucher_id = '${oldRv}';`);
  ok('a voucher with no definition is reported as unrecorded, never guessed at',
     unrecorded.rights_recorded === false && unrecorded.sessions_total === 0 &&
     /No therapy-service rights recorded/.test(unrecorded.summary_text));

  const listed = sql(`select count(*) from public.therapy_vouchers_without_rights()
                       where reward_voucher_id = '${oldRv}';`);
  ok('and it appears on the list a Manager works through', listed === '1');

  // Applying rights afterwards is deliberate, permissioned and marked.
  define(plain, [{ kind: 'fixed', service_id: detox, quantity: 1 }]);
  const staffApply = fails(
    `select public.apply_therapy_voucher_rights_retrospectively('${oldRv}');`, s => sqlAs('staff', s));
  ok('Staff cannot attach rights to an already issued voucher',
     /Owner or Manager/i.test(staffApply ?? ''));

  const applied = JSON.parse(sqlAs('manager',
    `select public.apply_therapy_voucher_rights_retrospectively('${oldRv}');`));
  ok('a Manager can, and the record says it was applied after the fact',
     applied.applied_retrospectively === true && applied.sessions_total === 1);

  const twice = fails(
    `select public.apply_therapy_voucher_rights_retrospectively('${oldRv}');`, s => sqlAs('manager', s));
  ok('but not twice', /already has recorded therapy rights/i.test(twice ?? ''));

  const eligible = json(`select coalesce(jsonb_agg(to_jsonb(e) order by e.sort_order, e.service_name), '[]')
                           from public.therapy_voucher_eligible_services('${rv}') e;`);
  // A service may appear under more than one component — here a fixed Power
  // Recharge and a choice that also offers it. Reporting per component is what
  // keeps "one Power Recharge, then one of two" legible, so the shape is the
  // assertion, not a flat list of names.
  ok('the eligible services of a held voucher come from its snapshot, per component',
     eligible.length === 3
     && eligible[0].component_kind === 'fixed' && eligible[0].service_name === 'Power Recharge'
     && eligible.filter(e => e.component_kind === 'choice').length === 2
     && eligible.filter(e => e.component_kind === 'choice').every(e => e.quantity === 2),
     eligible.map(e => `${e.sort_order}:${e.component_kind}:${e.service_name}`).join(' | '));
}

// =====================================================================
// 5. The mandatory credit-spending matrix (sections 8 and 9)
// =====================================================================
{
  // The matrix exactly as the task states it. Read as: a lot with this
  // provenance may fund these things and nothing else.
  const matrix = [
    ['package_paid',  'therapy_session',      true ],
    ['package_paid',  'session_voucher',      true ],
    ['package_paid',  'own_product',          false],
    ['package_paid',  'third_party_product',  false],
    ['package_paid',  'unlimited_therapy',    false],
    ['package_bonus', 'own_product',          true ],
    ['package_bonus', 'third_party_product',  false],
    ['package_bonus', 'therapy_session',      false],
    ['package_bonus', 'session_voucher',      false],
    ['bundle_any',    'own_product',          true ],
    ['bundle_any',    'third_party_product',  true ],
    ['bundle_any',    'therapy_session',      true ],
    ['bundle_any',    'session_voucher',      true ],
    // Nothing may be used to buy more credit, whatever it came from.
    ['bundle_any',    'credit_package',       false],
    ['open',          'credit_package',       false],
    ['open',          'premium_bundle',       false],
    // An unidentifiable balance is held, not assumed to be cash.
    ['needs_review',  'own_product',          false],
    ['needs_review',  'therapy_session',      false],
  ];
  const got = json(`select jsonb_agg(x) from (select public.credit_policy_allows(p, c) as x from (values ${
    matrix.map(([p, c]) => `('${p}','${c}')`).join(',')}) v(p, c)) q;`);
  const wrong = matrix.filter((row, i) => got[i] !== row[2]);
  ok('the credit matrix answers all eighteen combinations as specified',
     wrong.length === 0, wrong.map(r => r.join('/')).join(', '));

  // Provenance, not naming, decides the policy.
  const policies = json(`select jsonb_agg(public.credit_lot_policy(t, c, h)) from
    (values ('credit_package','paid',true), ('credit_package','bonus',true),
            ('premium_bundle','paid',true), ('manual','paid',true),
            ('credit_package','paid',false), ('something_new','paid',true))
     as v(t, c, h);`);
  ok('a lot policy is read from its source and category, in that order',
     JSON.stringify(policies) === JSON.stringify(
       ['package_paid','package_bonus','bundle_any','open','needs_review','needs_review']),
     policies.join(', '));
  ok('and a source this system does not recognise is held for review, not opened up',
     policies[4] === 'needs_review' && policies[5] === 'needs_review');
}

// --- the same rules, through the real allocation function ------------------
{
  const customer = sql(`insert into public.customers (full_name, phone)
    values ('TS-TEST Credit Holder', '+6598000242') returning id;`);
  const wallet = sql(`select public.ensure_customer_wallet('${customer}');`);
  const own = sql(`insert into public.products (name, product_type)
    values ('TS-TEST Own Brand', 'own') returning id;`);
  const third = sql(`insert into public.products (name, product_type)
    values ('TS-TEST Third Party', 'third_party') returning id;`);

  const lot = (category, source, amount) => sql(`insert into public.customer_credit_lots
    (wallet_id, customer_id, category, original_amount, remaining_amount,
     source_type, source_record_id, store_id)
    values ('${wallet}', '${customer}', '${category}', ${amount}, ${amount},
            '${source}', gen_random_uuid(), '${store}') returning id;`);

  const paidLot  = lot('paid',  'credit_package', 500);
  const bonusLot = lot('bonus', 'credit_package', 500);

  const invoice = (lines) => {
    const id = sql(`insert into public.invoices (invoice_no, customer_id, store_id, status)
      values ('TS-TEST-${Math.random().toString(36).slice(2, 8)}', '${customer}', '${store}', 'unpaid')
      returning id;`);
    for (const l of lines) {
      sql(`insert into public.invoice_items
        (invoice_id, line_kind, product_id, voucher_id, therapy_service_id,
         quantity, unit_price, line_total)
        values ('${id}', '${l.kind}', ${l.product ? `'${l.product}'` : 'null'},
                ${l.voucher ? `'${l.voucher}'` : 'null'},
                ${l.service ? `'${l.service}'` : 'null'}, 1, ${l.amount}, ${l.amount});`);
    }
    return id;
  };

  // A third-party product, paid for with credit-package credit. The paid lot
  // must refuse it; the bonus lot must refuse it too.
  // The refusal surfaces as an error rather than a silent partial payment,
  // which is the right shape: the cashier is told, and no row is written.
  const inv1 = invoice([{ kind: 'product', product: third, amount: 100 }]);
  const r1 = fails(`select public.allocate_invoice_wallet_credit('${inv1}', 100);`);
  const rows1 = sql(`select count(*) from public.invoice_line_credit_allocations
                      where invoice_id = '${inv1}';`);
  ok('credit-package credit cannot buy a third-party product',
     /could be funded by eligible credit/.test(r1 ?? '') && rows1 === '0',
     `${rows1} allocation(s)`);

  // The same wallet, an own-brand product: the BONUS lot pays, and the paid lot
  // is still refused. Checking which lot paid is the point — an allocation
  // existing is not evidence the right one funded it.
  const inv2 = invoice([{ kind: 'product', product: own, amount: 100 }]);
  sql(`select public.allocate_invoice_wallet_credit('${inv2}', 100);`);
  const funded = json(`select coalesce(jsonb_agg(jsonb_build_object(
      'lot', a.lot_id, 'category', a.category, 'amount', a.amount)), '[]')
    from public.invoice_line_credit_allocations a where a.invoice_id = '${inv2}';`);
  ok('an own-brand product is funded, and only from the bonus lot',
     funded.length === 1 && funded[0].lot === bonusLot && funded[0].category === 'bonus'
     && Number(funded[0].amount) === 100,
     funded.map(f => `${f.category} ${f.amount}`).join(', '));

  const paidLeft = sql(`select remaining_amount from public.customer_credit_lots where id = '${paidLot}';`);
  ok('and the restricted paid lot is untouched by it', paidLeft === '500.00', paidLeft);

  // What the paid lot IS for: an individual therapy session.
  const inv3 = invoice([{ kind: 'therapy', service: power, amount: 88 }]);
  sql(`select public.allocate_invoice_wallet_credit('${inv3}', 88);`);
  const session = json(`select coalesce(jsonb_agg(jsonb_build_object(
      'lot', a.lot_id, 'category', a.category)), '[]')
    from public.invoice_line_credit_allocations a where a.invoice_id = '${inv3}';`);
  ok('a therapy session IS payable from credit-package paid credit',
     session.length === 1 && session[0].lot === paidLot && session[0].category === 'paid',
     JSON.stringify(session));

  // The discriminator, not the price or the name: the same line kind without a
  // service is an unlimited-therapy package, which paid credit may not buy.
  const inv4 = invoice([{ kind: 'therapy', amount: 88 }]);
  const r4 = fails(`select public.allocate_invoice_wallet_credit('${inv4}', 88);`);
  const rows4 = sql(`select count(*) from public.invoice_line_credit_allocations
                      where invoice_id = '${inv4}';`);
  ok('while an unlimited-therapy line — same line kind, no service — is refused',
     /could be funded by eligible credit/.test(r4 ?? '') && rows4 === '0',
     `${rows4} allocation(s)`);

  // Buying more credit with credit, from any lot.
  const inv5 = invoice([{ kind: 'credit_package', amount: 100 }]);
  const r5 = fails(`select public.allocate_invoice_wallet_credit('${inv5}', 100);`);
  const rows5 = sql(`select count(*) from public.invoice_line_credit_allocations
                      where invoice_id = '${inv5}';`);
  ok('and no credit of any kind may buy another credit package',
     /could be funded by eligible credit/.test(r5 ?? '') && rows5 === '0',
     `${rows5} allocation(s)`);

  // An unidentifiable lot is held rather than treated as cash.
  const orphan = sql(`insert into public.customer_credit_lots
    (wallet_id, customer_id, category, original_amount, remaining_amount, source_type, store_id)
    values ('${wallet}', '${customer}', 'paid', 300, 300, 'credit_package', '${store}') returning id;`);
  ok('a package lot with no source record reads as needing review',
     sql(`select public.credit_lot_policy_for('${orphan}');`) === 'needs_review');
  const listed = sql(`select count(*) from public.credit_lots_needing_review() where lot_id = '${orphan}';`);
  ok('and appears on the review list with its amount untouched',
     listed === '1' && sql(`select remaining_amount from public.customer_credit_lots
                             where id = '${orphan}';`) === '300.00');

  const inv6 = invoice([{ kind: 'product', product: own, amount: 50 }]);
  fails(`select public.allocate_invoice_wallet_credit('${inv6}', 50);`);
  const spentOrphan = sql(`select count(*) from public.invoice_line_credit_allocations
                            where invoice_id = '${inv6}' and lot_id = '${orphan}';`);
  ok('an unreviewed lot is never spent, even when it would otherwise fit',
     spentOrphan === '0');

  const eligibility = json(`select coalesce(jsonb_agg(to_jsonb(e) order by e.policy), '[]')
                              from public.customer_credit_eligibility('${customer}') e;`);
  const byPolicy = Object.fromEntries(eligibility.map(e => [e.policy, e]));
  ok('the customer-facing summary states each balance WITH what it may pay for',
     eligibility.length === 3
     && byPolicy.package_paid?.allowed_categories?.includes('therapy_session')
     && byPolicy.package_bonus?.allowed_categories?.join() === 'own_product'
     && byPolicy.needs_review?.needs_review === true
     && byPolicy.needs_review?.allowed_categories?.length === 0,
     eligibility.map(e => `${e.policy}=${e.remaining}`).join(' '));
  ok('and the held balance carries the reason it cannot be spent, not just a flag',
     /cannot identify|confirm/i.test(byPolicy.needs_review?.explanation ?? ''),
     byPolicy.needs_review?.explanation);
}

// =====================================================================
// 6. Commission on package sales (section 11)
// =====================================================================
{
  const referrer = sql(`insert into public.customers (full_name, phone)
    values ('TS-TEST Referrer', '+6598000243') returning id;`);
  const buyer = sql(`insert into public.customers (full_name, phone, referred_by)
    values ('TS-TEST Buyer', '+6598000244', '${referrer}') returning id;`);

  sql(`insert into public.app_settings (id) values (true) on conflict (id) do nothing;`);
  const rates = json(`select to_jsonb(a) from public.app_settings a where id = true;`);

  // The catalogue can no longer claim a package is own-brand at all.
  const ownAttempt = fails(`insert into public.credit_packages
    (name, customer_price, paid_credit_amount, commission_classification)
    values ('TS-TEST Own Attempt', 1000, 1000, 'own');`);
  ok('a credit package can no longer be classified own-brand',
     /third_party_commission|check constraint/i.test(ownAttempt ?? ''));

  const pkg = sql(`insert into public.credit_packages
    (name, customer_price, paid_credit_amount) values ('TS-TEST Package', 1000, 1000) returning id;`);
  ok('and a new one defaults to third-party',
     sql(`select commission_classification from public.credit_packages where id = '${pkg}';`)
       === 'third_party');

  const inv = sql(`insert into public.invoices (invoice_no, customer_id, store_id, status, paid_at)
    values ('TS-TEST-COMM', '${buyer}', '${store}', 'paid', now()) returning id;`);

  // The sale carries an 'own' snapshot, which is exactly what the historical
  // rows carry. The commission function must ignore it — the snapshot is still
  // recorded, it simply no longer chooses the rate.
  const sale = sql(`insert into public.credit_package_sales
    (package_id, customer_id, store_id, invoice_id, classification_snapshot, external_paid)
    values ('${pkg}', '${buyer}', '${store}', '${inv}', 'own', 1000) returning id;`);

  json(`select public.earn_credit_package_commission('${sale}');`);
  const t1 = json(`select coalesce(to_jsonb(c), 'null'::jsonb) from public.commissions c
                    where c.invoice_id = '${inv}' and c.tier = 'tier1';`);
  ok('a S$1,000 package sale commissions at the third-party rate',
     Number(t1.rate) === Number(rates.commission_tier1_third_rate)
     && Number(t1.commission_amount) === 45, `${t1.rate}% = ${t1.commission_amount}`);
  ok('even though the sale still carries an own-brand snapshot — the defect',
     sql(`select classification_snapshot from public.credit_package_sales where id = '${sale}';`)
       === 'own' && Number(t1.commission_amount) !== 150,
     `the own rate of ${rates.commission_tier1_own_rate}% would have paid 150`);
  ok('and the classification recorded on the commission says third_party',
     t1.product_type === 'third_party', t1.product_type);

  // Basis: external money only. Credit issued and bonus credit earn nothing.
  const free = sql(`insert into public.credit_package_sales
    (package_id, customer_id, store_id, invoice_id, classification_snapshot, external_paid)
    values ('${pkg}', '${buyer}', '${store}', '${inv}', 'third_party', 0) returning id;`);
  const skipped = json(`select public.earn_credit_package_commission('${free}');`);
  ok('a package settled entirely from credit earns no commission at all',
     skipped.skipped === true && /no external payment/.test(skipped.reason ?? ''),
     skipped.reason);

  ok('the classification rule is a single answer, not a per-row setting',
     sql(`select public.package_commission_classification();`) === 'third_party');

  const diag = sql(`select count(*) from public.package_commission_diagnostic();`);
  ok('and a read-only diagnostic lists historical sales without changing one',
     Number.isFinite(Number(diag)), `${diag} row(s)`);

  const before = sql(`select count(*) from public.commissions;`);
  sql(`select * from public.package_commission_diagnostic();
       select * from public.package_classification_gaps();`);
  ok('running the diagnostics rewrites no commission',
     sql(`select count(*) from public.commissions;`) === before, before);

  // A catalogue row left classified 'own' behind the constraint would become
  // UNEDITABLE — a NOT VALID check skips existing rows but still binds updates
  // to them. The migration therefore corrects the catalogue before constraining
  // it. This drops the constraint, plants exactly that row, and re-applies it.
  sql(`alter table public.credit_packages drop constraint if exists credit_packages_third_party_commission;
       insert into public.credit_packages (name, customer_price, paid_credit_amount, commission_classification)
       values ('TS-TEST Legacy Own', 500, 500, 'own');`);
  apply('supabase/243_package_commission_classification.sql');

  const legacy = sql(`select commission_classification from public.credit_packages
                       where name = 'TS-TEST Legacy Own';`);
  ok('re-applying the migration corrects a catalogue row still classified own',
     legacy === 'third_party', legacy);

  const editable = fails(`update public.credit_packages set customer_price = 600
                           where name = 'TS-TEST Legacy Own';`);
  ok('and that row stays editable rather than being trapped behind the constraint',
     editable === null, editable ?? '');

  const audited = sql(`select count(*) from public.audit_logs
                        where action = 'commission_classification_corrected'
                          and record_id = (select id from public.credit_packages
                                            where name = 'TS-TEST Legacy Own');`);
  ok('the correction is recorded, with what the setting was before', audited === '1', audited);

  const snapshotsIntact = sql(`select count(*) from public.credit_package_sales
                                where classification_snapshot = 'own';`);
  ok('while past sale snapshots keep saying what they said',
     Number(snapshotsIntact) >= 1, `${snapshotsIntact} snapshot(s) still 'own'`);

  const gaps = sql(`select count(*) from public.package_classification_gaps();`);
  ok('and no catalogue row is left disagreeing with the rule', gaps === '0', gaps);
}

// =====================================================================
// 7. Selling an individual therapy session (section 7)
// =====================================================================
{
  // Migration 244 patches the INSTALLED create_invoice rather than restating
  // it, so what it anchors on has to still be true of the migration that last
  // defined it in production. The fixture's create_invoice reproduces those two
  // branches verbatim; this is what catches the copy going stale.
  const source = readFileSync('supabase/61_phase12_foc.sql', 'utf8');
  const checkAnchor = "elsif v_kind = 'therapy' then\n"
    + "      if v_qty <> 1 then raise exception 'A therapy line must have quantity 1'; end if;";
  const insertAnchor = "elsif v_kind = 'therapy' then\n"
    + "      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;\n"
    + "      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);";
  ok('the branches 244 anchors on still exist verbatim in the migration that defines create_invoice',
     source.split(checkAnchor).length === 2 && source.split(insertAnchor).length === 2);

  const patched = sql(`select position('therapy_service_id' in
    pg_get_functiondef('public.create_invoice(uuid,uuid,jsonb)'::regprocedure)) > 0;`);
  ok('and the patch reached the installed function', patched === 't');

  // create_invoice exists in more than one overload in production. 244 chooses
  // by content, because choosing by position patches a function nothing calls
  // and leaves the live one alone — a patch that appears to succeed and changes
  // nothing. The fixture provides an older overload with no therapy branch.
  const overloads = json(`select coalesce(jsonb_agg(jsonb_build_object(
      'sig', p.oid::regprocedure::text,
      'patched', position('therapy_service_id' in pg_get_functiondef(p.oid)) > 0)
      order by p.oid), '[]')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_invoice';`);
  ok('there is more than one create_invoice overload, as in production',
     overloads.length > 1, `${overloads.length} overload(s)`);
  ok('only the overload with a therapy branch is patched; the older one is untouched',
     overloads.filter(o => o.patched).length === 1
     && overloads.find(o => !o.patched)?.sig.includes('numeric'),
     overloads.map(o => `${o.patched ? 'patched' : 'left'}: ${o.sig}`).join(' | '));

  const customer = sql(`insert into public.customers (full_name, phone)
    values ('TS-TEST Session Buyer', '+6598000244') returning id;`);

  // A store where Power Recharge is offered at an override price, and Foot
  // Detox is not offered at all.
  sqlAs('manager', `select public.set_therapy_service_store('${power}', '${store}', true, 99.00);`);

  const inv = sql(`select public.create_invoice('${store}', '${customer}',
    '[{"line_kind":"therapy","therapy_service_id":"${power}","quantity":2}]'::jsonb);`);
  const line = json(`select to_jsonb(ii) from public.invoice_items ii where ii.invoice_id = '${inv}';`);
  ok('a therapy line naming a service sells that many sessions at the store price',
     Number(line.quantity) === 2 && Number(line.unit_price) === 99
     && Number(line.line_total) === 198,
     `${line.quantity} x ${line.unit_price} = ${line.line_total}`);
  ok('the line carries the service, not a package — the discriminator 242 relies on',
     line.therapy_service_id === power && line.therapy_package_id === null);
  ok('and snapshots the service name and duration as they were',
     line.therapy_service_name_snapshot === 'Power Recharge'
     && line.therapy_service_minutes_snapshot === 30,
     `${line.therapy_service_name_snapshot}, ${line.therapy_service_minutes_snapshot} min`);

  const notOffered = fails(`select public.create_invoice('${store}', '${customer}',
    '[{"line_kind":"therapy","therapy_service_id":"${detox}","quantity":1}]'::jsonb);`);
  ok('a service not offered at the store cannot be sold there',
     /is not offered at this store/.test(notOffered ?? ''));

  // The package path must be untouched by all of this.
  const pkg = sql(`insert into public.unlimited_therapy_packages (name, duration_months)
    values ('TS-TEST Unlimited 6', 6) returning id;`);
  const pkgInv = sql(`select public.create_invoice('${store}', '${customer}',
    '[{"line_kind":"therapy","therapy_package_id":"${pkg}","quantity":1}]'::jsonb);`);
  const pkgLine = json(`select to_jsonb(ii) from public.invoice_items ii where ii.invoice_id = '${pkgInv}';`);
  ok('an unlimited-therapy line still behaves exactly as before',
     pkgLine.therapy_package_id === pkg && pkgLine.therapy_service_id === null
     && Number(pkgLine.unit_price) === 1200 && pkgLine.plan_months_snapshot === 6,
     `${pkgLine.unit_price}, ${pkgLine.plan_months_snapshot} months`);

  const qtyRule = fails(`select public.create_invoice('${store}', '${customer}',
    '[{"line_kind":"therapy","therapy_package_id":"${pkg}","quantity":2}]'::jsonb);`);
  ok('including its rule that a package line has quantity 1',
     /must have quantity 1/.test(qtyRule ?? ''));

  // Nothing is held until the invoice is paid.
  const before = sql(`select count(*) from public.customer_therapy_sessions
                       where invoice_id = '${inv}';`);
  ok('an unpaid invoice hands the customer nothing', before === '0');

  sql(`update public.invoices set status = 'paid', paid_at = now() where id = '${inv}';`);
  const held = json(`select coalesce(jsonb_agg(to_jsonb(s)), '[]') from
    public.customer_therapy_sessions s where s.invoice_id = '${inv}';`);
  ok('paying it records the purchased sessions once',
     held.length === 1 && held[0].quantity_purchased === 2 && held[0].quantity_used === 0
     && held[0].status === 'available',
     `${held.length} row(s)`);
  ok('with the price and duration as sold, not as the catalogue reads today',
     Number(held[0].unit_price_snapshot) === 99 && held[0].service_minutes_snapshot === 30);

  // Re-running fulfilment must not double the customer's holdings.
  sql(`select public.create_therapy_sessions_for_invoice('${inv}');`);
  sql(`update public.invoices set status = 'unpaid' where id = '${inv}';`);
  sql(`update public.invoices set status = 'paid' where id = '${inv}';`);
  ok('and paying twice does not hand them a second set',
     sql(`select count(*) from public.customer_therapy_sessions where invoice_id = '${inv}';`) === '1');

  const balance = json(`select coalesce(jsonb_agg(to_jsonb(b)), '[]') from
    public.customer_therapy_session_balance('${customer}') b;`);
  ok('the balance reads two remaining sessions of Power Recharge',
     balance.length === 1 && balance[0].remaining === 2 && balance[0].purchased === 2
     && balance[0].service_name === 'Power Recharge',
     JSON.stringify(balance.map(b => `${b.service_name} ${b.remaining}`)));

  // Cancelling takes back what was never used.
  sql(`update public.invoices set status = 'cancelled' where id = '${inv}';`);
  const afterCancel = sql(`select status from public.customer_therapy_sessions where invoice_id = '${inv}';`);
  ok('cancelling the invoice takes back the unused sessions', afterCancel === 'cancelled');
  ok('and they stop counting towards the balance',
     sql(`select count(*) from public.customer_therapy_session_balance('${customer}');`) === '0');

  // A therapy line cannot be both things at once.
  const bothKinds = fails(`insert into public.invoice_items
    (invoice_id, line_kind, therapy_package_id, therapy_service_id, quantity, unit_price, line_total)
    values ('${inv}', 'therapy', '${pkg}', '${power}', 1, 10, 10);`);
  ok('a therapy line cannot name a package and a service at once',
     /invoice_item_therapy_is_one_kind/.test(bothKinds ?? ''));
}

// =====================================================================
// 8. One customer, three kinds of right (sections 12 and 13)
// =====================================================================
{
  const customer = sql(`insert into public.customers (full_name, phone)
    values ('TS-TEST Mixed Holder', '+6598000245') returning id;`);

  // (a) purchased sessions of Power Recharge
  sqlAs('manager', `select public.set_therapy_service_store('${power}', '${store}', true, 99.00);`);
  const inv = sql(`select public.create_invoice('${store}', '${customer}',
    '[{"line_kind":"therapy","therapy_service_id":"${power}","quantity":3}]'::jsonb);`);
  sql(`update public.invoices set status = 'paid', paid_at = now() where id = '${inv}';`);

  // (b) a voucher giving a CHOICE of either service
  const flexible = voucher('Flexible Two');
  define(flexible, [{ kind: 'choice', service_ids: [power, detox], quantity: 2 }]);
  sql(`insert into public.customer_reward_vouchers (customer_id, voucher_id, store_id, quantity)
       values ('${customer}', '${flexible}', '${store}', 1);`);

  // (c) a voucher giving one FIXED Foot Detox
  const fixed = voucher('Fixed Detox');
  define(fixed, [{ kind: 'fixed', service_id: detox, quantity: 1 }]);
  sql(`insert into public.customer_reward_vouchers (customer_id, voucher_id, store_id, quantity)
       values ('${customer}', '${fixed}', '${store}', 1);`);

  // (d) a voucher nobody ever described
  const undescribed = voucher('Never Described');
  sql(`insert into public.customer_reward_vouchers (customer_id, voucher_id, store_id, quantity)
       values ('${customer}', '${undescribed}', '${store}', 1);`);

  // (e) an unlimited period
  const pkg = sql(`insert into public.unlimited_therapy_packages (name, duration_months)
    values ('TS-TEST Unlimited 12', 12) returning id;`);
  // entitlement_no is required by the shape a sibling suite created; the value
  // is arbitrary here and only has to be unique.
  sql(`insert into public.purchased_therapy_entitlements
    (entitlement_no, customer_id, package_id, package_name, duration_months,
     status, activation_date, expiry_date)
    values ('TS-TEST-' || substr(gen_random_uuid()::text, 1, 8),
            '${customer}', '${pkg}', 'TS-TEST Unlimited 12', 12,
            'active', current_date - 10, current_date + 100);`);

  const ent = json(`select coalesce(jsonb_agg(to_jsonb(e)), '[]') from
    public.therapy_customer_entitlements('${customer}') e;`);
  const byKind = k => ent.filter(e => e.source_kind === k);

  ok('all three kinds of right are reported side by side',
     byKind('unlimited').length === 1 && byKind('sessions').length === 1
     && byKind('voucher').length === 3,
     ent.map(e => `${e.source_kind}:${e.title}`).join(' | '));

  const unlimited = byKind('unlimited')[0];
  ok('an unlimited period reports no count, because "how many" is the wrong question',
     unlimited.remaining === null && unlimited.eligibility === 'any_service'
     && unlimited.unit === 'period');
  ok('and counts its days inclusively, matching the therapy expiry convention',
     unlimited.days_remaining === 101, `${unlimited.days_remaining} days`);

  const purchased = byKind('sessions')[0];
  ok('purchased sessions are counted and tied to the one service they bought',
     purchased.remaining === 3 && purchased.eligibility === 'fixed'
     && purchased.service_names.join() === 'Power Recharge',
     `${purchased.remaining} x ${purchased.service_names}`);

  const flex = ent.find(e => e.title === 'TS-TEST Flexible Two');
  ok('a voucher offering two services is reported as a choice, not as a fixed right',
     flex.eligibility === 'choice' && flex.remaining === 2
     && flex.service_names.sort().join(', ') === 'Foot Detox, Power Recharge',
     `${flex.eligibility}: ${flex.service_names}`);

  const fix = ent.find(e => e.title === 'TS-TEST Fixed Detox');
  ok('and one offering a single service is reported as fixed',
     fix.eligibility === 'fixed' && fix.service_names.join() === 'Foot Detox',
     fix.eligibility);

  const unknown = ent.find(e => e.title === 'TS-TEST Never Described');
  ok('an undescribed voucher is neither counted nor guessed at',
     unknown.eligibility === 'unrecorded' && unknown.is_usable === false
     && /no recorded therapy-service rights/i.test(unknown.blocked_reason ?? ''),
     unknown.blocked_reason);

  const summary = json(`select public.therapy_customer_service_summary('${customer}');`);
  ok('the summary separates purchased sessions from voucher sessions',
     Number(summary.purchased_sessions) === 3 && Number(summary.voucher_sessions) === 3,
     `${summary.purchased_sessions} purchased, ${summary.voucher_sessions} on vouchers`);
  ok('and holds the unrecorded voucher out of the totals rather than adding it in',
     Number(summary.vouchers_needing_review) === 1
     && Number(summary.voucher_sessions) === 3);
  ok('while saying plainly that an unlimited period is running',
     summary.has_unlimited === true && summary.unlimited_expires !== null);

  const overview = json(`select public.therapy_customer_overview('${customer}');`);
  ok('the overview adds to 222\'s detail without replacing what it returns',
     overview.customer?.id === customer && overview.vouchers !== undefined
     && overview.unlimited !== undefined && overview.services !== undefined);

  // --- the permission half -------------------------------------------------
  const otherStore = sql(`insert into public.stores (name) values ('TS-TEST Other Store') returning id;`);

  const visible = sqlAs('manager', `select count(*) from public.therapy_calendar_services('${store}');`);
  ok('a calendar read lists the services offered at a store', visible === '1', visible);

  storeAccess = otherStore;
  const denied = sqlAs('manager', `select count(*) from public.therapy_calendar_services('${store}');`);
  ok('and returns nothing for a store the caller has no access to', denied === '0', denied);

  const refused = fails(`select public.therapy_booking_options('${customer}', '${power}', '${store}');`,
    s => sqlAs('manager', s));
  ok('the booking read REFUSES rather than returning an empty list',
     /do not have access to this store/i.test(refused ?? ''));
  storeAccess = 'all';

  // What can pay for a Power Recharge here: the unlimited period, the purchased
  // sessions, and the flexible voucher — but not the Foot-Detox-only voucher.
  const options = JSON.parse(sqlAs('manager',
    `select public.therapy_booking_options('${customer}', '${power}', '${store}');`));
  const kinds = options.entitlements.map(e => e.title).sort();
  ok('a booking read offers every right that covers this service',
     options.available === true && options.entitlements.length === 3
     && !kinds.includes('TS-TEST Fixed Detox'),
     kinds.join(' | '));
  ok('and a Foot-Detox-only voucher is not offered against Power Recharge',
     options.entitlements.every(e => e.title !== 'TS-TEST Fixed Detox'));

  // Frequency and entitlement are answered separately, on purpose.
  const soon = JSON.parse(sqlAs('manager',
    `select public.therapy_booking_options('${customer}', '${power}', '${store}',
       '2026-03-04T06:00:00Z'::timestamptz, array['2026-03-04T02:00:00Z'::timestamptz]);`));
  ok('holding an entitlement and being allowed one today are reported separately',
     soon.entitlements.length === 3 && soon.frequency.allowed === false
     && soon.payable_without_charge === false
     && /every 5 hours/.test(soon.reason ?? ''),
     soon.reason);

  const noRight = JSON.parse(sqlAs('manager', `select public.therapy_booking_options(
    (select id from public.customers where full_name = 'TS-TEST Session Buyer'),
    '${power}', '${store}');`));
  ok('a customer holding nothing is told it would be a paid session',
     noRight.entitlements.length === 0 && noRight.payable_without_charge === false
     && /paid session/.test(noRight.reason ?? ''), noRight.reason);
}

console.log(`\n${pass} checks passed.`);
