import React, { useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Customer, TherapyEntitlement, TherapyBeneficiary, isOwnerOrManager } from '../types';
import { Modal } from './ui';
import CustomerPicker from './CustomerPicker';
import { Play, ArrowRightLeft, CalendarClock, Ban, PauseCircle, PlayCircle } from 'lucide-react';

const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });

// Preview the inclusive ending date the same way the DB does:
// end = activation + N months - 1 day.
export const previewEnding = (startISO: string, months: number) => {
  if (!startISO || !months) return '';
  const [y, m, d] = startISO.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1 + months, d));
  dt.setUTCDate(dt.getUTCDate() - 1);
  return dt.toISOString().slice(0, 10);
};

// Buttons + dialogs for one beneficiary row. Used by the entitlement modal
// and the Beneficiaries tab so behaviour can't drift between them.
const TherapyBeneficiaryActions: React.FC<{
  beneficiary: TherapyBeneficiary;
  entitlement: TherapyEntitlement;
  customers: Customer[];
  onChanged: () => void;
  onError?: (msg: string) => void;
}> = ({ beneficiary: b, entitlement: e, customers, onChanged, onError }) => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const canChangeDates = profile?.role !== 'inventory_manager';
  const isUnlimited = e.entitlement_kind === 'unlimited';

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const fail = (m: string) => { setErr(m); onError?.(m); };

  const run = async (fn: () => PromiseLike<{ error: any }>) => {
    setBusy(true); setErr(null);
    const { error } = await fn();
    setBusy(false);
    if (error) { fail(error.message); return false; }
    onChanged(); return true;
  };

  const cName = (id: string | null) => id ? (customers.find(c => c.id === id)?.full_name ?? '—') : '—';

  // Activate
  const [actOpen, setActOpen] = useState(false);
  const [actDate, setActDate] = useState(sgToday());
  const activate = async () => {
    const ok = await run(() => supabase.rpc('activate_therapy_beneficiary', {
      p_beneficiary_id: b.id, p_activation_date: actDate, p_ending_override: null }));
    if (ok) setActOpen(false);
  };

  // Transfer
  const [xferOpen, setXferOpen] = useState(false);
  const [xferTo, setXferTo] = useState('');
  const [xferReason, setXferReason] = useState('');
  const transfer = async () => {
    if (!xferTo) { fail('Select the new beneficiary.'); return; }
    const ok = await run(() => supabase.rpc('transfer_therapy_beneficiary', {
      p_beneficiary_id: b.id, p_new_customer_id: xferTo, p_reason: xferReason.trim() || null }));
    if (ok) { setXferOpen(false); setXferTo(''); setXferReason(''); }
  };

  // Status
  const [statAction, setStatAction] = useState<'cancelled' | 'suspended' | 'resume' | null>(null);
  const [statReason, setStatReason] = useState('');
  const setStatus = async () => {
    if (!statAction) return;
    if (!statReason.trim()) { fail('A reason is required.'); return; }
    const ok = await run(() => supabase.rpc('set_therapy_beneficiary_status', {
      p_beneficiary_id: b.id, p_status: statAction, p_reason: statReason.trim() }));
    if (ok) { setStatAction(null); setStatReason(''); }
  };

  // Change dates
  const [dcOpen, setDcOpen] = useState(false);
  const [dcField, setDcField] = useState<'activation_date' | 'ending_date'>('activation_date');
  const [dcValue, setDcValue] = useState('');
  const [dcReason, setDcReason] = useState('');
  const applyDc = async () => {
    if (!dcValue) { fail('Pick the new date.'); return; }
    if (!dcReason.trim()) { fail('A reason is required.'); return; }
    const ok = await run(() => supabase.rpc('request_therapy_date_change', {
      p_beneficiary_id: b.id, p_field: dcField, p_new_value: dcValue, p_reason: dcReason.trim() }));
    if (ok) { setDcOpen(false); setDcValue(''); setDcReason(''); }
  };

  return (
    <>
      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
        {!b.activation_date && b.status !== 'cancelled' && (
          <>
            <button className="btn btn-primary btn-sm" onClick={() => { setActOpen(true); setActDate(sgToday()); }}><Play size={12} /> Activate</button>
            <button className="btn btn-secondary btn-sm" onClick={() => { setXferOpen(true); setXferTo(''); setXferReason(''); }}><ArrowRightLeft size={12} /> Transfer</button>
          </>
        )}
        {b.activation_date && canChangeDates && (
          <button className="btn btn-secondary btn-sm" onClick={() => { setDcOpen(true); setDcField('activation_date'); setDcValue(b.activation_date ?? ''); setDcReason(''); }}><CalendarClock size={12} /> Change Dates</button>
        )}
        {canManage && b.status !== 'cancelled' && (
          <>
            {b.status === 'suspended'
              ? <button className="btn btn-secondary btn-sm" onClick={() => { setStatAction('resume'); setStatReason(''); }}><PlayCircle size={12} /> Resume</button>
              : <button className="btn btn-secondary btn-sm" onClick={() => { setStatAction('suspended'); setStatReason(''); }}><PauseCircle size={12} /> Suspend</button>}
            <button className="btn btn-danger btn-sm" onClick={() => { setStatAction('cancelled'); setStatReason(''); }}><Ban size={12} /> Cancel</button>
          </>
        )}
      </div>

      {actOpen && (
        <Modal title={`Activate — ${cName(b.beneficiary_customer_id)}`} maxWidth={420} onClose={() => setActOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setActOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={activate} disabled={busy}>{busy ? 'Activating…' : 'Activate'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{e.package_name} · {isUnlimited ? `${b.portion_months} month(s)` : `${b.portion_vouchers} voucher(s)`}</div>
            <div className="form-group">
              <label>Activation date (SG) — backdating allowed</label>
              <input type="date" value={actDate} onChange={ev => setActDate(ev.target.value)} />
              {isUnlimited && actDate && (
                <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>
                  Ends (inclusive): <strong>{new Date(previewEnding(actDate, b.portion_months ?? 0)).toLocaleDateString()}</strong>
                </div>
              )}
              {!isUnlimited && <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>Vouchers have no expiry.</div>}
            </div>
          </div>
        </Modal>
      )}

      {xferOpen && (
        <Modal title={`Transfer — ${cName(b.beneficiary_customer_id)}`} maxWidth={460} onClose={() => setXferOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setXferOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={transfer} disabled={busy}>{busy ? 'Transferring…' : 'Transfer'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group">
              <label>New beneficiary</label>
              <CustomerPicker customers={customers} value={xferTo} onChange={setXferTo}
                pinnedId={e.customer_id} excludeId={b.beneficiary_customer_id} />
            </div>
            <div className="form-group"><label>Reason (optional)</label><input value={xferReason} onChange={ev => setXferReason(ev.target.value)} /></div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Transfers are only possible before activation.</div>
          </div>
        </Modal>
      )}

      {statAction && (
        <Modal title={`${statAction === 'cancelled' ? 'Cancel' : statAction === 'suspended' ? 'Suspend' : 'Resume'} — ${cName(b.beneficiary_customer_id)}`}
          maxWidth={420} onClose={() => setStatAction(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setStatAction(null)}>Back</button><button className={`btn ${statAction === 'cancelled' ? 'btn-danger' : 'btn-primary'}`} onClick={setStatus} disabled={busy}>Confirm</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group"><label>Reason *</label><input value={statReason} onChange={ev => setStatReason(ev.target.value)} autoFocus /></div>
          </div>
        </Modal>
      )}

      {dcOpen && (
        <Modal title={`Change dates — ${cName(b.beneficiary_customer_id)}`} maxWidth={460} onClose={() => setDcOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setDcOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={applyDc} disabled={busy}>{busy ? 'Applying…' : 'Apply Change'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Field</label>
                <select value={dcField} onChange={ev => { setDcField(ev.target.value as any); setDcValue((ev.target.value === 'activation_date' ? b.activation_date : b.ending_date) ?? ''); }}>
                  <option value="activation_date">Activation date</option>
                  <option value="ending_date">Ending date (manual override)</option>
                </select>
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}><label>New date</label><input type="date" value={dcValue} onChange={ev => setDcValue(ev.target.value)} /></div>
            </div>
            {dcField === 'activation_date' && isUnlimited && dcValue && (
              <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>New ending date: <strong>{new Date(previewEnding(dcValue, b.portion_months ?? 0)).toLocaleDateString()}</strong> (recalculated automatically)</div>
            )}
            <div className="form-group"><label>Reason *</label><input value={dcReason} onChange={ev => setDcReason(ev.target.value)} /></div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Applied immediately and recorded in the audit log (who, when, old → new, reason).</div>
          </div>
        </Modal>
      )}
    </>
  );
};

export default TherapyBeneficiaryActions;
