import React from 'react';
import { Modal } from './ui';
import { AlertTriangle } from 'lucide-react';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;

export interface PriceReviewResult {
  review_required: true; old_total: number; new_total: number;
  changes: { item_id: string; kind: string; name: string; old_price: number; new_price: number }[];
}

/** Shown when payment returns review_required: prices changed between invoice
 *  creation and payment. No money was recorded. */
export const PaymentPriceReview: React.FC<{
  review: PriceReviewResult; onClose: () => void; onConfirm: () => void; busy?: boolean;
}> = ({ review, onClose, onConfirm, busy }) => (
  <Modal title="Prices changed — review before paying" maxWidth={480} onClose={onClose}
    footer={<><button className="btn btn-secondary" onClick={onClose}>Not now</button>
      <button className="btn btn-primary" onClick={onConfirm} disabled={busy}>{busy ? 'Paying…' : 'Accept new total & pay'}</button></>}>
    <div className="form-grid">
      <div className="alert alert-warning" style={{ marginBottom: 0 }}>
        <span><AlertTriangle size={14} /></span>
        <div><strong>No payment was taken.</strong> Store prices changed since this invoice was created, so these lines were repriced. Review with the customer, then submit the payment again.</div>
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
