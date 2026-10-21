// The Invoices page wired to 416 and 417 (B16). The server makes every check
// below too; the page says it first, in the same words, and sends what the
// server now expects. Invented values only.
//
//  - CREATE-9 (416 rule 4): an amount with more than 2 decimal places is
//    refused, never rounded: Record Payment, an instalment portion and the
//    payment parts of Correct Invoice.
//  - CREATE-11 (416 rule 3): no invoice dated after today in Singapore; a date
//    once set cannot be cleared; an old undated invoice may stay undated.
//  - CREATE-15 (416 rule 5): one request id per New Invoice form.
//  - CREATE-M1 (416 rule 11): the correction summary is sent the corrected
//    lines and shows what the total and status become, and says that payment
//    changes are not checked until the save.
//  - CREATE-5: the summary is of the form as it was; a form changed after it
//    is reviewed again, not saved.
//  - CREATE-17, AFTER-16, SALES-EXTRAS-9: Singapore days, whatever the device.
//  - CREATE-14 (417, Q4 = A), CREATE-19, CREATE-4, CREATE-18: the page parts.
//  - W4-B04-IM-ADD-CUSTOMER: no Add customer button for Inventory Managers,
//    on the form and on each split-panel row.
//
// Run: node --test scripts/invoices/tests/page-checks-416.test.mjs
// A device outside Singapore: every day below must still be Singapore's.
process.env.TZ = 'America/Los_Angeles';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `
    export * from './src/lib/invoices/business';
    export * from './src/lib/invoices/correctionReview';
    export { displayDay, displayDateTime, calendarDate } from './src/lib/calendarDates';
    export { portionProblem } from './src/components/invoices/InstalmentPortionFields';`,
    resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'node', jsx: 'automatic',
  loader: { '.css': 'empty' }, define: { 'process.env.NODE_ENV': '"production"' },
});
const lib = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
const between = (a, b) => { const i = page.indexOf(a); assert.ok(i >= 0, `not found: ${a}`); const j = page.indexOf(b, i); return page.slice(i, j < 0 ? undefined : j); };

test('CREATE-9: at most 2 decimal places, refused rather than rounded', () => {
  const { hasAtMostTwoDecimals: ok, TWO_DECIMALS_MESSAGE } = lib;
  for (const v of [99.99, 0.07, 100, '0.1', '12.30', 1e-2]) assert.equal(ok(v), true, String(v));
  for (const v of [99.995, '1.005', 0.001, NaN, 'abc']) assert.equal(ok(v), false, String(v));
  assert.equal(TWO_DECIMALS_MESSAGE, 'Payment amounts can have at most 2 decimal places.');
  assert.equal(lib.portionProblem({ method_id: 'cash', months: 6 }, 99.995), TWO_DECIMALS_MESSAGE, 'an instalment portion');
  assert.equal(lib.portionProblem({ method_id: 'cash', months: 6 }, 99.99), null);
  assert.match(between('const paymentBlocker = ', 'const payBlockedReason'), /hasAtMostTwoDecimals\(p\.amount\)\)\) return TWO_DECIMALS_MESSAGE/, 'Record Payment');
  assert.match(between('const handleCreate = async', 'const header = {'), /kept\.some\(x => !hasAtMostTwoDecimals\(x\.amount\)\)/, 'the payment parts of a correction');
  assert.match(between('const handleCreate = async', 'const header = {'), /kept\.some\(x => x\.date > singaporeToday\(\)\)/, 'and their dates');
});

test('CREATE-11: the business date', () => {
  const p = (v, o) => lib.businessDateProblem(v, { today: '2026-10-18', ...o });
  assert.equal(p('', { editing: false }), 'Choose the invoice business date.');
  assert.equal(p('2026-10-19', { editing: false }), 'The invoice date cannot be after today.');
  assert.equal(p('2026-10-18', { editing: false }), null);
  assert.equal(p('', { editing: true, savedDate: '2026-09-01' }), 'Keep the invoice date; it cannot be cleared.');
  assert.equal(p('', { editing: true, savedDate: '' }), null, 'an invoice saved with no date may stay undated');
  assert.equal(p('2026-10-19', { editing: true, savedDate: '' }), 'The invoice date cannot be after today.');
  assert.equal(p('2026-08-01', { editing: true, savedDate: '2026-09-01' }), null, 'a past date is fine');
  assert.match(page, /<input type="date" value=\{cBusinessDate\} max=\{singaporeToday\(\)\}/, 'the input cannot pick tomorrow');
});

test('CREATE-15: a request id per New Invoice form, renewed when the form opens', () => {
  assert.match(between('const resetCreate = () => {', 'const paymentChanges'), /setCreateRequestId\(crypto\.randomUUID\(\)\);/);
  assert.match(page, /rpc\('create_invoice_with_details', \{[^}]*p_header: \{ \.\.\.header, request_id: createRequestId \} \}\)/);
  // A correction is not a creation: the header it sends carries no request id.
  assert.doesNotMatch(between('const header = {', '// Show what the correction'), /request_id/);
});

test('CREATE-M1 and CREATE-5: the summary is sent the lines and is of the form as it was', () => {
  const f = lib.correctionFingerprint;
  const items = [{ kind: 'product', product_id: 'p1', quantity: 1 }];
  const header = { customer_id: 'c1', notes: 'one', expected_edit_count: 2 };
  assert.equal(f(items, header, 'why'), f(items, { notes: 'one', customer_id: 'c1', expected_edit_count: 5 }, ' why '),
    'the same form, keys in any order and a moved edit count, is the same review');
  assert.notEqual(f(items, header, 'why'), f(items, { ...header, notes: 'two' }, 'why'), 'a note changed after the review');
  assert.notEqual(f(items, header, 'why'), f([{ ...items[0], quantity: 2 }], header, 'why'), 'a line changed');
  assert.notEqual(f(items, header, 'why'), f(items, header, 'other reason'), 'the reason changed');
  const create = between('const header = {', 'setCSaving(false);\n    if (error)');
  assert.match(create, /p_header: \{ \.\.\.header, items: allItems \}/, 'the corrected lines go to preview_invoice_correction');
  assert.match(create, /correctionReviewedRef\.current !== fingerprint/, 'Save the correction checks the form still matches');
  assert.match(create, /setCorrectionNotice\(changedAfterReview \? REVIEW_AGAIN_MESSAGE : null\)/);
  assert.equal(lib.REVIEW_AGAIN_MESSAGE, 'You changed the invoice after reviewing it. Review the changes again.');
  assert.match(page, /<fieldset className="form-grid invoice-editor invoice-editor-lock" disabled=\{!!correctionPreview\}/, 'the form is locked while the summary is open');
});

test('CREATE-M1: what the corrected lines make of the invoice, and what was not checked (rule 11)', () => {
  const o = lib.outcomeLines({ checked: true, total_before: 100, total_after: 200, status_before: 'paid', status_after: 'partially_paid',
    outstanding_after: 100, refund_due_after: 0,
    lines: [{ change: 'changed', label: 'Socks', quantity_before: 1, quantity_after: 2, charged_before: 100, charged_after: 200 }] });
  assert.equal(o.total, 'Total S$100.00 → S$200.00');
  assert.equal(o.status, 'Status Paid → Part paid');
  assert.deepEqual(o.money, ['S$100.00 owing']);
  assert.deepEqual(o.lines, ['Socks: quantity 1 → 2, S$100.00 → S$200.00']);
  assert.match(o.note, /Payment changes are checked only when you save, so the save can still be refused\./);
  const due = lib.outcomeLines({ checked: true, total_before: 100, total_after: 80, status_before: 'paid', status_after: 'paid',
    outstanding_after: 0, refund_due_after: 20, lines: [] });
  assert.equal(due.status, 'Status stays Paid');
  assert.deepEqual(due.money, ['S$20.00 becomes refund due']);
  assert.equal(lib.outcomeLines({ checked: false, refusal: 'A line you removed gave vouchers…' }), null, 'a refusal is said in needs_review');
  assert.equal(lib.outcomeLines(null), null, 'no lines sent: as before');
  const preview = readFileSync('src/components/invoices/CorrectionPreview.tsx', 'utf8');
  assert.match(preview, /total: 'Total and status', correction: 'The corrected lines'/);
  assert.match(preview, /vouchers: 'Vouchers given free'/, '416\'s vouchers entry keeps its label');
});

test('CREATE-17, AFTER-16: Singapore days, on a device that is not in Singapore', () => {
  // 00:30 on 1 Sep in Singapore is 31 Aug in Los Angeles and in UTC.
  assert.equal(lib.displayDay('2026-08-31T16:30:00Z'), '1/9/2026');
  assert.equal(lib.displayDay('2026-09-01'), '1/9/2026', 'a date-only value is that day');
  assert.equal(lib.displayDay(null), '');
  assert.match(lib.displayDateTime('2026-08-31T16:30:00Z'), /^1\/9\/2026, 12:30/);
  assert.doesNotMatch(page, /toLocaleDateString\('en-SG'\)|toLocaleDateString\(\)|toLocaleDateString\('en-GB'\)|toLocaleString\(/,
    'no date on the invoice follows the device\'s time zone');
  assert.doesNotMatch(page, /new Date\(\)\.toISOString\(\)\.slice\(0, 10\)/, 'no UTC "today"');
  assert.match(page, /rental_start_date: singaporeToday\(\)/, 'a new rental starts today in Singapore');
  assert.match(page, /calendarDate\(src\.paid_at, 'Asia\/Singapore'\)/, 'the legacy diagnosis asks about the Singapore day');
  assert.match(page, /<input type="date" aria-label="Date received" value=\{part\.date\} max=\{singaporeToday\(\)\}/, 'a corrected payment cannot be dated in the future');
});

test('SALES-EXTRAS-9: the promotion picker offers what is on sale on the invoice\'s day', () => {
  const live = lib.liveOnDay;
  assert.equal(live({ is_active: true, start_date: null, end_date: '2026-10-01' }, '2026-10-02'), false, 'ended');
  assert.equal(live({ is_active: true, start_date: '2026-10-03', end_date: null }, '2026-10-02'), false, 'not started');
  assert.equal(live({ is_active: true, start_date: '2026-10-01', end_date: '2026-10-01' }, '2026-10-01'), true, 'its one day');
  assert.equal(live({ is_active: false }, '2026-10-01'), false, 'switched off');
  assert.equal(live({ valid_from: '2026-01-01', valid_until: '2026-12-31' }, '2026-10-01'), true, 'a voucher');
  assert.match(page, /promotions\.filter\(p => liveOnDay\(p, promotionDay\) \|\| p\.id === l\.promotion_id\)/);
  assert.match(page, /const promotionDay = cBusinessDate/, 'a back-dated invoice is offered what ran on its date (the Owner, 9 Oct 2026)');
});

test('CREATE-4: a promotion line sends only its own promotion\'s picks', () => {
  assert.match(page, /withCatalogueItem\(l, \{ promotion_id: v \}, \{ selections: \{\} \}\)/, 'another promotion starts with no picks');
  assert.match(between("value={line.kind} onChange", 'style={{ width: 130 }}'), /selections: \{\},/, 'another kind of line keeps none');
  assert.match(page, /Object\.keys\(l\.selections\)\.filter\(groupId => groupsFor\(l\.promotion_id\)\.some\(g => g\.id === groupId\)\)/);
});

test('CREATE-14 (417, Q4 = A): the bin only where a delete can succeed, and a reason with it', () => {
  const del = lib.canDeleteInvoice;
  assert.equal(del({ status: 'unpaid', paid_amount: 0 }), true);
  assert.equal(del({ status: 'draft', paid_amount: '0' }), true);
  for (const status of ['completed_foc', 'paid', 'partially_paid', 'cancelled', 'refunded', 'refund_requested', 'cancellation_requested']) {
    assert.equal(del({ status, paid_amount: 0 }), false, status);
  }
  assert.equal(del({ status: 'unpaid', paid_amount: 5 }), false, 'money held');
  assert.equal(del({ status: 'unpaid', paid_amount: 0, is_exchange: true }), false, 'an exchange');
  assert.equal(del({ status: 'unpaid', paid_amount: 0, is_topup: true }), false, 'a top-up');
  assert.match(page, /rpc\('delete_invoice', \{ p_invoice_id: inv\.id, p_reason: reason \}\)/);
  assert.match(between('const handleDelete = async', 'Refund and cancellation requests'), /if \(!reason\) \{ setDeleteErr\(/, 'no reason, no call');
  assert.doesNotMatch(page, /Paid invoices cannot be deleted/, 'the server says why, not a page special case');
  assert.match(between("detail.status === 'completed_foc'", ': <>{copyButtons}\n'), /\{copyButtons\}\{refundCancelButton\}/,
    'a completed FOC is undone with the guided Cancel');
});

test('CREATE-19: FOC is not offered to Inventory Managers; Confirm FOC asks; Remove FOC takes a reason', () => {
  assert.equal(lib.canGiveFoc('inventory_manager'), false);
  for (const r of ['owner', 'manager', 'staff', 'admin']) assert.equal(lib.canGiveFoc(r), true, r);
  assert.equal((page.match(/canGiveFoc\(profile\?\.role\)/g) ?? []).length, 3, 'Make FOC, Remove FOC and Confirm FOC');
  assert.match(page, /This closes \{detail\.invoice_no\} as free of charge and takes the stock\./);
  assert.match(page, /rpc\('remove_line_foc', \{ p_invoice_item_id: itemId, p_reason: reason\.trim\(\) \|\| null \}\)/);
  assert.match(page, /'completed_foc', 'cancelled', 'refunded'\];/, 'the list can be filtered to FOC invoices');
  assert.match(page, /s === 'completed_foc' \? 'FOC \(completed\)'/);
  assert.match(page, /Press Review Changes again to apply the correction\./);
  assert.match(page, /&& detail\.status !== 'completed_foc' && !\(detail\.is_full_foc && Number\(detail\.total_amount\) <= 0\)/,
    'no payment entry on a completed FOC or a fully FOC S$0 invoice');
  const confirm = between('const handleConfirmFoc = async', 'const handleApplyLineFoc');
  assert.ok(confirm.indexOf('await refreshDetail(invoiceId)') < confirm.indexOf('setFocErr(\'Prices changed'), 'repriced: the invoice is reloaded before the message');
});

test('W4-B04-IM-ADD-CUSTOMER: New Invoice\'s own Add customer button is not shown to Inventory Managers', () => {
  assert.equal(lib.canAddCustomer('inventory_manager'), false);
  for (const r of ['owner', 'admin', 'manager', 'staff']) assert.equal(lib.canAddCustomer(r), true, r);
  for (const r of [null, undefined, '', 'viewer']) assert.equal(lib.canAddCustomer(r), false, String(r));
  const field = between('<label>Customer *</label>', '{issuedHeaderBefore &&');
  assert.match(field, /<CustomerSearchSelect value=\{cCustomer\}/, 'everyone still searches for and picks a customer');
  assert.match(field, /\{canAddCustomer\(profile\?\.role\) && \(\s*<button type="button" className="btn btn-secondary btn-sm"\s*onClick=\{\(\) => setQuickCustomerFor\(\{ target: 'invoice' \}\)\}>/,
    'the button is drawn only for a role that may add customers');
  assert.equal((page.match(/setQuickCustomerFor\(\{ target: 'invoice' \}\)/g) ?? []).length, 1, 'no other way into the page\'s own Add a customer window');
});

test('W4-B04-IM-ADD-CUSTOMER: nor is the split panels\' row + (Credit Package and Premium Bundle across customers)', () => {
  for (const f of ['src/components/CreditPackageSplitPanel.tsx', 'src/components/PremiumBundleSplitPanel.tsx']) {
    const src = readFileSync(f, 'utf8');
    assert.match(src, /import \{ canAddCustomer \} from '\.\.\/lib\/invoices\/business';/, `${f}: the page's own rule`);
    assert.match(src, /const \{ profile \} = useAuth\(\);\s*const mayAddCustomer = canAddCustomer\(profile\?\.role\);/, `${f}: for the signed-in role`);
    assert.equal(src.split('title="Add a customer for this row"').length - 1, 1, `${f}: one row + button`);
    assert.match(src, /\{mayAddCustomer && \(\s*<button type="button" className="btn btn-secondary btn-sm" title="Add a customer for this row"\s*onClick=\{\(\) => setAddCustomerRow\(i\)\}>\+<\/button>\s*\)\}/,
      `${f}: the row + is drawn only for a role that may add customers`);
    assert.equal((src.match(/setAddCustomerRow\(i\)/g) ?? []).length, 1, `${f}: no other way into its Add a customer window`);
    assert.equal((src.match(/<QuickCustomerModal/g) ?? []).length, 1, `${f}: one Add a customer window`);
    assert.match(src, /\{mayAddCustomer && addCustomerRow !== null && \(\s*<QuickCustomerModal/, `${f}: and the window itself is guarded`);
    assert.match(src, /onClick=\{addRow\}>\+ Add another person<\/button>/, `${f}: the button that only adds a row`);
    assert.doesNotMatch(src, />\+ Add Customer</, `${f}: no 'Add Customer' label left`);
  }
  assert.equal((page.match(/<QuickCustomerModal/g) ?? []).length, 1, 'the page mounts no other Add a customer window');
});

test('CREATE-18: what could never run is gone; status types stay for history', () => {
  for (const gone of ['PaymentPriceReview', 'priceReview', "from('therapy_package_rules')", 'is_voucher_claim &&', 'canEditOrdinary',
                      'const prodName', 'const creditLineName', 'const wholeVoucherBase', 'const staffName', 'calendarDateInRange']) {
    assert.ok(!page.includes(gone), `${gone} is still in the page`);
  }
  const types = readFileSync('src/types/index.ts', 'utf8');
  assert.match(types, /refund_requested: 'Refund Requested'/, 'the retired statuses keep their labels');
  assert.match(readFileSync('src/lib/invoices/business.ts', 'utf8'), /export function invoiceDateSearch/, 'invoiceDateSearch is kept');
});
