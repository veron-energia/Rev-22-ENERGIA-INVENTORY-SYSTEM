// Behaviour tests for the Special page (426): src/pages/SpecialPage.tsx.
//
//   SALES-EXTRAS-8   Refresh reloads the waiting list too, and a list that
//                    could not be read says so, never "Nothing waiting".
//   SALES-EXTRAS-7   Change rental terms: "Due back" follows the periods, a
//                    typed date is kept, the server's refusal shows in the
//                    window itself, and saving reloads the page.
//   W4-B12-RENTAL-FEE (the owner, 18 Oct 2026): the window shows the new fee
//                    as the save works it out: the list fee less the same
//                    discount as the invoice line sold it; the dates alone
//                    keep the fee as sold.
//   SALES-EXTRAS-12  The old New Sale, New Rental, Pay and Activate windows
//                    and the Cancel buttons are gone; old rows still print.
//   SALES-EXTRAS-15  The tabs and the header wrap, the waiting list is one
//                    column under 640 px, and Return asks before a stray tap
//                    loses it.
//   SALES-EXTRAS-16  An emptied description is sent as '' (cleared); a
//                    receipt uses the rental's own store and names the
//                    invoice that sold it, on paper and in what is sent.
//   INVOICES-AFTER-11 / -M3 (the Special page part; B16 built sendDoc): the
//                    WhatsApp window opens in the click, before anything is
//                    awaited; a blocked window and the email outcomes are
//                    said as sendDoc gives them, never "attached".
//   W2-B03-RENTAL-BUTTON (the owner, 10 Oct 2026): a rental cancelled while
//                    still with the customer shows "Receive returned item",
//                    which records it with 417's receive_returned_rental.
//
// JSDOM, with the database, sendDoc and printing stubbed; invented data only.
// Run: node --test scripts/special/tests/special-page.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'https://example.test/special' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
dom.window.requestAnimationFrame = fn => setTimeout(() => fn(Date.now()), 0);
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame;
if (!globalThis.navigator) globalThis.navigator = dom.window.navigator;
let confirms = 0;
dom.window.confirm = () => { confirms += 1; return false; };

const React = (await import('react')).default;
const { act } = await import('react');
const { createRoot } = await import('react-dom/client');
const { Simulate } = await import('react-dom/test-utils');

const require = createRequire(import.meta.url);
const dir = await mkdtemp(join(tmpdir(), 'energia-special-page-'));
const read = p => readFile(new URL(`../../../${p}`, import.meta.url), 'utf8');

const ICONS = ['Plus', 'Pencil', 'Trash2', 'RefreshCw', 'Boxes', 'KeyRound', 'ShoppingBag', 'CalendarClock', 'Clock',
               'Printer', 'MessageCircle', 'Mail', 'Lock'];
const STUBS = {
  sb: `export const supabase = new Proxy({}, { get: (_t, p) => globalThis.__SB__[p] });
       export const fetchCustomersByIds = async ids => globalThis.__DB__.customers.filter(c => ids.includes(c.id));`,
  auth: 'export const useAuth = () => ({ profile: { id: "u-1", role: globalThis.__ROLE__, full_name: "Fixture Owner" } });',
  router: `import React from 'react';
    export const Link = ({ to, children, ...p }) => React.createElement('a', { href: to, ...p }, children);`,
  send: `const S = () => globalThis.__SEND__;
    export const whatsappNumber = p => (p ? String(p).replace(/\\D/g, '') : null);
    export const emailAddress = e => (e ? String(e) : null);
    export function openSendWindow() { S().events.push('open'); return S().win; }
    export async function sendViaWhatsAppLink(a, o) { S().events.push('wa'); S().wa.push({ a, o }); return S().waReply(a, o); }
    export async function sendViaEmailAttachment(a) { S().events.push('email'); S().email.push(a); return S().emailReply(a); }`,
  pdf: 'export {};',
  print: `export const esc = s => String(s ?? '');
    export const money = n => 'S$' + Number(n ?? 0).toFixed(2);
    export function printA5Document(o) { globalThis.__PRINTS__.push(o); return true; }`,
  excel: 'export const ExcelExportButton = () => null;',
  search: 'export const SearchSelect = () => null; export const CustomerSearchSelect = () => null;',
  lucide: `import React from 'react';
    const Icon = () => React.createElement('span', { 'aria-hidden': 'true' });
    export const ${ICONS.map(n => `${n} = Icon`).join(', ')};`,
};

await build({
  entryPoints: ['src/pages/SpecialPage.tsx'],
  outfile: join(dir, 'page.mjs'),
  bundle: true, format: 'esm', platform: 'node', jsx: 'automatic', logLevel: 'silent',
  plugins: [{
    name: 'stubs',
    setup(b) {
      b.onResolve({ filter: /^react(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^react-dom(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^react-router-dom$/ }, () => ({ path: 'router', namespace: 's' }));
      b.onResolve({ filter: /^lucide-react$/ }, () => ({ path: 'lucide', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/supabase$/ }, () => ({ path: 'sb', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/sendDoc$/ }, () => ({ path: 'send', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/invoicePdf$/ }, () => ({ path: 'pdf', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/printDoc$/ }, () => ({ path: 'print', namespace: 's' }));
      b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 's' }));
      b.onResolve({ filter: /\/components\/ExcelExport$/ }, () => ({ path: 'excel', namespace: 's' }));
      b.onResolve({ filter: /\/components\/SearchSelect$/ }, () => ({ path: 'search', namespace: 's' }));
      b.onLoad({ filter: /.*/, namespace: 's' }, a => ({ contents: STUBS[a.path], loader: 'jsx' }));
    },
  }],
});
const { default: SpecialPage } = await import(pathToFileURL(join(dir, 'page.mjs')).href);

// ── Invented data ────────────────────────────────────────────────────────
const STORES = [
  { id: 'st-a', name: 'Fixture Main Store', paynow_uen: 'T00FX0001A', policy_text: 'Main store policy' },
  { id: 'st-b', name: 'Fixture Roadshow Van', paynow_uen: 'T00FX0002B', policy_text: 'Roadshow policy' },
];
const RENTAL = over => ({
  id: 'r-1', rental_no: 'RNT-2026-9901', special_product_id: 'sp-1', customer_id: 'c-1', warehouse_id: null,
  store_id: 'st-b', source_store_id: 'st-b', invoice_id: 'inv-1', invoice_item_id: 'li-1', status: 'active',
  quantity: 1, rate_type: 'day', rate_amount: 30, periods: 2, rental_fee: 60, start_date: '2026-10-10',
  expected_return_date: '2026-10-12', late_fee_per_day: 5, late_fee_total: 0, late_days: 0, notes: null,
  stock_returned: null, fulfilled_at: '2026-10-10T02:00:00Z', activated_at: '2026-10-10T02:00:00Z',
  created_at: '2026-10-10T02:00:00Z', ...over,
});
const WAITING = {
  doc_kind: 'rental', doc_id: 'r-9', doc_no: 'RNT-2026-9909', invoice_no: 'INV-2026-9909', special_product_id: 'sp-1',
  product_name: 'Fixture Machine', customer_name: 'Fixture Renter', store_name: 'Fixture Main Store', quantity: 1,
  rate_type: 'day', periods: 2, start_date: '2027-01-31', expected_return_date: '2027-02-02', rental_fee: 60,
  created_at: '2026-10-17T02:00:00Z',
};
function db(over = {}) {
  return {
    special_products: [{ id: 'sp-1', product_id: 'p-1', name: 'Fixture Machine', sku: 'FX-M', description: 'Old note',
      sale_price: 0, rate_day: 30, rate_week: 150, rate_month: 400, rate_year: 0, late_fee_per_day: 5, is_active: true }],
    warehouse_inventory: [], store_inventory: [], special_sales: [],
    rentals: [RENTAL(), RENTAL({ id: 'r-2', rental_no: 'RNT-2026-9902', status: 'cancelled', stock_returned: false,
      store_id: 'st-a', invoice_id: 'inv-2', invoice_item_id: 'li-2', cancelled_at: '2026-10-15T02:00:00Z' })],
    warehouses: [{ id: 'wh-1', name: 'Fixture Warehouse', is_active: true }],
    payment_methods: [], stores: STORES, profiles: [],
    invoices: [{ id: 'inv-1', invoice_no: 'INV-2026-9901', status: 'paid' }, { id: 'inv-2', invoice_no: 'INV-2026-9902', status: 'cancelled' }],
    customers: [{ id: 'c-1', full_name: 'Fixture Renter', phone: '+61491570737', email: 'renter@example.com' }],
    ...over,
  };
}

function makeSupabase(rpcReply) {
  const calls = [];
  const from = table => {
    calls.push(`from:${table}`);
    const c = new Proxy({}, {
      get: (_t, p) => p === 'then'
        ? (res, rej) => Promise.resolve({ data: globalThis.__DB__[table] ?? [], error: null }).then(res, rej)
        : () => c,
    });
    return c;
  };
  const rpc = async (name, args) => {
    calls.push(`rpc:${name}`);
    globalThis.__SEND__?.events.push(`rpc:${name}`);
    const r = rpcReply(name, args);
    if (r !== undefined) return r;
    if (name === 'special_docs_awaiting_fulfilment') return { data: [], error: null };
    return { data: [], error: null };
  };
  return { calls, rpcArgs: [], sb: { from, rpc } };
}

async function mount({ data = db(), rpc = () => undefined, send = {} } = {}) {
  globalThis.__ROLE__ = 'owner';
  globalThis.__DB__ = data;
  globalThis.__PRINTS__ = [];
  const rpcCalls = [];
  const stub = makeSupabase((n, a) => { rpcCalls.push([n, a]); return rpc(n, a); });
  globalThis.__SB__ = stub.sb;
  globalThis.__SEND__ = {
    events: [], wa: [], email: [], win: { closed: false, close() { this.closed = true; } },
    waReply: async () => ({ ok: true }), emailReply: async () => ({ ok: true, outcome: 'link' }), ...send,
  };
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  await act(async () => { root.render(React.createElement(SpecialPage)); });
  const settle = () => act(async () => { await new Promise(r => setTimeout(r, 10)); });
  await settle();
  const buttons = () => [...node.querySelectorAll('button')];
  const button = label => buttons().find(b => b.textContent.trim() === label || b.getAttribute('aria-label') === label);
  const dialog = title => [...node.querySelectorAll('[role="dialog"]')].find(d => d.querySelector('h3')?.textContent === title);
  return {
    node, stub, rpcCalls, settle, button, dialog, text: () => node.textContent,
    count: k => stub.calls.filter(c => c === k).length,
    async click(el) { assert.ok(el, 'the element to click exists'); await act(async () => { Simulate.click(el); }); await settle(); },
    async set(el, value) { assert.ok(el, 'the field exists'); el.value = value; await act(async () => { Simulate.change(el); }); },
    async tab(name) { await this.click(buttons().find(b => b.textContent.trim() === name)); },
    close() { act(() => root.unmount()); node.remove(); },
  };
}
const fieldIn = (dlg, label) => [...dlg.querySelectorAll('.form-group')]
  .find(g => g.querySelector('label')?.textContent.replace(' *', '').trim() === label)?.querySelector('input, select, textarea');

test('Refresh reloads the waiting list, and a list that could not be read says so', async () => {
  let fail = false;
  const ui = await mount({ rpc: n => n === 'special_docs_awaiting_fulfilment'
    ? (fail ? { data: null, error: { message: 'canceling statement due to statement timeout' } } : { data: [WAITING], error: null })
    : undefined });
  try {
    assert.equal(ui.count('rpc:special_docs_awaiting_fulfilment'), 1, 'loaded once on opening');
    assert.match(ui.text(), /Waiting for a warehouse1/);
    fail = true;
    await ui.click(ui.button('Refresh'));
    assert.equal(ui.count('rpc:special_docs_awaiting_fulfilment'), 2, 'Refresh reloads the waiting list too');
    assert.match(ui.text(), /Could not load the waiting list\. Press Refresh\./);
    assert.doesNotMatch(ui.text(), /Nothing waiting for a warehouse/);
    fail = false;
    await ui.click(ui.button('Refresh'));
    assert.match(ui.text(), /Waiting for a warehouse1/);
  } finally { ui.close(); }
});

test('Change rental terms: "Due back" follows, a typed date is kept, errors show in the window, saving reloads', async () => {
  let reply = { data: null, error: { message: 'RNT-2026-9909 is not waiting for a warehouse any more (it is cancelled), so its terms cannot be changed.' } };
  const ui = await mount({ rpc: n => n === 'special_docs_awaiting_fulfilment' ? { data: [WAITING], error: null }
    : n === 'update_pending_rental' ? reply : undefined });
  try {
    await ui.click(ui.button('Waiting for a warehouse1') ?? [...ui.node.querySelectorAll('button')].find(b => /Waiting for a warehouse/.test(b.textContent)));
    await ui.click(ui.button('Change'));
    const dlg = () => ui.dialog('Change rental terms — RNT-2026-9909');
    assert.ok(dlg(), 'the Change window opened');
    await ui.set(fieldIn(dlg(), 'Periods'), '5');
    assert.equal(fieldIn(dlg(), 'Due back').value, '2027-02-05', '5 days from 31 Jan');
    await ui.set(fieldIn(dlg(), 'Rate'), 'month');
    assert.equal(fieldIn(dlg(), 'Due back').value, '2027-06-30', '5 months from 31 Jan: the last day of June');
    await ui.set(fieldIn(dlg(), 'Due back'), '2027-07-10');
    await ui.set(fieldIn(dlg(), 'Quantity'), '2');
    assert.equal(fieldIn(dlg(), 'Due back').value, '2027-07-10', 'a typed date is kept while only the quantity changes');
    const rentalsBefore = ui.count('from:rentals');
    await ui.click([...dlg().querySelectorAll('button')].find(b => b.textContent === 'Save terms'));
    assert.match(dlg().textContent, /is not waiting for a warehouse any more \(it is cancelled\)/, 'the refusal is in the Change window');
    const sent = ui.rpcCalls.find(([n]) => n === 'update_pending_rental')[1];
    assert.deepEqual(sent, { p_rental_id: 'r-9', p_quantity: 2, p_rate_type: 'month', p_periods: 5,
      p_start_date: '2027-01-31', p_expected_return_date: '2027-07-10' });
    reply = { data: { success: true, rental_fee: 4000, invoiced_fee: 60, difference: 3940 }, error: null };
    await ui.click([...dlg().querySelectorAll('button')].find(b => b.textContent === 'Save terms'));
    assert.equal(dlg(), undefined, 'the window closes once saved');
    assert.ok(ui.count('from:rentals') > rentalsBefore, 'the Rentals tab is reloaded');
    assert.match(ui.text(), /S\$3940\.00 more than the S\$60\.00 already invoiced/);
    // A "Due back" before the start cannot be saved.
    await ui.click(ui.button('Change'));
    await ui.set(fieldIn(dlg(), 'Due back'), '2027-01-01');
    assert.match(dlg().textContent, /"Due back" cannot be before the start\./);
    assert.equal([...dlg().querySelectorAll('button')].find(b => b.textContent === 'Save terms').disabled, true);
    // A changed form asks before a stray tap closes it.
    const before = confirms;
    await ui.click(dlg().closest('[data-modal-overlay]'));
    assert.equal(confirms, before + 1, 'asked before closing');
    assert.ok(dlg(), 'still open after "Cancel" in the question');
  } finally { ui.close(); }
});

test('Change rental terms shows the new fee as the save works it out: the same discount as sold', async () => {
  // RNT-2026-9909, sold on INV-2026-9909: 2 machines for 2 days at S$30, S$120
  // less S$25 (S$95 paid). The invoice raised the rental at S$120.
  const waiting = { ...WAITING, quantity: 2, rental_fee: 120 };
  const base = db();
  const data = db({
    rentals: [...base.rentals, RENTAL({ id: 'r-9', rental_no: 'RNT-2026-9909', status: 'awaiting_fulfilment', source_store_id: null,
      store_id: 'st-a', invoice_id: 'inv-9', invoice_item_id: 'li-9', quantity: 2, rate_amount: 60, rental_fee: 120,
      start_date: '2027-01-31', expected_return_date: '2027-02-02', fulfilled_at: null, activated_at: null })],
    invoices: [...base.invoices, { id: 'inv-9', invoice_no: 'INV-2026-9909', status: 'paid' }],
    invoice_items: [{ id: 'li-9', quantity: 2, rental_rate_type: 'day', rental_periods: 2, line_total: 120, foc_quantity: 0,
      is_foc: false, line_discount: 25, line_discount_type: 'manual', line_discount_percent: null }],
  });
  let reply;
  const ui = await mount({ data, rpc: n => n === 'special_docs_awaiting_fulfilment' ? { data: [waiting], error: null }
    : n === 'update_pending_rental' ? reply : undefined });
  try {
    await ui.click([...ui.node.querySelectorAll('button')].find(b => /Waiting for a warehouse/.test(b.textContent)));
    await ui.click(ui.button('Change'));
    const dlg = () => ui.dialog('Change rental terms — RNT-2026-9909');
    const fee = () => dlg().querySelector('[data-rental-fee]').textContent.replace(/\s+/g, ' ');
    assert.equal(ui.count('from:invoice_items'), 1, 'the line that sold it is read once');
    assert.match(fee(), /The fee stays S\$95\.00: a change of the dates alone keeps it\./, 'the fee as sold, not S$120');
    await ui.set(fieldIn(dlg(), 'Starts'), '2027-02-10');
    assert.match(fee(), /The fee stays S\$95\.00/, 'a new start alone keeps it');
    await ui.set(fieldIn(dlg(), 'Periods'), '3');
    assert.match(fee(), /New fee S\$155\.00 \(S\$180\.00 at the list rate; the same S\$25\.00 off as sold\)\. That is S\$60\.00 more than the S\$95\.00 already invoiced — collect the difference on the invoice\./);
    await ui.set(fieldIn(dlg(), 'Quantity'), '1');
    assert.match(fee(), /New fee S\$65\.00 \(S\$90\.00 at the list rate; the same S\$25\.00 off as sold\)\. That is S\$30\.00 less than the S\$95\.00 already invoiced — refund the difference on the invoice\./);
    await ui.set(fieldIn(dlg(), 'Rate'), 'week');
    assert.match(fee(), /New fee S\$425\.00 \(S\$450\.00 at the list rate; the same S\$25\.00 off as sold\)/);
    // Back to the terms sold: the fee as sold again.
    await ui.set(fieldIn(dlg(), 'Rate'), 'day');
    await ui.set(fieldIn(dlg(), 'Quantity'), '2');
    await ui.set(fieldIn(dlg(), 'Periods'), '2');
    assert.match(fee(), /The fee stays S\$95\.00/);
    // What is saved is what was shown; the note names the discount kept.
    await ui.set(fieldIn(dlg(), 'Periods'), '3');
    assert.match(fee(), /New fee S\$155\.00/);
    reply = { data: { success: true, rental_fee: 155, invoiced_fee: 95, difference: 60, list_fee: 180,
      discount_kept: 'the same S$25.00 off as sold', expected_return_date: '2027-02-13' }, error: null };
    await ui.click([...dlg().querySelectorAll('button')].find(b => b.textContent === 'Save terms'));
    assert.deepEqual(ui.rpcCalls.find(([n]) => n === 'update_pending_rental')[1], { p_rental_id: 'r-9', p_quantity: 2,
      p_rate_type: 'day', p_periods: 3, p_start_date: '2027-02-10', p_expected_return_date: '2027-02-13' });
    assert.equal(dlg(), undefined, 'the window closes once saved');
    assert.match(ui.text(), /The rental fee is now S\$155\.00 \(the same S\$25\.00 off as sold\) — S\$60\.00 more than the S\$95\.00 already invoiced\./);
  } finally { ui.close(); }
});

test('Change rental terms: a line that cannot be read leaves the fee to the save', async () => {
  const data = db({ rentals: [...db().rentals, RENTAL({ id: 'r-9', rental_no: 'RNT-2026-9909', status: 'awaiting_fulfilment',
    source_store_id: null, invoice_id: 'inv-9', invoice_item_id: 'li-9' })], invoice_items: [] });
  const ui = await mount({ data, rpc: n => n === 'special_docs_awaiting_fulfilment' ? { data: [WAITING], error: null } : undefined });
  try {
    await ui.click([...ui.node.querySelectorAll('button')].find(b => /Waiting for a warehouse/.test(b.textContent)));
    await ui.click(ui.button('Change'));
    const dlg = ui.dialog('Change rental terms — RNT-2026-9909');
    await ui.set(fieldIn(dlg, 'Periods'), '3');
    const said = dlg.querySelector('[data-rental-fee]').textContent.replace(/\s+/g, ' ');
    assert.match(said, /The fee will be worked out when you save: a change of the dates alone keeps it as sold, and a new quantity, rate or number of periods is priced at the list rate with the same discount as sold\. You will be told any difference to collect or refund on the invoice\./);
    // No amount is named: the rental's own fee may be before a line discount or a correction.
    assert.doesNotMatch(said, /S\$|paid at/);
    assert.doesNotMatch(dlg.textContent, /New fee/);
  } finally { ui.close(); }
});

test('a rental cancelled while still with the customer: "Receive returned item" records what came back', async () => {
  let receive = { data: { rental_id: 'r-2', returned_quantity: 1, location_type: 'store', location_name: 'Fixture Roadshow Van' }, error: null };
  const ui = await mount({ rpc: n => n === 'receive_returned_rental' ? receive : undefined });
  try {
    await ui.tab('Rentals');
    assert.match(ui.text(), /Cancelled, still with customer/);
    const open = ui.button('Receive returned item: Fixture Machine (RNT-2026-9902)');
    assert.ok(open, 'the button is on the cancelled rental');
    assert.equal(ui.button('Receive returned item: Fixture Machine (RNT-2026-9901)'), undefined, 'not on a rental still running');
    await ui.click(open);
    const dlg = () => ui.dialog('Receive returned item — RNT-2026-9902');
    const record = () => [...dlg().querySelectorAll('button')].find(b => b.textContent === 'Record what came back');
    assert.equal(record().disabled, true, 'nothing is chosen for them');
    await ui.set(fieldIn(dlg(), 'What happened'), 'good');
    const where = fieldIn(dlg(), 'Goes back to');
    assert.equal(where.options[0].textContent, 'Fixture Roadshow Van (its store)');
    assert.equal(record().disabled, true, 'a note is needed');
    // A stray tap with something chosen asks first.
    const before = confirms;
    await ui.click(dlg().closest('[data-modal-overlay]'));
    assert.equal(confirms, before + 1);
    await ui.set(fieldIn(dlg(), 'Note'), ' Brought back to the counter ');
    receive = { data: null, error: { message: 'Rental not accessible' } };
    await ui.click(record());
    assert.match(dlg().textContent, /Rental not accessible/, 'a refusal shows in the window');
    receive = { data: { rental_id: 'r-2', returned_quantity: 1, location_type: 'store', location_name: 'Fixture Roadshow Van' }, error: null };
    const rentalsBefore = ui.count('from:rentals');
    await ui.click(record());
    const calls = ui.rpcCalls.filter(([n]) => n === 'receive_returned_rental');
    const args = calls[calls.length - 1][1];
    assert.equal(args.p_rental_id, 'r-2');
    assert.equal(args.p_warehouse_id, null, 'back where it came from');
    assert.equal(args.p_condition, 'good');
    assert.equal(args.p_reason, 'Brought back to the counter');
    assert.match(String(args.p_request_id), /^[0-9a-f-]{36}$/);
    assert.equal(args.p_request_id, calls[0][1].p_request_id, 'one request id for the window, so a retry is the same request');
    assert.match(dlg().textContent, /RNT-2026-9902 is back in good condition and on sale again at Fixture Roadshow Van\./);
    assert.ok(ui.count('from:rentals') > rentalsBefore, 'the Rentals tab is reloaded');
    await ui.click([...dlg().querySelectorAll('button')].find(b => b.textContent === 'Done'));
    assert.match(ui.text(), /RNT-2026-9902 is back in good condition/, 'still said on the tab');
  } finally { ui.close(); }
});

test("a receipt uses the rental's own store and names the invoice that sold it", async () => {
  const ui = await mount();
  try {
    await ui.tab('Rentals');
    const row = [...ui.node.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('RNT-2026-9901'));
    await ui.click([...row.querySelectorAll('button')].find(b => b.textContent.includes('Print')));
    const o = globalThis.__PRINTS__[0];
    assert.equal(o.branding.name, 'Fixture Roadshow Van', 'the second store, not the first in the list');
    assert.equal(o.policyText, 'Roadshow policy');
    assert.ok(o.headerLines.includes('Invoice INV-2026-9901'), o.headerLines.join(' | '));
    // The cancelled one was sold at the first store and released from the second: the invoice's store.
    const row2 = [...ui.node.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('RNT-2026-9902'));
    await ui.click([...row2.querySelectorAll('button')].find(b => b.textContent.includes('Print')));
    assert.equal(globalThis.__PRINTS__[1].branding.name, 'Fixture Main Store');
    assert.ok(globalThis.__PRINTS__[1].headerLines.includes('Invoice INV-2026-9902'));
  } finally { ui.close(); }
});

test('WhatsApp: the window opens in the click, before anything is awaited, and goes to the send', async () => {
  const ui = await mount();
  try {
    await ui.tab('Rentals');
    globalThis.__SEND__.events.length = 0;
    act(() => { Simulate.click(ui.button('Send RNT-2026-9901 by WhatsApp')); });
    assert.deepEqual(globalThis.__SEND__.events.slice(0, 2), ['open', 'wa'], 'opened first, with nothing awaited before the send');
    await ui.settle();
    const { a, o } = globalThis.__SEND__.wa[0];
    assert.equal(o.win, globalThis.__SEND__.win, 'the window from the click is the one used');
    assert.equal(a.storeId, 'st-b', 'filed under the rental\'s own store');
    assert.equal(a.pdf.storeName, 'Fixture Roadshow Van');
    assert.equal(a.pdf.headerNote, 'Invoice INV-2026-9901');
    assert.deepEqual(a.pdf.payDetails, ['CIMB UEN: T00FX0002B']);
    assert.match(ui.text(), /WhatsApp should now be open with the link to RNT-2026-9901; send the message there\./);
  } finally { ui.close(); }
});

test('WhatsApp: a blocked window is said, and nothing claims it was sent', async () => {
  const BLOCKED = 'Your browser blocked the WhatsApp window. Allow pop-ups for this site, then press WhatsApp again.';
  const ui = await mount({ send: { win: null, waReply: async () => ({ ok: false, reason: BLOCKED }) } });
  try {
    await ui.tab('Rentals');
    await ui.click(ui.button('Send RNT-2026-9901 by WhatsApp'));
    assert.equal(globalThis.__SEND__.wa[0].o.win, null, 'the refusal is passed on, so it is not logged as sent');
    assert.match(ui.text(), /Your browser blocked the WhatsApp window/);
    assert.doesNotMatch(ui.text(), /should now be open/);
  } finally { ui.close(); }
});

test('Email from this device: the link and the share sheet are said as they are, never "attached"', async () => {
  let reply = { ok: true, outcome: 'link', mailto: 'mailto:renter%40example.com?subject=Rental',
    reason: 'Your mail app should open with a link to the PDF; send it from there.' };
  let again = 0;
  const ui = await mount({ send: { emailReply: async () => reply } });
  try {
    await ui.tab('Rentals');
    const email = ui.button('Email RNT-2026-9901 from this device');
    assert.equal(email.getAttribute('title'), "Email from this device's mail app");
    await ui.click(email);
    assert.match(ui.text(), /Your mail app should open with a link to the PDF; send it from there\./);
    assert.equal(ui.node.querySelector('a[href^="mailto:"]').textContent, 'Open the email again');
    reply = { ok: false, reason: 'The share sheet did not open. Press Email again.',
      shareAgain: async () => { again += 1; return { ok: true, outcome: 'shared', reason: 'The PDF went to the app you chose. Send the email to renter@example.com from there.' }; } };
    await ui.click(email);
    assert.match(ui.text(), /The PDF is ready\. Press "Share the PDF" to choose your mail app\./);
    await ui.click(ui.button('Share the PDF'));
    assert.equal(again, 1, 'the share sheet is asked for again from the new tap');
    assert.match(ui.text(), /The PDF went to the app you chose/);
    reply = { ok: false, reason: 'Not sent: the share sheet was closed.' };
    await ui.click(email);
    assert.match(ui.text(), /Not sent: the share sheet was closed\./);
    assert.doesNotMatch(ui.text(), /attached/i);
  } finally { ui.close(); }
});

test('an emptied description is sent as "" so it is cleared', async () => {
  const ui = await mount({ rpc: n => (n === 'upsert_special_product_from_product' ? { data: 'sp-1', error: null } : undefined) });
  try {
    const edit = [...ui.node.querySelectorAll('tbody tr button')].find(b => b.className.includes('btn-icon') && !b.className.includes('btn-danger'));
    await ui.click(edit);
    const dlg = ui.dialog('Edit Special Product');
    const area = fieldIn(dlg, 'Description');
    assert.equal(area.value, 'Old note');
    await ui.set(area, '   ');
    await ui.click([...dlg.querySelectorAll('button')].find(b => b.textContent === 'Save'));
    const args = ui.rpcCalls.find(([n]) => n === 'upsert_special_product_from_product')[1];
    assert.equal(args.p_description, '', 'not null, which would keep the old text');
  } finally { ui.close(); }
});

test('Return asks before a stray tap loses it', async () => {
  const ui = await mount();
  try {
    await ui.tab('Rentals');
    const row = [...ui.node.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('RNT-2026-9901'));
    await ui.click([...row.querySelectorAll('button')].find(b => b.textContent === 'Return'));
    const dlg = ui.dialog('Return — RNT-2026-9901');
    assert.ok(dlg);
    const before = confirms;
    await ui.click(dlg.closest('[data-modal-overlay]'));
    assert.equal(confirms, before + 1, 'asked');
    assert.ok(ui.dialog('Return — RNT-2026-9901'), 'still open');
  } finally { ui.close(); }
});

test('the old windows and their server calls are gone; the layout wraps on a phone', async () => {
  const page = await read('src/pages/SpecialPage.tsx');
  for (const fn of ['create_special_sale', 'create_rental', 'pay_rental', 'activate_rental', 'cancel_rental',
                    'cancel_special_sale', 'pay_special_with_credit', 'customer_credit_balances']) {
    assert.doesNotMatch(page, new RegExp(`rpc\\('${fn}'`), `the page still calls ${fn}`);
  }
  for (const words of ['title="New Special Sale"', 'title="New Rental"', 'title={`Pay Rental', '>Activate</button>',
                       'Pay with wallet credit', 'Create Rental (Draft)', 'Complete Sale']) {
    assert.ok(!page.includes(words), `${words} is still on the page`);
  }
  assert.match(page, /flexWrap: 'wrap', alignItems: 'center'/, 'the tab row wraps');
  assert.match(page, /display: 'flex', gap: 10, flexWrap: 'wrap'/, 'the header actions wrap');
  assert.match(page, /className="special-queue-grid special-queue-row"/);
  assert.doesNotMatch(page, /minmax\(260px, 2fr\) minmax\(280px, 1\.4fr\)/, 'the 600 px grid is gone');
  assert.match(page, /confirmClose=\{!done\}/, 'Return asks while not done');
  assert.match(page, /confirmClose=\{termsChanged\(rentForm, rentOpened\)\}/);
  const css = await read('src/styles/globals.css');
  assert.match(css, /@media \(max-width: 640px\) \{\s*\.special-queue-grid \{ grid-template-columns: minmax\(0, 1fr\);/);
  // The rendered page: no old window opens, and an old cancelled sale shows no Cancel button.
  const ui = await mount({ data: db({ special_sales: [{ id: 's-1', sale_no: 'SPS-2026-9901', special_product_id: 'sp-1',
    customer_id: 'c-1', store_id: 'st-a', invoice_id: 'inv-1', status: 'paid', quantity: 1, unit_price: 100, total_amount: 100,
    created_at: '2026-10-01T02:00:00Z' }] }) });
  try {
    await ui.tab('Sales');
    const row = [...ui.node.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('SPS-2026-9901'));
    assert.ok(row, 'an old sale is still listed');
    assert.deepEqual([...row.querySelectorAll('button')].map(b => b.textContent.trim() || b.getAttribute('aria-label')),
      ['Print', 'Send SPS-2026-9901 by WhatsApp', 'Email SPS-2026-9901 from this device'], 'print and send only');
    await ui.click([...row.querySelectorAll('button')].find(b => b.textContent.includes('Print')));
    assert.ok(globalThis.__PRINTS__[0].headerLines.includes('Invoice INV-2026-9901'), 'a sale receipt names its invoice too');
    assert.equal(globalThis.__PRINTS__[0].branding.name, 'Fixture Main Store');
  } finally { ui.close(); }
});
