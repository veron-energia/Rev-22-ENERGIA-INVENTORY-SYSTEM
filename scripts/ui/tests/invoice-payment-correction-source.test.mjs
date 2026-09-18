/**
 * The correction form searches for the affiliate and corrects the money.
 *
 * Source assertions for the client side of 336: the affiliate field is the
 * same type-ahead the unpaid-invoice panel uses; each recorded payment offers
 * amount, date received and method, or can be marked as recorded by mistake;
 * wallet-credit payments stay fixed; reversed entries are not offered as
 * payments; the header carries the changes the server expects; and the
 * preview knows the payments area.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const page = read('src/pages/InvoicesPage.tsx');
const preview = read('src/components/invoices/CorrectionPreview.tsx');

const form = page.slice(page.indexOf('Referrer / affiliate'), page.indexOf('quickCustomerFor &&'));

test('the affiliate on a correction is found by search, not scrolled to', () => {
  assert.match(form, /<SearchSelect[\s\S]*?placeholder="[^"]*search[^"]*"[\s\S]*?setAffTouched\(true\)/i, 'SearchSelect marks the affiliate as touched');
  assert.match(form, /search: `\$\{a\.full_name\} \$\{a\.phone \?\? ''\} \$\{a\.email \?\? ''\}`/, 'findable by name, phone and email');
  assert.doesNotMatch(form, /<select value=\{cAffiliate\}/, 'the plain dropdown is gone');
});

test('each recorded payment offers amount, date and method, or removal', () => {
  assert.match(form, /<input type="number"[^>]*aria-label="Payment amount"/, 'amount field');
  assert.match(form, /<input type="date"[^>]*aria-label="Date received"/, 'date field');
  assert.match(form, /recorded by mistake/i, 'removal is explained as a mistake, not a refund');
  assert.doesNotMatch(form, /amounts cannot be changed here/, 'the old notice is gone');
});

test('wallet-credit payments stay fixed and reversals are not offered', () => {
  assert.match(form, /wallet credit/i, 'wallet payments are shown as fixed');
  assert.match(page, /entry_kind !== 'correction_reversal'[\s\S]*?corrects_payment_id === p\.id/, 'superseded payments and reversals are filtered out of the form');
});

test('the save sends what the server expects', () => {
  assert.match(page, /payment_corrections/, 'amount/date corrections travel in the header');
  assert.match(page, /payment_removals/, 'removals travel in the header');
  assert.match(page, /payment_methods/, 'method-only changes keep their in-place path');
});

test('a payment can be split across methods; each part is a replacement of the same receipt', () => {
  assert.match(form, /\+ Split across methods/, 'the split button');
  assert.match(form, /aria-label="Drop this part"/, 'an added part can be dropped');
  assert.match(page, /parts: e\.parts\.map\(x => \(\{ amount: Number\(x\.amount\)/, 'a split travels as parts of one payment_corrections entry');
  assert.match(page, /e\.parts\.length > 1/, 'one part stays a plain correction');
});

test('the preview names the payments area', () => {
  assert.match(preview, /payments: 'Payments'/);
});
