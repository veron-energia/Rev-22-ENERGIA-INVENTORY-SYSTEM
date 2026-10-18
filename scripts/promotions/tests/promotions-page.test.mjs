// The Promotions page against 424, rendered for real against a fake backend.
//
// The actual src/pages/PromotionsPage.tsx is bundled with esbuild and mounted
// in jsdom. Only the Supabase client and the auth context are stubbed: the
// client by a small in-memory backend that records every call. Every name,
// number and id below is invented.
//
// It checks that a promotion past its end date shows Ended and one before its
// start shows Not started (SALES-EXTRAS-9); that editing starts with "every
// store" unticked and changes the store prices only when the price changes,
// keeping each store's on/off (SALES-EXTRAS-10); that a failed price step
// after a new promotion is saved leaves the window editing that promotion, so
// Save again updates it rather than making a second one, that a repeated code
// is said in words, and that removals are confirmed by name and their errors
// shown (SALES-EXTRAS-11); and that the builder's Original says it counts the
// base choice, and a group added in the builder can set its base too
// (SALES-EXTRAS-13), a base that only a products group saves (the till reads it
// for products only) and that is cleared for the next group. A new promotion's
// hint says whether the stores get its price.
//
// Run: node --test scripts/promotions/tests/promotions-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://promotions.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
const confirms = [];
dom.window.confirm = m => { confirms.push(String(m)); return true; };
globalThis.confirm = dom.window.confirm;
dom.window.alert = () => {};
globalThis.alert = dom.window.alert;
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

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as PromotionsPage } from './src/pages/PromotionsPage';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };
      export class ErrorBoundary extends React.Component {
        constructor(p) { super(p); this.state = { error: null }; }
        static getDerivedStateFromError(error) { return { error }; }
        componentDidCatch(error) { globalThis.__renderErrors.push(String(error && error.stack || error)); }
        render() { return this.state.error ? React.createElement('div', { id: 'crashed' }, String(this.state.error.message)) : this.props.children; }
      }`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };` }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { PromotionsPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture and fake backend ───────────────────────────────────────────────
const promo = (id, name, code, extra = {}) => ({ id, name, code, promo_type: 'bundle', fixed_price: 100, start_date: null,
  end_date: null, is_active: true, description: null, terms: null, deleted_at: null, created_at: '2026-09-01T00:00:00Z', ...extra });
function makeFixture() {
  return {
    promotions: [
      promo('pr-live', 'XP Live', 'XPLIVE'),
      promo('pr-ended', 'XP September', 'XPSEPT', { start_date: '2026-07-01', end_date: '2026-10-01' }),
      promo('pr-soon', 'XP Next Year', 'XPNEXT', { start_date: '2999-01-01' }),
      promo('pr-off', 'XP Off', 'XPOFF', { is_active: false }),
    ],
    products: [{ id: 'p-a', name: 'XP A', sku: 'XPA', is_active: true, deleted_at: null }],
    stores: [{ id: 'st-1', name: 'XP Store', is_active: true, deleted_at: null }],
    items: [{ id: 'pi-1', promotion_id: 'pr-live', item_type: 'product', product_id: 'p-a', quantity: 1, created_at: '2026-09-01T00:00:00Z' }],
    groups: [{ id: 'g-1', promotion_id: 'pr-live', label: 'Pick one', item_kind: 'product', choose_qty: 1, base_mode: 'cheapest', created_at: '2026-09-01T00:00:00Z' }],
    options: [{ id: 'o-1', group_id: 'g-1', product_id: 'p-a' }],
    sold: { 'pr-live': 3 },
  };
}
function createBackend(fx) {
  const b = { calls: [], fx, failPriceOnce: false, insertError: null, deleteError: {}, deleteNothing: {} };
  let n = 0;
  const tables = {
    promotions: fx.promotions, products: fx.products, vouchers: [], stores: fx.stores,
    promotion_items: fx.items, promotion_choice_groups: fx.groups, promotion_choice_options: fx.options,
    unlimited_therapy_packages: [], credit_packages: [], invoice_items: [],
  };
  const rpcs = {
    promotion_original_total: () => 160,
    set_promotion_price_all_stores: () => {
      if (b.failPriceOnce) { b.failPriceOnce = false; throw Object.assign(new Error('the price step failed'), { code: 'P0001' }); }
      return 1;
    },
    add_promotion_item: () => null,
    set_promotion_prices: () => null,
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], isSingle: false, op: 'select', opts: null }); }
    select(_cols, opts) { if (this.op === 'select') this.opts = opts ?? null; return this; }
    insert(row) { this.op = 'insert'; this.row = row; return this; }
    update(row) { this.op = 'update'; this.row = row; return this; }
    delete() { this.op = 'delete'; return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); this.eqs = [...(this.eqs ?? []), [c, v]]; return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    order() { return this; }
    limit() { return this; }
    single() { this.isSingle = true; return this; }
    maybeSingle() { this.isSingle = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, op: this.op, args: this.args, row: this.row, eqs: this.eqs });
      await Promise.resolve();
      if (this.kind === 'rpc') {
        const fn = rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        try { return { data: structuredClone(fn(this.args)), error: null }; }
        catch (e) { return { data: null, error: { message: String(e.message), code: e.code } }; }
      }
      const rows = tables[this.name] ?? [];
      if (this.op === 'insert') {
        if (b.insertError) return { data: null, error: b.insertError };
        const row = { id: `new-${++n}`, created_at: '2026-10-09T00:00:00Z', deleted_at: null, ...this.row };
        rows.push(row);
        return { data: structuredClone(this.isSingle ? row : [row]), error: null };
      }
      const hit = rows.filter(r => this.filters.every(f => f(r)));
      if (this.op === 'update') {
        hit.forEach(r => Object.assign(r, this.row));
        return { data: structuredClone(this.isSingle ? hit[0] ?? null : hit), error: null };
      }
      if (this.op === 'delete') {
        const id = hit[0]?.id;
        if (b.deleteError[id]) return { data: null, error: b.deleteError[id] };
        if (b.deleteNothing[id]) return { data: [], error: null };
        for (const r of hit) rows.splice(rows.indexOf(r), 1);
        return { data: hit.map(r => ({ id: r.id })), error: null };
      }
      if (this.opts?.head) {
        const pid = (this.eqs ?? []).find(([c]) => c === 'promotion_id')?.[1];
        return { data: null, count: this.name === 'invoice_items' ? (fx.sold[pid] ?? 0) : hit.length, error: null };
      }
      return { data: structuredClone(this.isSingle ? hit[0] ?? null : hit), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving the page ───────────────────────────────────────────────────────
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount() {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture());
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true } };
  confirms.length = 0;
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(PromotionsPage))));
  await tick();
}
const text = () => document.body.textContent;
const modal = () => [...document.querySelectorAll('.modal')].at(-1);
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(b => b.textContent.trim() === label);
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype
    : el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick(3);
}
const row = name => [...document.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes(name));
const priceCalls = () => backend.calls.filter(c => c.name === 'set_promotion_price_all_stores');
const everyStoreBox = () => [...modal().querySelectorAll('label')].find(l => l.textContent.includes('Use this price at every store')).querySelector('input');
const priceInput = () => modal().querySelector('input[placeholder="e.g. 188"]');
const nameInput = () => [...modal().querySelectorAll('.form-group')]
  .find(g => g.querySelector('label')?.textContent.startsWith('Name'))?.querySelector('input');
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
test('a promotion past its end date shows Ended, one before its start Not started', async () => {
  await mount();
  assert.deepEqual(globalThis.__renderErrors, []);
  const badge = name => row(name).querySelector('.badge:not(.badge-primary)')?.textContent;
  assert.equal(badge('XP Live'), 'Active');
  assert.equal(badge('XP September'), 'Ended');
  assert.equal(badge('XP Next Year'), 'Not started');
  assert.equal(badge('XP Off'), 'Inactive');
  // the till still lists an ended promotion but refuses it; only Exchanges hides it
  const ended = row('XP September').querySelector('.badge:not(.badge-primary)').title;
  assert.match(ended, /^Ended .+\. The till refuses it, and Exchanges no longer offers it\.$/);
  assert.ok(!ended.includes('No longer offered at the till'), ended);
});

test('editing leaves store prices alone unless the price changes, and then keeps each store on or off', async () => {
  await mount();
  const editButton = name => [...row(name).querySelectorAll('button')].at(-2);   // Items, Prices, Edit, Delete
  await click(editButton('XP Live'));
  assert.ok(modal().textContent.includes('Edit Promotion') || text().includes('Edit Promotion'));
  assert.equal(everyStoreBox().checked, false, 'editing starts with "every store" ticked');
  assert.equal(everyStoreBox().disabled, true, 'with the price unchanged there is nothing to set at every store');
  // a name change only: no store price is touched
  await setValue(nameInput(), 'XP Live Renamed');
  await click(button('Save', modal()));
  assert.equal(priceCalls().length, 0, 'a name change reset the store prices');
  assert.equal(document.querySelectorAll('.modal').length, 0);
  // a new price ticks the box, and is set at every store keeping each store's on/off
  await click(editButton('XP Live Renamed'));
  await setValue(priceInput(), '120');
  assert.equal(everyStoreBox().checked, true);
  assert.ok(text().includes('every store gets this price and stays on or off as it is'));
  await click(button('Save', modal()));
  assert.equal(priceCalls().length, 1);
  assert.deepEqual(priceCalls()[0].args, { p_promotion_id: 'pr-live', p_price: 120, p_available: null });
  // unticked, a new price leaves the stores alone
  await click(editButton('XP Live Renamed'));
  await setValue(priceInput(), '130');
  await click(everyStoreBox());
  assert.equal(everyStoreBox().checked, false);
  await click(button('Save', modal()));
  assert.equal(priceCalls().length, 1, 'the stores were given a price the box said not to');
});

test('a failed price step leaves the window editing the new promotion: Save again updates it', async () => {
  await mount();
  await click(button('Add Promotion'));
  assert.equal(everyStoreBox().checked, true, 'a new promotion is priced at every store');
  await setValue(nameInput(), 'XP New');
  await setValue(modal().querySelector('input[placeholder="e.g. BUNDLE1"]'), 'XPNEW');
  await setValue(priceInput(), '88');
  backend.failPriceOnce = true;
  await click(button('Save & Add Items', modal()));
  assert.ok(modal().textContent.includes('Saved, but the store prices could not be set: the price step failed. Press Save to try the prices again.'),
    modal().textContent.slice(0, 400));
  assert.ok(button('Save', modal()), 'the window did not switch to editing the saved promotion');
  await click(button('Save', modal()));
  const inserts = backend.calls.filter(c => c.name === 'promotions' && c.op === 'insert');
  const updates = backend.calls.filter(c => c.name === 'promotions' && c.op === 'update');
  assert.equal(inserts.length, 1, 'Save again made a second promotion');
  assert.equal(updates.length, 1);
  assert.equal(priceCalls().length, 2, 'the prices were not tried again');
  assert.deepEqual(priceCalls()[1].args, { p_promotion_id: 'new-1', p_price: 88, p_available: null });
});

test('a code already used by a live promotion is said in words', async () => {
  await mount();
  await click(button('Add Promotion'));
  await setValue(nameInput(), 'XP Copy');
  await setValue(modal().querySelector('input[placeholder="e.g. BUNDLE1"]'), 'xplive');
  backend.insertError = { code: '23505', message: 'duplicate key value violates unique constraint "promotions_code_live_key"' };
  await click(button('Save & Add Items', modal()));
  assert.ok(modal().textContent.includes('This code is already used by another promotion. Choose another code.'));
  assert.ok(!modal().textContent.includes('duplicate key'));
});

test('removals are confirmed by name, and a refusal is shown', async () => {
  await mount();
  await click([...row('XP Live').querySelectorAll('button')].find(b => b.textContent.includes('Items')));
  assert.ok(modal().textContent.includes('Original, with the base choice'), 'the Original does not say it counts the base choice');
  // a choice group used in sales cannot go
  backend.deleteError['g-1'] = { code: '23503', message: 'update or delete on table "promotion_choice_groups" violates foreign key constraint' };
  await click(modal().querySelector('button[title="Remove this choice group"]'));
  assert.match(confirms.at(-1), /^Remove the choice group "Pick one" and its options\?/);
  assert.match(confirms.at(-1), /This promotion is in 3 past sales\. Those sales keep what they sold/);
  assert.ok(modal().textContent.includes('The choice group "Pick one" was used in past sales, so it cannot be removed. Switch this promotion off and create a new one instead.'),
    modal().textContent.slice(0, 600));
  // an item the database did not remove (no rights, or already gone)
  backend.deleteNothing['pi-1'] = true;
  await click(modal().querySelector('button[title="Remove this item"]'));
  assert.match(confirms.at(-1), /^Remove "📦 XP A" from this promotion\?/);
  assert.ok(modal().textContent.includes('"📦 XP A" was not removed. Refresh and try again.'));
  // an option goes, after asking, and on a sold promotion the question warns
  // about past sales, as for a group or an item
  await click(modal().querySelector('[aria-label="Remove this option"]'));
  assert.match(confirms.at(-1), /^Remove "XP A" from the choices in "Pick one"\?/);
  assert.match(confirms.at(-1), /This promotion is in 3 past sales\. Those sales keep what they sold; from now on it is sold without this\./);
  assert.ok(backend.calls.some(c => c.name === 'promotion_choice_options' && c.op === 'delete'));
});

test('a promotion that could not be deleted says so', async () => {
  await mount();
  backend.client.from = (orig => name => {
    const q = orig(name);
    if (name === 'promotions') {
      const upd = q.update.bind(q);
      q.update = row => { upd(row); if (row.deleted_at) q.exec = async () => ({ data: null, error: { message: 'permission denied' } }); return q; };
    }
    return q;
  })(backend.client.from);
  await click(row('XP Off').querySelector('.btn-danger'));
  assert.ok(text().includes('"XP Off" was not deleted: permission denied'));
});

test('a choice group added in the builder can be based on its dearest option', async () => {
  await mount();
  await click([...row('XP Live').querySelectorAll('button')].find(b => b.textContent.includes('Items')));
  await setValue(modal().querySelector('input[placeholder^="Group label"]'), 'Pick a colour');
  const base = [...modal().querySelectorAll('select')].find(sel => sel.title === 'Which option sets the base price');
  assert.ok(base, 'the builder offers no base choice for a products group');
  await setValue(base, 'highest');
  await click([...modal().querySelectorAll('button')].find(b => b.textContent.trim() === 'Group'));
  const ins = backend.calls.filter(c => c.name === 'promotion_choice_groups' && c.op === 'insert').at(-1);
  assert.equal(ins?.row?.base_mode, 'highest');
  assert.equal(ins?.row?.label, 'Pick a colour');
});

test('a new promotion says whether the stores get its price, and unticked none is set', async () => {
  await mount();
  await click(button('Add Promotion'));
  const hint = () => everyStoreBox().closest('.form-group').textContent;
  assert.ok(hint().includes('Every store sells it at this price. Use Prices to set one store differently.'));
  await click(everyStoreBox());
  assert.equal(everyStoreBox().checked, false);
  assert.ok(hint().includes('No store sells it until you set a price under Prices.'), hint());
  assert.ok(!hint().includes('Every store sells it'), 'the hint still says every store sells it');
  await setValue(nameInput(), 'XP Unpriced');
  await setValue(modal().querySelector('input[placeholder="e.g. BUNDLE1"]'), 'XPUNP');
  await setValue(priceInput(), '77');
  await click(button('Save & Add Items', modal()));
  assert.equal(priceCalls().length, 0, 'an unticked new promotion was priced at every store');
  assert.equal(backend.calls.filter(c => c.name === 'promotions' && c.op === 'insert').length, 1);
});

test('only a products group saves its dearest base, and the base is cleared for the next group', async () => {
  // the Add window
  await mount();
  await click(button('Add Promotion'));
  const kindSel = () => [...modal().querySelectorAll('select')].find(sel => [...sel.options].some(o => o.textContent === 'Vouchers'));
  const newBase = () => [...modal().querySelectorAll('select')].find(sel => sel.title === 'Which option sets the base price');
  const label = () => modal().querySelector('input[placeholder^="Group label"]');
  const addGroupButton = () => [...modal().querySelectorAll('button')].find(b => b.textContent.trim() === 'Group');
  await setValue(label(), 'Pick a product');
  await setValue(newBase(), 'highest');
  await click(addGroupButton());
  assert.equal(newBase().value, 'cheapest', 'the next group starts at the dearest base');
  await setValue(newBase(), 'highest');
  await setValue(kindSel(), 'voucher');
  assert.equal(newBase(), undefined, 'a vouchers group offers a base choice');
  await setValue(label(), 'Pick a voucher');
  await click(addGroupButton());
  await setValue(nameInput(), 'XP Groups');
  await setValue(modal().querySelector('input[placeholder="e.g. BUNDLE1"]'), 'XPGRP');
  await click(button('Save & Add Items', modal()));
  const saved = backend.calls.filter(c => c.name === 'promotion_choice_groups' && c.op === 'insert').map(c => [c.row.label, c.row.item_kind, c.row.base_mode]);
  assert.deepEqual(saved, [['Pick a product', 'product', 'highest'], ['Pick a voucher', 'voucher', 'cheapest']]);

  // the builder
  await mount();
  await click([...row('XP Live').querySelectorAll('button')].find(b => b.textContent.includes('Items')));
  await setValue(label(), 'Pick a colour');
  await setValue(newBase(), 'highest');
  await click(addGroupButton());
  assert.equal(newBase().value, 'cheapest', 'after a group is added the base is not cleared');
  await setValue(newBase(), 'highest');
  await setValue(kindSel(), 'voucher');
  await setValue(label(), 'Pick a voucher');
  await click(addGroupButton());
  const ins = backend.calls.filter(c => c.name === 'promotion_choice_groups' && c.op === 'insert').map(c => [c.row.label, c.row.item_kind, c.row.base_mode]);
  assert.deepEqual(ins, [['Pick a colour', 'product', 'highest'], ['Pick a voucher', 'voucher', 'cheapest']]);
});
