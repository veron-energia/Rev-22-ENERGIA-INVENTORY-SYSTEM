// The invoice list stays current: after every save, after another user or
// tab changes something, after the tab comes back, and when the realtime
// channel is not there. The real page, driven the way a person drives it,
// against an in-memory database shared between tabs; no network, no
// credentials, no timers left running.
//
// Usage: node scripts/invoices/tests/list-refresh-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

// ---------------------------------------------------------------------------
// Fixtures. Invoice n is INV-000n; created a minute apart so the default sort
// (newest first) is stable.
// ---------------------------------------------------------------------------
const T0 = Date.parse('2026-09-01T01:00:00Z');
const common = { is_active: true, deleted_at: null };
const owner = { id: 'owner', full_name: 'Test Owner', role: 'owner', ...common };
const staff = { id: 'staff', full_name: 'Test Staff', role: 'staff', ...common };
const inv = (n, over = {}) => ({
  id: `inv${n}`, invoice_no: `INV-${String(n).padStart(4, '0')}`, store_id: 'store', customer_id: 'c1',
  subtotal: 100, total_amount: 100, paid_amount: 0, discount_total: 0, manual_discount: 0, status: 'unpaid',
  created_at: new Date(T0 + n * 60_000).toISOString(), business_date: '2026-09-01', created_by: 'owner',
  edit_count: 0, notes: null, ...common, ...over,
});
const item = (n, qty = 1) => ({ id: `item${n}`, invoice_id: `inv${n}`, line_kind: 'product', product_id: 'socks',
  quantity: qty, unit_price: 100, line_total: 100 * qty, topup_amount: 0, foc_quantity: 0 });
const receipt = (n, method, amount, k = '') => ({ id: `pay${n}${k}`, invoice_id: `inv${n}`, payment_method_id: method,
  amount, created_at: new Date(T0 + n * 60_000).toISOString(), effective_at: new Date(T0 + n * 60_000).toISOString(), entry_kind: 'receipt' });
const paid = (n, method = 'cash', over = {}) => inv(n, { status: 'paid', paid_amount: 100, paid_at: new Date(T0 + n * 60_000).toISOString(), ...over });

const baseTables = () => ({
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }, { id: 'other', name: 'Other Store', code: 'OTH', ...common }],
  customers: [{ id: 'c1', full_name: 'Ann Buyer', phone: '+6591234567', ...common }, { id: 'c2', full_name: 'Ben Buyer', phone: '+6591234568', ...common }],
  profiles: [owner, staff],
  products: [{ id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common }],
  store_product_prices: [{ store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, non_member_price: 100, availability: 'available', ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }, { id: 'bank', name: 'Bank Transfer', ...common }],
  promotions: [], promotion_store_prices: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_promotion_selections: [], invoice_revisions: [], invoice_service_staff: [], warehouses: [],
  vouchers: [], voucher_store_prices: [], special_products: [], therapy_package_rules: [], unlimited_therapy_packages: [],
  unlimited_therapy_store_prices: [], therapy_services: [], therapy_service_stores: [],
});

/** The everyday set: a mix of paid and unpaid, one in a store the staff member cannot see. */
const everyday = () => ({
  ...baseTables(),
  invoices: [paid(1), inv(2), inv(3), paid(4, 'bank', { subtotal: 200, total_amount: 200, paid_amount: 200 }), paid(5, 'cash', { store_id: 'other' }),
    paid(6), paid(7), paid(8), paid(9), paid(10), paid(11), paid(12)],
  invoice_items: [item(1), item(2), item(3), item(4, 2), item(5), item(6), item(7), item(8), item(9), item(10), item(11), item(12)],
  invoice_payments: [receipt(1, 'cash', 100), receipt(4, 'bank', 200), receipt(5, 'cash', 100), receipt(6, 'cash', 100), receipt(7, 'cash', 100),
    receipt(8, 'cash', 100), receipt(9, 'cash', 100), receipt(10, 'cash', 100), receipt(11, 'cash', 100), receipt(12, 'cash', 100)],
});
/** Twenty-six paid invoices: page two of the Paid filter holds exactly one row. */
const twentySix = () => {
  const t = baseTables();
  const ns = Array.from({ length: 26 }, (_, i) => i + 20);
  t.invoices = ns.map(n => paid(n)); t.invoice_items = ns.map(n => item(n)); t.invoice_payments = ns.map(n => receipt(n, 'cash', 100));
  return t;
};

// ---------------------------------------------------------------------------
// The stand-in for the Supabase client. The database lives in localStorage so
// two tabs of one browser share it, the way two tabs share one server.
// ---------------------------------------------------------------------------
const mock = `export const supabase = (() => {
  const db = () => JSON.parse(localStorage.getItem('__db') || '{}');
  const save = t => localStorage.setItem('__db', JSON.stringify(t));
  const calls = (window.__calls = window.__calls || []);
  const err = m => ({ data: null, error: { message: m } });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const thenable = p => { const q = new Proxy({}, { get(_, k) { if (k === 'then') return (ok, bad) => p.then(ok, bad); return () => q; } }); return q; };
  function from(table) {
    let rows = [...(db()[table] || [])], one = false;
    if (table === 'invoice_payments') { const ms = db().payment_methods || []; rows = rows.map(p => ({ ...p, payment_methods: { name: ms.find(m => m.id === p.payment_method_id)?.name ?? null } })); }
    const q = new Proxy({}, { get(_, key) {
      if (key === 'then') return (ok, bad) => Promise.resolve().then(() => {
        calls.push({ name: 'from:' + table, at: Date.now() });
        if (window.__failInvoiceReload && table === 'invoices' && one) return err('Network error while reloading the invoice');
        return { data: one ? (rows[0] || null) : rows, error: null };
      }).then(async r => { if (window.__detailDelay && table === 'invoices' && one) await sleep(window.__detailDelay); return r; }).then(ok, bad);
      return (...a) => { if (key === 'eq') rows = rows.filter(r => r[a[0]] === a[1]); if (key === 'in') rows = rows.filter(r => a[1].includes(r[a[0]]));
        if (key === 'is') rows = rows.filter(r => r[a[0]] === a[1]); if (key === 'single' || key === 'maybeSingle') one = true; return q; };
    } });
    return q;
  }
  const finance = i => { const p = Number(i.paid_amount || 0), t = Number(i.total_amount || 0);
    return { total: t, net_received: p, outstanding: Math.max(0, t - p), refund_due: Math.max(0, p - t), refunded: Number(i.refunded || 0), status: i.status }; };
  const touch = (id, patch, bump = false) => { const t = db(); t.invoices = t.invoices.map(i => i.id === id ? { ...i, ...patch, edit_count: (i.edit_count || 0) + (bump ? 1 : 0) } : i); save(t); };
  const requests = (window.__requests = window.__requests || {});
  async function rpcImpl(name, args) {
    calls.push({ name, args, at: Date.now() });
    const t = db();
    const find = id => t.invoices.find(i => i.id === id);
    switch (name) {
      case 'invoice_list_page': {
        if (window.__listDelays && window.__listDelays.length) { const d = window.__listDelays.shift(); await sleep(d); }
        if (window.__failList) return err('Server unavailable (test)');
        const allowed = window.__profile.role === 'staff' ? window.__accessibleStores : null;
        let rows = t.invoices.filter(i => !i.deleted_at && (!allowed || allowed.includes(i.store_id)));
        if (args.p_status) rows = rows.filter(i => i.status === args.p_status);
        if (args.p_search) { const q = args.p_search.toLowerCase(); rows = rows.filter(i => i.invoice_no.toLowerCase().includes(q) || (t.customers.find(c => c.id === i.customer_id)?.full_name || '').toLowerCase().includes(q)); }
        if (args.p_date_from) rows = rows.filter(i => i.business_date && i.business_date >= args.p_date_from);
        if (args.p_date_to) rows = rows.filter(i => i.business_date && i.business_date <= args.p_date_to);
        const dir = args.p_sort_dir === 'asc' ? 1 : -1;
        const f = args.p_sort_field === 'invoice_no' ? 'invoice_no' : args.p_sort_field === 'total' ? 'total_amount' : args.p_sort_field === 'business_date' ? 'business_date' : 'created_at';
        rows.sort((a, b) => a[f] < b[f] ? -dir : a[f] > b[f] ? dir : 0);
        const total = rows.length, pages = Math.ceil(total / args.p_limit);
        const page = rows.slice(args.p_offset, args.p_offset + args.p_limit).map(i => ({ ...i, customer_name: t.customers.find(c => c.id === i.customer_id)?.full_name ?? null }));
        const sum = k => rows.reduce((s, i) => s + Number(i[k] || 0), 0);
        return { data: { rows: page, total, pages, summary: { matching: total, total_amount: sum('total_amount'), outstanding: rows.reduce((s, i) => s + Math.max(0, Number(i.total_amount) - Number(i.paid_amount || 0)), 0), paid: sum('paid_amount') } }, error: null };
      }
      case 'invoice_financial_position': return { data: finance(find(args.p_invoice_id)), error: null };
      case 'invoice_refund_options': { const i = find(args.p_invoice_id); return { data: { financial: finance(i), sources: [], stock: [], benefits: [], lines: [], review_required: false }, error: null }; }
      case 'invoice_action_plan': { const i = find(args.p_invoice_id); const lines = t.invoice_items.filter(x => x.invoice_id === i.id);
        const chosen = (args.p_lines || []); const qtyOf = l => chosen.find(c => c.invoice_item_id === l.id)?.quantity ?? l.quantity;
        const amount = args.p_action === 'cancel' ? Number(i.paid_amount) : lines.reduce((s, l) => s + 100 * qtyOf(l), 0);
        return { data: { invoice_no: i.invoice_no, action: args.p_action, refund_amount: amount, refund_due: args.p_action === 'cancel' ? Number(i.paid_amount) : 0,
          window: { created_on: '2026-09-01', deadline: '2026-09-06', within: true, days_remaining: 3, override_required: false, creation_reliable: true },
          lines: lines.map(l => ({ invoice_item_id: l.id, name: 'Long Energia Socks', line_kind: 'product', quantity: l.quantity, selected_quantity: qtyOf(l), amount: 100 * qtyOf(l) })),
          stock: [], sources: t.invoice_payments.filter(p => p.invoice_id === i.id).map(p => ({ payment_id: p.id, method: t.payment_methods.find(m => m.id === p.payment_method_id)?.name, wallet: false, amount: Number(p.amount) })),
          overrides_required: [], blockers: [], summary: ['Test plan'], requires_override: false, blocked: false, plan_hash: 'h1', status: i.status }, error: null }; }
      case 'invoice_rentals_awaiting_return': return { data: [], error: null };
      case 'request_invoice_action_v2': { const id = 'req-' + Object.keys(requests).length; requests[id] = { invoice_id: args.p_invoice_id, action: args.p_action, lines: args.p_lines || [] }; return { data: { request_id: id }, error: null }; }
      case 'resolve_invoice_action_v2': { const r = requests[args.p_request_id]; const i = find(r.invoice_id);
        if (window.__mutationDelay) await sleep(window.__mutationDelay);
        if (r.action === 'cancel') { touch(i.id, { status: 'cancelled' }, true); return { data: { cancellation: true, refund_still_due: Number(i.paid_amount) }, error: null }; }
        const amt = r.action === 'refund_full' ? Number(i.paid_amount) : r.lines.reduce((s, l) => s + 100 * Number(l.quantity), 0);
        const left = Number(i.paid_amount) - amt;
        touch(i.id, { paid_amount: left, refunded: Number(i.refunded || 0) + amt, status: left <= 0 ? 'refunded' : i.status }, true);
        return { data: { refund_recorded: true, refunded_amount: amt }, error: null }; }
      case 'record_invoice_settlement': { const i = find(args.p_invoice_id); const rs = args.p_payload?.receipts || [];
        const taken = rs.reduce((s, r) => s + Number(r.amount || 0), 0); const p = Number(i.paid_amount || 0) + taken; const settled = p >= Number(i.total_amount) - 0.001;
        for (const r of rs) t.invoice_payments.push({ id: 'pay-' + Math.random().toString(36).slice(2), invoice_id: i.id, payment_method_id: r.payment_method_id, amount: Number(r.amount), created_at: new Date().toISOString(), effective_at: new Date().toISOString(), entry_kind: 'receipt' });
        save(t); touch(i.id, { paid_amount: p, status: settled ? 'paid' : 'partially_paid', paid_at: settled ? new Date().toISOString() : i.paid_at });
        return { data: { success: true, status: settled ? 'paid' : 'partially_paid' }, error: null }; }
      case 'preview_invoice_correction': { const i = find(args.p_invoice_id); return { data: { invoice_no: i.invoice_no, status: i.status, edit_count: i.edit_count, effects: [], needs_review: [], blocking: false, affiliate: {} }, error: null }; }
      case 'correct_invoice': { const i = find(args.p_invoice_id); const h = args.p_header || {};
        if (h.expected_edit_count !== undefined && Number(h.expected_edit_count) !== Number(i.edit_count || 0)) return err('This invoice was changed by another user. Reload it before saving.');
        const patch = {}; if (h.customer_id) patch.customer_id = h.customer_id; if (h.business_date) patch.business_date = h.business_date; if (h.notes !== undefined) patch.notes = h.notes;
        for (const pm of (h.payment_methods || [])) t.invoice_payments = t.invoice_payments.map(p => p.id === pm.payment_id ? { ...p, payment_method_id: pm.payment_method_id } : p);
        save(t); touch(i.id, patch, true); return { data: { success: true, revision: 1 }, error: null }; }
      case 'create_invoice_with_details': { const n = t.invoices.length + 1; const id = 'new' + n;
        t.invoices.push({ id, invoice_no: 'INV-NEW-' + n, store_id: args.p_store_id, customer_id: args.p_customer_id, status: 'unpaid', subtotal: 100, total_amount: 100, paid_amount: 0, discount_total: 0, manual_discount: 0,
          created_at: new Date().toISOString(), business_date: args.p_header?.business_date || '2026-09-02', created_by: 'owner', edit_count: 0, is_active: true, deleted_at: null, notes: args.p_header?.notes || null });
        t.invoice_items.push({ id: 'item-' + id, invoice_id: id, line_kind: 'product', product_id: 'socks', quantity: 1, unit_price: 100, line_total: 100, topup_amount: 0, foc_quantity: 0 });
        save(t); return { data: id, error: null }; }
      case 'delete_invoice': touch(args.p_invoice_id, { deleted_at: new Date().toISOString() }); return { data: null, error: null };
      case 'correct_invoice_payment': { const pay = t.invoice_payments.find(x => x.id === args.p_payment_id); const i = find(pay.invoice_id);
        const p = Number(i.paid_amount) - Number(pay.amount) + Number(args.p_amount);
        t.invoice_payments = t.invoice_payments.map(x => x.id === pay.id ? { ...x, amount: Number(args.p_amount), payment_method_id: args.p_method_id, effective_at: args.p_date + 'T04:00:00Z' } : x);
        save(t); touch(i.id, { paid_amount: p, status: p >= Number(i.total_amount) - 0.001 ? 'paid' : p > 0 ? 'partially_paid' : 'unpaid' });
        return { data: { success: true }, error: null }; }
      case 'invoice_reopen_preview': { const i = find(args.p_invoice_id); return { data: { can_reopen: true, explanation: 'Test reopen', total: i.total_amount, net_received: i.paid_amount, blockers: [] }, error: null }; }
      case 'reopen_invoice': { const i = find(args.p_invoice_id); const p = Number(i.paid_amount);
        touch(i.id, { status: p >= Number(i.total_amount) - 0.001 ? 'paid' : p > 0 ? 'partially_paid' : 'unpaid' }, true); return { data: { success: true }, error: null }; }
      case 'active_affiliates_for_picker': return { data: [{ affiliate_id: 'aff1', customer_id: 'c2', full_name: 'Ben Buyer', phone: '+6591234568', store_id: 'store' }], error: null };
      case 'set_invoice_affiliate': touch(args.p_invoice_id, { affiliate_id: args.p_affiliate_id, affiliate_selection_explicit: true }); return { data: { success: true, affiliate_id: args.p_affiliate_id }, error: null };
      case 'invoice_effective_affiliate': return { data: { found: true, has_affiliate: false }, error: null };
      case 'customer_search': return { data: t.customers, error: null };
      case 'invoice_benefit_review_options': return { data: { lines: [] }, error: null };
      case 'invoice_transferable_benefits': return { data: [], error: null };
      case 'my_assigned_store_id': return { data: window.__profile.role === 'staff' ? 'store' : null, error: null };
      case 'my_assigned_stores': return { data: window.__profile.role === 'staff' ? [{ store_id: 'store', store_name: 'Test Store', is_default: true }] : [], error: null };
      default: return { data: [], error: null };
    }
  }
  const rpc = (name, args) => thenable(rpcImpl(name, args));
  // Realtime: bindings and status callbacks the test drives by hand.
  const channels = (window.__channels = window.__channels || {});
  window.__emit = (table, payload) => { for (const ch of Object.values(channels)) if (!ch.removed) for (const b of ch.bindings) if (b.filter.table === table) b.cb({ schema: 'public', table, ...payload }); };
  window.__realtime = status => { for (const ch of Object.values(channels)) if (!ch.removed && ch.status) ch.status(status); };
  function channel(name) {
    const ch = { name, bindings: [], removed: false, status: null,
      on(type, filter, cb) { ch.bindings.push({ type, filter, cb }); return ch; },
      subscribe(cb) { ch.status = cb; setTimeout(() => { if (!ch.removed) cb(window.__realtimeDown ? 'CHANNEL_ERROR' : 'SUBSCRIBED'); }, 10); return ch; },
      unsubscribe() { ch.removed = true; return Promise.resolve('ok'); } };
    channels[name] = ch; return ch;
  }
  const removeChannel = ch => { ch.removed = true; window.__removed = (window.__removed || 0) + 1; return Promise.resolve('ok'); };
  return { from, rpc, channel, removeChannel, auth: { getSession: async () => ({ data: { session: { user: { id: window.__profile.id } } } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } };
})();`;

const built = await build({
  stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import InvoicesPage from './src/pages/InvoicesPage';window.__root=createRoot(document.getElementById('root'));window.__root.render(<BrowserRouter><InvoicesPage/></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' },
  bundle: true, define: { 'import.meta.env': '{}' }, format: 'iife', write: false,
  plugins: [{ name: 'isolated-fixtures', setup(b) {
    b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock
      : a.path === 'auth' ? `export const useAuth=()=>({profile:window.__profile,session:{user:{id:window.__profile.id}},assignments:[],loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = built.outputFiles[0].text;
const css = (await readFile('src/styles/globals.css', 'utf8') + '\n' + await readFile('src/components/invoices/invoice-controls.css', 'utf8')).replace(/^@import.*$/gm, '');
const HTML = '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>';

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => { assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`); checks++; console.log(`  ok  ${label}`); };

/** A tab of the invoices page. `seed` writes the shared database; a second tab of the same context passes seed=false. */
async function openTab(context, { seed = null, profile = owner, accessible = ['store'], realtimeDown = false, clock = false, width = 1280 } = {}) {
  const page = await context.newPage();
  await page.setViewportSize({ width, height: 900 });
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/' ? route.fulfill({ contentType: 'text/html', body: HTML }) : route.abort());
  await page.goto('https://invoice.test/');
  if (clock) await page.clock.install({ time: new Date('2026-09-18T02:00:00Z') });
  await page.evaluate(([t, p, a, rd]) => { if (t) localStorage.setItem('__db', JSON.stringify(t)); window.__profile = p; window.__accessibleStores = a; window.__realtimeDown = rd; window.__calls = []; }, [seed, profile, accessible, realtimeDown]);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  if (clock) await page.clock.runFor(50);
  await page.getByRole('button', { name: 'View', exact: true }).first().waitFor();
  return page;
}
/** List rows carry a status badge; rows inside an open invoice's own tables do not. */
const listRows = page => page.locator('tbody tr').filter({ has: page.locator('.badge') });
const row = (page, no) => page.locator('tbody tr').filter({ has: page.getByText(no, { exact: true }) });
const badge = async (page, no) => (await row(page, no).locator('.badge').first().textContent()).trim();
const cell = async (page, no, n) => (await row(page, no).locator('td').nth(n).textContent()).trim();
const listCalls = page => page.evaluate(() => window.__calls.filter(c => c.name === 'invoice_list_page').length);
const rpcCalls = (page, name) => page.evaluate(n => window.__calls.filter(c => c.name === n).length, name);
const dbSet = (page, id, patch) => page.evaluate(([id, patch]) => { const t = JSON.parse(localStorage.getItem('__db')); t.invoices = t.invoices.map(i => i.id === id ? { ...i, ...patch } : i); localStorage.setItem('__db', JSON.stringify(t)); }, [id, patch]);
const dbRow = (page, id) => page.evaluate(id => JSON.parse(localStorage.getItem('__db')).invoices.find(i => i.id === id), id);
const emit = (page, table, payload) => page.evaluate(([t, p]) => window.__emit(t, p), [table, payload]);
const waitBadge = (page, no, text) => page.waitForFunction(([no, text]) => {
  const tr = Array.from(document.querySelectorAll('tbody tr')).find(r => Array.from(r.querySelectorAll('strong')).some(s => s.textContent.trim() === no));
  return tr && tr.querySelector('.badge')?.textContent.trim() === text; }, [no, text]);
const waitGone = (page, no) => page.waitForFunction(no => !Array.from(document.querySelectorAll('tbody tr strong')).some(s => s.textContent.trim() === no), no);
const money = n => `S$${Number(n).toFixed(2)}`;
/** The customer picker searches the server after a pause and re-renders its rows; wait for the row, then choose it. */
async function pickCustomer(page, name) {
  await page.waitForFunction(() => !document.body.textContent.includes('Searching…'));
  const opt = page.locator('div', { hasText: new RegExp(`^${name}$`) }).last();
  await opt.waitFor(); await opt.scrollIntoViewIfNeeded(); await opt.click({ force: true });
  await page.getByRole('button', { name: new RegExp(`^${name}`) }).first().waitFor();
}

/** Open an invoice, cancel it through the guided flow, leave the Done screen and the invoice open. */
async function guidedCancel(page, no, reason = 'Customer changed their mind') {
  await row(page, no).getByRole('button', { name: 'View', exact: true }).click();
  await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).click();
  const dlg = page.getByRole('dialog', { name: /Refund or cancel/ });
  await dlg.getByRole('button', { name: /Cancel invoice/ }).click();
  await dlg.getByPlaceholder('What happened, in a sentence').fill(reason);
  await dlg.getByRole('button', { name: 'Continue', exact: true }).click();
  await dlg.locator('.invoice-guided-foot .btn-primary').last().click();
  await page.getByRole('dialog', { name: 'Done' }).waitFor();
}
async function guidedRefund(page, no, partialQty = null) {
  await row(page, no).getByRole('button', { name: 'View', exact: true }).click();
  await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).click();
  const dlg = page.getByRole('dialog', { name: /Refund or cancel/ });
  if (partialQty === null) await dlg.getByRole('button', { name: /Full refund/ }).click();
  else {
    await dlg.getByRole('button', { name: /Partial refund/ }).click();
    await dlg.getByRole('spinbutton', { name: /Quantity of Long Energia Socks coming back/ }).fill(String(partialQty));
    await dlg.getByRole('button', { name: 'Continue', exact: true }).click();
  }
  await dlg.getByPlaceholder('What happened, in a sentence').fill('Returned in the box');
  await dlg.getByRole('button', { name: 'Continue', exact: true }).click();
  await dlg.locator('.invoice-guided-foot .btn-primary').last().click();
  await page.getByRole('dialog', { name: 'Done' }).waitFor();
}
async function closeAll(page) {
  const done = page.getByRole('dialog', { name: 'Done' });
  if (await done.count()) await done.getByRole('button', { name: 'Close', exact: true }).click();
  const close = page.getByRole('button', { name: 'Close', exact: true });
  if (await close.count()) await close.last().click();
}
async function recordPayment(page, no, amount = null) {
  await row(page, no).getByRole('button', { name: 'View', exact: true }).click();
  await page.getByRole('button', { name: 'Payment method', exact: true }).first().click();
  await page.getByRole('combobox', { name: 'Search payment method' }).fill('cash');
  await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
  if (amount !== null) await page.getByPlaceholder('Amount').first().fill(String(amount));
  await page.getByRole('button', { name: 'Record Payment', exact: true }).click();
}

try {
  for (const width of [1280, 375]) {
    console.log(`\n== width ${width} ==`);
    const context = await browser.newContext();

    // ---- a paid invoice cancelled: All shows Cancelled, without a reload ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      ok('the list opens with the paid invoice shown as Paid', await badge(page, 'INV-0001') === 'Paid');
      const before = await listCalls(page);
      await guidedCancel(page, 'INV-0001');
      await waitBadge(page, 'INV-0001', 'Cancelled');
      ok('cancelling a paid invoice shows Cancelled in the list behind the dialog, with no reload', true);
      ok('exactly one list refresh followed the cancellation', await listCalls(page) === before + 1, `${await listCalls(page) - before} refreshes`);
      ok('the cancellation was sent exactly once', await rpcCalls(page, 'resolve_invoice_action_v2') === 1);
      // Its realtime echo arrives a moment later: already covered, no second refresh.
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv1', status: 'cancelled' }, old: { id: 'inv1' } });
      await page.waitForTimeout(700);
      ok('the realtime echo of this tab\'s own save does not refresh again', await listCalls(page) === before + 1);
      ok('no page errors', page.errors.length === 0, page.errors.join('; '));
      await page.screenshot({ path: `.invoice-test/browser/list-refresh-cancel-${width}.png` });
      await page.close();
    }

    // ---- under the Paid filter, with a search, the cancelled row leaves ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await page.getByPlaceholder(/Search invoice number/).fill('INV-00');
      await page.getByRole('button', { name: 'Paid', exact: true }).click();
      await page.locator('#invoice-page-size').selectOption('50');
      await page.waitForFunction(() => Array.from(document.querySelectorAll('tbody tr .badge')).length > 0 && Array.from(document.querySelectorAll('tbody tr .badge')).every(b => b.textContent.trim() === 'Paid'));
      const matchesBefore = await page.locator('.invoice-paging-count').textContent();
      await guidedCancel(page, 'INV-0006');
      await waitGone(page, 'INV-0006');
      ok('under the Paid filter a cancelled invoice leaves the result', true);
      const matchesAfter = await page.locator('.invoice-paging-count').textContent();
      ok('the match count and totals come from the server, not from the visible rows', matchesBefore !== matchesAfter && /of 9\b/.test(matchesAfter), `${matchesBefore.trim()} → ${matchesAfter.trim()}`);
      ok('the search stayed', await page.getByPlaceholder(/Search invoice number/).inputValue() === 'INV-00');
      ok('the status filter stayed', await page.getByRole('button', { name: 'Paid', exact: true }).evaluate(b => b.classList.contains('btn-primary')));
      ok('the page size stayed', await page.locator('#invoice-page-size').inputValue() === '50');
      await page.close();
    }

    // ---- payments: full, then partial ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await recordPayment(page, 'INV-0002');
      await waitBadge(page, 'INV-0002', 'Paid');
      ok('paying in full shows Paid in the list', true);
      ok('with nothing outstanding', await cell(page, 'INV-0002', 5) === money(0));
      ok('and the payment method label', await cell(page, 'INV-0002', 6) === 'Cash');
      await closeAll(page);
      await recordPayment(page, 'INV-0003', 40);
      await waitBadge(page, 'INV-0003', 'Partially Paid');
      ok('a part payment shows Partially Paid', true);
      ok('with the balance outstanding', await cell(page, 'INV-0003', 5) === money(60));
      ok('each payment was sent exactly once', await rpcCalls(page, 'record_invoice_settlement') === 2);
      await page.close();
    }

    // ---- refunds: partial, then full; the list shows what the server holds ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await guidedRefund(page, 'INV-0004', 1);
      await page.waitForFunction(() => { const tr = Array.from(document.querySelectorAll('tbody tr')).find(r => r.textContent.includes('INV-0004')); return tr && tr.querySelectorAll('td')[5].textContent.trim() === 'S$100.00'; });
      const afterPartial = await dbRow(page, 'inv4');
      ok('a partial refund shows the server\'s paid amount', afterPartial.paid_amount === 100 && await badge(page, 'INV-0004') === 'Paid');
      await closeAll(page);
      await guidedRefund(page, 'INV-0004');
      await waitBadge(page, 'INV-0004', 'Refunded');
      ok('a full refund shows Refunded', (await dbRow(page, 'inv4')).status === 'refunded');
      await page.close();
    }

    // ---- creation: the count and the row update; the create → detail flow stays ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      const countBefore = (await page.locator('.invoice-paging-count').textContent()).trim();
      await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
      await page.locator('select').filter({ has: page.locator('option[value="store"]') }).selectOption('store');
      await page.getByRole('button', { name: 'Search name, ID, phone or email…' }).first().click();
      await page.getByPlaceholder('Search name, ID, phone or email…').fill('Ann');
      await pickCustomer(page, 'Ann Buyer');
      await page.getByRole('button', { name: 'Search product name or SKU…' }).first().click();
      await page.getByText('Long Energia Socks', { exact: false }).last().click();
      await page.getByRole('button', { name: 'Create Invoice', exact: true }).click();
      await page.getByRole('heading', { name: /Invoice INV-NEW-/ }).waitFor();
      ok('creating an invoice opens it, as before', true);
      await page.waitForFunction(() => Array.from(document.querySelectorAll('tbody tr strong')).some(s => /INV-NEW-/.test(s.textContent)));
      const countAfter = (await page.locator('.invoice-paging-count').textContent()).trim();
      ok('and the list behind it gains the row and the count', countBefore !== countAfter, `${countBefore} → ${countAfter}`);
      await page.close();
    }

    // ---- a correction: date and customer change in the list; a payment-method change relabels ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await row(page, 'INV-0007').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
      await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Wrong date and customer keyed');
      await page.getByLabel('Invoice business date').fill('2026-09-15');
      await page.getByRole('button', { name: /^Ann Buyer/ }).first().click();
      await page.getByPlaceholder('Search name, ID, phone or email…').fill('Ben');
      await pickCustomer(page, 'Ben Buyer');
      await page.getByRole('button', { name: 'Payment method', exact: true }).first().click();
      await page.getByRole('combobox', { name: 'Search payment method' }).fill('bank');
      await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
      await page.getByRole('button', { name: 'Review Changes', exact: true }).click();
      await page.getByRole('button', { name: 'Save the correction', exact: true }).click();
      await page.waitForFunction(() => { const tr = Array.from(document.querySelectorAll('tbody tr')).find(r => r.textContent.includes('INV-0007')); return tr && tr.querySelectorAll('td')[6].textContent.trim() === 'Bank Transfer'; });
      ok('after a correction the list shows the new customer', await cell(page, 'INV-0007', 3) === 'Ben Buyer');
      ok('the new invoice date', /15\/09\/2026/.test(await cell(page, 'INV-0007', 1)));
      ok('and the changed payment-method label', true);
      ok('the correction was sent exactly once', await rpcCalls(page, 'correct_invoice') === 1);
      await page.close();
    }

    // ---- the Refresh button: reloads the page and its labels, keeping the rows on screen ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await dbSet(page, 'inv8', { status: 'cancelled' });
      const before = await listCalls(page);
      const rowsBefore = await listRows(page).count();
      await page.getByRole('button', { name: 'Refresh', exact: true }).click();
      await waitBadge(page, 'INV-0008', 'Cancelled');
      ok('Refresh reloads the current page from the server', await listCalls(page) === before + 1);
      ok('the rows were never emptied while it ran', await listRows(page).count() === rowsBefore);
      await page.close();
    }

    // ---- the last row on a page leaves: the viewer lands on the last page that exists ----
    if (width === 1280) {
      const page = await openTab(context, { seed: twentySix(), width });
      await page.getByRole('button', { name: 'Paid', exact: true }).click();
      await page.waitForFunction(() => /of 26/.test(document.querySelector('.invoice-paging-count')?.textContent || ''));
      await page.getByRole('button', { name: 'Next', exact: true }).click();
      await page.waitForFunction(() => document.querySelectorAll('tbody tr .badge').length === 1);
      ok('page two of the Paid filter holds one row', /Page 2 of 2/.test(await page.locator('.invoice-paging-where').textContent()));
      const only = (await page.locator('tbody tr strong').first().textContent()).trim();
      await guidedCancel(page, only);
      await page.waitForFunction(() => /Page 1 of 1/.test(document.querySelector('.invoice-paging-where')?.textContent || ''));
      ok('cancelling it moves the viewer back to page one', await listRows(page).count() === 25, `${await listRows(page).count()} rows`);
      await page.close();
    }

    // ---- the save went through, the refresh did not ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await page.evaluate(() => { window.__failList = true; });
      await guidedCancel(page, 'INV-0009');
      const banner = page.getByTestId('invoice-list-refresh-error');
      await banner.waitFor();
      const text = await banner.textContent();
      ok('the list says the action was saved and only the list could not be refreshed', /The action was recorded/.test(text) && /could not be refreshed/.test(text) && /Do not repeat/.test(text), text);
      ok('the cancellation was not repeated', await rpcCalls(page, 'resolve_invoice_action_v2') === 1);
      ok('the earlier rows stay on screen rather than an empty error state', await listRows(page).count() > 0);
      await page.evaluate(() => { window.__failList = false; });
      await closeAll(page);   // the notice sits on the list, behind the dialogs just used
      await banner.getByRole('button', { name: 'Try again' }).click();
      await waitBadge(page, 'INV-0009', 'Cancelled');
      ok('Try again is a read-only refresh that brings the list up to date', await rpcCalls(page, 'resolve_invoice_action_v2') === 1);
      ok('and the notice goes', await banner.count() === 0);
      await page.close();
    }

    // ---- overlapping requests: a slow older answer never overwrites a newer one ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), width });
      await page.evaluate(() => { window.__listDelays = [900, 0]; });
      await page.getByRole('button', { name: 'Refresh', exact: true }).click();           // slow, for All
      await page.getByRole('button', { name: 'Unpaid', exact: true }).click();            // fast, for Unpaid
      await page.waitForTimeout(1300);
      const badges = await page.locator('tbody tr .badge').allTextContents();
      ok('a slow refresh started before a filter change cannot overwrite the filtered result', badges.length > 0 && badges.every(b => b.trim() === 'Unpaid'), badges.join(','));
      await page.getByRole('button', { name: 'All', exact: true }).click();
      await waitBadge(page, 'INV-0010', 'Paid');
      await page.evaluate(() => { window.__listDelays = [900, 0]; });
      await page.getByRole('button', { name: 'Refresh', exact: true }).click();           // slow, sees Paid
      await guidedCancel(page, 'INV-0010');                                                 // its refresh queues behind
      await page.waitForTimeout(1500);
      ok('a refresh started before a cancellation cannot put Paid back after it', await badge(page, 'INV-0010') === 'Cancelled');
      await page.close();
    }

    // ---- another user: a realtime event is a signal to ask the server again ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await page.waitForFunction(() => document.querySelector('.invoice-live-status')?.textContent === 'Live');
      ok('the page shows it is live once subscribed', true);
      const before = await listCalls(page);
      await dbSet(page, 'inv11', { status: 'cancelled' });
      for (let i = 0; i < 5; i++) await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv11', status: 'cancelled' }, old: { id: 'inv11' } });
      await emit(page, 'invoice_payments', { eventType: 'INSERT', new: { id: 'p', invoice_id: 'inv11' }, old: null });
      await waitBadge(page, 'INV-0011', 'Cancelled');
      ok('a change made elsewhere reaches the list without a reload', true);
      ok('a burst of six events became one refresh', await listCalls(page) === before + 1, `${await listCalls(page) - before}`);
      await page.close();
    }

    // ---- another tab of this browser: the tab that saved tells the others ----
    if (width === 1280) {
      const a = await openTab(context, { seed: everyday(), width });
      const b = await openTab(context, { seed: null, width });
      const before = await listCalls(a);
      await guidedCancel(b, 'INV-0012');
      await waitBadge(a, 'INV-0012', 'Cancelled');
      ok('a cancellation in another tab updates this tab', await listCalls(a) === before + 1);
      ok('and this tab sent no mutation of its own', await rpcCalls(a, 'resolve_invoice_action_v2') === 0);
      await a.close(); await b.close();
    }

    // ---- drafts survive; an open invoice is told, not reset ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
      await page.getByLabel('Notes').fill('keep me');
      const before = await listCalls(page);
      await dbSet(page, 'inv6', { status: 'cancelled' });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv6' }, old: { id: 'inv6' } });
      await page.waitForFunction(n => window.__calls.filter(c => c.name === 'invoice_list_page').length > n, before);
      await page.waitForTimeout(200);
      ok('a background refresh leaves an unsaved new invoice exactly as typed', await page.getByLabel('Notes').inputValue() === 'keep me' && await page.getByRole('button', { name: 'Create Invoice', exact: true }).count() === 1);
      await page.getByRole('button', { name: 'Cancel', exact: true }).click();
      // The open invoice with a payment entry in progress.
      await row(page, 'INV-0002').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByPlaceholder('Amount').first().fill('25');
      await dbSet(page, 'inv2', { notes: 'changed elsewhere' });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv2' }, old: { id: 'inv2' } });
      await page.getByTestId('invoice-detail-stale').waitFor();
      ok('an invoice with entries in progress is told it changed, not reset', await page.getByPlaceholder('Amount').first().inputValue() === '25');
      await page.getByRole('button', { name: 'Reload invoice', exact: true }).click();
      await page.waitForFunction(() => !document.querySelector('[data-testid="invoice-detail-stale"]'));
      ok('reloading on request brings the current figures back', await page.getByPlaceholder('Amount').first().inputValue() === '100');
      // An untouched open invoice just updates, and says so.
      await dbSet(page, 'inv2', { notes: 'changed again' });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv2' }, old: { id: 'inv2' } });
      await page.getByTestId('invoice-detail-updated').waitFor();
      ok('an untouched open invoice is refreshed quietly with a note', true);
      await page.close();
    }

    // ---- concurrent edits: review before saving, never a silent overwrite ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), width });
      await row(page, 'INV-0007').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
      await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Fix the date');
      await page.getByLabel('Invoice business date').fill('2026-09-20');
      await dbSet(page, 'inv7', { edit_count: 1, notes: 'someone else saved' });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv7', edit_count: 1 }, old: { id: 'inv7' } });
      await page.getByTestId('invoice-edit-conflict').waitFor();
      ok('editing an invoice someone else just saved raises the review, with the entries kept', await page.getByLabel('Invoice business date').inputValue() === '2026-09-20');
      await page.getByRole('button', { name: 'Review Changes', exact: true }).click();
      await page.waitForTimeout(300);
      ok('saving is refused until the current invoice has been reviewed', await rpcCalls(page, 'correct_invoice') === 0 && await rpcCalls(page, 'preview_invoice_correction') === 0);
      await page.getByRole('button', { name: 'Review the current invoice', exact: true }).click();
      await page.locator('.invoice-conflict-table').waitFor();
      ok('the review shows what changed', /Edits\s*0\s*1/.test((await page.locator('.invoice-conflict-table').textContent()).replace(/\s+/g, ' ')));
      await page.getByRole('button', { name: /I have reviewed it/ }).click();
      await page.getByRole('button', { name: 'Review Changes', exact: true }).click();
      await page.getByRole('button', { name: 'Save the correction', exact: true }).click();
      await page.waitForFunction(() => window.__calls.some(c => c.name === 'correct_invoice'));
      const sent = await page.evaluate(() => window.__calls.find(c => c.name === 'correct_invoice').args.p_header.expected_edit_count);
      ok('after the review the save carries the current version, so the server accepts it', sent === 1);
      await page.waitForFunction(() => { const tr = Array.from(document.querySelectorAll('tbody tr')).find(r => r.textContent.includes('INV-0007')); return tr && /20\/09\/2026/.test(tr.textContent); });
      ok('and the list shows the saved date', true);
      // The server's own refusal of a stale save (no event seen) maps to the same review.
      await row(page, 'INV-0008').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
      await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Fix a note');
      await page.getByLabel('Notes').fill('mine');
      await dbSet(page, 'inv8', { edit_count: 3 });
      await page.getByRole('button', { name: 'Review Changes', exact: true }).click();
      await page.getByRole('button', { name: 'Save the correction', exact: true }).click();
      await page.getByTestId('invoice-edit-conflict').waitFor();
      ok('a stale save refused by the server also opens the review and keeps the entries', await page.getByLabel('Notes').inputValue() === 'mine');
      await page.close();
    }

    // ---- store restriction: an event about a store the staff member cannot see changes nothing ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), profile: staff, accessible: ['store'], width });
      ok('a staff member never sees the other store\'s invoice', await row(page, 'INV-0005').count() === 0);
      const before = await listCalls(page);
      const rows = await listRows(page).count();
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv5', status: 'cancelled' }, old: { id: 'inv5' } });
      await page.waitForFunction(n => window.__calls.filter(c => c.name === 'invoice_list_page').length > n, before);
      await page.waitForTimeout(200);
      ok('an event is only a signal: the refreshed list still comes from the access-checked query', await row(page, 'INV-0005').count() === 0 && await listRows(page).count() === rows);
      await page.close();
    }

    // ---- a closed invoice stays closed when it changes elsewhere ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await row(page, 'INV-0002').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('heading', { name: /Invoice INV-0002/ }).waitFor();
      await page.getByRole('button', { name: 'Close', exact: true }).last().click();
      await page.waitForFunction(() => !document.querySelector('.modal'));
      const before = await listCalls(page);
      await dbSet(page, 'inv2', { notes: 'changed after close' });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv2' }, old: { id: 'inv2' } });
      await page.waitForFunction(n => window.__calls.filter(c => c.name === 'invoice_list_page').length > n, before);
      await page.waitForTimeout(600);
      ok('a change to an invoice the user closed never reopens it', await page.getByRole('heading', { name: /Invoice INV-0002/ }).count() === 0
         && await page.getByTestId('invoice-detail-stale').count() === 0 && await page.getByTestId('invoice-detail-updated').count() === 0);
      await page.close();
    }

    // ---- this tab's own echo arriving while the invoice is still being re-read ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await page.evaluate(() => { window.__detailDelay = 700; });
      const before = await listCalls(page);
      await recordPayment(page, 'INV-0002', 40);
      await page.waitForFunction(() => window.__calls.some(c => c.name === 'record_invoice_settlement'));
      await page.waitForTimeout(150);
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv2', status: 'partially_paid' }, old: { id: 'inv2' } });
      await emit(page, 'invoice_payments', { eventType: 'INSERT', new: { id: 'p-echo', invoice_id: 'inv2' }, old: null });
      await waitBadge(page, 'INV-0002', 'Partially Paid');
      await page.waitForTimeout(1200);
      ok('the echo of this tab\'s own save, arriving mid-reload, is not reported as another user\'s change',
         await page.getByTestId('invoice-detail-updated').count() === 0 && await page.getByTestId('invoice-detail-stale').count() === 0);
      ok('and costs no second list request', await listCalls(page) === before + 1, `${await listCalls(page) - before}`);
      await page.evaluate(() => { window.__detailDelay = 0; });
      await page.close();
    }

    // ---- the loading indicator settles when a background refresh overtakes a page change ----
    if (width === 1280) {
      const page = await openTab(context, { seed: twentySix(), width });
      await page.getByRole('button', { name: 'Paid', exact: true }).click();
      await page.waitForFunction(() => /of 26/.test(document.querySelector('.invoice-paging-count')?.textContent || ''));
      await page.evaluate(() => { window.__listDelays = [900, 0]; });
      await page.getByRole('button', { name: 'Next', exact: true }).click();          // slow foreground load of page 2
      await page.waitForTimeout(100);
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv20' }, old: { id: 'inv20' } });   // fast background refresh wins
      await page.waitForFunction(() => /Page 2 of 2/.test(document.querySelector('.invoice-paging-where')?.textContent || '') && document.querySelectorAll('tbody tr .badge').length === 1);
      await page.waitForTimeout(1200);
      ok('the loading indicator clears even though the background refresh answered first', !(await page.locator('.invoice-page-busy').count()));
      ok('and paging is usable again', !(await page.getByRole('button', { name: 'Previous', exact: true }).isDisabled()));
      await page.close();
    }

    // ---- guided cancel: the detail re-read fails, the list still refreshes ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await page.evaluate(() => { window.__failInvoiceReload = true; });
      await guidedCancel(page, 'INV-0010');
      const done = page.getByRole('dialog', { name: 'Done' });
      ok('the dialog says the action was saved and only the invoice could not be reloaded', /This was saved/.test(await done.textContent()));
      await waitBadge(page, 'INV-0010', 'Cancelled');
      ok('the list behind it still shows the cancellation', true);
      ok('the cancellation was sent once', await rpcCalls(page, 'resolve_invoice_action_v2') === 1);
      await page.evaluate(() => { window.__failInvoiceReload = false; });
      await done.getByRole('button', { name: 'Reload the invoice', exact: true }).click();
      await page.waitForTimeout(800);
      ok('Reload the invoice only re-reads', await rpcCalls(page, 'resolve_invoice_action_v2') === 1);
      await page.close();
    }

    // ---- Refresh while a slow refresh is running: rows kept, feedback shown, no second request ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), width });
      const rowsBefore = await listRows(page).count();
      const before = await listCalls(page);
      await page.evaluate(() => { window.__listDelays = [900]; });
      const refresh = page.getByRole('button', { name: /Refresh/ });
      await refresh.click();
      await page.waitForTimeout(300);
      ok('mid-refresh the rows are still on screen', await listRows(page).count() === rowsBefore);
      ok('the button shows it is working and cannot be clicked again', /Refreshing/.test(await refresh.textContent()) && await refresh.isDisabled());
      await page.waitForFunction(() => /Refresh$/.test(document.querySelector('.page-header button')?.textContent?.trim() || ''));
      ok('one click, one request', await listCalls(page) === before + 1);
      await page.close();
    }

    // ---- another tab's save and its realtime echo are one change ----
    if (width === 1280) {
      const a = await openTab(context, { seed: everyday(), width });
      const b = await openTab(context, { seed: null, width });
      const before = await listCalls(a);
      await a.evaluate(() => { window.__listDelays = [600]; });
      await guidedCancel(b, 'INV-0011');
      await a.waitForTimeout(150);
      await emit(a, 'invoices', { eventType: 'UPDATE', new: { id: 'inv11', status: 'cancelled' }, old: { id: 'inv11' } });
      await waitBadge(a, 'INV-0011', 'Cancelled');
      await a.waitForTimeout(800);
      ok('the other tab\'s announcement and the realtime event for it cost one list request', await listCalls(a) === before + 1, `${await listCalls(a) - before}`);
      await a.close(); await b.close();
    }

    // ---- a second change after "I have reviewed it" asks for a second review ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), width });
      await row(page, 'INV-0009').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
      await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Fix a note');
      await page.getByLabel('Notes').fill('mine');
      await dbSet(page, 'inv9', { edit_count: 1 });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv9', edit_count: 1 }, old: { id: 'inv9' } });
      await page.getByTestId('invoice-edit-conflict').waitFor();
      await page.getByRole('button', { name: 'Review the current invoice', exact: true }).click();
      await page.getByRole('button', { name: /I have reviewed it/ }).click();
      await dbSet(page, 'inv9', { edit_count: 2 });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv9', edit_count: 2 }, old: { id: 'inv9' } });
      await page.getByRole('button', { name: 'Review the current invoice', exact: true }).waitFor();
      ok('a further change after a review asks for the review again, entries kept', await page.getByLabel('Notes').inputValue() === 'mine');
      await page.getByRole('button', { name: 'Review Changes', exact: true }).click();
      await page.waitForTimeout(300);
      ok('and saving is blocked until it is done', await rpcCalls(page, 'correct_invoice') === 0);
      ok('Discard my entries and reopen stays available', await page.getByRole('button', { name: 'Discard my entries and reopen', exact: true }).count() === 1);
      await page.close();
    }

    // ---- a refund/correction being entered in the finance panel is protected ----
    {
      const page = await openTab(context, { seed: everyday(), width });
      await row(page, 'INV-0006').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Correct amount / date', exact: true }).first().click();
      await page.getByLabel('Correct amount', { exact: true }).fill('75');
      await dbSet(page, 'inv6', { notes: 'changed elsewhere' });
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv6' }, old: { id: 'inv6' } });
      await page.getByTestId('invoice-detail-stale').waitFor();
      ok('a payment correction being entered survives a change elsewhere', await page.getByLabel('Correct amount', { exact: true }).inputValue() === '75');
      // Finishing it refreshes the list: the payment becomes 75 of 100.
      await page.getByLabel('Reason (required)', { exact: true }).fill('Keyed 100, was 75');
      await page.getByRole('button', { name: 'Record with audit history' }).click();
      await waitBadge(page, 'INV-0006', 'Partially Paid');
      ok('a payment amount correction shows in the list', await cell(page, 'INV-0006', 5) === money(25));
      ok('sent once', await rpcCalls(page, 'correct_invoice_payment') === 1);
      await page.close();
    }

    // ---- reopen, delete and affiliate change all refresh the list ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), width });
      await guidedCancel(page, 'INV-0007');
      await closeAll(page);
      await waitBadge(page, 'INV-0007', 'Cancelled');
      await row(page, 'INV-0007').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Preview reopening', exact: true }).click();
      await page.getByLabel('Reason (required)', { exact: true }).fill('Cancelled by mistake');
      await page.getByRole('button', { name: 'Confirm reopening', exact: true }).click();
      await waitBadge(page, 'INV-0007', 'Paid');
      ok('reopening shows the invoice as Paid again in the list', true);
      await closeAll(page);
      // Delete an unpaid invoice from the row.
      page.on('dialog', d => d.accept());
      const countBefore = (await page.locator('.invoice-paging-count').textContent()).trim();
      await row(page, 'INV-0003').locator('.btn-danger').click();
      await waitGone(page, 'INV-0003');
      ok('a deleted invoice leaves the list and the count', (await page.locator('.invoice-paging-count').textContent()).trim() !== countBefore);
      // Affiliate on an unpaid invoice.
      const before = await listCalls(page);
      await row(page, 'INV-0002').getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Search affiliate name, phone or email…' }).click();
      await page.getByPlaceholder('Search affiliate name, phone or email…').fill('Ben');
      await page.locator('div', { hasText: /^Ben Buyer$/ }).last().click({ force: true });
      await page.waitForFunction(n => window.__calls.filter(c => c.name === 'invoice_list_page').length > n, before);
      ok('an affiliate change refreshes the list', await rpcCalls(page, 'set_invoice_affiliate') === 1);
      await page.close();
    }

    // ---- an invalid date range sends nothing; an empty result is handled ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), width });
      await page.getByLabel('Invoice date from').fill('2026-09-10');
      await page.getByLabel('Invoice date to').fill('2026-09-01');
      await page.getByTestId('invoice-date-range-error').waitFor();
      const before = await listCalls(page);
      await page.getByRole('button', { name: /Refresh/ }).click();
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv1' }, old: { id: 'inv1' } });
      await page.waitForTimeout(900);
      ok('a reversed date range sends no request, from Refresh or from a signal', await listCalls(page) === before);
      await page.getByRole('button', { name: 'All dates', exact: true }).click();
      await page.getByPlaceholder(/Search invoice number/).fill('nothing-matches-this');
      await page.getByText('No invoices match these filters').waitFor();
      await emit(page, 'invoices', { eventType: 'UPDATE', new: { id: 'inv1' }, old: { id: 'inv1' } });
      await page.waitForTimeout(900);
      ok('an empty result stays a clear empty state through a refresh', await page.getByText('No invoices match these filters').count() === 1 && await page.locator('.invoice-page-busy').count() === 0);
      await page.close();
    }

    // ---- leaving the page stops everything ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), realtimeDown: true, clock: true, width });
      await page.waitForFunction(() => document.querySelector('.invoice-live-status')?.textContent === 'Updates paused');
      await page.evaluate(() => { window.__root.unmount(); });
      const before = await listCalls(page);
      await page.clock.runFor(125_000);
      ok('after unmount the poll is gone', await listCalls(page) === before);
      ok('and the realtime channel was removed', await page.evaluate(() => window.__removed) >= 1);
      await page.close();
    }

    // ---- realtime unavailable: bounded polling while visible; reconnect and focus refresh ----
    if (width === 1280) {
      const page = await openTab(context, { seed: everyday(), realtimeDown: true, clock: true, width });
      await page.waitForFunction(() => document.querySelector('.invoice-live-status')?.textContent === 'Updates paused');
      ok('with no realtime the page says updates are paused', true);
      let before = await listCalls(page);
      await page.clock.runFor(59_000);
      ok('no poll before a minute', await listCalls(page) === before);
      await page.clock.runFor(2_000);
      await page.waitForFunction(n => window.__calls.filter(c => c.name === 'invoice_list_page').length > n, before);
      ok('a visible tab without realtime polls once a minute', await listCalls(page) === before + 1);
      // Hidden: no polling.
      await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
      before = await listCalls(page);
      await page.clock.runFor(125_000);
      ok('a hidden tab makes no requests', await listCalls(page) === before);
      // Back: one refresh.
      await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
      await page.waitForFunction(n => window.__calls.filter(c => c.name === 'invoice_list_page').length > n, before);
      ok('coming back to the tab refreshes it', await listCalls(page) === before + 1);
      // Realtime returns: subscribed, then a drop and a re-subscription refresh once.
      await page.evaluate(() => { window.__realtimeDown = false; window.__realtime('SUBSCRIBED'); });
      await page.waitForFunction(() => document.querySelector('.invoice-live-status')?.textContent === 'Live');
      before = await listCalls(page);
      await page.evaluate(() => { window.__realtime('CHANNEL_ERROR'); });
      await page.waitForFunction(() => document.querySelector('.invoice-live-status')?.textContent === 'Updates paused');
      await page.evaluate(() => { window.__realtime('SUBSCRIBED'); });
      await page.waitForFunction(n => window.__calls.filter(c => c.name === 'invoice_list_page').length > n, before);
      ok('a re-subscription after a drop refreshes once, in case events were missed', await listCalls(page) === before + 1);
      before = await listCalls(page);
      await page.clock.runFor(125_000);
      ok('while live, there is no polling', await listCalls(page) === before);
      await page.close();
    }

    await context.close();
  }
  console.log(`\nPASS list-refresh-browser: ${checks} checks`);
} finally { await browser.close(); }
