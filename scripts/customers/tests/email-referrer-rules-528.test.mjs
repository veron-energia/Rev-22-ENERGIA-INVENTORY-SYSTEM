/**
 * 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026): who changes a customer's
 * email and referrer, and the affiliate on an invoice already made. The database refuses anyone
 * else (supabase/528_...; scripts/customers/tests/email-referrer-invoice-affiliate-528.sql); the
 * pages do not offer it to them:
 *   - the rules (src/lib/customers/emailReferrerRules.mjs): an Owner or Manager only (not the
 *     old Admin role), the Singapore day a customer was made, an email changed as stored;
 *   - the invoice view offers the Affiliate picker to an Owner or Manager only, and Staff see the
 *     affiliate read only (set_invoice_affiliate is never called for them); New Invoice keeps no
 *     check of its own (choosing it while making stays Staff's);
 *   - the correction form (Edit Invoice on a paid invoice) shows the Referrer / affiliate read
 *     only to anyone else, and never sends affiliate_id for them (correct_invoice refuses it:
 *     "Owner/Manager for every change", the user, 19 Nov 2026);
 *   - the Customers page and the health survey window ask customer_is_affiliate_or_portal_login
 *     for anyone but an Owner or Manager (their own tests drive them: customers-page.test.mjs,
 *     survey-window-419.test.mjs).
 *   node --test scripts/customers/tests/email-referrer-rules-528.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as rules from '../../../src/lib/customers/emailReferrerRules.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const invoices = read('src/pages/InvoicesPage.tsx');
const customers = read('src/pages/CustomersPage.tsx');
const survey = read('src/components/SurveyDetailModal.tsx');

test('an Owner or Manager only: not the old Admin role, Staff or an Inventory Manager', () => {
  for (const [role, yes] of [['owner', true], ['manager', true], ['admin', false], ['staff', false], ['inventory_manager', false],
                             [null, false], [undefined, false], ['', false]]) {
    assert.equal(rules.isOwnerOrManagerRole(role), yes, String(role));
    assert.equal(rules.mayChangeInvoiceAffiliate(role), yes, `${role}: the affiliate on an invoice already made`);
    assert.equal(rules.mayChangeEmail(role, true), yes, `${role}: an affiliate's email`);
    assert.equal(rules.mayChangeEmail(role, false), true, `${role}: a plain customer's email (the database checks the role)`);
    assert.equal(rules.mayChangeEmail(role, null), true, `${role}: not known: open, the database decides`);
  }
});

test('an email changed as it will be stored: trimmed, blank as none, case kept', () => {
  assert.equal(rules.emailChanged('', '  '), false);
  assert.equal(rules.emailChanged(null, ''), false);
  assert.equal(rules.emailChanged('a@example.invalid', ' a@example.invalid '), false);
  assert.equal(rules.emailChanged('a@example.invalid', 'A@example.invalid'), true, 'the database compares the text as it is');
  assert.equal(rules.emailChanged('a@example.invalid', ''), true, 'removed');
  assert.equal(rules.emailChanged(null, 'a@example.invalid'), true, 'added');
});

test('the day a customer was made is Singapore\'s', () => {
  const now = new Date('2026-11-19T04:00:00Z');                          // 12:00 on 19 Nov in Singapore
  assert.equal(rules.sgYmd('2026-11-18T16:00:00Z'), '2026-11-19', '00:00 in Singapore is the 19th');
  assert.equal(rules.madeBeforeTodaySg('2026-11-18T16:01:00Z', now), false, '00:01 today in Singapore (the 18th in UTC)');
  assert.equal(rules.madeBeforeTodaySg('2026-11-18T15:59:00Z', now), true, '23:59 yesterday in Singapore');
  assert.equal(rules.madeBeforeTodaySg('2026-11-19T03:59:00Z', now), false);
  assert.equal(rules.madeBeforeTodaySg(null, now), true, 'an unknown date counts as before today');
  assert.equal(rules.madeBeforeTodaySg('not a date', now), true);
  for (const [role, older, today] of [['staff', false, true], ['admin', false, true], ['manager', true, true], ['owner', true, true]]) {
    assert.equal(rules.mayAddReferrer(role, '2026-11-01T02:00:00Z', now), older, `${role}: a customer made on 1 Nov`);
    assert.equal(rules.mayAddReferrer(role, '2026-11-18T16:30:00Z', now), today, `${role}: a customer made today`);
  }
  // A device outside Singapore sees the same day.
  const la = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Los_Angeles' }).format(new Date('2026-11-18T16:01:00Z'));
  assert.equal(la, '2026-11-18');
  assert.equal(rules.sgYmd(new Date('2026-11-18T16:01:00Z')), '2026-11-19');
});

test('the invoice view offers the Affiliate picker to an Owner or Manager only', () => {
  const box = invoices.slice(invoices.indexOf('{/* Affiliate selector'), invoices.indexOf('{revisions.length > 0 && ('));
  assert.ok(box.length > 0, 'the Affiliate box is found');
  const gate = box.indexOf('{mayChangeInvoiceAffiliate(profile?.role) ? (');
  assert.ok(gate > 0, 'the picker is behind the role');
  assert.ok(box.indexOf('changeInvoiceAffiliate(') > gate, 'set_invoice_affiliate is reached only through the gated picker');
  assert.match(box, /data-invoice-affiliate-readonly/, 'Staff see the affiliate read only');
  assert.match(box, /INVOICE_AFFILIATE_LOCKED_HINT/, 'and why');
  assert.match(box, /\{affiliateErr && /, 'a refusal from the database is shown');
  assert.equal((invoices.match(/rpc\('set_invoice_affiliate'/g) ?? []).length, 1, 'one caller of set_invoice_affiliate');
  // New Invoice: choosing it while making stays Staff's (create_invoice_with_details takes it).
  assert.match(invoices, /rpc\('create_invoice_with_details'/);
  assert.doesNotMatch(invoices.slice(invoices.indexOf("rpc('create_invoice_with_details'"), invoices.indexOf("rpc('create_invoice_with_details'") + 400),
    /mayChangeInvoiceAffiliate/);
});

test('the Customers page and the survey window ask the database who is an affiliate or a portal login', () => {
  assert.match(customers, /rpc\('customer_is_affiliate_or_portal_login', \{ p_customer_id: c\.id \}\)/);
  assert.match(customers, /const lockAsked = canComplete \? null/, 'an Owner or Manager does not ask');
  assert.match(customers, /const needsReason = phoneChanged \|\| dobChanged \|\| emailChange;/);
  assert.match(customers, /disabled=\{referrerLocked\}/);
  assert.match(survey, /rpc\('customer_is_affiliate_or_portal_login', \{ p_customer_id: askedFor \}\)/);
  assert.match(survey, /customerEmail: cust\?\.email \?\? null/);
  assert.match(survey, /select\('id, date_of_birth, email'\)/, 'the customer\'s email is read to tell a new one');
});

test('the correction form shows the affiliate read only to anyone but an Owner or Manager, and never sends it for them', () => {
  assert.match(invoices, /\.\.\.\(affTouched && mayChangeInvoiceAffiliate\(profile\?\.role\) \? \{ affiliate_id: cAffiliate \|\| null \} : \{\}\),/,
    'affiliate_id is sent only when an Owner or Manager touched it');
  assert.equal((invoices.match(/affiliate_id: cAffiliate/g) ?? []).length, 1, 'no other place sends the form\'s affiliate');
  const field = invoices.slice(invoices.indexOf('<label>Referrer / affiliate</label>'), invoices.indexOf('{/* Who raised it.'));
  assert.ok(field.length > 0, 'the field is found');
  const gate = field.indexOf('{mayChangeInvoiceAffiliate(profile?.role) ? (<>');
  assert.ok(gate >= 0 && field.indexOf('setAffTouched(true)') > gate, 'only the gated picker marks it touched');
  assert.match(field, /data-correction-affiliate-readonly/);
  assert.match(field, /\{INVOICE_AFFILIATE_LOCKED_HINT\}/, 'the same hint as the invoice view');
  // The server's refusal of a correction is shown on the form, as any other.
  assert.match(invoices, /setCErr\(goodsRefusal\(error\.message\) \?\? error\.message\);/);
});
