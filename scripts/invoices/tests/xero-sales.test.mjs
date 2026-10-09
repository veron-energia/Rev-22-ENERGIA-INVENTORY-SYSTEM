// Offline checks of the actual export loader, row builder and recorder (411).
// Database, React rendering and browser download boundaries are replaced with
// local fixtures. Every name, number and amount is invented.
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import Papa from 'papaparse';
import { toXeroCsv, XERO_SALES_INVOICE_HEADERS } from '../../../src/lib/xero/salesInvoiceTemplate.mjs';

const bundled = await build({
  entryPoints: ['src/components/XeroExport.tsx'], bundle: true, write: false,
  format: 'esm', platform: 'node', target: 'node22',
  plugins: [{ name: 'offline-export-boundaries', setup(builder) {
    builder.onResolve({ filter: /^(react(?:\/jsx-runtime)?|lucide-react|\.\/ui|\.\.\/lib\/supabase|\.\.\/lib\/invoices\/business)$/ }, args => ({ path: args.path, namespace: 'fixture' }));
    builder.onLoad({ filter: /.*/, namespace: 'fixture' }, args => ({ loader: 'js', contents:
      args.path.endsWith('supabase') ? 'export const supabase = {};' :
      args.path.endsWith('business') ? 'export const singaporeToday = () => "2026-10-09";' :
      args.path === './ui' ? 'export const Modal = () => null;' :
      args.path === 'lucide-react' ? 'export const FileSpreadsheet = () => null; export const AlertTriangle = () => null;' :
      args.path === 'react/jsx-runtime' ? 'export const jsx = () => null; export const jsxs = jsx; export const Fragment = "fragment";' :
      'const outside = () => { throw Error("Rendering is outside this unit test"); }; export default {}; export const useState = outside, useEffect = outside, useMemo = outside, useRef = outside;',
    }));
  } }],
});
const { loadXeroSalesExport, buildXeroSalesRows, recordXeroSalesDownload, xeroSalesDate, XeroRecordRefused } = await import(
  `data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`);

const PREFIX = { receipt: 'PAY', correction_replacement: 'ADJ', correction_reversal: 'REV', refund: 'REF' };
const event = (event_id, amount, event_kind = 'receipt', document_date = '2026-08-01', extra = {}) => {
  const e = { event_id, invoice_id: 'invoice-1', invoice_no: 'INV-TEST', store_id: 'store-a', amount, event_kind, document_date,
    customer_id: 'customer-1', contact_name: 'Tan, "Mei"', contact_email: 'mei@sig.invalid', contact_address: '1 Test Road\nUnit 2',
    recorded_at: `${document_date}T02:00:00Z`, ...extra };
  e.document_number = extra.document_number !== undefined ? extra.document_number
    : PREFIX[e.event_kind] ? `${e.invoice_no}-${PREFIX[e.event_kind]}-${String(event_id).replace(/-/g, '')}` : null;
  return e;
};
const make = events => buildXeroSalesRows(events, '1011', 'NONE');
const csvRows = rows => {
  const parsed = Papa.parse(toXeroCsv(rows), { header: true, skipEmptyLines: true });
  assert.deepEqual(parsed.errors, []);
  assert.deepEqual(parsed.meta.fields, XERO_SALES_INVOICE_HEADERS);
  return parsed.data;
};
const cents = value => BigInt(String(value).replace('.', ''));

test('every payment, correction and refund becomes one signed document, whatever the invoice became later', () => {
  const events = [event('p1', '100.03'), event('p2', '-100.03', 'correction_reversal'),
    event('p3', '80.02', 'correction_replacement'), event('r1', '-20.01', 'refund', '2026-09-10'),
    // A payment on an invoice cancelled later, and a refund made on its cancellation.
    event('p4', '40.07', 'receipt', '2026-08-03', { invoice_id: 'cancelled', invoice_no: 'INV-CANCELLED' }),
    event('r2', '-40.07', 'refund', '2026-08-05', { invoice_id: 'cancelled', invoice_no: 'INV-CANCELLED' })];
  const result = buildXeroSalesRows(events, ' 1011 ', ' NONE ');
  assert.equal(result.total, '60.01');
  assert.equal(result.rows.length, 6);
  const rows = csvRows(result.rows);
  assert.equal(rows.reduce((sum, row) => sum + cents(row['*UnitAmount']), 0n), 6001n);
  assert.equal(rows[0]['*UnitAmount'], '100.03');
  assert.ok(rows.every(row => row['*Quantity'] === '1' && row.InventoryItemCode === '' && row.Discount === ''));
  assert.ok(rows.every(row => row['*AccountCode'] === '1011' && row['*TaxType'] === 'NONE'));
  assert.equal(rows[0]['*ContactName'], 'Tan, "Mei"');
  assert.equal(rows[0].POAddressLine1, '1 Test Road\nUnit 2');
  assert.equal(rows[5]['*InvoiceNumber'], 'INV-CANCELLED-REF-r2');
  assert.equal(rows[5].Reference, 'INV-CANCELLED', 'a credit note keeps the original invoice number as its Reference');
  assert.equal(rows[5]['*InvoiceDate'], '05/08/2026');
});

test('document numbers are the ones the page has always written, and the server must agree', () => {
  const uuid = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const rows = make([event(uuid, '100.00'), event(uuid, '-100.00', 'correction_reversal'),
    event(uuid, '90.00', 'correction_replacement'), event('refund-uuid', '-20.00', 'refund', '2026-09-10')]).rows;
  assert.deepEqual(rows.map(r => r['*InvoiceNumber']), [
    'INV-TEST-PAY-0f1e2d3c4b5a69788796a5b4c3d2e1f0', 'INV-TEST-REV-0f1e2d3c4b5a69788796a5b4c3d2e1f0',
    'INV-TEST-ADJ-0f1e2d3c4b5a69788796a5b4c3d2e1f0', 'INV-TEST-REF-refunduuid']);
  assert.deepEqual(make([event(uuid, '100.00')]).rows, make([event(uuid, '100.00')]).rows, 'stable on a retry');
  assert.equal(rows[3]['*InvoiceDate'], '10/09/2026');
  assert.equal(rows[3]['*DueDate'], '10/09/2026');
  assert.ok(rows.every(row => row.Reference === 'INV-TEST' && row['*Description'].includes('ENERGIA invoice ID: invoice-1')));
  assert.throws(() => make([event(uuid, '100.00', 'receipt', '2026-08-01', { document_number: 'INV-TEST-PAY-other' })]), /Xero number .* not the expected one/);
});

test('decimal cents reconcile without floating-point rounding lines', () => {
  const result = make([event('p1', 0.1), event('p2', 0.2), event('r1', -0.01, 'refund')]);
  assert.equal(result.total, '0.29');
  assert.deepEqual(result.rows.map(row => row['*UnitAmount']), ['0.10', '0.20', '-0.01']);
  assert.throws(() => make([event('bad', 0.001)]), /invalid currency amount/);
});

test('missing, contradictory or unexportable source data stops the export instead of guessing', () => {
  assert.throws(() => make([event('duplicate', 1), event('duplicate', 1)]), /duplicate event/);
  assert.throws(() => make([event('bad-sign', 1, 'refund')]), /inconsistent payment or refund/);
  assert.throws(() => make([event('bad-sign', -1, 'receipt')]), /inconsistent payment or refund/);
  assert.throws(() => make([event('no-invoice', 1, 'receipt', '2026-08-01', { invoice_no: null })]), /original invoice or event reference/);
  assert.throws(() => make([event('unsourced', -40, 'refund_unsourced', '2026-09-06')]), /recorded without the payment it returned/);
  assert.throws(() => make([event('legacy', 100, 'legacy_refund_left_out')]), /kind the export does not know/);
  assert.throws(() => make([event('odd', 100, 'something_new')]), /kind the export does not know/);
  assert.throws(() => make([event('p1', 1, 'receipt', '2026-08-01', { contact_name: null })]), /customer for invoice INV-TEST could not be found/);
  assert.throws(() => buildXeroSalesRows([event('p1', 1)], '', 'NONE'), /AccountCode/);
  assert.throws(() => make([event('p1', 1, 'receipt', '2026-08-01', { contact_name: '' })]), /ContactName/);
  // A walk-in sale has no customer: its contact says so.
  assert.equal(make([event('walk', 5, 'receipt', '2026-08-01', { customer_id: null, contact_name: null })]).rows[0]['*ContactName'], 'Walk-in customer');
  // Nothing came in or went back: no document.
  assert.equal(make([event('zero', '0.00', 'refund')]).rows.length, 0);
});

test('date-only values are timezone independent and invalid dates stop the export', () => {
  const originalTimezone = process.env.TZ;
  try {
    for (const zone of ['America/Los_Angeles', 'Asia/Singapore', 'Pacific/Auckland']) {
      process.env.TZ = zone;
      assert.equal(xeroSalesDate('2026-09-01'), '01/09/2026');
    }
  } finally { if (originalTimezone === undefined) delete process.env.TZ; else process.env.TZ = originalTimezone; }
  for (const invalid of ['', '2026-02-30', '2026-13-01', '2026-09-01T23:00:00Z']) {
    assert.throws(() => xeroSalesDate(invalid), /valid payment or refund date/);
  }
});

function mockDatabase(events, review, fail = '', failCode = undefined) {
  const calls = [];
  const query = (name, args, rows) => {
    const ordering = [];
    let range = null;
    const q = {
      order(field) { ordering.push(field); return q; },
      range(from, to) { range = [from, to]; return q; },
      then(resolve, reject) {
        calls.push({ name, args, ordering, range });
        if (name === fail) return Promise.resolve({ data: null, error: { message: 'Fixture call failed', ...(failCode !== undefined ? { code: failCode } : {}) } }).then(resolve, reject);
        if (!Array.isArray(rows)) return Promise.resolve({ data: rows, error: null }).then(resolve, reject);
        const sorted = [...rows].sort((a, b) => {
          for (const field of ordering) { if (a[field] !== b[field]) return a[field] < b[field] ? -1 : 1; }
          return 0;
        });
        return Promise.resolve({ data: range ? sorted.slice(range[0], range[1] + 1) : sorted, error: null }).then(resolve, reject);
      },
    };
    return q;
  };
  return {
    calls,
    rpc(name, args) {
      assert.ok(['xero_sales_events', 'xero_sales_export_review', 'record_xero_sales_export'].includes(name), `unexpected rpc ${name}`);
      return query(name, args, name === 'xero_sales_events' ? events : name === 'xero_sales_export_review' ? review : { export_id: 'x-1', exported_at: '2026-10-09T02:00:00Z', document_count: 1, net_total: 1 });
    },
    from(table) { throw new Error(`the export reads no table directly (asked for ${table})`); },
  };
}
const emptyReview = { recorded_since: null, exports: [], downloads: [], vanished: [], missed: [] };

test('the loader asks the server for the dates and store, pages past 1000 documents, and reads the review', async () => {
  const events = Array.from({ length: 1205 }, (_, i) => event(`e-${String(i).padStart(4, '0')}`, '0.01', 'receipt', '2026-09-10')).reverse();
  const db = mockDatabase(events, emptyReview);
  const loaded = await loadXeroSalesExport(db, '2026-09-01', '2026-09-30', 'store-a');
  assert.equal(loaded.events.length, 1205);
  assert.equal(loaded.events[0].event_id, 'e-0000', 'ordered as the server orders them');
  assert.deepEqual(loaded.review, emptyReview);
  const pages = db.calls.filter(c => c.name === 'xero_sales_events');
  assert.deepEqual(pages.map(c => c.range), [[0, 999], [1000, 1999]]);
  assert.ok(pages.every(c => c.ordering.join() === 'document_date,event_id,event_kind'));
  assert.ok(db.calls.every(c => c.name === 'record_xero_sales_export'
    || JSON.stringify(c.args) === JSON.stringify({ p_from: '2026-09-01', p_to: '2026-09-30', p_store_id: 'store-a' })));
  assert.equal(buildXeroSalesRows(loaded.events, '1011', 'NONE').total, '12.05');
  // All stores is sent as no store, not as an empty id.
  const all = mockDatabase([], emptyReview);
  await loadXeroSalesExport(all, '2026-09-01', '2026-09-30', '');
  assert.ok(all.calls.every(c => c.args.p_store_id === null));
});

test('a failed read stops the export instead of silently skipping documents', async () => {
  await assert.rejects(loadXeroSalesExport(mockDatabase([event('p1', 1)], emptyReview, 'xero_sales_events'), '2026-08-01', '2026-08-31'), /Fixture call failed/);
  await assert.rejects(loadXeroSalesExport(mockDatabase([event('p1', 1)], emptyReview, 'xero_sales_export_review'), '2026-08-01', '2026-08-31'), /Fixture call failed/);
});

test('the recorder sends exactly the documents of the file, with the request ID', async () => {
  const db = mockDatabase([], emptyReview);
  const docs = [event('p1', '100.00'), event('r1', '-20.00', 'refund', '2026-09-10')];
  const result = await recordXeroSalesDownload(db, '2026-09-01', '2026-09-30', '', docs, 'req-1');
  assert.equal(result.export_id, 'x-1');
  const [call] = db.calls;
  assert.equal(call.name, 'record_xero_sales_export');
  assert.deepEqual(call.args, { p_from: '2026-09-01', p_to: '2026-09-30', p_store_id: null, p_request_id: 'req-1',
    p_documents: [
      { event_kind: 'receipt', event_id: 'p1', document_number: 'INV-TEST-PAY-p1', document_date: '2026-08-01', amount: '100.00' },
      { event_kind: 'refund', event_id: 'r1', document_number: 'INV-TEST-REF-r1', document_date: '2026-09-10', amount: '-20.00' }] });
  await assert.rejects(recordXeroSalesDownload(mockDatabase([], emptyReview, 'record_xero_sales_export'), '2026-09-01', '2026-09-30', '', docs, 'req-2'), /Fixture call failed/);
});

test('documents asked for again are marked "redownload"; no other document is', async () => {
  const db = mockDatabase([], emptyReview);
  const docs = [event('p1', '100.00'), event('p2', '50.00'), event('r1', '-20.00', 'refund', '2026-09-10')];
  await recordXeroSalesDownload(db, '2026-09-01', '2026-09-30', 'store-a', docs, 'req-3', new Set(['receipt:p2']));
  assert.deepEqual(db.calls[0].args.p_documents.map(d => [d.event_id, d.redownload]),
    [['p1', undefined], ['p2', true], ['r1', undefined]]);
  assert.ok(!('redownload' in db.calls[0].args.p_documents[0]), 'the field is sent only when asked for');
});

test('a record the database refused (a SQLSTATE) is told apart from one that got no answer', async () => {
  const docs = [event('p1', '100.00')];
  for (const code of ['P0001', '42501', '57014']) {
    const error = await recordXeroSalesDownload(mockDatabase([], emptyReview, 'record_xero_sales_export', code),
      '2026-09-01', '2026-09-30', '', docs, 'req-4').catch(e => e);
    assert.ok(error instanceof XeroRecordRefused, `${code}: refused, so nothing was recorded`);
    assert.equal(error.message, 'Fixture call failed');
  }
  // No answer from the database: it may have recorded, so the caller retries the same request.
  for (const code of [undefined, '', 'PGRST301']) {
    const error = await recordXeroSalesDownload(mockDatabase([], emptyReview, 'record_xero_sales_export', code),
      '2026-09-01', '2026-09-30', '', docs, 'req-5').catch(e => e);
    assert.ok(error instanceof Error && !(error instanceof XeroRecordRefused), `${String(code)}: not known to be refused`);
  }
});
