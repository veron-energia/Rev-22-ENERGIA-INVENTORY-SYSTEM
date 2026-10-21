// 419: the rules the Health Surveys pages follow, without the pages.
//
//   - a QR link works to the end of the chosen Singapore day, and the list
//     calls it Expired once that has passed (CUSTOMERS-7);
//   - Edit details starts from what is stored ("Not answered" stays so) and
//     sends only what changed; a filled-in date of birth is an Owner's or
//     Manager's to change, with a reason (CUSTOMERS-4, Q9);
//   - Save Review has nothing to save until the boxes differ from the saved
//     review, and emptied boxes never replace it (CUSTOMERS-K1).
//
// Run: node --test scripts/survey/tests/survey-helpers-419.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { linkExpiryFromDay, linkStatus, sgDate, plainDate, sgDateTime } from '../../../src/lib/survey/links.mjs';
import {
  seedParticulars, particularsChanges, particularsNeedReason, dobChangeAllowed, answerLabel,
} from '../../../src/lib/survey/particulars.mjs';
import { savedReview, reviewState } from '../../../src/lib/survey/review.mjs';

test('CUSTOMERS-7: the last day chosen works until midnight in Singapore', () => {
  assert.equal(linkExpiryFromDay('2026-10-19'), '2026-10-19T15:59:59.999Z');
  assert.equal(linkExpiryFromDay(''), null);
  assert.equal(linkExpiryFromDay(null), null);
  assert.equal(linkExpiryFromDay('19/10/2026'), null);
  // Before 419 the page stored UTC midnight: 8am in Singapore.
  assert.notEqual(linkExpiryFromDay('2026-10-19'), new Date('2026-10-19').toISOString());
});

test('CUSTOMERS-7: the list says Expired once the link is past its last moment, whatever its switch', () => {
  const exp = linkExpiryFromDay('2026-10-02');
  assert.equal(linkStatus({ is_active: true, expires_at: exp }, new Date('2026-10-02T15:59:00Z')), 'active');
  assert.equal(linkStatus({ is_active: true, expires_at: exp }, new Date('2026-10-02T16:00:00Z')), 'expired');
  assert.equal(linkStatus({ is_active: false, expires_at: null }), 'inactive');
  assert.equal(linkStatus({ is_active: true, expires_at: null }), 'active');
});

test('dates show as dd/mm/yyyy in Singapore time; a date of birth never moves a day', () => {
  assert.equal(sgDate('2026-10-02T16:30:00Z'), '03/10/2026');
  assert.equal(sgDate(null), '—');
  assert.equal(plainDate('1980-01-02'), '02/01/1980');
  assert.equal(plainDate(null), '—');
  assert.match(sgDateTime('2026-10-02T16:30:00Z'), /^03\/10\/2026, 00:30$/);
});

const SURVEY = {
  first_name: 'Bea', last_name: 'Testtwo', phone: '+61491570157', email: 'bea@example.com',
  date_of_birth: '1981-05-06', sex: 'female', occupation: null, others_text: null,
  source_option_id: 'src-1', source_details: null, treatment_list: null,
  has_medical_condition: null, drinks_alcohol: false, smokes: null, on_treatment: null,
};

test('CUSTOMERS-4: Edit details starts from what is stored; Not answered stays Not answered', () => {
  const seed = seedParticulars(SURVEY, [{ option_id: 'b', duration_text: '2 weeks' }]);
  assert.equal(seed.has_medical_condition, null);
  assert.equal(seed.drinks_alcohol, false);
  assert.deepEqual(seed.symptoms, { b: '2 weeks' });
  // Saving without touching anything sends nothing.
  assert.deepEqual(particularsChanges(seed, { ...seed }), {});
});

test('CUSTOMERS-4: only what changed is sent, and Not answered can be chosen', () => {
  const seed = seedParticulars(SURVEY, []);
  assert.deepEqual(particularsChanges(seed, { ...seed, smokes: true }), { smokes: true });
  assert.deepEqual(particularsChanges(seed, { ...seed, drinks_alcohol: null }), { drinks_alcohol: null });
  assert.deepEqual(particularsChanges(seed, { ...seed, occupation: '  Baker ' }), { occupation: 'Baker' });
  assert.deepEqual(particularsChanges(seed, { ...seed, on_treatment: false, treatment_list: 'x' }), { on_treatment: false });
  assert.deepEqual(particularsChanges(seed, { ...seed, symptoms: { a: '' } }), { symptoms: [{ option_id: 'a', duration_text: null }] });
});

test('Q9: a filled-in date of birth needs an Owner or Manager and a reason; a missing one anyone fills', () => {
  const filled = { hasCustomer: true, customerDob: '1981-05-06' };
  const change = { date_of_birth: '1981-05-07' };
  assert.equal(particularsNeedReason(change, filled), true);
  assert.equal(dobChangeAllowed(change, { ...filled, role: 'staff' }), false);
  assert.equal(dobChangeAllowed(change, { ...filled, role: 'manager' }), true);
  assert.equal(dobChangeAllowed({ date_of_birth: null }, { ...filled, role: 'staff' }), false);
  const missing = { hasCustomer: true, customerDob: null };
  assert.equal(particularsNeedReason(change, missing), false);
  assert.equal(dobChangeAllowed(change, { ...missing, role: 'staff' }), true);
  // A form with no customer yet (held for staff): nothing to protect.
  assert.equal(dobChangeAllowed(change, { hasCustomer: false, role: 'staff' }), true);
  // A new phone goes onto the customer: a reason is asked for.
  assert.equal(particularsNeedReason({ phone: '+61491573087' }, filled), true);
  assert.equal(particularsNeedReason({ occupation: 'Baker' }, filled), false);
});

test('declarations read Yes, No or Not answered', () => {
  assert.equal(answerLabel(true), 'Yes');
  assert.equal(answerLabel(false), 'No');
  assert.equal(answerLabel(null), 'Not answered');
});

test('CUSTOMERS-K1: nothing to save until the boxes differ from the saved review', () => {
  const saved = savedReview({ acidity_result: 'green', health_goals: 'Sleep', remarks_condition: 'Tight back', remarks_recommendation: null });
  assert.deepEqual(reviewState(saved, { acidity: 'green', goals: 'Sleep', cond: 'Tight back', rec: '' }),
                   { changed: false, blanks: false, canSave: false });
  assert.equal(reviewState(saved, { acidity: 'green', goals: 'Sleep', cond: 'Better', rec: '' }).canSave, true);
});

test('CUSTOMERS-K1: emptied boxes never replace a saved review', () => {
  const saved = savedReview({ acidity_result: 'green', health_goals: 'Sleep', remarks_condition: 'Tight back' });
  const st = reviewState(saved, { acidity: 'green', goals: ' ', cond: '', rec: '' });
  assert.equal(st.changed, true);
  assert.equal(st.blanks, true);
  assert.equal(st.canSave, false);
  // With nothing saved yet, typing anything may be saved.
  assert.equal(reviewState(savedReview(null), { acidity: '', goals: 'Sleep', cond: '', rec: '' }).canSave, true);
  assert.equal(reviewState(savedReview(null), { acidity: '', goals: '', cond: '', rec: '' }).canSave, false);
});
