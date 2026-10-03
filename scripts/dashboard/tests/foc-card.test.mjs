/**
 * The Dashboard's FOC card reads what the FOC report returns.
 *
 * The card listed its top stores and reasons from report_foc_lines, but read
 * l.store_name, l.foc_amount and l.reason_label. The report returns store_id,
 * foc_value and foc_reason, so every line went under one store called
 * "undefined" worth S$0.00. It also read every FOC line ever given under a
 * heading that says 30 days, and listed the first two stores and reasons it
 * met, not the biggest. The total, the stores and the reasons now come from
 * the same 30 days of rows. Every name below is invented.
 *
 * Run: node --test scripts/dashboard/tests/foc-card.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { focSnapshot, focWindowStart, focReasonLabel, FOC_SNAPSHOT_DAYS } from '../../../src/lib/dashboard/focSnapshot.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

// The columns report_foc_lines returns (its RETURNS TABLE, 61; later
// migrations patch only its body).
const ddl = read('supabase/61_phase12_foc.sql');
const at = ddl.indexOf('create or replace function public.report_foc_lines(');
assert.ok(at > 0, 'report_foc_lines not found in 61');
const returned = ddl.slice(ddl.indexOf('returns table (', at) + 'returns table ('.length, ddl.indexOf(')', ddl.indexOf('returns table (', at)))
  .split(',').map(c => c.trim().split(/\s+/)[0]).filter(Boolean);

// A row exactly as the report returns it.
const row = (store_id, foc_value, foc_reason) =>
  ({ ...Object.fromEntries(returned.map(c => [c, null])), store_id, foc_value, foc_reason });

const STORES = new Map([['s-van', 'Test Van'], ['s-shop', 'Test Shop'], ['s-pop', 'Test Pop-up']]);

test('the fields the card reads are ones the report returns', () => {
  for (const c of ['store_id', 'foc_value', 'foc_reason']) assert.ok(returned.includes(c), `report_foc_lines does not return ${c}`);
  for (const c of ['store_name', 'foc_amount', 'reason_label']) assert.ok(!returned.includes(c), `fixture assumption: ${c} is not returned`);
});

test('the total and the store lines add up the value given, by store name', () => {
  const s = focSnapshot([
    row('s-van', '327.00', 'Promotional Gift — Lucky Draw'),
    row('s-shop', '99.50', 'Staff Welfare — Staff'),
    row('s-van', '594.00', 'Promotional Gift'),
    row('s-pop', '40.00', 'Promotional Gift — Buy 2 get 1 free'),
    row('s-shop', '0.10', 'Other — test'),
    row('s-shop', '0.20', 'Other — test'),
  ], STORES);
  assert.equal(s.total, 1060.8);
  assert.equal(s.lineCount, 6);
  assert.deepEqual(s.stores, [{ name: 'Test Van', value: 921 }, { name: 'Test Shop', value: 99.8 }],
    'the two biggest stores, by value, not the first two met');
  assert.deepEqual(s.reasons, [{ label: 'Promotional Gift', count: 3 }, { label: 'Other', count: 2 }],
    'reasons are counted by their label, without the note, most used first');
});

test('no store is called "undefined" and no value is lost', () => {
  const s = focSnapshot([row('s-gone', 12.34, null)], STORES);
  assert.deepEqual(s.stores, [{ name: 'Other store', value: 12.34 }]);
  assert.deepEqual(s.reasons, [{ label: 'No reason', count: 1 }]);
  assert.equal(focSnapshot([], STORES).total, 0);
  assert.equal(focSnapshot(null, null).lineCount, 0);
});

test('a free-text reason is its own label; a label keeps its note out', () => {
  assert.equal(focReasonLabel('72-dollar discount'), '72-dollar discount');
  assert.equal(focReasonLabel('Management Approval — Teacher Approved'), 'Management Approval');
  assert.equal(focReasonLabel('  FOC  '), 'FOC');
});

test('the window is 30 days, today included, across a month and a year', () => {
  assert.equal(FOC_SNAPSHOT_DAYS, 30);
  assert.equal(focWindowStart('2026-10-03'), '2026-09-04');
  assert.equal(focWindowStart('2026-03-01'), '2026-01-31');
  assert.equal(focWindowStart('2027-01-15', 30), '2026-12-17');
  assert.equal(focWindowStart('not a date'), null);
});

test('the Dashboard asks for the last 30 days and shows the snapshot', () => {
  const page = read('src/pages/DashboardPage.tsx');
  assert.match(page, /rpc\('report_foc_lines', \{ p_from: focWindowStart\(focToday\), p_to: focToday, p_store_id: null \}\)/,
    'the FOC card must read the 30 days its heading names');
  assert.match(page, /setFoc\(focSnapshot\(/);
  const card = page.slice(page.indexOf('FOC value (30 days)'), page.indexOf('FOC value (30 days)') + 900);
  assert.match(card, /foc\?\.total/, 'the headline is the total of the rows listed under it');
  for (const f of ['store_name', 'foc_amount', 'reason_label']) assert.ok(!card.includes(f), `the card still reads ${f}`);
});
