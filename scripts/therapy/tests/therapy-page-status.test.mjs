// The Therapy page's purchased units, rendered for real against the preview
// stub (410): a unit whose start date has come shows as Active, and is not
// offered Claim, Reschedule or Refund as if it had not started, even before
// the nightly refresh stores that. A unit with a start date set is not offered
// Reschedule (THERAPY-10): moving it is a new Claim.
//
// src/pages/TherapyPage.tsx is bundled with esbuild, as the preview
// (vite.therapy-preview.config.mts) bundles it: the Supabase client and the
// auth context are the preview's stubs. Its UTP-0000010 is stored 'scheduled'
// with a start of 5 Oct 2026, so from that day it has started.
//
// Run: node --test scripts/therapy/tests/therapy-page-status.test.mjs
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
const { TherapyPage, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });

test('a unit whose start date has come is Active, with no Claim, Reschedule or Refund', async () => {
  assert.ok(sgToday() >= '2026-10-05', 'the stub unit UTP-0000010 starts on 5 Oct 2026');
  const host = document.createElement('div'); document.body.appendChild(host);
  const root = createRoot(host);
  try {
    await act(async () => { root.render(React.createElement(TherapyPage)); });
    for (let i = 0; i < 30 && !host.textContent.includes('UTP-0000010'); i++) await act(async () => { await new Promise(r => setTimeout(r, 10)); });
    const row = no => [...host.querySelectorAll('tbody tr')].find(tr => tr.querySelector('td')?.textContent === no);
    const started = row('UTP-0000010');
    assert.ok(started, 'UTP-0000010 is listed');
    const badge = started.querySelector('td:nth-child(9) .badge')?.textContent;
    assert.equal(badge, 'Active', 'shown as Active by its dates, though stored as scheduled');
    const buttons = [...started.querySelectorAll('button')].map(b => b.textContent.trim() || b.title);
    assert.ok(!buttons.includes('Claim'), 'no Claim: ' + buttons.join(', '));
    assert.ok(!buttons.includes('Reschedule'), 'no Reschedule: ' + buttons.join(', '));
    assert.ok(!buttons.includes('Refund'), 'no Refund: ' + buttons.join(', '));
    // A unit not claimed yet keeps Claim, Reschedule and Refund.
    const open = row('UTP-0000013');
    const openButtons = [...open.querySelectorAll('button')].map(b => b.textContent.trim() || b.title);
    assert.ok(openButtons.includes('Claim'), 'an unclaimed unit can be claimed: ' + openButtons.join(', '));
  } finally { await act(async () => root.unmount()); host.remove(); }
});
