// Pure logic for the public health‑survey form: initial state, "has the customer
// entered anything meaningful?" detection, date‑of‑birth parsing, field
// validation, and mapping recognised server errors back to a field / section.
//
// Kept framework‑free and in .mjs (with a sibling .d.mts) so it can be unit
// tested directly by the Node test runner, matching the repo convention used by
// lib/customer-phones/normalize.mjs.

import { PHONE_LIMIT_MESSAGE } from '../customer-phones/normalize.mjs';

/** Fields that can carry an inline error, in visual reading order. */
export const FIELD_ORDER = [
  'first_name',
  'date_of_birth',
  'age',
  'phone',
  'email',
  'source_option_id',
  'source_details',
  'occupation',
  'event_name',
  'treatment_list',
  'symptoms',
  'others_text',
  'signature_data',
];

/**
 * 530 (security audit of 17 Nov 2026, M4): the sizes submit_health_survey
 * takes, well above the longest answers on file. The page sets them as each
 * box's maxLength and checks them before sending, so the server's refusal
 * (SURVEY_INPUT) is only a backstop.
 */
export const SURVEY_LIMITS = {
  name: 100,            // first and last name together
  email: 254,
  occupation: 100,
  event_name: 100,
  source_details: 200,
  treatment_list: 1000,
  others_text: 1000,
  duration_text: 60,
  age: 120,
  signature: 100000,
};

/** Control characters, which the server refuses in any answer typed (530). */
const CONTROL_RE = /[\u0001-\u001f\u007f-\u009f]/;

/**
 * 530 ("Day it arrives"): today's date in Singapore, YYYY-MM-DD, whatever the
 * device's own time zone. Singapore keeps UTC+8 all year, so no time zone
 * data is needed. The server dates the form the day it arrives (sg_today());
 * the page shows and prints the same day.
 */
export function sgDate(now = new Date()) {
  return new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

/**
 * The form's initial, untouched state. `signedDate` is the pre‑filled "today"
 * value — it is an initial value, so it must never count as an unsaved change.
 */
export function makeInitialForm(signedDate) {
  return {
    first_name: '', last_name: '', full_name: '',
    date_of_birth: '', age: '', sex: '',
    phone: '', email: '', occupation: '',
    source_option_id: '', source_details: '',
    event_name: '',
    has_medical_condition: null, drinks_alcohol: null, smokes: null, on_treatment: null,
    treatment_list: '', others_text: '',
    consent_newsletter_email: false, consent_marketing_email: false,
    consent_marketing_sms: false, consent_marketing_phone: false,
    signature_data: '', signed_date: signedDate,
  };
}

/**
 * Resolve the three day / month / year selects into a status + ISO string.
 * Never converts an impossible date into a real one — "31 February" is
 * `invalid`, not silently rolled to 3 March.
 */
export function parseDob(parts, today = new Date()) {
  const d = String(parts?.d ?? '').trim();
  const m = String(parts?.m ?? '').trim();
  const y = String(parts?.y ?? '').trim();
  const filled = [d, m, y].filter(Boolean).length;
  if (filled === 0) return { status: 'empty', iso: '' };
  if (filled < 3) return { status: 'partial', iso: '' };

  const dd = Number(d), mm = Number(m), yy = Number(y);
  if (![dd, mm, yy].every(Number.isInteger)) return { status: 'invalid', iso: '' };
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31 || yy < 1900) return { status: 'invalid', iso: '' };

  const dt = new Date(yy, mm - 1, dd);
  const real = dt.getFullYear() === yy && dt.getMonth() === mm - 1 && dt.getDate() === dd;
  if (!real) return { status: 'invalid', iso: '' };
  if (dt.getTime() > today.getTime()) return { status: 'invalid', iso: '' };
  if (today.getFullYear() - yy > 130) return { status: 'invalid', iso: '' };

  const iso = `${String(yy).padStart(4, '0')}-${String(mm).padStart(2, '0')}-${String(dd).padStart(2, '0')}`;
  return { status: 'valid', iso };
}

const TEXT_KEYS = [
  'first_name', 'last_name', 'sex', 'email', 'occupation', 'event_name',
  'source_option_id', 'source_details', 'treatment_list', 'others_text',
  'signature_data',
];
const TRISTATE_KEYS = ['has_medical_condition', 'drinks_alcohol', 'smokes', 'on_treatment'];
const CONSENT_KEYS = [
  'consent_newsletter_email', 'consent_marketing_email',
  'consent_marketing_sms', 'consent_marketing_phone',
];

/**
 * True when the customer has entered something worth warning about before they
 * navigate away. Auto‑loaded options, the default signed date, event details and
 * other initial values are ignored; a value returned exactly to its initial
 * state clears the flag.
 */
export function isSurveyDirty(cur, initialForm) {
  const f = cur.form;
  for (const k of TEXT_KEYS) {
    if (String(f[k] ?? '') !== String(initialForm[k] ?? '')) return true;
  }
  for (const k of TRISTATE_KEYS) if (f[k] !== initialForm[k]) return true;
  for (const k of CONSENT_KEYS) if (!!f[k] !== !!initialForm[k]) return true;
  if (f.signed_date !== initialForm.signed_date) return true;

  // Phone: any interaction (typing or confirming the country) counts, and so
  // does a non‑empty value restored from props.
  if (cur.phoneTouched || String(f.phone ?? '').trim() !== '') return true;

  // Date of birth: any of the three selects chosen.
  if (cur.dob?.d || cur.dob?.m || cur.dob?.y) return true;

  // Symptoms: a tick, or a duration typed against one.
  for (const v of Object.values(cur.ticks ?? {})) {
    if (v && (v.on || String(v.duration ?? '').trim() !== '')) return true;
  }
  return false;
}

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/**
 * Validate the whole form. Returns a `{ field: message }` map; empty means OK.
 * Mirrors the deployed `submit_health_survey` rules (supabase/162) and adds no
 * new required fields.
 */
export function validateSurvey(input) {
  const { form, dob, phoneValid, requireSource, sourceRequiresDetails } = input;
  const e = {};

  if (!String(form.first_name ?? '').trim()) {
    e.first_name = 'Please enter your first name.';
  }

  // 530: the name (first and last together) at most 100 characters, no control characters.
  const fullName = [String(form.first_name ?? '').trim(), String(form.last_name ?? '').trim()].filter(Boolean).join(' ');
  if (!e.first_name && fullName.length > SURVEY_LIMITS.name) {
    e.first_name = 'Please shorten your name: your first and last name together can be at most 100 characters.';
  } else if (!e.first_name && CONTROL_RE.test(fullName)) {
    e.first_name = 'Please enter your name without special characters.';
  }

  if (dob.status === 'partial') {
    e.date_of_birth = 'Please choose the day, month and year — or clear all three.';
  } else if (dob.status === 'invalid') {
    e.date_of_birth = 'Please enter a real date that is not in the future.';
  }

  // 530: an age, when given, from 0 to 120.
  const age = String(form.age ?? '').trim();
  if (age && (!/^[0-9]{1,3}$/.test(age) || Number(age) > SURVEY_LIMITS.age)) {
    e.age = 'Please enter an age from 0 to 120, or leave it blank.';
  }

  if (!String(form.phone ?? '').trim() || !phoneValid) {
    e.phone = 'Please enter a valid mobile number and confirm the country.';
  }

  const email = String(form.email ?? '').trim();
  if (!email) e.email = 'Please enter your email address.';
  else if (email.length > SURVEY_LIMITS.email) e.email = 'Please enter an email address of at most 254 characters.';
  else if (!EMAIL_RE.test(email) || CONTROL_RE.test(email)) e.email = 'Please enter a valid email address, like name@example.com.';

  if (requireSource) {
    if (!form.source_option_id) {
      e.source_option_id = 'Please tell us how you heard about us.';
    } else if (sourceRequiresDetails && !String(form.source_details ?? '').trim()) {
      e.source_details = 'Please add a few more details here.';
    }
  }

  // 530: the other answers typed: at most so many characters, no control characters.
  const text = (field, max, tooLong, odd) => {
    const v = String(form[field] ?? '');
    if (v.trim().length > max) e[field] = tooLong;
    else if (CONTROL_RE.test(v)) e[field] = odd;
  };
  if (requireSource && !e.source_details) {
    text('source_details', SURVEY_LIMITS.source_details,
      'Please shorten these details to at most 200 characters.', 'Please enter these details without special characters.');
  }
  text('occupation', SURVEY_LIMITS.occupation,
    'Please shorten your occupation to at most 100 characters.', 'Please enter your occupation without special characters.');
  text('event_name', SURVEY_LIMITS.event_name,
    'Please shorten the event name to at most 100 characters.', 'Please enter the event name without special characters.');
  text('treatment_list', SURVEY_LIMITS.treatment_list,
    'Please shorten the list of treatments to at most 1000 characters.', 'Please enter the list of treatments without special characters.');
  text('others_text', SURVEY_LIMITS.others_text,
    'Please shorten "Others" to at most 1000 characters.', 'Please enter "Others" without special characters.');
  for (const s of input.symptoms ?? []) {
    const d = String(s?.duration_text ?? '');
    if (d.trim().length > SURVEY_LIMITS.duration_text || CONTROL_RE.test(d)) {
      e.symptoms = 'Please keep how long you have had each symptom to at most 60 characters, without special characters.';
      break;
    }
  }

  if (!form.signature_data) {
    e.signature_data = 'Please sign in the box below using your finger or mouse.';
  } else if (String(form.signature_data).length > SURVEY_LIMITS.signature) {
    e.signature_data = 'Your signature is too large to save. Please clear it and sign again.';
  }

  return e;
}

/**
 * Map a raw server error string to the field or section the customer should act
 * on. Never surfaces raw database text for the unrecognised case.
 */
export function mapServerError(raw) {
  const m = String(raw ?? '');

  // 530 (security audit of 17 Nov 2026, M4): an answer the server refused,
  // SURVEY_INPUT(<field>): <what to fix>, shown by that field when the page
  // has one, else near Submit; and the limits per connection and per link,
  // SURVEY_BUSY: <try again later>, near Submit. The answers stay on screen.
  const input = /SURVEY_INPUT\(([a-z_]+)\):\s*([\s\S]+)$/.exec(m);
  if (input) {
    const message = input[2].trim();
    return FIELD_ORDER.includes(input[1]) ? { field: input[1], message } : { scope: 'form', message };
  }
  const busy = /SURVEY_BUSY:\s*([\s\S]+)$/.exec(m);
  if (busy) return { scope: 'form', message: busy[1].trim() };

  // 524 (the user, 18 Nov 2026): the form no longer refuses a form sent again,
  // one for a customer who has a survey, one beside an older survey with no
  // customer, or one beside an old record of that name whose phone cannot be
  // read: each is accepted and waits for staff. These two messages stay for
  // what can still send the codes: a database before 524, and a consultant's
  // record signed at the same moment (HEALTH_SURVEY_ALREADY_EXISTS).
  if (m.includes('HEALTH_SURVEY_ALREADY_EXISTS')) {
    // 468 (the Owner, 24 Oct 2026): neutral words; the reply does not say
    // which of the details typed were found.
    return {
      scope: 'identity',
      message: 'A health survey has already been completed for these details. '
        + 'Please ask our consultant to help update your details.',
    };
  }
  if (m.includes('AMBIGUOUS_CUSTOMER_MATCH')) {
    return {
      scope: 'identity',
      message: 'More than one customer record matches this phone number and name. '
        + 'Please ask our consultant to confirm your identity before submitting.',
    };
  }
  if (m.includes('CUSTOMER_PHONE_LIMIT')) {
    return { field: 'phone', message: PHONE_LIMIT_MESSAGE };
  }
  if (m.includes('CUSTOMER_PHONE_REVIEW')) {
    return { field: 'phone', message: 'Please confirm the phone country and enter a valid international phone number.' };
  }
  if (/valid email address/i.test(m)) {
    return { field: 'email', message: 'Please enter a valid email address, like name@example.com.' };
  }
  if (/how you heard|source option is not available/i.test(m)) {
    return { field: 'source_option_id', message: 'Please tell us how you heard about us.' };
  }
  if (/add a few details/i.test(m)) {
    return { field: 'source_details', message: 'Please add a few more details here.' };
  }
  if (/signature is required/i.test(m)) {
    return { field: 'signature_data', message: 'Please sign in the box below.' };
  }
  if (/document is too large/i.test(m)) {
    return { scope: 'form', message: 'Your signature could not be saved. Please clear it and sign again with a shorter stroke.' };
  }
  if (/link (is not recognised|has been deactivated|has expired)/i.test(m)) {
    return { scope: 'form', message: m };
  }
  return {
    scope: 'form',
    message: 'Sorry — something went wrong sending your form. Please try again in a moment. '
      + 'If it keeps happening, please let our consultant know.',
  };
}
