import React, { useMemo, useState } from 'react';
import { Pencil, RotateCcw, Search, UserPlus, UserX, Users } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { ReasonModal } from '../ui';
import { ExcelColumn, ExcelExportButton } from '../ExcelExport';
import { GuestModal, GuestSaved } from './GuestModal';
import {
  DayLoad, EventRow, Guest, StaffOption, fmtDayMonth, fmtTime, fmtWeekday, guestDay,
  invoiceStatusLabel, paymentLabel, paymentTone, slug,
} from './model';

type TypeFilter = 'all' | 'ticket' | 'free';
type StatusFilter = 'registered' | 'cancelled' | 'all';

/** The guest list export: the guest, then coming / attended / code for each day. */
export function guestExportColumns(event: EventRow): ExcelColumn<Guest>[] {
  return [
    { header: 'Name', value: g => g.name },
    { header: 'Phone', value: g => g.phone ?? '' },
    { header: 'Customer', value: g => g.customer_name ?? '' },
    { header: 'Type', value: g => (g.source === 'ticket' ? 'Ticket' : 'Free') },
    { header: 'Ticket option', value: g => g.ticket_option_name ?? '' },
    { header: 'Invoice no', value: g => g.invoice_no ?? '' },
    { header: 'Invoice status', value: g => invoiceStatusLabel(g.invoice_status) },
    { header: 'Paid', value: g => (g.source === 'ticket' && g.invoice_paid != null ? g.invoice_paid : null) },
    { header: 'Registered by', value: g => g.registered_by_name ?? '' },
    { header: 'Notes', value: g => g.notes ?? '' },
    { header: 'Status', value: g => (g.status === 'registered' ? 'Registered' : 'Cancelled') },
    ...event.days.flatMap(d => {
      const label = fmtDayMonth(d.day);
      return [
        { header: `${label} coming`, value: (g: Guest) => (guestDay(g, d.day) ? 'Y' : 'N') },
        { header: `${label} attended`, value: (g: Guest) => fmtTime(guestDay(g, d.day)?.attended_at) },
        { header: `${label} code`, value: (g: Guest) => guestDay(g, d.day)?.check_in_code ?? '' },
      ] as ExcelColumn<Guest>[];
    }),
  ];
}

export const GuestsTab: React.FC<{
  event: EventRow;
  guests: Guest[];
  loading: boolean;
  loads: DayLoad[];
  staff: StaffOption[];
  currentUserId: string | null;
  currentUserName: string | null;
  onSaved: (r: GuestSaved) => void;
  onReload: () => Promise<void> | void;
}> = ({ event, guests, loading, loads, staff, currentUserId, currentUserName, onSaved, onReload }) => {
  const [search, setSearch] = useState('');
  const [day, setDay] = useState('');
  const [type, setType] = useState<TypeFilter>('all');
  const [status, setStatus] = useState<StatusFilter>('registered');
  const [editing, setEditing] = useState<{ guest: Guest | null } | null>(null);
  const [cancelling, setCancelling] = useState<Guest | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    // Digits are matched against phones only when the search looks like a
    // phone number, so "INV-2026-0002" does not find a phone ending 0002.
    const qDigits = /^[\d\s+()-]+$/.test(q) ? q.replace(/\D/g, '') : '';
    return guests.filter(g => {
      if (status !== 'all' && g.status !== status) return false;
      if (type !== 'all' && g.source !== type) return false;
      if (day && !guestDay(g, day)) return false;
      if (!q) return true;
      return g.name.toLowerCase().includes(q)
        || (g.customer_name ?? '').toLowerCase().includes(q)
        || (g.invoice_no ?? '').toLowerCase().includes(q)
        || (g.phone ?? '').toLowerCase().includes(q)
        || (qDigits.length >= 3 && (g.phone ?? '').replace(/\D/g, '').includes(qDigits));
    });
  }, [guests, search, day, type, status]);

  const registered = guests.filter(g => g.status === 'registered');
  const counts = {
    registered: registered.length,
    ticket: registered.filter(g => g.source === 'ticket').length,
    free: registered.filter(g => g.source === 'free').length,
    cancelled: guests.length - registered.length,
  };

  const setCancelled = async (g: Guest, cancelled: boolean, reason: string | null) => {
    setErr(null); setBusyId(g.guest_id);
    const { error } = await supabase.rpc('event_set_guest_cancelled', {
      p_guest_id: g.guest_id, p_cancelled: cancelled, p_reason: reason,
    });
    setBusyId(null);
    if (error) { setErr(error.message); return; }
    await onReload();
  };

  return (
    <div>
      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}

      <div className="events-toolbar">
        <div className="events-search">
          <Search size={15} className="events-search-icon" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name, phone or invoice no…"
            aria-label="Search guests" />
        </div>
        <select value={day} onChange={e => setDay(e.target.value)} aria-label="Day">
          <option value="">Every day</option>
          {event.days.map(d => <option key={d.day} value={d.day}>{fmtWeekday(d.day)}</option>)}
        </select>
        <select value={type} onChange={e => setType(e.target.value as TypeFilter)} aria-label="Type">
          <option value="all">Ticket and free</option>
          <option value="ticket">Ticket</option>
          <option value="free">Free</option>
        </select>
        <select value={status} onChange={e => setStatus(e.target.value as StatusFilter)} aria-label="Status">
          <option value="registered">Registered</option>
          <option value="cancelled">Cancelled</option>
          <option value="all">Registered and cancelled</option>
        </select>
        <div style={{ display: 'flex', gap: 8, marginLeft: 'auto', flexWrap: 'wrap' }}>
          <ExcelExportButton rows={filtered} columns={guestExportColumns(event)}
            filename={`event-guests-${slug(event.name)}`} sheetName="Guests" />
          {event.can_run && (
            <button className="btn btn-primary" onClick={() => setEditing({ guest: null })}>
              <UserPlus size={15} /> Add guest
            </button>
          )}
        </div>
      </div>

      {!(loading && guests.length === 0) && (
        <div className="events-count-line">
          Showing {filtered.length} of {guests.length} · {counts.registered} registered
          ({counts.ticket} ticket, {counts.free} free){counts.cancelled ? ` · ${counts.cancelled} cancelled` : ''}
        </div>
      )}

      <div className="card">
        <div className="table-wrap">
          {loading && guests.length === 0 ? (
            <div className="empty-state"><p>Loading the guest list…</p></div>
          ) : filtered.length === 0 ? (
            <div className="empty-state">
              <Users size={32} style={{ opacity: 0.3, marginBottom: 8 }} />
              <p style={{ fontWeight: 600 }}>{guests.length === 0 ? 'No guests yet' : 'No guest matches'}</p>
              <p style={{ fontSize: 13 }}>
                {guests.length === 0
                  ? 'Tickets sold on invoices appear here by themselves; free guests are added with Add guest.'
                  : 'Change the search or the filters.'}
              </p>
            </div>
          ) : (
            <table className="events-table">
              <thead>
                <tr>
                  <th>Name</th><th>Phone</th><th>Days</th><th>Ticket</th><th>Registered by</th><th>Notes</th><th></th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(g => (
                  <tr key={g.guest_id} className={g.status === 'cancelled' ? 'events-row-cancelled' : undefined}>
                    <td>
                      <strong>{g.name}</strong>
                      {g.customer_id && <div className="events-sub">Customer: {g.customer_name ?? 'linked'}</div>}
                      {g.status === 'cancelled' && (
                        <div><span className="badge badge-muted">Cancelled</span>
                          {g.cancelled_reason && <span className="events-sub"> {g.cancelled_reason}</span>}</div>
                      )}
                    </td>
                    <td className="events-nowrap">{g.phone ?? <span className="events-muted">—</span>}</td>
                    <td>
                      <div className="events-chips">
                        {g.days.map(d => (
                          <span key={d.day} className={`events-chip${d.attended_at ? ' events-chip-done' : ''}`}
                            title={d.attended_at ? `Checked in ${fmtTime(d.attended_at)}${d.checked_in_by_name ? ` by ${d.checked_in_by_name}` : ''}` : 'Not checked in'}>
                            {fmtWeekday(d.day)}{d.attended_at ? ' ✓' : ''}{d.check_in_code ? ` · ${d.check_in_code}` : ''}
                          </span>
                        ))}
                      </div>
                    </td>
                    <td>
                      {g.source === 'ticket' ? (
                        <span>
                          {g.ticket_option_name ?? 'Ticket'}
                          {g.invoice_no ? <>{' · '}<span className="events-nowrap">{g.invoice_no}</span></> : ''}
                          {' · '}<span className={`events-pay-${paymentTone(g.invoice_status)}`}>{paymentLabel(g.invoice_status)}</span>
                        </span>
                      ) : <span className="badge badge-primary">Free</span>}
                    </td>
                    <td>{g.registered_by_name ?? <span className="events-muted">—</span>}</td>
                    <td style={{ maxWidth: 220, overflowWrap: 'anywhere' }}>{g.notes ?? ''}</td>
                    <td>
                      {event.can_run && (
                        <div className="events-actions">
                          <button className="btn btn-secondary btn-sm btn-icon" title="Edit guest" aria-label={`Edit ${g.name}`}
                            onClick={() => setEditing({ guest: g })}><Pencil size={13} /></button>
                          {g.source === 'free' && g.status === 'registered' && (
                            <button className="btn btn-secondary btn-sm" disabled={busyId === g.guest_id}
                              onClick={() => setCancelling(g)}><UserX size={13} /> Cancel</button>
                          )}
                          {g.source === 'free' && g.status === 'cancelled' && (
                            <button className="btn btn-secondary btn-sm" disabled={busyId === g.guest_id}
                              onClick={() => void setCancelled(g, false, null)}><RotateCcw size={13} /> Restore</button>
                          )}
                        </div>
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
        Ticket guests come from their invoice: cancelling or correcting the invoice changes them.
      </div>

      {editing && (
        <GuestModal event={event} guest={editing.guest} loads={loads} staff={staff}
          currentUserId={currentUserId} currentUserName={currentUserName}
          onClose={() => setEditing(null)}
          onSaved={r => { setEditing(null); onSaved(r); }} />
      )}
      {cancelling && (
        <ReasonModal title={`Cancel ${cancelling.name}`} label="Reason (optional)" required={false}
          placeholder="e.g. Cannot come after all" confirmLabel="Cancel guest"
          onClose={() => setCancelling(null)}
          onSubmit={reason => { const g = cancelling; setCancelling(null); void setCancelled(g, true, reason || null); }} />
      )}
    </div>
  );
};

export default GuestsTab;
