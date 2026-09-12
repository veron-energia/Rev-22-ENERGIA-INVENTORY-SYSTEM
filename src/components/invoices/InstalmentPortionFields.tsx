import React from 'react';
import { InvoiceSearchSelect } from './InvoiceSearchSelect';

/** The sentinel the payment-method selector uses for "Instalment". It is an
 *  arrangement, not an account, so it never reaches the database as a method. */
export const INSTALMENT_METHOD = 'instalment';

export type InstalmentPortion = {
  category: '' | 'in_house' | 'provider_funded';
  /** The real method the money comes through. Never INSTALMENT_METHOD. */
  method_id: string;
  months: number | '';
  covered_amount: number;
};

export const emptyPortion: InstalmentPortion = { category: 'in_house', method_id: '', months: 12, covered_amount: 0 };

/** What is wrong with this portion, in a sentence, or null. The server checks
 *  all of this again; this only saves a round trip. */
export function portionProblem(p: InstalmentPortion | undefined, receivedNow: number): string | null {
  if (!p) return 'Fill in the instalment details.';
  if (!p.category) return 'Choose whether the instalment is in-house or provider-funded.';
  if (!p.method_id) return 'Choose the payment method the instalment money actually comes through.';
  if (p.method_id === INSTALMENT_METHOD) return 'An instalment cannot be its own payment method.';
  if (!p.months || Number(p.months) <= 0 || !Number.isInteger(Number(p.months))) {
    return 'Enter a positive whole number of months.';
  }
  if (!(p.covered_amount > 0)) return 'Enter the amount this arrangement covers.';
  if (receivedNow < 0) return 'The amount received now cannot be negative.';
  return null;
}

/**
 * The fields an instalment portion needs, revealed when Instalment is chosen
 * as the payment method.
 *
 * The covered amount and the amount received now are asked for separately on
 * purpose: an in-house arrangement usually receives nothing today, and
 * recording the promise as though it were money is how an invoice ends up
 * marked paid for cash nobody has.
 */
export function InstalmentPortionFields({ value, onChange, methods, receivedNow, onReceivedNow, error }: {
  value: InstalmentPortion;
  onChange: (v: InstalmentPortion) => void;
  methods: { id: string; name: string; is_wallet_credit?: boolean; is_active?: boolean; deleted_at?: string | null }[];
  receivedNow: number;
  onReceivedNow: (n: number) => void;
  error?: string | null;
}) {
  const preset = [3, 6, 9, 12];
  return (
    <fieldset className="instalment-portion">
      <legend>Instalment arrangement</legend>

      <label>Category
        <select value={value.category}
          onChange={e => onChange({ ...value, category: e.target.value as InstalmentPortion['category'] })}>
          <option value="in_house">In-house — the customer pays us over time</option>
          <option value="provider_funded">Provider-funded — a provider settles with us</option>
        </select>
      </label>

      <InvoiceSearchSelect label="Actual payment method" value={value.method_id}
        onChange={id => onChange({ ...value, method_id: id })}
        options={methods
          // Wallet credit is not an instalment channel, and Instalment can
          // never be its own underlying method.
          .filter(m => !m.is_wallet_credit && m.is_active !== false && !m.deleted_at && m.id !== INSTALMENT_METHOD)
          .map(m => ({ value: m.id, label: m.name }))} />

      <label>Duration
        <div className="instalment-months">
          {preset.map(n => (
            <button type="button" key={n}
              className={`btn btn-sm ${Number(value.months) === n ? 'btn-primary' : 'btn-secondary'}`}
              aria-pressed={Number(value.months) === n}
              onClick={() => onChange({ ...value, months: n })}>{n}</button>
          ))}
          <input type="number" min={1} step={1} inputMode="numeric" aria-label="Custom number of months"
            placeholder="Custom" value={preset.includes(Number(value.months)) ? '' : value.months}
            onChange={e => onChange({ ...value, months: e.target.value === '' ? '' : Number(e.target.value) })} />
          <span className="muted">months</span>
        </div>
      </label>

      <label>Amount covered by this arrangement
        <input type="number" min={0} step={0.01} inputMode="decimal" value={value.covered_amount || ''}
          onChange={e => onChange({ ...value, covered_amount: +e.target.value })} />
      </label>

      <label>Amount actually received now
        <input type="number" min={0} step={0.01} inputMode="decimal" value={receivedNow || ''}
          onChange={e => onReceivedNow(+e.target.value)} />
        <small>
          {value.category === 'provider_funded'
            ? 'What the provider has actually settled. Leave at 0 until the money arrives.'
            : 'Any deposit taken today. Leave at 0 if the customer has paid nothing yet — the arrangement on its own settles nothing.'}
        </small>
      </label>

      {error && <p className="instalment-problem" role="alert">{error}</p>}
    </fieldset>
  );
}
