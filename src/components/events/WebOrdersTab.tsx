import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CreditCard, Globe, RefreshCw, Store, UserRound } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { ExcelColumn, ExcelExportButton } from '../ExcelExport';
import {
  EventRow, WEB_ORDER_MODE_BADGE, WEB_ORDER_MODE_LABELS, WEB_ORDER_STATUS_BADGE, WEB_ORDER_STATUS_LABELS,
  WebOrder, WebOrderList, WebOrderMode, WebOrderOutcome, fmtDateTime, fmtSgDate, fmtTime, money,
  normalizeWebOrderList, normalizeWebOrderOutcome, sgStamp, slug, webOrderCanInvoice, webOrderIsOpen, webOrderStatusText,
  webOrderTestRefused,
} from './model';

/*
 * Tickets bought on the event's website. Each paid order is recorded here;
 * while the channel is Live it becomes an invoice at once, raised by the
 * channel's person at its store and paid by its payment method. An order
 * that could not be matched to one customer waits as Needs review, and every
 * order waits as Recorded while the channel only records: Create invoice
 * finishes either, except for a Stripe test payment while the channel does
 * not accept test orders. Owners, Admins and Managers see this tab and only
 * the Owner switches the channel; the server enforces all three. An invoice
 * created here is not sent back to the website, so its workbook is filled in
 * by hand or from this tab's export.
 */

const MODES: WebOrderMode[] = ['off', 'record_only', 'live'];
const MODE_BUTTONS: Record<WebOrderMode, string> = { off: 'Off', record_only: 'Record only', live: 'Live' };

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
  // Side by side, as the website's workbook needs them: its Order ID is the
  // Stripe checkout, and an invoice created on this tab never reaches it.
  { header: 'Invoice no', value: o => o.invoice_no ?? '' },
  { header: 'Order ID (Stripe checkout)', value: o => o.stripe_session_id },
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
  const [applying, setApplying] = useState<string | null>(null);

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
  const counts = useMemo(() => ({
    invoiced: orders.filter(o => o.status === 'invoiced').length,
    recorded: orders.filter(o => o.status === 'recorded').length,
    review: orders.filter(o => o.status === 'needs_review').length,
    refused: orders.filter(o => o.status === 'refused').length,
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
          <div className="events-line"><CreditCard size={14} /><span>Payment method: {channel.payment_method_name ?? '—'}</span></div>
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
            `${orders.length} order${orders.length === 1 ? '' : 's'}`,
            counts.invoiced && `${counts.invoiced} invoiced`,
            counts.recorded && `${counts.recorded} recorded`,
            counts.review && `${counts.review} need${counts.review === 1 ? 's' : ''} review`,
            counts.refused && `${counts.refused} refused`,
            counts.test && `${counts.test} test`,
          ].filter(Boolean).join(' · ') : ''}
        </div>
        <div style={{ display: 'flex', gap: 8, marginLeft: 'auto' }}>
          <button className="btn btn-secondary" onClick={() => void load()}>
            <RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh
          </button>
          <ExcelExportButton rows={orders} columns={WEB_ORDER_COLUMNS} filename={`website-orders-${slug(event.name)}`}
            sheetName="Website orders" dateOf={o => o.paid_at} dateLabel="Paid" dateTimeZone="Asia/Singapore" disabled={!list} />
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
              <p style={{ fontSize: 13 }}>Tickets paid for on the event's website appear here.</p>
            </div>
          ) : (
            <table className="events-table">
              <thead>
                <tr>
                  <th>Paid at (SGT)</th><th>Buyer</th><th>Pass</th><th>People</th>
                  <th className="events-num">Total S$</th><th>Early bird</th><th>Status</th><th></th>
                </tr>
              </thead>
              <tbody>
                {orders.map(o => (
                  <tr key={o.id} data-order={o.id}>
                    <td>
                      {o.paid_at
                        ? <><span className="events-nowrap">{fmtSgDate(o.paid_at)},</span> <span className="events-nowrap">{fmtTime(o.paid_at)}</span></>
                        : <span className="events-muted">—</span>}
                    </td>
                    <td className="events-web-wide">
                      <strong>{o.buyer_name || '—'}</strong>
                      {!o.livemode && (
                        <> <span className="badge badge-accent" title="Paid in Stripe's test mode: no money was taken">Test</span></>
                      )}
                      {o.buyer_phone && <div className="events-sub">{o.buyer_phone}</div>}
                      {o.buyer_email && <div className="events-sub">{o.buyer_email}</div>}
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
                    </td>
                    <td>
                      {webOrderCanInvoice(o, channel) ? (
                        <div className="events-actions">
                          <button className="btn btn-primary btn-sm" onClick={() => setResolving(o)}>Create invoice</button>
                        </div>
                      ) : webOrderIsOpen(o) && webOrderTestRefused(o, channel) && (
                        <span className="events-sub events-web-no-invoice"
                          title="Paid in Stripe's test mode while this channel does not accept test orders: no money was taken, so no invoice is made">
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
        A Stripe refund is not brought in: refund its invoice by hand. Door sales paid in cash or PayNow are
        invoiced on the Invoices page, as any sale is.
      </div>
      <div className="events-sub" style={{ marginTop: 4 }}>
        The number of an invoice created here does not reach the website's workbook by itself: type it into the
        workbook's Invoice No column, on every row whose Order ID is the order's Stripe checkout (cs_…; one row per
        person), or use this tab's Excel export, which lists both.
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
              paid by {channel.payment_method_name ?? 'the channel\'s payment method'}.
            </div>
            <div className="events-sub">
              An order recorded before now is invoiced if its names come in later and it was paid in the last 7 days;
              otherwise create its invoice here (one paid more than 7 days ago shows why first).
            </div>
            {channel.allow_test && (
              <div className="alert alert-warning" style={{ marginBottom: 0 }}>
                <AlertTriangle size={15} /><div>Test orders are accepted: a Stripe test payment will also become an invoice.</div>
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
              While the channel is off, every order paid on the website is refused. It is listed here but its
              invoice cannot be created here: it has to be invoiced by hand on the Invoices page.
            </div>
            <div className="events-sub">Orders already recorded stay, and their invoices can still be created here.</div>
          </div>
        </Modal>
      )}
      {resolving && (
        <ResolveModal order={resolving} onClose={() => setResolving(null)} onResolved={onResolved} />
      )}
    </div>
  );
};

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
        <div className="events-preview">
          <span><strong>{order.ticket_label}</strong> × {order.quantity} · {money(order.amount_total)}{order.early_bird ? ' · early bird' : ''}</span>
          <span>
            Paid {fmtDateTime(order.paid_at)}
            {order.checkout_opened_at && <> · checkout opened {fmtDateTime(order.checkout_opened_at)} (the invoice is dated that day)</>}
          </span>
          <span>{[order.buyer_name, order.buyer_phone, order.buyer_email].filter(Boolean).join(' · ')}</span>
          {!order.livemode && <span>A Stripe test order: no money was taken.</span>}
        </div>

        {outcome ? (
          outcome.status === 'invoiced' ? (
            <div className="alert alert-info" role="status" style={{ marginBottom: 0 }}>
              <span>✓</span>
              <div>
                Invoice {outcome.invoice_no ?? ''} is created.
                <div className="events-sub">
                  The website's workbook does not get this number: type it into its Invoice No column, on every row
                  with Order ID {order.stripe_session_id}.
                </div>
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

export default WebOrdersTab;
