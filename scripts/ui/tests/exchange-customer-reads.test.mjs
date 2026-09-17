/**
 * The Exchanges page must not read the customers table wholesale.
 *
 * It used to open with `from('customers').select('*')` — a thousand rows of all
 * twenty-six columns, 666 kB on a 1,200-customer database — to supply names
 * that the by-id lookup beside it already supplied. The read was also capped at
 * a thousand rows by PGRST_DB_MAX_ROWS, so it could never have been the
 * authority on a name in the first place.
 *
 * Source assertions, because the thing worth protecting is an absence: no test
 * of the rendered page can prove a request was not made on a table larger than
 * the fixture.
 *
 * Two pages still carry a lighter form of this — SpecialPage and TherapyPage
 * each read `id, full_name, phone` for the whole table in one uncapped request.
 * They are deliberately not asserted here; claiming them clean would be false.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const page = readFileSync(new URL('../../../src/pages/ExchangesPage.tsx', import.meta.url), 'utf8');

test('the page never reads the whole customers table', () => {
  const reads = page.match(/from\('customers'\)[\s\S]{0,160}?(?=[,;]\s*\n|\n\s*\n)/g) ?? [];
  for (const read of reads) {
    assert.doesNotMatch(read, /select\('\*'\)/,
      `a whole-table customer read is back: ${read.slice(0, 120)}`);
  }
});

test('names come from a lookup by id', () => {
  assert.match(page, /fetchCustomersByIds\(\(\(ex\.data as any\[\]\) \?\? \[\]\)\.map\(x => x\.customer_id\)\)/,
    'the exchange rows must resolve their own customers by id');
  assert.match(page, /fetchCustomersByIds\(\[cid\]\)/,
    'a found invoice must resolve its customer by id');
});

test('the rows are named before they are shown, not a moment after', () => {
  const load = page.match(/const load = useCallback\([\s\S]*?\n  \}, \[\]\);/)[0];
  const fetched = load.indexOf('fetchCustomersByIds');
  const done = load.indexOf('setLoading(false)');
  assert.ok(fetched > 0 && fetched < done,
    'the by-id fetch must be awaited inside load, before the page stops loading');
  assert.doesNotMatch(load, /void \(async \(\) => \{[\s\S]*?fetchCustomersByIds/,
    'left running in the background, the rows render as dashes and fill in later');
});

test('the customer picker is untouched and still searches the server', () => {
  assert.doesNotMatch(page, /options=\{customers\./,
    'a selector must never be fed from the local customer array');
});
