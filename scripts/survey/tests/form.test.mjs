// Pure-logic tests for the public health-survey form helpers.
// Run: node --test scripts/survey/tests/form.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  makeInitialForm, parseDob, isSurveyDirty, validateSurvey, mapServerError, FIELD_ORDER, SURVEY_LIMITS, sgDate,
} from '../../../src/lib/survey/form.mjs';

const SIGNED = '2026-09-08';
const initial = () => makeInitialForm(SIGNED);
const dirtyInput = (over = {}) => ({
  form: over.form ?? initial(),
  dob: over.dob ?? { d: '', m: '', y: '' },
  ticks: over.ticks ?? {},
  phoneTouched: over.phoneTouched ?? false,
});

test('parseDob: empty / partial / invalid / valid', () => {
  assert.equal(parseDob({ d: '', m: '', y: '' }).status, 'empty');
  assert.equal(parseDob({ d: '5', m: '', y: '' }).status, 'partial');
  assert.equal(parseDob({ d: '5', m: '3', y: '' }).status, 'partial');
  // 31 February must not roll forward to March.
  const feb31 = parseDob({ d: '31', m: '2', y: '1990' });
  assert.equal(feb31.status, 'invalid');
  assert.equal(feb31.iso, '');
  // 29 Feb only in a leap year.
  assert.equal(parseDob({ d: '29', m: '2', y: '2001' }).status, 'invalid');
  assert.equal(parseDob({ d: '29', m: '2', y: '2000' }).status, 'valid');
  const ok = parseDob({ d: '7', m: '4', y: '1985' });
  assert.equal(ok.status, 'valid');
  assert.equal(ok.iso, '1985-04-07');
  // Future date is rejected.
  assert.equal(parseDob({ d: '1', m: '1', y: '2999' }).status, 'invalid');
});

test('isSurveyDirty: untouched form (with default signed date) is clean', () => {
  assert.equal(isSurveyDirty(dirtyInput(), initial()), false);
});

test('isSurveyDirty: each control type flips it, and reverting clears it', () => {
  assert.equal(isSurveyDirty(dirtyInput({ form: { ...initial(), first_name: 'A' } }), initial()), true);
  assert.equal(isSurveyDirty(dirtyInput({ form: { ...initial(), has_medical_condition: false } }), initial()), true);
  assert.equal(isSurveyDirty(dirtyInput({ form: { ...initial(), consent_marketing_sms: true } }), initial()), true);
  assert.equal(isSurveyDirty(dirtyInput({ form: { ...initial(), signature_data: 'data:image/png;base64,x' } }), initial()), true);
  assert.equal(isSurveyDirty(dirtyInput({ form: { ...initial(), signed_date: '2020-01-01' } }), initial()), true);
  // Phone: interaction alone counts even if the value came back empty.
  assert.equal(isSurveyDirty(dirtyInput({ phoneTouched: true }), initial()), true);
  // DOB: any select chosen.
  assert.equal(isSurveyDirty(dirtyInput({ dob: { d: '1', m: '', y: '' } }), initial()), true);
  // Symptom tick on, then off + no duration -> back to clean.
  assert.equal(isSurveyDirty(dirtyInput({ ticks: { s1: { on: true, duration: '' } } }), initial()), true);
  assert.equal(isSurveyDirty(dirtyInput({ ticks: { s1: { on: false, duration: '' } } }), initial()), false);
  // A duration typed but unticked still counts.
  assert.equal(isSurveyDirty(dirtyInput({ ticks: { s1: { on: false, duration: '2wk' } } }), initial()), true);
});

test('validateSurvey: collects every missing required field, in order', () => {
  const e = validateSurvey({
    form: initial(), dob: parseDob({ d: '', m: '', y: '' }),
    phoneValid: false, requireSource: true, sourceRequiresDetails: false,
  });
  assert.ok(e.first_name && e.phone && e.email && e.source_option_id && e.signature_data);
  assert.equal(e.date_of_birth, undefined); // DOB is optional
  const firstBad = FIELD_ORDER.find(k => e[k]);
  assert.equal(firstBad, 'first_name');
});

test('validateSurvey: email shape, partial DOB, conditional source details', () => {
  const base = {
    ...initial(), first_name: 'A', phone: '+6591234567', email: 'nope',
    source_option_id: 's2', source_details: '', signature_data: 'sig',
  };
  let e = validateSurvey({
    form: base, dob: parseDob({ d: '1', m: '2', y: '' }),
    phoneValid: true, requireSource: true, sourceRequiresDetails: true,
  });
  assert.ok(/valid email/i.test(e.email));
  assert.ok(/day, month and year/i.test(e.date_of_birth));
  assert.ok(e.source_details, 'details required when the chosen source needs them');

  e = validateSurvey({
    form: { ...base, email: 'a@b.co', source_details: 'a friend' },
    dob: parseDob({ d: '1', m: '2', y: '1990' }),
    phoneValid: true, requireSource: true, sourceRequiresDetails: true,
  });
  assert.deepEqual(e, {});
});

test('validateSurvey: event-linked survey skips the source question', () => {
  const e = validateSurvey({
    form: { ...initial(), first_name: 'A', phone: '+6591234567', email: 'a@b.co', signature_data: 'sig' },
    dob: parseDob({ d: '', m: '', y: '' }),
    phoneValid: true, requireSource: false, sourceRequiresDetails: false,
  });
  assert.deepEqual(e, {});
});

test('mapServerError: recognised errors route to a field or section', () => {
  assert.equal(mapServerError('...HEALTH_SURVEY_ALREADY_EXISTS...').scope, 'identity');
  // 468: neutral words (the Owner, 24 Oct 2026).
  assert.equal(mapServerError('HEALTH_SURVEY_ALREADY_EXISTS').message,
    'A health survey has already been completed for these details. Please ask our consultant to help update your details.');
  assert.equal(mapServerError('AMBIGUOUS_CUSTOMER_MATCH').scope, 'identity');
  assert.equal(mapServerError('CUSTOMER_PHONE_LIMIT: ...').field, 'phone');
  assert.equal(mapServerError('CUSTOMER_PHONE_REVIEW: ...').field, 'phone');
  assert.equal(mapServerError('Please enter a valid email address.').field, 'email');
  assert.equal(mapServerError('Please add a few details for "Friend".').field, 'source_details');
  // Unknown -> a friendly, non-technical form-level message (no raw DB text).
  const unknown = mapServerError('duplicate key value violates unique constraint "pk"');
  assert.equal(unknown.scope, 'form');
  assert.ok(!/constraint/i.test(unknown.message));
});

// ── 530 (security audit of 17 Nov 2026, M4): the sizes the server takes, checked first ──
const ok530 = () => ({
  ...initial(), first_name: 'A', phone: '+6591234567', email: 'a@b.co', source_option_id: 's1',
  signature_data: 'data:image/png;base64,AAAA',
});
const v530 = (form, extra = {}) => validateSurvey({
  form, dob: parseDob({ d: '', m: '', y: '' }), phoneValid: true, requireSource: true, sourceRequiresDetails: false, ...extra,
});

test('530: every limit holds at its size and refuses one past it, by its field', () => {
  assert.deepEqual(v530(ok530()), {});
  assert.deepEqual(v530({ ...ok530(), first_name: 'N'.repeat(49), last_name: 'M'.repeat(50) }), {});
  assert.match(v530({ ...ok530(), first_name: 'N'.repeat(50), last_name: 'M'.repeat(50) }).first_name, /at most 100 characters/);
  assert.match(v530({ ...ok530(), last_name: 'T\u0007x' }).first_name, /without special characters/);
  const at = n => 'e'.repeat(n - '@example.com'.length) + '@example.com';
  assert.deepEqual(v530({ ...ok530(), email: at(254) }), {});
  assert.match(v530({ ...ok530(), email: at(255) }).email, /at most 254/);
  for (const [k, n] of [['occupation', 100], ['event_name', 100], ['treatment_list', 1000], ['others_text', 1000], ['source_details', 200]]) {
    assert.deepEqual(v530({ ...ok530(), [k]: 'x'.repeat(n) }), {}, `${k} at ${n}`);
    assert.match(v530({ ...ok530(), [k]: 'x'.repeat(n + 1) })[k], new RegExp(`at most ${n} characters`), `${k} past ${n}`);
    assert.match(v530({ ...ok530(), [k]: 'x\u001bx' })[k], /without special characters/, `${k} with a control character`);
  }
  for (const age of ['', '0', '120']) assert.deepEqual(v530({ ...ok530(), age }), {}, `age ${age}`);
  for (const age of ['121', '-1', '4.5', 'forty']) assert.match(v530({ ...ok530(), age }).age, /from 0 to 120/, `age ${age}`);
  assert.deepEqual(v530(ok530(), { symptoms: [{ duration_text: 'w'.repeat(60) }] }), {});
  assert.match(v530(ok530(), { symptoms: [{ duration_text: 'w'.repeat(61) }] }).symptoms, /at most 60 characters/);
  assert.match(v530(ok530(), { symptoms: [{ duration_text: 'w\u0008' }] }).symptoms, /without special characters/);
  assert.deepEqual(v530({ ...ok530(), signature_data: 'x'.repeat(SURVEY_LIMITS.signature) }), {});
  assert.match(v530({ ...ok530(), signature_data: 'x'.repeat(SURVEY_LIMITS.signature + 1) }).signature_data, /too large/);
  // Each new field has its place in the reading order.
  for (const k of ['age', 'occupation', 'event_name', 'treatment_list', 'symptoms', 'others_text']) assert.ok(FIELD_ORDER.includes(k), k);
});

test('530: sgDate is the date in Singapore (UTC+8), whatever the device\'s zone', () => {
  assert.equal(sgDate(new Date('2026-11-19T15:59:59Z')), '2026-11-19');
  assert.equal(sgDate(new Date('2026-11-19T16:00:00Z')), '2026-11-20');
  assert.equal(sgDate(new Date('2026-12-31T16:30:00Z')), '2027-01-01');
});

test('530: the server\'s SURVEY_INPUT goes to its field (or near Submit), SURVEY_BUSY near Submit, in its own words', () => {
  assert.deepEqual(mapServerError('SURVEY_INPUT(first_name): Please shorten your name: your first and last name together can be at most 100 characters.'),
    { field: 'first_name', message: 'Please shorten your name: your first and last name together can be at most 100 characters.' });
  assert.deepEqual(mapServerError('SURVEY_INPUT(email): Please enter a valid email address, like name@example.com.'),
    { field: 'email', message: 'Please enter a valid email address, like name@example.com.' });
  assert.equal(mapServerError('SURVEY_INPUT(symptoms): Please tick each symptom only once.').field, 'symptoms');
  assert.deepEqual(mapServerError('SURVEY_INPUT(sex): Please choose Female or Male, or leave it blank.'),
    { scope: 'form', message: 'Please choose Female or Male, or leave it blank.' });
  assert.deepEqual(mapServerError('SURVEY_INPUT(form): This form is too large to send. Please shorten your answers and try again.'),
    { scope: 'form', message: 'This form is too large to send. Please shorten your answers and try again.' });
  assert.deepEqual(mapServerError('SURVEY_BUSY: Many forms have been sent from this connection in the last hour. Please try again later, or ask our consultant for help.'),
    { scope: 'form', message: 'Many forms have been sent from this connection in the last hour. Please try again later, or ask our consultant for help.' });
});
