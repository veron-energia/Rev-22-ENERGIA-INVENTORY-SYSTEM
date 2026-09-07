import React, { useMemo, useState, useEffect, useRef } from 'react';
import {
  AsYouType, getCountries, getCountryCallingCode, parsePhoneNumberFromString,
  CountryCode,
} from 'libphonenumber-js/max';
import { inspectPhone, isValidE164 } from '../lib/customer-phones/normalize.mjs';

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
  const initialNormalized = inspectPhone(value).normalized;
  const parsedInit = initialNormalized ? parsePhoneNumberFromString(initialNormalized) : undefined;
  const [country, setCountry] = useState<CountryCode | ''>(parsedInit?.country || (value && !initialNormalized ? '' : defaultCountry));
  const emittedValue = useRef<string | null>(null);
  const [national, setNational] = useState<string>(parsedInit ? parsedInit.formatNational() : value);

  // Keep in sync if an external value arrives (e.g. opening an edit modal).
  useEffect(() => {
    if (value === emittedValue.current) return;
    if (!value) { setNational(''); setCountry(defaultCountry); return; }
    const normalized = inspectPhone(value).normalized;
    const p = normalized ? parsePhoneNumberFromString(normalized) : undefined;
    if (p) {
      if (p.country) setCountry(p.country);
      setNational(p.formatNational());
    } else { setNational(value); setCountry(''); }
  }, [value]);

  const countries = useMemo(() => {
    const all = getCountries();
    const rest = all.filter(c => !PRIORITY.includes(c)).sort((a, b) => countryName(a).localeCompare(countryName(b)));
    return [...PRIORITY.filter(c => all.includes(c)), ...rest];
  }, []);

  const notify = (nextValue: string, valid: boolean) => {
    emittedValue.current = nextValue;
    onChange(nextValue, valid);
  };
  const emit = (nextCountry: CountryCode | '', rawNational: string) => {
    if (/[^0-9+\s().-]/.test(rawNational)) {
      setNational(rawNational); notify(rawNational, false); return;
    }
    // Never reinterpret an explicit country code as a national number.
    if (/^(\+|00)/.test(rawNational.trim()) || /^(65|60)[0-9 ()-]+$/.test(rawNational.trim())) {
      const inspected = inspectPhone(rawNational);
      if (inspected.normalized) {
        const p = parsePhoneNumberFromString(inspected.normalized);
        if (p?.country) setCountry(p.country);
        setNational(p?.formatNational() ?? rawNational);
        notify(inspected.normalized, true);
        return;
      }
      if (/^(\+|00)/.test(rawNational.trim())) {
        setNational(rawNational); notify(rawNational, false); return;
      }
    }
    if (!nextCountry) { setNational(rawNational); notify(rawNational, false); return; }
    const formatted = new AsYouType(nextCountry).input(rawNational);
    setNational(formatted);
    const p = parsePhoneNumberFromString(rawNational, nextCountry);
    const e164 = ['SG', 'MY'].includes(nextCountry)
      ? inspectPhone(rawNational, nextCountry).normalized ?? ''
      : p?.number ?? '';
    notify(e164 || rawNational, e164 ? isValidE164(e164) : false);
  };

  return (
    <div className="phone-input">
      <select
        aria-label="Country calling code"
        value={country}
        onChange={e => { const c = e.target.value as CountryCode; setCountry(c); emit(c, national); }}
        className="input">
        <option value="">Confirm phone country</option>
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
export const isPhoneValid = (e164: string) => !!e164 && isValidE164(e164);

export default PhoneInput;
