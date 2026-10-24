// A printed invoice longer than one A4 sheet (the Owner, 22 Oct 2026, item 5; the recommendations
// accepted): the plan of a copy's pages (src/lib/invoices/printPages.mjs, planCopyPages), the script
// that carries it into the print window, and the print markup it reads.
//
//  (a) page k of the customer copy and page k of the office copy on sheet k; one page prints as before;
//  (b) page 2 onward: a compact line and the item table's head again;
//  (c) the tail (totals to footer) whole on the last page with at least the last item line; every page
//      but the last ends "Continued on page k+1"; a line and its promotion sub-rows never split unless
//      the line alone is taller than a page; a tail taller than a page with the last row goes on between
//      its parts, the totals with the last line.
// The review of 23 Oct 2026: a first line that does not fit under the header but fits a page, and the
// only line with a tail that do not fit under it, go whole on page 2 (page 1 the header alone); a
// part taller than a page (a note of many lines, a head with many returned items) goes on between its
// rows, a table's head repeated, rather than be cut off or squeeze every other page.
// The print window itself is checked in Chrome: scripts/invoices/tests/print-pages-browser.mjs.
//
// Run: node --test scripts/invoices/tests/print-pages.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';
import { planCopyPages, PRINT_PAGES_SCRIPT } from '../../../src/lib/invoices/printPages.mjs';

const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
const printDoc = readFileSync('src/lib/printDoc.ts', 'utf8');
const between = (src, a, b) => { const i = src.indexOf(a); assert.ok(i >= 0, `not found: ${a}`); const j = src.indexOf(b, i); return src.slice(i, j < 0 ? undefined : j); };

// Heights as the print window measures them (CSS px): a half's content box, the full head, the compact
// line, the item table's head, "Continued", a plain row, a promotion sub-row, and a tail of totals,
// payments, staff and the signatures-to-footer part.
const BASE = { cap: 748, head: 210, contHead: 22, thead: 18, foot: 16 };
const TAIL = [60, 52, 30, 150];
const plain = n => Array.from({ length: n }, () => [19]);
const sum = a => a.reduce((s, v) => s + v, 0);
const EPS = 0.01;

/** A plan's input as units: the plain shape (head, thead, groups, tail) or units and theads. */
function unitsOf(p) {
  if (p.units) return { units: p.units, theads: p.theads ?? [] };
  const list = v => (v == null ? [] : Array.isArray(v) ? v : [v]);
  return { theads: [p.thead], units: [
    ...list(p.head).map(rows => ({ kind: 'head', rows })),
    ...list(p.groups).map(rows => ({ kind: 'line', table: 0, rows })),
    ...list(p.tail).map(rows => ({ kind: 'tail', rows })),
  ] };
}

/** Checks every rule a plan must keep, and returns it with its rows. */
function checked(p, label = '') {
  const pages = planCopyPages(p);
  const { units, theads } = unitsOf(p);
  // Every row: its height, its unit, kind and table.
  const rows = units.flatMap((u, k) => (Array.isArray(u.rows) ? u.rows : [u.rows]).map(h => ({ h, unit: k, kind: u.kind, table: u.table ?? -1 })));
  const n = rows.length, N = pages.length;
  const at = m => `${label}: ${m} — ${JSON.stringify(pages.map(q => [q.from, q.to]))}`;
  const unitRows = k => rows.map((r, j) => j).filter(j => rows[j].unit === k);
  const startOf = j => unitRows(rows[j].unit)[0], endOf = j => unitRows(rows[j].unit).at(-1) + 1;
  const pageOf = j => pages.findIndex(q => q.from <= j && j < q.to);
  /** What rows [a, b) take on a page, each table's head once. */
  const span = (a, b) => sum(rows.slice(a, b).map(r => r.h)) + sum([...new Set(rows.slice(a, b).map(r => r.table).filter(t => t >= 0))].map(t => theads[t] ?? 0));
  const fresh = p.cap - p.contHead - p.foot, freshLast = p.cap - p.contHead;
  assert.ok(N >= 1, at('a page'));
  // Every row once, in order, page after page; every page holds a row.
  for (const [k, pg] of pages.entries()) {
    assert.equal(pg.from, k ? pages[k - 1].to : 0, at(`page ${k + 1} starts where the last ended`));
    assert.ok(pg.to > pg.from || n === 0, at(`page ${k + 1} holds something`));
    assert.equal(pg.first, k === 0, at('first'));
    assert.equal(pg.last, k === N - 1, at('last'));
  }
  assert.equal(pages[N - 1].to, n, at('every row'));
  const lastLine = rows.map(r => r.kind).lastIndexOf('line');
  const tailStart = rows.findIndex(r => r.kind === 'tail') < 0 ? n : rows.findIndex(r => r.kind === 'tail');
  const fStart = lastLine >= 0 ? startOf(lastLine) : tailStart;
  const tailSum = sum(rows.slice(tailStart).map(r => r.h));
  const lastTh = lastLine >= 0 && rows[lastLine].table >= 0 ? theads[rows[lastLine].table] : 0;
  const tailWhole = (lastLine >= 0 ? rows[lastLine].h + lastTh : 0) + tailSum <= freshLast + EPS;
  const totalsEnd = tailStart < n ? endOf(tailStart) : n;
  // Each page within the page: its head (page 1: none but its rows), each table's head once,
  // "Continued" on all but the last. Only a page that cannot be made to fit may run over: a single
  // row, or the rest of the last line with the totals on a page of their own.
  for (const [k, pg] of pages.entries()) {
    const used = (k ? p.contHead : 0) + span(pg.from, pg.to) + (pg.last ? 0 : p.foot);
    const forced = pg.to - pg.from === 1 || (!tailWhole && pg.to === totalsEnd && pg.from >= fStart && pg.from < tailStart);
    if (!(forced && used > p.cap)) assert.ok(used <= p.cap + EPS, at(`page ${k + 1} holds ${used} of ${p.cap}`));
  }
  if (tailStart < n && lastLine >= 0) {
    // The totals never alone: they start on the page with (at least) the last row.
    assert.equal(pageOf(tailStart), pageOf(tailStart - 1), at('the totals with the last row'));
    // The tail whole on the last page, whenever it fits a page with the last row.
    if (tailWhole) assert.ok(pageOf(tailStart) === N - 1, at('the tail whole, on the last page'));
  }
  // A unit goes on between pages only when it cannot be whole: taller than a page; the last line,
  // when it and the tail (or the totals) are taller than a page; or a tail part when the tail is
  // taller than a page with the last row.
  for (let j = 1; j < n; j++) {
    if (rows[j].unit !== rows[j - 1].unit || pageOf(j) === pageOf(j - 1)) continue;
    const s = startOf(j), e = endOf(j), h = span(s, e);
    if (s === fStart && lastLine >= 0) {
      const withTail = h + (tailWhole ? tailSum : sum(rows.slice(tailStart, totalsEnd).map(r => r.h)));
      assert.ok(withTail > (tailWhole ? freshLast : fresh) + EPS, at(`the last line (${h}) split though it fits a page with the ${tailWhole ? 'tail' : 'totals'}`));
      continue;
    }
    assert.ok(h > fresh + EPS, at(`unit at row ${s} (${h}) split though it fits a page (${fresh})`));
    // An item line taller than a page starts a page of its own when other lines are before it.
    if (rows[s].kind === 'line') {
      const pg = pages[pageOf(s)];
      assert.ok(rows.slice(pg.from, s).every(r => r.kind === 'head'), at(`tall line at row ${s} starts after other lines on its page`));
    }
  }
  // Pages are filled in turn: a page ends early only when the next part does not fit on it whole
  // (the last line: with the tail, or the totals).
  for (const pg of pages.slice(0, -1)) {
    const j = pg.to;
    if (j !== startOf(j)) continue;
    const used = (pg.first ? 0 : p.contHead) + span(pg.from, pg.to);
    if (j < fStart) assert.ok(used + span(pg.from, endOf(j)) - span(pg.from, pg.to) + p.foot > p.cap + EPS, at(`page ending at ${j} had room for the next part`));
    else if (j === fStart && lastLine >= 0 && tailWhole) assert.ok((pg.first ? 0 : p.contHead) + span(pg.from, n) > p.cap + EPS, at('the last line and the tail had room'));
  }
  return { pages, rows, n, tailStart, fStart };
}
const ranges = r => r.pages.map(q => [q.from, q.to]);

test('everything on one page: one page, every row and the whole tail, as it always printed', () => {
  const p = { ...BASE, groups: plain(5), tail: TAIL };
  assert.deepEqual(checked(p, 'five lines').pages, [{ from: 0, to: 10, first: true, last: true }]);
  // Exactly full: still one page; a pixel more: two.
  const room = BASE.cap - BASE.head - BASE.thead - sum(TAIL);
  assert.equal(planCopyPages({ ...BASE, groups: [[room]], tail: TAIL }).length, 1);
  assert.equal(planCopyPages({ ...BASE, groups: [[room + 1]], tail: TAIL }).length, 2);
  assert.equal(planCopyPages({ ...BASE, groups: [], tail: [] }).length, 1, 'nothing but the head');
  assert.equal(planCopyPages({ ...BASE, groups: plain(3), tail: 100 }).length, 1, 'a tail given as one height');
});

test('many lines: pages filled in turn, the tail whole on the last with the last lines', () => {
  for (const n of [15, 19, 25, 40, 60, 150, 400]) {
    const { pages } = checked({ ...BASE, groups: plain(n), tail: TAIL }, `${n} lines`);
    // Page 1 holds the head and what fits under it; the pages after it, what fits under the compact
    // line (all but the one before the last, which may end early to carry the last line).
    if (pages.length > 2) assert.equal(pages[0].to - 1, Math.floor((BASE.cap - BASE.head - BASE.thead - BASE.foot) / 19), `${n}: page 1 full`);
    for (const pg of pages.slice(1, -2)) {
      assert.equal(pg.to - pg.from, Math.floor((BASE.cap - BASE.contHead - BASE.thead - BASE.foot) / 19), `${n}: page ${pg.from}-${pg.to} full`);
    }
    assert.ok(pages.at(-1).to - pages.at(-1).from >= 1 + TAIL.length, `${n}: the last line with the tail`);
  }
  // 19 lines: page 1 has room for all of them, but not with the tail: the last line goes on with it.
  // (Rows: the head, the 19 lines, the tail's four parts.)
  assert.deepEqual(ranges(checked({ ...BASE, groups: plain(19), tail: TAIL }, '19 lines')), [[0, 19], [19, 24]]);
  assert.deepEqual([40, 60, 150].map(n => planCopyPages({ ...BASE, groups: plain(n), tail: TAIL }).length), [2, 3, 5]);
});

test('a line and its promotion sub-rows go whole on the page where they start', () => {
  // Fourteen promotions of a line and three sub-rows, between plain lines.
  const groups = [...plain(2), ...Array.from({ length: 14 }, () => [19, 13, 13, 13]), ...plain(2)];
  const r = checked({ ...BASE, groups, tail: TAIL }, 'promotions');
  for (const pg of r.pages) assert.ok(pg.from === 0 || r.rows[pg.from].unit !== r.rows[pg.from - 1].unit, `page ${pg.from}-${pg.to} splits a line`);
  // A promotion that does not fit under the page's lines starts the next page whole.
  const p2 = checked({ ...BASE, groups: [...plain(24), [19, ...Array(10).fill(13)], ...plain(3)], tail: TAIL }, 'one promotion');
  assert.equal(p2.pages[0].to, 25, 'page 1 ends before the promotion');
});

test('the first line: whole on page 2 when it does not fit under the header but fits a page (review, 23 Oct)', () => {
  // A promotion of 45 contents first (604 px): it does not fit under page 1's head, but fits a page of
  // its own, so page 1 holds the head alone and the line goes whole on page 2.
  const promo = [19, ...Array(45).fill(13)];
  const r = checked({ ...BASE, groups: [promo, ...plain(19)], tail: TAIL }, 'first promotion');
  assert.deepEqual(r.pages[0], { from: 0, to: 1, first: true, last: false }, 'page 1: the head alone');
  assert.equal(r.pages[1].from, 1);
  assert.ok(r.pages[1].to >= 47, 'the promotion whole on page 2');
  // One taller than a page still starts right under the head: it goes on between its rows anyway.
  const tall = [19, ...Array(70).fill(13)];
  const t = checked({ ...BASE, groups: [tall, ...plain(3)], tail: TAIL }, 'first tall');
  assert.ok(t.pages[0].to > 1 && t.pages[0].to < 72, 'its first rows under the head');
});

test('the only line: with the whole tail on page 2 when they do not fit under the header (review, 23 Oct)', () => {
  // The reviewer's case: a line and a tail of totals, payments, staff and a 400 px foot (a note).
  const r = checked({ cap: 748, head: 210, contHead: 22, thead: 18, foot: 16, groups: [[19]], tail: [60, 52, 30, 400] }, 'one line');
  assert.deepEqual(ranges(r), [[0, 1], [1, 6]], 'page 1 the head alone; page 2 the line and the whole tail');
  // A tail taller than a page even with the line: the totals with the line under the head.
  const long = checked({ ...BASE, groups: [[19]], tail: [60, 52, 30, 700] }, 'one line, long tail');
  assert.ok(long.pages[0].to >= 3, 'the line and the totals on page 1');
});

test('a line taller than a page goes on between its rows', () => {
  // Seventy sub-rows: 19 + 70 x 13 = 929 px, more than any page holds.
  const tall = [19, ...Array(70).fill(13)];
  for (const groups of [[...plain(2), tall, ...plain(3)], [tall], [...plain(3), tall]]) {
    const r = checked({ ...BASE, groups, tail: TAIL }, `tall at ${groups.indexOf(tall)}`);
    const at = 1 + groups.slice(0, groups.indexOf(tall)).flat().length;
    assert.ok(r.pages.filter(pg => pg.from < at + 71 && pg.to > at).length >= 2, 'it spans pages');
    // It starts on a page of its own when lines came before it.
    if (at > 1) assert.ok(r.pages.some(pg => pg.from === at), 'it starts a page');
  }
  // One row taller than a page still gets a page (it cannot be made shorter).
  const huge = planCopyPages({ ...BASE, groups: [[19], [2000], [19]], tail: TAIL });
  assert.ok(huge.some(pg => pg.from === 2 && pg.to === 3), JSON.stringify(huge));
  assert.equal(huge.at(-1).to, 8);
});

test('the tail never alone: it carries the last line, or as much of the last line as fits with it', () => {
  const fresh = BASE.cap - BASE.contHead - BASE.thead;
  // A last promotion that fits a page with the tail: it goes on whole with it.
  const fits = [19, ...Array(30).fill(13)];
  assert.ok(sum(fits) + sum(TAIL) <= fresh);
  assert.deepEqual(ranges(checked({ ...BASE, groups: [...plain(10), fits], tail: TAIL }, 'last promotion')), [[0, 11], [11, 46]]);
  // A longer one: with the tail it is taller than a page, so its first rows stay before, and as much
  // of it as fits goes on with the tail.
  const lastPromo = [19, ...Array(36).fill(13)];
  assert.ok(sum(lastPromo) + sum(TAIL) > fresh);
  const r = checked({ ...BASE, groups: [...plain(10), lastPromo], tail: TAIL }, 'long last promotion');
  const last = r.pages.at(-1);
  assert.ok(last.from > 11 && last.to === r.n && r.pages[0].to > 11, JSON.stringify(r.pages));
  assert.ok(sum(lastPromo.slice(last.from - 11)) + sum(TAIL) <= fresh);
  assert.ok(sum(lastPromo.slice(last.from - 12)) + sum(TAIL) > fresh, 'and no more fits');
});

test('a tail taller than a page with the last row goes on between its parts, the totals with the last line', () => {
  // A note of 45 lines (560 px) in the tail, as one part.
  const tail = [60, 52, 30, 560, 150];
  const r = checked({ ...BASE, groups: plain(6), tail }, 'long note');
  assert.ok(r.pages.length >= 2);
  assert.ok(r.pages[0].to > r.tailStart, 'the lines and the totals on page 1');
  // A part taller than a page alone still gets a page.
  const huge = checked({ ...BASE, groups: plain(2), tail: [60, 2000, 150] }, 'huge part');
  assert.ok(huge.pages.some(pg => pg.from === 4 && pg.to === 5), JSON.stringify(huge.pages));
  // No item lines at all: the tail goes on between its parts.
  checked({ ...BASE, groups: [], tail: [300, 300, 300] }, 'no lines');
});

test('a note taller than a page goes on between its lines; no page is left with one part or the totals alone (review, 23 Oct)', () => {
  // The reviewer's case: twenty lines and a note of 120 one-character lines (239 characters, which the
  // server allows), its heading with its first line: 1460 px, two pages of it.
  const note = [32, ...Array(119).fill(12)];
  const r = checked({ ...BASE, groups: plain(20), tail: [60, 52, 30, note, 150] }, '120-line note');
  const noteFrom = r.tailStart + 3;
  assert.ok(r.pages.length === 4, JSON.stringify(ranges(r)));
  assert.ok(r.pages[0].to >= r.tailStart + 1, 'the totals with the last line on page 1');
  assert.ok(r.pages.slice(1).every(pg => pg.to - pg.from > 5), 'no page of a part or two alone');
  assert.ok(r.pages.filter(pg => pg.from < noteFrom + 120 && pg.to > noteFrom).length >= 2, 'the note over pages');
  // It goes on right under the parts before it (the staff), not from a page of its own.
  assert.ok(r.pages.some(pg => pg.from <= noteFrom - 1 && pg.to > noteFrom), 'the staff and the note together');
  // A note of 62 short lines on a six-line invoice of three payments (495 characters).
  checked({ ...BASE, groups: plain(6), tail: [60, 90, 30, [32, ...Array(61).fill(12)], 150] }, '62-line note');
});

test('a head taller than page 1 goes on to page 2 between its parts, a table of returned items under its head again (review, 23 Oct)', () => {
  // An exchange invoice: the header, Exchange Details, a note of 30 lines, 40 returned items (a table
  // whose head is 20 px), then twenty replacement lines and the tail.
  const units = [
    { kind: 'head', rows: 210 }, { kind: 'head', rows: 30 },
    { kind: 'head', table: 0, rows: Array(30).fill(12) },
    ...Array.from({ length: 40 }, (_, k) => ({ kind: 'head', table: 1, rows: [k === 39 ? 34 : 17] })),
    ...plain(20).map(rows => ({ kind: 'line', table: 2, rows })),
    ...TAIL.map(rows => ({ kind: 'tail', rows })),
  ];
  const p = { cap: 748, contHead: 22, foot: 16, theads: [2, 20, 18], units };
  const r = checked(p, 'exchange');
  assert.ok(r.pages.length >= 2);
  // Page 1 full: the returned items go on where it ends, on page 2.
  const returned = r.rows.map((row, j) => j).filter(j => r.rows[j].table === 1);
  assert.ok(r.pages[0].to > returned[0] && r.pages[0].to <= returned.at(-1), 'the returned items over pages 1 and 2');
  // The same with a note in the head taller than a page: it goes on between its lines.
  const tallNote = units.map((u, k) => (k === 2 ? { ...u, rows: Array(120).fill(12) } : u));
  checked({ ...p, units: tallNote }, 'exchange with a long note');
  // A head of one row taller than page 1: a page of its own.
  checked({ ...BASE, head: 800, groups: plain(3), tail: TAIL }, 'a huge head');
});

test('any invoice: every rule holds (a sweep of shapes)', () => {
  let seed = 7;
  const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
  for (let k = 0; k < 3000; k++) {
    const groups = Array.from({ length: Math.floor(rand() * 80) }, () =>
      rand() < 0.2 ? [19 + Math.floor(rand() * 20), ...Array(Math.floor(rand() * (rand() < 0.1 ? 80 : 8))).fill(13)] : [19 + (rand() < 0.2 ? 15 : 0)]);
    const tail = Array.from({ length: 1 + Math.floor(rand() * 6) }, () =>
      rand() < 0.15 ? [32, ...Array(Math.floor(rand() * 150)).fill(12)] : 20 + Math.floor(rand() * (rand() < 0.1 ? 700 : 120)));
    if (k % 3) { checked({ ...BASE, head: 120 + Math.floor(rand() * 200), groups, tail }, `shape ${k}`); continue; }
    // Exchange-like heads: a note's lines and a table of returned items in the head.
    const units = [{ kind: 'head', rows: 120 + Math.floor(rand() * 200) },
      ...(rand() < 0.5 ? [{ kind: 'head', table: 0, rows: Array(1 + Math.floor(rand() * 100)).fill(12) }] : []),
      ...Array.from({ length: Math.floor(rand() * 60) }, () => ({ kind: 'head', table: 1, rows: [17] })),
      ...groups.map(rows => ({ kind: 'line', table: 2, rows })),
      ...tail.map(rows => ({ kind: 'tail', rows }))];
    checked({ cap: 748, contHead: 22, foot: 16, theads: [2, 20, 18], units }, `exchange shape ${k}`);
  }
});

test('the print window runs the same plan: the script defines it, from minified code too', async () => {
  const fromScript = new Function(`${PRINT_PAGES_SCRIPT}; return { planCopyPages, paginatePrintCopies };`)();
  assert.equal(typeof fromScript.paginatePrintCopies, 'function');
  const shapes = [{ ...BASE, groups: plain(60), tail: TAIL }, { ...BASE, groups: [...plain(3), [19, ...Array(70).fill(13)]], tail: [60, 560, 150] },
    { cap: 748, contHead: 22, foot: 16, theads: [2, 20, 18], units: [{ kind: 'head', rows: 210 }, { kind: 'head', table: 1, rows: Array(50).fill(17) },
      ...plain(20).map(rows => ({ kind: 'line', table: 2, rows })), { kind: 'tail', rows: [32, ...Array(100).fill(12)] }, { kind: 'tail', rows: 150 }] }];
  for (const s of shapes) assert.deepEqual(fromScript.planCopyPages(s), planCopyPages(s));
  // As the app is built: minified, the functions renamed. The script still defines both by name.
  const min = await build({ entryPoints: ['src/lib/invoices/printPages.mjs'], bundle: true, minify: true, write: false, format: 'esm' });
  const lib = await import('data:text/javascript;base64,' + Buffer.from(min.outputFiles[0].text).toString('base64'));
  const minScript = Object.values(lib).find(v => typeof v === 'string');
  const fromMin = new Function(`${minScript}; return { planCopyPages, paginatePrintCopies };`)();
  for (const s of shapes) assert.deepEqual(fromMin.planCopyPages(s), planCopyPages(s));
  assert.equal(typeof fromMin.paginatePrintCopies, 'function');
  // Nothing from outside: in a scope with only the browser's own names.
  assert.doesNotThrow(() => new Function('"use strict";' + minScript));
});

test('the print markup: head and tail wrapped, each line its own body, the plan run first', () => {
  const print = between(page, 'const printInvoice = async', 'const copyButtons = detail');
  assert.match(print, /<tbody class="p-row"><tr><td>\$\{esc\(lineName\(it\)\)\}/, 'each line its own body');
  assert.match(print, /\(it\.line_kind === 'promotion' \? subFor\(it\) : ''\) \+ '<\/tbody>'/, 'with its promotion sub-rows');
  assert.match(print, /<div class="copy" data-doc-no="\$\{esc\(detail\.invoice_no\)\}">\s*<div class="p-head">\s*\$\{logosTop\}/);
  assert.match(print, /<h2>Items<\/h2>\s*\$\{exchangeBlock\}\s*<\/div>\s*<table class="p-items"><thead>[\s\S]*?<\/thead>\$\{itemRows\}<\/table>\s*<div class="p-tail">\s*<table class="totals">/);
  assert.match(print, /\$\{footerBits \? `<div class="footer">\$\{footerBits\}<\/div>` : ''\}\s*<\/div>\s*<\/div>`;/, 'the tail ends after the footer');
  // A note taller than a page goes on between its lines; the exchange's returned items between their
  // rows, the returned value with the last (review, 23 Oct 2026).
  assert.match(print, /<div data-testid="print-note" data-p-lines style=/);
  assert.match(print, /<div class="mut" data-testid="print-exchange-note" data-p-lines style=/);
  assert.match(print, /<th>Returned Item<\/th>[\s\S]*?<\/thead>\$\{\(returnedRows\.length \? returnedRows : \[''\]\)\.map\(\(r: string, k: number, all: string\[\]\) =>\s*`<tbody class="p-row">\$\{r\}\$\{k === all\.length - 1 \? returnedValue : ''\}<\/tbody>`\)\.join\(''\)\}<\/table>/);
  // The exchange document's returned items too (ExchangesPage, printA5Document).
  const exchanges = readFileSync('src/pages/ExchangesPage.tsx', 'utf8');
  assert.match(exchanges, /\.map\(i => `<tbody class="p-row"><tr><td>\$\{printEsc\(pName\(i\.product_id\)\)\}/);
  assert.match(exchanges, /<h2>Notes<\/h2><div class="mut" data-p-lines>/);
  assert.match(print, /<script>\$\{CREDIT_BALANCE_FIT_SCRIPT\}\s*\$\{PRINT_PAGES_SCRIPT\}\s*window\.onload=function\(\)\{try\{paginatePrintCopies\(planCopyPages\);\}catch\(e\)\{\}try\{fitCreditBalance\(\);\}catch\(e\)\{\}window\.print\(\);\}<\/script>/,
    'the pages first, then the credit block, then the print');
  // The receipts and the exchange print share it (printA5Document, buildCopy).
  assert.match(printDoc, /\.p-head,\.p-tail\{display:contents;\}/);
  assert.match(printDoc, /<div class="copy" data-doc-no="\$\{esc\(o\.docNo\)\}">\s*<div class="p-head">/);
  assert.match(printDoc, /<table class="p-items"><thead>[\s\S]*?<\/thead>\$\{itemRows\}<\/table>\s*<div class="p-tail">/);
  assert.match(printDoc, /const itemRows = o\.lines\.map\(l => `<tbody class="p-row">/);
  assert.match(printDoc, /window\.onload=function\(\)\{try\{paginatePrintCopies\(planCopyPages\);\}catch\(e\)\{\}window\.print\(\);\}/);
});
