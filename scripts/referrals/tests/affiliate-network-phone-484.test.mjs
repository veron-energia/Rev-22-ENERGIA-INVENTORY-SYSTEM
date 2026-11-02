// 484: the affiliate portal's My Network shows the phone numbers the database sends for the affiliate's own direct
// referrals (Tier 1), and nothing of a phone until it sends one, rendered for real against a fake backend (the
// Owner, 31 Oct 2026: the pages go out with the Phone column hidden; the database sends a number only where its
// rules allow, so the numbers appear one by one).
//
//   * Hidden: while no Tier 1 row has a number ('phone' text that is not blank), the page is as 482 left it: no
//     Phone column, no Phone line on the cards, no sentence about phone numbers in the note, Tier 1's empty row
//     spanning 6 columns. So it is with no 'phone' key at all (production today, and once 482 is in) and with
//     every Tier 1 'phone' null, blank or not text (a number, an object, an array, true or false).
//   * Shown: once any Tier 1 row has a number, a middle one alone too (the rows come newest first and the numbers
//     appear one by one): a "Phone" column right after Booking in the table (1200 px and wider) and a "Phone" line
//     right after Booking on each Tier 1 card (narrower); the number as the database sends it, in the font of the
//     staff Downline's phone cell (var(--font-display)), kept whole; a grey "—" (var(--text-muted)) on a row
//     without one (null, blank, not text, or no key); and the note's sentence (push #2, the Owner, 1 Nov 2026) "A
//     phone number shows only for a direct referral who registered through your link after being told you would
//     see it. Use it only to help them with their visit."
//   * Loading, or not loaded: no sentence, whatever the answer will hold; it comes with the numbers.
//   * Tier 2: never a Phone column or line; a number sent there is never shown and never shows Tier 1's column.
//   * The staff Downline is unchanged.
//
// The pages are bundled with esbuild and mounted in jsdom; only the Supabase client, the auth context and xlsx are
// stubbed. Every name and phone is invented (ACMA's fictional +61 2 5550 numbers).
//
// Run: node --test scripts/referrals/tests/affiliate-network-phone-484.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

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
const row = (name, tier, booking, extra = {}) => ({ customer_name: name, tier, referral_date: '2026-10-20T02:00:00Z', joined_at: '2026-10-20T02:00:00Z',
  purchases: 1, total_spent: 60, your_commission: 9, ...booking, ...extra });
// What the database sends without 484 (production today, and once 482 is in): no 'phone' key on any row.
const BASE = {
  tier1: [
    row('Ada One', 'tier1', { booking_state: 'upcoming', booking_at: UPCOMING }),
    row('Ben One', 'tier1', { booking_state: 'visited', booking_at: null }),
    row('Cat One', 'tier1', { booking_state: 'none', booking_at: null }),
    row('Dan One', 'tier1', { booking_state: 'miss', booking_at: MISSED }),
    row('Eve One', 'tier1', { booking_state: 'came', booking_at: CAME }),
    row('Fay One', 'tier1', { booking_state: 'visited', booking_at: null }),
  ],
  tier2: [
    row('Gus Two', 'tier2', { booking_state: 'came', booking_at: CAME }, { parent_name: 'Ada One' }),
    row('Hal Two', 'tier2', { booking_state: 'none', booking_at: null }, { parent_name: 'Ada One' }),
  ],
};
const TIER1 = BASE.tier1.map(r => r.customer_name);
// A number on a Tier 2 row (the database sends none there): never shown, and it never shows Tier 1's column.
const TIER2_NUMBER = '+61255509399';
/** BASE with each Tier 1 row's 'phone' as given (undefined: no key) and a number on Hal Two's Tier 2 row. */
const withPhones = phones => ({
  tier1: BASE.tier1.map((r, i) => (phones[i] === undefined ? { ...r } : { ...r, phone: phones[i] })),
  tier2: BASE.tier2.map(r => (r.customer_name === 'Hal Two' ? { ...r, phone: TIER2_NUMBER } : { ...r })),
});
// Production today, before 482: no 'phone' key and no 'visited' either.
const BEFORE_482 = { tier1: BASE.tier1.map(r => (r.booking_state === 'visited' ? { ...r, booking_state: 'none' } : r)), tier2: BASE.tier2 };
const ALL_NULL = withPhones([null, null, null, null, null, null]);
const BLANK_OR_NOT_TEXT = withPhones([null, '', '   ', ' \t ', 61255509305, undefined]);
const MIXED = withPhones(['+61255509301', null, undefined, '   ', 61255509305, '02 5550 9306']);
const ALL = withPhones(['+61255509301', '+61255509302', '+61255509303', '+61255509304', '+61255509305', '02 5550 9306']);
// Not text: no number, whatever it holds. A number on a middle row alone: any Tier 1 row shows the column, not only
// the first or the last.
const ODD_TYPES = withPhones([{}, ['+61255509301'], true, false, { number: '+61255509305' }, undefined]);
const MIDDLE_ONLY = withPhones([null, undefined, '+61255509303', '   ', null, null]);

let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
/** Mount with the backend's answers; gates[name] holds that call until it resolves, failures[name] fails it. */
async function mount(element, answers, { gates = {}, failures = {} } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = { calls: [], answers };
  backend.rpc = async (name, args) => {
    backend.calls.push({ name, args });
    await Promise.resolve();
    if (gates[name]) await gates[name];
    if (failures[name]) return { data: null, error: { message: failures[name] } };
    return { data: structuredClone(backend.answers[name] ?? null), error: null };
  };
  globalThis.__backend = backend;
  globalThis.__auth = { profile: { id: 'u-staff', role: 'staff', full_name: 'Test Staff', is_active: true }, user: { id: 'u-aff' },
    signOut: async () => {}, affiliate: { customer_id: 'c-rae' } };
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(MemoryRouter, null, element)));
  await tick();
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });
const network = async answer => {
  await mount(React.createElement(M.AffiliateNetworkPage), { affiliate_portal_network: answer, affiliate_portal_campaign_progress: { campaign: null } });
  assert.ok(backend.calls.some(c => c.name === 'affiliate_portal_network'));
};

const TIER1_HEADS = ['Customer', 'Joined', 'Booking', 'Purchases', 'Total Spent', 'Your Commission'];
const TIER1_HEADS_PHONE = ['Customer', 'Joined', 'Booking', 'Phone', 'Purchases', 'Total Spent', 'Your Commission'];
const TIER2_HEADS = ['Customer', 'Referred By', 'Joined', 'Booking', 'Purchases', 'Total Spent', 'Your Commission'];
const NOTE = "Booking is each person's next appointment at the centre, or their last one; Miss means no visit and no purchase at the "
  + 'centre were recorded that day. Came in means they have come to the centre without a booking.';
const PHONE_SENTENCE = ' A phone number shows only for a direct referral who registered through your link after being told you would '
  + 'see it. Use it only to help them with their visit.';

const tables = () => { const t = document.querySelectorAll('.portal-desktop-only table'); assert.equal(t.length, 2); return t; };
const heads = table => [...table.querySelectorAll('thead th')].map(th => th.textContent.trim());
const note = () => document.querySelector('[data-booking-note]').textContent.replace(/\s+/g, ' ').trim();
/** Each tier's cards (the first .portal-mobile-only is Tier 1's, the second Tier 2's). */
const cards = tier => [...document.querySelectorAll('.portal-network .portal-mobile-only')[tier - 1].querySelectorAll('.portal-mobile-card')];
const keys = card => [...card.querySelectorAll('.row .k')].map(k => k.textContent);
/** The cell of a column of each row of a table, by the row's first cell. */
function cells(table, column) {
  const at = heads(table).indexOf(column);
  assert.ok(at >= 0, `a ${column} column: ${heads(table).join(' | ')}`);
  return Object.fromEntries([...table.querySelectorAll('tbody tr')].filter(tr => tr.children.length > 1)
    .map(tr => [tr.children[0].textContent.trim(), tr.children[at]]));
}
/** Each Tier 1 card's line of a label, by the card's title. */
const cardLines = label => Object.fromEntries(cards(1).map(c => [c.querySelector('.title').textContent,
  [...c.querySelectorAll('.row')].find(r => r.querySelector('.k')?.textContent === label) ?? null]));
function checkNumber(cell, number, who) {
  const p = cell.querySelector('[data-phone]');
  assert.equal(p?.getAttribute('data-phone'), 'number', `${who}: a number`);
  assert.equal(p.textContent, number, who);
  assert.equal(p.style.fontFamily, 'var(--font-display)', `${who}: the font of the staff Downline's phone cell`);
  assert.equal(p.style.whiteSpace, 'nowrap', `${who}: kept whole`);
}
function checkDash(cell, who) {
  const p = cell.querySelector('[data-phone]');
  assert.equal(p?.getAttribute('data-phone'), 'none', `${who}: no number`);
  assert.equal(p.textContent, '—', who);
  assert.equal(p.style.color, 'var(--text-muted)', `${who}: a grey dash`);
}
/** Every row of both tables has a cell under each heading, and an empty row spans them all. */
function checkSpans(label) {
  for (const t of tables()) {
    for (const tr of t.querySelectorAll('tbody tr')) {
      const empty = tr.children.length === 1 && tr.textContent === 'No members yet';
      if (empty) assert.equal(Number(tr.children[0].getAttribute('colspan')), heads(t).length, `${label}: the empty row spans the table`);
      else assert.equal(tr.children.length, heads(t).length, `${label}: a cell under each heading`);
    }
  }
}
/** Tier 2, whatever the database sends: no Phone column or line, no number on screen. */
function checkTier2(label) {
  const t2 = tables()[1];
  assert.deepEqual(heads(t2), TIER2_HEADS, `${label}: Tier 2's columns as before`);
  assert.equal(t2.querySelectorAll('[data-phone]').length, 0, `${label}: no phone cell in Tier 2`);
  for (const c of cards(2)) assert.ok(!keys(c).includes('Phone') && !c.querySelector('[data-phone]'), `${label}: no Phone line on a Tier 2 card`);
  assert.ok(!document.body.textContent.includes(TIER2_NUMBER), `${label}: a Tier 2 number is never shown`);
}
/** No number to show: the page as 482 left it. */
function checkHidden(label) {
  const [t1] = tables();
  assert.deepEqual(heads(t1), TIER1_HEADS, `${label}: Tier 1's columns as 482 left them, no Phone`);
  assert.equal(document.querySelectorAll('[data-phone]').length, 0, `${label}: no phone cell anywhere`);
  for (const c of cards(1)) assert.deepEqual(keys(c), ['Joined', 'Booking', 'Purchases', 'Total Spent', 'Your Commission'], `${label}: no Phone line`);
  assert.equal(note(), NOTE, `${label}: the note as 482 left it, no phone sentence`);
  assert.ok(!/phone number|\+6125550|5550 93/i.test(document.body.textContent), `${label}: nothing of a phone on screen`);
  checkSpans(label);
  checkTier2(label);
}
/** Numbers to show: the column and the card line right after Booking, the sentence; "—" for the rows without one. */
function checkShown(label, numbers) {
  const [t1] = tables();
  assert.deepEqual(heads(t1), TIER1_HEADS_PHONE, `${label}: Phone right after Booking`);
  const ph = cells(t1, 'Phone');
  const line = cardLines('Phone');
  for (const c of cards(1)) assert.deepEqual(keys(c), ['Joined', 'Booking', 'Phone', 'Purchases', 'Total Spent', 'Your Commission'], `${label}: the card line right after Booking`);
  for (const who of TIER1) {
    if (numbers[who]) { checkNumber(ph[who], numbers[who], `${label}: ${who}`); checkNumber(line[who], numbers[who], `${label}, card: ${who}`); }
    else { checkDash(ph[who], `${label}: ${who}`); checkDash(line[who], `${label}, card: ${who}`); }
  }
  // Booking is still the column before, untouched.
  assert.equal(cells(t1, 'Booking')['Ada One'].querySelector('[data-booking]').getAttribute('data-booking'), 'upcoming');
  assert.equal(note(), NOTE + PHONE_SENTENCE, `${label}: the note's sentence about phone numbers`);
  checkSpans(label);
  checkTier2(label);
}

test('no phone key on any row (production today, and once 482 is in): no Phone column, no card line, no sentence', async () => {
  await network(BEFORE_482);
  checkHidden('before 482');
  await network(BASE);
  checkHidden('482 in, no phone key');
  assert.equal(cells(tables()[0], 'Booking')['Ben One'].textContent, 'Came in');
});

test('every Tier 1 phone null, blank or not text: the same page as with no key (a Tier 2 number changes nothing)', async () => {
  await network(BASE);
  const noKey = document.getElementById('root').innerHTML;
  for (const [label, answer] of [['all null', ALL_NULL], ['null, blank or not text', BLANK_OR_NOT_TEXT], ['objects, arrays, booleans', ODD_TYPES]]) {
    await network(answer);
    checkHidden(label);
    assert.equal(document.getElementById('root').innerHTML, noKey, `${label}: the very same page as with no phone key`);
  }
});

test('some numbers: the Phone column and card line right after Booking and the sentence, "—" for the others', async () => {
  await network(MIXED);
  checkShown('mixed', { 'Ada One': '+61255509301', 'Fay One': '02 5550 9306' });
});

test('a number on a middle Tier 1 row only: the column, line and sentence, "—" for the rest', async () => {
  await network(MIDDLE_ONLY);
  checkShown('a middle row only', { 'Cat One': '+61255509303' });
});

test('while My Network loads, or when it could not load: no sentence about phone numbers; it comes with the numbers', async () => {
  // A page showing the sentence while loading used to fail only the source test below; this catches it on screen.
  let release;
  const gate = new Promise(r => { release = r; });
  await mount(React.createElement(M.AffiliateNetworkPage), { affiliate_portal_network: MIXED, affiliate_portal_campaign_progress: { campaign: null } },
    { gates: { affiliate_portal_network: gate } });
  assert.ok(backend.calls.some(c => c.name === 'affiliate_portal_network'), 'asked');
  assert.ok(document.body.textContent.includes('Loading…'), 'still loading');
  assert.equal(note(), NOTE, 'loading: the note as 482 left it');
  assert.ok(!/phone number/i.test(document.body.textContent), 'loading: nothing about phone numbers');
  assert.equal(document.querySelectorAll('.portal-network, [data-phone]').length, 0, 'loading: no tables yet');
  release();
  await tick();
  checkShown('loaded after the wait', { 'Ada One': '+61255509301', 'Fay One': '02 5550 9306' });

  // Not loaded: the error and Try again, no sentence; Try again brings the numbers and the sentence together.
  const failures = { affiliate_portal_network: 'Failed to fetch' };
  await mount(React.createElement(M.AffiliateNetworkPage), { affiliate_portal_network: MIXED, affiliate_portal_campaign_progress: { campaign: null } },
    { failures });
  assert.ok(document.querySelector('[data-portal-error]'), 'the error is shown');
  assert.equal(note(), NOTE, 'not loaded: no sentence');
  assert.ok(!/phone number/i.test(document.body.textContent));
  delete failures.affiliate_portal_network;
  const retry = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Try again');
  await act(async () => { retry.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
  checkShown('after Try again', { 'Ada One': '+61255509301', 'Fay One': '02 5550 9306' });
});

test('every Tier 1 row with a number: each shown as the database sends it', async () => {
  await network(ALL);
  checkShown('all', { 'Ada One': '+61255509301', 'Ben One': '+61255509302', 'Cat One': '+61255509303', 'Dan One': '+61255509304',
    'Eve One': '+61255509305', 'Fay One': '02 5550 9306' });
});

test('a number on Tier 2 rows only: never shown, and Tier 1 stays without the column', async () => {
  await network({ tier1: BASE.tier1, tier2: BASE.tier2.map(r => ({ ...r, phone: TIER2_NUMBER })) });
  checkHidden('Tier 2 numbers only');
  await network({ tier1: [], tier2: BASE.tier2.map(r => ({ ...r, phone: TIER2_NUMBER })) });
  checkTier2('no Tier 1, Tier 2 numbers');
  assert.deepEqual(heads(tables()[0]), TIER1_HEADS);
  assert.equal(note(), NOTE);
});

test('the empty rows: Tier 1\'s spans 6 columns, Tier 2\'s 7, with numbers shown or not', async () => {
  const spans = () => [...document.querySelectorAll('.portal-desktop-only td')].filter(td => td.textContent === 'No members yet').map(td => td.getAttribute('colspan'));
  await network({ tier1: [], tier2: [] });
  assert.deepEqual(spans(), ['6', '7'], 'no one');
  checkSpans('no one');
  await network({ tier1: [], tier2: BASE.tier2.map(r => ({ ...r, phone: TIER2_NUMBER })) });
  assert.deepEqual(spans(), ['6'], 'an empty Tier 1 beside Tier 2 numbers');
  checkSpans('an empty Tier 1');
  await network({ tier1: ALL_NULL.tier1, tier2: [] });
  assert.deepEqual(spans(), ['7'], 'numbers hidden, an empty Tier 2');
  checkHidden('numbers hidden, an empty Tier 2');
  await network({ tier1: MIXED.tier1, tier2: [] });
  assert.deepEqual(spans(), ['7'], 'numbers shown, an empty Tier 2');
  checkSpans('numbers shown, an empty Tier 2');
  assert.deepEqual(heads(tables()[0]), TIER1_HEADS_PHONE);
});

test('the staff Downline is unchanged: its phone column and font as before', async () => {
  const dl = { customer_id: 'c-rae', name: 'Rae Test', phone: '+61255509300',
    tier1: [{ customer_id: 'c-1', name: 'Ada One', phone: '+61255509301', joined_on: '2026-10-20', joined_from_created: false, visited: false, first_visit_on: null, booking_state: 'none', booking_at: null }],
    tier2: [{ customer_id: 'c-2', name: 'Gus Two', phone: '+61255509302', parent_id: 'c-1', parent_name: 'Ada One', joined_on: '2026-10-21', joined_from_created: false, visited: false, first_visit_on: null, booking_state: 'none', booking_at: null }] };
  await mount(React.createElement(M.DownlineModal, { customerId: 'c-rae', name: 'Rae Test', onClose() {} }), { customer_downline_visits: dl });
  const t = document.querySelectorAll('table');
  assert.deepEqual(heads(t[0]), ['Name', 'Phone', 'Joined', 'Visited', 'First visit', 'Booking']);
  assert.deepEqual(heads(t[1]), ['Name', 'Referred by', 'Phone', 'Joined', 'Visited', 'First visit', 'Booking']);
  assert.equal(cells(t[0], 'Phone')['Ada One'].textContent, '+61255509301');
  assert.equal(cells(t[1], 'Phone')['Gus Two'].textContent, '+61255509302');
  assert.equal(cells(t[0], 'Phone')['Ada One'].style.fontFamily, 'var(--font-display)');
});

test('the source: one phone reader, Tier 1 only, shown only when Tier 1 has a number, the Downline\'s font', () => {
  const src = read('src/pages/AffiliateNetworkPage.tsx');
  assert.match(src, /const showPhone = \(n\?\.tier1 \?\? \[\]\)\.some\(\(r: any\) => phoneOf\(r\) !== null\);/);
  assert.match(src, /<NetTable rows=\{n\.tier1 \?\? \[\]\} showPhone=\{showPhone\} \/>/);
  assert.match(src, /<NetTable rows=\{n\.tier2 \?\? \[\]\} showParent \/>/);
  assert.match(src, /\{showPhone && <th>Phone<\/th>\}/);
  assert.match(src, /\{showPhone && ' A phone number shows only for a direct referral who registered through your link after being told you would see it\. Use it only to help them with their visit\.'\}/);
  assert.doesNotMatch(src, /Phone numbers are shown for your direct referrals only/, 'the old sentence is gone');
  assert.equal(src.match(/phoneOf\(/g).length, 2, 'the one reader, used by the cell and by the page');
  assert.match(src, /fontFamily: 'var\(--font-display\)'/);
  assert.match(read('src/components/referrals/DownlineModal.tsx'), /<td style=\{\{ fontFamily: 'var\(--font-display\)' \}\}>\{r\.phone \?\? '—'\}<\/td>/);
});
