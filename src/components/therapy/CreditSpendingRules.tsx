import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import './therapy.css';

const money = (n: unknown) => `S$${Number(n || 0).toFixed(2)}`;
const label = (c: string) => c.replace(/_/g, ' ').replace(/^\w/, s => s.toUpperCase());

type Rules = { paid: string[]; bonus: string[]; source?: string; updated_at?: string; updated_by?: string };
type Preview = {
  before: Rules; after: Rules;
  affected_customers: number; affected_paid_credit: number; affected_bonus_credit: number; note?: string;
};

/**
 * What a credit package's paid and bonus credit may be spent on.
 *
 * Owner-only, and the server agrees: set_credit_package_spending_rules refuses
 * anyone else, so a Manager calling the API directly meets the same refusal as
 * a Manager looking at this screen. They can still open it read-only, because
 * knowing what a customer's balance covers is part of serving that customer.
 *
 * Nothing saves without a preview first. A rule change silently re-scopes money
 * customers have already handed over, so the Owner is shown how many people and
 * how much unused credit move before the change is theirs to confirm.
 *
 * Credit buying more credit is never offered here and is refused server-side.
 */
export function CreditSpendingRules({ packageId, packageName, canEdit, onClose }: {
  packageId: string; packageName: string; canEdit: boolean; onClose: () => void;
}) {
  const [categories, setCategories] = useState<string[]>([]);
  const [rules, setRules] = useState<Rules | null>(null);
  const [paid, setPaid] = useState<string[]>([]);
  const [bonus, setBonus] = useState<string[]>([]);
  const [reason, setReason] = useState('');
  const [preview, setPreview] = useState<Preview | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [cats, eff] = await Promise.all([
        supabase.rpc('credit_spendable_categories'),
        supabase.rpc('credit_package_effective_rules', { p_package_id: packageId }),
      ]);
      if (cancelled) return;
      if (cats.error || eff.error) { setError((cats.error || eff.error)!.message); return; }
      setCategories((cats.data as string[]) ?? []);
      const r = (eff.data as Rules) ?? { paid: [], bonus: [] };
      setRules(r); setPaid(r.paid ?? []); setBonus(r.bonus ?? []);
    })();
    return () => { cancelled = true; };
  }, [packageId]);

  const toggle = (list: string[], set: (v: string[]) => void, c: string) =>
    set(list.includes(c) ? list.filter(x => x !== c) : [...list, c]);

  const review = async () => {
    setBusy(true); setError('');
    const { data, error: err } = await supabase.rpc('preview_credit_package_policy_change', {
      p_package_id: packageId, p_paid: paid, p_bonus: bonus,
    });
    setBusy(false);
    if (err) { setError(err.message); return; }
    setPreview(data as Preview);
  };

  const save = async () => {
    if (!reason.trim()) { setError('Give a reason — it is kept in the policy history.'); return; }
    setBusy(true); setError('');
    const { error: err } = await supabase.rpc('set_credit_package_spending_rules', {
      p_package_id: packageId, p_paid: paid, p_bonus: bonus, p_reason: reason.trim(),
    });
    setBusy(false);
    if (err) { setError(err.message); return; }
    setSaved(true);
  };

  const picker = (title: string, hint: string, list: string[], set: (v: string[]) => void) => (
    <fieldset className="credit-rules-set">
      <legend>{title}</legend>
      <p className="credit-rules-hint">{hint}</p>
      <div className="credit-rules-options">
        {categories.map(c => (
          <label key={c} className={list.includes(c) ? 'chosen' : ''}>
            <input type="checkbox" checked={list.includes(c)} disabled={!canEdit}
              onChange={() => toggle(list, set, c)} />
            {label(c)}
          </label>
        ))}
      </div>
      {list.length === 0 && (
        <p className="credit-rules-warn">This credit would not be spendable on anything.</p>
      )}
    </fieldset>
  );

  return (
    <div className="credit-rules-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="credit-rules" role="dialog" aria-modal="true" aria-labelledby="credit-rules-title">
        <div className="credit-rules-head">
          <h3 id="credit-rules-title">Credit spending rules — {packageName}</h3>
          <button type="button" className="credit-rules-close" aria-label="Close" onClick={onClose}>&times;</button>
        </div>

        {rules && (
          <p className="credit-rules-status">
            {rules.source === 'default'
              ? 'Using the approved defaults.'
              : `Changed from the defaults${rules.updated_by ? ` by ${rules.updated_by}` : ''}`
                + `${rules.updated_at ? ` on ${String(rules.updated_at).slice(0, 10)}` : ''}.`}
            {!canEdit && ' Only an Owner can change these.'}
          </p>
        )}

        <div className="credit-rules-body">
          {saved ? (
            <p role="status">
              Saved. Unused balances from this package and every future purchase of it now follow the
              new rules. No balance amount and no past spending changed.
            </p>
          ) : preview ? (
            <>
              <div className="credit-rules-diff">
                <div>
                  <strong>Now</strong>
                  <div>Paid: {(preview.before.paid ?? []).map(label).join(', ') || 'nothing'}</div>
                  <div>Bonus: {(preview.before.bonus ?? []).map(label).join(', ') || 'nothing'}</div>
                </div>
                <div>
                  <strong>Proposed</strong>
                  <div>Paid: {(preview.after.paid ?? []).map(label).join(', ') || 'nothing'}</div>
                  <div>Bonus: {(preview.after.bonus ?? []).map(label).join(', ') || 'nothing'}</div>
                </div>
              </div>
              <ul className="credit-rules-impact">
                <li>{preview.affected_customers} customer{preview.affected_customers === 1 ? '' : 's'} holding
                  unused credit from this package</li>
                <li>{money(preview.affected_paid_credit)} paid credit affected</li>
                <li>{money(preview.affected_bonus_credit)} bonus credit affected</li>
              </ul>
              <p className="credit-rules-hint">
                {preview.note || 'Unused balances and future purchases will use the new rules.'}
              </p>
              <label className="credit-rules-reason">
                Reason <span aria-hidden="true">*</span>
                <textarea rows={2} value={reason} onChange={e => setReason(e.target.value)}
                  placeholder="Why the rules are changing" />
              </label>
            </>
          ) : (
            <>
              {picker('Paid credit', 'What the credit the customer paid for may buy.', paid, setPaid)}
              {picker('Bonus credit', 'What the additional gifted credit may buy.', bonus, setBonus)}
              <p className="credit-rules-hint">
                Credit can never buy another credit package or premium bundle, so those are not offered here.
              </p>
            </>
          )}
          {error && <p className="credit-rules-warn" role="alert">{error}</p>}
        </div>

        <div className="credit-rules-foot">
          {saved ? (
            <button type="button" className="btn btn-primary" onClick={onClose}>Close</button>
          ) : preview ? (
            <>
              <button type="button" className="btn" onClick={() => { setPreview(null); setError(''); }}>Back</button>
              <button type="button" className="btn btn-primary" disabled={busy || !reason.trim()} onClick={save}>
                {busy ? 'Saving…' : 'Save rules'}
              </button>
            </>
          ) : (
            <>
              <button type="button" className="btn" onClick={onClose}>Close</button>
              {canEdit && (
                <button type="button" className="btn btn-primary" disabled={busy} onClick={review}>
                  {busy ? 'Checking…' : 'Review changes'}
                </button>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
