/**
 * The manual discount reason is internal.
 *
 * It lives on the invoice for staff and in the audit history. It must not be
 * carried into anything the customer receives — the printed A5, the PDF, the
 * WhatsApp/email message — nor into the accounting exports. Those builders
 * assemble their payloads field by field; this asserts none of them names the
 * column, so a future "spread the whole invoice" cannot leak it unnoticed.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const page = read('src/pages/InvoicesPage.tsx');

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
    assert.doesNotMatch(block(page, marker), /manual_discount_reason|cDiscountReason/,
      `${marker.trim()} carries the internal reason into a customer document`);
  }
  // The A5 print template is inline HTML: no reason anywhere in it.
  const printHtml = page.slice(page.indexOf('printA5Document('), page.indexOf('printA5Document(') + 6000);
  assert.doesNotMatch(printHtml, /manual_discount_reason/, 'the print template names the reason');
});

test('the share message and the document libraries never mention it', () => {
  for (const f of ['src/lib/sendDoc.ts', 'src/lib/invoicePdf.ts', 'src/lib/printDoc.ts']) {
    assert.doesNotMatch(read(f), /manual_discount_reason/, `${f} references the reason`);
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
});
