// 419: the Health Surveys page.
//
//   - Start survey opens the survey window for the customer and makes no
//     record (CUSTOMERS-5); the window gets the person's stores (M1).
//   - Refresh and every save reload the customer list; a failed load says so
//     and offers Retry; the page no longer reads every survey (CUSTOMERS-6).
//   - Inventory Managers get no Remarks (CUSTOMERS-M2).
//   - A new QR link works to the end of the chosen Singapore day, and the list
//     shows Expired once that has passed (CUSTOMERS-7).
//   - A link with an event says how its customers heard about us, Event Name
//     to start with (CUSTOMERS-12).
//
// JSDOM tests with the database stubbed; invented data only.
// Run: node --test scripts/survey/tests/surveys-page-419.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'https://example.test/surveys' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
if (!globalThis.navigator) globalThis.navigator = dom.window.navigator;

const React = (await import('react')).default;
const { act } = await import('react');
const { createRoot } = await import('react-dom/client');
const { Simulate } = await import('react-dom/test-utils');

const require = createRequire(import.meta.url);
const dir = await mkdtemp(join(tmpdir(), 'energia-surveys-page-419-'));

const ICONS = ['RefreshCw', 'Plus', 'QrCode', 'Copy', 'ClipboardList', 'Search', 'Link2', 'Check', 'Eye'];
const STUBS = {
  sb: 'export const supabase = new Proxy({}, { get: (_t, p) => globalThis.__SB__[p] });',
  auth: 'export const useAuth = () => ({ profile: { id: "u-1", role: globalThis.__ROLE__ } });',
  types: `export const isOwnerOrManager = r => r === 'owner' || r === 'manager';`,
  qrcode: 'export default { toDataURL: async () => "data:image/png;base64,QR" };',
  print: 'export const esc = s => String(s);',
  ui: `import React from 'react';
    export const Modal = ({ title, children, footer }) =>
      React.createElement('div', { role: 'dialog' }, React.createElement('h1', null, title), children,
                          React.createElement('footer', null, footer));`,
  // The survey window: records what it was opened with.
  detail: `import React from 'react';
    export default function Detail(p) {
      globalThis.__DETAIL__ = p;
      return React.createElement('div', { 'data-detail': true }, p.customer ? 'start ' + p.customer.full_name : 'open ' + p.surveyId);
    }`,
  none: 'export default function Stub() { return null; }',
  lucide: `import React from 'react';
    const Icon = () => React.createElement('span', { 'aria-hidden': 'true' });
    export const ${ICONS.map(n => `${n} = Icon`).join(', ')};`,
};

await build({
  entryPoints: ['src/pages/SurveysPage.tsx'],
  outfile: join(dir, 'page.mjs'),
  bundle: true, format: 'esm', platform: 'node', jsx: 'automatic', logLevel: 'silent',
  plugins: [{
    name: 'stubs',
    setup(b) {
      b.onResolve({ filter: /^react(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^react-dom(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^lucide-react$/ }, () => ({ path: 'lucide', namespace: 's' }));
      b.onResolve({ filter: /^qrcode$/ }, () => ({ path: 'qrcode', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/supabase$/ }, () => ({ path: 'sb', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/printDoc$/ }, () => ({ path: 'print', namespace: 's' }));
      b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 's' }));
      b.onResolve({ filter: /\/types$/ }, () => ({ path: 'types', namespace: 's' }));
      b.onResolve({ filter: /\/components\/ui$/ }, () => ({ path: 'ui', namespace: 's' }));
      b.onResolve({ filter: /\/SurveyDetailModal$/ }, () => ({ path: 'detail', namespace: 's' }));
      b.onResolve({ filter: /\/(SourceOptionsModal|SurveyHoldsPanel)$/ }, () => ({ path: 'none', namespace: 's' }));
      b.onLoad({ filter: /.*/, namespace: 's' }, a => ({ contents: STUBS[a.path], loader: 'jsx' }));
    },
  }],
});
const { default: SurveysPage } = await import(pathToFileURL(join(dir, 'page.mjs')).href);

const ROWS = [
  { customer_id: 'c-1', full_name: 'Alda Testone', phone: '+61491570156', email: null, survey_id: null, total_count: 2, remark_count: 0 },
  { customer_id: 'c-2', full_name: 'Bea Testtwo', phone: '+61491570157', email: null, survey_id: 'hs-2', survey_no: 'HS-2',
    source: 'consultant', reviewed_at: null, total_count: 2, remark_count: 0 },
];
const LINKS = [
  { id: 'l-old', token: 'tok-old', store_id: 'st-a', event_name: 'Old Fair', is_active: true,
    expires_at: '2026-10-02T00:00:00Z', created_by: null, created_at: '2026-09-01T00:00:00Z' },
  { id: 'l-new', token: 'tok-new', store_id: 'st-a', event_name: null, is_active: true,
    expires_at: null, created_by: null, created_at: '2026-10-01T00:00:00Z' },
];
const SOURCES = [
  { id: 'src-walk', label: 'Walk-in', requires_details: false },
  { id: 'src-event', label: 'Event Name', requires_details: true },
  { id: 'src-road', label: 'RoadShow', requires_details: true },
];

function makeDb({ overviewFails = false } = {}) {
  const state = { calls: [], tables: [], inserts: [], overviewFails };
  const chain = table => {
    const c = {
      select: () => c, order: () => c, is: () => c, eq: () => c,
      insert: row => { state.inserts.push({ table, row }); return Promise.resolve({ data: null, error: null }); },
      update: () => c,
      then: (res, rej) => Promise.resolve({
        data: table === 'survey_links' ? LINKS : table === 'stores' ? [{ id: 'st-a', name: 'Store A' }, { id: 'st-b', name: 'Store B' }] : [],
        error: null,
      }).then(res, rej),
    };
    return c;
  };
  state.sb = {
    rpc: async (name, args) => {
      state.calls.push({ name, args });
      if (name === 'customer_survey_overview') {
        return state.overviewFails ? { data: null, error: { message: 'canceling statement due to statement timeout' } } : { data: ROWS, error: null };
      }
      if (name === 'health_survey_holds_list') return { data: [], error: null };
      if (name === 'my_assigned_stores') return { data: [{ store_id: 'st-a', store_name: 'Store A' }, { store_id: 'st-b', store_name: 'Store B' }], error: null };
      if (name === 'active_customer_source_options') return { data: SOURCES, error: null };
      return { data: null, error: null };
    },
    from: table => { state.tables.push(table); return chain(table); },
  };
  return state;
}

async function mount(role, db) {
  globalThis.__ROLE__ = role;
  globalThis.__SB__ = db.sb;
  globalThis.__DETAIL__ = null;
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  await act(async () => { root.render(React.createElement(SurveysPage)); });
  await act(async () => { await new Promise(r => setTimeout(r, 20)); });
  const $ = sel => node.querySelector(sel);
  const flush = async () => { await act(async () => { await new Promise(r => setTimeout(r, 20)); }); };
  const button = text => [...node.querySelectorAll('button')].find(b => b.textContent.trim() === text || b.textContent.includes(text));
  return {
    node, $, button, text: () => node.textContent,
    async click(el) { await act(async () => { Simulate.click(typeof el === 'string' ? $(el) : el); }); await flush(); },
    async change(sel, value) { await act(async () => { Simulate.change($(sel), { target: { value } }); }); },
    count: name => db.calls.filter(c => c.name === name).length,
    close() { act(() => root.unmount()); node.remove(); },
  };
}

test('CUSTOMERS-5: Start survey opens the window and makes no record; M1: it gets the person\'s stores', async () => {
  const db = makeDb();
  const ui = await mount('staff', db);
  try {
    await ui.click('[data-open-survey="c-1"]');
    assert.equal(ui.count('upsert_consultant_survey'), 0);
    assert.match(ui.$('[data-detail]').textContent, /start Alda Testone/);
    assert.equal(globalThis.__DETAIL__.surveyId, null);
    assert.deepEqual(globalThis.__DETAIL__.stores, [{ store_id: 'st-a', store_name: 'Store A' }, { store_id: 'st-b', store_name: 'Store B' }]);
    await ui.click(ui.button('Close') ?? '[data-open-survey="c-2"]');
    await ui.click('[data-open-survey="c-2"]');
    assert.match(ui.$('[data-detail]').textContent, /open hs-2/);
  } finally { ui.close(); }
});

test('CUSTOMERS-6: no read of every survey; Refresh and a save reload the customer list', async () => {
  const db = makeDb();
  const ui = await mount('owner', db);
  try {
    assert.ok(!db.tables.includes('health_surveys'), 'the page no longer reads every survey');
    const before = ui.count('customer_survey_overview');
    await ui.click(ui.button('Refresh'));
    assert.equal(ui.count('customer_survey_overview'), before + 1);
    await ui.click('[data-open-survey="c-2"]');
    await act(async () => { globalThis.__DETAIL__.onSaved(); });
    await act(async () => { await new Promise(r => setTimeout(r, 20)); });
    assert.equal(ui.count('customer_survey_overview'), before + 2);
  } finally { ui.close(); }
});

test('CUSTOMERS-6: a failed customer list says so and offers Retry, not "No customers match"', async () => {
  const db = makeDb({ overviewFails: true });
  const ui = await mount('staff', db);
  try {
    assert.ok(ui.$('[data-cust-error]'));
    assert.match(ui.text(), /Could not load customers \(canceling statement due to statement timeout\)/);
    assert.doesNotMatch(ui.text(), /No customers match/);
    db.overviewFails = false;
    await ui.click(ui.button('Retry'));
    assert.equal(ui.$('[data-cust-error]'), null);
    assert.match(ui.text(), /Alda Testone/);
  } finally { ui.close(); }
});

test('CUSTOMERS-M2: Inventory Managers get no survey list, no Remarks and no survey buttons', async () => {
  const db = makeDb();
  const ui = await mount('inventory_manager', db);
  try {
    // 419: the list shows the consultant's findings; the server refuses it to them.
    assert.equal(ui.count('customer_survey_overview'), 0, 'the list is not asked for');
    assert.ok(ui.$('[data-no-health-data]'), 'the page says why');
    assert.doesNotMatch(ui.text(), /Alda Testone/);
    assert.equal(ui.$('[data-cust-error]'), null, 'no error is shown');
    assert.equal(ui.$('[data-remarks]'), null);
    assert.equal(ui.$('[data-open-survey]'), null);
  } finally { ui.close(); }
  const staff = await mount('staff', makeDb());
  try { assert.ok(staff.$('[data-remarks="c-1"]'), 'staff keep Remarks'); } finally { staff.close(); }
});

test('CUSTOMERS-7: the links list says Expired once a link is past its last day, whatever its switch', async () => {
  const db = makeDb();
  const ui = await mount('owner', db);
  try {
    await ui.click('[data-tab="links"]');
    assert.match(ui.$('[data-link="l-old"]').textContent, /Expired/);
    assert.match(ui.$('[data-link="l-old"]').textContent, /02\/10\/2026/);
    assert.match(ui.$('[data-link="l-new"]').textContent, /Active/);
  } finally { ui.close(); }
});

test('CUSTOMERS-7 and -12: a new event link works to the end of its last Singapore day, and names its source', async () => {
  const db = makeDb();
  const ui = await mount('owner', db);
  try {
    await ui.click('[data-tab="links"]');
    await ui.click(ui.button('New QR Link'));
    await ui.change('#link-store', 'st-b');
    await ui.change('#link-event', 'Fair 2026');
    assert.equal(ui.$('#link-source').value, 'src-event', 'Event Name to start with');
    await ui.change('#link-source', '');
    await ui.click('[data-create-link]');
    assert.match(ui.text(), /Choose how these customers heard about us\./);
    assert.equal(db.inserts.length, 0);
    await ui.change('#link-source', 'src-road');
    await ui.change('#link-expiry', '2026-10-20');
    await ui.click('[data-create-link]');
    assert.equal(db.inserts.length, 1);
    const row = db.inserts[0].row;
    assert.equal(row.store_id, 'st-b');
    assert.equal(row.event_name, 'Fair 2026');
    assert.equal(row.source_option_id, 'src-road');
    assert.equal(row.expires_at, '2026-10-20T15:59:59.999Z', 'the end of 20 Oct in Singapore');
  } finally { ui.close(); }
});

test('CUSTOMERS-12: a link with no event records no source of its own', async () => {
  const db = makeDb();
  const ui = await mount('owner', db);
  try {
    await ui.click('[data-tab="links"]');
    await ui.click(ui.button('New QR Link'));
    await ui.change('#link-store', 'st-a');
    assert.equal(ui.$('#link-source'), null);
    await ui.click('[data-create-link]');
    assert.equal(db.inserts[0].row.source_option_id, null);
    assert.equal(db.inserts[0].row.expires_at, null);
  } finally { ui.close(); }
});

test.after(async () => { dom.window.close(); await rm(dir, { recursive: true, force: true }); });
