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
 * was waste; it is gone, and the lookup is now awaited because the search box
 * filters on customer name.
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

  test(`${name} resolves names by id`, () => {
    assert.match(source, /fetchCustomersByIds\(/,
      `${name} must look its customers up by id`);
  });

  test(`${name} names its rows before showing them, not a moment after`, () => {
    // Left running behind the render, rows appear as dashes and fill in later —
    // and on Therapy a search typed in that window misses rows that do match.
    assert.doesNotMatch(source, /void \(async \(\) => \{[\s\S]{0,400}?fetchCustomersByIds/,
      `${name} must await its customer lookup inside load`);
  });
}

test('Special & Rentals fetches the columns its row actions actually read', () => {
  // The page reads ?.email and ?.phone for the WhatsApp and email buttons.
  // fetchCustomersByIds supplies both; the old hand-written select did not.
  assert.match(special, /\?\.email/, 'the email button still reads an email column');
  assert.doesNotMatch(special, /from\('customers'\)\.select\('id,full_name,phone'\)/,
    'that select omits email, which disables every Send-by-email button');
});

test('Special & Rentals still picks customers through the server-side selector', () => {
  assert.match(special, /CustomerSearchSelect/,
    'the pickers must keep searching the server, not a local array');
  assert.doesNotMatch(special, /options=\{customers/,
    'a selector must never be fed from the local customer array');
});
