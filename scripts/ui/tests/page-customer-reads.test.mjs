/**
 * The Special & Rentals and Therapy pages must not read the customers table
 * wholesale.
 *
 * On Special & Rentals this was not merely wasteful. The read was capped at a
 * thousand rows by PGRST_DB_MAX_ROWS and nothing fetched the rest, so a sale or
 * rental belonging to anyone further down the alphabet rendered with no
 * customer name and both Send buttons disabled — verified against a fixture of
 * 1,206 customers, where the row showed "—" and neither WhatsApp nor email
 * could be sent. The query also never asked for `email` while the page read
 * `?.email`, so Send-by-email was disabled on every row regardless.
 *
 * On Therapy the by-id lookup already covered every entitlement, so the read
 * was waste; it is gone. Since 422 the Therapy lists come a page at a time from
 * therapy_list_page, each row with its customer's name and phone, and the
 * search runs on the server, so the page reads no customer at all.
 *
 * Source assertions, because the thing worth protecting is an absence: no test
 * of a rendered page can prove a request was not made on a table larger than
 * the fixture.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = name => readFileSync(new URL(`../../../src/pages/${name}`, import.meta.url), 'utf8');
const special = read('SpecialPage.tsx');
const therapy = read('TherapyPage.tsx');

/** Any `from('customers')` call that is not narrowed by .in()/.eq(). */
function wholeTableReads(source) {
  return (source.match(/from\('customers'\)[^\n]*/g) ?? [])
    .filter(line => !/\.(in|eq)\(/.test(line));
}

for (const [name, source] of [['SpecialPage', special], ['TherapyPage', therapy]]) {
  test(`${name} never reads the whole customers table`, () => {
    assert.deepEqual(wholeTableReads(source), [],
      `a whole-table customer read is back in ${name}`);
  });
}

test('SpecialPage resolves names by id', () => {
  assert.match(special, /fetchCustomersByIds\(/, 'SpecialPage must look its customers up by id');
});

test('SpecialPage names its rows before showing them, not a moment after', () => {
  // Left running behind the render, rows appear as dashes and fill in later.
  assert.doesNotMatch(special, /void \(async \(\) => \{[\s\S]{0,400}?fetchCustomersByIds/,
    'SpecialPage must await its customer lookup inside load');
});

test('TherapyPage takes its names with its rows, from the server (422)', () => {
  // therapy_list_page returns each row with customer_name and customer_phone,
  // and searches on the server, so no name arrives after the row.
  assert.match(therapy, /rpc\('therapy_list_page'/, 'the lists come from therapy_list_page');
  assert.match(therapy, /customer_name/, 'rows are named from the server');
  assert.doesNotMatch(therapy, /from\('customers'\)/, 'the Therapy page reads no customer itself');
  assert.doesNotMatch(therapy, /from\('purchased_therapy_entitlements'\)|from\('therapy_entitlements'\)/,
    'nor the entitlement tables whole');
});

test('Special & Rentals fetches the columns its row actions actually read', () => {
  // The page reads ?.email and ?.phone for the WhatsApp and email buttons.
  // fetchCustomersByIds supplies both; the old hand-written select did not.
  assert.match(special, /\?\.email/, 'the email button still reads an email column');
  assert.doesNotMatch(special, /from\('customers'\)\.select\('id,full_name,phone'\)/,
    'that select omits email, which disables every Send-by-email button');
});

test('Special & Rentals never feeds a customer picker from its local array', () => {
  // 426 removed the New Sale and New Rental windows, which no screen opened
  // and which held the page's only customer pickers: sales and rentals are
  // raised on the Invoices page. A picker added back must search the server
  // (CustomerSearchSelect), never the customers this page happens to hold.
  assert.doesNotMatch(special, /options=\{customers/,
    'a selector must never be fed from the local customer array');
  assert.doesNotMatch(special, /<SearchSelect[^>]*options=\{[^}]*customers/,
    'nor a SearchSelect built from it');
});
