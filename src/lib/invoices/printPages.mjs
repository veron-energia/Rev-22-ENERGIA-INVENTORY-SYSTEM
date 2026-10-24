// A printed invoice longer than one A4 sheet (the Owner, 22 Oct 2026, item 5;
// the recommendations accepted).
//
// The paper copy is one A4 landscape sheet: the customer copy on the left half,
// the office copy on the right, a cut line between them (src/lib/printDoc.ts,
// PRINT_CSS). Each half is a fixed 148.5 x 210 mm box, so a long invoice used to
// be cut off at the foot of both halves, silently. Now:
//
//  (a) Each sheet holds page k of the customer copy (left) and page k of the
//      office copy (right), so the cut line stays and the two copies stay the
//      same and separate. An invoice that fits one sheet prints exactly as
//      before: nothing here runs unless a half is cut off.
//  (b) Page 2 onward starts with a compact line (Energia, the invoice number,
//      CUSTOMER COPY / OFFICE COPY (continued), Page k of N), then the item
//      table's head again. The full header, the logos and Bill To are on page 1
//      only.
//  (c) The totals, payments, credit, service staff, goods, the printed note,
//      signatures, terms, policy and footer (the tail) are on the last page
//      only, never split and never alone: they carry at least the last item
//      line on to their page. Page numbers only when there is more than one
//      page; every page but the last ends "Continued on page k+1". A line and
//      its promotion sub-rows are never split unless the line alone is taller
//      than a page.
//
// Beyond the owner's rules, for what cannot fit them (nothing is ever cut off
// while a page can hold it):
//  - a tail taller than a page even with the last line alone goes on between
//    its parts, the totals with the last line; a part of it taller than a page
//    (a note of many short lines) goes on between its lines;
//  - the head goes on to page 2 only when it is taller than page 1 (an
//    exchange invoice with a very long note or list of returned items): the
//    returned items are a table of their own, its head row repeated, like the
//    item table.
//
// planCopyPages is the plan, a pure function of measured heights (tested in
// scripts/invoices/tests/print-pages.test.mjs). paginatePrintCopies measures a
// print window's copies and lays the sheets out by it. PRINT_PAGES_SCRIPT puts
// both into the print window, where window.onload runs
// `paginatePrintCopies(planCopyPages)` first, before fitCreditBalance and the
// print (InvoicesPage's print, and printA5Document for the receipts and the
// exchange document).
//
// The markup they read (copyHtml in src/pages/InvoicesPage.tsx, buildCopy in
// src/lib/printDoc.ts): each .copy carries data-doc-no; its head is wrapped in
// .p-head and its tail in .p-tail, both display:contents so the halves lay out
// exactly as before; the item table is table.p-items. In it, and in any other
// table that may run long (the returned items), each line with its sub-rows is
// its own tbody.p-row. A note that may run long carries data-p-lines.

/**
 * The pages of one copy, from the heights of its parts (any one unit, e.g. CSS
 * pixels or mm).
 *
 *  cap       what one page of the copy holds (its content box)
 *  contHead  what pages 2 onward start with: the compact "(continued)" line
 *  foot      the "Continued on page k+1" line that ends every page but the last
 *  units     the copy's parts, top to bottom: { kind, rows, table }
 *            kind   'head' (page 1's header down to the items), 'line' (an item
 *                   line), 'tail' (the totals down to the footer)
 *            rows   the heights of its rows (a number alone: one row): an item
 *                   line and its promotion sub-rows; a note's lines; a part of
 *                   one row
 *            table  the table (or note) its rows are in, by index into theads,
 *                   or none
 *  theads    for each table: what it takes on every page its rows are on (its
 *            head row and margins)
 *
 * or, the plain shape: head (a height, or the head's parts), thead (the item
 * table's head row), groups (each item line as the heights of its rows, or one
 * number) and tail (the tail's parts, or its height alone).
 *
 * Returns one entry a page: rows [from, to) of all the units' rows, in order,
 * are on it. One page, everything, when everything fits; otherwise every page
 * is filled in turn:
 *  - a part goes whole on the page where it starts, leaving room for the
 *    "Continued" line; else whole on the next page. Only one taller than a page
 *    goes on between its rows, from where it is; an item line, though, from
 *    the top of a page when other lines are already on this one;
 *  - the last item line goes with the whole tail on the last page when they fit
 *    a page together; else the tail goes whole with as much of the line as fits
 *    a page with it (its first rows before); only a tail taller than a page
 *    with the last row alone goes on between its parts, its first (the totals)
 *    with the rest of the last line;
 *  - every page holds at least one row: a row taller than a page still gets a
 *    page of its own (it cannot be made shorter here).
 * So page 1 may hold the head alone, when the first line does not fit under
 * it but fits a page of its own (it is not split), or when the only line and
 * the tail do not fit under it but fit a page together.
 *
 * Self-contained (no names from outside it, no newer syntax), as it is also
 * written into the print window as text (PRINT_PAGES_SCRIPT).
 */
export function planCopyPages(p) {
  var EPS = 0.01;
  var num = function (v) { v = Number(v); return isFinite(v) && v > 0 ? v : 0; };
  var list = function (v) { return v == null ? [] : (Array.isArray(v) ? v : [v]); };
  p = p || {};
  var cap = Number(p.cap) || 0, contHead = num(p.contHead), foot = num(p.foot);
  var units = p.units, theads = p.theads || [];
  if (!units) {
    // The plain shape: the head, the item table's lines, the tail's parts.
    units = []; theads = [p.thead];
    var hd = list(p.head), gs = list(p.groups), tl = list(p.tail);
    for (var a = 0; a < hd.length; a++) units.push({ kind: 'head', rows: hd[a] });
    for (a = 0; a < gs.length; a++) units.push({ kind: 'line', table: 0, rows: gs[a] });
    for (a = 0; a < tl.length; a++) units.push({ kind: 'tail', rows: tl[a] });
  }
  // Every row in order: its height, where its unit starts and ends, its kind
  // (0 the head, 1 an item line, 2 the tail) and its table (-1: none).
  var hs = [], starts = [], ends = [], kinds = [], tabs = [];
  for (var u = 0; u < units.length; u++) {
    var rows = list(units[u] && units[u].rows);
    if (!rows.length) continue;
    var kd = units[u].kind === 'line' ? 1 : (units[u].kind === 'tail' ? 2 : 0);
    var tb = typeof units[u].table === 'number' && units[u].table >= 0 ? units[u].table : -1;
    var s0 = hs.length, e0 = s0 + rows.length;
    for (var r = 0; r < rows.length; r++) { hs.push(num(rows[r])); starts.push(s0); ends.push(e0); kinds.push(kd); tabs.push(tb); }
  }
  var n = hs.length;
  var th = function (t) { return t >= 0 ? num(theads[t]) : 0; };
  var sum = function (a, b) { var s = 0; for (var k = a; k < b; k++) s += hs[k]; return s; };
  // What rows [a, b) take on a page where the tables in `seen0` already are.
  var span = function (a, b, seen0) {
    var s = 0, seen = {};
    for (var k = a; k < b; k++) {
      s += hs[k];
      var t = tabs[k];
      if (t >= 0 && !seen0[t] && !seen[t]) { seen[t] = 1; s += th(t); }
    }
    return s;
  };

  // Everything on one page: as it always printed.
  if (span(0, n, {}) <= cap + EPS) return [{ from: 0, to: n, first: true, last: true }];

  var lastLine = -1, tailStart = n;
  for (var k = 0; k < n; k++) {
    if (kinds[k] === 1) lastLine = k;
    if (kinds[k] === 2 && tailStart === n) tailStart = k;
  }
  // The last item line and the tail after it (the tail alone, with no lines).
  var fStart = lastLine >= 0 ? starts[lastLine] : tailStart;
  var lastTab = lastLine >= 0 ? tabs[lastLine] : -1;
  // A page after the first: what it holds as the last page, and before it.
  var freshLast = cap - contHead, fresh = freshLast - foot;
  var tailSum = sum(tailStart, n);
  // The tail stays whole when it fits a page with at least the last row.
  var tailWhole = (lastLine >= 0 ? hs[lastLine] + th(lastTab) : 0) + tailSum <= freshLast + EPS;

  var pages = [], i = 0, from = 0, used = 0, room = 0, on = {}, body = false;
  // Rows [i, b) on this page.
  var place = function (b) {
    used += span(i, b, on);
    for (; i < b; i++) { if (tabs[i] >= 0) on[tabs[i]] = 1; if (kinds[i]) body = true; }
  };
  // Rows from i on, before b, one by one while they fit with "Continued"; at
  // least one on a page that holds nothing yet.
  var fill = function (b) {
    while (i < b && used + span(i, i + 1, on) + foot <= room + EPS) place(i + 1);
    if (i === from && i < b) place(i + 1);
  };
  var guard = 0;
  while (i < n && guard++ < 100000) {
    from = i; used = 0; on = {}; body = false;
    room = cap - (pages.length ? contHead : 0);
    while (i < n) {
      // Everything left fits: the last page.
      if (used + span(i, n, on) <= room + EPS) { place(n); break; }
      var e = ends[i];
      if (i < fStart) {
        // A part before the last item line: whole where it starts, with room
        // left for "Continued"; else whole on the next page, when it fits one.
        if (used + span(i, e, on) + foot <= room + EPS) { place(e); continue; }
        if (i > from && (sum(i, e) + th(tabs[i]) <= fresh + EPS || (body && kinds[i] === 1))) break;
        // Taller than a page: it goes on between its rows, from here (an item
        // line from the top of a page, when lines are before it here).
        fill(e); break;
      }
      if (i < tailStart) {
        // The last item line, and the tail with it: together on the next page,
        // when they fit one.
        if (i > from && sum(i, n) + th(lastTab) <= freshLast + EPS) break;
        if (tailWhole) {
          // Taller than a page together: the tail whole with as much of the
          // line as fits a page with it, the line's first rows [i, keep) before.
          var keep = tailStart - 1, s = hs[keep] + th(lastTab) + tailSum;
          while (keep - 1 > i && s + hs[keep - 1] <= freshLast + EPS) { s += hs[keep - 1]; keep--; }
          if (used + span(i, keep, on) + foot <= room + EPS) { place(keep); break; }
          if (i > from && body) break;
          fill(keep); break;
        }
        // The tail is taller than a page even with the last row alone: it goes
        // on between its parts, the first (the totals) with the rest of the line.
        var tot = tailStart < n ? ends[tailStart] : n;
        if (used + span(i, tot, on) + foot <= room + EPS) { place(tot); continue; }
        if (i > from && (sum(i, tot) + th(lastTab) <= fresh + EPS || body)) break;
        fill(tailStart - 1);
        if (i === from) place(tot);
        break;
      }
      // The tail's parts after the totals (or the tail with no item lines):
      // each whole where it starts, else on the next page; one taller than a
      // page (a note of many lines) goes on between its rows, from here.
      if (tailWhole && i === tailStart && i > from) break;
      if (used + span(i, e, on) + foot <= room + EPS) { place(e); continue; }
      if (i > from && sum(i, e) <= fresh + EPS) break;
      fill(e); break;
    }
    pages.push({ from: from, to: i, first: pages.length === 0, last: false });
  }
  if (pages.length) pages[pages.length - 1].last = true;
  return pages;
}

/**
 * Lays out the print window's sheet as the pages the copies need: run once the
 * page has laid out (window.onload), before fitCreditBalance and the print,
 * with planCopyPages as `plan`. Does nothing when no half is cut off at its
 * foot, so an invoice that fits one sheet is left exactly as it was. Otherwise
 * it measures the customer copy at its full length, plans its pages, and puts
 * in place of the one sheet one sheet a page: page k of the customer copy, the
 * cut line, page k of the office copy (the same markup, so the two stay in
 * step). Built aside and swapped in at once, so a failure part-way leaves the
 * page as it was.
 *
 * If a built page still runs past its half (a measure a few pixels out, e.g. a
 * table's columns sized anew for fewer rows), it plans again with that much
 * less room, but only for a page that holds more than one row, as only that
 * can be mended: a single row taller than a page stays as it is, and the other
 * pages keep their room. Of the plans tried, the one that runs least past its
 * halves (then on fewer sheets) is kept. Returns how many sheets there are.
 *
 * Self-contained, as it is written into the print window as text.
 */
export function paginatePrintCopies(plan) {
  var sheet = document.querySelector('.sheet');
  if (!sheet || !sheet.parentNode) return 1;
  var copiesOf = function (s) {
    var out = [];
    for (var c = s.firstElementChild; c; c = c.nextElementSibling) if (c.classList.contains('copy')) out.push(c);
    return out;
  };
  var copies = copiesOf(sheet);
  if (!copies.length || !copies[0].querySelector('table.p-items')) return 1;
  var px = function (v) { return parseFloat(v) || 0; };
  // The boxes a copy lays out: its children, and the children of a wrapper
  // that draws no box of its own (.p-head, .p-tail: display:contents).
  var boxes = function (el) {
    var out = [];
    for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
      var d = getComputedStyle(c).display;
      if (d === 'contents') out = out.concat(boxes(c));
      else if (d !== 'none') out.push(c);
    }
    return out;
  };
  // How far a copy's content runs past `edge` px above its foot (0: it does not).
  var over = function (copy, edge) {
    var all = boxes(copy), low = -Infinity;
    for (var k = 0; k < all.length; k++) low = Math.max(low, all[k].getBoundingClientRect().bottom);
    return Math.max(0, low - (copy.getBoundingClientRect().bottom - edge));
  };
  var cut = false;
  for (var k = 0; k < copies.length; k++) if (over(copies[k], 0) > 0.5) cut = true;
  if (!cut) return 1;

  // A note that may run long (data-p-lines) goes on between its lines: each
  // line, between its <br>s, in a box of its own, laid out as before (a blank
  // line keeps its height; the break after the last line draws none).
  var blank = function (nodes) {
    for (var j = 0; j < nodes.length; j++) {
      if (nodes[j].nodeType === 1 || (nodes[j].nodeType === 3 && /\S/.test(nodes[j].nodeValue))) return false;
    }
    return true;
  };
  var splitLines = function (el) {
    var segs = [[]];
    while (el.firstChild) {
      var c = el.firstChild;
      el.removeChild(c);
      if (c.nodeType === 1 && c.tagName === 'BR') segs.push([]);
      else segs[segs.length - 1].push(c);
    }
    if (segs.length > 1 && blank(segs[segs.length - 1])) segs.pop();
    for (var j = 0; j < segs.length; j++) {
      var d = document.createElement('div');
      d.className = 'p-line';
      if (blank(segs[j])) d.appendChild(document.createElement('br'));
      else for (var q = 0; q < segs[j].length; q++) d.appendChild(segs[j][q]);
      el.appendChild(d);
    }
  };
  for (k = 0; k < copies.length; k++) {
    var notes = copies[k].querySelectorAll('[data-p-lines]');
    for (var j0 = 0; j0 < notes.length; j0++) splitLines(notes[j0]);
  }

  // A copy's rows, top to bottom, as the plan counts them: each with the
  // elements it is drawn as (a heading goes with what follows it; the
  // signatures with everything after them), its unit, its kind and its table
  // (a table of tbody.p-row lines, or a note's lines; `own` is that element).
  var rowsOf = function (copy) {
    var out = [], pending = [], unit = 0, tables = 0, after = false, kd = 0;
    var tailWrap = copy.querySelector('.p-tail');
    var push = function (els, table, own) {
      out.push({ els: pending.concat(els), kind: kd, table: table, unit: unit, own: own });
      pending = [];
    };
    var all = boxes(copy);
    for (var j = 0; j < all.length; j++) {
      var el = all[j];
      var items = el.tagName === 'TABLE' && el.classList.contains('p-items');
      kd = items ? 1 : (after || (tailWrap && tailWrap.contains(el)) ? 2 : 0);
      if (items) after = true;
      if (el.tagName === 'H2') { pending.push(el); continue; }
      if (kd === 2 && el.classList.contains('signrow')) { push(all.slice(j), -1, null); unit++; pending = []; break; }
      var bodies = [];
      if (el.tagName === 'TABLE') {
        for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
          if (c.tagName === 'TBODY' && c.classList.contains('p-row') && c.rows.length) bodies.push(c);
        }
      }
      if (bodies.length) {
        var t = tables++;
        for (var b = 0; b < bodies.length; b++) {
          for (var r = 0; r < bodies[b].rows.length; r++) push([bodies[b].rows[r]], t, el);
          unit++;
        }
        continue;
      }
      if (el.hasAttribute('data-p-lines') && el.firstElementChild) {
        t = tables++;
        for (c = el.firstElementChild; c; c = c.nextElementSibling) push([c], t, el);
        unit++;
        continue;
      }
      push([el], -1, null); unit++;
    }
    if (pending.length) { push([], -1, null); unit++; }
    return out;
  };

  var text = function (el, s) { el.appendChild(document.createTextNode(s)); return el; };
  var bold = function (s) { return text(document.createElement('b'), s); };
  var tagOf = function (copy) { var t = copy.querySelector('.copytag'); return t ? t.textContent.trim() : ''; };
  // Page 2 onward: Energia, the number, the copy (continued), Page k of N.
  var contLine = function (copy, tag, k, n) {
    var d = document.createElement('div');
    d.className = 'p-conthead';
    d.setAttribute('style', 'display:flex;justify-content:space-between;align-items:baseline;gap:8px;'
      + 'border-bottom:1.5px solid #111;padding-bottom:3px;margin-bottom:2px;font-size:10px;');
    var left = document.createElement('div'), right = document.createElement('div');
    left.appendChild(bold('Energia'));
    var no = copy.getAttribute('data-doc-no') || '';
    if (no) text(left, ' · ' + no);
    right.appendChild(bold(tag || 'COPY'));
    text(right, ' (continued) · Page ' + k + ' of ' + n);
    d.appendChild(left); d.appendChild(right);
    return d;
  };
  var contFoot = function (k) {
    var d = text(document.createElement('div'), 'Continued on page ' + k);
    d.className = 'mut p-cont'; d.setAttribute('style', 'text-align:right;margin-top:3px;');
    return d;
  };
  var addPageNo = function (copy, n) {
    var tag = copy.querySelector('.copytag');
    if (!tag || !tag.parentNode) return;
    var s = text(document.createElement('span'), 'Page 1 of ' + n);
    s.className = 'mut p-pageno'; s.setAttribute('style', 'margin-left:6px;');
    tag.parentNode.insertBefore(s, tag.nextSibling);
  };
  var outer = function (el) {
    var cs = getComputedStyle(el), b = el.getBoundingClientRect();
    return { top: b.top - px(cs.marginTop), bottom: b.bottom + px(cs.marginBottom) };
  };
  var height = function (el) { var o = outer(el); return o.bottom - o.top; };

  // Each row's elements tagged with its number (data-p-r), and each table or
  // note its rows are in (data-p-own), on both copies: a page is shaped from a
  // copy of them by these, as a copy not yet on the page has no layout to
  // read. The two copies are the same markup, so the same rows.
  var rowCount = -1;
  for (k = 0; k < copies.length; k++) {
    var live = rowsOf(copies[k]);
    if (rowCount >= 0 && live.length !== rowCount) return 1;
    rowCount = live.length;
    for (var j1 = 0; j1 < live.length; j1++) {
      for (var q1 = 0; q1 < live[j1].els.length; q1++) live[j1].els[q1].setAttribute('data-p-r', String(j1));
      if (live[j1].own) live[j1].own.setAttribute('data-p-own', '');
    }
  }

  // Measured at full length: a copy of the customer copy, its height free.
  var model = copies[0], mcs = getComputedStyle(model);
  var cap = model.clientHeight - px(mcs.paddingTop) - px(mcs.paddingBottom);
  var m = model.cloneNode(true);
  m.style.height = 'auto'; m.style.minHeight = '0'; m.style.maxHeight = 'none'; m.style.overflow = 'visible';
  m.style.position = 'absolute'; m.style.left = '-100000px'; m.style.top = '0';
  addPageNo(m, 2);
  sheet.parentNode.appendChild(m);
  var measured;
  try {
    var mr = rowsOf(m);
    if (mr.length !== rowCount) return 1;
    var units = [], theads = [];
    for (var x = 0; x < mr.length; x++) {
      var row = mr[x], h = 0;
      for (var y = 0; y < row.els.length; y++) {
        var el = row.els[y];
        if (row.own && y === row.els.length - 1) {
          // A table's or a note's row: to where the next of its rows starts.
          var top = el.getBoundingClientRect().top;
          var nx = x + 1 < mr.length && mr[x + 1].own === row.own ? mr[x + 1].els[mr[x + 1].els.length - 1] : null;
          h += (nx ? nx.getBoundingClientRect().top : el.getBoundingClientRect().bottom) - top;
          // The table's head and margins, on every page its rows are on.
          if (theads[row.table] == null) theads[row.table] = top - outer(row.own).top;
          if (!nx) theads[row.table] += outer(row.own).bottom - el.getBoundingClientRect().bottom;
        } else h += height(el);
      }
      if (!units.length || units[units.length - 1].id !== row.unit) {
        units.push({ id: row.unit, kind: row.kind === 1 ? 'line' : (row.kind === 2 ? 'tail' : 'head'), table: row.table, rows: [] });
      }
      units[units.length - 1].rows.push(h);
    }
    // Page 2 onward: the compact line on top; every page but the last: "Continued".
    var cl = contLine(m, tagOf(m), 2, 2);
    m.insertBefore(cl, m.firstChild);
    var contHead = height(cl);
    var cf = contFoot(2);
    m.appendChild(cf);
    var foot = height(cf);
    measured = { cap: cap, contHead: contHead, foot: foot, theads: theads, units: units };
  } finally {
    m.parentNode.removeChild(m);
  }

  // One copy's page: its rows (and the tables and notes they are in), the
  // compact line or the page number, and "Continued" on all but the last.
  var shape = function (copy, pg, k, n) {
    var tag = tagOf(copy);
    var els = copy.querySelectorAll('[data-p-r]'), owners = copy.querySelectorAll('[data-p-own]');
    for (var j = 0; j < els.length; j++) {
      var r = Number(els[j].getAttribute('data-p-r'));
      if ((r < pg.from || r >= pg.to) && els[j].parentNode) els[j].parentNode.removeChild(els[j]);
    }
    for (j = 0; j < owners.length; j++) {
      var own = owners[j], left = 0;
      if (own.tagName === 'TABLE') {
        for (var c = own.firstElementChild, nc; c; c = nc) {
          nc = c.nextElementSibling;
          if (c.tagName === 'TBODY' && c.classList.contains('p-row')) { if (c.rows.length) left++; else own.removeChild(c); }
        }
      } else left = own.children.length;
      if (!left && own.parentNode) own.parentNode.removeChild(own);
    }
    if (k === 1) addPageNo(copy, n);
    else copy.insertBefore(contLine(copy, tag, k, n), copy.firstChild);
    if (k < n) copy.appendChild(contFoot(k + 1));
    copy.setAttribute('data-page', String(k));
  };
  var build = function (pages) {
    var out = [];
    for (var k = 0; k < pages.length; k++) {
      var s = sheet.cloneNode(false);
      for (var c = sheet.firstElementChild; c; c = c.nextElementSibling) {
        var cl = c.cloneNode(true);
        if (c.classList.contains('copy')) shape(cl, pages[k], k + 1, pages.length);
        s.appendChild(cl);
      }
      if (k < pages.length - 1) { s.style.pageBreakAfter = 'always'; s.style.breakAfter = 'page'; }
      s.setAttribute('data-page', String(k + 1));
      out.push(s);
    }
    return out;
  };

  var parent = sheet.parentNode, next = sheet.nextSibling, shown = null, best = null, less = 1;
  var swap = function (els) {
    if (shown) for (var j = 0; j < shown.length; j++) parent.removeChild(shown[j]);
    else parent.removeChild(sheet);
    for (j = 0; j < els.length; j++) parent.insertBefore(els[j], next);
    shown = els;
  };
  for (var attempt = 0; attempt < 4; attempt++) {
    var pages = plan({ cap: measured.cap - less, contHead: measured.contHead, foot: measured.foot,
      theads: measured.theads, units: measured.units });
    if (!pages || pages.length < 2) break;
    var made = build(pages);
    swap(made);
    // How far each page runs past its half's content box, and how much of
    // that less room can mend (a page of more than one row).
    var lost = 0, mend = 0;
    for (k = 0; k < made.length; k++) {
      var cs = copiesOf(made[k]), o = 0;
      for (var c2 = 0; c2 < cs.length; c2++) o = Math.max(o, over(cs[c2], px(getComputedStyle(cs[c2]).paddingBottom)));
      if (o <= 0.5) continue;
      lost += o;
      if (pages[k].to - pages[k].from > 1) mend = Math.max(mend, o);
    }
    if (!best || lost < best.lost - 0.5 || (lost <= best.lost + 0.5 && made.length < best.made.length)) best = { made: made, lost: lost };
    if (mend <= 0.5) break;
    less += mend + 1;
  }
  if (best && shown !== best.made) swap(best.made);
  return shown ? shown.length : 1;
}

/**
 * The two functions above, for the print window's own <script>. Its
 * window.onload runs `paginatePrintCopies(planCopyPages)` first (in a try, so
 * a failure prints the sheet as it is), then fitCreditBalance, then the print.
 */
export const PRINT_PAGES_SCRIPT = `var planCopyPages = (${planCopyPages.toString()});
var paginatePrintCopies = (${paginatePrintCopies.toString()});`;
