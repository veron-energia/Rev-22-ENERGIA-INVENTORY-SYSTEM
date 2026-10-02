// The credit balance printed on the invoice, and the Total Paid beside it.
//
// Owner's decisions, 2 Oct 2026: the printed invoice and the PDF/image copy
// show the customer's wallet credit as it stands when printed — a total and
// each kind they hold — whenever the customer holds credit or the invoice was
// paid from their wallet. Never on a cancelled or refunded invoice, and never
// at the cost of the invoice printing. Invented customers and amounts only.
import test from 'node:test';
import assert from 'node:assert/strict';
// Run as a browser in Los Angeles would, so a date taken from the machine's own
// time zone instead of Singapore's cannot pass by luck.
process.env.TZ = 'America/Los_Angeles';
const {
  WALLET_KINDS, signedPaymentAmount, paymentsTotal, paidWithWalletCredit, singaporeDateLabel,
  shouldShowCreditBalance, creditBalanceLine, creditBalanceHtml, creditBalanceForInvoice,
  readCreditBalanceForInvoice, isCreditAccessRefusal, wrapCreditDetail, CREDIT_KIND_SEPARATOR,
} = await import('../../../src/lib/invoices/creditBalanceLine.mjs');

// 1 Oct 2026, 17:30 UTC — already 2 Oct in Singapore (01:30).
const LATE_EVENING_UTC = new Date('2026-10-01T17:30:00Z');
const balance = (cats, extra = {}) => ({
  customer_id: 'cust-a',
  categories: { paid: 0, bonus: 0, legacy: 0, promotional: 0, exchange: 0, ...cats },
  available_total: Object.values(cats).reduce((s, v) => s + v, 0),
  ...extra,
});
const ok = data => () => Promise.resolve({ data, error: null });
const receipt = (method, amount, extra = {}) => ({ payment_method_id: method, amount, entry_kind: 'receipt', ...extra });
const reversal = (method, amount) => ({ payment_method_id: method, amount, entry_kind: 'correction_reversal' });
const replacement = (method, amount) => ({ payment_method_id: method, amount, entry_kind: 'correction_replacement' });
const WALLET = ['wallet-paid', 'wallet-bonus'];
const base = (over = {}) => ({
  invoice: { customer_id: 'cust-a', status: 'paid' }, payments: [receipt('cash', 100)],
  walletMethodIds: WALLET, now: LATE_EVENING_UTC, ...over,
});

// ---- Total Paid ------------------------------------------------------------

test('Total Paid matches the payment rows: a correction reversal counts against', () => {
  // The bug found on 2 Oct: S$3,000 taken, reversed and replaced with S$500
  // printed Total Paid S$3,550 while the rows read 3,000 − 3,000 + 500 + 50.
  const pays = [receipt('cash', 3000), reversal('cash', 3000), replacement('bank', 500), receipt('cash', 50)];
  assert.equal(paymentsTotal(pays), 550);
  assert.deepEqual(pays.map(signedPaymentAmount), [3000, -3000, 500, 50]);
});

test('Total Paid adds in cents, so it never drifts by a fraction', () => {
  assert.equal(paymentsTotal([receipt('cash', 0.1), receipt('cash', 0.2)]), 0.3);
  assert.equal(paymentsTotal(Array.from({ length: 10 }, () => receipt('cash', '0.10'))), 1);
  assert.equal(paymentsTotal([]), 0);
  assert.equal(paymentsTotal(null), 0);
});

// ---- Paid from the wallet --------------------------------------------------

test('an invoice paid partly from the wallet counts as paid with credit', () => {
  assert.equal(paidWithWalletCredit([receipt('cash', 50), receipt('wallet-bonus', 20)], WALLET), true);
  assert.equal(paidWithWalletCredit([receipt('cash', 50)], WALLET), false);
  assert.equal(paidWithWalletCredit([receipt('wallet-paid', 50)], []), false, 'no wallet methods known, nothing counts');
});

test('a wallet payment that was reversed and taken another way no longer counts', () => {
  assert.equal(paidWithWalletCredit([receipt('wallet-paid', 80), reversal('wallet-paid', 80), replacement('cash', 80)], WALLET), false);
  assert.equal(paidWithWalletCredit([receipt('wallet-paid', 80), reversal('wallet-paid', 80), replacement('wallet-paid', 30)], WALLET), true);
});

// ---- The date ----------------------------------------------------------------

test('the as-at date is the Singapore date, in the owner\'s form', () => {
  assert.equal(singaporeDateLabel(LATE_EVENING_UTC), '2 Oct 2026');
  assert.equal(singaporeDateLabel(new Date('2026-10-01T15:59:59Z')), '1 Oct 2026', 'one second before midnight in Singapore');
  // Never 'Sept', whatever the locale data says.
  assert.equal(singaporeDateLabel(new Date('2026-09-15T04:00:00Z')), '15 Sep 2026');
  assert.equal(singaporeDateLabel(new Date('2026-12-31T16:00:00Z')), '1 Jan 2027');
});

// ---- The line ---------------------------------------------------------------

test('the line is a total, then each kind the customer holds, in the owner\'s order', () => {
  const line = creditBalanceLine(balance({ exchange: 5, bonus: 50, paid: 300 }), LATE_EVENING_UTC);
  assert.deepEqual(line, {
    label: 'Credit balance (as at 2 Oct 2026)',
    amount: 'S$355.00',
    detail: 'Paid S$300.00 · Bonus S$50.00 · Exchange S$5.00',
  });
  const all = creditBalanceLine(balance({ paid: 1, bonus: 2, legacy: 3, promotional: 4, exchange: 5 }), LATE_EVENING_UTC);
  assert.equal(all.detail, 'Paid S$1.00 · Bonus S$2.00 · Legacy S$3.00 · Promotional S$4.00 · Exchange S$5.00');
  assert.deepEqual(WALLET_KINDS.map(([k]) => k), ['paid', 'bonus', 'legacy', 'promotional', 'exchange']);
});

test('the owner\'s example prints exactly as given', () => {
  const line = creditBalanceLine(balance({ paid: 300, bonus: 50 }), LATE_EVENING_UTC);
  assert.equal(`${line.label}  ${line.amount}`, 'Credit balance (as at 2 Oct 2026)  S$350.00');
  assert.equal(line.detail, 'Paid S$300.00 · Bonus S$50.00');
});

test('a balance of nothing prints S$0.00 with no kinds listed', () => {
  const line = creditBalanceLine(balance({}), LATE_EVENING_UTC);
  assert.equal(line.amount, 'S$0.00');
  assert.equal(line.detail, null);
});

test('amounts arriving as text are read as money', () => {
  const line = creditBalanceLine({ categories: { paid: '12.5', legacy: '0.00' }, available_total: '12.50' }, LATE_EVENING_UTC);
  assert.equal(line.amount, 'S$12.50');
  assert.equal(line.detail, 'Paid S$12.50');
});

test('without a server total the kinds are added up', () => {
  assert.equal(creditBalanceLine({ categories: { paid: 10, bonus: 2.5 } }, LATE_EVENING_UTC).amount, 'S$12.50');
});

test('the printed row escapes what it prints and is empty without a line', () => {
  const html = creditBalanceHtml({ label: 'Credit <b>', amount: 'S$1.00', detail: 'Paid & more' });
  assert.match(html, /Credit &lt;b&gt;/);
  assert.match(html, /Paid&nbsp;&amp;&nbsp;more/);
  assert.doesNotMatch(html, /<b>/);
  assert.equal(creditBalanceHtml(null), '');
  const plain = creditBalanceHtml(creditBalanceLine(balance({}), LATE_EVENING_UTC));
  assert.doesNotMatch(plain, /class="mut/, 'no second line when there are no kinds');
});

test('the printed breakdown can only wrap between kinds', () => {
  const line = creditBalanceLine(balance({ paid: 1234.5, bonus: 250, legacy: 1880, promotional: 120, exchange: 45.6 }), LATE_EVENING_UTC);
  const html = creditBalanceHtml(line);
  const detail = html.match(/<div class="mut credit-detail">(.*?)<\/div>/)[1];
  // A kind's name and amount are held together, and so is the dot to the kind
  // before it; the only places a line may break are after a dot.
  assert.equal(detail,
    'Paid&nbsp;S$1234.50&nbsp;· Bonus&nbsp;S$250.00&nbsp;· Legacy&nbsp;S$1880.00&nbsp;· Promotional&nbsp;S$120.00&nbsp;· Exchange&nbsp;S$45.60');
  assert.equal(detail.split('&nbsp;· ').length, 5);
  for (const kind of detail.split('&nbsp;· ')) assert.doesNotMatch(kind, / /, `"${kind}" can break inside a kind`);
  // The block the print window fits: whole, without its breakdown, or not at all.
  assert.match(html, /^<div class="credit-balance" style="flex:0 1 auto;min-height:0;overflow:hidden">/);
});

test('the PDF and image breakdown wraps between kinds only', () => {
  const detail = 'Paid S$1234.50 · Bonus S$250.00 · Legacy S$1880.00 · Promotional S$120.00 · Exchange S$45.60';
  const width = t => t.length;            // one unit a character
  // 75 characters fit 'Paid … · Bonus … · Legacy … · Promotional S$120.00 · Exchange' but not its amount.
  const lines = wrapCreditDetail(detail, 75, width);
  assert.deepEqual(lines, ['Paid S$1234.50 · Bonus S$250.00 · Legacy S$1880.00 · Promotional S$120.00', 'Exchange S$45.60']);
  assert.equal(lines.join(CREDIT_KIND_SEPARATOR), detail, 'nothing lost');
  for (const ln of lines) assert.ok(width(ln) <= 75, `"${ln}" is too wide`);
  assert.deepEqual(wrapCreditDetail(detail, 1000, width), [detail], 'one line when it fits');
  assert.deepEqual(wrapCreditDetail(detail, 20, width), detail.split(' · '), 'one kind a line when space is short');
  assert.deepEqual(wrapCreditDetail('Promotional S$12345.67', 5, width), ['Promotional S$12345.67'], 'a kind wider than the space is kept whole');
  assert.deepEqual(wrapCreditDetail(null, 10, width), []);
  assert.deepEqual(wrapCreditDetail('', 10, width), []);
});

// ---- When it shows ------------------------------------------------------------

test('it shows when the customer holds credit, or the invoice was paid from the wallet', () => {
  const s = over => shouldShowCreditBalance({ customerId: 'cust-a', status: 'paid', balanceTotal: 0, paidWithWallet: false, ...over });
  assert.equal(s({ balanceTotal: 0.01 }), true);
  assert.equal(s({ paidWithWallet: true }), true, 'even at S$0.00 once the wallet paid for this invoice');
  assert.equal(s({}), false, 'no credit and no wallet payment');
  assert.equal(s({ balanceTotal: 0.004 }), false, 'less than a cent is nothing');
});

test('it never shows without a customer, on a cancelled or refunded invoice, or without a balance', () => {
  const s = over => shouldShowCreditBalance({ customerId: 'cust-a', status: 'paid', balanceTotal: 100, paidWithWallet: true, ...over });
  assert.equal(s({ customerId: null }), false);
  assert.equal(s({ status: 'cancelled' }), false);
  assert.equal(s({ status: 'refunded' }), false);
  assert.equal(s({ balanceTotal: null }), false);
  for (const status of ['unpaid', 'partially_paid', 'paid', 'completed_foc', 'refund_requested', 'cancellation_requested']) {
    assert.equal(s({ status }), true, status);
  }
});

// ---- Reading the balance -------------------------------------------------------

test('the balance is read for the invoice\'s own customer at the moment of printing', async () => {
  const asked = [];
  const line = await creditBalanceForInvoice(base({
    fetchBalances: id => { asked.push(id); return Promise.resolve({ data: balance({ paid: 300, bonus: 50 }), error: null }); },
  }));
  assert.deepEqual(asked, ['cust-a']);
  assert.deepEqual(line, { label: 'Credit balance (as at 2 Oct 2026)', amount: 'S$350.00', detail: 'Paid S$300.00 · Bonus S$50.00' });
});

test('a balance answered for another customer is never printed', async () => {
  const line = await creditBalanceForInvoice(base({ fetchBalances: ok(balance({ paid: 999 }, { customer_id: 'cust-b' })) }));
  assert.equal(line, null);
});

test('S$0.00 prints when the wallet paid for this invoice and nothing is left', async () => {
  const line = await creditBalanceForInvoice(base({ payments: [receipt('wallet-paid', 40), receipt('cash', 60)], fetchBalances: ok(balance({})) }));
  assert.deepEqual(line, { label: 'Credit balance (as at 2 Oct 2026)', amount: 'S$0.00', detail: null });
});

test('no line when the customer holds nothing and the wallet paid nothing', async () => {
  assert.equal(await creditBalanceForInvoice(base({ fetchBalances: ok(balance({})) })), null);
});

test('a cancelled, refunded or customerless invoice does not even ask', async () => {
  let asked = 0;
  const fetchBalances = () => { asked++; return Promise.resolve({ data: balance({ paid: 10 }), error: null }); };
  for (const invoice of [{ customer_id: 'cust-a', status: 'cancelled' }, { customer_id: 'cust-a', status: 'refunded' }, { customer_id: null, status: 'paid' }]) {
    assert.equal(await creditBalanceForInvoice(base({ invoice, fetchBalances })), null);
  }
  assert.equal(asked, 0);
});

test('a refused, failed or slow read prints without the line and never throws', async () => {
  // A role that may not see credit is refused by the server.
  assert.equal(await creditBalanceForInvoice(base({ fetchBalances: () => Promise.resolve({ data: null, error: { message: 'You do not have access to customer credit' } }) })), null);
  assert.equal(await creditBalanceForInvoice(base({ fetchBalances: () => Promise.reject(new Error('offline')) })), null);
  assert.equal(await creditBalanceForInvoice(base({ fetchBalances: () => { throw new Error('no client'); } })), null);
  assert.equal(await creditBalanceForInvoice(base({ fetchBalances: ok(null) })), null);
  // An answer that carries an error is not trusted, whatever data came with it.
  assert.equal(await creditBalanceForInvoice(base({ fetchBalances: () => Promise.resolve({ data: balance({ paid: 5 }), error: { message: 'partial' } }) })), null);
  const started = Date.now();
  const slow = await creditBalanceForInvoice(base({ timeoutMs: 50, fetchBalances: () => new Promise(r => setTimeout(() => r({ data: balance({ paid: 5 }), error: null }), 400)) }));
  assert.equal(slow, null);
  assert.ok(Date.now() - started < 300, 'gave up at the timeout rather than waiting for the answer');
});

test('the page is told when the balance could not be read, never when it was not theirs to read', async () => {
  const read = over => readCreditBalanceForInvoice(base(over));
  const unread = async (over, why) => assert.deepEqual(await read(over), { line: null, unreadable: true }, why);
  const quiet = async (over, why) => assert.equal((await read(over)).unreadable, false, why);
  await unread({ timeoutMs: 30, fetchBalances: () => new Promise(() => {}) }, 'a read that hangs');
  await unread({ fetchBalances: () => Promise.resolve({ data: null, error: { message: 'network down' } }) }, 'an error');
  await unread({ fetchBalances: () => Promise.reject(new Error('offline')) }, 'a rejected read');
  await unread({ fetchBalances: () => { throw new Error('no client'); } }, 'a throw');
  await unread({ fetchBalances: ok(null) }, 'no answer');
  await unread({ fetchBalances: ok(balance({ paid: 9 }, { customer_id: 'cust-b' })) }, 'an answer for another customer');
  await quiet({ fetchBalances: () => Promise.resolve({ data: null, error: { message: 'You do not have access to customer credit' } }) }, 'a role that may not see credit');
  await quiet({ fetchBalances: ok(balance({})) }, 'read, and nothing to show');
  for (const invoice of [{ customer_id: 'cust-a', status: 'cancelled' }, { customer_id: 'cust-a', status: 'refunded' }, { customer_id: null, status: 'paid' }]) {
    await quiet({ invoice, fetchBalances: () => Promise.reject(new Error('never asked')) }, `${invoice.status} / ${invoice.customer_id}`);
  }
  assert.deepEqual(await read({ fetchBalances: ok(balance({ paid: 300, bonus: 50 })) }),
    { line: { label: 'Credit balance (as at 2 Oct 2026)', amount: 'S$350.00', detail: 'Paid S$300.00 · Bonus S$50.00' }, unreadable: false });
  assert.equal(isCreditAccessRefusal({ message: 'You do not have access to customer credit' }), true);
  assert.equal(isCreditAccessRefusal({ message: 'timed out' }), false);
  assert.equal(isCreditAccessRefusal(null), false);
});

test('a Supabase-style builder (a thenable, not a promise) is read like one', async () => {
  const builder = { then: (resolve, reject) => Promise.resolve({ data: balance({ legacy: 7 }), error: null }).then(resolve, reject) };
  const line = await creditBalanceForInvoice(base({ fetchBalances: () => builder }));
  assert.equal(line?.detail, 'Legacy S$7.00');
});
