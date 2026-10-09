import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { InvoiceSearchSelect } from './InvoiceSearchSelect';
import { singaporeToday, usedValueText } from '../../lib/invoices/business';
import { CustomerSearchSelect } from '../SearchSelect';
import { InvoiceBenefitEvidenceReview } from './InvoiceBenefitEvidenceReview';
import { InvoiceRewardResolution } from './InvoiceRewardResolution';
import { useWaitingItems, WaitingItemsQuestion } from './WaitingItemsQuestion';
import { type WaitingAnswers, unansweredItems, withWaitingAnswers } from '../../lib/special/waitingItems';

const money = (n: unknown) => `S$${Number(n || 0).toFixed(2)}`;
const cents = (n: unknown) => Math.round((Number(n) || 0) * 100) / 100;

/** 409: the refund still due, taken from the original payments in the order
 *  listed, each up to what it still holds. */
export function splitRefundDue(due: number, sources: { payment_id: string; remaining: number }[]): Record<string, number> {
  let left = cents(due);
  const out: Record<string, number> = {};
  for (const s of sources ?? []) {
    const take = cents(Math.min(left, Number(s.remaining) || 0));
    if (take > 0) { out[s.payment_id] = take; left = cents(left - take); }
  }
  return out;
}
// 'refund_due' (409): the refund still owed on a cancelled or refunded invoice,
// recorded when it has actually gone back. 'refund' is the line-by-line form,
// reached from it when the money must go back through a purchase's benefits.
type Mode = '' | 'refund' | 'refund_due' | 'payment' | 'reopen' | 'transfer';
type Source = { payment_id: string; method: string; wallet: boolean; remaining: number };
type Benefit = { id: string; invoice_item_id: string; customer_name?: string; customer_id?: string; store_id?: string; benefit_kind?: string; cancelled_unused_value?: number; remaining_value: number; max_refund: number; reward_voucher_id?: string };
type Stock = { movement_id: string; product_name: string; quantity: number; resolved_quantity: number };
type Line = { invoice_item_id: string; name: string; remaining: number; line_kind: string };
type Options = { financial: Record<string, any>; sources: Source[]; benefits: Benefit[]; stock: Stock[]; lines: Line[]; review_required: boolean; review_notes?: string[]; therapy_sessions?: { invoice_item_id: string; name: string; used: number; unused: number; paid_value: number | null; max_refund: number | null }[] };

/** All amounts are proposals: the locked database transaction rechecks capacity,
 * source ownership, benefit use and stock evidence before recording anything. */
export function InvoiceFinancePanel({ invoiceId, canManage, payments, methods, stores = [], onChanged,
  requestedMode = null, requestedPaymentId = null, onRequestHandled, onActiveChange, usedValue = null }: {
  invoiceId: string; canManage: boolean; payments: any[]; methods: any[]; stores?: { id: string; name: string }[]; onChanged: () => Promise<void>;
  /** 409: on a cancelled invoice, what its customer already had from it (the
   *  guided cancellation's override codes); null while unknown. With any, the
   *  money it holds is not all owed back, and "Record refund paid" is not
   *  offered: this says why instead. */
  usedValue?: string[] | null;
  /** "Record refund paid" (the invoice footer) and payment correction (the
   *  payments list) open this panel, not a row of buttons of its own. */
  requestedMode?: Mode | null; requestedPaymentId?: string | null; onRequestHandled?: () => void;
  /** Whether a refund, cancellation, correction or transfer is being entered
   *  here. The invoice view uses it to leave those entries alone when the
   *  invoice changes underneath them. */
  onActiveChange?: (active: boolean) => void;
}) {
  const [options, setOptions] = useState<Options | null>(null);
  const [mode, setMode] = useState<Mode>('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [reason, setReason] = useState('');
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [lineAmounts, setLineAmounts] = useState<Record<string, number>>({});
  const [benefitAmounts, setBenefitAmounts] = useState<Record<string, number>>({});
  const [sourceAmounts, setSourceAmounts] = useState<Record<string, number>>({});
  const [stock, setStock] = useState<Record<string, { sellable_quantity: number; damaged_quantity: number; not_returned_quantity: number }>>({});
  const [benefitOverpayment, setBenefitOverpayment] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const [paymentId, setPaymentId] = useState('');
  const [amount, setAmount] = useState(0);
  const [date, setDate] = useState(singaporeToday);
  const [methodId, setMethodId] = useState('');
  const [preview, setPreview] = useState<any>(null);
  const [transferBenefit, setTransferBenefit] = useState('');
  const [transferCustomer, setTransferCustomer] = useState('');
  const [transferStore, setTransferStore] = useState('');
  // Set when a refund or cancellation is refused because the package's
  // qualification rewards are still outstanding. The review answers it.
  const [rewardReview, setRewardReview] = useState(false);
  // 409: "Record refund paid" was refused because the money must go back
  // through the purchase's benefits; the line-by-line form is offered.
  const [dueByLine, setDueByLine] = useState(false);
  // Whether the amounts in "Record refund paid" were typed, so a reload of the
  // invoice's figures does not overwrite them.
  const [dueTouched, setDueTouched] = useState(false);
  // 393: special products and rentals still waiting for a warehouse. A refund
  // asks, for each, whether the customer is still taking it.
  const waitingItems = useWaitingItems(invoiceId, payments);
  const [waitingAnswers, setWaitingAnswers] = useState<WaitingAnswers>({});
  // Every line going back in full closes the invoice, which cancels them all
  // without asking (the Owner, 6 Oct 2026).
  const wholeInvoice = !!options?.lines?.length && options.lines.every(l =>
    Number(l.remaining) <= 0.005 || (lineAmounts[l.invoice_item_id] ?? 0) >= Number(l.remaining) - 0.005);
  const waitingLeft = wholeInvoice ? [] : unansweredItems(waitingItems, waitingAnswers);
  useEffect(() => {
    let cancelled = false;
    setOptions(null);
    supabase.rpc('invoice_refund_options', { p_invoice_id: invoiceId }).then(({ data, error }) => {
      if (!cancelled) { setOptions(data); setError(error?.message || ''); }
    });
    return () => { cancelled = true; };
  }, [invoiceId, payments]);
  const close = () => { setMode(''); onRequestHandled?.(); onActiveChange?.(false); };
  const open = async (next: Mode) => {
    onActiveChange?.(true);
    setMode(next); setError(''); setReason(''); setRequestId(crypto.randomUUID()); setConfirmed(false); setBenefitOverpayment(false);
    setLineAmounts({}); setBenefitAmounts({}); setSourceAmounts({}); setStock({}); setPreview(null); setWaitingAnswers({});
    setTransferBenefit(''); setTransferCustomer(''); setTransferStore(''); setDueByLine(false); setDueTouched(false);
    if (next === 'refund' && ['cancelled', 'refunded'].includes(options?.financial?.status)) {
      // From "Record refund paid": what a cancellation would return, line by
      // line with each line's benefits, as the guided flow works it out. The
      // person checks it; the server checks everything again.
      const { data } = await supabase.rpc('invoice_action_plan', { p_invoice_id: invoiceId, p_action: 'cancel', p_lines: [] });
      const plan = data as any;
      if (plan) {
        setLineAmounts(Object.fromEntries((plan.lines ?? []).filter((l: any) => Number(l.amount) > 0)
          .map((l: any) => [l.invoice_item_id, Number(l.amount)])));
        setBenefitAmounts(Object.fromEntries((plan.lines ?? []).flatMap((l: any) => (l.benefits ?? [])
          .filter((b: any) => Number(b.amount) > 0).map((b: any) => [b.benefit_id, Number(b.amount)]))));
        setSourceAmounts(Object.fromEntries((plan.sources ?? []).map((s: any) => [s.payment_id, Number(s.amount)])));
      }
    }
    if (next === 'reopen') {
      const { data, error } = await supabase.rpc('invoice_reopen_preview', { p_invoice_id: invoiceId });
      setPreview(data); setError(error?.message || '');
    }
  };
  // "Record refund paid" starts from what is still due, taken from the
  // original payments in the order listed, each up to what it still holds.
  // The person can change it; the server holds it to the refund due.
  useEffect(() => {
    if (mode !== 'refund_due' || !options || dueTouched || (usedValue?.length ?? 0) > 0) return;
    setSourceAmounts(splitRefundDue(Number(options.financial?.refund_due ?? 0), options.sources));
  }, [mode, options, dueTouched, usedValue]);
  const currentPayments = payments.filter(p => p.entry_kind !== 'correction_reversal' && !payments.some(r => r.corrects_payment_id === p.id && r.entry_kind === 'correction_reversal'));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => () => { onActiveChange?.(false); }, []);
  useEffect(() => {
    if (!requestedMode || !canManage) return;
    let cancelled = false;
    (async () => {
      await open(requestedMode);
      if (cancelled) return;
      if (requestedMode === 'payment') {
        const target = requestedPaymentId && currentPayments.some(p => p.id === requestedPaymentId)
          ? requestedPaymentId : currentPayments[0]?.id;
        if (target) choosePayment(target);
      }
      onRequestHandled?.();
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestedMode, requestedPaymentId]);
  const choosePayment = (id: string) => {
    const p = currentPayments.find(p => p.id === id);
    setPaymentId(id); setAmount(Number(p.amount)); setMethodId(p.payment_method_id);
    setDate(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore' }).format(new Date(p.effective_at || p.created_at)));
  };
  const submit = async () => {
    if (!reason.trim()) { setError('Enter a reason for the audit history.'); return; }
    if (mode === 'refund_due' && dueProblem) { setError(dueProblem); return; }
    if (mode === 'refund' && !confirmed) { setError('Confirm the actual refund and stock outcomes before recording.'); return; }
    if (mode === 'refund' && waitingLeft.length) { setError('Say whether the customer is still taking each item waiting for a warehouse.'); return; }
    setBusy(true); setError('');
    try {
      let result;
      const common = { p_invoice_id: invoiceId, p_reason: reason.trim(), p_request_id: requestId };
      if (mode === 'refund_due') {
        // 409: on a cancelled invoice nothing is charged any more, so the money
        // still held is owed back as a whole, not by line: one line without an
        // item, through the original payments. The server holds it to the
        // refund due, replays a repeat of this request and audits it.
        result = await supabase.rpc('refund_invoice_recorded', { ...common,
          p_lines: [{ invoice_item_id: null, amount: dueTotal }],
          p_sources: Object.entries(sourceAmounts).filter(([, amount]) => amount > 0)
            .map(([payment_id, amount]) => ({ payment_id, amount: cents(amount) })),
          p_stock: [],
        });
      } else if (mode === 'refund') {
        const lines = Object.entries(lineAmounts).filter(([, amount]) => amount > 0).map(([id, amount]) => ({
          invoice_item_id: id === 'excess' ? null : id, amount, overpayment: benefitOverpayment && (options?.benefits || []).some(b => b.invoice_item_id === id),
          benefits: (options?.benefits || []).filter(b => b.invoice_item_id === id && benefitAmounts[b.id] > 0).map(b => ({ benefit_id: b.id, amount: benefitAmounts[b.id] })),
        }));
        result = await supabase.rpc('refund_invoice_recorded', { ...common,
          p_lines: wholeInvoice ? lines : withWaitingAnswers(lines, waitingItems, waitingAnswers),
          p_sources: Object.entries(sourceAmounts).filter(([, amount]) => amount > 0).map(([payment_id, amount]) => ({ payment_id, amount })),
          p_stock: Object.entries(stock).filter(([, q]) => q.sellable_quantity + q.damaged_quantity + q.not_returned_quantity > 0).map(([movement_id, q]) => ({ movement_id, ...q })),
        });
      } else if (mode === 'transfer') {
        if (!confirmed || !transferBenefit || !transferCustomer || !transferStore) throw new Error('Choose the unused benefit, recipient and store, then confirm the move.');
        result = await supabase.rpc('transfer_invoice_unused_benefit', { p_benefit_id: transferBenefit,
          p_customer_id: transferCustomer, p_store_id: transferStore, p_reason: reason.trim(), p_request_id: requestId });
      } else if (mode === 'payment') {
        result = await supabase.rpc('correct_invoice_payment', { p_payment_id: paymentId, p_amount: amount, p_date: date,
          p_method_id: methodId, p_reason: reason.trim(), p_request_id: requestId });
      } else if (mode === 'reopen') result = await supabase.rpc('reopen_invoice', common);
      else throw new Error('Choose what to record.');
      if (result.error) throw result.error;
      close(); await onChanged();
    } catch (e: any) {
      const message = e.message || 'The request could not be completed. Your entered details have been kept.';
      setError(message);
      // This refusal has a way forward; offer it instead of a dead end.
      if (/qualification reward entitlements/i.test(message)) setRewardReview(true);
      // Issued credit or sold vouchers go back through the purchase's own
      // benefits, line by line (the server refuses the single line for them).
      if (mode === 'refund_due' && /original unused purchased benefits/i.test(message)) setDueByLine(true);
    }
    finally { setBusy(false); }
  };
  const f = options?.financial;
  const total = Object.values(lineAmounts).reduce((a, b) => a + b, 0);
  const sourceTotal = Object.values(sourceAmounts).reduce((a, b) => a + b, 0);
  // 409: the refund still due on a cancelled or refunded invoice.
  const refundDue = Number(f?.refund_due ?? 0);
  const dueTotal = cents(sourceTotal);
  const dueProblem = dueTotal <= 0 ? 'Enter how much went back through each payment.'
    : dueTotal > cents(refundDue) ? `That is more than the ${money(refundDue)} still due.`
    : !confirmed ? `Confirm that the ${money(dueTotal)} has actually gone back to the customer.` : '';
  const amountInput = (label: string, value: number, max: number, change: (n: number) => void) => <label className="invoice-finance-amount">{label}
    <input aria-label={label} type="number" min="0" max={max} step="0.01" value={value || ''} placeholder="0.00" onChange={e => change(Number(e.target.value))} /></label>;
  return <section className="invoice-finance" aria-label="Invoice settlement and corrections">
    {error && <div role="alert" className="alert alert-danger">{error}</div>}
    {rewardReview && <InvoiceRewardResolution invoiceId={invoiceId}
      onCancel={() => setRewardReview(false)}
      onResolved={() => {
        setRewardReview(false);
        setError('The reward entitlements are recorded. Confirm again to complete the refund or cancellation.');
      }} />}
    {options?.review_notes?.map(note => <p role="status" key={note}>{note}</p>)}
    {f && <p>Net payments held: <strong>{money(f.net_received)}</strong> · Outstanding: <strong>{money(f.outstanding)}</strong> · Refund due: <strong>{money(f.refund_due)}</strong> · Refunded: {money(f.refunded)}</p>}
    {canManage && f?.status === 'cancelled' && Number(f?.refund_due) > 0.005 && (usedValue?.length ?? 0) > 0 &&
      <p role="status" data-testid="refund-due-used">This cancelled invoice still holds {money(f.refund_due)}, but its customer already had
        part of what it sold ({usedValueText(usedValue ?? [])}), which the cancellation kept. Not all of it is owed back, so it cannot be
        recorded as paid back here; how much goes back is for the Owner to decide.</p>}
    {/* Refund and cancellation are one footer action now, and payment correction
        sits with the payments it corrects. Only what has no other home remains. */}
    {canManage && !mode && <div className="invoice-finance-actions">
      {!!options?.benefits.some(b => Number(b.remaining_value) > 0) && !['cancelled', 'refunded', 'cancellation_requested', 'refund_requested'].includes(f?.status) &&
        <button className="btn btn-secondary" onClick={() => open('transfer')}>Correct unused benefit recipient</button>}
      {['cancelled', 'refunded'].includes(f?.status) &&
        <button className="btn btn-secondary" onClick={() => open('reopen')}>Preview reopening</button>}
    </div>}
    {mode && <div className="form-grid">
      <strong>{mode === 'refund' ? 'Record money or credit actually returned' : mode === 'refund_due' ? 'Record refund paid' : mode === 'payment' ? 'Correct a recorded payment' : mode === 'transfer' ? 'Move unused credit or vouchers' : 'Reopen invoice'}</strong>
      {mode === 'refund_due' && options && <>
        <p>This invoice is {String(f?.status ?? '').replace(/_/g, ' ')} and still holds <strong>{money(refundDue)}</strong> that has not been
          recorded as returned to the customer. Record it here once it has actually gone back: recording does not send money anywhere. It is
          recorded against the original payments it came in on; a payment made with credit gets that credit back.</p>
        <strong>Paid back through</strong>
        {options.sources.filter(s => Number(s.remaining) > 0).map(s => <div key={s.payment_id}>{amountInput(
          `${s.method} · ${s.wallet ? 'credit restored' : 'money returned'} · up to ${money(s.remaining)}`,
          sourceAmounts[s.payment_id], Number(s.remaining), n => { setDueTouched(true); setSourceAmounts(v => ({ ...v, [s.payment_id]: n })); })}</div>)}
        {options.sources.every(s => Number(s.remaining) <= 0) && <p role="alert">No payment on this invoice still holds money, so there is nothing to record.</p>}
        <p>Recording {money(dueTotal)} of the {money(refundDue)} still due.</p>
        {dueTotal > cents(refundDue) && <p role="alert">{dueProblem}</p>}
        <label><input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} /> The {money(dueTotal)} has actually
          gone back to the customer.</label>
        {dueByLine && <div role="status">
          <p>This invoice's credit or vouchers were issued, so the money goes back through them, line by line.</p>
          <button className="btn btn-secondary" disabled={busy} onClick={() => void open('refund')}>Allocate it line by line instead</button>
        </div>}
      </>}
      {mode === 'transfer' && <>
        <p>Move the selected benefit’s unused balance to the correct recipient or store. Previously consumed value stays with its original recipient. The invoice buyer and original records remain in history.</p>
        <InvoiceSearchSelect label="Unused benefit" value={transferBenefit} onChange={id => {
          const b = options?.benefits.find(b => b.id === id);
          setTransferBenefit(id); setTransferCustomer(b?.customer_id || ''); setTransferStore(b?.store_id || ''); setConfirmed(false);
        }} options={(options?.benefits || []).filter(b => Number(b.remaining_value) > 0 && !Number(b.cancelled_unused_value)).map(b => ({ value: b.id,
          label: `${b.customer_name || 'Recipient'} · ${b.benefit_kind || 'Benefit'} · ${b.reward_voucher_id ? `${b.remaining_value} voucher(s)` : money(b.remaining_value)} unused` }))} />
        <div className="invoice-recipient-picker"><label>Correct recipient</label>
          <CustomerSearchSelect value={transferCustomer} onChange={id => { setTransferCustomer(id); setConfirmed(false); }} />
        </div>
        <InvoiceSearchSelect label="Benefit store" value={transferStore} onChange={id => { setTransferStore(id); setConfirmed(false); }}
          options={stores.map(s => ({ value: s.id, label: s.name }))} />
        <p>No money is returned. Credit category and usage restrictions stay the same. Moving limited vouchers between stores requires stock at the destination.</p>
        <label><input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} /> I confirm the selected unused balance should move to this recipient and store.</label>
      </>}
      {mode === 'refund' && options && <>
        {options.review_required && <p role="alert">Historical refunds need payment-source review before another refund can be recorded.</p>}
        <p>Allocate the refund to invoice lines and original payment sources. Wallet portions return to their original credit source.</p>
        {Number(f?.refund_due) > 0 && options.benefits.length > 0 && <label><input type="checkbox" checked={benefitOverpayment} onChange={e => setBenefitOverpayment(e.target.checked)} /> Refund the correction overpayment from the selected unused benefits. Revoke their proportional unused value without reducing the corrected invoice charge again.</label>}
        {(options.lines || []).map(l => <div key={l.invoice_item_id}>
          {amountInput(`${l.name} (up to ${money(l.remaining)})`, lineAmounts[l.invoice_item_id], l.remaining, n => setLineAmounts(v => ({ ...v, [l.invoice_item_id]: n })))}
          {options.therapy_sessions?.filter(s => s.invoice_item_id === l.invoice_item_id).map(s => <p key={s.invoice_item_id}>{s.used} used · {s.unused} unused session(s). {s.paid_value == null ? 'Original paid value needs review before refund.' : `Refund whole unused sessions only, up to ${money(s.max_refund)}.`}</p>)}
          {options.benefits.filter(b => b.invoice_item_id === l.invoice_item_id).map(b => <div key={b.id}>{amountInput(
            `${b.customer_name || 'Recipient'} · ${b.reward_voucher_id ? 'unused voucher' : 'unused credit'} · up to ${money(b.max_refund)}`,
            benefitAmounts[b.id], b.max_refund, n => setBenefitAmounts(v => ({ ...v, [b.id]: n })))}</div>)}
        </div>)}
        {Number(f?.overpayment_refundable) > 0 && options.benefits.length === 0 && amountInput('Correction overpayment', lineAmounts.excess, f?.overpayment_refundable, n => setLineAmounts(v => ({ ...v, excess: n })))}
        <strong>Return through original payment sources</strong>
        {options.sources.map(s => <div key={s.payment_id}>{amountInput(`${s.method} · ${s.wallet ? 'restore credit' : 'actual refund'} · up to ${money(s.remaining)}`, sourceAmounts[s.payment_id], s.remaining, n => setSourceAmounts(v => ({ ...v, [s.payment_id]: n })))}</div>)}
        <p>Line refund: {money(total)} · Payment allocation: {money(sourceTotal)}</p>
        {options.stock.length > 0 && <strong>Actual product outcomes (quantities)</strong>}
        {options.stock.filter(s => s.quantity > s.resolved_quantity).map(s => <fieldset key={s.movement_id}>
          <legend>{s.product_name} · {s.quantity - s.resolved_quantity} unresolved</legend>
          {(['sellable_quantity', 'damaged_quantity', 'not_returned_quantity'] as const).map((key, idx) => <label className="invoice-finance-amount" key={key}>
            {['Returned and sellable', 'Returned but damaged', 'Not returned'][idx]}
            <input type="number" min="0" step="1" max={s.quantity - s.resolved_quantity} value={stock[s.movement_id]?.[key] || ''} placeholder="0"
              onChange={e => setStock(v => ({ ...v, [s.movement_id]: { ...(v[s.movement_id] || { sellable_quantity: 0, damaged_quantity: 0, not_returned_quantity: 0 }), [key]: Number(e.target.value) } }))} />
          </label>)}
        </fieldset>)}
        {wholeInvoice
          ? waitingItems.length > 0 && <p>Every line goes back in full, so the {waitingItems.length === 1 ? 'item' : `${waitingItems.length} items`} still
              waiting for a warehouse {waitingItems.length === 1 ? 'is' : 'are'} cancelled with the refund.</p>
          : <WaitingItemsQuestion items={waitingItems} answers={waitingAnswers} onChange={setWaitingAnswers}
              lineName={id => options.lines.find(l => l.invoice_item_id === id)?.name} disabled={busy} />}
        <label><input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} /> I confirm the actual money/credit returned and the stock outcomes above. Blank stock quantities do not return stock.</label>
      </>}
      {mode === 'payment' && <>
        <p>The original payment stays in history. This records a reversal and replacement, with a reason. It does not record a customer refund.</p>
        <InvoiceSearchSelect label="Recorded payment" value={paymentId} onChange={choosePayment} options={currentPayments.map(p => ({ value: p.id, label: `${methods.find(m => m.id === p.payment_method_id)?.name || 'Payment'} · ${money(p.amount)} · ${new Date(p.effective_at || p.created_at).toLocaleDateString('en-SG')}` }))} />
        <label>Correct amount<input type="number" min="0.01" step="0.01" value={amount} onChange={e => setAmount(Number(e.target.value))} /></label>
        <label>Actual payment date<input type="date" value={date} onChange={e => setDate(e.target.value)} /></label>
        <InvoiceSearchSelect value={methodId} onChange={setMethodId} options={methods.filter(m => m.is_active && !m.deleted_at).map(m => ({ value: m.id, label: m.name }))} />
      </>}
      {mode === 'reopen' && (preview ? <>
        <p>{preview.explanation}</p>
        <p>Invoice total: {money(preview.total)} · Net payments: {money(preview.net_received)} · Payment required to settle again: {money(Math.max(0, Number(preview.total) - Number(preview.net_received)))}</p>
        <p>Voucher units to replace after settlement: {Number(preview.voucher_units_to_reinstate_after_settlement || 0)}</p>
        <p>Revoked credit to reinstate after settlement: {money(preview.credit_to_reinstate_after_settlement)}</p>
        {!!preview.sessions_to_reinstate_after_settlement && <p>Unused therapy sessions to reinstate after settlement: {preview.sessions_to_reinstate_after_settlement}</p>}
        {preview.blockers?.map((b: string) => <p role="alert" key={b}>{b}</p>)}
        {preview.stock_to_issue?.map((s: any, idx: number) => <p key={idx}>Stock to issue: {s.quantity} × {s.item_name || s.item_id || s.product_id}</p>)}
      </> : <p>Loading reconciliation preview…</p>)}
      <label>Reason (required)<textarea value={reason} onChange={e => setReason(e.target.value)} rows={2} /></label>
      <div className="invoice-finance-actions">
        <button className="btn btn-secondary" disabled={busy} onClick={close}>Back</button>
        <button className="btn btn-primary" disabled={busy || !reason.trim() || (mode === 'transfer' && (!confirmed || !transferBenefit || !transferCustomer || !transferStore)) || (mode === 'reopen' && !preview?.can_reopen) || (mode === 'refund' && (!confirmed || options?.review_required || total <= 0 || Math.abs(total - sourceTotal) > 0.001 || waitingLeft.length > 0)) || (mode === 'refund_due' && !!dueProblem)} onClick={submit}>
          {busy ? 'Recording…' : mode === 'reopen' ? 'Confirm reopening' : mode === 'refund_due' ? `Record ${money(dueTotal)} refund paid` : 'Record with audit history'}
        </button>
      </div>
    </div>}
    {canManage && <InvoiceBenefitEvidenceReview invoiceId={invoiceId} onChanged={onChanged} />}
  </section>;
}
