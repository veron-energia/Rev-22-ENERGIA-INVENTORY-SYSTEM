// A Credit Package's and a Premium Bundle's own commission rates on the Therapy page after 535
// (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026), rendered for real against the
// preview stub (scripts/therapy/preview/supabase-stub.ts):
//   * the forms show the Tier 1 and Tier 2 boxes, as before 535, and no staff commission box;
//     for anyone but an Owner the two are disabled, with "Only an Owner sets these rates.";
//   * the stored staff commission rate is read and sent back exactly as read, unseen, so no
//     save changes it; a Manager's save sends Tier 1 and Tier 2 back as read too (the server
//     refuses any change to the three);
//   * an Owner types Tier 1 and Tier 2; one outside 0 to 100 is refused before anything is
//     sent, in the server's words; 0 and 100 are sent.
// The database's own refusals are proved by scripts/commissions/tests/invoice-keeps-its-rates-535.sql.
//
// Run: node --test scripts/therapy/tests/package-rates-535.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://therapy.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver', 'sessionStorage', 'localStorage']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
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

const built = await build({
  stdin: {
    contents: `
      export { default as TherapyPage } from './src/pages/TherapyPage';
      export { supabase } from './scripts/therapy/preview/supabase-stub.ts';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      import React from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: REPO + 'scripts/therapy/preview/supabase-stub.ts' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: REPO + 'scripts/therapy/preview/auth-stub.tsx' }));
  } }],
});
const { TherapyPage, supabase, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const ONLY_OWNER = 'Only an Owner sets these rates.';
const calls = () => globalThis.__therapyStubCalls ?? [];
const tick = () => act(async () => { await new Promise(r => setTimeout(r, 10)); });
const until = async (cond, what) => {
  for (let i = 0; i < 100; i++) { if (cond()) return; await tick(); }
  assert.fail('timed out waiting for ' + what);
};
const click = el => act(async () => { el.dispatchEvent(new MouseEvent('click', { bubbles: true })); });
const setValue = (el, value) => act(async () => {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
});
const button = (el, text) => [...el.querySelectorAll('button')].find(b => b.textContent.trim() === text);
const tabBtn = (host, label) => [...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.trim() === label);
const field = (host, label) => [...host.querySelectorAll('.modal .form-group')].find(g => g.querySelector('label')?.textContent === label)?.querySelector('input');
const RATE_LABELS = ['Tier 1 rate (%)', 'Tier 2 rate (%)'];
// The form's own error line (the last red box in the window), its words only.
const formError = host => [...host.querySelectorAll('.modal .alert-danger')].pop()?.querySelector('div')?.textContent;

async function renderPage(role) {
  globalThis.__THERAPY_PREVIEW_ROLE = role;
  if (globalThis.__therapyStubCalls) globalThis.__therapyStubCalls.length = 0;
  const host = document.createElement('div'); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(React.createElement(TherapyPage)); });
  await until(() => host.textContent.includes('UTP-0000013'), 'the page');
  return { host, done: async () => { await act(async () => root.unmount()); host.remove(); } };
}
async function openPackage(host) {
  await click(tabBtn(host, 'Credit Packages'));
  await until(() => host.textContent.includes('S$1,000 Credit Package'), 'the Credit Packages tab');
  const row = [...host.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('S$1,000 Credit Package'));
  await click(row.querySelector('button.btn-icon'));
  await until(() => host.querySelector('.modal') && field(host, 'Tier 1 rate (%)'), 'the package window');
}
async function save(host, name, what) {
  const from = calls().length;
  await click(button(host.querySelector('.modal-footer'), 'Save'));
  await until(() => calls().slice(from).some(c => c.name === 'set_catalogue_reward') || formError(host), what);
  return calls().slice(from).find(c => c.name === name)?.args;
}
// The stub's package row, given its own rates for one test (the rows are the stub's own objects).
async function withPackageRates(rates, fn) {
  const { data } = await supabase.from('credit_packages').select('*');
  const row = data.find(r => r.id === 'cp1');
  const was = { tier1_rate: row.tier1_rate, tier2_rate: row.tier2_rate, staff_commission_rate: row.staff_commission_rate };
  Object.assign(row, rates);
  try { await fn(); } finally { Object.assign(row, was); }
}


test('a Manager sees Tier 1 and Tier 2 disabled with the note, no staff box, and the save sends all three back as read', async () => {
  await withPackageRates({ tier1_rate: 10, tier2_rate: 20.5, staff_commission_rate: 2 }, async () => {
    const { host, done } = await renderPage('manager');
    try {
      await openPackage(host);
      assert.deepEqual(RATE_LABELS.map(l => field(host, l).value), ['10', '20.5'], 'the stored rates are shown');
      assert.ok(RATE_LABELS.every(l => field(host, l).disabled), 'both are disabled');
      assert.equal(field(host, 'Staff commission rate (%)'), undefined, 'no staff commission box');
      assert.equal(host.querySelector('.modal [data-note="own-rates-owner-only"]')?.textContent, ONLY_OWNER);
      assert.equal(field(host, 'Package name *').disabled, false, 'the rest stays editable');
      await setValue(field(host, 'Package name *'), 'S$1,000 Credit Package (renamed)');
      const sent = await save(host, 'upsert_credit_package', 'the Manager\'s save');
      assert.ok(sent, 'the save is sent');
      assert.equal(sent.p_name, 'S$1,000 Credit Package (renamed)');
      assert.deepEqual([sent.p_tier1_rate, sent.p_tier2_rate, sent.p_staff_commission_rate], [10, 20.5, 2], 'the three rates as read');
    } finally { await done(); }
  });
});

test('a Manager\'s new bundle has the two boxes disabled, with the note, and sends no rate', async () => {
  const { host, done } = await renderPage('manager');
  try {
    await click(tabBtn(host, 'Premium Bundles'));
    await click(button(host, 'New Bundle'));
    await until(() => host.querySelector('.modal') && field(host, 'Tier 2 rate (%)'), 'the bundle window');
    assert.ok(RATE_LABELS.every(l => field(host, l).disabled && field(host, l).value === ''));
    assert.equal(field(host, 'Staff commission rate (%)'), undefined, 'no staff commission box');
    assert.equal(host.querySelector('.modal [data-note="own-rates-owner-only"]')?.textContent, ONLY_OWNER);
    await setValue(field(host, 'Bundle name *'), 'Fixture Bundle');
    const sent = await save(host, 'upsert_premium_bundle', 'the bundle save');
    assert.deepEqual([sent.p_tier1_rate, sent.p_tier2_rate, sent.p_staff_commission_rate], [null, null, null]);
  } finally { await done(); }
});

test('an Owner types Tier 1 and Tier 2; outside 0 to 100 is refused before sending, in the server\'s words; the staff rate goes back as read', async () => {
  await withPackageRates({ staff_commission_rate: 3 }, async () => {
    const { host, done } = await renderPage('owner');
    try {
      await openPackage(host);
      assert.ok(RATE_LABELS.every(l => !field(host, l).disabled), 'the Owner edits both');
      assert.equal(field(host, 'Staff commission rate (%)'), undefined, 'no staff commission box for the Owner either');
      assert.equal(host.querySelector('.modal [data-note="own-rates-owner-only"]'), null, 'no note for the Owner');
      for (const [label, value, sentence] of [
        ['Tier 1 rate (%)', '500', "A package's or bundle's Tier 1 rate must be between 0 and 100."],
        ['Tier 2 rate (%)', '-1', "A package's or bundle's Tier 2 rate must be between 0 and 100."]]) {
        for (const l of RATE_LABELS) await setValue(field(host, l), '');
        await setValue(field(host, label), value);
        const from = calls().length;
        await click(button(host.querySelector('.modal-footer'), 'Save'));
        await until(() => formError(host) === sentence, 'the refusal for ' + label);
        assert.ok(!calls().slice(from).some(c => c.name === 'upsert_credit_package'), 'nothing is sent for ' + label);
      }
      await setValue(field(host, 'Tier 1 rate (%)'), '0');
      await setValue(field(host, 'Tier 2 rate (%)'), '100');
      const sent = await save(host, 'upsert_credit_package', 'the Owner\'s save');
      assert.deepEqual([sent.p_tier1_rate, sent.p_tier2_rate, sent.p_staff_commission_rate], [0, 100, 3], 'the staff rate as read');
    } finally { await done(); }
  });
});
