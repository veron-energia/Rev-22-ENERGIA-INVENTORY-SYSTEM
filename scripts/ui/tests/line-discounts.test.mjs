/**
 * One discount per invoice line (384), as the form and the printed copies
 * share it: src/lib/invoices/lineDiscounts.ts.
 *
 * Pins the owner's rules (3 Oct 2026): which line kinds offer which
 * discounts, what each one sends to the server, how a saved line comes back
 * when an invoice is corrected (old FOC-and-voucher lines included), and the
 * arithmetic, which has to equal create_invoice to the cent or the form shows
 * one total and saves another. Every name and amount is invented.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoices/lineDiscounts';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const d = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const pct = (id, percent, over = {}) => ({ id, name: `Fixture ${percent}%`, voucher_kind: 'percentage_discount', discount_percent: percent, max_discount_cap: null, ...over });
const fixed = (id, amount, over = {}) => ({ id, name: `Fixture S$${amount}`, voucher_kind: 'fixed_discount', discount_amount: amount, ...over });
const S = c => (c / 100).toFixed(2);

test('each line kind offers only the discounts the owner allowed on it', () => {
  const all = ['', 'foc', 'voucher', 'birthday', 'staff', 'manual', 'percentage'];
  assert.deepEqual(d.discountChoicesFor('product'), all, 'our own product: everything');
  assert.deepEqual(d.discountChoicesFor('product', { thirdParty: true }), ['', 'foc', 'manual', 'percentage'],
    'a third-party product: no voucher of any category');
  for (const kind of ['voucher', 'promotion', 'therapy', 'special_product', 'rental', 'event_ticket']) {
    assert.deepEqual(d.discountChoicesFor(kind), ['', 'foc', 'manual', 'percentage'], `${kind}: FOC, manual or percentage`);
  }
  for (const kind of ['credit_package', 'premium_bundle']) {
    assert.deepEqual(d.discountChoicesFor(kind), [], `${kind}: none, a discount would scale its credit down`);
  }
  assert.deepEqual(d.discountChoicesFor('product', { categories: ['birthday'] }), ['', 'foc', 'birthday', 'manual', 'percentage'],
    'only the voucher categories on offer are listed');
  assert.deepEqual(d.discountChoicesFor('product', { inventoryManager: true }), ['', 'manual', 'percentage'],
    'an Inventory Manager gives neither FOC nor a voucher; Manual and Percentage are open to everyone who invoices');
  assert.deepEqual(d.discountChoicesFor('credit_package', { inventoryManager: true }), []);
  assert.equal(d.DISCOUNT_CHOICE_LABELS.manual, 'Manual discount (S$)');
  assert.equal(d.DISCOUNT_CHOICE_LABELS.percentage, 'Percentage discount (%)');
});

test('a discount voucher is told apart by its category; one saved before categories is a plain voucher', () => {
  assert.equal(d.voucherCategory(pct('a', 20, { discount_category: 'birthday' })), 'birthday');
  assert.equal(d.voucherCategory(pct('a', 10, { discount_category: 'staff' })), 'staff');
  assert.equal(d.voucherCategory(pct('a', 10)), 'voucher');
  assert.equal(d.voucherCategory({ id: 'n', name: 'Gift', voucher_kind: 'normal' }), null);
  assert.equal(d.voucherCategory(undefined), null);
});

test('the payload: FOC keys only for FOC, one discount otherwise, reasons only where they belong', () => {
  const base = { kind: 'product', line_voucher_id: '', foc_quantity: 0, foc_reason_id: '', foc_reason: '' };
  assert.deepEqual(d.lineDiscountPayload({ ...base, discount: '' }), { line_voucher_id: null }, 'none, on a product line');
  assert.deepEqual(d.lineDiscountPayload({ ...base, kind: 'therapy', discount: '' }), {}, 'none, on any other line');
  assert.deepEqual(d.lineDiscountPayload({ ...base, discount: 'foc', foc_quantity: 2, foc_reason_id: 'r-1', foc_reason: 'Note' }),
    { line_voucher_id: null, foc_quantity: 2, foc_reason_id: 'r-1', foc_reason: 'Note' });
  assert.deepEqual(d.lineDiscountPayload({ ...base, discount: 'birthday', line_voucher_id: 'v-b' }),
    { line_voucher_id: 'v-b', line_discount_type: 'birthday' });
  assert.deepEqual(d.lineDiscountPayload({ ...base, discount: 'staff', line_voucher_id: 'v-s', foc_quantity: 1 }),
    { line_voucher_id: 'v-s', line_discount_type: 'staff' }, 'a leftover FOC quantity is never sent with a discount');
  assert.deepEqual(d.lineDiscountPayload({ ...base, kind: 'promotion', discount: 'manual', discount_amount: '12.50', discount_reason: '  Fixture reason  ' }),
    { line_discount_type: 'manual', line_discount_amount: 12.5, line_discount_reason: 'Fixture reason' });
  assert.deepEqual(d.lineDiscountPayload({ ...base, kind: 'event_ticket', discount: 'percentage', discount_percent: '12.5', discount_reason: 'Fixture reason' }),
    { line_discount_type: 'percentage', line_discount_percent: 12.5, line_discount_reason: 'Fixture reason' });
  // Saved before 384: a voucher with no type goes back with none, so the
  // server sees the line as it stored it (and treats it as its category).
  assert.deepEqual(d.lineDiscountPayload({ ...base, discount: 'voucher', line_voucher_id: 'v-old', discount_untyped: true }),
    { line_voucher_id: 'v-old' });
  // An old line with FOC and a voucher both goes back exactly as stored.
  assert.deepEqual(d.lineDiscountPayload({ ...base, discount: 'legacy', line_voucher_id: 'v-old', foc_quantity: 1, foc_reason_id: 'r-1', foc_reason: '' }),
    { line_voucher_id: 'v-old', foc_quantity: 1, foc_reason_id: 'r-1', foc_reason: null });
  // Exchange credit is kept by the server; the form sends nothing for it.
  assert.deepEqual(d.lineDiscountPayload({ ...base, discount: 'exchange' }), { line_voucher_id: null });
  // A credit package given away with Make FOC goes back unchanged.
  assert.deepEqual(d.lineDiscountPayload({ ...base, kind: 'credit_package', discount: 'foc', foc_quantity: 1, foc_reason_id: 'r-1' }),
    { foc_quantity: 1, foc_reason_id: 'r-1', foc_reason: null });
  for (const choice of ['', 'foc', 'voucher', 'birthday', 'staff', 'legacy', 'exchange']) {
    const out = d.lineDiscountPayload({ ...base, discount: choice, discount_reason: 'Fixture reason', line_voucher_id: 'v' });
    assert.ok(!('line_discount_reason' in out), `${choice || 'none'} carries no reason`);
  }
});

test('a percentage is round(value × % ÷ 100, 2), half away from zero, as Postgres rounds', () => {
  assert.equal(d.percentOfCents(3333, 15), 500, '33.33 × 15% = 4.9995 → 5.00');
  assert.equal(d.percentOfCents(10000, 12.5), 1250);
  assert.equal(d.percentOfCents(999, 33.333), 333, '9.99 × 33.333% = 3.32997 → 3.33');
  assert.equal(d.percentOfCents(5, 50), 3, '0.05 × 50% = 0.025 → 0.03');
  assert.equal(d.percentOfCents(10000, 100), 10000);
  assert.equal(d.divRound(-5, 2), -3, 'half away from zero below zero too');
});

test('a line: FOC, then its one discount on what is charged', () => {
  // unit × quantity, a share free.
  let m = d.lineMoney({ unit: 33.33, quantity: 3, choice: 'foc', foc_quantity: 1 });
  assert.deepEqual([m.gross, m.foc, m.charged, m.discount], [9999, 3333, 6666, 0]);
  // A FOC quantity left over from another choice is not FOC.
  m = d.lineMoney({ unit: 50, quantity: 2, choice: 'manual', amount: '10', foc_quantity: 2 });
  assert.deepEqual([m.foc, m.charged, m.discount], [0, 10000, 1000]);
  // A manual discount never exceeds the line (the form refuses it first).
  assert.equal(d.lineMoney({ unit: 20, quantity: 1, choice: 'manual', amount: '25' }).discount, 2000);
  // Percentage of the whole line.
  assert.equal(d.lineMoney({ unit: 33.33, quantity: 1, choice: 'percentage', percent: '15' }).discount, 500);
  assert.equal(d.lineMoney({ unit: 10, quantity: 1, choice: 'percentage', percent: '101' }).discount, 0, 'over 100% counts for nothing');
  // A promotion's top-up is part of the line's value.
  m = d.lineMoney({ unit: 300, quantity: 1, topup: 20, choice: 'percentage', percent: '10' });
  assert.deepEqual([m.gross, m.discount], [32000, 3200]);
  // Voucher categories all work as voucher_discount_amount.
  assert.equal(d.lineMoney({ unit: 200, quantity: 1, choice: 'birthday', voucher: pct('b', 20, { max_discount_cap: 30 }) }).discount, 3000, 'capped');
  assert.equal(d.lineMoney({ unit: 200, quantity: 1, choice: 'staff', voucher: pct('s', 10) }).discount, 2000);
  m = d.lineMoney({ unit: 72, quantity: 1, choice: 'voucher', voucher: fixed('f', 72) });
  assert.ok(m.voucherRefused, 'a fixed voucher needs the line strictly above its amount');
  assert.equal(d.lineMoney({ unit: 73, quantity: 1, choice: 'voucher', voucher: fixed('f', 72) }).discount, 7200);
  // An old line with FOC and a voucher: the voucher on what is charged, as 68 did.
  m = d.lineMoney({ unit: 100, quantity: 2, choice: 'legacy', foc_quantity: 1, voucher: pct('v', 10) });
  assert.deepEqual([m.foc, m.charged, m.discount], [10000, 10000, 1000]);
  // A saved line left unchanged keeps what the server stored.
  m = d.lineMoney({ unit: 999, quantity: 9, choice: 'voucher', voucher: pct('v', 50),
    saved: { line_total: 90, line_discount: 7.5, foc_amount: 10 } });
  assert.deepEqual([m.gross, m.foc, m.charged, m.discount], [10000, 1000, 9000, 750]);
  assert.equal(d.lineMoney({ unit: null, quantity: 1, choice: '' }).charged, 0, 'no price, no money');
});

test('the invoice totals follow create_invoice, and an edit is totalled the same way', () => {
  const line = (charged, discount = 0, thirdParty = false) => ({ gross: charged, foc: 0, charged, discount, thirdParty });
  // The owner's example (rule 11a): subtotal 100, manual 20, 10% invoice voucher → 8 off.
  let t = d.invoiceTotals({ lines: [line(10000)], manual: 20, invoiceVoucher: pct('iv', 10) });
  assert.deepEqual([t.subtotal, t.manual, t.voucherBase, t.voucherDiscount, t.discountTotal, t.total].map(S),
    ['100.00', '20.00', '80.00', '8.00', '28.00', '72.00']);
  // The manual discount reaches third-party value; the voucher does not.
  t = d.invoiceTotals({ lines: [line(10000), line(10000, 0, true)], manual: 50, invoiceVoucher: pct('iv', 10) });
  assert.deepEqual([t.voucherBase, t.voucherDiscount, t.discountTotal, t.total].map(S), ['50.00', '5.00', '55.00', '145.00']);
  // Line discounts on our own products come off the voucher's base (one on a
  // third-party line does not: that value is not in the base), and every one
  // stacks with the invoice-level discounts.
  t = d.invoiceTotals({ lines: [line(10000, 1000), line(5000, 500, true)], manual: 0, invoiceVoucher: pct('iv', 10) });
  assert.deepEqual([t.lineDiscounts, t.voucherBase, t.voucherDiscount, t.discountTotal, t.total].map(S),
    ['15.00', '90.00', '9.00', '24.00', '126.00']);
  // All three together: 100 own (10% off) + 80 third-party (S$5 off), manual 10, 10% invoice voucher.
  // Base (180 − 80) − 10 − 10 = 80 → 8.00; discount 10 + 15 + 8 = 33.
  t = d.invoiceTotals({ lines: [line(10000, 1000), line(8000, 500, true)], manual: 10, invoiceVoucher: pct('iv', 10) });
  assert.deepEqual([t.voucherBase, t.voucherDiscount, t.discountTotal, t.total].map(S), ['80.00', '8.00', '33.00', '147.00']);
  // A manual discount larger than our own value is capped there for the base, not below zero.
  t = d.invoiceTotals({ lines: [line(2000), line(8000, 0, true)], manual: 50, invoiceVoucher: pct('iv', 10) });
  assert.deepEqual([t.voucherBase, t.voucherDiscount, t.discountTotal].map(S), ['0.00', '0.00', '50.00']);
  // Never more than the subtotal.
  t = d.invoiceTotals({ lines: [line(10000, 2000)], manual: 500 });
  assert.deepEqual([t.manual, t.discountTotal, t.total].map(S), ['100.00', '100.00', '0.00']);
  // FOC is not a discount: it is what the subtotal leaves out.
  t = d.invoiceTotals({ lines: [{ gross: 9999, foc: 3333, charged: 6666, discount: 0, thirdParty: false }], manual: 0 });
  assert.deepEqual([t.subtotal, t.focTotal, t.discountTotal].map(S), ['66.66', '33.33', '0.00']);
  // A fixed invoice voucher the base is not above gives nothing (the server refuses it).
  t = d.invoiceTotals({ lines: [line(5000)], manual: 0, invoiceVoucher: fixed('iv', 50) });
  assert.equal(t.voucherDiscount, 0);
});

test('the birthday check: the customer, their date of birth, and the invoice date in Singapore', () => {
  const p = (rule, dob, day) => d.birthdayProblem(rule, { hasCustomer: true, dob, businessDate: day });
  assert.match(d.birthdayProblem('actual_date', { hasCustomer: false }), /Choose the customer first/);
  assert.match(p('actual_date', null, '2026-10-03'), /Add the customer's date of birth/);
  assert.match(p('whole_month', '', '2026-10-03'), /Add the customer's date of birth/);
  assert.equal(p('actual_date', '1990-10-03', '2026-10-03'), null, 'on the birthday');
  assert.match(p('actual_date', '1990-10-04', '2026-10-03'), /birthday itself \(4 October\); the invoice is dated 3 October 2026/);
  assert.equal(p('whole_month', '1990-10-28', '2026-10-03'), null, 'anywhere in the birth month');
  assert.match(p('whole_month', '1990-11-03', '2026-10-03'), /birth month \(November\)/);
  assert.equal(p('actual_date', '2000-02-29', '2027-02-28'), null, '29 February is 28 February in other years');
  assert.match(p('actual_date', '2000-02-29', '2028-02-28'), /29 February/, 'and 29 February in a leap year');
  assert.equal(p('actual_date', '2000-02-29T00:00:00', '2028-02-29'), null);
});

test('a saved line comes back as saved, on every kind of line', () => {
  const cat = id => ({ 'v-b': 'birthday', 'v-s': 'staff' })[id] ?? null;
  const r = it => d.restoreLineDiscount(it, cat);
  assert.equal(r({ line_discount: 0 }).discount, '');
  assert.deepEqual(pick(r({ foc_quantity: 2, foc_reason_id: 'r-1', foc_reason: 'Note' }), 'discount', 'foc_quantity', 'foc_reason_id', 'foc_reason'),
    { discount: 'foc', foc_quantity: 2, foc_reason_id: 'r-1', foc_reason: 'Note' });
  assert.deepEqual(pick(r({ line_discount: 12, line_voucher_id: 'v-b', line_discount_type: 'birthday' }), 'discount', 'line_voucher_id', 'discount_untyped'),
    { discount: 'birthday', line_voucher_id: 'v-b', discount_untyped: false });
  // Saved before 384: shown under its voucher's category, sent back untyped.
  assert.deepEqual(pick(r({ line_discount: 5, line_voucher_id: 'v-s' }), 'discount', 'line_voucher_id', 'discount_untyped'),
    { discount: 'staff', line_voucher_id: 'v-s', discount_untyped: true });
  assert.equal(r({ line_discount: 5, line_voucher_id: 'v-unknown' }).discount, 'voucher', 'an unknown voucher is a plain voucher');
  assert.deepEqual(pick(r({ line_kind: 'therapy', line_discount: 12.5, line_discount_type: 'manual', line_discount_reason: 'Fixture reason' }),
    'discount', 'discount_amount', 'discount_reason'), { discount: 'manual', discount_amount: '12.50', discount_reason: 'Fixture reason' });
  assert.deepEqual(pick(r({ line_discount: 3.5, line_discount_type: 'percentage', line_discount_percent: '12.500', line_discount_reason: 'Fixture reason' }),
    'discount', 'discount_percent'), { discount: 'percentage', discount_percent: '12.5' });
  // FOC and a voucher both, from before the one-discount rule: read-only until changed.
  assert.deepEqual(pick(r({ foc_quantity: 1, foc_reason_id: 'r-1', line_voucher_id: 'v-s', line_discount: 9 }), 'discount', 'line_voucher_id', 'foc_quantity'),
    { discount: 'legacy', line_voucher_id: 'v-s', foc_quantity: 1 });
  // Exchange credit: a line discount with no voucher and no type.
  assert.equal(r({ line_discount: 40 }).discount, 'exchange');
  assert.equal(r({ line_discount: 40, foc_quantity: 1 }).discount, 'exchange');
  // A line saved all free stays all free when its quantity changes; a share stays a share.
  assert.equal(r({ quantity: 2, foc_quantity: 2, foc_reason_id: 'r-1' }).foc_all, true);
  assert.equal(r({ quantity: 3, foc_quantity: 1, foc_reason_id: 'r-1' }).foc_all, false);
});

test('a quantity retyped never makes more of a line free than staff chose', () => {
  const line = over => ({ kind: 'product', quantity: 3, line_voucher_id: '', discount: 'foc', foc_quantity: 1, foc_reason_id: 'r-1', foc_all: false, ...over });
  const type = (l, ...steps) => steps.reduce((x, q) => d.withQuantity(x, q), l);
  // 1 of 3 free; the field cleared (0) and 4 typed: still 1 free.
  assert.equal(type(line(), 0, 4).foc_quantity, 1);
  // Cleared and 12 typed digit by digit: "1" is momentarily all of it, but not all free.
  assert.equal(type(line(), 0, 1, 12).foc_quantity, 1);
  // 2 of 3, typed down to 1 and back up to 3: still 2 (more than the quantity for a moment).
  assert.deepEqual(type(line({ foc_quantity: 2 }), 1).foc_quantity, 2);
  assert.equal(type(line({ foc_quantity: 2 }), 1, 3).foc_quantity, 2);
  assert.match(d.lineDiscountProblem(type(line({ foc_quantity: 2 }), 1), { valueCents: 10000, changed: true, allowed: d.discountChoicesFor('product'), quantity: 1 }),
    /cannot be more than the quantity/, 'and the save refuses it while it is');
  // All free follows the quantity, however it is typed.
  assert.equal(type(line({ foc_quantity: 3, foc_all: true }), 0, 1, 12).foc_quantity, 12);
  assert.equal(type(line({ foc_quantity: 3, foc_all: true }), 0).foc_quantity, 3, 'an empty field changes nothing');
  // Any other discount: the quantity alone.
  assert.equal(type(line({ discount: 'manual', foc_quantity: 0, foc_all: true }), 5).foc_quantity, 0);
});

test('switching a line\'s discount: one per line, the saved one comes back, an old FOC-and-voucher line keeps its FOC or voucher', () => {
  const cat = id => ({ 'v-s': 'staff', 'v-v': 'voucher' })[id] ?? null;
  const line = over => ({ kind: 'product', quantity: 2, line_voucher_id: '', discount: '', foc_quantity: 0, ...over });
  // FOC afresh: every unit free, and it stays all free.
  let l = d.switchDiscount(line(), 'foc', undefined, cat);
  assert.deepEqual(pick(l, 'discount', 'foc_quantity', 'foc_all'), { discount: 'foc', foc_quantity: 2, foc_all: true });
  // Anything else clears the FOC.
  l = d.switchDiscount(l, 'manual', undefined, cat);
  assert.deepEqual(pick(l, 'discount', 'foc_quantity', 'foc_all'), { discount: 'manual', foc_quantity: 0, foc_all: false });
  // Saved before the one-discount rule: 1 of 2 free with a reason, and a staff voucher.
  const saved = { kind: 'product', discount: 'legacy', line_voucher_id: 'v-s', foc_quantity: 1, foc_reason_id: 'r-old', foc_reason: 'Saved note', foc_all: false };
  const changed = line({ ...saved, quantity: 3 });
  l = d.switchDiscount(changed, 'foc', saved, cat);
  assert.deepEqual(pick(l, 'discount', 'foc_quantity', 'foc_reason_id', 'foc_reason', 'foc_all', 'line_voucher_id'),
    { discount: 'foc', foc_quantity: 1, foc_reason_id: 'r-old', foc_reason: 'Saved note', foc_all: false, line_voucher_id: '' },
    'FOC keeps the free quantity and reason it had, not every unit');
  assert.equal(d.switchDiscount(line({ ...saved, foc_quantity: 1, quantity: 1 }), 'foc', { ...saved, foc_quantity: 2 }, cat).foc_quantity, 1,
    'never more free than the quantity');
  l = d.switchDiscount(changed, 'staff', saved, cat);
  assert.deepEqual(pick(l, 'discount', 'line_voucher_id', 'foc_quantity'), { discount: 'staff', line_voucher_id: 'v-s', foc_quantity: 0 },
    'its voucher\'s category keeps the voucher, without the FOC');
  assert.equal(d.switchDiscount(changed, 'voucher', saved, cat).line_voucher_id, '', 'another category starts empty');
  // The saved discount chosen again comes back as saved.
  const savedFoc = { kind: 'product', discount: 'foc', line_voucher_id: '', foc_quantity: 1, foc_reason_id: 'r-1', foc_reason: '', foc_all: false };
  l = d.switchDiscount(d.switchDiscount(line({ ...savedFoc, quantity: 3 }), 'manual', savedFoc, cat), 'foc', savedFoc, cat);
  assert.ok(d.sameDiscount(l, savedFoc), 'switching away and back is no change');
});
function pick(o, ...keys) { return Object.fromEntries(keys.map(k => [k, o[k]])); }

test('what stops a line from saving is said in a sentence staff can act on', () => {
  const ok = { valueCents: 10000, changed: true, allowed: d.discountChoicesFor('product'), quantity: 2 };
  const p = (draft, o = {}) => d.lineDiscountProblem({ kind: 'product', ...draft }, { ...ok, ...o });
  assert.equal(p({ discount: '' }), null);
  assert.match(p({ discount: 'foc', foc_quantity: 0 }), /how many are free/);
  assert.match(p({ discount: 'foc', foc_quantity: 3, foc_reason_id: 'r' }), /cannot be more than the quantity/);
  assert.match(p({ discount: 'foc', foc_quantity: 1 }), /Give the FOC reason/);
  assert.equal(p({ discount: 'foc', foc_quantity: 1, foc_reason: 'Note' }), null);
  assert.match(p({ discount: 'birthday' }), /Choose the birthday discount voucher/);
  assert.equal(p({ discount: 'staff', line_voucher_id: 'v' }), null);
  assert.match(p({ discount: 'manual', discount_amount: '0', discount_reason: 'x' }), /more than S\$0\.00/);
  assert.match(p({ discount: 'manual', discount_amount: '100.01', discount_reason: 'x' }), /more than the line's value \(S\$100\.00\)/);
  assert.match(p({ discount: 'manual', discount_amount: '1.005', discount_reason: 'x' }), /to the cent/);
  assert.match(p({ discount: 'manual', discount_amount: '10' }), /Give the reason for the manual discount/);
  assert.equal(p({ discount: 'manual', discount_amount: '100', discount_reason: 'Fixture reason' }), null, 'the whole line may be discounted');
  assert.match(p({ discount: 'percentage', discount_percent: '0', discount_reason: 'x' }), /above 0 and no more than 100/);
  assert.match(p({ discount: 'percentage', discount_percent: '100.5', discount_reason: 'x' }), /above 0 and no more than 100/);
  assert.match(p({ discount: 'percentage', discount_percent: '12.3456', discount_reason: 'x' }), /three decimal places/);
  assert.match(p({ discount: 'percentage', discount_percent: '10', discount_reason: '  ' }), /reason for the percentage discount/);
  assert.equal(p({ discount: 'percentage', discount_percent: '100', discount_reason: 'Fixture reason' }), null);
  assert.match(p({ discount: 'birthday', line_voucher_id: 'v' }, { allowed: d.discountChoicesFor('product', { thirdParty: true }) }),
    /Birthday discount cannot be given on this line/);
  assert.equal(p({ discount: 'legacy' }, { changed: false }), null, 'an old line left as it is saves as it is');
  assert.match(p({ discount: 'legacy' }), /both FOC and a voucher from before\. Choose one discount/);
  assert.equal(p({ discount: 'exchange' }), null);
  // A saved line left as it is is never refused: the server keeps it as stored.
  const makeFoc = { kind: 'credit_package', discount: 'foc', foc_quantity: 1, foc_reason_id: 'r' };
  const pkg = { ...ok, allowed: d.discountChoicesFor('credit_package'), quantity: 1 };
  assert.equal(d.lineDiscountProblem(makeFoc, { ...pkg, changed: false }), null,
    'a credit package given away with Make FOC saves again unchanged');
  // Its price corrected by the Owner: the line changed, its FOC did not. The
  // server keeps the FOC, and the line has no Discount select to change it with.
  assert.equal(d.lineDiscountProblem(makeFoc, { ...pkg, saved: { ...makeFoc } }), null,
    'a Make-FOC credit package whose price is corrected keeps its FOC');
  assert.match(d.lineDiscountProblem(makeFoc, pkg), /FOC cannot be given on this line/,
    'but FOC it did not have is refused (the server refuses it when the line is written)');
  assert.match(d.lineDiscountProblem({ ...makeFoc, foc_reason: 'Other' }, { ...pkg, saved: makeFoc }), /FOC cannot be given on this line/);
  // Elsewhere a saved discount the line may not take is still refused when the line changes (the server refuses it too).
  assert.match(d.lineDiscountProblem({ kind: 'product', discount: 'staff', line_voucher_id: 'v' },
    { ...ok, allowed: d.discountChoicesFor('product', { inventoryManager: true }), saved: { kind: 'product', discount: 'staff', line_voucher_id: 'v' } }),
    /Staff discount cannot be given on this line/, 'an Inventory Manager changing a line with a saved voucher');
});

test('the printed line names the discount and its amount, never its reason', () => {
  const it = over => ({ line_discount: 12, line_discount_reason: 'Fixture internal reason', ...over });
  assert.equal(d.printedLineDiscount(it({ line_discount_type: 'birthday', line_voucher_id: 'v' }), 'Birthday 20% (Actual Date)'), 'Birthday 20% (Actual Date) −S$12.00');
  assert.equal(d.printedLineDiscount(it({ line_voucher_id: 'v' }), 'Old Voucher'), 'Old Voucher −S$12.00', 'an old untyped voucher line');
  assert.equal(d.printedLineDiscount(it({ line_discount_type: 'manual' }), ''), 'Discount −S$12.00');
  assert.equal(d.printedLineDiscount(it({ line_discount_type: 'percentage', line_discount_percent: 10 }), ''), 'Discount 10% −S$12.00');
  assert.equal(d.printedLineDiscount(it({ line_discount_type: 'percentage', line_discount_percent: '12.500' }), '', '-'), 'Discount 12.5% -S$12.00',
    'the PDF takes an ASCII minus');
  assert.equal(d.printedLineDiscount(it({}), ''), null, 'exchange credit is named by the totals, not the line');
  assert.equal(d.printedLineDiscount({ line_discount: 0, line_discount_type: 'manual' }, ''), null);
  for (const type of ['voucher', 'birthday', 'staff', 'manual', 'percentage']) {
    assert.doesNotMatch(d.printedLineDiscount(it({ line_discount_type: type, line_voucher_id: 'v', line_discount_percent: 5 }), 'Name') ?? '', /Fixture internal reason/);
  }
  assert.equal(d.printedLineDiscount.length >= 2 && !/reason/.test(d.printedLineDiscount.toString()), true, 'the printer cannot read a reason');
});
