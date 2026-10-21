// What the customer's copies of an invoice say (B16): src/lib/invoices/customerCopy.ts.
//
// AFTER-10: a refunded or cancelled invoice's copies said REFUNDED or
// CANCELLED but showed neither the money given back nor any still due, and the
// print ("Total Paid", every receipt) and the PDF ("Paid", the net figure,
// dropped at 0) disagreed. Both now take their rows from one builder, fed by
// invoice_financial_position: Paid (every receipt), then Refunded and Net paid
// when money went back, then Refund due when some is still owed back.
//
// Q7 (the Owner, 9 Oct 2026, option 1): an FOC reason is internal; every copy
// says 'FOC' and its value only. W4-B16-PRICE-REASON (the Owner, 18 Oct
// 2026): a hand-changed price's reason is internal too; every copy says
// 'Manual price override' only, and staff see the reason on screen. AFTER-9: a promotion's contents and top-up,
// and an exchange invoice's labels, on the PDF and image as on the print.
// CREATE-18: the print escapes quotes too, as some values sit in attributes.
//
// Run: node --test scripts/invoices/tests/copy-refund-rows.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoices/customerCopy';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'node',
});
const { copyMoneyRows, focCopyNote, priceOverrideCopyNote, promotionCopyNotes, exchangeCopyLabels, escapeHtml } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

test('a fully refunded invoice: every receipt, the refund, and nothing left', () => {
  // Paid S$6,000, all of it refunded: the print used to say "Total Paid S$6000.00" and nothing else.
  assert.deepEqual(copyMoneyRows({ paid: 6000, refunded: 6000, netPaid: 0, refundDue: 0 }),
    [['Paid', 'S$6000.00'], ['Refunded', '−S$6000.00'], ['Net paid', 'S$0.00']]);
});

test('a cancelled invoice still holding money: the refund still due', () => {
  assert.deepEqual(copyMoneyRows({ paid: 40, refunded: 0, netPaid: 40, refundDue: 40 }),
    [['Paid', 'S$40.00'], ['Refund due', 'S$40.00']]);
});

test('part refunded, part still due back', () => {
  assert.deepEqual(copyMoneyRows({ paid: 1000, refunded: 250, netPaid: 750, refundDue: 100, minus: '-' }),
    [['Paid', 'S$1000.00'], ['Refunded', '-S$250.00'], ['Net paid', 'S$750.00'], ['Refund due', 'S$100.00']]);
});

test('an ordinary paid invoice says Paid once; an unpaid one says nothing', () => {
  assert.deepEqual(copyMoneyRows({ paid: 100, refunded: 0, netPaid: 100, refundDue: 0 }), [['Paid', 'S$100.00']]);
  assert.deepEqual(copyMoneyRows({ paid: 0 }), []);
  // No financial position read yet: net is worked out from the receipts.
  assert.deepEqual(copyMoneyRows({ paid: 50, refunded: 20 }), [['Paid', 'S$50.00'], ['Refunded', '−S$20.00'], ['Net paid', 'S$30.00']]);
  // Amounts as the database sends them (strings) and cents that do not float exactly.
  assert.deepEqual(copyMoneyRows({ paid: '0.10', refunded: '0.07', netPaid: '0.03' }),
    [['Paid', 'S$0.10'], ['Refunded', '−S$0.07'], ['Net paid', 'S$0.03']]);
});

test('Q7: a line\'s FOC is "FOC" and its value, never its reason', () => {
  assert.equal(focCopyNote({ quantity: 2, foc_quantity: 2, foc_amount: 360, foc_reason: 'Birthday gift for a friend' }),
    'FOC (full line) — value S$360.00');
  assert.equal(focCopyNote({ quantity: 3, foc_quantity: 1, foc_amount: '25' }), 'FOC 1 of 3 free — value S$25.00');
  assert.equal(focCopyNote({ quantity: 3, foc_quantity: 0 }), null);
  // The pages use it, and the print no longer adds the reason.
  const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
  const print = page.slice(page.indexOf('const printInvoice = '), page.indexOf('const statusOptions'));
  assert.doesNotMatch(print, /foc_reason/, 'the printed copy never names the FOC reason');
  const pdf = page.slice(page.indexOf('const buildPdfDoc = '), page.indexOf('const sendPdf = '));
  assert.doesNotMatch(pdf, /foc_reason/, 'nor does the PDF (and so the WhatsApp and email copies)');
  assert.match(pdf, /focCopyNote\(it\)/);
});

test('W4-B16-PRICE-REASON: a hand-changed price says so on every copy, never its reason', () => {
  assert.equal(priceOverrideCopyNote({ price_overridden: true, override_reason: 'Fixture reason: old shelf tag' }), 'Manual price override');
  assert.equal(priceOverrideCopyNote({ price_overridden: true, override_reason: null }), 'Manual price override');
  assert.equal(priceOverrideCopyNote({ price_overridden: false, override_reason: 'left over' }), null);
  assert.equal(priceOverrideCopyNote({}), null);
  const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
  const print = page.slice(page.indexOf('const printInvoice = '), page.indexOf('const statusOptions'));
  assert.ok(print.length > 1000 && print.includes('CUSTOMER COPY'), 'the print builder was found');
  assert.doesNotMatch(print, /override_reason/, 'the printed copy never names the reason');
  assert.match(print, /const priceNote = priceOverrideCopyNote\(it\);/);
  const pdf = page.slice(page.indexOf('const buildPdfDoc = '), page.indexOf('const sendPdf = '));
  assert.ok(pdf.length > 1000, 'the PDF builder was found');
  assert.doesNotMatch(pdf, /override_reason/, 'nor does the PDF (and so the image, WhatsApp and email copies)');
  assert.match(pdf, /const priceNote = priceOverrideCopyNote\(it\);\s*if \(priceNote\) notes\.push\(priceNote\);/);
  // On screen, for staff: the line says so with its internal reason.
  const screen = page.slice(page.indexOf('const priceOverrideDetail = '), page.indexOf('const [sendErr, setSendErr]'));
  assert.match(screen, /internal reason:/);
  assert.match(screen, /it\.override_reason/);
  assert.match(page, /\{lineDiscountDetail\(it\)\}\s*\{priceOverrideDetail\(it\)\}/, 'shown under the line on the invoice screen');
  // Only the screen reads the reason.
  assert.equal((page.match(/override_reason/g) ?? []).length, 2, 'the page reads override_reason only in priceOverrideDetail');
});

test('AFTER-9: what is inside a promotion, and its top-up', () => {
  const nameOf = x => x.name;
  assert.deepEqual(promotionCopyNotes(2, [{ name: 'Knee Band', quantity: 1 }], [{ name: 'Water Bottle', quantity: 3 }], nameOf, 20),
    ['Knee Band × 2 (included)', 'Water Bottle × 3 (chosen)', 'incl. top-up S$20.00']);
  assert.deepEqual(promotionCopyNotes(1, [], [], nameOf, 0), []);
});

test('AFTER-9: an exchange invoice says so; any other does not', () => {
  assert.deepEqual(exchangeCopyLabels({ found: true, original_invoice_no: 'INV-T-0001' }), {
    headerNote: 'Exchange invoice: replaces items from INV-T-0001',
    discountLabel: 'Exchange credit applied', totalLabel: 'Net top-up' });
  assert.deepEqual(exchangeCopyLabels(null), { headerNote: null, discountLabel: 'Discount', totalLabel: 'Total' });
  assert.deepEqual(exchangeCopyLabels({ found: false }), { headerNote: null, discountLabel: 'Discount', totalLabel: 'Total' });
});

test('CREATE-18: the print escapes everything an attribute could be closed by', () => {
  assert.equal(escapeHtml(`https://x.test/a.png" onerror="alert(1)`), 'https://x.test/a.png&quot; onerror=&quot;alert(1)');
  assert.equal(escapeHtml(`<b>Tom & Jerry's</b>`), '&lt;b&gt;Tom &amp; Jerry&#39;s&lt;/b&gt;');
  assert.equal(escapeHtml(null), '');
});
