/**
 * Shared print document — two A5 copies on one A4 sheet.
 *
 * The invoice print and the Special Products / Rentals receipts must look the
 * same, so both build on this single definition. Keeping the CSS and the page
 * chrome here is what stops the two drifting apart the next time either is
 * touched.
 */

export const esc = (v: any) =>
  String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;');

export const money = (n: any) => `S$${Number(n ?? 0).toFixed(2)}`;

/** Branding and contact details, taken from the store row. */
export interface PrintBranding {
  company_logo_url?: string | null;
  store_logo_url?: string | null;
  name?: string | null;
  address?: string | null;
  phone?: string | null;
  email?: string | null;
  website?: string | null;
  co_reg_no?: string | null;
  paynow_uen?: string | null;
  bank_account?: string | null;
}

export interface PrintLine {
  name: string;
  qty?: number | string;
  unit?: number | string | null;
  total?: number | string | null;
  /** Indented detail lines shown under the main row. */
  subLines?: string[];
}

export interface PrintTotal {
  label: string;
  value: string;
  grand?: boolean;
}

export interface PrintDocOptions {
  /** e.g. "INV-2026-0011" or "RENT-2026-0007" */
  docNo: string;
  /** e.g. "Tax Invoice", "Special Product Sale", "Special Product Rental" */
  docTitle: string;
  branding: PrintBranding;
  /** Right-hand header lines under the document number. */
  headerLines?: string[];
  billToName: string;
  billToLines?: string[];
  lines: PrintLine[];
  totals: PrintTotal[];
  /** Rows for the payment table: [label, amount]. */
  payments?: [string, string][];
  /** Free-form blocks inserted after the payment table. */
  extraBlocks?: string[];
  /** Name printed under the second signature line. */
  issuedByName?: string | null;
  termsText?: string;
  /** Column heading for the first table column. */
  itemHeading?: string;
}

/** The stylesheet. Identical for every document type. */
export const PRINT_CSS = `
  /* Two A5 copies on one A4 portrait sheet: cut along the dashed line, the
     customer keeps the top half and the shop files the bottom half. */
  @page { size: A4 portrait; margin: 0; }
  body{font-family:Arial,Helvetica,sans-serif;font-size:9px;color:#111;margin:0;}
  h1{font-size:13px;margin:0;} h2{font-size:8px;margin:5px 0 2px;text-transform:uppercase;letter-spacing:0.04em;color:#333;}
  .mut{color:#666;font-size:7.5px;} .r{text-align:right;}
  table{width:100%;border-collapse:collapse;margin-top:2px;}
  th{font-size:7px;text-transform:uppercase;color:#666;text-align:left;border-bottom:1px solid #999;padding:2px 3px;}
  th.r{text-align:right;} td{padding:2px 3px;border-bottom:1px solid #eee;vertical-align:top;}
  tr.sub td{border-bottom:none;padding:0 3px 0 12px;font-size:7.5px;color:#555;}
  .ther{border:1px solid #ddd;border-radius:3px;padding:3px 4px;margin-top:2px;}
  .entb{margin-top:3px;padding-top:3px;border-top:1px solid #eee;}
  .entb:first-of-type{border-top:none;padding-top:0;margin-top:2px;}
  .bentbl{margin-top:2px;} .bentbl th{font-size:6.5px;padding:1px 2px;border-bottom:1px solid #ccc;}
  .bentbl td{font-size:7.5px;padding:1px 2px;border-bottom:1px solid #f2f2f2;}
  .totals{margin-top:3px;width:170px;margin-left:auto;} .totals td{border:none;padding:1px 3px;}
  .paytbl td{border:none;padding:1px 3px;}
  .grand{font-size:11px;font-weight:bold;border-top:1px solid #999;}
  .head{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:1.5px solid #111;padding-bottom:4px;}
  .copytag{font-size:7px;font-weight:bold;letter-spacing:0.08em;color:#111;margin-top:2px;
           border:1px solid #111;border-radius:2px;padding:1px 4px;display:inline-block;}
  .paydetail{font-size:7.5px;color:#333;display:inline;}
  .payfoot{margin-top:3px;font-size:7.5px;color:#333;}
  .signrow{margin-top:8px;display:flex;gap:14px;}
  .sign{flex:1;font-size:7.5px;color:#333;}
  .signline{border-bottom:1px solid #333;height:18px;margin-bottom:2px;}
  .terms{margin-top:5px;padding-top:3px;border-top:1px solid #ccc;font-size:7px;color:#333;}
  .footer{margin-top:3px;padding-top:2px;border-top:1px solid #ccc;font-size:6.5px;color:#444;line-height:1.4;text-align:center;}
  .logos{display:flex;gap:10px;align-items:center;margin-bottom:3px;}
  /* Each copy is exactly half an A4 page. */
  .copy{height:148.5mm;padding:5mm 7mm;box-sizing:border-box;overflow:hidden;}
  .cut{border-top:1px dashed #999;position:relative;height:0;}
  .cut span{position:absolute;top:-5px;left:50%;transform:translateX(-50%);background:#fff;
            padding:0 6px;font-size:6.5px;color:#999;letter-spacing:0.08em;}
  @media print { .cut{page-break-inside:avoid;} }
`;

/** Build one copy of the document. */
export function buildCopy(o: PrintDocOptions, copyLabel: string): string {
  const b = o.branding ?? {};

  const logosTop = (b.company_logo_url || b.store_logo_url)
    ? `<div class="logos">
        ${b.company_logo_url ? `<img src="${esc(b.company_logo_url)}" style="max-height:30px;max-width:120px;object-fit:contain" />` : ''}
        ${b.store_logo_url ? `<img src="${esc(b.store_logo_url)}" style="max-height:30px;max-width:120px;object-fit:contain" />` : ''}
      </div>` : '';

  const payDetailBits = [
    b.paynow_uen ? `PayNow: ${esc(b.paynow_uen)}` : '',
    b.bank_account ? `Bank: ${esc(b.bank_account)}` : '',
  ].filter(Boolean);
  const payRow = payDetailBits.length
    ? `<div class="paydetail">${payDetailBits.join(' &nbsp;·&nbsp; ')}</div>` : '';

  const footerBits = [
    b.phone ? `DID: ${esc(b.phone)}` : '',
    b.email ? `Email: ${esc(b.email)}` : '',
    b.website ? `Website: ${esc(b.website)}` : '',
    b.co_reg_no ? `Co. Reg No.: ${esc(b.co_reg_no)}` : '',
  ].filter(Boolean).join(' &nbsp;|&nbsp; ');

  const itemRows = o.lines.map(l => `
    <tr>
      <td>${esc(l.name)}</td>
      <td class="r">${esc(l.qty ?? '')}</td>
      <td class="r">${l.unit == null ? '' : (typeof l.unit === 'number' ? money(l.unit) : esc(l.unit))}</td>
      <td class="r"><strong>${l.total == null ? '' : (typeof l.total === 'number' ? money(l.total) : esc(l.total))}</strong></td>
    </tr>
    ${(l.subLines ?? []).map(sl => `<tr class="sub"><td colspan="3">— ${esc(sl)}</td><td></td></tr>`).join('')}
  `).join('');

  const payTable = (o.payments ?? []).length
    ? `<h2>Payment Methods</h2><table class="paytbl"><tbody>
        ${(o.payments ?? []).map(([k, v]) => `<tr><td>${esc(k)}</td><td class="r">${esc(v)}</td></tr>`).join('')}
      </tbody></table>` : '';

  return `
    <div class="copy">
      ${logosTop}
      <div class="head">
        <div><h1>Energia</h1><div class="mut">Wellness &amp; Retail</div>
          <div class="copytag">${esc(copyLabel)}</div></div>
        <div style="text-align:right"><h1>${esc(o.docNo)}</h1>
          <div class="mut">${esc(o.docTitle)}</div>
          ${b.name ? `<div class="mut">${esc(b.name)}</div>` : ''}
          ${b.address ? `<div class="mut">${esc(b.address)}</div>` : ''}
          ${b.phone ? `<div class="mut">Tel: ${esc(b.phone)}</div>` : ''}
          ${(o.headerLines ?? []).map(h => `<div class="mut">${h}</div>`).join('')}
        </div>
      </div>
      <h2>Bill To</h2>
      <div>${esc(o.billToName)}</div>
      ${(o.billToLines ?? []).map(l => `<div class="mut">${esc(l)}</div>`).join('')}
      <h2>Items</h2>
      <table><thead><tr>
        <th>${esc(o.itemHeading ?? 'Item')}</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Total</th>
      </tr></thead><tbody>${itemRows}</tbody></table>
      <table class="totals"><tbody>
        ${o.totals.map(t => `<tr${t.grand ? ' class="grand"' : ''}><td>${esc(t.label)}</td><td class="r">${esc(t.value)}</td></tr>`).join('')}
      </tbody></table>
      ${payTable}
      ${(o.extraBlocks ?? []).join('')}
      <div class="signrow">
        <div class="sign"><div class="signline"></div>Customer Signature</div>
        <div class="sign"><div class="signline"></div>Issued By${o.issuedByName ? ` — ${esc(o.issuedByName)}` : ''}</div>
      </div>
      <div class="terms">${esc(o.termsText ?? 'Goods and services sold are neither refundable nor exchangeable. Goods and services have been checked and collected.')}</div>
      ${payRow ? `<div class="payfoot"><strong>How to pay</strong> &nbsp; ${payRow}</div>` : ''}
      ${footerBits ? `<div class="footer">${footerBits}</div>` : ''}
    </div>`;
}

/** Open a print window with the customer and office copies. */
export function printA5Document(o: PrintDocOptions): boolean {
  const html = `<!doctype html><html><head><title>${esc(o.docNo)}</title>
    <style>${PRINT_CSS}</style></head><body>
    ${buildCopy(o, 'CUSTOMER COPY')}
    <div class="cut"><span>✂  CUT HERE</span></div>
    ${buildCopy(o, 'OFFICE COPY')}
    <script>window.onload=function(){window.print();}</script>
  </body></html>`;
  const w = window.open('', '_blank');
  if (!w) { alert('Please allow pop-ups to print.'); return false; }
  w.document.write(html); w.document.close();
  return true;
}
