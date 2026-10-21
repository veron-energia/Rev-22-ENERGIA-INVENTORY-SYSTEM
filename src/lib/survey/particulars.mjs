// Edit details on a health survey (CUSTOMERS-4).
//
// The window used to send every field on every save, with the four yes/no
// declarations as tick boxes, so "Not answered" was saved as "No" and a date
// of birth was written onto the customer each time. It now starts from what
// is stored (a declaration not answered stays not answered), and sends only
// the fields the user changed (update_survey_particulars_v2, 419).

export const DECLARATIONS = ['has_medical_condition', 'drinks_alcohol', 'smokes', 'on_treatment'];
const TEXT_FIELDS = ['first_name', 'last_name', 'phone', 'email', 'date_of_birth', 'sex', 'occupation',
                     'others_text', 'source_option_id', 'source_details', 'treatment_list'];

const tidy = v => {
  const s = v == null ? '' : String(v).trim();
  return s === '' ? null : s;
};
const yesNo = v => (v === true || v === false ? v : null);

/** The draft the window starts from: exactly what is stored. */
export function seedParticulars(survey, symptoms) {
  const s = survey ?? {};
  const draft = {};
  for (const k of TEXT_FIELDS) draft[k] = s[k] == null ? '' : String(s[k]);
  draft.date_of_birth = s.date_of_birth ? String(s.date_of_birth).slice(0, 10) : '';
  for (const k of DECLARATIONS) draft[k] = yesNo(s[k]);
  draft.symptoms = Object.fromEntries((symptoms ?? []).map(x => [String(x.option_id), x.duration_text ?? '']));
  return draft;
}

const symptomList = m => Object.entries(m ?? {})
  .map(([option_id, d]) => ({ option_id, duration_text: tidy(d) }))
  .sort((a, b) => (a.option_id < b.option_id ? -1 : a.option_id > b.option_id ? 1 : 0));

/** Only what changed, as update_survey_particulars_v2 takes it. */
export function particularsChanges(seed, draft) {
  const out = {};
  for (const k of TEXT_FIELDS) {
    if (tidy(seed?.[k]) !== tidy(draft?.[k])) out[k] = tidy(draft?.[k]);
  }
  for (const k of DECLARATIONS) {
    if (yesNo(seed?.[k]) !== yesNo(draft?.[k])) out[k] = yesNo(draft?.[k]);
  }
  // No to treatment clears the list (the server does the same).
  if ('on_treatment' in out && out.on_treatment === false) delete out.treatment_list;
  const a = symptomList(seed?.symptoms);
  const b = symptomList(draft?.symptoms);
  if (JSON.stringify(a) !== JSON.stringify(b)) out.symptoms = b;
  return out;
}

/**
 * Whether the save needs a reason: a date of birth already filled in is
 * changed or cleared (the Owner's rule, Q9), or the phone is changed (it
 * goes onto the customer). customerDob is the customer's own date of birth
 * when the survey has a customer.
 */
export function particularsNeedReason(changes, { hasCustomer = false, customerDob = null } = {}) {
  if (!hasCustomer) return false;
  if ('phone' in changes && changes.phone) return true;
  if ('date_of_birth' in changes) {
    const old = tidy(customerDob);
    return old !== null && old.slice(0, 10) !== (changes.date_of_birth ?? null);
  }
  return false;
}

/** A date of birth already filled in may be changed by an Owner or Manager only (Q9). */
export function dobChangeAllowed(changes, { hasCustomer = false, customerDob = null, role = null } = {}) {
  if (!hasCustomer || !('date_of_birth' in changes)) return true;
  const old = tidy(customerDob);
  if (old === null || old.slice(0, 10) === (changes.date_of_birth ?? null)) return true;
  return role === 'owner' || role === 'manager';
}

/** "Yes", "No" or "Not answered". */
export const answerLabel = v => (v === true ? 'Yes' : v === false ? 'No' : 'Not answered');
