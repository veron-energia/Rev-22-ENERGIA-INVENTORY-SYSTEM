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
  overrides_required: { code: string; message: string; amount_required?: boolean }[];
  blockers: { code: string; message: string }[];
  summary: string[]; requires_override: boolean; blocked: boolean; plan_hash: string;
  status?: string;
  /** Money, credits, stock and overrides kept apart — the review renders these
   *  rather than inferring one quantity from another. */
  effects?: {
    money_returned: { total: number; destinations: { payment_id: string; method: string; wallet: boolean; amount: number }[] };
    benefits: { kind: string; holder?: string; credit_removed?: number | null; units_revoked?: number | null; accounting_value?: number; line?: string }[];
    stock_returned: PlanStock[];
    overrides: { code: string; message: string }[];
  };
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
  // A refresh that fails after a successful save must never look like a failed
  // save, and retrying it must never resubmit the action.
  const [refreshFailed, setRefreshFailed] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  // Rentals still with the customer when the invoice is cancelled. Receiving
  // them is a separate confirmed event with a destination and a condition.
  const [awaiting, setAwaiting] = useState<any[]>([]);
  const [warehouses, setWarehouses] = useState<{ id: string; name: string }[]>([]);
  const [whFilter, setWhFilter] = useState('');
  const [rentalReturn, setRentalReturn] = useState<Record<string, { warehouse_id: string; condition: string }>>({});
  const dialog = useRef<HTMLDivElement>(null);
  const opener = useRef<Element | null>(null);
  // Kept in a ref so the key handler, bound once, always sees the current one.
  const closeRef = useRef<() => void>(() => onClose());

  // Keyboard and screen-reader behaviour: trap Tab, close on Escape, and put
  // focus back where it came from.
  useEffect(() => {
    opener.current = document.activeElement;
    dialog.current?.querySelector<HTMLElement>('button:not([disabled]), input, select, textarea')?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeRef.current(); return; }
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
    try { setRefreshFailed(false); await onDone(); } catch { setRefreshFailed(true); }
  };

  const line = (id: string) => plan?.lines.find(l => l.invoice_item_id === id);

  /** Anything the person has actually typed or chosen and would lose. */
  const hasUnsavedInput = () =>
    (!reviewing && reason.trim().length > 0)
    || returnNotes.trim().length > 0
    || Object.values(quantities).some(q => q > 0)
    || Object.values(overrideReasons).some(r => (r ?? '').trim().length > 0);

  // The project's existing pattern for abandoning work is a confirm(); a
  // finished success message closes straight away, with nothing to lose.
  const requestClose = () => {
    if (done || !hasUnsavedInput()
        || confirm('Discard what you have entered for this refund or cancellation?')) {
      onClose();
    }
  };
  closeRef.current = requestClose;

  if (done) return (
    <div className="invoice-chooser-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="invoice-chooser" role="dialog" aria-modal="true" aria-labelledby="ga-done" ref={dialog}>
        <h3 id="ga-done">Done</h3>
        <p>{done}</p>
        {refreshFailed && (
          <div className="invoice-guided-warn" role="status">
            <strong>This was saved.</strong> The invoice on screen could not be reloaded, so what
            you can see behind this message may be out of date. Retrying only re-reads the
            invoice — it does not repeat the {action === 'cancel' ? 'cancellation' : 'refund'}.
            <div className="invoice-chooser-actions">
              <button className="btn" disabled={refreshing} onClick={async () => {
                setRefreshing(true);
                try { await onDone(); setRefreshFailed(false); } catch { /* still stale */ }
                setRefreshing(false);
              }}>{refreshing ? 'Reloading…' : 'Reload the invoice'}</button>
            </div>
          </div>
        )}
        <div className="invoice-chooser-actions"><button className="btn btn-primary" onClick={onClose}>Close</button></div>
      </div>
    </div>
  );

  return (
    <div className="invoice-chooser-backdrop" onClick={e => { if (e.target === e.currentTarget) requestClose(); }}>
      <div className="invoice-chooser invoice-guided" role="dialog" aria-modal="true" aria-labelledby="ga-title" ref={dialog}>
        <div className="invoice-guided-head">
          <h3 id="ga-title">Refund or cancel {plan?.invoice_no ?? ''}</h3>
          <button type="button" className="invoice-guided-close" aria-label="Close without saving"
            onClick={requestClose}>&times;</button>
        </div>
        {plan && (
          <p className="invoice-guided-status">
            <strong>{plan.invoice_no}</strong>
            {plan.status ? <> · {String(plan.status).replace(/_/g, ' ')}</> : null}
            {plan.window ? <> · created {plan.window.created_on}</> : null}
          </p>
        )}
        <ol className="invoice-guided-steps" aria-label="Progress">
          {['Action', 'Items', 'Reason', 'Review'].map((label, n) => (
            <li key={label} aria-current={step === n + 1 ? 'step' : undefined}
              className={step === n + 1 ? 'current' : step > n + 1 ? 'done' : ''}>{label}</li>
          ))}
        </ol>

        <div className="invoice-guided-body">
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

        {step === 1 && plan?.blocked && (
          <p className="muted">Every action is unavailable until the review above is resolved.</p>
        )}
        {step === 1 && (
          <div className="invoice-guided-choices">
            <button className="btn" disabled={busy || plan?.blocked} onClick={() => chooseAction('cancel')}>
              <strong>Cancel invoice</strong><span>It should not have been raised, or the customer is not going ahead.</span></button>
            <button className="btn" disabled={busy || plan?.blocked} onClick={() => chooseAction('refund_full')}>
              <strong>Full refund</strong><span>Everything on this invoice is being reversed — goods, services, vouchers and credits alike.</span></button>
            <button className="btn" disabled={busy || plan?.blocked} onClick={() => chooseAction('refund_partial')}>
              <strong>Partial refund</strong><span>Only some of what was bought is being reversed.</span></button>
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
            {(() => {
              const fx = plan.effects;
              if (!fx) return <ul className="invoice-guided-summary">{plan.summary.map((s, n) => <li key={n}>{s}</li>)}</ul>;
              const credits = (fx.benefits ?? []).filter(b => b.credit_removed != null || b.units_revoked != null);
              return (<>
                {Number(fx.money_returned?.total ?? 0) > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Money returned</h5>
                    <p className="invoice-guided-figure">{money(fx.money_returned.total)}</p>
                    <ul>{(fx.money_returned.destinations ?? []).map(d => (
                      <li key={d.payment_id}>{money(d.amount)} to {d.method}
                        {d.wallet ? ' — restores the original credit' : ''}</li>))}</ul>
                    <p className="muted">Recording this does not send money anywhere. It records that
                      the money was returned; making the payment is a separate act.</p>
                  </section>
                )}
                {action === 'cancel' && Number(plan.refund_due ?? 0) > 0 && !recordRefund && (
                  <section className="invoice-guided-section">
                    <h5>Refund due</h5>
                    <p className="invoice-guided-figure">{money(plan.refund_due)}</p>
                    <p className="muted">Nothing is recorded as returned until someone confirms it was.</p>
                  </section>
                )}
                {credits.length > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Credits and benefits cancelled</h5>
                    <ul>{credits.map((b, n) => (
                      <li key={n}>
                        {b.credit_removed != null
                          ? <>{money(b.credit_removed)} of {b.kind} credit</>
                          : <>{b.units_revoked} unused voucher unit{Number(b.units_revoked) === 1 ? '' : 's'}</>}
                        {b.holder ? <> — {b.holder}</> : null}
                        {b.line ? <span className="muted"> ({b.line})</span> : null}
                      </li>))}</ul>
                  </section>
                )}
                {(fx.stock_returned ?? []).length > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Stock returned</h5>
                    <ul>{fx.stock_returned.map(st2 => (
                      <li key={st2.movement_id}>{st2.proposed_sellable} × {st2.product_name} →{' '}
                        {st2.store_name ?? 'the original store'} <span className="muted">(condition confirmed below)</span></li>))}</ul>
                  </section>
                )}
                {(plan.overrides_required ?? []).length > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Overrides required</h5>
                    <ul>{plan.overrides_required.map(o => <li key={o.code}>{o.message}</li>)}</ul>
                  </section>
                )}
              </>);
            })()}

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
            {!canApprove && <p className="muted">This will be sent to an Owner or Manager. Nothing changes until they approve it.</p>}
          </div>
        )}
        {error && step !== 4 && <p className="invoice-guided-warn" role="alert">{error}</p>}
        </div>

        {/* One footer, outside the scrolling body, so Back and the
            confirming action stay reachable however long the review gets. */}
        <div className="invoice-guided-foot">
          {step === 1 && (
            <button type="button" className="btn" onClick={requestClose}>Close</button>
          )}
          {step === 2 && (<>
            <button type="button" className="btn" onClick={() => setStep(1)}>Back</button>
            <button type="button" className="btn btn-primary"
              disabled={busy || !Object.values(quantities).some(q => q > 0)}
              onClick={async () => { await derive('refund_partial', quantities); setStep(3); }}>Continue</button>
          </>)}
          {step === 3 && (<>
            <button type="button" className="btn" onClick={() => setStep(action === 'refund_partial' ? 2 : 1)}>Back</button>
            <button type="button" className="btn btn-primary" disabled={!reason.trim()}
              onClick={() => setStep(4)}>Continue</button>
          </>)}
          {step === 4 && plan && !(reviewing && detail?.legacy) && (<>
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
                  {(() => {
                    const amount = Number(plan.refund_amount ?? 0);
                    if (!canApprove && !reviewing) {
                      return action === 'cancel' ? 'Submit cancellation request' : 'Submit refund request';
                    }
                    if (action === 'cancel') {
                      return recordRefund && Number(plan.refund_due ?? 0) > 0
                        ? `Confirm cancellation and ${money(plan.refund_due)} refund`
                        : 'Confirm cancellation';
                    }
                    return amount > 0 ? `Confirm ${money(amount)} refund` : 'Confirm refund';
                  })()}
                </button>}
          </>)}
        </div>

      </div>
    </div>
  );
}
