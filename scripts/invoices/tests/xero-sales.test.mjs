// Offline checks of the actual export loader and row builder. Database, React
// rendering and browser download boundaries are replaced with local fixtures.
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import Papa from 'papaparse';
import { toXeroCsv, XERO_SALES_INVOICE_HEADERS } from '../../../src/lib/xero/salesInvoiceTemplate.mjs';

const bundled = await build({
  entryPoints: ['src/components/XeroExport.tsx'], bundle: true, write: false,
  format: 'esm', platform: 'node', target: 'node22',
  plugins: [{ name: 'offline-export-boundaries', setup(builder) {
    builder.onResolve({ filter: /^(react(?:\/jsx-runtime)?|lucide-react|\.\/ui|\.\.\/lib\/supabase)$/ }, args => ({ path: args.path, namespace: 'fixture' }));
    builder.onLoad({ filter: /.*/, namespace: 'fixture' }, args => ({ loader: 'js', contents:
      args.path.endsWith('supabase') ? 'export const supabase = {};' :
      args.path === './ui' ? 'export const Modal = () => null;' :
      args.path === 'lucide-react' ? 'export const FileSpreadsheet = () => null;' :
      args.path === 'react/jsx-runtime' ? 'export const jsx = () => null; export const jsxs = jsx; export const Fragment = "fragment";' :
      'export default {}; export const useState = () => { throw Error("Rendering is outside this unit test"); };',
    }));
  } }],
});
const { loadXeroSalesEvents, buildXeroSalesRows, xeroSalesDate } = await import(
  `data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`);

const invoice = { id: 'invoice', invoice_no: 'INV-TEST', customer_id: 'customer', store_id: 'store-a', status: 'refunded', business_date: '2026-08-01', total_amount: 50, paid_amount: 1000 };
const customer = { id: 'customer', full_name: 'Tan, "Mei"', email: 'mei@example.invalid', address: '1 Test Road\nUnit 2' };
const event = (event_id, amount, event_kind = 'receipt', sales_date = '2026-08-01', invoice_id = 'invoice') => ({ event_id, invoice_id, amount, event_kind, sales_date });
const data = events => ({ events, invoices: [invoice], customers: [customer] });
const make = events => buildXeroSalesRows(data(events), '1011', 'NONE');
const csvRows = rows => {
  const parsed = Papa.parse(toXeroCsv(rows), { header: true, skipEmptyLines: true });
  assert.deepEqual(parsed.errors, []);
  assert.deepEqual(parsed.meta.fields, XERO_SALES_INVOICE_HEADERS);
  return parsed.data;
};
const cents = value => BigInt(String(value).replace('.', ''));

test('export equals signed external sales events, including held cancelled receipts and overpayments', () => {
  const events = [event('p1', '100.03'), event('p2', '-100.03', 'correction_reversal'),
    event('p3', '80.02', 'correction_replacement'), event('r1', '-20.01', 'refund', '2026-09-10'),
    event('p4', '40.07', 'receipt', '2026-08-03', 'cancelled'), event('wallet-return', 0, 'refund')];
  const result = buildXeroSalesRows({ ...data(events), invoices: [invoice, { ...invoice, id: 'cancelled', invoice_no: 'INV-CANCELLED', status: 'cancelled' }] }, ' 1011 ', ' NONE ');
  assert.equal(result.total, '100.08');
  assert.equal(result.rows.length, 5, 'zero external wallet refunds do not create documents');
  const rows = csvRows(result.rows);
  assert.equal(rows.reduce((sum, row) => sum + cents(row['*UnitAmount']), 0n), 10008n);
  assert.equal(rows[0]['*UnitAmount'], '100.03', 'receipt is not capped at billed50 or derived from wallet-inclusive paid1000');
  assert.ok(rows.every(row => row['*Quantity'] === '1' && row.InventoryItemCode === '' && row.Discount === ''));
  assert.ok(rows.every(row => row['*AccountCode'] === '1011' && row['*TaxType'] === 'NONE'));
  assert.equal(rows[0]['*ContactName'], customer.full_name);
  assert.equal(rows[0].POAddressLine1, customer.address);
});

test('refunds and reversal events have distinct stable credit-note numbers and preserve original references', () => {
  const events = [event('same-uuid', '100.00'), event('same-uuid', '-100.00', 'correction_reversal'),
    event('refund-uuid', '-20.00', 'refund', '2026-09-10')];
  const first = make(events).rows;
  const retry = make(events).rows;
  assert.deepEqual(first, retry);
  assert.equal(new Set(first.map(row => row['*InvoiceNumber'])).size, 3);
  assert.match(first[0]['*InvoiceNumber'], /^INV-TEST-PAY-/);
  assert.match(first[1]['*InvoiceNumber'], /^INV-TEST-REV-/);
  assert.match(first[2]['*InvoiceNumber'], /^INV-TEST-REF-/);
  assert.equal(first[2]['*InvoiceDate'], '10/09/2026');
  assert.equal(first[2]['*DueDate'], '10/09/2026');
  assert.equal(first[0]['*InvoiceDate'], '01/08/2026');
  assert.ok(first.every(row => row.Reference === invoice.invoice_no && row['*Description'].includes(`ENERGIA invoice ID: ${invoice.id}`)));
});

test('decimal cents reconcile without floating-point rounding lines', () => {
  const result = make([event('p1', 0.1), event('p2', 0.2), event('r1', -0.01, 'refund')]);
  assert.equal(result.total, '0.29');
  assert.deepEqual(result.rows.map(row => row['*UnitAmount']), ['0.10', '0.20', '-0.01']);
  assert.throws(() => make([event('bad', 0.001)]), /invalid currency amount/);
});

test('missing or contradictory source data prevents an incomplete or guessed export', () => {
  assert.throws(() => make([event('duplicate', 1), event('duplicate', 1)]), /duplicate event/);
  assert.throws(() => make([event('bad-sign', 1, 'refund')]), /inconsistent payment or refund/);
  assert.throws(() => make([event('missing-invoice', 1, 'receipt', '2026-09-10', 'unknown')]), /original invoice or event reference/);
  assert.throws(() => buildXeroSalesRows({ ...data([event('p1', 1)]), customers: [] }, '1011', 'NONE'), /customer.*could not be loaded/);
  assert.throws(() => buildXeroSalesRows(data([event('p1', 1)]), '', 'NONE'), /AccountCode/);
  assert.throws(() => buildXeroSalesRows({ ...data([event('p1', 1)]), customers: [{ ...customer, full_name: '' }] }, '1011', 'NONE'), /ContactName/);
});

test('date-only values are timezone independent and invalid dates remain pending review', () => {
  const originalTimezone = process.env.TZ;
  try {
    for (const zone of ['America/Los_Angeles', 'Asia/Singapore', 'Pacific/Auckland']) {
      process.env.TZ = zone;
      assert.equal(xeroSalesDate('2026-09-01'), '01/09/2026');
    }
  } finally { if (originalTimezone === undefined) delete process.env.TZ; else process.env.TZ = originalTimezone; }
  for (const invalid of ['', '2026-02-30', '2026-13-01', '2026-09-01T23:00:00Z']) {
    assert.throws(() => xeroSalesDate(invalid), /valid business or refund date/);
  }
});

function mockDatabase(tables, ledger, failTable = '') {
  const calls = [];
  const query = (table, initialRows) => {
    const filters = [], ordering = [];
    let range = [0, 999], columns;
    const q = {
      select(value) { columns = value; return q; },
      in(field, values) { filters.push(['in', field, values]); return q; },
      gte(field, value) { filters.push(['gte', field, value]); return q; },
      lte(field, value) { filters.push(['lte', field, value]); return q; },
      order(field) { ordering.push(field); return q; },
      range(from, to) { range = [from, to]; return q; },
      then(resolve, reject) {
        calls.push({ table, filters, ordering, range, columns });
        let rows = initialRows.filter(row => filters.every(([op, field, value]) => op === 'in' ? value.includes(row[field]) : op === 'gte' ? row[field] >= value : row[field] <= value));
        rows = [...rows].sort((a, b) => {
          for (const field of ordering) { if (a[field] !== b[field]) return a[field] < b[field] ? -1 : 1; }
          return 0;
        });
        return Promise.resolve(table === failTable ? { data: null, error: { message: 'Fixture fetch failed' } }
          : { data: rows.slice(range[0], range[1] + 1), error: null }).then(resolve, reject);
      },
    };
    return q;
  };
  return { calls, rpc(name) { assert.equal(name, 'invoice_sales_ledger'); return query(name, ledger); },
    from(table) { assert.ok(['invoices', 'customers'].includes(table), `unexpected non-ledger export source ${table}`); return query(table, tables[table] || []); } };
}

test('refund-only periods load original invoices by ID without status or invoice-date filtering', async () => {
  const db = mockDatabase({ invoices: [invoice], customers: [customer] }, [event('old-receipt', 100, 'receipt'), event('later-refund', -20, 'refund', '2026-09-10')]);
  const loaded = await loadXeroSalesEvents(db, '2026-09-01', '2026-09-30', 'store-a');
  assert.equal(loaded.events.length, 1);
  assert.equal(loaded.events[0].event_id, 'later-refund');
  assert.equal(buildXeroSalesRows(loaded, '1011', 'NONE').total, '-20.00');
  assert.ok(db.calls.filter(c => c.table === 'invoices').every(c => c.filters.every(([operation, field]) => operation === 'in' && field === 'id')));
});

test('ledger pagination and sorted invoice/customer chunks retain more than 1000 events with store filtering', async () => {
  const invoices = Array.from({ length: 1205 }, (_, i) => ({ ...invoice, id: `inv-${String(i).padStart(4, '0')}`, customer_id: `c-${i}`, store_id: i % 2 ? 'store-a' : 'store-b' }));
  const customers = invoices.map(i => ({ ...customer, id: i.customer_id }));
  const ledger = invoices.map((i, index) => event(`event-${String(index).padStart(4, '0')}`, '0.01', 'receipt', '2026-09-10', i.id)).reverse();
  const db = mockDatabase({ invoices, customers }, ledger);
  const loaded = await loadXeroSalesEvents(db, '2026-09-01', '2026-09-30', 'store-a');
  assert.equal(loaded.events.length, 602);
  assert.equal(loaded.invoices.length, 602);
  assert.equal(loaded.customers.length, 602);
  assert.equal(buildXeroSalesRows(loaded, '1011', 'NONE').total, '6.02');
  assert.deepEqual(db.calls.filter(c => c.table === 'invoice_sales_ledger').map(c => c.range), [[0, 999], [1000, 1999]]);
  assert.ok(db.calls.filter(c => c.table !== 'invoice_sales_ledger').every(c => c.ordering.join() === 'id' && c.filters[0][2].length <= 200));
  assert.equal(db.calls.filter(c => c.table === 'invoices').length, 7);
  assert.equal(db.calls.filter(c => c.table === 'customers').length, 4);
});

test('fetch failures or missing referenced invoices stop export instead of silently skipping records', async () => {
  const ledger = [event('p1', 1)];
  await assert.rejects(loadXeroSalesEvents(mockDatabase({ invoices: [] }, ledger), '2026-08-01', '2026-08-31'), /referenced by the sales report/);
  await assert.rejects(loadXeroSalesEvents(mockDatabase({ invoices: [invoice] }, ledger, 'customers'), '2026-08-01', '2026-08-31'), /Fixture fetch failed/);
});
