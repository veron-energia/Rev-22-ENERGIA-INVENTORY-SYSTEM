import React, { useMemo, useState, useEffect } from 'react';
import {
  AsYouType, getCountries, getCountryCallingCode, parsePhoneNumberFromString,
  isValidPhoneNumber, CountryCode,
} from 'libphonenumber-js';

// One reusable phone entry used by ReferralSignup, Public Health Survey and
// Customers (add / change phone). Renders [Country ▼] [National number] and
// emits a canonical E.164 value. Storage/matching stays canonical; only the
// display is prettified.

// Common countries surfaced first (Energia's usual markets); the rest follow.
const PRIORITY: CountryCode[] = ['SG', 'MY', 'MM', 'ID', 'CN', 'HK', 'TW', 'IN', 'AU', 'GB', 'US'];

const REGION_NAMES: Intl.DisplayNames | null = (() => {
  try { return new Intl.DisplayNames(['en'], { type: 'region' }); } catch { return null; }
})();
const countryName = (c: string) => REGION_NAMES?.of(c) ?? c;

interface Props {
  value: string;                                   // canonical E.164, e.g. +6591234567
  onChange: (e164: string, valid: boolean) => void;
  defaultCountry?: CountryCode;                    // default SG
  id?: string;
  autoFocus?: boolean;
}

const PhoneInput: React.FC<Props> = ({ value, onChange, defaultCountry = 'SG', id, autoFocus }) => {
  // Derive initial country + national part from any stored E.164 value.
  const parsedInit = value ? parsePhoneNumberFromString(value) : undefined;
  const [country, setCountry] = useState<CountryCode>((parsedInit?.country as CountryCode) || defaultCountry);
  const [national, setNational] = useState<string>(parsedInit ? parsedInit.formatNational() : '');

  // Keep in sync if an external value arrives (e.g. opening an edit modal).
  useEffect(() => {
    if (!value) return;
    const p = parsePhoneNumberFromString(value);
    if (p) {
      if (p.country) setCountry(p.country as CountryCode);
      setNational(p.formatNational());
    }
  }, [value]);

  const countries = useMemo(() => {
    const all = getCountries();
    const rest = all.filter(c => !PRIORITY.includes(c)).sort((a, b) => countryName(a).localeCompare(countryName(b)));
    return [...PRIORITY.filter(c => all.includes(c)), ...rest];
  }, []);

  const emit = (nextCountry: CountryCode, rawNational: string) => {
    // Gracefully handle a pasted full international value in the national field.
    if (rawNational.trim().startsWith('+')) {
      const p = parsePhoneNumberFromString(rawNational.trim());
      if (p) {
        setCountry((p.country as CountryCode) || nextCountry);
        setNational(p.formatNational());
        onChange(p.number, p.isValid());
        return;
      }
    }
    const formatted = new AsYouType(nextCountry).input(rawNational);
    setNational(formatted);
    const p = parsePhoneNumberFromString(rawNational, nextCountry);
    const e164 = p ? p.number : '';
    onChange(e164, e164 ? isValidPhoneNumber(e164) : false);
  };

  return (
    <div className="phone-input">
      <select
        aria-label="Country calling code"
        value={country}
        onChange={e => { const c = e.target.value as CountryCode; setCountry(c); emit(c, national); }}
        className="input">
        {countries.map(c => (
          <option key={c} value={c}>{countryName(c)} (+{getCountryCallingCode(c)})</option>
        ))}
      </select>
      <input
        id={id}
        className="input"
        type="tel"
        inputMode="tel"
        autoFocus={autoFocus}
        placeholder="Phone number"
        value={national}
        onChange={e => emit(country, e.target.value)} />
    </div>
  );
};

// Convenience validity check for callers that only hold the E.164 string.
export const isPhoneValid = (e164: string) => !!e164 && isValidPhoneNumber(e164);

export default PhoneInput;
