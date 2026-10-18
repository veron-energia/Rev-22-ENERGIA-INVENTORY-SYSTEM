// 418 (CUSTOMERS-11): a phone typed the way people write it is matched on its
// digits, in the browser (the referrer and invoice customer picker) the same
// way as in search_customers and customer_survey_overview.
//
// Run: node --test scripts/customers/tests/phone-search.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { phoneSearchDigits, phoneSearchFilters } from '../../../src/lib/customers/phoneSearch.mjs';

test('a phone with spaces, dashes, brackets, dots or +65 gives its digits', () => {
  for (const term of ['9123 4567', '9123-4567', ' 91234567 ', '9123.4567']) {
    assert.deepEqual(phoneSearchDigits(term), { digits: '91234567', national: null }, term);
  }
  for (const term of ['+65 9123 4567', '(+65) 9123-4567', '+65-9123-4567', '65 9123 4567']) {
    assert.deepEqual(phoneSearchDigits(term), { digits: '6591234567', national: '91234567' }, term);
  }
  // Another country's number: its digits, and no Singapore part.
  assert.deepEqual(phoneSearchDigits('+60 12-345 6789'), { digits: '60123456789', national: null });
  // A part of a number, 4 digits or more.
  assert.deepEqual(phoneSearchDigits('4567'), { digits: '4567', national: null });
});

test('a name, an email, a customer number or fewer than 4 digits is not a phone', () => {
  for (const term of ['', '   ', null, undefined, 'Ada Tan', 'ada@sig.invalid', 'CUST-999999', 'Tan 9123 4567', '912', '9 1 2', '+65']) {
    assert.equal(phoneSearchDigits(term), null, String(term));
  }
});

test('the picker adds the digits, and the 8 digits after +65, to its search', () => {
  assert.deepEqual(phoneSearchFilters('+65 9123 4567'), ['phone.ilike.%6591234567%', 'phone.ilike.%91234567%']);
  assert.deepEqual(phoneSearchFilters('9123 4567'), ['phone.ilike.%91234567%']);
  assert.deepEqual(phoneSearchFilters('Ada'), []);
});

test('the database applies the same rule (418)', () => {
  const sql = readFileSync(new URL('../../../supabase/418_customer_edits_audited_and_phone_search.sql', import.meta.url), 'utf8');
  // Only phone characters, 4 digits or more, and +65 with 8 digits.
  assert.ok(sql.includes("~ '^[0-9+().[:space:]-]+$'"), 'the phone characters');
  assert.ok(sql.includes("length(regexp_replace(p_query, '[^0-9]', '', 'g')) >= 4"), '4 digits or more');
  assert.ok(sql.includes("~ '^65[0-9]{8}$'"), '+65 and 8 digits');
  const page = readFileSync(new URL('../../../src/components/SearchSelect.tsx', import.meta.url), 'utf8');
  assert.match(page, /phoneSearchFilters\(query\)/, 'the customer picker uses the rule');
});
