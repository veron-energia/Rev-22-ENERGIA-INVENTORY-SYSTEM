import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, CheckCircle2, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { HolidayCountryField, suggestCountryFromPhone } from './HolidayAdmin';
import { Covered, coverageText } from './coverage';
import { CoverageNotice } from './ExpiryExplanation';
import './therapy.css';

type UnitState = {
  purchased_id: string; entitlement_no: string; unit_label: string; store_id: string;
  offered_choices: ('unlimited' | 'voucher')[]; offers_choice: boolean;
  benefit_choice: 'unlimited' | 'voucher' | null; choice_pending: boolean;
  choice_deadline: string | null; choice_deadline_passed: boolean;
  status: string; duration_months: number | null; voucher_qty: number;
  activation_deadline: string | null; scheduled_date: string | null;
  activation_date: string | null; expiry_date: string | null;
  voucher_entitlement_id: string | null;
  vouchers: { entitled: number; claimed: number; remaining: number; deadline_passed: boolean } | null;
  eligible_vouchers: { voucher_id: string; name: string }[];
  eligible_services: Covered[];
  can_switch: boolean;
  holiday_country: string | null; holiday_region: string | null;
};
type VoucherRow = { voucher_id: string; name: string; available: number | null; offered: boolean };

const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });
const readable = (iso?: string | null) => {
  if (!iso) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return iso;
  const month = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][Number(m[2]) - 1];
  return `${Number(m[3])} ${month} ${m[1]}`;
};
const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

/**
 * Claiming a purchased package, the way a Legacy entitlement is claimed.
 *
 * One window: take unlimited therapy with a start date, or take vouchers. The
 * database chooses and starts (or chooses and hands over) in one transaction,
 * so a failure leaves nothing half-done — and an overlapping start date asks
 * first and records nothing until it is confirmed.
 *
 * Vouchers can be collected a few at a time up to the number. Anyone at the
 * counter can record the choice, start therapy and hand vouchers over, as
 * anyone can when claiming a Legacy entitlement as vouchers; the page still
 * passes canCollectVouchers so a narrower rule can be put back in one place.
 */
export const PurchasedClaimPanel: React.FC<{
  purchasedId: string;
  customerName: string;
  customerPhone?: string | null;
  canCollectVouchers: boolean;
  canSwitch: boolean;
  onDone: () => void;
  onSwitch: () => void;
  onClose: () => void;
}> = ({ purchasedId, customerName, customerPhone, canCollectVouchers, canSwitch, onDone, onSwitch, onClose }) => {
  const [state, setState] = useState<UnitState | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [choice, setChoice] = useState<'unlimited' | 'voucher' | null>(null);
  const [startDate, setStartDate] = useState(sgToday());
  const [countries, setCountries] = useState<any[]>([]);
  const [country, setCountry] = useState<string | null>(null);
  const [region, setRegion] = useState<string | null>(null);
  const [vouchers, setVouchers] = useState<VoucherRow[]>([]);
  const [basket, setBasket] = useState<Record<string, number>>({});
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [overlap, setOverlap] = useState<any | null>(null);
  const [done, setDone] = useState<any | null>(null);
  // One id per attempt: a double click is refused by the server rather than
  // claiming twice. A confirmed overlap is a new attempt.
  const requestRef = useRef<string>(crypto.randomUUID());

  const load = useCallback(async (keepOnError = false) => {
    setLoadError(null);
    const { data, error: err } = await supabase.rpc('purchased_therapy_unit_state', { p_purchased_id: purchasedId });
    // A re-read that fails after a claim went through must not turn the page
    // into "nothing has been claimed": keep what is shown and say it is stale.
    if (err) { setLoadError(err.message); if (!keepOnError) setState(null); return; }
    const s = data as UnitState;
    setState(s);
    if (!keepOnError) {
      const offered = s.benefit_choice ? [s.benefit_choice] : (s.offered_choices ?? []);
      setChoice(offered.length === 1 ? offered[0] : null);
      const suggested = suggestCountryFromPhone(customerPhone);
      setCountry(s.holiday_country ?? suggested.country); setRegion(s.holiday_region ?? null);
    }

    // What each eligible voucher has in stock at the store that sold it.
    const ids = (s.eligible_vouchers ?? []).map(v => v.voucher_id);
    if (ids.length) {
      const [{ data: vs }, { data: stock }] = await Promise.all([
        supabase.from('vouchers').select('id,name,qty_type,is_active,deleted_at,reward_eligible').in('id', ids),
        supabase.from('voucher_store_stock').select('voucher_id,current_qty').eq('store_id', s.store_id).in('voucher_id', ids),
      ]);
      const stockBy = new Map<string, number>(((stock as any[]) ?? []).map(r => [r.voucher_id, Number(r.current_qty ?? 0)]));
      setVouchers(((vs as any[]) ?? []).filter(v => ids.includes(v.id)).map(v => ({
        voucher_id: v.id, name: v.name,
        available: v.qty_type === 'unlimited' ? null : (stockBy.get(v.id) ?? 0),
        offered: !!v.is_active && !v.deleted_at && v.reward_eligible !== false,
      })).sort((a, b) => a.name.localeCompare(b.name)));
    } else setVouchers([]);
  }, [purchasedId, customerPhone]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    void supabase.from('therapy_holiday_countries').select('*').order('name')
      .then(({ data }) => setCountries((data as any[]) ?? []));
  }, []);

  const offered = useMemo(() => !state ? [] : state.benefit_choice ? [state.benefit_choice] : (state.offered_choices ?? []),
    [state]);
  const remaining = !state ? 0
    : state.benefit_choice === 'voucher' ? (state.vouchers?.remaining ?? 0) : (state.voucher_qty ?? 0);
  const picked = Object.values(basket).reduce((n, q) => n + (q || 0), 0);
  const deadline = state?.benefit_choice === 'unlimited' ? state.activation_deadline : state?.choice_deadline ?? state?.activation_deadline;
  const scheduled = state?.status === 'scheduled';
  const deadlinePassed = !!deadline && sgToday() > deadline;
  const covers = state?.eligible_services ?? [];

  const setQty = (id: string, q: number, available: number | null) => {
    const others = picked - (basket[id] ?? 0);
    const ceiling = Math.min(Math.max(remaining - others, 0), available ?? Number.MAX_SAFE_INTEGER);
    setBasket(b => ({ ...b, [id]: Math.max(0, Math.min(Math.floor(q) || 0, ceiling)) }));
  };

  const submit = async (allowOverlap = false) => {
    if (!state || !choice) return;
    setBusy(true); setError(null);
    const selections = Object.entries(basket).filter(([, q]) => q > 0).map(([voucher_id, quantity]) => ({ voucher_id, quantity }));
    const { data, error: err } = await supabase.rpc('claim_purchased_therapy', {
      p_purchased_id: state.purchased_id,
      p_choice: choice,
      p_activation_date: choice === 'unlimited' ? startDate : null,
      p_holiday_country: choice === 'unlimited' ? (country || null) : null,
      p_holiday_region: choice === 'unlimited' ? (region || null) : null,
      p_allow_overlap: allowOverlap,
      p_voucher_selections: choice === 'voucher' && selections.length ? selections : null,
      p_request_id: requestRef.current,
      p_note: note.trim() || null,
    });
    setBusy(false);
    // The id changes only once an attempt is settled. After an error it is kept:
    // if the request did land and only the answer was lost, pressing again is
    // refused as a repeat instead of handing vouchers over twice. (A request
    // the server refused leaves nothing behind, so reusing its id is safe.)
    if (err) {
      setError(err.message);
      // A repeat refusal means the earlier attempt landed: that one is settled,
      // so the next attempt gets a fresh id.
      if (/already been submitted/.test(err.message)) requestRef.current = crypto.randomUUID();
      void load(true); return;
    }
    requestRef.current = crypto.randomUUID();
    const res = data as any;
    if (res?.requires_confirmation) { setOverlap(res); return; }
    setOverlap(null); setDone(res); setBasket({});
    onDone();
    void load(true);
  };

  const title = state ? `Claim — ${state.entitlement_no}` : 'Claim';
  const canSubmit = !!state && !!choice && !busy && !deadlinePassed && (
    choice === 'unlimited'
      ? !!startDate
      : state.benefit_choice === 'voucher' ? picked > 0 && canCollectVouchers : picked <= remaining);

  const footer = (
    <>
      <button className="btn btn-secondary" onClick={onClose}>{done ? 'Done' : 'Cancel'}</button>
      {state && !done && state.benefit_choice && state.can_switch && canSwitch && (
        <button className="btn btn-secondary" onClick={onSwitch}>Switch benefit…</button>)}
      {state && !done && choice && (
        <button className="btn btn-primary" disabled={!canSubmit} onClick={() => void submit(false)}>
          {busy ? 'Claiming…'
            : choice === 'unlimited'
              ? (startDate > sgToday()
                  ? (scheduled ? `Move the start to ${readable(startDate)}` : `Schedule for ${readable(startDate)}`)
                  : 'Start unlimited therapy today')
              : picked > 0 ? `Collect ${plural(picked, 'voucher')}` : 'Take vouchers — collect later'}
        </button>)}
    </>
  );

  return (
    <Modal title={title} maxWidth={540} onClose={onClose} footer={footer}>
      {loadError && !state && (
        <div className="alert alert-danger" role="alert">
          <AlertTriangle size={15} aria-hidden="true" />
          <div><strong>This purchase could not be loaded.</strong> {loadError}
            <br />Nothing has been claimed.
            <br /><button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => void load()}>
              <RefreshCw size={13} aria-hidden="true" /> Try again</button>
          </div>
        </div>
      )}
      {!state && !loadError && <p className="therapy-remaining-hint" aria-live="polite">Loading…</p>}
      {state && loadError && (
        <p className="credit-rules-warn" role="status">This window could not be refreshed ({loadError}); what it shows may be out of date.</p>
      )}

      {state && (
        <div className="form-grid therapy-scope">
          <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
            {customerName} · {state.unit_label}
            <div className="therapy-remaining-hint">
              {deadline && <>Claim by {readable(deadline)}{deadlinePassed && ' — the deadline has passed'}</>}
            </div>
          </div>

          {done && (
            <div className="alert alert-success" role="status" style={{ marginBottom: 0 }}>
              <CheckCircle2 size={15} aria-hidden="true" />
              <div>
                {done.activation ? (
                  <><strong>Unlimited therapy {done.activation.status === 'scheduled' ? 'scheduled' : 'started'}.</strong>{' '}
                    Runs from {readable(done.activation.activation_date)} to {readable(done.activation.expiry_date)} inclusive
                    {done.activation.closure_days_added > 0 &&
                      <> — {plural(done.activation.closure_days_added, 'closure day')} added to a base expiry of {readable(done.activation.base_expiry)}</>}.
                    {covers.length > 0 && <div style={{ marginTop: 4 }}>Covers {coverageText(covers)}.</div>}
                    <CoverageNotice coverage={done.activation.coverage} /></>
                ) : done.claim ? (
                  <><strong>Collected {plural(done.claim.claimed_now, 'voucher')}.</strong>{' '}
                    {(done.claim.issued ?? []).map((v: any) => `${v.quantity} × ${v.name}`).join(', ')}. Document {done.claim.invoice_no}.
                    {done.claim.state?.remaining > 0 && <> {done.claim.state.remaining} still to collect.</>}</>
                ) : (
                  <><strong>Vouchers recorded.</strong> Nothing has been handed over yet; they can be collected
                    here, a few at a time, until {readable(state.choice_deadline)}.</>
                )}
              </div>
            </div>
          )}

          {!done && (
            <>
              {offered.length > 1 && <legend style={{ fontSize: 12.5, fontWeight: 700 }}>What the customer takes</legend>}
              {offered.length === 0 && <p className="credit-rules-warn">This purchase has nothing left to claim.</p>}
              {offered.map(opt => (
                <label key={opt} className={`benefit-option${choice === opt ? ' picked' : ''}`}>
                  <input type="radio" name="claim-benefit" value={opt} checked={choice === opt}
                    disabled={offered.length === 1}
                    onChange={() => { setChoice(opt); setError(null); setOverlap(null); setBasket({}); }} />
                  <span>
                    {opt === 'unlimited' ? (
                      <><strong>Unlimited therapy — {plural(state.duration_months ?? 0, 'calendar month')}</strong>
                        <span className="benefit-option-body">
                          {covers.length
                            ? `As often as they like: ${coverageText(covers)}.`
                            : 'This purchase lists no specific therapy services (it was sold before any were linked, or its package has none).'}
                        </span></>
                    ) : (
                      <><strong>Vouchers — {plural(state.voucher_qty ?? 0, 'voucher')}</strong>
                        <span className="benefit-option-body">
                          {state.eligible_vouchers.length
                            ? `Chosen from ${state.eligible_vouchers.map(v => v.name).join(', ')}.`
                            : 'No vouchers are recorded for this purchase.'}
                          {state.vouchers && ` ${state.vouchers.claimed} collected, ${state.vouchers.remaining} left.`}
                        </span></>
                    )}
                  </span>
                </label>
              ))}

              {choice === 'unlimited' && (
                <>
                  {scheduled && (
                    <p className="credit-rules-hint" style={{ margin: 0 }}>
                      {state.activation_date
                        ? <>Scheduled to start on {readable(state.activation_date)}{state.expiry_date && <>, running to {readable(state.expiry_date)}</>}.</>
                        : <>Marked as scheduled for {readable(state.scheduled_date)}, but no start has been fixed yet.</>}
                      {' '}Choose today to start it now, or another date to move it.
                    </p>
                  )}
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label htmlFor="pc-start">Start date</label>
                    <input id="pc-start" type="date" value={startDate} min={sgToday()}
                      max={state.activation_deadline ?? undefined}
                      onChange={e => { setStartDate(e.target.value); setOverlap(null); }} />
                    <div className="therapy-remaining-hint" style={{ marginTop: 3 }}>
                      Today starts it now; a later date schedules it. It then runs for
                      {' '}{plural(state.duration_months ?? 0, 'calendar month')}, extended by any public
                      holidays or company closures inside that period.
                    </div>
                  </div>
                  <HolidayCountryField countries={countries} value={country} region={region}
                    phone={customerPhone} onChange={(c, r) => { setCountry(c); setRegion(r); }} />
                </>
              )}

              {choice === 'voucher' && (
                <div>
                  <h4 style={{ fontSize: 12.5, marginBottom: 4 }}>
                    Collect now <span className="therapy-remaining-hint">(up to {remaining})</span>
                  </h4>
                  {!canCollectVouchers && (
                    <p className="credit-rules-hint">
                      Only an Owner or Manager can hand vouchers over.
                      {!state.benefit_choice && ' You can still record that the customer takes vouchers; they are collected later.'}
                    </p>
                  )}
                  {vouchers.length === 0 && <p className="credit-rules-warn">No eligible vouchers are recorded for this purchase.</p>}
                  {vouchers.map(v => (
                    <div className="therapy-basket-row" key={v.voucher_id}>
                      <label htmlFor={`pc-q-${v.voucher_id}`}>
                        {v.name}
                        <span className="therapy-remaining-hint">
                          {' '}· {!v.offered ? 'no longer offered' : v.available === null ? 'unlimited stock' : `${v.available} in stock`}
                        </span>
                      </label>
                      <input id={`pc-q-${v.voucher_id}`} type="number" min={0} step={1}
                        max={v.available ?? remaining}
                        value={basket[v.voucher_id] ?? 0}
                        disabled={!canCollectVouchers || !v.offered || deadlinePassed}
                        onChange={e => setQty(v.voucher_id, Number(e.target.value), v.available)} />
                    </div>
                  ))}
                  <p className="therapy-remaining-hint" aria-live="polite" style={{ marginTop: 6 }}>
                    {picked} of {remaining} chosen now
                    {remaining - picked > 0 && ` · ${remaining - picked} stay collectable until ${readable(deadline)}`}
                  </p>
                  <label className="credit-rules-reason">Note (optional)
                    <input value={note} onChange={e => setNote(e.target.value)} placeholder="Anything worth recording" /></label>
                </div>
              )}

              {overlap && (
                <div className="alert alert-warning" style={{ marginBottom: 0 }} role="status">
                  <span>⚠</span>
                  <div>
                    <strong>Nothing has been claimed.</strong> {overlap.reason}
                    {Array.isArray(overlap.existing) && overlap.existing.length > 0 && (
                      <ul style={{ margin: '6px 0 0 18px', fontSize: 12 }}>
                        {overlap.existing.map((x: any, i: number) => (
                          <li key={i}>{x.entitlement_no} — {x.status}, runs to {readable(x.expiry_date)}</li>
                        ))}
                      </ul>
                    )}
                    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 8 }}>
                      {overlap.suggested_start && (
                        <button className="btn btn-primary btn-sm"
                          onClick={() => { setStartDate(overlap.suggested_start); setOverlap(null); }}>
                          Start on {readable(overlap.suggested_start)} instead
                        </button>)}
                      <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => void submit(true)}>
                        Overlap deliberately
                      </button>
                    </div>
                    <div style={{ fontSize: 11, marginTop: 6 }}>
                      Overlapping means the customer pays for two periods covering the same days.
                    </div>
                  </div>
                </div>
              )}

              {!state.benefit_choice && offered.length > 1 && (
                <p className="therapy-remaining-hint" style={{ margin: 0 }}>
                  One or the other, never both.{canSwitch
                    ? ' It can be switched later only while nothing has been used.'
                    : ' Once claimed, only an Owner or Manager can switch it, and only while nothing has been used.'}
                </p>
              )}
            </>
          )}

          {error && <p className="credit-rules-warn" role="alert" style={{ margin: 0 }}>{error}</p>}
        </div>
      )}
    </Modal>
  );
};
