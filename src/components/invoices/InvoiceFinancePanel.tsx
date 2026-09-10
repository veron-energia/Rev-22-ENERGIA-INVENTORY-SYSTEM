import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { InvoiceSearchSelect } from './InvoiceSearchSelect';
import { singaporeToday } from '../../lib/invoices/business';
import { CustomerSearchSelect } from '../SearchSelect';
import { InvoiceBenefitEvidenceReview } from './InvoiceBenefitEvidenceReview';

const money = (n: unknown) => `S$${Number(n || 0).toFixed(2)}`;
type Mode = '' | 'refund' | 'payment' | 'cancel' | 'reopen' | 'transfer';
type Source = { payment_id: string; method: string; wallet: boolean; remaining: number };
type Benefit = { id: string; invoice_item_id: string; customer_name?: string; customer_id?: string; store_id?: string; benefit_kind?: string; cancelled_unused_value?: number; remaining_value: number; max_refund: number; reward_voucher_id?: string };
type Stock = { movement_id: string; product_name: string; quantity: number; resolved_quantity: number };
type Line = { invoice_item_id: string; name: string; remaining: number; line_kind: string };
type Options = { financial: Record<string, any>; sources: Source[]; benefits: Benefit[]; stock: Stock[]; lines: Line[]; review_required: boolean; review_notes?: string[]; therapy_sessions?: { invoice_item_id: string; name: string; used: number; unused: number; paid_value: number | null; max_refund: number | null }[] };

/** All amounts are proposals: the locked database transaction rechecks capacity,
 * source ownership, benefit use and stock evidence before recording anything. */
export function InvoiceFinancePanel({ invoiceId, canManage, payments, methods, stores = [], onChanged }: {
  invoiceId: string; canManage: boolean; payments: any[]; methods: any[]; stores?: { id: string; name: string }[]; onChanged: () => Promise<void>;
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
  useEffect(() => {
    let cancelled = false;
    setOptions(null);
    supabase.rpc('invoice_refund_options', { p_invoice_id: invoiceId }).then(({ data, error }) => {
      if (!cancelled) { setOptions(data); setError(error?.message || ''); }
    });
    return () => { cancelled = true; };
  }, [invoiceId, payments]);
  const open = async (next: Mode) => {
    setMode(next); setError(''); setReason(''); setRequestId(crypto.randomUUID()); setConfirmed(false); setBenefitOverpayment(false);
    setLineAmounts({}); setBenefitAmounts({}); setSourceAmounts({}); setStock({}); setPreview(null);
    setTransferBenefit(''); setTransferCustomer(''); setTransferStore('');
    if (next === 'reopen') {
      const { data, error } = await supabase.rpc('invoice_reopen_preview', { p_invoice_id: invoiceId });
      setPreview(data); setError(error?.message || '');
    }
  };
  const currentPayments = payments.filter(p => p.entry_kind !== 'correction_reversal' && !payments.some(r => r.corrects_payment_id === p.id && r.entry_kind === 'correction_reversal'));
  const choosePayment = (id: string) => {
    const p = currentPayments.find(p => p.id === id);
    setPaymentId(id); setAmount(Number(p.amount)); setMethodId(p.payment_method_id);
    setDate(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore' }).format(new Date(p.effective_at || p.created_at)));
  };
  const submit = async () => {
    if (!reason.trim()) { setError('Enter a reason for the audit history.'); return; }
    if (mode === 'refund' && !confirmed) { setError('Confirm the actual refund and stock outcomes before recording.'); return; }
    setBusy(true); setError('');
    try {
      let result;
      const common = { p_invoice_id: invoiceId, p_reason: reason.trim(), p_request_id: requestId };
      if (mode === 'refund') {
        const lines = Object.entries(lineAmounts).filter(([, amount]) => amount > 0).map(([id, amount]) => ({
          invoice_item_id: id === 'excess' ? null : id, amount, overpayment: benefitOverpayment && (options?.benefits || []).some(b => b.invoice_item_id === id),
          benefits: (options?.benefits || []).filter(b => b.invoice_item_id === id && benefitAmounts[b.id] > 0).map(b => ({ benefit_id: b.id, amount: benefitAmounts[b.id] })),
        }));
        result = await supabase.rpc('refund_invoice_recorded', { ...common, p_lines: lines,
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
      } else result = await supabase.rpc(mode === 'reopen' ? 'reopen_invoice' : 'cancel_invoice_recorded', common);
      if (result.error) throw result.error;
      setMode(''); await onChanged();
    } catch (e: any) { setError(e.message || 'The request could not be completed. Your entered details have been kept.'); }
    finally { setBusy(false); }
  };
  const f = options?.financial;
  const total = Object.values(lineAmounts).reduce((a, b) => a + b, 0);
  const sourceTotal = Object.values(sourceAmounts).reduce((a, b) => a + b, 0);
  const amountInput = (label: string, value: number, max: number, change: (n: number) => void) => <label className="invoice-finance-amount">{label}
    <input aria-label={label} type="number" min="0" max={max} step="0.01" value={value || ''} placeholder="0.00" onChange={e => change(Number(e.target.value))} /></label>;
  return <section className="invoice-finance" aria-label="Invoice settlement and corrections">
    {error && <div role="alert" className="alert alert-danger">{error}</div>}
    {options?.review_notes?.map(note => <p role="status" key={note}>{note}</p>)}
    {f && <p>Net payments held: <strong>{money(f.net_received)}</strong> · Outstanding: <strong>{money(f.outstanding)}</strong> · Refund due: <strong>{money(f.refund_due)}</strong> · Refunded: {money(f.refunded)}</p>}
    {canManage && !mode && <div className="invoice-finance-actions">
      <button className="btn btn-secondary" onClick={() => open('refund')}>Record full / partial refund</button>
      {!!options?.benefits.some(b => Number(b.remaining_value) > 0) && !['cancelled', 'refunded', 'cancellation_requested', 'refund_requested'].includes(f?.status) &&
        <button className="btn btn-secondary" onClick={() => open('transfer')}>Correct unused benefit recipient</button>}
      {currentPayments.length > 0 && <button className="btn btn-secondary" onClick={() => { open('payment'); choosePayment(currentPayments[0].id); }}>Correct payment amount / date</button>}
      {['cancelled', 'refunded'].includes(f?.status) ? <button className="btn btn-secondary" onClick={() => open('reopen')}>Preview reopening</button>
        : <button className="btn btn-danger" onClick={() => open('cancel')}>Cancel invoice</button>}
    </div>}
    {mode && <div className="form-grid">
      <strong>{mode === 'refund' ? 'Record money or credit actually returned' : mode === 'payment' ? 'Correct a recorded payment' : mode === 'transfer' ? 'Move unused credit or vouchers' : mode === 'reopen' ? 'Reopen invoice' : 'Cancel invoice'}</strong>
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
        <label><input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} /> I confirm the actual money/credit returned and the stock outcomes above. Blank stock quantities do not return stock.</label>
      </>}
      {mode === 'payment' && <>
        <p>The original payment stays in history. This records a reversal and replacement, with a reason. It does not record a customer refund.</p>
        <InvoiceSearchSelect label="Recorded payment" value={paymentId} onChange={choosePayment} options={currentPayments.map(p => ({ value: p.id, label: `${methods.find(m => m.id === p.payment_method_id)?.name || 'Payment'} · ${money(p.amount)} · ${new Date(p.effective_at || p.created_at).toLocaleDateString('en-SG')}` }))} />
        <label>Correct amount<input type="number" min="0.01" step="0.01" value={amount} onChange={e => setAmount(Number(e.target.value))} /></label>
        <label>Actual payment date<input type="date" value={date} onChange={e => setDate(e.target.value)} /></label>
        <InvoiceSearchSelect value={methodId} onChange={setMethodId} options={methods.filter(m => m.is_active && !m.deleted_at).map(m => ({ value: m.id, label: m.name }))} />
      </>}
      {mode === 'cancel' && <p>Cancellation releases outstanding stock deductions and unused benefits. Existing payments and consumed benefits remain in history. Record any actual refund separately.</p>}
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
        <button className="btn btn-secondary" disabled={busy} onClick={() => setMode('')}>Back</button>
        <button className="btn btn-primary" disabled={busy || !reason.trim() || (mode === 'transfer' && (!confirmed || !transferBenefit || !transferCustomer || !transferStore)) || (mode === 'reopen' && !preview?.can_reopen) || (mode === 'refund' && (!confirmed || options?.review_required || total <= 0 || Math.abs(total - sourceTotal) > 0.001))} onClick={submit}>
          {busy ? 'Recording…' : mode === 'reopen' ? 'Confirm reopening' : mode === 'cancel' ? 'Confirm cancellation' : 'Record with audit history'}
        </button>
      </div>
    </div>}
    {canManage && <InvoiceBenefitEvidenceReview invoiceId={invoiceId} onChanged={onChanged} />}
  </section>;
}
