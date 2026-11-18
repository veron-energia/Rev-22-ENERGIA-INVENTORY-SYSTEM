// The print window holds no script now (the app's Content-Security-Policy has no 'unsafe-inline'):
// the app, the opener, lays the sheet out and prints (src/lib/printWindow.ts). The browser tests
// serve the print window's HTML as a page of its own, so this stands in for the opener: the same
// steps on that page's document, in the same order (the pages, then the credit block), then the
// print. Run it after `sheet.goto(...)`.
import { PRINT_PAGES_SCRIPT } from '../../../src/lib/invoices/printPages.mjs';
import { CREDIT_BALANCE_FIT_SCRIPT } from '../../../src/lib/invoices/creditBalanceLine.mjs';

export async function runAsOpener(sheet, { credit = true } = {}) {
  await sheet.addScriptTag({ content: `${PRINT_PAGES_SCRIPT}\n${CREDIT_BALANCE_FIT_SCRIPT}` });
  await sheet.evaluate(withCredit => {
    try { paginatePrintCopies(planCopyPages, document); } catch (e) { /* printed as it is */ }
    if (withCredit) { try { fitCreditBalance(document); } catch (e) { /* printed as it is */ } }
    window.print();
  }, credit);
}
