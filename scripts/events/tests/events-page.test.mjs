// The Events page, rendered for real against a fake backend.
//
// The actual src/pages/EventsPage.tsx is bundled with esbuild and mounted in
// jsdom. Only the Supabase client, the auth context and xlsx are stubbed: the
// client by a small in-memory backend that records every call, xlsx so an
// export is captured instead of written. Every name, phone and amount below is
// invented.
//
// It checks what the page promises: the list shows each event's days, prices
// (with the early bird) and how full each day is; an event opens on its guest
// list; a free guest is sent as the server expects and a day going over
// capacity is shown as a warning; the door sends the day's code and shows the
// check-in from the server's answer; staff run an event but cannot set one
// up; the guest export has coming / attended / code for every day; the
// sales totals leave out cancelled invoices; and the Website orders tab is
// for Owners, Admins and Managers, shows every order status, creates an
// invoice for the customer chosen (never for a Stripe test payment the
// channel does not accept), says the website fills its workbook's invoice
// numbers itself, asks before the Owner switches it Live and exports its
// orders with the invoice number beside the Stripe checkout. Since 380 it also
// lists staff-link registrations (Cash, PayNow or Bank Transfer, with their
// date paid, reference and the staff member credited), which a Manager
// invoices, links to an invoice already made by hand, or dismisses and
// restores; both exports carry the new columns, and the orders export lists
// every order whatever the status filter. An order says when an invoice made
// by hand has the buyer's phone, one paid other than the price is sent to be
// invoiced by hand and linked, and one refused while the channel was off can
// be linked.
//
// Run: node --test scripts/events/tests/events-page.test.mjs
process.env.TZ = 'America/Los_Angeles'; // west of UTC, where a date-only value parsed as a Date shows a day early

import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://events.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
// Bundled as ESM, React's act() queues each task on a new MessageChannel and
// never closes it; Node's ports then keep the runner alive after the last test.
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
      export { default as EventsPage } from './src/pages/EventsPage';
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
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const utils = {
        json_to_sheet: (body, opts) => ({ body, header: opts && opts.header }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws, name) => { wb.sheets.push({ ws, name }); },
      };
      export const writeFile = (wb, filename) => { globalThis.__exports.push({ filename, sheet: wb.sheets[0] }); };` }));
  } }],
});
const { EventsPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── dates, spelled out independently of the page ───────────────────────────
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const TODAY = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const addDays = (day, n) => { const [y, m, d] = day.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10); };
const utc = day => { const [y, m, d] = day.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); };
const dMon = day => `${utc(day).getUTCDate()} ${MON[utc(day).getUTCMonth()]}`;
const wdDMon = day => `${WD[utc(day).getUTCDay()]} ${dMon(day)}`;
const full = day => `${wdDMon(day)} ${utc(day).getUTCFullYear()}`;
// The event is three weeks out, so the test does not depend on the day it runs.
const D1 = addDays(TODAY, 20), D2 = addDays(TODAY, 21), EB = addDays(TODAY, 10), PAST = addDays(TODAY, -5);

// ── fixture ────────────────────────────────────────────────────────────────
function makeFixture() {
  const event = {
    id: 'ev-1', name: 'Test Open Days', description: 'Invented event for the test.', daily_start: '10:00', daily_end: '19:00',
    early_bird_until: EB, early_bird_percent: '50.00', is_active: true, notes: null, created_at: '2026-09-01T02:00:00Z',
    first_day: D1, last_day: D2,
    // Numbers arrive as numbers or as numeric strings.
    days: [{ day: D1, capacity: null, registered: 3, attended: 1 }, { day: D2, capacity: '4', registered: '4', attended: 0 }],
    stores: [{ id: 'st-1', name: 'North Store' }],
    options: [
      { id: 'op-2', name: '2 Days', days_count: 2, price: '94.00', is_active: true, sort_order: 2, early_bird_price: '47.00', sold: false },
      { id: 'op-1', name: '1 Day', days_count: 1, price: '61.00', is_active: true, sort_order: 1, early_bird_price: '30.50', sold: true },
    ],
    guests: 5, ticket_guests: 3, free_guests: 2, can_manage: true, can_run: true,
  };
  const past = {
    id: 'ev-2', name: 'Old Tea Morning', description: null, daily_start: null, daily_end: null, early_bird_until: null,
    early_bird_percent: null, is_active: false, notes: null, created_at: '2026-08-01T02:00:00Z', first_day: PAST, last_day: PAST,
    days: [{ day: PAST, capacity: 20, registered: 2, attended: 2 }], stores: [{ id: 'st-2', name: 'South Store' }],
    options: [{ id: 'op-9', name: 'Entry', days_count: 1, price: 20, is_active: false, sort_order: 1, early_bird_price: null, sold: false }],
    guests: 2, ticket_guests: 0, free_guests: 2, can_manage: true, can_run: true,
  };
  const day = (d, attended_at = null, check_in_code = null, checked_in_by_name = null) => ({ day: d, attended_at, check_in_code, checked_in_by_name });
  const g = (id, name, extra) => ({
    guest_id: id, name, phone: null, customer_id: null, customer_name: null, source: 'free', status: 'registered', cancelled_reason: null,
    notes: null, registered_by: 'u-staff', registered_by_name: 'Staff One', ticket_option_id: null, ticket_option_name: null,
    invoice_id: null, invoice_no: null, invoice_status: null, invoice_total: null, invoice_paid: null, invoice_store_id: null,
    created_at: '2026-09-20T02:00:00Z', days: [], email: null, order_id: null, payment_methods: null, ...extra,
  });
  const ticket = (no, status, total, paid, option) => ({ source: 'ticket', invoice_id: `inv-${no}`, invoice_no: `INV-TEST-000${no}`,
    invoice_status: status, invoice_total: total, invoice_paid: paid, invoice_store_id: 'st-1',
    ticket_option_id: option === '2 Days' ? 'op-2' : 'op-1', ticket_option_name: option });
  const guests = [
    g('g-1', 'Guest One', { phone: '+65 9123 0001', ...ticket(1, 'paid', '94.00', '94.00', '2 Days'),
      email: 'guest1@tests.invalid', order_id: 'cs_live_testwo10000', payment_methods: 'Stripe (online)',
      days: [day(D1, '2026-09-20T02:04:00Z', 'CD 12', 'Staff One'), day(D2)] }),
    g('g-2', 'Guest Two', { phone: '+65 9123 0002', ...ticket(1, 'paid', '94.00', '94.00', '2 Days'), days: [day(D1), day(D2)] }),
    // 380: the invoice's payment methods may also arrive as a list.
    g('g-3', 'Guest Three', { phone: '+65 9123 0003', ...ticket(2, 'partially_paid', 61, 30, '1 Day'), days: [day(D1)],
      order_id: 'OFF-20260928-0000D1', payment_methods: ['Cash', 'PayNow'] }),
    g('g-4', 'Guest Four', { phone: '+65 9123 0004', customer_id: 'c-1', customer_name: 'Customer One', notes: 'VEG', days: [day(D2)] }),
    g('g-5', 'Guest Five', { notes: 'Free Sock', days: [day(D2)] }),
    g('g-6', 'Guest Six', { phone: '+65 9123 0006', status: 'cancelled', cancelled_reason: 'Cannot come', days: [day(D1)] }),
  ];
  const invoices = [
    { invoice_id: 'inv-1', invoice_no: 'INV-TEST-0001', business_date: addDays(TODAY, -3), store_id: 'st-1', store_name: 'North Store',
      customer_id: 'c-1', customer_name: 'Customer One', status: 'paid', total_amount: '94.00', paid_amount: '94.00', source: 'ticket',
      ticket_people: 2, ticket_total: '94.00' },
    { invoice_id: 'inv-2', invoice_no: 'INV-TEST-0002', business_date: addDays(TODAY, -2), store_id: 'st-1', store_name: 'North Store',
      customer_id: 'c-2', customer_name: 'Customer Two', status: 'partially_paid', total_amount: 61, paid_amount: 30, source: 'ticket',
      ticket_people: 1, ticket_total: 61 },
    { invoice_id: 'inv-3', invoice_no: 'INV-TEST-0003', business_date: addDays(TODAY, -2), store_id: 'st-1', store_name: 'North Store',
      customer_id: 'c-3', customer_name: 'Customer Three', status: 'cancelled', total_amount: 61, paid_amount: 0, source: 'ticket',
      ticket_people: 1, ticket_total: 61 },
    { invoice_id: 'inv-4', invoice_no: 'INV-TEST-0004', business_date: addDays(TODAY, -1), store_id: 'st-1', store_name: 'North Store',
      customer_id: null, customer_name: null, status: 'paid', total_amount: 120, paid_amount: 120, source: 'staff',
      ticket_people: 0, ticket_total: 0 },
  ];
  const profiles = [
    { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true, deleted_at: null },
    { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true, deleted_at: null },
    { id: 'u-inv', full_name: 'Stock Keeper', role: 'inventory_manager', is_active: true, deleted_at: null },
  ];
  const stores = [{ id: 'st-1', name: 'North Store', is_active: true, deleted_at: null }, { id: 'st-2', name: 'South Store', is_active: true, deleted_at: null }];
  const customers = [{ id: 'c-1', full_name: 'Customer One', phone: '+65 9123 0101', email: 'one@tests.invalid', notes: null, deleted_at: null }];
  // Website orders, newest first, one in every status.
  const order = (id, extra) => ({
    id, stripe_session_id: `cs_live_test${id.replace(/\W/g, '')}0000`, livemode: true, status: 'recorded', ticket: 'day1',
    ticket_label: 'Day 1 only', quantity: 1, unit_amount: 61, amount_total: 61, early_bird: false,
    buyer_name: 'Guest', buyer_email: null, buyer_phone: null, checkout_opened_at: null, paid_at: null,
    attendees: null, names_at: null, invoice_id: null, invoice_no: null, review_reason: null, candidates: [], created_at: null, ...extra,
  });
  const web = {
    channel: { key: 'test-channel', mode: 'record_only', allow_test: true, store_name: 'North Store', acting_name: 'Owner One',
      payment_method_name: 'Stripe (online)' },
    can_switch: false,
    orders: [
      // Paid at 01:30 in Singapore: still the day before in UTC and here.
      order('wo-5', { livemode: false, stripe_session_id: 'cs_test_00000005', buyer_name: 'Guest Twenty-Four',
        buyer_phone: '+65 9123 0024', paid_at: '2026-10-04T17:30:00Z', checkout_opened_at: '2026-10-04T17:28:00Z' }),
      order('wo-4', { status: 'refused', ticket: 'day2', ticket_label: 'Day 2 only', unit_amount: 10, amount_total: 10,
        buyer_name: 'Guest Twenty-Three', buyer_phone: '+65 9123 0023', paid_at: '2026-10-03T05:15:00Z',
        review_reason: 'The amount paid does not match the pass price' }),
      // Amounts can arrive as numeric strings.
      order('wo-3', { ticket: 'day2', ticket_label: 'Day 2 only', quantity: '3', unit_amount: '61.00', amount_total: '183.00',
        buyer_name: 'Guest Twenty-One', buyer_phone: '+65 9123 0021', buyer_email: 'guest21@tests.invalid', paid_at: '2026-10-02T10:30:00Z' }),
      order('wo-2', { status: 'needs_review', ticket: 'both', ticket_label: 'Both days', unit_amount: 47, amount_total: 47, early_bird: true,
        buyer_name: 'Guest Twenty-Two', buyer_phone: '+65 9123 0020', buyer_email: 'guest22@tests.invalid', paid_at: '2026-09-21T02:02:00Z',
        attendees: [{ name: 'Guest Twenty-Two', email: 'guest22@tests.invalid', whatsapp: '+65 9123 0020' }], names_at: '2026-09-21T02:05:00Z',
        review_reason: '2 customers have this phone',
        candidates: [
          { customer_id: 'c-2', full_name: 'Customer Two', phone: '+65 9123 0020', email: 'two@tests.invalid', last_invoice_at: '2026-08-14' },
          { customer_id: 'c-3', full_name: 'Customer Three', phone: '+65 9123 0020', email: null, last_invoice_at: null },
        ] }),
      order('wo-1', { status: 'invoiced', quantity: 2, unit_amount: 30.5, amount_total: 61, early_bird: true,
        buyer_name: 'Guest Twenty', buyer_phone: '+65 9123 0030', buyer_email: 'guest30@tests.invalid', paid_at: '2026-09-18T12:44:00Z',
        attendees: [{ name: 'Guest Twenty', email: null, whatsapp: '+65 9123 0030' }, { name: 'Guest Twenty-Five', email: null, whatsapp: null }],
        names_at: '2026-09-18T12:50:00Z', invoice_id: 'inv-101', invoice_no: 'INV-TEST-0101' }),
    ],
  };
  // 380: registrations sent through the website's staff link, one in every
  // state a Manager meets. The OFF ids are invented.
  const door = (id, extra) => order(id, { provider: 'door', door_method: 'cash', payment_reference: null,
    staff_profile_id: null, staff_name: null, ...extra, checkout_opened_at: extra.paid_at, names_at: extra.paid_at });
  const doorOrders = [
    door('wo-d1', { stripe_session_id: 'OFF-20260928-0000D1', door_method: 'paynow', payment_reference: 'PN-TEST-01',
      paid_on: '2026-09-28', paid_at: '2026-09-28T06:05:00Z', staff_profile_id: 'u-staff', staff_name: 'Staff One',
      ticket: 'both', ticket_label: 'Both days', quantity: 2, unit_amount: 47, amount_total: 94, early_bird: true,
      buyer_name: 'Guest Door One', buyer_phone: '+65 9123 4567', buyer_email: 'door1@tests.invalid',
      attendees: [{ name: 'Guest Door One', email: 'door1@tests.invalid', whatsapp: '+65 9123 4567' },
        { name: 'Guest Door Guest', email: null, whatsapp: null }] }),
    door('wo-d2', { stripe_session_id: 'OFF-20260927-0000D2', status: 'needs_review', paid_on: '2026-09-27',
      paid_at: '2026-09-27T09:00:00Z', unit_amount: 50, amount_total: 50, buyer_name: 'Guest Door Two', buyer_phone: '+65 9123 4568',
      attendees: [{ name: 'Guest Door Two', email: null, whatsapp: '+65 9123 4568' }],
      review_reason: 'S$50.00 was paid but the pass costs S$61.00 on that day' }),
    door('wo-d3', { stripe_session_id: 'OFF-20260926-0000D3', status: 'dismissed', door_method: 'bank', payment_reference: 'BT-TEST-03',
      paid_on: '2026-09-26', paid_at: '2026-09-26T03:00:00Z', buyer_name: 'Test Buyer', buyer_phone: '+65 9123 4569',
      attendees: [{ name: 'Test Buyer', email: null, whatsapp: null }], review_reason: 'Test registration' }),
    door('wo-d4', { stripe_session_id: 'OFF-20260925-0000D4', status: 'invoiced', door_method: 'bank', paid_on: '2026-09-25',
      paid_at: '2026-09-25T03:00:00Z', staff_profile_id: 'u-staff', staff_name: 'Staff One', buyer_name: 'Guest Door Four',
      attendees: [{ name: 'Guest Door Four', email: null, whatsapp: null }], invoice_id: 'inv-201', invoice_no: 'INV-TEST-0201' }),
  ];
  return { event, past, guests, invoices, profiles, stores, customers, web, doorOrders };
}

// ── fake backend ───────────────────────────────────────────────────────────
function createBackend(fx, { canManage = true, canSwitch = false } = {}) {
  const b = { calls: [], failures: new Map(), handlers: {} };
  const rpcs = {
    events_list: () => [fx.event, fx.past].map(e => ({ ...e, can_manage: canManage })),
    my_assigned_stores: () => fx.stores.map((s, i) => ({ store_id: s.id, store_name: s.name, is_default: i === 0 })),
    event_guest_list: () => fx.guests,
    event_invoices: () => fx.invoices,
    event_save_guest: () => ({ guest_id: 'g-new', over_capacity: [] }),
    event_check_in: a => ({ guest_id: a.p_guest_id, day: a.p_day,
      attended_at: a.p_attended ? '2026-09-20T02:15:00Z' : null, check_in_code: a.p_attended ? a.p_code : null }),
    event_save: a => a.p_event.id ?? 'ev-new',
    event_set_guest_cancelled: () => null,
    event_delete: () => null,
    web_orders_list: () => ({ ...fx.web, can_switch: canSwitch }),
    web_order_resolve: () => ({ status: 'invoiced', invoice_no: 'INV-TEST-0102', review_reason: null }),
    web_order_link_preview: a => ({ invoice_no: a.p_invoice_no, store: 'North Store', date: '2026-09-28',
      customer_name: 'Customer Door', total: '94.00', paid: '94.00', methods: 'PayNow', people: 2, warnings: [] }),
    web_order_link_invoice: a => ({ status: 'invoiced', invoice_no: a.p_invoice_no }),
    web_order_dismiss: a => ({ status: a.p_dismiss ? 'dismissed' : 'recorded' }),
    web_order_channel_set_mode: a => { fx.web.channel.mode = a.p_mode; return null; },
  };
  const tables = { profiles: fx.profiles, stores: fx.stores, customers: fx.customers };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    or() { return this; }
    order() { return this; }
    limit() { return this; }
    maybeSingle() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
      await Promise.resolve();
      if (b.failures.has(this.name)) return { data: null, error: { message: b.failures.get(this.name) } };
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        return { data: structuredClone(fn(this.args)), error: null };
      }
      const rows = (tables[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
      return { data: structuredClone(this.single ? rows[0] ?? null : rows), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving the page ───────────────────────────────────────────────────────
const USERS = {
  owner: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
  admin: { id: 'u-adm', full_name: 'Admin One', role: 'admin', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true },
  inventory_manager: { id: 'u-inv', full_name: 'Stock Keeper', role: 'inventory_manager', is_active: true },
};
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount({ role = 'manager', setup } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture(), { canManage: ['owner', 'admin', 'manager'].includes(role), canSwitch: role === 'owner' });
  globalThis.__backend = backend; globalThis.__exports = []; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: USERS[role] };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(EventsPage))));
  await tick();
}
const text = () => document.body.textContent;
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const buttons = (scope = document) => [...scope.querySelectorAll('button')];
const button = (label, scope = document) => buttons(scope).find(b => b.textContent.trim() === label);
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype
    : el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick(2);
}
const modal = () => document.querySelector('.modal');
const fieldIn = (scope, label) => {
  const group = [...scope.querySelectorAll('.form-group')].find(g => g.querySelector('label')?.textContent.trim() === label);
  return group?.querySelector('input, textarea, select');
};
const card = name => [...document.querySelectorAll('.events-card')].find(c => c.querySelector('.events-card-name')?.textContent === name);
const guestRows = () => [...document.querySelectorAll('.events-table tbody tr')].map(r => [...r.querySelectorAll('td')].map(td => td.textContent));
const callsOf = name => backend.calls.filter(c => c.name === name);
async function openEvent(name = 'Test Open Days') { await click(card(name)); }
async function openTab(label) { await click(buttons().find(b => b.getAttribute('role') === 'tab' && b.textContent.trim() === label)); }
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
test('the list shows each event with its days, prices, early bird and how full each day is', async () => {
  await mount();
  assert.deepEqual(callsOf('events_list').length, 1);
  const c = card('Test Open Days');
  assert.ok(c, 'the upcoming event is listed');
  const t = c.textContent;
  assert.ok(t.includes(`${wdDMon(D1)} & ${wdDMon(D2)} ${D2.slice(0, 4)}`), `days with weekdays: ${t}`);
  assert.ok(t.includes('10:00–19:00'), 'daily hours');
  assert.ok(t.includes('North Store'), 'the store');
  assert.ok(t.includes(`1 Day S$61.00 · early bird S$30.50 until ${dMon(EB)}`), `1 Day price with early bird: ${t}`);
  assert.ok(t.includes(`2 Days S$94.00 · early bird S$47.00 until ${dMon(EB)}`), '2 Days price with early bird');
  assert.ok(t.indexOf('1 Day S$61.00') < t.indexOf('2 Days S$94.00'), 'options in their order');
  assert.ok(t.includes(`${wdDMon(D1)}: 3 registered`), 'a day without a capacity shows who is registered');
  assert.ok(t.includes(`${wdDMon(D2)}: 4 / 4 · full`), `a full day is marked: ${t}`);
  assert.ok(c.querySelector('.events-chip-full'), 'the full day is highlighted');
  assert.ok(t.includes('On sale'), 'status badge');
  assert.ok(t.includes('5 guests (3 ticket, 2 free)'), 'guest counts');
  assert.ok(!card('Old Tea Morning'), 'a past event is not under Upcoming');
  assert.ok(button('New event'), 'a manager can create an event');

  await click(button('Past'));
  const p = card('Old Tea Morning');
  assert.ok(p && p.textContent.includes('Ended'), 'the past event shows as Ended');
  assert.ok(!card('Test Open Days'), 'the upcoming event is not under Past');
  await click(button('All'));
  assert.ok(card('Old Tea Morning') && card('Test Open Days'), 'All shows both');
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('opening an event shows its guest list, registered guests first', async () => {
  await mount();
  await openEvent();
  assert.deepEqual(callsOf('event_guest_list').map(c => c.args), [{ p_event_id: 'ev-1' }]);
  assert.ok(button('All events'), 'there is a way back');
  const rows = guestRows();
  const names = rows.map(r => r[0]);
  assert.equal(rows.length, 5, 'the cancelled guest is hidden by default');
  assert.ok(!names.some(n => n.includes('Guest Six')));
  const one = rows.find(r => r[0].startsWith('Guest One'));
  assert.ok(one[2].includes(`${wdDMon(D1)} ✓ · CD 12`), `attended day with its code: ${one[2]}`);
  assert.ok(one[3].includes('2 Days · INV-TEST-0001 · Paid'), `ticket: ${one[3]}`);
  const three = rows.find(r => r[0].startsWith('Guest Three'));
  assert.ok(three[3].includes('Part-paid'));
  const four = rows.find(r => r[0].startsWith('Guest Four'));
  assert.ok(four[0].includes('Customer: Customer One'), 'the linked customer is named');
  assert.equal(four[3], 'Free');
  assert.equal(four[5], 'VEG');
  assert.ok(buttons().some(b => b.textContent.trim() === 'Cancel'), 'a free guest can be cancelled');

  await setValue(document.querySelector('select[aria-label="Status"]'), 'cancelled');
  assert.deepEqual(guestRows().map(r => r[0].split('Cancelled')[0]), ['Guest Six']);
  assert.ok(button('Restore'), 'a cancelled free guest can be restored');
  await click(button('Restore'));
  assert.deepEqual(callsOf('event_set_guest_cancelled').at(-1).args, { p_guest_id: 'g-6', p_cancelled: false, p_reason: null });

  await setValue(document.querySelector('select[aria-label="Status"]'), 'registered');
  await setValue(document.querySelector('input[aria-label="Search guests"]'), 'INV-TEST-0002');
  assert.deepEqual(guestRows().map(r => r[0]), ['Guest Three'], 'search finds a guest by invoice no');
  await setValue(document.querySelector('input[aria-label="Search guests"]'), '9123 0004');
  assert.deepEqual(guestRows().map(r => r[0].split('Customer')[0]), ['Guest Four'], 'and by phone');
});

test('adding a free guest sends what the server expects, and a day going over capacity is a warning', async () => {
  await mount({ setup: b => { b.handlers.event_save_guest = () => ({ guest_id: 'g-new', over_capacity: [{ day: D2, capacity: '4', registered: '5' }] }); } });
  await openEvent();
  await click(button('Add guest'));
  const m = modal();
  assert.ok(m, 'the Add guest form opens');
  assert.equal(fieldIn(m, 'Registered by').value, 'u-mgr', 'registered by defaults to the person adding');
  await setValue(fieldIn(m, 'Name *'), '  Guest New ');
  await setValue(fieldIn(m, 'Phone'), '+65 9123 0099');
  await setValue(fieldIn(m, 'Notes'), 'VEG');
  const d2 = m.querySelector(`input[type="checkbox"][aria-label="${wdDMon(D2)}"]`);
  assert.ok(d2.closest('label').textContent.includes('4 / 4'), 'each day shows registered / capacity');
  assert.ok(d2.closest('label').textContent.includes('Full'), 'a full day is marked Full');
  await click(d2);
  assert.ok(modal().textContent.includes('A chosen day is full'), 'choosing a full day warns before saving');
  await click(button('Add guest', document.querySelector('.modal-footer')));

  assert.deepEqual(callsOf('event_save_guest').map(c => c.args), [{ p_guest: {
    event_id: 'ev-1', name: 'Guest New', phone: '+65 9123 0099', customer_id: null, days: [D2], registered_by: 'u-mgr', notes: 'VEG',
  } }]);
  assert.equal(modal(), null, 'the form closes: the guest is saved');
  const warning = document.querySelector('.alert-warning');
  assert.ok(warning, 'an over-capacity warning is shown');
  assert.ok(warning.textContent.includes(`${dMon(D2)} is over capacity: 5 of 4`), warning.textContent);
  assert.equal(callsOf('event_guest_list').length, 2, 'the guest list is reloaded');
});

test('a ticket guest is edited without their days, which come from the invoice', async () => {
  await mount();
  await openEvent();
  await click(document.querySelector('button[aria-label="Edit Guest Three"]'));
  const m = modal();
  assert.ok(m.textContent.includes('Days come from the invoice'), 'the days are explained');
  assert.equal(m.querySelectorAll('input[type="checkbox"]').length, 0, 'and cannot be changed');
  await setValue(fieldIn(m, 'Notes'), 'Late');
  await click(button('Save guest'));
  const sent = callsOf('event_save_guest')[0].args.p_guest;
  assert.equal(sent.id, 'g-3');
  assert.equal(sent.notes, 'Late');
  assert.ok(!('days' in sent), 'no days are sent for a ticket guest');
});

test('the door sends the day\'s code, shows the check-in from the server\'s answer, and can undo it', async () => {
  await mount();
  await openEvent();
  await openTab('Check-in');
  const active = document.querySelector('.events-checkin-day.active');
  assert.ok(active.textContent.startsWith(wdDMon(D1)), 'the first day is chosen when today is not an event day');
  assert.ok(text().includes('Checked in 1 of 3 registered'), text());
  const row = () => document.querySelector('.events-checkin-row[data-guest="g-3"]');
  await setValue(row().querySelector('input[aria-label="Code for Guest Three"]'), 'CD 12');
  await click(button('Check in', row()));
  assert.deepEqual(callsOf('event_check_in').map(c => c.args), [{ p_guest_id: 'g-3', p_day: D1, p_attended: true, p_code: 'CD 12' }]);
  assert.ok(row().classList.contains('done'), 'the row shows as checked in');
  assert.ok(row().textContent.includes('In at 10:15 · CD 12'), `Singapore time and code: ${row().textContent}`);
  assert.ok(text().includes('Checked in 2 of 3 registered'), 'the counter follows');
  assert.equal(callsOf('event_guest_list').length, 1, 'no reload between two people at the door');

  await click(button('Undo', row()));
  assert.deepEqual(callsOf('event_check_in').at(-1).args, { p_guest_id: 'g-3', p_day: D1, p_attended: false, p_code: null });
  assert.ok(!row().classList.contains('done'));
  assert.ok(button('Check in', row()), 'the row can be checked in again');

  // The other day, and a refusal shown on the row itself.
  await click(buttons().find(b => b.classList.contains('events-checkin-day') && b.textContent.startsWith(wdDMon(D2))));
  assert.ok(text().includes('Checked in 0 of 4 registered (capacity 4)'), text());
  backend.failures.set('event_check_in', 'Guest Five is not registered (cancelled)');
  const five = document.querySelector('.events-checkin-row[data-guest="g-5"]');
  await click(button('Check in', five));
  assert.ok(five.querySelector('[role="alert"]').textContent.includes('Guest Five is not registered'), 'the error is shown inline');
  await setValue(document.querySelector('input[aria-label="Find a guest"]'), 'four');
  assert.deepEqual([...document.querySelectorAll('.events-checkin-name')].map(n => n.textContent), ['Guest Four']);
});

test('staff run an event but cannot set one up; other roles have no access', async () => {
  await mount({ role: 'staff' });
  assert.ok(card('Test Open Days'), 'staff see the event at their store');
  assert.ok(!button('New event'), 'no New event for staff');
  await openEvent();
  assert.ok(!button('Edit'), 'no Edit for staff');
  assert.ok(!button('Delete'), 'no Delete for staff');
  assert.ok(button('Add guest'), 'staff add free guests');
  await openTab('Check-in');
  assert.ok(button('Check in'), 'staff check people in');
  assert.equal(callsOf('my_assigned_stores').length, 0, 'staff never load the editor\'s stores');

  await mount({ role: 'inventory_manager' });
  assert.ok(text().includes('Access restricted'));
  assert.equal(backend.calls.filter(c => c.kind === 'rpc').length, 0, 'nothing is asked of the server');
});

test('the guest export has the guest, then coming / attended / code for every day', async () => {
  await mount();
  await openEvent();
  globalThis.__exports = [];
  await click(button('Export Excel'));
  const exported = globalThis.__exports.at(-1);
  assert.ok(exported, 'the guest list exports');
  assert.deepEqual(exported.sheet.ws.header, [
    'Name', 'Phone', 'Email', 'Customer', 'Type', 'Ticket option', 'Invoice no', 'Order ID', 'Invoice status', 'Paid',
    'Payment method', 'Registered by', 'Notes', 'Status',
    `${dMon(D1)} coming`, `${dMon(D1)} attended`, `${dMon(D1)} code`,
    `${dMon(D2)} coming`, `${dMon(D2)} attended`, `${dMon(D2)} code`,
  ]);
  const body = exported.sheet.ws.body;
  assert.equal(body.length, 5, 'the rows on screen: registered guests');
  const one = body.find(r => r.Name === 'Guest One');
  assert.equal(one.Type, 'Ticket');
  assert.equal(one.Paid, 94, 'paid is a number');
  assert.equal(one['Invoice status'], 'Paid');
  assert.equal(one[`${dMon(D1)} coming`], 'Y');
  assert.equal(one[`${dMon(D1)} attended`], '10:04');
  assert.equal(one[`${dMon(D1)} code`], 'CD 12');
  // 380: who to write to, the website order behind the ticket and how it was paid.
  assert.deepEqual([one.Email, one['Order ID'], one['Payment method']], ['guest1@tests.invalid', 'cs_live_testwo10000', 'Stripe (online)']);
  const three = body.find(r => r.Name === 'Guest Three');
  assert.deepEqual([three.Email, three['Order ID'], three['Payment method']], ['', 'OFF-20260928-0000D1', 'Cash, PayNow'],
    'a list of payment methods is joined');
  const four = body.find(r => r.Name === 'Guest Four');
  assert.equal(four.Type, 'Free');
  assert.equal(four.Paid, '', 'a free guest has no payment');
  assert.equal(four[`${dMon(D1)} coming`], 'N');
  assert.equal(four[`${dMon(D2)} coming`], 'Y');
  assert.equal(four.Notes, 'VEG');
  assert.deepEqual([four.Email, four['Order ID'], four['Payment method']], ['', '', ''], 'a free guest has none of them');
});

test('sales list the event\'s invoices, with totals that leave out cancelled ones', async () => {
  await mount();
  await openEvent();
  await openTab('Sales');
  assert.deepEqual(callsOf('event_invoices').map(c => c.args), [{ p_event_id: 'ev-1' }]);
  const table = document.querySelector('.events-table');
  assert.deepEqual([...table.querySelectorAll('thead th')].map(th => th.textContent),
    ['Invoice no', 'Date', 'Store', 'Customer', 'Status', 'Total', 'Paid', 'Why', 'Ticket people', 'Ticket S$']);
  const rows = [...table.querySelectorAll('tbody tr')].map(r => [...r.querySelectorAll('td')].map(td => td.textContent));
  assert.equal(rows.length, 5, 'four invoices and the totals');
  assert.deepEqual(rows[0].slice(0, 2), ['INV-TEST-0001', full(addDays(TODAY, -3))]);
  assert.equal(rows[0][7], 'Ticket');
  assert.equal(rows[3][7], 'Marked by staff');
  assert.deepEqual(rows[4], ['Total (3 invoices)', 'S$275.00', 'S$244.00', '', '3', 'S$155.00']);
  assert.ok(text().includes('Totals leave out cancelled and refunded invoices (1 here'), 'and it says so');
});

test('the editor checks the obvious, previews the prices and sends the event as the server expects', async () => {
  await mount();
  await click(button('New event'));
  await click(button('Create event'));
  assert.ok(modal().textContent.includes('Give the event a name.'), 'a missing name is caught here');
  assert.equal(callsOf('event_save').length, 0, 'nothing is sent while the form is incomplete');
  await click(button('Cancel', document.querySelector('.modal-footer')));

  await openEvent();
  await click(button('Edit'));
  const m = modal();
  assert.ok(m.textContent.includes(`1 Day: S$61.00 (early bird S$30.50 until ${full(EB)})`), `live preview: ${m.querySelector('[aria-label="Price preview"]').textContent}`);
  const removeButtons = [...m.querySelectorAll('button[aria-label="Remove option"]')];
  assert.equal(removeButtons.length, 2);
  assert.equal(removeButtons[0].disabled, true, 'a sold option cannot be removed');
  assert.equal(removeButtons[1].disabled, false);
  const dayRemovers = [...m.querySelectorAll('button[aria-label="Remove day"]')];
  assert.ok(dayRemovers.every(b => b.disabled), 'days with people registered stay');

  // A price changed; everything else goes back as it came.
  await setValue(m.querySelectorAll('input[aria-label="Price"]')[1], '90');
  await click(button('Save changes'));
  const [{ args }] = callsOf('event_save');
  assert.deepEqual(args.p_event, {
    id: 'ev-1', name: 'Test Open Days', description: 'Invented event for the test.', daily_start: '10:00', daily_end: '19:00',
    early_bird_until: EB, early_bird_percent: 50, is_active: true, notes: null,
    days: [{ day: D1, capacity: null }, { day: D2, capacity: 4 }],
    store_ids: ['st-1'],
    options: [
      { id: 'op-1', name: '1 Day', days_count: 1, price: 61, is_active: true, sort_order: 1 },
      { id: 'op-2', name: '2 Days', days_count: 2, price: 90, is_active: true, sort_order: 2 },
    ],
  });
  assert.equal(modal(), null, 'the editor closes once saved');
  assert.ok(text().includes('Event saved.'));

  // The server's refusal is shown as it is.
  backend.failures.set('event_save', '"1 Day" has been sold, so it cannot be removed. Take it off sale instead.');
  await click(button('Edit'));
  await click(button('Save changes'));
  assert.ok(modal().querySelector('.alert-danger').textContent.includes('Take it off sale instead.'));
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── website orders ─────────────────────────────────────────────────────────
const orderRow = id => document.querySelector(`tr[data-order="${id}"]`);
const cells = row => [...row.querySelectorAll('td')].map(td => td.textContent);
const tab = label => buttons().find(b => b.getAttribute('role') === 'tab' && b.textContent.trim() === label);
const modeSwitch = () => document.querySelector('[role="group"][aria-label="Website orders mode"]');
const footer = () => document.querySelector('.modal-footer');
async function openWebOrders(opts) { await mount(opts); await openEvent(); await openTab('Website orders'); }

test('website orders are for Owners, Admins and Managers only', async () => {
  await mount({ role: 'staff' });
  await openEvent();
  assert.ok(tab('Sales'), 'staff see the other tabs');
  assert.ok(!tab('Website orders'), 'staff do not see Website orders');
  assert.equal(callsOf('web_orders_list').length, 0, 'nothing is asked of the server');
  for (const role of ['manager', 'admin', 'owner']) {
    await mount({ role });
    await openEvent();
    assert.ok(tab('Website orders'), `${role} sees Website orders`);
  }
});

test('website orders show the channel and every order status, and flag test orders', async () => {
  await openWebOrders();
  assert.deepEqual(callsOf('web_orders_list').map(c => c.args), [{ p_event_id: 'ev-1' }]);
  const head = document.querySelector('.events-web-head').textContent;
  for (const bit of ['Record only — no invoices yet', 'Test orders accepted', 'Store: North Store', 'Raised by: Owner One',
    'Payment method: Stripe (online)']) assert.ok(head.includes(bit), `${bit}: ${head}`);
  assert.equal(modeSwitch(), null, 'a Manager cannot switch the channel');
  assert.ok(text().includes('5 orders · 1 invoiced · 2 recorded · 1 needs review · 1 refused · 1 test'), text());

  const table = document.querySelector('.events-table');
  assert.deepEqual([...table.querySelectorAll('thead th')].map(th => th.textContent),
    ['Paid at (SGT)', 'Buyer', 'Pass', 'People', 'Total S$', 'Early bird', 'Status', '']);
  assert.deepEqual([...table.querySelectorAll('tbody tr')].map(r => r.dataset.order), ['wo-5', 'wo-4', 'wo-3', 'wo-2', 'wo-1'], 'newest first');

  const invoiced = cells(orderRow('wo-1'));
  assert.equal(invoiced[0], `${full('2026-09-18')}, 20:44`, 'paid at, on the Singapore clock');
  assert.ok(invoiced[1].includes('Guest Twenty') && invoiced[1].includes('+65 9123 0030') && invoiced[1].includes('guest30@tests.invalid'));
  assert.equal(invoiced[3], 'Guest TwentyGuest Twenty-Five', 'the registered names');
  assert.equal(invoiced[4], 'S$61.00' + '2 × S$30.50');
  assert.equal(invoiced[5], 'Yes');
  assert.equal(invoiced[6], 'Invoiced · INV-TEST-0101');
  assert.equal(orderRow('wo-1').querySelector('a'), null, 'the invoices page has no ?open=, so the number is not a link');
  assert.ok(!button('Create invoice', orderRow('wo-1')), 'an invoiced order is done');

  assert.equal(cells(orderRow('wo-2'))[6], 'Needs review: 2 customers have this phone');
  assert.ok(button('Create invoice', orderRow('wo-2')));
  const recorded = cells(orderRow('wo-3'));
  assert.equal(recorded[3], '3 peopleNames not in yet');
  assert.equal(recorded[4], 'S$183.00' + '3 × S$61.00');
  assert.equal(recorded[6], 'Recorded');
  assert.ok(button('Create invoice', orderRow('wo-3')));
  assert.equal(cells(orderRow('wo-4'))[6], 'Refused: The amount paid does not match the pass price');
  assert.ok(!button('Create invoice', orderRow('wo-4')), 'a refused order cannot be invoiced here');

  const test5 = orderRow('wo-5');
  assert.equal(cells(test5)[0], `${full('2026-10-05')}, 01:30`, 'a payment after midnight in Singapore is on the Singapore day');
  assert.ok(test5.querySelector('.badge[title*="test mode"]')?.textContent === 'Test', 'the test order is flagged');
  assert.ok(!orderRow('wo-3').querySelector('.badge[title*="test mode"]'), 'a live order is not');
  assert.ok(button('Create invoice', test5), 'while test orders are accepted, a test order can be invoiced');
  assert.ok(!text().includes('Test payment — not invoiced'));

  const note = text();
  for (const bit of ['A Stripe or HitPay refund is not brought in: refund its invoice by hand.',
    'Staff-link registrations (paid in cash, by PayNow or by bank transfer) come here too, marked Staff link.',
    'They are never invoiced by themselves, even while the channel is Live: check that the money has arrived, then click Create invoice.',
    'Already invoiced by hand? Use Link invoice.',
    'Amount not the pass price (a discount, say)? Raise the invoice by hand for the amount paid, then use Link invoice.',
    'Dismiss a test registration.',
    "The website fills in its workbook's Invoice No column itself, for website and staff-link orders alike, and adds the tickets sold on the Invoices page"])
    assert.ok(note.includes(bit), bit);
  for (const gone of ['Door sales paid in cash or PayNow are invoiced on the Invoices page', 'does not reach the website\'s workbook',
    'type it into the workbook']) assert.ok(!note.includes(gone), `the old wording is gone: ${gone}`);
  assert.deepEqual(globalThis.__renderErrors, []);

  await mount({ setup: b => { b.handlers.web_orders_list = () => ({ channel: null, can_switch: false, orders: [] }); } });
  await openEvent();
  await openTab('Website orders');
  assert.ok(text().includes('This event has no website channel'), 'an event without a channel says so');
  assert.ok(text().includes('No website orders yet'));
});

test('Create invoice sends the customer chosen, a new customer, or leaves the match to the server', async () => {
  await openWebOrders();
  await click(button('Create invoice', orderRow('wo-2')));
  let m = modal();
  assert.ok(m.textContent.includes('2 customers have this phone'), 'the reason it waits is shown');
  const radios = [...m.querySelectorAll('input[type="radio"]')];
  assert.deepEqual(radios.map(r => r.value), ['customer:c-2', 'customer:c-3', 'new', 'auto']);
  assert.ok(radios.every(r => !r.checked), 'with customers to choose from, nothing is picked for staff');
  const two = radios[0].closest('label').textContent;
  assert.ok(two.includes('Customer Two') && two.includes('+65 9123 0020 · two@tests.invalid') && two.includes(`Last invoice ${full('2026-08-14')}`), two);
  assert.ok(radios[1].closest('label').textContent.includes('No invoices yet'));
  assert.equal(button('Create invoice', footer()).disabled, true, 'nothing is sent until a choice is made');

  await click(radios[0]);
  await click(button('Create invoice', footer()));
  assert.deepEqual(callsOf('web_order_resolve').map(c => c.args), [{ p_order_id: 'wo-2', p_customer_id: 'c-2', p_new_customer: false }]);
  assert.ok(modal().textContent.includes('Invoice INV-TEST-0102 is created.'), 'the result is shown');
  assert.ok(modal().textContent.includes("The website fills this number into its workbook's Invoice No column itself, "
    + 'on the rows with Order ID cs_live_testwo20000, the next time it checks with the inventory.'), modal().textContent);
  assert.equal(callsOf('web_orders_list').length, 2, 'the orders are reloaded');
  assert.equal(callsOf('event_guest_list').length, 2, 'and the guest list, which the invoice adds to');
  await click(button('Close', footer()));
  assert.equal(modal(), null);

  // No candidates: Match automatically is the default. The server may park it.
  backend.handlers.web_order_resolve = () => ({ status: 'needs_review', invoice_no: null, review_reason: '2 customers have this phone' });
  await click(button('Create invoice', orderRow('wo-3')));
  m = modal();
  assert.equal(m.querySelector('input[value="auto"]').checked, true, 'Match automatically is chosen');
  await click(button('Create invoice', footer()));
  assert.deepEqual(callsOf('web_order_resolve').at(-1).args, { p_order_id: 'wo-3', p_customer_id: null, p_new_customer: false });
  assert.ok(modal().querySelector('.alert-warning').textContent.includes('No invoice was created. Needs review: 2 customers have this phone'));
  assert.equal(callsOf('event_guest_list').length, 2, 'no invoice, so the guest list stays');
  await click(button('Close', footer()));

  delete backend.handlers.web_order_resolve;
  await click(button('Create invoice', orderRow('wo-3')));
  await click(modal().querySelector('input[value="new"]'));
  await click(button('Create invoice', footer()));
  assert.deepEqual(callsOf('web_order_resolve').at(-1).args, { p_order_id: 'wo-3', p_customer_id: null, p_new_customer: true });
  await click(button('Close', footer()));

  // A refusal is shown in the form, which stays open.
  backend.failures.set('web_order_resolve', 'This order already has an invoice');
  await click(button('Create invoice', orderRow('wo-5')));
  assert.ok(modal().textContent.includes('A Stripe test order: no money was taken.'));
  await click(button('Create invoice', footer()));
  assert.ok(modal().querySelector('.alert-danger').textContent.includes('This order already has an invoice'));
  assert.ok(button('Create invoice', footer()), 'the form stays to try again');
});

test('a Stripe test order is not offered an invoice while the channel does not accept test orders', async () => {
  const fx = makeFixture();
  fx.web.channel.allow_test = false;
  // Refused at payment, as 372 refuses a test payment the channel does not accept.
  fx.web.orders.push({ ...fx.web.orders.at(-1), id: 'wo-0', livemode: false, stripe_session_id: 'cs_test_00000000', status: 'refused',
    invoice_id: null, invoice_no: null, review_reason: 'A Stripe test payment', buyer_name: 'Guest Nineteen', paid_at: '2026-09-17T03:00:00Z' });
  await openWebOrders({ setup: b => { b.handlers.web_orders_list = () => fx.web; } });
  assert.ok(!document.querySelector('.events-web-head').textContent.includes('Test orders accepted'));

  const test5 = orderRow('wo-5');
  assert.equal(cells(test5)[6], 'Recorded', 'it was recorded while test orders were accepted');
  assert.ok(!button('Create invoice', test5), 'a test order the channel does not accept is not offered an invoice');
  assert.equal(cells(test5)[7], 'Test payment — not invoiced', 'and it says why');
  assert.ok(test5.querySelector('[title*="no money was taken"]'), 'with the reason on hover');

  assert.ok(button('Create invoice', orderRow('wo-3')), 'a live recorded order is still offered one');
  assert.ok(button('Create invoice', orderRow('wo-2')), 'and a live order waiting for review');
  assert.equal(cells(orderRow('wo-0'))[6], 'Refused: A Stripe test payment');
  assert.equal(cells(orderRow('wo-0'))[7], '', 'a refused order says nothing more');
  assert.equal(cells(orderRow('wo-1'))[7], '', 'nor does an invoiced one');
  assert.equal(callsOf('web_order_resolve').length, 0);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('a HitPay order says so: its badge, its sandbox, the channel\'s HitPay method and the export (376)', async () => {
  const fx = makeFixture();
  fx.web.channel.hitpay_payment_method_name = 'HitPay (online)';
  fx.web.orders.push({ ...fx.web.orders.at(-1), id: 'wo-h', provider: 'hitpay', livemode: false,
    stripe_session_id: '9e9be41b-2866-4307-8621-e35c633c431f', status: 'recorded', invoice_id: null, invoice_no: null,
    review_reason: null, buyer_name: 'Guest Hit', paid_at: '2026-09-16T03:00:00Z' });
  await openWebOrders({ setup: b => { b.handlers.web_orders_list = () => fx.web; } });
  const head = document.querySelector('.events-web-head').textContent;
  assert.ok(head.includes('Payment method: Stripe (online) · HitPay orders: HitPay (online)'), head);

  const row = orderRow('wo-h');
  assert.equal(row.querySelector('.badge[title="Paid through HitPay"]')?.textContent, 'HitPay', 'a HitPay order is badged');
  assert.ok(row.querySelector('.badge[title*="HitPay\'s sandbox"]'), 'and its test badge names the sandbox');
  assert.ok(!row.querySelector('.badge[title*="test mode"]'), 'not Stripe\'s test mode');
  assert.ok(!orderRow('wo-3').querySelector('.badge[title="Paid through HitPay"]'), 'a Stripe order has no HitPay badge');

  globalThis.__exports = [];
  await click(button('Export Excel'));
  await click(button('Export 6 row(s)', footer()));
  const body = globalThis.__exports.at(-1).sheet.ws.body;
  assert.equal(body.find(r => r.Buyer === 'Guest Hit')['Paid through'], 'HitPay');
  assert.equal(body.find(r => r.Buyer === 'Guest Hit')['Order ID (checkout)'], '9e9be41b-2866-4307-8621-e35c633c431f');
  assert.equal(body.find(r => r.Buyer === 'Guest Twenty')['Paid through'], 'Stripe');
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('the mode switch is the Owner\'s, and Live and Off are confirmed first', async () => {
  await openWebOrders({ role: 'owner' });
  const sw = modeSwitch();
  assert.ok(sw, 'the Owner can switch the channel');
  assert.deepEqual(buttons(sw).map(b => [b.textContent, b.getAttribute('aria-pressed')]),
    [['Off', 'false'], ['Record only', 'true'], ['Live', 'false']]);

  await click(button('Live', sw));
  assert.ok(modal()?.textContent.includes('Switch website orders to Live?'), 'Live asks first');
  assert.ok(modal().textContent.includes('raised by Owner One at North Store, paid by Stripe (online)'), modal().textContent);
  assert.ok(modal().textContent.includes('An order recorded before now is invoiced if its names come in later and it was paid in the last 7 days'),
    'recorded orders are invoiced once Live when their names come in, if recent (373)');
  assert.ok(modal().textContent.includes('one paid more than 7 days ago shows why first'), modal().textContent);
  assert.ok(modal().querySelector('.alert-warning').textContent.includes('a Stripe test payment or a HitPay sandbox payment will also become an invoice'),
    'with test orders accepted, it says they become invoices too');
  assert.ok(modal().textContent.includes('Registrations through the staff link are never invoiced by themselves'),
    'staff-link registrations still wait for a Manager (380)');
  assert.equal(callsOf('web_order_channel_set_mode').length, 0, 'nothing is switched while it asks');
  await click(button('Cancel', footer()));
  assert.equal(modal(), null);
  assert.equal(callsOf('web_order_channel_set_mode').length, 0, 'Cancel switches nothing');

  await click(button('Live', modeSwitch()));
  await click(button('Switch to Live', footer()));
  assert.deepEqual(callsOf('web_order_channel_set_mode').map(c => c.args), [{ p_key: 'test-channel', p_mode: 'live' }]);
  assert.ok(document.querySelector('.events-web-head').textContent.includes('Live — invoices are created'), 'the new mode is shown');

  await click(button('Off', modeSwitch()));
  assert.ok(modal()?.textContent.includes('Switch website orders off?'), 'Off asks first');
  assert.ok(modal().textContent.includes('every order paid on the website, and every registration sent through its staff link, is refused'),
    modal().textContent);
  assert.ok(modal().textContent.includes('invoiced by hand on the Invoices page'));
  assert.ok(modal().textContent.includes('A staff-link registration invoiced that way is then linked to its invoice here with Link invoice'),
    'and a staff-link one is linked to that invoice afterwards (380)');
  await click(button('Cancel', footer()));
  assert.equal(callsOf('web_order_channel_set_mode').length, 1, 'Cancel leaves it Live');
  await click(button('Off', modeSwitch()));
  await click(button('Switch off', footer()));
  assert.deepEqual(callsOf('web_order_channel_set_mode').at(-1).args, { p_key: 'test-channel', p_mode: 'off' });
  assert.ok(document.querySelector('.events-web-head').textContent.includes('Off'));

  backend.failures.set('web_order_channel_set_mode', 'Only the Owner can switch website orders');
  await click(button('Record only', modeSwitch()));
  assert.equal(modal(), null, 'Record only is not asked');
  assert.ok(document.querySelector('.alert-danger').textContent.includes('Only the Owner can switch website orders'));

  // Without test orders accepted, Live says nothing about them.
  await mount({ role: 'owner', setup: b => { b.handlers.web_orders_list = () => ({ can_switch: true, orders: [],
    channel: { key: 'test-channel', mode: 'record_only', allow_test: false, store_name: 'North Store', acting_name: 'Owner One',
      payment_method_name: 'Stripe (online)' } }); } });
  await openEvent();
  await openTab('Website orders');
  await click(button('Live', modeSwitch()));
  assert.ok(modal()?.textContent.includes('Switch website orders to Live?'));
  assert.ok(!modal().textContent.includes('test payment'), modal().textContent);
});

test('an invoiced order whose names could not go on its ticket line says why', async () => {
  const fx = makeFixture();
  const reason = "The buyer's names are kept here but are not on the invoice: they are for 2 people and its ticket line is for 3";
  fx.web.orders = fx.web.orders.map(o => (o.id === 'wo-1' ? { ...o, review_reason: reason } : o));
  await openWebOrders({ setup: b => { b.handlers.web_orders_list = () => fx.web; } });
  const status = orderRow('wo-1').querySelectorAll('td')[6];
  assert.equal(status.querySelector('.events-status-badge').textContent, 'Invoiced · INV-TEST-0101');
  assert.equal(status.querySelector('.events-web-names-note')?.textContent, reason);
  assert.ok(!button('Create invoice', orderRow('wo-1')), 'it is still done');
  assert.equal(orderRow('wo-2').querySelector('.events-web-names-note'), null, 'a waiting order shows its reason in the badge only');
  assert.equal(orderRow('wo-2').querySelector('.events-web-apply-names'), null);

  // Once staff have fixed the ticket line, a Manager puts the names on from here.
  backend.handlers.web_order_apply_names = () => {
    fx.web.orders = fx.web.orders.map(o => (o.id === 'wo-1' ? { ...o, review_reason: null } : o));
    return { status: 'invoiced', invoice_no: 'INV-TEST-0101', review_reason: null };
  };
  await click(button('Put names on the invoice', orderRow('wo-1')));
  assert.deepEqual(callsOf('web_order_apply_names').map(c => c.args), [{ p_order_id: 'wo-1' }]);
  assert.equal(orderRow('wo-1').querySelector('.events-web-names-note'), null, 'the note clears after the list reloads');
  assert.equal(orderRow('wo-1').querySelector('.events-web-apply-names'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('putting names on shows the server\'s refusal', async () => {
  const fx = makeFixture();
  fx.web.orders = fx.web.orders.map(o => (o.id === 'wo-1' ? { ...o, review_reason: 'The buyer\'s names are kept here but are not on the invoice: it has no ticket line for this pass' } : o));
  await openWebOrders({ setup: b => {
    b.handlers.web_orders_list = () => fx.web;
    b.failures.set('web_order_apply_names', 'Only an invoiced order\'s names can be put on its invoice');
  } });
  await click(button('Put names on the invoice', orderRow('wo-1')));
  assert.ok(document.querySelector('.alert-danger')?.textContent.includes("Only an invoiced order's names can be put on its invoice"), text());
  assert.ok(orderRow('wo-1').querySelector('.events-web-names-note'), 'the note stays');
});

test('the website orders export has one row per order, with its people, amounts and status', async () => {
  await openWebOrders();
  globalThis.__exports = [];
  await click(button('Export Excel'));
  await click(button('Export 5 row(s)', footer()));
  const exported = globalThis.__exports.at(-1);
  assert.ok(exported, 'the orders export');
  assert.ok(exported.filename.startsWith('website-orders-test-open-days-'), exported.filename);
  assert.equal(exported.sheet.name, 'Website orders');
  assert.deepEqual(exported.sheet.ws.header, [
    'Paid at (SGT)', 'Buyer', 'Phone', 'Email', 'Pass', 'People', 'Names', 'Unit S$', 'Total S$', 'Early bird', 'Status',
    'Invoice no', 'Order ID (checkout)', 'Source', 'Paid through', 'Date paid', 'Payment ref', 'Registered by',
    'Reason', 'Test order', 'Checkout opened (SGT)', 'Names received (SGT)',
  ], 'the invoice number sits beside the checkout, which is the Order ID in the website\'s workbook');
  const body = exported.sheet.ws.body;
  assert.equal(body.length, 5);
  assert.deepEqual(body.find(r => r.Buyer === 'Guest Twenty'), {
    'Paid at (SGT)': '2026-09-18 20:44', Buyer: 'Guest Twenty', Phone: '+65 9123 0030', Email: 'guest30@tests.invalid', Pass: 'Day 1 only',
    People: 2, Names: 'Guest Twenty, Guest Twenty-Five', 'Unit S$': 30.5, 'Total S$': 61, 'Early bird': 'Y', Status: 'Invoiced',
    'Invoice no': 'INV-TEST-0101', 'Order ID (checkout)': 'cs_live_testwo10000', Source: 'Website', 'Paid through': 'Stripe',
    'Date paid': '2026-09-18', 'Payment ref': '', 'Registered by': '', Reason: '', 'Test order': 'N',
    'Checkout opened (SGT)': '', 'Names received (SGT)': '2026-09-18 20:50',
  });
  const recorded = body.find(r => r.Buyer === 'Guest Twenty-One');
  assert.deepEqual([recorded.People, recorded['Unit S$'], recorded['Total S$'], recorded.Names], [3, 61, 183, ''], 'numbers are numbers');
  assert.equal(body.find(r => r.Buyer === 'Guest Twenty-Two').Reason, '2 customers have this phone');
  const test5 = body.find(r => r.Buyer === 'Guest Twenty-Four');
  assert.deepEqual([test5['Paid at (SGT)'], test5['Test order'], test5['Checkout opened (SGT)']], ['2026-10-05 01:30', 'Y', '2026-10-05 01:28']);
  assert.equal(test5['Date paid'], '2026-10-05', 'a website order\'s Date paid is the Singapore day it was paid');
});

// ── staff-link registrations (380) ─────────────────────────────────────────
async function openWithDoorOrders(opts = {}) {
  const fx = makeFixture();
  fx.web.orders.push(...fx.doorOrders);
  await openWebOrders({ ...opts, setup: b => { b.handlers.web_orders_list = () => fx.web; opts.setup?.(b); } });
  return fx;
}
const statusFilter = () => document.querySelector('select[aria-label="Order status"]');

test('a staff-link registration shows its method, date paid, reference and who registered it, and waits for a Manager', async () => {
  await openWithDoorOrders();
  assert.ok(text().includes('Showing 8 of 9 orders · 2 invoiced · 3 recorded · 2 need review · 1 refused · 1 dismissed · '
    + '4 through the staff link · 1 test'), text());
  assert.equal(orderRow('wo-d3'), null, 'a dismissed registration is out of sight by default');

  const one = orderRow('wo-d1');
  const c = cells(one);
  assert.equal(c[0], `${full('2026-09-28')}PayNow · ref PN-TEST-01Form sent ${full('2026-09-28')}, 14:05`,
    'the date paid as a calendar day, the method and reference, and when the form was sent on the Singapore clock');
  assert.equal(one.querySelector('.badge[title="Registered through the website\'s staff link"]')?.textContent, 'Staff link');
  assert.ok(!one.querySelector('.badge[title="Paid through HitPay"]') && !one.querySelector('.badge[title*="test mode"]'));
  assert.ok(c[1].includes('+65 9123 4567') && c[1].includes('door1@tests.invalid'), c[1]);
  assert.equal(one.querySelector('.events-web-staff')?.textContent, 'Registered by Staff One');
  assert.equal(c[3], 'Guest Door OneGuest Door Guest', 'named on arrival');
  assert.equal(c[6], 'Recorded', 'never invoiced by itself');
  assert.deepEqual(buttons(one).map(b => b.textContent.trim()), ['Create invoice', 'Link invoice', 'Dismiss']);

  const two = orderRow('wo-d2');
  assert.ok(cells(two)[0].startsWith(`${full('2026-09-27')}Cash`), 'cash, without a reference');
  assert.ok(!cells(two)[0].includes('ref'));
  assert.equal(two.querySelector('.events-web-staff'), null, 'no staff member was chosen');
  assert.equal(cells(two)[6], 'Needs review: S$50.00 was paid but the pass costs S$61.00 on that day');
  assert.deepEqual(buttons(two).map(b => b.textContent.trim()), ['Create invoice', 'Link invoice', 'Dismiss']);

  const four = orderRow('wo-d4');
  assert.ok(cells(four)[0].includes('Bank Transfer'));
  assert.equal(cells(four)[6], 'Invoiced · INV-TEST-0201');
  assert.deepEqual(buttons(four), [], 'an invoiced registration is done');

  // A website order can be linked too, but only a staff-link one is dismissed; a test payment is neither.
  assert.deepEqual(buttons(orderRow('wo-3')).map(b => b.textContent.trim()), ['Create invoice', 'Link invoice']);
  assert.deepEqual(buttons(orderRow('wo-5')).map(b => b.textContent.trim()), ['Create invoice'], 'no real invoice is a test payment\'s');
  assert.deepEqual(buttons(orderRow('wo-4')), [], 'a refused order has no action');

  await setValue(statusFilter(), 'dismissed');
  assert.deepEqual([...document.querySelectorAll('.events-table tbody tr')].map(r => r.dataset.order), ['wo-d3']);
  const three = orderRow('wo-d3');
  assert.ok(three.classList.contains('events-row-cancelled'), 'it is shown set aside');
  assert.equal(cells(three)[6], 'Dismissed: Test registration');
  assert.ok(cells(three)[0].includes('Bank Transfer · ref BT-TEST-03'));
  assert.deepEqual(buttons(three).map(b => b.textContent.trim()), ['Restore']);
  assert.ok(text().includes('Showing 1 of 9 orders'), text());

  await click(button('Restore', three));
  assert.deepEqual(callsOf('web_order_dismiss').map(c => c.args), [{ p_order_id: 'wo-d3', p_reason: null, p_dismiss: false }]);
  assert.equal(callsOf('web_orders_list').length, 2, 'the orders are reloaded');

  await setValue(statusFilter(), 'waiting');
  assert.deepEqual([...document.querySelectorAll('.events-table tbody tr')].map(r => r.dataset.order), ['wo-5', 'wo-3', 'wo-2', 'wo-d1', 'wo-d2']);
  await setValue(statusFilter(), 'all');
  assert.equal(document.querySelectorAll('.events-table tbody tr').length, 9);
  // The actions are the last cell of every row, the one pinned to the table's right edge (events.css).
  const table = document.querySelector('.events-web-table');
  assert.ok(table, 'the website orders table carries the class the pinned column hangs on');
  assert.ok(table.querySelector('thead th:last-child').classList.contains('events-web-actions-cell'));
  for (const row of table.querySelectorAll('tbody tr')) {
    const last = row.querySelector('td:last-child');
    assert.ok(last.classList.contains('events-web-actions-cell'), row.dataset.order);
    assert.ok(buttons(row).every(b => last.contains(b)), `${row.dataset.order}: every action is in the pinned cell`);
  }
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('Create invoice for a staff-link registration shows how it was paid and who it credits, and asks for the money first', async () => {
  await openWithDoorOrders();
  await click(button('Create invoice', orderRow('wo-d1')));
  const m = modal();
  const preview = m.querySelector('.events-preview').textContent;
  assert.ok(preview.includes('Both days × 2 · S$94.00 · early bird'), preview);
  assert.ok(preview.includes(`Staff link OFF-20260928-0000D1 · paid by PayNow on ${full('2026-09-28')} (the invoice is dated that day) · ref PN-TEST-01`), preview);
  assert.ok(preview.includes(`Form sent ${full('2026-09-28')}, 14:05 · registered by Staff One`), preview);
  assert.ok(!preview.includes('checkout opened'), 'a staff-link registration has no checkout');
  const note = m.querySelector('.events-web-door-note').textContent;
  assert.ok(note.includes('Create it only once the money has arrived: the invoice is made paid by PayNow, with reference PN-TEST-01.'), note);
  assert.ok(note.includes("Staff One is its service staff and its guests' Registered by."), note);
  assert.equal(m.querySelector('input[value="auto"]').checked, true);
  await click(button('Create invoice', footer()));
  assert.deepEqual(callsOf('web_order_resolve').map(c => c.args), [{ p_order_id: 'wo-d1', p_customer_id: null, p_new_customer: false }]);
  assert.ok(modal().textContent.includes('Invoice INV-TEST-0102 is created.'));
  assert.ok(modal().textContent.includes('on the rows with Order ID OFF-20260928-0000D1'), modal().textContent);
  assert.equal(callsOf('event_guest_list').length, 2, 'the guest list is reloaded');
  await click(button('Close', footer()));

  // Without a reference or a staff member: the OFF id is the reference and nobody is credited.
  await click(button('Create invoice', orderRow('wo-d2')));
  assert.ok(modal().textContent.includes('S$50.00 was paid but the pass costs S$61.00 on that day'), 'why it waits');
  const bare = modal().querySelector('.events-web-door-note').textContent;
  assert.ok(bare.includes('the invoice is made paid by Cash, with reference OFF-20260927-0000D2.'), bare);
  assert.ok(!bare.includes('service staff'), bare);
  await click(button('Cancel', footer()));

  // A website order shows no staff-link note.
  await click(button('Create invoice', orderRow('wo-3')));
  assert.equal(modal().querySelector('.events-web-door-note'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('Dismiss asks why and sends the reason; the server\'s refusal is shown', async () => {
  await openWithDoorOrders();
  await click(button('Dismiss', orderRow('wo-d2')));
  let m = modal();
  assert.ok(m.textContent.includes('Dismiss Guest Door Two'), m.textContent);
  await click(button('Dismiss', footer()));
  assert.ok(modal().textContent.includes('This field is required.'), 'a reason is required');
  assert.equal(callsOf('web_order_dismiss').length, 0, 'nothing is sent without one');
  await setValue(fieldIn(modal(), 'Why is it dismissed? *'), '  Test registration ');
  await click(button('Dismiss', footer()));
  assert.deepEqual(callsOf('web_order_dismiss').map(c => c.args), [{ p_order_id: 'wo-d2', p_reason: 'Test registration', p_dismiss: true }]);
  assert.equal(modal(), null);
  assert.equal(callsOf('web_orders_list').length, 2, 'the orders are reloaded');

  backend.failures.set('web_order_dismiss', 'Give a reason of at least 3 characters');
  await click(button('Dismiss', orderRow('wo-d1')));
  m = modal();
  await setValue(fieldIn(m, 'Why is it dismissed? *'), 'x');
  await click(button('Dismiss', footer()));
  assert.ok(document.querySelector('.alert-danger')?.textContent.includes('Give a reason of at least 3 characters'), text());
  assert.equal(callsOf('web_orders_list').length, 2, 'nothing changed, so nothing is reloaded');
});

test('Link invoice looks the invoice up, shows what does not match, and links only what was shown', async () => {
  await openWithDoorOrders({ setup: b => {
    b.handlers.web_order_link_preview = a => ({ invoice_no: a.p_invoice_no.toUpperCase(), store: 'South Store', date: '2026-09-28',
      customer_name: 'Customer Door', total: '122.00', paid: 122, methods: ['PayNow', 'Cash'], people: '3',
      warnings: ['The invoice total (S$122.00) is not the order\'s amount (S$94.00)', 'The invoice has 3 people for this event; the order has 2',
        'The invoice is at South Store, not the channel\'s store'] });
  } });
  await click(button('Link invoice', orderRow('wo-d1')));
  let m = modal();
  assert.ok(m.textContent.includes('Link Guest Door One to an existing invoice'), m.textContent);
  assert.ok(m.textContent.includes('Staff link OFF-20260928-0000D1 · paid by PayNow'), 'the order is shown');
  assert.ok(!m.textContent.includes('the invoice is dated that day'), 'no new invoice is dated');
  assert.equal(button('Link invoice', footer()).disabled, true, 'nothing to link before the invoice is looked up');
  assert.equal(button('Look up', m).disabled, true, 'and nothing to look up without a number');

  await setValue(fieldIn(m, 'Invoice no *'), ' inv-test-0301 ');
  await click(button('Look up', modal()));
  assert.deepEqual(callsOf('web_order_link_preview').map(c => c.args), [{ p_order_id: 'wo-d1', p_invoice_no: 'inv-test-0301' }]);
  m = modal();
  const shown = m.querySelector('[aria-label="Invoice to link"]').textContent;
  for (const bit of [`INV-TEST-0301 · South Store · ${full('2026-09-28')}`, 'Customer Door', 'Total S$122.00 · paid S$122.00 by PayNow, Cash',
    '3 people on its tickets for this event']) assert.ok(shown.includes(bit), `${bit}: ${shown}`);
  const warnings = [...m.querySelectorAll('.events-web-link-warnings div div')].map(d => d.textContent);
  assert.deepEqual(warnings, ['The invoice total (S$122.00) is not the order\'s amount (S$94.00)',
    'The invoice has 3 people for this event; the order has 2', 'The invoice is at South Store, not the channel\'s store']);
  assert.equal(button('Link invoice', footer()).disabled, false);

  // Changing the number takes the looked-up invoice away again.
  await setValue(fieldIn(m, 'Invoice no *'), 'INV-TEST-0302');
  assert.equal(modal().querySelector('[aria-label="Invoice to link"]'), null);
  assert.equal(button('Link invoice', footer()).disabled, true);
  await setValue(fieldIn(modal(), 'Invoice no *'), 'INV-TEST-0301');
  await click(button('Look up', modal()));
  await click(button('Link invoice', footer()));
  assert.deepEqual(callsOf('web_order_link_invoice').map(c => c.args), [{ p_order_id: 'wo-d1', p_invoice_no: 'INV-TEST-0301' }],
    'the invoice looked up is the one linked');
  assert.ok(modal().textContent.includes('The order is linked to invoice INV-TEST-0301.'), modal().textContent);
  assert.ok(modal().textContent.includes('on the rows with Order ID OFF-20260928-0000D1'));
  assert.equal(callsOf('web_orders_list').length, 2, 'the orders are reloaded');
  assert.equal(callsOf('event_guest_list').length, 2, 'and the guest list, whose order ids change');
  assert.equal(callsOf('web_order_resolve').length, 0, 'no invoice is created');
  await click(button('Close', footer()));
  assert.equal(modal(), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('Link invoice shows the server\'s refusal and links nothing', async () => {
  await openWithDoorOrders({ setup: b => {
    b.failures.set('web_order_link_preview', 'INV-TEST-0399 has no ticket for this event');
  } });
  await click(button('Link invoice', orderRow('wo-d2')));
  await setValue(fieldIn(modal(), 'Invoice no *'), 'INV-TEST-0399');
  await click(button('Look up', modal()));
  assert.ok(modal().querySelector('.alert-danger').textContent.includes('INV-TEST-0399 has no ticket for this event'));
  assert.equal(button('Link invoice', footer()).disabled, true, 'nothing to link');

  // The preview passes but the link is refused (another order has the invoice): the form stays.
  backend.failures.delete('web_order_link_preview');
  backend.failures.set('web_order_link_invoice', 'INV-TEST-0301 is already the invoice of another website order');
  await setValue(fieldIn(modal(), 'Invoice no *'), 'INV-TEST-0301');
  await click(button('Look up', modal()));
  assert.equal(modal().querySelector('.events-web-link-warnings'), null, 'no warnings, none shown');
  await click(button('Link invoice', footer()));
  assert.ok(modal().querySelector('.alert-danger').textContent.includes('already the invoice of another website order'));
  assert.ok(button('Link invoice', footer()), 'the form stays to try again');
  assert.equal(callsOf('web_orders_list').length, 1, 'nothing changed, so nothing is reloaded');
});

test('the website orders export lists staff-link registrations with their source, method, date paid, reference and staff', async () => {
  await openWithDoorOrders();
  globalThis.__exports = [];
  await click(button('Export Excel'));
  await click(button('Export 9 row(s)', footer()));
  let body = globalThis.__exports.at(-1).sheet.ws.body;
  const dismissed = body.find(r => r.Buyer === 'Test Buyer');
  assert.deepEqual([dismissed.Status, dismissed.Reason, dismissed['Paid through']], ['Dismissed', 'Test registration', 'Bank Transfer'],
    'every registration, the dismissed one too, though it is out of sight');
  const one = body.find(r => r.Buyer === 'Guest Door One');
  assert.deepEqual(
    [one.Source, one['Paid through'], one['Date paid'], one['Payment ref'], one['Registered by'], one['Order ID (checkout)'], one['Paid at (SGT)'],
      one.Names, one['Test order'], one.Status],
    ['Staff link', 'PayNow', '2026-09-28', 'PN-TEST-01', 'Staff One', 'OFF-20260928-0000D1', '2026-09-28 14:05',
      'Guest Door One, Guest Door Guest', 'N', 'Recorded']);
  const two = body.find(r => r.Buyer === 'Guest Door Two');
  assert.deepEqual([two['Paid through'], two['Payment ref'], two['Registered by']], ['Cash', '', '']);
  const four = body.find(r => r.Buyer === 'Guest Door Four');
  assert.deepEqual([four['Paid through'], four['Invoice no']], ['Bank Transfer', 'INV-TEST-0201']);
  assert.equal(body.find(r => r.Buyer === 'Guest Twenty-Three').Source, 'Website');

  // The status filter only changes what is on screen: the export still lists every order.
  await setValue(statusFilter(), 'waiting');
  globalThis.__exports = [];
  await click(button('Export Excel'));
  await click(button('Export 9 row(s)', footer()));
  body = globalThis.__exports.at(-1).sheet.ws.body;
  assert.deepEqual(body.map(r => r.Status).sort(),
    ['Dismissed', 'Invoiced', 'Invoiced', 'Needs review', 'Needs review', 'Recorded', 'Recorded', 'Recorded', 'Refused']);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('an order whose buyer\'s phone is on an invoice made by hand says so, in its row and before Create invoice', async () => {
  await openWithDoorOrders({ setup: b => {
    const list = b.handlers.web_orders_list;
    b.handlers.web_orders_list = a => {
      const web = list(a);
      return { ...web, orders: web.orders.map(o => (o.id === 'wo-d1'
        ? { ...o, hand_invoices: [{ invoice_no: 'INV-TEST-0401', store: 'North Store' }, { invoice_no: null, store: 'South Store' }] }
        : o.id === 'wo-d4' ? { ...o, hand_invoices: [{ invoice_no: 'INV-TEST-0402', store: 'North Store' }] } : o)) };
    };
  } });
  const hint = orderRow('wo-d1').querySelector('.events-web-hand-hint');
  assert.equal(hint?.textContent, 'Possibly already invoiced by hand: INV-TEST-0401 (North Store), an invoice at South Store. '
    + 'Use Link invoice if so.');
  assert.equal(cells(orderRow('wo-d1'))[6].startsWith('Recorded'), true, 'it still only waits, as recorded');
  assert.equal(orderRow('wo-d4').querySelector('.events-web-hand-hint'), null, 'an invoiced order has nothing to link');
  assert.equal(orderRow('wo-d2').querySelector('.events-web-hand-hint'), null, 'none found, nothing said');

  await click(button('Create invoice', orderRow('wo-d1')));
  const note = modal().querySelector('.events-web-hand-note')?.textContent ?? '';
  assert.ok(note.includes('The buyer\'s phone is on INV-TEST-0401 (North Store), an invoice at South Store, made by hand for this event.'), note);
  assert.ok(note.includes('use Link invoice instead, so it is not invoiced twice'), note);
  await click(button('Cancel', footer()));
  await click(button('Create invoice', orderRow('wo-3')));
  assert.equal(modal().querySelector('.events-web-hand-note'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('Create invoice for a staff-link registration paid other than the price says to invoice it by hand and link it', async () => {
  await openWithDoorOrders();
  await click(button('Create invoice', orderRow('wo-d2')));
  const note = modal().querySelector('.events-web-amount-note')?.textContent ?? '';
  assert.ok(note.includes('An invoice made here is always for the price of the pass, so it will not be made for the S$50.00 paid.'), note);
  assert.ok(note.includes('raise the invoice by hand on the Invoices page for S$50.00, paid by Cash, then link this registration to it '
    + 'with Link invoice'), note);
  assert.ok(note.includes('If the form\'s amount is wrong, dismiss this registration and register it again.'), note);
  await click(button('Cancel', footer()));
  // Its amount is the price: nothing to say.
  await click(button('Create invoice', orderRow('wo-d1')));
  assert.equal(modal().querySelector('.events-web-amount-note'), null);
  await click(button('Cancel', footer()));
  // A website order is always charged the price.
  backend.handlers.web_orders_list = () => {
    const fx = makeFixture();
    fx.web.orders = fx.web.orders.map(o => (o.id === 'wo-3' ? { ...o, status: 'needs_review',
      review_reason: 'The invoice would be S$61.00 but Stripe charged S$50.00, so nothing was invoiced' } : o));
    return fx.web;
  };
  await click(button('Refresh'));
  await click(button('Create invoice', orderRow('wo-3')));
  assert.equal(modal().querySelector('.events-web-amount-note'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('a staff-link registration refused while the channel was off can be linked to the invoice made by hand for it', async () => {
  await openWithDoorOrders({ setup: b => {
    const list = b.handlers.web_orders_list;
    b.handlers.web_orders_list = a => {
      const web = list(a);
      return { ...web, orders: web.orders.map(o => (o.id === 'wo-d2'
        ? { ...o, status: 'refused', review_reason: 'The website channel is off' } : o)) };
    };
  } });
  assert.deepEqual(buttons(orderRow('wo-d2')).map(b => b.textContent.trim()), ['Link invoice'],
    'refused while off: no Create invoice and no Dismiss, but it can be linked');
  assert.deepEqual(buttons(orderRow('wo-4')), [], 'a refused website order still has no action');
  await click(button('Link invoice', orderRow('wo-d2')));
  await setValue(fieldIn(modal(), 'Invoice no *'), 'INV-TEST-0301');
  await click(button('Look up', modal()));
  await click(button('Link invoice', footer()));
  assert.deepEqual(callsOf('web_order_link_invoice').map(c => c.args), [{ p_order_id: 'wo-d2', p_invoice_no: 'INV-TEST-0301' }]);
  assert.deepEqual(globalThis.__renderErrors, []);
});
