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
//
// B16 (AFTER-8): all of that holds while the copy fits one A5 page with every
// payment listed. A copy that still runs off the page once the goods and the
// line have given way shortens its payments to one row, and if even that
// does not fit, takes a second page; there the line has room again. The line
// itself never causes either. AFTER-9: an exchange note under the header.
// Item 5 (the Owner, 22 Oct 2026): a copy with more rows than two pages hold
// lists every one, on as many pages as they need, each page saying Page k of
// N; a row taller than a page goes on between its notes; payments that do not
// fit under the totals on the last page of rows shorten, then go on a page of
// their own.
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
/** How many pages the copy took (B16: a second one when it runs long). */
const pageCount = d => buildDocumentPdf(d).getNumberOfPages();
/** The payments were shortened to one row (B16, AFTER-8). */
const paymentsShortened = items => items.some(i => /^Payments: \d+; full list on the store copy$/.test(i.text));
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
  // all — never the other way round — while every payment is listed. B16
  // (AFTER-8): once the listed payments themselves would run the footer off
  // the page, they shorten to one row, and the line has room again, in full.
  const order = { full: 0, total: 1, none: 2 };
  let last = 'full';
  const states = [];
  let shortened = false;
  for (let pays = 0; pays <= 24; pays++) {
    const items = drawn(doc(1, pays, CREDIT, NO_TOTALS));
    const now = lineShown(items, CREDIT);
    if (paymentsShortened(items)) {
      shortened = true;
      assert.equal(now, 'full', `${pays} payments, shortened to one row: ${now}`);
      continue;
    }
    assert.ok(!shortened, `${pays} payments: listed again after a shorter list was shortened`);
    assert.ok(order[now] >= order[last], `${pays} payments: ${now} after ${last}`);
    states.push(now); last = now;
  }
  assert.ok(shortened, 'a long enough list is shortened');
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
  // breakdown goes and the total alone sits beside the totals. (At 9 items the
  // copy ran off the page even without the line; since B16 it takes a second
  // page, where the line has room: see the second-page test below.)
  const full = drawn(doc(7, 2, big, short)), bare = drawn(doc(7, 2, null, short));
  assert.equal(pageCount(doc(7, 2, big, short)), 1);
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
      const bareDoc = doc(n, pays, null, { totals: TOTALS['S$0 owed, nothing paid'] });
      if (pageCount(bareDoc) === 1 && !paymentsShortened(without)) {
        assert.equal(lineShown(withLine, big), n < from ? 'full' : 'total', at);
        // In full it is under the payments; the total alone, beside the totals.
        assert.equal(beside(withLine), n >= from, `${at}: beside`);
      } else {
        // B16 (AFTER-8): the copy runs off the page without the line, so its
        // payments shorten or it takes a second page. The line never causes
        // either, and there it has room: never left off.
        assert.equal(pageCount(doc(n, pays, big, { totals: TOTALS['S$0 owed, nothing paid'] })), pageCount(bareDoc), `${at}: pages`);
        assert.equal(paymentsShortened(withLine), paymentsShortened(without), `${at}: payments`);
        assert.notEqual(lineShown(withLine, big), 'none', at);
      }
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
  const d2 = doc(1, 17, CREDIT, NO_TOTALS);
  buildDocumentPdf(d2);
  assert.equal(creditBalanceShown(d2), 'none', 'left off for space');
  assert.equal(lineShown(drawnPdf(buildDocumentPdf(d2)), CREDIT), 'none');
  // B16: with the payments shortened to one row the line has room, and that is what is remembered.
  const d5 = doc(1, 20, CREDIT, NO_TOTALS);
  buildDocumentPdf(d5);
  assert.equal(creditBalanceShown(d5), 'full');
  assert.ok(paymentsShortened(drawnPdf(buildDocumentPdf(d5))));
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

// ── B16 (AFTER-8, AFTER-9): a copy that runs long, and what is on it ─────────
/** Every string drawn, page by page: each page's own content stream. */
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
// As long as the longest policy any store has in production (195 characters,
// one paragraph, read 18 Oct 2026). The words are invented.
const POLICY_195 = 'Items may be exchanged within 7 days with the receipt and the original box, after a check in store. '
  + 'Orders paid by deposit are final. Therapy packages run 12 months from the day they start.';
/** Six lines as a real invoice has them: each with an FOC or discount note, a promotion with its contents. */
const realLines = () => [
  { name: 'Far-Infrared Bio-Ceramic Pillow (Queen)', qty: 2, unit: 180, total: 180, notes: ['FOC 1 of 2 free — value S$180.00'] },
  { name: 'Germanium Wellness Socks (L)', qty: 3, unit: 25, total: 70, notes: ['Discount -S$5.00'] },
  { name: 'Promotion: Fixture Wellness Bundle', qty: 1, unit: 500, total: 500,
    notes: ['Tourmaline Knee Support Band × 2 (included)', 'Negative Ion Water Bottle 750ml × 1 (chosen)', 'incl. top-up S$20.00'] },
  { name: 'Voucher: Fixture Massage Voucher', qty: 1, unit: 80, total: 80, notes: [] },
  { name: 'Posture Corrector Corset (M)', qty: 1, unit: 120, total: 120, notes: ['Manual price override'] },
  { name: 'Heated Lumbar Pad with Controller', qty: 1, unit: 150, total: 150, notes: ['Voucher Ten -S$15.00'] },
];
const lastPage = pdf => drawnPages(pdf).at(-1);

test('a 6-line, 4-payment invoice with the longest store policy keeps everything on its page', () => {
  for (const totals of Object.values(TOTALS)) {
    const d = doc(6, 4, OWNERS, { lines: realLines(), policyText: POLICY_195, totals });
    const pdf = buildDocumentPdf(d);
    const pages = drawnPages(pdf);
    assert.equal(pages.length, pdf.getNumberOfPages(), 'one content stream a page');
    const last = pages.at(-1);
    // The footer's last line at least 8 mm above the edge of its page, and nothing cut off.
    assert.ok(footerY(last) >= ON_PAGE - 0.01, `the footer is ${(footerY(last) / PT_PER_MM).toFixed(1)} mm from the foot`);
    for (const t of ['Staff Signature', 'Customer Signature', 'CANCELLATION / EXCHANGE / REFUND POLICY', 'How to pay']) {
      assert.ok(last.some(i => i.text === t), `"${t}" is on the copy`);
    }
    assert.ok(pages.flat().every(i => i.y >= ON_PAGE - 0.01 - 3 * PT_PER_MM), 'nothing drawn off the foot of a page');
    // Every line is listed, with its notes.
    for (const l of realLines()) assert.ok(pages[0].some(i => i.text === l.name), `"${l.name}" is listed`);
    assert.ok(pages[0].some(i => i.text === 'Negative Ion Water Bottle 750ml × 1 (chosen)'), 'a promotion lists what is in it');
  }
});

test('payments that would run the footer off the page shorten to one row, with their count and total', () => {
  const d = doc(7, 2);
  assert.equal(pageCount(d), 1);
  const items = drawn(d);
  assert.ok(paymentsShortened(items), 'one row for the payments');
  assert.equal(items.find(i => i.text === 'Payments: 2; full list on the store copy') && items.some(i => i.text === 'S$10.00'), true);
  assert.ok(!items.some(i => i.text.startsWith('Cash · ')), 'the list itself is left for the store copy');
  assert.ok(footerY(items) >= ON_PAGE - 0.01, 'and the footer is on the page');
  // With room for the list, it is listed as before.
  assert.ok(!paymentsShortened(drawn(doc(3, 2))));
  assert.equal(drawn(doc(3, 2)).filter(i => i.text.startsWith('Cash · ')).length, 2);
});

test('when even one row does not fit, the copy takes a second page, with every payment there', () => {
  // Nine items and twelve payments: the items stay on page 1 with their totals.
  const short = buildDocumentPdf(doc(9, 12));
  assert.equal(short.getNumberOfPages(), 2);
  const [p1, p2] = drawnPages(short);
  assert.ok(p1.some(i => i.text === 'Continued on page 2'), 'page 1 says it goes on');
  assert.ok(p1.some(i => i.text === 'Total'), 'the totals stay with the items');
  assert.equal(rowNames(p1).length, 9);
  assert.ok(p2.some(i => i.text === 'INV-T-0001 (continued)') && p2.some(i => i.text === 'Page 2 of 2'));
  assert.equal(p2.filter(i => i.text.startsWith('Cash · ')).length, 12, 'every payment, listed');
  assert.ok(!paymentsShortened(p2));
  assert.ok(footerY(p2) >= ON_PAGE - 0.01, 'the footer on the second page, on the page');
  assert.ok(p2.some(i => i.text === 'Staff Signature') && !p1.some(i => i.text === 'Staff Signature'));
  // B16 (AFTER-9): fourteen items are more than page 1 lists. The rows carry
  // on to page 2 under the column heads, with the totals after the last one;
  // none is left for the store copy.
  const d = doc(14, 12);
  const pdf = buildDocumentPdf(d);
  assert.equal(pdf.getNumberOfPages(), 2);
  const [first, second] = drawnPages(pdf);
  assert.ok(first.some(i => i.text === 'Continued on page 2'), 'page 1 says it goes on');
  assert.ok(!first.some(i => i.text === 'Total') && second.some(i => i.text === 'Total'), 'the totals follow the last row');
  assert.ok(second.some(i => i.text === 'ITEM') && second.some(i => i.text === 'QTY'), 'the column heads again');
  assert.deepEqual([...rowNames(first), ...rowNames(second)], Array.from({ length: 14 }, (_, n) => `Test item ${n + 1}`), 'every row, in order');
  assert.ok(!continued(first) && !continued(second), 'no row left off');
  assert.equal(second.filter(i => i.text.startsWith('Cash · ')).length, 12, 'every payment, listed');
  assert.ok(footerY(second) >= ON_PAGE - 0.01, 'the footer on the second page, on the page');
  assert.ok(second.some(i => i.text === 'Staff Signature') && !first.some(i => i.text === 'Staff Signature'));
  assert.equal(first.filter(i => i.text === 'Continued on page 2').length, 1, 'said once');
});

// Item 5 (the Owner, 22 Oct 2026): more rows than two pages hold are no longer cut at page 1
// ("…continued — see the full invoice in store"): every row is listed, on as many A5 pages as
// they need, each page saying which it is of how many.
test('more rows than two pages hold: every row listed, on as many pages as they need, each saying Page k of N', () => {
  for (const [n, pays] of [[24, 1], [40, 1], [40, 12], [80, 2], [150, 1]]) {
    const at = `${n} rows, ${pays} payment(s)`;
    const pdf = buildDocumentPdf(doc(n, pays));
    const pages = drawnPages(pdf), N = pdf.getNumberOfPages();
    assert.equal(pages.length, N, `${at}: one content stream a page`);
    assert.ok(N >= (n >= 40 ? 3 : 2), `${at}: ${N} pages`);
    assert.deepEqual(pages.flatMap(rowNames), Array.from({ length: n }, (_, k) => `Test item ${k + 1}`), `${at}: every row, once, in order`);
    assert.ok(!pages.some(continued), `${at}: no "see the full invoice in store" cut`);
    for (const [k, p] of pages.entries()) {
      assert.equal(p.filter(i => i.text === `Page ${k + 1} of ${N}`).length, 1, `${at}: page ${k + 1} says which it is`);
      assert.equal(p.some(i => i.text === `Continued on page ${k + 2}`), k < N - 1, `${at}: page ${k + 1} says where it goes on`);
      if (k > 0) assert.ok(p.some(i => i.text === 'INV-T-0001 (continued)'), `${at}: page ${k + 1} says what it continues`);
      if (rowNames(p).length) assert.ok(p.some(i => i.text === 'ITEM') && p.some(i => i.text === 'TOTAL'), `${at}: the column heads on page ${k + 1}`);
      assert.ok(p.every(i => i.y >= ON_PAGE - 0.01 - 3 * PT_PER_MM), `${at}: nothing drawn off the foot of page ${k + 1}`);
    }
    const last = pages.at(-1);
    assert.ok(footerY(last) >= ON_PAGE - 0.01, `${at}: the footer on the last page, on the page`);
    assert.ok(last.some(i => i.text === 'Staff Signature') && !pages.slice(0, -1).some(p => p.some(i => i.text === 'Staff Signature')), `${at}: the signatures on the last page only`);
    // The totals never stand alone: they follow the last row on its page.
    const withTotal = pages.findIndex(p => p.some(i => i.text === 'Total'));
    assert.ok(rowNames(pages[withTotal]).at(-1) === `Test item ${n}`, `${at}: the totals with the last row`);
    const listed = pages.flat().filter(i => i.text.startsWith('Cash · ')).length;
    assert.ok(listed === pays || paymentsShortened(pages.flat()), `${at}: every payment, or their summary`);
  }
  // A page the rows go on from is used down to its foot, not only down to the room the totals need.
  const [first] = drawnPages(buildDocumentPdf(doc(80, 1)));
  assert.ok(rowNames(first).length > rowNames(drawn(doc(9, 0))).length, 'page 1 holds more rows than a one-page copy lists');
  // One page: no page numbers.
  assert.ok(!drawn(doc(3, 1)).some(i => /^Page \d+ of \d+$/.test(i.text)));
});

test('a row taller than a page goes on between its notes; any other row is never split', () => {
  const tallLine = (k) => ({ name: 'Promotion: Fixture Big Bundle', qty: 1, unit: 10, total: 10,
    notes: Array.from({ length: k }, (_, j) => `Fixture content item ${j + 1} × 1 (included)`) });
  for (const [where, k] of [['middle', 70], ['last', 70], ['last', 40]]) {
    const lines = Array.from({ length: 6 }, (_, j) => ({ name: `Test item ${j + 1}`, qty: 1, unit: 10, total: 10, notes: [] }));
    lines.splice(where === 'last' ? 6 : 3, 0, tallLine(k));
    const pdf = buildDocumentPdf(doc(lines.length, 1, null, { lines, policyText: POLICY_195 }));
    const pages = drawnPages(pdf), N = pages.length;
    const at = `${k} notes, ${where}`;
    const contents = pages.flat().filter(i => i.text.startsWith('Fixture content item')).map(i => i.text);
    assert.deepEqual(contents, Array.from({ length: k }, (_, j) => `Fixture content item ${j + 1} × 1 (included)`), `${at}: every note once, in order`);
    assert.ok(pages.filter(p => p.some(i => i.text.startsWith('Fixture content item'))).length >= 2, `${at}: over more than one page`);
    assert.deepEqual(pages.flatMap(rowNames), lines.filter(l => l.name.startsWith('Test item')).map(l => l.name), `${at}: every other row`);
    assert.ok(pages.every(p => p.every(i => i.y >= ON_PAGE - 0.01 - 3 * PT_PER_MM)), `${at}: nothing off the foot of a page`);
    assert.ok(footerY(pages.at(-1)) >= ON_PAGE - 0.01, `${at}: the footer on the last page`);
    assert.ok(pages.every((p, j) => p.some(i => i.text === `Page ${j + 1} of ${N}`)), `${at}: Page k of N`);
  }
  // Promotions of a few notes each: each row with all its notes on one page.
  const promos = Array.from({ length: 30 }, (_, j) => ({ name: `Test promo ${j + 1}`, qty: 1, unit: 10, total: 10,
    notes: ['Fixture content A × 1 (included)', 'Fixture content B × 1 (included)', 'Fixture content C × 1 (included)'] }));
  const pages = drawnPages(buildDocumentPdf(doc(30, 1, null, { lines: promos })));
  for (const p of pages) {
    const names = p.filter(i => /^Test promo \d+$/.test(i.text)).length;
    assert.equal(p.filter(i => i.text.startsWith('Fixture content')).length, names * 3, 'a row\'s notes on its own page');
  }
  assert.equal(pages.flat().filter(i => /^Test promo \d+$/.test(i.text)).length, 30);
});

test('a first row that does not fit under the header but fits a page starts page 2, whole (review, 23 Oct 2026)', () => {
  // The review's case: a promotion of 39-41 notes first (138-145 mm) was split from its notes on
  // page 1 though it fits a page of its own (rows start 23 mm down a later page; 196 mm hold rows).
  const promo = k => ({ name: 'Promotion: Fixture Bundle', qty: 1, unit: 10, total: 10,
    notes: Array.from({ length: k }, (_, j) => `Fixture content item ${j + 1} × 1 (included)`) });
  const plainRows = n => Array.from({ length: n }, (_, j) => ({ name: `Test item ${j + 1}`, qty: 1, unit: 10, total: 10, notes: [] }));
  for (const [k, after] of [[39, 6], [41, 6], [30, 0]]) {
    const lines = [promo(k), ...plainRows(after)];
    const pages = drawnPages(buildDocumentPdf(doc(lines.length, 1, null, { lines, policyText: POLICY_195 })));
    const at = `${k} notes, ${after} rows after it`;
    const where = pages.map(p => p.filter(i => i.text.startsWith('Fixture content item') || i.text === 'Promotion: Fixture Bundle').length);
    assert.equal(where.filter(Boolean).length, 1, `${at}: the row and its notes on one page — ${JSON.stringify(where)}`);
    assert.equal(where[1], k + 1, `${at}: on page 2`);
    assert.ok(!pages[0].some(i => i.text === 'ITEM') && pages[1].some(i => i.text === 'ITEM'), `${at}: the column heads with the rows, not over an empty page 1`);
    assert.ok(pages[0].some(i => i.text === 'BILL TO') && pages[0].some(i => i.text === 'Continued on page 2'), `${at}: page 1 ends at Bill To`);
    assert.ok(pages.every(p => p.every(i => i.y >= ON_PAGE - 0.01 - 3 * PT_PER_MM)), `${at}: nothing off the foot of a page`);
    assert.deepEqual(pages.flatMap(rowNames), lines.slice(1).map(l => l.name), `${at}: every other row`);
    // The totals with the last row, the footer on the last page.
    const withTotal = pages.findIndex(p => p.some(i => i.text === 'Total'));
    assert.ok(pages[withTotal].some(i => i.text === (after ? `Test item ${after}` : 'Promotion: Fixture Bundle')), `${at}: the totals with the last row`);
    assert.ok(footerY(pages.at(-1)) >= ON_PAGE - 0.01, `${at}: the footer on its page`);
  }
});

test('when the payments onward do not fit under the totals on the last page of rows, they shorten, then take a page of their own', () => {
  // Rows that end low on their last page: the payments and the foot cannot follow the totals there.
  const seen = { ownPage: 0, shortened: 0 };
  for (const pays of [1, 2, 12]) {
    for (let n = 15; n <= 40; n++) {
      const at = `${n} rows, ${pays} payment(s)`;
      const pdf = buildDocumentPdf(doc(n, pays, OWNERS));
      const pages = drawnPages(pdf);
      const last = pages.at(-1);
      // The rows went on to a second page, and the payments to a page of their own after it.
      if (pages.length >= 3 && !rowNames(last).length && rowNames(pages.at(-2)).length) {
        seen.ownPage++;
        assert.ok(pages.at(-2).some(i => i.text === 'Total') && last.some(i => i.text === 'PAYMENT METHODS'), `${at}: the totals with the rows, the payments on`);
      }
      if (paymentsShortened(pages.flat())) seen.shortened++;
      assert.ok(footerY(last) >= ON_PAGE - 0.01, `${at}: the footer on its page`);
      assert.ok(pages.every(p => p.every(i => i.y >= ON_PAGE - 0.01 - 3 * PT_PER_MM)), `${at}: nothing off the foot of a page`);
      assert.deepEqual(pages.flatMap(rowNames), Array.from({ length: n }, (_, k) => `Test item ${k + 1}`), `${at}: every row`);
      const listed = pages.flat().filter(i => i.text.startsWith('Cash · ')).length;
      assert.ok(listed === pays || paymentsShortened(pages.flat()), `${at}: every payment, or their summary`);
    }
  }
  assert.ok(seen.ownPage > 0 && seen.shortened > 0, JSON.stringify(seen));
});

test('promotion contents never push a row off the copy (AFTER-9)', () => {
  /** `notes[i]` content lines under line i, as a promotion lists what is inside it. */
  const promoLines = notes => notes.map((n, i) => ({
    name: `Promotion line ${i + 1} with a long fixture bundle name`, qty: 1, unit: 10, total: 10,
    notes: Array.from({ length: n }, (_, k) => `Fixture content item ${k + 1} × 1 (included)`),
  }));
  for (const notes of [[4, 4, 0, 0, 0, 0], [9, 3, 0, 0], [3, 3, 3, 0], [9, 0, 0, 0, 0]]) {
    for (const pays of [1, 2]) {
      const lines = promoLines(notes);
      const d = doc(lines.length, pays, null, { lines, policyText: POLICY_195 });
      const pdf = buildDocumentPdf(d);
      const pages = drawnPages(pdf);
      const at = `notes ${notes.join(',')}, ${pays} payment(s)`;
      for (const l of lines) assert.ok(pages.flat().some(i => i.text === l.name), `${at}: "${l.name}" is drawn`);
      assert.ok(!pages.flat().some(i => i.text.startsWith('…continued')), `${at}: no row left off`);
      for (const n of notes.keys()) {
        for (let k = 1; k <= notes[n]; k++) assert.ok(pages.flat().some(i => i.text === `Fixture content item ${k} × 1 (included)`), `${at}: content ${k}`);
      }
      assert.ok(footerY(pages.at(-1)) >= ON_PAGE - 0.01, `${at}: the footer on its page`);
      assert.ok(pages.flat().every(i => i.y >= ON_PAGE - 0.01 - 3 * PT_PER_MM), `${at}: nothing drawn off the foot of a page`);
    }
  }
});

test('a payment list too long even for a second page is shortened there', () => {
  const d = doc(14, 40);
  const pdf = buildDocumentPdf(d);
  assert.equal(pdf.getNumberOfPages(), 2);
  const second = lastPage(pdf);
  assert.ok(paymentsShortened(second));
  assert.ok(second.some(i => i.text === 'S$200.00'), 'the 40 payments\' total');
  assert.ok(footerY(second) >= ON_PAGE - 0.01);
});

test('an exchange invoice says so under its header (AFTER-9)', () => {
  const note = 'Exchange invoice: replaces items from INV-T-0000';
  const items = drawn(doc(2, 1, null, { headerNote: note }));
  assert.ok(yOf(items, note) > yOf(items, 'BILL TO'), 'above Bill To');
  assert.ok(!drawn(doc(2, 1)).some(i => i.text.startsWith('Exchange invoice')), 'and only on an exchange');
});
