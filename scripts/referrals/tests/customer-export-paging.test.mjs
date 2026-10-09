/**
 * 409: the Customers page's Excel exports read every page of
 * search_customers and never hand back a short or doubled sheet.
 *
 * Production, 9 Oct 2026: 12,748 of 12,936 customers share one of 32 import
 * timestamps; ordered by created_at alone, the export's pages of 1,000 gave
 * 12,936 rows but 12,810 customers. 409 orders by created_at desc, id desc
 * (its SQL test is scripts/referrals/tests/customer-paging.sql); the page's
 * reader now also refuses a failed page, a customer met twice or a list that
 * changed while it was read, instead of exporting it.
 *
 * Run: node --test scripts/referrals/tests/customer-export-paging.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fetchAllCustomerRows, CHANGED_WHILE_EXPORTING } from '../../../src/lib/customers/exportPaging.mjs';

// 2,345 customers on three import timestamps, as the import left them.
const customers = Array.from({ length: 2345 }, (_, n) => ({
  id: `c-${String(n).padStart(5, '0')}`,
  created_at: n < 1200 ? '2026-07-01T02:00:00Z' : n < 2000 ? '2026-07-02T02:00:00Z' : '2026-07-03T02:00:00Z',
}));
const byNewestThenId = (a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : a.id < b.id ? 1 : a.id > b.id ? -1 : 0);
const server = (list, order) => async (limit, offset) => {
  const sorted = [...list].sort(order);
  return { data: sorted.slice(offset, offset + limit).map(c => ({ ...c, total_count: list.length })), error: null };
};

test('one fixed order: every customer once, in that order, at any page size', async () => {
  for (const size of [1000, 50, 7]) {
    const rows = await fetchAllCustomerRows(server(customers, byNewestThenId), size);
    assert.equal(rows.length, customers.length);
    assert.equal(new Set(rows.map(r => r.id)).size, customers.length);
    assert.deepEqual(rows.map(r => r.id), [...customers].sort(byNewestThenId).map(c => c.id));
  }
});

test('the order before 409 (ties in any order on each page) is refused, not exported', async () => {
  // Each page sorts the ties its own way, as an OFFSET over an unsettled
  // order may: page k shuffles equal timestamps by a different key.
  let call = 0;
  const unsettled = async (limit, offset) => {
    call += 1;
    const salt = call;
    const sorted = [...customers].sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1
      : ((a.id.charCodeAt(4) * salt) % 7) - ((b.id.charCodeAt(4) * salt) % 7) || (a.id < b.id ? -1 : 1)));
    return { data: sorted.slice(offset, offset + limit).map(c => ({ ...c, total_count: customers.length })), error: null };
  };
  await assert.rejects(fetchAllCustomerRows(unsettled, 1000), { message: CHANGED_WHILE_EXPORTING });
});

test('a failed page fails the export', async () => {
  const failing = async (limit, offset) => offset === 0
    ? server(customers, byNewestThenId)(limit, offset)
    : { data: null, error: { message: 'canceling statement due to statement timeout' } };
  await assert.rejects(fetchAllCustomerRows(failing, 1000), /could not be read \(canceling statement due to statement timeout\)\. Nothing was exported\./);
});

test('a customer added while exporting fails the export', async () => {
  let call = 0;
  const growing = async (limit, offset) => {
    call += 1;
    const list = call === 1 ? customers : [{ id: 'c-new', created_at: '2026-10-09T02:00:00Z' }, ...customers];
    return server(list, byNewestThenId)(limit, offset);
  };
  await assert.rejects(fetchAllCustomerRows(growing, 1000), { message: CHANGED_WHILE_EXPORTING });
});

test('nothing matched: an empty export', async () => {
  assert.deepEqual(await fetchAllCustomerRows(async () => ({ data: [], error: null }), 1000), []);
});

test('the Customers page exports through it, in pages of 1,000', () => {
  const page = readFileSync(new URL('../../../src/pages/CustomersPage.tsx', import.meta.url), 'utf8');
  assert.match(page, /const fetchAllForExport = \(\) => fetchAllCustomerRows<any>\(async \(limit, offset\) => \{/);
  assert.match(page, /p_limit: limit, p_offset: offset,/);
  assert.ok(!/for \(let offset = 0; ; offset \+= PAGE\)/.test(page), 'the old loop, which ignored errors, is gone');
  const sql = readFileSync(new URL('../../../supabase/409_refund_requests_refund_due_customer_order.sql', import.meta.url), 'utf8');
  assert.ok(sql.includes("order by m.created_at desc, m.id desc"), 'search_customers settles ties by id');
});
