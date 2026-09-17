/**
 * The invoice detail opens from the full row, never from the list row.
 *
 * 324 made the list a page of narrow rows — number, dates, totals, names —
 * and openDetail used to keep that row as `detail`. openEdit then restored
 * the manual discount, the notes, the discount voucher and the instalment
 * label from fields the row never had, so a correction would have saved them
 * blank. Nothing in production was lost before this was caught, but the path
 * existed. openDetail must fetch the whole invoice before it sets `detail`.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const page = readFileSync(new URL('../../../src/pages/InvoicesPage.tsx', import.meta.url), 'utf8');
const start = page.indexOf('const openDetail = async (inv: Invoice) => {');
assert.ok(start > 0, 'openDetail not found');
const body = page.slice(start, page.indexOf('\n  };', start));

test('openDetail fetches the full invoice before anything reads detail', () => {
  const fetchAt = body.indexOf(".from('invoices').select('*').eq('id', inv.id)");
  const setAt = body.indexOf('setDetail(inv)');
  assert.ok(fetchAt > 0, 'openDetail does not fetch the full row');
  assert.ok(setAt > fetchAt, 'the full row must be fetched before detail is set');
  assert.match(body.slice(fetchAt, setAt), /if \(fullRow\) inv = fullRow as Invoice;/, 'the fetched row must replace the list row');
});

test('a superseded open never overwrites a newer one', () => {
  const fetchAt = body.indexOf(".from('invoices').select('*').eq('id', inv.id)");
  assert.match(body.slice(fetchAt, fetchAt + 400), /if \(superseded\(\)\) return;/,
    'the guard must run after the await, not only before it');
});

test('the form restores the fields the list row lacks', () => {
  for (const f of ['manual_discount', 'manual_discount_reason', 'notes', 'discount_voucher_id', 'instalment_category']) {
    assert.match(page, new RegExp(`\\(detail as any\\)\\.${f}`), `openEdit no longer restores ${f}`);
  }
});
