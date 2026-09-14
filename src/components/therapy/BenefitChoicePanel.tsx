import React, { useCallback, useEffect, useRef, useState } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import './therapy.css';

type Named = { voucher_id?: string; service_id?: string; name: string };
type UnitState = {
  purchased_id: string; entitlement_no: string; unit_label: string;
  package_name: string; unit_index: number; unit_count: number;
  offered_choices: string[]; offers_choice: boolean;
  benefit_choice: 'unlimited' | 'voucher' | null; choice_pending: boolean;
  choice_deadline: string | null; choice_deadline_passed: boolean;
  status: string; duration_months: number | null; voucher_qty: number;
  activation_date: string | null; scheduled_date: string | null; expiry_date: string | null;
  voucher_entitlement_id: string | null;
  vouchers: { entitled: number; claimed: number; remaining: number } | null;
  eligible_vouchers: Named[]; eligible_services: Named[];
  can_switch: boolean; switch_blocked_reason: string | null;
};

const readable = (iso?: string | null) => {
  if (!iso) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return iso;
  const month = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][Number(m[2]) - 1];
  return `${Number(m[3])} ${month} ${m[1]}`;
};
const months = (n: number | null) =>
  `${n ?? 0} calendar ${(n ?? 0) === 1 ? 'month' : 'months'}`;
const vouchers = (n: number) => `${n} ${n === 1 ? 'voucher' : 'vouchers'}`;

/**
 * Which benefit a purchased unit is taken as.
 *
 * A pending choice is a state, not a fault, so it is described plainly rather
 * than coloured as an error. The two options are labelled from the terms this
 * unit was actually sold with, not from the package as it stands today.
 *
 * Recording a choice is ordinary counter work and uses the ordinary store
 * permission. Changing one that has already been made is not: it is Owner or
 * Manager only, needs a reason, and the server enforces both.
 */
export const BenefitChoicePanel: React.FC<{
  purchasedId: string;
  canSwitch: boolean;
  onDone?: () => void;
  onClose: () => void;
}> = ({ purchasedId, canSwitch, onDone, onClose }) => {
  const [state, setState] = useState<UnitState | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [picked, setPicked] = useState<'unlimited' | 'voucher' | null>(null);
  const [switching, setSwitching] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);
  const reasonRef = useRef<HTMLTextAreaElement | null>(null);

  const load = useCallback(async () => {
    setLoadError(null);
    const { data, error: err } = await supabase.rpc('purchased_therapy_unit_state',
      { p_purchased_id: purchasedId });
    if (err) { setLoadError(err.message); setState(null); return; }
    const s = data as UnitState;
    setState(s); setPicked(null); setSwitching(false); setReason('');
  }, [purchasedId]);

  useEffect(() => { void load(); }, [load]);

  const submitChoice = async () => {
    if (!picked) return;
    setBusy(true); setError(null);
    const { data, error: err } = await supabase.rpc('choose_therapy_benefit', {
      p_purchased_id: purchasedId, p_choice: picked,
      // A stable id per attempt: a retry with the same id is refused by the
      // server rather than creating a second allowance.
      p_request_id: crypto.randomUUID(), p_note: null,
    });
    setBusy(false);
    if (err) { setError(err.message); return; }
    setSaved(picked === 'voucher'
      ? 'Vouchers recorded. Nothing is issued until they are claimed.'
      : 'Unlimited therapy recorded. It has not started — activate it when the customer is ready.');
    void load(); onDone?.();
    void data;
  };

  const submitSwitch = async () => {
    if (!picked) return;
    if (!reason.trim()) { setError('Give a reason for the switch.'); reasonRef.current?.focus(); return; }
    setBusy(true); setError(null);
    const { error: err } = await supabase.rpc('switch_therapy_benefit', {
      p_purchased_id: purchasedId, p_new_choice: picked,
      p_reason: reason.trim(), p_request_id: crypto.randomUUID(),
    });
    setBusy(false);
    if (err) { setError(err.message); return; }
    setSaved('Benefit switched. The previous one has been withdrawn.');
    void load(); onDone?.();
  };

  const option = (value: 'unlimited' | 'voucher', title: string, body: string, note?: string) => {
    const current = state?.benefit_choice === value;
    const disabled = current || (!switching && state?.benefit_choice != null);
    return (
      <label key={value} className={`benefit-option${picked === value ? ' picked' : ''}${current ? ' current' : ''}${disabled && !current ? ' disabled' : ''}`}>
        <input type="radio" name="benefit" value={value} checked={picked === value}
          disabled={disabled} onChange={() => setPicked(value)} />
        <span>
          <strong>{title}</strong>
          <span className="benefit-option-body">{body}</span>
          {note && <span className="benefit-option-note">{note}</span>}
          {current && <span className="benefit-option-note">Currently selected.</span>}
        </span>
      </label>
    );
  };

  return (
    <div className="credit-rules-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="credit-rules" role="dialog" aria-modal="true" aria-labelledby="bc-title">
        <div className="credit-rules-head">
          <h3 id="bc-title">{state ? state.unit_label : 'Benefit'}</h3>
          <button type="button" className="credit-rules-close" aria-label="Close" onClick={onClose}>&times;</button>
        </div>

        <div className="credit-rules-body">
          {loadError && (
            <div className="alert alert-danger" role="alert">
              <AlertTriangle size={15} aria-hidden="true" />
              <div><strong>This purchase could not be loaded.</strong> {loadError}
                <br />Nothing has been changed.
                <br /><button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }}
                  onClick={() => void load()}><RefreshCw size={13} aria-hidden="true" /> Try again</button>
              </div>
            </div>
          )}

          {state && (
            <>
              <p className="credit-rules-status">
                {state.entitlement_no} · {state.status.replace(/_/g, ' ')}
                {state.choice_deadline && <> · choose by {readable(state.choice_deadline)}</>}
              </p>

              {saved && <p role="status" className="voucher-claim-done">{saved}</p>}

              {state.choice_pending && !state.choice_deadline_passed && (
                <p className="credit-rules-hint">
                  No benefit has been chosen yet. Nothing is active and nothing has been issued
                  until one is.
                </p>
              )}
              {state.choice_pending && state.choice_deadline_passed && (
                <p className="credit-rules-warn">
                  The deadline for choosing passed on {readable(state.choice_deadline)}.
                </p>
              )}

              {!state.offers_choice && !state.choice_pending && (
                <p className="credit-rules-hint">
                  This package granted one benefit only, so there is nothing to choose.
                </p>
              )}

              {(state.offers_choice || state.choice_pending) && (
                <div className="benefit-options" role="radiogroup" aria-label="Benefit">
                  {state.offered_choices.includes('unlimited') && option(
                    'unlimited',
                    `Unlimited therapy — ${months(state.duration_months)}`,
                    state.eligible_services.length
                      ? `Covers ${state.eligible_services.map(s => s.name).join(', ')}.`
                      : 'Covers the configured therapy services.',
                    'Recording this does not start it. Activate it separately when the customer is ready.')}
                  {state.offered_choices.includes('voucher') && option(
                    'voucher',
                    `Vouchers — ${vouchers(state.voucher_qty)}`,
                    state.eligible_vouchers.length
                      ? `Chosen from ${state.eligible_vouchers.map(v => v.name).join(', ')}.`
                      : 'Chosen from the package’s eligible vouchers.',
                    'Claim all at once or a few at a time, up to the deadline.')}
                </div>
              )}

              {state.vouchers && (
                <div className="voucher-claim-tally" style={{ marginTop: 10 }}>
                  <div><span>{state.vouchers.entitled}</span>Entitled</div>
                  <div><span>{state.vouchers.claimed}</span>Claimed</div>
                  <div className="vc-remaining"><span>{state.vouchers.remaining}</span>Remaining</div>
                </div>
              )}

              {state.benefit_choice === 'unlimited' && (state.activation_date || state.scheduled_date) && (
                <p className="credit-rules-hint">
                  {state.activation_date ? `Started ${readable(state.activation_date)}` : `Scheduled for ${readable(state.scheduled_date)}`}
                  {state.expiry_date && ` · runs to ${readable(state.expiry_date)}`}.
                </p>
              )}

              {switching && (
                <label className="credit-rules-reason">
                  Reason <span aria-hidden="true">*</span>
                  <textarea ref={reasonRef} rows={2} value={reason}
                    onChange={e => setReason(e.target.value)}
                    placeholder="Why the benefit is being changed" />
                  <span className="therapy-choice-hint">
                    Kept with the purchase, against your name.
                  </span>
                </label>
              )}

              {!state.choice_pending && !switching && (
                <p className={state.can_switch ? 'credit-rules-hint' : 'credit-rules-warn'}>
                  {state.can_switch
                    ? (canSwitch
                        ? 'This choice can still be changed because nothing has been used yet.'
                        : 'Only an Owner or Manager can change a chosen benefit.')
                    : state.switch_blocked_reason}
                </p>
              )}
            </>
          )}
          {error && <p className="credit-rules-warn" role="alert">{error}</p>}
        </div>

        <div className="credit-rules-foot">
          <button type="button" className="btn" onClick={onClose}>Close</button>
          {state && state.choice_pending && !state.choice_deadline_passed && (
            <button type="button" className="btn btn-primary" disabled={busy || !picked}
              onClick={submitChoice}>{busy ? 'Saving…' : 'Confirm choice'}</button>
          )}
          {state && !state.choice_pending && state.can_switch && canSwitch && !switching && (
            <button type="button" className="btn btn-secondary"
              onClick={() => { setSwitching(true); setPicked(null); setError(null); }}>
              Switch benefit
            </button>
          )}
          {state && switching && (
            <button type="button" className="btn btn-primary" disabled={busy || !picked || !reason.trim()}
              onClick={submitSwitch}>{busy ? 'Switching…' : 'Confirm switch'}</button>
          )}
        </div>
      </div>
    </div>
  );
};
