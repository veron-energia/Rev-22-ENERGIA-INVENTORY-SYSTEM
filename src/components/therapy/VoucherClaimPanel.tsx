import React, { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import './therapy.css';

type Eligible = {
  voucher_id: string; name: string;
  available: number | null; still_offered: boolean;
};
type State = {
  entitlement_id: string; entitlement_no: string; package_name: string;
  entitled: number; claimed: number; revoked: number; remaining: number;
  claim_deadline: string | null; deadline_passed: boolean; status: string;
  cancelled: boolean;
  eligible: Eligible[]; snapshot_present: boolean;
};

const readable = (iso?: string | null) => {
  if (!iso) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return iso;
  const month = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][Number(m[2]) - 1];
  return `${Number(m[3])} ${month} ${m[1]}`;
};

/**
 * Vouchers a customer is owed, claimed a few at a time.
 *
 * The three numbers at the top are the ones the counter conversation starts
 * with, so they are stated plainly rather than left to be worked out from a
 * total and a history.
 *
 * The choices offered are the ones snapshotted when the purchase happened, not
 * whatever the package lists today — a customer who bought in January is owed
 * what they were sold. One that predates the snapshot says so instead of
 * silently offering everything.
 */
export const VoucherClaimPanel: React.FC<{
  entitlementId: string;
  canClaim: boolean;
  onClaimed?: (result: any) => void;
  onClose: () => void;
}> = ({ entitlementId, canClaim, onClaimed, onClose }) => {
  const [state, setState] = useState<State | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [basket, setBasket] = useState<Record<string, number>>({});
  // Two steps. Asking "how many" first is what people actually decide first,
  // and it makes the second step a distribution of a known total rather than
  // an open-ended tally that only reveals its own limit on submission.
  const [step, setStep] = useState<'quantity' | 'distribute'>('quantity');
  const [wanted, setWanted] = useState('');
  const [wantedError, setWantedError] = useState<string | null>(null);
  const wantedRef = React.useRef<HTMLInputElement | null>(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<any | null>(null);

  const load = useCallback(async () => {
    setLoadError(null);
    const { data, error: err } = await supabase.rpc('entitlement_voucher_state',
      { p_entitlement_id: entitlementId });
    if (err) { setLoadError(err.message); setState(null); return; }
    setState(data as State);
    setBasket({}); setStep('quantity'); setWanted(''); setWantedError(null);
  }, [entitlementId]);

  useEffect(() => { void load(); }, [load]);

  const picked = Object.values(basket).reduce((n, q) => n + (q || 0), 0);
  const remaining = state?.remaining ?? 0;
  const requested = Number(wanted) || 0;
  const over = picked > requested;

  // Going back to change the total is allowed; if what is already chosen no
  // longer fits, say so rather than quietly issuing a different number.
  const goBack = () => {
    setStep('quantity');
    setError(picked > 0 && picked !== requested
      ? `You had ${picked} selected. Set a new total, then adjust the selection to match it.`
      : null);
  };
  const goForward = () => {
    const n = Number(wanted);
    if (!Number.isInteger(n) || n <= 0) {
      setWantedError('Enter a whole number of 1 or more.'); wantedRef.current?.focus(); return;
    }
    if (n > remaining) {
      setWantedError(`Only ${remaining} left to collect on this purchase.`); wantedRef.current?.focus(); return;
    }
    setWantedError(null); setError(null); setStep('distribute');
  };

  const setQty = (id: string, q: number, available: number | null) => {
    const ceiling = Math.min(remaining, available ?? Number.MAX_SAFE_INTEGER);
    setBasket(b => ({ ...b, [id]: Math.max(0, Math.min(q, ceiling)) }));
  };

  const submit = async () => {
    setBusy(true); setError(null);
    const selections = Object.entries(basket)
      .filter(([, q]) => q > 0)
      .map(([voucher_id, quantity]) => ({ voucher_id, quantity }));
    const { data, error: err } = await supabase.rpc('claim_entitlement_vouchers', {
      p_entitlement_id: entitlementId,
      p_selections: selections,
      p_note: note.trim() || null,
    });
    setBusy(false);
    if (err) { setError(err.message); return; }
    setDone(data);
    onClaimed?.(data);
    void load();
  };

  return (
    <div className="credit-rules-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="credit-rules" role="dialog" aria-modal="true" aria-labelledby="vc-title">
        <div className="credit-rules-head">
          <h3 id="vc-title">Claim vouchers{state ? ` — ${state.entitlement_no}` : ''}</h3>
          <button type="button" className="credit-rules-close" aria-label="Close" onClick={onClose}>&times;</button>
        </div>

        <div className="credit-rules-body">
          {loadError && (
            <div className="alert alert-danger" role="alert">
              <AlertTriangle size={15} aria-hidden="true" />
              <div><strong>The entitlement could not be loaded.</strong> {loadError}
                <br />Nothing has been claimed.
                <br /><button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }}
                  onClick={() => void load()}><RefreshCw size={13} aria-hidden="true" /> Try again</button>
              </div>
            </div>
          )}

          {state && (
            <>
              <div className="voucher-claim-tally">
                <div><span>{state.entitled}</span>Entitled</div>
                <div><span>{state.claimed}</span>Claimed</div>
                <div className="vc-remaining"><span>{state.remaining}</span>Remaining</div>
                {state.revoked > 0 && <div><span>{state.revoked}</span>Withdrawn</div>}
              </div>
              <p className="credit-rules-hint">
                {state.package_name} · claim by {readable(state.claim_deadline)}
                {state.deadline_passed && ' — the deadline has passed'}
              </p>

              {done && (
                <p role="status" className="voucher-claim-done">
                  Claimed {done.claimed_now}. Document {done.invoice_no}. It records the hand-over
                  only — no payment, and nothing further is owed on it.
                </p>
              )}

              {!state.snapshot_present && (
                <p className="credit-rules-warn">
                  This entitlement predates the record of which vouchers it was sold with, so any
                  reward voucher can be chosen. Check it against the original purchase first.
                </p>
              )}

              {state.cancelled ? (
                <p className="credit-rules-warn">
                  This entitlement was cancelled, so nothing can be claimed against it. The
                  entitled figure is shown for reference only.
                </p>
              ) : state.deadline_passed ? (
                <p className="credit-rules-warn">The claim deadline has passed. Nothing can be claimed.</p>
              ) : state.remaining <= 0 ? (
                <p className="credit-rules-hint">Nothing left to claim on this entitlement.</p>
              ) : step === 'quantity' ? (
                <>
                  <h4 className="vc-step-title">How many vouchers would you like to collect today?</h4>
                  <dl className="vc-facts">
                    <div><dt>From</dt><dd>{state.package_name}</dd></div>
                    <div><dt>Reference</dt><dd>{state.entitlement_no}</dd></div>
                    <div><dt>Total allowance</dt><dd>{state.entitled}</dd></div>
                    <div><dt>Already collected</dt><dd>{state.claimed}</dd></div>
                    {state.revoked > 0 && <div><dt>Withdrawn</dt><dd>{state.revoked}</dd></div>}
                    <div><dt>Still available</dt><dd><b>{state.remaining}</b></dd></div>
                    <div><dt>Collect by</dt><dd>{readable(state.claim_deadline)}</dd></div>
                  </dl>
                  <label className="vc-quantity-label" htmlFor="vc-wanted">
                    Number to collect now
                    <input id="vc-wanted" ref={wantedRef} type="number" inputMode="numeric"
                      min={1} max={state.remaining} step={1} value={wanted}
                      disabled={!canClaim}
                      aria-describedby="vc-wanted-help"
                      aria-invalid={wantedError ? true : undefined}
                      onChange={e => { setWanted(e.target.value); setWantedError(null); }} />
                  </label>
                  <p id="vc-wanted-help" className="credit-rules-hint">
                    A whole number between 1 and {state.remaining}. Whatever is left stays
                    collectable until the deadline.
                  </p>
                  {wantedError && <p className="credit-rules-warn" role="alert">{wantedError}</p>}
                </>
              ) : (
                <>
                  <h4 className="vc-step-title">Which vouchers, and how many of each?</h4>
                  <p className={picked === requested ? 'vc-counter vc-counter-done' : 'vc-counter'}
                     role="status" aria-live="polite">
                    {picked} of {requested} selected
                    {picked < requested && ` — choose ${requested - picked} more`}
                    {picked > requested && ` — that is ${picked - requested} too many`}
                  </p>
                  <table className="voucher-claim-table">
                    <thead><tr><th>Voucher</th><th>In stock</th><th>Collect</th></tr></thead>
                    <tbody>
                      {state.eligible.map(v => (
                        <tr key={v.voucher_id} className={v.still_offered ? '' : 'vc-withdrawn'}>
                          <td>{v.name}{!v.still_offered && <div className="vc-note">no longer offered</div>}</td>
                          <td>{v.available === null ? 'unlimited' : v.available}</td>
                          <td>
                            <input type="number" min={0}
                              max={Math.min(requested, v.available ?? requested)}
                              value={basket[v.voucher_id] ?? 0} disabled={!canClaim || !v.still_offered}
                              onChange={e => setQty(v.voucher_id, Number(e.target.value), v.available)} />
                          </td>
                        </tr>
                      ))}
                      {state.eligible.length === 0 && (
                        <tr><td colSpan={3} className="vc-note">No eligible vouchers are recorded for this entitlement.</td></tr>
                      )}
                    </tbody>
                  </table>
                  <label className="credit-rules-reason">Note (optional)
                    <input value={note} onChange={e => setNote(e.target.value)}
                      placeholder="Anything worth recording about this collection" /></label>
                </>
              )}
            </>
          )}
          {error && <p className="credit-rules-warn" role="alert">{error}</p>}
          {over && <p className="credit-rules-warn">That is {picked - requested} more than the {requested} you asked to collect.</p>}
        </div>

        <div className="credit-rules-foot">
          <button type="button" className="btn" onClick={onClose}>Close</button>
          {canClaim && state && !state.cancelled && !state.deadline_passed && state.remaining > 0 && (
            step === 'quantity' ? (
              <button type="button" className="btn btn-primary" onClick={goForward}>
                Choose vouchers
              </button>
            ) : (
              <>
                <button type="button" className="btn btn-secondary" onClick={goBack}>
                  Change the number
                </button>
                <button type="button" className="btn btn-primary"
                  disabled={busy || picked !== requested || requested <= 0} onClick={submit}>
                  {busy ? 'Collecting…' : `Collect ${requested}`}
                </button>
              </>
            )
          )}
        </div>
      </div>
    </div>
  );
};
