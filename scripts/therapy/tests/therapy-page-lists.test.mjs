// The Therapy page's lists and windows after 422, rendered for real against
// the preview stub (scripts/therapy/preview/supabase-stub.ts):
//   * the Purchased and Legacy lists come a page at a time from
//     therapy_list_page, searched and filtered on the server, with names,
//     claimed and left figures and days left from it (THERAPY-5, -15, -19);
//   * a package on a refunded sale offers no Claim, Benefit or Reschedule,
//     says why, and an Owner closes it with "Cancel package (no money back)",
//     which says no money moves and links to the invoice (THERAPY-20, -9);
//   * typing in a search box reads nothing until Search is pressed, and a
//     page past the end steps back to the last page (THERAPY-19);
//   * a Legacy claim starts on the first free day and asks before it
//     overlaps (THERAPY-M2), and never offers a free day after the claim
//     deadline;
//   * any member of staff hands a credit-package reward's vouchers over
//     (THERAPY-12, Q16 A); a reward with no sale and no voucher list waits
//     for an Owner or Manager (the Owner, 9 Oct 2026);
//   * Cancel package says commission stays as it is (commission follows the
//     money, the Owner, 9 Oct 2026), and reads the Legacy list again too;
//   * on a reward that waits for an Owner or Manager, staff see one message
//     only: no number to type and no "any reward voucher" warning;
//   * the tabs wrap and the Packages table scrolls in its frame (THERAPY-11);
//   * the credit-package form shows the till's rules, not tick boxes
//     (THERAPY-6, Q15 A);
//   * the holdings say Issued and Held, never Used (THERAPY-16).
//
// src/pages/TherapyPage.tsx is bundled with esbuild, as the preview bundles it:
// the Supabase client and the auth context are the preview's stubs. The stub
// records every call in globalThis.__therapyStubCalls.
//
// Run: node --test scripts/therapy/tests/therapy-page-lists.test.mjs
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
// The page's own date format (TherapyPage's d()).
const d = s => new Date(s).toLocaleDateString('en-GB');
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const calls = () => globalThis.__therapyStubCalls ?? [];
const lastCall = name => [...calls()].reverse().find(c => c.name === name);
const tick = () => act(async () => { await new Promise(r => setTimeout(r, 10)); });
const until = async (cond, what) => {
  for (let i = 0; i < 100; i++) { if (cond()) return; await tick(); }
  assert.fail('timed out waiting for ' + what);
};
const click = el => act(async () => { el.dispatchEvent(new MouseEvent('click', { bubbles: true })); });
const setValue = (el, value) => act(async () => {
  const proto = el.tagName === 'SELECT' ? HTMLSelectElement.prototype
    : el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
  el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
});
const buttonsIn = el => [...el.querySelectorAll('button')].map(b => b.textContent.trim() || b.title);
const button = (el, text) => [...el.querySelectorAll('button')].find(b => b.textContent.trim() === text);
const row = (host, no) => [...host.querySelectorAll('tbody tr')].find(tr => tr.querySelector('td')?.textContent === no);

async function renderPage(role = 'owner') {
  globalThis.__THERAPY_PREVIEW_ROLE = role;
  if (globalThis.__therapyStubCalls) globalThis.__therapyStubCalls.length = 0;
  const host = document.createElement('div'); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(React.createElement(TherapyPage)); });
  await until(() => host.textContent.includes('UTP-0000013'), 'the Purchased list');
  return { host, done: async () => { await act(async () => root.unmount()); host.remove(); } };
}

test('the Purchased list comes a page at a time from the server, with names and days left', async () => {
  const { host, done } = await renderPage();
  try {
    const call = [...calls()].reverse().find(c => c.name === 'therapy_list_page' && c.args.p_tab === 'purchased');
    assert.ok(call, 'the Purchased list is read through therapy_list_page');
    assert.equal(call.args.p_status, 'all');
    assert.equal(call.args.p_limit, 50);
    assert.equal(call.args.p_offset, 0);
    assert.ok(!calls().some(c => c.name === 'purchased_therapy_units'), 'the page no longer reads purchased_therapy_units');
    const r13 = row(host, 'UTP-0000013');
    assert.match(r13.textContent, /Preview Customer A/, 'the name comes with the row');
    assert.match(row(host, 'UTP-0000012').textContent, /80 days left/, 'a running unit counts its days left');
    assert.match(row(host, 'UTP-0009011').textContent, /92 days from start/, 'a unit not started yet counts from its start');
  } finally { await done(); }
});

test('a package on a refunded sale is not offered Claim, and an Owner closes it with no money moved', async () => {
  const { host, done } = await renderPage();
  try {
    const r = row(host, 'UTP-0009099');
    assert.ok(r, 'UTP-0009099 is listed');
    const b = buttonsIn(r);
    assert.ok(!b.includes('Claim'), 'no Claim: ' + b.join(', '));
    assert.ok(!b.includes('Benefit'), 'no Benefit: ' + b.join(', '));
    assert.ok(!b.includes('Reschedule'), 'no Reschedule: ' + b.join(', '));
    assert.match(r.textContent, /Invoice INV-2026-9001 was refunded\. Close this package with Cancel package\./);
    assert.ok(!b.includes('Refund'), 'the old Refund label is gone');
    await click(button(r, 'Cancel package (no money back)'));
    const dialog = host.querySelector('[data-cancel-package]');
    assert.ok(dialog, 'the Cancel package window opens');
    assert.match(dialog.textContent, /No money is paid back here\./);
    assert.match(dialog.textContent.replace(/\s+/g, ' '), /The invoice stays as it is, and so does any commission on it: commission follows the money\./);
    assert.equal(dialog.querySelector('a').getAttribute('href'), '/invoices?review=inv-e-refunded', 'it links to the invoice');
    const confirm = button(host.querySelector('.modal-footer'), 'Cancel package');
    assert.ok(confirm.disabled, 'a reason is needed first');
    await setValue(dialog.querySelector('textarea'), 'The sale was refunded');
    assert.ok(!button(host.querySelector('.modal-footer'), 'Cancel package').disabled);
    await click(button(host.querySelector('.modal-footer'), 'Cancel package'));
    await until(() => lastCall('refund_purchased_therapy'), 'the cancel call');
    assert.deepEqual(lastCall('refund_purchased_therapy').args, { p_entitlement_id: 'e-refunded', p_reason: 'The sale was refunded' });
    // Both lists are read again: closing a package also cancels the voucher
    // allowance it gave, which the Legacy tab shows.
    const sinceCancel = () => calls().slice(calls().findIndex(c => c.name === 'refund_purchased_therapy'));
    await until(() => ['purchased', 'legacy'].every(t =>
      sinceCancel().some(c => c.name === 'therapy_list_page' && c.args.p_tab === t)), 'both lists read again');
    // A unit not claimed yet on a paid sale keeps Claim.
    assert.ok(buttonsIn(row(host, 'UTP-0000013')).includes('Claim'));
  } finally { await done(); }
});

test('search, the status filter and the pages are sent to the server', async () => {
  const { host, done } = await renderPage();
  try {
    const input = host.querySelector('input[type="search"][aria-label="Search purchased packages"]');
    await setValue(input, 'UTP-0009099');
    await click(button(host.querySelector('.therapy-filters'), 'Search'));
    await until(() => lastCall('therapy_list_page')?.args.p_search === 'UTP-0009099', 'the search call');
    await until(() => !row(host, 'UTP-0000013'), 'the narrowed list');
    assert.ok(row(host, 'UTP-0009099'));
    await setValue(host.querySelector('.therapy-filters select'), 'closed');
    await until(() => lastCall('therapy_list_page')?.args.p_status === 'closed', 'the filter call');
    await until(() => host.textContent.includes('Nothing matches.'), 'the empty result');
    assert.equal(lastCall('therapy_list_page').args.p_offset, 0, 'a new filter starts from the first page');
  } finally { await done(); }
});

test('typing in a search box reads nothing until Search is pressed', async () => {
  const { host, done } = await renderPage();
  try {
    await tick(); await tick();
    const reads = () => calls().filter(c => c.name === 'therapy_list_page' && c.args.p_tab === 'purchased').length;
    const before = reads();
    const input = host.querySelector('input[type="search"][aria-label="Search purchased packages"]');
    for (const v of ['U', 'UT', 'UTP', 'UTP-', 'UTP-0']) await setValue(input, v);
    await tick(); await tick();
    assert.equal(reads(), before, 'five keys typed, no read');
    await click(button(host.querySelector('.therapy-filters'), 'Search'));
    await until(() => reads() === before + 1, 'one read for Search');
    assert.equal(lastCall('therapy_list_page').args.p_search, 'UTP-0');
  } finally { await done(); }
});

test('a page past the end steps back to the last page there is', async () => {
  globalThis.__therapyStubPurchasedPadding = 100;
  const { host, done } = await renderPage();
  try {
    const filters = () => host.querySelector('.therapy-filters');
    await until(() => /Page 1 of 3/.test(filters().textContent), 'three pages');
    await click(button(filters(), 'Next'));
    await until(() => /Page 2 of 3/.test(filters().textContent), 'page 2');
    await click(button(filters(), 'Next'));
    await until(() => /Page 3 of 3/.test(filters().textContent) && lastCall('therapy_list_page')?.args.p_offset === 100, 'page 3');
    // Most rows go (claimed or closed elsewhere), so page 3 is now past the end.
    globalThis.__therapyStubPurchasedPadding = 10;
    const from = calls().length;
    await click(button(host, 'Refresh'));
    const purchasedReads = () => calls().slice(from).filter(c => c.name === 'therapy_list_page' && c.args.p_tab === 'purchased');
    await until(() => purchasedReads().some(c => c.args.p_offset === 0), 'the read of the last page');
    assert.equal(purchasedReads()[0].args.p_offset, 100, 'the refresh read page 3 first');
    await until(() => row(host, 'UTP-0000013'), 'the rows of the last page');
    assert.ok(!/Page \d+ of/.test(filters().textContent), 'one page now, so no pager');
    assert.match(filters().textContent, /\d+ found/);
    assert.ok(!host.textContent.includes('Nothing matches.'));
  } finally { globalThis.__therapyStubPurchasedPadding = 0; await done(); }
});

test('the Legacy list shows what was handed over, hides cancelled rewards, and asks before an overlap', async () => {
  const { host, done } = await renderPage();
  try {
    await click([...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.includes('Legacy Therapy')));
    await until(() => row(host, 'LEG-0009004'), 'the Legacy list');
    const old = row(host, 'LEG-0009004');
    assert.match(old.textContent, /0 of 10 left/, 'claimed before claim documents counts (THERAPY-5)');
    assert.match(old.textContent, /10 handed over/);
    assert.ok(!row(host, 'LEG-0009078'), 'a cancelled reward is hidden by default');
    const legacyCall = [...calls()].reverse().find(c => c.name === 'therapy_list_page' && c.args.p_tab === 'legacy');
    assert.equal(legacyCall.args.p_status, 'open');
    // Cancelled on request: says so, and offers no Vouchers.
    const select = [...host.querySelectorAll('.therapy-filters select')].pop();
    await setValue(select, 'cancelled');
    await until(() => row(host, 'LEG-0009078'), 'the cancelled reward');
    const cancelled = row(host, 'LEG-0009078');
    assert.match(cancelled.textContent, /cancelled/);
    assert.ok(!buttonsIn(cancelled).includes('Vouchers'), 'no Vouchers on a cancelled reward');
    await setValue(select, 'open');
    await until(() => row(host, 'LEG-0009200'), 'the open rewards');

    // THERAPY-M2: the claim starts on the first free day ...
    await click(button(row(host, 'LEG-0009200'), 'Claim'));
    await until(() => host.querySelector('#claim-date'), 'the claim window');
    if (sgToday() < '2026-12-26') {
      assert.equal(host.querySelector('#claim-date').value, '2026-12-26', 'the start date is the first free day');
      assert.ok(host.querySelector('[data-next-free]'), 'and the window says why');
      // In plain words: until when the running therapy lasts, and that the
      // first free day is filled in.
      assert.match(host.querySelector('[data-next-free]').textContent.replace(/\s+/g, ' ').trim(),
        new RegExp(`^This customer's unlimited therapy runs until ${esc(d('2026-12-25'))}\\. The first free day, ${esc(d('2026-12-26'))}, `
          + `is filled in\\. You can choose another day\\. If it overlaps, you will be asked first\\.$`));
    }
    await until(() => button(host, 'Claim unlimited therapy'), 'the reward options');
    await click(button(host, 'Claim unlimited therapy'));
    // ... and asks before it overlaps, claiming nothing.
    await until(() => host.querySelector('[data-overlap]'), 'the overlap question');
    const ask = host.querySelector('[data-overlap]');
    assert.match(ask.textContent, /Nothing has been claimed\./);
    assert.match(ask.textContent, /UTP-0009012/);
    assert.equal(lastCall('claim_legacy_therapy').args.p_allow_overlap, false);
    assert.ok(button(ask, 'Start on 26 Dec 2026 instead'), 'it offers the free day');
    await click(button(ask, 'Start anyway, overlapping'));
    await until(() => host.textContent.includes('Unlimited therapy activated'), 'the confirmation');
    assert.equal(lastCall('claim_legacy_therapy').args.p_allow_overlap, true);
  } finally { await done(); }
});

test('a Legacy claim never offers a first free day after the claim deadline', async () => {
  if (sgToday() > '2027-01-31') return;   // the fixture's deadline has passed
  const { host, done } = await renderPage();
  try {
    await click([...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.includes('Legacy Therapy')));
    await until(() => row(host, 'LEG-0009201'), 'the Legacy list');
    await click(button(row(host, 'LEG-0009201'), 'Claim'));
    await until(() => host.querySelector('#claim-date'), 'the claim window');
    assert.equal(host.querySelector('#claim-date').value, sgToday(), 'today is filled in, not 1 Mar 2027');
    assert.ok(host.querySelector('[data-next-free="after-deadline"]'), 'the window says the free day is after the deadline');
    assert.match(host.querySelector('[data-next-free="after-deadline"]').textContent.replace(/\s+/g, ' ').trim(),
      new RegExp(`^This customer's unlimited therapy runs until ${esc(d('2027-02-28'))}\\. The first free day, ${esc(d('2027-03-01'))}, `
        + `is after the claim deadline, ${esc(d('2027-01-31'))}, so it is not filled in\\. If the day you choose overlaps, `
        + `you will be asked first\\.$`));
    assert.ok(!host.querySelector('[data-next-free=""]'), 'it does not say the free day is filled in');
    await until(() => button(host, 'Claim unlimited therapy'), 'the reward options');
    await click(button(host, 'Claim unlimited therapy'));
    await until(() => host.querySelector('[data-overlap]'), 'the overlap question');
    const ask = host.querySelector('[data-overlap]');
    assert.ok(!button(ask, 'Start on 1 Mar 2027 instead'), 'a day past the deadline is not offered');
    assert.match(ask.querySelector('[data-free-after-deadline]').textContent,
      /The first free day, 1 Mar 2027, is after the claim\s+deadline, 31 Jan 2027\./);
    assert.ok(button(ask, 'Start anyway, overlapping'));
  } finally { await done(); }
});

test('a deleted customer\'s row says "Deleted customer"', async () => {
  const { host, done } = await renderPage();
  try {
    await click([...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.includes('Legacy Therapy')));
    await until(() => row(host, 'LEG-0009300'), 'the Legacy list');
    assert.equal(row(host, 'LEG-0009300').querySelectorAll('td')[1].textContent, 'Deleted customer',
      'the server sends no name for a deleted customer (422, rule 9), and the page says so');
    assert.equal(row(host, 'LEG-0009004').querySelectorAll('td')[1].textContent, 'Preview Customer A', 'a live customer keeps their name');
  } finally { await done(); }
});

test('a member of staff hands a credit-package reward over, and cannot close packages', async () => {
  const { host, done } = await renderPage('staff');
  try {
    const refunded = row(host, 'UTP-0009099');
    assert.match(refunded.textContent, /Ask an Owner or Manager to close this package\./);
    assert.ok(!buttonsIn(refunded).some(t => t.startsWith('Cancel package')), 'staff do not close packages');
    await click([...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.includes('Legacy Therapy')));
    await until(() => row(host, 'LEG-0009120'), 'the Legacy list');
    await click(button(row(host, 'LEG-0009120'), 'Vouchers'));
    await until(() => host.querySelector('#vc-wanted'), 'the Vouchers window');
    assert.ok(!host.querySelector('#vc-wanted').disabled, 'the number to collect can be typed');
    assert.ok(button(host, 'Choose vouchers'), 'staff may go on to hand them over (Q16 A)');
    assert.ok(![...host.querySelectorAll('.therapy-tabs button')].some(b => b.textContent.includes('Credit Packages')),
      'the catalogue tabs stay with Owners and Managers');
  } finally { await done(); }
});

test('a reward with no sale and no voucher list waits for an Owner or Manager', async () => {
  for (const role of ['staff', 'manager']) {
    const { host, done } = await renderPage(role);
    try {
      await click([...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.includes('Legacy Therapy')));
      await until(() => row(host, 'LEG-0009400'), 'the Legacy list');
      const r = row(host, 'LEG-0009400');
      assert.match(r.querySelector('[data-owner-or-manager]')?.textContent ?? '', /An Owner or Manager hands these over\./, role);
      assert.ok(!row(host, 'LEG-0009120').querySelector('[data-owner-or-manager]'), 'a reward with a sale is not marked');
      await click(button(r, 'Vouchers'));
      // The window's note (the row's is a div).
      await until(() => host.querySelector('p[data-owner-or-manager]'), 'the Vouchers window');
      const note = host.querySelector('p[data-owner-or-manager]');
      const dialog = host.querySelector('[role="dialog"]');
      assert.match(note.textContent, /No sale and no voucher list are recorded for this reward, so an Owner or Manager hands it over\./);
      if (role === 'staff') {
        // One message only: no number to type, no hand-over, and no "any
        // reward voucher can be chosen" warning that is not theirs to act on.
        assert.match(note.textContent, /Ask an Owner or Manager\./);
        assert.ok(!host.querySelector('#vc-wanted'), 'staff are not asked how many to collect');
        assert.doesNotMatch(dialog.textContent, /How many vouchers would you like to collect today\?/);
        assert.ok(!button(host, 'Choose vouchers'), 'staff are not offered the hand-over');
        assert.doesNotMatch(dialog.textContent, /predates the record/, 'staff do not see the check-it warning');
      } else {
        await until(() => host.querySelector('#vc-wanted'), 'the number to collect');
        assert.doesNotMatch(note.textContent, /Ask an Owner or Manager/);
        assert.ok(!host.querySelector('#vc-wanted').disabled, 'a Manager types the number');
        assert.ok(button(host, 'Choose vouchers'), 'a Manager hands it over');
        assert.match(dialog.textContent, /predates the record/, 'a Manager is told to check it against the purchase');
      }
    } finally { await done(); }
  }
});

test('the tabs wrap, the Packages table scrolls in its frame, and the holdings say Issued and Held', async () => {
  const { host, done } = await renderPage();
  try {
    assert.ok(host.querySelector('.therapy-tabs.therapy-tabs-wrap'), 'the tab row wraps (THERAPY-11)');
    await until(() => host.querySelector('.therapy-summary-table'), 'the holdings');
    const heads = [...host.querySelectorAll('.therapy-summary-table th')].map(th => th.textContent.trim());
    assert.ok(heads.includes('Held'), 'Held: ' + heads.join(', '));
    assert.ok(!heads.includes('Used'), 'no Used column: ' + heads.join(', '));
    assert.ok(host.querySelector('[data-not-enforced]'), 'it says use is not recorded yet');
    await click([...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.trim() === 'Packages'));
    await until(() => host.textContent.includes('New Package'), 'the Packages tab');
    const table = [...host.querySelectorAll('table')].find(t => t.textContent.includes('Duration'));
    assert.ok(table?.parentElement.classList.contains('table-wrap'), 'the Packages table sits in a table-wrap');
  } finally { await done(); }
});

test('the credit-package form shows what the till lets the credit buy, with no tick boxes', async () => {
  const { host, done } = await renderPage();
  try {
    await click([...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.trim() === 'Credit Packages'));
    await until(() => host.textContent.includes('S$1,000 Credit Package'), 'the Credit Packages tab');
    const pkgRow = [...host.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('S$1,000 Credit Package'));
    await click(pkgRow.querySelector('button.btn-icon'));
    await until(() => host.querySelector('[data-credit-rules]')?.textContent.includes('therapy session'), 'the rules');
    const form = host.querySelector('.modal');
    const rules = host.querySelector('[data-credit-rules]');
    assert.match(rules.textContent, /Paid Credit: therapy session/);
    assert.match(rules.textContent, /Bonus Credit: own product, third party product/);
    assert.doesNotMatch(form.textContent, /Paid Credit may be spent on/);
    assert.doesNotMatch(form.textContent, /every normal category/);
    const labels = [...form.querySelectorAll('label')].map(l => l.textContent.trim());
    for (const gone of ['Normal Products', 'Purchasable Therapy', 'Special Products', 'Rentals']) {
      assert.ok(!labels.includes(gone), `no "${gone}" tick box`);
    }
    assert.match(form.textContent, /Paid Credit S\$1000\.00, spendable on therapy session/);
    assert.equal(lastCall('credit_package_effective_rules').args.p_package_id, 'cp1');
  } finally { await done(); }
});
