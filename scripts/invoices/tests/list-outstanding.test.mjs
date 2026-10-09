// 409: the Invoices list's Outstanding owes nothing on a cancelled, refunded
// or FOC invoice.
//
// It was total minus paid for every status, so a cancelled S$14,000 sale
// showed S$14,000 owed while the invoice itself said 0; on production
// (9 Oct 2026) the list showed S$59,039.50 outstanding against S$18,916.50
// real. invoice_list_page now applies the rule (its SQL test is
// scripts/invoice-actions/tests/refund-requests-and-refund-due.sql); the row
// cell and the Excel export apply the same rule here, and the summary says
// how much of the total is cancelled or refunded.
import { build } from 'esbuild';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const bundle = async (contents, plugins = []) => {
  const built = await build({ stdin: { contents, resolveDir: process.cwd(), loader: 'ts' },
    bundle: true, write: false, format: 'esm', plugins });
  return import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
};
const { invoiceListOutstanding, OWES_NOTHING_STATUSES } = await bundle(`export * from './src/lib/invoices/business';`);

// ---- the rule ---------------------------------------------------------------
const row = (status, total, paid) => ({ status, total_amount: total, paid_amount: paid });
assert.equal(invoiceListOutstanding(row('cancelled', 15000, 1000)), 0, 'a cancelled sale owes nothing');
assert.equal(invoiceListOutstanding(row('refunded', 10000, 0)), 0, 'a refunded sale owes nothing');
assert.equal(invoiceListOutstanding(row('completed_foc', 0, 0)), 0, 'an FOC invoice owes nothing');
assert.equal(invoiceListOutstanding(row('unpaid', 100, 0)), 100);
assert.equal(invoiceListOutstanding(row('partially_paid', 300, 120)), 180);
assert.equal(invoiceListOutstanding(row('paid', 100, 100)), 0);
assert.equal(invoiceListOutstanding(row('paid', 100, 120)), 0, 'an overpayment is not a negative balance');
assert.equal(invoiceListOutstanding(row('draft', '250.50', null)), 250.5, 'numbers arrive as strings from PostgREST');
// A request still waiting is not a decision: the money is still owed.
assert.equal(invoiceListOutstanding(row('cancellation_requested', 100, 40)), 60);
// 409 review: the row's own figure from invoice_list_page (what it still
// charges less what it holds) is used for an open invoice, so a part refund
// is not shown as owed: S$200 paid, S$100 of it refunded, holds S$100.
const listed = (status, total, paid, outstanding) => ({ ...row(status, total, paid), outstanding });
assert.equal(invoiceListOutstanding(listed('paid', 200, 100, '0.00')), 0, 'a part refund is not owed');
assert.equal(invoiceListOutstanding(listed('partially_paid', 300, 150, 50)), 50);
assert.equal(invoiceListOutstanding(listed('cancelled', 500, 40, 460)), 0, 'a closed invoice owes nothing whatever the row says');
assert.equal(invoiceListOutstanding(listed('unpaid', 100, 0, null)), 100, 'without the figure, total less held');
assert.equal(invoiceListOutstanding(listed('unpaid', 100, 0, '')), 100);
assert.equal(invoiceListOutstanding(listed('paid', 100, 120, -20)), 0, 'never negative');
assert.deepEqual([...OWES_NOTHING_STATUSES].sort(), ['cancelled', 'completed_foc', 'refunded']);

// ---- the same rule as the database's ---------------------------------------
const sql = readFileSync('supabase/409_refund_requests_refund_due_customer_order.sql', 'utf8');
assert.ok(sql.includes("case when i.status in (''cancelled'',''refunded'',''completed_foc'') then 0::numeric"),
  'invoice_list_page names the same three statuses');
assert.ok(sql.includes("else greatest(public.invoice_charge_total(i.id) - coalesce(i.paid_amount,0), 0) end as outstanding"),
  'and owes what it still charges less what it holds, as the invoice does');

// ---- the page uses it: the row cell, the export, the summary --------------
const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
assert.ok(page.includes('{money(invoiceListOutstanding(inv))}'), 'the row cell shows the rule');
assert.ok(!page.includes('money(Math.max(0, Number(inv.total_amount ?? 0) - Number(inv.paid_amount ?? 0)))'),
  'total minus paid is gone from the row');
assert.ok(page.includes("{ header: 'Outstanding', value: (i: any) => invoiceListOutstanding(i) }"),
  'the export carries the same Outstanding as the table');
assert.ok(page.includes('of it cancelled or refunded'), 'the summary says how much of the total is cancelled or refunded');

// ---- the summary's new figures come through, and their absence is harmless --
const stubbed = summary => [{ name: 'stub', setup(b) {
  b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 'st' }));
  b.onLoad({ filter: /.*/, namespace: 'st' }, () => ({ loader: 'js', contents:
    `export const supabase = { rpc: async () => ({ data: { rows: [], total: 4, pages: 1, limit: 25,
       summary: ${JSON.stringify(summary)} }, error: null }) };` }));
} }];
const q = { search: '', status: 'all', dateMode: 'all', dateFrom: '', dateTo: '', storeId: '', sortField: 'created_at',
  sortDir: 'desc', pageSize: 25, page: 1 };
const withClosed = await bundle(`export * from './src/lib/invoices/listPage';`,
  stubbed({ matching: 4, total_amount: '1100.00', outstanding: '280.00', paid: '160.00', closed_total: '700.00', closed_count: 2 }));
const r1 = await withClosed.fetchInvoicePage(q);
assert.deepEqual(r1.summary, { matching: 4, total_amount: 1100, outstanding: 280, paid: 160, closed_total: 700, closed_count: 2 });
const without = await bundle(`export * from './src/lib/invoices/listPage';`,
  stubbed({ matching: 4, total_amount: 1100, outstanding: 280, paid: 160 }));
const r2 = await without.fetchInvoicePage(q);
assert.deepEqual(r2.summary, { matching: 4, total_amount: 1100, outstanding: 280, paid: 160 },
  'a database without 409 sends no closed total, and the page shows none');

console.log('PASS: the list owes nothing on cancelled, refunded and FOC invoices (row, export, database alike); the summary carries the cancelled-or-refunded total when the database sends it');
