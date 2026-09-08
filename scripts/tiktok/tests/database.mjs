// Migration 210 against the isolated local database, and — the point of this
// file — agreement between the SQL and the JavaScript.
//
//   scripts/auth-email/bootstrap-local.sh start
//   npm run test:tiktok:db
//
// Two implementations of the same period rule is a liability unless something
// checks they agree; the import page reads one and the report reads the other.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { settlementPeriod, toIsoDate, settledDateSgt, isInPeriod }
  from '../../../src/lib/tiktok/settlementPeriod.mjs';
import { summarise, formatCents, classifyTransaction }
  from '../../../src/lib/tiktok/classification.mjs';

process.env.PGHOST ??= '/tmp'; process.env.PGPORT ??= '55442';
process.env.PGUSER ??= 'postgres'; process.env.PGDATABASE ??= 'energia_auth_email_test';
if (process.env.PGDATABASE !== 'energia_auth_email_test' || process.env.PGPORT !== '55442') {
  throw new Error('Refusing to run outside the disposable database on port 55442.');
}
const args = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'];
const sql = s => execFileSync('psql', [...args, '-c', s], { encoding: 'utf8' }).trim();
// Each psql invocation is its own session, so a set_config in one call is gone by
// the next. Anything depending on session state has to travel with its query.
const sqlAs = (role, access, s) =>
  execFileSync('psql', [...args,
    '-c', `select set_config('test.role', '${role}', false), set_config('test.store_access', '${access}', false);`,
    '-c', s], { encoding: 'utf8' }).trim().split('\n').filter(Boolean).pop();
const json = s => JSON.parse(sql(s));
let pass = 0;
const ok = (label, cond, detail = '') => {
  console.log(`${cond ? 'PASS' : 'FAIL'}: ${label}${detail ? ` — ${detail}` : ''}`);
  if (!cond) process.exitCode = 1; else pass++;
};

const apply = f => execFileSync('psql', [...args, '-f', f], { encoding: 'utf8' });
const outParams = fn =>
  sql(`select coalesce(pg_get_function_result(oid), '') from pg_proc
        where proname = '${fn}' and pronamespace = 'public'::regnamespace;`);

// Put the database into the state migration 210 actually finds: the report
// functions as migrations 66 and 67 left them. Without this the create-or-
// replaces have nothing to replace, every run is clean, and the test says
// nothing about the database the migration is going to meet.
apply('scripts/tiktok/tests/prior-state.sql');
const before = outParams('report_tiktok_settlement');
ok('the prior state really is the old row type — no finance_category',
   before !== '' && !before.includes('finance_category'), before.slice(0, 60));

// The failure this reproduces: 42P13, cannot change return type of existing
// function. It is only caught by applying 210 on top of the line above.
apply('supabase/210_tiktok_settlement_periods.sql');
apply('supabase/210_tiktok_settlement_periods.sql');
ok('migration 210 applies over the pre-210 functions, and applies again, cleanly', true);
ok('the report row type was actually replaced, not silently left alone',
   outParams('report_tiktok_settlement').includes('finance_category'));
ok('the 4-argument daily report with its basis toggle is gone',
   sql(`select count(*) from pg_proc where proname = 'report_tiktok_settlement_daily'
         and pronamespace = 'public'::regnamespace
         and pg_get_function_identity_arguments(oid) like '%text%';`) === '0');

// --- the period rule agrees with the JS, month by month, for seven years -----
{
  let mismatches = [];
  for (let y = 2024; y <= 2030; y++) {
    for (let m = 1; m <= 12; m++) {
      const row = sql(`select start_date || '..' || end_date from public.tiktok_settlement_period(${y}, ${m});`);
      const js = `${toIsoDate(settlementPeriod(y, m).start)}..${toIsoDate(settlementPeriod(y, m).end)}`;
      if (row !== js) mismatches.push(`${y}-${m}: sql=${row} js=${js}`);
    }
  }
  ok('SQL and JS agree on all 84 periods, 2024-2030', mismatches.length === 0, mismatches.slice(0, 3).join('; '));
}

// --- the documented examples ------------------------------------------------
ok('August 2026 is 30 Jul - 26 Aug',
   sql("select start_date || '..' || end_date from public.tiktok_settlement_period(2026, 8);") === '2026-07-30..2026-08-26');
ok('October 2026 starts on the 1st (September ended on a Wednesday)',
   sql("select start_date from public.tiktok_settlement_period(2026, 10);") === '2026-10-01');

// --- the Singapore day boundary --------------------------------------------
{
  const r = sql("select start_at || '|' || end_at_exclusive from public.tiktok_settlement_period_range(2026, 8);");
  ok('the instant range is the SGT day boundary, half-open',
     r.startsWith('2026-07-30 00:00:00+08') && r.includes('2026-08-27 00:00:00+08'), r);
}

// --- classification agrees with the JS --------------------------------------
{
  const cases = [
    ['GMV payment for TikTok Ads', -283.30], ['GMV payment for TikTok Ads', 50],
    ['Affiliate Shop Ads commission', -5], ['Affiliate commission refund', 5],
    ['Withdrawal', -500], ['Transfer to bank', -100], ['Reserve release', 20],
    ['Order', 0], ['Return refund', -10], ['Transaction fee', -2],
    ['Mystery adjustment 47', -99], ['', 0],
  ];
  const bad = [];
  for (const [t, adj] of cases) {
    const s = sql(`select public.tiktok_finance_category('${t.replace(/'/g, "''")}', ${adj});`);
    const j = classifyTransaction(t, { adjustmentCents: Math.round(adj * 100) });
    if (s !== j) bad.push(`"${t}" sql=${s} js=${j}`);
  }
  ok('SQL and JS classify identically', bad.length === 0, bad.join('; '));
}

// --- load the sanitized fixture and compare totals --------------------------
const fx = JSON.parse(readFileSync(new URL('./fixtures/settlement-sample.json', import.meta.url)));
// A real store row, not a bare uuid: the settlement rows carry a foreign key to
// it and report_tiktok_settlement joins it for the store name.
sql('delete from public.tiktok_settlement_rows;');
sql("delete from public.stores where name = 'Test Store';");
const store = sql("insert into public.stores (name) values ('Test Store') returning id;");
const esc = v => (v === null || v === undefined || v === '') ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
const num = v => { const n = Number(String(v ?? '0').replace(/,/g, '')); return Number.isFinite(n) ? n : 0; };
const values = fx.rows.map((r, i) => {
  const d = settledDateSgt(r.orderSettledTime);
  return `('${store}', ${i + 1}, ${esc(r.orderId)}, ${num(r.totalSettlementAmount)}, ${num(r.totalFees)}, `
       + `${num(r.totalRevenue)}, ${num(r.adjustmentAmount)}, ${esc(r.currency)}, `
       + `${d ? `timestamptz '${d} 12:00:00+08'` : 'null'}, ${esc(r.transactionType)}, 'pending', false, true, true)`;
}).join(',\n');
sql(`insert into public.tiktok_settlement_rows
  (store_id, row_no, order_id, settlement_amount, fee_amount, revenue_amount, adjustment_amount,
   currency, settled_time, transaction_type, match_status, excluded, confirmed, is_current)
  values ${values};`);
ok('44 sanitized rows loaded', sql('select count(*) from public.tiktok_settlement_rows;') === '44');

const check = (label, y, m, want) => {
  const t = json(`select public.tiktok_settlement_totals(${y}, ${m}, '${store}');`);
  const got = [t.row_count, t.revenue.toFixed(2), t.fee.toFixed(2), t.settlement.toFixed(2),
               t.expense.toFixed(2), t.income.toFixed(2)];
  ok(label, got.join('|') === want.join('|'), got.join(' / '));
  return t;
};
check('August 2026 totals from SQL', 2026, 8, [30, '2770.17', '596.73', '2173.44', '565.35', '1608.09']);
check('September 2026 totals from SQL', 2026, 9, [14, '1979.51', '317.63', '1661.88', '886.91', '774.97']);

// --- SQL totals equal JS totals, row for row --------------------------------
{
  const rows = fx.rows.map(r => ({ ...r, settled: settledDateSgt(r.orderSettledTime) }));
  let bad = [];
  for (const [y, m] of [[2026, 8], [2026, 9]]) {
    const s = json(`select public.tiktok_settlement_totals(${y}, ${m}, '${store}');`);
    const j = summarise(rows.filter(r => isInPeriod(r.settled, y, m)));
    for (const [k, sv, jv] of [
      ['revenue', s.revenue, j.revenue], ['fee', s.fee, j.fee],
      ['settlement', s.settlement, j.settlement], ['expense', s.expense, j.expense],
      ['income', s.income, j.income], ['tiktok_net', s.tiktok_net_settlement, j.tiktokNetSettlement],
    ]) if (sv.toFixed(2) !== formatCents(jv)) bad.push(`${y}-${m} ${k}: sql=${sv} js=${formatCents(jv)}`);
  }
  ok('every SQL figure equals its JS counterpart', bad.length === 0, bad.join('; '));
}

// --- what counts and what does not ------------------------------------------
{
  const before = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('a pending order match still contributes', before.pending_match_count === 30 && before.row_count === 30);
  // Must be a row inside the August period: the fixture is in file order and
  // begins in September, so row_no 1 would prove nothing.
  const augRow = sql(`select row_no from public.tiktok_settlement_rows
                       where (settled_time at time zone 'Asia/Singapore')::date
                             between '2026-07-30' and '2026-08-26' order by row_no limit 1;`);

  sql(`update public.tiktok_settlement_rows set excluded = true where row_no = ${augRow};`);
  const ex = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('an excluded row stops contributing', ex.row_count === before.row_count - 1);
  sql(`update public.tiktok_settlement_rows set excluded = false where row_no = ${augRow};`);

  sql(`update public.tiktok_settlement_rows set confirmed = false where row_no = ${augRow};`);
  const un = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('an unconfirmed row does not inflate confirmed totals', un.row_count === before.row_count - 1);
  sql(`update public.tiktok_settlement_rows set confirmed = true where row_no = ${augRow};`);

  sql(`update public.tiktok_settlement_rows set is_current = false where row_no = ${augRow};`);
  const sup = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('a superseded version does not contribute', sup.row_count === before.row_count - 1);
  sql(`update public.tiktok_settlement_rows set is_current = true where row_no = ${augRow};`);
}

// --- undated rows are surfaced, not hidden ----------------------------------
{
  sql(`insert into public.tiktok_settlement_rows
       (store_id, row_no, order_id, settlement_amount, fee_amount, revenue_amount, adjustment_amount,
        currency, settled_time, transaction_type, match_status, excluded, confirmed, is_current)
       values ('${store}', 900, '9999999999999999999', 10, 0, 10, 0, 'SGD', null, 'Order', 'pending', false, true, true);`);
  const t = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('a row with no settled date is counted as needing review', t.undated_count === 1 && t.needs_review === true);
  ok('and it is not silently assigned to a month', t.row_count === 30);
  sql(`delete from public.tiktok_settlement_rows where row_no = 900;`);
}

// --- unknown types block a "reconciled" claim -------------------------------
{
  sql(`insert into public.tiktok_settlement_rows
       (store_id, row_no, order_id, settlement_amount, fee_amount, revenue_amount, adjustment_amount,
        currency, settled_time, transaction_type, match_status, excluded, confirmed, is_current)
       values ('${store}', 901, '8888888888888888888', -42, 0, 0, -42, 'SGD',
               timestamptz '2026-08-05 12:00:00+08', 'Mystery adjustment 47', 'pending', false, true, true);`);
  const t = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('an unknown type contributes nothing to expense', t.expense.toFixed(2) === '565.35');
  ok('but it is flagged and blocks a reconciled claim', t.unknown_count === 1 && t.needs_review === true);
  sql(`delete from public.tiktok_settlement_rows where row_no = 901;`);
}

// --- balance movements are excluded from the figures ------------------------
{
  sql(`insert into public.tiktok_settlement_rows
       (store_id, row_no, order_id, settlement_amount, fee_amount, revenue_amount, adjustment_amount,
        currency, settled_time, transaction_type, match_status, excluded, confirmed, is_current)
       values ('${store}', 902, '7777777777777777777', -61.97, 0, 0, -61.97, 'SGD',
               timestamptz '2026-08-05 12:00:00+08', 'Withdrawal', 'no_match_needed', false, true, true);`);
  const t = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('a withdrawal does not become an expense', t.expense.toFixed(2) === '565.35');
  ok('and it does not touch revenue or income',
     t.revenue.toFixed(2) === '2770.17' && t.income.toFixed(2) === '1608.09');
  ok('but it is visible as a balance movement', t.balance_movement_count === 1);
  sql(`delete from public.tiktok_settlement_rows where row_no = 902;`);
}

// --- both repeated-ID rows survive ------------------------------------------
{
  const counts = new Map();
  for (const r of fx.rows) counts.set(r.orderId, (counts.get(r.orderId) ?? 0) + 1);
  const [dupId] = [...counts].find(([, n]) => n > 1);
  const n = sql(`select count(*) from public.tiktok_settlement_rows where order_id = '${dupId}';`);
  const s = sql(`select round(sum(revenue_amount), 2) from public.tiktok_settlement_rows where order_id = '${dupId}';`);
  ok('both rows sharing one Order ID are stored and counted', n === '2' && s === '451.58', `${n} rows, ${s}`);
}

// --- daily breakdown ties to the period total -------------------------------
{
  const d = sql(`select round(sum(revenue), 2) || '|' || round(sum(expense), 2)
                   from public.tiktok_settlement_daily(2026, 8, '${store}');`);
  ok('the daily breakdown sums to the period totals', d === '2770.17|565.35', d);
}

// --- store permissions -------------------------------------------------------
{
  // Access is granted per store, so "no access" is modelled as access to a
  // DIFFERENT store rather than access to nothing. A blanket off switch would
  // pass even if the function ignored which store it was asked about.
  sql("delete from public.stores where name = 'Other Store';");
  const other = sql("insert into public.stores (name) values ('Other Store') returning id;");

  const denied = JSON.parse(sqlAs('staff', other,
    `select public.tiktok_settlement_totals(2026, 8, '${store}');`));
  ok('a staff member assigned elsewhere sees nothing', denied.row_count === 0, `row_count=${denied.row_count}`);

  const allowed = JSON.parse(sqlAs('staff', store,
    `select public.tiktok_settlement_totals(2026, 8, '${store}');`));
  ok('a staff member assigned to the store sees it', allowed.row_count === 30, `row_count=${allowed.row_count}`);

  const owner = JSON.parse(sqlAs('owner', other,
    `select public.tiktok_settlement_totals(2026, 8, '${store}');`));
  ok('an owner sees every store without needing an assignment', owner.row_count === 30);

  const leak = sqlAs('staff', other, `select count(*) from public.tiktok_settlement_eligible(null);`);
  ok('the report function cannot expose an unauthorized store', leak === '0', `rows=${leak}`);
}

// --- aggregation is over the whole set, not a page --------------------------
{
  const total = json(`select public.tiktok_settlement_totals(2026, 8, '${store}');`);
  ok('aggregation covers every eligible row, not a capped page',
     total.row_count === 30 && Number(sql(`select count(*) from public.tiktok_settlement_eligible('${store}');`)) === 44);
}

// --- the diagnostic ----------------------------------------------------------
{
  const d = json(`select public.tiktok_settlement_diagnostic('${store}');`);
  ok('the diagnostic reports advertising reclassified to expense', d.ads_reclassified_to_expense === 20);
  ok('the diagnostic reports no missing settled dates in this sample', d.missing_settled_date === 0);
  ok('the diagnostic reports a single currency', JSON.stringify(d.currencies) === '["SGD"]');
}

// --- settlement processing moves no stock ------------------------------------
{
  const touchesStock = sql(`select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname='public' and p.proname like 'tiktok_settlement%'
       and pg_get_functiondef(p.oid) ~* '(stock_movements|store_inventory|warehouse_inventory|adjust_product_stock|adjust_voucher_stock)';`);
  ok('no settlement function touches inventory', touchesStock === '0');
}

console.log(`\n${pass} checks passed.`);
