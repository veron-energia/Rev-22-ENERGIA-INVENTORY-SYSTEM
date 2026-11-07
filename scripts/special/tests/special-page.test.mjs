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
//   494              Consignment: a ticked product is on its own tab; its sale
//                    can go to a supplier linked on the Products page, with a
//                    note of where to deliver; a rental and any other product
//                    are offered none; the Sales tab and its Excel name the
//                    supplier, and say when the invoice was taken back.
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
               'Printer', 'MessageCircle', 'Mail', 'Lock', 'Truck'];
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
  excel: 'export const ExcelExportButton = p => { globalThis.__EXCEL__ = p; return null; };',
  search: 'export const SearchSelect = p => { globalThis.__PICK__ = p.onChange; return null; }; export const CustomerSearchSelect = () => null;',
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

// ── 494: Consignment ─────────────────────────────────────────────────────
const CONSIGNED = { id: 'sp-2', product_id: 'p-2', name: 'Fixture Infrared Bed', sku: 'FX-B', description: null, sale_price: 900,
  rate_day: 40, rate_week: 0, rate_month: 0, rate_year: 0, late_fee_per_day: 0, is_active: true, is_consignment: true };
const UNLINKED = { ...CONSIGNED, id: 'sp-3', product_id: 'p-3', name: 'Fixture Unlinked Chair', sku: 'FX-C' };
const SUPPLIERS = [
  { id: 'sup-b', name: 'Fixture Supplier B', phone: '+61255500101', is_active: true, deleted_at: null },
  { id: 'sup-a', name: 'Fixture Supplier A', phone: null, is_active: true, deleted_at: null },
  { id: 'sup-off', name: 'Fixture Supplier Off', phone: null, is_active: false, deleted_at: null },
  { id: 'sup-gone', name: 'Fixture Supplier Gone', phone: null, is_active: true, deleted_at: '2026-10-01T02:00:00Z' },
  { id: 'sup-other', name: 'Fixture Supplier Other', phone: null, is_active: true, deleted_at: null },
];
const LINKS = [
  { product_id: 'p-2', supplier_id: 'sup-b' }, { product_id: 'p-2', supplier_id: 'sup-a' },
  { product_id: 'p-2', supplier_id: 'sup-off' }, { product_id: 'p-2', supplier_id: 'sup-gone' },
  { product_id: 'p-1', supplier_id: 'sup-other' },
];
const BUYER = { id: 'c-2', full_name: 'Fixture Buyer', phone: '+61255500102', email: 'buyer@example.invalid' };
const SALE = over => ({ id: 's-9', sale_no: 'SPS-2026-9909', special_product_id: 'sp-2', customer_id: 'c-2', store_id: 'st-a',
  invoice_id: 'inv-1', status: 'pending', quantity: 1, unit_price: 900, total_amount: 900, warehouse_id: null, source_store_id: null,
  supplier_id: null, deliver_to: null, created_at: '2026-10-17T02:00:00Z', ...over });
const SALE_WAITING = { doc_kind: 'special_sale', doc_id: 's-9', doc_no: 'SPS-2026-9909', invoice_no: 'INV-2026-9901', special_product_id: 'sp-2',
  product_name: 'Fixture Infrared Bed', customer_name: 'Fixture Buyer', store_name: 'Fixture Main Store', quantity: 1, created_at: '2026-10-17T02:00:00Z' };
const STOCK_AT_WH = { location_type: 'warehouse', warehouse_id: 'wh-1', warehouse_name: 'Fixture Warehouse', on_hand: 3, reserved: 0, available: 3 };
function consignmentDb(over = {}) {
  const base = db();
  return db({ special_products: [...base.special_products, CONSIGNED, UNLINKED], suppliers: SUPPLIERS, product_suppliers: LINKS,
    products: [{ id: 'p-1', default_cost_price: 300 }, { id: 'p-2', default_cost_price: 450 }],
    customers: [...base.customers, BUYER], special_sales: [SALE()], ...over });
}
const openWaiting = ui => ui.click([...ui.node.querySelectorAll('button')].find(b => /Waiting for a warehouse/.test(b.textContent)));
const queueRow = (ui, docNo) => [...ui.node.querySelectorAll('.special-queue-row')].find(r => r.textContent.includes(docNo));
const supplierOptions = row => [...(row.querySelector('optgroup')?.querySelectorAll('option') ?? [])].map(o => o.textContent);
const waitingRpc = (list, extra = () => undefined) => (n, a) => {
  if (n === 'special_docs_awaiting_fulfilment') return { data: list(), error: null };
  return extra(n, a);
};
const tableNames = ui => [...ui.node.querySelectorAll('tbody tr')].map(tr => tr.querySelector('strong')?.textContent);
// As the browser sends them: the page reads the dropdown's value inside its state
// update, by when a simulated event has been put back to the old value.
const choose = async (el, value) => {
  assert.ok(el, 'the dropdown exists');
  el.value = value;
  await act(async () => { el.dispatchEvent(new dom.window.Event('change', { bubbles: true })); });
};

test('Consignment: a ticked product is on the Consignment tab only, with its suppliers; the Catalog keeps the rest', async () => {
  const ui = await mount({ data: consignmentDb() });
  try {
    assert.deepEqual(tableNames(ui), ['Fixture Machine'], 'the Catalog has the unticked product alone');
    assert.match(ui.text(), /Special products: sold directly or rented \(fee upfront, late fee at return\)\./);
    assert.doesNotMatch(ui.text(), /Warehouse-only|No commission applies/, 'a supplier can send it, and it earns as its product does (489)');
    assert.ok(ui.button('Add Special Product'));
    assert.equal(ui.button('Add Consignment Product'), undefined);
    assert.ok(![...ui.node.querySelectorAll('thead th')].some(th => th.textContent === 'Suppliers'), 'no Suppliers column on the Catalog');
    await ui.tab('Consignment');
    assert.deepEqual(tableNames(ui), ['Fixture Infrared Bed', 'Fixture Unlinked Chair']);
    assert.ok(ui.button('Add Consignment Product'));
    assert.equal(ui.button('Add Special Product'), undefined);
    const [linked, none] = ui.node.querySelectorAll('tbody tr');
    assert.match(linked.textContent, /Fixture Supplier A, Fixture Supplier B/, 'its active suppliers, by name');
    assert.doesNotMatch(linked.textContent, /Supplier (Off|Gone|Other)/, 'not one closed, deleted or of another product');
    assert.match(none.textContent, /None yet: link one on the Products page/);
  } finally { ui.close(); }
  // With nothing ticked, the tab says so and the Catalog is as it was.
  const empty = await mount();
  try {
    assert.deepEqual(tableNames(empty), ['Fixture Machine'], 'a product with no tick at all stays on the Catalog');
    await empty.tab('Consignment');
    assert.match(empty.text(), /No consignment products yet/);
  } finally { empty.close(); }
});

test('Waiting list: the sale of a consignment product offers its suppliers; a rental and any other product offer none', async () => {
  const list = [SALE_WAITING,
    { ...SALE_WAITING, doc_id: 's-8', doc_no: 'SPS-2026-9908', special_product_id: 'sp-1', product_name: 'Fixture Machine' },
    { ...WAITING, doc_id: 'r-8', doc_no: 'RNT-2026-9908', special_product_id: 'sp-2', product_name: 'Fixture Infrared Bed' }];
  const ui = await mount({ data: consignmentDb(), rpc: waitingRpc(() => list) });
  try {
    await openWaiting(ui);
    assert.match(ui.text(), /Choosing a supplier takes no stock: the supplier sends it directly\./);
    const sale = queueRow(ui, 'SPS-2026-9909');
    assert.equal(sale.querySelector('optgroup').label, 'Supplier sends it directly');
    assert.deepEqual(supplierOptions(sale), ['🚚 Fixture Supplier A', '🚚 Fixture Supplier B — +61255500101'],
      'by name, with the phone to call, and none that is closed, deleted or of another product');
    assert.equal(sale.querySelector('select option').textContent, 'Choose a location or supplier…');
    assert.deepEqual(supplierOptions(queueRow(ui, 'SPS-2026-9908')), [], 'a product not ticked: no supplier, though one is linked');
    assert.deepEqual(supplierOptions(queueRow(ui, 'RNT-2026-9908')), [], 'a rental of a ticked product: no supplier');
    assert.doesNotMatch(queueRow(ui, 'RNT-2026-9908').textContent, /No supplier is linked/);
    assert.doesNotMatch(queueRow(ui, 'SPS-2026-9908').textContent, /No supplier is linked/);
  } finally { ui.close(); }
});

test('Release to a supplier: the note is trimmed, no stock call is made, the choice goes and the list reloads', async () => {
  let list = [SALE_WAITING];
  const ui = await mount({ data: consignmentDb(), rpc: waitingRpc(() => list, n => {
    if (n === 'release_special_sale_to_supplier') { list = []; return { data: { success: true }, error: null }; }
    return undefined;
  }) });
  try {
    await openWaiting(ui);
    const row = () => queueRow(ui, 'SPS-2026-9909');
    const release = () => [...row().querySelectorAll('button')].find(b => b.textContent === 'Release');
    assert.equal(release().disabled, true, 'nothing chosen yet');
    assert.equal(row().querySelector('input[aria-label^="Deliver to"]'), null, 'no note until a supplier is chosen');
    await choose(row().querySelector('select'), 'supplier:sup-b');
    assert.equal(release().disabled, false, 'a supplier needs no stock on hand');
    assert.match(row().textContent, /Supplier's phone: \+61255500101\. Customer's phone: \+61255500102\. No stock moves\./,
      'the dropdown can cut the supplier\'s phone off, so it is said in full');
    const note = row().querySelector('input[aria-label="Deliver to, for SPS-2026-9909"]');
    assert.equal(note.maxLength, 500);
    await ui.set(note, '  12 Example Road, Sydney  ');
    const waits = ui.count('rpc:special_docs_awaiting_fulfilment');
    await ui.click(release());
    assert.deepEqual(ui.rpcCalls.find(([n]) => n === 'release_special_sale_to_supplier')[1],
      { p_sale_id: 's-9', p_supplier_id: 'sup-b', p_deliver_to: '12 Example Road, Sydney' });
    assert.equal(ui.count('rpc:fulfil_special_doc'), 0, 'the stock call is not made');
    assert.ok(ui.count('rpc:special_docs_awaiting_fulfilment') > waits, 'the list reloads');
    assert.equal(ui.dialog('Waiting for a warehouse'), undefined, 'nothing left: the window closes');
  } finally { ui.close(); }
});

test('Release to a supplier: no note sends null; a refusal stays on the list in the window; a warehouse goes as before', async () => {
  let reply = { data: null, error: { message: 'Fixture Supplier A is not linked to this product on the Products page.' } };
  const ui = await mount({ data: consignmentDb(), rpc: waitingRpc(() => [SALE_WAITING], n => {
    if (n === 'release_special_sale_to_supplier') return reply;
    if (n === 'special_product_availability') return { data: [STOCK_AT_WH], error: null };
    if (n === 'fulfil_special_doc') return { data: { success: true }, error: null };
    return undefined;
  }) });
  try {
    await openWaiting(ui);
    const row = () => queueRow(ui, 'SPS-2026-9909');
    const release = () => [...row().querySelectorAll('button')].find(b => b.textContent === 'Release');
    await choose(row().querySelector('select'), 'supplier:sup-a');
    assert.doesNotMatch(row().textContent, /Supplier's phone/, 'a supplier with no phone on file: not said');
    await ui.set(row().querySelector('input[aria-label^="Deliver to"]'), '   ');
    await ui.click(release());
    assert.deepEqual(ui.rpcCalls.find(([n]) => n === 'release_special_sale_to_supplier')[1],
      { p_sale_id: 's-9', p_supplier_id: 'sup-a', p_deliver_to: null }, 'a blank note is no note');
    assert.match(ui.dialog('Waiting for a warehouse').textContent, /is not linked to this product on the Products page/);
    assert.equal(row().querySelector('select').value, 'supplier:sup-a', 'still chosen, to try again');
    // The same sale from a warehouse: fulfil_special_doc, as any sale.
    await choose(row().querySelector('select'), 'warehouse:wh-1');
    assert.equal(row().querySelector('input[aria-label^="Deliver to"]'), null, 'the note goes with the supplier');
    await ui.click(release());
    assert.deepEqual(ui.rpcCalls.find(([n]) => n === 'fulfil_special_doc')[1],
      { p_doc_kind: 'special_sale', p_doc_id: 's-9', p_warehouse_id: 'wh-1', p_location_type: 'warehouse' });
    assert.equal(ui.rpcCalls.filter(([n]) => n === 'release_special_sale_to_supplier').length, 1, 'no second supplier call');
  } finally { ui.close(); }
});

test('Waiting list: a consignment sale with no supplier linked says where to link one, and needs stock as any sale', async () => {
  const waiting = { ...SALE_WAITING, doc_id: 's-7', doc_no: 'SPS-2026-9907', special_product_id: 'sp-3', product_name: 'Fixture Unlinked Chair' };
  const ui = await mount({ data: consignmentDb(), rpc: waitingRpc(() => [waiting]) });
  try {
    await openWaiting(ui);
    const row = queueRow(ui, 'SPS-2026-9907');
    assert.match(row.textContent, /No supplier is linked to this product yet\. Link one on the Products page\./);
    assert.deepEqual(supplierOptions(row), []);
    assert.equal(row.querySelector('select option').textContent, 'Nowhere holds this');
    assert.equal([...row.querySelectorAll('button')].find(b => b.textContent === 'Release').disabled, true);
  } finally { ui.close(); }
});

test('Waiting list: short of stock, a sale a supplier can send is not told to add stock; any other sale still is', async () => {
  const short = { ...STOCK_AT_WH, on_hand: 1, reserved: 1, available: 0 };
  const list = [SALE_WAITING, { ...SALE_WAITING, doc_id: 's-8', doc_no: 'SPS-2026-9908', special_product_id: 'sp-1', product_name: 'Fixture Machine' }];
  const ui = await mount({ data: consignmentDb(), rpc: waitingRpc(() => list,
    n => (n === 'special_product_availability' ? { data: [short], error: null } : undefined)) });
  try {
    await openWaiting(ui);
    const consigned = () => queueRow(ui, 'SPS-2026-9909');
    assert.doesNotMatch(consigned().textContent, /Add stock/);
    assert.match(queueRow(ui, 'SPS-2026-9908').textContent, /Add stock, or approve\/reject the transfers holding it\./);
    // The short location is still not enough, supplier or no supplier.
    await choose(consigned().querySelector('select'), 'warehouse:wh-1');
    assert.equal([...consigned().querySelectorAll('button')].find(b => b.textContent === 'Release').disabled, true);
  } finally { ui.close(); }
});

test('Sales tab: From names the supplier, or where it left; the note and a taken-back invoice show on supplier sales alone', async () => {
  const sales = [
    SALE({ id: 's-1', sale_no: 'SPS-2026-9901', status: 'completed', supplier_id: 'sup-a', deliver_to: '12 Example Road', invoice_id: 'inv-r' }),
    SALE({ id: 's-2', sale_no: 'SPS-2026-9902', status: 'completed', supplier_id: 'sup-b', invoice_id: 'inv-c' }),
    SALE({ id: 's-3', sale_no: 'SPS-2026-9903', status: 'completed', supplier_id: 'sup-b', invoice_id: 'inv-p' }),
    SALE({ id: 's-4', sale_no: 'SPS-2026-9904', status: 'completed', warehouse_id: 'wh-1', invoice_id: 'inv-r' }),
    SALE({ id: 's-5', sale_no: 'SPS-2026-9905', status: 'completed', source_store_id: 'st-b', invoice_id: 'inv-p' }),
  ];
  const invoices = [{ id: 'inv-r', invoice_no: 'INV-2026-9911', status: 'refunded' }, { id: 'inv-c', invoice_no: 'INV-2026-9912', status: 'cancelled' },
                    { id: 'inv-p', invoice_no: 'INV-2026-9913', status: 'paid' }];
  const ui = await mount({ data: consignmentDb({ special_sales: sales, invoices }) });
  try {
    await ui.tab('Sales');
    const row = no => [...ui.node.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes(no));
    const fromHeader = [...ui.node.querySelectorAll('thead th')].findIndex(th => th.textContent === 'From');
    assert.ok(fromHeader >= 0, 'the column is From: not every sale leaves a warehouse');
    const from = no => row(no).querySelectorAll('td')[fromHeader].textContent;
    assert.equal(from('SPS-2026-9901'), 'Supplier: Fixture Supplier ADeliver to: 12 Example Road');
    assert.equal(from('SPS-2026-9902'), 'Supplier: Fixture Supplier B');
    assert.equal(from('SPS-2026-9904'), 'Fixture Warehouse');
    assert.equal(from('SPS-2026-9905'), 'Fixture Roadshow Van', 'released from a store: the store');
    assert.match(row('SPS-2026-9901').textContent, /ReleasedInvoice refunded/);
    assert.match(row('SPS-2026-9902').textContent, /ReleasedInvoice cancelled/);
    assert.doesNotMatch(row('SPS-2026-9903').textContent, /Invoice (refunded|cancelled)/, 'a paid invoice: nothing to say');
    assert.doesNotMatch(row('SPS-2026-9904').textContent, /Invoice (refunded|cancelled)/, 'from a warehouse: as it always read');
    // A receipt names no supplier: the customer's paper is as it was.
    await ui.click([...row('SPS-2026-9901').querySelectorAll('button')].find(b => b.textContent.includes('Print')));
    assert.doesNotMatch(JSON.stringify(globalThis.__PRINTS__[0]), /Supplier|Example Road/);
  } finally { ui.close(); }
});

test("Excel: the Sales tab's columns give the list per supplier; the Consignment tab's its products and suppliers", async () => {
  const sale = SALE({ status: 'completed', supplier_id: 'sup-a', deliver_to: '12 Example Road', invoice_id: 'inv-2' });
  const ui = await mount({ data: consignmentDb({ special_sales: [sale] }) });
  const cell = (r, header) => globalThis.__EXCEL__.columns.find(c => c.header === header)?.value(r);
  try {
    assert.deepEqual(globalThis.__EXCEL__.rows.map(p => p.name), ['Fixture Machine'], 'the Catalog: what the tab lists');
    assert.equal(cell(CONSIGNED, 'Suppliers'), undefined, 'no Suppliers column on the Catalog');
    await ui.tab('Consignment');
    assert.deepEqual(globalThis.__EXCEL__.rows.map(p => p.name), ['Fixture Infrared Bed', 'Fixture Unlinked Chair']);
    assert.equal(cell(CONSIGNED, 'Suppliers'), 'Fixture Supplier A, Fixture Supplier B');
    await ui.tab('Sales');
    assert.equal(cell(sale, 'Supplier'), 'Fixture Supplier A');
    assert.equal(cell(sale, 'Deliver to'), '12 Example Road');
    assert.equal(cell(sale, 'Product cost now'), 450);
    assert.equal(cell(sale, 'Invoice status'), 'cancelled');
    const plain = SALE({ status: 'completed', warehouse_id: 'wh-1', special_product_id: 'sp-3', invoice_id: null });
    assert.equal(cell(plain, 'Supplier'), '');
    assert.equal(cell(plain, 'Deliver to'), '');
    assert.equal(cell(plain, 'Product cost now'), 0, 'a product with no cost on file');
    assert.equal(cell(plain, 'Invoice status'), '');
  } finally { ui.close(); }
});

test('The form: the Consignment tick is sent after the save, only when it changed, and says where the product went', async () => {
  const replies = { upsert_special_product_from_product: () => ({ data: 'sp-new', error: null }),
                    set_special_product_consignment: () => ({ data: null, error: null }) };
  const ui = await mount({ data: consignmentDb(), rpc: (n, a) => replies[n]?.(a) });
  const inTable = name => [...ui.node.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes(name));
  const edit = name => ui.click([...inTable(name).querySelectorAll('button')].find(b => b.className.includes('btn-icon') && !b.className.includes('btn-danger')));
  const tick = dlg => [...dlg.querySelectorAll('label')].find(l => l.textContent.startsWith('Consignment:')).querySelector('input');
  const save = dlg => ui.click([...dlg.querySelectorAll('button')].find(b => b.textContent === 'Save'));
  const tickCalls = () => ui.rpcCalls.filter(([n]) => n === 'set_special_product_consignment').map(([, a]) => a);
  const setTick = async (el, on) => { if (el.checked !== on) await act(async () => { el.click(); }); assert.equal(el.checked, on); };
  try {
    // Saved with the tick as it was: no call, no note.
    await edit('Fixture Machine');
    let dlg = ui.dialog('Edit Special Product');
    assert.equal(tick(dlg).checked, false);
    // 501: the sale price says what a save on the Products page does to it.
    assert.equal(dlg.querySelector('[data-testid="special-sale-price-hint"]').textContent,
      'Saving the product on the Products page sets this to its price there.');
    await save(dlg);
    assert.deepEqual(tickCalls(), [], 'not changed: not sent');
    assert.doesNotMatch(ui.text(), /It is now on the/);
    // Ticked on the Catalog: sent after the save, and it says where it went.
    await edit('Fixture Machine');
    dlg = ui.dialog('Edit Special Product');
    await setTick(tick(dlg), true);
    await save(dlg);
    assert.deepEqual(tickCalls(), [{ p_id: 'sp-1', p_on: true }]);
    const order = ui.rpcCalls.map(([n]) => n);
    assert.ok(order.lastIndexOf('upsert_special_product_from_product') < order.lastIndexOf('set_special_product_consignment'), 'after the save');
    assert.match(ui.text(), /Saved\. It is now on the Consignment tab\./);
    // Unticked on the Consignment tab; opening a tab clears the note first.
    await ui.tab('Consignment');
    assert.doesNotMatch(ui.text(), /It is now on the/);
    await edit('Fixture Infrared Bed');
    dlg = ui.dialog('Edit Consignment Product');
    assert.equal(tick(dlg).checked, true);
    await setTick(tick(dlg), false);
    await save(dlg);
    assert.deepEqual(tickCalls()[1], { p_id: 'sp-2', p_on: false });
    assert.match(ui.text(), /Saved\. It is now on the Catalog tab\./);
    // A new product on the Consignment tab starts ticked, and uses the id the save gave back.
    await ui.click(ui.button('Add Consignment Product'));
    dlg = ui.dialog('Add Consignment Product');
    assert.equal(tick(dlg).checked, true, 'added here, it starts ticked');
    await act(async () => { globalThis.__PICK__('p-9'); });
    const price = fieldIn(dlg, 'Sale Price (S$)');
    Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value').set.call(price, '900');
    await act(async () => { price.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
    await save(dlg);
    assert.deepEqual(tickCalls()[2], { p_id: 'sp-new', p_on: true });
    assert.doesNotMatch(ui.text(), /It is now on the/, 'it is on this tab');
    // A save that is refused sends no tick; a tick that is refused keeps the form open.
    await edit('Fixture Infrared Bed');
    dlg = ui.dialog('Edit Consignment Product');
    await setTick(tick(dlg), false);
    replies.upsert_special_product_from_product = () => ({ data: null, error: { message: 'Set a sale price first.' } });
    await save(dlg);
    assert.equal(tickCalls().length, 3, 'a refused save sends no tick');
    assert.match(ui.dialog('Edit Consignment Product').textContent, /Set a sale price first\./);
    replies.upsert_special_product_from_product = () => ({ data: 'sp-2', error: null });
    replies.set_special_product_consignment = () => ({ data: null, error: { message: 'That special product does not exist.' } });
    await save(ui.dialog('Edit Consignment Product'));
    assert.match(ui.dialog('Edit Consignment Product').textContent, /That special product does not exist\./, 'still open, with the reason');
  } finally { ui.close(); }
});
