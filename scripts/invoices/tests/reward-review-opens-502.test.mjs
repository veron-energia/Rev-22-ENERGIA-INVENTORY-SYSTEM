// 502 (the user, 10 Nov 2026): the server's refusal to refund an older Credit
// Package sale whose reward vouchers are still outstanding has new words
// (assert_invoice_credit_source_evidence, as 502 rewords it). The invoice's
// settlement panel (InvoiceFinancePanel) opens the reward voucher review on
// that refusal, so the refund has a way forward instead of a dead end. This
// test is the link between the two: the panel is driven with real React and
// DOM events against a stubbed Supabase client whose refund and cancellation
// fail with the server's exact words, the new ones and the old ones (a
// database before 502, or a page loaded before it), and a refusal about
// anything else opens no review.
//
// The panel refunds in two places, and the refusal can reach either: "Record
// refund paid" on a cancelled invoice, and the line-by-line refund it hands
// over to when the purchase's credit was issued. Since 409 the panel has no
// cancellation of its own (the guided Refund / Cancel dialog settles reward
// vouchers in its plan, 417); the stub refuses cancel_invoice_recorded with the
// same words all the same.
//
// The 502 SQL suite checks that the server's refusal carries REFUSAL_PHRASE
// below: keep the two the same.
// Fixtures only: every number, name and amount is made up.
//
// Run: node --test scripts/invoices/tests/reward-review-opens-502.test.mjs
// A device outside Singapore: every day the review shows must be Singapore's.
process.env.TZ = 'America/Los_Angeles';
import { JSDOM } from 'jsdom';
import { build, stop } from 'esbuild';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

/** The words the page opens the review on. The 502 SQL suite checks that the
 *  server's refusal has the same phrase. */
const REFUSAL_PHRASE = 'reward vouchers that are still outstanding';
/** The refusal since 502, exactly as the server raises it. */
const REFUSAL_502 = `This Credit Package came with ${REFUSAL_PHRASE}. Review them and record what should happen to them, `
  + 'then refund or cancel. Vouchers not handed over yet are withdrawn; those already handed over stay with the customer.';
/** The refusal before 502 (291), which the page must still answer. */
const REFUSAL_291 = 'This package granted qualification reward entitlements that are still outstanding. Review them and record '
  + 'what should happen to them, then refund or cancel — unclaimed ones are withdrawn and claimed ones keep their history.';
/** The server's answer to "Record refund paid" when the purchase's credit was issued (409). */
const BY_LINE = 'Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment';
/** Refusals that must open no review: the same server check's other refusal,
 *  502's other two reward texts (the permission refusal of the review itself,
 *  and the benefit review's note), and one about the amount. */
const UNRELATED = [
  'Historical bonus-credit provenance is unresolved. Review the original bonus lot or documented no-bonus decision before allocating, refunding or moving this purchase.',
  'Only an Owner or Manager can settle reward vouchers',
  'This Credit Package came with reward vouchers. Review their original hand-over records first; credit-only allocations cannot complete this purchase.',
  'Amount exceeds the correction refund due',
];

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>',
  { url: 'https://tests.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'Element', 'Node', 'Event',
                 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame',
                 'cancelAnimationFrame']) {
  try { globalThis[k] = dom.window[k]; }
  catch { Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true }); }
}
// The review scrolls itself into view; jsdom lays nothing out.
dom.window.Element.prototype.scrollIntoView = function scrollIntoView() {};
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
if (!globalThis.crypto?.randomUUID) {
  globalThis.crypto = { ...(globalThis.crypto ?? {}), randomUUID: () => 'req-' + Math.random().toString(16).slice(2) };
}

// A cancelled S$1,000 Credit Package sale that still holds the S$1,000 paid.
const cancelledPackage = () => ({
  financial: { status: 'cancelled', total: 1000, net_received: 1000, outstanding: 0, refund_due: 1000, refunded: 0,
               overpayment_refundable: 0 },
  sources: [{ payment_id: 'P502', method: 'Bank transfer', wallet: false, remaining: 1000 }],
  benefits: [], stock: [], review_required: false,
  lines: [{ invoice_item_id: 'L502', name: 'Fixture Credit Package', remaining: 1000, line_kind: 'credit_package' }],
});
// What the cancellation returns, line by line (the line-by-line form's prefill).
const cancelPlan = { refund_due: 1000, lines: [{ invoice_item_id: 'L502', amount: 1000, benefits: [] }],
  sources: [{ payment_id: 'P502', amount: 1000 }] };
// The two rewards it came with: one not handed over yet, one partly handed
// over (first on 1 Sep, last at 00:30 on 15 Sep in Singapore, which is still
// 14 Sep in Los Angeles and in UTC).
const reward = over => ({ sale_id: 'S502', invoice_item_id: 'L502', package_name: 'Fixture Credit Package', reward_units: 2,
  status: 'pending_activation', activation_date: null, claimed_at: null, resolved_at: null, ...over });
const REWARDS = [
  reward({ entitlement_id: 'E1', entitlement_no: 'LEG-9050201', disposition: 'withdrawable' }),
  reward({ entitlement_id: 'E2', entitlement_no: 'LEG-9050202', disposition: 'consumed',
           activation_date: '2026-09-01', claimed_at: '2026-09-14T16:30:00Z' }),
];

const calls = [];
const ok = data => Promise.resolve({ data, error: null });
const fail = message => Promise.resolve({ data: null, error: { message } });
const stub = {
  options: null, plan: null, rewards: REWARDS,
  /** What the refund and the cancellation fail with; null: they go through. */
  refusal: null,
  /** "Record refund paid" (one line without an item) meets the purchase's issued credit first. */
  byLineFirst: false,
  // A query of any shape: awaited or ordered, it is empty.
  from: () => {
    const q = { select: () => q, eq: () => q, is: () => q,
      order: () => Promise.resolve({ data: [], error: null }),
      then: (res, rej) => Promise.resolve({ data: [], error: null }).then(res, rej) };
    return q;
  },
  rpc: (name, args) => {
    calls.push({ name, args });
    switch (name) {
      case 'invoice_refund_options': return ok(stub.options);
      case 'invoice_action_plan': return ok(stub.plan);
      case 'invoice_rentals_awaiting_return': return ok([]);
      case 'invoice_credit_reward_entitlements': return ok(stub.rewards);
      case 'resolve_invoice_credit_rewards': return ok({ withdrawn: 1, consumed: 1 });
      case 'refund_invoice_recorded':
      case 'cancel_invoice_recorded':
        if (stub.byLineFirst && name === 'refund_invoice_recorded' && args.p_lines?.[0]?.invoice_item_id === null) return fail(BY_LINE);
        return stub.refusal ? fail(stub.refusal) : ok({ success: true });
      default: return ok(null);
    }
  },
};

const built = await build({
  stdin: {
    contents: `
      export { InvoiceFinancePanel } from './src/components/invoices/InvoiceFinancePanel';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react-dom/test-utils';
      export { default as React } from 'react';`,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic',
  loader: { '.css': 'empty' },
  define: { 'process.env.NODE_ENV': '"development"' },
  plugins: [{ name: 'stub', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 'st' }));
    b.onLoad({ filter: /.*/, namespace: 'st' }, () => ({
      contents: 'export const supabase = globalThis.__supabase;', loader: 'js' }));
  } }],
});
// esbuild's service would keep the process alive once the tests are done.
await stop();
globalThis.__supabase = stub;
const { InvoiceFinancePanel, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const root = createRoot(document.getElementById('root'));
const flush = async () => { for (let i = 0; i < 3; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
let scenario = 0; let changed = 0;
// The panel as the invoice footer's "Record refund paid" opens it, for an Owner or Manager.
const render = async () => {
  scenario += 1;
  await act(async () => {
    root.render(React.createElement(InvoiceFinancePanel, {
      key: `s-${scenario}`, invoiceId: 'INV-502', canManage: true, payments: [], methods: [], stores: [],
      requestedMode: 'refund_due', onRequestHandled: () => {}, onChanged: async () => { changed++; } }));
  });
  await flush();
};
const text = () => document.body.textContent;
const byText = (tag, s) => Array.from(document.querySelectorAll(tag)).find(e => e.textContent.includes(s));
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await flush(); };
const type = async (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set;
  await act(async () => { setter.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  await flush();
};
const tick = async el => { await act(async () => { el.click(); }); await flush(); };
// Asserted as true or false, never as an element: a failed assert would
// print the element, and with it the whole jsdom window.
const review = () => document.querySelector('[aria-label="Reward voucher review"]');
const refunds = () => calls.filter(c => c.name === 'refund_invoice_recorded');
const recordRefundPaid = () => Array.from(document.querySelectorAll('button')).find(b => /refund paid$/.test(b.textContent));

/** A fresh panel on the cancelled sale, its refund refused with `refusal`. */
const start = async (refusal, { byLineFirst = false } = {}) => {
  calls.length = 0;
  Object.assign(stub, { options: cancelledPackage(), plan: cancelPlan, rewards: REWARDS, refusal, byLineFirst });
  await render();
};
/** "Record refund paid": the reason, the tick, the button. */
const recordRefundPaidWith = async reason => {
  await type(document.querySelector('.form-grid textarea'), reason);
  await tick(byText('label', 'has actually').querySelector('input'));
  const button = recordRefundPaid();
  assert.ok(button && !button.disabled, 'Record refund paid can be pressed: ' + button?.textContent);
  await click(button);
};
/** The line-by-line refund "Record refund paid" hands over to, prefilled as the cancellation returns it. */
const refundLineByLine = async () => {
  await recordRefundPaidWith('Paid back by bank transfer');
  assert.ok(text().includes(BY_LINE), 'the issued credit sends the refund line by line');
  assert.ok(!review(), 'that refusal opens no reward review');
  await click(byText('button', 'Allocate it line by line instead'));
  assert.equal(Number(document.querySelector('input[aria-label^="Fixture Credit Package"]')?.value), 1000, 'the line, prefilled');
  assert.equal(Number(document.querySelector('input[aria-label^="Bank transfer"]')?.value), 1000, 'the payment, prefilled');
  await type(document.querySelector('.form-grid textarea'), 'Paid back by bank transfer');
  await tick(byText('label', 'I confirm the actual money/credit returned').querySelector('input'));
  await click(byText('button', 'Record with audit history'));
};
/** The review is open, says what it is about, and has read this invoice's rewards. */
const assertReviewOpens = (refusal, how) => {
  assert.ok(text().includes(refusal), `${how}: the server's refusal is shown as it came`);
  const r = review();
  assert.ok(r, `${how}: the reward voucher review opens`);
  assert.match(r.textContent, /This Credit Package came with reward vouchers/, how);
  assert.ok(calls.some(c => c.name === 'invoice_credit_reward_entitlements' && c.args.p_invoice_id === 'INV-502'),
    `${how}: the review reads this invoice's rewards`);
};

test('the refusal since 502 opens the reward voucher review from "Record refund paid" on a cancelled sale', async () => {
  assert.ok(REFUSAL_502.includes(REFUSAL_PHRASE));
  await start(REFUSAL_502);
  await recordRefundPaidWith('Paid back by bank transfer');
  assert.equal(refunds().length, 1, 'one refund was sent, and refused');
  assertReviewOpens(REFUSAL_502, 'Record refund paid');
});

test('and from the line-by-line refund that "Record refund paid" hands over to', async () => {
  await start(REFUSAL_502, { byLineFirst: true });
  await refundLineByLine();
  const sent = refunds().at(-1);
  assert.equal(JSON.stringify(sent?.args.p_lines?.map(l => [l.invoice_item_id, l.amount])), '[["L502",1000]]', 'the line-by-line refund was sent');
  assertReviewOpens(REFUSAL_502, 'line by line');
});

test('the refusal before 502 (an older database or page) opens the same review, from both', async () => {
  await start(REFUSAL_291);
  await recordRefundPaidWith('Paid back by bank transfer');
  assertReviewOpens(REFUSAL_291, 'Record refund paid, old words');
  await start(REFUSAL_291, { byLineFirst: true });
  await refundLineByLine();
  assertReviewOpens(REFUSAL_291, 'line by line, old words');
});

test('the review says what happens to each reward in plain words, and the refund goes ahead once the decision is recorded', async () => {
  changed = 0;
  await start(REFUSAL_502);
  await recordRefundPaidWith('Paid back by bank transfer');
  const r = review();
  assert.ok(r, 'the review is open');
  const said = r.textContent;
  assert.match(said, /When it was sold it came with free vouchers for the customer\. Decide what happens to them before the refund or cancellation\. Nothing is changed until you confirm\./);
  const line = no => Array.from(r.querySelectorAll('.invoice-evidence-line')).find(l => l.textContent.includes(no))?.textContent ?? '';
  assert.match(line('LEG-9050201'), /Not handed over — will be withdrawn/);
  assert.match(line('LEG-9050201'), /Status: to hand over$/);
  assert.match(line('LEG-9050202'), /Handed over \(some or all\) — stays with the customer/);
  assert.match(line('LEG-9050202'), /Status: to hand over · first handed over 1\/9\/2026 · last handed over 15\/9\/2026$/,
    'the days are Singapore\'s, whatever the device\'s time zone');
  assert.match(said, /1 reward not handed over yet will be withdrawn\. Any vouchers already issued against them are revoked and their stock returned\./);
  assert.match(said, /I understand 1 reward has already had vouchers handed over\. Those vouchers stay with the customer, and the history is kept\./);
  assert.doesNotMatch(said, /Legacy|[Qq]ualification|entitlement|claimed|activated/, 'no old word in the review');

  const record = byText('button', 'Record this decision and continue');
  assert.ok(record.disabled, 'not before the box is ticked');
  assert.equal(record.title, 'Tick the box above first.');
  await type(r.querySelector('input:not([type="checkbox"])'), 'Customer returned the package');
  await tick(r.querySelector('.invoice-evidence-confirm input'));
  assert.equal(byText('button', 'Record this decision and continue').disabled, false);
  await click(byText('button', 'Record this decision and continue'));
  const resolved = calls.filter(c => c.name === 'resolve_invoice_credit_rewards');
  assert.equal(resolved.length, 1, 'the decision is recorded once');
  assert.equal(resolved[0].args.p_invoice_id, 'INV-502');
  assert.equal(resolved[0].args.p_reason, 'Customer returned the package');
  assert.equal(resolved[0].args.p_acknowledge_consumed, true, 'with the handed-over reward acknowledged');
  assert.ok(resolved[0].args.p_request_id, 'as one request');
  assert.ok(!review(), 'the review closes');
  assert.ok(text().includes('The decision on the reward vouchers is recorded. Now try again.'));

  // The server now lets the refund through: the same request, with what was entered kept.
  stub.refusal = null;
  await click(recordRefundPaid());
  const tries = refunds();
  assert.equal(tries.length, 2, 'the refund is sent again');
  assert.equal(tries[1].args.p_request_id, tries[0].args.p_request_id, 'as the same request, so it can never be recorded twice');
  assert.equal(tries[1].args.p_reason, 'Paid back by bank transfer');
  assert.equal(changed, 1, 'and the invoice is reloaded');
});

test('a refusal about anything else opens no review', async () => {
  for (const refusal of UNRELATED) {
    await start(refusal);
    await recordRefundPaidWith('Paid back by bank transfer');
    assert.ok(text().includes(refusal), `${refusal}: shown as it came`);
    assert.ok(!review(), `${refusal}: no reward voucher review`);
    assert.ok(!calls.some(c => c.name === 'invoice_credit_reward_entitlements'), `${refusal}: no rewards read`);
  }
});

// The 502 migration raises the refusal the page opens the review on. Checked
// here only while 502 is in this checkout; the 502 SQL suite checks it in the
// database.
const mig502 = readdirSync('supabase').find(f => /^502_.*\.sql$/.test(f));
test('the 502 migration raises the refusal with the phrase the page opens the review on',
  { skip: mig502 ? false : 'no supabase/502_*.sql in this checkout yet' }, () => {
    const sql = readFileSync(`supabase/${mig502}`, 'utf8');
    assert.match(sql, /'This Credit Package came with reward vouchers that are still outstanding\./);
    assert.ok(sql.includes(REFUSAL_PHRASE));
  });

// Once every test has run: unmount and close the window. React's act, bundled
// here, schedules its work through MessageChannel ports, which would keep the
// process alive (as in reopen-dialog-478.test.mjs): they are let go.
test.after(async () => {
  await act(async () => { root.unmount(); });
  dom.window.close();
  for (const h of process._getActiveHandles?.() ?? []) if (h?.constructor?.name === 'MessagePort') h.unref?.();
});
