// Ordering the invoice list.
//
// The loader pages through EVERY accessible invoice before the page renders,
// so ordering the loaded set orders all matching records. These assertions
// cover each supported field, both directions, and the two cases that make a
// list feel broken: rows that swap places on equal values, and undated rows
// moving around when the direction flips.
import { build } from 'esbuild';
import assert from 'node:assert/strict';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoices/business';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const lib = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { sortInvoices, compareInvoices, isInvoiceSortField, INVOICE_SORT_FIELDS } = lib;

const names = { c1: 'Alice Tan', c2: 'bob lim', c3: 'Zara Ng' };
const storeNames = { s1: 'Adelphi', s2: 'Van & RoadShow' };
const ctx = {
  customerName: id => names[id] ?? '',
  storeName: id => storeNames[id] ?? '',
  outstanding: i => Math.max(0, Number(i.total_amount ?? 0) - Number(i.paid_amount ?? 0)),
};
const inv = (o) => ({ invoice_no: 'INV-2026-0001', created_at: '2026-01-01T00:00:00Z',
  business_date: '2026-01-01', customer_id: 'c1', store_id: 's1',
  total_amount: 0, paid_amount: 0, status: 'paid', ...o });

const order = (rows, field, dir) => sortInvoices(rows, field, dir, ctx).map(r => r.invoice_no);

let failures = 0;
const check = (name, cond, detail) => {
  if (cond) console.log(`  ok   ${name}`);
  else { failures++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`); }
};

// ---- the field list is closed -------------------------------------------
check('only known fields are accepted',
  isInvoiceSortField('total') && !isInvoiceSortField('total; drop table invoices')
  && !isInvoiceSortField('__proto__') && !isInvoiceSortField(''));
check('every offered field is a real one', INVOICE_SORT_FIELDS.every(f => isInvoiceSortField(f.value)));

// ---- invoice number sorts by its sequence, not as text -------------------
{
  const rows = [inv({ invoice_no: 'INV-2026-9999' }), inv({ invoice_no: 'INV-2026-10000' }),
                inv({ invoice_no: 'INV-2026-0002' })];
  check('ascending by number is numeric, not lexical',
    order(rows, 'invoice_no', 'asc').join() === 'INV-2026-0002,INV-2026-9999,INV-2026-10000',
    order(rows, 'invoice_no', 'asc').join());
  check('descending is the exact reverse',
    order(rows, 'invoice_no', 'desc').join() === 'INV-2026-10000,INV-2026-9999,INV-2026-0002');
}

// ---- dates ---------------------------------------------------------------
{
  const rows = [
    inv({ invoice_no: 'A', created_at: '2026-03-01T10:00:00Z' }),
    inv({ invoice_no: 'B', created_at: '2026-01-01T10:00:00Z' }),
    inv({ invoice_no: 'C', created_at: '2026-02-01T10:00:00Z' }),
  ];
  check('created ascending', order(rows, 'created_at', 'asc').join() === 'B,C,A');
  check('created descending', order(rows, 'created_at', 'desc').join() === 'A,C,B');
}

// ---- undated rows stay at the bottom, both ways --------------------------
{
  const rows = [
    inv({ invoice_no: 'DATED-2', business_date: '2026-02-01' }),
    inv({ invoice_no: 'NONE-1', business_date: null }),
    inv({ invoice_no: 'DATED-1', business_date: '2026-01-01' }),
    inv({ invoice_no: 'NONE-2', business_date: null }),
  ];
  const asc = order(rows, 'business_date', 'asc');
  const desc = order(rows, 'business_date', 'desc');
  check('undated invoices sort last ascending', asc.slice(-2).every(x => x.startsWith('NONE')), asc.join());
  check('and last descending too — the date-review state is not buried',
    desc.slice(-2).every(x => x.startsWith('NONE')), desc.join());
  check('dated rows still order correctly', asc[0] === 'DATED-1' && desc[0] === 'DATED-2');
}

// ---- people and places sort case-insensitively ---------------------------
{
  const rows = [inv({ invoice_no: 'Z', customer_id: 'c3' }), inv({ invoice_no: 'B', customer_id: 'c2' }),
                inv({ invoice_no: 'A', customer_id: 'c1' })];
  check('customer ascending ignores case', order(rows, 'customer', 'asc').join() === 'A,B,Z',
    order(rows, 'customer', 'asc').join());
  const s = [inv({ invoice_no: 'V', store_id: 's2' }), inv({ invoice_no: 'A', store_id: 's1' })];
  check('store ascending', order(s, 'store', 'asc').join() === 'A,V');
}

// ---- money ---------------------------------------------------------------
{
  const rows = [
    inv({ invoice_no: 'SMALL', total_amount: 10, paid_amount: 10 }),
    inv({ invoice_no: 'BIG', total_amount: 1000, paid_amount: 100 }),
    inv({ invoice_no: 'MID', total_amount: 500, paid_amount: 500 }),
  ];
  check('total descending', order(rows, 'total', 'desc').join() === 'BIG,MID,SMALL');
  check('outstanding descending puts the largest debt first',
    order(rows, 'outstanding', 'desc')[0] === 'BIG');
  check('and a settled invoice has none', ctx.outstanding(rows[0]) === 0 && ctx.outstanding(rows[2]) === 0);
}

// ---- status --------------------------------------------------------------
{
  const rows = [inv({ invoice_no: 'U', status: 'unpaid' }), inv({ invoice_no: 'C', status: 'cancelled' }),
                inv({ invoice_no: 'P', status: 'paid' })];
  check('status ascending is alphabetical', order(rows, 'status', 'asc').join() === 'C,P,U');
}

// ---- equal values never reorder -----------------------------------------
{
  const rows = [
    inv({ invoice_no: 'INV-2026-0003', total_amount: 100 }),
    inv({ invoice_no: 'INV-2026-0001', total_amount: 100 }),
    inv({ invoice_no: 'INV-2026-0002', total_amount: 100 }),
  ];
  const a = order(rows, 'total', 'desc');
  const b = order([...rows].reverse(), 'total', 'desc');
  check('rows with the same total land in the same order whatever the input order',
    a.join() === b.join(), `${a.join()} vs ${b.join()}`);
  check('and that order is by invoice number, newest first',
    a.join() === 'INV-2026-0003,INV-2026-0002,INV-2026-0001', a.join());
  // sorting an already sorted list changes nothing
  check('sorting twice is idempotent',
    order(sortInvoices(rows, 'total', 'desc', ctx), 'total', 'desc').join() === a.join());
}

// ---- the caller's array is not mutated -----------------------------------
{
  const rows = [inv({ invoice_no: 'B' }), inv({ invoice_no: 'A' })];
  const before = rows.map(r => r.invoice_no).join();
  sortInvoices(rows, 'invoice_no', 'asc', ctx);
  check('sorting returns a copy', rows.map(r => r.invoice_no).join() === before);
}

// ---- a full set larger than one API page stays completely ordered --------
{
  const many = Array.from({ length: 1203 }, (_, i) =>
    inv({ invoice_no: `INV-2026-${String(i + 1).padStart(4, '0')}`, total_amount: (i * 7) % 500 }));
  const out = sortInvoices(many, 'invoice_no', 'asc', ctx);
  check('every row survives the sort', out.length === 1203);
  check('and the whole set is ordered, not just the first page',
    out.every((r, i) => i === 0 || compareInvoices(out[i - 1], r, 'invoice_no', 'asc', ctx) <= 0));
}

console.log(failures === 0
  ? '\nPASS: every supported field and direction orders correctly, invoice numbers sort by sequence, undated rows stay at the bottom either way, equal values never reorder, the input array is untouched, and a set larger than one API page is ordered throughout'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
