import React, { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';

const money = (n: unknown) => `S$${Number(n || 0).toFixed(2)}`;

type Action = 'cancel' | 'refund_full' | 'refund_partial';
type PlanLine = { invoice_item_id: string; name: string; line_kind: string; quantity: number; selected_quantity: number; amount: number };
type PlanStock = { movement_id: string; product_name: string; store_name?: string; outstanding: number; proposed_sellable: number };
type Plan = {
  invoice_no: string; action: Action; refund_amount: number; refund_due: number;
  window: { created_on: string; deadline: string; within: boolean; days_remaining: number; override_required: boolean; creation_reliable: boolean; review_note?: string };
  lines: PlanLine[]; stock: PlanStock[]; sources: { payment_id: string; method: string; wallet: boolean; amount: number }[];
  overrides_required: { code: string; message: string }[];
  blockers: { code: string; message: string }[];
  summary: string[]; requires_override: boolean; blocked: boolean; plan_hash: string;
};

/**
 * The guided refund/cancellation flow.
 *
 * Staff choose what happened, not which ledger rows to touch: the plan — the
 * amount, the payment sources, the stock to take back, the vouchers,
 * entitlements and credits to reverse — is derived on the server from the
 * original invoice's own evidence and shown back in plain words.
 *
 * Four things are kept visibly apart, because they are four different events:
 * the request being submitted, the request being approved, money going back,
 * and goods coming back.
 */
export function InvoiceGuidedAction({ invoiceId, canApprove, onDone, onClose, requestId: reviewRequestId }: {
  invoiceId: string; canApprove: boolean; onDone: () => Promise<void> | void; onClose: () => void;
  /** Approval mode: review an existing request instead of raising a new one.
   *  The same steps, plan, stock confirmation and override fields are reused,
   *  so an approval from Approvals and one from the invoice cannot diverge. */
  requestId?: string;
}) {
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);
  const [action, setAction] = useState<Action | null>(null);
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [reason, setReason] = useState('');
  const [returnNotes, setReturnNotes] = useState('');
  const [plan, setPlan] = useState<Plan | null>(null);
  const [stockConfirm, setStockConfirm] = useState<Record<string, { sellable_quantity: number; damaged_quantity: number; not_returned_quantity: number }>>({});
  const [overrideReasons, setOverrideReasons] = useState<Record<string, string>>({});
  const [recordRefund, setRecordRefund] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState<string>('');
  const [requestId] = useState(() => crypto.randomUUID());
  const reviewing = Boolean(reviewRequestId);
  const [detail, setDetail] = useState<any>(null);
  const [rejecting, setRejecting] = useState(false);
  // Rentals still with the customer when the invoice is cancelled. Receiving
  // them is a separate confirmed event with a destination and a condition.
  const [awaiting, setAwaiting] = useState<any[]>([]);
  const [warehouses, setWarehouses] = useState<{ id: string; name: string }[]>([]);
  const [whFilter, setWhFilter] = useState('');
  const [rentalReturn, setRentalReturn] = useState<Record<string, { warehouse_id: string; condition: string }>>({});
  const dialog = useRef<HTMLDivElement>(null);
  const opener = useRef<Element | null>(null);

  // Keyboard and screen-reader behaviour: trap Tab, close on Escape, and put
  // focus back where it came from.
  useEffect(() => {
    opener.current = document.activeElement;
    dialog.current?.querySelector<HTMLElement>('button:not([disabled]), input, select, textarea')?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); onClose(); return; }
      if (e.key !== 'Tab') return;
      const list = Array.from(dialog.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]), [href], input:not([disabled]), select, textarea, [tabindex]:not([tabindex="-1"])') ?? []);
      if (!list.length) return;
      const firstEl = list[0], lastEl = list[list.length - 1];
      if (e.shiftKey && document.activeElement === firstEl) { e.preventDefault(); lastEl.focus(); }
      else if (!e.shiftKey && document.activeElement === lastEl) { e.preventDefault(); firstEl.focus(); }
    };
    document.addEventListener('keydown', onKey, true);
    return () => { document.removeEventListener('keydown', onKey, true); (opener.current as HTMLElement | null)?.focus?.(); };
  }, [onClose]);

  const derive = useCallback(async (next: Action, qty: Record<string, number>) => {
    setBusy(true); setError('');
    const lines = Object.entries(qty).filter(([, q]) => q > 0)
      .map(([invoice_item_id, quantity]) => ({ invoice_item_id, quantity }));
    const { data, error } = await supabase.rpc('invoice_action_plan', {
      p_invoice_id: invoiceId, p_action: next, p_lines: lines,
    });
    setBusy(false);
    if (error) { setError(error.message); return null; }
    const p = data as Plan;
    setPlan(p);
    // Propose the goods as returned and sellable; the person confirms or edits.
    setStockConfirm(Object.fromEntries((p.stock ?? []).map(s => [s.movement_id,
      { sellable_quantity: s.proposed_sellable, damaged_quantity: 0, not_returned_quantity: 0 }])));
    return p;
  }, [invoiceId]);

  // Active warehouses are the only valid destinations; the server checks again.
  useEffect(() => {
    supabase.from('warehouses').select('id,name').eq('is_active', true).is('deleted_at', null)
      .order('name').then(({ data }) => setWarehouses((data as any[]) ?? []));
    supabase.rpc('invoice_rentals_awaiting_return', { p_invoice_id: invoiceId })
      .then(({ data }) => {
        const rows = (data as any[]) ?? [];
        setAwaiting(rows);
        setRentalReturn(Object.fromEntries(rows.map(r =>
          [r.rental_id, { warehouse_id: r.default_warehouse_id ?? '', condition: 'good' }])));
      });
  }, [invoiceId]);

  // Step 1 needs the line list, which the plan already carries.
  useEffect(() => {
    if (reviewing) return;
    void derive('refund_full', {});
  }, [derive, reviewing]);

  // Approval mode: load the request, then show its CURRENT effects.
  useEffect(() => {
    if (!reviewRequestId) return;
    let cancelled = false;
    setBusy(true);
    supabase.rpc('invoice_action_request_detail', { p_request_id: reviewRequestId }).then(({ data, error }) => {
      if (cancelled) return;
      setBusy(false);
      if (error) { setError(error.message); return; }
      const d = data as any;
      setDetail(d);
      setAction(d.action as Action);
      setReason(d.reason ?? '');
      setQuantities(Object.fromEntries((d.requested_lines ?? []).map((l: any) => [l.invoice_item_id, l.quantity])));
      const p = (d.current_plan ?? d.requested_plan) as Plan | null;
      if (p) {
        setPlan(p);
        setStockConfirm(Object.fromEntries((p.stock ?? []).map(s => [s.movement_id,
          { sellable_quantity: s.proposed_sellable, damaged_quantity: 0, not_returned_quantity: 0 }])));
      }
      setStep(4);
    });
    return () => { cancelled = true; };
  }, [reviewRequestId]);

  const chooseAction = async (next: Action) => {
    setAction(next);
    if (next === 'refund_partial') { setStep(2); return; }
    await derive(next, {});
    setStep(3);
  };

  const reject = async () => {
    if (!reviewRequestId || !reason.trim()) { setError('Give the requester a reason for the rejection.'); return; }
    setBusy(true); setError('');
    const { error } = await supabase.rpc('resolve_invoice_action_v2', {
      p_request_id: reviewRequestId, p_approve: false, p_note: reason.trim(),
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    setDone('Request rejected. The requester sees the reason on the invoice. Nothing on the invoice has changed.');
    try { await onDone(); } catch { /* the rejection is recorded either way */ }
  };

  const submit = async () => {
    if (reviewing) { await approve(reviewRequestId!); return; }
    if (!action || !reason.trim()) { setError('Enter a reason for the audit history.'); return; }
    setBusy(true); setError('');
    const lines = Object.entries(quantities).filter(([, q]) => q > 0)
      .map(([invoice_item_id, quantity]) => ({ invoice_item_id, quantity }));
    const { data, error } = await supabase.rpc('request_invoice_action_v2', {
      p_invoice_id: invoiceId, p_action: action, p_lines: lines,
      p_reason: reason.trim(), p_return_notes: returnNotes.trim() || null, p_request_id: requestId,
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    if (!canApprove) {
      setDone(`Request submitted for approval. Nothing has changed on ${plan?.invoice_no ?? 'this invoice'} yet — no money has moved and no stock has been returned.`);
      await onDone();
      return;
    }
    await approve((data as any).request_id);
  };

  const approve = async (requestRecordId: string) => {
    setBusy(true); setError('');
    const stock = Object.entries(stockConfirm).map(([movement_id, q]) => ({ movement_id, ...q }));
    const overrides = (plan?.overrides_required ?? []).map(o => ({ code: o.code, reason: overrideReasons[o.code] ?? '' }));
    const { data, error } = await supabase.rpc('resolve_invoice_action_v2', {
      p_request_id: requestRecordId, p_approve: true, p_note: reason.trim(),
      p_plan_hash: plan?.plan_hash ?? null, p_overrides: overrides,
      p_stock: stock.length ? stock : null, p_record_refund: recordRefund,
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    const r = data as any;
    if (r?.confirmation_required) {
      setPlan(r.revised_plan);
      setError('What this would do has changed since the request was raised. The revised effects are shown below — review them and confirm again.');
      return;
    }
    // Report what actually happened, from the server's own answer — never
    // "refund recorded" because a checkbox was ticked.
    const parts: string[] = [];
    if (r?.cancellation) parts.push('Invoice cancelled.');
    if (r?.refund_recorded) parts.push(`Refund of ${money(r?.refunded_amount)} recorded.`);
    if (Number(r?.goods_returned ?? 0) > 0) parts.push('Returned goods recorded.');
    if (Number(r?.refund_still_due ?? 0) > 0) {
      parts.push(`${money(r.refund_still_due)} is still due back to the customer — record it when the money actually goes back.`);
    }
    setDone(parts.join(' ') || 'Done.');
    // Items physically handed back are recorded as their own event, against
    // the destination and condition the person actually confirmed.
    for (const r of awaiting) {
      const choice = rentalReturn[r.rental_id];
      if (!choice?.warehouse_id) continue;
      const { error: rerr } = await supabase.rpc('receive_returned_rental', {
        p_rental_id: r.rental_id, p_warehouse_id: choice.warehouse_id,
        p_condition: choice.condition, p_reason: reason.trim() || 'Received with the cancellation',
        p_request_id: requestId,
      });
      if (rerr) { setError(`The invoice was saved. The rental return could not be recorded: ${rerr.message}`); break; }
    }
    // A save that worked must not be lost because the refresh failed.
    try { await onDone(); } catch { setError('This was saved. The screen could not refresh — reopen the invoice to see it.'); }
  };

  const line = (id: string) => plan?.lines.find(l => l.invoice_item_id === id);

  if (done) return (
    <div className="invoice-chooser-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="invoice-chooser" role="dialog" aria-modal="true" aria-labelledby="ga-done" ref={dialog}>
        <h3 id="ga-done">Done</h3>
        <p>{done}</p>
        <div className="invoice-chooser-actions"><button className="btn btn-primary" onClick={onClose}>Close</button></div>
      </div>
    </div>
  );

  return (
    <div className="invoice-chooser-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="invoice-chooser invoice-guided" role="dialog" aria-modal="true" aria-labelledby="ga-title" ref={dialog}>
        <h3 id="ga-title">Refund or cancel {plan?.invoice_no ?? ''}</h3>
        <ol className="invoice-guided-steps" aria-label="Progress">
          {['What happened', 'Which items', 'Why', 'Review'].map((label, n) => (
            <li key={label} aria-current={step === n + 1 ? 'step' : undefined}
              className={step === n + 1 ? 'current' : step > n + 1 ? 'done' : ''}>{label}</li>
          ))}
        </ol>

        {plan?.window && !plan.window.within && (
          <p className="invoice-guided-warn" role="status">
            Outside the five-day window — created {plan.window.created_on}, open through {plan.window.deadline}.
            An Owner or Manager override with a reason is required.
          </p>
        )}
        {plan?.blocked && (
          <div className="invoice-guided-block" role="alert">
            <strong>This invoice needs review first.</strong>
            <ul>{plan.blockers.map(b => <li key={b.code}>{b.message}</li>)}</ul>
          </div>
        )}

        {step === 1 && (
          <div className="invoice-guided-choices">
            <button className="btn" disabled={busy || plan?.blocked} onClick={() => chooseAction('cancel')}>
              <strong>Cancel the invoice</strong><span>It should not have been raised, or the customer is not taking it.</span></button>
            <button className="btn" disabled={busy || plan?.blocked} onClick={() => chooseAction('refund_full')}>
              <strong>Refund everything</strong><span>All items are coming back.</span></button>
            <button className="btn" disabled={busy || plan?.blocked} onClick={() => chooseAction('refund_partial')}>
              <strong>Refund some items</strong><span>Only part of the invoice is coming back.</span></button>
          </div>
        )}

        {step === 2 && (
          <fieldset className="invoice-guided-lines">
            <legend>Which items are coming back?</legend>
            {(plan?.lines ?? []).map(l => (
              <label key={l.invoice_item_id}>
                <span>{l.name} <small>({l.line_kind.replace(/_/g, ' ')}, {l.quantity} sold)</small></span>
                <input type="number" min={0} max={l.quantity} inputMode="numeric"
                  aria-label={`Quantity of ${l.name} coming back, out of ${l.quantity}`}
                  value={quantities[l.invoice_item_id] ?? 0}
                  onChange={e => setQuantities({ ...quantities, [l.invoice_item_id]: Math.max(0, Math.min(l.quantity, Number(e.target.value))) })} />
              </label>
            ))}
            <div className="invoice-chooser-actions">
              <button className="btn" onClick={() => setStep(1)}>Back</button>
              <button className="btn btn-primary" disabled={busy || !Object.values(quantities).some(q => q > 0)}
                onClick={async () => { await derive('refund_partial', quantities); setStep(3); }}>Continue</button>
            </div>
          </fieldset>
        )}

        {step === 3 && (
          <div className="invoice-guided-why">
            <label>Reason <span aria-hidden="true">*</span>
              <textarea value={reason} onChange={e => setReason(e.target.value)} rows={2} required
                aria-describedby="ga-reason-help" placeholder="What happened, in a sentence" />
            </label>
            <p id="ga-reason-help" className="muted">Kept in the audit history and shown to whoever approves this.</p>
            <label>Return details <small>(optional)</small>
              <textarea value={returnNotes} onChange={e => setReturnNotes(e.target.value)} rows={2}
                placeholder="Condition, who is bringing it back, when" />
            </label>
            <div className="invoice-chooser-actions">
              <button className="btn" onClick={() => setStep(action === 'refund_partial' ? 2 : 1)}>Back</button>
              <button className="btn btn-primary" disabled={!reason.trim()} onClick={() => setStep(4)}>Review</button>
            </div>
          </div>
        )}

        {reviewing && detail && (
          <div className="invoice-guided-request" aria-label="The request being reviewed">
            <div><strong>{detail.requested_by ?? 'Staff'}</strong> asked to{' '}
              {detail.action === 'cancel' ? 'cancel this invoice'
                : detail.action === 'refund_partial' ? 'refund some items' : 'refund everything'}
              {' '}· {detail.store}</div>
            <div className="muted">“{detail.reason}”{detail.return_notes ? ` · ${detail.return_notes}` : ''}</div>
            {detail.requested_amount != null && (
              <div>Amount when asked: {money(detail.requested_amount)}</div>)}
            {(detail.requested_lines ?? []).length > 0 && (
              <div>Items requested: {(detail.requested_lines as any[]).map((l: any) =>
                `${line(l.invoice_item_id)?.name ?? 'item'} × ${l.quantity}`).join(', ')}</div>)}
            {detail.changed && (
              <p className="invoice-guided-warn" role="status">
                This is no longer what it was when it was asked for. It is now{' '}
                {money(detail.current_plan?.refund_amount ?? detail.current_plan?.refund_due)} rather than{' '}
                {money(detail.requested_amount)}. Review the current effects below before approving.
              </p>)}
            {detail.status !== 'pending' && (
              <p className="invoice-guided-warn" role="status">
                Already {detail.status}
                {detail.rejection_reason ? ` — ${detail.rejection_reason}` : ''}.
              </p>)}
          </div>
        )}

        {reviewing && detail?.legacy && (
          <div className="invoice-guided-block" role="alert">
            <strong>This request cannot be approved as it stands.</strong>
            <p>{detail.legacy_note}</p>
            <label>Reason for the requester
              <textarea value={reason} onChange={e => setReason(e.target.value)} rows={2} /></label>
            <div className="invoice-chooser-actions">
              <button className="btn" onClick={onClose}>Close</button>
              <button className="btn btn-danger" disabled={busy || !reason.trim()} onClick={reject}>Reject</button>
            </div>
          </div>
        )}

        {step === 4 && plan && !(reviewing && detail?.legacy) && (
          <div className="invoice-guided-review">
            <h4>What this will do</h4>
            <ul className="invoice-guided-summary">{plan.summary.map((s, n) => <li key={n}>{s}</li>)}</ul>

            {plan.stock.length > 0 && (
              <fieldset className="invoice-guided-stock">
                <legend>Confirm the goods</legend>
                <p className="muted">A refund is not proof that anything came back. Damaged and not-returned
                  units are recorded separately and are never put back on sale.</p>
                {plan.stock.map(s => (
                  <div key={s.movement_id} className="invoice-guided-stock-row">
                    <span>{s.product_name} <small>→ {s.store_name ?? 'original store'}, {s.outstanding} outstanding</small></span>
                    {(['sellable_quantity', 'damaged_quantity', 'not_returned_quantity'] as const).map(k => (
                      <label key={k}>{k === 'sellable_quantity' ? 'Good' : k === 'damaged_quantity' ? 'Damaged' : 'Not returned'}
                        <input type="number" min={0} max={s.outstanding} inputMode="numeric"
                          value={stockConfirm[s.movement_id]?.[k] ?? 0}
                          onChange={e => setStockConfirm({ ...stockConfirm,
                            [s.movement_id]: { ...stockConfirm[s.movement_id], [k]: Math.max(0, Number(e.target.value)) } as any })} />
                      </label>
                    ))}
                  </div>
                ))}
              </fieldset>
            )}

            {canApprove && awaiting.length > 0 && (
              <fieldset className="invoice-guided-stock">
                <legend>Rented items still out</legend>
                <p className="muted">Cancelling the invoice ends the rental but does not bring the item
                  back. Record where it goes and what state it is in only when it is actually in your hands —
                  damaged and lost items are never put back on sale.</p>
                <label>Find a warehouse
                  <input type="search" value={whFilter} onChange={e => setWhFilter(e.target.value)}
                    placeholder="Type to filter destinations" aria-label="Filter warehouses" /></label>
                {awaiting.map(r => (
                  <div key={r.rental_id} className="invoice-guided-stock-row">
                    <span>{r.item} <small>· {r.rental_no} · {r.quantity} out</small></span>
                    <label>Destination
                      <select value={rentalReturn[r.rental_id]?.warehouse_id ?? ''}
                        aria-label={`Destination warehouse for ${r.rental_no}`}
                        onChange={e => setRentalReturn({ ...rentalReturn,
                          [r.rental_id]: { ...rentalReturn[r.rental_id], warehouse_id: e.target.value } })}>
                        <option value="">Not back yet</option>
                        {warehouses
                          .filter(w => !whFilter || w.name.toLowerCase().includes(whFilter.toLowerCase()))
                          .map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
                      </select>
                    </label>
                    <label>Condition
                      <select value={rentalReturn[r.rental_id]?.condition ?? 'good'}
                        aria-label={`Condition of ${r.rental_no}`}
                        onChange={e => setRentalReturn({ ...rentalReturn,
                          [r.rental_id]: { ...rentalReturn[r.rental_id], condition: e.target.value } })}>
                        <option value="good">Good — back on sale</option>
                        <option value="damaged">Damaged — not for sale</option>
                        <option value="lost">Lost — never came back</option>
                      </select>
                    </label>
                  </div>
                ))}
              </fieldset>
            )}

            {canApprove && plan.overrides_required.length > 0 && (
              <fieldset className="invoice-guided-overrides">
                <legend>Override reasons</legend>
                {plan.overrides_required.map(o => (
                  <label key={o.code}><span>{o.message}</span>
                    <input type="text" value={overrideReasons[o.code] ?? ''} required
                      aria-label={`Reason for override: ${o.code}`}
                      onChange={e => setOverrideReasons({ ...overrideReasons, [o.code]: e.target.value })} />
                  </label>
                ))}
              </fieldset>
            )}

            {canApprove && action === 'cancel' && (plan.refund_due ?? 0) > 0 && (
              <label className="invoice-guided-refunddue">
                <input type="checkbox" checked={recordRefund} onChange={e => setRecordRefund(e.target.checked)} />
                <span>The {money(plan.refund_due)} has actually gone back to the customer now.
                  Leave this unticked to cancel now and show <strong>Refund due</strong> until the money is really returned.</span>
              </label>
            )}

            {error && <p className="invoice-guided-warn" role="alert">{error}</p>}
            {reviewing && rejecting && (
              <label className="invoice-guided-why">Reason for rejecting
                <textarea value={reason} onChange={e => setReason(e.target.value)} rows={2} autoFocus /></label>
            )}
            <div className="invoice-chooser-actions">
              {reviewing
                ? <button className="btn" onClick={() => rejecting ? setRejecting(false) : onClose()}>
                    {rejecting ? 'Back' : 'Close'}</button>
                : <button className="btn" onClick={() => setStep(3)}>Back</button>}
              {reviewing && !rejecting && (
                <button className="btn btn-danger" disabled={busy || detail?.status !== 'pending'}
                  onClick={() => setRejecting(true)}>Reject</button>)}
              {reviewing && rejecting
                ? <button className="btn btn-danger" disabled={busy || !reason.trim()} onClick={reject}>Confirm rejection</button>
                : <button className="btn btn-primary"
                    disabled={busy || plan.blocked || (reviewing && detail?.status !== 'pending')} onClick={submit}>
                    {reviewing ? 'Approve and record' : canApprove ? 'Confirm and record' : 'Submit for approval'}
                  </button>}
            </div>
            {!canApprove && <p className="muted">This will be sent to an Owner or Manager. Nothing changes until they approve it.</p>}
          </div>
        )}
        {error && step !== 4 && <p className="invoice-guided-warn" role="alert">{error}</p>}
        {step === 1 && <div className="invoice-chooser-actions"><button className="btn" onClick={onClose}>Close</button></div>}
      </div>
    </div>
  );
}
