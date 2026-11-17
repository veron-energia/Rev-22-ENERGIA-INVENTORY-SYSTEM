// The user, 17 Nov 2026: two changes to how an invoice prints.
//  1. 'Balance due' on every copy (both printed halves, the PDF, the image) and on the invoice
//     screen: right after 'Paid' (after 'Net paid' when money went back, before 'Refund due'), even
//     at S$0.00, and the Payment Methods section is there even before any payment. Left out when
//     the financial position could not be read.
//  2. An 'Office notes (not on the customer copy)' block on the OFFICE COPY of the paper print only:
//     the internal notes and the reasons for a discount, an FOC, a price change, a refund and a
//     payment correction.
//
// Run: node --test scripts/invoices/tests/balance-due-office-notes.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoices/customerCopy';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'node',
});
const { copyMoneyRows, officeNoteLines, noteHtml } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
const between = (s, a, b) => { const i = s.indexOf(a); assert.ok(i >= 0, `${a} found`); const j = s.indexOf(b, i); assert.ok(j > i, `${b} found`); return s.slice(i, j); };

// ---- Balance due -------------------------------------------------------------------------------

test('fully paid: Paid S$994.00 then Balance due S$0.00', () => {
  assert.deepEqual(copyMoneyRows({ paid: 994, refunded: 0, netPaid: 994, refundDue: 0, outstanding: 0 }),
    [['Paid', 'S$994.00'], ['Balance due', 'S$0.00']]);
});

test('part paid: what is still owed', () => {
  assert.deepEqual(copyMoneyRows({ paid: 400, refunded: 0, netPaid: 400, refundDue: 0, outstanding: 594 }),
    [['Paid', 'S$400.00'], ['Balance due', 'S$594.00']]);
});

test('unpaid: the section still says Paid S$0.00 and what is owed', () => {
  assert.deepEqual(copyMoneyRows({ paid: 0, refunded: 0, netPaid: 0, refundDue: 0, outstanding: 994 }),
    [['Paid', 'S$0.00'], ['Balance due', 'S$994.00']]);
});

test('credit paid everything: Paid S$0.00 and Balance due S$0.00', () => {
  assert.deepEqual(copyMoneyRows({ paid: 0, refunded: 0, netPaid: 0, refundDue: 0, outstanding: '0' }),
    [['Paid', 'S$0.00'], ['Balance due', 'S$0.00']]);
});

test('with refunds: Paid, Refunded, Net paid, Balance due, Refund due, in that order', () => {
  assert.deepEqual(copyMoneyRows({ paid: 1000, refunded: 250, netPaid: 750, refundDue: 100, outstanding: 0, minus: '-' }),
    [['Paid', 'S$1000.00'], ['Refunded', '-S$250.00'], ['Net paid', 'S$750.00'], ['Balance due', 'S$0.00'], ['Refund due', 'S$100.00']]);
  // A cancelled invoice (the position gives outstanding 0) still holding money.
  assert.deepEqual(copyMoneyRows({ paid: 40, refunded: 0, netPaid: 40, refundDue: 40, outstanding: 0 }),
    [['Paid', 'S$40.00'], ['Balance due', 'S$0.00'], ['Refund due', 'S$40.00']]);
});

test('position not read: no Balance due is guessed, and the rows are as before', () => {
  assert.deepEqual(copyMoneyRows({ paid: 0 }), []);
  assert.deepEqual(copyMoneyRows({ paid: 0, outstanding: undefined }), []);
  assert.deepEqual(copyMoneyRows({ paid: 0, outstanding: null }), []);
  assert.deepEqual(copyMoneyRows({ paid: 0, outstanding: '' }), []);
  assert.deepEqual(copyMoneyRows({ paid: 100 }), [['Paid', 'S$100.00']]);
});

test('every copy takes Balance due from the shared rows; the screen says Balance due', () => {
  const print = between(page, 'const printInvoice = async', 'const copyButtons = detail');
  assert.equal((print.match(/outstanding: detailFinancial\?\.outstanding/g) ?? []).length, 2, 'both print branches pass it');
  assert.match(print, /\$\{payRows \|\| moneyRowsHtml \? `<h2>Payment Methods<\/h2>/, 'the section is there whenever there are rows');
  const pdf = between(page, 'const buildPdfDoc = ', 'const sendPdf = ');
  assert.equal((pdf.match(/outstanding: detailFinancial\?\.outstanding/g) ?? []).length, 2, 'the PDF and image pass it too');
  assert.match(pdf, /minus: '-'/, 'the PDF keeps its ASCII minus');
  assert.doesNotMatch(pdf, /\['Balance', /, 'the old PDF-only Balance row is gone: one row, from the shared helper');
  assert.match(page, /<span>Balance due<\/span><strong>\{money\(Number\(detailFinancial\?\.outstanding \?\? 0\)\)\}<\/strong>/);
  assert.doesNotMatch(page, /Remaining balance/);
});

// ---- Office notes ------------------------------------------------------------------------------

const names = ['Test Cream', 'Test Massage'];
const base = {
  lineName: i => names[i],
  focReasonName: id => (id === 'r1' ? 'Staff gift' : null),
  day: x => `D(${x})`,
};

test('nothing to say: no lines, so no block', () => {
  assert.deepEqual(officeNoteLines({}), []);
  assert.deepEqual(officeNoteLines({ ...base, invoice: { notes: ' \n ', manual_discount_reason: null },
    items: [{ line_discount_reason: '', foc_reason: null, override_reason: '  ' }], refunds: [{ reason: null, amount: 5 }], payments: [{ correction_reason: '' }] }), []);
});

test('invoice notes and the whole-invoice discount reason, printed as they are', () => {
  assert.deepEqual(officeNoteLines({ ...base, invoice: { notes: 'Website order ref_TEST123\r\nsecond line', manual_discount_reason: 'Loyal customer' } }),
    ['Internal notes: Website order ref_TEST123\nsecond line', 'Discount reason: Loyal customer']);
});

test('each line: discount, FOC and price change reasons, numbered as the lines print', () => {
  const lines = officeNoteLines({ ...base, items: [
    { line_discount_reason: 'Damaged box', foc_reason_id: null, foc_reason: null, override_reason: null },
    { line_discount_reason: null, foc_reason_id: 'r1', foc_reason: 'sample for a friend', override_reason: 'Shelf tag was old' },
  ] });
  assert.deepEqual(lines, [
    'Line 1 · Test Cream · Discount reason: Damaged box',
    'Line 2 · Test Massage · FOC reason: Staff gift — sample for a friend',
    'Line 2 · Test Massage · Price change reason: Shelf tag was old',
  ]);
});

test('an FOC reason: the saved text already starts with the name; one gone from the list shows by its text; name alone', () => {
  const one = foc => officeNoteLines({ ...base, items: [foc] });
  assert.deepEqual(one({ foc_reason_id: 'r1', foc_reason: 'Staff gift — sample for a friend' }), ['Line 1 · Test Cream · FOC reason: Staff gift — sample for a friend']);
  assert.deepEqual(one({ foc_reason_id: 'r1', foc_reason: 'Staff gift' }), ['Line 1 · Test Cream · FOC reason: Staff gift']);
  assert.deepEqual(one({ foc_reason_id: 'r1', foc_reason: null }), ['Line 1 · Test Cream · FOC reason: Staff gift']);
  assert.deepEqual(one({ foc_reason_id: 'old', foc_reason: 'Retired reason — note' }), ['Line 1 · Test Cream · FOC reason: Retired reason — note']);
  assert.deepEqual(one({ foc_reason_id: null, foc_reason: 'Typed only' }), ['Line 1 · Test Cream · FOC reason: Typed only']);
});

test('refund and payment correction reasons, only those that have one', () => {
  assert.deepEqual(officeNoteLines({ ...base,
    refunds: [{ reason: 'Customer changed mind', amount: '12.5', created_at: 'T1' }, { reason: null, amount: 3, created_at: 'T2' }],
    payments: [{ correction_reason: 'Wrong method keyed', effective_at: 'T3', created_at: 'T4' }, { correction_reason: null, created_at: 'T5' }, { correction_reason: 'Typo', created_at: 'T6' }] }),
  ['Refund D(T1) (S$12.50): Customer changed mind', 'Payment correction D(T4): Wrong method keyed', 'Payment correction D(T6): Typo']);
});

test('one correction (its reversal and two replacements, the same reason) says its reason once, dated when it was made', () => {
  // On production every correction row carries the reason: correct, split and remove write a reversal and
  // replacements together, with the same reason and moment, but each replacement may keep its own payment date.
  assert.deepEqual(officeNoteLines({ ...base, payments: [
    { correction_reason: null, effective_at: 'P0', created_at: 'P0' },
    { correction_reason: 'Split into cash and card', effective_at: 'P0', created_at: 'C1' },
    { correction_reason: 'Split into cash and card', effective_at: 'P1', created_at: 'C1' },
    { correction_reason: 'Split into cash and card', effective_at: 'P2', created_at: 'C1' },
    { correction_reason: 'Wrong method keyed', effective_at: 'P3', created_at: 'C2' },
    { correction_reason: 'Wrong method keyed', effective_at: 'P3', created_at: 'C2' } ] }),
  ['Payment correction D(C1): Split into cash and card', 'Payment correction D(C2): Wrong method keyed']);
});

test('the page escapes each line and keeps a multi-line note\'s breaks', () => {
  const [line] = officeNoteLines({ ...base, invoice: { notes: `<b>x</b> & "y"\nz` } });
  assert.equal(noteHtml(line), 'Internal notes: &lt;b&gt;x&lt;/b&gt; &amp; &quot;y&quot;<br/>z');
});

test('only the OFFICE COPY half gets the block, between the note and the signatures; never the PDF or image', () => {
  const print = between(page, 'const printInvoice = async', 'const copyButtons = detail');
  assert.match(print, /<h2>Office notes \(not on the customer copy\)<\/h2>\$\{officeLines\.map\(l => `<div>\$\{noteHtml\(l\)\}<\/div>`\)\.join\(''\)\}/);
  assert.match(print, /\$\{noteBlock\}\s*\$\{copyLabel === 'OFFICE COPY' \? officeBlock : ''\}\s*<div class="signrow">/);
  assert.equal((print.match(/officeBlock/g) ?? []).length, 2, 'defined once, printed only in the office copy');
  assert.match(print, /\$\{copyHtml\('CUSTOMER COPY'\)\}[\s\S]*\$\{copyHtml\('OFFICE COPY'\)\}/);
  assert.equal((page.match(/officeNoteLines\(/g) ?? []).length, 1, 'built once, in the print');
  const pdf = between(page, 'const buildPdfDoc = ', 'const sendPdf = ');
  assert.doesNotMatch(pdf, /office/i, 'the PDF (and so the image, WhatsApp and email) never gets it');
  for (const f of ['src/lib/invoicePdf.ts', 'src/lib/invoiceImage.ts']) assert.doesNotMatch(readFileSync(f, 'utf8'), /officeNote|Office notes/);
  // The block's own reasons are read only inside the office helper, never in the print or the PDF builders.
  assert.doesNotMatch(print, /foc_reason|override_reason|line_discount_reason|correction_reason|manual_discount_reason/);
  // Refunds are read with their reason.
  assert.match(page, /from\('invoice_refunds'\)\.select\('id,payment_id,amount,credit_returned,created_at,reason'\)/);
});

test('printPages.mjs counts the office block with the signatures\' row and measures the taller half', () => {
  const src = readFileSync('src/lib/invoices/printPages.mjs', 'utf8');
  assert.match(src, /if \(el\.hasAttribute\('data-p-office'\)\) \{ pending\.push\(el\); continue; \}/);
  assert.match(src, /var measureOne = function \(copy\)/);
  assert.match(src, /measured\.units\[u\]\.rows\[v\] = Math\.max\(/);
});
