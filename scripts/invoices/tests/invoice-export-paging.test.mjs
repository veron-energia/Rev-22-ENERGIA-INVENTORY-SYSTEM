// An export must contain every invoice the filter matched.
//
// invoice_list_page clamps its page size to 200 and reports back the limit it
// actually used. The export asked for 500 a page and then advanced the OFFSET
// by 500, so on every round it skipped the rows between 200 and 500 — an
// export of 1,000 matching invoices silently contained 400 of them, in the
// right order, with no error and a plausible-looking file.
//
// The stub below reproduces the clamp, so this test fails against the old
// page-arithmetic and passes against paging by what the server returned.
import { build } from 'esbuild';
import assert from 'node:assert/strict';

const SERVER_MAX = 200;   // least(greatest(coalesce(p_limit,25),1),200) in 324_invoice_list_pagination.sql

// Stand in for supabase.rpc('invoice_list_page', …): a table of invoices
// served through the same clamp the real function applies.
function stubClient(total, calls) {
  const rows = Array.from({ length: total }, (_, i) => ({
    id: `id-${i}`, invoice_no: `INV-2026-${String(i + 1).padStart(4, '0')}`,
  }));
  return {
    rpc: (fn, args) => {
      assert.equal(fn, 'invoice_list_page');
      const limit = Math.min(Math.max(args.p_limit ?? 25, 1), SERVER_MAX);
      const offset = args.p_offset ?? 0;
      calls.push({ asked: args.p_limit, limit, offset });
      return Promise.resolve({
        data: {
          rows: rows.slice(offset, offset + limit),
          total, limit,
          pages: Math.ceil(total / limit),
          summary: { matching: total, total_amount: 0, outstanding: 0, paid: 0 },
        },
        error: null,
      });
    },
  };
}

async function exportAll(total, calls) {
  const built = await build({
    stdin: { contents: `export * from './src/lib/invoices/listPage';`, resolveDir: process.cwd(), loader: 'ts' },
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
  globalThis.__stub = stubClient(total, calls);
  const mod = await import('data:text/javascript;base64,'
    + Buffer.from(built.outputFiles[0].text).toString('base64') + `#${total}-${Math.random()}`);
  const q = {
    search: '', status: 'all', dateMode: 'all', dateFrom: '', dateTo: '',
    storeId: '', sortField: 'invoice_no', sortDir: 'desc',
  };
  const progress = [];
  const out = await mod.fetchAllMatchingInvoices(q, (fetched, t) => progress.push([fetched, t]));
  return { out, progress };
}

// 1,000 matching invoices: five clamped windows, and the boundary crossed four
// times. This is the case the old code turned into 400 rows.
{
  const calls = [];
  const { out, progress } = await exportAll(1000, calls);
  assert.equal(out.length, 1000, 'every matching invoice is in the export');
  assert.equal(new Set(out.map(r => r.id)).size, 1000, 'no invoice repeated or skipped');
  assert.equal(out[0].invoice_no, 'INV-2026-0001', 'server order preserved');
  assert.equal(out[999].invoice_no, 'INV-2026-1000');
  // Offsets must step by what the server returned, never by what was asked for.
  const steps = calls.map(c => c.offset);
  assert.deepEqual(steps, [0, 200, 400, 600, 800], 'paged by the effective limit');
  assert.ok(calls.every(c => c.asked <= SERVER_MAX), 'never asks for more than the server will give');
  assert.deepEqual(progress[progress.length - 1], [1000, 1000], 'progress ends at the true total');
}

// A short last page, and a total that is an exact multiple, both terminate.
for (const total of [1, 199, 200, 201, 400, 587]) {
  const calls = [];
  const { out } = await exportAll(total, calls);
  assert.equal(out.length, total, `${total} matching invoices exported`);
  assert.equal(new Set(out.map(r => r.id)).size, total, `${total}: no duplicates`);
  assert.ok(calls.length <= Math.ceil(total / SERVER_MAX) + 1, `${total}: no wasted round trips`);
}

// An empty result is an empty file, not a loop.
{
  const calls = [];
  const { out } = await exportAll(0, calls);
  assert.equal(out.length, 0);
  assert.equal(calls.length, 1, 'one request, then stop');
}

console.log('PASS: the export returns every matching invoice exactly once, paged by the limit the database applied');
