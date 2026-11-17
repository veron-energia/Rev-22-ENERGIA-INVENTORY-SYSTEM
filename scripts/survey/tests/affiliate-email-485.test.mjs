// 485 (the Owner, 2 Nov 2026): a form's email no longer goes onto a customer
// record that has a portal login or an affiliate record, not even when staff
// attach a held QR form or link a held registration. The database rule is
// supabase/485_forms_do_not_fill_affiliate_record_email.sql (its suite:
// affiliate-email-485.sql).
// 511 (17 Nov 2026): nor onto any other customer who was there before the
// form or the registration. The two staff windows now say the email is not
// copied at all; the database rule is
// supabase/511_a_form_puts_no_email_on_an_existing_customer.sql (its suite:
// form-email-existing-customer-511.sql). The Surveys window is also checked
// as rendered in survey-holds-panel.test.mjs.
// Run: node --test scripts/survey/tests/affiliate-email-485.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const flat = (s) => s.replace(/\s+/g, ' ');

test('the Event page\'s window for linking a held registration says the email is not copied (511)', () => {
  const src = flat(read('src/components/events/RegistrationHoldsPanel.tsx'));
  assert.ok(src.includes("Their name, phone and email stay as they are; the email on the registration is not copied (add it in Edit customer if it is theirs). Their referrer is not changed."));
  assert.ok(!src.includes('an empty email is filled from the registration'));
});

test('the Surveys window for attaching a held form says the email is not copied (511)', () => {
  const src = flat(read('src/components/SurveyHoldsPanel.tsx'));
  assert.ok(src.includes("Their name, phone and email stay as they are; empty details (date of birth, sex, occupation, how they heard about us) are filled from the form. The email on the form is not copied: add it in Edit customer if it is theirs."));
  assert.ok(!src.includes('empty details (email,'));
  assert.ok(!src.includes('except the email of an affiliate'));
});

test('485 made the three functions keep a form\'s email off a record with a portal login or an affiliate record', () => {
  const sql = read('supabase/485_forms_do_not_fill_affiliate_record_email.sql');
  for (const md5 of ['860743f4f2e92f669e257121de0a9308', '4cefb8a7ae96aa5836041cf57cb3f33f', '8a66d8e6d7008c79d94c5b20ffecb4df']) {
    assert.ok(sql.includes(`'${md5}'`), `485 names the AFTER ${md5}`);
  }
  // The three texts the file installs, between its $d1$, $d2$ and $d3$ quotes: each checks both tables.
  const def = (tag) => sql.split(`$${tag}$`)[1] || '';
  const fns = { d1: 'submit_health_survey', d2: 'event_web_fill_customer', d3: 'attach_held_health_survey' };
  for (const [tag, fn] of Object.entries(fns)) {
    const text = def(tag);
    assert.match(text, new RegExp(`^CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `$${tag}$ holds ${fn}`);
    assert.match(text, /exists \(select 1 from public\.affiliate_accounts a where a\.customer_id = (customers\.id|p_customer_id)\)/, `${fn} checks the portal login`);
    assert.match(text, /exists \(select 1 from public\.customer_affiliates f where f\.customer_id = (customers\.id|p_customer_id)\)/, `${fn} checks the affiliate record`);
  }
});

test('the new sentences go out with 511, which starts from 485\'s three functions and sets no email on a customer who was there', () => {
  const sql = read('supabase/511_a_form_puts_no_email_on_an_existing_customer.sql');
  const list = (name) => (sql.match(new RegExp(`  ${name} constant text\\[\\] := array\\[\\n([\\s\\S]*?)\\];\\n`)) || [])[1] || '';
  // BEFORE: 485's AFTER of the QR form, of staff attaching a held form and of the registration's fill, in that order.
  assert.deepEqual(list('c_before').match(/[0-9a-f]{32}/g),
    ['860743f4f2e92f669e257121de0a9308', '8a66d8e6d7008c79d94c5b20ffecb4df', '4cefb8a7ae96aa5836041cf57cb3f33f']);
  assert.deepEqual(list('c_after').match(/[0-9a-f]{32}/g),
    ['ddc02ed5fa82aacde5f031d6d367b300', '55b632c7e9289cb267516a26af97387b', 'ca9957a62467c9f9ea574de86c8fd1bb']);
  assert.deepEqual(list('c_sig').match(/'[^']+'/g),
    ["'submit_health_survey(text,jsonb,jsonb,text)'", "'attach_held_health_survey(uuid,uuid,text)'", "'event_web_fill_customer(uuid,uuid)'"]);
  // What it takes out sets the email; what it puts in does not.
  const taken = list('c_anchor').split('$a$').filter((_, i) => i % 2 === 1);
  const put = list('c_new').split('$n$').filter((_, i) => i % 2 === 1);
  assert.equal(taken.length, 3);
  assert.equal(put.length, 3);
  assert.match(taken[0], /set email\s+= case when email is null/);
  assert.match(taken[1], /set email\s+= case when email is null/);
  assert.match(taken[2], /v_keep_email := exists \(/);
  for (const text of put.slice(0, 2)) {
    assert.doesNotMatch(text, /\bemail\s+=/, 'the customer update no longer sets email');
    assert.match(text, /update public\.customers\s+set date_of_birth/);
  }
  assert.match(put[2], /v_keep_email := true;/);
});
