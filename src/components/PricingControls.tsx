import React, { useState } from 'react';
import { supabase } from '../lib/supabase';
import { InvoiceItem } from '../types';
import { Modal } from './ui';
import { AlertTriangle } from 'lucide-react';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;

/** Member/Non-Member manual override for a product/voucher/promotion line.
 *  Reason required; recorded with user + timestamp; may override eligibility. */
export const LineOverrideModal: React.FC<{
  item: InvoiceItem; lineName: string; onClose: () => void; onDone: () => void;
}> = ({ item, lineName, onClose, onDone }) => {
  const [mode, setMode] = useState<'member' | 'non_member'>(item.price_mode === 'member' ? 'non_member' : 'member');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const submit = async () => {
    if (!reason.trim()) { setErr('An override reason is required.'); return; }
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('override_invoice_line_price', {
      p_item_id: item.id, p_mode: mode, p_reason: reason.trim(),
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    onDone();
  };

  return (
    <Modal title={`Price Override — ${lineName}`} maxWidth={420} onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={submit} disabled={busy}>{busy ? 'Applying…' : 'Apply Override'}</button></>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
          Current: <strong>{item.price_mode === 'member' ? 'Member' : item.price_mode === 'non_member' ? 'Non-Member' : '—'}</strong> · {money(item.unit_price)}
          {item.member_price_snapshot != null && <> · M {money(item.member_price_snapshot)}</>}
          {item.non_member_price_snapshot != null && <> · NM {money(item.non_member_price_snapshot)}</>}
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Charge this line at</label>
          <select value={mode} onChange={e => setMode(e.target.value as any)}>
            <option value="member">Member price</option>
            <option value="non_member">Non-Member price</option>
          </select>
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Reason *</label>
          <input value={reason} onChange={e => setReason(e.target.value)} placeholder="Why is this line being overridden?" autoFocus />
        </div>
        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
          Overrides may bypass Member-Only / Non-Member-Only eligibility. Recorded in the audit log with your name.
        </div>
      </div>
    </Modal>
  );
};

export interface PriceReviewResult {
  review_required: true; old_total: number; new_total: number;
  changes: { item_id: string; kind: string; name: string; old_price: number; new_price: number }[];
}

/** Shown when payment returns review_required: prices changed between invoice
 *  creation and payment (e.g. membership expired). No money was recorded. */
export const PaymentPriceReview: React.FC<{
  review: PriceReviewResult; onClose: () => void; onConfirm: () => void; busy?: boolean;
}> = ({ review, onClose, onConfirm, busy }) => (
  <Modal title="Prices changed — review before paying" maxWidth={480} onClose={onClose}
    footer={<><button className="btn btn-secondary" onClick={onClose}>Not now</button>
      <button className="btn btn-primary" onClick={onConfirm} disabled={busy}>{busy ? 'Paying…' : 'Accept new total & pay'}</button></>}>
    <div className="form-grid">
      <div className="alert alert-warning" style={{ marginBottom: 0 }}>
        <span><AlertTriangle size={14} /></span>
        <div><strong>No payment was taken.</strong> The customer's membership status changed, so these lines were repriced. Review with the customer, then submit the payment again.</div>
      </div>
      <div style={{ fontSize: 13 }}>
        {review.changes.map(ch => (
          <div key={ch.item_id} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid var(--border)' }}>
            <span>{ch.name} <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>({ch.kind})</span></span>
            <span><s style={{ color: 'var(--text-muted)' }}>{money(ch.old_price)}</s> → <strong>{money(ch.new_price)}</strong></span>
          </div>
        ))}
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, fontWeight: 700 }}>
          <span>Invoice total</span>
          <span><s style={{ color: 'var(--text-muted)', fontWeight: 400 }}>{money(review.old_total)}</s> → {money(review.new_total)}</span>
        </div>
      </div>
    </div>
  </Modal>
);
