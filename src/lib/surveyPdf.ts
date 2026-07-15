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

const yn = (v: boolean | null | undefined) => v === true ? 'Yes' : v === false ? 'No' : '—';
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

/**
 * Builds the customer-signed record as a PDF, mirroring the printed
 * Energia form. This is the artifact frozen at the moment of signing:
 * identity, declarations, symptoms, consent and signature. Staff notes
 * (acidity / health goals / remarks) are deliberately NOT included —
 * they are added later and must not appear inside a signed document.
 */
export const buildSurveyPdf = (s: SurveyPdfInput): string => {
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const L = 14, R = 196, W = R - L;
  let y = 16;

  const line = (yy: number) => { doc.setDrawColor(210); doc.line(L, yy, R, yy); };
  const need = (h: number) => { if (y + h > 280) { doc.addPage(); y = 16; } };

  // Header
  doc.setFont('helvetica', 'bold'); doc.setFontSize(17); doc.setTextColor(230, 90, 40);
  doc.text('energia', L, y);
  doc.setTextColor(20); doc.setFontSize(13);
  doc.text('New Customer Form', R, y, { align: 'right' });
  y += 5;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(120);
  doc.text('energy flow . good blood flow', L, y);
  doc.text(`${s.store_name}${s.event_name ? ` · ${s.event_name}` : ''}`, R, y, { align: 'right' });
  y += 3; line(y); y += 6;

  // Identity
  doc.setTextColor(20); doc.setFontSize(9.5);
  const row = (pairs: [string, string][]) => {
    need(7);
    const cw = W / pairs.length;
    pairs.forEach(([k, v], i) => {
      const x = L + i * cw;
      doc.setTextColor(120); doc.setFont('helvetica', 'normal');
      doc.text(k, x, y);
      doc.setTextColor(20); doc.setFont('helvetica', 'bold');
      doc.text(String(v || '—'), x, y + 4.2);
    });
    y += 10;
  };
  row([['Name', s.full_name], ['HP No.', s.phone]]);
  row([['Date of Birth', d(s.date_of_birth)], ['Age', s.age ? String(s.age) : '—'], ['Sex', s.sex ? (s.sex === 'female' ? 'Female' : 'Male') : '—']]);
  row([['Email', s.email || '—'], ['Occupation', s.occupation || '—']]);
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
    doc.setTextColor(60); doc.text(q, L, y);
    doc.setFont('helvetica', 'bold'); doc.setTextColor(20); doc.text(a, R, y, { align: 'right' });
    doc.setFont('helvetica', 'normal');
    y += 5;
  });
  if (s.on_treatment && s.treatment_list) {
    need(6);
    doc.setTextColor(120); doc.text('If Yes, please list:', L, y);
    doc.setTextColor(20); doc.setFont('helvetica', 'bold');
    doc.text(doc.splitTextToSize(s.treatment_list, W - 32) as string[], L + 32, y);
    doc.setFont('helvetica', 'normal');
    y += 5;
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
        doc.setFont('helvetica', 'bold'); doc.setTextColor(20); doc.setFontSize(9);
        doc.text(cat, L, y); y += 4.5;
      }
      doc.setFont('helvetica', 'normal'); doc.setTextColor(60); doc.setFontSize(9);
      doc.text(`•  ${sy.label}`, L + 3, y);
      if (sy.duration_text) {
        doc.setTextColor(120);
        doc.text(`Duration: ${sy.duration_text}`, R, y, { align: 'right' });
      }
      y += 4.5;
    });
  }
  if (s.others_text) {
    need(6); y += 1;
    doc.setFont('helvetica', 'bold'); doc.setTextColor(20); doc.text('Others:', L, y);
    doc.setFont('helvetica', 'normal'); doc.setTextColor(60);
    doc.text(doc.splitTextToSize(s.others_text, W - 16) as string[], L + 16, y);
    y += 5;
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
