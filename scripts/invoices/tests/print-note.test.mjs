// The note printed on the invoice (456, the Owner, 22 Oct 2026, item 6): a NEW field "Note printed on
// the invoice" (up to 500 characters), separate from Notes, which becomes "Internal notes (not printed)"
// and never prints. It shows on the invoice screen, prints on both the customer and office copies above
// the signatures under "Note", and is on the PDF and the image (and so WhatsApp and email). It never gets
// cut: on the PDF a long note moves its tail to the next page. And (item 6, the exchange half) an
// exchange's own note prints under Exchange Details on its replacement invoice.
//
//  - The words every copy shares (src/lib/invoices/customerCopy.ts): print_note, never notes; escaped.
//  - The PDF (src/lib/invoicePdf.ts): the note under NOTE above the signatures, which stay where they
//    are; a long note's tail on the next page, the signatures and the footer after it, every page
//    saying which of how many it is; nothing above the note gives way for it or runs off a page (on a
//    full invoice the payments, the goods and the credit line come out exactly as without the note);
//    an exchange note under EXCHANGE DETAILS.
//  - The page (src/pages/InvoicesPage.tsx): the two boxes, what the form sends and restores, the print,
//    the PDF and image copy, the detail screen. The image is checked in Chrome
//    (scripts/invoices/tests/print-note-browser.mjs). Invented names only.
//
// Run: node --test scripts/invoices/tests/print-note.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoicePdf'; export * from './src/lib/invoices/customerCopy'; export { jsPDF } from 'jspdf';
                      export { copyCollection, copyTermsText } from './src/lib/invoices/handover.mjs';`,
           resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'node',
  external: ['html2canvas', 'dompurify', 'canvg'],
});
const lib = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { buildDocumentPdf, printedNote, exchangeNote, noteHtml, PRINT_NOTE_MAX, copyNoteLines, jsPDF,
  copyCollection, copyTermsText, creditBalanceShown } = lib;
const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
const between = (src, a, b) => { const i = src.indexOf(a); assert.ok(i >= 0, `not found: ${a}`); const j = src.indexOf(b, i); return src.slice(i, j < 0 ? undefined : j); };

// jsPDF writes its standard fonts in WinAnsi: these are single bytes.
const winAnsi = s => s.replace(/\x97/g, '—').replace(/\x85/g, '…').replace(/\xb7/g, '·').replace(/\xe9/g, 'é');
/** Every string drawn on each page, with its position: PDF points, y measured up from the foot. */
function drawnPages(pdf) {
  const out = pdf.output();
  const streams = out.split('endstream').slice(0, -1).map(s => s.slice(s.lastIndexOf('stream') + 6));
  const re = /(-?[\d.]+) (-?[\d.]+) Td\s*\(((?:\\.|[^\\)])*)\) Tj/g;
  return streams.map(st => {
    const items = [];
    for (let m; (m = re.exec(st));) items.push({ x: Number(m[1]), y: Number(m[2]), text: winAnsi(m[3].replace(/\\([()\\])/g, '$1')) });
    return items;
  }).filter(p => p.length);
}
const PT_PER_MM = 72 / 25.4;
const ON_PAGE = 8 * PT_PER_MM;
const yOf = (items, text) => { const it = items.find(i => i.text === text); assert.ok(it, `"${text}" was not drawn`); return it.y; };
const footerY = items => { const f = items.filter(i => i.text.includes('Co. Reg No.')); assert.ok(f.length, 'footer drawn'); return f[f.length - 1].y; };
const POLICY = 'Items may be exchanged within 7 days with the receipt and the original box, after a check in store. '
  + 'Orders paid by deposit are final. Therapy packages run 12 months from the day they start.';
const doc = (lines, pays, over = {}) => ({
  kindLabel: 'Tax Invoice', docNo: 'INV-T-0456', date: '22/10/2026', status: 'PAID', storeName: 'Test Store',
  storeAddress: '1 Example Road #01-01, Singapore 000001', storePhone: '+6560000000 · WhatsApp +6590000000',
  customerName: 'Test Customer (-)', customerContact: '+61255504560 · test.customer@example.com',
  lines: Array.from({ length: lines }, (_, n) => ({ name: `Test item ${n + 1}`, qty: 1, unit: 10, total: 10, notes: [] })),
  totals: [['Subtotal', 'S$10.00'], ['Discount', '-S$0.00'], ['Paid', 'S$10.00']], grandTotal: ['Total', 'S$10.00'],
  payments: Array.from({ length: pays }, (_, n) => [`Cash · 0${(n % 9) + 1}/10/2026`, 'S$5.00']),
  creditBalance: null, staffName: 'Test Owner', policyText: POLICY,
  payDetails: ['CIMB UEN: TEST0001X', 'CIMB corporate account: 000-000000-0'],
  footerBits: ['DID: +6560000000', 'Email: shop@example.test', 'Website: example.test', 'Co. Reg No.: TEST0001X'],
  ...over,
});
/** The note's own lines as drawn (every page), in order: between NOTE and the signatures. */
const noteLinesDrawn = (pages, note) => {
  const want = new Set(note.split('\n').filter(Boolean));
  return pages.flat().filter(i => want.has(i.text)).map(i => i.text);
};

test('every copy prints print_note, never the internal Notes, and escapes it', () => {
  assert.equal(PRINT_NOTE_MAX, 500);
  assert.equal(printedNote({ print_note: '  Collect on Friday.  ', notes: 'Website order cs_test_x' }), 'Collect on Friday.');
  assert.equal(printedNote({ notes: 'Website order cs_test_x' }), null, 'the internal Notes never print');
  assert.equal(printedNote({ print_note: ' \n\t ' }), null);
  assert.equal(printedNote(null), null);
  assert.equal(printedNote({ print_note: 'One\r\nTwo  \n\n\n\nThree' }), 'One\nTwo\n\nThree', 'line breaks kept, blank runs made one');
  assert.equal(exchangeNote({ found: true, notes: ' Larger size \n' }), 'Larger size');
  assert.equal(exchangeNote({ found: false, notes: 'x' }), null);
  assert.equal(exchangeNote(null), null);
  assert.equal(noteHtml('<b>Test</b> & "Co" \'s\nNext'), '&lt;b&gt;Test&lt;/b&gt; &amp; &quot;Co&quot; &#39;s<br/>Next');
});

test('the PDF draws the note under NOTE, above the signatures; on a short invoice nothing below it moves', () => {
  const note = 'Thank you, Test Customer.\nCollect the second pair on Friday.';
  for (const [lines, pays] of [[1, 1], [3, 2], [5, 1]]) {
    const withNote = buildDocumentPdf(doc(lines, pays, { note }));
    const without = buildDocumentPdf(doc(lines, pays));
    const at = `${lines} line(s), ${pays} payment(s)`;
    assert.equal(withNote.getNumberOfPages(), 1, `${at}: one page`);
    const [p] = drawnPages(withNote), [q] = drawnPages(without);
    const sig = yOf(p, 'Staff Signature');
    assert.ok(yOf(p, 'NOTE') > yOf(p, 'Thank you, Test Customer.') && yOf(p, 'Thank you, Test Customer.') > yOf(p, 'Collect the second pair on Friday.'));
    assert.ok(yOf(p, 'Collect the second pair on Friday.') > sig, `${at}: above the signatures`);
    assert.ok(yOf(p, 'NOTE') < yOf(p, 'Cash · 01/10/2026'), `${at}: under the payments`);
    assert.ok(sig <= yOf(q, 'Staff Signature') + 0.01, `${at}: the signatures never go up`);
    assert.ok(footerY(p) >= ON_PAGE - 0.01, `${at}: the footer stays on the page`);
    if (lines <= 3) {
      assert.equal(sig, yOf(q, 'Staff Signature'), `${at}: the signatures stay where they are`);
      assert.equal(footerY(p), footerY(q), `${at}: and the footer`);
    }
    assert.ok(!q.some(i => i.text === 'NOTE'), 'no note, no heading');
  }
});

test('a long note never gets cut: its tail goes on to the next page, then the signatures and the footer', () => {
  // 500 characters, most of them line breaks between short lines, on a full invoice.
  const lines = Array.from({ length: 60 }, (_, n) => `Fixture line ${n + 1}`);
  let note = ''; for (const l of lines) { if ((note + l + '\n').length > 500) break; note += l + '\n'; }
  note = note.trim();
  assert.ok(note.length <= 500 && note.split('\n').length >= 30);
  for (const [items, pays] of [[1, 1], [6, 2], [9, 1], [14, 12]]) {
    const pdf = buildDocumentPdf(doc(items, pays, { note }));
    const pages = drawnPages(pdf);
    const n = pdf.getNumberOfPages();
    const at = `${items} item(s), ${pays} payment(s)`;
    assert.equal(pages.length, n, `${at}: one content stream a page`);
    assert.ok(n >= 2, `${at}: the note takes another page`);
    assert.deepEqual(noteLinesDrawn(pages, note), note.split('\n'), `${at}: every line of the note, in order`);
    const last = pages.at(-1);
    assert.ok(last.some(i => i.text === 'Staff Signature') && !pages.slice(0, -1).some(p => p.some(i => i.text === 'Staff Signature')),
      `${at}: the signatures once, on the last page`);
    // On each page, every note line is above where the signatures are pinned.
    const sigLine = yOf(last, 'Staff Signature');
    for (const p of pages) {
      for (const i of p.filter(i => note.split('\n').includes(i.text))) assert.ok(i.y > sigLine, `${at}: "${i.text}" above the signature line`);
    }
    assert.ok(footerY(last) >= ON_PAGE - 0.01, `${at}: the footer on its page`);
    assert.ok(pages.flat().every(i => i.y >= ON_PAGE - 0.01 - 3 * PT_PER_MM), `${at}: nothing drawn off the foot of a page`);
    for (let k = 2; k <= n; k++) {
      assert.ok(pages[k - 2].some(i => i.text === `Continued on page ${k}`), `${at}: page ${k - 1} says it goes on`);
      assert.ok(pages[k - 1].some(i => i.text === 'INV-T-0456 (continued)') && pages[k - 1].some(i => i.text === `Page ${k} of ${n}`),
        `${at}: page ${k} says which it is of ${n}`);
    }
    assert.ok(!pages.flat().some(i => i.text.startsWith('…continued')), `${at}: no item row left off`);
  }
});

test('a note that just fits stays on the page, using the room under the footer; one line more goes on to the next', () => {
  for (const items of [1, 3, 6]) {
    const pdfOf = n => buildDocumentPdf(doc(items, 1, { note: Array.from({ length: n }, (_, i) => `Short line ${i + 1}`).join('\n') }));
    let k = 1;
    while (pdfOf(k).getNumberOfPages() === 1) k++;
    const fit = drawnPages(pdfOf(k - 1)), over = drawnPages(pdfOf(k));
    const pinned = yOf(drawnPages(buildDocumentPdf(doc(items, 1)))[0], 'Staff Signature');
    assert.ok(k - 1 >= (items < 6 ? 6 : 2), `${items} item(s): room for ${k - 1} lines`);
    assert.equal(fit.length, 1);
    assert.ok(footerY(fit[0]) >= ON_PAGE - 0.01 && footerY(fit[0]) < ON_PAGE + 4 * PT_PER_MM,
      `${items} item(s): the longest note that fits takes the room down to the foot of the page`);
    assert.ok(yOf(fit[0], 'Staff Signature') < pinned, `${items} item(s): the signatures moved down into it`);
    assert.equal(over.length, 2);
    assert.ok(over[1].some(i => i.text === `Short line ${k}`) && over[0].some(i => i.text === `Short line ${k - 1}`),
      `${items} item(s): the tail, and only the tail, moves`);
    assert.equal(yOf(over[1], 'Staff Signature'), pinned, `${items} item(s): on the next page the signatures are where they always are`);
  }
});

// A long invoice: every other line with a line-discount note, instalments, and (rich) a part-paid
// invoice's goods (4 collected, 4 to collect) and a credit balance with where it came from.
const goods = n => ({ products: Array.from({ length: n }, (_, k) => ({ product_id: `p${k}`, name: `Test Product ${k + 1}`,
  required: 2, collected: k % 2, to_collect: 2 - (k % 2), out: k % 2, in_store: 5, via: [] })) });
const longDoc = (items, pays, rich, over = {}) => doc(items, pays, {
  lines: Array.from({ length: items }, (_, n) => ({ name: `Test item ${n + 1}`, qty: 1, unit: 10, total: 10, notes: n % 2 ? ['Line discount 10%'] : [] })),
  payments: Array.from({ length: pays }, (_, n) => [`Instalment ${n + 1}`, 'S$5.00']),
  payDetails: ['Instalment 6 months', 'CIMB UEN: TEST0001X', 'CIMB corporate account: 000-000000-0'],
  ...(rich ? { status: 'PARTIALLY_PAID', termsText: copyTermsText('partially_paid'), collection: copyCollection('partially_paid', goods(8)),
    creditBalance: { label: 'Credit balance', amount: 'S$120.00', detail: 'Credit Package S$100.00 · Premium Bundle S$20.00' } } : {}),
  ...over,
});
/** What a copy draws before `stop`, page by page, in order: the "(continued)" heads and the page
 *  numbers left out (a note may add a page). */
const drawnBefore = (pages, stop) => {
  const out = [];
  for (const [k, p] of pages.entries()) {
    for (const i of p) {
      if (i.text === stop) return out;
      if (!/^Page \d+ of \d+$|^Continued on page \d+$|\(continued\)$/.test(i.text)) out.push(`${k + 1}|${i.x}|${i.y}|${i.text}`);
    }
  }
  assert.fail(`"${stop}" was not drawn`);
};

test('nothing above the note gives way for it, and nothing above it runs off a page', () => {
  // Each of these drew payment rows, goods or "Continued on page 2" below the foot of page 1 when
  // the note started its own page without the copy's give-way order seeing what was above it.
  const two = 'Thank you, Test Customer.\nCollect the second pair on Friday.';
  const cases = [[9, 10, false, two], [9, 8, false, two], [8, 10, false, two], [6, 14, false, two], [1, 23, false, two],
    [7, 7, true, two], [6, 9, true, two], [5, 11, true, two], [4, 13, true, two], [3, 16, true, two],
    [6, 12, true, 'Thank you, Test Customer.']];
  for (const [items, pays, rich, note] of cases) {
    const at = `${items} item(s), ${pays} payment(s)${rich ? ', goods and credit' : ''}`;
    const bareDoc = longDoc(items, pays, rich), notedDoc = longDoc(items, pays, rich, { note });
    const bare = drawnPages(buildDocumentPdf(bareDoc)), noted = drawnPages(buildDocumentPdf(notedDoc));
    // Nothing on any page lower than the footer's last line may sit on a copy without a note.
    for (const [k, p] of noted.entries()) {
      for (const i of p) assert.ok(i.y >= ON_PAGE - 0.05, `${at}: "${i.text}" on page ${k + 1} is ${(i.y / PT_PER_MM).toFixed(1)} mm from the foot`);
    }
    // Everything above the note is drawn exactly as the same copy draws above its signatures without one.
    assert.deepEqual(drawnBefore(noted, 'NOTE'), drawnBefore(bare, 'Test Owner'), `${at}: nothing above the note moved or gave way`);
    assert.equal(creditBalanceShown(notedDoc), creditBalanceShown(bareDoc), `${at}: the credit line comes out the same`);
    // Every payment, or the one summary row, is on a page; the goods are said.
    const texts = noted.flat().map(i => i.text);
    const listed = Array.from({ length: pays }, (_, n) => `Instalment ${n + 1}`).every(t => texts.includes(t));
    assert.ok(listed || texts.includes(`Payments: ${pays}; full list on the store copy`), `${at}: every payment, or their summary`);
    if (rich) assert.ok(texts.some(t => /^(Collected|To collect):/.test(t)) || /GOODS: \d+ COLLECTED, \d+ TO COLLECT\./.test(texts.join(' ')), `${at}: the goods`);
    // And the note is whole, above the signatures, which come once, on the last page, with the footer.
    assert.deepEqual(noteLinesDrawn(noted, note), note.split('\n'), `${at}: every line of the note`);
    const last = noted.at(-1);
    assert.ok(last.some(i => i.text === 'Staff Signature') && !noted.slice(0, -1).some(p => p.some(i => i.text === 'Staff Signature')), `${at}: signatures on the last page`);
    assert.ok(footerY(last) >= ON_PAGE - 0.05, `${at}: the footer on its page`);
  }
});

test('a word longer than the line is broken, never drawn past the margin', () => {
  const word = 'W'.repeat(300);
  const pdf = buildDocumentPdf(doc(1, 1, { note: word }));
  const measure = new jsPDF({ unit: 'pt', format: 'a5' });
  measure.setFont('helvetica', 'normal'); measure.setFontSize(8.5);
  const parts = drawnPages(pdf).flat().filter(i => /^W+$/.test(i.text));
  assert.equal(parts.map(i => i.text).join(''), word, 'all of it');
  assert.ok(parts.length > 1);
  for (const i of parts) assert.ok(i.x + measure.getTextWidth(i.text) <= (148.5 - 10) * PT_PER_MM + 0.5, 'inside the right margin');
  assert.deepEqual(copyNoteLines('a\n\nb', t => [t]), ['a', '', 'b'], 'a blank line is kept');
});

test('an exchange invoice\'s own note goes under EXCHANGE DETAILS, below the header note', () => {
  const p = drawnPages(buildDocumentPdf(doc(2, 1, { headerNote: 'Exchange invoice: replaces items from INV-T-0001',
    exchangeNote: 'Swapped for the larger size (L).\nThe customer keeps the box.' })))[0];
  assert.ok(yOf(p, 'Exchange invoice: replaces items from INV-T-0001') > yOf(p, 'EXCHANGE DETAILS'));
  assert.ok(yOf(p, 'EXCHANGE DETAILS') > yOf(p, 'Note: Swapped for the larger size (L).'));
  assert.ok(yOf(p, 'Note: Swapped for the larger size (L).') > yOf(p, 'The customer keeps the box.'));
  assert.ok(yOf(p, 'The customer keeps the box.') > yOf(p, 'BILL TO'), 'above Bill To');
  assert.ok(!drawnPages(buildDocumentPdf(doc(2, 1)))[0].some(i => i.text === 'EXCHANGE DETAILS'), 'and only with an exchange note');
});

test('the page: two boxes, the printed one sent, restored and cleared; the internal one never on a copy', () => {
  assert.match(page, /<label>Note printed on the invoice\s*<textarea data-testid="invoice-print-note" value=\{cPrintNote\} maxLength=\{PRINT_NOTE_MAX\}/);
  assert.match(page, /<label>Internal notes \(not printed\)<textarea data-testid="invoice-internal-notes" value=\{cNotes\}/);
  assert.doesNotMatch(page, /<label>Notes<textarea/, 'the old label is gone');
  assert.match(between(page, 'const resetCreate = () => {', '};'), /setCNotes\(''\); setCPrintNote\(''\);/, 'a new form starts blank');
  assert.match(page, /setCPrintNote\(detail\.print_note \?\? ''\);/, 'Edit and Correct start from the saved note');
  assert.match(between(page, 'const header = {', '};'), /print_note: cPrintNote\.trim\(\) \|\| null,/, 'always sent, so clearing it clears it');
  assert.match(between(page, 'const conflictRows = ', '];'), /row\('Printed note', String\(b\.print_note \?\? '—'\), String\(a\.print_note \?\? '—'\)\)/);
  assert.match(between(page, 'const conflictRows = ', '];'), /row\('Internal notes', String\(b\.notes/);
  // The print: on both halves (copyHtml is drawn twice), after the goods, before the signatures.
  const print = between(page, 'const printInvoice = async', 'const copyButtons = detail');
  assert.match(print, /const printNote = printedNote\(detail\);/);
  // data-p-lines: a note taller than a page goes on between its lines (item 5, printPages.mjs).
  assert.match(print, /<h2>Note<\/h2><div data-testid="print-note" data-p-lines style="flex:0 0 auto;overflow-wrap:anywhere">\$\{noteHtml\(printNote\)\}<\/div>/);
  assert.match(print, /\$\{collectionBlock\}\s*\$\{noteBlock\}\s*<div class="signrow">/);
  assert.match(print, /\$\{copyHtml\('CUSTOMER COPY'\)\}[\s\S]*\$\{copyHtml\('OFFICE COPY'\)\}/);
  assert.match(print, /Note: \$\{noteHtml\(exNote\)\}/, 'the exchange note under Exchange Details');
  assert.ok(print.indexOf('<h2>Exchange Details</h2>') < print.indexOf('Note: ${noteHtml(exNote)}')
    && print.indexOf('Note: ${noteHtml(exNote)}') < print.indexOf('<th>Returned Item</th>'));
  // The PDF and image (and so WhatsApp and email) are built from one doc.
  const pdf = between(page, 'const buildPdfDoc = async', 'return { pdf, invoiceId');
  assert.match(pdf, /exchangeNote: exchangeNote\(detailExchange\),\s*note: printedNote\(detail\),/);
  // The internal Notes are on no copy.
  for (const part of [print, pdf]) assert.doesNotMatch(part, /\.notes\b/, 'no copy reads the internal Notes');
  // The detail screen shows the printed note, and an exchange's note.
  assert.match(page, /data-testid="invoice-detail-print-note"[\s\S]{0,200}<strong>Note printed on the invoice<\/strong>/);
  assert.match(page, /data-testid="invoice-detail-exchange-note"/);
  const types = readFileSync('src/types/index.ts', 'utf8');
  assert.match(between(types, 'export interface Invoice {', '}'), /print_note\?: string \| null;/);
});
