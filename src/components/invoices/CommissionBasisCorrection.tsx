// 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Owner repair, recorded"):
// an Owner corrects one invoice's kept commission rates (535) and line kinds (538), with a reason.
// The window reads what is kept, shows a preview of the commission before and after per tier, and
// saves only after the Owner confirms that preview. Anyone else sees nothing here; the database
// refuses them too (42501).
import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import type { UserRole } from '../../types';
import {
  canCorrectCommissionBasis, basisChanges, COMMISSION_BASIS_MESSAGES, KEPT_RATE_KEYS, KEPT_RATE_LABELS,
  LINE_KIND_LABELS, kindsOffered, newRequestId, type KeptRateKey,
} from '../../lib/permissions/commissions';

type Basis = {
  rates: Partial<Record<KeptRateKey, number>> | null;
  lines: { invoice_item_id: string; name: string; line_kind: string; kind: string; kept: boolean }[];
  totals: { tier1: number; tier2: number };
};
type Result = { before: { tier1: number; tier2: number }; after: { tier1: number; tier2: number } };

const money = (n: unknown) => `S$${Number(n ?? 0).toFixed(2)}`;

export const CommissionBasisCorrection: React.FC<{ invoiceId: string; role?: UserRole | null; onSaved?: () => void }> = ({ invoiceId, role, onSaved }) => {
  const [open, setOpen] = useState(false);
  const [basis, setBasis] = useState<Basis | null>(null);
  const [rates, setRates] = useState<Partial<Record<KeptRateKey, string>>>({});
  const [kinds, setKinds] = useState<Record<string, string>>({});
  const [reason, setReason] = useState('');
  const [preview, setPreview] = useState<Result | null>(null);
  const [done, setDone] = useState<Result | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [requestId, setRequestId] = useState(newRequestId);
  if (!canCorrectCommissionBasis(role)) return null;

  const openWindow = async () => {
    setOpen(true); setErr(null); setPreview(null); setDone(null); setReason(''); setBasis(null); setRequestId(newRequestId());
    const { data, error } = await supabase.rpc('invoice_commission_kept_basis', { p_invoice_id: invoiceId });
    if (error) { setErr(error.message); return; }
    const b = data as Basis;
    setBasis(b);
    setRates(Object.fromEntries(KEPT_RATE_KEYS.map(k => [k, b.rates?.[k] != null ? String(b.rates[k]) : ''])));
    setKinds(Object.fromEntries(b.lines.map(l => [l.invoice_item_id, l.kind])));
  };
  // Any edit means the preview no longer shows what would be saved.
  const edited = () => { setPreview(null); setErr(null); };
  const changes = basis ? basisChanges({ rates: basis.rates, lines: basis.lines }, { rates, kinds }) : null;
  const nothing = !!changes && !changes.error && Object.keys(changes.rates).length === 0 && changes.kinds.length === 0;

  const runPreview = async () => {
    if (!changes || changes.error) { setErr(changes?.error ?? null); return; }
    if (nothing) { setErr(COMMISSION_BASIS_MESSAGES.nothing); return; }
    setBusy(true); setErr(null);
    // A new request id for each preview: a confirm carries the id of exactly what was previewed, so
    // a save whose answer was lost is never mistaken for a later, different one.
    setRequestId(newRequestId());
    const { data, error } = await supabase.rpc('preview_invoice_commission_correction',
      { p_invoice_id: invoiceId, p_rates: changes.rates, p_kinds: changes.kinds });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setPreview(data as Result);
  };
  const confirm = async () => {
    if (!preview || !changes || changes.error) return;
    if (!reason.trim()) { setErr(COMMISSION_BASIS_MESSAGES.reason); return; }
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('correct_invoice_commission_basis',
      { p_invoice_id: invoiceId, p_rates: changes.rates, p_kinds: changes.kinds, p_reason: reason.trim(), p_request_id: requestId });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setDone(data as Result); setPreview(null); onSaved?.();
  };

  return (
    <>
      <button type="button" className="btn btn-secondary btn-sm" data-commission-basis onClick={() => void openWindow()}>
        Commission rates and kinds
      </button>
      {open && (
        <Modal title="Commission rates and line kinds" maxWidth={560} onClose={() => setOpen(false)}
          footer={done
            ? <button className="btn btn-primary" onClick={() => setOpen(false)}>Close</button>
            : <>
                <button className="btn btn-secondary" onClick={() => setOpen(false)}>Cancel</button>
                <button className="btn btn-secondary" disabled={busy || !basis?.rates} onClick={() => void runPreview()}>Preview</button>
                <button className="btn btn-primary" disabled={busy || !preview || !reason.trim()} onClick={() => void confirm()}>
                  {busy ? 'Saving…' : 'Confirm'}
                </button>
              </>}>
          <div className="form-grid" data-commission-basis-window>
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              This invoice keeps the commission rates and line kinds it first earned at. Correct them only to put a mistake
              right: the invoice's commission is worked out again, and anything already paid out is netted against it. The
              change goes in the Audit Log with the reason.
            </div>
            {!basis && !err && <div style={{ fontSize: 12.5 }}>Loading…</div>}
            {basis && !basis.rates && <div className="alert alert-info" data-note="not-earned" style={{ marginBottom: 0 }}><div>{COMMISSION_BASIS_MESSAGES.notEarned}</div></div>}
            {basis?.rates && (
              <>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                  {KEPT_RATE_KEYS.map(k => (
                    <div className="form-group" style={{ marginBottom: 0 }} key={k}>
                      <label htmlFor={`kept-${k}`}>{KEPT_RATE_LABELS[k]} (%)</label>
                      <input id={`kept-${k}`} name={k} type="text" inputMode="decimal" value={rates[k] ?? ''} disabled={!!done}
                        onChange={e => { setRates(r => ({ ...r, [k]: e.target.value })); edited(); }} />
                    </div>
                  ))}
                </div>
                <div>
                  <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 4 }}>Line kinds</div>
                  {basis.lines.map(l => (
                    <div key={l.invoice_item_id} data-line={l.invoice_item_id} style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 4 }}>
                      <span style={{ flex: 1, fontSize: 12.5 }}>{l.name}</span>
                      <select aria-label={`Kind of ${l.name}`} value={kinds[l.invoice_item_id] ?? l.kind} disabled={!!done}
                        onChange={e => { setKinds(m => ({ ...m, [l.invoice_item_id]: e.target.value })); edited(); }}>
                        {kindsOffered(l.line_kind, l.kind).map(k => <option key={k} value={k}>{LINE_KIND_LABELS[k]}</option>)}
                      </select>
                    </div>
                  ))}
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label htmlFor="basis-reason">Reason *</label>
                  <textarea id="basis-reason" rows={2} value={reason} disabled={!!done} onChange={e => setReason(e.target.value)} />
                </div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)' }} data-now>
                  Commission now: Tier 1 {money(basis.totals.tier1)}, Tier 2 {money(basis.totals.tier2)}.
                </div>
              </>
            )}
            {preview && (
              <div className="alert alert-warning" data-preview style={{ marginBottom: 0 }}>
                <div>
                  <div style={{ fontWeight: 600 }}>Check the change before you confirm it:</div>
                  <div>Tier 1: {money(preview.before.tier1)} → {money(preview.after.tier1)}</div>
                  <div>Tier 2: {money(preview.before.tier2)} → {money(preview.after.tier2)}</div>
                </div>
              </div>
            )}
            {done && (
              <div className="alert alert-success" data-done style={{ marginBottom: 0 }}>
                <div>Corrected. Tier 1: {money(done.before.tier1)} → {money(done.after.tier1)}; Tier 2: {money(done.before.tier2)} → {money(done.after.tier2)}.</div>
              </div>
            )}
            {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><div>{err}</div></div>}
          </div>
        </Modal>
      )}
    </>
  );
};

export default CommissionBasisCorrection;
