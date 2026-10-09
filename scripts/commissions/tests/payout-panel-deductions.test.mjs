// The Commissions page's Balances tab, rendered for real against a fake
// backend (410): an affiliate who owes commission back is offered nothing to
// pay, "Remaining payable" leaves them out, and the deduction is shown. Both
// with 410's figures and against a database without them (the page works the
// same figures out from the months).
//
// src/components/commissions/AffiliatePayoutPanel.tsx is bundled with esbuild
// and mounted in jsdom; only the Supabase client is stubbed. Every name and
// amount below is invented.
//
// Run: node --test scripts/commissions/tests/payout-panel-deductions.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://commissions.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver', 'sessionStorage']) {
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
      export { AffiliatePayoutPanel } from './src/components/commissions/AffiliatePayoutPanel';
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
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { rpc: (...a) => globalThis.__rpc(...a), from: () => ({}) };' }));
  } }],
});
const { AffiliatePayoutPanel, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// a owes 562.35 back from September and earned 7.08 in October (the
// production case of 8 Oct 2026); b is owed 100.00 for October.
const month = (referrer, m, earned, adjustments, paid, extra = {}) =>
  ({ referrer, month: m, earned, adjustments, paid, balance: +(earned + adjustments - paid).toFixed(2), tier1: earned, tier2: 0, review_reason: null, ...extra });
function overview(with410) {
  const groups = [month('ref-a', '2026-10-01', 7.08, 0, 0), month('ref-b', '2026-10-01', 100, 0, 0), month('ref-a', '2026-09-01', 1705.59, -991.64, 1276.30)];
  if (!with410) return { groups, payouts: [], methods: [{ id: 'm1', name: 'Bank Transfer', is_active: true, deleted_at: null, is_wallet_credit: false }] };
  const refs = { 'ref-a': { referrer: 'ref-a', owed: -555.27, unpaid: 0, deduction: 555.27, payable: 0 },
                 'ref-b': { referrer: 'ref-b', owed: 100, unpaid: 100, deduction: 0, payable: 100 } };
  return {
    groups: groups.map(g => ({ ...g, payable: g.referrer === 'ref-b' ? 100 : 0, referrer_owed: refs[g.referrer].owed,
                               referrer_payable: refs[g.referrer].payable, referrer_deduction: refs[g.referrer].deduction })),
    referrers: Object.values(refs), payouts: [],
    methods: [{ id: 'm1', name: 'Bank Transfer', is_active: true, deleted_at: null, is_wallet_credit: false }],
  };
}

async function render(with410) {
  globalThis.__rpc = async (name) => {
    if (name === 'affiliate_payout_overview') return { data: overview(with410), error: null };
    if (name === 'commission_referrer_names') return { data: [{ id: 'ref-a', full_name: 'Alpha Affiliate' }, { id: 'ref-b', full_name: 'Bravo Affiliate' }], error: null };
    return { data: null, error: { message: 'unexpected ' + name } };
  };
  const host = document.createElement('div'); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(React.createElement(AffiliatePayoutPanel, { mode: 'earned', canPay: true, userId: 'owner', onSaved: () => {} })); });
  for (let i = 0; i < 10 && !host.textContent.includes('Bravo Affiliate'); i++) await act(async () => { await new Promise(r => setTimeout(r, 10)); });
  const rows = [...host.querySelectorAll('tbody tr')].map(tr => ({
    text: tr.textContent, button: tr.querySelector('button'),
  }));
  return { host, root, rows };
}

for (const with410 of [true, false]) {
  test(`${with410 ? 'with 410' : 'before 410 (worked out on the page)'}: nothing is offered while a deduction is owed`, async () => {
    const { host, root, rows } = await render(with410);
    try {
      assert.match(host.textContent, /Remaining payable: S\$100\.00/, 'only Bravo\'s 100.00 is payable, not Alpha\'s 7.08');
      assert.match(host.textContent, /Deductions to recover: S\$555\.27 \(1 affiliate\)/);
      const alphaOct = rows.find(r => r.text.startsWith('2026-10') && r.text.includes('Alpha Affiliate'));
      const bravoOct = rows.find(r => r.text.startsWith('2026-10') && r.text.includes('Bravo Affiliate'));
      const alphaSep = rows.find(r => r.text.startsWith('2026-09') && r.text.includes('Alpha Affiliate'));
      assert.ok(alphaOct && bravoOct && alphaSep, 'three month rows');
      assert.equal(alphaOct.button.disabled, true, 'Record payout is closed for Alpha\'s October 7.08');
      assert.match(alphaOct.text, /Affiliate owes S\$555\.27 back; recovered from later commission first\./);
      assert.equal(bravoOct.button.disabled, false, 'Bravo can be paid');
      assert.match(alphaSep.text, /Owed back: S\$562\.35/);
      assert.doesNotMatch(host.textContent, /S\$-(555\.27|562\.35)/, 'what is owed back is never shown as a negative balance');
    } finally { await act(async () => root.unmount()); host.remove(); }
  });
}
