// The Therapy page's lists and windows after 422 and 502, rendered for real
// against the preview stub (scripts/therapy/preview/supabase-stub.ts):
//   * the Purchased and Vouchers to hand over lists come a page at a time from
//     therapy_list_page, searched and filtered on the server, with names,
//     handed-over and left figures and days left from it (THERAPY-5, -15, -19);
//   * Vouchers to hand over lists what customers are still owed from a Credit
//     Package, a Premium Bundle or a therapy package taken as vouchers, and
//     never a reward of the old same-day spending reward (502: the server's
//     contract, which the stub reproduces; the SQL suite proves the server);
//     Vouchers shows only where vouchers can still be handed over (some left,
//     the collect-by date not passed, the sale not closed); a reward on a
//     closed sale reads "Sale closed", and a cancelled one says so once; a
//     server without 502 makes that tab say the list could not be loaded,
//     and nothing else breaks;
//   * the hand-over window uses the list's words (owed, handed over, left,
//     collect by), and the holdings card lists the vouchers still to hand
//     over by their collect-by date, apart from packages not claimed yet;
//   * a package on a refunded sale offers no Claim, Benefit or Reschedule,
//     says why, and an Owner closes it with "Cancel package (no money back)",
//     which says no money moves and links to the invoice (THERAPY-20, -9);
//   * typing in a search box reads nothing until Search is pressed, and a
//     page past the end steps back to the last page (THERAPY-19);
//   * any member of staff hands a credit-package reward's vouchers over
//     (THERAPY-12, Q16 A); a reward with no sale and no voucher list waits
//     for an Owner or Manager (the Owner, 9 Oct 2026);
//   * Cancel package says commission stays as it is (commission follows the
//     money, the Owner, 9 Oct 2026), and reads the Vouchers to hand over list
//     again too;
//   * on a reward that waits for an Owner or Manager, staff see one message
//     only: no number to type and no "any reward voucher" warning;
//   * the tabs wrap and the Packages table scrolls in its frame (THERAPY-11);
//   * the credit-package form shows the till's rules, not tick boxes
//     (THERAPY-6, Q15 A), and no reward: new sales give credit only, the
//     threshold and voucher list are sent back as read, and every save
//     switches the reward off (502), a new package's on the id the server
//     gave it;
//   * the Premium Bundle form is unchanged (502);
//   * Holidays holds only the holiday calendars and the expiry recalculation
//     preview;
//   * no tab, window or row names Legacy or Qualification, and the page calls
//     none of their functions (502);
//   * the holdings say Issued and Held, never Used (THERAPY-16), and the old
//     reward's vouchers read "Earlier reward".
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
// The page's own date format (TherapyPage's d()): the Singapore day, dd/mm/yyyy,
// whatever the time zone the test runs in.
const d = s => s.split('-').reverse().join('/');
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
const tabBtn = (host, label) => [...host.querySelectorAll('.therapy-tabs button')].find(b => b.textContent.trim() === label);
const tabLabels = host => [...host.querySelectorAll('.therapy-tabs button')].map(b => b.textContent.trim());
const openTab = async (host, label) => {
  const b = tabBtn(host, label);
  assert.ok(b, `a tab "${label}": ` + tabLabels(host).join(', '));
  await click(b);
};
// The rows of the old same-day spending reward in the stub (earner_kind
// customer or affiliate). Vouchers to hand over never shows them (502).
//
// A stub-contract check, not a test of a filter in the page: the page lists
// whatever therapy_list_page('vouchers') returns, and the stub leaves these
// rows out itself, as 502's server does. So the checks below pin that the page
// asks for the 'vouchers' list (never 'legacy') and adds nothing of its own.
// The proof that the server leaves them out is the 502 SQL suite
// (scripts/therapy/tests/legacy-retired-502-reads.sql).
const OLD_REWARD_ROWS = ['LEG-0009004', 'LEG-0009078', 'LEG-0009200', 'LEG-0009201', 'LEG-0009300', 'LEG-0009500'];
const VOUCHERS_TAB = 'Vouchers to hand over';
const showFilter = async (host, label) => {
  const select = host.querySelector('.therapy-filters select');
  const option = [...select.options].find(o => o.textContent === label);
  assert.ok(option, `a "${label}" filter: ` + [...select.options].map(o => o.textContent).join(', '));
  await setValue(select, option.value);
  await until(() => lastCall('therapy_list_page')?.args.p_status === option.value
    && !host.querySelector('.therapy-filters')?.textContent.includes('Loading'), `the ${label} list`);
};

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
    // allowance it gave, which Vouchers to hand over shows.
    const sinceCancel = () => calls().slice(calls().findIndex(c => c.name === 'refund_purchased_therapy'));
    await until(() => ['purchased', 'vouchers'].every(t =>
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

test('Vouchers to hand over lists what customers are still owed, offers Vouchers only where they can be handed over, and lists no Legacy reward (the server contract, as the stub reproduces it)', async () => {
  const { host, done } = await renderPage();
  try {
    // The list is read when the page opens, from the server's 'vouchers' list,
    // and starts on what is still to hand over. The old list is never asked for.
    const first = calls().find(c => c.name === 'therapy_list_page' && c.args.p_tab === 'vouchers');
    assert.ok(first, 'the list is read through therapy_list_page');
    assert.equal(first.args.p_status, 'pending_activation', 'it opens on To hand over');
    await openTab(host, VOUCHERS_TAB);
    await until(() => row(host, 'LEG-0009120'), 'the Vouchers to hand over list');
    assert.deepEqual([...host.querySelectorAll('thead th')].map(th => th.textContent.trim()),
      ['No.', 'Customer', 'From', 'Vouchers', 'Collect by', 'Status', '']);
    assert.equal(host.querySelector('input[type="search"]').getAttribute('aria-label'), 'Search vouchers to hand over');
    assert.deepEqual([...host.querySelector('.therapy-filters select').options].map(o => o.textContent),
      ['To hand over', 'Handed over', 'All but cancelled', 'Cancelled', 'All']);

    // A credit-package reward, 3 of 10 handed over (THERAPY-5: the server's figures).
    const credit = row(host, 'LEG-0009120');
    assert.match(credit.textContent, /7 of 10 left/);
    assert.match(credit.textContent, /3 handed over/);
    assert.match(credit.textContent, /INV-2026-9337/, 'the sale it came from');
    assert.equal(credit.querySelector('.badge').textContent, 'To hand over');
    assert.ok(buttonsIn(credit).includes('Vouchers'), 'its vouchers can be handed over');
    // A therapy package taken as vouchers.
    assert.match(row(host, 'LEG-0009140').textContent, /6 of 10 left/);
    // Past its collect-by date: says so, in the status and by the date.
    const passed = row(host, 'LEG-0009150');
    assert.equal(passed.querySelector('.badge').textContent, 'Deadline passed');
    // The collect-by date is its Singapore day in any time zone (written out, not computed).
    assert.equal(passed.querySelectorAll('td')[4].textContent, '01/10/2026 · passed');
    assert.equal(credit.querySelectorAll('td')[4].textContent, d('2027-09-20'));
    // Nothing can be handed over once the collect-by date has passed (the
    // server refuses it), so no Vouchers button: the window could only refuse.
    assert.match(passed.textContent, /10 of 10 left/, 'the vouchers are still left on it');
    assert.ok(!buttonsIn(passed).includes('Vouchers'), 'no Vouchers once the collect-by date has passed: ' + buttonsIn(passed).join(', '));
    // A sale refunded, cancelled or deleted: "Sale closed", not "To hand over",
    // with the reason in red, and no Vouchers button (the server refuses it).
    const closed = row(host, 'LEG-0009170');
    assert.ok(closed, 'a reward on a closed sale that the server still keeps waiting is listed');
    const closedBadge = closed.querySelector('.badge');
    assert.equal(closedBadge.textContent, 'Sale closed');
    assert.ok(closedBadge.classList.contains('badge-muted'), 'a muted badge: ' + closedBadge.className);
    assert.match(closed.textContent, /5 of 5 left/);
    assert.equal(closed.querySelector('.therapy-cell-sub')?.textContent, 'Invoice INV-2026-9339 was deleted', 'why, in red');
    assert.ok(!buttonsIn(closed).includes('Vouchers'), 'no Vouchers on a closed sale: ' + buttonsIn(closed).join(', '));
    // A reward an Owner or Manager hands over, past its collect-by date: nothing
    // can be handed over on it, so it is not marked for them and offers no Vouchers.
    const ownerPassed = row(host, 'LEG-0009410');
    assert.ok(ownerPassed, 'the Owner-or-Manager reward past its date is listed');
    assert.equal(ownerPassed.querySelector('.badge').textContent, 'Deadline passed');
    assert.ok(!ownerPassed.querySelector('[data-owner-or-manager]'), 'no "An Owner or Manager hands these over." once the date has passed');
    assert.ok(!buttonsIn(ownerPassed).includes('Vouchers'), 'no Vouchers: ' + buttonsIn(ownerPassed).join(', '));
    // A package ended after 4 were handed over, the other 6 withdrawn, its sale
    // still open: the server keeps it waiting, but nothing is left to hand over.
    const ended = row(host, 'LEG-0009190');
    assert.ok(ended, 'the ended package is listed under To hand over (the server keeps it waiting)');
    assert.match(ended.textContent, /0 of 10 left/);
    assert.equal(ended.querySelector('.badge').textContent, 'Withdrawn', 'not "To hand over" with nothing left');
    assert.ok(!buttonsIn(ended).includes('Vouchers'), 'no Vouchers when nothing is left: ' + buttonsIn(ended).join(', '));
    // Exactly the rows that can be handed over offer Vouchers.
    assert.deepEqual([...host.querySelectorAll('tbody tr')].filter(tr => buttonsIn(tr).includes('Vouchers'))
      .map(tr => tr.querySelector('td').textContent).sort(),
      ['LEG-0009120', 'LEG-0009140', 'LEG-0009301', 'LEG-0009400']);
    // No Claim, no unlimited therapy and no affiliate reward here.
    assert.ok(!buttonsIn(host.querySelector('table')).includes('Claim'), 'no Claim button');
    assert.ok(![...host.querySelectorAll('.badge')].some(b => b.textContent === 'Affiliate'), 'no Affiliate badge');
    for (const no of OLD_REWARD_ROWS) assert.ok(!row(host, no), `${no} is not listed under To hand over`);

    // Handed over: a reward with nothing left offers no Vouchers (the window
    // could only refuse), whether it was all collected or the rest withdrawn.
    await showFilter(host, 'Handed over');
    await until(() => row(host, 'LEG-0009130'), 'the handed-over rewards');
    const bundle = row(host, 'LEG-0009130');
    assert.match(bundle.textContent, /0 of 20 left/);
    assert.match(bundle.textContent, /20 handed over/);
    assert.equal(bundle.querySelector('.badge').textContent, 'Handed over');
    assert.ok(!buttonsIn(bundle).includes('Vouchers'), 'no Vouchers on a reward handed over in full');
    const refunded = row(host, 'LEG-0009160');
    assert.match(refunded.textContent, /0 of 10 left/);
    assert.match(refunded.textContent, /4 handed over/);
    assert.match(refunded.textContent, /6 withdrawn/);
    assert.ok(!buttonsIn(refunded).includes('Vouchers'), 'no Vouchers when the rest was withdrawn');
    // "Handed over" only when nothing was withdrawn.
    assert.equal(refunded.querySelector('.badge').textContent, 'Withdrawn', 'some withdrawn, the sale still open');
    const refundedSale = row(host, 'LEG-0009180');
    assert.ok(refundedSale, 'a reward on a refunded sale with nothing left is listed under Handed over');
    assert.match(refundedSale.textContent, /0 of 10 left/);
    assert.match(refundedSale.textContent, /2 handed over/);
    assert.match(refundedSale.textContent, /8 withdrawn/);
    assert.equal(refundedSale.querySelector('.badge').textContent, 'Sale closed', 'not "Handed over" when 8 of the 10 were withdrawn');
    assert.equal(refundedSale.querySelector('.therapy-cell-sub')?.textContent, 'Invoice INV-2026-9341 was refunded', 'why, in red');
    assert.ok(!buttonsIn(refundedSale).includes('Vouchers'), 'no Vouchers on a refunded sale');
    for (const no of OLD_REWARD_ROWS) assert.ok(!row(host, no), `${no} is not listed under Handed over`);

    // Cancelled on request: says so once, in Status (a dash under Vouchers),
    // and offers no Vouchers.
    await showFilter(host, 'Cancelled');
    await until(() => row(host, 'LEG-0009079'), 'the cancelled reward');
    const cancelled = row(host, 'LEG-0009079');
    assert.match(cancelled.textContent, /cancelled/i);
    assert.equal(cancelled.querySelectorAll('td')[3].textContent, '—', 'its Vouchers column shows a dash');
    assert.deepEqual([...cancelled.querySelectorAll('.badge')].map(b => b.textContent), ['Cancelled'],
      'one Cancelled badge, in Status');
    assert.ok(!buttonsIn(cancelled).includes('Vouchers'), 'no Vouchers on a cancelled reward');
    for (const no of OLD_REWARD_ROWS) assert.ok(!row(host, no), `${no} is not listed under Cancelled`);

    // Every filter, All included: never a reward of the old same-day spending reward.
    for (const label of ['All but cancelled', 'All']) {
      await showFilter(host, label);
      await until(() => row(host, 'LEG-0009079') || row(host, 'LEG-0009120'), `the ${label} list`);
      for (const no of OLD_REWARD_ROWS) assert.ok(!row(host, no), `${no} is not listed under ${label}`);
      assert.doesNotMatch(host.textContent, /Legacy|Qualification/, label);
    }
    assert.ok(row(host, 'LEG-0009079'), 'All lists the cancelled reward too');
    assert.ok(!calls().some(c => c.name === 'therapy_list_page' && c.args.p_tab === 'legacy'), 'the old list is never asked for');
  } finally { await done(); }
});

test('a server without 502 refuses the list: the tab says so, and the rest of the page works', async () => {
  // The deploy order is 502 first, then the pages; this is what a page deployed
  // too early shows. It does not fall back to the old list.
  globalThis.__therapyStubBefore502 = true;
  const { host, done } = await renderPage();
  try {
    await openTab(host, VOUCHERS_TAB);
    await until(() => host.querySelector('.card [role="alert"]'), 'the refusal');
    assert.match(host.querySelector('.card [role="alert"]').textContent,
      /The list could not be loaded: Unknown list: vouchers \(purchased or legacy\)/);
    assert.ok(!calls().some(c => c.name === 'therapy_list_page' && c.args.p_tab === 'legacy'), 'no fallback to the old list');
    await openTab(host, 'Purchased');
    await until(() => row(host, 'UTP-0000013'), 'the Purchased list');
  } finally { globalThis.__therapyStubBefore502 = false; await done(); }
});

test('a deleted customer\'s row says "Deleted customer"', async () => {
  const { host, done } = await renderPage();
  try {
    await openTab(host, VOUCHERS_TAB);
    await until(() => row(host, 'LEG-0009301'), 'the Vouchers to hand over list');
    assert.equal(row(host, 'LEG-0009301').querySelectorAll('td')[1].textContent, 'Deleted customer',
      'the server sends no name for a deleted customer (422, rule 9), and the page says so');
    assert.equal(row(host, 'LEG-0009120').querySelectorAll('td')[1].textContent, 'Preview Customer B', 'a live customer keeps their name');
  } finally { await done(); }
});

test('a member of staff hands a credit-package reward over, and cannot close packages', async () => {
  const { host, done } = await renderPage('staff');
  try {
    const refunded = row(host, 'UTP-0009099');
    assert.match(refunded.textContent, /Ask an Owner or Manager to close this package\./);
    assert.ok(!buttonsIn(refunded).some(t => t.startsWith('Cancel package')), 'staff do not close packages');
    assert.deepEqual(tabLabels(host), ['Purchased', VOUCHERS_TAB], 'staff see the two lists only');
    assert.ok(!tabBtn(host, 'Holidays'), 'Holidays stays with Owners and Managers');
    await openTab(host, VOUCHERS_TAB);
    await until(() => row(host, 'LEG-0009120'), 'the Vouchers to hand over list');
    await click(button(row(host, 'LEG-0009120'), 'Vouchers'));
    await until(() => host.querySelector('#vc-wanted'), 'the Vouchers window');
    // The window speaks the list's words: hand over, owed, handed over, left, collect by.
    assert.equal(host.querySelector('#vc-title').textContent, 'Hand over vouchers — LEG-0009120');
    assert.deepEqual([...host.querySelectorAll('.voucher-claim-tally > div')].map(t => t.textContent),
      ['10Owed', '3Handed over', '7Left']);
    assert.equal(host.querySelector('.voucher-claim-tally + .credit-rules-hint').textContent.replace(/\s+/g, ' ').trim(),
      'Credit package reward · collect by 20 Sep 2027');
    assert.doesNotMatch(host.querySelector('[role="dialog"]').textContent, /[Ee]ntitle|[Cc]laim/, 'no "claim" or "entitlement" in the window');
    assert.ok(!host.querySelector('#vc-wanted').disabled, 'the number to collect can be typed');
    assert.ok(button(host, 'Choose vouchers'), 'staff may go on to hand them over (Q16 A)');
    assert.ok(!tabLabels(host).some(l => l.includes('Credit Packages')), 'the catalogue tabs stay with Owners and Managers');
  } finally { await done(); }
});

test('a reward with no sale and no voucher list waits for an Owner or Manager', async () => {
  for (const role of ['staff', 'manager']) {
    const { host, done } = await renderPage(role);
    try {
      await openTab(host, VOUCHERS_TAB);
      await until(() => row(host, 'LEG-0009400'), 'the Vouchers to hand over list');
      // A credit-package reward: still listed, and still handed over.
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
    assert.deepEqual(tabLabels(host),
      ['Purchased', VOUCHERS_TAB, 'Holidays', 'Credit Packages', 'Premium Bundles', 'Packages']);
    await until(() => host.querySelector('.therapy-summary-table'), 'the holdings');
    const heads = [...host.querySelectorAll('.therapy-summary-table th')].map(th => th.textContent.trim());
    assert.ok(heads.includes('Held'), 'Held: ' + heads.join(', '));
    assert.ok(!heads.includes('Used'), 'no Used column: ' + heads.join(', '));
    assert.ok(host.querySelector('[data-not-enforced]'), 'it says use is not recorded yet');
    await openTab(host, 'Packages');
    await until(() => host.textContent.includes('New Package'), 'the Packages tab');
    const table = [...host.querySelectorAll('table')].find(t => t.textContent.includes('Duration'));
    assert.ok(table?.parentElement.classList.contains('table-wrap'), 'the Packages table sits in a table-wrap');
  } finally { await done(); }
});

test('the holdings card lists the vouchers still to hand over by their collect-by date, apart from packages not claimed yet', async () => {
  const { host, done } = await renderPage();
  try {
    await until(() => host.querySelector('.therapy-row-button'), 'the holdings');
    await click([...host.querySelectorAll('.therapy-row-button')].find(b => b.textContent.includes('Preview Customer A')));
    await until(() => host.querySelector('[data-vouchers-to-hand-over]'), 'the customer\'s detail');
    const lines = section => [...section.querySelectorAll('.therapy-kv')].map(kv => [...kv.children].map(c => c.textContent));
    // Vouchers still owed, in the words of Vouchers to hand over: collect by,
    // and no kind word from the server ('voucher').
    const owed = host.querySelector('[data-vouchers-to-hand-over]');
    assert.equal(owed.querySelector('h4').textContent, 'Vouchers still to hand over');
    // One past its collect-by date is marked, as on Vouchers to hand over.
    assert.deepEqual(lines(owed), [['LEG-0009132', 'collect by 15 Oct 2026 · passed'], ['LEG-0009131', 'collect by 31 Mar 2036']]);
    assert.doesNotMatch(lines(owed).flat().join(' | '), /\bvoucher\b|claim|unlimited/i);
    // A therapy package bought and not claimed yet is not a voucher to hand
    // over: it keeps its own list and "claim by" (Claim, on Purchased), in words.
    const notClaimed = host.querySelector('[data-not-claimed]');
    assert.equal(notClaimed.querySelector('h4').textContent, 'Unclaimed — not yet usable');
    assert.deepEqual(lines(notClaimed), [
      ['UTP-0009021 · unlimited therapy, 3 mo', 'claim by 30 Apr 2027'],
      ['UTP-0009022 · unlimited 1 mo or 10 vouchers — not chosen yet', 'claim by 31 May 2027']]);
    // The server's kind words never stand alone on the card.
    const labels = [...owed.closest('.therapy-detail').querySelectorAll('.therapy-kv .k')].map(k => k.textContent.trim());
    assert.ok(labels.length >= 3, labels.join(' | '));
    for (const label of labels) assert.doesNotMatch(label, /(^|· )(voucher|unlimited|choice)$/, label);
  } finally { await done(); }
});

test('the credit-package form shows what the till lets the credit buy, with no tick boxes and no reward', async () => {
  const { host, done } = await renderPage();
  try {
    await openTab(host, 'Credit Packages');
    await until(() => host.textContent.includes('S$1,000 Credit Package'), 'the Credit Packages tab');
    // No Reward column (the package in the stub still has the reward on).
    const heads = [...host.querySelectorAll('thead th')].map(th => th.textContent.trim());
    assert.deepEqual(heads, ['Name', 'SKU', 'Price', 'Credit', 'Commission', 'Tier 1 / 2', 'Effective', 'Active', '']);
    const pkgRow = [...host.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('S$1,000 Credit Package'));
    assert.equal(pkgRow.querySelectorAll('td').length, heads.length, 'one cell per heading');
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
    // 502: no reward section at all — no threshold, no voucher list, no tick,
    // no reward units — and the package issues Paid Credit and Bonus Credit only.
    for (const gone of ['Reward threshold (S$)', 'Eligible voucher choices *', 'Vouchers listed on this package']) {
      assert.ok(!labels.includes(gone), `no "${gone}" field: ` + labels.join(' | '));
    }
    assert.ok(!labels.some(l => /Also grant/.test(l)), 'no reward tick box: ' + labels.join(' | '));
    assert.ok(!labels.includes('MEOL Voucher'), 'no voucher to tick');
    assert.doesNotMatch(form.textContent, /Reward units|qualification reward|reward threshold/i);
    const issues = [...form.querySelectorAll('div')].find(el => el.firstElementChild?.textContent === 'This package issues');
    assert.ok(issues, 'the This package issues box');
    assert.deepEqual([...issues.children].map(el => el.textContent.replace(/\s+/g, ' ').trim()), [
      'This package issues',
      'Paid Credit S$1000.00, spendable on therapy session',
      'Bonus Credit S$50.00, spendable on own product, third party product',
      'The full credit and bonus are issued even if the package is discounted or made FOC. Commission is earned only on money actually paid.',
    ]);
    assert.equal(lastCall('credit_package_effective_rules').args.p_package_id, 'cp1');

    // Save sends the hidden threshold and voucher list back exactly as they were
    // read, and switches the reward off.
    const from = calls().length;
    await click(button(host.querySelector('.modal-footer'), 'Save'));
    await until(() => calls().slice(from).some(c => c.name === 'set_catalogue_reward'), 'the save');
    const upsert = calls().slice(from).find(c => c.name === 'upsert_credit_package').args;
    assert.equal(upsert.p_id, 'cp1');
    assert.equal(upsert.p_reward_qualifying_amount, 994, 'the threshold, as read');
    assert.deepEqual(upsert.p_voucher_ids, ['vc-meol'], 'the voucher list, as read');
    assert.ok(!('p_grants_reward' in upsert));
    assert.deepEqual(calls().slice(from).find(c => c.name === 'set_catalogue_reward').args,
      { p_kind: 'credit_package', p_id: 'cp1', p_grants: false });
    await until(() => !host.querySelector('.modal'), 'the window closes');

    // A new package: nothing to send back, and the reward is switched off too
    // (the column's default would switch it on), on the new package itself:
    // the stub gives it the id 'cp-new', so the id the save goes on with is
    // the one upsert_credit_package returned, not the package edited above.
    const fromNew = calls().length;
    await click(button(host, 'New Package'));
    await until(() => host.querySelector('.modal'), 'the new package window');
    await setValue([...host.querySelectorAll('.modal .form-group')].find(g => g.querySelector('label')?.textContent === 'Package name *').querySelector('input'),
      'Fixture Credit Package');
    await click(button(host.querySelector('.modal-footer'), 'Save'));
    await until(() => calls().slice(fromNew).some(c => c.name === 'set_catalogue_reward'), 'the new package save');
    const created = calls().slice(fromNew).find(c => c.name === 'upsert_credit_package').args;
    assert.equal(created.p_id, null);
    assert.equal(created.p_reward_qualifying_amount, null);
    assert.equal(created.p_voucher_ids, null);
    assert.equal(calls().slice(fromNew).find(c => c.name === 'set_catalogue_sku').args.p_id, 'cp-new', 'the SKU goes on the new package');
    assert.deepEqual(calls().slice(fromNew).find(c => c.name === 'set_catalogue_reward').args,
      { p_kind: 'credit_package', p_id: 'cp-new', p_grants: false });
  } finally { await done(); }
});

test('the Premium Bundle form is unchanged: free vouchers, a threshold falling back to 994, and the reward tick', async () => {
  const { host, done } = await renderPage();
  try {
    await openTab(host, 'Premium Bundles');
    await click(button(host, 'New Bundle'));
    await until(() => host.querySelector('.modal'), 'the bundle window');
    const form = host.querySelector('.modal');
    const field = label => [...form.querySelectorAll('.form-group')].find(g => g.querySelector('label')?.textContent === label);
    assert.equal(field('Free vouchers')?.querySelector('input').getAttribute('placeholder'), 'auto from payment');
    assert.equal(field('Reward threshold (S$)')?.querySelector('input').getAttribute('placeholder'), '994');
    assert.ok(field('Eligible voucher choices *'), 'the voucher list');
    const tick = [...form.querySelectorAll('label')].find(l => l.textContent.trim() === 'Also grant free reward vouchers')?.querySelector('input');
    assert.ok(tick, 'the reward tick');
    assert.equal(tick.checked, false, 'off by default');
    await setValue(field('Bundle name *').querySelector('input'), 'Fixture Bundle');
    await act(async () => { tick.click(); });
    assert.equal(tick.checked, true);
    const from = calls().length;
    await click(button(host.querySelector('.modal-footer'), 'Save'));
    await until(() => calls().slice(from).some(c => c.name === 'set_catalogue_reward'), 'the save');
    assert.equal(calls().slice(from).find(c => c.name === 'upsert_premium_bundle').args.p_reward_qualifying_amount, null,
      'a blank threshold is sent blank (the server falls back to 994)');
    assert.deepEqual(calls().slice(from).find(c => c.name === 'set_catalogue_reward').args,
      { p_kind: 'premium_bundle', p_id: 'pb1', p_grants: true });
  } finally { await done(); }
});

test('Holidays holds the holiday calendars and the expiry recalculation preview, and nothing else', async () => {
  const { host, done } = await renderPage();
  try {
    await openTab(host, 'Holidays');
    await until(() => host.querySelector('[data-holiday-calendars]'), 'the Holidays tab');
    assert.equal(host.querySelector('[data-holiday-calendars] h3').textContent, 'Holiday calendars and company closures');
    assert.deepEqual([...host.querySelectorAll('summary')].map(s => s.textContent.trim()), ['Expiry recalculation preview']);
    assert.match(host.textContent.replace(/\s+/g, ' '),
      /each one that falls on a Monday to Saturday inside a running period adds one day to its end\. Sundays add nothing/);
    const buttons = buttonsIn(host);
    for (const gone of ['New Rule', 'Re-check paid days', 'Show']) assert.ok(!buttons.includes(gone), `no "${gone}" button`);
    assert.doesNotMatch(host.textContent, /Affiliate residual by day|Unclaimed entitlements and their reward options|is not fully configured/);
    // The recalculation names its sources Purchased and Reward, never the server's 'legacy'.
    const recalcRow = no => [...host.querySelectorAll('details tbody tr')].find(tr => tr.textContent.includes(no));
    await until(() => recalcRow('ENT-000733'), 'the recalculation preview');
    assert.equal(recalcRow('PTE-000412').querySelectorAll('td')[2].textContent, 'Purchased');
    assert.equal(recalcRow('ENT-000733').querySelectorAll('td')[2].textContent, 'Reward');
    assert.doesNotMatch(host.querySelector('details').textContent, /legacy/i);
  } finally { await done(); }
  for (const [role, has] of [['manager', true], ['staff', false]]) {
    const { host: h, done: d2 } = await renderPage(role);
    try { assert.equal(!!tabBtn(h, 'Holidays'), has, `${role}: Holidays ${has ? 'shown' : 'not shown'}`); }
    finally { await d2(); }
  }
});

test('no tab, window or row names Legacy or Qualification, and none of their functions is called', async () => {
  const { host, done } = await renderPage();
  const clean = where => assert.doesNotMatch(host.textContent, /Legacy|Qualification/, where);
  try {
    // The holdings: the old reward's vouchers are an "Earlier reward", and its
    // used free month is not listed.
    await until(() => host.querySelector('.therapy-row-button'), 'the holdings');
    await click([...host.querySelectorAll('.therapy-row-button')].find(b => b.textContent.includes('Preview Customer A')));
    await until(() => host.textContent.includes('PTE-000412'), 'the customer\'s detail');
    const chips = [...host.querySelectorAll('.therapy-chip-source')].map(c => c.textContent);
    assert.ok(chips.includes('Earlier reward'), 'the old source name reads Earlier reward: ' + chips.join(', '));
    assert.ok(chips.includes('Premium bundle'), 'other sources keep their names');
    assert.doesNotMatch(host.textContent, /LEG-0009081|unlimited \(per month\)/, 'the old free month is not listed');
    clean('Purchased');

    for (const label of tabLabels(host).slice(1)) {
      await openTab(host, label);
      await tick(); await tick();
      clean(label);
      if (label === VOUCHERS_TAB) {
        await showFilter(host, 'All');
        clean(`${label}, All`);
      }
      if (label === 'Credit Packages') {
        const pkgRow = [...host.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('S$1,000 Credit Package'));
        await click(pkgRow.querySelector('button.btn-icon'));
        await until(() => host.querySelector('[data-credit-rules]')?.textContent.includes('therapy session'), 'the rules');
        clean('the Credit Package window');
        await click(button(host.querySelector('.modal-footer'), 'Cancel'));
      }
      if (label === 'Premium Bundles') {
        await click(button(host, 'New Bundle'));
        clean('the Premium Bundle window');
        await click(button(host.querySelector('.modal-footer'), 'Cancel'));
      }
      if (label === 'Packages') {
        await click(button(host, 'New Package'));
        clean('the Therapy Package window');
        await click(button(host.querySelector('.modal-footer'), 'Cancel'));
      }
    }

    const names = new Set(calls().map(c => c.name));
    for (const fn of ['legacy_setup_status', 'affiliate_legacy_day_summary', 'backfill_legacy_qualification', 'upsert_legacy_rule',
      'claim_legacy_therapy', 'legacy_reward_options', 'legacy_reward_options_diagnostic', 'legacy_reward_voucher_options',
      'therapy_reward_mapping_preview', 'therapy_map_entitlement_tier']) {
      assert.ok(!names.has(fn), `${fn} is not called`);
    }
    const tables = calls().filter(c => c.name === 'from').map(c => c.args.table);
    assert.ok(tables.includes('credit_packages'), 'the page\'s own reads are recorded: ' + tables.join(', '));
    assert.ok(!tables.includes('therapy_package_rules'), 'the old rules are not read');
    assert.ok(!calls().some(c => c.name === 'therapy_list_page' && c.args.p_tab === 'legacy'), 'nor the old list');
  } finally { await done(); }
});
