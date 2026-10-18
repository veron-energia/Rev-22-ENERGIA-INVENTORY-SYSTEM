// The Reconciliation tab's "Mark reviewed" button (427; the Owner, 18 Oct
// 2026, W4-B13-MARK-REVIEWED, rule (a)): a settled TikTok line with no
// imported order can be marked as needing no stock taken off, with a reason,
// by an Owner at any store and by a Manager at a store they work at. It calls
// review_tiktok_settlement_without_order(uuid[], text), which checks the same
// again, and the list is read again after saving.
//
// The actual src/pages/TikTokImportPage.tsx is bundled with esbuild and
// mounted in jsdom. Only the Supabase client and the auth context are
// stubbed: the client by a small in-memory backend that answers as 427 does.
// Every store, order and id below is invented.
//
// Run: node --test scripts/tiktok/tests/mark-reviewed.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://tiktok.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'Element', 'Node', 'Event',
  'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
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

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as TikTokImportPage } from './src/pages/TikTokImportPage';
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
    b.onResolve({ filter: /(^|\/)lib\/supabase$|^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { TikTokImportPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const NORTH = 'st-north', SOUTH = 'st-south';
const STORES = [
  { id: NORTH, name: 'North Store', deleted_at: null, is_active: true },
  { id: SOUTH, name: 'South Store', deleted_at: null, is_active: true },
];
// The Reconciliation tab's rows, as 427's report_tiktok_recon_exceptions
// returns them: each names its store, and a settlement line its id.
const LINES = [
  { kind: 'order_without_settlement', store_name: 'North Store', order_id: 'ORD-100', detail: 'net deducted 1 unit(s)', amount: null, store_id: NORTH, settlement_row_id: null },
  { kind: 'reconciliation_difference', store_name: 'North Store', order_id: 'ORD-900', detail: 'settlement 9 vs revenue+fees 8', amount: 1, store_id: NORTH, settlement_row_id: 'sw-9' },
  { kind: 'settlement_without_order', store_name: 'North Store', order_id: 'ORD-201', detail: 'Order', amount: 10.5, store_id: NORTH, settlement_row_id: 'sw-1' },
  { kind: 'settlement_without_order', store_name: 'North Store', order_id: 'ORD-201', detail: 'Order', amount: 4.25, store_id: NORTH, settlement_row_id: 'sw-2' },
  { kind: 'settlement_without_order', store_name: 'South Store', order_id: 'ORD-301', detail: 'Order', amount: 7, store_id: SOUTH, settlement_row_id: 'sw-3' },
];

// ── fake backend ───────────────────────────────────────────────────────────
function createBackend({ lines = LINES } = {}) {
  const b = { calls: [], failures: new Map(), reviewed: new Set(), lines };
  const tables = { stores: STORES, products: [], vouchers: [], promotions: [], tiktok_status_mappings: [], tiktok_physical_returns: [] };
  const rpcs = {
    my_assigned_store_id: () => null,
    my_assigned_stores: () => (globalThis.__auth.assignments ?? [])
      .map((x, i) => ({ store_id: x.store_id, store_name: STORES.find(s => s.id === x.store_id)?.name, is_default: i === 0 })),
    report_tiktok_imports: () => [],
    report_tiktok_recon_exceptions: a => b.lines
      .filter(r => !(r.kind === 'settlement_without_order' && b.reviewed.has(r.settlement_row_id)))
      .filter(r => !a?.p_store_id || r.store_id === a.p_store_id),
    // As 427: Owners and Managers only; a Manager only at a store they work
    // at; a reason; a line already reviewed is left as it was.
    review_tiktok_settlement_without_order: a => {
      const role = globalThis.__auth.profile.role;
      const mine = new Set((globalThis.__auth.assignments ?? []).map(x => x.store_id));
      if (!['owner', 'manager'].includes(role)) throw Object.assign(new Error('Only active Owners and Managers can mark a TikTok settlement as needing no stock taken off.'), { code: '42501' });
      if (!String(a.p_reason ?? '').trim()) throw new Error('A reason is required: say why no stock is to be taken off.');
      const ids = [...new Set(a.p_row_ids)];
      for (const id of ids) {
        const line = b.lines.find(r => r.settlement_row_id === id && r.kind === 'settlement_without_order');
        if (!line) throw new Error('A settlement line was not found. Refresh and try again.');
        if (role === 'manager' && !mine.has(line.store_id)) throw Object.assign(new Error('That settlement line belongs to a store you are not assigned to.'), { code: '42501' });
      }
      const fresh = ids.filter(id => !b.reviewed.has(id));
      fresh.forEach(id => b.reviewed.add(id));
      return { reviewed: fresh.length, already_reviewed: ids.length - fresh.length };
    },
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], rangeV: null, one: false }); }
    select() { return this; }
    is(col, v) { this.filters.push(r => (r[col] ?? null) === v); return this; }
    eq(col, v) { this.filters.push(r => r[col] === v); return this; }
    in(col, vs) { this.filters.push(r => vs.includes(r[col])); return this; }
    order() { return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    single() { this.one = true; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args });
      await Promise.resolve();
      if (b.failures.has(this.name)) return { data: null, error: { code: 'XX000', message: b.failures.get(this.name) } };
      let src;
      try {
        src = this.kind === 'table' ? tables[this.name] : rpcs[this.name]?.(this.args);
      } catch (e) { return { data: null, error: { code: e.code ?? 'P0001', message: e.message } }; }
      if (src === undefined) return { data: null, error: { code: 'PGRST202', message: `unknown ${this.kind} ${this.name}` } };
      if (!Array.isArray(src)) return { data: src, error: null };
      let rows = src.filter(r => this.filters.every(f => f(r)));
      if (this.rangeV) rows = rows.slice(this.rangeV[0], this.rangeV[1] + 1);
      return { data: this.one ? rows[0] ?? null : rows, error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving the page ───────────────────────────────────────────────────────
let root = null;
let backend = null;
let confirms = [];
let confirmAnswer = true;
globalThis.alert = () => {};
globalThis.confirm = msg => { confirms.push(String(msg)); return confirmAnswer; };
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount({ role = 'owner', assignments = [], lines } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend({ lines });
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: { id: 'u-1', full_name: 'Test User', role },
    assignments: assignments.map((s, i) => ({ id: `a-${i}`, user_id: 'u-1', store_id: s, created_at: '2026-01-01T00:00:00Z' })) };
  confirms = []; confirmAnswer = true;
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(TikTokImportPage))));
  await tick();
  assert.ok(!document.getElementById('crashed'), document.getElementById('crashed')?.textContent);
  await click([...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Reconciliation'));
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const callsOf = name => backend.calls.filter(c => c.name === name);
const recon = () => [...document.querySelectorAll('.card')].find(c => c.querySelector('h3')?.textContent === 'Reconciliation');
const text = el => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
// The tick box of each line, keyed by its order and amount, as shown.
const boxes = () => [...recon().querySelectorAll('tbody input[type="checkbox"]')]
  .map(i => text(i.closest('tr').children[3]) + ' ' + text(i.closest('tr').children[5]));
const boxFor = (order, amount) => [...recon().querySelectorAll('tbody input[type="checkbox"]')]
  .find(i => text(i.closest('tr').children[3]) === order && text(i.closest('tr').children[5]) === amount);
const markButton = () => [...recon().querySelectorAll('button')].find(x => /Mark reviewed|Saving/.test(x.textContent));
async function tickBox(el) { await click(el); }
async function setValue(el, value) {
  await act(async () => {
    Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
  });
  await tick();
}
const reason = () => recon().querySelector('#review-reason');
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
test('an Owner ticks settled lines with no imported order, at any store, gives a reason and marks them reviewed; the list is read again', async () => {
  await mount({ role: 'owner' });
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.deepEqual(boxes(), ['ORD-201 10.50', 'ORD-201 4.25', 'ORD-301 7.00'],
    'a tick box on each settlement without order, both stores; none on the other kinds of exception');
  assert.ok(markButton().disabled, 'nothing ticked, no reason: the button waits');
  assert.match(text(recon().querySelector('[data-testid="mark-reviewed"]')), /no order file brought their order in, so their stock was never taken off/);

  await tickBox(boxFor('ORD-201', '10.50'));
  await tickBox(boxFor('ORD-301', '7.00'));
  assert.ok(markButton().disabled, 'still no reason');
  await setValue(reason(), '   ');
  assert.ok(markButton().disabled, 'a reason of spaces is no reason');
  await setValue(reason(), '  Sold before the app tracked TikTok stock  ');
  assert.match(text(recon()), /2 selected · S\$17\.50/);
  assert.equal(markButton().disabled, false);
  const reads = callsOf('report_tiktok_recon_exceptions').length;

  await click(markButton());
  assert.equal(confirms.length, 1);
  assert.match(confirms[0], /Mark 2 settled lines as reviewed\? No stock will be taken off for them, and this cannot be undone\./);
  const calls = callsOf('review_tiktok_settlement_without_order');
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].args, { p_row_ids: ['sw-1', 'sw-3'], p_reason: 'Sold before the app tracked TikTok stock' });
  assert.equal(callsOf('report_tiktok_recon_exceptions').length, reads + 1, 'the list is read again after saving');
  assert.equal(text(document.querySelector('[data-testid="review-note"]')), 'Marked reviewed: 2 lines. No stock was taken off.');
  assert.deepEqual(boxes(), ['ORD-201 4.25'], 'the reviewed lines have left the list');
  assert.equal(reason().value, '', 'the reason is cleared');
  assert.ok(markButton().disabled, 'and nothing is ticked');
  assert.ok(text(recon()).includes('ORD-900') && text(recon()).includes('ORD-100'), 'the other exceptions stay');
});

test('a Manager gets tick boxes only on the lines of the stores they work at; Tick all ticks only those', async () => {
  await mount({ role: 'manager', assignments: [NORTH] });
  assert.deepEqual(boxes(), ['ORD-201 10.50', 'ORD-201 4.25'], 'North lines only, not South\'s');
  const all = recon().querySelector('thead input[type="checkbox"]');
  assert.equal(all.getAttribute('aria-label'), 'Tick every line to mark reviewed');
  await tickBox(all);
  await setValue(reason(), 'Covered by the September stock count');
  assert.match(text(recon()), /2 selected · S\$14\.75/);
  await click(markButton());
  assert.deepEqual(callsOf('review_tiktok_settlement_without_order')[0].args.p_row_ids, ['sw-1', 'sw-2']);
  assert.deepEqual(boxes(), [], 'both reviewed');
  assert.equal(recon().querySelector('[data-testid="mark-reviewed"]'), null, 'no button once nothing is left to review here');
  assert.match(text(recon().querySelector('[data-testid="mark-reviewed-who"]')), /an Owner, or by a Manager at its store/,
    'South\'s line is still listed, with who can mark it');
});

test('a Manager at no store, an Admin, an Inventory Manager and Staff get no tick box and no button; they are told who can', async () => {
  for (const [role, assignments] of [['manager', []], ['admin', [NORTH, SOUTH]], ['inventory_manager', [NORTH]], ['staff', [NORTH]]]) {
    await mount({ role, assignments });
    assert.deepEqual(globalThis.__renderErrors, [], role);
    assert.deepEqual(boxes(), [], `${role}: no tick box`);
    assert.equal(markButton(), undefined, `${role}: no button`);
    assert.match(text(recon().querySelector('[data-testid="mark-reviewed-who"]')),
      /can be marked reviewed by an Owner, or by a Manager at its store/, `${role}: told who can`);
    assert.equal(callsOf('review_tiktok_settlement_without_order').length, 0);
  }
});

test('a refusal is shown with the server\'s reason; the ticks and the reason stay, and nothing leaves the list', async () => {
  await mount({ role: 'manager', assignments: [NORTH] });
  await tickBox(boxFor('ORD-201', '10.50'));
  await setValue(reason(), 'Sold before tracking');
  // The Manager's store assignment ended after the page loaded: the server
  // checks the store again and refuses.
  backend.failures.set('review_tiktok_settlement_without_order', 'That settlement line belongs to a store you are not assigned to.');
  await click(markButton());
  assert.equal(text(document.querySelector('[data-testid="review-error"]')),
    'Not marked reviewed: That settlement line belongs to a store you are not assigned to.');
  assert.equal(document.querySelector('[data-testid="review-note"]'), null);
  assert.equal(reason().value, 'Sold before tracking');
  assert.equal(boxFor('ORD-201', '10.50').checked, true);
  assert.equal(backend.reviewed.size, 0);
});

test('saying No to the question saves nothing', async () => {
  await mount({ role: 'owner' });
  await tickBox(boxFor('ORD-301', '7.00'));
  await setValue(reason(), 'x');
  confirmAnswer = false;
  await click(markButton());
  assert.equal(confirms.length, 1);
  assert.match(confirms[0], /Mark 1 settled line as reviewed\? No stock will be taken off for it/);
  assert.equal(callsOf('review_tiktok_settlement_without_order').length, 0);
  assert.equal(boxFor('ORD-301', '7.00').checked, true, 'still ticked');
});

test('a line already reviewed elsewhere is said, not counted twice', async () => {
  await mount({ role: 'owner' });
  await tickBox(boxFor('ORD-201', '10.50'));
  await tickBox(boxFor('ORD-201', '4.25'));
  await setValue(reason(), 'Sold before tracking');
  backend.reviewed.add('sw-2');   // another Owner reviewed it a moment ago
  await click(markButton());
  assert.equal(text(document.querySelector('[data-testid="review-note"]')),
    'Marked reviewed: 1 line. 1 had already been reviewed. No stock was taken off.');
});

test('a database before 427 sends no line id: nothing is offered and nothing is said', async () => {
  const old = LINES.map(({ store_id, settlement_row_id, ...r }) => r);
  await mount({ role: 'owner', lines: old });
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.equal(recon().querySelectorAll('tbody tr').length, 5, 'the exceptions still show');
  assert.deepEqual(boxes(), []);
  assert.equal(markButton(), undefined);
  assert.equal(recon().querySelector('[data-testid="mark-reviewed-who"]'), null);
});

test('at 375 px: the table scrolls inside its own box, and the reason, the total and the button wrap', async () => {
  await mount({ role: 'owner' });
  const wrap = recon().querySelector('table').closest('.table-wrap');
  assert.ok(wrap, 'the table is inside .table-wrap (overflow-x: auto), so the page itself does not scroll sideways');
  const row = reason().closest('div').parentElement;
  assert.equal(row.style.flexWrap, 'wrap', 'the controls wrap onto new lines on a phone');
  assert.equal(reason().closest('div').style.minWidth, '0px', 'the reason box may shrink below its basis');
  assert.equal(reason().getAttribute('maxlength'), '2000', 'the server\'s limit');
  assert.equal(recon().querySelector('label[for="review-reason"]').textContent.replace(/\s+/g, ' ').trim(), 'Reason *');
});
