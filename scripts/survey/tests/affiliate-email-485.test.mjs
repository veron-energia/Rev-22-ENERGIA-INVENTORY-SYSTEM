// 485 (the Owner, 2 Nov 2026): a form's email no longer goes onto a customer
// record that has a portal login or an affiliate record, not even when staff
// attach a held QR form or link a held registration. The two staff windows
// say so; the database rule is supabase/485_forms_do_not_fill_affiliate_record_email.sql
// (its suite: affiliate-email-485.sql). The Surveys window is also checked as
// rendered in survey-holds-panel.test.mjs.
// Run: node --test scripts/survey/tests/affiliate-email-485.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const flat = (s) => s.replace(/\s+/g, ' ');

test('the Event page\'s window for linking a held registration says an affiliate\'s email is not filled', () => {
  const src = flat(read('src/components/events/RegistrationHoldsPanel.tsx'));
  assert.ok(src.includes("Their name and phone stay as they are; an empty email is filled from the registration, except an affiliate's, even a former affiliate's (add it in Edit customer if it is theirs). Their referrer is not changed."));
  assert.ok(!src.includes('an empty email is filled from the registration. Their referrer'));
});

test('the Surveys window for attaching a held form says an affiliate\'s email is not filled', () => {
  const src = flat(read('src/components/SurveyHoldsPanel.tsx'));
  assert.ok(src.includes("empty details (email, date of birth, sex, occupation, how they heard about us) are filled from the form, except the email of an affiliate, even a former one (add it in Edit customer if it is theirs)."));
});

test('the sentences go out with 485, which makes the three functions follow the rule', () => {
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
