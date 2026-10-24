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
   *  see src/lib/invoices/creditBalanceLine.mjs: the total, and under it where
   *  the credit came from (443). Absent when it does not apply. */
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
  /** A line under the header, e.g. "Exchange invoice: replaces items from
   *  INV-…" (B16, AFTER-9). */
  headerNote?: string | null;
  /** 456 (item 6, the exchange half): an exchange invoice's own exchange note
   *  (product_exchanges.notes), drawn under "EXCHANGE DETAILS" below the
   *  header note, its line breaks kept. */
  exchangeNote?: string | null;
  /** 456 (the Owner, 22 Oct 2026): the note printed on the invoice (never its
   *  internal Notes), drawn under "NOTE" above the signatures, wrapped, its
   *  line breaks kept. It never gives way: on the PDF the lines that do not
   *  fit above the signatures go on to the next page, with the signatures and
   *  the rest of the foot after them; the image grows taller. Nothing above
   *  it gives way for it either, on the PDF or the image: the goods, the
   *  credit line and the payments are fitted as on the same copy without a
   *  note. */
  note?: string | null;
  /** The payments' total as printed, for the one-row summary. Worked out from
   *  `payments` when absent. */
  paymentsTotal?: string | null;
  /** Set by fitAroundPayments, never by the page (B16, AFTER-8): 'list' (the
   *  default) every payment; 'summary' one row with the count and total. */
  paymentsFit?: 'list' | 'summary';
  /** Set by fitAroundPayments, never by the page: the copy takes more pages
   *  (the PDF), or the image grows taller. Item 5 (the Owner, 22 Oct 2026):
   *  the item rows go on to as many pages as they need, every one listed; the
   *  payments, the signatures, the terms, the policy, how to pay and the
   *  footer follow the totals, or go on a page of their own when the rows
   *  all fit page 1 (B16). */
  pageBreak?: boolean;
  /** Set by fitAroundPayments, never by the page: on a copy of more pages,
   *  the payments onward go on a page of their own after the totals even
   *  when the rows went on to more pages, as they do not fit under them. */
  tailPage?: boolean;
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

/** A note's heading and each of its lines (456), in mm: 8.5 pt text, as the goods (399). */
const NOTE_HEAD = 3.6;
const NOTE_LINE = 3.4;

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

/** One drawing of a copy: what was drawn, how far down the page it ran,
 *  whether the credit balance went beside the totals, where it costs no height,
 *  and whether some item rows were left off ("…continued") for want of room. */
export interface CopyDrawing<T> { out: T; endY: number; creditBeside?: boolean; rowsCut?: boolean }

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
 * (where the credit came from: Credit Package, Premium Bundle, Other; 443) is
 * left off and only the total is drawn (beside the totals if it
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
  return fitCreditBalanceDrawing(d, draw, footLimit, discard).out;
}

/** fitAroundCreditBalance, keeping how far down the chosen drawing ran. */
export function fitCreditBalanceDrawing<T>(
  d: PdfDoc, draw: (d: PdfDoc) => CopyDrawing<T>, footLimit: number,
  discard: (out: T) => void = () => {},
): CopyDrawing<T> {
  const full = draw(d);
  if (!d.creditBalance) return full;
  const shown = (s: CreditBalanceShown, out: CopyDrawing<T>) => { creditShown.set(d, s); return out; };
  const whole: CreditBalanceShown = d.creditBalance.detail ? 'full' : 'total';
  if (full.creditBeside || full.endY <= footLimit + 0.01) return shown(whole, full);
  const bare = draw({ ...d, creditBalance: null });
  const limit = Math.max(bare.endY, footLimit);
  if (full.endY <= limit + 0.01) { discard(bare.out); return shown(whole, full); }
  discard(full.out);
  if (d.creditBalance.detail) {
    const totalOnly = draw({ ...d, creditBalance: { ...d.creditBalance, detail: null } });
    if (totalOnly.endY <= limit + 0.01) { discard(bare.out); return shown('total', totalOnly); }
    discard(totalOnly.out);
  }
  return shown('none', bare);
}

/**
 * A note's lines as a copy draws them (456): each line of it wrapped to the
 * width by `wrap`, a blank line kept as a blank line. Shared by the PDF and
 * the image.
 */
export function copyNoteLines(note: string, wrap: (t: string) => string[]): string[] {
  return String(note).replace(/\r\n?/g, '\n').split('\n')
    .flatMap(p => p.trim() === '' ? [''] : wrap(p.replace(/\s+$/, '')));
}

/** The payment rows a copy draws: every payment, or (paymentsFit 'summary')
 *  one row with how many there were and their total (B16, AFTER-8). */
export function copyPaymentRows(d: PdfDoc): [string, string][] {
  const list = d.payments ?? [];
  if (d.paymentsFit !== 'summary' || list.length < 2) return list;
  const total = d.paymentsTotal
    ?? `S$${(list.reduce((s, [, v]) => s + Math.round((Number(String(v).replace(/[^0-9.-]/g, '')) || 0) * 100), 0) / 100).toFixed(2)}`;
  return [[`Payments: ${list.length}; full list on the store copy`, total]];
}

/**
 * The last resort when a copy still runs off the page after the goods and the
 * credit balance have given way (B16, AFTER-8): the payment list shortens to
 * one row ("Payments: 4; full list on the store copy" and their total). If
 * even that runs off, the copy takes more pages (the PDF): the payments,
 * signatures, terms, policy, how to pay and the footer go on a page of their
 * own, with the full payment list, and it shortens there too only if that
 * page would overflow. The image grows taller instead (`grows`), so it never
 * needs the last steps. On a new page the goods and the credit balance have
 * room again and are fitted anew.
 * Whatever is drawn, the store contact and company registration are on the
 * copy. Each drawing thrown away is handed to `discard`, and how the credit
 * balance came out is kept for the copy the page made (creditBalanceShown).
 *
 * A drawing that left item rows off does not fit either, even when its footer
 * is on the page: a long invoice (promotions list what is inside them) takes
 * more pages, where its rows carry on, rather than lose a row (B16, AFTER-9).
 * Item 5 (the Owner, 22 Oct 2026): the rows go on to as many pages as they
 * need, every one listed (no more "see the full invoice in store"). When the
 * payments onward do not fit under the totals on the last of them, the
 * payments shorten there to one row; then they go on a page of their own,
 * listed, and shorten there only if that page would overflow. If nothing
 * fits, the drawing that runs least far down is kept.
 */
export function fitAroundPayments<T>(
  d: PdfDoc, drawFitted: (d: PdfDoc) => CopyDrawing<T>, footLimit: number,
  discard: (out: T) => void = () => {}, grows = false,
): T {
  const fits = (r: CopyDrawing<T>) => r.endY <= footLimit + 0.01 && !r.rowsCut;
  const take = (variant: PdfDoc, r: CopyDrawing<T>) => {
    if (variant !== d) {
      const s = creditShown.get(variant);
      if (s) creditShown.set(d, s); else creditShown.delete(d);
    }
    return r.out;
  };
  const first = drawFitted(d);
  if (fits(first)) return first.out;
  const many = (d.payments?.length ?? 0) > 1;
  // The rows come before the payments: a shorter payment list cannot bring
  // back a row the first drawing left off, so it is not tried then.
  if (many && !first.rowsCut) {
    const shortList = { ...d, paymentsFit: 'summary' as const };
    const summary = drawFitted(shortList);
    if (fits(summary)) { discard(first.out); return take(shortList, summary); }
    discard(summary.out);
  }
  discard(first.out);
  const brokenDoc: PdfDoc = { ...d, pageBreak: true };
  const broken = drawFitted(brokenDoc);
  if (fits(broken) || grows) return take(brokenDoc, broken);
  // The payments shortened under the totals; then on a page of their own,
  // listed; then shortened there.
  const tries: PdfDoc[] = [
    ...(many ? [{ ...brokenDoc, paymentsFit: 'summary' as const }] : []),
    { ...brokenDoc, tailPage: true },
    ...(many ? [{ ...brokenDoc, tailPage: true, paymentsFit: 'summary' as const }] : []),
  ];
  let best = { doc: brokenDoc, r: broken };
  for (const variant of tries) {
    const r = drawFitted(variant);
    if (fits(r)) { discard(best.r.out); return take(variant, r); }
    if (r.endY < best.r.endY - 0.01) { discard(best.r.out); best = { doc: variant, r }; } else discard(r.out);
  }
  return take(best.doc, best.r);
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
  // The goods give way first (fitAroundCollection), then the credit balance;
  // if the copy still runs off the page, the payments shorten, then more
  // pages are taken (fitAroundPayments).
  return fitAroundPayments(d, dd => fitCreditBalanceDrawing(dd,
    ddd => fitAroundCollection(ddd, drawDocumentPdf, FOOT_LIMIT), FOOT_LIMIT), FOOT_LIMIT);
}

/**
 * One drawing of the copy, and how far down the page it ran.
 *
 * On a copy of more pages (pageBreak) the item rows carry on to as many pages
 * as they need (item 5, the Owner, 22 Oct 2026), and once it is drawn every
 * page says which it is of how many.
 */
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

  // ---- A note under the header (an exchange invoice, AFTER-9) --------
  if (d.headerNote) {
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); black();
    for (const ln of doc.splitTextToSize(d.headerNote, RIGHT - M)) { doc.text(ln, M, y); y += 3.9; }
    doc.setFont('helvetica', 'normal');
    y += 1.5;
  }

  /** The pages after the first, each headed "(continued)"; each says which
   *  page of how many it is once the copy is drawn (the end of this). */
  const continuedPages: number[] = [];
  /** Where page 1 says it goes on: it says there which page it is (item 5). */
  let firstPageFootY: number | null = null;
  /** The rest of the copy goes on to a new page (B16; a long note, 456; item
   *  rows, item 5). */
  const nextPage = () => {
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); grey();
    if (doc.getNumberOfPages() === 1) firstPageFootY = y + 3;
    doc.text(`Continued on page ${doc.getNumberOfPages() + 1}`, M, y + 3);
    doc.addPage([A5_W, A5_H], 'portrait');
    continuedPages.push(doc.getNumberOfPages());
    y = M + 2;
    doc.text(`${d.docNo} (continued)`, M, y);
    y += 6;
    doc.setFontSize(10); black();
  };

  /**
   * The foot of the copy from the signatures' line down: the signatures, the
   * terms, the policy, how to pay and the footer. Drawn at `top`; or, with
   * `draw` false, only measured (nothing is written to the page), so a note
   * (456) knows how far down it may run. Returns where it ends.
   */
  const drawFoot = (top: number, draw: boolean): number => {
    let fy = top;
    const put = (t: string, tx: number, ty: number, o?: { align: 'center' }) => { if (draw) doc.text(t, tx, ty, o); };
    const rule = (x1: number, y1: number, x2: number, y2: number) => { if (draw) doc.line(x1, y1, x2, y2); };
    const pen = (g: number, w?: number) => { if (draw) { doc.setDrawColor(g, g, g); if (w !== undefined) doc.setLineWidth(w); } };
    const colW = (RIGHT - M - 6) / 2;
    doc.setFontSize(11); black(); doc.setFont('helvetica', 'bolditalic');
    if (d.staffName) put(d.staffName, M, fy);
    doc.setFont('helvetica', 'normal');
    pen(51, 0.25);
    rule(M, fy + 1.6, M + colW, fy + 1.6);
    rule(M + colW + 6, fy + 1.6, RIGHT, fy + 1.6);
    doc.setFontSize(8.5); doc.setTextColor(51, 51, 51);
    put('Staff Signature', M, fy + 5);
    put('Customer Signature', M + colW + 6, fy + 5);
    fy += 9;

    // ---- Terms, payment details, footer -----------------------------
    pen(200, 0.15);
    rule(M, fy, RIGHT, fy); fy += 3.4;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(8); doc.setTextColor(17, 17, 17);
    for (const ln of doc.splitTextToSize(copyTerms(d).toUpperCase(), RIGHT - M)) { put(ln, M, fy); fy += 3.2; }
    doc.setFont('helvetica', 'normal');

    if (d.policyText) {
      fy += 1.2;
      doc.setFont('helvetica', 'bold'); doc.setFontSize(7.5); doc.setTextColor(17, 17, 17);
      put('CANCELLATION / EXCHANGE / REFUND POLICY', M, fy); fy += 2.4;
      doc.setFont('helvetica', 'normal'); doc.setTextColor(51, 51, 51);
      for (const ln of doc.splitTextToSize(d.policyText, RIGHT - M)) { put(ln, M, fy); fy += 2.9; }
    }

    if (d.payDetails?.length) {
      fy += 1.4;
      doc.setFont('helvetica', 'bold'); doc.setFontSize(8); black();
      put('How to pay', M, fy);
      doc.setFont('helvetica', 'normal'); doc.setTextColor(51, 51, 51);
      let px = M + 15;
      for (const p of d.payDetails) {
        const w = doc.getTextWidth(p);
        if (px + w > RIGHT) { fy += 2.8; px = M; }
        put(p, px, fy); px += w + 5;
      }
      fy += 3;
    }

    if (d.footerBits?.length) {
      pen(200); rule(M, fy, RIGHT, fy); fy += 2.8;
      doc.setFontSize(7.5); grey();
      for (const ln of doc.splitTextToSize(d.footerBits.join('  |  '), RIGHT - M)) {
        put(ln, A5_W / 2, fy, { align: 'center' }); fy += 3;
      }
    }
    return fy;
  };

  // ---- The exchange's own note, under EXCHANGE DETAILS (456) ----------
  // Above the items, which make room for it as for a long header: on a long
  // copy their rows go on to the next page (fitAroundPayments).
  if (d.exchangeNote) {
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); grey();
    doc.text('EXCHANGE DETAILS', M, y); y += 4;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9); black();
    for (const ln of copyNoteLines(`Note: ${d.exchangeNote}`, t => doc.splitTextToSize(t, RIGHT - M) as string[])) {
      if (y + 3.8 > A5_H - 70) { nextPage(); doc.setFont('helvetica', 'normal'); doc.setFontSize(9); black(); }
      doc.text(ln, M, y); y += 3.8;
    }
    y += 1.5;
  }

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
  /** The column heads over the item rows. */
  const itemHeads = () => {
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); grey();
    doc.text('ITEM', M, y);
    doc.text('QTY', cQty, y, { align: 'right' });
    doc.text('UNIT', cUnit, y, { align: 'right' });
    doc.text('TOTAL', cTot, y, { align: 'right' });
    y += 1.5;
    doc.setDrawColor(150, 150, 150); doc.setLineWidth(0.2);
    doc.line(M, y, RIGHT, y);
    y += 3.6;
  };
  // B16 (AFTER-9): a row's height as it is drawn, its notes at 3.4 mm each.
  // Item 5 (the Owner, 22 Oct 2026): a copy of more pages (pageBreak) lists
  // every row, on as many pages as they need, under the column heads again
  // on each. A row goes whole on the page where it starts, down to the room
  // "Continued on page k+1" needs; the last row only down to the room the
  // totals and the signatures need, so the totals never stand alone on a
  // page. Else it starts the next page, whole; only a row taller than a page
  // goes on between its notes. A copy of one page lists them down to that
  // room and says it stopped (rowsCut), so fitAroundPayments takes more pages.
  const ROW_LIMIT = A5_H - 70;
  const PAGE_LIMIT = A5_H - M - 4;
  /** Where the rows start on a page after the first: under its "(continued)"
   *  line and the column heads (nextPage, itemHeads). */
  const ROWS_TOP = M + 2 + 6 + 1.5 + 3.6;
  let brokeInItems = false, rowsCut = false, rowsOnPage = 0;
  const rowFont = () => { black(); doc.setFont('helvetica', 'normal'); doc.setFontSize(10); };
  const rowHeight = (l: PdfLine) => {
    rowFont();
    return doc.splitTextToSize(l.name, cQty - M - 3).length * 4.2 + (l.notes?.length ?? 0) * 3.4 + 1.6;
  };
  const rowsGoOn = () => { nextPage(); itemHeads(); brokeInItems = true; rowsOnPage = 0; rowFont(); };
  // The first row too: when it does not fit under the header but fits a page
  // of its own, it starts page 2, whole, with the column heads (page 1 then
  // ends at Bill To), rather than go on between its notes.
  if (d.pageBreak && d.lines.length) {
    const first = rowHeight(d.lines[0]), firstLimit = d.lines.length > 1 ? PAGE_LIMIT : ROW_LIMIT;
    if (y + 1.5 + 3.6 + first > firstLimit && ROWS_TOP + first <= firstLimit) { nextPage(); brokeInItems = true; }
  }
  itemHeads();
  rowFont();
  for (let li = 0; li < d.lines.length; li++) {
    const l = d.lines[li], lastRow = li === d.lines.length - 1;
    const nameLines = doc.splitTextToSize(l.name, cQty - M - 3);
    const notes = l.notes ?? [];
    const rowH = nameLines.length * 4.2 + notes.length * 3.4 + 1.6;
    const limit = d.pageBreak && !lastRow ? PAGE_LIMIT : ROW_LIMIT;

    if (y + rowH > limit) {
      // One page: keep the signature block on it, and say the rows stop.
      if (!d.pageBreak) {
        grey(); doc.setFontSize(9);
        doc.text('…continued — see the full invoice in store', M, y);
        y += 4; black(); doc.setFontSize(10);
        rowsCut = true;
        break;
      }
      if (rowsOnPage > 0) rowsGoOn();
    }
    // Still too tall for the page it starts on: its notes go on to more pages.
    const tall = d.pageBreak && y + rowH > limit;

    doc.text(nameLines, M, y);
    doc.text(String(l.qty), cQty, y, { align: 'right' });
    doc.text(money(l.unit), cUnit, y, { align: 'right' });
    doc.setFont('helvetica', 'bold');
    doc.text(money(l.total), cTot, y, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    let ny = y + nameLines.length * 4.2;
    for (let k = 0; k < notes.length; k++) {
      if (tall) {
        // What is left of the row from this note on, as rowH counts it.
        const rest = (notes.length - k) * 3.4 + 1.6;
        if (ny + 3.4 + 1.6 > PAGE_LIMIT || (lastRow && ny + rest > ROW_LIMIT && ROWS_TOP + rest <= ROW_LIMIT)) {
          y = ny - 3.4;
          rowsGoOn();
          ny = y;
        }
      }
      grey(); doc.setFontSize(8);
      doc.text(notes[k], M + 2, ny); ny += 3.4;
      black(); doc.setFontSize(10);
    }
    // Separator sits below the row just drawn; the next baseline then starts
    // clear of it, otherwise the line strikes through the following text.
    const sepY = ny - 1.2;
    doc.setDrawColor(230, 230, 230); doc.setLineWidth(0.15);
    doc.line(M, sepY, RIGHT, sepY);
    y = sepY + 5.4;
    rowsOnPage++;
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

  // ---- A page of their own for the payments onward (fitAroundPayments) --
  // Taken here when the copy runs long and its rows all fit page 1; when the
  // rows went on to more pages, only if the rest does not fit under the
  // totals on the last of them (tailPage).
  if (d.pageBreak && (!brokeInItems || d.tailPage)) nextPage();

  // ---- Payments -----------------------------------------------------
  const paymentRows = copyPaymentRows(d);
  if (paymentRows.length) {
    y += 2;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); grey();
    doc.text('PAYMENT METHODS', M, y); y += 4;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10); black();
    for (const [k, v] of paymentRows) {
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
      // Wrapped between parts only ('Credit Package S$… · Premium Bundle S$… ·
      // Other S$…', 443), never between a part's name and its amount.
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

  // ---- The note printed on the invoice (456), above the signatures ---
  // It never gives way, and never pushes the footer off the page: it may take
  // the room above the signatures (pinned near the foot) and the blank space
  // under the footer, moving the signatures down into it; the lines that do
  // not fit go on to the next page, and the signatures, terms and footer
  // follow the last line there. Nothing above it gives way for it, and what
  // is above it never runs off a page: this drawing reports where the copy
  // would end without the note (endY, below), so the goods, the credit line
  // and the payments shorten, or the payments go on to a second page, exactly
  // as on the same copy without a note (fitAroundCollection,
  // fitCreditBalanceDrawing, fitAroundPayments). Once what is above the note
  // fits, the note's own lines always end on a page.
  const yAboveNote = y;
  const footH = d.note ? drawFoot(0, false) : 0;
  if (d.note) {
    const noteFloor = Math.max(A5_H - 56, FOOT_LIMIT - footH) - 4;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5);
    const noteLines = copyNoteLines(d.note, t => doc.splitTextToSize(t, RIGHT - M) as string[]);
    y += 1.5;
    // The heading never stands alone at the foot of a page.
    if (y + NOTE_HEAD + NOTE_LINE > noteFloor) nextPage();
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); grey();
    doc.text('NOTE', M, y); y += NOTE_HEAD;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); black();
    for (const ln of noteLines) {
      if (y + NOTE_LINE > noteFloor) { nextPage(); doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); black(); }
      doc.text(ln, M, y); y += NOTE_LINE;
    }
    doc.setFontSize(10);
  }

  // ---- Signatures, pinned near the foot -----------------------------
  const sigY = A5_H - 56;
  y = Math.max(y + 4, sigY);
  y = drawFoot(y, true);

  // ---- Each page says which it is, of how many, when there are more ---
  // Page 1 on the line where it says it goes on; the others at the top.
  const pageCount = doc.getNumberOfPages();
  if (pageCount > 1 && firstPageFootY !== null) {
    doc.setPage(1);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); grey();
    doc.text(`Page 1 of ${pageCount}`, RIGHT, firstPageFootY, { align: 'right' });
  }
  for (const p of continuedPages) {
    doc.setPage(p);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); grey();
    doc.text(`Page ${p} of ${pageCount}`, RIGHT, M + 2, { align: 'right' });
  }
  doc.setPage(pageCount);

  // A copy with a note (456): where it would end without it, if that is lower
  // down than where it ended. That is the copy's end unless what is above the
  // note runs long; the note's lines, which end on a page once that fits, do
  // not count.
  const endY = d.note ? Math.max(y, Math.max(yAboveNote + 4, sigY) + footH) : y;
  return { out: doc, endY, creditBeside, rowsCut };
}

/** The finished PDF as a Blob, ready to upload or download. */
export function documentPdfBlob(d: PdfDoc): Blob {
  return buildDocumentPdf(d).output('blob');
}

/** Save the PDF straight to the staff member's device. */
export function downloadDocumentPdf(d: PdfDoc, filename: string): void {
  buildDocumentPdf(d).save(filename);
}
