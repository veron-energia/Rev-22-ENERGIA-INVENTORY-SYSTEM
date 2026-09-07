import data from './rules.json' with { type: 'json' };
const full = (value, pattern) => new RegExp(`^(?:${pattern})$`).test(value);
export function isValidE164(value) {
  if (!/^\+[1-9][0-9]{6,14}$/.test(value ?? '')) return false;
  return data.rules.some(r => {
    if (!value.startsWith('+' + r.code)) return false;
    const national = value.slice(r.code.length + 1);
    return full(national, r.general) && r.types.some(t => t.lengths.includes(national.length) && full(national, t.pattern));
  });
}
export function inspectPhone(original, countryHint = null) {
  const raw = String(original ?? '').trim();
  const result = (normalized, reason, candidates = []) => ({
    normalized, country: normalized?.startsWith('+65') ? 'SG' : normalized?.startsWith('+60') ? 'MY' : null,
    status: normalized ? 'ready' : 'pending_review', reason, candidates,
  });
  if (!raw) return result(null, 'Phone number is empty.');
  if (/[^0-9+\s().-]/.test(raw)) return result(null, 'Unsupported characters or extension; confirm the full phone number.');
  let digits = raw.replace(/[\s().-]/g, '');
  if (digits.startsWith('00')) digits = '+' + digits.slice(2);
  if (digits.startsWith('+')) return isValidE164(digits)
    ? result(digits, 'Validated explicit international country code.', [digits])
    : result(null, 'Invalid explicit international phone number; country code was not changed.');
  if (!/^[0-9]+$/.test(digits)) return result(null, 'Invalid placement of country-code sign.');
  if (/^(65|60)/.test(digits) && isValidE164('+' + digits)) return result('+' + digits, 'Validated country code without plus sign.', ['+' + digits]);
  const sg = /^[3689][0-9]{7}$/.test(digits) && isValidE164('+65' + digits) ? '+65' + digits : null;
  const my = isValidE164('+60' + digits.replace(/^0/, '')) ? '+60' + digits.replace(/^0/, '') : null;
  const candidates = [sg, my].filter(Boolean);
  const hint = countryHint?.trim().toUpperCase();
  if (hint && !['SG', 'MY'].includes(hint)) return result(null, 'Use an explicit international number for this country.', candidates);
  if (hint) {
    const selected = hint === 'SG' ? sg : my;
    return selected ? result(selected, 'Validated using confirmed phone country.', [selected])
      : result(null, 'Number is not valid for the confirmed phone country.', candidates);
  }
  if (sg && my) return result(null, 'Ambiguous Singapore/Malaysia national number; confirm the phone country.', candidates);
  if (sg) return result(sg, 'Valid Singapore national phone pattern.', [sg]);
  if (my && digits.startsWith('0')) return result(my, 'Valid Malaysian domestic number with trunk prefix.', [my]);
  return result(null, my ? 'Possible Malaysian number; confirm country or supply +60.' : 'Invalid or unresolvable national number; confirm country and number.', candidates);
}
export const normalizeName = value => String(value ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
export function matchCustomers(rows, phone, name) {
  const normalized = inspectPhone(phone).normalized;
  if (!normalized || !normalizeName(name)) return { status: 'invalid', matches: [] };
  const matches = rows.filter(c => !c.deleted_at && inspectPhone(c.phone).normalized === normalized && normalizeName(c.full_name) === normalizeName(name));
  return { status: matches.length > 1 ? 'ambiguous' : matches.length === 1 ? 'matched' : 'new', matches };
}
export const PHONE_LIMIT_MESSAGE = 'This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.';
export function phoneErrorMessage(message) {
  if (message.includes('CUSTOMER_PHONE_LIMIT')) return PHONE_LIMIT_MESSAGE;
  if (message.includes('CUSTOMER_PHONE_REVIEW')) return 'Please confirm the phone country and enter a valid international phone number.';
  if (message.includes('AMBIGUOUS_CUSTOMER_MATCH')) return 'More than one customer has this phone number and name. Ask staff to verify and select the correct customer record.';
  return message;
}
