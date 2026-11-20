/**
 * The customer's phone beside their name (the user, 20 Nov 2026): under the
 * name in the Invoices list, and after it on the invoice ("Store · Name ·
 * phone"). A placeholder such as "LEGACY-NO-PHONE-CUST-123456" is never shown.
 *
 * The list query carries no phone, so each page reads its own customers'
 * phones by id; customer-name-source.test.mjs keeps every customers read
 * narrowed to named ids. Made-up numbers only.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { shownPhone } from '../../../src/lib/customers/shownPhone.mjs';

const page = readFileSync(new URL('../../../src/pages/InvoicesPage.tsx', import.meta.url), 'utf8');

test('a real number is shown as stored, trimmed', () => {
  assert.equal(shownPhone('+6591234567'), '+6591234567');
  assert.equal(shownPhone('  +61491570110 '), '+61491570110');
  assert.equal(shownPhone('91234567'), '91234567');
  assert.equal(shownPhone('+65 9123 4567'), '+65 9123 4567');
});

test('no number, or a placeholder, shows nothing', () => {
  for (const v of [null, undefined, '', '   ', 'LEGACY-NO-PHONE-CUST-123456', 'LEGACY-DUP-PHONE-CUST-123456',
    'LEGACY-INVALID-PHONE-CUST-123456', 'legacy-no-phone-cust-000001', 'NO PHONE', 'no-phone', 'N/A', 'NA', '-', '—']) {
    assert.equal(shownPhone(v), null, `shown: ${JSON.stringify(v)}`);
  }
});

test('each list row shows the phone under the name', () => {
  assert.match(page, /<td style=\{\{ fontSize: 13 \}\}>\{custName\(inv\.customer_id\)\}\s*\{\(\(\) => \{\s*const phone = phoneOf\(inv\.customer_id\);/,
    'the Customer cell must show phoneOf(inv.customer_id) under the name');
  assert.match(page, /data-testid="invoice-row-customer-phone"/);
});

test('the invoice shows the phone after the name', () => {
  assert.match(page, /· \{custName\(detail\.customer_id\)\}\s*\{\(\(\) => \{\s*const phone = phoneOf\(detail\.customer_id\);/,
    'the "Store · Name" line must go on with the phone');
  assert.match(page, /data-testid="invoice-detail-customer-phone"/);
});

test('the phone shown is never a placeholder, and prefers the page\'s own read', () => {
  assert.match(page, /const phoneOf = \(id: string \| null \| undefined\): string \| null =>\s*id \? shownPhone\(phoneById\[id\] \?\? customerOf\(id\)\?\.phone\) : null;/);
});

test('each page reads its own customers\' phones, by id, with the rows', () => {
  assert.match(page, /supabase\.from\('customers'\)\.select\('id, phone'\)\.in\('id', slice\)/,
    'the phone read asks for the id and the phone only, for named ids');
  assert.match(page, /rememberNames\(res\.rows as any\[\]\);\s*void loadPhonesFor\(res\.rows\.map\(r => r\.customer_id\)\);/,
    'each loaded page must read its customers\' phones');
});
