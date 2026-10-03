import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CreditCard, Globe, Link2, RefreshCw, RotateCcw, Store, UserRound, XCircle } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal, ReasonModal } from '../ui';
import { ExcelColumn, ExcelExportButton } from '../ExcelExport';
import {
  EventRow, WEB_ORDER_MODE_BADGE, WEB_ORDER_MODE_LABELS, WEB_ORDER_STATUS_BADGE, WEB_ORDER_STATUS_LABELS,
  WebOrder, WebOrderLinkPreview, WebOrderList, WebOrderMode, WebOrderOutcome, fmtDate, fmtDateTime, fmtSgDate, fmtTime, money,
  normalizeWebOrderLinkPreview, normalizeWebOrderList, normalizeWebOrderOutcome, sgStamp, slug,
  webOrderAmountDiffers, webOrderCanDismiss, webOrderCanInvoice, webOrderCanLink, webOrderCanRestore, webOrderDatePaid, webOrderIsOpen,
  webOrderPaidThrough, webOrderProviderName, webOrderSource, webOrderStatusText, webOrderTestPlace, webOrderTestRefused,
} from './model';

/*
 * Tickets bought on the event's website. Each paid order is recorded here;
 * while the channel is Live it becomes an invoice at once, raised by the
 * channel's person at its store and paid by its payment method. An order
 * that could not be matched to one customer waits as Needs review, and every
 * order waits as Recorded while the channel only records: Create invoice
 * finishes either, except for a test payment (Stripe's test mode or HitPay's
 * sandbox) while the channel does not accept test orders. Owners, Admins and Managers see this tab and only
 * the Owner switches the channel; the server enforces all three.
 *
 * 380: registrations made through the website's staff link (paid in cash, by
 * PayNow or by bank transfer) come here too and are never invoiced by
 * themselves, even while Live: a Manager checks that the money arrived and
 * clicks Create invoice, which pays it by the form's method and credits the
 * staff member the form names. One already invoiced by hand is linked to that
 * invoice instead (the list names any invoice made by hand for the event with
 * the buyer's phone), and so is one whose amount is not the price, which
 * Create invoice cannot make, or one refused while the channel was off. A test
 * registration is dismissed (and can be restored).
 * The website asks the inventory for the invoice numbers and fills its
 * workbook with them itself.
 */

const MODES: WebOrderMode[] = ['off', 'record_only', 'live'];
const MODE_BUTTONS: Record<WebOrderMode, string> = { off: 'Off', record_only: 'Record only', live: 'Live' };

// Dismissed registrations are tests set aside, so they stay out of sight unless asked for.
type StatusFilter = 'current' | 'waiting' | 'invoiced' | 'refused' | 'dismissed' | 'all';
const STATUS_FILTERS: { value: StatusFilter; label: string }[] = [
  { value: 'current', label: 'All but dismissed' },
  { value: 'waiting', label: 'Waiting for an invoice' },
  { value: 'invoiced', label: 'Invoiced' },
  { value: 'refused', label: 'Refused' },
  { value: 'dismissed', label: 'Dismissed' },
  { value: 'all', label: 'All, dismissed too' },
];
const statusShown = (o: WebOrder, f: StatusFilter) =>
  f === 'all' || (f === 'current' ? o.status !== 'dismissed' : f === 'waiting' ? webOrderIsOpen(o) : o.status === f);

/** "INV-… (Store)", or "an invoice at Store" where the number is out of sight. */
const handInvoicesText = (o: WebOrder) => o.hand_invoices
  .map(h => (h.invoice_no ? `${h.invoice_no}${h.store ? ` (${h.store})` : ''}` : `an invoice at ${h.store ?? 'another store'}`))
  .join(', ');

export const WEB_ORDER_COLUMNS: ExcelColumn<WebOrder>[] = [
  { header: 'Paid at (SGT)', value: o => sgStamp(o.paid_at) },
  { header: 'Buyer', value: o => o.buyer_name },
  { header: 'Phone', value: o => o.buyer_phone ?? '' },
  { header: 'Email', value: o => o.buyer_email ?? '' },
  { header: 'Pass', value: o => o.ticket_label },
  { header: 'People', value: o => o.quantity },
  { header: 'Names', value: o => (o.attendees ?? []).map(a => a.name).join(', ') },
  { header: 'Unit S$', value: o => o.unit_amount },
  { header: 'Total S$', value: o => o.amount_total },
  { header: 'Early bird', value: o => (o.early_bird ? 'Y' : 'N') },
  { header: 'Status', value: o => WEB_ORDER_STATUS_LABELS[o.status] },
  // Side by side, as in the website's workbook: its Order ID is the checkout
  // (Stripe's, or HitPay's payment request), or the staff link's OFF-… id.
  { header: 'Invoice no', value: o => o.invoice_no ?? '' },
  { header: 'Order ID (checkout)', value: o => o.stripe_session_id },
  // 380: a staff-link registration is paid by the form's method on its Date
  // paid; its Paid at is when the form was sent.
  { header: 'Source', value: o => webOrderSource(o) },
  { header: 'Paid through', value: o => webOrderPaidThrough(o) },
  { header: 'Date paid', value: o => webOrderDatePaid(o) ?? '' },
  { header: 'Payment ref', value: o => o.payment_reference ?? '' },
  { header: 'Registered by', value: o => o.staff_name ?? '' },
  { header: 'Reason', value: o => o.review_reason ?? '' },
  { header: 'Test order', value: o => (o.livemode ? 'N' : 'Y') },
  { header: 'Checkout opened (SGT)', value: o => sgStamp(o.checkout_opened_at) },
  { header: 'Names received (SGT)', value: o => sgStamp(o.names_at) },
];

export const WebOrdersTab: React.FC<{ event: EventRow; onInvoiced: () => void }> = ({ event, onInvoiced }) => {
  const [list, setList] = useState<WebOrderList | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [switching, setSwitching] = useState(false);
  const [confirming, setConfirming] = useState<WebOrderMode | null>(null);
  const [resolving, setResolving] = useState<WebOrder | null>(null);
  const [linking, setLinking] = useState<WebOrder | null>(null);
  const [dismissing, setDismissing] = useState<WebOrder | null>(null);
  const [applying, setApplying] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [filter, setFilter] = useState<StatusFilter>('current');

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('web_orders_list', { p_event_id: event.id });
    setLoading(false);
    if (error) { setErr(error.message); return; }
    setErr(null);
    setList(normalizeWebOrderList(data));
  }, [event.id]);
  useEffect(() => { void load(); }, [load]);

  const channel = list?.channel ?? null;
  const orders = useMemo(() => list?.orders ?? [], [list]);
  const shown = useMemo(() => orders.filter(o => statusShown(o, filter)), [orders, filter]);
  const counts = useMemo(() => ({
    invoiced: orders.filter(o => o.status === 'invoiced').length,
    recorded: orders.filter(o => o.status === 'recorded').length,
    review: orders.filter(o => o.status === 'needs_review').length,
    refused: orders.filter(o => o.status === 'refused').length,
    dismissed: orders.filter(o => o.status === 'dismissed').length,
    door: orders.filter(o => o.provider === 'door').length,
    test: orders.filter(o => !o.livemode).length,
  }), [orders]);

  const setMode = async (mode: WebOrderMode) => {
    if (!channel) return;
    setConfirming(null); setSwitching(true); setErr(null);
    const { error } = await supabase.rpc('web_order_channel_set_mode', { p_key: channel.key, p_mode: mode });
    setSwitching(false);
    if (error) { setErr(error.message); return; }
    await load();
  };
  // Live invoices every paid order and Off refuses them, so both are asked first.
  const pickMode = (mode: WebOrderMode) => {
    if (!channel || mode === channel.mode) return;
    if (mode === 'record_only') void setMode(mode); else setConfirming(mode);
  };

  // 373: names kept on an invoiced order (its ticket line did not fit them) go on once it does.
  const applyNames = async (o: WebOrder) => {
    setApplying(o.id); setErr(null);
    const { error } = await supabase.rpc('web_order_apply_names', { p_order_id: o.id });
    setApplying(null);
    if (error) { setErr(error.message); return; }
    await load();
  };

  const onResolved = (r: WebOrderOutcome) => {
    void load();
    if (r.status === 'invoiced') onInvoiced();
  };

  // 380: a staff-link registration set aside (a test) with a reason, or brought back.
  const setDismissed = async (o: WebOrder, dismiss: boolean, reason: string | null) => {
    setBusyId(o.id); setErr(null);
    const { error } = await supabase.rpc('web_order_dismiss', { p_order_id: o.id, p_reason: reason, p_dismiss: dismiss });
    setBusyId(null);
    if (error) { setErr(error.message); return; }
    await load();
  };

  return (
    <div>
      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}

      {channel ? (
        <div className="card events-web-head">
          <div className="events-head-top">
            <div className="events-web-mode">
              <Globe size={16} /><strong>Website</strong>
              <span className={WEB_ORDER_MODE_BADGE[channel.mode]}>{WEB_ORDER_MODE_LABELS[channel.mode]}</span>
              {channel.allow_test && <span className="events-chip">Test orders accepted</span>}
            </div>
            {list?.can_switch && (
              <div className="events-seg" role="group" aria-label="Website orders mode">
                {MODES.map(m => (
                  <button key={m} className={`btn btn-sm ${channel.mode === m ? 'btn-primary' : 'btn-secondary'}`}
                    aria-pressed={channel.mode === m} disabled={switching} onClick={() => pickMode(m)}>
                    {MODE_BUTTONS[m]}
                  </button>
                ))}
              </div>
            )}
          </div>
          <div className="events-line"><Store size={14} /><span>Store: {channel.store_name ?? '—'}</span></div>
          <div className="events-line"><UserRound size={14} /><span>Raised by: {channel.acting_name ?? '—'}</span></div>
          <div className="events-line"><CreditCard size={14} /><span>Payment method: {channel.payment_method_name ?? '—'}{channel.hitpay_payment_method_name ? <> · HitPay orders: {channel.hitpay_payment_method_name}</> : null}</span></div>
          <div className="events-sub">Channel {channel.key}</div>
        </div>
      ) : list && (
        <div className="alert alert-info" role="status">
          <span>ⓘ</span><div>This event has no website channel, so no website orders come in for it.</div>
        </div>
      )}

      <div className="events-toolbar">
        <div className="events-count-line" style={{ marginBottom: 0 }}>
          {list ? [
            shown.length === orders.length
              ? `${orders.length} order${orders.length === 1 ? '' : 's'}`
              : `Showing ${shown.length} of ${orders.length} orders`,
            counts.invoiced && `${counts.invoiced} invoiced`,
            counts.recorded && `${counts.recorded} recorded`,
            counts.review && `${counts.review} need${counts.review === 1 ? 's' : ''} review`,
            counts.refused && `${counts.refused} refused`,
            counts.dismissed && `${counts.dismissed} dismissed`,
            counts.door && `${counts.door} through the staff link`,
            counts.test && `${counts.test} test`,
          ].filter(Boolean).join(' · ') : ''}
        </div>
        <div style={{ display: 'flex', gap: 8, marginLeft: 'auto', flexWrap: 'wrap' }}>
          <select value={filter} onChange={e => setFilter(e.target.value as StatusFilter)} aria-label="Order status">
            {STATUS_FILTERS.map(f => <option key={f.value} value={f.value}>{f.label}</option>)}
          </select>
          <button className="btn btn-secondary" onClick={() => void load()}>
            <RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh
          </button>
          {/* Every order, whatever the status filter shows: the Status column tells them apart. */}
          <ExcelExportButton rows={orders} columns={WEB_ORDER_COLUMNS} filename={`website-orders-${slug(event.name)}`}
            sheetName="Website orders" dateOf={webOrderDatePaid} dateLabel="Paid" dateTimeZone="Asia/Singapore" disabled={!list} />
        </div>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading && !list ? (
            <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          ) : !list ? (
            <div className="empty-state"><p>The website orders could not be loaded.</p></div>
          ) : orders.length === 0 ? (
            <div className="empty-state">
              <Globe size={32} style={{ opacity: 0.3, marginBottom: 8 }} />
              <p style={{ fontWeight: 600 }}>No website orders yet</p>
              <p style={{ fontSize: 13 }}>Tickets paid for on the event's website, or registered through its staff link, appear here.</p>
            </div>
          ) : shown.length === 0 ? (
            <div className="empty-state">
              <p style={{ fontWeight: 600 }}>No order matches</p>
              <p style={{ fontSize: 13 }}>Change the status filter.</p>
            </div>
          ) : (
            <table className="events-table events-web-table">
              <thead>
                <tr>
                  <th>Paid at (SGT)</th><th>Buyer</th><th>Pass</th><th>People</th>
                  <th className="events-num">Total S$</th><th>Early bird</th><th>Status</th>
                  <th className="events-web-actions-cell"></th>
                </tr>
              </thead>
              <tbody>
                {shown.map(o => (
                  <tr key={o.id} data-order={o.id} className={o.status === 'dismissed' ? 'events-row-cancelled' : undefined}>
                    <td>
                      {o.provider === 'door' ? (
                        // 380: a staff-link registration is paid on the form's date, by its method.
                        <>
                          <span className="events-nowrap">{fmtDate(o.paid_on)}</span>
                          <div className="events-sub events-web-door-pay">
                            {webOrderPaidThrough(o)}{o.payment_reference ? ` · ref ${o.payment_reference}` : ''}
                          </div>
                          {o.paid_at && <div className="events-sub">Form sent {fmtDateTime(o.paid_at)}</div>}
                        </>
                      ) : o.paid_at
                        ? <><span className="events-nowrap">{fmtSgDate(o.paid_at)},</span> <span className="events-nowrap">{fmtTime(o.paid_at)}</span></>
                        : <span className="events-muted">—</span>}
                    </td>
                    <td className="events-web-wide">
                      <strong>{o.buyer_name || '—'}</strong>
                      {o.provider === 'hitpay' && (
                        <> <span className="badge badge-muted" title="Paid through HitPay">HitPay</span></>
                      )}
                      {o.provider === 'door' && (
                        <> <span className="badge badge-muted" title="Registered through the website's staff link">Staff link</span></>
                      )}
                      {!o.livemode && (
                        <> <span className="badge badge-accent" title={`Paid in ${webOrderTestPlace(o.provider)}: no money was taken`}>Test</span></>
                      )}
                      {o.buyer_phone && <div className="events-sub">{o.buyer_phone}</div>}
                      {o.buyer_email && <div className="events-sub">{o.buyer_email}</div>}
                      {o.staff_name && <div className="events-sub events-web-staff">Registered by {o.staff_name}</div>}
                    </td>
                    <td className="events-nowrap">{o.ticket_label || '—'}</td>
                    <td className="events-web-wide">
                      {o.attendees && o.attendees.length > 0
                        ? o.attendees.map((a, i) => <div key={i}>{a.name}</div>)
                        : (
                          <>
                            <div>{o.quantity} {o.quantity === 1 ? 'person' : 'people'}</div>
                            <div className="events-sub">Names not in yet</div>
                          </>
                        )}
                    </td>
                    <td className="events-num">
                      {money(o.amount_total)}
                      {o.quantity > 1 && <div className="events-sub">{o.quantity} × {money(o.unit_amount)}</div>}
                    </td>
                    <td>{o.early_bird ? 'Yes' : <span className="events-muted">—</span>}</td>
                    <td className="events-web-status">
                      <span className={`${WEB_ORDER_STATUS_BADGE[o.status]} events-status-badge`}>{webOrderStatusText(o)}</span>
                      {/* 373: names that could not go on the invoice's ticket line say why. */}
                      {o.status === 'invoiced' && o.review_reason && (
                        <>
                          <div className="events-sub events-web-names-note">{o.review_reason}</div>
                          <button className="btn btn-secondary btn-sm events-web-apply-names" disabled={applying === o.id}
                            title="After fixing the invoice's ticket line, put the buyer's names on it"
                            onClick={() => void applyNames(o)}>
                            {applying === o.id ? 'Putting names on…' : 'Put names on the invoice'}
                          </button>
                        </>
                      )}
                      {/* 380: an invoice made by hand for the event with the buyer's phone may already be this order's. */}
                      {webOrderCanLink(o) && o.hand_invoices.length > 0 && (
                        <div className="events-sub events-web-hand-hint">
                          Possibly already invoiced by hand: {handInvoicesText(o)}. Use Link invoice if so.
                        </div>
                      )}
                    </td>
                    <td className="events-web-actions-cell">
                      {(webOrderCanInvoice(o, channel) || webOrderCanLink(o) || webOrderCanDismiss(o) || webOrderCanRestore(o)) && (
                        <div className="events-actions events-web-actions">
                          {webOrderCanInvoice(o, channel) && (
                            <button className="btn btn-primary btn-sm" onClick={() => setResolving(o)}>Create invoice</button>
                          )}
                          {webOrderCanLink(o) && (
                            <button className="btn btn-secondary btn-sm" title="It was already invoiced by hand: link it to that invoice"
                              onClick={() => setLinking(o)}><Link2 size={13} /> Link invoice</button>
                          )}
                          {webOrderCanDismiss(o) && (
                            <button className="btn btn-secondary btn-sm" disabled={busyId === o.id}
                              title="Set aside a test registration; it can be restored" onClick={() => setDismissing(o)}>
                              <XCircle size={13} /> Dismiss
                            </button>
                          )}
                          {webOrderCanRestore(o) && (
                            <button className="btn btn-secondary btn-sm" disabled={busyId === o.id}
                              onClick={() => void setDismissed(o, false, null)}><RotateCcw size={13} /> Restore</button>
                          )}
                        </div>
                      )}
                      {webOrderIsOpen(o) && webOrderTestRefused(o, channel) && (
                        <span className="events-sub events-web-no-invoice"
                          title={`Paid in ${webOrderTestPlace(o.provider)} while this channel does not accept test orders: no money was taken, so no invoice is made`}>
                          <span className="events-nowrap">Test payment —</span>{' '}<span className="events-nowrap">not invoiced</span>
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
      <div className="events-sub" style={{ marginTop: 8 }}>
        A Stripe or HitPay refund is not brought in: refund its invoice by hand.
      </div>
      <div className="events-sub" style={{ marginTop: 4 }}>
        Staff-link registrations (paid in cash, by PayNow or by bank transfer) come here too, marked Staff link. They
        are never invoiced by themselves, even while the channel is Live: check that the money has arrived, then click
        Create invoice. Already invoiced by hand? Use Link invoice. Amount not the pass price (a discount, say)? Raise
        the invoice by hand for the amount paid, then use Link invoice. Dismiss a test registration.
      </div>
      <div className="events-sub" style={{ marginTop: 4 }}>
        The website fills in its workbook's Invoice No column itself, for website and staff-link orders alike, and adds
        the tickets sold on the Invoices page, so nothing needs typing in.
      </div>

      {confirming === 'live' && channel && (
        <Modal title="Switch website orders to Live?" maxWidth={460} onClose={() => setConfirming(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setConfirming(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={() => void setMode('live')}>Switch to Live</button>
          </>}>
          <div className="form-grid">
            <div>
              From the next paid order on, each website order becomes an invoice straight away: raised
              by {channel.acting_name ?? 'the channel\'s person'} at {channel.store_name ?? 'the channel\'s store'},
              paid by {channel.payment_method_name ?? 'the channel\'s payment method'}
              {channel.hitpay_payment_method_name ? <>, or {channel.hitpay_payment_method_name} for HitPay orders</> : null}.
            </div>
            <div className="events-sub">
              An order recorded before now is invoiced if its names come in later and it was paid in the last 7 days;
              otherwise create its invoice here (one paid more than 7 days ago shows why first).
            </div>
            <div className="events-sub">
              Registrations through the staff link are never invoiced by themselves: they wait here for a Manager to
              check the money and create the invoice.
            </div>
            {channel.allow_test && (
              <div className="alert alert-warning" style={{ marginBottom: 0 }}>
                <AlertTriangle size={15} /><div>Test orders are accepted: a Stripe test payment or a HitPay sandbox payment will also become an invoice.</div>
              </div>
            )}
          </div>
        </Modal>
      )}
      {confirming === 'off' && channel && (
        <Modal title="Switch website orders off?" maxWidth={460} onClose={() => setConfirming(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setConfirming(null)}>Cancel</button>
            <button className="btn btn-danger" onClick={() => void setMode('off')}>Switch off</button>
          </>}>
          <div className="form-grid">
            <div>
              While the channel is off, every order paid on the website, and every registration sent through its
              staff link, is refused: it is listed here but its invoice cannot be created here, so it has to be
              invoiced by hand on the Invoices page.
            </div>
            <div className="events-sub">
              A staff-link registration invoiced that way is then linked to its invoice here with Link invoice, so
              the website's workbook lists it once.
            </div>
            <div className="events-sub">Orders already recorded stay, and their invoices can still be created here.</div>
          </div>
        </Modal>
      )}
      {resolving && (
        <ResolveModal order={resolving} onClose={() => setResolving(null)} onResolved={onResolved} />
      )}
      {linking && (
        <LinkModal order={linking} onClose={() => setLinking(null)} onLinked={onResolved} />
      )}
      {dismissing && (
        <ReasonModal title={`Dismiss ${dismissing.buyer_name || 'this registration'}`} label="Why is it dismissed?"
          placeholder="e.g. A test registration" confirmLabel="Dismiss"
          onClose={() => setDismissing(null)}
          onSubmit={reason => { const o = dismissing; setDismissing(null); void setDismissed(o, true, reason); }} />
      )}
    </div>
  );
};

/** The order as both dialogs show it; `dated` says which day a new invoice takes. */
const OrderSummary: React.FC<{ order: WebOrder; dated?: boolean }> = ({ order, dated = false }) => {
  const dating = dated ? ' (the invoice is dated that day)' : '';
  return (
    <div className="events-preview">
      <span><strong>{order.ticket_label}</strong> × {order.quantity} · {money(order.amount_total)}{order.early_bird ? ' · early bird' : ''}</span>
      {order.provider === 'door' ? (
        <>
          <span>
            Staff link {order.stripe_session_id} · paid by {webOrderPaidThrough(order)} on {fmtDate(order.paid_on)}{dating}
            {order.payment_reference ? <> · ref {order.payment_reference}</> : null}
          </span>
          <span>Form sent {fmtDateTime(order.paid_at)}{order.staff_name ? <> · registered by {order.staff_name}</> : null}</span>
        </>
      ) : (
        <span>
          Paid {fmtDateTime(order.paid_at)}
          {order.checkout_opened_at && <> · checkout opened {fmtDateTime(order.checkout_opened_at)}{dating}</>}
        </span>
      )}
      <span>{[order.buyer_name, order.buyer_phone, order.buyer_email].filter(Boolean).join(' · ')}</span>
      {!order.livemode && <span>A {webOrderProviderName(order.provider)} {order.provider === 'hitpay' ? 'sandbox' : 'test'} order: no money was taken.</span>}
    </div>
  );
};

/** How the website's workbook gets an invoice's number. */
const WorkbookNote: React.FC<{ order: WebOrder }> = ({ order }) => (
  <div className="events-sub">
    The website fills this number into its workbook's Invoice No column itself, on the rows with Order
    ID {order.stripe_session_id}, the next time it checks with the inventory.
  </div>
);

/*
 * Creates the invoice for a recorded or parked order: for a customer staff
 * pick, for a new customer made from the buyer, or matched by the buyer's
 * phone exactly as a live order is.
 */
const ResolveModal: React.FC<{
  order: WebOrder;
  onClose: () => void;
  onResolved: (r: WebOrderOutcome) => void;
}> = ({ order, onClose, onResolved }) => {
  // 'auto', 'new', or 'customer:<id>'. With candidates to choose from nothing
  // is picked for the person.
  const [choice, setChoice] = useState(order.candidates.length ? '' : 'auto');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<WebOrderOutcome | null>(null);

  const submit = async () => {
    if (!choice) return;
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('web_order_resolve', {
      p_order_id: order.id,
      p_customer_id: choice.startsWith('customer:') ? choice.slice('customer:'.length) : null,
      p_new_customer: choice === 'new',
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    const r = normalizeWebOrderOutcome(data);
    setOutcome(r);
    onResolved(r);
  };

  const option = (value: string, title: React.ReactNode, ...details: (string | null)[]) => (
    <label key={value} className={`events-inline events-choice${choice === value ? ' checked' : ''}`}>
      <input type="radio" name="web-order-bill-to" value={value} checked={choice === value}
        disabled={busy} onChange={() => setChoice(value)} />
      <span>
        <strong>{title}</strong>
        {details.filter(Boolean).map((d, i) => <span key={i} className="events-sub" style={{ display: 'block' }}>{d}</span>)}
      </span>
    </label>
  );

  return (
    <Modal title={`Create the invoice for ${order.buyer_name || 'this order'}`} maxWidth={560} onClose={onClose}
      footer={outcome ? (
        <button className="btn btn-primary" onClick={onClose}>Close</button>
      ) : <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={() => void submit()} disabled={busy || !choice}>
          {busy ? 'Creating…' : 'Create invoice'}
        </button>
      </>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        <OrderSummary order={order} dated />

        {outcome ? (
          outcome.status === 'invoiced' ? (
            <div className="alert alert-info" role="status" style={{ marginBottom: 0 }}>
              <span>✓</span>
              <div>
                Invoice {outcome.invoice_no ?? ''} is created.
                <WorkbookNote order={order} />
              </div>
            </div>
          ) : (
            <div className={`alert ${outcome.status === 'refused' ? 'alert-danger' : 'alert-warning'}`} role="status" style={{ marginBottom: 0 }}>
              <AlertTriangle size={15} />
              <div>No invoice was created. {webOrderStatusText(outcome)}</div>
            </div>
          )
        ) : (
          <>
            {order.review_reason && (
              <div className="alert alert-warning" style={{ marginBottom: 0 }}>
                <AlertTriangle size={15} /><div>{order.review_reason}</div>
              </div>
            )}
            {order.hand_invoices.length > 0 && (
              // 380: a second invoice for tickets already invoiced by hand.
              <div className="alert alert-warning events-web-hand-note" style={{ marginBottom: 0 }}>
                <AlertTriangle size={15} />
                <div>
                  The buyer's phone is on {handInvoicesText(order)}, made by hand for this event. If that is this
                  order, cancel this and use Link invoice instead, so it is not invoiced twice.
                </div>
              </div>
            )}
            {webOrderAmountDiffers(order) && (
              // 380: Create invoice never makes an invoice for other than what was paid.
              <div className="alert alert-info events-web-amount-note" style={{ marginBottom: 0 }}>
                <span>ⓘ</span>
                <div>
                  An invoice made here is always for the price of the pass, so it will not be made for
                  the {money(order.amount_total)} paid. If that amount is right (a discount, say), raise the invoice by
                  hand on the Invoices page for {money(order.amount_total)}, paid by {webOrderPaidThrough(order)}, then
                  link this registration to it with Link invoice. If the form's amount is wrong, dismiss this
                  registration and register it again.
                </div>
              </div>
            )}
            {order.provider === 'door' && (
              // 380: a staff-link registration's invoice is made paid, so the money is checked first.
              <div className="alert alert-info events-web-door-note" style={{ marginBottom: 0 }}>
                <span>ⓘ</span>
                <div>
                  Create it only once the money has arrived: the invoice is made paid
                  by {webOrderPaidThrough(order)}, with reference {order.payment_reference ?? order.stripe_session_id}.
                  {order.staff_name ? <> {order.staff_name} is its service staff and its guests' Registered by.</> : null}
                </div>
              </div>
            )}
            <div>
              <div className="events-section-title">Who is the invoice for?</div>
              <div className="events-rows" role="radiogroup" aria-label="Bill to">
                {order.candidates.map(c => option(`customer:${c.customer_id}`, c.full_name,
                  [c.phone, c.email].filter(Boolean).join(' · ') || null,
                  c.last_invoice_at ? `Last invoice ${fmtSgDate(c.last_invoice_at)}` : 'No invoices yet'))}
                {option('new', 'Create a new customer', 'Made from the buyer\'s name, phone and email.')}
                {option('auto', 'Match automatically',
                  'By the buyer\'s phone, as a live order is: one customer with it is used, none makes a new one, two or more come back here.')}
              </div>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
};

/*
 * 380: links an open order to the invoice already made for it by hand, so it
 * is not invoiced twice. The invoice is looked up first and shown with what
 * does not match the order; linking changes nothing on the invoice or its
 * guests.
 */
const LinkModal: React.FC<{
  order: WebOrder;
  onClose: () => void;
  onLinked: (r: WebOrderOutcome) => void;
}> = ({ order, onClose, onLinked }) => {
  const [invoiceNo, setInvoiceNo] = useState('');
  const [preview, setPreview] = useState<WebOrderLinkPreview | null>(null);
  const [busy, setBusy] = useState<'check' | 'link' | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<WebOrderOutcome | null>(null);

  const check = async () => {
    const no = invoiceNo.trim();
    if (!no) return;
    setBusy('check'); setErr(null); setPreview(null);
    const { data, error } = await supabase.rpc('web_order_link_preview', { p_order_id: order.id, p_invoice_no: no });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    const p = normalizeWebOrderLinkPreview(data);
    setPreview({ ...p, invoice_no: p.invoice_no || no });
  };

  const link = async () => {
    if (!preview) return;
    setBusy('link'); setErr(null);
    const { data, error } = await supabase.rpc('web_order_link_invoice', { p_order_id: order.id, p_invoice_no: preview.invoice_no });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    const r = normalizeWebOrderOutcome(data);
    setOutcome(r);
    onLinked(r);
  };

  return (
    <Modal title={`Link ${order.buyer_name || 'this order'} to an existing invoice`} maxWidth={560} onClose={onClose}
      footer={outcome ? (
        <button className="btn btn-primary" onClick={onClose}>Close</button>
      ) : <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={() => void link()} disabled={!preview || busy !== null}>
          {busy === 'link' ? 'Linking…' : 'Link invoice'}
        </button>
      </>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        <OrderSummary order={order} />

        {outcome ? (
          outcome.status === 'invoiced' ? (
            <div className="alert alert-info" role="status" style={{ marginBottom: 0 }}>
              <span>✓</span>
              <div>
                The order is linked to invoice {outcome.invoice_no ?? preview?.invoice_no ?? ''}.
                <WorkbookNote order={order} />
              </div>
            </div>
          ) : (
            <div className="alert alert-warning" role="status" style={{ marginBottom: 0 }}>
              <AlertTriangle size={15} />
              <div>The order was not linked. {webOrderStatusText(outcome)}</div>
            </div>
          )
        ) : (
          <>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label htmlFor="web-order-link-no">Invoice no *</label>
              <div style={{ display: 'flex', gap: 8 }}>
                <input id="web-order-link-no" value={invoiceNo} placeholder="e.g. INV-2026-0001" autoFocus
                  disabled={busy !== null}
                  onChange={e => { setInvoiceNo(e.target.value); setPreview(null); setErr(null); }}
                  onKeyDown={e => { if (e.key === 'Enter') void check(); }} />
                <button className="btn btn-secondary" onClick={() => void check()} disabled={!invoiceNo.trim() || busy !== null}>
                  {busy === 'check' ? 'Looking…' : 'Look up'}
                </button>
              </div>
              <div className="events-sub" style={{ marginTop: 4 }}>
                The invoice already made by hand for this order. It is not changed: the order is marked invoiced with it.
              </div>
            </div>
            {preview && (
              <>
                <div className="events-preview events-web-link-preview" aria-label="Invoice to link">
                  <span>
                    <strong>{preview.invoice_no}</strong>
                    {preview.store ? ` · ${preview.store}` : ''}{preview.date ? ` · ${fmtDate(preview.date)}` : ''}
                  </span>
                  <span>{preview.customer_name ?? 'No customer'}</span>
                  <span>Total {money(preview.total)} · paid {money(preview.paid)}{preview.methods ? ` by ${preview.methods}` : ''}</span>
                  <span>{preview.people} {preview.people === 1 ? 'person' : 'people'} on its tickets for this event</span>
                </div>
                {preview.warnings.length > 0 && (
                  <div className="alert alert-warning events-web-link-warnings" role="status" style={{ marginBottom: 0 }}>
                    <AlertTriangle size={15} />
                    <div>{preview.warnings.map((w, i) => <div key={i}>{w}</div>)}</div>
                  </div>
                )}
              </>
            )}
          </>
        )}
      </div>
    </Modal>
  );
};

export default WebOrdersTab;
