// The Vouchers page after 548 (the Owner, 27 Nov 2026: "The 4 voucher for class should go to the class
// page"): the vouchers marked as classes (class_vouchers, keyed by voucher, not by name) are not listed;
// every other voucher is, as before. Before 548 is in there is no class table: the read finds nothing and
// every voucher is listed, so the page can ship first. The real page against a fake backend; every name
// is made up.
//
// Run: node --test scripts/classes/tests/vouchers-page-without-classes.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/vouchers');
dom.window.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
const mod = await bundle(`
  import React from 'react';
  export { default as VouchersPage } from './src/pages/VouchersPage';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { React, VouchersPage } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });
const h = React.createElement;

const V = (id, name, code, price, over = {}) => ({ id, name, code, voucher_kind: 'normal', discount_amount: null, discount_percent: null, max_discount_cap: null,
  qty_type: 'unlimited', selling_price: price, valid_from: null, valid_until: null, is_active: true, description: null, terms: null, deleted_at: null,
  created_at: '2026-11-01T00:00:00Z', reward_eligible: true, discount_category: null, birthday_rule: null, ...over });
const VOUCHERS = [
  V('v-found', 'Lymphatic Foundation Workshop 2027', 'EmiLymphatic', 799), V('v-adv', 'Lymphatic Advanced Workshop 2027', 'AdvancedZoom', 1441),
  V('v-skin', 'Korea No.1 Skin Care Workshop', 'KPopClass', 676), V('v-lc', 'Lymphatic Class', 'L-C', 399),
  V('v-plain', 'Fixture Sleep Voucher', 'SLEEP1', 72), V('v-disc', 'Fixture 10 Off', 'TEN', 0, { voucher_kind: 'fixed_discount', discount_amount: 10, discount_category: 'voucher' }),
];
async function open({ classes, fail } = {}) {
  const sb = fakeSupabase({
    tables: { vouchers: structuredClone(VOUCHERS), stores: [], voucher_store_stock: [], class_vouchers: classes ?? [] },
    rpc: {}, fail: fail ?? {},
  });
  globalThis.__supabase = sb;
  globalThis.__auth = { profile: { id: 'u-1', full_name: 'Olive Test', role: 'owner' }, session: { user: { id: 'u-1' } }, assignments: [], loading: false };
  await d.mount(h(VouchersPage));
  for (let i = 0; i < 30 && !document.querySelector('tbody tr'); i++) await d.tick(2);
  return sb;
}
const names = () => [...document.querySelectorAll('tbody tr td:first-child strong')].map(s => s.textContent).sort();
const CLASS_ROWS = ['v-found', 'v-adv', 'v-skin', 'v-lc'].map(voucher_id => ({ voucher_id }));

test('the four class vouchers are not on the Vouchers page; the others are', async () => {
  const sb = await open({ classes: CLASS_ROWS });
  assert.deepEqual(names(), ['Fixture 10 Off', 'Fixture Sleep Voucher']);
  assert.ok(sb.calls.some(c => c.table === 'class_vouchers'), 'it reads the class table, not names');
});

test('a class is told by its voucher id, not its name: a voucher named like a class stays, a renamed class stays off', async () => {
  const sb = fakeSupabase({
    tables: { vouchers: [V('v-x', 'Lymphatic Class', 'COPY', 5), V('v-found', 'Anything at all', 'EmiLymphatic', 799)], stores: [], voucher_store_stock: [], class_vouchers: [{ voucher_id: 'v-found' }] },
  });
  globalThis.__supabase = sb;
  await d.mount(h(VouchersPage));
  for (let i = 0; i < 30 && !document.querySelector('tbody tr'); i++) await d.tick(2);
  assert.deepEqual(names(), ['Lymphatic Class']);
});

test('before 548 (no class rows): every voucher is listed as before', async () => {
  await open({ classes: [] });
  assert.equal(names().length, 6);
});

test('before 548 (the class table cannot be read): every voucher is listed as before', async () => {
  await open({ fail: { class_vouchers: 'relation "public.class_vouchers" does not exist' } });
  assert.equal(names().length, 6);
});
