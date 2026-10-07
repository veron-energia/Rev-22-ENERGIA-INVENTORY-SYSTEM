import { jsPDF } from 'jspdf';
import { wrapCreditDetail } from './invoices/creditBalanceLine.mjs';
import { collectionText, collectionLineFitted, collectionSummary, type CopyCollection } from './invoices/handover.mjs';

/**
 * Builds the CUSTOMER COPY as a real A5 PDF.
 *
 * Drawn with jsPDF's text and line primitives rather than by rasterising the
 * printed HTML, so the text stays selectable and crisp and the file is a few
 * tens of kilobytes instead of a multi-megabyte image — which matters when it
 * is being sent over WhatsApp.
 *
 * The layout deliberately mirrors the printed customer copy: same header,
 * same columns, same totals, same payment details.
 */

export interface PdfLine {
  name: string;
  qty: number | string;
  unit: number;
  total: number;
  /** Small grey notes under the line, e.g. FOC or a discount. */
  notes?: string[];
}

export interface PdfDoc {
  /** Cancellation / exchange / refund wording, set per store. */
  policyText?: string | null;
  kindLabel: string;           // "Tax Invoice", "Special Product Sale", …
  docNo: string;
  date: string;
  /** Separately labelled reference for unresolved invoice dates. */
  status?: string;
  storeName?: string | null;
  storeAddress?: string | null;
  storePhone?: string | null;
  customerName: string;
  customerContact?: string | null;
  lines: PdfLine[];
  totals: [string, string][];  // label, formatted value
  grandTotal?: [string, string];
  payments?: [string, string][];
  /** The customer's credit balance as printed, read fresh for this copy —
   *  see src/lib/invoices/creditBalanceLine.mjs. Absent when it does not apply. */
  creditBalance?: { label: string; amount: string; detail?: string | null } | null;
  payDetails?: string[];
  staffName?: string | null;
  termsText?: string;
  /** An unpaid or part-paid invoice's goods (399), Collected and To
   *  collect, drawn under the payments in the blank space above the
   *  signatures (src/lib/invoices/handover.mjs, copyCollection). Absent once
   *  paid in full. They give way when there is no room: fitAroundCollection. */
  collection?: CopyCollection | null;
  /** How the goods are drawn; set by fitAroundCollection, never by the page:
   *  'full' (the default) both lists, wrapped; 'short' one line each, ending
   *  "+N more"; 'terms' no lists, a few words added to the terms line. */
  collectionFit?: CollectionFit;
  footerBits?: string[];
}

const A5_W = 148.5;
const A5_H = 210;
const M = 10;                    // page margin
const RIGHT = A5_W - M;

/**
 * How far down the copy may run and still count as on the page: the drawing
 * ends 3 mm under the last footer line, so this keeps that line's baseline
 * 8 mm above the edge.
 */
const FOOT_LIMIT = A5_H - M / 2;

/** How a copy's goods are drawn: see PdfDoc.collectionFit. */
export type CollectionFit = 'full' | 'short' | 'terms';

const STANDARD_TERMS = 'Goods and services sold are neither refundable nor exchangeable. Goods and services have been checked and collected.';

/** The terms line of a copy (before it is upper-cased): the page's, or the
 *  standard one, with the goods in a few words when they are drawn there. */
export function copyTerms(d: PdfDoc): string {
  const base = d.termsText ?? STANDARD_TERMS;
  return d.collection && d.collectionFit === 'terms' ? `${base} ${collectionSummary(d.collection)}` : base;
}

/** The goods lines of a copy (none when they are in the terms): `wrap` wraps
 *  a line to the width, `measure` measures one, both in the goods' face. */
export function copyCollectionDrawn(d: PdfDoc, width: number, wrap: (t: string) => string[],
                                    measure: (t: string) => number): string[] {
  if (!d.collection || d.collectionFit === 'terms') return [];
  if (d.collectionFit === 'short') {
    return [collectionLineFitted('Collected', d.collection.collected, width, measure),
            collectionLineFitted('To collect', d.collection.toCollect, width, measure)];
  }
  return collectionText(d.collection).flatMap(wrap);
}

/**
 * The goods (399) give way when the copy runs long, before the credit balance
 * and before any item row. Drawn with both lists in full when that keeps the
 * copy on the page. If not, they may still take the room the copy would use
 * anyway with the goods in the terms (whose two lines are no longer than the
 * standard "... checked and collected" terms they replace, so that is no lower
 * than the copy ended before 399); then one line each ("+N more"); and if even
 * that runs past it, a few words in the terms ("Goods: 2 collected, 3 to
 * collect."). So the goods never push the footer (store contact, company
 * registration) lower than the copy without them or the on-page limit,
 * whichever is lower down. At most three drawings; each one thrown away is
 * handed to `discard`. Shared by the PDF and the image.
 */
export function fitAroundCollection<T>(
  d: PdfDoc, draw: (d: PdfDoc) => CopyDrawing<T>, footLimit: number,
  discard: (out: T) => void = () => {},
): CopyDrawing<T> {
  const full = draw({ ...d, collectionFit: 'full' });
  if (!d.collection || full.endY <= footLimit + 0.01) return full;
  const terms = draw({ ...d, collectionFit: 'terms' });
  const limit = Math.max(terms.endY, footLimit);
  if (full.endY <= limit + 0.01) { discard(terms.out); return full; }
  discard(full.out);
  const short = draw({ ...d, collectionFit: 'short' });
  if (short.endY <= limit + 0.01) { discard(terms.out); return short; }
  discard(short.out);
  return terms;
}

/** One drawing of a copy: what was drawn, how far down the page it ran, and
 *  whether the credit balance went beside the totals, where it costs no height. */
export interface CopyDrawing<T> { out: T; endY: number; creditBeside?: boolean }

/** How the credit balance came out on a copy: in full, the total alone, or left off for space. */
export type CreditBalanceShown = 'full' | 'total' | 'none';
const creditShown = new WeakMap<object, CreditBalanceShown>();

/**
 * How the credit balance came out the last time this copy was drawn (PDF or
 * image), so the page can say when it was left off for want of room. Null when
 * the copy had no line to draw, or has not been drawn.
 */
export function creditBalanceShown(d: PdfDoc): CreditBalanceShown | null {
  return creditShown.get(d) ?? null;
}

/**
 * The credit balance line gives way; apart from an unpaid or part-paid
 * invoice's goods, which shorten first (fitAroundCollection, inside `draw`),
 * nothing else on the copy does.
 *
 * Each drawing puts it in the empty left column beside the right-aligned
 * totals when it fits there: that costs no height at all, so the copy is drawn
 * once. Only when it does not fit there does it go under the payments, in the
 * blank space above the signatures — and there it never costs an item row and
 * never pushes the footer (store contact, company registration) lower than
 * `limit`: where the footer ends without the line, or the on-page limit if that
 * is lower down.
 *
 * Drawn with the full line first. If that ends past the limit, the breakdown
 * of kinds is left off and only the total is drawn (beside the totals if it
 * fits there now); if even that does not fit, the copy goes without the line.
 * At most three drawings; each one thrown away is handed to `discard` (the
 * image releases its canvas). How it came out is kept: creditBalanceShown.
 *
 * Shared by the PDF and the image, which each say how they draw a copy.
 */
export function fitAroundCreditBalance<T>(
  d: PdfDoc, draw: (d: PdfDoc) => CopyDrawing<T>, footLimit: number,
  discard: (out: T) => void = () => {},
): T {
  const full = draw(d);
  if (!d.creditBalance) return full.out;
  const shown = (s: CreditBalanceShown, out: T) => { creditShown.set(d, s); return out; };
  const whole: CreditBalanceShown = d.creditBalance.detail ? 'full' : 'total';
  if (full.creditBeside || full.endY <= footLimit + 0.01) return shown(whole, full.out);
  const bare = draw({ ...d, creditBalance: null });
  const limit = Math.max(bare.endY, footLimit);
  if (full.endY <= limit + 0.01) { discard(bare.out); return shown(whole, full.out); }
  discard(full.out);
  if (d.creditBalance.detail) {
    const totalOnly = draw({ ...d, creditBalance: { ...d.creditBalance, detail: null } });
    if (totalOnly.endY <= limit + 0.01) { discard(bare.out); return shown('total', totalOnly.out); }
    discard(totalOnly.out);
  }
  return shown('none', bare.out);
}

/**
 * The credit balance's place beside the totals: the left column from the
 * margin to just short of the totals block (its widest label, or the rule over
 * the grand total). `top` is the first totals row's baseline and `bottom` the
 * last baseline the totals draw; the line goes there only if all of it fits
 * between the two, so it moves nothing else on the copy.
 *
 * `labelW`/`amountW` are the label's and total's widths in the bold face, and
 * `detailLines` the breakdown wrapped to `width`, measured in the small face.
 * Returns the baselines to draw at, or null when it does not fit.
 */
export function creditBesideTotals(p: {
  top: number; bottom: number; width: number; labelW: number; amountW: number;
  detailLines: { width: number }[]; lineH: number; detailH: number; gap: number;
}): { labelY: number; amountY: number; amountOnLabelLine: boolean; detailY: number[] } | null {
  if (p.width <= 0 || p.labelW > p.width || p.amountW > p.width) return null;
  if (p.detailLines.some(l => l.width > p.width + 0.01)) return null;
  const amountOnLabelLine = p.labelW + p.gap + p.amountW <= p.width;
  const labelY = p.top;
  const amountY = amountOnLabelLine ? labelY : labelY + p.lineH;
  const detailY = p.detailLines.map((_, i) => amountY + p.lineH + i * p.detailH);
  const last = detailY.length ? detailY[detailY.length - 1] : amountY;
  if (last > p.bottom + 0.01) return null;
  return { labelY, amountY, amountOnLabelLine, detailY };
}

export function buildDocumentPdf(d: PdfDoc): jsPDF {
  // The goods give way first (fitAroundCollection), then the credit balance.
  return fitAroundCreditBalance(d, dd => fitAroundCollection(dd, drawDocumentPdf, FOOT_LIMIT), FOOT_LIMIT);
}

/** One drawing of the copy, and how far down the page it ran. */
function drawDocumentPdf(d: PdfDoc): CopyDrawing<jsPDF> {
  const doc = new jsPDF({ unit: 'mm', format: [A5_W, A5_H], orientation: 'portrait' });
  let y = M;

  const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
  const grey = () => doc.setTextColor(110, 110, 110);
  const black = () => doc.setTextColor(17, 17, 17);

  // ---- Header -------------------------------------------------------
  doc.setFont('helvetica', 'bold'); doc.setFontSize(18); black();
  doc.text('Energia', M, y + 4);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); grey();
  doc.text('Wellness & Retail', M, y + 8);

  doc.setFont('helvetica', 'bold'); doc.setFontSize(14); black();
  doc.text(d.docNo, RIGHT, y + 4, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); grey();
  let hy = y + 8;
  for (const t of [d.kindLabel, d.storeName, d.storeAddress, d.storePhone ? `Tel: ${d.storePhone}` : '',
                   `Date: ${d.date}`, d.status ? `Status: ${d.status}` : '']) {
    if (!t) continue;
    // Long addresses wrap rather than running off the page.
    for (const ln of doc.splitTextToSize(String(t), 80)) {
      doc.text(ln, RIGHT, hy, { align: 'right' }); hy += 3.9;
    }
  }

  y = Math.max(y + 14, hy) + 1;
  black(); doc.setDrawColor(17, 17, 17); doc.setLineWidth(0.4);
  doc.line(M, y, RIGHT, y);
  y += 5;

  // ---- Customer -----------------------------------------------------
  doc.setFont('helvetica', 'bold'); doc.setFontSize(9); grey();
  doc.text('BILL TO', M, y); y += 4;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(11.5); black();
  doc.text(d.customerName, M, y); y += 3.6;
  if (d.customerContact) {
    doc.setFontSize(9); grey(); doc.text(d.customerContact, M, y); y += 3.6;
  }
  y += 2;

  // ---- Items --------------------------------------------------------
  const cQty = RIGHT - 46, cUnit = RIGHT - 24, cTot = RIGHT;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(9); grey();
  doc.text('ITEM', M, y);
  doc.text('QTY', cQty, y, { align: 'right' });
  doc.text('UNIT', cUnit, y, { align: 'right' });
  doc.text('TOTAL', cTot, y, { align: 'right' });
  y += 1.5;
  doc.setDrawColor(150, 150, 150); doc.setLineWidth(0.2);
  doc.line(M, y, RIGHT, y);
  y += 3.6;

  black(); doc.setFont('helvetica', 'normal'); doc.setFontSize(10);
  for (const l of d.lines) {
    const nameLines = doc.splitTextToSize(l.name, cQty - M - 3);
    const rowH = nameLines.length * 4.2 + (l.notes?.length ?? 0) * 3 + 1.6;

    // Keep the signature block on the page: stop listing and summarise.
    if (y + rowH > A5_H - 70) {
      grey(); doc.setFontSize(9);
      doc.text('…continued — see the full invoice in store', M, y);
      y += 4; black(); doc.setFontSize(10);
      break;
    }

    doc.text(nameLines, M, y);
    doc.text(String(l.qty), cQty, y, { align: 'right' });
    doc.text(money(l.unit), cUnit, y, { align: 'right' });
    doc.setFont('helvetica', 'bold');
    doc.text(money(l.total), cTot, y, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    let ny = y + nameLines.length * 4.2;
    for (const n of l.notes ?? []) {
      grey(); doc.setFontSize(8);
      doc.text(n, M + 2, ny); ny += 3.4;
      black(); doc.setFontSize(10);
    }
    // Separator sits below the row just drawn; the next baseline then starts
    // clear of it, otherwise the line strikes through the following text.
    const sepY = ny - 1.2;
    doc.setDrawColor(230, 230, 230); doc.setLineWidth(0.15);
    doc.line(M, sepY, RIGHT, sepY);
    y = sepY + 5.4;
  }

  // ---- Totals -------------------------------------------------------
  y += 2;
  doc.setFontSize(10);
  const totalsTop = y;
  let totalsBottom = -Infinity;
  const totalsLabelW = Math.max(0, ...d.totals.map(([label]) => doc.getTextWidth(label)));
  for (const [label, value] of d.totals) {
    grey(); doc.text(label, cUnit, y, { align: 'right' });
    black(); doc.text(value, cTot, y, { align: 'right' });
    totalsBottom = y;
    y += 4.8;
  }
  if (d.grandTotal) {
    doc.setDrawColor(150, 150, 150); doc.setLineWidth(0.3);
    doc.line(cUnit - 22, y - 2.6, RIGHT, y - 2.6);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(13); black();
    doc.text(d.grandTotal[0], cUnit, y + 1.4, { align: 'right' });
    doc.text(d.grandTotal[1], cTot, y + 1.4, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    totalsBottom = y + 1.4;
    y += 6;
  }

  // ---- Credit balance beside the totals, where it costs no height -----
  let creditBeside = false;
  if (d.creditBalance) {
    const width = Math.min(cUnit - 22, cUnit - totalsLabelW) - 4 - M;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(10);
    const labelW = doc.getTextWidth(d.creditBalance.label), amountW = doc.getTextWidth(d.creditBalance.amount);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5);
    const detail = d.creditBalance.detail ? wrapCreditDetail(d.creditBalance.detail, width, t => doc.getTextWidth(t)) : [];
    const at = creditBesideTotals({ top: totalsTop, bottom: totalsBottom, width, labelW, amountW,
      detailLines: detail.map(t => ({ width: doc.getTextWidth(t) })), lineH: 4.2, detailH: 3.4, gap: 3 });
    if (at) {
      creditBeside = true;
      doc.setFont('helvetica', 'bold'); doc.setFontSize(10); black();
      doc.text(d.creditBalance.label, M, at.labelY);
      if (at.amountOnLabelLine) doc.text(d.creditBalance.amount, M + width, at.amountY, { align: 'right' });
      else doc.text(d.creditBalance.amount, M, at.amountY);
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); grey();
      detail.forEach((ln, i) => doc.text(ln, M, at.detailY[i]));
    }
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10); black();
  }

  // ---- Payments -----------------------------------------------------
  if (d.payments?.length) {
    y += 2;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); grey();
    doc.text('PAYMENT METHODS', M, y); y += 4;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10); black();
    for (const [k, v] of d.payments) {
      doc.text(k, M, y); doc.text(v, cTot, y, { align: 'right' }); y += 4.6;
    }
  }

  // ---- Credit balance under the payments, when not beside the totals ----
  if (d.creditBalance && !creditBeside) {
    y += 1.5;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(10); black();
    doc.text(d.creditBalance.label, M, y);
    doc.text(d.creditBalance.amount, cTot, y, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    y += 4.2;
    if (d.creditBalance.detail) {
      doc.setFontSize(8.5); grey();
      // Wrapped between kinds only, never between a kind's name and its amount.
      for (const ln of wrapCreditDetail(d.creditBalance.detail, RIGHT - M, t => doc.getTextWidth(t))) { doc.text(ln, M, y); y += 3.4; }
      doc.setFontSize(10); black();
    }
  }

  // ---- Goods collected and still to collect (399) -------------------
  // In the blank space above the signatures, which are pinned near the foot,
  // so on all but a long invoice it moves nothing below it; on a long one
  // they shorten or go into the terms (fitAroundCollection).
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5);
  const goodsLines = copyCollectionDrawn(d, RIGHT - M, t => doc.splitTextToSize(t, RIGHT - M) as string[],
                                         t => doc.getTextWidth(t));
  if (goodsLines.length) {
    y += 1.5;
    black();
    for (const ln of goodsLines) { doc.text(ln, M, y); y += 3.4; }
  }
  doc.setFontSize(10);

  // ---- Signatures, pinned near the foot -----------------------------
  const sigY = A5_H - 56;
  y = Math.max(y + 4, sigY);
  const colW = (RIGHT - M - 6) / 2;
  doc.setFontSize(11); black(); doc.setFont('helvetica', 'bolditalic');
  if (d.staffName) doc.text(d.staffName, M, y);
  doc.setFont('helvetica', 'normal');
  doc.setDrawColor(51, 51, 51); doc.setLineWidth(0.25);
  doc.line(M, y + 1.6, M + colW, y + 1.6);
  doc.line(M + colW + 6, y + 1.6, RIGHT, y + 1.6);
  doc.setFontSize(8.5); doc.setTextColor(51, 51, 51);
  doc.text('Staff Signature', M, y + 5);
  doc.text('Customer Signature', M + colW + 6, y + 5);
  y += 9;

  // ---- Terms, payment details, footer -------------------------------
  doc.setDrawColor(200, 200, 200); doc.setLineWidth(0.15);
  doc.line(M, y, RIGHT, y); y += 3.4;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(8); doc.setTextColor(17, 17, 17);
  for (const ln of doc.splitTextToSize(copyTerms(d).toUpperCase(), RIGHT - M)) { doc.text(ln, M, y); y += 3.2; }
  doc.setFont('helvetica', 'normal');

  if (d.policyText) {
    y += 1.2;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(7.5); doc.setTextColor(17, 17, 17);
    doc.text('CANCELLATION / EXCHANGE / REFUND POLICY', M, y); y += 2.4;
    doc.setFont('helvetica', 'normal'); doc.setTextColor(51, 51, 51);
    for (const ln of doc.splitTextToSize(d.policyText, RIGHT - M)) { doc.text(ln, M, y); y += 2.9; }
  }

  if (d.payDetails?.length) {
    y += 1.4;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(8); black();
    doc.text('How to pay', M, y);
    doc.setFont('helvetica', 'normal'); doc.setTextColor(51, 51, 51);
    let px = M + 15;
    for (const p of d.payDetails) {
      const w = doc.getTextWidth(p);
      if (px + w > RIGHT) { y += 2.8; px = M; }
      doc.text(p, px, y); px += w + 5;
    }
    y += 3;
  }

  if (d.footerBits?.length) {
    doc.setDrawColor(200, 200, 200); doc.line(M, y, RIGHT, y); y += 2.8;
    doc.setFontSize(7.5); grey();
    for (const ln of doc.splitTextToSize(d.footerBits.join('  |  '), RIGHT - M)) {
      doc.text(ln, A5_W / 2, y, { align: 'center' }); y += 3;
    }
  }

  return { out: doc, endY: y, creditBeside };
}

/** The finished PDF as a Blob, ready to upload or download. */
export function documentPdfBlob(d: PdfDoc): Blob {
  return buildDocumentPdf(d).output('blob');
}

/** Save the PDF straight to the staff member's device. */
export function downloadDocumentPdf(d: PdfDoc, filename: string): void {
  buildDocumentPdf(d).save(filename);
}
