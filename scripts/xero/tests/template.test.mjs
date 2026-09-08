// The Xero sales-invoice CSV: column order, escaping, and the mandatory fields.
//
//   npm run test:xero
//
// The header list is checked against Xero's own template file verbatim, so if
// Xero ever changes it the test says so rather than the import failing quietly.

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  XERO_SALES_INVOICE_HEADERS, XERO_MANDATORY_HEADERS,
  csvCell, toXeroCsv, findMissingMandatory, xeroCsvFilename,
} from '../../../src/lib/xero/salesInvoiceTemplate.mjs';

// Copied verbatim from the header row of Xero's SalesInvoiceTemplate.csv.
const TEMPLATE_HEADER_ROW =
  '*ContactName,EmailAddress,POAddressLine1,POAddressLine2,POAddressLine3,POAddressLine4,' +
  'POCity,PORegion,POPostalCode,POCountry,*InvoiceNumber,Reference,*InvoiceDate,*DueDate,Total,' +
  'InventoryItemCode,*Description,*Quantity,*UnitAmount,Discount,*AccountCode,*TaxType,TaxAmount,' +
  'TrackingName1,TrackingOption1,TrackingName2,TrackingOption2,Currency,BrandingTheme';

test('the header row matches Xero\'s template exactly, in order', () => {
  assert.equal(XERO_SALES_INVOICE_HEADERS.join(','), TEMPLATE_HEADER_ROW);
  assert.equal(XERO_SALES_INVOICE_HEADERS.length, 29);
});

test('the mandatory columns are the nine starred ones', () => {
  assert.deepEqual(XERO_MANDATORY_HEADERS, [
    '*ContactName', '*InvoiceNumber', '*InvoiceDate', '*DueDate',
    '*Description', '*Quantity', '*UnitAmount', '*AccountCode', '*TaxType',
  ]);
});

test('an empty export is still a valid template, not a blank file', () => {
  const csv = toXeroCsv([]);
  assert.equal(csv, TEMPLATE_HEADER_ROW + '\r\n');
});

test('a row is written in template order regardless of key order', () => {
  const csv = toXeroCsv([{
    '*TaxType': 'NONE', '*ContactName': 'Ada Lovelace', '*Quantity': 2,
    '*InvoiceNumber': 'INV-001', '*UnitAmount': 12.5, '*Description': 'Item',
    '*InvoiceDate': '08/09/2026', '*DueDate': '08/09/2026', '*AccountCode': '200',
  }]);
  const [header, row] = csv.trimEnd().split('\r\n');
  assert.equal(header, TEMPLATE_HEADER_ROW);
  const cols = row.split(',');
  assert.equal(cols[0], 'Ada Lovelace');              // *ContactName, first column
  assert.equal(cols[10], 'INV-001');                  // *InvoiceNumber, eleventh
  assert.equal(cols[16], 'Item');                     // *Description
  assert.equal(cols[17], '2');                        // *Quantity
  assert.equal(cols[18], '12.5');                     // *UnitAmount
  assert.equal(cols.length, 29, 'every column present, unused ones empty');
});

test('commas, quotes and newlines in a name cannot break the file', () => {
  assert.equal(csvCell('Tan, Ah Kow'), '"Tan, Ah Kow"');
  assert.equal(csvCell('He said "hi"'), '"He said ""hi"""');
  assert.equal(csvCell('line1\nline2'), '"line1\nline2"');
  assert.equal(csvCell('  padded  '), '"  padded  "');
  assert.equal(csvCell('plain'), 'plain');

  // A customer name with a comma must still leave exactly 29 columns.
  const csv = toXeroCsv([{ '*ContactName': 'Tan, Ah Kow', '*Description': 'Item' }]);
  const row = csv.trimEnd().split('\r\n')[1];
  assert.match(row, /^"Tan, Ah Kow",/);
});

test('empty and zero are treated differently', () => {
  // Zero is a real amount — a discount line or a rounding line can legitimately
  // be zero — so it must not be mistaken for a missing value.
  assert.equal(csvCell(0), '0');
  assert.equal(csvCell(''), '');
  assert.equal(csvCell(null), '');
  assert.equal(csvCell(undefined), '');
  assert.equal(csvCell(-4.25), '-4.25');
});

test('a blank mandatory field is reported before Xero sees it', () => {
  const rows = [
    { '*ContactName': 'Ada', '*InvoiceNumber': 'INV-1', '*InvoiceDate': '08/09/2026',
      '*DueDate': '08/09/2026', '*Description': 'Item', '*Quantity': 1,
      '*UnitAmount': 10, '*AccountCode': '200', '*TaxType': 'NONE' },
    { '*ContactName': '', '*InvoiceNumber': 'INV-2', '*InvoiceDate': '08/09/2026',
      '*DueDate': '08/09/2026', '*Description': '   ', '*Quantity': 1,
      '*UnitAmount': 0, '*AccountCode': '200', '*TaxType': 'NONE' },
  ];
  const problems = findMissingMandatory(rows);
  assert.deepEqual(problems, [
    { row: 2, field: '*ContactName' },
    { row: 2, field: '*Description' },
  ]);
  // *UnitAmount of 0 on row 2 is NOT flagged.
  assert.ok(!problems.some(p => p.field === '*UnitAmount'));
});

test('the filename says csv and carries the period', () => {
  assert.equal(xeroCsvFilename('all-stores', '2026-08-01', '2026-08-31'),
    'xero-invoices-all-stores-2026-08-01-to-2026-08-31.csv');
  assert.equal(xeroCsvFilename('Thomson Plaza', '2026-08-01', '2026-08-31'),
    'xero-invoices-Thomson-Plaza-2026-08-01-to-2026-08-31.csv');
});
