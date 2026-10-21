import { PdfDoc, PdfLine, CopyDrawing, fitCreditBalanceDrawing, fitAroundCollection, fitAroundPayments, creditBesideTotals, copyTerms,
  copyCollectionDrawn, copyPaymentRows } from './invoicePdf';
import { wrapCreditDetail } from './invoices/creditBalanceLine.mjs';

/**
 * Renders the customer copy as a PNG.
 *
 * WhatsApp shows an image inline in the chat, so the customer sees the invoice
 * without opening anything — often nicer than a PDF for a short receipt. The
 * layout deliberately mirrors buildDocumentPdf so both look like the same
 * document.
 *
 * Drawn with the browser's own Canvas API rather than by adding html2canvas,
 * which would pull in a large dependency to rasterise markup we would have to
 * build anyway.
 */

const MM = 8;                       // pixels per mm — A5 becomes 1188 x 1680
const W = Math.round(148.5 * MM);
const H = Math.round(210 * MM);
const M = 10 * MM;                  // margin
const RIGHT = W - M;

const GREY = '#6e6e6e';
const BLACK = '#111111';

export function documentImageBlob(d: PdfDoc): Promise<Blob> {
  let c: HTMLCanvasElement;
  try {
    // The goods and then the credit balance line give way on the image as on
    // the PDF — see fitAroundCollection and fitAroundCreditBalance. A canvas
    // thrown away is released at once: phones cap the canvas memory a page
    // may hold.
    const release = (old: HTMLCanvasElement) => { old.width = 0; old.height = 0; };
    // When the copy still runs off the A5 page, the payments shorten to one
    // row, then the image grows taller (fitAroundPayments), as the PDF takes
    // a second page.
    c = fitAroundPayments(d, dd => fitCreditBalanceDrawing(dd,
      ddd => fitAroundCollection(ddd, drawDocumentImage, H - (M / 2), release), H - (M / 2), release),
      H - (M / 2), release, true);
  } catch (e) {
    return Promise.reject(e);
  }
  return new Promise((resolve, reject) => {
    c.toBlob(b => b ? resolve(b) : reject(new Error('Could not create the invoice image.')), 'image/png');
  });
}

/** How far down an image may run and still be one A5 page. */
const FOOT = H - M / 2;

/**
 * One drawing of the copy, and how far down the image it ran.
 *
 * A copy that runs long (pageBreak) grows instead of taking a second page
 * (B16, AFTER-8): it is measured on a canvas three pages tall, then drawn
 * again on one exactly as tall as it needs, never shorter than an A5 page. A
 * canvas that grows always fits, so nothing above has to give way for it.
 *
 * As on the PDF, an A5 drawing lists the item rows only down to the room the
 * signatures need; past that the copy goes to the growing drawing, which
 * lists every row down to three pages (B16, AFTER-9). If that copy fits one
 * A5 page once its goods and credit line are left off, those give way as on
 * an A5 copy (it says how far down it really ran), so they never make the
 * image grow.
 */
function drawDocumentImage(d: PdfDoc): CopyDrawing<HTMLCanvasElement> {
  if (!d.pageBreak) return paintDocumentImage(d, H, H - 70 * MM);
  const rowLimit = H * 3 - 70 * MM;
  const probe = paintDocumentImage(d, H * 3, rowLimit);
  probe.out.width = 0; probe.out.height = 0;
  const grown = paintDocumentImage(d, Math.max(H, Math.ceil(probe.endY + M / 2)), rowLimit);
  const { bareEndY, ...drawing } = grown;
  return { ...drawing, endY: bareEndY <= FOOT + 0.01 ? grown.endY : Math.min(grown.endY, FOOT) };
}

/** The copy drawn on a canvas of the given height, its item rows listed
 *  while they end above `rowLimit`; and how far down it would have run
 *  without its goods and credit line (`bareEndY`). */
function paintDocumentImage(d: PdfDoc, height: number, rowLimit: number): CopyDrawing<HTMLCanvasElement> & { bareEndY: number } {
  const c = document.createElement('canvas');
  c.width = W; c.height = height;
  const x = c.getContext('2d');
  if (!x) throw new Error('This browser cannot render the invoice image.');

  const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
  const font = (size: number, weight: 'normal' | 'bold' | 'italic' | 'bold italic' = 'normal') =>
    (x.font = `${weight} ${size * MM}px Helvetica, Arial, sans-serif`);
  const right = (t: string, rx: number, ry: number) => {
    x.textAlign = 'right'; x.fillText(t, rx, ry); x.textAlign = 'left';
  };
  /** Wraps to the given width and returns the lines. */
  const wrap = (t: string, maxW: number): string[] => {
    const words = String(t).split(/\s+/); const out: string[] = []; let line = '';
    for (const w of words) {
      const t2 = line ? `${line} ${w}` : w;
      if (x.measureText(t2).width > maxW && line) { out.push(line); line = w; } else { line = t2; }
    }
    if (line) out.push(line);
    return out;
  };

  x.fillStyle = '#ffffff'; x.fillRect(0, 0, W, c.height);
  x.textBaseline = 'alphabetic';
  let y = M + 4 * MM;

  // ---- Header -------------------------------------------------------
  x.fillStyle = BLACK; font(6.76, 'bold');
  x.fillText('Energia', M, y);
  font(3.12); x.fillStyle = GREY;
  x.fillText('Wellness & Retail', M, y + 3.4 * MM);

  x.fillStyle = BLACK; font(5.2, 'bold');
  right(d.docNo, RIGHT, y);
  font(3.12); x.fillStyle = GREY;
  let hy = y + 3.4 * MM;
  for (const t of [d.kindLabel, d.storeName, d.storeAddress,
                   d.storePhone ? `Tel: ${d.storePhone}` : '',
                   `Date: ${d.date}`, d.status ? `Status: ${d.status}` : '']) {
    if (!t) continue;
    for (const ln of wrap(String(t), 80 * MM)) { right(ln, RIGHT, hy); hy += 3.9 * MM; }
  }

  y = Math.max(y + 6 * MM, hy) + 1 * MM;
  x.strokeStyle = BLACK; x.lineWidth = 0.4 * MM;
  x.beginPath(); x.moveTo(M, y); x.lineTo(RIGHT, y); x.stroke();
  y += 5 * MM;

  // ---- A note under the header (an exchange invoice), as on the PDF --
  if (d.headerNote) {
    font(3.12, 'bold'); x.fillStyle = BLACK;
    for (const ln of wrap(d.headerNote, RIGHT - M)) { x.fillText(ln, M, y); y += 3.9 * MM; }
    y += 1.5 * MM;
  }

  // ---- Customer -----------------------------------------------------
  font(3.12, 'bold'); x.fillStyle = GREY;
  x.fillText('BILL TO', M, y); y += 4 * MM;
  font(4.16); x.fillStyle = BLACK;
  x.fillText(d.customerName, M, y); y += 3.6 * MM;
  if (d.customerContact) {
    font(3.12); x.fillStyle = GREY; x.fillText(d.customerContact, M, y); y += 3.6 * MM;
  }
  y += 2 * MM;

  // ---- Items --------------------------------------------------------
  const cQty = RIGHT - 46 * MM, cUnit = RIGHT - 24 * MM, cTot = RIGHT;
  font(3.12, 'bold'); x.fillStyle = GREY;
  x.fillText('ITEM', M, y);
  right('QTY', cQty, y); right('UNIT', cUnit, y); right('TOTAL', cTot, y);
  y += 1.5 * MM;
  x.strokeStyle = '#969696'; x.lineWidth = 0.2 * MM;
  x.beginPath(); x.moveTo(M, y); x.lineTo(RIGHT, y); x.stroke();
  y += 3.6 * MM;

  const drawLine = (l: PdfLine) => {
    font(3.64); x.fillStyle = BLACK;
    const nameLines = wrap(l.name, cQty - M - 3 * MM);
    let ny = y;
    for (const ln of nameLines) { x.fillText(ln, M, ny); ny += 4.2 * MM; }
    right(String(l.qty), cQty, y);
    right(money(l.unit), cUnit, y);
    font(3.64, 'bold'); right(money(l.total), cTot, y); font(3.64);
    for (const n of l.notes ?? []) {
      font(2.73); x.fillStyle = GREY;
      x.fillText(n, M + 2 * MM, ny); ny += 3.6 * MM;
      font(3.64); x.fillStyle = BLACK;
    }
    // Separator sits below the row just drawn, clear of the next baseline.
    const sepY = ny - 1.2 * MM;
    x.strokeStyle = '#e6e6e6'; x.lineWidth = 0.15 * MM;
    x.beginPath(); x.moveTo(M, sepY); x.lineTo(RIGHT, sepY); x.stroke();
    y = sepY + 5.4 * MM;
  };

  // B16 (AFTER-9): a row's height as it is drawn (names 4.2 mm a line, notes
  // 3.6 mm each), so a promotion's contents never push a row past the limit.
  let rowsCut = false;
  font(3.64);
  for (const l of d.lines) {
    const rowH = wrap(l.name, cQty - M - 3 * MM).length * 4.2 * MM + (l.notes?.length ?? 0) * 3.6 * MM + 1.6 * MM;
    if (y + rowH > rowLimit) {
      font(3.12); x.fillStyle = GREY;
      x.fillText('…continued — see the full invoice in store', M, y);
      y += 4 * MM; x.fillStyle = BLACK;
      rowsCut = true;
      break;
    }
    drawLine(l);
  }

  // ---- Totals -------------------------------------------------------
  y += 2 * MM; font(3.64);
  const totalsTop = y;
  let totalsBottom = -Infinity;
  const totalsLabelW = Math.max(0, ...d.totals.map(([label]) => x.measureText(label).width));
  for (const [label, value] of d.totals) {
    x.fillStyle = GREY; right(label, cUnit, y);
    x.fillStyle = BLACK; right(value, cTot, y);
    totalsBottom = y;
    y += 4.8 * MM;
  }
  if (d.grandTotal) {
    x.strokeStyle = '#969696'; x.lineWidth = 0.3 * MM;
    x.beginPath(); x.moveTo(cUnit - 22 * MM, y - 2.6 * MM); x.lineTo(RIGHT, y - 2.6 * MM); x.stroke();
    font(4.81, 'bold'); x.fillStyle = BLACK;
    right(d.grandTotal[0], cUnit, y + 1.4 * MM);
    right(d.grandTotal[1], cTot, y + 1.4 * MM);
    totalsBottom = y + 1.4 * MM;
    y += 6 * MM;
  }

  // ---- Credit balance beside the totals, where it costs no height -----
  let creditBeside = false;
  if (d.creditBalance) {
    const width = Math.min(cUnit - 22 * MM, cUnit - totalsLabelW) - 4 * MM - M;
    font(3.64, 'bold');
    const labelW = x.measureText(d.creditBalance.label).width, amountW = x.measureText(d.creditBalance.amount).width;
    font(2.9);
    const detail = d.creditBalance.detail ? wrapCreditDetail(d.creditBalance.detail, width, t => x.measureText(t).width) : [];
    const at = creditBesideTotals({ top: totalsTop, bottom: totalsBottom, width, labelW, amountW,
      detailLines: detail.map(t => ({ width: x.measureText(t).width })), lineH: 4.2 * MM, detailH: 3.4 * MM, gap: 3 * MM });
    if (at) {
      creditBeside = true;
      font(3.64, 'bold'); x.fillStyle = BLACK;
      x.fillText(d.creditBalance.label, M, at.labelY);
      if (at.amountOnLabelLine) right(d.creditBalance.amount, M + width, at.amountY);
      else x.fillText(d.creditBalance.amount, M, at.amountY);
      font(2.9); x.fillStyle = GREY;
      detail.forEach((ln, i) => x.fillText(ln, M, at.detailY[i]));
    }
    font(3.64); x.fillStyle = BLACK;
  }

  // ---- Payments: every one, or one summary row (fitAroundPayments) ----
  const paymentRows = copyPaymentRows(d);
  if (paymentRows.length) {
    y += 2 * MM;
    font(3.12, 'bold'); x.fillStyle = GREY;
    x.fillText('PAYMENT METHODS', M, y); y += 4 * MM;
    font(3.64); x.fillStyle = BLACK;
    for (const [k, v] of paymentRows) { x.fillText(k, M, y); right(v, cTot, y); y += 4.6 * MM; }
  }

  // ---- Credit balance under the payments, when not beside the totals ----
  const yBeforeExtras = y;
  if (d.creditBalance && !creditBeside) {
    y += 1.5 * MM;
    font(3.64, 'bold'); x.fillStyle = BLACK;
    x.fillText(d.creditBalance.label, M, y);
    right(d.creditBalance.amount, cTot, y);
    y += 4.2 * MM;
    if (d.creditBalance.detail) {
      font(2.9); x.fillStyle = GREY;
      // Wrapped between kinds only, never between a kind's name and its amount.
      for (const ln of wrapCreditDetail(d.creditBalance.detail, RIGHT - M, t => x.measureText(t).width)) { x.fillText(ln, M, y); y += 3.4 * MM; }
    }
    font(3.64); x.fillStyle = BLACK;
  }

  // ---- Goods collected and still to collect (399), as on the PDF -----
  font(2.9);
  const goodsLines = copyCollectionDrawn(d, RIGHT - M, t => wrap(t, RIGHT - M), t => x.measureText(t).width);
  if (goodsLines.length) {
    y += 1.5 * MM;
    x.fillStyle = BLACK;
    for (const ln of goodsLines) { x.fillText(ln, M, y); y += 3.4 * MM; }
  }
  font(3.64);

  // ---- Signatures ---------------------------------------------------
  // Without the goods and the credit line the signatures would sit here.
  const bareSigY = Math.max(yBeforeExtras + 4 * MM, H - 56 * MM);
  y = Math.max(y + 4 * MM, H - 56 * MM);
  const extrasH = y - bareSigY;
  const colW = (RIGHT - M - 6 * MM) / 2;
  if (d.staffName) { font(3.9, 'bold italic'); x.fillStyle = BLACK; x.fillText(d.staffName, M, y); }
  x.strokeStyle = '#333333'; x.lineWidth = 0.25 * MM;
  x.beginPath();
  x.moveTo(M, y + 1.6 * MM); x.lineTo(M + colW, y + 1.6 * MM);
  x.moveTo(M + colW + 6 * MM, y + 1.6 * MM); x.lineTo(RIGHT, y + 1.6 * MM);
  x.stroke();
  font(2.86); x.fillStyle = '#333333';
  x.fillText('Staff Signature', M, y + 5 * MM);
  x.fillText('Customer Signature', M + colW + 6 * MM, y + 5 * MM);
  y += 9 * MM;

  // ---- Terms, payment details, footer -------------------------------
  x.strokeStyle = '#c8c8c8'; x.lineWidth = 0.15 * MM;
  x.beginPath(); x.moveTo(M, y); x.lineTo(RIGHT, y); x.stroke();
  y += 3.4 * MM;
  font(2.6, 'bold'); x.fillStyle = BLACK;
  const termsLines = wrap(copyTerms(d).toUpperCase(), RIGHT - M);
  for (const ln of termsLines) { x.fillText(ln, M, y); y += 3.2 * MM; }
  // Goods put in the terms can make them a line longer.
  const termsExtraH = (termsLines.length - wrap(copyTerms({ ...d, collection: null }).toUpperCase(), RIGHT - M).length) * 3.2 * MM;

  if (d.policyText) {
    y += 1.2 * MM;
    font(2.47, 'bold'); x.fillStyle = BLACK;
    x.fillText('CANCELLATION / EXCHANGE / REFUND POLICY', M, y); y += 2.4 * MM;
    font(2.47); x.fillStyle = '#333333';
    for (const ln of wrap(d.policyText, RIGHT - M)) { x.fillText(ln, M, y); y += 2.9 * MM; }
  }

  if (d.payDetails?.length) {
    y += 1.4 * MM;
    font(2.73, 'bold'); x.fillStyle = BLACK; x.fillText('How to pay', M, y);
    font(2.73); x.fillStyle = '#333333';
    let px = M + 15 * MM;
    for (const p of d.payDetails) {
      const w = x.measureText(p).width;
      if (px + w > RIGHT) { y += 2.8 * MM; px = M; }
      x.fillText(p, px, y); px += w + 5 * MM;
    }
    y += 3 * MM;
  }

  if (d.footerBits?.length) {
    x.strokeStyle = '#c8c8c8'; x.beginPath(); x.moveTo(M, y); x.lineTo(RIGHT, y); x.stroke();
    y += 2.8 * MM;
    font(2.47); x.fillStyle = GREY; x.textAlign = 'center';
    for (const ln of wrap(d.footerBits.join('  |  '), RIGHT - M)) { x.fillText(ln, W / 2, y); y += 3 * MM; }
    x.textAlign = 'left';
  }

  return { out: c, endY: y, creditBeside, rowsCut, bareEndY: y - extrasH - termsExtraH };
}
