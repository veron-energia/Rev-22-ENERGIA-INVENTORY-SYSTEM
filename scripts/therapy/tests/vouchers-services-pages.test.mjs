// The pages 423 changes, rendered for real against a fake backend.
//
// The actual components are bundled with esbuild and mounted in jsdom. Only
// the Supabase client, the auth context and xlsx are stubbed: the client
// records every call and answers from the fixture below. Every name and
// number here is invented.
//
// What it checks (THERAPY-14, -18, -13, -17, -21, STOCK-13, and the parts of
// THERAPY-7 and -16):
//   * Vouchers: editing leaves the store prices alone unless "Use this price
//     at every store" is ticked, and then keeps each store's on-sale tick; a
//     voucher is red only after its last valid day in Singapore; Delete goes
//     through soft_delete_voucher, says what still depends on the voucher and
//     needs a reason, and shows a refusal; "Can be given as a reward" is
//     shown and sent for free-session vouchers only.
//   * Store prices: a negative price is refused before it is sent; closing
//     with prices typed but not saved asks first; saving one store keeps what
//     is typed for another; when the saved prices cannot be read, no row can
//     be changed until Retry reads them.
//   * Therapy Services: the store list leaves out closed stores but keeps a
//     closed store this service already has; the stores are saved in one call
//     with the error inside the window; a failed read of a service's stores
//     does not open the window; notes are read and sent back; an
//     archived service in a choice can be unticked; the visit limits are
//     described as a guide.
//   * Split panels: a failed preview shows its error with Retry; a retry of
//     "Create" sends the same request id (both panels); a lost answer says the
//     outcome is unknown, Cancel then asks, and the split opened again for the
//     same package and store sends the same id; a refusal says the invoices
//     were not created; an id that already made another sale (other
//     customers or amounts) is let go and says to check the invoices first.
//   * Benefit window: no unreachable "Confirm choice"; a switch retried after
//     an error keeps its request id.
//   * Holidays: a region field for the calendar (needed to mark a regional
//     calendar checked) and for a new date, read once typing pauses, and an
//     older answer arriving late is dropped; the recalculation asks first and
//     counts only the periods it will change.
//
// Run: node --test scripts/therapy/tests/vouchers-services-pages.test.mjs
process.env.TZ = 'America/Los_Angeles'; // west of UTC: a date parsed as a Date would show a day early

import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import {
  sgToday, isPastValidUntil, dayText, priceProblem, unsavedStoreNames, voucherDependents,
  serviceStoreRows, lengtheningCount, outcomeUnknown, splitRequestUsed,
} from '../../../src/lib/catalogue/pageRules.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://vouchers.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement',
  'Element', 'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame',
  'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.MessageChannel = class {
  constructor() {
    const port = () => ({ onmessage: null, close() {} });
    this.port1 = port(); this.port2 = port();
    this.port1.postMessage = data => setImmediate(() => this.port2.onmessage?.({ data }));
    this.port2.postMessage = data => setImmediate(() => this.port1.onmessage?.({ data }));
  }
};
const consoleError = console.error;
console.error = (...a) => { if (!String(a[0]).includes('not wrapped in act')) consoleError(...a); };

// window.confirm and window.prompt answer from a queue and remember what was asked.
const asked = [];
let answers = [];
dom.window.confirm = msg => { asked.push(msg); return answers.length ? answers.shift() : true; };
dom.window.prompt = msg => { asked.push(msg); return answers.length ? answers.shift() : null; };

const built = await build({
  stdin: {
    contents: `
      export { default as VouchersPage } from './src/pages/VouchersPage';
      export { default as TherapyServicesPage } from './src/pages/TherapyServicesPage';
      export { default as StorePriceEditor } from './src/components/StorePriceEditor';
      export { CreditPackageSplitPanel } from './src/components/CreditPackageSplitPanel';
      export { PremiumBundleSplitPanel } from './src/components/PremiumBundleSplitPanel';
      export { BenefitChoicePanel } from './src/components/therapy/BenefitChoicePanel';
      export { HolidayAdmin } from './src/components/therapy/HolidayAdmin';
      export { RecalculationPreview } from './src/components/therapy/TherapyDiagnostics';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      import React from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      function chain(table) {
        const q = { table, op: 'select', filters: [], payload: null, single: false };
        const run = () => globalThis.__sb.query(q);
        const c = {
          select() { return c; }, insert(p) { q.op = 'insert'; q.payload = p; return c; },
          update(p) { q.op = 'update'; q.payload = p; return c; },
          eq(k, v) { q.filters.push(['eq', k, v]); return c; }, is(k, v) { q.filters.push(['is', k, v]); return c; },
          in() { return c; }, gte() { return c; }, lte() { return c; }, order() { return c; }, limit() { return c; },
          or() { return c; },
          single() { q.single = true; return Promise.resolve(run()); },
          maybeSingle() { q.single = true; return Promise.resolve(run()); },
          then(res, rej) { return Promise.resolve(run()).then(res, rej); },
        };
        return c;
      }
      export const supabase = {
        from: t => chain(t),
        rpc: (fn, args) => Promise.resolve(globalThis.__sb.rpc(fn, args ?? {})),
      };
      export default supabase;` }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => ({ profile: globalThis.__profile, user: { id: "u-1" } }); export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const utils = { json_to_sheet: () => ({}), book_new: () => ({}), book_append_sheet: () => {} }; export const writeFile = () => {};' }));
  } }],
});
const { VouchersPage, TherapyServicesPage, StorePriceEditor, CreditPackageSplitPanel, PremiumBundleSplitPanel,
  BenefitChoicePanel, HolidayAdmin, RecalculationPreview, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── The fake backend ─────────────────────────────────────────────────────
let calls = [];
let tables = {};
let rpcs = {};
globalThis.__sb = {
  query(q) {
    calls.push({ kind: 'from', ...q });
    if (q.op !== 'select') {
      const id = q.filters.find(([op, k]) => op === 'eq' && k === 'id')?.[2] ?? q.payload?.id ?? 'new-id';
      return { data: { ...q.payload, id }, error: null };
    }
    let rows = tables[q.table] ?? [];
    if (rows.error) return { data: null, error: rows.error };
    for (const [op, k, v] of q.filters) rows = rows.filter(r => op === 'is' ? (r[k] ?? null) === v : r[k] === v);
    return { data: q.single ? rows[0] ?? null : rows, error: null };
  },
  rpc(fn, args) {
    calls.push({ kind: 'rpc', fn, args });
    const h = rpcs[fn];
    const out = typeof h === 'function' ? h(args) : h;
    return out ?? { data: null, error: null };
  },
};
const rpcCalls = fn => calls.filter(c => c.kind === 'rpc' && c.fn === fn);

let root = null;
const tick = async (n = 8) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(el, { profile = { role: 'owner' } } = {}) {
  if (root) await act(async () => root.unmount());
  globalThis.__profile = profile;
  calls = []; asked.length = 0; answers = [];
  document.body.innerHTML = '<div id="root"></div>';
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(el));
  await tick();
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

const $$ = (sel, from = document) => [...from.querySelectorAll(sel)];
const byText = (sel, text, from = document) => $$(sel, from).find(e => e.textContent.includes(text));
const click = async el => { assert.ok(el, 'element to click'); await act(async () => { el.click(); }); await tick(); };
const setterOf = el => Object.getOwnPropertyDescriptor(
  el instanceof dom.window.HTMLTextAreaElement ? dom.window.HTMLTextAreaElement.prototype
    : el instanceof dom.window.HTMLSelectElement ? dom.window.HTMLSelectElement.prototype
      : dom.window.HTMLInputElement.prototype, 'value').set;
async function type(el, value) {
  assert.ok(el, 'field to type in');
  await act(async () => {
    setterOf(el).call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick();
}
const checkboxLabelled = (text, from = document) => byText('label', text, from)?.querySelector('input[type=checkbox]');
const modal = () => $$('.modal').at(-1);

// ── The rules, as plain functions ───────────────────────────────────────
test('the shared rules: Singapore dates, prices, unsaved rows, what a voucher still has', () => {
  assert.equal(sgToday(new Date('2026-10-09T16:30:00Z')), '2026-10-10', 'half past midnight in Singapore is the next day');
  assert.equal(isPastValidUntil('2026-10-09', '2026-10-09'), false, 'the last valid day is still valid');
  assert.equal(isPastValidUntil('2026-10-08', '2026-10-09'), true);
  assert.equal(isPastValidUntil(null, '2026-10-09'), false);
  assert.equal(dayText('2026-10-09'), '9 Oct 2026');
  assert.equal(priceProblem(''), null);
  assert.equal(priceProblem('0'), null);
  assert.equal(priceProblem('-0.01'), 'cannot be negative');
  assert.equal(priceProblem('abc'), 'is not a number');
  const stores = [{ id: 'a', name: 'Store A' }, { id: 'b', name: 'Store B' }];
  assert.deepEqual(unsavedStoreNames(stores, { a: { m: '10', avail: true }, b: { m: '', avail: true } },
    [{ store_id: 'a', selling_price: '10.00', available_at_store: true }]), [], '10 typed is 10.00 saved; no row and blank is unchanged');
  assert.deepEqual(unsavedStoreNames(stores, { a: { m: '12', avail: true }, b: { m: '', avail: false } },
    [{ store_id: 'a', selling_price: 10, available_at_store: true }]), ['Store A', 'Store B']);
  assert.deepEqual(voucherDependents({ holders_customers: 10, holders_units: 13, store_stock: [{ store_name: 'Store A', quantity: 4 }],
    used_in: { promotions: 1, premium_bundles: 2, credit_packages: 0, therapy_packages: 0 } }),
  ['10 customers hold 13 units of it. They keep them.', 'In stock: Store A 4.', 'Offered by 1 live promotion and 2 premium bundles.']);
  assert.match(serviceStoreRows(stores, { a: { available: true, override: '-1' } }).problem, /The price at Store A cannot be negative/);
  assert.deepEqual(serviceStoreRows(stores, { a: { available: true, override: ' 60 ' } }).rows,
    [{ store_id: 'a', is_available: true, price_override: 60 }, { store_id: 'b', is_available: false, price_override: null }]);
  assert.equal(lengtheningCount([{ change_days: 3 }, { change_days: -1, shortens: true }, { change_days: null }, { change_days: 0 }]), 1);
  assert.equal(lengtheningCount([{ change_days: 1, needs_country: true }, { change_days: 2, needs_country: false }]), 1,
    'a period with no holiday country is left out by the server, so it is not counted');
  assert.equal(outcomeUnknown({ message: 'TypeError: Failed to fetch', code: '' }), true, 'no answer: postgrest-js sends code ""');
  assert.equal(outcomeUnknown({ message: '<html>504 Gateway Time-out</html>' }), true, 'a gateway page has no code');
  assert.equal(outcomeUnknown({ message: 'Not enough stock', code: 'P0001' }), false, 'the database refused it');
  assert.equal(outcomeUnknown({ message: 'JWT expired', code: 'PGRST301' }), false, 'the API refused it');
  assert.equal(outcomeUnknown(null), false);
  assert.equal(splitRequestUsed({ message: 'This request was already used for another sale. Close the split and start again.', code: 'P0001' }), true);
  assert.equal(splitRequestUsed({ message: 'Customer T is not active.', code: 'P0001' }), false);
  assert.equal(splitRequestUsed({ message: 'already used for another sale', code: '' }), false, 'no answer is not a refusal');
  assert.equal(splitRequestUsed(null), false);
});

// ── Vouchers page ───────────────────────────────────────────────────────
const yesterday = (() => { const d = new Date(`${sgToday()}T12:00:00+08:00`); d.setUTCDate(d.getUTCDate() - 1); return d.toISOString().slice(0, 10); })();
function voucherFixture() {
  tables = {
    vouchers: [
      { id: 'v1', name: 'T Free Session', code: 'TFS', voucher_kind: 'normal', qty_type: 'unlimited', selling_price: 50,
        valid_from: null, valid_until: sgToday(), is_active: true, reward_eligible: true, deleted_at: null, created_at: '2026-10-01T00:00:00Z' },
      { id: 'v2', name: 'T Old Event', code: 'TOE', voucher_kind: 'normal', qty_type: 'unlimited', selling_price: 30,
        valid_from: null, valid_until: yesterday, is_active: true, reward_eligible: false, deleted_at: null, created_at: '2026-10-01T00:00:00Z' },
      { id: 'v3', name: 'T Birthday', code: 'TBD', voucher_kind: 'percentage_discount', discount_percent: 10, qty_type: 'unlimited',
        selling_price: 0, discount_category: 'birthday', birthday_rule: 'whole_month', valid_from: null, valid_until: null,
        is_active: true, reward_eligible: true, deleted_at: null, created_at: '2026-10-01T00:00:00Z' },
    ],
    stores: [{ id: 's-a', name: 'Store A', is_active: true, deleted_at: null }, { id: 's-b', name: 'Store B', is_active: true, deleted_at: null }],
    voucher_store_stock: [],
  };
  rpcs = {};
}
const voucherRow = name => $$('tbody tr').find(tr => tr.textContent.includes(name));
const editButton = name => $$('button', voucherRow(name)).find(b => b.className.includes('btn-icon') && !b.className.includes('btn-danger'));
const saveCall = () => calls.filter(c => c.kind === 'from' && c.table === 'vouchers' && c.op !== 'select').at(-1);

test('Vouchers: an edit leaves store prices alone unless the box is ticked, and then keeps each store\'s on-sale tick', async () => {
  voucherFixture();
  await mount(React.createElement(VouchersPage));
  await click(editButton('T Free Session'));
  const box = checkboxLabelled('Use this price at every store', modal());
  assert.equal(box.checked, false, 'unticked when editing');
  assert.match(modal().textContent, /Store prices stay as they are/);
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.equal(saveCall().op, 'update');
  assert.equal(rpcCalls('set_voucher_price_all_stores').length, 0, 'no store price was touched');

  await click(editButton('T Free Session'));
  await click(checkboxLabelled('Use this price at every store', modal()));
  assert.match(modal().textContent, /A store where it is switched off stays off\. A store with no price yet starts selling it\./);
  assert.doesNotMatch(modal().textContent, /Whether each store sells it does not change/);
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.deepEqual(rpcCalls('set_voucher_price_all_stores').map(c => c.args), [{ p_voucher_id: 'v1', p_price: 50, p_available: null }]);
});

test('Vouchers: a new voucher gets the price at every store', async () => {
  voucherFixture();
  await mount(React.createElement(VouchersPage));
  await click(byText('button', 'Add Voucher'));
  assert.equal(checkboxLabelled('Use this price at every store', modal()).checked, true, 'ticked for a new voucher');
  const inputs = $$('input', modal());
  await type(inputs[0], 'T New');
  await type(inputs[1], 'TNEW');
  await type($$('input[type=number]', modal())[0], '25');
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.equal(saveCall().op, 'insert');
  assert.equal(saveCall().payload.reward_eligible, true);
  assert.equal(rpcCalls('set_voucher_price_all_stores')[0]?.args.p_available, null);
  assert.equal(rpcCalls('set_voucher_price_all_stores')[0]?.args.p_price, 25);
});

test('Vouchers: red only after the last valid day (Singapore), and dates shown without a day shift', async () => {
  voucherFixture();
  await mount(React.createElement(VouchersPage));
  const cell = name => $$('td', voucherRow(name)).find(td => /Until /.test(td.textContent));
  assert.notEqual(cell('T Free Session').style.color, 'var(--danger)', 'valid until today: not red');
  assert.equal(cell('T Old Event').style.color, 'var(--danger)', 'valid until yesterday: red');
  assert.equal(cell('T Free Session').textContent, `Until ${dayText(sgToday())}`);
});

test('Vouchers: "Can be given as a reward" for free-session vouchers only', async () => {
  voucherFixture();
  await mount(React.createElement(VouchersPage));
  assert.match(voucherRow('T Old Event').textContent, /Not given as a reward/);
  await click(editButton('T Free Session'));
  const box = checkboxLabelled('Can be given as a reward', modal());
  assert.equal(box.checked, true);
  await click(box);
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.equal(saveCall().payload.reward_eligible, false);

  await click(editButton('T Birthday'));
  assert.equal(checkboxLabelled('Can be given as a reward', modal()), undefined, 'not offered for a discount voucher');
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.equal('reward_eligible' in saveCall().payload, false, 'a discount voucher\'s flag is not sent');
});

test('Vouchers: Delete says what still depends on the voucher, needs a reason, and is done by the server', async () => {
  voucherFixture();
  rpcs.soft_delete_voucher = args => args.p_confirmed
    ? { data: { deleted: true, needs_confirmation: false }, error: null }
    : { data: { deleted: false, needs_confirmation: true, holders_customers: 10, holders_units: 13,
        store_stock: [{ store_id: 's-a', store_name: 'Store A', quantity: 4 }], store_stock_total: 4,
        used_in: { promotions: 1, premium_bundles: 0, credit_packages: 0, therapy_packages: 0 }, used_in_total: 1 }, error: null };
  await mount(React.createElement(VouchersPage));
  await click($$('button', voucherRow('T Old Event')).find(b => b.getAttribute('aria-label') === 'Delete T Old Event'));
  assert.equal(asked[0], 'Delete voucher "T Old Event"?');
  assert.deepEqual(rpcCalls('soft_delete_voucher')[0].args, { p_voucher_id: 'v2', p_reason: null, p_confirmed: false });
  assert.equal(calls.filter(c => c.kind === 'from' && c.table === 'vouchers' && c.op === 'update').length, 0, 'the table is not written directly');
  const text = modal().textContent;
  assert.match(text, /10 customers hold 13 units of it\. They keep them\./);
  assert.match(text, /In stock: Store A 4\./);
  assert.match(text, /Offered by 1 live promotion\./);
  const go = byText('button', 'Delete anyway', modal());
  assert.equal(go.disabled, true, 'a reason first');
  await type(modal().querySelector('textarea'), 'The event is over');
  await click(byText('button', 'Delete anyway', modal()));
  assert.deepEqual(rpcCalls('soft_delete_voucher')[1].args, { p_voucher_id: 'v2', p_reason: 'The event is over', p_confirmed: true });
  assert.match(document.body.textContent, /"T Old Event" deleted\. Customers keep the vouchers they hold\./);
});

test('Vouchers: a refused delete says so', async () => {
  voucherFixture();
  rpcs.soft_delete_voucher = { data: null, error: { message: 'Only an Owner or Manager can do this.' } };
  await mount(React.createElement(VouchersPage));
  await click($$('button', voucherRow('T Free Session')).find(b => b.getAttribute('aria-label') === 'Delete T Free Session'));
  assert.match(byText('[role=alert]', 'was not deleted').textContent, /"T Free Session" was not deleted: Only an Owner or Manager can do this\./);
});

// ── Store prices ────────────────────────────────────────────────────────
test('Store prices: a negative price is refused before it is sent; unsaved prices are not lost without asking', async () => {
  tables = { unlimited_therapy_store_prices: [{ store_id: 's-a', selling_price: 100, available_at_store: true, deleted_at: null, package_id: 'p1' }] };
  rpcs = {};
  let closed = 0;
  const stores = [{ id: 's-a', name: 'Store A' }, { id: 's-b', name: 'Store B' }];
  const el = () => React.createElement(StorePriceEditor, { kind: 'therapy', targetId: 'p1', targetName: 'T Package', stores, onClose: () => { closed++; } });
  await mount(el());
  const priceA = document.getElementById('store-price-s-a');
  await type(priceA, '-5');
  assert.match(modal().textContent, /Price cannot be negative/);
  const saveA = $$('button', priceA.closest('div[style]').parentElement).find(b => b.textContent === 'Save');
  assert.equal(saveA.disabled, true);
  assert.equal(rpcCalls('set_unlimited_therapy_price').length, 0);

  await type(priceA, '120');
  answers = [false];
  await click(byText('button', 'Done', modal()));
  assert.equal(asked.at(-1), 'You have unsaved prices for Store A. Discard them?');
  assert.equal(closed, 0, 'kept open');
  answers = [true];
  await click(byText('button', 'Done', modal()));
  assert.equal(closed, 1, 'closed once discarding is confirmed');

  await mount(el());
  await click(byText('button', 'Done', modal()));
  assert.equal(asked.length, 0, 'nothing typed: no question');
  assert.equal(closed, 2);

  await mount(el());
  await type(document.getElementById('store-price-s-b'), '0');
  await click($$('button', document.getElementById('store-price-s-b').closest('div[style]').parentElement).find(b => b.textContent === 'Save'));
  assert.deepEqual(rpcCalls('set_unlimited_therapy_price')[0].args,
    { p_package_id: 'p1', p_store_id: 's-b', p_member: 0, p_non_member: 0, p_available: true });
});

test('Store prices: saving one store keeps the price typed for another', async () => {
  tables = { unlimited_therapy_store_prices: [{ store_id: 's-a', selling_price: 100, available_at_store: true, deleted_at: null, package_id: 'p1' }] };
  rpcs = {};
  let closed = 0;
  const stores = [{ id: 's-a', name: 'Store A' }, { id: 's-b', name: 'Store B' }];
  await mount(React.createElement(StorePriceEditor, { kind: 'therapy', targetId: 'p1', targetName: 'T Package', stores, onClose: () => { closed++; } }));
  await type(document.getElementById('store-price-s-a'), '110');
  await type(document.getElementById('store-price-s-b'), '90');
  // The server saves A; the window reads the saved rows again.
  rpcs.set_unlimited_therapy_price = args => {
    tables.unlimited_therapy_store_prices = [{ store_id: 's-a', selling_price: args.p_member, available_at_store: true, deleted_at: null, package_id: 'p1' }];
    return { data: null, error: null };
  };
  const rowOf = id => document.getElementById(id).closest('div[style]').parentElement;
  await click($$('button', rowOf('store-price-s-a')).find(b => b.textContent === 'Save'));
  assert.equal(rpcCalls('set_unlimited_therapy_price').length, 1);
  assert.equal(rpcCalls('set_unlimited_therapy_price')[0].args.p_store_id, 's-a');
  assert.equal(document.getElementById('store-price-s-a').value, '110', 'A shows what was saved');
  assert.equal(document.getElementById('store-price-s-b').value, '90', 'B is still as typed');
  answers = [false];
  await click(byText('button', 'Done', modal()));
  assert.equal(asked.at(-1), 'You have unsaved prices for Store B. Discard them?');
  assert.equal(closed, 0);
});

test('Store prices: when the saved prices cannot be read, nothing can be changed until Retry reads them', async () => {
  tables = { unlimited_therapy_store_prices: { error: { message: 'offline' } } };
  rpcs = {};
  let closed = 0;
  const stores = [{ id: 's-a', name: 'Store A' }, { id: 's-b', name: 'Store B' }];
  await mount(React.createElement(StorePriceEditor, { kind: 'therapy', targetId: 'p1', targetName: 'T Package', stores, onClose: () => { closed++; } }));
  assert.match(modal().textContent, /The saved prices could not be loaded: offline/);
  assert.equal($$('[id^=store-price-]').length, 0, 'no price box');
  assert.equal($$('input[type=checkbox]', modal()).length, 0, 'no Available tick');
  assert.equal($$('button', modal()).filter(b => b.textContent === 'Save').length, 0, 'no Save');
  assert.equal(rpcCalls('set_unlimited_therapy_price').length, 0);

  tables.unlimited_therapy_store_prices = [{ store_id: 's-b', selling_price: 80, available_at_store: false, deleted_at: null, package_id: 'p1' }];
  await click(byText('button', 'Retry', modal()));
  assert.equal(document.getElementById('store-price-s-b').value, '80', 'the saved price, once read');
  const availB = document.getElementById('store-price-s-b').closest('div[style]').parentElement.querySelector('input[type=checkbox]');
  assert.equal(availB.checked, false, 'a store switched off stays off');
  assert.doesNotMatch(modal().textContent, /could not be loaded/);
  await click(byText('button', 'Done', modal()));
  assert.equal(closed, 1, 'nothing typed: closes');
});

// ── Therapy Services ────────────────────────────────────────────────────
function servicesFixture() {
  const svc = (id, name, extra = {}) => ({ id, service_code: id.toUpperCase(), name, description: null, standard_price: 50, effective_price: 50,
    duration_minutes: 30, frequency_kind: 'unrestricted', frequency_max_per_period: 1, frequency_interval_hours: null,
    frequency_description: 'No frequency limit.', is_active: true, is_archived: false, store_count: 1, store_names: ['Store A'],
    available_here: true, has_price_override: false, can_manage: true, ...extra });
  tables = {
    stores: [
      { id: 's-a', name: 'Store A', is_active: true, deleted_at: null },
      { id: 's-b', name: 'Store B', is_active: true, deleted_at: null },
      { id: 's-c', name: 'Store C', is_active: false, deleted_at: null },
      { id: 's-d', name: 'Store D', is_active: true, deleted_at: '2026-09-01T00:00:00Z' },
    ],
    vouchers: [{ id: 'tv1', name: 'T Two Sessions', code: 'T2S', deleted_at: null, is_active: true }],
    therapy_service_stores: [{ service_id: 'svc-a', store_id: 's-c', is_available: true, price_override: 10 }],
    therapy_services: [{ id: 'svc-a', notes: 'Keep me' }],
  };
  rpcs = {
    therapy_service_catalogue: { data: [svc('svc-a', 'T Service A'), svc('svc-b', 'T Service B', { is_active: false, is_archived: true })], error: null },
    therapy_voucher_definition: { data: { version: 1, sessions_per_voucher: 1, validity_kind: 'none', repeat_kind: 'unrestricted',
      components: [{ component_kind: 'choice', quantity: 1, label: null, services: [{ service_id: 'svc-a' }, { service_id: 'svc-b' }] }] }, error: null },
  };
}
const serviceRow = name => $$('tbody tr').find(tr => tr.textContent.includes(name));

test('Therapy Services: open stores only, plus a closed store this service has; one save for all stores, errors inside the window', async () => {
  servicesFixture();
  await mount(React.createElement(TherapyServicesPage), { profile: { role: 'manager' } });
  const filter = document.querySelector('select.therapy-store-select');
  assert.deepEqual($$('option', filter).map(o => o.textContent), ['Every store (standard price)', 'Store A', 'Store B']);

  await click($$('button', serviceRow('T Service A')).find(b => b.title === 'Stores and prices'));
  const names = $$('.therapy-store-row label', modal()).map(l => l.textContent);
  assert.deepEqual(names, ['Store A', 'Store B', 'Store C (closed store)'], 'Store D (deleted, no row) is not offered');

  const rowOf = n => $$('.therapy-store-row', modal()).find(r => r.textContent.startsWith(n));
  await click(rowOf('Store B').querySelector('input[type=checkbox]'));
  await type(rowOf('Store B').querySelector('input[type=number]'), '-1');
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.match(modal().querySelector('[role=alert]').textContent, /The price at Store B cannot be negative/);
  assert.equal(rpcCalls('set_therapy_service_stores').length, 0, 'nothing sent');

  rpcs.set_therapy_service_stores = { data: null, error: { message: 'A store in this list no longer exists. Close the window and open it again.' } };
  await type(rowOf('Store B').querySelector('input[type=number]'), '5');
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.ok(modal(), 'still open');
  assert.match(modal().querySelector('[role=alert]').textContent, /Nothing was saved\. A store in this list no longer exists/);
  assert.deepEqual(rpcCalls('set_therapy_service_stores')[0].args, { p_service_id: 'svc-a', p_rows: [
    { store_id: 's-a', is_available: false, price_override: null },
    { store_id: 's-b', is_available: true, price_override: 5 },
    { store_id: 's-c', is_available: true, price_override: 10 },
  ] }, 'every row in one call');
  assert.equal(rpcCalls('set_therapy_service_store').length, 0, 'not one store at a time');

  rpcs.set_therapy_service_stores = { data: 3, error: null };
  await click(byText('button', 'Save', modal().querySelector('.modal-footer')));
  assert.equal($$('.modal').length, 0, 'closed after a good save');
});

test('Therapy Services: a failed read of a service\'s stores does not open the window', async () => {
  servicesFixture();
  tables.therapy_service_stores = { error: { message: 'offline' } };
  await mount(React.createElement(TherapyServicesPage), { profile: { role: 'manager' } });
  await click($$('button', serviceRow('T Service A')).find(b => b.title === 'Stores and prices'));
  assert.equal($$('.modal').length, 0, 'no window with every store switched off');
  assert.match(document.body.textContent, /The stores of T Service A could not be read: offline/);
  assert.equal(rpcCalls('set_therapy_service_stores').length, 0);
});

test('Therapy Services: the notes are read into the form and sent back', async () => {
  servicesFixture();
  await mount(React.createElement(TherapyServicesPage), { profile: { role: 'manager' } });
  await click($$('button', serviceRow('T Service A')).find(b => b.title === 'Edit'));
  const notes = document.getElementById('service-notes');
  assert.equal(notes.value, 'Keep me');
  await click(byText('button', 'Save Changes', modal()));
  assert.equal(rpcCalls('upsert_therapy_service')[0].args.p_notes, 'Keep me');

  await click($$('button', serviceRow('T Service A')).find(b => b.title === 'Edit'));
  await type(document.getElementById('service-notes'), '');
  await click(byText('button', 'Save Changes', modal()));
  assert.equal(rpcCalls('upsert_therapy_service')[1].args.p_notes, '', 'an emptied box clears them');

  tables.therapy_services = { error: { message: 'offline' } };
  await click($$('button', serviceRow('T Service A')).find(b => b.title === 'Edit'));
  assert.equal(document.getElementById('service-notes').disabled, true);
  assert.match(modal().textContent, /could not be read, so they are kept as they are/);
  await click(byText('button', 'Save Changes', modal()));
  assert.equal(rpcCalls('upsert_therapy_service')[2].args.p_notes, null, 'unread notes are not sent, so they are kept');
});

test('Therapy Services: an archived service in a choice can be unticked; the limits are a guide', async () => {
  servicesFixture();
  await mount(React.createElement(TherapyServicesPage), { profile: { role: 'manager' } });
  await click(byText('button', 'What a voucher gives'));
  await type(byText('label', 'Voucher').parentElement.querySelector('select'), 'tv1');
  const archived = checkboxLabelled('T Service B (archived): untick to take it out');
  assert.ok(archived, 'the archived service is shown');
  assert.equal(archived.checked, true);
  assert.match(document.body.textContent, /These limits are a guide for staff: the app does not check them at the counter yet\./);
  assert.doesNotMatch(document.body.textContent, /stricter of the two applies/);
  await click(archived);
  assert.equal(checkboxLabelled('T Service B (archived)'), undefined, 'gone once unticked');
  await click(byText('button', 'Save what this voucher gives'));
  assert.deepEqual(rpcCalls('upsert_therapy_voucher_definition')[0].args.p_components,
    [{ kind: 'choice', quantity: 1, service_ids: ['svc-a'], label: null }]);
});

// ── Split panels ────────────────────────────────────────────────────────
test('Split panels: a failed preview shows the error with Retry', async () => {
  let n = 0;
  tables = {};
  rpcs = {
    credit_package_benefit_preview: () => (++n === 1 ? { data: null, error: { message: 'Network lost' } }
      : { data: { found: true, package_name: 'T Credit', customer_price: 1000, paid_credit_total: 1000, bonus_total: 0,
          grants_reward: false, reward_voucher_total: 0 }, error: null }),
    premium_bundle_benefit_preview: { data: null, error: { message: 'Bundle preview failed' } },
  };
  await mount(React.createElement(CreditPackageSplitPanel, { storeId: 's-a', creditPackageId: 'cp1', serviceStaff: [], affiliateId: null,
    notes: null, onCreated: () => {}, onCancel: () => {} }));
  assert.match(document.body.textContent, /The package could not be loaded: Network lost/);
  assert.doesNotMatch(document.body.textContent, /Loading package/);
  await click(byText('button', 'Retry'));
  assert.match(document.body.textContent, /Customer Allocation — T Credit/);

  await mount(React.createElement(PremiumBundleSplitPanel, { storeId: 's-a', bundleId: 'pb1', serviceStaff: [], affiliateId: null,
    notes: null, onCreated: () => {}, onCancel: () => {} }));
  assert.match(document.body.textContent, /The bundle could not be loaded: Bundle preview failed/);
  assert.ok(byText('button', 'Retry'));
});

const splitCustomers = [
  { id: 'c-1', full_name: 'T Customer One', phone: '+6591234801', deleted_at: null },
  { id: 'c-2', full_name: 'T Customer Two', phone: '+6591234802', deleted_at: null },
];
const creditPreview = { data: { found: true, package_name: 'T Credit', customer_price: 1000, paid_credit_total: 1000,
  bonus_total: 0, grants_reward: false, reward_voucher_total: 0 }, error: null };
const bundlePreview = { data: { found: true, bundle_name: 'T Bundle', customer_price: 1000, paid_credit_total: 1000,
  bonus_total: 0, free_voucher_total: 0, allowed_vouchers: [] }, error: null };
// Picks both customers and types the two payments.
async function fillSplit(pay = ['600', '400']) {
  const rows = $$('tbody tr');
  for (const [i, name] of [[0, 'T Customer One'], [1, 'T Customer Two']]) {
    await click($$('button', rows[i])[0]);
    await act(async () => { await new Promise(r => setTimeout(r, 260)); });
    await tick();
    const option = $$('div', rows[i]).find(d => d.firstChild?.textContent === name);
    await act(async () => { option.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
    await tick();
  }
  await type(rows[0].querySelector('input[type=number]'), pay[0]);
  await type(rows[1].querySelector('input[type=number]'), pay[1]);
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

test('Split panels: pressing Create again sends the same request id; a new panel, a new id', async () => {
  tables = { customers: splitCustomers };
  let n = 0;
  const created = [];
  rpcs = {
    credit_package_benefit_preview: creditPreview,
    create_split_credit_package_invoices: () => (++n === 1 ? { data: null, error: { message: 'TypeError: Failed to fetch', code: '' } }
      : { data: { split_group_id: 'g1', invoices: [] }, error: null }),
  };
  const panel = () => React.createElement(CreditPackageSplitPanel, { storeId: 's-a', creditPackageId: 'cp1', serviceStaff: [],
    affiliateId: null, notes: null, onCreated: d => created.push(d), onCancel: () => {} });
  await mount(panel());
  await fillSplit();
  const create = byText('button', 'Create 2 Invoices');
  assert.equal(create.disabled, false, 'ready to create');
  await click(create);
  assert.match(document.body.textContent,
    /We could not tell if the invoices were made \(TypeError: Failed to fetch\)\. Press Create again: if they were made, they are shown and no second sale is made\./);
  assert.doesNotMatch(document.body.textContent, /The invoices were not created/, 'a lost answer is not called a failure');
  await click(byText('button', 'Create 2 Invoices'));
  const ids = rpcCalls('create_split_credit_package_invoices').map(c => c.args.p_request_id);
  assert.equal(ids.length, 2);
  assert.match(ids[0], UUID);
  assert.equal(ids[1], ids[0], 'the retry is the same request');
  assert.equal(created.length, 1);

  // Made: the next split of the same package and store is another sale.
  await mount(panel());
  await fillSplit(['500', '500']);
  await click(byText('button', 'Create 2 Invoices'));
  assert.notEqual(rpcCalls('create_split_credit_package_invoices')[0].args.p_request_id, ids[0]);
  assert.equal(created.length, 2);
});

test('Split panels: the bundle panel sends the same request id when Create is pressed again', async () => {
  tables = { customers: splitCustomers };
  let n = 0;
  const created = [];
  rpcs = {
    premium_bundle_benefit_preview: bundlePreview,
    create_split_premium_bundle_invoices: () => (++n === 1 ? { data: null, error: { message: 'TypeError: Failed to fetch', code: '' } }
      : { data: { split_group_id: 'g2', invoices: [], replayed: true }, error: null }),
  };
  await mount(React.createElement(PremiumBundleSplitPanel, { storeId: 's-a', bundleId: 'pb1', serviceStaff: [],
    affiliateId: null, notes: null, onCreated: d => created.push(d), onCancel: () => {} }));
  await fillSplit();
  await click(byText('button', 'Create 2 Invoices'));
  assert.match(document.body.textContent, /We could not tell if the invoices were made \(TypeError: Failed to fetch\)/);
  await click(byText('button', 'Create 2 Invoices'));
  const ids = rpcCalls('create_split_premium_bundle_invoices').map(c => c.args.p_request_id);
  assert.equal(ids.length, 2);
  assert.match(ids[0], UUID);
  assert.equal(ids[1], ids[0], 'the retry is the same request');
  assert.equal(created.length, 1);
});

test('Split panels: after a lost answer, Cancel asks, and the split opened again sends the same id', async () => {
  tables = { customers: splitCustomers };
  let cancelled = 0;
  const created = [];
  rpcs = {
    premium_bundle_benefit_preview: bundlePreview,
    create_split_premium_bundle_invoices: { data: null, error: { message: '<html>504 Gateway Time-out</html>' } },
  };
  const panel = (storeId = 's-a') => React.createElement(PremiumBundleSplitPanel, { storeId, bundleId: 'pb7', serviceStaff: [],
    affiliateId: null, notes: null, onCreated: d => created.push(d), onCancel: () => { cancelled++; } });
  await mount(panel());
  await fillSplit();
  await click(byText('button', 'Create 2 Invoices'));
  assert.match(document.body.textContent, /We could not tell if the invoices were made/);
  const first = rpcCalls('create_split_premium_bundle_invoices')[0].args.p_request_id;
  answers = [false];
  await click(byText('button', 'Cancel'));
  assert.equal(asked.at(-1), 'The invoices may already have been made. Press Create again to find out. Close anyway?');
  assert.equal(cancelled, 0, 'kept open');
  answers = [true];
  await click(byText('button', 'Cancel'));
  assert.equal(cancelled, 1);

  // Opened again (Cancel or "Single Customer" closed it): the same id, and it says why.
  rpcs.create_split_premium_bundle_invoices = { data: { split_group_id: 'g7', invoices: [], replayed: true }, error: null };
  await mount(panel());
  assert.match(document.body.textContent, /An earlier try got no answer, so these invoices may already have been made\./);
  await fillSplit();
  await click(byText('button', 'Create 2 Invoices'));
  assert.equal(rpcCalls('create_split_premium_bundle_invoices')[0].args.p_request_id, first, 'the same sale, not a second one');
  assert.equal(created.length, 1);

  // Another store is another sale; and once shown, the id is let go.
  await mount(panel('s-b'));
  assert.doesNotMatch(document.body.textContent, /An earlier try got no answer/);
  await mount(panel());
  assert.doesNotMatch(document.body.textContent, /An earlier try got no answer/);
  await fillSplit();
  await click(byText('button', 'Create 2 Invoices'));
  assert.notEqual(rpcCalls('create_split_premium_bundle_invoices')[0].args.p_request_id, first);
  await click(byText('button', 'Cancel'));
  assert.equal(asked.length, 0, 'nothing unsure: Cancel does not ask');
});

test('Split panels: a refusal says the invoices were not created', async () => {
  tables = { customers: splitCustomers };
  let cancelled = 0;
  rpcs = {
    credit_package_benefit_preview: creditPreview,
    create_split_credit_package_invoices: { data: null, error: { message: 'Customer T is not active.', code: 'P0001' } },
  };
  await mount(React.createElement(CreditPackageSplitPanel, { storeId: 's-a', creditPackageId: 'cp9', serviceStaff: [],
    affiliateId: null, notes: null, onCreated: () => {}, onCancel: () => { cancelled++; } }));
  await fillSplit();
  await click(byText('button', 'Create 2 Invoices'));
  assert.match(document.body.textContent, /The invoices were not created\. Customer T is not active\./);
  assert.doesNotMatch(document.body.textContent, /could not tell/);
  await click(byText('button', 'Cancel'));
  assert.equal(asked.length, 0, 'a known refusal: Cancel does not ask');
  assert.equal(cancelled, 1);
});

test('Split panels: an id that already made another sale is let go, and staff are told to check first', async () => {
  tables = { customers: splitCustomers };
  const created = [];
  let cancelled = 0;
  rpcs = {
    credit_package_benefit_preview: creditPreview,
    create_split_credit_package_invoices: { data: null, error: { message: 'TypeError: Failed to fetch', code: '' } },
  };
  const panel = () => React.createElement(CreditPackageSplitPanel, { storeId: 's-a', creditPackageId: 'cp5', serviceStaff: [],
    affiliateId: null, notes: null, onCreated: d => created.push(d), onCancel: () => { cancelled++; } });
  await mount(panel());
  await fillSplit();
  await click(byText('button', 'Create 2 Invoices'));
  assert.match(document.body.textContent, /We could not tell if the invoices were made/);
  const first = rpcCalls('create_split_credit_package_invoices')[0].args.p_request_id;

  // The amounts are changed and Create pressed again: the server made the
  // first sale and refuses this id for another one.
  rpcs.create_split_credit_package_invoices = { data: null,
    error: { message: 'This request was already used for another sale. Close the split and start again.', code: 'P0001' } };
  const rows = $$('tbody tr');
  await type(rows[0].querySelector('input[type=number]'), '500');
  await type(rows[1].querySelector('input[type=number]'), '500');
  await click(byText('button', 'Create 2 Invoices'));
  assert.equal(rpcCalls('create_split_credit_package_invoices')[1].args.p_request_id, first, 'sent with the kept id');
  assert.match(document.body.textContent,
    /An earlier try of this split already made invoices, with other customers, amounts or vouchers\. Check the invoice list first\. Press Create again only if this is a second sale\./);
  assert.doesNotMatch(document.body.textContent, /The invoices were not created/);
  assert.equal(created.length, 0, 'nothing is shown as made');

  // Pressed again: a new id, so it is a new sale, not stuck on the old id.
  rpcs.create_split_credit_package_invoices = { data: { split_group_id: 'g5', invoices: [] }, error: null };
  await click(byText('button', 'Create 2 Invoices'));
  const third = rpcCalls('create_split_credit_package_invoices')[2].args.p_request_id;
  assert.match(third, UUID);
  assert.notEqual(third, first, 'a new id');
  assert.equal(created.length, 1);

  // Opened again: the old id is not kept, and nothing is unsure.
  await mount(panel());
  assert.doesNotMatch(document.body.textContent, /An earlier try got no answer/);
  await click(byText('button', 'Cancel'));
  assert.equal(asked.length, 0, 'Cancel does not ask');
  assert.equal(cancelled, 1);
});

test('Split panels: the bundle panel lets go of an id that already made another sale', async () => {
  tables = { customers: splitCustomers };
  rpcs = {
    premium_bundle_benefit_preview: bundlePreview,
    create_split_premium_bundle_invoices: { data: null, error: { message: 'TypeError: Failed to fetch', code: '' } },
  };
  const panel = () => React.createElement(PremiumBundleSplitPanel, { storeId: 's-a', bundleId: 'pb5', serviceStaff: [],
    affiliateId: null, notes: null, onCreated: () => {}, onCancel: () => {} });
  await mount(panel());
  await fillSplit();
  await click(byText('button', 'Create 2 Invoices'));
  const first = rpcCalls('create_split_premium_bundle_invoices')[0].args.p_request_id;
  rpcs.create_split_premium_bundle_invoices = { data: null,
    error: { message: 'This request was already used for another sale. Close the split and start again.', code: 'P0001' } };
  await click(byText('button', 'Create 2 Invoices'));
  assert.match(document.body.textContent, /An earlier try of this split already made invoices/);
  await click(byText('button', 'Create 2 Invoices'));
  const ids = rpcCalls('create_split_premium_bundle_invoices').map(c => c.args.p_request_id);
  assert.equal(ids[1], first);
  assert.notEqual(ids[2], first, 'a new id after the refusal');
  await mount(panel());
  assert.doesNotMatch(document.body.textContent, /An earlier try got no answer/, 'the old id is not kept');
});

// ── Benefit window ──────────────────────────────────────────────────────
const unit = extra => ({ purchased_id: 'pu1', entitlement_no: 'UTP-T0001', unit_label: 'T Package', package_name: 'T Package',
  unit_index: 1, unit_count: 1, offered_choices: ['unlimited', 'voucher'], offers_choice: true, benefit_choice: null,
  choice_pending: true, choice_deadline: '2026-12-31', choice_deadline_passed: false, status: 'pending', duration_months: 12,
  voucher_qty: 10, activation_date: null, scheduled_date: null, expiry_date: null, voucher_entitlement_id: null, vouchers: null,
  eligible_vouchers: [], eligible_services: [], can_switch: false, switch_blocked_reason: null, ...extra });

test('Benefit window: no unreachable "Confirm choice"; it points to Claim', async () => {
  tables = {};
  rpcs = { purchased_therapy_unit_state: { data: unit(), error: null } };
  await mount(React.createElement(BenefitChoicePanel, { purchasedId: 'pu1', canSwitch: true, onClose: () => {} }));
  assert.equal(byText('button', 'Confirm choice'), undefined);
  assert.match(document.body.textContent, /Choose it with Claim on the Therapy page\./);
  assert.match(document.body.textContent, /Start it with Claim when the customer is ready\./);
  assert.doesNotMatch(document.body.textContent, /Activate it separately/);
  assert.ok($$('input[type=radio]').every(r => r.disabled), 'nothing to pick here');
});

test('Benefit window: a switch retried after an error is the same request', async () => {
  let n = 0;
  tables = {};
  rpcs = {
    purchased_therapy_unit_state: { data: unit({ choice_pending: false, benefit_choice: 'unlimited', can_switch: true, status: 'pending' }), error: null },
    switch_therapy_benefit: () => (++n === 1 ? { data: null, error: { message: 'Failed to fetch' } } : { data: null, error: null }),
  };
  await mount(React.createElement(BenefitChoicePanel, { purchasedId: 'pu1', canSwitch: true, onClose: () => {} }));
  await click(byText('button', 'Switch benefit'));
  await click($$('input[type=radio]').find(r => r.value === 'voucher'));
  await type(document.querySelector('textarea'), 'Customer asked');
  await click(byText('button', 'Confirm switch'));
  assert.match(document.body.textContent, /Failed to fetch/);
  await click(byText('button', 'Confirm switch'));
  const ids = rpcCalls('switch_therapy_benefit').map(c => c.args.p_request_id);
  assert.equal(ids.length, 2);
  assert.equal(ids[1], ids[0]);
  assert.match(document.body.textContent, /Benefit switched\./);
});

// ── Holidays and the recalculation ──────────────────────────────────────
test('Holidays: a regional calendar is checked per region; a new date takes a region', async () => {
  tables = {
    therapy_holiday_countries: [
      { code: 'MY', name: 'Malaysia', is_active: true, requires_region: true, notes: null },
      { code: 'SG', name: 'Singapore', is_active: true, requires_region: false, notes: null },
    ],
    therapy_closure_dates: [],
  };
  rpcs = { therapy_calendar_gaps: { data: { verified: false, reasons: ['Not checked'] }, error: null } };
  await mount(React.createElement(HolidayAdmin, { canManage: true }));
  assert.equal(document.getElementById('cal-region'), null, 'Singapore: no region');
  await type(document.getElementById('cal-country'), 'MY');
  const check = byText('button', 'I have checked these dates');
  assert.equal(check.disabled, true, 'Malaysia needs a region first');
  const before = rpcCalls('therapy_calendar_gaps').length;
  for (const typed of ['S', 'Se', 'Sel', ' Selangor ']) await type(document.getElementById('cal-region'), typed);
  assert.equal(rpcCalls('therapy_calendar_gaps').length, before, 'not read on every key');
  await act(async () => { await new Promise(r => setTimeout(r, 350)); });
  await tick();
  assert.equal(rpcCalls('therapy_calendar_gaps').length, before + 1, 'read once typing pauses');
  assert.equal(rpcCalls('therapy_calendar_gaps').at(-1).args.p_region, 'Selangor');
  answers = ['jakim.gov.my'];
  await click(byText('button', 'I have checked these dates'));
  assert.deepEqual(rpcCalls('set_therapy_calendar_coverage')[0].args, { p_country: 'MY', p_year: new Date().getFullYear(),
    p_region: 'Selangor', p_verified: true, p_source: 'jakim.gov.my', p_source_reference: null, p_notes: null });
  await type(document.getElementById('cal-region'), 'Johor');
  assert.equal(byText('button', 'I have checked these dates').disabled, true, 'not until the calendar shown is the one typed');
  await act(async () => { await new Promise(r => setTimeout(r, 350)); });
  await tick();
  assert.equal(byText('button', 'I have checked these dates').disabled, false);
  assert.equal(rpcCalls('therapy_calendar_gaps').at(-1).args.p_region, 'Johor');

  await type(document.getElementById('add-date'), '2027-03-02');
  await type(document.getElementById('add-name'), 'T State Day');
  await type(document.getElementById('add-scope'), 'MY');
  await type(document.getElementById('add-region'), '  Johor ');
  await click(byText('button', 'Add date'));
  let a = rpcCalls('upsert_therapy_closure_date').at(-1).args;
  assert.equal(a.p_country, 'MY'); assert.equal(a.p_region, 'Johor');

  await type(document.getElementById('add-date'), '2027-03-03');
  await type(document.getElementById('add-name'), 'T Closure');
  await type(document.getElementById('add-scope'), 'ALL');
  assert.equal(document.getElementById('add-region'), null, 'all countries: no region');
  await click(byText('button', 'Add date'));
  a = rpcCalls('upsert_therapy_closure_date').at(-1).args;
  assert.equal(a.p_country, null); assert.equal(a.p_region, null);
});

test('Holidays: an older calendar answer arriving late does not replace the newer one', async () => {
  tables = {
    therapy_holiday_countries: [{ code: 'MY', name: 'Malaysia', is_active: true, requires_region: true, notes: null }],
    therapy_closure_dates: [],
  };
  const wait = ms => act(async () => { await new Promise(r => setTimeout(r, ms)); });
  rpcs = { therapy_calendar_gaps: args => args.p_region === 'Sel'
    // The answer for "Sel" is slow and says checked; the one for "Selangor" is quick and says not.
    ? new Promise(r => setTimeout(() => r({ data: { verified: true, reasons: [] }, error: null }), 800))
    : { data: { verified: false, reasons: ['Not checked'] }, error: null } };
  await mount(React.createElement(HolidayAdmin, { canManage: true }));
  await type(document.getElementById('cal-country'), 'MY');
  await type(document.getElementById('cal-region'), 'Sel');
  await wait(350);
  await type(document.getElementById('cal-region'), 'Selangor');
  await wait(350);
  assert.deepEqual(rpcCalls('therapy_calendar_gaps').slice(-2).map(c => c.args.p_region), ['Sel', 'Selangor']);
  await wait(700);
  await tick();
  assert.match(document.body.textContent, /MY · Selangor \d{4} has not been checked against a source\./);
  assert.doesNotMatch(document.body.textContent, /has been checked against a source/);
});

test('Recalculation: Apply asks first, with how many periods are lengthened', async () => {
  tables = {};
  rpcs = {
    therapy_recalculation_preview: { data: [
      { entitlement_kind: 'purchased', entitlement_id: 'e1', entitlement_no: 'UTP-T1', change_days: 3, shortens: false, coverage: { verified: false } },
      { entitlement_kind: 'purchased', entitlement_id: 'e2', entitlement_no: 'UTP-T2', change_days: 5, shortens: false, coverage: { verified: true } },
      { entitlement_kind: 'purchased', entitlement_id: 'e3', entitlement_no: 'UTP-T3', change_days: -2, shortens: true, coverage: { verified: true } },
      { entitlement_kind: 'purchased', entitlement_id: 'e4', entitlement_no: 'UTP-T4', change_days: null, needs_country: true },
      // No country, yet a change is shown (an all-country closure): the server skips it.
      { entitlement_kind: 'purchased', entitlement_id: 'e5', entitlement_no: 'UTP-T5', change_days: 1, shortens: false, needs_country: true,
        coverage: { verified: false } },
      // No country and shorter: skipped for the country, so counted once.
      { entitlement_kind: 'purchased', entitlement_id: 'e6', entitlement_no: 'UTP-T6', change_days: -1, shortens: true, needs_country: true },
    ], error: null },
    therapy_apply_recalculation: { data: { updated: 2, unchanged: 0, skipped_needs_country: 3, skipped_would_shorten: 1 }, error: null },
  };
  await mount(React.createElement(RecalculationPreview, { canManage: true }));
  const apply = byText('button', 'Apply 2 lengthening change(s)');
  answers = [false];
  await click(apply);
  assert.match(asked[0], /^Lengthen 2 therapy periods\?/);
  assert.match(asked[0], /Left as they are: 1 that would be shortened and 3 with no holiday country\./);
  assert.match(asked[0], /1 of them run through a holiday calendar that has not been checked\./);
  assert.equal(rpcCalls('therapy_apply_recalculation').length, 0, 'cancelled: nothing applied');
  answers = [true];
  await click(byText('button', 'Apply 2 lengthening change(s)'));
  assert.equal(rpcCalls('therapy_apply_recalculation').length, 1);
});
