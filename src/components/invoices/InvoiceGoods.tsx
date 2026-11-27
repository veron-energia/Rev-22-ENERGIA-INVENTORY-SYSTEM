import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import {
  collectableProducts, returnableProducts, handoverProblem, handoverPayload, setPick, emptyPick, returnProblem, returnPayload,
  setReturn, emptyReturn, historyLine, historySource,
  collectableSpecials, returnableSpecials, pickedSpecials, setSpecialPick, setSpecialHow, specialHow, specialPicked,
  setSpecialReturn, specialReturned,
  type GoodsStatus, type HandoverAnswer, type HandoverPick, type ReturnEntries, type ReturnField,
} from '../../lib/invoices/handover.mjs';

/* Goods handed over before full payment (399, the Owner, 6 Oct 2026). The
 * database checks every quantity again; these only ask and show.
 * 547 (the Owner, 27 Nov 2026): special, consignment and rental items too, on a
 * paid invoice as well: staff record Collected or, for a consignment sale,
 * Delivered; no stock moves until an Owner or Manager releases the item on
 * Special & Rentals. */

const when = (iso: string) => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString('en-SG', { dateStyle: 'medium', timeStyle: 'short' });
};

/** One number box per product still to collect, up to what is still to collect; 547: and per
 *  special, consignment or rental line, with Collected / Delivered for a consignment sale. */
export function HandoverPicker({ goods, pick, onChange, disabled }: {
  goods: GoodsStatus; pick: HandoverPick; onChange: (p: HandoverPick) => void; disabled?: boolean;
}) {
  const rows = collectableProducts(goods);
  const specials = collectableSpecials(goods);
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
      {specials.map(p => (
        <div key={p.invoice_item_id} data-testid="handover-special" style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <div style={{ flex: '1 1 180px', minWidth: 0, overflowWrap: 'anywhere' }}>
            <strong>{p.name}</strong>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
              {p.to_collect} still to collect · {p.line_kind === 'rental' ? 'rental' : p.is_consignment ? 'consignment' : 'special product'}
              {' '}· released from a warehouse by an Owner or Manager
            </div>
          </div>
          {p.can_deliver && (
            <select aria-label={`${p.name}: collected or delivered`} disabled={disabled}
              value={specialHow(pick, p.invoice_item_id)} style={{ width: 'auto', minHeight: 40 }}
              onChange={e => onChange(setSpecialHow(pick, p.invoice_item_id, e.target.value === 'delivered' ? 'delivered' : 'collected'))}>
              <option value="collected">Collected</option>
              <option value="delivered">Delivered</option>
            </select>
          )}
          <input type="number" min={0} max={p.to_collect} step={1} inputMode="numeric"
            aria-label={`${p.name}: how many ${specialHow(pick, p.invoice_item_id) === 'delivered' ? 'delivered' : 'taken'} now`} disabled={disabled}
            value={specialPicked(pick, p.invoice_item_id) ? String(specialPicked(pick, p.invoice_item_id)) : ''} placeholder="0"
            style={{ width: 90, minHeight: 40 }}
            onChange={e => onChange(setSpecialPick(pick, p.invoice_item_id, e.target.value))} />
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
        {collectableSpecials(goods).length > 0 && ' Special, consignment and rental items the customer takes now are recorded as collected; an Owner or Manager then releases them from a warehouse.'}
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
  // 547: the special, consignment and rental lines, on a paid invoice too.
  const specials = goods.specials ?? [];
  if (products.length === 0 && specials.length === 0 && goods.history.length === 0) return null;
  const open = goods.open;
  const anyDelivered = specials.some(p => p.delivered > 0 || p.can_deliver);
  return (
    <div data-testid="invoice-goods" style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginBottom: 6 }}>
        <div style={{ fontSize: 12.5, fontWeight: 700 }}>
          Goods — {goods.collected_total + (goods.special_collected_total ?? 0)} collected
          {(goods.special_delivered_total ?? 0) > 0 ? `, ${goods.special_delivered_total} delivered` : ''}
          {open || (goods.special_to_collect_total ?? 0) > 0
            ? `, ${(open ? goods.to_collect_total : 0) + (goods.special_to_collect_total ?? 0)} to collect` : ''}
          {open && goods.fulfil_from_warehouse ? ' (fulfilled from a warehouse at full payment)' : ''}
        </div>
        {(goods.can_record_return || goods.can_record_special_return) && onRecordReturn &&
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
      {specials.length > 0 && (
        <div style={{ overflowX: 'auto', marginTop: products.length > 0 ? 6 : 0 }} data-testid="invoice-goods-specials">
          <table style={{ width: '100%', fontSize: 12.5 }}>
            <thead><tr><th>Special, consignment or rental item</th><th style={{ textAlign: 'right' }}>On invoice</th>
              <th style={{ textAlign: 'right' }}>Collected</th>{anyDelivered && <th style={{ textAlign: 'right' }}>Delivered</th>}
              <th style={{ textAlign: 'right' }}>To collect</th></tr></thead>
            <tbody>
              {specials.map(p => (
                <tr key={p.invoice_item_id}>
                  <td style={{ overflowWrap: 'anywhere' }}>{p.name}
                    {p.is_consignment && p.line_kind !== 'rental' && <span style={{ color: 'var(--text-muted)' }}> · consignment</span>}</td>
                  <td style={{ textAlign: 'right' }}>{p.quantity}</td>
                  <td style={{ textAlign: 'right' }}>{p.collected}</td>
                  {anyDelivered && <td style={{ textAlign: 'right' }}>{p.delivered}</td>}
                  <td style={{ textAlign: 'right', fontWeight: p.to_collect > 0 ? 700 : 400 }}>{p.to_collect}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>
            Collected is recorded here when the customer takes the item; it leaves stock when an Owner or Manager releases it on Special &amp; Rentals.
          </div>
        </div>
      )}
      {goods.history.length > 0 && (
        <div style={{ marginTop: 6, fontSize: 12 }}>
          {goods.history.map(h => (
            <div key={h.id} style={{ marginBottom: 2 }}>
              <span style={{ color: 'var(--text-muted)' }}>{when(h.created_at)}{h.created_by_name ? ` · ${h.created_by_name}` : ''} · </span>
              {historyLine(h)}
              <span style={{ color: 'var(--text-muted)' }}> ({historySource(h, goods)}){h.reason ? ` — ${h.reason}` : ''}</span>
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
  // 547: "Record items collected" (no product can be handed over): with nothing entered yet, the
  // hint says what to enter, and one line above Record says at least one is needed.
  const recordOnly = collectableProducts(goods).length === 0;
  const nothingYet = recordOnly && pickedSpecials(goods, pick).length === 0;
  const hint = nothingYet ? 'Enter how many the customer takes now.' : problem;
  const save = async () => {
    if (problem) { setErr(problem); return; }
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('record_invoice_handover', {
      p_invoice_id: goods.invoice_id, p_handover: handoverPayload(goods, 'items', pick), p_request_id: requestId,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    const items = ((data as any)?.items ?? []) as { name: string; quantity: number }[];
    // 547: and the special items, Collected or Delivered.
    const specials = ((data as any)?.specials ?? []) as { name: string; quantity: number; how: string }[];
    onDone([items.length ? `Handed over: ${items.map(i => `${i.name} × ${i.quantity}`).join(', ')}.` : '',
            specials.length ? `Recorded: ${specials.map(i => `${i.name} × ${i.quantity} ${i.how === 'delivered' ? 'delivered' : 'collected'}`).join(', ')}.` : '']
      .filter(Boolean).join(' '));
  };
  return (
    <Modal title={`${collectableProducts(goods).length ? 'Hand over items' : 'Record items collected'} — ${goods.invoice_no}`} onClose={onClose} confirmClose maxWidth={560}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>Cancel</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || Boolean(problem)}
          title={nothingYet ? 'Enter at least one item.' : problem ?? undefined}>
          {busy ? 'Saving…' : collectableProducts(goods).length ? 'Hand over' : 'Record'}</button>
      </>}>
      {collectableProducts(goods).length > 0 && (
        <p style={{ fontSize: 12.5, marginTop: 0 }}>
          The items the customer takes now leave {goods.store_name || 'the store'}'s stock straight away and are not taken again when the invoice is paid in full.
        </p>)}
      {collectableSpecials(goods).length > 0 && (
        <p style={{ fontSize: 12.5, marginTop: 0 }} data-testid="handover-special-note">
          Special, consignment and rental items are recorded as Collected (the customer took it) or Delivered (its supplier brought it to the customer).
          No stock moves here: an Owner or Manager releases each one on Special &amp; Rentals{goods.open ? ', where it now waits for a warehouse' : ''}.
        </p>)}
      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}
      <HandoverPicker goods={goods} pick={pick} onChange={setPickState} disabled={busy} />
      {hint && !err && <p role="status" data-testid="handover-hint" style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 0 }}>{hint}</p>}
      {nothingYet && !err && <p data-testid="handover-need-one" style={{ fontSize: 12, color: 'var(--text-muted)', textAlign: 'right', margin: '12px 0 0' }}>Enter at least one item.</p>}
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
  const rows = returnableProducts(goods);
  const specials = returnableSpecials(goods);
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
      {rows.length > 0 && (
        <p style={{ fontSize: 12.5, marginTop: 0 }}>
          Goods handed over before full payment that came back. Good goes back into {goods.store_name || 'the store'}'s stock;
          Damaged and Not returned are written off. Once recorded, a correction may take them off the invoice.
        </p>)}
      {specials.length > 0 && (
        <p style={{ fontSize: 12.5, marginTop: 0 }} data-testid="return-special-note">
          Special, consignment and rental items that came back. One released from a warehouse or a store goes back there; one sent by its supplier goes back to the supplier, with no stock change.
          A rental already released comes back with Return on Special &amp; Rentals instead. Once recorded, the invoice may be cancelled, corrected or refunded.
        </p>)}
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
        {specials.map(p => (
          <div key={p.invoice_item_id} data-testid="return-special" style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
            <div style={{ flex: '1 1 160px', minWidth: 0, overflowWrap: 'anywhere' }}>
              <strong>{p.name}</strong>
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{p.out} with the customer</div>
            </div>
            <label style={{ display: 'flex', flexDirection: 'column', fontSize: 11.5, fontWeight: 400 }}>
              Returned
              <input type="number" min={0} max={p.out} step={1} inputMode="numeric" disabled={busy}
                aria-label={`${p.name}: returned`}
                value={specialReturned(entries, p.invoice_item_id) ? String(specialReturned(entries, p.invoice_item_id)) : ''} placeholder="0"
                style={{ width: 80, minHeight: 40 }}
                onChange={e => setEntries(setSpecialReturn(entries, p.invoice_item_id, e.target.value))} />
            </label>
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
