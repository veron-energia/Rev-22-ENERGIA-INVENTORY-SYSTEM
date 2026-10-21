// The Event page's planning answers (436 round 7, the owner's answers of 21 Oct
// 2026), rendered for real against a fake backend, as website-tab.test.mjs
// renders the page.
//
// It checks what the page promises the owner:
//   * Guests (S1): food, allergy (red, never cut), part-day and access badges
//     from each guest's answers, merged by guest id (a VIP's show on their VIP
//     record), each with its full text for screen readers and touch screens;
//     Answers opens the full answers; staff edit them on the guest's behalf
//     (the answers, the version they opened and a note go to the server; a
//     refusal keeps the form); the form offers the guest's own days, the
//     event's half hours and the talk titles (a title no longer listed stays
//     ticked and marked; with no titles, saved talks still show); without
//     daily hours, only Whole day.
//   * The export (S2) adds the answers worded as the website's sheet, and never
//     drops them silently: a failed read gives every answer cell "Not loaded"
//     and a warning (K14); a database without round 7 adds none.
//   * Check-in (S3): allergy first, then food and access; no timing; a failed
//     read keeps the badges and says so; the answers are read at most every 2
//     minutes while Check-in is open (K13).
//   * Planning (S2): per day food, allergies (VIP marked), late and early by
//     time, what to prepare; the VIPs for the dinner, with the VIP payments
//     still waiting counted apart (K30); talks with "no longer listed"; how they
//     heard; the questions; the tab shows only with a website or answers.
//   * Website tab (S4): the talk titles, pre-filled with the suggested list,
//     reordered, removed, added (at most 20, 120 characters) and saved by an
//     Owner, Admin or Manager; back to the suggested list and "no titles" ask
//     first.
//   * To match (R6-4): someone held under the affiliate's own name is warned
//     about before a new customer is made.
//   * model.ts: the labels, limits and time rule are the contract's.
//
// Every name, phone and email here is invented.
// Run: node --test scripts/events/tests/planning.test.mjs
process.env.TZ = 'America/Los_Angeles';

import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
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
Object.defineProperty(dom.window.navigator, 'clipboard', { value: { writeText: async () => {} }, configurable: true });

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as EventsPage } from './src/pages/EventsPage';
      export * as model from './src/components/events/model';
      export * as contract from './src/components/events/eventWebsiteContract';
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
const { EventsPage, model, contract, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── dates ──────────────────────────────────────────────────────────────────
const TODAY = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const addDays = (day, n) => { const [y, m, d] = day.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10); };
const D1 = TODAY, D2 = addDays(TODAY, 1);
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const wdDMon = d => { const [y, m, dd] = d.split('-').map(Number); return `${WD[new Date(Date.UTC(y, m - 1, dd)).getUTCDay()]} ${dd} ${MON[m - 1]}`; };
const dMon = d => { const [, m, dd] = d.split('-').map(Number); return `${dd} ${MON[m - 1]}`; };

const SUGGESTED = ['Sleep better, stress less', 'Healthy joints, back and muscles', 'Good circulation for everyday energy',
  'Caring for your eyes', 'Ageing well and staying active', 'Eating well for long-term health', "Women's wellness"];
// 60 characters: shown in full on every badge (K2).
const LONG_ALLERGY = 'Peanuts, tree nuts and shellfish; carries an adrenaline pen.';
assert.equal(LONG_ALLERGY.length, 60);

// ── fixture ────────────────────────────────────────────────────────────────
const blank = () => ({ food: null, food_other: null, allergy: null, allergy_details: null, timing: [], talks: [], access: [],
  access_other: null, heard_from: null, heard_from_other: null, question: null });
function makeFixture() {
  const event = {
    id: 'ev-1', name: 'Test Health Seminar', description: null, daily_start: '09:00', daily_end: '19:00',
    early_bird_until: null, early_bird_percent: null, is_active: true, notes: null, created_at: '2026-10-20T02:00:00Z',
    first_day: D1, last_day: D2, days: [{ day: D1, capacity: null, registered: 3, attended: 0 }, { day: D2, capacity: null, registered: 2, attended: 0 }],
    stores: [{ id: 'st-van', name: 'Van Store' }],
    options: [{ id: 'op-vip', name: 'VIP', days_count: 2, price: '72.00', is_active: true, sort_order: 1, early_bird_price: null, sold: true }],
    guests: 4, ticket_guests: 1, free_guests: 3, can_manage: true, can_run: true, web_channel_mode: null,
  };
  const day = d => ({ day: d, attended_at: null, check_in_code: null, checked_in_by_name: null });
  const g = (id, name, extra) => ({
    guest_id: id, name, phone: null, customer_id: null, customer_name: null, source: 'free', status: 'registered', cancelled_reason: null,
    notes: null, registered_by: null, registered_by_name: null, ticket_option_id: null, ticket_option_name: null,
    invoice_id: null, invoice_no: null, invoice_status: null, invoice_total: null, invoice_paid: null, invoice_store_id: null,
    created_at: '2026-10-20T02:00:00Z', days: [], email: null, order_id: null, payment_methods: null, ...extra,
  });
  const guests = [
    g('g-vip', 'Vera Vip', { phone: '+61491570737', source: 'ticket', ticket_option_id: 'op-vip', ticket_option_name: 'VIP',
      invoice_id: 'inv-1', invoice_no: 'INV-TEST-0001', invoice_status: 'paid', invoice_total: 72, invoice_paid: 72,
      invoice_store_id: 'st-van', customer_id: 'c-1', customer_name: 'Vera Vip', days: [day(D1), day(D2)] }),
    g('g-vip-free', 'Vera Vip', { phone: '+61491570737', status: 'cancelled', cancelled_reason: 'Upgraded to VIP · INV-TEST-0001', days: [day(D1)] }),
    g('g-free', 'Fred Free', { phone: '+61491572983', customer_id: 'c-2', customer_name: 'Fred Free', days: [day(D1)] }),
    g('g-held', 'Hana Held', { phone: '+61491573770', days: [day(D2)] }),
    g('g-staff', 'Sam Staffadded', { days: [day(D1)] }),
  ];
  const xg = (guest_id, extra) => ({ guest_id, person_id: null, website: true, is_test: false, registration_id: null, position: 1, group_size: 1,
    parked: false, vip: 'none', vip_guest: false, vip_invoice_no: null, vip_waiting: null, hold: null, closed: false, match: 'exact',
    referral: null, upgrade_token: null, gift: null, ...extra });
  const extras = {
    settings: { store_id: 'st-van', store_name: 'Van Store', vip_option_id: 'op-vip', mode: 'live', code: 'TEST-SEMINAR',
      venue: null, site_url: 'https://healthtalk.example.com', gift_store_access: true },
    guests: [xg('g-vip', { person_id: 'p-1', vip: 'paid', vip_guest: true }), xg('g-vip-free', { person_id: 'p-1', vip: 'paid', parked: true }),
      xg('g-free', { person_id: 'p-2' }), xg('g-held', { person_id: 'p-3', match: 'held', hold: { reason: 'phone_in_use', held_at: '2026-10-20T03:00:00Z' } })],
    holds: [{ person_id: 'p-3', guest_id: 'g-held', registration_id: 'REG-20261020-AAAA0002', position: 1, group_size: 1,
      held_at: '2026-10-20T03:00:00Z', reason: 'phone_in_use', full_name: 'Hana Held', phone: '+61491573770', email: 'hana@example.com',
      days: [D2], vip_waiting: false, referral_note: null,
      candidates: [{ customer_id: 'c-9', full_name: 'Holly Holder', phone: '+61491573770', email: null, created_at: '2026-01-01T00:00:00Z',
        phone_matches: true, email_matches: false, name_matches: false }] }],
    gift_choices: [], can_close_holds: true, can_undo_gifts: true,
  };
  const vipAnswers = { ...blank(), food: 'other', food_other: 'No pork', allergy: 'no', heard_from: 'other', heard_from_other: 'Radio',
    talks: ['Sleep better, stress less', 'Managing stress at work'], timing: [{ date: D1, whole_day: true, arrive: null, leave: null }],
    question: 'Morning or evening walks?\nI walk after dinner.' };
  const row = (guest_id, days, version, answers, by = 'guest', staff_name = null) =>
    ({ guest_id, plan_id: `pl-${guest_id}`, days, version, answers, updated_at: '2026-10-21T02:05:00Z', updated_by: by, staff_name });
  const planning = {
    talk_titles: [...SUGGESTED], talk_titles_saved: false, hours: { daily_start: '09:00', daily_end: '19:00' },
    guests: [
      row('g-vip', [D1, D2], 3, vipAnswers, 'staff', 'Staff One'),
      row('g-vip-free', [D1, D2], 3, vipAnswers, 'staff', 'Staff One'),
      row('g-free', [D1], 1, { ...blank(), food: 'vegetarian', allergy: 'no', heard_from: 'tiktok', talks: ['Caring for your eyes'],
        timing: [{ date: D1, whole_day: false, arrive: '14:00', leave: '19:00' }] }),
      row('g-held', [D2], 2, { ...blank(), food: 'no_preference', allergy: 'yes', allergy_details: LONG_ALLERGY,
        timing: [{ date: D2, whole_day: false, arrive: '09:00', leave: '15:00' }], access: ['wheelchair', 'front_seat'],
        access_other: 'Needs a quiet corner near the exit door please' }),
    ],
  };
  const person = (guest_id, name, vip = false) => ({ guest_id, name, vip });
  const food = (o = {}) => ({ no_preference: 0, vegetarian: 0, vegan: 0, halal: 0, no_beef: 0, other: 0, not_said: 0, ...o });
  const summary = {
    event_id: 'ev-1', hours: { daily_start: '09:00', daily_end: '19:00' }, registered: 4, answered: 3,
    days: [
      { day: D1, label: 'Day 1', registered: 3, answered: 2, food: food({ vegetarian: 1, other: 1, not_said: 1 }),
        food_other: [{ ...person('g-vip', 'Vera Vip', true), text: 'No pork' }], allergies: [],
        late: [{ ...person('g-free', 'Fred Free'), time: '14:00' }], early: [], access: [] },
      { day: D2, label: 'Day 2', registered: 2, answered: 2, food: food({ no_preference: 1, other: 1 }),
        food_other: [{ ...person('g-vip', 'Vera Vip', true), text: 'No pork' }],
        allergies: [{ ...person('g-held', 'Hana Held'), text: LONG_ALLERGY }],
        late: [], early: [{ ...person('g-held', 'Hana Held'), time: '15:00' }],
        access: [{ ...person('g-held', 'Hana Held'), needs: ['wheelchair', 'front_seat'], other: 'Needs a quiet corner' }] },
    ],
    vip: { count: 1, answered: 1, waiting: 3, food: food({ other: 1 }), food_other: [{ ...person('g-vip', 'Vera Vip', true), text: 'No pork' }], allergies: [] },
    talks: [{ title: 'Sleep better, stress less', count: 1, listed: true }, { title: 'Caring for your eyes', count: 1, listed: true },
      ...SUGGESTED.filter(t => !['Sleep better, stress less', 'Caring for your eyes'].includes(t)).map(title => ({ title, count: 0, listed: true })),
      { title: 'Managing stress at work', count: 1, listed: false }],
    heard_from: { tiktok: 1, facebook: 0, instagram: 0, google: 0, whatsapp: 0, friend_family: 0, staff: 0, email: 0, other: 1, not_said: 2 },
    heard_from_other: [{ ...person('g-vip', 'Vera Vip', true), text: 'Radio' }],
    questions: [{ ...person('g-vip', 'Vera Vip', true), text: 'Morning or evening walks?\nI walk after dinner.' }],
  };
  const settings = {
    event_id: 'ev-1', event_name: 'Test Health Seminar',
    settings: { event_id: 'ev-1', code: 'TEST-SEMINAR', mode: 'record_only', venue: null, store_id: 'st-van', store_name: 'Van Store',
      acting_profile_id: 'u-own', acting_name: 'Owner One', vip_option_id: 'op-vip', vip_option_name: 'VIP', vip_voucher_ids: [],
      gift_product_ids: [], hitpay_payment_method_id: 'pm-hp', paynow_payment_method_id: null, bank_payment_method_id: null,
      source_option_id: null, source_label: null, source_details: null, sync_url: 'https://healthtalk.example.com/api/app/sync',
      site_url: 'https://healthtalk.example.com', last_sync_at: null, last_test_sync_at: null },
    readiness: { blocking: [], errors: [], warnings: ['The talk titles are the suggested list: set the real ones under Talk titles once the speakers\' titles are known.'] },
    endpoint_path: '/functions/v1/event-website', keys: [],
    requests: [{ type: 'planning_answers', received_at: '2026-10-21T02:05:00Z', outcome: 'ok', kind: 'live', is_write: true }],
    test: { registrations: [], orders: [] },
    choices: { stores: [{ id: 'st-van', name: 'Van Store' }], profiles: [], options: [], vouchers: [], products: [], methods: [], sources: [] },
    talks: { titles: [...SUGGESTED], saved: false, suggested: [...SUGGESTED] },
  };
  return { event, guests, extras, planning, summary, settings };
}

function createBackend(fx, role) {
  const b = { calls: [], handlers: {} };
  const manager = ['owner', 'admin', 'manager'].includes(role);
  const rpcs = {
    events_list: () => [{ ...fx.event, can_manage: manager }],
    my_assigned_stores: () => [{ store_id: 'st-van', store_name: 'Van Store', is_default: true }],
    event_guest_list: () => fx.guests,
    event_web_guest_extras: () => fx.extras,
    event_planning_list: () => fx.planning,
    event_planning_summary: () => fx.summary,
    event_planning_save: a => ({ ok: true, guest_id: a.p_guest_id, plan_id: 'pl-x', version: (a.p_version ?? 0) + 1, answers: a.p_answers,
      updated_at: '2026-10-21T03:00:00Z', updated_by: 'staff' }),
    event_check_in: a => ({ guest_id: a.p_guest_id, day: a.p_day, attended_at: '2026-10-20T02:15:00Z', check_in_code: null,
      checked_in_by: 'u-x', checked_in_by_name: 'Door Staff', already_in: false, changed: true }),
    event_registration_create_customer: () => ({ ok: true, customer_id: 'c-new', vip_orders: [] }),
    event_web_settings_get: () => ({ ...fx.settings, can_manage: role === 'owner', can_clear_tests: manager, can_set_venue: manager,
      can_set_talks: manager }),
    event_web_set_talks: a => ({ ok: true, talk_titles: a.p_titles ?? [...SUGGESTED], saved: a.p_titles !== null }),
    event_vip_orders_list: () => ({ settings: null, orders: [], can_close: false }),
    web_orders_list: () => ({ channel: null, can_switch: false, orders: [] }),
    event_invoices: () => [],
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args }); }
    select() { return this; } eq() { return this; } is() { return this; } in() { return this; } or() { return this; }
    order() { return this; } limit() { return this; } maybeSingle() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
      await Promise.resolve();
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}`, code: 'PGRST202' } };
        const out = fn(this.args);
        if (out && out.__error) return { data: null, error: { message: out.__error, code: out.__code ?? '' } };
        return { data: structuredClone(out), error: null };
      }
      // A table the fixture lists (customers for the customer search); any other reads as empty.
      const t = this.kind === 'table' ? fx.tables?.[this.name] : null;
      if (t) return { data: structuredClone(this.single ? t[0] ?? null : t), error: null };
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
async function mount({ role = 'manager', setup, fixture } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  const fx = fixture ?? makeFixture();
  backend = createBackend(fx, role);
  globalThis.__backend = backend; globalThis.__exports = []; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: USERS[role] };
  setup?.(backend, fx);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(EventsPage))));
  await tick();
  await click([...document.querySelectorAll('.events-card')].find(c => c.textContent.includes('Test Health Seminar')));
  return fx;
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
const modal = () => [...document.querySelectorAll('.modal')].at(-1);
const callsOf = name => backend.calls.filter(c => c.name === name);
const tab = label => buttons().find(b => b.getAttribute('role') === 'tab' && b.textContent.trim() === label);
const row = id => document.querySelector(`tr[data-guest="${id}"]`);
const checkRow = id => document.querySelector(`.events-checkin-row[data-guest="${id}"]`);
const badges = el => [...(el?.querySelectorAll('[data-plan-badge]') ?? [])].map(b => ({ kind: b.dataset.planBadge, text: b.textContent,
  label: b.getAttribute('aria-label'), cls: b.className }));
const choice = (scope, label) => [...scope.querySelectorAll('label')].find(l => l.textContent.trim() === label)?.querySelector('input');
const exportNow = async () => { globalThis.__exports = []; await click(button('Export Excel')); return globalThis.__exports.at(-1).sheet.ws; };
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── 1. Guests: badges ───────────────────────────────────────────────────────
test('guests: food, allergy (red), part-day and access badges from the answers, merged by guest id; a VIP\'s answers show on their VIP record; none for a guest without answers', async () => {
  await mount();
  assert.deepEqual(callsOf('event_planning_list').map(c => c.args), [{ p_event_id: 'ev-1' }], 'read once with the guest list');
  assert.deepEqual(badges(row('g-free')).map(b => [b.kind, b.text]), [['food', 'Vegetarian'], ['time', 'Day 1 from 2:00 pm']]);
  assert.deepEqual(badges(row('g-held')).map(b => [b.kind, b.text]), [
    ['allergy', `Allergy: ${LONG_ALLERGY}`],
    ['time', 'Day 2 until 3:00 pm'],
    ['access', 'Access: Wheelchair, Front seat, Needs a…'],
  ], 'No preference is no badge; the allergy is never cut (K2); a long access text is cut at 40');
  assert.deepEqual(badges(row('g-vip')).map(b => [b.kind, b.text]), [['food', 'Food: No pork']], 'the VIP record shows the answers');
  assert.equal(row('g-staff').querySelector('[data-plan-badges]'), null, 'no answers: no badges');
  // K2: every badge has its full text for screen readers and touch screens, not in title alone.
  for (const b of [...badges(row('g-held')), ...badges(row('g-free'))]) assert.ok(b.label && b.label.length >= b.text.replace('…', '').length, b.text);
  const held = badges(row('g-held'));
  assert.equal(held[0].label, `Allergy: ${LONG_ALLERGY}`);
  assert.equal(held[1].label, `Day 2 until 3:00 pm (${wdDMon(D2)})`);
  assert.equal(held[2].label, 'Access: Wheelchair access; Seat near the front (hearing or sight); Other: Needs a quiet corner near the exit door please');
  // K3: the app's own badge classes.
  assert.match(held[0].cls, /\bbadge badge-danger events-badge-allergy\b/);
  assert.match(held[1].cls, /\bbadge-accent\b/);
  assert.match(held[2].cls, /\bbadge-primary\b/);
  assert.match(badges(row('g-free'))[0].cls, /\bbadge-success\b/);
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── 2. Guests: the detail and the staff form ───────────────────────────────
test('guests: Answers opens the full answers; Edit sends the answers, the version and the note; a refusal keeps the form open with the message; a save reloads the answers', async () => {
  await mount();
  await click(document.querySelector('[data-answers="g-vip"]'));
  const m = modal();
  assert.ok(m.querySelector('.modal-header').textContent.includes('Vera Vip: answers'));
  assert.equal(m.querySelector('[data-answer="food"]').textContent, 'Other: No pork');
  assert.equal(m.querySelector('[data-answer="allergy"]').textContent, 'No', 'section 5\'s wording, as the export');
  assert.equal(m.querySelector(`[data-answer-day="${D1}"]`).textContent, 'Whole day');
  assert.equal(m.querySelector(`[data-answer-day="${D2}"]`).textContent, 'Not answered');
  assert.ok(m.querySelector('[data-answer="talks"]').textContent.includes('Managing stress at work (no longer listed)'));
  assert.equal(m.querySelector('[data-answer="access"]').textContent, 'Not answered');
  assert.equal(m.querySelector('[data-answer="heard"]').textContent, 'Other: Radio');
  assert.equal(m.querySelector('[data-answer="question"]').textContent, 'Morning or evening walks?\nI walk after dinner.');
  assert.equal(m.querySelector('[data-plan-updated]').textContent, 'Last changed by Staff One on 21 Oct 2026, 10:05 am.');
  await click(button('Close', m));

  await click(document.querySelector('[data-answers="g-free"]'));
  assert.equal(modal().querySelector('[data-plan-updated]').textContent, 'Answered on the website on 21 Oct 2026, 10:05 am.');
  await click(button('Edit answers', modal()));
  await click(choice(modal(), 'Vegan'));
  await click(choice(modal(), 'Yes'));
  await setValue(modal().querySelector('input[aria-label="Which allergies?"]'), '  Sesame   seeds ');
  await click(choice(modal(), 'Wheelchair access'));
  await setValue(modal().querySelector('textarea'), 'Line one\r\nLine two\r\n');
  await setValue(modal().querySelector('input[aria-label="Note for the log"]'), 'Told by phone on 21 Nov');
  // The server refuses: the answers changed meanwhile. The form stays, with the message.
  backend.handlers.event_planning_save = () => ({ __error: 'These answers were changed by the guest on the website on 21 Oct 2026, 11:00 am since you opened them. Close this and open them again.', __code: 'P0001' });
  const before = callsOf('event_planning_list').length;
  await click(modal().querySelector('[data-save-answers]'));
  const sent = callsOf('event_planning_save').at(-1).args;
  assert.equal(sent.p_guest_id, 'g-free');
  assert.equal(sent.p_version, 1, 'the version the form was opened on');
  assert.equal(sent.p_note, 'Told by phone on 21 Nov');
  assert.deepEqual(sent.p_answers, {
    food: 'vegan', food_other: null, allergy: 'yes', allergy_details: 'Sesame seeds',
    timing: [{ date: D1, whole_day: false, arrive: '14:00', leave: '19:00' }], talks: ['Caring for your eyes'],
    access: ['wheelchair'], access_other: null, heard_from: 'tiktok', heard_from_other: null, question: 'Line one\nLine two',
  }, 'every key, in the normal form');
  assert.ok(modal()?.querySelector('[role="alert"]')?.textContent.includes('These answers were changed by the guest on the website'));
  assert.ok(modal().querySelector('[data-save-answers]'), 'the form stays open');
  assert.equal(callsOf('event_planning_list').length, before, 'nothing read again after a refusal');
  // Saved: the window closes, the notice says so and the answers are read again.
  delete backend.handlers.event_planning_save;
  await click(modal().querySelector('[data-save-answers]'));
  assert.equal(modal(), undefined, 'closed');
  assert.ok(document.querySelector('[data-plan-notice]').textContent.includes('Fred Free\'s answers are saved.'));
  assert.equal(callsOf('event_planning_list').length, before + 1, 'the answers are read again');
  // Nothing changed.
  backend.handlers.event_planning_save = a => ({ ok: true, guest_id: a.p_guest_id, changed: false });
  await click(document.querySelector('[data-answers="g-free"]'));
  await click(button('Edit answers', modal()));
  await click(modal().querySelector('[data-save-answers]'));
  assert.ok(document.querySelector('[data-plan-notice]').textContent.includes('Nothing changed.'));
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── 3. Guests: what the staff form offers ──────────────────────────────────
test('guests: the staff form offers the guest\'s own days, the event\'s half hours (arriving 9:00 am … 6:30 pm, leaving after arriving), the titles, and a saved title no longer listed (ticked, marked)', async () => {
  await mount();
  await click(document.querySelector('[data-answers="g-vip"]'));
  await click(button('Edit answers', modal()));
  const days = [...modal().querySelectorAll('[data-plan-day]')].map(f => f.dataset.planDay);
  assert.deepEqual(days, [D1, D2], 'a VIP answers for every day');
  const d2 = modal().querySelector(`[data-plan-day="${D2}"]`);
  assert.ok(d2.querySelector('legend').textContent === `Day 2 · ${wdDMon(D2)}`);
  await click(choice(d2, 'Part of the day'));
  const arrive = d2.querySelector(`select[aria-label^="Arriving around"]`);
  const opts = s => [...s.options].map(o => o.textContent);
  assert.equal(opts(arrive)[0], '9:00 am');
  assert.equal(opts(arrive).at(-1), '6:30 pm');
  assert.equal(opts(arrive).length, 20);
  await setValue(arrive, '14:00');
  const leave = d2.querySelector(`select[aria-label^="Leaving around"]`);
  assert.equal(opts(leave)[0], '2:30 pm', 'leaving only after arriving');
  assert.equal(opts(leave).at(-1), '7:00 pm');
  const talks = modal().querySelector('[data-plan-talks]');
  const ticks = [...talks.querySelectorAll('label')].map(l => [l.textContent, l.querySelector('input').checked]);
  assert.deepEqual(ticks.slice(0, 7).map(t => t[0]), SUGGESTED, 'the titles, in order');
  assert.deepEqual(ticks.at(-1), ['Managing stress at work (no longer listed)', true], 'a saved title no longer listed: ticked, marked');
  await setValue(leave, '16:00');
  await click(modal().querySelector('[data-save-answers]'));
  const sent = callsOf('event_planning_save').at(-1).args;
  assert.deepEqual(sent.p_answers.timing, [{ date: D1, whole_day: true, arrive: null, leave: null },
    { date: D2, whole_day: false, arrive: '14:00', leave: '16:00' }]);
  assert.deepEqual(sent.p_answers.talks, ['Sleep better, stress less', 'Managing stress at work']);
  assert.equal(sent.p_version, 3);

  // With no titles saved ([]): Q4 still shows the guest's saved talks, so they can be removed (R6).
  await mount({ setup: (b, fx) => { fx.planning.talk_titles = []; fx.planning.talk_titles_saved = true; } });
  await click(document.querySelector('[data-answers="g-vip"]'));
  await click(button('Edit answers', modal()));
  assert.deepEqual([...modal().querySelectorAll('[data-plan-talks] label')].map(l => l.textContent),
    ['Sleep better, stress less (no longer listed)', 'Managing stress at work (no longer listed)']);
  await click(button('Cancel', modal()));
  await click(button('Close', modal()));
  // A guest without answers: Q4 is the titles only; nothing chosen and no titles: no Q4.
  await click(document.querySelector('[data-answers="g-staff"]') ?? document.querySelector('[data-answers="g-free"]'));
  await click(button('Edit answers', modal()));
  assert.equal(modal().querySelector('[data-plan-talks]'), null, 'no titles and nothing chosen: no talks question');
  await click(button('Cancel', modal()));
  await click(button('Close', modal()));

  // Without daily hours: only Not answered and Whole day (R5).
  await mount({ setup: (b, fx) => { fx.planning.hours = { daily_start: null, daily_end: null }; } });
  await click(document.querySelector('[data-answers="g-vip"]'));
  await click(button('Edit answers', modal()));
  assert.ok(modal().querySelector('[data-no-hours]').textContent.includes('The event has no daily hours (Edit event)'));
  const labels = [...modal().querySelector(`[data-plan-day="${D2}"]`).querySelectorAll('label')].map(l => l.textContent.trim());
  assert.deepEqual(labels, ['Not answered', 'Whole day']);
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── 4. The export ──────────────────────────────────────────────────────────
test('guests: the export adds food, allergies, each day\'s timing, talks, access, how they heard, the question and when they were changed (the site\'s sheet wording)', async () => {
  await mount();
  const ws = await exportNow();
  const answerHeaders = ['Food', 'Allergies', `Day 1 timing (${dMon(D1)})`, `Day 2 timing (${dMon(D2)})`, 'Talks', 'Access needs',
    'Heard from', 'Question for speakers', 'Answers updated'];
  assert.deepEqual(ws.header.slice(-9), answerHeaders, 'after the website columns');
  assert.equal(ws.header[ws.header.length - 10], 'Referral note');
  const r = name => ws.body.find(x => x.Name === name);
  assert.equal(r('Fred Free').Food, 'Vegetarian');
  assert.equal(r('Fred Free').Allergies, 'No');
  assert.equal(r('Fred Free')[`Day 1 timing (${dMon(D1)})`], 'From 2:00 pm');
  assert.equal(r('Fred Free')[`Day 2 timing (${dMon(D2)})`], '', 'not coming that day: blank');
  assert.equal(r('Fred Free')['Heard from'], 'TikTok');
  assert.equal(r('Fred Free')['Answers updated'], '2026-10-21 10:05 · Website');
  assert.equal(r('Hana Held').Food, 'No preference');
  assert.equal(r('Hana Held').Allergies, `Yes: ${LONG_ALLERGY}`);
  assert.equal(r('Hana Held')[`Day 2 timing (${dMon(D2)})`], 'Until 3:00 pm');
  assert.equal(r('Hana Held')['Access needs'], 'Wheelchair access; Seat near the front (hearing or sight); Other: Needs a quiet corner near the exit door please');
  assert.equal(r('Vera Vip').Food, 'Other: No pork');
  assert.equal(r('Vera Vip')[`Day 1 timing (${dMon(D1)})`], 'Whole day');
  assert.equal(r('Vera Vip')[`Day 2 timing (${dMon(D2)})`], '', 'not answered: blank');
  assert.equal(r('Vera Vip').Talks, 'Sleep better, stress less; Managing stress at work');
  assert.equal(r('Vera Vip')['Heard from'], 'Other: Radio');
  assert.equal(r('Vera Vip')['Question for speakers'], 'Morning or evening walks?\nI walk after dinner.');
  assert.equal(r('Vera Vip')['Answers updated'], '2026-10-21 10:05 · Staff One');
  assert.equal(r('Sam Staffadded').Food, '', 'no answers: blank');
});

// ── 5. No website, no answers; K14 ─────────────────────────────────────────
test('guests: an event without a website and without answers shows no Answers button and no answer columns', async () => {
  await mount({ setup: (b, fx) => {
    fx.extras = { settings: null, guests: [], holds: [], gift_choices: [], can_close_holds: true, can_undo_gifts: true };
    fx.planning.guests = [];
  } });
  assert.equal(document.querySelector('[data-answers]'), null);
  assert.ok(!(await exportNow()).header.includes('Food'));
  assert.equal(tab('Planning'), undefined, 'no Planning tab');
  // Answers given (staff recorded them) on an event without a website: the button and the columns are there.
  await mount({ setup: (b, fx) => {
    fx.extras = { settings: null, guests: [], holds: [], gift_choices: [], can_close_holds: true, can_undo_gifts: true };
    fx.planning.guests = fx.planning.guests.filter(g => g.guest_id === 'g-free');
  } });
  assert.ok(document.querySelector('[data-answers="g-free"]'));
  assert.equal(document.querySelector('[data-answers="g-staff"]'), null, 'no website: only who has answers');
  assert.ok((await exportNow()).header.includes('Food'));
});

test('guests: answers that could not be read are never left out of the export silently (K14); a database without round 7 adds none', async () => {
  await mount({ setup: b => { b.handlers.event_planning_list = () => ({ __error: 'canceling statement due to statement timeout', __code: '57014' }); } });
  assert.ok(document.querySelector('[data-planning-error]').textContent.includes('Could not load the guests\' answers'));
  assert.ok(document.querySelector('[data-plan-export-warning]').textContent.includes('Not loaded'), 'the warning above the export');
  assert.equal(document.querySelector('[data-answers]'), null, 'no form without answers read');
  const ws = await exportNow();
  assert.ok(ws.header.includes('Food') && ws.header.includes('Answers updated'), 'the answer columns are there');
  for (const r of ws.body) for (const h of ['Food', 'Allergies', 'Talks', 'Answers updated']) assert.equal(r[h], 'Not loaded', `${r.Name}: ${h}`);

  await mount({ setup: b => { b.handlers.event_planning_list = () => ({ __error: 'Could not find the function', __code: 'PGRST202' }); } });
  assert.equal(document.querySelector('[data-planning-error]'), null);
  assert.equal(document.querySelector('[data-plan-export-warning]'), null);
  assert.ok(!(await exportNow()).header.includes('Food'), 'none: as before round 7');
  assert.equal(tab('Planning'), undefined);
});

// ── A10. The detail words the answers as the export does (section 5) ─────
test('guests: the answers detail uses the export\'s words (section 5): No, Yes: …, Whole day, From 2:00 pm, Until 3:00 pm, Other: …', async () => {
  await mount();
  const ws = await exportNow();
  const r = name => ws.body.find(x => x.Name === name);
  for (const [id, name] of [['g-free', 'Fred Free'], ['g-held', 'Hana Held'], ['g-vip', 'Vera Vip']]) {
    await click(document.querySelector(`[data-answers="${id}"]`));
    const m = modal();
    const cell = sel => m.querySelector(sel).textContent;
    const orNot = v => v || 'Not answered';
    assert.equal(cell('[data-answer="food"]'), orNot(r(name).Food), `${name}: food`);
    assert.equal(cell('[data-answer="allergy"]'), orNot(r(name).Allergies), `${name}: allergies`);
    for (const [n, d] of [[1, D1], [2, D2]]) {
      const el = m.querySelector(`[data-answer-day="${d}"]`);
      if (el) assert.equal(el.textContent, orNot(r(name)[`Day ${n} timing (${dMon(d)})`]), `${name}: day ${n}`);
    }
    assert.equal(cell('[data-answer="access"]'), orNot(r(name)['Access needs']), `${name}: access`);
    assert.equal(cell('[data-answer="heard"]'), orNot(r(name)['Heard from']), `${name}: heard`);
    await click(button('Close', m));
  }
  await click(document.querySelector('[data-answers="g-free"]'));
  assert.equal(modal().querySelector(`[data-answer-day="${D1}"]`).textContent, 'From 2:00 pm');
  assert.equal(modal().querySelector('[data-answer="allergy"]').textContent, 'No');
  await click(button('Close', modal()));
  await click(document.querySelector('[data-answers="g-held"]'));
  assert.equal(modal().querySelector('[data-answer="allergy"]').textContent, `Yes: ${LONG_ALLERGY}`);
  assert.ok(modal().querySelector('[data-answer="allergy"] .events-plan-allergy'), 'an allergy stays red');
  assert.equal(modal().querySelector(`[data-answer-day="${D2}"]`).textContent, 'Until 3:00 pm');
  await click(button('Close', modal()));
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── A11. At the door every badge is in full ─────────────────────────────────
test('check-in: a 120-character access "other" and a 60-character food "other" show in full on the check-in row (and wrap); the Guests table still cuts them at 40', async () => {
  const ACCESS_OTHER = 'A carer comes with me and I need a chair with arm rests near the aisle, close to a quiet exit and the toilets please, ok';
  const FOOD_OTHER = 'No pork, no lard and nothing cooked in wine or alcohol, thx!';
  assert.equal(ACCESS_OTHER.length, 120);
  assert.equal(FOOD_OTHER.length, 60);
  await mount({ role: 'staff', setup: (b, fx) => {
    const held = fx.planning.guests.find(g => g.guest_id === 'g-held');
    held.answers = { ...held.answers, food: 'other', food_other: FOOD_OTHER, access: [], access_other: ACCESS_OTHER };
  } });
  const table = badges(row('g-held'));
  assert.equal(table.find(b => b.kind === 'access').text.length, 40, 'the Guests table keeps its 40-character cut');
  assert.ok(table.find(b => b.kind === 'access').text.endsWith('…'));
  await click(tab('Check-in'));
  await click(buttons().find(b => b.classList.contains('events-checkin-day') && b.textContent.startsWith(wdDMon(D2))));
  const door = badges(checkRow('g-held'));
  assert.deepEqual(door.map(b => [b.kind, b.text]), [
    ['allergy', `Allergy: ${LONG_ALLERGY}`], ['food', `Food: ${FOOD_OTHER}`], ['access', `Access: Other: ${ACCESS_OTHER}`],
  ]);
  const css = readFileSync(join(REPO, 'src/components/events/events.css'), 'utf8');
  assert.ok(css.includes('.events-checkin-row .events-plan-badges .badge { white-space: normal; overflow-wrap: anywhere; }'), 'door badges wrap');
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── A talk title changed only in its capitals ──────────────────────────────
test('guests: a saved talk whose title changed only in its capitals shows once, ticked, as the listed title (not "no longer listed")', async () => {
  const RECASED = SUGGESTED.map(t => (t === 'Sleep better, stress less' ? 'Sleep Better, Stress Less' : t));
  await mount({ setup: (b, fx) => { fx.planning.talk_titles = [...RECASED]; fx.planning.talk_titles_saved = true; } });
  await click(document.querySelector('[data-answers="g-vip"]'));
  assert.ok(!modal().querySelector('[data-answer="talks"]').textContent.includes('Sleep better, stress less (no longer listed)'));
  assert.ok(modal().querySelector('[data-answer="talks"]').textContent.includes('Sleep Better, Stress Less'));
  await click(button('Edit answers', modal()));
  const ticks = [...modal().querySelectorAll('[data-plan-talks] label')].map(l => [l.textContent, l.querySelector('input').checked]);
  assert.deepEqual(ticks.filter(t => t[0].toLowerCase().startsWith('sleep better')), [['Sleep Better, Stress Less', true]], 'one checkbox, ticked');
  await click(modal().querySelector('[data-save-answers]'));
  assert.deepEqual(callsOf('event_planning_save').at(-1).args.p_answers.talks, ['Sleep Better, Stress Less', 'Managing stress at work']);
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── Website tab: one card's Save keeps the other card's unsaved typing ──────
test('website tab: saving the venue keeps talk title edits not saved yet, and saving the titles keeps a venue not saved yet', async () => {
  await mount({ role: 'manager', setup: b => { b.handlers.event_web_set_venue = a => ({ ok: true, venue: a.p_venue }); } });
  await click(tab('Website'));
  const card = () => document.querySelector('[data-section="talks"]');
  const inputs = () => [...card().querySelectorAll('[data-talk-row] input')];
  const venue = () => document.querySelector('input[aria-label="Venue"]');
  await setValue(inputs()[1], 'Healthy joints and a strong back');
  await setValue(venue(), 'Hall 2, Example Centre');
  await click(button('Save venue'));
  assert.deepEqual(callsOf('event_web_set_venue').at(-1).args, { p_event_id: 'ev-1', p_venue: 'Hall 2, Example Centre' });
  assert.equal(inputs()[1].value, 'Healthy joints and a strong back', 'the talk title being edited is kept');
  await setValue(venue(), 'Hall 3, Example Centre');
  await click(button('Save talk titles', card()));
  assert.deepEqual(callsOf('event_web_set_talks').at(-1).args.p_titles[1], 'Healthy joints and a strong back');
  assert.equal(venue().value, 'Hall 3, Example Centre', 'the venue being typed is kept');
  // Refresh reads everything again.
  await click(button('Refresh', document.querySelector('[data-section="settings"]')));
  assert.equal(venue().value, '');
  assert.deepEqual(inputs().map(i => i.value), SUGGESTED);
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── 6, 7. Check-in ─────────────────────────────────────────────────────────
test('check-in: allergy, food and access badges on the row (allergy first, never cut); no timing badge', async () => {
  await mount({ role: 'staff' });
  await click(tab('Check-in'));
  // Day 2 is Hana's.
  await click(buttons().find(b => b.classList.contains('events-checkin-day') && b.textContent.startsWith(wdDMon(D2))));
  assert.deepEqual(badges(checkRow('g-held')).map(b => [b.kind, b.text]), [
    ['allergy', `Allergy: ${LONG_ALLERGY}`],
    ['access', 'Access: Wheelchair access; Seat near the front (hearing or sight); Other: Needs a quiet corner near the exit door please'],
  ], 'allergy first; every badge in full at the door (a phone has no hover); no timing; No preference shows nothing');
  assert.equal(badges(checkRow('g-held'))[1].label, 'Access: Wheelchair access; Seat near the front (hearing or sight); Other: Needs a quiet corner near the exit door please');
  await click(buttons().find(b => b.classList.contains('events-checkin-day') && b.textContent.startsWith(wdDMon(D1))));
  assert.deepEqual(badges(checkRow('g-free')).map(b => [b.kind, b.text]), [['food', 'Vegetarian']], 'no "Day 1 from 2:00 pm" at the door');
  assert.deepEqual(badges(checkRow('g-vip')).map(b => [b.kind, b.text]), [['food', 'Food: No pork']]);
  assert.equal(checkRow('g-staff').querySelector('[data-plan-badges]'), null);
});

test('check-in: a failed read of the answers keeps the badges and says so; a database without round 7 shows none', async () => {
  let fail = null;
  await mount({ role: 'staff', setup: (b, fx) => { b.handlers.event_planning_list = () => fail ?? fx.planning; } });
  fail = { __error: 'canceling statement due to statement timeout', __code: '57014' };
  await click(button('Refresh'));
  assert.ok(document.querySelector('[data-planning-error]').textContent.includes('showing what was loaded before'));
  assert.ok(document.querySelector('[data-planning-error]').textContent.includes('statement timeout'));
  await click(tab('Check-in'));
  assert.ok(badges(checkRow('g-free')).length > 0, 'the badges stay at the door');
  assert.ok(document.querySelector('[data-planning-error]'), 'and the page says so');
  assert.equal(document.querySelector('[data-plan-export-warning]'), null, 'answers were read before: the export keeps them');
  fail = { __error: 'Could not find the function', __code: 'PGRST202' };
  await click(tab('Guests'));
  await click(button('Refresh'));
  await click(tab('Check-in'));
  assert.equal(document.querySelector('[data-planning-error]'), null);
  assert.equal(document.querySelector('[data-plan-badges]'), null, 'a database without round 7: none');
});

test('check-in: the answers are read at most every 2 minutes while Check-in is open; entering the tab and a save read again (K13)', async () => {
  const realSet = dom.window.setInterval;
  const timers = [];
  dom.window.setInterval = (fn, ms) => { const t = { fn, ms }; timers.push(t); return realSet.call(dom.window, () => {}, 1e9); };
  const RealDate = Date;
  let shift = 0;
  class ShiftedDate extends RealDate {
    constructor(...a) { if (a.length) super(...a); else super(RealDate.now() + shift); }
    static now() { return RealDate.now() + shift; }
  }
  globalThis.Date = ShiftedDate;
  try {
    await mount({ role: 'staff' });
    const reads = () => callsOf('event_planning_list').length;
    const lists = () => callsOf('event_guest_list').length;
    assert.equal(reads(), 1, 'read with the guest list');
    await click(tab('Check-in'));
    assert.equal(reads(), 2, 'entering Check-in reads them');
    const refresh = timers.filter(t => t.ms === 25_000).at(-1);
    assert.ok(refresh, 'the 25 s door refresh');
    const listsBefore = lists();
    for (let i = 1; i <= 3; i++) {
      shift = i * 25_000;
      await act(async () => { refresh.fn(); });
      await tick();
    }
    assert.equal(lists(), listsBefore + 3, 'the guest list is read every 25 s');
    assert.equal(reads(), 2, 'three refreshes: no read of the answers');
    shift = 125_000;
    await act(async () => { refresh.fn(); });
    await tick();
    assert.equal(reads(), 3, '2 minutes on: read with the guest list');
    // Away from Check-in, every guest-list read reads them.
    await click(tab('Guests'));
    await click(button('Refresh'));
    assert.equal(reads(), 4);
  } finally {
    globalThis.Date = RealDate;
    dom.window.setInterval = realSet;
  }
});

// ── 8, 9. Planning tab ─────────────────────────────────────────────────────
test('planning: per day food counts, allergies (VIP marked), late and early by time, access; the VIP block; talks with counts and "no longer listed"; how they heard; the questions', async () => {
  await mount();
  await click(tab('Planning'));
  assert.deepEqual(callsOf('event_planning_summary').map(c => c.args), [{ p_event_id: 'ev-1' }]);
  assert.equal(document.querySelector('[data-plan-answered]').textContent, 'Answers from 3 of 4 registered guests');
  const day1 = document.querySelector(`[data-planning-day="${D1}"]`);
  assert.ok(day1.textContent.includes(`Day 1 · ${wdDMon(D1)}`));
  assert.ok(day1.textContent.includes('3 coming · 2 answered'));
  assert.deepEqual([...day1.querySelectorAll('[data-food]')].map(c => c.textContent),
    ['Vegetarian 1', 'Vegan 0', 'Halal 0', 'No beef 0', 'Other 1', 'No preference 0', 'Not answered 1']);
  assert.ok(day1.querySelector('[data-plan-food-other]').textContent.includes('Other food: Vera Vip — No pork'));
  assert.ok(day1.querySelector('[data-plan-food-other] [aria-label="VIP"]'), 'a VIP is marked');
  assert.ok(day1.querySelector('[data-plan-allergies]').textContent.includes('Allergies (0)No allergies given.'));
  assert.ok(day1.querySelector('[data-plan-late]').textContent.includes('Arriving late (1)2:00 pm (1)2:00 pm · Fred Free'));
  const day2 = document.querySelector(`[data-planning-day="${D2}"]`);
  assert.ok(day2.querySelector('[data-plan-allergies]').textContent.includes(`Hana Held — ${LONG_ALLERGY}`));
  assert.ok(day2.querySelector('[data-plan-early]').textContent.includes('Leaving early (1)3:00 pm (1)3:00 pm · Hana Held'));
  assert.ok(day2.querySelector('[data-plan-access]').textContent.includes('Hana Held — Wheelchair access; Seat near the front (hearing or sight); Other: Needs a quiet corner'));
  const vip = document.querySelector('[data-planning-vip]');
  assert.ok(vip.textContent.includes('VIP guests (dinner with the founder)'));
  assert.ok(vip.textContent.includes('1 VIP · 1 answered'));
  assert.equal(vip.querySelector('[data-plan-vip-waiting]').textContent, '3 more VIP payments wait to be confirmed (not counted here).', 'K30');
  const talks = document.querySelector('[data-planning-talks]');
  assert.ok(talks.querySelector('[data-talk="Managing stress at work"]').textContent.includes('(no longer listed)'));
  assert.ok(talks.querySelector('[data-talk="Caring for your eyes"]').textContent.endsWith('1'));
  assert.equal(talks.querySelectorAll('[data-talk]').length, 8, 'every listed title (0 too) and the one no longer listed');
  const heard = document.querySelector('[data-planning-heard]');
  assert.deepEqual([...heard.querySelectorAll('[data-heard]')].map(c => c.textContent), ['TikTok 1', 'Other 1', 'Not answered 2']);
  assert.ok(heard.textContent.includes('Other: Vera Vip — Radio'));
  const q = document.querySelector('[data-planning-questions]');
  assert.ok(q.querySelector('summary').textContent.includes('Questions for the speakers (1)'));
  assert.ok(q.textContent.includes('Vera Vip: Morning or evening walks?\nI walk after dinner.'));
  // K30: none waiting: no line.
  await mount({ setup: (b, fx) => { fx.summary.vip.waiting = 0; } });
  await click(tab('Planning'));
  assert.equal(document.querySelector('[data-plan-vip-waiting]'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('planning: the tab shows for an event with a website or with answers, not for others; Refresh reads again', async () => {
  await mount({ role: 'staff' });
  assert.ok(tab('Planning'), 'with a website: everyone who sees the guests');
  await click(tab('Planning'));
  await click(button('Refresh', document.querySelector('[data-planning-tab]')));
  assert.equal(callsOf('event_planning_summary').length, 2);
  await mount({ setup: (b, fx) => { fx.extras = { ...fx.extras, settings: null, guests: [], holds: [] }; fx.planning.guests = []; } });
  assert.equal(tab('Planning'), undefined, 'no website, no answers: no tab');
  await mount({ setup: (b, fx) => { fx.extras = { ...fx.extras, settings: null, guests: [], holds: [] }; } });
  assert.ok(tab('Planning'), 'no website, with answers: the tab');
  await mount({ setup: (b, fx) => { fx.summary.answered = 0; } });
  await click(tab('Planning'));
  assert.ok(document.querySelector('[data-plan-none]').textContent.includes('No answers yet.'));
});

// ── 10. Website tab: talk titles ───────────────────────────────────────────
test('website tab: Talk titles pre-filled with the suggested list until saved; a Manager reorders, removes, adds (at most 20, 120 characters) and saves; Use the suggested list asks first and sends null; with no titles it asks first; staff cannot', async () => {
  await mount({ role: 'manager' });
  await click(tab('Website'));
  const card = () => document.querySelector('[data-section="talks"]');
  assert.ok(card().querySelector('[data-talks-state="suggested"]').textContent.includes('Suggested list (not saved yet)'));
  assert.ok(document.querySelector('[data-readiness]').textContent.includes('The talk titles are the suggested list'), 'the readiness warning');
  const inputs = () => [...card().querySelectorAll('[data-talk-row] input')];
  assert.deepEqual(inputs().map(i => i.value), SUGGESTED);
  assert.ok(inputs().every(i => i.maxLength === 120));
  assert.ok(inputs().every(i => !i.disabled));
  await click(card().querySelector('[aria-label="Move talk title 2 up"]'));
  assert.deepEqual(inputs().slice(0, 2).map(i => i.value), [SUGGESTED[1], SUGGESTED[0]]);
  await click(button('Remove', card().querySelectorAll('[data-talk-row]')[6]));
  await click(buttons(card()).find(b => b.textContent.trim() === 'Add a title'));
  await setValue(inputs().at(-1), '  Q&A   with the founder ');
  await click(button('Save talk titles', card()));
  assert.deepEqual(callsOf('event_web_set_talks').at(-1).args, { p_event_id: 'ev-1',
    p_titles: [SUGGESTED[1], SUGGESTED[0], ...SUGGESTED.slice(2, 6), 'Q&A with the founder'] });
  assert.ok(text().includes('The talk titles are saved: the website shows them within a minute.'));

  // Saved: back to the suggested list asks first, then sends null.
  backend.handlers.event_web_settings_get = () => ({ ...makeFixture().settings, can_manage: false, can_clear_tests: true, can_set_venue: true,
    can_set_talks: true, talks: { titles: ['Talk A', 'Talk B'], saved: true, suggested: [...SUGGESTED] } });
  await click(button('Refresh', document.querySelector('[data-section="settings"]')));
  assert.ok(card().querySelector('[data-talks-state="saved"]'));
  const sends = callsOf('event_web_set_talks').length;
  await click(button('Use the suggested list', card()));
  assert.equal(callsOf('event_web_set_talks').length, sends, 'asks first');
  assert.equal(modal().querySelector('[data-talks-confirm]').textContent, 'Go back to the suggested list? Answers already given keep the titles people chose.');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_web_set_talks').at(-1).args, { p_event_id: 'ev-1', p_titles: null });

  // No titles: asks first, then sends [].
  for (const b of buttons(card()).filter(x => x.textContent.trim() === 'Remove')) await click(b);
  assert.equal(inputs().length, 0);
  await click(button('Save talk titles', card()));
  assert.equal(modal().querySelector('[data-talks-confirm]').textContent, 'Save with no titles? The website then does not ask about talks.');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_web_set_talks').at(-1).args, { p_event_id: 'ev-1', p_titles: [] });

  // At most 20.
  backend.handlers.event_web_settings_get = () => ({ ...makeFixture().settings, can_manage: false, can_clear_tests: true, can_set_venue: true,
    can_set_talks: true, talks: { titles: Array.from({ length: 20 }, (_, i) => `Talk ${i + 1}`), saved: true, suggested: [...SUGGESTED] } });
  await click(button('Refresh', document.querySelector('[data-section="settings"]')));
  assert.ok(buttons(card()).find(b => b.textContent.trim() === 'Add a title').disabled);

  // Who may not: the server says so (can_set_talks false); staff do not see the tab at all.
  backend.handlers.event_web_settings_get = () => ({ ...makeFixture().settings, can_manage: false, can_set_venue: true, can_set_talks: false });
  await click(button('Refresh', document.querySelector('[data-section="settings"]')));
  assert.ok(inputs().every(i => i.disabled));
  assert.ok(!button('Save talk titles', card()));
  assert.ok(card().querySelector('[data-talks-who]').textContent.includes('Owners, Admins and Managers set the talk titles.'));
  await mount({ role: 'staff' });
  assert.equal(tab('Website'), undefined);
  // The test-mode copy (R13).
  await mount({ role: 'owner' });
  await click(tab('Website'));
  assert.ok(document.querySelector('[data-section="test"]').textContent.includes('A test key\'s planning answers are checked and never kept.'));
  assert.ok(document.querySelector('[data-section="requests"]').textContent.includes('planning_answers'));
  assert.deepEqual(globalThis.__renderErrors, []);
});

// ── R6-4: To match, someone under the affiliate's own name ─────────────────
test('to match: someone held under the affiliate\'s own name warns before a new customer is made (R6-4); other holds do not', async () => {
  await mount({ role: 'staff', setup: (b, fx) => {
    Object.assign(fx.extras.holds[0], { reason: 'affiliate_name', affiliate_name: 'Ann Affiliate' });
  } });
  const warning = 'This looks like Ann Affiliate herself. Link her own record unless you are sure it is a different person; a new customer earns her upline nothing.';
  assert.equal(document.querySelector('[data-hold="p-3"] [data-affiliate-warning]').textContent, warning);
  await click(document.querySelector('[data-create="p-3"]'));
  assert.equal(modal().querySelector('[data-affiliate-warning]').textContent, warning, 'and in the New customer window');
  assert.ok(!modal().querySelector('[data-confirm]').disabled, 'staff may still make the customer (no Owner or Manager needed)');
  await click(modal().querySelector('[data-confirm]'));
  assert.equal(callsOf('event_registration_create_customer').length, 1);
  // Without the server naming her: the candidate with her name.
  await mount({ role: 'staff', setup: (b, fx) => {
    Object.assign(fx.extras.holds[0], { reason: 'affiliate_name' });
    fx.extras.holds[0].candidates = [{ customer_id: 'c-ann', full_name: 'Ann Affiliate', phone: '+61491570737', email: null,
      created_at: '2026-01-01T00:00:00Z', phone_matches: false, email_matches: false, name_matches: true }];
  } });
  assert.ok(document.querySelector('[data-affiliate-warning]').textContent.startsWith('This looks like Ann Affiliate herself.'));
  await mount({ role: 'staff' });
  assert.equal(document.querySelector('[data-affiliate-warning]'), null, 'a phone_in_use hold has no such warning');
  await click(document.querySelector('[data-create="p-3"]'));
  assert.equal(modal().querySelector('[data-affiliate-warning]'), null);
});

// ── Round 8 (the owner, 21 Oct 2026: P1): two VIP payments for one customer ──
test('to match (round 8): a candidate already a guest shows their days and VIP; a held person who paid gets the two-VIP warning before linking; linking stays allowed', async () => {
  const warning = 'Linking gives Holly Holder two VIP payments for this event. Refund one after linking.';
  await mount({ role: 'staff', setup: (b, fx) => {
    Object.assign(fx.extras.holds[0], { vip_waiting: true, vip_payment: true });
    fx.extras.holds[0].candidates[0].guest = { days: [D1, D2], vips: [{ state: 'paid', invoice_no: 'INV-TEST-0009' }] };
    fx.extras.holds[0].candidates.push({ customer_id: 'c-8', full_name: 'Hal Nonguest', phone: '+61491573770', email: null,
      created_at: '2026-02-01T00:00:00Z', phone_matches: true, email_matches: false, name_matches: false, guest: null });
    b.handlers.event_registration_attach = a => ({ ok: true, customer_id: a.p_customer_id, vip_orders: [] });
  } });
  const hold = document.querySelector('[data-hold="p-3"]');
  const rows = [...hold.querySelectorAll('tbody tr')];
  assert.equal(rows.length, 2);
  assert.equal(rows[0].querySelector('[data-candidate-guest]').textContent,
    `Already a guest: ${wdDMon(D1)} & ${wdDMon(D2)} ${D1.slice(0, 4)} · VIP paid (INV-TEST-0009)`.replace(` & ${wdDMon(D2)} ${D1.slice(0, 4)}`,
      D1.slice(0, 4) === D2.slice(0, 4) ? ` & ${wdDMon(D2)} ${D1.slice(0, 4)}` : ` & ${wdDMon(D2)}`));
  assert.equal(rows[0].querySelector('[data-double-vip-note]').textContent, warning);
  assert.equal(rows[1].querySelector('[data-candidate-guest]'), null, 'a candidate who is not a guest says nothing');
  assert.equal(rows[1].querySelector('[data-double-vip-note]'), null);
  await click(rows[0].querySelector('[data-attach="c-9"]'));
  assert.equal(modal().querySelector('[data-double-vip-warning]').textContent, warning, 'the Link window warns first');
  assert.ok(modal().querySelector('[data-candidate-guest]').textContent.includes('VIP paid (INV-TEST-0009)'));
  await setValue(modal().querySelector('textarea'), 'Asked at the door, same birthday');
  assert.ok(!modal().querySelector('[data-confirm]').disabled, 'linking stays allowed');
  await click(modal().querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_registration_attach').map(c => c.args),
    [{ p_person_id: 'p-3', p_customer_id: 'c-9', p_note: 'Asked at the door, same birthday' }]);
  // A VIP payment waiting (a transfer) on the candidate's side warns the same; no payment of the held person's own
  // (a checkout opened and left unpaid: vip_waiting only) does not.
  await mount({ role: 'staff', setup: (b, fx) => {
    Object.assign(fx.extras.holds[0], { vip_waiting: true, vip_payment: false });
    fx.extras.holds[0].candidates[0].guest = { days: [D2], vips: [{ state: 'waiting', invoice_no: null }] };
  } });
  assert.ok(document.querySelector('[data-hold="p-3"] [data-candidate-guest]').textContent.endsWith(' · VIP payment waiting'));
  assert.equal(document.querySelector('[data-double-vip-note]'), null);
  await click(document.querySelector('[data-attach="c-9"]'));
  assert.equal(modal().querySelector('[data-double-vip-warning]'), null);
  // A guest without a VIP: days only, no warning even when the held person paid.
  await mount({ role: 'staff', setup: (b, fx) => {
    Object.assign(fx.extras.holds[0], { vip_waiting: true, vip_payment: true });
    fx.extras.holds[0].candidates[0].guest = { days: [D2], vips: [] };
  } });
  assert.equal(document.querySelector('[data-hold="p-3"] [data-candidate-guest]').textContent, `Already a guest: ${wdDMon(D2)} ${D2.slice(0, 4)}`);
  assert.equal(document.querySelector('[data-double-vip-note]'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('to match (the review of round 8): "Find another customer…" reads the picked customer from the guest list: already a guest with a VIP gets the two-VIP warning; a guest without one, days only; someone else, nothing', async () => {
  const pick = async (name) => {
    await click(document.querySelector('[data-other="p-3"]'));
    const field = modal().querySelector('.form-group');
    await click(field.querySelector('button'));
    await setValue(field.querySelector('input'), name.split(' ')[0]);
    await act(async () => { await new Promise(r => setTimeout(r, 300)); });
    await tick();
    await click([...field.querySelectorAll('div')].find(d => d.firstChild?.textContent === name));
    return modal();
  };
  const customers = [{ id: 'c-1', full_name: 'Vera Vip', phone: '+61491570737', email: null, notes: null },
    { id: 'c-2', full_name: 'Fred Free', phone: '+61491572983', email: null, notes: null },
    { id: 'c-7', full_name: 'Nora Nonguest', phone: '+61491570006', email: null, notes: null }];
  const setup = vipPayment => (b, fx) => {
    Object.assign(fx.extras.holds[0], { vip_waiting: vipPayment, vip_payment: vipPayment });
    fx.tables = { customers };
    b.handlers.event_registration_attach = a => ({ ok: true, customer_id: a.p_customer_id, vip_orders: [] });
  };
  await mount({ role: 'staff', setup: setup(true) });
  let m = await pick('Vera Vip');
  assert.equal(m.querySelector('[data-double-vip-warning]').textContent,
    'Linking gives Vera Vip two VIP payments for this event. Refund one after linking.', 'warned before linking, as for a listed candidate');
  const note = m.querySelector('[data-candidate-guest]').textContent;
  assert.ok(note.startsWith('Already a guest: ') && note.endsWith(' · VIP paid.'), note);
  await setValue(m.querySelector('textarea'), 'Asked at the door, same birthday');
  assert.ok(!m.querySelector('[data-confirm]').disabled, 'linking stays allowed');
  await click(m.querySelector('[data-confirm]'));
  assert.deepEqual(callsOf('event_registration_attach').map(c => c.args),
    [{ p_person_id: 'p-3', p_customer_id: 'c-1', p_note: 'Asked at the door, same birthday' }]);
  // A guest without a VIP: days only, no warning.
  await mount({ role: 'staff', setup: setup(true) });
  m = await pick('Fred Free');
  assert.equal(m.querySelector('[data-double-vip-warning]'), null);
  assert.equal(m.querySelector('[data-candidate-guest]').textContent, `Already a guest: ${wdDMon(D1)} ${D1.slice(0, 4)}.`);
  // Not a guest of this event: nothing.
  await mount({ role: 'staff', setup: setup(true) });
  m = await pick('Nora Nonguest');
  assert.equal(m.querySelector('[data-double-vip-warning]'), null);
  assert.equal(m.querySelector('[data-candidate-guest]'), null);
  // The held person has no VIP payment of their own: no warning, the note still shows.
  await mount({ role: 'staff', setup: setup(false) });
  m = await pick('Vera Vip');
  assert.equal(m.querySelector('[data-double-vip-warning]'), null);
  assert.ok(m.querySelector('[data-candidate-guest]').textContent.endsWith(' · VIP paid.'));
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('guests and planning (round 8): a customer holding two VIP payments is flagged on their rows and named in the VIP block, counted once', async () => {
  const fixture = makeFixture();
  fixture.extras.guests.find(x => x.guest_id === 'g-vip').vip_double = true;
  fixture.extras.vip_doubles = [{ customer_id: 'c-1', full_name: 'Vera Vip',
    vips: [{ state: 'paid', invoice_no: 'INV-TEST-0001' }, { state: 'waiting', invoice_no: null }] }];
  // A guest row the website does not know of, on the same customer: flagged by the customer.
  fixture.guests.find(g => g.guest_id === 'g-staff').customer_id = 'c-1';
  // Their cancelled (parked) free record is not flagged (the review of round 8), even when the server's row says so.
  fixture.guests.find(g => g.guest_id === 'g-vip-free').customer_id = 'c-1';
  fixture.extras.guests.find(x => x.guest_id === 'g-vip-free').vip_double = true;
  fixture.summary.vip.doubles = [{ customer_id: 'c-1', name: 'Vera Vip',
    vips: [{ state: 'paid', invoice_no: 'INV-TEST-0001' }, { state: 'waiting', invoice_no: null }] }];
  await mount({ role: 'staff', fixture });
  const flag = id => row(id)?.querySelector('[data-vip-double]')?.textContent ?? null;
  assert.equal(flag('g-vip'), 'Two VIP payments: refund one');
  assert.equal(flag('g-staff'), 'Two VIP payments: refund one');
  assert.equal(flag('g-free'), null);
  assert.equal(flag('g-held'), null);
  await setValue(document.querySelector('select[aria-label="Status"]'), 'all');
  assert.ok(row('g-vip-free'), 'the cancelled row is listed');
  assert.equal(flag('g-vip-free'), null, 'a cancelled row is not flagged');
  assert.equal(flag('g-vip'), 'Two VIP payments: refund one');
  await click(tab('Planning'));
  const block = document.querySelector('[data-planning-vip] [data-plan-vip-doubles]');
  assert.ok(block.textContent.startsWith('Two VIP payments: refund one'));
  assert.equal(block.querySelector('[data-plan-vip-double="c-1"]').textContent,
    'Vera Vip: VIP paid (INV-TEST-0001) + VIP payment waiting (counted once)');
  assert.ok(document.querySelector('[data-planning-vip]').textContent.includes('1 VIP · 1 answered'));
  // Nobody holding two: no flag, no block (and an older 436 without the fields reads as none).
  await mount({ role: 'staff' });
  assert.equal(document.querySelector('[data-vip-double]'), null);
  await click(tab('Planning'));
  assert.equal(document.querySelector('[data-plan-vip-doubles]'), null);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('model (round 8): the VIP payment texts and the warning', () => {
  assert.equal(model.vipHeldText([{ state: 'paid', invoice_no: 'INV-1' }, { state: 'waiting', invoice_no: null }]), 'VIP paid (INV-1) + VIP payment waiting');
  assert.equal(model.vipHeldText([{ state: 'paid', invoice_no: null }]), 'VIP paid', 'no invoice number without the store\'s access');
  const hold = { vip_payment: true };
  const cand = (vips) => ({ full_name: 'Holly Holder', guest: vips ? { days: [], vips } : null });
  assert.equal(model.doubleVipWarning(hold, cand([{ state: 'waiting', invoice_no: null }])),
    'Linking gives Holly Holder two VIP payments for this event. Refund one after linking.');
  assert.equal(model.doubleVipWarning(hold, cand([])), null);
  assert.equal(model.doubleVipWarning(hold, cand(null)), null);
  assert.equal(model.doubleVipWarning({ vip_payment: false }, cand([{ state: 'paid', invoice_no: null }])), null);
  assert.equal(model.doubleVipWarning(hold, null), null, 'nobody picked yet');
  // "Find another customer…" (the review of round 8): the picked customer read from the guest list.
  const day = d => ({ day: d, attended_at: null, check_in_code: null, checked_in_by_name: null });
  const gl = [
    { guest_id: 'g1', name: 'Pia Picked', customer_id: 'c-p', customer_name: 'Pia Picked', status: 'registered', days: [day(D2)] },
    { guest_id: 'g2', name: 'Pia Picked', customer_id: 'c-p', customer_name: 'Pia Picked', status: 'registered', days: [day(D1), day(D2)] },
    { guest_id: 'g3', name: 'Pia Picked', customer_id: 'c-p', customer_name: 'Pia Picked', status: 'cancelled', days: [day(D1)] },
    { guest_id: 'g4', name: 'Tom Testkey', customer_id: 'c-t', customer_name: 'Tom Testkey', status: 'registered', days: [day(D1)] },
  ];
  const xs = { guests: { g1: { vip_guest: false, vip: 'none', vip_waiting: 'paynow', is_test: false, closed: false },
    g2: { vip_guest: true, vip: 'paid', vip_invoice_no: 'INV-TEST-0042', vip_waiting: null, is_test: false, closed: false },
    g3: { vip_guest: true, vip: 'paid', vip_invoice_no: 'INV-TEST-0041', vip_waiting: null, is_test: false, closed: false },
    g4: { vip_guest: false, vip: 'none', vip_waiting: 'paynow', is_test: true, closed: false } }, vip_doubles: [] };
  const p = model.pickedCustomerCandidate('c-p', gl, xs);
  assert.deepEqual([p.full_name, p.guest.days, p.guest.vips], ['Pia Picked', [D1, D2].sort(),
    [{ state: 'waiting', invoice_no: null }, { state: 'paid', invoice_no: 'INV-TEST-0042' }]], 'registered rows only; days joined');
  assert.equal(model.doubleVipWarning(hold, p), 'Linking gives Pia Picked two VIP payments for this event. Refund one after linking.');
  assert.deepEqual(model.pickedCustomerCandidate('c-t', gl, xs).guest.vips, [], 'a test key\'s payment is none');
  assert.equal(model.pickedCustomerCandidate('c-x', gl, xs), null, 'not a guest');
  assert.equal(model.pickedCustomerCandidate('', gl, xs), null, 'nobody picked');
  const dv = [{ customer_id: 'c-p', full_name: 'Pia Picked', vips: [{ state: 'paid', invoice_no: 'INV-1' }, { state: 'paid', invoice_no: 'INV-2' }] }];
  assert.deepEqual(model.pickedCustomerCandidate('c-p', gl, { ...xs, vip_doubles: dv }).guest.vips, dv[0].vips, 'two already: the server\'s list');
  assert.equal(model.isVipDouble({ guests: { g3: { vip_double: true } }, vip_doubles: dv }, gl[2]), false, 'a cancelled row is not flagged');
  assert.equal(model.isVipDouble({ guests: {}, vip_doubles: dv }, gl[0]), true);
  const x = model.normalizeWebExtras({ settings: { store_id: 's', mode: 'live', code: 'X' }, guests: [], holds: [
    { person_id: 'p', registration_id: 'R', vip_waiting: true, candidates: [{ customer_id: 'c', full_name: 'C' }] }] });
  assert.equal(x.holds[0].vip_payment, true, 'an older 436 without vip_payment: vip_waiting stands in');
  assert.equal(x.holds[0].candidates[0].guest, null);
  assert.deepEqual(x.vip_doubles, []);
  assert.deepEqual(model.normalizePlanningSummary({ vip: { count: 1 } }).vip.doubles, []);
});

// ── 11, 12. model.ts against the contract ──────────────────────────────────
test('model: the food, access and how-heard labels and the limits are the contract\'s', () => {
  assert.deepEqual([...model.FOOD_CHOICES], [...contract.FOOD_CHOICES]);
  assert.deepEqual(model.FOOD_LABELS, contract.FOOD_LABELS);
  assert.deepEqual([...model.ACCESS_CHOICES], [...contract.ACCESS_CHOICES]);
  assert.deepEqual(model.ACCESS_LABELS, contract.ACCESS_LABELS);
  assert.deepEqual([...model.HEARD_FROM_CHOICES], [...contract.HEARD_FROM_CHOICES]);
  assert.deepEqual(model.HEARD_FROM_LABELS, contract.HEARD_FROM_LABELS);
  const { note, ...limits } = model.PLANNING_LIMITS;
  assert.deepEqual(limits, { ...contract.PLANNING_LIMITS });
  assert.equal(note, 200, 'the staff note (event_planning_save)');
  assert.equal(model.TIME_STEP_MINUTES, contract.TIME_STEP_MINUTES);
  assert.deepEqual(SUGGESTED, [...contract.SUGGESTED_TALK_TITLES], 'this file\'s suggested list is the contract\'s');
});

test('model: timing text and time options', () => {
  const vectors = [['09:00', '19:00'], ['09:00', '18:45'], ['10:15', '11:00'], ['09:00', '09:20'], [null, null], ['09:00', null],
    ['08:30', '17:30'], ['00:00', '23:30'], ['9:00', '19:00']];
  for (const [s, e] of vectors) assert.deepEqual(model.timeOptions(s, e), contract.planningTimeOptions(s, e), `${s}-${e}`);
  const nine = model.timeOptions('09:00', '19:00');
  assert.equal(nine.arrive.length, 20);
  assert.equal(nine.leave.length, 20);
  assert.deepEqual([nine.arrive[0], nine.arrive.at(-1), nine.leave[0], nine.leave.at(-1)], ['09:00', '18:30', '09:30', '19:00']);
  assert.equal(model.fmtClock('12:00'), '12:00 pm');
  assert.equal(model.fmtClock('09:30'), '9:30 am');
  assert.equal(model.fmtClock('00:30'), '12:30 am');
  assert.equal(model.fmtClock('14:00'), '2:00 pm');
  const part = (arrive, leave) => ({ date: D1, whole_day: false, arrive, leave });
  assert.equal(model.timingText({ date: D1, whole_day: true, arrive: null, leave: null }, '09:00', '19:00'), 'Whole day');
  assert.equal(model.timingText(part('14:00', '19:00'), '09:00', '19:00'), 'From 2:00 pm');
  assert.equal(model.timingText(part('09:00', '15:00'), '09:00', '19:00'), 'Until 3:00 pm');
  assert.equal(model.timingText(part('14:00', '16:00'), '09:00', '19:00'), '2:00 pm – 4:00 pm');
  assert.equal(model.timingText(part('14:00', '19:00'), null, null), '2:00 pm – 7:00 pm', 'hours unknown: the range');
  // A tolerant reader: unknown codes dropped, hours mapped.
  const p = model.normalizePlanning({ hours: { daily_start: '09:00:00', daily_end: '19:00' }, talk_titles: ['A'], guests: [
    { guest_id: 'g', days: [D2, D1], version: '2', answers: { food: 'pescatarian', access: ['front_seat', 'jetpack', 'wheelchair'], allergy: 'maybe',
      timing: [{ date: D1, whole_day: false, arrive: '14:00:00', leave: '19:00' }] } }] });
  assert.deepEqual(p.hours, { start: '09:00', end: '19:00' });
  assert.equal(p.guests.g.version, 2);
  assert.deepEqual(p.guests.g.days, [D1, D2]);
  assert.equal(p.guests.g.answers.food, null);
  assert.equal(p.guests.g.answers.allergy, null);
  assert.deepEqual(p.guests.g.answers.access, ['wheelchair', 'front_seat']);
  assert.deepEqual(p.guests.g.answers.timing, [{ date: D1, whole_day: false, arrive: '14:00', leave: '19:00' }]);
});

// ── 439 (the owner, 21 Oct 2026): a candidate that a merge folded the record they were held for into ──
test('to match (439): a candidate with a record merged into it says whose phone or email that was; older servers send none', async () => {
  await mount({ role: 'staff', setup: (b, fx) => {
    fx.extras.holds[0].candidates[0].merged_from = [{ customer_id: 'c-old', full_name: 'Holly Oldrecord', phone: '+61491572983',
      email: null, phone_matches: true, email_matches: false }];
  } });
  const rows = [...document.querySelector('[data-hold="p-3"]').querySelectorAll('tbody tr')];
  assert.equal(rows[0].querySelector('[data-candidate-merged]').textContent, 'Merged from Holly Oldrecord, who had this phone');
  await mount({ role: 'staff' });
  assert.equal(document.querySelector('[data-candidate-merged]'), null, 'nothing merged into it: nothing said');
  const x = model.normalizeWebExtras({ settings: { store_id: 's', mode: 'live', code: 'X' }, guests: [], holds: [
    { person_id: 'p', registration_id: 'R', candidates: [{ customer_id: 'c', full_name: 'C', merged_from: [
      { customer_id: 'm1', full_name: 'M One', phone_matches: true, email_matches: true }, { customer_id: '', full_name: 'none' }] },
      { customer_id: 'd', full_name: 'D' }] }] });
  assert.deepEqual(x.holds[0].candidates[0].merged_from,
    [{ customer_id: 'm1', full_name: 'M One', phone: null, email: null, phone_matches: true, email_matches: true }]);
  assert.equal(model.candidateMergedText(x.holds[0].candidates[0]), 'Merged from M One, who had this phone and email');
  assert.deepEqual(x.holds[0].candidates[1].merged_from, [], 'an older 436 sends no merged_from');
  assert.equal(model.candidateMergedText(x.holds[0].candidates[1]), null);
});
