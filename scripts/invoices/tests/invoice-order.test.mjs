// The invoice list reads in invoice-number order.
//
// Reported: a single day's invoices came out 0168, 0169, 0172, 0171. The list
// was ordered by business_date and then by id — a uuid — so invoices sharing a
// date fell in random order.
import { build } from 'esbuild';
import assert from 'node:assert/strict';
const built = await build({
  stdin: { contents: `export * from './src/lib/invoices/business';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const lib = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { compareInvoiceNo, byInvoiceNoDesc } = lib;

const order = (list) => [...list].sort(byInvoiceNoDesc).map(i => i.invoice_no);
const nos = (...v) => v.map(invoice_no => ({ invoice_no }));

// The reported case, in the order the screenshot showed it.
assert.deepEqual(
  order(nos('INV-2026-0168', 'INV-2026-0169', 'INV-2026-0172', 'INV-2026-0171')),
  ['INV-2026-0172', 'INV-2026-0171', 'INV-2026-0169', 'INV-2026-0168'],
);

// Ascending is the exact reverse, so the comparator is a true ordering.
assert.deepEqual(
  [...nos('INV-2026-0171', 'INV-2026-0168', 'INV-2026-0172')]
    .sort((a, b) => compareInvoiceNo(a.invoice_no, b.invoice_no)).map(i => i.invoice_no),
  ['INV-2026-0168', 'INV-2026-0171', 'INV-2026-0172'],
);

// Years order by year, not by sequence within it.
assert.deepEqual(
  order(nos('INV-2025-9999', 'INV-2026-0001')),
  ['INV-2026-0001', 'INV-2025-9999'],
);

// The case a plain text sort gets wrong: past 9999 the sequence grows a digit,
// and '1' < '9' would put 10000 before 9999.
assert.deepEqual(
  order(nos('INV-2026-9999', 'INV-2026-10000', 'INV-2026-10001')),
  ['INV-2026-10001', 'INV-2026-10000', 'INV-2026-9999'],
);
assert.ok('INV-2026-10000' < 'INV-2026-9999', 'a plain string sort really does misplace this');

// Exchange invoices keep their own numbering and group away from INV-.
assert.deepEqual(
  order(nos('SG-ADL-EX-INV-2026-00002', 'INV-2026-0172', 'SG-ADL-EX-INV-2026-00010')),
  ['SG-ADL-EX-INV-2026-00010', 'SG-ADL-EX-INV-2026-00002', 'INV-2026-0172'],
);
// Two stores' exchange sequences stay separated by store code.
assert.deepEqual(
  order(nos('SG-VAN-EX-INV-2026-00001', 'SG-ADL-EX-INV-2026-00009')),
  ['SG-VAN-EX-INV-2026-00001', 'SG-ADL-EX-INV-2026-00009'],
);

// Degenerate input must not throw or reorder unpredictably.
assert.equal(compareInvoiceNo('INV-2026-0001', 'INV-2026-0001'), 0);
assert.equal(byInvoiceNoDesc({ invoice_no: null }, { invoice_no: null }), 0);
assert.deepEqual(order([{ invoice_no: 'INV-2026-0001' }, { invoice_no: null }, { invoice_no: undefined }]),
  ['INV-2026-0001', null, undefined]);

// Sorting is stable and idempotent: sorting an already-sorted list changes nothing.
const once = [...nos('INV-2026-0172', 'INV-2026-0168', 'INV-2026-0171')].sort(byInvoiceNoDesc);
assert.deepEqual([...once].sort(byInvoiceNoDesc).map(i => i.invoice_no), once.map(i => i.invoice_no));

console.log('PASS: invoice list orders by invoice number — reported case, both formats, year rollover, padding overflow, per-store exchange sequences, empty values');
