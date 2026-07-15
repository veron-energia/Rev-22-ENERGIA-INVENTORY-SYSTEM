import React, { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Customer, TherapyEntitlement, TherapyBeneficiary, TherapyDateChangeRequest, isOwnerOrManager } from '../types';
import { useAuth } from '../context/AuthContext';
import { Modal } from './ui';
import CustomerPicker from './CustomerPicker';
import TherapyBeneficiaryActions from './TherapyBeneficiaryActions';
import { Plus } from 'lucide-react';

const fmt = (d: string | null) => d ? new Date(d).toLocaleDateString() : '—';

export const STATUS_CLS: Record<string, string> = {
  pending_activation: 'badge-muted', scheduled: 'badge-primary', active: 'badge-success',
  ended: 'badge-muted', expired_before_activation: 'badge-danger', cancelled: 'badge-danger', suspended: 'badge-warning',
};
export const statusBadge = (s: string) => <span className={`badge ${STATUS_CLS[s] ?? 'badge-muted'}`}>{s.replace(/_/g, ' ')}</span>;

const TherapyEntitlementModal: React.FC<{
  entitlement: TherapyEntitlement;
  beneficiaries: TherapyBeneficiary[];
  dateRequests: TherapyDateChangeRequest[];
  customers: Customer[];
  onClose: () => void;
  onChanged: () => void;
}> = ({ entitlement: e, beneficiaries, dateRequests, customers, onClose, onChanged }) => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const cName = (id: string | null) => id ? (customers.find(c => c.id === id)?.full_name ?? '—') : '—';
  const mine = beneficiaries.filter(b => b.entitlement_id === e.id);
  const isUnlimited = e.entitlement_kind === 'unlimited';
  const totalPortion = isUnlimited ? (e.duration_months ?? 0) : (e.voucher_qty ?? 0);
  const usedPortion = mine.filter(b => b.status !== 'cancelled')
    .reduce((s, b) => s + Number((isUnlimited ? b.portion_months : b.portion_vouchers) ?? 0), 0);
  const remaining = totalPortion - usedPortion;

  // ---- Assign ----
  const [addOpen, setAddOpen] = useState(false);
  const [addCust, setAddCust] = useState(e.customer_id);
  const [addPortion, setAddPortion] = useState(1);
  const assign = async () => {
    if (!addCust) { setErr('Select a beneficiary.'); return; }
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('assign_therapy_beneficiary', {
      p_entitlement_id: e.id, p_customer_id: addCust,
      p_portion_months: isUnlimited ? addPortion : null,
      p_portion_vouchers: isUnlimited ? null : addPortion,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setAddOpen(false); setAddCust(e.customer_id); setAddPortion(1); onChanged();
  };

  const pendingDc = dateRequests.filter(d => d.status === 'pending' && mine.some(b => b.id === d.beneficiary_id));

  return (
    <Modal title={`${e.entitlement_no} — ${e.package_name}`} maxWidth={760} onClose={onClose}
      footer={<button className="btn btn-secondary" onClick={onClose}>Close</button>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}

        <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
          Buyer on the invoice: <strong>{cName(e.customer_id)}</strong> · Activate by <strong>{fmt(e.activation_deadline)}</strong> ·{' '}
          {isUnlimited ? `${e.duration_months} month(s)` : `${e.voucher_qty} voucher(s)`} total ·{' '}
          <span style={{ color: remaining > 0 ? 'var(--primary)' : 'var(--text-muted)' }}>{remaining} unassigned</span>
        </div>

        {pendingDc.length > 0 && (
          <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
            <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>Pending date-change requests</div>
            {pendingDc.map(d => (
              <div key={d.id} style={{ fontSize: 12.5, marginBottom: 4 }}>
                {d.field.replace('_', ' ')}: {fmt(d.old_value)} → <strong>{fmt(d.new_value)}</strong>{' '}
                <span style={{ color: 'var(--text-muted)' }}>({d.reason})</span>
              </div>
            ))}
          </div>
        )}

        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
            <label style={{ margin: 0 }}>Beneficiaries</label>
            {remaining > 0 && <button className="btn btn-secondary btn-sm" onClick={() => { setAddOpen(true); setAddCust(e.customer_id); setAddPortion(remaining || 1); }}><Plus size={13} /> Assign</button>}
          </div>

          {addOpen && (
            <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10, marginBottom: 8 }}>
              <div className="form-group" style={{ marginBottom: 8 }}>
                <label>Beneficiary — search by name, phone or email</label>
                <CustomerPicker customers={customers} value={addCust} onChange={setAddCust} pinnedId={e.customer_id} />
              </div>
              <div className="form-group" style={{ marginBottom: 8 }}>
                <label>{isUnlimited ? 'Months' : 'Vouchers'} (max {remaining})</label>
                <input type="number" min={1} max={remaining} value={addPortion} onChange={ev => setAddPortion(+ev.target.value)} style={{ maxWidth: 140 }} />
              </div>
              <div style={{ display: 'flex', gap: 6 }}>
                <button className="btn btn-primary btn-sm" onClick={assign} disabled={busy}>{busy ? 'Assigning…' : 'Assign'}</button>
                <button className="btn btn-secondary btn-sm" onClick={() => setAddOpen(false)}>Cancel</button>
              </div>
            </div>
          )}

          <div className="table-wrap">
            <table>
              <thead><tr><th>Beneficiary</th><th>Portion</th><th>Activated</th><th>Ends</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {mine.length === 0 && <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 16 }}>No beneficiaries assigned yet</td></tr>}
                {mine.map(b => (
                  <tr key={b.id}>
                    <td><strong>{cName(b.beneficiary_customer_id)}</strong>
                      {b.transferred_from && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>transferred from {cName(b.transferred_from)}</div>}</td>
                    <td style={{ fontSize: 12.5 }}>{isUnlimited ? `${b.portion_months} mo` : `${b.portion_vouchers} vouchers`}</td>
                    <td style={{ fontSize: 12.5 }}>{fmt(b.activation_date)}</td>
                    <td style={{ fontSize: 12.5 }}>{isUnlimited ? fmt(b.ending_date) : <span style={{ color: 'var(--text-muted)' }}>no expiry</span>}</td>
                    <td>{statusBadge(b.status)}</td>
                    <td><TherapyBeneficiaryActions beneficiary={b} entitlement={e} customers={customers} onChanged={onChanged} onError={setErr} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Modal>
  );
};

export default TherapyEntitlementModal;
