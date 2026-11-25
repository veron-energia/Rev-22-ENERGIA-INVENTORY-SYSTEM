// The Owner's correction of an invoice's kept commission rates and line kinds (538; security
// audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Owner repair, recorded"), rendered for real
// against a fake backend: src/components/invoices/CommissionBasisCorrection.tsx and the helpers in
// src/lib/permissions/commissions.ts.
//   * only an Owner sees it (a Manager, an Admin and Staff see nothing);
//   * the window shows the kept rates and each line's kind; an invoice that has not earned says so;
//   * Preview sends only what differs and shows the commission before and after per tier;
//     Confirm stays off until a preview of what is in the boxes and a reason; any edit after a
//     preview needs a new preview; the save carries the reason and a request id;
//   * the server's refusal is shown in its words.
// Every id and name is invented. Run: node --test scripts/commissions/tests/commission-basis-538.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://basis.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver', 'sessionStorage']) {
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

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { CommissionBasisCorrection } from './src/components/invoices/CommissionBasisCorrection';
      export * from './src/lib/permissions/commissions';
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
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { rpc: (...a) => globalThis.__backend.rpc(...a), from: () => ({}) };' }));
  } }],
});
const m = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { CommissionBasisCorrection, createRoot, act, React } = m;

const ITEM_A = 'line-a', ITEM_B = 'line-b';
const BASIS = { rates: { tier1_own: 15, tier1_third: 4.5, tier2_own: 35, tier2_third: 35 },
  lines: [{ invoice_item_id: ITEM_A, name: 'Fixture Pillow', line_kind: 'product', kind: 'own', kept: true },
          { invoice_item_id: ITEM_B, name: 'Fixture Session', line_kind: 'product', kind: 'no_commission', kept: true }],
  totals: { tier1: 15, tier2: 5.25 } };
function backend(basis = BASIS, fail = {}) {
  const b = { calls: [], fail };
  b.rpc = async (name, args) => {
    b.calls.push({ name, args });
    if (b.fail[name]) return { data: null, error: { message: b.fail[name] } };
    if (name === 'invoice_commission_kept_basis') return { data: structuredClone(basis), error: null };
    if (name === 'preview_invoice_commission_correction') return { data: { before: { tier1: 15, tier2: 5.25 }, after: { tier1: 4.5, tier2: 1.58 }, preview: true }, error: null };
    if (name === 'correct_invoice_commission_basis') return { data: { before: { tier1: 15, tier2: 5.25 }, after: { tier1: 4.5, tier2: 1.58 } }, error: null };
    return { data: null, error: null };
  };
  return b;
}
let root = null;
const tick = async (n = 6) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(role, be = backend()) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  globalThis.__backend = be;
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(CommissionBasisCorrection, { invoiceId: 'inv-1', role })));
  await tick();
  return be;
}
const button = label => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === label);
const click = async el => { assert.ok(el, 'the element exists'); await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
async function setValue(el, value) {
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick(2);
}
const kindSelect = name => document.querySelector(`select[aria-label="Kind of ${name}"]`);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

test('538: only an Owner sees the correction (a Manager, an Admin and Staff see nothing)', async () => {
  for (const role of ['manager', 'admin', 'staff', 'inventory_manager', null]) {
    await mount(role);
    assert.equal(document.querySelector('[data-commission-basis]'), null, String(role));
  }
  await mount('owner');
  assert.ok(document.querySelector('[data-commission-basis]'));
});

test('538: the window shows the kept rates and line kinds; Preview sends only what differs; Confirm needs the preview and a reason', async () => {
  const be = await mount('owner');
  await click(document.querySelector('[data-commission-basis]'));
  assert.equal(document.querySelector('input[name="tier1_own"]').value, '15');
  assert.equal(document.querySelector('input[name="tier2_third"]').value, '35');
  assert.equal(kindSelect('Fixture Pillow').value, 'own');
  assert.equal(kindSelect('Fixture Session').value, 'no_commission');
  assert.equal(button('Confirm').disabled, true, 'no confirm before a preview');
  await click(button('Preview'));
  assert.ok(document.querySelector('[role="alert"]').textContent.includes(m.COMMISSION_BASIS_MESSAGES.nothing), 'nothing changed: said so');
  await setValue(kindSelect('Fixture Pillow'), 'third_party');
  await click(button('Preview'));
  assert.deepEqual(be.calls.filter(c => c.name === 'preview_invoice_commission_correction').map(c => c.args),
    [{ p_invoice_id: 'inv-1', p_rates: {}, p_kinds: [{ invoice_item_id: ITEM_A, kind: 'third_party' }] }]);
  const pv = document.querySelector('[data-preview]').textContent;
  assert.ok(pv.includes('Tier 1: S$15.00 → S$4.50') && pv.includes('Tier 2: S$5.25 → S$1.58'), pv);
  assert.equal(button('Confirm').disabled, true, 'no confirm without a reason');
  await setValue(document.querySelector('#basis-reason'), 'Sold as a partner product');
  assert.equal(button('Confirm').disabled, false);
  // An edit after the preview needs a new preview.
  await setValue(document.querySelector('input[name="tier2_own"]'), '30');
  assert.equal(document.querySelector('[data-preview]'), null);
  assert.equal(button('Confirm').disabled, true);
  await setValue(document.querySelector('input[name="tier2_own"]'), '35');
  await click(button('Preview'));
  await click(button('Confirm'));
  const saved = be.calls.filter(c => c.name === 'correct_invoice_commission_basis').map(c => c.args);
  assert.equal(saved.length, 1);
  assert.deepEqual({ ...saved[0], p_request_id: typeof saved[0].p_request_id },
    { p_invoice_id: 'inv-1', p_rates: {}, p_kinds: [{ invoice_item_id: ITEM_A, kind: 'third_party' }], p_reason: 'Sold as a partner product', p_request_id: 'string' });
  assert.ok(document.querySelector('[data-done]').textContent.includes('Tier 1: S$15.00 → S$4.50'));
});

test('538: a rate box out of range is refused before anything is sent, in the server\'s words', async () => {
  const be = await mount('owner');
  await click(document.querySelector('[data-commission-basis]'));
  await setValue(document.querySelector('input[name="tier1_own"]'), '150');
  await click(button('Preview'));
  assert.equal(document.querySelector('[role="alert"]').textContent, m.COMMISSION_BASIS_MESSAGES.rate);
  assert.equal(be.calls.filter(c => c.name === 'preview_invoice_commission_correction').length, 0);
});

test('538: an invoice that has not earned says so, and offers no preview; a refusal is shown in its words', async () => {
  await mount('owner', backend({ rates: null, lines: [], totals: { tier1: 0, tier2: 0 } }));
  await click(document.querySelector('[data-commission-basis]'));
  assert.equal(document.querySelector('[data-note="not-earned"]').textContent, m.COMMISSION_BASIS_MESSAGES.notEarned);
  assert.equal(button('Preview').disabled, true);
  await mount('owner', backend(BASIS, { invoice_commission_kept_basis: m.COMMISSION_BASIS_MESSAGES.ownerOnly }));
  await click(document.querySelector('[data-commission-basis]'));
  assert.equal(document.querySelector('[role="alert"]').textContent, m.COMMISSION_BASIS_MESSAGES.ownerOnly);
});

test('538: the helpers: only an Owner; only what differs is sent; the sentences are the server\'s', () => {
  for (const [role, ok] of [['owner', true], ['manager', false], ['admin', false], ['staff', false], ['inventory_manager', false], [null, false]]) {
    assert.equal(m.canCorrectCommissionBasis(role), ok, String(role));
  }
  const kept = { rates: BASIS.rates, lines: BASIS.lines };
  const same = { rates: { tier1_own: '15', tier1_third: '4.5', tier2_own: '35', tier2_third: '35' }, kinds: { [ITEM_A]: 'own', [ITEM_B]: 'no_commission' } };
  assert.deepEqual(m.basisChanges(kept, same), { rates: {}, kinds: [], error: null });
  assert.deepEqual(m.basisChanges(kept, { ...same, rates: { ...same.rates, tier2_third: '40' } }).rates, { tier2_third: 40 });
  assert.equal(m.basisChanges(kept, { ...same, rates: { ...same.rates, tier1_own: '' } }).error, m.COMMISSION_BASIS_MESSAGES.rate);
  assert.equal(m.basisChanges(kept, { ...same, rates: { ...same.rates, tier1_own: '-1' } }).error, m.COMMISSION_BASIS_MESSAGES.rate);
  assert.deepEqual(m.COMMISSION_BASIS_MESSAGES, {
    ownerOnly: "Only an Owner can correct an invoice's kept commission rates or line kinds.",
    reason: 'Give the reason for the correction.',
    notEarned: 'This invoice has earned no affiliate commission yet, so it keeps no rates or line kinds to correct.',
    rate: 'A rate is tier1_own, tier1_third, tier2_own or tier2_third, each a number from 0 to 100.',
    line: 'That line is not on this invoice, or it is a package, a bundle or a late fee (they have no kind of their own).',
    kind: "A line's kind is own, third_party or no_commission.",
    nothing: 'Nothing would change: these are the rates and kinds this invoice keeps.',
  });
});

// Audit notes d and e (538 pre-check, 25 Nov 2026).
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

test('538: every preview makes a new request id, so a confirm after a lost answer and an edit carries its own', async () => {
  const be = backend(BASIS, { correct_invoice_commission_basis: 'The connection was lost.' });
  await mount('owner', be);
  await click(document.querySelector('[data-commission-basis]'));
  await setValue(kindSelect('Fixture Pillow'), 'third_party');
  await setValue(document.querySelector('#basis-reason'), 'Sold as a partner product');
  await click(button('Preview'));
  await click(button('Confirm'));
  assert.equal(document.querySelector('[role="alert"]').textContent, 'The connection was lost.');
  // The Owner changes the boxes, previews again and confirms (the answer this time arrives).
  delete be.fail.correct_invoice_commission_basis;
  await setValue(document.querySelector('input[name="tier2_third"]'), '40');
  await click(button('Preview'));
  await click(button('Confirm'));
  const ids = be.calls.filter(c => c.name === 'correct_invoice_commission_basis').map(c => c.args.p_request_id);
  assert.equal(ids.length, 2);
  assert.notEqual(ids[0], ids[1], 'the second confirm carries a new id');
  assert.ok(ids.every(id => UUID_V4.test(id)), ids.join(' '));
  assert.ok(document.querySelector('[data-done]'));
});

test('538: the request id is a v4 uuid also where crypto.randomUUID is missing', () => {
  const real = globalThis.crypto;
  try {
    Object.defineProperty(globalThis, 'crypto', { value: { getRandomValues: a => real.getRandomValues(a) }, configurable: true });
    const a = m.newRequestId(), b = m.newRequestId();
    assert.ok(UUID_V4.test(a) && UUID_V4.test(b) && a !== b, a + ' ' + b);
    Object.defineProperty(globalThis, 'crypto', { value: undefined, configurable: true });
    assert.ok(UUID_V4.test(m.newRequestId()));
  } finally {
    Object.defineProperty(globalThis, 'crypto', { value: real, configurable: true });
  }
  assert.ok(UUID_V4.test(m.newRequestId()));
});

test('538: each line offers only the kinds that change something', async () => {
  const lines = [
    { invoice_item_id: 'l-prod', name: 'Fixture Pillow', line_kind: 'product', kind: 'own', kept: true },
    { invoice_item_id: 'l-vou', name: 'Fixture Voucher', line_kind: 'voucher', kind: 'own', kept: true },
    { invoice_item_id: 'l-pro', name: 'Fixture Promotion', line_kind: 'promotion', kind: 'own', kept: true },
    { invoice_item_id: 'l-sp', name: 'Fixture Chair', line_kind: 'special_product', kind: 'third_party', kept: true },
    { invoice_item_id: 'l-the', name: 'Fixture Therapy', line_kind: 'therapy', kind: 'own', kept: true },
  ];
  await mount('owner', backend({ ...BASIS, lines }));
  await click(document.querySelector('[data-commission-basis]'));
  const offered = name => [...kindSelect(name).options].map(o => o.value);
  assert.deepEqual(offered('Fixture Pillow'), ['own', 'third_party', 'no_commission']);
  assert.deepEqual(offered('Fixture Chair'), ['own', 'third_party', 'no_commission']);
  assert.deepEqual(offered('Fixture Therapy'), ['own', 'third_party', 'no_commission']);
  assert.deepEqual(offered('Fixture Voucher'), ['own', 'no_commission'], 'a voucher always earns as own');
  assert.deepEqual(offered('Fixture Promotion'), ['own', 'no_commission'], 'a promotion earns by its split');
  // A kind already kept is still shown.
  assert.deepEqual(m.kindsOffered('promotion', 'third_party'), ['own', 'third_party', 'no_commission']);
  assert.deepEqual(m.kindsOffered('voucher', null), ['own', 'no_commission']);
});
