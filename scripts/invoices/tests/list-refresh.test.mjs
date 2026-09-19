/**
 * The traffic control around refreshing the invoice list (src/lib/invoices/listRefresh.ts).
 *
 * The list itself is a server query; these are the parts that decide when to
 * run it and whose answer may be written: one refresh in flight with one
 * queued, per-invoice ordering for labels, event bursts collected into one
 * signal, and where the viewer lands when their page disappears.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/invoices/listRefresh';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const mod = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { createRefreshQueue, createStampedWriter, invoiceIdsFromChange, createChangeCollector, refreshCovers, pageAfterRefresh, announcedMatchesShown } = mod;

const tick = () => new Promise(r => setTimeout(r, 0));

test('overlapping refresh requests run once now and once after, never in parallel', async () => {
  let running = 0, maxRunning = 0, runs = 0;
  let release;
  const q = createRefreshQueue(async () => {
    runs++; running++; maxRunning = Math.max(maxRunning, running);
    await new Promise(r => { release = r; });
    running--;
  });
  const a = q.request();               // starts run 1
  await tick();
  const b = q.request();               // queued behind run 1
  const c = q.request();               // coalesced with b
  assert.equal(runs, 1); assert.ok(q.busy());
  release(); await tick(); await tick(); // run 1 done → run 2 starts (for b and c)
  assert.equal(runs, 2);
  release(); await Promise.all([a, b, c]);
  assert.equal(runs, 2, 'three requests, two runs');
  assert.equal(maxRunning, 1, 'never two at once');
  assert.ok(!q.busy());
});

test('a request made after the queue drained starts a fresh run', async () => {
  let runs = 0;
  const q = createRefreshQueue(async () => { runs++; });
  await q.request(); await q.request();
  assert.equal(runs, 2);
});

test('a failing run does not wedge the queue', async () => {
  let n = 0;
  const q = createRefreshQueue(async () => { if (++n === 1) throw new Error('boom'); });
  await assert.rejects(q.request());
  await q.request();
  assert.equal(n, 2); assert.ok(!q.busy());
});

test('an older label response cannot overwrite a newer one for the same invoice', () => {
  const w = createStampedWriter();
  const first = w.stamp(['a', 'b']);
  const second = w.stamp(['b', 'c']);
  assert.ok(w.accepts('a', first), 'a: only the first request claimed it');
  assert.ok(!w.accepts('b', first), 'b: the second request claimed it since');
  assert.ok(w.accepts('b', second));
  assert.ok(w.accepts('c', second));
  assert.ok(!w.accepts('d', second), 'a key nobody stamped is never written');
});

test('ids are read from invoice rows and from payment rows, new and old', () => {
  assert.deepEqual(invoiceIdsFromChange('invoices', { new: { id: 'i1' }, old: { id: 'i1' } }), ['i1']);
  assert.deepEqual(invoiceIdsFromChange('invoices', { new: null, old: { id: 'i2' } }), ['i2']);
  assert.deepEqual(invoiceIdsFromChange('invoice_payments', { new: { id: 'p1', invoice_id: 'i3' } }), ['i3']);
  assert.deepEqual(invoiceIdsFromChange('invoice_payments', { old: { id: 'p1' } }), [], 'a payment old-record without invoice_id names no invoice');
  assert.deepEqual(invoiceIdsFromChange('invoices', null), []);
});

test('a burst of events is delivered once, with every id and the time of the first', () => {
  let now = 1000; const timers = [];
  const delivered = [];
  const c = createChangeCollector(400, b => delivered.push(b), () => now,
    fn => { timers.push(fn); return timers.length; }, () => {});
  c.push(['a'], { a: { id: 'a', status: 'unpaid' } }); now = 1100; c.push(['b', 'a'], { a: { id: 'a', status: 'paid' } }); now = 1300; c.push([]);
  assert.equal(timers.length, 1, 'one timer for the burst');
  assert.deepEqual(delivered, []);
  timers[0]();
  assert.deepEqual(delivered, [{ ids: ['a', 'b'], firstAt: 1000, rows: { a: { id: 'a', status: 'paid' } } }], 'the latest announced row per id travels with the burst');
  // The next burst starts clean.
  now = 5000; c.push(['z']); timers[1]();
  assert.deepEqual(delivered[1], { ids: ['z'], firstAt: 5000, rows: {} });
});

test('cancel drops a pending burst', () => {
  const delivered = []; const timers = []; let cancelled = 0;
  const c = createChangeCollector(400, b => delivered.push(b), () => 1, fn => { timers.push(fn); return 1; }, () => { cancelled++; });
  c.push(['a']); c.cancel();
  assert.equal(cancelled, 1); assert.ok(!c.pending());
});

test('a refresh covers a change only if it started at or after the change was first seen', () => {
  assert.ok(refreshCovers(1000, 1000));
  assert.ok(refreshCovers(1500, 1000));
  assert.ok(!refreshCovers(900, 1000));
  assert.ok(!refreshCovers(0, 1000), 'nothing loaded yet covers nothing');
});

test('the viewer lands on a page that exists', () => {
  assert.equal(pageAfterRefresh(3, 3, 60), 3, 'still there');
  assert.equal(pageAfterRefresh(3, 2, 40), 2, 'the last row on page 3 left: step back');
  assert.equal(pageAfterRefresh(5, 1, 3), 1);
  assert.equal(pageAfterRefresh(2, 0, 0), 1, 'nothing at all: page one');
  assert.equal(pageAfterRefresh(1, 0, 0), 1);
  assert.equal(pageAfterRefresh(0, 4, 90), 1, 'never below one');
});

test('an announced row is news only where it differs from the row the list shows', () => {
  const shown = { id: 'i', status: 'paid', paid_amount: '100.00', total_amount: '100.00', customer_id: 'c1', store_id: 's', business_date: '2026-09-01' };
  assert.equal(announcedMatchesShown({ id: 'i', status: 'paid', paid_amount: 100 }, shown), true, 'same money, numeric vs text');
  assert.equal(announcedMatchesShown({ id: 'i', status: 'cancelled' }, shown), false, 'a status change is news');
  assert.equal(announcedMatchesShown({ id: 'i', paid_amount: 60 }, shown), false, 'a paid amount change is news');
  assert.equal(announcedMatchesShown({ id: 'i', deleted_at: '2026-09-19T00:00:00Z' }, { ...shown, deleted_at: null }), false, 'a deletion is news');
  assert.equal(announcedMatchesShown({ id: 'i', notes: 'x' }, shown), null, 'nothing comparable says nothing');
  assert.equal(announcedMatchesShown(undefined, shown), null);
  assert.equal(announcedMatchesShown({ id: 'i', status: 'paid' }, undefined), null, 'not on this page: unknown');
});
