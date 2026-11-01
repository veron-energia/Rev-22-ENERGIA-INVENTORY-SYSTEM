// 482: a grey "Came in" in the Booking column for someone who has come to the centre without a cal.com
// booking, on the staff Downline window (with its Excel export) and on the affiliate portal's My Network, rendered
// for real against a fake backend (the Owner, 30 Oct 2026; the word "Came in" and its grey, 31 Oct 2026).
//
//   * The database decides it (calcom_customer_bookings answers 'visited'); the page only words it: "Came in" in
//     the grey of a past booking's date (var(--text-secondary)), no date, no badge, not bold, never red; the red
//     "No booking" stays for 'none'. The screens and the export use the one word (BOOKING_STATUS_LABELS.visited).
//   * The Downline: both tiers, Booking Status "Came in" and an empty Booking in the export, and one sentence in
//     its note. Visited and First visit are the database's, as before (a purchase-only customer reads Visited
//     "No" beside Booking "Came in"). My Network: both tiers in the tables (1200 px and wider) and on the cards
//     (narrower), and one sentence above them.
//   * A state the page does not know shows "—", never "No booking" (how the pages from before 482 show
//     'visited' if 482 reached the database first).
//
// The pages are bundled with esbuild and mounted in jsdom; only the Supabase client, the auth context and xlsx
// are stubbed. Every name and phone is invented (ACMA's fictional +61 2 5550 numbers).
//
// Run: node --test scripts/referrals/tests/downline-booking-482.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { bookingView, BOOKING_STATUS_LABELS } from '../../../src/lib/referral/booking.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

// ── The wording, on its own ─────────────────────────────────────────────────
test('bookingView: visited is "Came in" with no date; unknown states are still "—"', () => {
  const v = (state, text, day, time, label) => ({ state, text, day, time, label });
  assert.equal(BOOKING_STATUS_LABELS.visited, 'Came in');
  assert.equal(BOOKING_STATUS_LABELS.none, 'No booking');
  assert.deepEqual(bookingView({ booking_state: 'visited', booking_at: null }), v('visited', '', '', '', 'Came in'));
  // The database sends no time with it; one sent anyway is not shown (Came in has no date).
  assert.deepEqual(bookingView({ booking_state: 'visited', booking_at: '2026-10-24T03:30:00Z' }), v('visited', '', '', '', 'Came in'));
  assert.deepEqual(bookingView({ booking_state: 'none', booking_at: null }), v('none', '', '', '', 'No booking'));
  assert.deepEqual(bookingView({ booking_state: 'came', booking_at: '2026-10-24T03:30:00Z' }), v('came', 'Sat 24 Oct 2026, 11:30 am', 'Sat 24 Oct 2026', '11:30 am', 'Came'));
  // A state the page does not know (as 'visited' was to the pages before 482): unknown, never "No booking".
  assert.deepEqual(bookingView({ booking_state: 'later_state', booking_at: null }), v('unknown', '', '', '', ''));
  assert.deepEqual(bookingView({ booking_state: 'Visited' }), v('unknown', '', '', '', ''));
  assert.deepEqual(bookingView({ booking_state: 'Came in' }), v('unknown', '', '', '', ''));
});

// ── The pages ───────────────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://app.invalid/', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver',
  'sessionStorage', 'localStorage', 'location', 'history']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.matchMedia = dom.window.matchMedia ?? (() => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} }));
globalThis.matchMedia = dom.window.matchMedia;
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
globalThis.__exports = [];

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as DownlineModal } from './src/components/referrals/DownlineModal';
      export { default as AffiliateNetworkPage } from './src/pages/AffiliateNetworkPage';
      export { MemoryRouter } from 'react-router-dom';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: `export const supabase = {
        rpc: (...a) => globalThis.__backend.rpc(...a),
        from: () => { const q = { select: () => q, eq: () => q, order: () => q, limit: () => q, in: () => q, is: () => q,
          maybeSingle: async () => ({ data: null, error: null }), single: async () => ({ data: null, error: null }),
          then: (res) => Promise.resolve({ data: [], error: null }).then(res) }; return q; },
        auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }), signOut: async () => ({}) },
        functions: { invoke: async () => ({ data: null, error: null }) } };` }));
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
const M = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { MemoryRouter, createRoot, act, React } = M;

const UPCOMING = '2026-10-31T06:00:00+00:00', MISSED = '2026-10-27T08:00:00+00:00';
const bk = (state, at) => ({ booking_state: state, booking_at: at });
const DOWNLINE = {
  customer_id: 'c-rae', name: 'Rae Test', phone: '+61255509200',
  tier1: [
    // Came in by a visit (Visited: Yes), and by a purchase at the centre only (Visited: No): both "Came in".
    { customer_id: 'c-1', name: 'Ada Visit', phone: '+61255509201', joined_on: '2026-10-20', joined_from_created: false, visited: true, first_visit_on: '2026-10-22', ...bk('visited', null) },
    { customer_id: 'c-2', name: 'Ben Bought', phone: '+61255509202', joined_on: '2026-10-10', joined_from_created: false, visited: false, first_visit_on: null, ...bk('visited', null) },
    { customer_id: 'c-3', name: 'Cat None', phone: '+61255509203', joined_on: '2026-10-09', joined_from_created: true, visited: false, first_visit_on: null, ...bk('none', null) },
    { customer_id: 'c-4', name: 'Dan Miss', phone: '+61255509204', joined_on: '2026-10-08', joined_from_created: false, visited: true, first_visit_on: '2026-10-01', ...bk('miss', MISSED) },
  ],
  tier2: [
    { customer_id: 'c-5', name: 'Eli Visit', phone: '+61255509205', parent_id: 'c-1', parent_name: 'Ada Visit', joined_on: '2026-10-21', joined_from_created: false, visited: true, first_visit_on: '2026-10-23', ...bk('visited', null) },
    { customer_id: 'c-6', name: 'Fox None', phone: '+61255509206', parent_id: 'c-1', parent_name: 'Ada Visit', joined_on: '2026-10-11', joined_from_created: false, visited: false, first_visit_on: null, ...bk('none', null) },
    { customer_id: 'c-7', name: 'Gil Up', phone: '+61255509207', parent_id: 'c-2', parent_name: 'Ben Bought', joined_on: '2026-10-12', joined_from_created: false, visited: true, first_visit_on: '2026-10-13', ...bk('upcoming', UPCOMING) },
  ],
};
const net = (r, tier, extra = {}) => ({ customer_name: r.name, tier, referral_date: `${r.joined_on}T02:00:00Z`, joined_at: `${r.joined_on}T02:00:00Z`,
  purchases: 0, total_spent: 0, your_commission: 0, booking_state: r.booking_state, booking_at: r.booking_at, ...extra });
const NETWORK = { tier1: DOWNLINE.tier1.map(r => net(r, 'tier1')), tier2: DOWNLINE.tier2.map(r => net(r, 'tier2', { parent_name: r.parent_name })) };

let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(element, answers) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = { calls: [], answers };
  backend.rpc = async (name, args) => {
    backend.calls.push({ name, args });
    await Promise.resolve();
    return { data: structuredClone(backend.answers[name] ?? null), error: null };
  };
  globalThis.__backend = backend;
  globalThis.__auth = { profile: { id: 'u-staff', role: 'staff', full_name: 'Test Staff', is_active: true }, user: { id: 'u-aff' },
    signOut: async () => {}, affiliate: { customer_id: 'c-rae' } };
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(MemoryRouter, null, element)));
  await tick();
}
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

/** The cell of a column of each row of a table, by the row's first cell. */
function cells(table, column) {
  const heads = [...table.querySelectorAll('thead th')].map(th => th.textContent.trim());
  const at = heads.indexOf(column);
  assert.ok(at >= 0, `a ${column} column: ${heads.join(' | ')}`);
  return Object.fromEntries([...table.querySelectorAll('tbody tr')].filter(tr => tr.children.length > 1)
    .map(tr => [tr.children[0].textContent.trim(), tr.children[at]]));
}
function checkVisited(cell, who) {
  const b = cell.querySelector('[data-booking]');
  assert.equal(b?.getAttribute('data-booking'), 'visited', who);
  assert.equal(b.textContent, 'Came in', `${who}: the words Came in, no date`);
  assert.equal(b.textContent, BOOKING_STATUS_LABELS.visited, `${who}: the export's word`);
  assert.equal(b.style.color, 'var(--text-secondary)', `${who}: grey, as a past booking's date`);
  assert.equal(b.style.fontWeight, '', `${who}: not bold like No booking`);
  assert.equal(b.querySelector('.badge'), null, `${who}: no badge`);
  assert.ok(!cell.querySelector('[style*="--danger"]') && !cell.querySelector('.badge-danger'), `${who}: nothing red`);
}
function checkNone(cell, who) {
  const b = cell.querySelector('[data-booking]');
  assert.equal(b?.getAttribute('data-booking'), 'none', who);
  assert.equal(b.textContent, 'No booking', who);
  assert.equal(b.style.color, 'var(--danger)', `${who}: No booking in red`);
}

test('Downline: Came in, in grey, on both tiers, beside Visited Yes or No as the database says; No booking stays red', async () => {
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }), { customer_downline_visits: DOWNLINE });
  assert.deepEqual(backend.calls, [{ name: 'customer_downline_visits', args: { p_customer_id: 'c-rae' } }]);
  const tables = document.querySelectorAll('table');
  assert.equal(tables.length, 2);
  const t1 = cells(tables[0], 'Booking'), t2 = cells(tables[1], 'Booking');
  checkVisited(t1['Ada Visit'], 'Tier 1 visited by a visit');
  checkVisited(t1['Ben Bought'], 'Tier 1 visited by a purchase');
  checkNone(t1['Cat None'], 'Tier 1 none');
  assert.equal(t1['Dan Miss'].querySelector('[data-booking]').getAttribute('data-booking'), 'miss');
  checkVisited(t2['Eli Visit'], 'Tier 2 visited');
  checkNone(t2['Fox None'], 'Tier 2 none');
  assert.equal(t2['Gil Up'].querySelector('[data-booking]').textContent, 'Sat 31 Oct 2026, 2:00 pm');
  // Visited and First visit are the database's, as before: a purchase-only customer reads No there.
  const v1 = cells(tables[0], 'Visited'), f1 = cells(tables[0], 'First visit');
  assert.equal(v1['Ada Visit'].textContent, 'Yes');
  assert.equal(f1['Ada Visit'].textContent, '22/10/2026');
  assert.equal(v1['Ben Bought'].textContent, 'No');
  assert.equal(f1['Ben Bought'].textContent, '—');
  assert.equal(document.querySelectorAll('[data-booking="visited"]').length, 3);
  assert.equal(document.querySelectorAll('[data-booking="none"]').length, 2);
  // The note: what Miss means, as before, and now what Came in means.
  const note = document.body.textContent.replace(/\s+/g, ' ');
  assert.match(note, /Miss means no visit and no purchase at the centre were recorded on that booking's day\. Came in under Booking means they have no cal\.com booking but have come to the centre \(a visit, or a purchase at the centre\)\./);
  assert.ok(!/Visited under Booking|Visited means they have come/.test(note), 'no sentence uses Visited for the Booking word');
  // The tier headings still count the Visited column (the database's visited), not Came in.
  assert.ok(note.includes('Tier 1 — referred by Rae Test (4, 2 visited)') && note.includes('Tier 2 — referred by their Tier 1 (3, 2 visited)'), note);
});

test('Downline export: Booking Status "Came in" and an empty Booking; the other rows as before', async () => {
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }), { customer_downline_visits: DOWNLINE });
  globalThis.__exports = [];
  await click([...document.querySelectorAll('button')].find(b => b.textContent.includes('Export Excel')));
  assert.equal(globalThis.__exports.length, 1);
  const { sheet } = globalThis.__exports[0];
  assert.deepEqual(sheet.ws.header, ['Tier', 'Name', 'Referred By', 'Phone', 'Joined', 'Joined Is Created Date', 'Visited', 'First Visit', 'Booking', 'Booking Status']);
  assert.deepEqual(sheet.ws.body.map(r => [r.Tier, r.Name, r.Visited, r.Booking, r['Booking Status']]), [
    ['Tier 1', 'Ada Visit', 'Yes', '', 'Came in'], ['Tier 1', 'Ben Bought', 'No', '', 'Came in'],
    ['Tier 1', 'Cat None', 'No', '', 'No booking'], ['Tier 1', 'Dan Miss', 'Yes', 'Tue 27 Oct 2026, 4:00 pm', 'Miss'],
    ['Tier 2', 'Eli Visit', 'Yes', '', 'Came in'], ['Tier 2', 'Fox None', 'No', '', 'No booking'],
    ['Tier 2', 'Gil Up', 'Yes', 'Sat 31 Oct 2026, 2:00 pm', 'Upcoming'],
  ]);
});

test('My Network: Came in, in grey, on both tiers, in the tables and on the cards; the note says what it means', async () => {
  await mount(React.createElement(M.AffiliateNetworkPage), { affiliate_portal_network: NETWORK, affiliate_portal_campaign_progress: { campaign: null } });
  assert.ok(backend.calls.some(c => c.name === 'affiliate_portal_network'));
  const tables = document.querySelectorAll('.portal-desktop-only table');
  assert.equal(tables.length, 2);
  const t1 = cells(tables[0], 'Booking'), t2 = cells(tables[1], 'Booking');
  checkVisited(t1['Ada Visit'], 'portal Tier 1 visited by a visit');
  checkVisited(t1['Ben Bought'], 'portal Tier 1 visited by a purchase');
  checkNone(t1['Cat None'], 'portal Tier 1 none');
  checkVisited(t2['Eli Visit'], 'portal Tier 2 visited');
  checkNone(t2['Fox None'], 'portal Tier 2 none');
  const cards = [...document.querySelectorAll('.portal-mobile-only .portal-mobile-card')];
  assert.equal(cards.length, 7);
  const line = card => [...card.querySelectorAll('.row')].find(r => r.querySelector('.k')?.textContent === 'Booking');
  const byName = Object.fromEntries(cards.map(c => [c.querySelector('.title').textContent, line(c)]));
  checkVisited(byName['Ada Visit'], 'card Tier 1 visited');
  checkVisited(byName['Eli Visit'], 'card Tier 2 visited');
  checkNone(byName['Fox None'], 'card none');
  assert.match(document.querySelector('[data-booking-note]').textContent.replace(/\s+/g, ' '),
    /Miss means no visit and no purchase at the centre were recorded that day\. Came in means they have come to the centre without a booking\./);
  // This fixture sends no 'phone' (as a database before 484): no number shows; 484's page test covers the Phone column.
  assert.ok(!/\+6125550/.test(document.body.textContent), 'no number on the portal when the database sends none');
});

test('a state the page does not know shows "—", never "No booking" (the pages before 482, if 482 came first)', async () => {
  const later = { ...DOWNLINE, tier1: DOWNLINE.tier1.map(r => ({ ...r, booking_state: r.booking_state === 'visited' ? 'later_state' : r.booking_state })), tier2: [] };
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }), { customer_downline_visits: later });
  const t1 = cells(document.querySelectorAll('table')[0], 'Booking');
  for (const who of ['Ada Visit', 'Ben Bought']) {
    const b = t1[who].querySelector('[data-booking]');
    assert.equal(b.getAttribute('data-booking'), 'unknown', who);
    assert.equal(b.textContent, '—', who);
  }
  assert.equal(document.querySelectorAll('[data-booking="none"]').length, 1, 'only the real none is No booking');
});

test('the pages use the one cell and the one wording (no second copy of the rule)', () => {
  const cell = read('src/components/referrals/BookingCell.tsx');
  // The grey of a past booking's date, and the export's word (one wording for the screens and the export).
  assert.match(cell, /data-booking="visited" style=\{\{ color: 'var\(--text-secondary\)', whiteSpace: 'nowrap' \}\}>\{b\.label\}<\/span>/);
  for (const p of ['src/components/referrals/DownlineModal.tsx', 'src/pages/AffiliateNetworkPage.tsx']) {
    const src = read(p);
    assert.match(src, /<BookingCell row=\{r\} \/>/, p);
    assert.doesNotMatch(src, /booking_state ===|'visited'|"visited"/, `${p} leaves the states to BookingCell and bookingView`);
  }
});
