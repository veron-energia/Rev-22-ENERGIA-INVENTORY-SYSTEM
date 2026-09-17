import React from 'react';
import { InvoiceSearchSelect } from './InvoiceSearchSelect';

/** The sentinel the payment-method selector uses for "Instalment". It is a
 *  label on the payment, not an account, so it never reaches the database as
 *  a method. */
export const INSTALMENT_METHOD = 'instalment';

export type InstalmentPortion = {
  /** The real method the money comes through. Never INSTALMENT_METHOD. */
  method_id: string;
  months: number | '';
};

export const emptyPortion: InstalmentPortion = { method_id: '', months: 12 };

/**
 * What is wrong with this portion, in a sentence, or null.
 *
 * The amount is the money received now, and it is required: an instalment here
 * records a payment that has been taken, not a promise to pay later. The server
 * checks all of this again; this only saves a round trip.
 */
export function portionProblem(p: InstalmentPortion | undefined, receivedNow: number): string | null {
  if (!p) return 'Fill in the instalment details.';
  if (!p.method_id) return 'Choose the payment method the instalment money actually comes through.';
  if (p.method_id === INSTALMENT_METHOD) return 'An instalment cannot be its own payment method.';
  if (!p.months || Number(p.months) <= 0 || !Number.isInteger(Number(p.months))) {
    return 'Enter a positive whole number of months.';
  }
  if (!(receivedNow > 0)) return 'Enter the amount received for this instalment.';
  return null;
}

/**
 * The fields an instalment needs, revealed when Instalment is chosen as the
 * payment method.
 *
 * An instalment here is a label on money that has arrived, not an arrangement
 * to collect it later: the amount settles the invoice today and no
 * invoice_payment_arrangements row is written. The duration is recorded on the
 * invoice for reference, which is what instalmentText displays.
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
      <legend>Instalment</legend>

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

      <label>Amount
        <input type="number" min={0} step={0.01} inputMode="decimal" value={receivedNow || ''}
          onChange={e => onReceivedNow(+e.target.value)} />
        <small>What the customer is paying through this instalment. It settles the
          invoice today; nothing is left outstanding to collect later.</small>
      </label>

      {error && <p className="instalment-problem" role="alert">{error}</p>}
    </fieldset>
  );
}
