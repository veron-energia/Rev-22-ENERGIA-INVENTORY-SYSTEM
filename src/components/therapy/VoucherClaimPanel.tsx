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
    setBasket({});
  }, [entitlementId]);

  useEffect(() => { void load(); }, [load]);

  const picked = Object.values(basket).reduce((n, q) => n + (q || 0), 0);
  const remaining = state?.remaining ?? 0;
  const over = picked > remaining;

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

              {state.deadline_passed ? (
                <p className="credit-rules-warn">The claim deadline has passed. Nothing can be claimed.</p>
              ) : state.remaining <= 0 ? (
                <p className="credit-rules-hint">Nothing left to claim on this entitlement.</p>
              ) : (
                <>
                  <p className="credit-rules-hint">
                    Take any number up to {state.remaining}. The rest stays claimable until the deadline.
                  </p>
                  <table className="voucher-claim-table">
                    <thead><tr><th>Voucher</th><th>In stock</th><th>Claim</th></tr></thead>
                    <tbody>
                      {state.eligible.map(v => (
                        <tr key={v.voucher_id} className={v.still_offered ? '' : 'vc-withdrawn'}>
                          <td>{v.name}{!v.still_offered && <div className="vc-note">no longer offered</div>}</td>
                          <td>{v.available === null ? 'unlimited' : v.available}</td>
                          <td>
                            <input type="number" min={0}
                              max={Math.min(state.remaining, v.available ?? state.remaining)}
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
                      placeholder="Anything worth recording about this claim" /></label>
                </>
              )}
            </>
          )}
          {error && <p className="credit-rules-warn" role="alert">{error}</p>}
          {over && <p className="credit-rules-warn">That is {picked - remaining} more than remains.</p>}
        </div>

        <div className="credit-rules-foot">
          <button type="button" className="btn" onClick={onClose}>Close</button>
          {canClaim && state && !state.deadline_passed && state.remaining > 0 && (
            <button type="button" className="btn btn-primary" disabled={busy || picked <= 0 || over}
              onClick={submit}>
              {busy ? 'Claiming…' : picked > 0 ? `Claim ${picked}` : 'Claim'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
