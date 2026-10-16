// Behaviour tests for the Health Surveys page's "To match" tab (433):
//
//   - with forms waiting, the tab shows their number, and the Submissions tab
//     says how many wait, with a way to open them;
//   - on a server without 433 (no health_survey_holds_list) there is no tab;
//   - an Inventory Manager, who sees no health surveys, gets no tab and the
//     page does not ask for the list;
//   - a failure after the list was shown keeps it, rather than emptying the
//     page, and says so until a reload works.
//
// JSDOM tests with the database stubbed; invented data only.
// Run: node --test scripts/survey/tests/surveys-page-to-match.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'https://example.test/surveys' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
dom.window.requestAnimationFrame = fn => setTimeout(() => fn(Date.now()), 0);
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame;
if (!globalThis.navigator) globalThis.navigator = dom.window.navigator;

const React = (await import('react')).default;
const { act } = await import('react');
const { createRoot } = await import('react-dom/client');
const { Simulate } = await import('react-dom/test-utils');

const require = createRequire(import.meta.url);
const dir = await mkdtemp(join(tmpdir(), 'energia-surveys-page-'));

const ICONS = ['RefreshCw', 'Plus', 'QrCode', 'Copy', 'ClipboardList', 'Search', 'Link2', 'Check', 'Eye', 'FileText',
               'UserPlus', 'XCircle', 'Lock'];
const STUBS = {
  sb: 'export const supabase = new Proxy({}, { get: (_t, p) => globalThis.__SB__[p] });',
  auth: 'export const useAuth = () => ({ profile: { id: "u-1", role: globalThis.__ROLE__ } });',
  types: `export const isOwnerOrManager = r => r === 'owner' || r === 'manager';`,
  qrcode: 'export default { toDataURL: async () => "data:image/png;base64,QR" };',
  print: 'export const esc = s => String(s);',
  none: 'export default function Stub() { return null; }',
  search: `export const CustomerSearchSelect = () => null;`,
  lucide: `import React from 'react';
    const Icon = () => React.createElement('span', { 'aria-hidden': 'true' });
    export const ${ICONS.map(n => `${n} = Icon`).join(', ')};`,
};

await build({
  entryPoints: ['src/pages/SurveysPage.tsx'],
  outfile: join(dir, 'page.mjs'),
  bundle: true, format: 'esm', platform: 'node', jsx: 'automatic',
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
      b.onResolve({ filter: /\/(SurveyDetailModal|SourceOptionsModal)$/ }, () => ({ path: 'none', namespace: 's' }));
      b.onResolve({ filter: /\/SearchSelect$/ }, () => ({ path: 'search', namespace: 's' }));
      b.onLoad({ filter: /.*/, namespace: 's' }, a => ({ contents: STUBS[a.path], loader: 'jsx' }));
    },
  }],
});
const { default: SurveysPage } = await import(pathToFileURL(join(dir, 'page.mjs')).href);

const FORM = n => ({
  survey_id: `hs-${n}`, survey_no: `HS-20261016-00000${n}`, submitted_at: '2026-10-16T02:15:00Z', store_name: 'Fixture Store',
  event_name: null, full_name: `Fixture Person ${n}`, date_of_birth: null, sex: null, phone: '+6584330901', email: null,
  occupation: null, source_label: null, reason: 'phone_in_use', held_at: '2026-10-16T02:15:00Z', candidates: [],
});

function makeSupabase(holdsReply) {
  const calls = [];
  const chain = () => {
    const c = { select: () => c, order: () => c, is: () => c, eq: () => c, then: (res, rej) => Promise.resolve({ data: [] }).then(res, rej) };
    return c;
  };
  return {
    calls,
    sb: {
      rpc: async (name, args) => {
        calls.push(name);
        if (name === 'health_survey_holds_list') return holdsReply();
        if (name === 'customer_survey_overview') return { data: [] };
        return { data: null, error: null };
      },
      from: () => chain(),
    },
  };
}

async function mount(role, holdsReply) {
  globalThis.__ROLE__ = role;
  const stub = makeSupabase(holdsReply);
  globalThis.__SB__ = stub.sb;
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  await act(async () => { root.render(React.createElement(SurveysPage)); });
  await act(async () => { await new Promise(r => setTimeout(r, 10)); });
  const tabs = () => [...node.querySelectorAll('[data-tab]')].map(b => b.textContent);
  return {
    stub, node, tabs, text: () => node.textContent,
    async click(el) {
      await act(async () => { Simulate.click(el); });
      await act(async () => { await new Promise(r => setTimeout(r, 10)); });
    },
    close() { act(() => root.unmount()); node.remove(); },
  };
}

test('forms waiting: the tab shows how many, and Submissions says so and opens it', async () => {
  const ui = await mount('staff', () => ({ data: [FORM(1), FORM(2)], error: null }));
  try {
    assert.deepEqual(ui.tabs(), ['Submissions', 'To match (2)', 'QR Links']);
    assert.match(ui.text(), /2 QR forms are waiting to be matched to a customer\./);
    const open = [...ui.node.querySelectorAll('button')].find(b => b.textContent === 'Open To match');
    await ui.click(open);
    assert.match(ui.text(), /Fixture Person 1/);
    assert.match(ui.text(), /HS-20261016-000002/);
  } finally { ui.close(); }
});

test('a server without 433: no tab and no banner', async () => {
  const ui = await mount('owner', () => ({ data: null, error: { code: 'PGRST202', message: 'Could not find the function public.health_survey_holds_list' } }));
  try {
    assert.deepEqual(ui.tabs(), ['Submissions', 'QR Links']);
    assert.doesNotMatch(ui.text(), /waiting to be matched/);
  } finally { ui.close(); }
});

test('an Inventory Manager gets no tab, and the list is not asked for', async () => {
  const ui = await mount('inventory_manager', () => ({ data: [FORM(1)], error: null }));
  try {
    assert.deepEqual(ui.tabs(), ['Submissions', 'QR Links']);
    assert.ok(!ui.stub.calls.includes('health_survey_holds_list'));
  } finally { ui.close(); }
});

test('a failure after the list was shown keeps the list and the tab', async () => {
  let fail = false;
  const ui = await mount('staff', () => (fail ? { data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } }
                                              : { data: [FORM(1)], error: null }));
  try {
    const tab = ui.node.querySelector('[data-tab="to_match"]');
    await ui.click(tab);
    assert.match(ui.text(), /Fixture Person 1/);
    fail = true;
    const refresh = [...ui.node.querySelectorAll('button')].find(b => b.textContent.includes('Refresh'));
    await ui.click(refresh);
    assert.deepEqual(ui.tabs(), ['Submissions', 'To match (1)', 'QR Links']);
    assert.match(ui.text(), /Fixture Person 1/);
    assert.match(ui.text(), /could not be reloaded just now \(canceling statement due to statement timeout\)/);
    fail = false;
    await ui.click(refresh);
    assert.doesNotMatch(ui.text(), /could not be reloaded/);
  } finally { ui.close(); }
});
