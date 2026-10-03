/**
 * Discount reasons are internal.
 *
 * The invoice-level manual discount's reason, and since 384 the reason of a
 * line's manual or percentage discount, live on the invoice for staff and in
 * the audit history. They must not be carried into anything the customer
 * receives — the printed A5, the PDF, the image, the WhatsApp/email message —
 * nor into the accounting exports. Those builders assemble their payloads
 * field by field; this asserts none of them names a reason, so a future
 * "spread the whole invoice" cannot leak one unnoticed.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const page = read('src/pages/InvoicesPage.tsx');
const lineDiscounts = read('src/lib/invoices/lineDiscounts.ts');
// Either reason, by column or by the form's field for it.
const REASON = /manual_discount_reason|cDiscountReason|line_discount_reason|discount_reason/;

/** Source of one function body, from its declaration to the next top-level `  const ` at the same indent. */
function block(src, startMarker) {
  const i = src.indexOf(startMarker);
  assert.ok(i >= 0, `marker not found: ${startMarker}`);
  const rest = src.slice(i);
  const m = rest.slice(startMarker.length).search(/\n  const [a-zA-Z]/);
  return m < 0 ? rest : rest.slice(0, startMarker.length + m);
}

test('the customer documents never mention the reason', () => {
  for (const marker of ['const buildPdfDoc = ', 'const printInvoice = ', 'const sendInvoice = ']) {
    if (!page.includes(marker)) continue;
    assert.doesNotMatch(block(page, marker), REASON,
      `${marker.trim()} carries an internal reason into a customer document`);
  }
  // The A5 print template is inline HTML: no reason anywhere in it.
  const printHtml = page.slice(page.indexOf('printA5Document('), page.indexOf('printA5Document(') + 6000);
  assert.doesNotMatch(printHtml, /manual_discount_reason/, 'the print template names the reason');
});

test('the share message and the document libraries never mention it', () => {
  for (const f of ['src/lib/sendDoc.ts', 'src/lib/invoicePdf.ts', 'src/lib/invoiceImage.ts', 'src/lib/printDoc.ts']) {
    assert.doesNotMatch(read(f), REASON, `${f} references a reason`);
  }
});

test('the printed line discount is built without the line reason', () => {
  // printInvoice and buildPdfDoc print a line's discount through this one
  // function; it takes the line and the voucher's name, and reads no reason.
  const start = lineDiscounts.indexOf('export function printedLineDiscount(');
  assert.ok(start > 0, 'printedLineDiscount exists');
  const body = lineDiscounts.slice(start, lineDiscounts.indexOf('\n}\n', start));
  assert.doesNotMatch(body, REASON, 'printedLineDiscount reads a reason');
  for (const marker of ['const buildPdfDoc = ', 'const printInvoice = ']) {
    assert.match(block(page, marker), /printedLineDiscount\(it, printedVoucher\(it\.line_voucher_id\)/,
      `${marker.trim()} prints the line's discount by name and amount`);
  }
});

test('the accounting and list exports never mention it', () => {
  for (const f of ['src/components/XeroExport.tsx', 'src/components/PaymentSummaryExport.tsx', 'src/components/ExcelExport.tsx']) {
    assert.doesNotMatch(read(f), /manual_discount_reason/, `${f} references the reason`);
  }
  // The invoice list export is an explicit column list on the page, and the
  // reason is not one of them.
  const exportCols = page.slice(page.indexOf("filename=\"invoices\""), page.indexOf("filename=\"invoices\"") + 2500);
  assert.doesNotMatch(exportCols, /manual_discount_reason/, 'the Excel column list includes the reason');
});

test('the reason is shown where staff work, and only there', () => {
  assert.match(page, /data-testid="invoice-detail-discount-reason"/, 'the internal detail panel shows it');
  assert.match(page, /manual_discount_reason: \(cDiscount \|\| 0\) > 0 \? cDiscountReason\.trim\(\) : null/, 'the form sends it with a positive discount only');
  // A line's reason: on the invoice screen beside the line, for staff.
  assert.match(page, /data-testid="invoice-line-discount-reason"/, 'the invoice screen shows a line\'s reason');
  // And sent only with a manual or percentage discount.
  const payload = lineDiscounts.slice(lineDiscounts.indexOf('export function lineDiscountPayload('));
  const sends = payload.slice(0, payload.indexOf('\n}\n')).match(/line_discount_reason/g) ?? [];
  assert.equal(sends.length, 2, 'line_discount_reason goes with Manual and Percentage only');
});
