import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Ban, Crown, RefreshCw, RotateCcw, XCircle } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../context/AuthContext';
import { isOwnerOrManager } from '../../types';
import { Modal, ReasonModal } from '../ui';
import { ExcelColumn, ExcelExportButton } from '../ExcelExport';
import {
  EventRow, VIP_ORDER_STATUS_BADGE, VIP_ORDER_STATUS_LABELS, VIP_PROVIDER_LABELS, VipOrder, VipOrderList, WEB_ORDER_MODE_BADGE,
  WEB_ORDER_MODE_LABELS, fmtDate, fmtDateTime, money, normalizeVipOrderList, sgStamp, slug, vipOrderCanClose,
  vipOrderCanDismiss, vipOrderCanInvoice, vipOrderCanRestore, vipOrderClosedRefunded, vipOrderRefundOpen,
} from './model';

/*
 * Website orders → VIP orders (436): the VIP payments the event's own website
 * sent. HitPay payments are invoiced at once while the website is Live (one
 * invoice per person, each paid with the payment's reference); PayNow and
 * bank transfers always wait here for an Owner, Admin or Manager to confirm
 * the money arrived (Create invoices; when the buyer typed another amount
 * than the order costs, an Owner or Manager enters what really arrived, which
 * the server audits). An order that needs a look says why. A
 * transfer or a test is dismissed (and restored) with a reason; an order
 * whose money was refunded outside the app is closed as refunded by an Owner
 * or Manager (415's rule). HitPay's refund notices are shown until the VIP
 * invoices are cancelled or refunded here, with the app's own refund flow, or
 * that much is recorded as refunded on them (a part refund an Owner or
 * Manager records when a VIP voucher was already used, 436 round 3).
 */

type Filter = 'current' | 'waiting' | 'all';
const FILTERS: { value: Filter; label: string }[] = [
  { value: 'current', label: 'All but dismissed and open checkouts' },
  { value: 'waiting', label: 'Waiting for invoices' },
  { value: 'all', label: 'All, open checkouts too' },
];
const shown = (o: VipOrder, f: Filter) =>
  f === 'all' || (f === 'waiting' ? vipOrderCanInvoice(o) : o.status !== 'dismissed' && o.status !== 'pending');

const paidText = (o: VipOrder) => (o.provider === 'hitpay'
  ? (o.paid_at ? fmtDateTime(o.paid_at) : null)
  : (o.paid_on ? fmtDate(o.paid_on) : null));

export const VIP_ORDER_COLUMNS: ExcelColumn<VipOrder>[] = [
  { header: 'Started (SGT)', value: o => sgStamp(o.created_at) },
  { header: 'Order ID', value: o => o.order_id },
  { header: 'Paid through', value: o => VIP_PROVIDER_LABELS[o.provider] },
  { header: 'Status', value: o => VIP_ORDER_STATUS_LABELS[o.status] },
  { header: 'Payer', value: o => o.payer_name ?? '' },
  { header: 'Payer email', value: o => o.payer_email ?? '' },
  { header: 'Payer phone', value: o => o.payer_phone ?? '' },
  { header: 'People', value: o => o.people.map(p => p.name).join(', ') },
  { header: 'Total S$', value: o => o.amount_total },
  { header: 'Paid S$', value: o => o.amount_paid },
  { header: 'Paid at / on', value: o => (o.provider === 'hitpay' ? sgStamp(o.paid_at) : o.paid_on ?? '') },
  { header: 'Reference', value: o => (o.provider === 'hitpay' ? o.hitpay_payment_id ?? o.hitpay_payment_request_id ?? '' : o.reference ?? '') },
  { header: 'Invoice nos', value: o => o.people.map(p => p.invoice_no).filter(Boolean).join(', ') },
  { header: 'Reason', value: o => o.review_reason ?? '' },
  { header: 'Refunded in HitPay S$', value: o => (o.refunded_total ? o.refunded_total : null) },
  { header: 'Test', value: o => (o.is_test ? 'Y' : 'N') },
];

export const VipOrdersSection: React.FC<{
  event: EventRow;
  /** Invoices were made: the guest list changes. */
  onInvoiced: () => void;
  /** Whether the event has website settings, once known (the channel part can hide then). */
  onLoaded?: (hasSettings: boolean) => void;
}> = ({ event, onInvoiced, onLoaded }) => {
  const { profile } = useAuth();
  const canCloseRole = isOwnerOrManager(profile?.role);
  const [list, setList] = useState<VipOrderList | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>('current');
  const [confirming, setConfirming] = useState<VipOrder | null>(null);
  // What arrived, as an Owner or Manager enters it for a transfer whose typed
  // amount is not the order's total (S$, as typed).
  const [arrived, setArrived] = useState('');
  const [confirmErr, setConfirmErr] = useState<string | null>(null);
  const [dismissing, setDismissing] = useState<VipOrder | null>(null);
  const [closing, setClosing] = useState<VipOrder | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  // The latest callback, so a parent's inline function does not reload the list.
  const loaded = useRef(onLoaded);
  loaded.current = onLoaded;

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('event_vip_orders_list', { p_event_id: event.id });
    setLoading(false);
    // A database without 436, or no access: nothing to show here.
    if (error) { setList(null); loaded.current?.(false); return; }
    const l = normalizeVipOrderList(data);
    setList(l);
    loaded.current?.(!!l.settings);
  }, [event.id]);
  useEffect(() => { void load(); }, [load]);

  const orders = useMemo(() => list?.orders ?? [], [list]);
  const rows = useMemo(() => orders.filter(o => shown(o, filter)), [orders, filter]);
  if (!list?.settings) return null;
  const s = list.settings;
  const canClose = canCloseRole && list.can_close;
  const methodName = (o: VipOrder) => (o.provider === 'hitpay' ? s.hitpay_method_name : o.provider === 'paynow' ? s.paynow_method_name : s.bank_method_name);

  // A transfer whose typed amount is not the order's total: what arrived may be entered.
  const amountDiffers = (o: VipOrder) => o.provider !== 'hitpay' && o.amount_paid !== o.amount_total;
  const openConfirm = (o: VipOrder) => {
    setConfirmErr(null);
    setArrived(o.amount_paid != null ? o.amount_paid.toFixed(2) : '');
    setConfirming(o);
  };
  const createInvoices = async () => {
    const o = confirming;
    if (!o) return;
    // Sent only when an Owner or Manager changed it; the server checks the role and audits it.
    let amountCents: number | null = null;
    if (amountDiffers(o) && canCloseRole) {
      const v = Number(arrived.trim());
      if (!arrived.trim() || !Number.isFinite(v) || v < 0) { setConfirmErr('Enter the amount that arrived, in S$.'); return; }
      const cents = Math.round(v * 100);
      if (cents !== (o.amount_paid == null ? null : Math.round(o.amount_paid * 100))) amountCents = cents;
    }
    setConfirming(null); setBusyId(o.id); setErr(null); setNotice(null);
    const { data, error } = await supabase.rpc('event_vip_order_invoice', amountCents == null
      ? { p_order_id: o.id }
      : { p_order_id: o.id, p_amount_cents: amountCents });
    setBusyId(null);
    if (error) { setErr(error.message); return; }
    const r = (data ?? {}) as { status?: string; review_reason?: string | null; invoice_nos?: string[] };
    if (r.status === 'invoiced') {
      setNotice(`${o.order_id} is invoiced: ${(r.invoice_nos ?? []).join(', ')}.`);
      onInvoiced();
    } else {
      setErr(`${o.order_id} still waits: ${r.review_reason ?? r.status ?? ''}`);
    }
    await load();
  };
  const setDismissed = async (o: VipOrder, dismiss: boolean, reason: string | null): Promise<string | null> => {
    setBusyId(o.id); setErr(null);
    const { error } = await supabase.rpc('event_vip_order_dismiss', { p_order_id: o.id, p_reason: reason, p_dismiss: dismiss });
    setBusyId(null);
    if (error) return error.message;
    await load();
    return null;
  };
  const setClosed = async (o: VipOrder, close: boolean, reason: string | null): Promise<string | null> => {
    setBusyId(o.id); setErr(null);
    const { error } = await supabase.rpc('event_vip_order_close_refunded', { p_order_id: o.id, p_reason: reason, p_close: close });
    setBusyId(null);
    if (error) return error.message;
    await load();
    return null;
  };
  const restore = async (o: VipOrder) => { const f = await setDismissed(o, false, null); if (f) setErr(f); };
  const reopen = async (o: VipOrder) => { const f = await setClosed(o, false, null); if (f) setErr(f); };

  const waiting = orders.filter(vipOrderCanInvoice).length;
  const refunds = orders.filter(vipOrderRefundOpen).length;

  return (
    <div className="events-vip-orders" data-vip-orders>
      <div className="card events-web-head">
        <div className="events-head-top">
          <div className="events-web-mode">
            <Crown size={16} /><strong>VIP orders</strong>
            <span className={WEB_ORDER_MODE_BADGE[s.mode]}>Website: {WEB_ORDER_MODE_LABELS[s.mode]}</span>
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <select value={filter} onChange={e => setFilter(e.target.value as Filter)} aria-label="VIP order status">
              {FILTERS.map(f => <option key={f.value} value={f.value}>{f.label}</option>)}
            </select>
            <button className="btn btn-secondary btn-sm" onClick={() => void load()}>
              <RefreshCw size={13} className={loading ? 'spin' : ''} /> Refresh
            </button>
            <ExcelExportButton rows={orders} columns={VIP_ORDER_COLUMNS} filename={`vip-orders-${slug(event.name)}`} sheetName="VIP orders" />
          </div>
        </div>
        <div className="events-sub">
          {orders.length} order{orders.length === 1 ? '' : 's'}{waiting ? ` · ${waiting} waiting for invoices` : ''}
          {refunds ? ` · ${refunds} refunded in HitPay` : ''} · invoices at {s.store_name ?? '—'} · event code {s.code}
        </div>
      </div>
      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
      {notice && <div className="alert alert-info" role="status"><span>✓</span><div>{notice}</div></div>}

      <div className="card">
        <div className="table-wrap">
          {rows.length === 0 ? (
            <div className="empty-state"><p style={{ fontWeight: 600 }}>{orders.length ? 'No VIP order matches' : 'No VIP orders yet'}</p></div>
          ) : (
            <table className="events-table events-vip-table">
              <thead>
                <tr><th>Payer</th><th>People</th><th className="events-num">Total S$</th><th>Paid</th><th>Status</th><th></th></tr>
              </thead>
              <tbody>
                {rows.map(o => (
                  <tr key={o.id} data-vip-order={o.order_id} className={o.status === 'dismissed' ? 'events-row-cancelled' : undefined}>
                    <td className="events-web-wide">
                      <strong>{o.payer_name ?? '—'}</strong>{' '}
                      <span className="badge badge-muted">{VIP_PROVIDER_LABELS[o.provider]}</span>
                      {o.is_test && <> <span className="badge badge-accent" title="Sent with the website's test key: nothing was made">Test</span></>}
                      <div className="events-sub">{[o.payer_phone, o.payer_email].filter(Boolean).join(' · ')}</div>
                      <div className="events-sub">{o.order_id}</div>
                    </td>
                    <td className="events-web-wide">
                      {o.people.map(p => (
                        <div key={p.person_id}>
                          {p.name}{' '}
                          {p.match === 'held'
                            ? <span className="badge badge-danger" title="Link them to a customer on the Guests tab first">To match</span>
                            : p.customer_name ? <span className="events-sub">({p.customer_name})</span> : null}
                          {p.invoice_no && <span className="events-sub"> · {p.invoice_no}{p.invoice_status && ['cancelled', 'refunded'].includes(p.invoice_status) ? ` (${p.invoice_status})` : ''}</span>}
                        </div>
                      ))}
                    </td>
                    <td className="events-num">
                      {money(o.amount_total)}
                      {o.quantity > 1 && <div className="events-sub">{o.quantity} × {money(o.unit_amount)}</div>}
                      {o.amount_paid != null && o.amount_paid !== o.amount_total && <div className="events-sub">paid {money(o.amount_paid)}</div>}
                    </td>
                    <td>
                      {paidText(o) ?? <span className="events-muted">{o.status === 'pending' ? (o.expired ? 'Checkout expired' : 'Checkout open') : '—'}</span>}
                      {o.provider !== 'hitpay' && o.reference && <div className="events-sub">ref {o.reference}</div>}
                    </td>
                    <td className="events-web-status">
                      <span className={`${VIP_ORDER_STATUS_BADGE[o.status]} events-status-badge`}>{VIP_ORDER_STATUS_LABELS[o.status]}</span>
                      {o.review_reason && o.status !== 'invoiced' && <div className="events-sub">{o.review_reason}</div>}
                      {o.test_note && <div className="events-sub">{o.test_note}</div>}
                      {vipOrderRefundOpen(o) && (
                        <div className="events-sub events-vip-refund">
                          HitPay refunded {money(o.refunded_total)}{o.refund_noted_at ? ` on ${fmtDateTime(o.refund_noted_at)}` : ''}:
                          cancel or refund the VIP invoice(s) here with the usual refund (once a VIP voucher was
                          used, an Owner or Manager records a part refund instead).
                        </div>
                      )}
                    </td>
                    <td className="events-web-actions-cell">
                      <div className="events-actions events-web-actions">
                        {vipOrderCanInvoice(o) && (
                          <button className="btn btn-primary btn-sm" disabled={busyId === o.id} onClick={() => openConfirm(o)}>Create invoices</button>
                        )}
                        {vipOrderCanDismiss(o) && (
                          <button className="btn btn-secondary btn-sm" disabled={busyId === o.id} onClick={() => setDismissing(o)}>
                            <XCircle size={13} /> Dismiss
                          </button>
                        )}
                        {vipOrderCanRestore(o) && (
                          <button className="btn btn-secondary btn-sm" disabled={busyId === o.id} onClick={() => void restore(o)}>
                            <RotateCcw size={13} /> Restore
                          </button>
                        )}
                        {canClose && vipOrderCanClose(o) && !o.is_test && (
                          <button className="btn btn-secondary btn-sm" disabled={busyId === o.id} onClick={() => setClosing(o)}>
                            <Ban size={13} /> Close as refunded
                          </button>
                        )}
                        {canClose && vipOrderClosedRefunded(o) && (
                          <button className="btn btn-secondary btn-sm" disabled={busyId === o.id} onClick={() => void reopen(o)}>
                            <RotateCcw size={13} /> Reopen
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {confirming && (
        <Modal title={`Create invoices for ${confirming.order_id}?`} maxWidth={480} onClose={() => setConfirming(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setConfirming(null)}>Cancel</button>
            <button className="btn btn-primary" data-confirm onClick={() => void createInvoices()}>Create invoices</button>
          </>}>
          <div className="form-grid">
            {confirming.provider === 'hitpay' ? (
              <div>HitPay took {money(confirming.amount_paid ?? confirming.amount_total)}{confirming.paid_at ? ` on ${fmtDateTime(confirming.paid_at)}` : ''}.
                Check the payment in HitPay first if the order says why it waits.</div>
            ) : amountDiffers(confirming) ? (
              <>
                <div data-amount-differs>
                  Expected {money(confirming.amount_total)} ({confirming.quantity} × {money(confirming.unit_amount)}) · the buyer typed{' '}
                  {confirming.amount_paid == null ? 'no amount' : money(confirming.amount_paid)}, by {VIP_PROVIDER_LABELS[confirming.provider]}
                  {confirming.reference ? `, reference ${confirming.reference}` : ''}{confirming.paid_on ? `, on ${fmtDate(confirming.paid_on)}` : ''}.
                  Check the bank statement for what really arrived.
                </div>
                {canCloseRole ? (
                  <div className="form-group">
                    <label htmlFor="vip-arrived">Amount that arrived (S$)</label>
                    <input id="vip-arrived" type="number" inputMode="decimal" min={0} step="0.01" value={arrived} data-arrived
                      onChange={e => { setArrived(e.target.value); setConfirmErr(null); }} />
                  </div>
                ) : (
                  <div className="events-sub">Only an Owner or Manager can enter the amount that arrived.</div>
                )}
                <div className="events-sub">
                  If what arrived is not {confirming.quantity} × {money(confirming.unit_amount)}, nothing is invoiced: dismiss this order and
                  send the VIP link again for the people actually paid for.
                </div>
                {confirmErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{confirmErr}</div></div>}
              </>
            ) : (
              <div>{money(confirming.amount_paid ?? confirming.amount_total)} arrived by {VIP_PROVIDER_LABELS[confirming.provider]}
                {confirming.reference ? `, reference ${confirming.reference}` : ''}{confirming.paid_on ? `, on ${fmtDate(confirming.paid_on)}` : ''}?
                Check the bank statement first.</div>
            )}
            <div className="events-sub">
              One invoice per person ({confirming.quantity}), each {money(confirming.unit_amount)} paid by {methodName(confirming) ?? 'the website\'s method'},
              with the VIP vouchers on each person's own account.
            </div>
          </div>
        </Modal>
      )}
      {dismissing && (
        <ReasonModal title={`Dismiss ${dismissing.order_id}`} label="Why is it set aside?" confirmLabel="Dismiss" minLength={3}
          placeholder="e.g. Sent twice, never paid" onClose={() => setDismissing(null)}
          onSubmitAsync={reason => setDismissed(dismissing, true, reason)} />
      )}
      {closing && (
        <ReasonModal title={`Close ${closing.order_id} as refunded`} label="How was it refunded?" confirmLabel="Close as refunded"
          minLength={3} placeholder="e.g. Refunded in HitPay on 25 Nov" onClose={() => setClosing(null)}
          onSubmitAsync={reason => setClosed(closing, true, reason)} />
      )}
    </div>
  );
};

export default VipOrdersSection;
