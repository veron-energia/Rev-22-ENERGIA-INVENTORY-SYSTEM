// The goods of an unpaid or part-paid invoice on its A5 PDF copy (399, the
// Owner, 6 Oct 2026): "Collected: …" and "To collect: …" under the payments,
// in the blank space above the signatures, and terms that stop at "neither
// refundable nor exchangeable". The signatures are pinned near the foot, so on
// all but a long invoice the goods move nothing below them: the footer (store
// contact, company registration) stays exactly where it is without them. A
// fully paid invoice keeps "checked and collected". The image copy draws the
// same block (src/lib/invoiceImage.ts).
//
// With a store footer as full as production's (a 195-character policy, two
// ways to pay and the instalment line) and 6 products' goods listed, the
// footer does not move for invoices of up to 4 lines with one payment, or 3
// with two. On a longer invoice the goods give way (fitAroundCollection): one
// line each ending "+N more", or a few words in the terms, which take no more
// room than the standard "... checked and collected" terms they replace. So
// the goods never push the footer lower than the copy drew before 399, or the
// on-page limit, whichever is lower down: checked up to 10 lines with one or
// two payments and as many products as lines. Invented names and amounts only.
//
// Run: node --test scripts/invoices/tests/handover-pdf-layout.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoicePdf'; export * from './src/lib/invoices/handover.mjs';`,
           resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'node',
  external: ['html2canvas', 'dompurify', 'canvg'],
});
const { buildDocumentPdf, copyTermsText, copyCollectionLines, copyCollection } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const winAnsi = s => s.replace(/\x97/g, '—').replace(/\x85/g, '…').replace(/\xb7/g, '·').replace(/\xd7/g, '×');
/** Every string drawn, with its position: PDF points, y measured up from the foot. */
function drawn(d) {
  const out = buildDocumentPdf(d).output();
  const re = /(-?[\d.]+) (-?[\d.]+) Td\s*\(((?:\\.|[^\\)])*)\) Tj/g;
  const items = [];
  for (let m; (m = re.exec(out));) items.push({ x: Number(m[1]), y: Number(m[2]), text: winAnsi(m[3].replace(/\\([()\\])/g, '$1')) });
  return items;
}
const PT_PER_MM = 72 / 25.4;
const footerY = items => { const f = items.filter(i => i.text.includes('Co. Reg No.')); assert.ok(f.length, 'footer drawn'); return f[f.length - 1].y; };
const yOf = (items, text) => { const it = items.find(i => i.text === text); assert.ok(it, `"${text}" was not drawn`); return it.y; };

// A 195-character policy, as production's stores have.
const POLICY = 'Goods may be exchanged within 7 days with the original receipt and packaging, subject to inspection. '
  + 'Deposits for orders are not refundable. Therapy packages are valid for 12 months.';
const goods = (n, name = k => `Test Product ${k + 1}`) => ({ products: Array.from({ length: n }, (_, k) => ({
  product_id: `p${k}`, name: name(k), required: 2, collected: k % 2, to_collect: 2 - (k % 2), out: k % 2, in_store: 5, via: [] })) });
// Names as long as the shop's own.
const LONG = ['Far-Infrared Bio-Ceramic Pillow (Queen)', 'Germanium Wellness Socks (L)', 'Tourmaline Knee Support Band',
  'Negative Ion Water Bottle 750ml', 'Posture Corrector Corset (M)', 'Heated Lumbar Pad with Controller'];
const longName = k => `${LONG[k % LONG.length]} ${k + 1}`;
const doc = (lines, status, g, pays = 1) => ({
  kindLabel: 'Tax Invoice', docNo: 'INV-2026-9101', date: '06/10/2026', status: status.toUpperCase(), storeName: 'Test Store',
  storeAddress: '1 Example Road #01-01, Singapore 000001', storePhone: '+6560000000 · WhatsApp +6590000000',
  customerName: 'Jane Tan (-)', customerContact: '+6591390001 · jane@sig.invalid',
  lines: Array.from({ length: lines }, (_, n) => ({ name: `Test item ${n + 1}`, qty: 1, unit: 10, total: 10, notes: [] })),
  totals: [['Subtotal', 'S$10.00'], ['Discount', '-S$0.00'], ['Paid', 'S$5.00'], ['Balance', 'S$5.00']], grandTotal: ['Total', 'S$10.00'],
  payments: Array.from({ length: pays }, () => ['Cash · 06/10/2026', 'S$5.00']), creditBalance: null, staffName: 'Test Owner', policyText: POLICY,
  payDetails: ['Instalment 6 months', 'CIMB UEN: TEST0001X', 'CIMB corporate account: 000-000000-0'],
  footerBits: ['DID: +6560000000', 'Email: shop@example.test', 'Website: example.test', 'Co. Reg No.: TEST0001X'],
  termsText: copyTermsText(status), collection: copyCollection(status, g),
});
// The same invoice as its copy was drawn before 399: the standard terms, no goods.
const before399 = d => ({ ...d, termsText: undefined, collection: null });
// The goods are said somewhere: as lists, or in the terms.
const saysGoods = items => items.some(i => /^(Collected|To collect):/.test(i.text))
  || /GOODS: \d+ COLLECTED, \d+ TO COLLECT\./.test(items.map(i => i.text).join(' '));

test('a part-paid copy lists its goods above the signatures and never says "checked and collected"', () => {
  const items = drawn(doc(3, 'partially_paid', goods(3)));
  const lines = copyCollectionLines('partially_paid', goods(3));
  assert.deepEqual(lines, ['Collected: Test Product 2 × 1', 'To collect: Test Product 1 × 2, Test Product 2 × 1, Test Product 3 × 2']);
  for (const l of lines) {
    assert.ok(yOf(items, l) > yOf(items, 'Staff Signature'), `"${l}" is above the signatures`);
    assert.ok(yOf(items, l) < yOf(items, 'Cash · 06/10/2026'), `"${l}" is under the payments`);
  }
  const all = items.map(i => i.text).join(' ');
  assert.match(all, /GOODS AND SERVICES SOLD ARE NEITHER REFUNDABLE NOR EXCHANGEABLE\./);
  assert.doesNotMatch(all, /CHECKED AND COLLECTED/);
});

test('a fully paid copy keeps "checked and collected" and lists no goods', () => {
  const items = drawn(doc(3, 'paid', goods(3)));
  assert.match(items.map(i => i.text).join(' '), /CHECKED AND COLLECTED/);
  assert.ok(!items.some(i => /^(Collected|To collect):/.test(i.text)), 'no goods lines');
});

test('in the blank space above the signatures: the footer does not move on a short invoice', () => {
  for (const [pays, maxLines] of [[1, 4], [2, 3]]) {
    for (let lines = 1; lines <= maxLines; lines++) {
      const without = footerY(drawn(doc(lines, 'partially_paid', null, pays)));
      const withGoods = footerY(drawn(doc(lines, 'partially_paid', goods(6), pays)));
      assert.equal(withGoods, without, `${lines} line(s), ${pays} payment(s): the footer moved`);
    }
  }
});

test('the goods never push the footer lower than before 399, or off the page, and are always said', () => {
  const forms = new Set();
  for (const pays of [1, 2]) {
    for (let lines = 1; lines <= 10; lines++) {
      for (const g of [goods(6), goods(lines, longName), goods(Math.max(lines, 8), longName)]) {
        const d = doc(lines, 'partially_paid', g, pays);
        const items = drawn(d);
        const y = footerY(items), was = footerY(drawn(before399(d)));
        const bound = Math.min(was, 8 * PT_PER_MM);
        assert.ok(y >= bound - 0.01, `${lines} line(s), ${pays} payment(s), ${g.products.length} products: `
          + `the footer is ${(y / PT_PER_MM).toFixed(1)} mm from the foot (before 399 ${(was / PT_PER_MM).toFixed(1)} mm)`);
        assert.ok(saysGoods(items), `${lines} line(s), ${pays} payment(s): the goods are on the copy`);
        assert.doesNotMatch(items.map(i => i.text).join(' '), /CHECKED AND COLLECTED/);
        const all = items.map(i => i.text).join(' ');
        forms.add(/GOODS: \d+ COLLECTED/.test(all) ? 'terms' : /\+\d+ more/.test(all) ? 'short' : 'full');
      }
    }
  }
  assert.deepEqual([...forms].sort(), ['full', 'short', 'terms'], 'every form is reached somewhere in the range');
});

test('a long part-paid invoice shortens the lists, then puts the goods in its terms', () => {
  // 7 lines and 2 payments: the full lists would run the footer off the page.
  const d = doc(7, 'partially_paid', goods(7, longName), 2);
  const items = drawn(d);
  const all = items.map(i => i.text).join(' ');
  assert.ok(footerY(items) >= Math.min(footerY(drawn(before399(d))), 8 * PT_PER_MM) - 0.01);
  if (/GOODS: \d+ COLLECTED/.test(all)) {
    const c = copyCollection('partially_paid', goods(7, longName));
    const n = l => l.reduce((a, i) => a + i.qty, 0);
    assert.match(all, new RegExp(`NEITHER REFUNDABLE NOR EXCHANGEABLE\\. ?GOODS: ${n(c.collected)} COLLECTED, ${n(c.toCollect)} TO COLLECT\\.`));
    assert.ok(!items.some(i => /^(Collected|To collect):/.test(i.text)), 'no lists as well');
  } else {
    const goodsLines = items.filter(i => /^(Collected|To collect):/.test(i.text));
    assert.equal(goodsLines.length, 2, 'one line each');
    assert.ok(goodsLines.some(i => /\+\d+ more$/.test(i.text)));
  }
});

test('a long list wraps rather than running off the side', () => {
  const items = drawn(doc(2, 'unpaid', goods(16)));
  const sig = yOf(items, 'Staff Signature'), pay = yOf(items, 'Cash · 06/10/2026');
  const goodsLines = items.filter(i => i.y > sig && i.y < pay && i.x < 12 * PT_PER_MM);
  assert.ok(goodsLines.length > 2, 'the lists wrap onto more lines');
  assert.ok(goodsLines.every(i => Math.abs(i.x - 10 * PT_PER_MM) < 0.01), 'from the left margin');
  assert.ok(goodsLines.some(i => i.text.startsWith('To collect:')) && goodsLines.some(i => i.text.startsWith('Collected:')));
});
