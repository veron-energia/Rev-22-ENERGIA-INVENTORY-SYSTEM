import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import './therapy.css';

/**
 * Choosing a reward for one qualifying unit.
 *
 * A unit buys ONE alternative — unlimited therapy or vouchers, never both — so
 * the choice is a radio group over the options the database returns, and the
 * claim carries the chosen rule.
 *
 * The important behaviour here is the failure path. Previously an error loading
 * the options and a genuinely empty list looked identical, and the dialog
 * quietly showed the entitlement's own kind — which is why a customer entitled
 * to choose 10 vouchers only ever saw unlimited therapy. Now a failed request
 * says so, and an empty list is explained by the diagnostic, which also names
 * the rule an administrator has to create.
 */

export interface RewardOption {
  // null for the entitlement's own snapshot — the reward as granted, claimable
  // with no rule at all, which is what keeps a historical entitlement claimable
  // after the qualification rules move.
  rule_id: string | null;
  name: string; entitlement_kind: 'unlimited' | 'voucher';
  duration_months: number | null; voucher_qty: number | null;
  tier_key: string | null; applies_to: string; is_current_choice: boolean;
  is_entitlement_snapshot: boolean;
  availability: 'available' | 'retired' | 'as_earned';
}

/** 'YYYY-MM-DD' as "9 Oct 2026". */
const readable = (iso?: string | null) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso ?? '');
  if (!m) return iso ?? '—';
  const month = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][Number(m[2]) - 1];
  return `${Number(m[3])} ${month} ${m[1]}`;
};

/** Radio values must be strings; the snapshot has no rule id to use as one. */
const SNAPSHOT = '__as_earned__';
const optionKey = (o: RewardOption) => o.rule_id ?? SNAPSHOT;
interface VoucherOption { voucher_id: string; name: string; code: string; available_qty: number | null; }

type LoadState = 'idle' | 'loading' | 'ready' | 'failed';

export const RewardChoice: React.FC<{
  entitlement: { id: string; store_id: string | null; entitlement_no?: string;
                 package_name?: string; entitlement_kind?: string; voucher_qty?: number | null;
                 activation_deadline?: string | null };
  claimDate: string;
  holidayCountry?: string | null;
  holidayRegion?: string | null;
  onClaimed: (result: any) => void;
  /** Use another start date: the free day an overlap suggests (THERAPY-M2). */
  onUseDate?: (date: string) => void;
  canManage: boolean;
}> = ({ entitlement, claimDate, holidayCountry, holidayRegion, onClaimed, onUseDate, canManage }) => {
  const [state, setState] = useState<LoadState>('idle');
  const [loadError, setLoadError] = useState<string | null>(null);
  const [options, setOptions] = useState<RewardOption[]>([]);
  const [diagnostic, setDiagnostic] = useState<any | null>(null);
  const [chosen, setChosen] = useState<string>('');
  const [vouchers, setVouchers] = useState<VoucherOption[]>([]);
  const [basket, setBasket] = useState<Record<string, number>>({});
  const [busy, setBusy] = useState(false);
  const [claimError, setClaimError] = useState<string | null>(null);
  // 422: the server asks before a second unlimited period starts on top of
  // one the customer already has. Nothing has been claimed while this shows.
  const [overlap, setOverlap] = useState<any | null>(null);
  useEffect(() => { setOverlap(null); }, [claimDate, chosen]);

  const load = useCallback(async () => {
    setState('loading'); setLoadError(null);
    const [{ data: opts, error: optErr }, { data: diag }] = await Promise.all([
      supabase.rpc('legacy_reward_options', { p_entitlement_id: entitlement.id }),
      supabase.rpc('legacy_reward_options_diagnostic', { p_entitlement_id: entitlement.id }),
    ]);
    if (optErr) {
      // Never fall through to "unlimited only". A failure is a failure.
      setState('failed'); setLoadError(optErr.message); setOptions([]); setDiagnostic(diag ?? null);
      return;
    }
    const list = (opts as RewardOption[]) ?? [];
    setOptions(list); setDiagnostic(diag ?? null); setState('ready');
    const preferred = list.find(o => o.is_current_choice) ?? (list.length === 1 ? list[0] : null);
    setChosen(preferred ? optionKey(preferred) : '');

    const { data: vo } = await supabase.rpc('legacy_reward_voucher_options',
      { p_store_id: entitlement.store_id });
    setVouchers((vo as VoucherOption[]) ?? []);
  }, [entitlement.id, entitlement.store_id]);

  useEffect(() => { void load(); }, [load]);

  const selected = options.find(o => optionKey(o) === chosen) ?? null;
  const required = selected?.entitlement_kind === 'voucher' ? (selected.voucher_qty ?? 0) : 0;
  const picked = useMemo(() => Object.values(basket).reduce((n, q) => n + (q || 0), 0), [basket]);
  const short = required - picked;

  const setQty = (id: string, q: number, available: number | null) => {
    const capped = Math.max(0, Math.min(Math.floor(q) || 0, available ?? Number.MAX_SAFE_INTEGER));
    setBasket(b => ({ ...b, [id]: capped }));
  };

  const submit = async (allowOverlap = false) => {
    setBusy(true); setClaimError(null);
    // Whole numbers of at least one only: the server refuses anything else.
    const selections = Object.entries(basket)
      .filter(([, q]) => Number.isInteger(q) && q > 0).map(([voucher_id, quantity]) => ({ voucher_id, quantity }));
    const { data, error } = await supabase.rpc('claim_legacy_therapy', {
      p_entitlement_id: entitlement.id,
      p_activation_date: claimDate || null,
      // The snapshot is claimed by sending no rule, which is what
      // claim_legacy_therapy has always done with p_rule_id null.
      p_rule_id: chosen === SNAPSHOT ? null : (chosen || null),
      p_voucher_selections: selections.length ? selections : null,
      p_holiday_country: holidayCountry || null,
      p_holiday_region: holidayRegion || null,
      p_allow_overlap: allowOverlap,
    });
    setBusy(false);
    if (error) { setClaimError(error.message); return; }
    if ((data as any)?.requires_confirmation) { setOverlap(data); return; }
    setOverlap(null);
    onClaimed(data);
  };

  if (state === 'loading' || state === 'idle') {
    return <p className="therapy-remaining-hint" aria-live="polite">Loading the reward options…</p>;
  }

  if (state === 'failed') {
    return (
      <div className="alert alert-danger" role="alert">
        <AlertTriangle size={15} aria-hidden="true" />
        <div>
          <strong>The reward options could not be loaded.</strong> {loadError}
          <br />
          Nothing has been claimed. Claiming is disabled until this loads, so a unit
          cannot be spent on the wrong reward by accident.
          <br />
          <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => void load()}>
            <RefreshCw size={13} aria-hidden="true" /> Try again
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="therapy-scope">
      <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
        <legend style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>
          Reward for this qualifying unit
        </legend>

        {diagnostic?.configured_option_count === 0 && (
          <div className="alert alert-info" role="status">
            <AlertTriangle size={15} aria-hidden="true" />
            <div>
              <strong>This entitlement can still be claimed as what it was granted.</strong>{' '}
              No current rule matches its qualifying amount, so there is no alternative to
              choose between — but the reward it earned is unchanged and is offered above.
              {canManage && (
                <p style={{ marginTop: 6 }}>
                  To offer the alternative as well, map it to a reward tier from the
                  Qualification tab.
                </p>
              )}
            </div>
          </div>
        )}

        {options.map(o => (
          <label key={optionKey(o)} className="therapy-inline" style={{ padding: '7px 0' }}>
            <input type="radio" name="reward-option" value={optionKey(o)}
                   checked={chosen === optionKey(o)}
                   onChange={() => { setChosen(optionKey(o)); setBasket({}); }} />
            <span>
              <strong>{o.name}</strong>
              {o.availability === 'as_earned' && (
                <span className="therapy-chip" style={{ marginLeft: 6 }}>as earned</span>
              )}
              {o.availability === 'retired' && (
                <span className="therapy-chip therapy-chip-warn" style={{ marginLeft: 6 }}>no longer offered</span>
              )}
              <span className="therapy-remaining-hint">
                {' '}— {o.entitlement_kind === 'unlimited'
                  ? `${o.duration_months} calendar month${o.duration_months === 1 ? '' : 's'} of unlimited therapy`
                  : `${o.voucher_qty} voucher${o.voucher_qty === 1 ? '' : 's'}`}
              </span>
            </span>
          </label>
        ))}

        {options.length === 1 && diagnostic?.reasons?.length > 0 && (
          <p className="therapy-remaining-hint" style={{ marginTop: 4 }}>
            {diagnostic.reasons[0]}
          </p>
        )}
      </fieldset>

      {selected?.entitlement_kind === 'voucher' && (
        <div style={{ marginTop: 12 }}>
          <h4 style={{ fontSize: 12.5, marginBottom: 4 }}>Choose {required} voucher{required === 1 ? '' : 's'}</h4>
          <p className="therapy-remaining-hint" style={{ marginBottom: 6 }}>
            Any mixture of the types below.
          </p>
          {vouchers.length === 0 && (
            <div className="alert alert-warning" role="status">
              No voucher is currently available as a reward at this store.
            </div>
          )}
          {vouchers.map(v => (
            <div className="therapy-basket-row" key={v.voucher_id}>
              <label htmlFor={`qty-${v.voucher_id}`}>
                {v.name}
                <span className="therapy-remaining-hint">
                  {' '}· {v.available_qty === null ? 'unlimited stock' : `${v.available_qty} in stock`}
                </span>
              </label>
              <input id={`qty-${v.voucher_id}`} type="number" min={0}
                     max={v.available_qty ?? undefined}
                     value={basket[v.voucher_id] ?? 0}
                     onChange={e => setQty(v.voucher_id, Number(e.target.value), v.available_qty)} />
              <span className="therapy-remaining-hint">
                {v.available_qty !== null && (basket[v.voucher_id] ?? 0) > v.available_qty ? 'Over stock' : ''}
              </span>
            </div>
          ))}
          <p className="therapy-remaining-hint" data-over={picked > required} aria-live="polite"
             style={{ marginTop: 8 }}>
            {picked} of {required} chosen
            {short > 0 && <> · {short} still to choose</>}
            {short < 0 && <> · {Math.abs(short)} too many</>}
          </p>
        </div>
      )}

      {overlap && (
        <div className="alert alert-warning" role="status" style={{ marginTop: 10 }} data-overlap="">
          <AlertTriangle size={15} aria-hidden="true" />
          <div>
            <strong>Nothing has been claimed.</strong> {overlap.reason}
            {Array.isArray(overlap.existing) && overlap.existing.length > 0 && (
              <ul style={{ margin: '6px 0 0 18px', fontSize: 12 }}>
                {overlap.existing.map((x: any, i: number) => (
                  <li key={i}>{x.entitlement_no} — {String(x.status).replace('_', ' ')}, runs to {readable(x.expiry_date)}</li>
                ))}
              </ul>
            )}
            {/* The first free day can be after the claim deadline; the claim
                would then be refused, so it is not offered. */}
            {overlap.suggested_start && entitlement.activation_deadline
              && overlap.suggested_start > entitlement.activation_deadline && (
              <div style={{ fontSize: 12, marginTop: 6 }} data-free-after-deadline="">
                The first free day, {readable(overlap.suggested_start)}, is after the claim
                deadline, {readable(entitlement.activation_deadline)}. Start anyway, overlapping,
                or choose another day.
              </div>)}
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 8 }}>
              {overlap.suggested_start && onUseDate
                && (!entitlement.activation_deadline || overlap.suggested_start <= entitlement.activation_deadline) && (
                <button className="btn btn-primary btn-sm" disabled={busy}
                        onClick={() => { onUseDate(overlap.suggested_start); setOverlap(null); }}>
                  Start on {readable(overlap.suggested_start)} instead
                </button>)}
              <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => void submit(true)}>
                Start anyway, overlapping
              </button>
            </div>
            <div style={{ fontSize: 11, marginTop: 6 }}>
              Overlapping means the customer has two periods covering the same days.
            </div>
          </div>
        </div>
      )}

      {claimError && (
        <div className="alert alert-danger" role="alert" style={{ marginTop: 10 }}>
          <AlertTriangle size={15} aria-hidden="true" />
          <div>{claimError}</div>
        </div>
      )}

      <button className="btn btn-primary" style={{ marginTop: 12 }}
              disabled={busy || !chosen || !!overlap || (selected?.entitlement_kind === 'voucher' && short !== 0)}
              onClick={() => void submit()}>
        {busy ? 'Claiming…'
          : selected?.entitlement_kind === 'voucher'
            ? `Claim ${required} voucher${required === 1 ? '' : 's'}`
            : 'Claim unlimited therapy'}
      </button>
      {selected?.entitlement_kind === 'voucher' && short !== 0 && (
        <p className="therapy-remaining-hint" style={{ marginTop: 6 }}>
          Choose exactly {required} to claim. A part-filled basket is not a valid claim.
        </p>
      )}
    </div>
  );
};

/** What was actually issued — written by the database, not predicted by the page. */
export const ClaimConfirmation: React.FC<{ result: any }> = ({ result }) => {
  if (!result) return null;
  const issued = result.issued_vouchers ?? [];
  return (
    <div className="alert alert-success" role="status">
      <CheckCircle2 size={15} aria-hidden="true" />
      <div>
        {result.kind === 'voucher' ? (
          <>
            <strong>Issued.</strong>{' '}
            {issued.length === 0
              ? 'The vouchers have been issued to this customer.'
              : <>These vouchers are now held by the customer:{' '}
                  {issued.map((v: any) => `${v.quantity} × ${v.name}`).join(', ')}.</>}
            <br />
            <span className="therapy-remaining-hint">
              No therapy period was started — a voucher reward does not activate unlimited therapy.
            </span>
          </>
        ) : (
          <>
            <strong>Unlimited therapy {result.status === 'scheduled' ? 'scheduled' : 'activated'}.</strong>{' '}
            Runs from {result.activation_date} to {result.expiry_date} inclusive
            {result.closure_days_added > 0 && <> — {result.closure_days_added} closure day
              {result.closure_days_added === 1 ? '' : 's'} added to a base expiry of {result.base_expiry}</>}.
          </>
        )}
      </div>
    </div>
  );
};
