import { build } from 'esbuild';
import assert from 'node:assert/strict';
const built = await build({ stdin: { contents: `export * from './src/lib/calendarDates'; export * from './src/lib/invoices/business';`, resolveDir: process.cwd(), loader: 'ts' }, bundle: true, write: false, format: 'esm' });
const dates = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
for (const zone of ['Asia/Singapore', 'UTC', 'America/Los_Angeles', 'Pacific/Honolulu']) {
  assert.equal(dates.calendarDate('2020-02-01', zone), '2020-02-01');
  assert.equal(dates.calendarDateInRange('2020-02-01', '2020-02-01', '2020-02-01', zone), true);
  assert.equal(dates.calendarDateInRange(null, '2020-02-01', '', zone), false);
}
assert.equal(dates.calendarDate('2020-01-31T16:00:00Z', 'Asia/Singapore'), '2020-02-01');
assert.equal(dates.calendarDate('2020-01-31T15:59:59Z', 'Asia/Singapore'), '2020-01-31');
assert.equal(dates.calendarDate('2020-02-30'), '');
assert.equal(dates.displayInvoiceDate({ business_date: null, created_at: '2020-01-01' }), 'Date pending review');
assert.equal(dates.invoiceCreatedOn({ created_at: '2020-01-31T16:00:00Z' }), '01/02/2020');
assert.equal(dates.displayInvoiceDate({ business_date: '2019-12-01' }), '01/12/2019');
assert.ok(dates.invoiceDateSearch({ business_date: '2019-12-01' }).includes('01 Dec 2019'));
assert.equal(dates.singaporeToday(), new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date()));
console.log('PASS: date-only values/ranges across four time zones, SG midnight, invalid dates, separate creation reference, search and today default');
