// 480: each customer's cal.com booking on the staff Downline window (with its
// Excel export) and on the affiliate portal's My Network, rendered for real
// against a fake backend.
//
//   * The date and time are Singapore's ("Sat 31 Oct 2026, 2:00 pm"), whatever
//     the device's zone, built from numbers so no engine's month spelling shows.
//   * Upcoming: plain text; came: grey text; Miss: the date and a red "Miss"
//     badge (badge-danger); none: "No booking" in red. A database before 480
//     (no booking_state) shows "—" and exports blanks, never "No booking".
//   * The Downline: a Booking column in both tiers, Booking and Booking Status
//     in the export, one sentence in its note (Miss: no visit and no purchase
//     at the centre that day). My Network: a Booking column in both tiers on a
//     computer (1200 px and wider) and a Booking line on each card (narrower:
//     phones, phones held sideways, tablets), and the same meaning of Miss
//     above them.
//
// The pages are bundled with esbuild and mounted in jsdom; only the Supabase
// client, the auth context and xlsx are stubbed. Every name and phone is
// invented (ACMA's fictional +61 2 5550 numbers).
//
// Run: node --test scripts/referrals/tests/downline-booking-480.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { bookingWhen, bookingParts, bookingView, BOOKING_STATUS_LABELS } from '../../../src/lib/referral/booking.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

// ── The wording, on its own ─────────────────────────────────────────────────
test('bookingWhen: the Singapore day and time, "Sat 31 Oct 2026, 2:00 pm"', () => {
  assert.equal(bookingWhen('2026-10-31T06:00:00+00:00'), 'Sat 31 Oct 2026, 2:00 pm');
  assert.equal(bookingWhen('2026-10-31T14:00:00+08:00'), 'Sat 31 Oct 2026, 2:00 pm');
  // Late evening UTC is the next morning in Singapore.
  assert.equal(bookingWhen('2026-10-31T16:30:00Z'), 'Sun 1 Nov 2026, 12:30 am');
  assert.equal(bookingWhen('2026-09-07T04:05:00Z'), 'Mon 7 Sep 2026, 12:05 pm');
  assert.equal(bookingWhen('2026-12-31T15:59:00Z'), 'Thu 31 Dec 2026, 11:59 pm');
  assert.equal(bookingWhen('2027-01-01T01:00:00.123Z'), 'Fri 1 Jan 2027, 9:00 am');
  for (const bad of [null, undefined, '', 'not a date']) assert.equal(bookingWhen(bad), '');
  assert.deepEqual(bookingParts('2026-10-31T06:00:00Z'), { day: 'Sat 31 Oct 2026', time: '2:00 pm' });
  assert.deepEqual(bookingParts('2026-10-31T04:00:00Z'), { day: 'Sat 31 Oct 2026', time: '12:00 pm' });
  assert.equal(bookingParts('soon'), null);
});

test('bookingWhen does not depend on the device\'s time zone', async () => {
  const { execFileSync } = await import('node:child_process');
  const script = `import { bookingWhen } from ${JSON.stringify(new URL('../../../src/lib/referral/booking.mjs', import.meta.url).href)};
    console.log(bookingWhen('2026-10-31T16:30:00Z'));`;
  for (const tz of ['America/Los_Angeles', 'Pacific/Kiritimati', 'UTC']) {
    const out = execFileSync(process.execPath, ['--input-type=module', '-e', script], { env: { ...process.env, TZ: tz }, encoding: 'utf8' }).trim();
    assert.equal(out, 'Sun 1 Nov 2026, 12:30 am', tz);
  }
});

test('bookingView: the state, the text and the export\'s word', () => {
  const v = (state, text, day, time, label) => ({ state, text, day, time, label });
  assert.deepEqual(bookingView({ booking_state: 'upcoming', booking_at: '2026-10-31T06:00:00Z' }), v('upcoming', 'Sat 31 Oct 2026, 2:00 pm', 'Sat 31 Oct 2026', '2:00 pm', 'Upcoming'));
  assert.deepEqual(bookingView({ booking_state: 'came', booking_at: '2026-10-24T03:30:00Z' }), v('came', 'Sat 24 Oct 2026, 11:30 am', 'Sat 24 Oct 2026', '11:30 am', 'Came'));
  assert.deepEqual(bookingView({ booking_state: 'miss', booking_at: '2026-10-27T08:00:00Z' }), v('miss', 'Tue 27 Oct 2026, 4:00 pm', 'Tue 27 Oct 2026', '4:00 pm', 'Miss'));
  assert.deepEqual(bookingView({ booking_state: 'none', booking_at: null }), v('none', '', '', '', 'No booking'));
  // A database before 480 sends no state: unknown, not "No booking".
  assert.deepEqual(bookingView({}), v('unknown', '', '', '', ''));
  assert.deepEqual(bookingView({ booking_state: 'toString' }), v('unknown', '', '', '', ''));
  assert.deepEqual(bookingView(null), v('unknown', '', '', '', ''));
  assert.deepEqual(BOOKING_STATUS_LABELS, { upcoming: 'Upcoming', came: 'Came', miss: 'Miss', none: 'No booking' });
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

const UPCOMING = '2026-10-31T06:00:00+00:00', CAME = '2026-10-24T03:30:00+00:00', MISSED = '2026-10-27T08:00:00+00:00';
const bk = (state, at) => ({ booking_state: state, booking_at: at });
const DOWNLINE = {
  customer_id: 'c-rae', name: 'Rae Test', phone: '+61255509100',
  tier1: [
    { customer_id: 'c-1', name: 'Ann Up', phone: '+61255509101', joined_on: '2026-10-20', joined_from_created: false, visited: false, first_visit_on: null, ...bk('upcoming', UPCOMING) },
    { customer_id: 'c-2', name: 'Bea Came', phone: '+61255509102', joined_on: '2026-10-10', joined_from_created: false, visited: true, first_visit_on: '2026-10-24', ...bk('came', CAME) },
    { customer_id: 'c-3', name: 'Cy Miss', phone: '+61255509103', joined_on: '2026-10-09', joined_from_created: false, visited: false, first_visit_on: null, ...bk('miss', MISSED) },
    { customer_id: 'c-4', name: 'Di None', phone: '+61255509104', joined_on: '2026-10-08', joined_from_created: true, visited: false, first_visit_on: null, ...bk('none', null) },
  ],
  tier2: [
    { customer_id: 'c-5', name: 'Eve Up', phone: '+61255509105', parent_id: 'c-1', parent_name: 'Ann Up', joined_on: '2026-10-21', joined_from_created: false, visited: false, first_visit_on: null, ...bk('upcoming', UPCOMING) },
    { customer_id: 'c-6', name: 'Flo Came', phone: '+61255509106', parent_id: 'c-1', parent_name: 'Ann Up', joined_on: '2026-10-11', joined_from_created: false, visited: true, first_visit_on: '2026-10-24', ...bk('came', CAME) },
    { customer_id: 'c-7', name: 'Gus Miss', phone: '+61255509107', parent_id: 'c-2', parent_name: 'Bea Came', joined_on: '2026-10-12', joined_from_created: false, visited: false, first_visit_on: null, ...bk('miss', MISSED) },
    { customer_id: 'c-8', name: 'Hal None', phone: '+61255509108', parent_id: 'c-2', parent_name: 'Bea Came', joined_on: '2026-10-13', joined_from_created: false, visited: false, first_visit_on: null, ...bk('none', null) },
  ],
};
const strip = rows => rows.map(({ booking_state, booking_at, ...r }) => r);
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

/** The Booking cell of each row of a table, by the row's first cell. */
function bookingCells(table) {
  const heads = [...table.querySelectorAll('thead th')].map(th => th.textContent.trim());
  const at = heads.indexOf('Booking');
  assert.ok(at >= 0, `a Booking column: ${heads.join(' | ')}`);
  return Object.fromEntries([...table.querySelectorAll('tbody tr')].filter(tr => tr.children.length > 1)
    .map(tr => [tr.children[0].textContent.trim(), tr.children[at]]));
}
function checkCell(cell, state, text, who) {
  const b = cell.querySelector('[data-booking]');
  assert.equal(b?.getAttribute('data-booking'), state, who);
  if (state === 'none') {
    assert.equal(b.textContent, 'No booking', who);
    assert.equal(b.style.color, 'var(--danger)', `${who}: No booking in red`);
  } else if (state === 'miss') {
    const badge = b.querySelector('.badge');
    assert.ok(badge && badge.classList.contains('badge-danger') && badge.textContent === 'Miss', `${who}: a red Miss badge`);
    assert.equal(b.textContent.replace(/\s+/g, ' ').trim(), `${text} Miss`, who);
  } else {
    assert.equal(b.textContent, text, who);
    assert.equal(b.style.color, state === 'came' ? 'var(--text-secondary)' : '', `${who}: ${state === 'came' ? 'grey' : 'plain'}`);
    assert.equal(b.querySelector('.badge'), null, `${who}: no badge`);
  }
}

test('Downline: a Booking column in both tiers, each state as asked', async () => {
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }), { customer_downline_visits: DOWNLINE });
  assert.deepEqual(backend.calls, [{ name: 'customer_downline_visits', args: { p_customer_id: 'c-rae' } }]);
  const tables = document.querySelectorAll('table');
  assert.equal(tables.length, 2);
  assert.deepEqual([...tables[0].querySelectorAll('thead th')].map(th => th.textContent), ['Name', 'Phone', 'Joined', 'Visited', 'First visit', 'Booking']);
  assert.deepEqual([...tables[1].querySelectorAll('thead th')].map(th => th.textContent), ['Name', 'Referred by', 'Phone', 'Joined', 'Visited', 'First visit', 'Booking']);
  const t1 = bookingCells(tables[0]), t2 = bookingCells(tables[1]);
  checkCell(t1['Ann Up'], 'upcoming', 'Sat 31 Oct 2026, 2:00 pm', 'Tier 1 upcoming');
  checkCell(t1['Bea Came'], 'came', 'Sat 24 Oct 2026, 11:30 am', 'Tier 1 came');
  checkCell(t1['Cy Miss'], 'miss', 'Tue 27 Oct 2026, 4:00 pm', 'Tier 1 miss');
  checkCell(t1['Di None'], 'none', '', 'Tier 1 none');
  checkCell(t2['Eve Up'], 'upcoming', 'Sat 31 Oct 2026, 2:00 pm', 'Tier 2 upcoming');
  checkCell(t2['Flo Came'], 'came', 'Sat 24 Oct 2026, 11:30 am', 'Tier 2 came');
  checkCell(t2['Gus Miss'], 'miss', 'Tue 27 Oct 2026, 4:00 pm', 'Tier 2 miss');
  checkCell(t2['Hal None'], 'none', '', 'Tier 2 none');
  const note = document.body.textContent.replace(/\s+/g, ' ');
  assert.match(note, /Booking is the customer's next cal\.com booking, else their last one \(cancelled ones are left out\); Miss means no visit and no purchase at the centre were recorded on that booking's day\./);
});

test('Downline export: Booking (the date and time, or blank) and Booking Status (Upcoming, Came, Miss, No booking)', async () => {
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }), { customer_downline_visits: DOWNLINE });
  globalThis.__exports = [];
  await click([...document.querySelectorAll('button')].find(b => b.textContent.includes('Export Excel')));
  assert.equal(globalThis.__exports.length, 1);
  const { sheet } = globalThis.__exports[0];
  assert.deepEqual(sheet.ws.header, ['Tier', 'Name', 'Referred By', 'Phone', 'Joined', 'Joined Is Created Date', 'Visited', 'First Visit', 'Booking', 'Booking Status']);
  assert.deepEqual(sheet.ws.body.map(r => [r.Tier, r.Name, r.Booking, r['Booking Status']]), [
    ['Tier 1', 'Ann Up', 'Sat 31 Oct 2026, 2:00 pm', 'Upcoming'], ['Tier 1', 'Bea Came', 'Sat 24 Oct 2026, 11:30 am', 'Came'],
    ['Tier 1', 'Cy Miss', 'Tue 27 Oct 2026, 4:00 pm', 'Miss'], ['Tier 1', 'Di None', '', 'No booking'],
    ['Tier 2', 'Eve Up', 'Sat 31 Oct 2026, 2:00 pm', 'Upcoming'], ['Tier 2', 'Flo Came', 'Sat 24 Oct 2026, 11:30 am', 'Came'],
    ['Tier 2', 'Gus Miss', 'Tue 27 Oct 2026, 4:00 pm', 'Miss'], ['Tier 2', 'Hal None', '', 'No booking'],
  ]);
  // The columns it had are as they were.
  assert.deepEqual(sheet.ws.body[1], { Tier: 'Tier 1', Name: 'Bea Came', 'Referred By': 'Rae Test', Phone: '+61255509102', Joined: '10/10/2026',
    'Joined Is Created Date': 'No', Visited: 'Yes', 'First Visit': '24/10/2026', Booking: 'Sat 24 Oct 2026, 11:30 am', 'Booking Status': 'Came' });
});

test('Downline from a database before 480: "—" and blank export cells, never a false "No booking"', async () => {
  const old = { ...DOWNLINE, tier1: strip(DOWNLINE.tier1), tier2: strip(DOWNLINE.tier2) };
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }), { customer_downline_visits: old });
  assert.equal(document.querySelectorAll('[data-booking="unknown"]').length, 8);
  assert.ok(!document.body.textContent.includes('No booking'));
  globalThis.__exports = [];
  await click([...document.querySelectorAll('button')].find(b => b.textContent.includes('Export Excel')));
  assert.ok(globalThis.__exports[0].sheet.ws.body.every(r => r.Booking === '' && r['Booking Status'] === ''));
});

test('Downline with no one: the empty row spans the new column', async () => {
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }),
    { customer_downline_visits: { ...DOWNLINE, tier1: [], tier2: [] } });
  const empties = [...document.querySelectorAll('td')].filter(td => td.textContent === 'No one yet');
  assert.deepEqual(empties.map(td => td.getAttribute('colspan')), ['6', '7']);
});

test('My Network: a Booking column in both tiers and a Booking line on each card, the same cell; cards below 1200 px', async () => {
  await mount(React.createElement(M.AffiliateNetworkPage), { affiliate_portal_network: NETWORK, affiliate_portal_campaign_progress: { campaign: null } });
  assert.ok(backend.calls.some(c => c.name === 'affiliate_portal_network'));
  const tables = document.querySelectorAll('.portal-desktop-only table');
  assert.equal(tables.length, 2);
  assert.deepEqual([...tables[0].querySelectorAll('thead th')].map(th => th.textContent),
    ['Customer', 'Joined', 'Booking', 'Purchases', 'Total Spent', 'Your Commission']);
  assert.deepEqual([...tables[1].querySelectorAll('thead th')].map(th => th.textContent),
    ['Customer', 'Referred By', 'Joined', 'Booking', 'Purchases', 'Total Spent', 'Your Commission']);
  // With the extra column no word or date breaks in the middle, so the tables need the full content column:
  // both tiers sit in .portal-network, whose cards replace the tables below 1200 px (globals.css; jsdom applies
  // no media query, so the rule itself is read from the stylesheet).
  assert.ok([...tables].every(tb => tb.style.overflowWrap === 'normal'));
  assert.ok([...tables].every(tb => tb.closest('.portal-network')), 'the tables are inside .portal-network');
  assert.equal(document.querySelectorAll('.portal-network .portal-mobile-only').length, 2, 'both tiers\' cards are inside .portal-network');
  const css = read('src/styles/globals.css').replace(/\s+/g, ' ');
  assert.match(css, /@media \(max-width: 1199px\) \{ \.portal-network \.portal-desktop-only \{ display: none !important; \} \.portal-network \.portal-mobile-only \{ display: block !important; \} \}/);
  const t1 = bookingCells(tables[0]), t2 = bookingCells(tables[1]);
  checkCell(t1['Ann Up'], 'upcoming', 'Sat 31 Oct 2026, 2:00 pm', 'portal Tier 1 upcoming');
  checkCell(t1['Bea Came'], 'came', 'Sat 24 Oct 2026, 11:30 am', 'portal Tier 1 came');
  checkCell(t1['Cy Miss'], 'miss', 'Tue 27 Oct 2026, 4:00 pm', 'portal Tier 1 miss');
  checkCell(t1['Di None'], 'none', '', 'portal Tier 1 none');
  checkCell(t2['Eve Up'], 'upcoming', 'Sat 31 Oct 2026, 2:00 pm', 'portal Tier 2 upcoming');
  checkCell(t2['Gus Miss'], 'miss', 'Tue 27 Oct 2026, 4:00 pm', 'portal Tier 2 miss');
  checkCell(t2['Hal None'], 'none', '', 'portal Tier 2 none');
  // The cards (shown below 1200 px on this page: phones, phones held sideways, tablets): each has a Booking
  // line with the same cell.
  const cards = [...document.querySelectorAll('.portal-mobile-only .portal-mobile-card')];
  assert.equal(cards.length, 8);
  const line = card => [...card.querySelectorAll('.row')].find(r => r.querySelector('.k')?.textContent === 'Booking');
  const byName = Object.fromEntries(cards.map(c => [c.querySelector('.title').textContent, line(c)]));
  checkCell(byName['Ann Up'], 'upcoming', 'Sat 31 Oct 2026, 2:00 pm', 'card upcoming');
  checkCell(byName['Flo Came'], 'came', 'Sat 24 Oct 2026, 11:30 am', 'card came');
  checkCell(byName['Cy Miss'], 'miss', 'Tue 27 Oct 2026, 4:00 pm', 'card miss');
  checkCell(byName['Hal None'], 'none', '', 'card none');
  assert.deepEqual([...cards[0].querySelectorAll('.row .k')].map(k => k.textContent), ['Joined', 'Booking', 'Purchases', 'Total Spent', 'Your Commission']);
  assert.deepEqual([...cards[4].querySelectorAll('.row .k')].map(k => k.textContent), ['Referred By', 'Joined', 'Booking', 'Purchases', 'Total Spent', 'Your Commission']);
  assert.match(document.querySelector('[data-booking-note]').textContent, /Booking is each person's next appointment at the centre, or their last one; Miss means no visit and no purchase at the centre were recorded that day\./);
  // Nothing of a booking but its moment and state reaches the page, and no phone is shown.
  assert.ok(!/\+6125550/.test(document.body.textContent));
});

test('My Network from a database before 480, and with no one', async () => {
  await mount(React.createElement(M.AffiliateNetworkPage),
    { affiliate_portal_network: { tier1: strip(NETWORK.tier1), tier2: [] }, affiliate_portal_campaign_progress: { campaign: null } });
  assert.equal(document.querySelectorAll('.portal-desktop-only [data-booking="unknown"]').length, 4);
  assert.ok(!document.body.textContent.includes('No booking'));
  const empty = [...document.querySelectorAll('.portal-desktop-only td')].find(td => td.textContent === 'No members yet');
  assert.equal(empty.getAttribute('colspan'), '7');
  await mount(React.createElement(M.AffiliateNetworkPage), { affiliate_portal_network: { tier1: [], tier2: [] }, affiliate_portal_campaign_progress: { campaign: null } });
  assert.deepEqual([...document.querySelectorAll('.portal-desktop-only td')].filter(td => td.textContent === 'No members yet').map(td => td.getAttribute('colspan')), ['6', '7']);
});

test('the pages use the one cell and the one wording (no second copy of the rule)', () => {
  const cell = read('src/components/referrals/BookingCell.tsx');
  assert.match(cell, /className="badge badge-danger"/);
  assert.match(cell, /var\(--danger\)/);
  for (const p of ['src/components/referrals/DownlineModal.tsx', 'src/pages/AffiliateNetworkPage.tsx']) {
    const src = read(p);
    assert.match(src, /<BookingCell row=\{r\} \/>/, p);
    assert.doesNotMatch(src, /booking_state ===|'miss'|"miss"/, `${p} leaves the states to BookingCell and bookingView`);
  }
  // The screens read the two RPCs as before.
  assert.match(read('src/components/referrals/DownlineModal.tsx'), /rpc\('customer_downline_visits', \{ p_customer_id: customerId \}\)/);
  assert.match(read('src/pages/AffiliateNetworkPage.tsx'), /usePortalRpc<any>\('affiliate_portal_network'\)/);
});
