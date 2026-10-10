import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Receipt, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { ExcelColumn, ExcelExportButton } from '../ExcelExport';
import {
  EventInvoice, EventRow, NOT_COUNTED_STATUSES, SALE_SOURCE_LABELS, fmtDate, invoiceStatusLabel,
  money, normalizeInvoice, slug,
} from './model';

/*
 * The event's sales: invoices dated on an event day at an event store,
 * invoices holding one of its tickets, and invoices staff marked by hand.
 * The server returns only those at stores the person can see.
 *
 * 415 (EVENTS-4, the Owner 9 Oct 2026): an invoice holding a ticket counts
 * under the event the ticket is for, even when it is dated on another
 * event's day at its store. An invoice counts under one event, whole: its
 * other lines go with its ticket. One holding tickets for two events counts
 * under the one running that day there. Staff marking an invoice by hand
 * still decides.
 */

const STATUS_BADGE: Record<string, string> = {
  paid: 'badge badge-success', partially_paid: 'badge badge-accent', unpaid: 'badge badge-danger',
  completed_foc: 'badge badge-primary', cancelled: 'badge badge-muted', refunded: 'badge badge-muted',
};

const COLUMNS: ExcelColumn<EventInvoice>[] = [
  { header: 'Invoice no', value: r => r.invoice_no },
  { header: 'Date', value: r => r.business_date ?? '' },
  { header: 'Store', value: r => r.store_name ?? '' },
  { header: 'Customer', value: r => r.customer_name ?? '' },
  { header: 'Status', value: r => invoiceStatusLabel(r.status) },
  { header: 'Total', value: r => r.total_amount },
  { header: 'Paid', value: r => r.paid_amount },
  { header: 'Why', value: r => SALE_SOURCE_LABELS[r.source] },
  { header: 'Ticket people', value: r => r.ticket_people },
  { header: 'Ticket S$', value: r => r.ticket_total },
];

export const SalesTab: React.FC<{ event: EventRow }> = ({ event }) => {
  const [rows, setRows] = useState<EventInvoice[]>([]);
  const [loading, setLoading] = useState(true);
  const [loaded, setLoaded] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('event_invoices', { p_event_id: event.id });
    setLoading(false);
    if (error) { setErr(error.message); return; }
    setErr(null);
    setRows((Array.isArray(data) ? data : []).map(normalizeInvoice));
    setLoaded(true);
  }, [event.id]);
  useEffect(() => { void load(); }, [load]);

  const counted = useMemo(() => rows.filter(r => !NOT_COUNTED_STATUSES.includes(r.status)), [rows]);
  const totals = useMemo(() => counted.reduce((t, r) => ({
    total: t.total + r.total_amount, paid: t.paid + r.paid_amount,
    people: t.people + r.ticket_people, tickets: t.tickets + r.ticket_total,
  }), { total: 0, paid: 0, people: 0, tickets: 0 }), [counted]);
  const leftOut = rows.length - counted.length;

  return (
    <div>
      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
      <div className="events-toolbar">
        <div className="events-count-line" style={{ marginBottom: 0 }}>
          {loaded ? `${rows.length} invoice${rows.length === 1 ? '' : 's'}` : ''}
        </div>
        <div style={{ display: 'flex', gap: 8, marginLeft: 'auto' }}>
          <button className="btn btn-secondary" onClick={() => void load()}>
            <RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh
          </button>
          <ExcelExportButton rows={err ? [] : rows} columns={COLUMNS} filename={`event-sales-${slug(event.name)}`}
            sheetName="Event sales" dateOf={r => r.business_date} dateLabel="Invoice date" disabled={!!err} />
        </div>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading && !loaded ? (
            <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          ) : err && !loaded ? (
            <div className="empty-state"><p>The sales could not be loaded.</p></div>
          ) : rows.length === 0 ? (
            <div className="empty-state">
              <Receipt size={32} style={{ opacity: 0.3, marginBottom: 8 }} />
              <p style={{ fontWeight: 600 }}>No sales yet</p>
              <p style={{ fontSize: 13 }}>
                Invoices dated on an event day at {event.stores.map(s => s.name).join(', ') || 'an event store'}, invoices
                with a ticket, and invoices staff mark for this event appear here.
              </p>
            </div>
          ) : (
            <table className="events-table">
              <thead>
                <tr>
                  <th>Invoice no</th><th>Date</th><th>Store</th><th>Customer</th><th>Status</th>
                  <th className="events-num">Total</th><th className="events-num">Paid</th><th>Why</th>
                  <th className="events-num">Ticket people</th><th className="events-num">Ticket S$</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(r => (
                  <tr key={r.invoice_id} className={NOT_COUNTED_STATUSES.includes(r.status) ? 'events-row-cancelled' : undefined}>
                    <td className="events-nowrap"><strong>{r.invoice_no}</strong></td>
                    <td className="events-nowrap">{fmtDate(r.business_date)}</td>
                    <td>{r.store_name ?? '—'}</td>
                    <td>{r.customer_name ?? '—'}</td>
                    <td><span className={STATUS_BADGE[r.status] ?? 'badge badge-muted'}>{invoiceStatusLabel(r.status)}</span></td>
                    <td className="events-num">{money(r.total_amount)}</td>
                    <td className="events-num">{money(r.paid_amount)}</td>
                    <td>{SALE_SOURCE_LABELS[r.source]}</td>
                    <td className="events-num">{r.ticket_people || ''}</td>
                    <td className="events-num">{r.ticket_people ? money(r.ticket_total) : ''}</td>
                  </tr>
                ))}
                <tr className="events-total-row">
                  <td colSpan={5}>Total ({counted.length} invoice{counted.length === 1 ? '' : 's'})</td>
                  <td className="events-num">{money(totals.total)}</td>
                  <td className="events-num">{money(totals.paid)}</td>
                  <td></td>
                  <td className="events-num">{totals.people}</td>
                  <td className="events-num">{money(totals.tickets)}</td>
                </tr>
              </tbody>
            </table>
          )}
        </div>
      </div>
      <div className="events-sub" style={{ marginTop: 8 }}>
        Totals leave out cancelled and refunded invoices{leftOut ? ` (${leftOut} here, shown faded)` : ''}.
        Only invoices at stores you can see are listed. A ticket counts under the event it is for, even when sold on
        another event's day, and the rest of its invoice goes with it. An invoice with tickets for two events counts
        under the one running that day.
      </div>
    </div>
  );
};

export default SalesTab;
