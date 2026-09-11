// loadInvoiceList must return every invoice exactly once, in invoice-number
// order, across PostgREST's 500-row pages.
//
// Paging is only safe when the server order is a TOTAL order. The previous
// order was business_date then id; business_date is nullable and the fallback
// was a uuid, so a page boundary landing inside a group of equal dates could
// repeat or drop rows. invoice_no is NOT NULL and UNIQUE, so it cannot.
import { build } from 'esbuild';
import assert from 'node:assert/strict';

// Stand in for the real Supabase client: a table of invoices that honours
// .order() and .range() the way PostgREST does — ordering invoice_no as TEXT,
// which is deliberately the wrong numeric order past the padding width.
const makeRows = (n) => Array.from({ length: n }, (_, i) => ({
  id: `id-${i}`, invoice_no: `INV-2026-${String(i + 1).padStart(4, '0')}`, deleted_at: null,
}));

function stubClient(rows, calls) {
  return {
    from: () => {
      const state = { asc: true, col: null };
      const api = {
        select: () => api,
        is: () => api,
        order: (col, opts) => { state.col = col; state.asc = opts?.ascending !== false; return api; },
        range: (from, to) => {
          const sorted = [...rows].sort((a, b) =>
            a[state.col] < b[state.col] ? -1 : a[state.col] > b[state.col] ? 1 : 0);
          if (!state.asc) sorted.reverse();
          calls.push({ col: state.col, from, to });
          return Promise.resolve({ data: sorted.slice(from, to + 1), error: null });
        },
      };
      return api;
    },
  };
}

async function loadWith(rows, calls) {
  const built = await build({
    stdin: { contents: `export * from './src/lib/invoices/loadInvoiceList';`, resolveDir: process.cwd(), loader: 'ts' },
    bundle: true, write: false, format: 'esm',
    plugins: [{
      name: 'stub-supabase',
      setup(b) {
        b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub-supabase', namespace: 'stub' }));
        b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({
          contents: 'export const supabase = globalThis.__stub;', loader: 'js',
        }));
      },
    }],
  });
  globalThis.__stub = stubClient(rows, calls);
  const mod = await import('data:text/javascript;base64,'
    + Buffer.from(built.outputFiles[0].text).toString('base64') + `#${rows.length}-${Math.random()}`);
  return mod.loadInvoiceList();
}

// 1203 invoices: three full pages and a short one, crossing the boundary twice.
{
  const calls = [];
  const { data, error } = await loadWith(makeRows(1203), calls);
  assert.equal(error, null);
  assert.equal(data.length, 1203, 'every invoice returned');
  assert.equal(new Set(data.map(i => i.id)).size, 1203, 'no invoice repeated or skipped across pages');
  assert.ok(calls.every(c => c.col === 'invoice_no'), 'paging is ordered by the unique invoice_no');
  assert.equal(data[0].invoice_no, 'INV-2026-1203', 'newest invoice number first');
  assert.equal(data[data.length - 1].invoice_no, 'INV-2026-0001', 'oldest last');
  // Strictly descending the whole way down, not just at the ends.
  for (let i = 1; i < data.length; i++) {
    assert.ok(Number(data[i - 1].invoice_no.slice(-5).replace(/\D/g, ''))
            > Number(data[i].invoice_no.slice(-5).replace(/\D/g, '')),
      `out of order at ${data[i - 1].invoice_no} / ${data[i].invoice_no}`);
  }
}

// Exactly one full page, then an empty one: the loop must still terminate.
{
  const calls = [];
  const { data } = await loadWith(makeRows(500), calls);
  assert.equal(data.length, 500);
  assert.equal(calls.length, 2, 'a full page is followed by one more request');
}

// Past the 4-digit padding, the server's TEXT order is wrong and the client
// sort has to correct it. This is the case the stub reproduces faithfully.
{
  const rows = [
    { id: 'a', invoice_no: 'INV-2026-9999', deleted_at: null },
    { id: 'b', invoice_no: 'INV-2026-10000', deleted_at: null },
    { id: 'c', invoice_no: 'INV-2026-10001', deleted_at: null },
  ];
  const { data } = await loadWith(rows, []);
  assert.deepEqual(data.map(i => i.invoice_no),
    ['INV-2026-10001', 'INV-2026-10000', 'INV-2026-9999'],
    'client sort corrects the server text order past the padding width');
}

// An error on any page is returned, not silently swallowed as a short list.
{
  const failing = { from: () => { const a = { select: () => a, is: () => a, order: () => a,
    range: () => Promise.resolve({ data: null, error: { message: 'permission denied' } }) }; return a; } };
  const built = await build({
    stdin: { contents: `export * from './src/lib/invoices/loadInvoiceList';`, resolveDir: process.cwd(), loader: 'ts' },
    bundle: true, write: false, format: 'esm',
    plugins: [{ name: 's', setup(b) {
      b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 's', namespace: 'stub' }));
      b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: 'export const supabase = globalThis.__stub;', loader: 'js' }));
    } }],
  });
  globalThis.__stub = failing;
  const mod = await import('data:text/javascript;base64,'
    + Buffer.from(built.outputFiles[0].text).toString('base64') + '#err');
  const { data, error } = await mod.loadInvoiceList();
  assert.equal(data, null);
  assert.equal(error.message, 'permission denied');
}

console.log('PASS: 1203 invoices paged with no repeats or gaps, ordered by invoice number, padding overflow corrected, page-boundary termination, errors surfaced');
