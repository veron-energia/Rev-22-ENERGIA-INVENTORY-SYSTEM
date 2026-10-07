import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import {
  collectable, returnable, handoverProblem, handoverPayload, setPick, emptyPick, returnProblem, returnPayload,
  setReturn, emptyReturn, historyLine, historySource,
  type GoodsStatus, type HandoverAnswer, type HandoverPick, type ReturnEntries, type ReturnField,
} from '../../lib/invoices/handover.mjs';

/* Goods handed over before full payment (399, the Owner, 6 Oct 2026). The
 * database checks every quantity again; these only ask and show. */

const when = (iso: string) => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString('en-SG', { dateStyle: 'medium', timeStyle: 'short' });
};

/** One number box per product still to collect, up to what is still to collect. */
export function HandoverPicker({ goods, pick, onChange, disabled }: {
  goods: GoodsStatus; pick: HandoverPick; onChange: (p: HandoverPick) => void; disabled?: boolean;
}) {
  const rows = collectable(goods);
  return (
    <div data-testid="handover-picker" style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 6 }}>
      {rows.map(p => (
        <div key={p.product_id} style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <div style={{ flex: '1 1 180px', minWidth: 0, overflowWrap: 'anywhere' }}>
            <strong>{p.name}</strong>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
              {p.to_collect} still to collect · {p.in_store} in {goods.store_name || 'the store'}
              {p.via.length > 0 ? ` · in ${p.via.join(', ')}` : ''}
            </div>
          </div>
          <input type="number" min={0} max={p.to_collect} step={1} inputMode="numeric"
            aria-label={`${p.name}: how many taken now`} disabled={disabled}
            value={pick[p.product_id] ? String(pick[p.product_id]) : ''} placeholder="0"
            style={{ width: 90, minHeight: 40 }}
            onChange={e => onChange(setPick(pick, p.product_id, e.target.value))} />
        </div>
      ))}
    </div>
  );
}

/** Record Payment's question for a part payment: "Nothing taken" or the items taken now. */
export function HandoverQuestion({ goods, answer, pick, onAnswer, onPick, disabled }: {
  goods: GoodsStatus; answer: HandoverAnswer; pick: HandoverPick;
  onAnswer: (a: HandoverAnswer) => void; onPick: (p: HandoverPick) => void; disabled?: boolean;
}) {
  // What still stops the payment, once an answer has been started.
  const problem = answer ? handoverProblem(goods, answer, pick) : null;
  return (
    <fieldset data-testid="handover-question" style={{ marginTop: 12, padding: 12, border: '1px solid var(--accent)', borderRadius: 'var(--radius-sm)', minWidth: 0 }}>
      <legend style={{ fontWeight: 700, fontSize: 13, padding: '0 4px' }}>Did the customer take any goods now?</legend>
      <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 6 }}>
        This is a part payment. Goods still to collect leave the shelf when the invoice is paid in full, unless the customer takes them now.
      </div>
      <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
        <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontWeight: 400, minHeight: 40 }}>
          <input type="radio" name="handover-answer" checked={answer === 'none'} disabled={disabled}
            onChange={() => onAnswer('none')} style={{ width: 'auto' }} /> Nothing taken
        </label>
        <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontWeight: 400, minHeight: 40 }}>
          <input type="radio" name="handover-answer" checked={answer === 'items'} disabled={disabled}
            onChange={() => onAnswer('items')} style={{ width: 'auto' }} /> Took items now
        </label>
      </div>
      {answer === 'items' && <HandoverPicker goods={goods} pick={pick} onChange={onPick} disabled={disabled} />}
      {problem && <p role="status" style={{ margin: '8px 0 0', fontSize: 12, color: 'var(--danger)' }}>{problem}</p>}
    </fieldset>
  );
}

/** What was collected and what is still to collect, and the hand-over history.
 *  Once the invoice is paid in full, completed FOC, cancelled or refunded
 *  (goods.open false) nothing is to collect, so only what was collected is
 *  shown, with the history. */
export function InvoiceGoodsPanel({ goods, error, onRecordReturn }: {
  goods: GoodsStatus | null; error?: string | null; onRecordReturn?: () => void;
}) {
  if (error) return <div className="alert alert-warning" style={{ marginBottom: 0 }}><span>⚠</span><div>{error}</div></div>;
  if (!goods) return null;
  const products = goods.products.filter(p => p.required > 0 || p.out > 0);
  if (products.length === 0 && goods.history.length === 0) return null;
  const open = goods.open;
  return (
    <div data-testid="invoice-goods" style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginBottom: 6 }}>
        <div style={{ fontSize: 12.5, fontWeight: 700 }}>
          Goods — {goods.collected_total} collected{open ? `, ${goods.to_collect_total} to collect` : ''}
          {open && goods.fulfil_from_warehouse ? ' (fulfilled from a warehouse at full payment)' : ''}
        </div>
        {goods.can_record_return && onRecordReturn &&
          <button type="button" className="btn btn-secondary btn-sm" onClick={onRecordReturn}>Record items returned</button>}
      </div>
      {products.length > 0 && (
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', fontSize: 12.5 }}>
            <thead><tr><th>Product</th><th style={{ textAlign: 'right' }}>On invoice</th>
              <th style={{ textAlign: 'right' }}>Collected</th>{open && <th style={{ textAlign: 'right' }}>To collect</th>}</tr></thead>
            <tbody>
              {products.map(p => (
                <tr key={p.product_id}>
                  <td style={{ overflowWrap: 'anywhere' }}>{p.name}
                    {p.via.length > 0 && <span style={{ color: 'var(--text-muted)' }}> · in {p.via.join(', ')}</span>}</td>
                  <td style={{ textAlign: 'right' }}>{p.required}</td>
                  <td style={{ textAlign: 'right' }}>{p.collected}</td>
                  {open && <td style={{ textAlign: 'right', fontWeight: p.to_collect > 0 ? 700 : 400 }}>{p.to_collect}</td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {goods.history.length > 0 && (
        <div style={{ marginTop: 6, fontSize: 12 }}>
          {goods.history.map(h => (
            <div key={h.id} style={{ marginBottom: 2 }}>
              <span style={{ color: 'var(--text-muted)' }}>{when(h.created_at)}{h.created_by_name ? ` · ${h.created_by_name}` : ''} · </span>
              {historyLine(h)}
              <span style={{ color: 'var(--text-muted)' }}> ({historySource(h)}){h.reason ? ` — ${h.reason}` : ''}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/** "Hand over items": goods a customer takes on an unpaid or part-paid invoice with no payment. */
export function HandoverModal({ goods, onClose, onDone }: {
  goods: GoodsStatus; onClose: () => void; onDone: (message: string) => void;
}) {
  const [pick, setPickState] = useState<HandoverPick>(emptyPick());
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // One request for this hand-over: a retry after a lost answer finds what it wrote.
  const [requestId] = useState(() => crypto.randomUUID());
  const problem = handoverProblem(goods, 'items', pick, { button: true });
  const save = async () => {
    if (problem) { setErr(problem); return; }
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('record_invoice_handover', {
      p_invoice_id: goods.invoice_id, p_handover: handoverPayload(goods, 'items', pick), p_request_id: requestId,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    const items = ((data as any)?.items ?? []) as { name: string; quantity: number }[];
    onDone(`Handed over: ${items.map(i => `${i.name} × ${i.quantity}`).join(', ')}.`);
  };
  return (
    <Modal title={`Hand over items — ${goods.invoice_no}`} onClose={onClose} confirmClose maxWidth={560}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>Cancel</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || Boolean(problem)} title={problem ?? undefined}>
          {busy ? 'Saving…' : 'Hand over'}</button>
      </>}>
      <p style={{ fontSize: 12.5, marginTop: 0 }}>
        The items the customer takes now leave {goods.store_name || 'the store'}'s stock straight away and are not taken again when the invoice is paid in full.
      </p>
      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}
      <HandoverPicker goods={goods} pick={pick} onChange={setPickState} disabled={busy} />
      {problem && !err && <p role="status" style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 0 }}>{problem}</p>}
    </Modal>
  );
}

const RETURN_FIELDS: [ReturnField, string][] = [['good', 'Good'], ['damaged', 'Damaged'], ['not_returned', 'Not returned']];

/** "Record items returned" (Owner/Manager): good back on the shelf, damaged or not returned written off. */
export function ReturnItemsModal({ goods, onClose, onDone }: {
  goods: GoodsStatus; onClose: () => void; onDone: (message: string) => void;
}) {
  const [entries, setEntries] = useState<ReturnEntries>(emptyReturn());
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [requestId] = useState(() => crypto.randomUUID());
  const rows = returnable(goods);
  const problem = returnProblem(goods, entries, reason);
  const save = async () => {
    if (problem) { setErr(problem); return; }
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('record_invoice_goods_return', {
      p_invoice_id: goods.invoice_id, p_items: returnPayload(goods, entries), p_reason: reason.trim(), p_request_id: requestId,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    onDone('The returned items were recorded.');
  };
  return (
    <Modal title={`Record items returned — ${goods.invoice_no}`} onClose={onClose} confirmClose maxWidth={620}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>Cancel</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || Boolean(problem)} title={problem ?? undefined}>
          {busy ? 'Saving…' : 'Record'}</button>
      </>}>
      <p style={{ fontSize: 12.5, marginTop: 0 }}>
        Goods handed over before full payment that came back. Good goes back into {goods.store_name || 'the store'}'s stock;
        Damaged and Not returned are written off. Once recorded, a correction may take them off the invoice.
      </p>
      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {rows.map(p => (
          <div key={p.product_id} style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
            <div style={{ flex: '1 1 160px', minWidth: 0, overflowWrap: 'anywhere' }}>
              <strong>{p.name}</strong>
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{p.out} with the customer</div>
            </div>
            {RETURN_FIELDS.map(([field, label]) => (
              <label key={field} style={{ display: 'flex', flexDirection: 'column', fontSize: 11.5, fontWeight: 400 }}>
                {label}
                <input type="number" min={0} max={p.out} step={1} inputMode="numeric" disabled={busy}
                  aria-label={`${p.name}: ${label.toLowerCase()}`}
                  value={entries[p.product_id]?.[field] ? String(entries[p.product_id][field]) : ''} placeholder="0"
                  style={{ width: 80, minHeight: 40 }}
                  onChange={e => setEntries(setReturn(entries, p.product_id, field, e.target.value))} />
              </label>
            ))}
          </div>
        ))}
      </div>
      <div className="form-group" style={{ marginTop: 12 }}>
        <label>Reason</label>
        <input value={reason} onChange={e => setReason(e.target.value)} disabled={busy}
          placeholder="e.g. Brought back unused; torn in the bag" />
      </div>
      {problem && !err && <p role="status" style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 0 }}>{problem}</p>}
    </Modal>
  );
}
