import { jsPDF } from 'jspdf';

export interface SurveyPdfInput {
  survey_no?: string;
  store_name: string;
  event_name?: string | null;
  full_name: string;
  date_of_birth?: string | null;
  age?: string | number | null;
  sex?: string | null;
  phone: string;
  email?: string | null;
  occupation?: string | null;
  source_label?: string | null;
  source_details?: string | null;
  has_medical_condition?: boolean | null;
  drinks_alcohol?: boolean | null;
  smokes?: boolean | null;
  on_treatment?: boolean | null;
  treatment_list?: string | null;
  others_text?: string | null;
  consent_newsletter_email?: boolean;
  consent_marketing_email?: boolean;
  consent_marketing_sms?: boolean;
  consent_marketing_phone?: boolean;
  signature_data?: string | null;
  signed_date?: string | null;
  symptoms: { category: string; label: string; duration_text?: string | null }[];
}

/** Text drawn as a picture: the image and its size on the page. */
export interface TextImage { dataUrl: string; widthMm: number; heightMm: number }
/**
 * Draws text the PDF's built-in font cannot show (Chinese, Tamil, ...) as a
 * picture, wrapped to maxWidthMm. Null when it cannot (no canvas).
 */
export type TextPainter = (text: string, opts: {
  sizePt: number; bold: boolean; maxWidthMm: number; color: [number, number, number];
}) => TextImage | null;

const yn = (v: boolean | null | undefined) => v === true ? 'Yes' : v === false ? 'No' : '—';
// A date-only value (date of birth, signed date) as dd/mm/yyyy, never moved by time zone.
const d = (s?: string | null) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(s ?? ''));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '—';
};
const PT_MM = 0.3528;

// jsPDF's built-in Helvetica has the Windows-1252 letters only.
const CP1252_EXTRA = '€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ';
/** Whether the built-in font can show every letter of s. */
export const fitsStandardFont = (s: string) => [...s].every(ch => {
  const c = ch.codePointAt(0)!;
  return c === 9 || c === 10 || c === 13 || (c >= 0x20 && c <= 0x7e) || (c >= 0xa0 && c <= 0xff) || CP1252_EXTRA.includes(ch);
});

// One wrap unit: a CJK letter, a word, or the spaces between words.
const UNITS = /[⺀-鿿가-힯぀-ヿ豈-﫿＀-￯]|[^\s⺀-鿿가-힯぀-ヿ豈-﫿＀-￯]+|\s+/g;

/** The browser's own fonts, through a canvas (every phone has Chinese ones). */
export const canvasPainter: TextPainter = (text, { sizePt, bold, maxWidthMm, color }) => {
  if (typeof document === 'undefined') return null;
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext?.('2d');
  if (!ctx) return null;
  const scale = 4;                              // canvas pixels per point, for a sharp print
  const pxPerMm = scale / PT_MM;
  const font = `${bold ? 'bold ' : ''}${sizePt * scale}px "Noto Sans SC", "PingFang SC", "Microsoft YaHei", "Hiragino Sans", "Noto Sans", sans-serif`;
  ctx.font = font;
  const maxPx = maxWidthMm * pxPerMm;
  const lines: string[] = [];
  for (const para of text.split('\n')) {
    let line = '';
    for (const unit of para.match(UNITS) ?? []) {
      const next = line + unit;
      if (line && ctx.measureText(next).width > maxPx) { lines.push(line.trimEnd()); line = unit.trimStart(); }
      else line = next;
    }
    lines.push(line);
  }
  const lineH = sizePt * scale * 1.3;
  const width = Math.min(maxPx, Math.max(1, ...lines.map(l => ctx.measureText(l).width)));
  canvas.width = Math.ceil(width) + 2;
  canvas.height = Math.ceil(lineH * lines.length) + 2;
  ctx.font = font;                              // resizing the canvas resets it
  ctx.fillStyle = `rgb(${color.join(',')})`;
  ctx.textBaseline = 'top';
  lines.forEach((l, i) => ctx.fillText(l, 1, 1 + i * lineH));
  return { dataUrl: canvas.toDataURL('image/png'), widthMm: canvas.width / pxPerMm, heightMm: canvas.height / pxPerMm };
};

/**
 * Builds the customer-signed record as a PDF, mirroring the printed
 * Energia form. This is the artifact frozen at the moment of signing:
 * identity, declarations, symptoms, consent and signature. Staff notes
 * (acidity / health goals / remarks) are deliberately NOT included —
 * they are added later and must not appear inside a signed document.
 *
 * 419 (CUSTOMERS-16): every value wraps inside its space, and a value the
 * built-in font cannot show (a Chinese name, say) is drawn as a picture by
 * painter, so it is printed rather than garbled. Without a painter such
 * letters print as "?".
 */
export const buildSurveyPdf = (s: SurveyPdfInput, opts: { painter?: TextPainter } = {}): string => {
  const painter = opts.painter ?? canvasPainter;
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const L = 14, R = 196, W = R - L;
  let y = 16;

  const line = (yy: number) => { doc.setDrawColor(210); doc.line(L, yy, R, yy); };
  const need = (h: number) => { if (y + h > 280) { doc.addPage(); y = 16; } };

  /**
   * Writes text at (x, baseline yy), wrapped to maxW; returns the height used
   * (mm). Text the font cannot show is drawn by the painter.
   */
  const put = (text: string, x: number, yy: number, o: {
    maxW: number; align?: 'left' | 'right'; bold?: boolean; size: number; color: [number, number, number];
  }): number => {
    const value = String(text ?? '');
    const lineH = o.size * PT_MM * 1.25;
    doc.setFont('helvetica', o.bold ? 'bold' : 'normal'); doc.setFontSize(o.size);
    doc.setTextColor(o.color[0], o.color[1], o.color[2]);
    if (!fitsStandardFont(value)) {
      const img = painter(value, { sizePt: o.size, bold: !!o.bold, maxWidthMm: o.maxW, color: o.color });
      if (img) {
        const left = o.align === 'right' ? x - img.widthMm : x;
        try {
          doc.addImage(img.dataUrl, 'PNG', left, yy - o.size * PT_MM * 0.85, img.widthMm, img.heightMm);
          return Math.max(lineH, img.heightMm);
        } catch { /* fall through to plain text */ }
      }
    }
    const safe = [...value].map(ch => (fitsStandardFont(ch) ? ch : '?')).join('');
    const lines = doc.splitTextToSize(safe, o.maxW) as string[];
    doc.text(lines, x, yy, o.align === 'right' ? { align: 'right' } : undefined);
    return lines.length * lineH;
  };

  // Header
  doc.setFont('helvetica', 'bold'); doc.setFontSize(17); doc.setTextColor(230, 90, 40);
  doc.text('energia', L, y);
  doc.setTextColor(20); doc.setFontSize(13);
  doc.text('New Customer Form', R, y, { align: 'right' });
  y += 5;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(120);
  doc.text('energy flow . good blood flow', L, y);
  y += put(`${s.store_name}${s.event_name ? ` · ${s.event_name}` : ''}`, R, y,
           { maxW: 110, align: 'right', size: 8, color: [120, 120, 120] }) - 3.5;
  y += 3; line(y); y += 6;

  // Identity
  const row = (pairs: [string, string][]) => {
    need(10);
    const cw = W / pairs.length;
    let h = 4.2;
    pairs.forEach(([k, v], i) => {
      const x = L + i * cw;
      put(k, x, y, { maxW: cw - 3, size: 9.5, color: [120, 120, 120] });
      h = Math.max(h, put(String(v || '—'), x, y + 4.2, { maxW: cw - 3, bold: true, size: 9.5, color: [20, 20, 20] }));
    });
    y += Math.max(10, 5.8 + h);
  };
  row([['Name', s.full_name], ['HP No.', s.phone]]);
  row([['Date of Birth', d(s.date_of_birth)], ['Age', s.age ? String(s.age) : '—'],
       ['Sex', s.sex === 'female' ? 'Female' : s.sex === 'male' ? 'Male' : s.sex === 'other' ? 'Other' : '—']]);
  row([['Email', s.email || '—'], ['Occupation', s.occupation || '—']]);
  row([['How did you hear about us?', (s.source_label || '—') + (s.source_details ? ` — ${s.source_details}` : '')]]);
  line(y); y += 6;

  // Declarations
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(20);
  doc.text('Declarations', L, y); y += 5;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
  const decl: [string, string][] = [
    ['Do you have any medical or physical condition to declare?', yn(s.has_medical_condition)],
    ['Do you drink alcohol?', yn(s.drinks_alcohol)],
    ['Do you smoke?', yn(s.smokes)],
    ['Are you now taking any medical / physiotherapy treatment or medicine / pain killer?', yn(s.on_treatment)],
  ];
  decl.forEach(([q, a]) => {
    need(6);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
    doc.setTextColor(60); doc.text(q, L, y);
    doc.setFont('helvetica', 'bold'); doc.setTextColor(20); doc.text(a, R, y, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    y += 5;
  });
  if (s.on_treatment && s.treatment_list) {
    need(6);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
    doc.setTextColor(120); doc.text('If Yes, please list:', L, y);
    y += put(s.treatment_list, L + 32, y, { maxW: W - 32, bold: true, size: 9, color: [20, 20, 20] }) + 1;
  }
  y += 2; line(y); y += 6;

  // Symptoms
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(20);
  doc.text('Symptoms or conditions declared', L, y); y += 5;
  doc.setFontSize(9);
  if (s.symptoms.length === 0) {
    doc.setFont('helvetica', 'normal'); doc.setTextColor(120);
    doc.text('None indicated.', L, y); y += 5;
  } else {
    let cat = '';
    s.symptoms.forEach(sy => {
      need(6);
      if (sy.category !== cat) {
        cat = sy.category;
        y += put(cat, L, y, { maxW: W, bold: true, size: 9, color: [20, 20, 20] }) + 0.5;
      }
      const used = put(`•  ${sy.label}`, L + 3, y, { maxW: sy.duration_text ? W - 63 : W - 3, size: 9, color: [60, 60, 60] });
      const usedD = sy.duration_text
        ? put(`Duration: ${sy.duration_text}`, R, y, { maxW: 58, align: 'right', size: 9, color: [120, 120, 120] })
        : 0;
      y += Math.max(4.5, used, usedD) + 0.5;
    });
  }
  if (s.others_text) {
    need(6); y += 1;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(20); doc.text('Others:', L, y);
    y += put(s.others_text, L + 16, y, { maxW: W - 16, size: 9, color: [60, 60, 60] }) + 1;
  }
  y += 2; line(y); y += 6;

  // Note — verbatim
  need(20);
  doc.setFont('helvetica', 'bold'); doc.setFontSize(8.5); doc.setTextColor(20);
  doc.text('Note:', L, y); y += 4;
  doc.setFont('helvetica', 'normal'); doc.setTextColor(60);
  doc.text(doc.splitTextToSize(
    'The Health & Wellness Analysis is NOT a diagnostic health procedure but serves only as a guide to the observation of an individual state of health.', W) as string[], L, y);
  y += 7;
  doc.setTextColor(200, 40, 40);
  doc.text(doc.splitTextToSize(
    'It is not recommended for any one with electronic heart pacemaker or a pregnant woman.', W) as string[], L, y);
  y += 6;

  // Privacy — verbatim
  need(30);
  doc.setFont('helvetica', 'bold'); doc.setTextColor(20); doc.text('Privacy Policy:', L, y); y += 4;
  doc.setFont('helvetica', 'normal'); doc.setTextColor(60);
  doc.text(doc.splitTextToSize(
    'You agree that Rev 22 Pte Ltd may collect, use and disclose your personal data, which you have provided in this form, for providing marketing material that you have agreed to receive, in accordance with the Personal Data Protection Act 2012.', W) as string[], L, y);
  y += 10;
  doc.text('Consent given:', L, y); y += 4.5;
  const tick = (b?: boolean) => b ? '[X]' : '[  ]';
  doc.setFontSize(8.5);
  doc.text(`1. Monthly Newsletter —  ${tick(s.consent_newsletter_email)} Email`, L + 3, y); y += 4.5;
  doc.text(`2. Products & services —  ${tick(s.consent_marketing_email)} Email    ${tick(s.consent_marketing_sms)} Text Message    ${tick(s.consent_marketing_phone)} Phone Call`, L + 3, y);
  y += 8;

  // Signature
  need(34);
  line(y); y += 6;
  doc.setFontSize(9); doc.setTextColor(120);
  doc.text('Signature:', L, y);
  doc.text('Date:', R - 46, y);
  doc.setTextColor(20); doc.setFont('helvetica', 'bold');
  doc.text(d(s.signed_date), R - 34, y);
  doc.setFont('helvetica', 'normal');
  if (s.signature_data) {
    try { doc.addImage(s.signature_data, 'PNG', L + 18, y - 12, 52, 18); } catch { /* signature unreadable — line still prints */ }
  }
  doc.setDrawColor(80); doc.line(L + 18, y + 1.5, L + 78, y + 1.5);
  y += 8;

  // Footer
  doc.setFontSize(7.5); doc.setTextColor(140);
  doc.text(`Rev 22 Pte Ltd${s.survey_no ? `  ·  ${s.survey_no}` : ''}  ·  Submitted ${new Date().toLocaleString('en-GB', { timeZone: 'Asia/Singapore' })} (SGT)`, L, 289);

  return doc.output('datauristring').split(',')[1];   // base64 only
};
