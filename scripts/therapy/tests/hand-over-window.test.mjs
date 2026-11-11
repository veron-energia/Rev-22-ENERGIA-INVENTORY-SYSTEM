// The hand-over window (Therapy → Vouchers to hand over → Vouchers) uses the
// list's words in every state it opens in (502, the user, 10 Nov 2026): "Hand
// over vouchers", Owed / Handed over / Left / Withdrawn, "collect by", and
// "reward". The window's own text never says claim, claimed, entitled or
// entitlement. The quantity step keeps its "collect" words, and the window
// works as before: the same calls, the same steps, the same refusals.
//
// src/components/therapy/VoucherClaimPanel.tsx is bundled with esbuild and
// mounted in jsdom against a fake Supabase client (scripts/ui/page-harness.mjs)
// that answers entitlement_voucher_state and claim_entitlement_vouchers. Every
// name and number is made up.
//
// Run: node --test scripts/therapy/tests/hand-over-window.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, driver, fakeSupabase } from '../../ui/page-harness.mjs';

const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { VoucherClaimPanel } from './src/components/therapy/VoucherClaimPanel';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`);
const { React, VoucherClaimPanel } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });

// A Premium Bundle's free vouchers, 3 of 10 handed over, as
// entitlement_voucher_state returns them.
const STATE = {
  entitlement_id: 'r1', entitlement_no: 'LEG-0001001', package_name: 'Premium bundle reward — Made-up Bundle',
  entitled: 10, claimed: 3, revoked: 0, remaining: 7, claim_deadline: '2027-03-31', deadline_passed: false,
  status: 'pending_activation', cancelled: false, snapshot_present: true, blocked_reason: null, owner_or_manager_only: false,
  eligible: [{ voucher_id: 'v1', name: 'Made-up Voucher', available: 20, still_offered: true }],
};

async function open(state, { fail, claim } = {}) {
  const backend = fakeSupabase({
    rpc: { entitlement_voucher_state: () => state, claim_entitlement_vouchers: claim ?? (() => null) },
    fail: fail ? { entitlement_voucher_state: fail } : {},
  });
  globalThis.__supabase = backend;
  await d.mount(React.createElement(VoucherClaimPanel, { entitlementId: 'r1', canClaim: true, onClose() {} }));
  return backend;
}
const dialog = () => document.querySelector('[role="dialog"]');
const words = el => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
const tally = () => [...document.querySelectorAll('.voucher-claim-tally > div')].map(t => t.textContent);
const hint = () => words(document.querySelector('.voucher-claim-tally + .credit-rules-hint'));
/** The window's own words: never claim or entitlement (each test's server says neither). */
const plain = where => assert.doesNotMatch(words(dialog()), /claim|entitle/i, where);
/** Whether the window lets anyone go on to hand vouchers over. */
const offersHandOver = () => !!document.querySelector('#vc-wanted') || !!d.button('Choose vouchers');

test('open on a reward with vouchers left: the list\'s words, and the quantity step keeps "collect"', async () => {
  await open(STATE);
  assert.equal(document.querySelector('#vc-title').textContent, 'Hand over vouchers — LEG-0001001');
  assert.deepEqual(tally(), ['10Owed', '3Handed over', '7Left'], 'no Withdrawn when nothing was withdrawn');
  assert.equal(hint(), 'Premium bundle reward — Made-up Bundle · collect by 31 Mar 2027');
  // The quantity step, word for word as before.
  assert.equal(words(document.querySelector('.vc-step-title')), 'How many vouchers would you like to collect today?');
  assert.deepEqual([...document.querySelectorAll('.vc-facts dt')].map(dt => dt.textContent),
    ['From', 'Reference', 'Total allowance', 'Already collected', 'Still available', 'Collect by']);
  assert.match(words(document.querySelector('.vc-quantity-label')), /^Number to collect now/);
  assert.equal(words(document.querySelector('#vc-wanted-help')), 'A whole number between 1 and 7. Whatever is left stays collectable until the deadline.');
  assert.ok(d.button('Choose vouchers'), 'it goes on to choose the vouchers');
  plain('open');
});

test('handing two over: "Handed over 2", the document, and nothing more owed on it; the same call as before', async () => {
  const backend = await open(STATE, { claim: () => ({ claimed_now: 2, invoice_no: 'VC-MADEUP-0001' }) });
  await d.setValue(document.querySelector('#vc-wanted'), '2');
  await d.click(d.button('Choose vouchers'));
  assert.equal(words(document.querySelector('.vc-step-title')), 'Which vouchers, and how many of each?');
  await d.setValue(document.querySelector('.voucher-claim-table tbody input'), '2');
  await d.click(d.button('Collect 2'));
  assert.equal(words(document.querySelector('.voucher-claim-done')),
    'Handed over 2. Document VC-MADEUP-0001. It records the hand-over only — no payment, and nothing further is owed on it.');
  assert.deepEqual(backend.calls.filter(c => c.rpc === 'claim_entitlement_vouchers').map(c => c.args),
    [{ p_entitlement_id: 'r1', p_selections: [{ voucher_id: 'v1', quantity: 2 }], p_note: null }]);
  plain('after a hand-over');
});

test('a reward that could not be loaded says so, and that nothing was handed over', async () => {
  await open(STATE, { fail: 'Made-up failure' });
  const alert = words(document.querySelector('[role="alert"]'));
  assert.ok(alert.startsWith('This reward could not be loaded. Made-up failure'), alert);
  assert.ok(alert.includes('Nothing has been handed over.'), alert);
  assert.ok(d.button('Try again'), 'it can be read again');
  assert.equal(document.querySelector('#vc-title').textContent, 'Hand over vouchers');
  plain('could not be loaded');
});

test('a reward from before the record of its vouchers: "This reward predates…"', async () => {
  await open({ ...STATE, snapshot_present: false });
  assert.ok(words(dialog()).includes('This reward predates the record of which vouchers it was sold with, so any '
    + 'free-session reward voucher can be chosen. Check it against the original purchase first.'), words(dialog()));
  assert.ok(offersHandOver(), 'it can still be handed over, after a check');
  plain('no voucher record');
});

test('a cancelled reward: nothing can be handed over on it, and the owed figure is for reference', async () => {
  await open({ ...STATE, cancelled: true, status: 'cancelled', claimed: 3, revoked: 7, remaining: 0 });
  assert.deepEqual(tally(), ['10Owed', '3Handed over', '0Left', '7Withdrawn']);
  assert.ok(words(dialog()).includes('This reward was cancelled, so nothing can be handed over on it. '
    + 'The owed figure is shown for reference only.'), words(dialog()));
  assert.ok(!offersHandOver(), 'nothing to hand over');
  plain('cancelled');
});

test('past its collect-by date: says so, and nothing can be handed over', async () => {
  await open({ ...STATE, claim_deadline: '2026-10-01', deadline_passed: true });
  assert.equal(hint(), 'Premium bundle reward — Made-up Bundle · collect by 1 Oct 2026 — the collect-by date has passed');
  assert.equal(words(document.querySelector('p.credit-rules-warn')), 'The collect-by date has passed. Nothing can be handed over.');
  assert.ok(!offersHandOver(), 'nothing to hand over');
  plain('collect-by date passed');
});

test('nothing left: "Nothing left to hand over on this reward."', async () => {
  await open({ ...STATE, claimed: 10, remaining: 0, status: 'active' });
  assert.deepEqual(tally(), ['10Owed', '10Handed over', '0Left']);
  assert.deepEqual([...document.querySelectorAll('p.credit-rules-hint')].map(words),
    ['Premium bundle reward — Made-up Bundle · collect by 31 Mar 2027', 'Nothing left to hand over on this reward.']);
  assert.ok(!offersHandOver(), 'nothing to hand over');
  plain('nothing left');
});

test('a closed sale: its reason, and nothing can be handed over (words unchanged)', async () => {
  await open({ ...STATE, blocked_reason: 'Invoice INV-MADEUP-1 was deleted' });
  assert.equal(words(document.querySelector('p.credit-rules-warn[role="status"]')),
    'Invoice INV-MADEUP-1 was deleted, so nothing can be handed over on this reward.');
  assert.ok(!offersHandOver(), 'nothing to hand over');
  plain('closed sale');
});

test('no voucher choices recorded: "No voucher choices are recorded for this reward."', async () => {
  await open({ ...STATE, eligible: [] });
  await d.setValue(document.querySelector('#vc-wanted'), '1');
  await d.click(d.button('Choose vouchers'));
  assert.equal(words(document.querySelector('.voucher-claim-table .vc-note')), 'No voucher choices are recorded for this reward.');
  assert.ok(d.button('Collect 1').disabled, 'nothing can be chosen, so nothing is handed over');
  plain('no voucher choices');
});
