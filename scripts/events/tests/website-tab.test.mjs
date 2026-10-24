// The Event page with an event's own website (436), rendered for real against
// a fake backend, as events-page.test.mjs renders it.
//
// It checks what the page promises the owner (20 Oct 2026):
//   * Guests: a VIP has a VIP badge and the perks written out, a person whose VIP
//     payment waits says by what, someone held for staff is "To match" and
//     waits in the To match panel with the customers they may be, where staff
//     link them (with a note), make a new customer, or (Owner or Manager)
//     close; the guest list merges the website's details by guest id; a VIP's
//     parked free record is hidden (and cannot be restored by hand); "Copy VIP
//     link" copies <site>/vip/<token>; the filter shows VIPs, website people or
//     those to match; the export adds VIP, registration, gift, code and the
//     referral note; a failed read of the website details keeps the badges
//     and says so; the affiliate through her own link (not referred, no
//     commission: the owner, 20 Oct 2026) has a plain note on the guest, on
//     To match and in the export.
//   * Check-in: a VIP has a badge and their perks; once in, the gifts appear
//     with the store's stock (none left: not offered), the one picked is sent
//     with the day and a request id (the same one again after a lost answer,
//     a new one after a refusal), then shown with its USE number; Later
//     hides it; an Owner or Manager can undo a gift (with a reason), staff
//     cannot.
//   * Website tab: Owners, Admins and Managers see it, staff do not; an Owner
//     saves the settings (Live asks first), makes a key that is shown once and
//     gone when the window closes, and revokes one with a reason; a Manager
//     reads it, cannot change it or make keys, and sets the venue; the address,
//     the event code, the website's settings and the contract are there to
//     copy, with an example that compiles as copied; test rows say what a
//     live key would have done (the affiliate herself: with the note); test data is
//     cleared; readiness and the latest requests show.
//   * Website orders: the VIP orders come first, with the provider, people
//     (to match or their customer), the total, the reference, the reason and
//     HitPay's refund notice; Create invoices asks "arrived by … reference …"
//     first (when the buyer typed another amount, an Owner or Manager enters
//     what arrived); a transfer is dismissed and restored; an Owner or Manager (not an
//     Admin) closes an order as refunded; without a channel the channel part
//     is left out.
//   * 444 (the owner, 21 Oct 2026: "Staff can close it"): a HitPay checkout
//     opened and left without paying says "Online payment started, not paid
//     (until HH:MM)" on the guest and on To match, not "VIP payment waiting"
//     (a payment taken still says that; a server before 444 too); closing such
//     a registration says the checkout closes with it (for all of a group
//     when it is for several people), and after it that it did; the 436 refusal for a payment taken reads as what to do on Website
//     orders. Website orders shows open checkouts by default (not expired
//     ones), with "Close unpaid checkout" for an Owner or Manager (a reason;
//     the server's dismiss; it says when the checkout is for several people);
//     not for an Admin (the owner, 22 Oct 2026), even when the server's
//     can_close is wrong; none on a payment; a closed checkout says so and
//     cannot be restored.
//   * The contract shown is the recorded version (its md5); the tab says
//     which days and hours the website shows (the event's own, 9 am to 7 pm).
//
// Every name, phone and email here is invented.
// Run: node --test scripts/events/tests/website-tab.test.mjs
process.env.TZ = 'America/Los_Angeles';

import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://events.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
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
// The clipboard, captured.
const clipboard = [];
Object.defineProperty(dom.window.navigator, 'clipboard', { value: { writeText: async t => { clipboard.push(t); } }, configurable: true });

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
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{"VITE_SUPABASE_URL":"https://project.supabase.example"}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onResolve({ filter: /\?raw$/ }, a => ({ path: join(a.resolveDir, a.path.replace(/\?raw$/, '')), namespace: 'raw' }));
    b.onLoad({ filter: /.*/, namespace: 'raw' }, a => ({ loader: 'text', contents: readFileSync(a.path, 'utf8') }));
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

// ── dates ──────────────────────────────────────────────────────────────────
const TODAY = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const addDays = (day, n) => { const [y, m, d] = day.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10); };
// The event is on now (today and tomorrow), so the door's day is today.
const D1 = TODAY, D2 = addDays(TODAY, 1);
const SITE = 'https://healthtalk.example.com';

// ── fixture ────────────────────────────────────────────────────────────────
function makeFixture() {
  const event = {
    id: 'ev-1', name: 'Test Health Seminar', description: null, daily_start: '09:00', daily_end: '19:00',
    early_bird_until: null, early_bird_percent: null, is_active: true, notes: null, created_at: '2026-10-20T02:00:00Z',
    first_day: D1, last_day: D2, days: [{ day: D1, capacity: null, registered: 4, attended: 0 }, { day: D2, capacity: null, registered: 3, attended: 0 }],
    stores: [{ id: 'st-van', name: 'Van Store' }],
    options: [{ id: 'op-vip', name: 'VIP', days_count: 2, price: '72.00', is_active: true, sort_order: 1, early_bird_price: null, sold: true }],
    guests: 4, ticket_guests: 1, free_guests: 3, can_manage: true, can_run: true, web_channel_mode: null,
  };
  const day = (d, attended_at = null) => ({ day: d, attended_at, check_in_code: null, checked_in_by_name: null });
  const g = (id, name, extra) => ({
    guest_id: id, name, phone: null, customer_id: null, customer_name: null, source: 'free', status: 'registered', cancelled_reason: null,
    notes: null, registered_by: null, registered_by_name: null, ticket_option_id: null, ticket_option_name: null,
    invoice_id: null, invoice_no: null, invoice_status: null, invoice_total: null, invoice_paid: null, invoice_store_id: null,
    created_at: '2026-10-20T02:00:00Z', days: [], email: null, order_id: null, payment_methods: null, ...extra,
  });
  const guests = [
    // A VIP: their VIP record (a ticket of the VIP option), and their parked free record.
    g('g-vip', 'Vera Vip', { phone: '+61491570737', source: 'ticket', ticket_option_id: 'op-vip', ticket_option_name: 'VIP',
      invoice_id: 'inv-1', invoice_no: 'INV-TEST-0001', invoice_status: 'paid', invoice_total: 72, invoice_paid: 72,
      invoice_store_id: 'st-van', customer_id: 'c-1', customer_name: 'Vera Vip', days: [day(D1), day(D2)] }),
    g('g-vip-free', 'Vera Vip', { phone: '+61491570737', status: 'cancelled', cancelled_reason: 'Upgraded to VIP · INV-TEST-0001',
      notes: 'Website · REG-20261020-AAAA0001 · 1 of 1', days: [day(D1)] }),
    // Registered on the website, not VIP, with a link to buy VIP.
    g('g-free', 'Fred Free', { phone: '+61491572983', customer_id: 'c-2', customer_name: 'Fred Free', notes: 'Website · REG-20261020-AAAA0002 · 1 of 2', days: [day(D1)] }),
    // Held for staff: their phone belongs to another customer.
    g('g-held', 'Hana Held', { phone: '+61491573770', notes: 'Website · REG-20261020-AAAA0002 · 2 of 2', days: [day(D2)] }),
    // Added by staff: nothing from the website.
    g('g-staff', 'Sam Staffadded', { days: [day(D1)] }),
  ];
  const extras = {
    settings: { store_id: 'st-van', store_name: 'Van Store', vip_option_id: 'op-vip', mode: 'live', code: 'TEST-SEMINAR',
      venue: null, site_url: SITE, gift_store_access: true },
    guests: [
      { guest_id: 'g-vip', person_id: 'p-1', website: true, is_test: false, registration_id: 'REG-20261020-AAAA0001', position: 1, group_size: 1,
        parked: false, vip: 'paid', vip_guest: true, vip_invoice_no: 'INV-TEST-0001', vip_waiting: null, hold: null, closed: false,
        match: 'new_customer', referral: null, upgrade_token: null, gift: null },
      { guest_id: 'g-vip-free', person_id: 'p-1', website: true, is_test: false, registration_id: 'REG-20261020-AAAA0001', position: 1, group_size: 1,
        parked: true, vip: 'paid', vip_guest: false, vip_invoice_no: 'INV-TEST-0001', vip_waiting: null, hold: null, closed: false,
        match: 'new_customer', referral: null, upgrade_token: null, gift: null },
      { guest_id: 'g-free', person_id: 'p-2', website: true, is_test: false, registration_id: 'REG-20261020-AAAA0002', position: 1, group_size: 2,
        parked: false, vip: 'pending', vip_guest: false, vip_invoice_no: null, vip_waiting: 'paynow', hold: null, closed: false, match: 'exact',
        referral: { code: 'AFF123', state: 'valid', outcome: 'already_customer', affiliate_name: 'Ann Affiliate' },
        upgrade_token: 'vip_abcdefghijklmnopqrstuvwxyz', gift: null },
      { guest_id: 'g-held', person_id: 'p-3', website: true, is_test: false, registration_id: 'REG-20261020-AAAA0002', position: 2, group_size: 2,
        parked: false, vip: 'none', vip_guest: false, vip_invoice_no: null, vip_waiting: null,
        hold: { reason: 'phone_in_use', held_at: '2026-10-20T03:00:00Z' }, closed: false, match: 'held', referral: null,
        upgrade_token: 'vip_bcdefghijklmnopqrstuvwxyz2', gift: null },
    ],
    holds: [{ person_id: 'p-3', guest_id: 'g-held', registration_id: 'REG-20261020-AAAA0002', position: 2, group_size: 2,
      held_at: '2026-10-20T03:00:00Z', reason: 'phone_in_use', full_name: 'Hana Held', phone: '+61491573770', phone_norm: '+61491573770',
      email: 'hana@example.com', days: [D2], vip_waiting: false,
      candidates: [{ customer_id: 'c-9', full_name: 'Holly Holder', phone: '+61491573770', email: null, created_at: '2026-01-01T00:00:00Z',
        phone_matches: true, email_matches: false, name_matches: false }] }],
    gift_choices: [{ product_id: 'pr-socks', name: 'Socks Black', stock: 2 }, { product_id: 'pr-gloves', name: 'Gloves', stock: 0 }],
    can_close_holds: true, can_undo_gifts: true,
  };
  const settings = {
    event_id: 'ev-1', event_name: 'Test Health Seminar',
    settings: { event_id: 'ev-1', code: 'TEST-SEMINAR', mode: 'record_only', venue: null, store_id: 'st-van', store_name: 'Van Store',
      acting_profile_id: 'u-own', acting_name: 'Owner One', vip_option_id: 'op-vip', vip_option_name: 'VIP',
      vip_voucher_ids: ['v-72', 'v-3in1'], gift_product_ids: ['pr-socks'], hitpay_payment_method_id: 'pm-hp',
      paynow_payment_method_id: 'pm-pn', bank_payment_method_id: null, source_option_id: 'so-1', source_label: 'Event Name',
      source_details: 'Seminar (website)', sync_url: `${SITE}/api/app/sync`, site_url: SITE, last_sync_at: null, last_test_sync_at: null },
    readiness: { blocking: [], errors: ['"$72 discount Voucher" has no price at the store: give it one on the Vouchers page.'],
      warnings: ['No live key yet.'] },
    endpoint_path: '/functions/v1/event-website',
    keys: [{ id: 'k-1', kind: 'test', key_hint: 'evk_test_AbCd…wxyz', label: 'Preview', created_at: '2026-10-20T02:00:00Z',
      created_by_name: 'Owner One', last_used_at: null, revoked_at: null, revoked_by_name: null, revoked_reason: null }],
    requests: [{ type: 'register', received_at: '2026-10-20T03:00:00Z', outcome: 'registered', kind: 'test', is_write: true }],
    test: {
      registrations: [{ registration_id: 'REG-20261020-TTTT0001', submitted_at: '2026-10-20T03:00:00Z', created_at: '2026-10-20T03:00:00Z',
        referral_code: null, referral_state: 'none', people: [{ person_id: 'tp-1', position: 1, full_name: 'Tess Testing', phone: '+61491570737',
          email: 'tess@example.com', days: [D1], vip: 'none', test_outcome: { match: 'new_customer', hold_reason: null, referral: null } }] }],
      orders: [{ id: 'to-1', order_id: 'VIP-20261020-TTTT0001', provider: 'hitpay', status: 'test', livemode: false, amount_total: 72,
        amount_paid: 72, test_note: 'A live key would have made 1 invoice(s) of S$72.00.', test_would: 'invoiced', review_reason: null,
        created_at: '2026-10-20T03:05:00Z' }],
    },
    choices: {
      stores: [{ id: 'st-van', name: 'Van Store' }],
      profiles: [{ id: 'u-own', full_name: 'Owner One', role: 'owner' }],
      options: [{ id: 'op-vip', name: 'VIP', days_count: 2, price: 72, is_active: true }],
      vouchers: [{ id: 'v-72', name: '$72 discount Voucher', code: 'SAVE72', priced_at_store: false },
        { id: 'v-3in1', name: '3-in-1 Vouchers', code: '3-in-1', priced_at_store: true }],
      products: [{ id: 'pr-socks', name: 'Socks Black', sku: 'S-B', stock: 2 }, { id: 'pr-gloves', name: 'Gloves', sku: 'G', stock: 0 }],
      methods: [{ id: 'pm-hp', name: 'HitPay (online)' }, { id: 'pm-pn', name: 'PayNow' }, { id: 'pm-bank', name: 'Bank Transfer' }],
      sources: [{ id: 'so-1', label: 'Event Name', requires_details: true }],
    },
  };
  const person = (id, name, extra) => ({ person_id: id, position: 1, name, phone: null, email: null, match: 'exact', hold_reason: null,
    customer_id: 'c-' + id, customer_name: name, days: [D1], invoice_id: null, invoice_no: null, invoice_status: null, ...extra });
  const vip = {
    settings: { mode: 'live', code: 'TEST-SEMINAR', store_name: 'Van Store', hitpay_method_name: 'HitPay (online)',
      paynow_method_name: 'PayNow', bank_method_name: null },
    can_close: true,
    orders: [
      { id: 'vo-1', order_id: 'VIP-20261020-00000001', provider: 'paynow', status: 'recorded', is_test: false, livemode: true,
        unit_amount: 72, quantity: 2, amount_total: 144, amount_paid: 144, payer_name: 'Fred Free', payer_email: 'fred@example.com',
        payer_phone: '+61491572983', checkout_opened_at: '2026-10-20T03:10:00Z', expires_at: null, expired: false, paid_at: null,
        paid_on: D1, reference: 'PN-1', hitpay_payment_request_id: null, hitpay_payment_id: null, review_reason: null, refusal: null,
        waiting_for_match: false, test_note: null, test_would: null, refunded_total: 0, refund_noted_at: null, refund_covered: false,
        created_at: '2026-10-20T03:10:00Z',
        people: [person('p-2', 'Fred Free'), person('p-3', 'Hana Held', { match: 'held', customer_id: null, customer_name: null })] },
      { id: 'vo-2', order_id: 'VIP-20261020-00000002', provider: 'hitpay', status: 'invoiced', is_test: false, livemode: true,
        unit_amount: 72, quantity: 1, amount_total: 72, amount_paid: 72, payer_name: 'Vera Vip', payer_email: 'vera@example.com',
        payer_phone: null, checkout_opened_at: '2026-10-20T02:00:00Z', expires_at: '2026-10-20T03:10:00Z', expired: false,
        paid_at: '2026-10-20T02:03:00Z', paid_on: D1, reference: '9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d',
        hitpay_payment_request_id: '9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d', hitpay_payment_id: '1f2e3d4c-5b6a-4978-8a9b-0c1d2e3f4a5b',
        review_reason: null, refusal: null, waiting_for_match: false, test_note: null, test_would: null, refunded_total: 72,
        refund_noted_at: '2026-10-21T02:00:00Z', refund_covered: false, created_at: '2026-10-20T02:00:00Z',
        people: [person('p-1', 'Vera Vip', { invoice_id: 'inv-1', invoice_no: 'INV-TEST-0001', invoice_status: 'paid' })] },
      { id: 'vo-3', order_id: 'VIP-20261020-00000003', provider: 'hitpay', status: 'needs_review', is_test: false, livemode: true,
        unit_amount: 72, quantity: 1, amount_total: 72, amount_paid: 70, payer_name: 'Dina Short', payer_email: 'dina@example.com',
        payer_phone: null, checkout_opened_at: '2026-10-20T02:00:00Z', expires_at: null, expired: false, paid_at: '2026-10-20T02:05:00Z',
        paid_on: D1, reference: null, hitpay_payment_request_id: null, hitpay_payment_id: null,
        review_reason: 'HitPay charged S$70.00, but 1 × VIP costs S$72.00', refusal: null, waiting_for_match: false, test_note: null,
        test_would: null, refunded_total: 0, refund_noted_at: null, refund_covered: false, created_at: '2026-10-20T02:04:00Z',
        people: [person('p-4', 'Dina Short')] },
    ],
  };
  return { event, guests, extras, settings, vip };
}

// 436 round 7: the suggested talk titles (the contract's SUGGESTED_TALK_TITLES).
const SUGGESTED = ['Sleep better, stress less', 'Healthy joints, back and muscles', 'Good circulation for everyday energy',
  'Caring for your eyes', 'Ageing well and staying active', 'Eating well for long-term health', "Women's wellness"];

function createBackend(fx, role) {
  const b = { calls: [], handlers: {} };
  const rpcs = {
    events_list: () => [{ ...fx.event, can_manage: ['owner', 'admin', 'manager'].includes(role) }],
    my_assigned_stores: () => [{ store_id: 'st-van', store_name: 'Van Store', is_default: true }],
    event_guest_list: () => fx.guests,
    // The server says what the caller's role may do.
    event_web_guest_extras: () => ({ ...fx.extras, can_close_holds: ['owner', 'manager'].includes(role),
      can_undo_gifts: ['owner', 'manager'].includes(role) }),
    event_check_in: a => ({ guest_id: a.p_guest_id, day: a.p_day, attended_at: a.p_attended ? '2026-10-20T02:15:00Z' : null,
      check_in_code: a.p_code ?? null, checked_in_by: 'u-x', checked_in_by_name: 'Door Staff', already_in: false, changed: true }),
    event_vip_gift_give: a => ({ gift_id: 'gift-1', use_no: 'USE-000123', product_id: a.p_product_id,
      product_name: a.p_product_id === 'pr-socks' ? 'Socks Black' : 'Gloves', remaining: 1, replayed: false }),
    event_vip_gift_undo: () => ({ ok: true, use_no: 'USE-000123', message: 'Put the item back with Stock, Adjust (an adjustment request), quoting USE-000123.' }),
    event_registration_attach: () => ({ ok: true, customer_id: 'c-9', vip_orders: [] }),
    event_registration_create_customer: () => ({ ok: true, customer_id: 'c-new', vip_orders: [{ order_id: 'VIP-20261020-00000009', status: 'invoiced', review_reason: null }] }),
    event_registration_close: () => ({ ok: true }),
    event_web_settings_get: () => ({ ...fx.settings, can_manage: role === 'owner', can_clear_tests: ['owner', 'manager'].includes(role),
      can_set_venue: ['owner', 'admin', 'manager'].includes(role),
      // 436 round 7: the talk titles (the suggested list until saved), set by an Owner, Admin or Manager.
      talks: { titles: [...SUGGESTED], saved: false, suggested: [...SUGGESTED] }, can_set_talks: ['owner', 'admin', 'manager'].includes(role) }),
    event_web_set_talks: a => ({ ok: true, talk_titles: a.p_titles ?? [...SUGGESTED], saved: a.p_titles !== null }),
    // 436 round 7: nobody has answered yet (planning.test.mjs covers the answers).
    event_planning_list: () => ({ talk_titles: [...SUGGESTED], talk_titles_saved: false,
      hours: { daily_start: '09:00', daily_end: '19:00' }, guests: [] }),
    event_web_settings_save: () => ({ ok: true, readiness: fx.settings.readiness }),
    event_web_set_venue: a => ({ ok: true, venue: a.p_venue }),
    event_web_key_create: a => ({ key_id: 'k-new', kind: a.p_kind, key_hint: `evk_${a.p_kind}_NeWk…zzzz`,
      key: `evk_${a.p_kind}_NeWkEyNeWkEyNeWkEyNeWkEyNeWkEyNeWkEyNeWkzzzz` }),
    event_web_key_revoke: () => ({ ok: true }),
    event_web_test_clear: () => ({ registrations: 1, orders: 1, requests: 3 }),
    event_vip_orders_list: () => ({ ...fx.vip, can_close: ['owner', 'manager'].includes(role) }),
    event_vip_order_invoice: () => ({ status: 'invoiced', review_reason: null, invoice_nos: ['INV-TEST-0005', 'INV-TEST-0006'] }),
    event_vip_order_dismiss: () => ({ ok: true }),
    event_vip_order_close_refunded: () => ({ ok: true }),
    web_orders_list: () => ({ channel: null, can_switch: false, orders: [] }),
    event_invoices: () => [],
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args }); }
    select() { return this; } eq() { return this; } is() { return this; } in() { return this; } or() { return this; }
    order() { return this; } limit() { return this; } maybeSingle() { return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
      await Promise.resolve();
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        const out = fn(this.args);
        if (out && out.__error) return { data: null, error: { message: out.__error, code: out.__code ?? '' } };
        return { data: structuredClone(out), error: null };
      }
      return { data: [], error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

const USERS = {
  owner: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
  admin: { id: 'u-adm', full_name: 'Admin One', role: 'admin', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true },
};
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount({ role = 'manager', setup } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture(), role);
  globalThis.__backend = backend; globalThis.__exports = []; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: USERS[role] };
  clipboard.length = 0;
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(EventsPage))));
  await tick();
  await click([...document.querySelectorAll('.events-card')].find(c => c.textContent.includes('Test Health Seminar')));
}
const text = () => document.body.textContent;
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const buttons = (scope = document) => [...scope.querySelectorAll('button')];
const button = (label, scope = document) => buttons(scope).find(b => b.textContent.trim() === label);
const buttonStarting = (label, scope = document) => buttons(scope).find(b => b.textContent.trim().startsWith(label));
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
const modal = () => [...document.querySelectorAll('.modal')].at(-1);
const callsOf = name => backend.calls.filter(c => c.name === name);
const tab = label => buttons().find(b => b.getAttribute('role') === 'tab' && b.textContent.trim() === label);
const row = id => document.querySelector(`tr[data-guest="${id}"]`);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── Guests ─────────────────────────────────────────────────────────────────
test('guests: VIP badge, VIP waiting, To match and Website badges merged by guest id; the parked record is hidden', async () => {
  await mount();
  assert.deepEqual(callsOf('event_web_guest_extras').map(c => c.args), [{ p_event_id: 'ev-1' }]);
  const vip = row('g-vip');
  assert.ok(vip.querySelector('.events-badge-vip'), 'the VIP has a VIP badge');
  assert.equal(vip.querySelector('.events-badge-vip').title, 'Priority for the free therapies · personalised seating · VIP name tag', 'the perks are on the badge');
  assert.equal(vip.querySelector('.events-vip-perks').textContent, 'Priority for the free therapies · personalised seating · VIP name tag',
    'and written out under the name (a phone shows no hover)');
  assert.ok(!/dinner/i.test(vip.textContent), 'no dinner with the founder any more (the owner, 22 Oct 2026)');
  assert.equal(row('g-free').querySelector('.events-vip-perks'), null, 'not for a guest who is not VIP');
  assert.ok(row('g-free').textContent.includes('VIP waiting · PayNow'), 'a VIP payment waiting says by what');
  assert.ok(row('g-held').textContent.includes('To match'));
  assert.ok(row('g-free').textContent.includes('Website'));
  assert.ok(!row('g-staff').querySelector('.events-badges'), 'a guest staff added has no website badges');
  assert.equal(row('g-vip-free'), null, 'the VIP\'s parked free record is hidden');
  await setValue(document.querySelector('select[aria-label="Status"]'), 'cancelled');
  assert.ok(row('g-vip-free'), 'and shown with the cancelled ones');
  assert.ok(!button('Restore', row('g-vip-free')), 'but it cannot be restored by hand');
  assert.ok(text().includes('1 VIP'), 'the count line counts the VIPs');
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('guests: a failed read of the website details keeps the badges and says so; a database without 436 shows none', async () => {
  let fail = null;
  await mount({ setup: b => {
    b.handlers.event_web_guest_extras = () => (fail ?? makeFixture().extras);
  } });
  assert.ok(row('g-vip').querySelector('.events-badge-vip'));
  fail = { __error: 'canceling statement due to statement timeout', __code: '57014' };
  await click(buttons().find(b => b.textContent.trim() === 'Refresh'));
  assert.equal(callsOf('event_web_guest_extras').length, 2);
  assert.ok(row('g-vip').querySelector('.events-badge-vip'), 'the VIP badge stays');
  assert.ok(text().includes('To match'), 'the To match panel stays');
  assert.ok(document.querySelector('[data-extras-error]').textContent.includes('Could not load the website details'));
  assert.ok(document.querySelector('[data-extras-error]').textContent.includes('statement timeout'));
  fail = null;
  await click(buttons().find(b => b.textContent.trim() === 'Refresh'));
  assert.equal(document.querySelector('[data-extras-error]'), null, 'gone once it reads again');
  fail = { __error: 'Could not find the function public.event_web_guest_extras', __code: 'PGRST202' };
  await click(buttons().find(b => b.textContent.trim() === 'Refresh'));
  assert.equal(document.querySelector('[data-extras-error]'), null, 'a database without 436: no warning');
  assert.equal(row('g-vip').querySelector('.events-badge-vip'), null, 'and no website badges');
});

test('guests: the filter shows VIPs, website people or those to match', async () => {
  await mount();
  const group = document.querySelector('[role="group"][aria-label="Website filter"]');
  await click(buttonStarting('VIP (', group));
  assert.deepEqual([...document.querySelectorAll('.events-table tbody tr')].map(r => r.dataset.guest), ['g-vip']);
  await click(buttonStarting('To match', group));
  assert.deepEqual([...document.querySelectorAll('.events-table tbody tr')].map(r => r.dataset.guest), ['g-held']);
  await click(button('Website', group));
  assert.deepEqual([...document.querySelectorAll('.events-table tbody tr')].map(r => r.dataset.guest).sort(), ['g-free', 'g-held', 'g-vip']);
  await click(button('All guests', group));
  assert.equal(document.querySelectorAll('.events-table tbody tr').length, 4);
});

test('guests: Copy VIP link copies <site>/vip/<token>; a VIP has none', async () => {
  await mount();
  await click(button('Copy VIP link', row('g-free')));
  assert.deepEqual(clipboard, [`${SITE}/vip/vip_abcdefghijklmnopqrstuvwxyz`]);
  assert.ok(text().includes('Fred Free\'s VIP link is copied'));
  assert.ok(!button('Copy VIP link', row('g-vip')), 'a VIP has no VIP link');
  assert.ok(!button('Copy VIP link', row('g-staff')), 'nor does a guest staff added');
});

test('guests: To match lists the person with the customers they may be; staff link, make a customer, or close', async () => {
  await mount({ role: 'staff' });
  const panel = document.querySelector('[data-holds]');
  assert.ok(panel.textContent.includes('To match (1)'));
  // The intro covers every reason a person waits here, the affiliate's own name too (the review of 21 Oct 2026).
  assert.ok(panel.textContent.replace(/\s+/g, ' ').includes('Registered on the website, but staff must confirm who they are (their phone or '
    + 'email is on another customer\'s record, or they gave the affiliate\'s own name on a new phone and email).'));
  assert.ok(panel.textContent.includes('Their phone number belongs to a customer under another name.'));
  assert.ok(panel.textContent.includes('Holly Holder') && panel.querySelector('.badge-success').textContent === 'Phone');
  await click(panel.querySelector('[data-attach="c-9"]'));
  assert.ok(modal().querySelector('[data-confirm]').disabled, 'a note is needed first');
  await setValue(modal().querySelector('textarea'), 'Same person, asked at the door');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_registration_attach').at(-1).args,
    { p_person_id: 'p-3', p_customer_id: 'c-9', p_note: 'Same person, asked at the door' });
  assert.ok(text().includes('Hana Held is now linked to Holly Holder.'));
  assert.equal(callsOf('event_guest_list').length, 2, 'the guest list is read again');

  await click(document.querySelector('[data-create="p-3"]'));
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_registration_create_customer').at(-1).args, { p_person_id: 'p-3', p_note: null });
  assert.ok(text().includes('Their VIP payment VIP-20261020-00000009 is now invoiced.'), 'a waiting VIP payment invoiced says so');
  assert.ok(!document.querySelector('[data-close="p-3"]'), 'staff cannot close a registration');
});

test('guests: an Owner or Manager closes a registration that is not real, with a reason', async () => {
  await mount({ role: 'manager' });
  await click(document.querySelector('[data-close="p-3"]'));
  await setValue(modal().querySelector('textarea'), 'A test registration');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_registration_close').at(-1).args, { p_person_id: 'p-3', p_reason: 'A test registration' });
});

test('guests: the export adds VIP, registration, gift, referral code and note', async () => {
  await mount();
  globalThis.__exports = [];
  await click(button('Export Excel'));
  const exported = globalThis.__exports.at(-1);
  // 436 round 7: the planning answers follow the website's columns (planning.test.mjs checks them).
  const header = exported.sheet.ws.header;
  const at = header.indexOf('VIP');
  assert.deepEqual(header.slice(at, at + 6), ['VIP', 'Registration', 'Gift', 'Referral code', 'Referral note', 'Food']);
  const body = exported.sheet.ws.body;
  assert.equal(body.find(r => r.Name === 'Vera Vip').VIP, 'Y');
  assert.equal(body.find(r => r.Name === 'Fred Free').VIP, 'Waiting');
  assert.equal(body.find(r => r.Name === 'Fred Free')['Referral code'], 'AFF123');
  assert.equal(body.find(r => r.Name === 'Hana Held').Registration, 'REG-20261020-AAAA0002 · 2 of 2');
});

// No self-referral (the owner, 20 Oct 2026): the affiliate through her own link is not referred, and staff see why.
// Her own row says "She earns no commission from it" (the owner, 21 Oct 2026); her own referrer still earns on her VIP.
const SELF_NOTE = 'Not referred: this is Ann Affiliate, the affiliate whose link (AFF123) was used. She earns no commission from it.';
const NAME_NOTE = 'Not referred: the same name as Ann Affiliate, the affiliate whose link (AFF123) was used. If this is Ann Affiliate, link her record: she earns no commission from it. If it is someone else, make a new customer: they are not referred through this link either.';
test('guests: the affiliate through her own link: a plain note on the guest, on To match, in the export; none on others', async () => {
  await mount({ role: 'staff', setup: b => {
    b.handlers.event_web_guest_extras = () => {
      const x = makeFixture().extras;
      x.guests.find(g => g.guest_id === 'g-free').referral = { code: 'AFF123', state: 'valid', outcome: 'self', affiliate_name: 'Ann Affiliate', note: SELF_NOTE };
      x.holds[0].referral_note = NAME_NOTE;
      x.holds[0].reason = 'affiliate_name';
      return { ...x, can_close_holds: false, can_undo_gifts: false };
    };
  } });
  assert.equal(row('g-free').querySelector('[data-referral-note]').textContent, SELF_NOTE, 'under the guest\'s name');
  assert.equal(row('g-vip').querySelector('[data-referral-note]'), null, 'not on a guest who was not found to be the affiliate');
  assert.equal(document.querySelector('[data-hold="p-3"] [data-referral-note]').textContent, NAME_NOTE, 'on the person to match');
  assert.ok(document.querySelector('[data-hold="p-3"]').textContent.includes('Their name is the affiliate\'s (whose link was used), on a phone and email not on her record.'),
    'held under the affiliate\'s name (the owner, 21 Oct 2026): the reason says so');
  await click(document.querySelector('[data-create="p-3"]'));
  assert.ok(modal().textContent.includes('The affiliate is never their own referral, and someone made a customer under her name is not referred either.'));
  assert.ok(modal().textContent.includes('someone on another customer\'s phone, or on the affiliate\'s own phone or email, becomes the affiliate\'s referral only once an Owner or Manager checks them, and the affiliate earns commission on their VIP only from then.'),
    'making a customer of someone else on another customer\'s phone or the affiliate\'s phone or email: referred only once an Owner or Manager checks them, and the affiliate (not they) earns on their VIP from then (the owner, 20 and 21 Oct 2026)');
  assert.ok(!modal().textContent.includes('and earn commission on VIP'), 'the dialog never reads as if the relative earns the commission');
  globalThis.__exports = [];
  await click(button('Export Excel'));
  const body = globalThis.__exports.at(-1).sheet.ws.body;
  assert.equal(body.find(r => r.Name === 'Fred Free')['Referral note'], SELF_NOTE);
  assert.equal(body.find(r => r.Name === 'Vera Vip')['Referral note'], '');
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── Check-in ───────────────────────────────────────────────────────────────
const checkRow = id => document.querySelector(`.events-checkin-row[data-guest="${id}"]`);
test('check-in: a VIP has a badge and their perks; once in, the gifts with the stock; the one picked is recorded', async () => {
  await mount({ role: 'staff' });
  await click(tab('Check-in'));
  const r = () => checkRow('g-vip');
  assert.ok(r().querySelector('.events-badge-vip'));
  assert.ok(r().textContent.includes('Priority for the free therapies'));
  assert.ok(!/dinner/i.test(r().textContent), 'no dinner with the founder at the door (the owner, 22 Oct 2026)');
  assert.equal(r().querySelector('.events-gift-picker'), null, 'no gift before they are in');
  assert.equal(checkRow('g-free').querySelector('.events-badge-vip'), null, 'a free guest is not VIP');
  await click(button('Check in', r()));
  const picker = r().querySelector('.events-gift-picker');
  assert.ok(picker, 'checked in: the gifts appear');
  assert.ok(button('Socks Black (2)', picker) && !button('Socks Black (2)', picker).disabled);
  assert.ok(button('Gloves (0)', picker).disabled, 'none left: not offered');
  await click(button('Socks Black (2)', picker));
  const give = callsOf('event_vip_gift_give').at(-1).args;
  assert.equal(give.p_guest_id, 'g-vip');
  assert.equal(give.p_product_id, 'pr-socks');
  assert.equal(give.p_day, D1);
  assert.match(give.p_request_id, /^[0-9a-f-]{36}$/);
  assert.ok(r().textContent.includes('Gift: Socks Black · USE-000123'));
  assert.equal(r().querySelector('.events-gift-picker'), null, 'one gift each');
  assert.ok(!button('Undo gift', r()), 'staff cannot undo a gift');
});

test('check-in: a gift tapped again after a lost answer is the same request; after a refusal, a new one', async () => {
  let n = 0;
  await mount({ role: 'staff', setup: b => {
    b.handlers.event_vip_gift_give = a => {
      n++;
      if (n === 1) return { __error: 'TypeError: Failed to fetch' };
      if (n === 2) return { __error: 'Only 0 of "Socks Black" in stock at this store', __code: 'P0001' };
      return { gift_id: 'gift-1', use_no: 'USE-000123', product_id: a.p_product_id, product_name: 'Socks Black', remaining: 1, replayed: false };
    };
  } });
  await click(tab('Check-in'));
  await click(button('Check in', checkRow('g-vip')));
  for (let i = 0; i < 3; i++) await click(button('Socks Black (2)', checkRow('g-vip')));
  const ids = callsOf('event_vip_gift_give').map(c => c.args.p_request_id);
  assert.equal(ids.length, 3);
  assert.equal(ids[1], ids[0], 'after a lost answer, the same request (the server replays a gift it made)');
  assert.notEqual(ids[2], ids[1], 'after a refusal, a new request');
  assert.ok(checkRow('g-vip').textContent.includes('Gift: Socks Black · USE-000123'));
});

test('check-in: Later hides the gifts; a refusal shows; a Manager undoes a gift with a reason', async () => {
  await mount({ role: 'manager', setup: b => {
    b.handlers.event_vip_gift_give = () => ({ __error: 'Only 0 of "Socks Black" in stock at this store' });
  } });
  await click(tab('Check-in'));
  await click(button('Check in', checkRow('g-vip')));
  await click(button('Later', checkRow('g-vip')));
  assert.equal(checkRow('g-vip').querySelector('.events-gift-picker'), null, 'Later hides it');

  await mount({ role: 'manager', setup: b => {
    b.handlers.event_vip_gift_give = () => ({ __error: 'Only 0 of "Socks Black" in stock at this store' });
  } });
  await click(tab('Check-in'));
  await click(button('Check in', checkRow('g-vip')));
  await click(button('Socks Black (2)', checkRow('g-vip')));
  assert.ok(checkRow('g-vip').querySelector('[role="alert"]').textContent.includes('Only 0 of "Socks Black" in stock'));

  await mount({ role: 'manager', setup: b => {
    const x = b.handlers.event_web_guest_extras;
    b.handlers.event_web_guest_extras = () => {
      const fx = makeFixture().extras;
      fx.guests[0].gift = { gift_id: 'gift-9', product_id: 'pr-gloves', product_name: 'Gloves', use_no: 'USE-000099', day: D1,
        given_at: '2026-10-20T02:20:00Z', given_by_name: 'Staff One' };
      return x ? x() : fx;
    };
  } });
  await click(tab('Check-in'));
  assert.ok(checkRow('g-vip').textContent.includes('Gift: Gloves · USE-000099'));
  await click(button('Undo gift', checkRow('g-vip')));
  await setValue(modal().querySelector('textarea'), 'Wrong size');
  await click(button('Undo gift', modal()));
  assert.deepEqual(callsOf('event_vip_gift_undo').at(-1).args, { p_gift_id: 'gift-9', p_reason: 'Wrong size' });
  assert.ok(checkRow('g-vip').textContent.includes('quoting USE-000123'), 'the answer says how to put it back');
});

// ── Website tab ────────────────────────────────────────────────────────────
test('website tab: for Owners, Admins and Managers, not staff', async () => {
  await mount({ role: 'staff' });
  assert.equal(tab('Website'), undefined);
  for (const role of ['owner', 'admin', 'manager']) {
    await mount({ role });
    assert.ok(tab('Website'), `${role} sees the Website tab`);
  }
});

test('website tab: readiness, the address, the code, the settings to paste and the contract to copy', async () => {
  await mount({ role: 'manager' });
  await click(tab('Website'));
  assert.deepEqual(callsOf('event_web_settings_get').map(c => c.args), [{ p_event_id: 'ev-1' }]);
  const t = text();
  assert.ok(document.querySelector('[data-readiness]').textContent.includes('"$72 discount Voucher" has no price at the store'));
  assert.ok(t.includes('No live key yet.'));
  assert.equal(document.querySelector('[data-endpoint]').textContent, 'https://project.supabase.example/functions/v1/event-website');
  assert.equal(document.querySelector('[data-code]').textContent, 'TEST-SEMINAR');
  assert.ok(document.querySelector('[data-env]').textContent.includes('ENERGIA_EVENT_API_URL=https://project.supabase.example/functions/v1/event-website'));
  assert.ok(document.querySelector('[data-env]').textContent.includes('ENERGIA_EVENT_CODE=TEST-SEMINAR'));
  assert.ok(document.querySelector('[data-contract]').textContent.includes('export const CONTRACT_VERSION = 1'));
  assert.ok(document.querySelector('[data-example]').textContent.includes("callEventApi(config, 'register'"));
  // The days and hours the website shows are the event's own (9 am to 7 pm, the owner's answer of 20 Oct).
  assert.ok(document.querySelector('[data-hours]').textContent.includes('09:00–19:00'), document.querySelector('[data-hours]').textContent);
  assert.ok(document.querySelector('[data-hours]').textContent.includes('Edit event'));
  await click(button('Copy settings'));
  assert.ok(clipboard.at(-1).startsWith('ENERGIA_EVENT_API_URL='));
  await click(button('Copy contract'));
  assert.equal(clipboard.at(-1), readFileSync(join(REPO, 'src/components/events/eventWebsiteContract.ts'), 'utf8'));
  assert.ok(document.querySelector('[data-section="requests"]').textContent.includes('register'));
});

test('website tab: the usage example compiles as copied, beside the contract, and runs nothing when imported', async () => {
  await mount({ role: 'manager' });
  await click(tab('Website'));
  await click(button('Copy example'));
  const example = clipboard.at(-1);
  assert.ok(example.startsWith('// src/lib/event-api.ts on the website'));
  const ts = (await import('typescript')).default;
  const dir = mkdtempSync(join(tmpdir(), 'event-api-example-'));
  try {
    writeFileSync(join(dir, 'event-api.ts'), example);
    writeFileSync(join(dir, 'event-api-contract.ts'), readFileSync(join(REPO, 'src/components/events/eventWebsiteContract.ts')));
    // The website is Next.js on Node: process.env as @types/node declares it.
    writeFileSync(join(dir, 'node-env.d.ts'), 'declare const process: { env: Record<string, string | undefined> };\n');
    const program = ts.createProgram([join(dir, 'event-api.ts'), join(dir, 'node-env.d.ts')], {
      strict: true, noEmit: true, noUnusedLocals: true, isolatedModules: true, skipLibCheck: true,
      target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler,
      lib: ['lib.es2022.d.ts', 'lib.dom.d.ts'],
    });
    const problems = ts.getPreEmitDiagnostics(program).map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n'));
    assert.deepEqual(problems, []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  assert.ok(!/^\s*(const|let|var)\s+\w+\s*=\s*await\b/m.test(example), 'no top-level await: importing it calls nothing');
  assert.ok(example.includes('export async function eventInfo()') && example.includes('export async function register('));
});

test('website tab: a Manager reads the settings, cannot change them or make keys, and sets the venue', async () => {
  await mount({ role: 'manager' });
  await click(tab('Website'));
  assert.ok(document.querySelector('fieldset.events-web-form').disabled, 'the settings are read-only');
  assert.ok(!button('Save settings') && !button('Create live key') && !button('Revoke'));
  assert.ok(text().includes('Only an Owner changes these settings and the keys.'));
  await setValue(document.querySelector('input[aria-label="Venue"]'), 'Hall 2, Example Centre');
  await click(button('Save venue'));
  assert.deepEqual(callsOf('event_web_set_venue').at(-1).args, { p_event_id: 'ev-1', p_venue: 'Hall 2, Example Centre' });
});

test('website tab: an Owner saves the settings; Live asks first', async () => {
  await mount({ role: 'owner' });
  await click(tab('Website'));
  await setValue(document.querySelector('input[aria-label="Event code"]'), 'health-seminar-nov26');
  await click(buttons().find(b => b.closest('[aria-label="Website mode"]') && b.textContent.trim() === 'Live'));
  await click(button('Save settings'));
  assert.equal(callsOf('event_web_settings_save').length, 0, 'Live asks first');
  assert.ok(modal().textContent.includes('Switch the website Live?'));
  await click(modal().querySelector('[data-confirm]'));
  const saved = callsOf('event_web_settings_save').at(-1).args;
  assert.equal(saved.p_event_id, 'ev-1');
  assert.equal(saved.p_settings.code, 'HEALTH-SEMINAR-NOV26');
  assert.equal(saved.p_settings.mode, 'live');
  assert.deepEqual(saved.p_settings.vip_voucher_ids, ['v-72', 'v-3in1']);
  assert.equal(saved.p_settings.bank_payment_method_id, null);
  assert.equal(saved.p_settings.sync_url, `${SITE}/api/app/sync`);
  assert.ok(text().includes('The website settings are saved.'));
});

test('website tab: a key is shown once, and gone when its window closes; a key is revoked with a reason', async () => {
  await mount({ role: 'owner' });
  await click(tab('Website'));
  await click(button('Create live key'));
  await setValue(modal().querySelector('input[aria-label="Key label"]'), 'Vercel production');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_web_key_create').at(-1).args, { p_event_id: 'ev-1', p_kind: 'live', p_label: 'Vercel production' });
  const shown = modal().querySelector('[data-new-key]');
  assert.equal(shown.value, 'evk_live_NeWkEyNeWkEyNeWkEyNeWkEyNeWkEyNeWkEyNeWkzzzz');
  assert.ok(modal().textContent.includes('It is shown only now.'));
  await click(button('Copy key', modal()));
  assert.equal(clipboard.at(-1), 'evk_live_NeWkEyNeWkEyNeWkEyNeWkEyNeWkEyNeWkEyNeWkzzzz');
  await click(modal().querySelector('[data-copied]'));
  assert.ok(!document.body.innerHTML.includes('NeWkEyNeWkEy'), 'the key is nowhere on the page once its window closes');

  await click(button('Revoke', document.querySelector('[data-key="k-1"]')));
  await setValue(modal().querySelector('textarea'), 'Testing finished');
  await click(button('Revoke key', modal()));
  assert.deepEqual(callsOf('event_web_key_revoke').at(-1).args, { p_key_id: 'k-1', p_reason: 'Testing finished' });
});

test('website tab: a test row of the affiliate through her own link says so, with the note', async () => {
  await mount({ role: 'manager', setup: b => {
    b.handlers.event_web_settings_get = () => {
      const v = { ...makeFixture().settings, can_manage: false, can_clear_tests: true, can_set_venue: true };
      v.test.registrations[0].referral_code = 'AFF123'; v.test.registrations[0].referral_state = 'valid';
      v.test.registrations[0].people[0].test_outcome = { match: 'held', hold_reason: 'affiliate_name', referral: 'self' };
      v.test.registrations[0].people[0].referral_note = NAME_NOTE;
      return v;
    };
  } });
  await click(tab('Website'));
  const t = document.querySelector('[data-section="test"]');
  assert.ok(t.textContent.includes('A live key would have held for staff to match (Their name is the affiliate\'s (whose link was used), on a phone and email not on her record.), not referred (whether staff link her record or make someone else with her name a customer).'));
  assert.equal(t.querySelector('[data-referral-note]').textContent, NAME_NOTE);
});

test('website tab: a test row linked by the phone and the email says so (469)', async () => {
  await mount({ role: 'manager', setup: b => {
    b.handlers.event_web_settings_get = () => {
      const v = { ...makeFixture().settings, can_manage: false, can_clear_tests: true, can_set_venue: true };
      v.test.registrations[0].referral_code = 'AFF123'; v.test.registrations[0].referral_state = 'valid';
      v.test.registrations[0].people[0].test_outcome = { match: 'phone_and_email', hold_reason: null, referral: 'already_customer' };
      return v;
    };
  } });
  await click(tab('Website'));
  const t = document.querySelector('[data-section="test"]').textContent;
  assert.ok(t.includes('A live key would have linked to the customer with this phone and email address, not referred (already a customer).'), t);
  assert.ok(!t.includes('phone_and_email'), 'the raw value is never shown');
});

test('website tab: test rows say what a live key would have done, and are cleared', async () => {
  await mount({ role: 'manager' });
  await click(tab('Website'));
  const t = document.querySelector('[data-section="test"]').textContent;
  assert.ok(t.includes('REG-20261020-TTTT0001') && t.includes('Tess Testing'));
  assert.ok(t.includes('A live key would have made a new customer.'));
  assert.ok(t.includes('A live key would have made 1 invoice(s) of S$72.00.'));
  assert.equal(document.querySelector('[data-section="test"] [data-referral-note]'), null, 'no note for someone not found to be the affiliate');
  await click(button('Clear test data'));
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_web_test_clear').at(-1).args, { p_event_id: 'ev-1' });
  assert.ok(text().includes('Test data cleared: 1 registration(s), 1 VIP order(s), 3 request(s).'));
});

// ── Website orders: the VIP orders ─────────────────────────────────────────
const vipRow = id => document.querySelector(`tr[data-vip-order="${id}"]`);
test('website orders: the VIP orders first; without a channel the channel part is left out', async () => {
  await mount({ role: 'manager' });
  await click(tab('Website orders'));
  assert.deepEqual(callsOf('event_vip_orders_list').map(c => c.args), [{ p_event_id: 'ev-1' }]);
  const pn = vipRow('VIP-20261020-00000001');
  assert.ok(pn.textContent.includes('PayNow') && pn.textContent.includes('ref PN-1') && pn.textContent.includes('S$144.00'));
  assert.ok(pn.textContent.includes('2 × S$72.00'));
  assert.ok(pn.querySelector('.badge-danger').textContent === 'To match', 'a person still to match says so');
  const hp = vipRow('VIP-20261020-00000002');
  assert.ok(hp.textContent.includes('INV-TEST-0001'));
  assert.ok(hp.textContent.includes('HitPay refunded S$72.00'), 'HitPay\'s refund notice shows until it is covered');
  assert.ok(vipRow('VIP-20261020-00000003').textContent.includes('HitPay charged S$70.00, but 1 × VIP costs S$72.00'));
  assert.ok(!text().includes('This event has no website channel'), 'no channel: its part is left out');
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('website orders: Create invoices asks whether the money arrived, then makes them', async () => {
  await mount({ role: 'admin' });
  await click(tab('Website orders'));
  await click(button('Create invoices', vipRow('VIP-20261020-00000001')));
  assert.ok(modal().textContent.includes('S$144.00 arrived by PayNow, reference PN-1'), modal().textContent);
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_vip_order_invoice').at(-1).args, { p_order_id: 'vo-1' });
  assert.ok(text().includes('VIP-20261020-00000001 is invoiced: INV-TEST-0005, INV-TEST-0006.'));
  assert.ok(!button('Close as refunded', vipRow('VIP-20261020-00000003')), 'an Admin does not close orders as refunded');
  assert.ok(!button('Dismiss', vipRow('VIP-20261020-00000003')), 'a HitPay payment is never dismissed');
});

test('website orders: a transfer whose typed amount is not the total: an Owner or Manager enters what arrived', async () => {
  const short = b => {
    b.handlers.event_vip_orders_list = () => {
      const v = makeFixture().vip;
      Object.assign(v.orders[0], { amount_paid: 72, status: 'needs_review', review_reason: 'S$72.00 was paid, but 2 × VIP costs S$144.00' });
      return { ...v, can_close: true };
    };
  };
  await mount({ role: 'manager', setup: short });
  await click(tab('Website orders'));
  await click(button('Create invoices', vipRow('VIP-20261020-00000001')));
  assert.ok(modal().textContent.includes('Expected S$144.00 (2 × S$72.00) · the buyer typed S$72.00'), modal().textContent);
  assert.ok(modal().textContent.includes('dismiss this order and send the VIP link again'));
  assert.equal(modal().querySelector('[data-arrived]').value, '72.00');
  await setValue(modal().querySelector('[data-arrived]'), '');
  await click(modal().querySelector('[data-confirm]'));
  assert.ok(modal().textContent.includes('Enter the amount that arrived, in S$.'), 'an empty amount keeps the window open');
  assert.equal(callsOf('event_vip_order_invoice').length, 0);
  await setValue(modal().querySelector('[data-arrived]'), '144');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_vip_order_invoice').at(-1).args, { p_order_id: 'vo-1', p_amount_cents: 14400 });

  await mount({ role: 'admin', setup: short });
  await click(tab('Website orders'));
  await click(button('Create invoices', vipRow('VIP-20261020-00000001')));
  assert.equal(modal().querySelector('[data-arrived]'), null, 'an Admin does not enter amounts');
  assert.ok(modal().textContent.includes('Only an Owner or Manager can enter the amount that arrived.'));
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_vip_order_invoice').at(-1).args, { p_order_id: 'vo-1' });
});

test('website orders: a transfer is dismissed with a reason; an Owner or Manager closes a payment refunded outside the app', async () => {
  await mount({ role: 'manager' });
  await click(tab('Website orders'));
  await click(button('Dismiss', vipRow('VIP-20261020-00000001')));
  await setValue(modal().querySelector('textarea'), 'Sent twice');
  await click(button('Dismiss', modal()));
  assert.deepEqual(callsOf('event_vip_order_dismiss').at(-1).args, { p_order_id: 'vo-1', p_reason: 'Sent twice', p_dismiss: true });
  await click(button('Close as refunded', vipRow('VIP-20261020-00000003')));
  await setValue(modal().querySelector('textarea'), 'Refunded in HitPay');
  await click(button('Close as refunded', modal()));
  assert.deepEqual(callsOf('event_vip_order_close_refunded').at(-1).args, { p_order_id: 'vo-3', p_reason: 'Refunded in HitPay', p_close: true });
});

// ── 444: an online payment started and not paid ───────────────────────────
// Its checkout closes at 06:35 UTC: 14:35 in Singapore (the page's clock), whatever the browser's time zone.
const CHECKOUT = { order_id: 'VIP-20261021-0000000C', opened_at: '2026-10-21T05:25:00Z', expires_at: '2026-10-21T06:35:00Z', people: 1 };
const withCheckout = (b, { known = true, payment = false, people = 1 } = {}) => {
  b.handlers.event_web_guest_extras = () => {
    const x = makeFixture().extras;
    const held = x.guests.find(g => g.guest_id === 'g-held');
    const checkout = { ...CHECKOUT, people };
    Object.assign(held, { vip: 'pending', vip_checkout: known ? checkout : undefined });
    if (!known) delete held.vip_checkout;
    Object.assign(x.holds[0], { vip_waiting: true, vip_payment: payment, vip_checkout: payment ? null : checkout });
    if (!known) delete x.holds[0].vip_checkout;
    return x;
  };
};

test('444: an open unpaid checkout says "Online payment started, not paid (until HH:MM)", not "VIP payment waiting"', async () => {
  await mount({ role: 'manager', setup: b => withCheckout(b) });
  const panel = document.querySelector('[data-holds]');
  const badge = panel.querySelector('[data-hold="p-3"] [data-hold-vip]');
  assert.equal(badge.textContent.trim(), 'Online payment started, not paid (until 14:35)');
  assert.equal(badge.dataset.holdVip, 'checkout');
  assert.ok(!panel.textContent.includes('VIP payment waiting'), 'not a payment waiting');
  assert.equal(row('g-held').querySelector('[data-vip-checkout]').textContent.trim(), 'Online payment started, not paid (until 14:35)',
    'the guest row says the same');
  assert.equal(row('g-free').querySelector('[data-vip-checkout]'), null, 'a transfer waiting still says VIP waiting · PayNow');
  assert.ok(row('g-free').textContent.includes('VIP waiting · PayNow'));
  globalThis.__exports = [];
  await click(button('Export Excel'));
  const body = globalThis.__exports.at(-1).sheet.ws.body;
  assert.equal(body.find(r => r.Name === 'Hana Held').VIP, 'Online payment started, not paid');
  assert.equal(body.find(r => r.Name === 'Fred Free').VIP, 'Waiting');

  // A payment taken (or a transfer sent) still waits: "VIP payment waiting".
  await mount({ role: 'manager', setup: b => withCheckout(b, { payment: true }) });
  assert.equal(document.querySelector('[data-hold="p-3"] [data-hold-vip]').textContent.trim(), 'VIP payment waiting');
  // A server before 444 (no vip_checkout): its vip_waiting says "VIP payment waiting", as before.
  await mount({ role: 'manager', setup: b => withCheckout(b, { known: false }) });
  assert.equal(document.querySelector('[data-hold="p-3"] [data-hold-vip]').textContent.trim(), 'VIP payment waiting');
  assert.equal(row('g-held').querySelector('[data-vip-checkout]'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('444: closing a registration with an unpaid checkout says it closes too (for how many people), and that it did', async () => {
  // A checkout for one person: no word of a group.
  await mount({ role: 'manager', setup: b => withCheckout(b) });
  await click(document.querySelector('[data-close="p-3"]'));
  assert.equal(modal().querySelector('[data-close-checkout]').textContent.replace(/\s+/g, ' ').trim(),
    'Online payment started, not paid (until 14:35): their HitPay checkout VIP-20261021-0000000C is closed too. '
    + 'If HitPay reports a payment for it later, it waits on Website orders to be refunded.');

  // One checkout for two people: it closes for both, and the dialog says so.
  await mount({ role: 'manager', setup: b => {
    withCheckout(b, { people: 2 });
    b.handlers.event_registration_close = () => ({ ok: true, checkouts_closed: [{ order_id: CHECKOUT.order_id, people: 2, open: true }] });
  } });
  await click(document.querySelector('[data-close="p-3"]'));
  assert.equal(modal().querySelector('[data-close-checkout]').textContent.replace(/\s+/g, ' ').trim(),
    'Online payment started, not paid (until 14:35): their HitPay checkout VIP-20261021-0000000C is closed too. '
    + 'It is one checkout for 2 people: it closes for all of them (the others stay registered and can start a new one). '
    + 'If HitPay reports a payment for it later, it waits on Website orders to be refunded.');
  await setValue(modal().querySelector('textarea'), 'Pressed back, not coming');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_registration_close').at(-1).args, { p_person_id: 'p-3', p_reason: 'Pressed back, not coming' });
  assert.ok(text().includes('Hana Held\'s registration was closed. Their unpaid online checkout VIP-20261021-0000000C was closed too (for all 2 people on it).'),
    text());

  // Without a checkout, no note; a payment taken: the 436 refusal reads as what to do on Website orders.
  await mount({ role: 'manager', setup: b => {
    b.handlers.event_registration_close = () => ({ __error: 'A VIP payment for Hana Held is waiting: deal with it on Website orders first.' });
  } });
  await click(document.querySelector('[data-close="p-3"]'));
  assert.equal(modal().querySelector('[data-close-checkout]'), null);
  await setValue(modal().querySelector('textarea'), 'Duplicate');
  await click(modal().querySelector('[data-confirm]'));
  assert.ok(modal().querySelector('.alert-danger').textContent.includes(
    'Hana Held has a VIP payment on Website orders that was paid, or a transfer they sent, so the registration cannot be closed yet. '
    + 'On Website orders, create its invoices, or close it as refunded once the money is back (dismiss a transfer that never arrived); '
    + 'then close the registration.'), modal().textContent);
});

const vipCheckoutOrders = b => {
  b.handlers.event_vip_orders_list = () => {
    const v = makeFixture().vip;
    const base = { provider: 'hitpay', is_test: false, livemode: true, unit_amount: 72, quantity: 1, amount_total: 72, amount_paid: null,
      payer_email: 'olive@example.com', payer_phone: null, paid_at: null, paid_on: null, reference: null,
      hitpay_payment_request_id: null, hitpay_payment_id: null, refusal: null, waiting_for_match: false, test_note: null,
      test_would: null, refunded_total: 0, refund_noted_at: null, refund_covered: false, created_at: '2026-10-21T05:25:00Z',
      people: [{ person_id: 'p-3', position: 1, name: 'Hana Held', phone: null, email: null, match: 'held', hold_reason: 'phone_in_use',
        customer_id: null, customer_name: null, days: [D2], invoice_id: null, invoice_no: null, invoice_status: null }] };
    v.orders.push(
      { ...base, id: 'vo-open', order_id: 'VIP-20261021-0000000C', status: 'pending', payer_name: 'Olive Open', quantity: 2, amount_total: 144,
        checkout_opened_at: CHECKOUT.opened_at, expires_at: CHECKOUT.expires_at, expired: false, review_reason: null },
      { ...base, id: 'vo-old', order_id: 'VIP-20261021-0000000D', status: 'pending', payer_name: 'Otto Old',
        checkout_opened_at: '2026-10-21T01:00:00Z', expires_at: '2026-10-21T02:10:00Z', expired: true, review_reason: null },
      { ...base, id: 'vo-shut', order_id: 'VIP-20261021-0000000E', status: 'dismissed', payer_name: 'Sue Shut',
        checkout_opened_at: '2026-10-21T01:00:00Z', expires_at: '2026-10-21T02:10:00Z', expired: false,
        review_reason: 'Checkout closed: Pressed back' });
    return { ...v, can_close: true };
  };
};

test('444: Website orders shows an open unpaid checkout by default, and an Owner or Manager closes it with a reason', async () => {
  await mount({ role: 'manager', setup: vipCheckoutOrders });
  await click(tab('Website orders'));
  const open = vipRow('VIP-20261021-0000000C');
  assert.ok(open, 'an open checkout is shown by default');
  assert.equal(open.querySelector('[data-unpaid]').textContent.trim(), 'Online payment started, not paid (until 14:35)');
  assert.equal(vipRow('VIP-20261021-0000000D'), null, 'an expired one is not');
  assert.equal(vipRow('VIP-20261021-0000000E'), null, 'nor a closed one');
  assert.ok(!button('Close unpaid checkout', vipRow('VIP-20261020-00000003')), 'a HitPay payment is never closed as a checkout');
  assert.ok(!button('Dismiss', open), 'nor dismissed');
  const extrasBefore = callsOf('event_web_guest_extras').length;
  await click(button('Close unpaid checkout', open));
  assert.ok(modal().textContent.includes('Why is it closed? It is one checkout for 2 people: it closes for all of them (the others stay '
    + 'registered and can start a new one). If HitPay reports a payment for it later, it waits here to be refunded.'), modal().textContent);
  await setValue(modal().querySelector('textarea'), 'Pressed back, not paying online');
  await click(button('Close checkout', modal()));
  assert.deepEqual(callsOf('event_vip_order_dismiss').at(-1).args,
    { p_order_id: 'vo-open', p_reason: 'Pressed back, not paying online', p_dismiss: true });
  assert.ok(text().includes('VIP-20261021-0000000C\'s unpaid checkout is closed.'), text());
  assert.ok(callsOf('event_web_guest_extras').length > extrasBefore, 'the guest list and To match are read again');

  await setValue(document.querySelector('select[aria-label="VIP order status"]'), 'all');
  const old = vipRow('VIP-20261021-0000000D');
  assert.equal(old.querySelector('[data-unpaid]').textContent.trim(), 'Not paid: the checkout expired');
  assert.equal(old.querySelector('.events-status-badge').textContent.trim(), 'Checkout expired', 'not "Checkout open"');
  assert.ok(button('Close unpaid checkout', old), 'an expired one may be closed too');
  const shut = vipRow('VIP-20261021-0000000E');
  assert.ok(shut.textContent.includes('Checkout closed') && shut.textContent.includes('Checkout closed: Pressed back'));
  assert.deepEqual(buttons(shut).map(b => b.textContent.trim()), [], 'a closed checkout is not restored');
  assert.deepEqual(globalThis.__renderErrors, []);

  await mount({ role: 'owner', setup: vipCheckoutOrders });
  await click(tab('Website orders'));
  assert.ok(button('Close unpaid checkout', vipRow('VIP-20261021-0000000C')), 'an Owner closes one too');
});

test('444: an Admin sees an open unpaid checkout but is not offered Close unpaid checkout (the owner, 22 Oct 2026)', async () => {
  // The fixture's can_close is true: the page checks the Admin's role itself.
  await mount({ role: 'admin', setup: vipCheckoutOrders });
  await click(tab('Website orders'));
  const open = vipRow('VIP-20261021-0000000C');
  assert.ok(open, 'an open checkout is shown by default');
  assert.equal(open.querySelector('[data-unpaid]').textContent.trim(), 'Online payment started, not paid (until 14:35)');
  assert.ok(!button('Close unpaid checkout', open), 'an Admin does not close an unpaid checkout');
  assert.ok(!button('Dismiss', open), 'nor dismisses it');
  await setValue(document.querySelector('select[aria-label="VIP order status"]'), 'all');
  assert.ok(!button('Close unpaid checkout', vipRow('VIP-20261021-0000000D')), 'nor an expired one');
  assert.equal(document.querySelector('[data-close-checkout]'), null);
  assert.ok(button('Dismiss', vipRow('VIP-20261020-00000001')), 'an Admin still dismisses a transfer (436)');
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── 449: taken off the list, then signed up again ─────────────────────────
// Rita was taken off ("Cannot come", 21 Oct 14:05 in Singapore) and signed up again on 22 Oct 09:10 for both days.
const AGAIN = { held_at: '2026-10-22T01:10:00Z', removed_reason: 'Cannot come', removed_at: '2026-10-21T06:05:00Z' };
const signedUpAgain = (b, { alsoHeld = false, server449 = true } = {}) => {
  b.handlers.event_guest_list = () => {
    const fx = makeFixture();
    const rita = { ...structuredClone(fx.guests.find(g => g.guest_id === 'g-staff')), guest_id: 'g-again', name: 'Rita Returned',
      phone: '+61491578888', customer_id: 'c-rita', customer_name: 'Rita Returned', status: 'cancelled', cancelled_reason: 'Cannot come',
      notes: 'Website · REG-20261020-AAAA0009 · 1 of 1', days: [{ day: D1, attended_at: null, check_in_code: null, checked_in_by_name: null }] };
    return [...fx.guests, rita];
  };
  b.handlers.event_web_guest_extras = () => {
    const x = makeFixture().extras;
    x.guests.push({ guest_id: 'g-again', person_id: 'p-9', website: true, is_test: false, registration_id: 'REG-20261020-AAAA0009', position: 1,
      group_size: 1, parked: false, vip: 'none', vip_guest: false, vip_invoice_no: null, vip_waiting: null, vip_checkout: null, hold: null,
      ...(server449 ? { signed_up_again: { held_at: AGAIN.held_at, days: [D1, D2] } } : {}),
      closed: false, match: 'new_customer', referral: null, upgrade_token: 'vip_cdefghijklmnopqrstuvwxyz23', gift: null });
    x.holds.push({ person_id: 'p-9', guest_id: 'g-again', registration_id: 'REG-20261020-AAAA0009', position: 1, group_size: 1,
      held_at: AGAIN.held_at, reason: 'signed_up_again', full_name: 'Rita Returned', phone: '+61491578888', phone_norm: '+61491578888',
      email: 'rita@example.com', days: [D1], vip_waiting: false, vip_payment: false, vip_checkout: null, referral_note: null, candidates: [],
      ...(server449 ? { signed_up_again: { ...AGAIN, days: [D1, D2] } } : {}) });
    if (alsoHeld) x.holds[0].signed_up_again = { ...AGAIN, days: [D2] };
    // The server says what the caller's role may do (as the default handler).
    x.can_close_holds = ['owner', 'manager'].includes(globalThis.__auth.profile.role);
    return x;
  };
  b.handlers.event_set_guest_cancelled = a => ({ guest_id: a.p_guest_id, status: a.p_cancelled ? 'cancelled' : 'registered',
    days_dropped: [], days_added: a.p_cancelled ? [] : [D2], signed_up_again: !a.p_cancelled, over_capacity: [] });
  b.handlers.event_registration_close = () => ({ ok: true, checkouts_closed: [], signed_up_again: 'closed' });
};
const holdOf = id => document.querySelector(`[data-hold="${id}"]`);

test('449: someone taken off who signed up again waits under To match: who took them off, the days asked; staff put them back', async () => {
  await mount({ role: 'staff', setup: b => signedUpAgain(b) });
  const panel = document.querySelector('[data-holds]');
  assert.ok(panel.textContent.includes('To match (2)'));
  assert.ok(panel.textContent.replace(/\s+/g, ' ').includes('Someone taken off the list who signed up again waits here too: put them back '
    + 'on the list, or close it to leave them off. The website told them their place will be confirmed.'));
  const rita = holdOf('p-9');
  assert.ok(rita.textContent.includes('Signed up again after being taken off the list.'));
  assert.ok(rita.querySelector('[data-signed-up-again]').textContent.startsWith(
    'Taken off the list (Cannot come · Wed 21 Oct 2026, 14:05); signed up again Thu 22 Oct 2026, 09:10, asking for '),
    rita.querySelector('[data-signed-up-again]').textContent);
  assert.equal(rita.querySelector('table'), null, 'no customers to choose from: they have their customer');
  assert.ok(!rita.querySelector('[data-other]') && !rita.querySelector('[data-create]') && !rita.querySelector('[data-attach]'),
    'nothing to link or make');
  assert.ok(!rita.querySelector('[data-close]'), 'staff do not close it');
  assert.ok(holdOf('p-3').querySelector('[data-create]') && !holdOf('p-3').querySelector('[data-put-back]'),
    'a To match person is as before (no Put back)');

  await click(rita.querySelector('[data-put-back]'));
  assert.ok(modal().textContent.includes('Put Rita Returned back on the list'));
  assert.ok(modal().querySelector('[data-put-back-note]').textContent.startsWith(
    'Rita Returned comes back on the guest list for the days they had and the days they asked for now ('));
  assert.ok(modal().querySelector('[data-put-back-note]').textContent.includes('The website sends them nothing: let them know on WhatsApp that '
    + 'their place is confirmed, and send their VIP link (Guests tab, Copy VIP link) so they can buy VIP or change their answers.'));
  assert.equal(modal().querySelector('[data-confirm]').disabled, false, 'a note is optional');
  assert.equal(modal().querySelector('[data-confirm]').textContent.trim(), 'Put back');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_set_guest_cancelled').at(-1).args, { p_guest_id: 'g-again', p_cancelled: false, p_reason: null });
  assert.ok(text().includes('Rita Returned is back on the guest list.') && text().includes('added, as they asked. The website sends them nothing: '
    + 'let them know on WhatsApp that their place is confirmed, and send their VIP link (Guests tab, Copy VIP link)'), text());
  assert.equal(callsOf('event_guest_list').length, 2, 'the guest list (and To match) is read again');
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('449: an Owner or Manager closes it: they stay off; a stale page is told and reads the list again', async () => {
  await mount({ role: 'manager', setup: b => signedUpAgain(b) });
  await click(holdOf('p-9').querySelector('[data-close]'));
  assert.ok(modal().textContent.includes('Leave Rita Returned off the list'));
  assert.equal(modal().querySelector('[data-close-signed-up-again]').textContent,
    'They stay off the guest list (their registration stays as it is). If they sign up again, they show here again.');
  assert.ok(!modal().textContent.includes('For a registration that is not a real one'));
  assert.ok(modal().querySelector('[data-confirm]').disabled, 'a reason is needed');
  await setValue(modal().querySelector('textarea'), 'Asked not to come');
  assert.equal(modal().querySelector('[data-confirm]').textContent.trim(), 'Close');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_registration_close').at(-1).args, { p_person_id: 'p-9', p_reason: 'Asked not to come' });
  assert.ok(text().includes('Rita Returned stays off the guest list.'));

  // An unpaid HitPay checkout of hers (opened before she was taken off): the window says it closes too, and it did.
  await mount({ role: 'owner', setup: b => {
    signedUpAgain(b);
    const extras = b.handlers.event_web_guest_extras;
    b.handlers.event_web_guest_extras = () => {
      const x = extras();
      Object.assign(x.holds.find(h => h.person_id === 'p-9'), { vip_waiting: true, vip_checkout: { ...CHECKOUT } });
      return x;
    };
    b.handlers.event_registration_close = () => ({ ok: true, signed_up_again: 'closed',
      checkouts_closed: [{ order_id: CHECKOUT.order_id, people: 1, open: true }] });
  } });
  await click(holdOf('p-9').querySelector('[data-close]'));
  assert.equal(modal().querySelector('[data-close-checkout]').textContent.replace(/\s+/g, ' ').trim(),
    'Online payment started, not paid (until 14:35): their HitPay checkout VIP-20261021-0000000C is closed too. '
    + 'If HitPay reports a payment for it later, it waits on Website orders to be refunded.');
  await setValue(modal().querySelector('textarea'), 'Asked not to come');
  await click(modal().querySelector('[data-confirm]'));
  assert.ok(text().includes('Rita Returned stays off the guest list. Their unpaid online checkout VIP-20261021-0000000C was closed too.'), text());

  // Someone put her back meanwhile: the server says so, and the page reads the list again.
  await mount({ role: 'manager', setup: b => {
    signedUpAgain(b);
    b.handlers.event_registration_close = () => ({ __error: 'This registration is not waiting for staff any more.' });
  } });
  const reads = callsOf('event_guest_list').length;
  await click(holdOf('p-9').querySelector('[data-close]'));
  await setValue(modal().querySelector('textarea'), 'Asked not to come');
  await click(modal().querySelector('[data-confirm]'));
  assert.ok(modal().querySelector('.alert-danger').textContent.includes('This registration is not waiting for staff any more.'));
  assert.equal(callsOf('event_guest_list').length, reads + 1, 'the list is read again');
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('449: the Guests tab marks the cancelled row "Signed up again"; Restore there puts them back with the days asked', async () => {
  await mount({ role: 'staff', setup: b => signedUpAgain(b) });
  assert.equal(row('g-again'), null, 'cancelled: not with the registered guests');
  const group = document.querySelector('[role="group"][aria-label="Website filter"]');
  assert.ok(buttonStarting('To match', group).textContent.includes('(2)'));
  await setValue(document.querySelector('select[aria-label="Status"]'), 'cancelled');
  const badge = row('g-again').querySelector('[data-signed-up-again]');
  assert.equal(badge.textContent.trim(), 'Signed up again');
  assert.ok(badge.title.startsWith('Signed up again after being taken off the list, asking for '));
  await click(buttonStarting('To match', group));
  assert.deepEqual([...document.querySelectorAll('.events-table tbody tr')].map(r => r.dataset.guest), ['g-again'],
    'To match shows their cancelled row');
  await click(button('Restore', row('g-again')));
  assert.deepEqual(callsOf('event_set_guest_cancelled').at(-1).args, { p_guest_id: 'g-again', p_cancelled: false, p_reason: null });
  assert.ok(text().includes('Rita Returned is restored.') && text().includes('added, as they asked when they signed up again.'), text());
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('449: a To match person also taken off who signed up again shows once, with both; a server before 449 shows the code', async () => {
  await mount({ role: 'manager', setup: b => signedUpAgain(b, { alsoHeld: true }) });
  const hana = holdOf('p-3');
  assert.ok(hana.textContent.includes('Their phone number belongs to a customer under another name.')
    && hana.textContent.includes('Signed up again after being taken off the list.'));
  assert.ok(hana.querySelector('[data-attach="c-9"]') && hana.querySelector('[data-create]') && hana.querySelector('[data-put-back]')
    && hana.querySelector('[data-close]'), 'link, make, put back or close');
  await click(hana.querySelector('[data-close]'));
  assert.ok(modal().textContent.includes('For a registration that is not a real one'), 'Close there closes the registration (as 436)');
  assert.ok(modal().textContent.includes('Close Hana Held\'s registration'));

  // The guest extras of a server without the details: the page still offers Put back (Restore) and reads.
  await mount({ role: 'staff', setup: b => signedUpAgain(b, { server449: false }) });
  assert.ok(holdOf('p-9').querySelector('[data-put-back]'));
  assert.ok(!holdOf('p-9').querySelector('[data-signed-up-again]')?.textContent.includes('asking for'));
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── The contract ───────────────────────────────────────────────────────────
test('the contract the tab shows is the recorded version, as the edge function\'s is', () => {
  const md5 = f => createHash('md5').update(readFileSync(join(REPO, f))).digest('hex');
  const recorded = readFileSync(join(REPO, 'supabase/functions/event-website/contract.md5'), 'utf8').trim();
  assert.equal(md5('src/components/events/eventWebsiteContract.ts'), recorded);
  assert.equal(md5('supabase/functions/event-website/contract.ts'), recorded);
});
