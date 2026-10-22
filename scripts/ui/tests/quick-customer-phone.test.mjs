// The Add a customer window's phone (QuickCustomerModal: New/Edit Invoice's
// Add customer, and each row's + in the Credit Package and Premium Bundle
// splits).
//
// Its ".qc-field select" rule is as specific as the shared PhoneInput's own
// ".phone-input select" and loads later, so its width:100% made the country
// list fill the row and pushed the number box out of the window, where staff
// could not reach it (owner, 22 Oct 2026). The fix is scoped under .qc-field,
// so no other screen's PhoneInput changes. "Phone *" also labels the number
// box now, so clicking it puts the cursor there.
//
// The layout itself is measured in Chrome by instalment-and-phone-browser.mjs
// (npm run test:instalment-and-phone:browser).
//
// Run: node --test scripts/ui/tests/quick-customer-phone.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const css = readFileSync(new URL('../../../src/components/customers/quick-customer.css', import.meta.url), 'utf8');
const stripComments = s => s.replace(/\/\*[\s\S]*?\*\//g, '');

test('the phone rules restore the shared layout, and only inside this window', () => {
  const rules = stripComments(css);
  const generic = rules.indexOf('.qc-field input, .qc-field select {');
  assert.ok(generic >= 0, 'the generic field rule this works against');
  const select = rules.search(/\.qc-field \.phone-input select \{ width: \d+px; \}/);
  const input = rules.search(/\.qc-field \.phone-input input \{ width: auto; \}/);
  assert.ok(select > generic, 'the country list gets a fixed width again, after the rule that set 100%');
  assert.ok(input > generic, 'the number box takes the rest of the row again');
  // Vite puts every stylesheet on every page, so an unscoped .phone-input rule
  // here would change the phone box on Customers, surveys and sign-up pages.
  const selectors = rules.match(/[^{}]+(?=\{)/g).flatMap(s => s.split(',')).map(s => s.trim())
    .filter(s => s.includes('phone-input'));
  assert.ok(selectors.length >= 3, selectors.join(' | '));
  for (const s of selectors) assert.match(s, /^\.qc-field \.phone-input\b/, `${s} reaches outside the Add a customer window`);
});

test('"Phone *" labels the number box', async () => {
  const built = await build({
    stdin: {
      contents: `
        export { QuickCustomerModal } from './src/components/customers/QuickCustomerModal';
        export { createRoot } from 'react-dom/client';
        export { act, default as React } from 'react';`,
      resolveDir: process.cwd(), loader: 'ts',
    },
    bundle: true, write: false, format: 'esm', jsx: 'automatic',
    define: { 'process.env.NODE_ENV': '"development"' },
    plugins: [{ name: 'stub', setup(b) {
      b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'st' }));
      b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'st' }));
      b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'st' }));
      b.onLoad({ filter: /.*/, namespace: 'st' }, a => ({ loader: 'js', contents: a.path === 'db'
        ? 'export const supabase = { rpc: async () => ({ data: { candidates: [], used: 0, remaining: 3 }, error: null }) };'
        : a.path === 'auth' ? "export const useAuth = () => ({ profile: { id: 'staff-1', role: 'staff' } });" : '' }));
    } }],
  });
  const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://tests.invalid' });
  for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'Element', 'Node', 'Event', 'MouseEvent', 'getComputedStyle']) {
    try { globalThis[k] = dom.window[k]; }
    catch { Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true }); }
  }
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  // The bundled act() queues work on a MessageChannel; a real one would keep
  // node running after the tests.
  globalThis.MessageChannel = class {
    constructor() {
      const port = () => ({ onmessage: null, close() {} });
      this.port1 = port(); this.port2 = port();
      this.port1.postMessage = data => setImmediate(() => this.port2.onmessage?.({ data }));
      this.port2.postMessage = data => setImmediate(() => this.port1.onmessage?.({ data }));
    }
  };
  const { QuickCustomerModal, createRoot, act, React } = await import(
    'data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
  const root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(QuickCustomerModal,
    { onCreated: () => {}, onPickedExisting: () => {}, onClose: () => {} })));
  try {
    const label = [...document.querySelectorAll('.quick-customer label')].find(l => l.textContent.trim().startsWith('Phone'));
    const tel = document.querySelector('.quick-customer .phone-input input[type="tel"]');
    assert.ok(label && tel, 'the Phone label and the number box');
    assert.equal(label.htmlFor, 'qc-phone');
    // Compared as booleans: a failing assert.equal on two DOM nodes prints the
    // whole jsdom window.
    assert.ok(document.getElementById('qc-phone') === tel, 'the id is on the number box, not the country list');
    assert.ok(label.control === tel, 'so the label names, and focuses, the number box');
    assert.equal(document.querySelectorAll('#qc-phone').length, 1);
  } finally {
    await act(async () => root.unmount());
    dom.window.close();
  }
});
