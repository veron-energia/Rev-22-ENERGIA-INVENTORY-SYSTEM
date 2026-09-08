// Xero's Sales Invoice import template.
//
// Two things the accountant asked for, neither of which is about the data:
//
//   1. CSV, not a spreadsheet. Xero's importer takes a .csv file; an .xlsx is
//      rejected at the upload step, before any column is ever read. That is why
//      the feedback described what Xero needs in general terms rather than
//      auditing what was in the file — nobody got as far as the columns.
//
//   2. The template's own column set, in the template's own order. The export
//      already carried every mandatory field, but only 18 of the 29 columns, so
//      held against the template it looked incomplete. The eleven that were
//      missing are all optional; emitting them empty costs nothing and makes the
//      file a column-for-column match, which is one less thing to argue about.
//
// Kept free of React and of the export component so it can be unit-tested with
// the Node test runner, following the same `.mjs` + `.d.mts` shape as
// `lib/customer-phones/normalize.mjs` and `lib/survey/form.mjs`.

/** The template's columns, in the exact order Xero ships them. */
export const XERO_SALES_INVOICE_HEADERS = [
  '*ContactName', 'EmailAddress',
  'POAddressLine1', 'POAddressLine2', 'POAddressLine3', 'POAddressLine4',
  'POCity', 'PORegion', 'POPostalCode', 'POCountry',
  '*InvoiceNumber', 'Reference', '*InvoiceDate', '*DueDate', 'Total',
  'InventoryItemCode', '*Description', '*Quantity', '*UnitAmount', 'Discount',
  '*AccountCode', '*TaxType', 'TaxAmount',
  'TrackingName1', 'TrackingOption1', 'TrackingName2', 'TrackingOption2',
  'Currency', 'BrandingTheme',
];

/** The starred columns. Xero rejects a row where any of these is empty. */
export const XERO_MANDATORY_HEADERS = XERO_SALES_INVOICE_HEADERS.filter(h => h.startsWith('*'));

/**
 * One CSV cell.
 *
 * Quoted only when it has to be, because a file full of unnecessary quotes is
 * harder for a person to read when something goes wrong. A value containing a
 * quote, a comma, a newline or leading/trailing spaces is quoted, and inner
 * quotes are doubled — which is what every CSV reader, Xero's included, expects.
 */
export function csvCell(value) {
  if (value === null || value === undefined) return '';
  const s = typeof value === 'number' && Number.isFinite(value) ? String(value) : String(value);
  if (s === '') return '';
  return /[",\r\n]/.test(s) || s !== s.trim() ? `"${s.replace(/"/g, '""')}"` : s;
}

/**
 * Rows to a CSV document, always in the template's column order and always with
 * the full header row — including for an empty result, so an export with no
 * invoices still opens as a valid, recognisable template rather than a blank file.
 *
 * CRLF line endings: that is what the CSV convention specifies, and what Excel
 * and Xero both handle without complaint.
 */
export function toXeroCsv(rows, headers = XERO_SALES_INVOICE_HEADERS) {
  const lines = [headers.map(csvCell).join(',')];
  for (const row of rows ?? []) {
    lines.push(headers.map(h => csvCell(row?.[h])).join(','));
  }
  return lines.join('\r\n') + '\r\n';
}

/**
 * Every mandatory cell that is empty, so the problem is found here rather than
 * by Xero halfway through an import.
 *
 * Zero is a legitimate value for an amount and is NOT treated as missing; an
 * empty string, null and undefined are.
 */
export function findMissingMandatory(rows, headers = XERO_MANDATORY_HEADERS) {
  const problems = [];
  (rows ?? []).forEach((row, i) => {
    for (const h of headers) {
      const v = row?.[h];
      if (v === null || v === undefined || (typeof v === 'string' && v.trim() === '')) {
        problems.push({ row: i + 1, field: h });
      }
    }
  });
  return problems;
}

/** Filename for a CSV export. Xero does not care; a person looking for it does. */
export function xeroCsvFilename(scope, from, to) {
  return `xero-invoices-${scope}-${from}-to-${to}.csv`.replace(/\s+/g, '-');
}
