// Pure-logic tests for the public health-survey form helpers.
// Run: node --test scripts/survey/tests/form.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  makeInitialForm, parseDob, isSurveyDirty, validateSurvey, mapServerError, FIELD_ORDER,
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
