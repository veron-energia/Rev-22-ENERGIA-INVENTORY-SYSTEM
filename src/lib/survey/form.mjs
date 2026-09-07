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
  'phone',
  'email',
  'source_option_id',
  'source_details',
  'signature_data',
];

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

  if (dob.status === 'partial') {
    e.date_of_birth = 'Please choose the day, month and year — or clear all three.';
  } else if (dob.status === 'invalid') {
    e.date_of_birth = 'Please enter a real date that is not in the future.';
  }

  if (!String(form.phone ?? '').trim() || !phoneValid) {
    e.phone = 'Please enter a valid mobile number and confirm the country.';
  }

  const email = String(form.email ?? '').trim();
  if (!email) e.email = 'Please enter your email address.';
  else if (!EMAIL_RE.test(email)) e.email = 'Please enter a valid email address, like name@example.com.';

  if (requireSource) {
    if (!form.source_option_id) {
      e.source_option_id = 'Please tell us how you heard about us.';
    } else if (sourceRequiresDetails && !String(form.source_details ?? '').trim()) {
      e.source_details = 'Please add a few more details here.';
    }
  }

  if (!form.signature_data) {
    e.signature_data = 'Please sign in the box below using your finger or mouse.';
  }

  return e;
}

/**
 * Map a raw server error string to the field or section the customer should act
 * on. Never surfaces raw database text for the unrecognised case.
 */
export function mapServerError(raw) {
  const m = String(raw ?? '');

  if (m.includes('HEALTH_SURVEY_ALREADY_EXISTS')) {
    return {
      scope: 'identity',
      message: 'A health survey has already been completed for this phone number and name. '
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
