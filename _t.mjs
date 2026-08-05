import { buildDocumentPdf } from '/tmp/invoicePdf.mjs';
import fs from 'fs';

const mk = (n) => ({
  kindLabel: 'Tax Invoice',
  docNo: 'INV-2026-0011',
  date: '05/08/2026',
  status: 'Paid',
  storeName: 'Energia Rev 22 (Adelphi)',
  storeAddress: '1 Coleman Street, The Adelphi B1-37, Singapore 179803',
  storePhone: '63372768',
  customerName: 'John (Yvonne, GEX) Toh',
  customerContact: '+6598378991',
  lines: Array.from({ length: n }, (_, i) => ({
    name: i % 3 === 0 ? 'Premium King Sleep System Set with bolster and Therapy' : `Energia Product ${i + 1}`,
    qty: 1, unit: 468 + i, total: 468 + i,
    notes: i === 1 ? ['FOC (full line) — value S$468.00'] : [],
  })),
  totals: [['Subtotal', 'S$795.00'], ['Discount', '-S$0.00']],
  grandTotal: ['Total', 'S$795.00'],
  payments: [['Master Card', 'S$795.00']],
  payDetails: ['CIMB UEN: 201104431Z', 'CIMB corporate account: Rev 22 Pte Ltd 3483090275'],
  staffName: 'Tun Tun Aye',
  footerBits: ['DID: 63372768', 'Email: info@rev22.com', 'Website: https://energia.sg/', 'Co. Reg No.: 201104431Z'],
});

for (const n of [1, 5, 14, 40]) {
  const doc = buildDocumentPdf(mk(n));
  const ab = doc.output('arraybuffer');
  fs.writeFileSync(`/tmp/inv_pdf_${n}.pdf`, Buffer.from(ab));
  console.log(`${String(n).padStart(2)} items -> ${(ab.byteLength / 1024).toFixed(1)} KB`);
}
