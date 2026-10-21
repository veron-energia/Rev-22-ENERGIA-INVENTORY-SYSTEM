// AFTER-6: the invoice export's Payment column.
//
// The export read every matching invoice, then asked for their payment methods
// and read the column from the screen's state, which that request had not
// reached yet: every row not on the screen's page came out blank, and a
// failed batch was blank too. Each exported row now carries its own label from
// the read itself (withPaymentLabels in src/lib/invoices/listPage.ts), and a
// batch that cannot be read stops the export instead of leaving blanks that
// look like "no payment". Run on more rows than one screen page and than one
// batch of 200. Invented ids and names only.
//
// Run: node --test scripts/invoices/tests/export-payment-column.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoices/listPage';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
  plugins: [{ name: 'stub-supabase', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub-supabase', namespace: 'stub' }));
    b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: 'export const supabase = globalThis.__stub;', loader: 'js' }));
  } }],
});

// The module reads the client once, when it loads: it gets one that asks the test's current stub.
let current = null;
globalThis.__stub = { from: (...a) => current.from(...a) };
/** invoice_payments as the API serves it: the rows of the asked invoices, each with its method's name. */
function stub(payments, { failBatch = -1 } = {}) {
  const calls = [];
  current = {
    from(table) {
      assert.equal(table, 'invoice_payments');
      const q = { select: () => q, in: (col, ids) => {
        assert.equal(col, 'invoice_id');
        const batch = calls.length; calls.push(ids.length);
        if (batch === failBatch) return Promise.resolve({ data: null, error: { message: 'timeout (test)' } });
        return Promise.resolve({ data: payments.filter(p => ids.includes(p.invoice_id)), error: null });
      } };
      return q;
    },
  };
  return calls;
}
const { withPaymentLabels, fetchPaymentMethodNames } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const rows = Array.from({ length: 450 }, (_, i) => ({ id: `inv-${i}`, invoice_no: `INV-T-${i}` }));
// Every third invoice unpaid; the others paid by one or two methods, Cash twice on some.
const payments = rows.flatMap((r, i) => i % 3 === 0 ? []
  : i % 3 === 1 ? [{ invoice_id: r.id, payment_methods: { name: 'Cash' } }, { invoice_id: r.id, payment_methods: { name: 'Cash' } }]
  : [{ invoice_id: r.id, payment_methods: { name: 'PayNow' } }, { invoice_id: r.id, payment_methods: { name: 'Card' } }]);

test('every exported row with payments has its Payment value, not only the screen\'s page', async () => {
  const calls = stub(payments);
  const out = await withPaymentLabels(rows);
  assert.equal(out.length, 450);
  assert.deepEqual(calls, [200, 200, 50], 'read in batches of 200');
  for (const [i, r] of out.entries()) {
    const want = i % 3 === 0 ? '' : i % 3 === 1 ? 'Cash' : 'PayNow, Card';
    assert.equal(r.payment_methods_label, want, `${r.invoice_no}`);
  }
  assert.equal(out[0].invoice_no, 'INV-T-0', 'the row itself is kept');
});

test('a batch that cannot be read stops the export, saying how many', async () => {
  stub(payments, { failBatch: 1 });
  await assert.rejects(withPaymentLabels(rows), /The payment methods of 200 invoices could not be read \(timeout \(test\)\)\. Try the export again\./);
  // The list on screen keeps what it had for those rows: they are reported as unread, not as unpaid.
  stub(payments, { failBatch: 0 });
  const res = await fetchPaymentMethodNames(rows.slice(0, 210).map(r => r.id));
  assert.equal(res.failed.length, 200);
  assert.equal(res.names['inv-1'], undefined, 'an unread invoice has no entry');
  assert.deepEqual(res.names['inv-205'], ['Cash'], 'two cash payments read as one Cash');
  assert.deepEqual(res.names['inv-206'], ['PayNow', 'Card']);
  assert.deepEqual(res.names['inv-204'], [], 'read, and no payment');
});

test('the page exports the label each row carries, and clears its progress whatever happens', () => {
  const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
  const exportBlock = page.slice(page.indexOf('fetchAll={async () => {'), page.indexOf("header: 'Status'"));
  assert.match(exportBlock, /return await withPaymentLabels\(all\);/);
  assert.match(exportBlock, /finally \{\s*setExportProgress\(null\);/, 'the progress clears on failure too');
  assert.match(exportBlock, /value: \(i: any\) => i\.payment_methods_label \?\? /);
});
