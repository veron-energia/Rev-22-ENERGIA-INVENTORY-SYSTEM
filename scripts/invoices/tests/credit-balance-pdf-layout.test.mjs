// The credit balance line on the A5 PDF customer copy gives way; nothing else
// on the copy does.
//
// It goes in the empty left column beside the right-aligned totals, where it
// costs no height: every other line on the copy is drawn exactly where it is
// without it. Only when it does not fit there does it go under the payments,
// in the blank space above the signatures — and there it never costs an item
// row (the item list stops at exactly the same row with or without it), and it
// never pushes the footer (store contact, company registration) lower than
// where it ends without the line, or the on-page limit if that is lower down.
// When the full line does not fit, the breakdown of kinds is left off; when
// even the total does not fit, the copy goes without the line, and
// creditBalanceShown says so, so the page can tell staff. The image copy shares
// the rule (fitAroundCreditBalance); the browser test checks it there.
//
// With a store footer as full as a real one gets (address, WhatsApp, four
// footer bits, two ways to pay, a two-line policy) and long payment lists (an
// instalment plan, a corrected invoice), the line used to give way from 6 items
// with 2 payments, 7 items with 1, and 1–2 items with 10–12 payments. Beside
// the totals it is now drawn in full at every length from 1 to 30 items and
// 0 to 12 payments, for every totals block the invoice page makes (Subtotal and
// Discount, with Paid and/or Balance, then Total), for the owner's example and
// for all five kinds at five-figure amounts.
//
// Where it still gives way: a breakdown too wide for the column (all five
// kinds at seven-figure amounts) beside only Subtotal and Discount (nothing
// paid, nothing owed) goes under the payments, and loses its breakdown — the
// total stays, beside the totals — from 8 items with no payments, 7 with one
// or two, 4 with six, and at any length with twelve. Beside three or four
// totals rows the same breakdown still fits at every length. The total alone
// always fits beside a totals block, so a copy from the invoice page is never
// left without the line; that happens only on a copy with no totals block.
// Invented amounts only.
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoicePdf'; export { jsPDF } from 'jspdf';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'node',
  // jsPDF's optional HTML renderers; never reached by the copy.
  external: ['html2canvas', 'dompurify', 'canvg'],
});
const { buildDocumentPdf, fitAroundCreditBalance, creditBalanceShown, creditBesideTotals, jsPDF } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const LABEL = 'Credit balance (as at 2 Oct 2026)';
/** All five kinds, with amounts long enough that the breakdown needs more than one line. */
const CREDIT = { label: LABEL, amount: 'S$55555.55',
  detail: 'Paid S$11111.11 · Bonus S$11111.11 · Legacy S$11111.11 · Promotional S$11111.11 · Exchange S$11111.11' };
/** The owner's example: two kinds, one line. */
const OWNERS = { label: LABEL, amount: 'S$350.00', detail: 'Paid S$300.00 · Bonus S$50.00' };

/** The totals blocks the invoice page makes: Subtotal and Discount, with Paid when paid and Balance when owed. */
const TOTALS = {
  'S$0 owed, nothing paid': [['Subtotal', 'S$10.00'], ['Discount', '-S$0.00']],
  paid: [['Subtotal', 'S$10.00'], ['Discount', '-S$0.00'], ['Paid', 'S$10.00']],
  unpaid: [['Subtotal', 'S$10.00'], ['Discount', '-S$0.00'], ['Balance', 'S$10.00']],
  'part-paid': [['Subtotal', 'S$10.00'], ['Discount', '-S$0.00'], ['Paid', 'S$10.00'], ['Balance', 'S$5.00']],
};
/** A copy with a full store footer, `lines` items and `pays` payment rows. */
const doc = (lines, pays, creditBalance = null, over = {}) => ({
  kindLabel: 'Tax Invoice', docNo: 'INV-T-0001', date: '02/10/2026', status: 'PAID', storeName: 'Test Store',
  storeAddress: '1 Example Road #01-01, Singapore 000001', storePhone: '+6560000000 · WhatsApp +6590000000',
  customerName: 'Ann Credit (-)', customerContact: '+6590000001 · ann@example.test',
  lines: Array.from({ length: lines }, (_, n) => ({ name: `Test item ${n + 1}`, qty: 1, unit: 10, total: 10, notes: [] })),
  totals: TOTALS['part-paid'], grandTotal: ['Total', 'S$10.00'],
  payments: Array.from({ length: pays }, (_, n) => [`Cash · 0${(n % 9) + 1}/10/2026`, 'S$5.00']),
  creditBalance, staffName: 'Test Owner', policyText: 'Exchanges within 7 days with receipt.\nVouchers are not refundable.',
  payDetails: ['CIMB UEN: TEST0001X', 'CIMB corporate account: 000-000000-0'],
  footerBits: ['DID: +6560000000', 'Email: shop@example.test', 'Website: example.test', 'Co. Reg No.: TEST0001X'],
  ...over,
});
/** No totals block at all: nothing to sit beside, so the line goes under the payments and gives way there. */
const NO_TOTALS = { totals: [], grandTotal: undefined };

// jsPDF writes its standard fonts in WinAnsi: these three are single bytes.
const winAnsi = s => s.replace(/\x97/g, '—').replace(/\x85/g, '…').replace(/\xb7/g, '·');
/** Every string drawn, with its position: PDF points, y measured up from the foot (below zero is off the page). */
function drawnPdf(pdf) {
  const out = pdf.output();
  const re = /(-?[\d.]+) (-?[\d.]+) Td\s*\(((?:\\.|[^\\)])*)\) Tj/g;
  const items = [];
  for (let m; (m = re.exec(out));) items.push({ x: Number(m[1]), y: Number(m[2]), text: winAnsi(m[3].replace(/\\([()\\])/g, '$1')) });
  return items;
}
const drawn = d => drawnPdf(buildDocumentPdf(d));
const yOf = (items, text) => { const it = items.find(i => i.text === text); assert.ok(it, `"${text}" was not drawn`); return it.y; };
/** The last footer line's baseline, in points above the bottom edge. */
const footerY = items => { const f = items.filter(i => i.text.includes('Co. Reg No.')); assert.ok(f.length, 'footer drawn'); return f[f.length - 1].y; };
const rowNames = items => items.filter(i => /^Test item \d+$/.test(i.text)).map(i => i.text);
const continued = items => items.some(i => i.text.startsWith('…continued'));
const detailLines = (items, credit) => items.filter(i => credit.detail.split(' · ').some(k => i.text.includes(k)));
const isCredit = (i, credit) => i.text === credit.label || i.text === credit.amount || credit.detail.split(' · ').some(k => i.text.includes(k));
const PT_PER_MM = 72 / 25.4;
/** The on-page limit: the footer's last baseline 8 mm above the edge. */
const ON_PAGE = 8 * PT_PER_MM;
/** Where the totals block starts on the left: the rule over the grand total, 22 mm left of the UNIT column. */
const TOTALS_LEFT = (148.5 - 10 - 24 - 22) * PT_PER_MM;

/** Widths as jsPDF measures them, in points, in the faces the copy uses. */
const measure = new jsPDF({ unit: 'pt', format: 'a5' });
const widthOf = (text, size, bold) => { measure.setFont('helvetica', bold ? 'bold' : 'normal'); measure.setFontSize(size); return measure.getTextWidth(text); };

/** How the line came out on a copy: 'full', 'total' (no breakdown) or 'none'. */
function lineShown(items, credit) {
  const label = items.some(i => i.text === credit.label);
  const amount = items.some(i => i.text === credit.amount);
  const detail = detailLines(items, credit).map(i => i.text).join(' · ');
  assert.equal(label, amount, 'the label and the total are drawn together');
  if (!label) { assert.equal(detail, '', 'no breakdown without its total'); return 'none'; }
  if (!detail) return 'total';
  assert.equal(detail, credit.detail, 'the breakdown is drawn whole or not at all');
  return 'full';
}
/** Beside the totals: the label on the first totals row's line. */
const beside = items => { const l = items.find(i => i.text === LABEL); return !!l && Math.abs(l.y - yOf(items, 'Subtotal')) < 0.01; };

test('the line goes beside the totals, in the empty left column: label, total, then the kinds wrapped between kinds only', () => {
  const items = drawn(doc(3, 2, CREDIT));
  assert.equal(lineShown(items, CREDIT), 'full');
  assert.ok(beside(items), 'the label is on the Subtotal row');
  const label = items.find(i => i.text === LABEL), amount = items.find(i => i.text === CREDIT.amount);
  assert.ok(Math.abs(label.x - 10 * PT_PER_MM) < 0.01, 'at the left margin');
  assert.equal(amount.y, label.y, 'the total sits on the label\'s line when there is room');
  assert.ok(widthOf(LABEL, 10, true) < amount.x - label.x, 'clear of the label');
  const detail = detailLines(items, CREDIT);
  assert.ok(detail.length >= 2, 'all five kinds wrap onto more than one line in the column');
  assert.equal(detail.map(i => i.text).join(' · '), CREDIT.detail, 'and nothing is lost in the wrap');
  for (const kind of detail.flatMap(d => d.text.split(' · '))) assert.match(kind, /^(Paid|Bonus|Legacy|Promotional|Exchange) S\$[\d.]+$/, 'a kind is split');
  // Everything of the line stays left of the totals block and between its first and last lines.
  const top = yOf(items, 'Subtotal'), bottom = yOf(items, 'Total');
  for (const [it, size, bold] of [[label, 10, true], [amount, 10, true], ...detail.map(d => [d, 8.5, false])]) {
    assert.ok(it.x + widthOf(it.text, size, bold) <= TOTALS_LEFT - 3 * PT_PER_MM, `"${it.text}" runs into the totals`);
    assert.ok(it.y <= top + 0.01 && it.y >= bottom - 0.01, `"${it.text}" is outside the totals block's lines`);
  }
  assert.ok(yOf(items, 'Cash · 02/10/2026') < detail.at(-1).y, 'and the payments come after it');
});

test('beside the totals it moves nothing: every other line is drawn exactly where it is without it', () => {
  for (const [kind, totals] of Object.entries(TOTALS)) {
    for (const credit of [OWNERS, CREDIT]) {
      for (const [n, pays] of [[1, 0], [3, 2], [6, 2], [7, 1], [8, 2], [1, 12], [2, 10], [20, 12]]) {
        const without = drawn(doc(n, pays, null, { totals })), withLine = drawn(doc(n, pays, credit, { totals }));
        const at = `${kind}, ${n} items, ${pays} payments, ${credit === CREDIT ? 'five kinds' : 'two kinds'}`;
        assert.ok(beside(withLine), `${at}: not beside the totals`);
        assert.deepEqual(withLine.filter(i => !isCredit(i, credit)), without, `${at}: something else moved`);
      }
    }
  }
});

test('a short invoice keeps its signatures and footer exactly where they were, with the line in full', () => {
  const a = drawn(doc(3, 2)), b = drawn(doc(3, 2, CREDIT));
  assert.equal(lineShown(b, CREDIT), 'full');
  assert.equal(yOf(b, 'Staff Signature'), yOf(a, 'Staff Signature'));
  assert.equal(footerY(b), footerY(a));
});

test('the cases where the line used to give way now carry it in full, with the same rows and footer', () => {
  // Was: 6 items with 2 payments, 7 with 1 and 8 with 2 lost the line; 1–2
  // items with 10–12 payments too (and before that, rows or the footer).
  for (const [n, pays] of [[6, 2], [7, 1], [7, 2], [8, 1], [8, 2], [1, 11], [1, 12], [2, 10]]) {
    const withLine = drawn(doc(n, pays, OWNERS)), bare = drawn(doc(n, pays));
    assert.equal(lineShown(withLine, OWNERS), 'full', `${n} items, ${pays} payments`);
    assert.deepEqual(rowNames(withLine), rowNames(bare), `${n} items, ${pays} payments: rows changed`);
    assert.equal(footerY(withLine), footerY(bare), `${n} items, ${pays} payments: footer moved`);
  }
});

test('at every length and with long payment lists: the same item rows, and the footer never lower than the limit', () => {
  const seen = { full: 0, total: 0, none: 0 };
  const shapes = [...Object.entries(TOTALS).map(([k, totals]) => [k, { totals }]), ['no totals', NO_TOTALS]];
  for (const [shape, over] of shapes) {
    for (const credit of [CREDIT, OWNERS]) {
      for (const pays of [0, 1, 2, 6, 10, 11, 12]) {
        for (let n = 1; n <= 30; n++) {
          const label = `${shape}, ${n} items, ${pays} payments, ${credit === CREDIT ? 'five kinds' : 'two kinds'}`;
          const without = drawn(doc(n, pays, null, over)), withLine = drawn(doc(n, pays, credit, over));
          // Never costs an item row: the list stops at the same row, with the same note.
          assert.deepEqual(rowNames(withLine), rowNames(without), `${label}: item rows changed`);
          assert.equal(continued(withLine), continued(without), `${label}: the continued note changed`);
          // Never lower than where the footer was, or the on-page limit if that is lower down.
          assert.ok(footerY(withLine) >= Math.min(footerY(without), ON_PAGE) - 0.01,
            `${label}: footer ${(footerY(withLine) / PT_PER_MM).toFixed(2)} mm above the edge, without the line ${(footerY(without) / PT_PER_MM).toFixed(2)} mm`);
          const state = lineShown(withLine, credit);
          // Every totals block the invoice page makes has room for all of it beside the totals.
          if (shape !== 'no totals') assert.ok(state === 'full' && beside(withLine), `${label}: ${state}, not in full beside the totals`);
          seen[state]++;
        }
      }
    }
  }
  // The sweep reaches every way the line can come out.
  assert.ok(seen.full > 0 && seen.total > 0 && seen.none > 0, JSON.stringify(seen));
});

test('with nothing to sit beside, the line gives way in order: the breakdown first, then the total', () => {
  // Grow the payment list on a one-item copy with no totals block: the line
  // shows in full under the payments, then without the breakdown, then not at
  // all — never the other way round.
  const order = { full: 0, total: 1, none: 2 };
  let last = 'full';
  const states = [];
  for (let pays = 0; pays <= 24; pays++) {
    const now = lineShown(drawn(doc(1, pays, CREDIT, NO_TOTALS)), CREDIT);
    assert.ok(order[now] >= order[last], `${pays} payments: ${now} after ${last}`);
    states.push(now); last = now;
  }
  assert.ok(states.includes('full') && states.includes('total') && states.includes('none'), states.join(','));
});

test('a breakdown too long for the column goes under the payments; on a full page only its total stays, beside the totals', () => {
  // Seven-figure amounts: the total no longer fits on the label's line, and
  // with only Subtotal and Discount there is no room for every kind beside them.
  const big = { label: LABEL, amount: 'S$5555555.55',
    detail: 'Paid S$1111111.11 · Bonus S$1111111.11 · Legacy S$1111111.11 · Promotional S$1111111.11 · Exchange S$1111111.11' };
  const short = { totals: TOTALS['S$0 owed, nothing paid'] };
  const roomy = drawn(doc(2, 1, big, short));
  assert.equal(lineShown(roomy, big), 'full');
  assert.ok(!beside(roomy), 'under the payments');
  assert.ok(yOf(roomy, LABEL) < yOf(roomy, 'Cash · 01/10/2026'), 'below the last payment row');
  assert.equal(yOf(roomy, big.amount), yOf(roomy, LABEL), 'its total on the label\'s line, at the right');
  // A page already full: under the payments would push the footer, so the
  // breakdown goes and the total alone sits beside the totals.
  const full = drawn(doc(9, 2, big, short)), bare = drawn(doc(9, 2, null, short));
  assert.equal(lineShown(full, big), 'total');
  assert.ok(beside(full));
  assert.ok(yOf(full, big.amount) < yOf(full, LABEL), 'the total on its own line under the label');
  assert.equal(footerY(full), footerY(bare));
});

test('where it still gives way, stated: a breakdown too wide for the column beside two totals rows', () => {
  const big = { label: LABEL, amount: 'S$5555555.55',
    detail: 'Paid S$1111111.11 · Bonus S$1111111.11 · Legacy S$1111111.11 · Promotional S$1111111.11 · Exchange S$1111111.11' };
  // Payments → the first item count at which only the total is drawn.
  const givesWayFrom = { 0: 8, 1: 7, 2: 7, 6: 4, 12: 1 };
  for (const [pays, from] of Object.entries(givesWayFrom).map(([p, f]) => [Number(p), f])) {
    for (let n = 1; n <= 14; n++) {
      const at = `${n} items, ${pays} payments`;
      const withLine = drawn(doc(n, pays, big, { totals: TOTALS['S$0 owed, nothing paid'] }));
      const without = drawn(doc(n, pays, null, { totals: TOTALS['S$0 owed, nothing paid'] }));
      assert.equal(lineShown(withLine, big), n < from ? 'full' : 'total', at);
      // In full it is under the payments; the total alone, beside the totals.
      assert.equal(beside(withLine), n >= from, `${at}: beside`);
      assert.deepEqual(rowNames(withLine), rowNames(without), `${at}: rows`);
      assert.ok(footerY(withLine) >= Math.min(footerY(without), ON_PAGE) - 0.01, `${at}: footer`);
    }
  }
  // Beside three or four totals rows the same breakdown fits, in full, at every length.
  for (const totals of [TOTALS.paid, TOTALS.unpaid, TOTALS['part-paid']]) {
    for (const [n, pays] of [[1, 0], [8, 2], [14, 12], [30, 12]]) {
      const withLine = drawn(doc(n, pays, big, { totals }));
      assert.ok(lineShown(withLine, big) === 'full' && beside(withLine), `${totals.length} totals rows, ${n} items, ${pays} payments`);
    }
  }
});

test('the copy remembers how the line came out, for the page to say when it was left off', () => {
  const d1 = doc(3, 2, OWNERS);
  assert.equal(creditBalanceShown(d1), null, 'not drawn yet');
  buildDocumentPdf(d1);
  assert.equal(creditBalanceShown(d1), 'full');
  const d2 = doc(1, 20, CREDIT, NO_TOTALS);
  buildDocumentPdf(d2);
  assert.equal(creditBalanceShown(d2), 'none', 'left off for space');
  assert.equal(lineShown(drawnPdf(buildDocumentPdf(d2)), CREDIT), 'none');
  const d3 = doc(1, 15, CREDIT, NO_TOTALS);
  buildDocumentPdf(d3);
  assert.equal(creditBalanceShown(d3), 'total');
  const d4 = doc(3, 2);
  buildDocumentPdf(d4);
  assert.equal(creditBalanceShown(d4), null, 'no line to draw');
});

test('the place beside the totals: all of it between the first and last totals lines, inside the column', () => {
  const p = (over = {}) => ({ top: 100, bottom: 115, width: 80, labelW: 56, amountW: 15, detailLines: [{ width: 40 }], lineH: 4.2, detailH: 3.4, gap: 3, ...over });
  assert.deepEqual(creditBesideTotals(p()), { labelY: 100, amountY: 100, amountOnLabelLine: true, detailY: [104.2] });
  // No room on the label's line for the total: it goes on the next line.
  assert.deepEqual(creditBesideTotals(p({ amountW: 22 })), { labelY: 100, amountY: 104.2, amountOnLabelLine: false, detailY: [108.4] });
  // Three lines of kinds: 100, then 104.2, 107.6, 111.0.
  assert.deepEqual(creditBesideTotals(p({ detailLines: [{ width: 1 }, { width: 1 }, { width: 1 }] })).detailY.map(v => +v.toFixed(2)), [104.2, 107.6, 111]);
  assert.ok(creditBesideTotals(p({ bottom: 111, detailLines: [{ width: 1 }, { width: 1 }, { width: 1 }] })), 'the last line exactly on the last totals line fits');
  assert.equal(creditBesideTotals(p({ bottom: 110.9, detailLines: [{ width: 1 }, { width: 1 }, { width: 1 }] })), null, 'below it does not');
  assert.equal(creditBesideTotals(p({ detailLines: [{ width: 81 }] })), null, 'a kind wider than the column');
  assert.equal(creditBesideTotals(p({ labelW: 81 })), null, 'a label wider than the column');
  assert.equal(creditBesideTotals(p({ amountW: 81 })), null, 'a total wider than the column');
  assert.equal(creditBesideTotals(p({ width: 0 })), null, 'no column');
  assert.equal(creditBesideTotals(p({ bottom: -Infinity })), null, 'no totals block');
  assert.deepEqual(creditBesideTotals(p({ detailLines: [], bottom: 100 })), { labelY: 100, amountY: 100, amountOnLabelLine: true, detailY: [] }, 'the total alone fits on one line');
});

test('the fitting rule: at most three drawings, each one thrown away released', () => {
  // A stand-in drawing: the copy ends at 100 plus 10 a payment; the total adds 6 and the breakdown 4 more.
  const draws = [];
  const draw = d => {
    const endY = 100 + d.pays * 10 + (d.creditBalance ? 6 + (d.creditBalance.detail ? 4 : 0) : 0);
    const out = { kind: !d.creditBalance ? 'none' : d.creditBalance.detail ? 'full' : 'total' };
    draws.push(out);
    return { out, endY };
  };
  const credit = { label: 'x', amount: 'y', detail: 'z' };
  const run = (pays, limit, c = credit) => {
    draws.length = 0; const discarded = [];
    const d = { pays, creditBalance: c };
    const out = fitAroundCreditBalance(d, draw, limit, o => discarded.push(o));
    assert.ok(draws.length <= 3, `${draws.length} drawings`);
    // Everything drawn but the one returned is released, and nothing twice.
    assert.deepEqual(new Set(discarded), new Set(draws.filter(o => o !== out)));
    assert.equal(discarded.length, draws.length - 1);
    // And the copy remembers how it came out.
    assert.equal(creditBalanceShown(d), out.kind);
    return out.kind;
  };
  assert.equal(run(5, 160), 'full', 'room for all of it: 160');
  assert.equal(draws.length, 1, 'drawn once when it fits');
  assert.equal(run(5, 157), 'total', '160 is past 157; 156 fits');
  assert.equal(run(5, 155), 'none', 'neither fits');
  assert.equal(run(5, 155, { ...credit, detail: null }), 'none', 'a line with no breakdown goes straight to none');
  assert.equal(run(5, 156, { ...credit, detail: null }), 'total');
  // Already past the limit without the line: the line may only use what the copy already takes up.
  assert.equal(run(10, 150), 'none', '200 without the line; 210 and 206 are both lower');
  assert.equal(fitAroundCreditBalance({ pays: 5, creditBalance: null }, draw, 100), draws.at(-1), 'no line: drawn once and returned');
  // Past the on-page limit already, with the line in blank space that costs
  // nothing: the footer is no lower for it, so it is drawn in full.
  const free = d => ({ out: { kind: d.creditBalance ? 'full' : 'none' }, endY: 200 });
  assert.equal(fitAroundCreditBalance({ creditBalance: credit }, free, 150).kind, 'full');
  // Drawn beside the totals, it cost nothing: used at once, without drawing the copy again.
  let n = 0;
  const besideDraw = d => { n++; return { out: { kind: d.creditBalance ? 'full' : 'none' }, endY: 300, creditBeside: !!d.creditBalance }; };
  const d = { creditBalance: credit };
  assert.equal(fitAroundCreditBalance(d, besideDraw, 150).kind, 'full');
  assert.equal(n, 1, 'one drawing');
  assert.equal(creditBalanceShown(d), 'full');
});

test('without a credit line nothing changes', () => {
  const items = drawn(doc(5, 2));
  assert.ok(!items.some(i => i.text.startsWith('Credit balance')));
  assert.deepEqual(rowNames(drawn(doc(30, 2))), rowNames(drawn(doc(30, 2, null))));
});
