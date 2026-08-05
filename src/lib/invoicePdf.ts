import { jsPDF } from 'jspdf';

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
  kindLabel: string;           // "Tax Invoice", "Special Product Sale", …
  docNo: string;
  date: string;
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
  payDetails?: string[];
  staffName?: string | null;
  termsText?: string;
  footerBits?: string[];
}

const A5_W = 148.5;
const A5_H = 210;
const M = 10;                    // page margin
const RIGHT = A5_W - M;

export function buildDocumentPdf(d: PdfDoc): jsPDF {
  const doc = new jsPDF({ unit: 'mm', format: [A5_W, A5_H], orientation: 'portrait' });
  let y = M;

  const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
  const grey = () => doc.setTextColor(110, 110, 110);
  const black = () => doc.setTextColor(17, 17, 17);

  // ---- Header -------------------------------------------------------
  doc.setFont('helvetica', 'bold'); doc.setFontSize(15); black();
  doc.text('Energia', M, y + 4);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(7); grey();
  doc.text('Wellness & Retail', M, y + 8);

  doc.setFont('helvetica', 'bold'); doc.setFontSize(11); black();
  doc.text(d.docNo, RIGHT, y + 4, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(7); grey();
  let hy = y + 8;
  for (const t of [d.kindLabel, d.storeName, d.storeAddress, d.storePhone ? `Tel: ${d.storePhone}` : '',
                   `Date: ${d.date}`, d.status ? `Status: ${d.status}` : '']) {
    if (!t) continue;
    // Long addresses wrap rather than running off the page.
    for (const ln of doc.splitTextToSize(String(t), 80)) {
      doc.text(ln, RIGHT, hy, { align: 'right' }); hy += 3.1;
    }
  }

  y = Math.max(y + 14, hy) + 1;
  black(); doc.setDrawColor(17, 17, 17); doc.setLineWidth(0.4);
  doc.line(M, y, RIGHT, y);
  y += 5;

  // ---- Customer -----------------------------------------------------
  doc.setFont('helvetica', 'bold'); doc.setFontSize(7); grey();
  doc.text('BILL TO', M, y); y += 4;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9); black();
  doc.text(d.customerName, M, y); y += 3.6;
  if (d.customerContact) {
    doc.setFontSize(7); grey(); doc.text(d.customerContact, M, y); y += 3.6;
  }
  y += 2;

  // ---- Items --------------------------------------------------------
  const cQty = RIGHT - 46, cUnit = RIGHT - 24, cTot = RIGHT;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(7); grey();
  doc.text('ITEM', M, y);
  doc.text('QTY', cQty, y, { align: 'right' });
  doc.text('UNIT', cUnit, y, { align: 'right' });
  doc.text('TOTAL', cTot, y, { align: 'right' });
  y += 1.5;
  doc.setDrawColor(150, 150, 150); doc.setLineWidth(0.2);
  doc.line(M, y, RIGHT, y);
  y += 3.6;

  black(); doc.setFont('helvetica', 'normal'); doc.setFontSize(8);
  for (const l of d.lines) {
    const nameLines = doc.splitTextToSize(l.name, cQty - M - 3);
    const rowH = nameLines.length * 3.4 + (l.notes?.length ?? 0) * 3 + 1.6;

    // Keep the signature block on the page: stop listing and summarise.
    if (y + rowH > A5_H - 62) {
      grey(); doc.setFontSize(7);
      doc.text('…continued — see the full invoice in store', M, y);
      y += 4; black(); doc.setFontSize(8);
      break;
    }

    doc.text(nameLines, M, y);
    doc.text(String(l.qty), cQty, y, { align: 'right' });
    doc.text(money(l.unit), cUnit, y, { align: 'right' });
    doc.setFont('helvetica', 'bold');
    doc.text(money(l.total), cTot, y, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    let ny = y + nameLines.length * 3.4;
    for (const n of l.notes ?? []) {
      grey(); doc.setFontSize(6.5);
      doc.text(n, M + 2, ny); ny += 3;
      black(); doc.setFontSize(8);
    }
    // Separator sits below the row just drawn; the next baseline then starts
    // clear of it, otherwise the line strikes through the following text.
    const sepY = ny - 1.2;
    doc.setDrawColor(230, 230, 230); doc.setLineWidth(0.15);
    doc.line(M, sepY, RIGHT, sepY);
    y = sepY + 4.6;
  }

  // ---- Totals -------------------------------------------------------
  y += 2;
  doc.setFontSize(8);
  for (const [label, value] of d.totals) {
    grey(); doc.text(label, cUnit, y, { align: 'right' });
    black(); doc.text(value, cTot, y, { align: 'right' });
    y += 4;
  }
  if (d.grandTotal) {
    doc.setDrawColor(150, 150, 150); doc.setLineWidth(0.3);
    doc.line(cUnit - 22, y - 2.6, RIGHT, y - 2.6);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(10.5); black();
    doc.text(d.grandTotal[0], cUnit, y + 1.4, { align: 'right' });
    doc.text(d.grandTotal[1], cTot, y + 1.4, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    y += 6;
  }

  // ---- Payments -----------------------------------------------------
  if (d.payments?.length) {
    y += 2;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(7); grey();
    doc.text('PAYMENT METHODS', M, y); y += 4;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8); black();
    for (const [k, v] of d.payments) {
      doc.text(k, M, y); doc.text(v, cTot, y, { align: 'right' }); y += 3.8;
    }
  }

  // ---- Signatures, pinned near the foot -----------------------------
  const sigY = A5_H - 48;
  y = Math.max(y + 4, sigY);
  const colW = (RIGHT - M - 6) / 2;
  doc.setFontSize(8.5); black(); doc.setFont('helvetica', 'bolditalic');
  if (d.staffName) doc.text(d.staffName, M, y);
  doc.setFont('helvetica', 'normal');
  doc.setDrawColor(51, 51, 51); doc.setLineWidth(0.25);
  doc.line(M, y + 1.6, M + colW, y + 1.6);
  doc.line(M + colW + 6, y + 1.6, RIGHT, y + 1.6);
  doc.setFontSize(6.5); doc.setTextColor(51, 51, 51);
  doc.text('Staff Signature', M, y + 5);
  doc.text('Customer Signature', M + colW + 6, y + 5);
  y += 9;

  // ---- Terms, payment details, footer -------------------------------
  doc.setDrawColor(200, 200, 200); doc.setLineWidth(0.15);
  doc.line(M, y, RIGHT, y); y += 3.4;
  doc.setFontSize(6); doc.setTextColor(51, 51, 51);
  for (const ln of doc.splitTextToSize(
    d.termsText ?? 'Goods and services sold are neither refundable nor exchangeable. Goods and services have been checked and collected.',
    RIGHT - M)) { doc.text(ln, M, y); y += 2.6; }

  if (d.payDetails?.length) {
    y += 1.4;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(6.2); black();
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
    doc.setFontSize(5.6); grey();
    for (const ln of doc.splitTextToSize(d.footerBits.join('  |  '), RIGHT - M)) {
      doc.text(ln, A5_W / 2, y, { align: 'center' }); y += 2.4;
    }
  }

  return doc;
}

/** The finished PDF as a Blob, ready to upload or download. */
export function documentPdfBlob(d: PdfDoc): Blob {
  return buildDocumentPdf(d).output('blob');
}

/** Save the PDF straight to the staff member's device. */
export function downloadDocumentPdf(d: PdfDoc, filename: string): void {
  buildDocumentPdf(d).save(filename);
}
