import { PdfDoc, PdfLine } from './invoicePdf';

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
  const c = document.createElement('canvas');
  c.width = W; c.height = H;
  const x = c.getContext('2d');
  if (!x) return Promise.reject(new Error('This browser cannot render the invoice image.'));

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

  x.fillStyle = '#ffffff'; x.fillRect(0, 0, W, H);
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

  font(3.64);
  for (const l of d.lines) {
    const rowH = wrap(l.name, cQty - M - 3 * MM).length * 3.4 * MM + (l.notes?.length ?? 0) * 3 * MM + 1.6 * MM;
    if (y + rowH > H - 70 * MM) {
      font(3.12); x.fillStyle = GREY;
      x.fillText('…continued — see the full invoice in store', M, y);
      y += 4 * MM; x.fillStyle = BLACK;
      break;
    }
    drawLine(l);
  }

  // ---- Totals -------------------------------------------------------
  y += 2 * MM; font(3.64);
  for (const [label, value] of d.totals) {
    x.fillStyle = GREY; right(label, cUnit, y);
    x.fillStyle = BLACK; right(value, cTot, y);
    y += 4.8 * MM;
  }
  if (d.grandTotal) {
    x.strokeStyle = '#969696'; x.lineWidth = 0.3 * MM;
    x.beginPath(); x.moveTo(cUnit - 22 * MM, y - 2.6 * MM); x.lineTo(RIGHT, y - 2.6 * MM); x.stroke();
    font(4.81, 'bold'); x.fillStyle = BLACK;
    right(d.grandTotal[0], cUnit, y + 1.4 * MM);
    right(d.grandTotal[1], cTot, y + 1.4 * MM);
    y += 6 * MM;
  }

  // ---- Payments -----------------------------------------------------
  if (d.payments?.length) {
    y += 2 * MM;
    font(3.12, 'bold'); x.fillStyle = GREY;
    x.fillText('PAYMENT METHODS', M, y); y += 4 * MM;
    font(3.64); x.fillStyle = BLACK;
    for (const [k, v] of d.payments) { x.fillText(k, M, y); right(v, cTot, y); y += 4.6 * MM; }
  }

  // ---- Signatures ---------------------------------------------------
  y = Math.max(y + 4 * MM, H - 56 * MM);
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
  for (const ln of wrap(
    (d.termsText ?? 'Goods and services sold are neither refundable nor exchangeable. Goods and services have been checked and collected.').toUpperCase(),
    RIGHT - M)) { x.fillText(ln, M, y); y += 3.2 * MM; }

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

  return new Promise((resolve, reject) => {
    c.toBlob(b => b ? resolve(b) : reject(new Error('Could not create the invoice image.')), 'image/png');
  });
}
