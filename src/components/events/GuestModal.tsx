import React, { useMemo, useState } from 'react';
import { AlertTriangle } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { CustomerSearchSelect } from '../SearchSelect';
import {
  DayLoad, EventRow, Guest, OverCapacity, StaffOption, fmtTime, fmtWeekday,
  loadText, normalizeOverCapacity, paymentLabel,
} from './model';

/*
 * Adds a free guest, or changes any guest. A ticket guest's days come from
 * their invoice, so for them the days are shown and not sent: the server
 * refuses a ticket guest's days that differ from the invoice's.
 */

export interface GuestSaved { guest_id: string; over_capacity: OverCapacity[]; name: string; }

export const GuestModal: React.FC<{
  event: EventRow;
  guest: Guest | null;
  loads: DayLoad[];
  staff: StaffOption[];
  currentUserId: string | null;
  currentUserName?: string | null;
  onClose: () => void;
  onSaved: (r: GuestSaved) => void;
}> = ({ event, guest, loads, staff, currentUserId, currentUserName, onClose, onSaved }) => {
  const isTicket = guest?.source === 'ticket';
  const [name, setName] = useState(guest?.name ?? '');
  const [phone, setPhone] = useState(guest?.phone ?? '');
  const [customerId, setCustomerId] = useState(guest?.customer_id ?? '');
  const [days, setDays] = useState<string[]>(() => guest ? guest.days.map(d => d.day)
    : event.days.length === 1 ? [event.days[0].day] : []);
  const [registeredBy, setRegisteredBy] = useState(guest ? (guest.registered_by ?? '') : (currentUserId ?? ''));
  const [notes, setNotes] = useState(guest?.notes ?? '');
  const [err, setErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  // Whoever registered the guest stays choosable even if they have left, and
  // the person adding one is always there to be picked.
  const staffChoices = useMemo(() => {
    const list = [...staff];
    if (guest?.registered_by && !list.some(s => s.id === guest.registered_by)) {
      list.push({ id: guest.registered_by, full_name: guest.registered_by_name ?? 'Former staff member', role: '' });
    }
    if (!guest && currentUserId && !list.some(s => s.id === currentUserId)) {
      list.push({ id: currentUserId, full_name: currentUserName ?? 'Me', role: '' });
    }
    return list;
  }, [staff, guest, currentUserId, currentUserName]);

  const attendedDays = new Set((guest?.days ?? []).filter(d => d.attended_at).map(d => d.day));
  const alreadyOn = new Set((guest?.status === 'registered' ? guest.days : []).map(d => d.day));

  const pickCustomer = async (id: string) => {
    setCustomerId(id);
    if (!id || (name.trim() && phone.trim())) return;
    // Fill in what is blank from the customer's record; nothing typed is replaced.
    const { data } = await supabase.from('customers').select('id, full_name, phone').eq('id', id).maybeSingle();
    const c = data as { full_name?: string | null; phone?: string | null } | null;
    if (!c) return;
    setName(n => (n.trim() ? n : c.full_name ?? ''));
    setPhone(p => (p.trim() ? p : c.phone ?? ''));
  };

  const save = async () => {
    setErr(null);
    if (!name.trim()) { setErr('Give the guest\'s name.'); return; }
    if (!isTicket && days.length === 0) { setErr('Choose the day(s) the guest is coming.'); return; }
    const payload: Record<string, unknown> = {
      ...(guest ? { id: guest.guest_id } : {}),
      event_id: event.id,
      name: name.trim(),
      phone: phone.trim() || null,
      customer_id: customerId || null,
      ...(isTicket ? {} : { days: [...days].sort() }),
      registered_by: registeredBy || null,
      notes: notes.trim() || null,
    };
    setSaving(true);
    const { data, error } = await supabase.rpc('event_save_guest', { p_guest: payload });
    setSaving(false);
    if (error) { setErr(error.message); return; }
    const res = (data ?? {}) as { guest_id?: string; over_capacity?: unknown };
    onSaved({
      guest_id: String(res.guest_id ?? guest?.guest_id ?? ''),
      over_capacity: normalizeOverCapacity(res.over_capacity),
      name: name.trim(),
    });
  };

  return (
    <Modal title={guest ? `Edit ${guest.name}` : 'Add guest'} maxWidth={560} confirmClose onClose={onClose}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : guest ? 'Save guest' : 'Add guest'}
        </button>
      </>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        {!guest && (
          <div className="events-sub">
            A free guest, added here. People who bought a ticket are on the list already, from their invoice.
          </div>
        )}
        <div className="form-group">
          <label>Name *</label>
          <input value={name} onChange={e => setName(e.target.value)} autoFocus />
        </div>
        <div className="form-group">
          <label>Phone</label>
          <input type="tel" value={phone} onChange={e => setPhone(e.target.value)} placeholder="+65 …" />
        </div>
        <div className="form-group">
          <label>Customer (optional)</label>
          <div style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <CustomerSearchSelect value={customerId} onChange={id => { void pickCustomer(id); }}
                placeholder="Link an existing customer…" />
            </div>
            {customerId && (
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setCustomerId('')}>Unlink</button>
            )}
          </div>
        </div>

        <div className="form-group">
          <label>{isTicket ? 'Days' : 'Days coming *'}</label>
          {isTicket ? (
            <>
              <div className="events-chips">
                {(guest?.days ?? []).map(d => (
                  <span key={d.day} className={`events-chip${d.attended_at ? ' events-chip-done' : ''}`}>
                    {fmtWeekday(d.day)}{d.attended_at ? ` ✓ ${fmtTime(d.attended_at)}` : ''}
                  </span>
                ))}
              </div>
              <div className="events-sub" style={{ marginTop: 4 }}>
                Days come from the invoice{guest?.invoice_no ? ` (${guest.invoice_no}, ${guest.ticket_option_name ?? 'ticket'}, ${paymentLabel(guest.invoice_status)})` : ''}.
                Correct the invoice to change them.
              </div>
            </>
          ) : (
            <div className="events-rows">
              {loads.map(l => {
                const checked = days.includes(l.day);
                // The people on the day without this guest, so "full" means
                // adding them goes over.
                const others = l.registered - (alreadyOn.has(l.day) ? 1 : 0);
                const full = l.capacity != null && others >= l.capacity;
                const locked = attendedDays.has(l.day) && checked;
                return (
                  <label key={l.day} className={`events-inline events-day-pick${checked ? ' checked' : ''}`}>
                    <span style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                      <input type="checkbox" checked={checked} disabled={locked}
                        aria-label={fmtWeekday(l.day)}
                        onChange={e => setDays(ds => e.target.checked ? [...ds, l.day] : ds.filter(x => x !== l.day))} />
                      <strong>{fmtWeekday(l.day)}</strong>
                      {locked && <span className="events-sub">checked in, so this day stays</span>}
                    </span>
                    <span style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                      <span className="events-sub">{loadText(l)}</span>
                      {full && <span className={`events-chip ${others > (l.capacity ?? 0) ? 'events-chip-over' : 'events-chip-full'}`}>Full</span>}
                    </span>
                  </label>
                );
              })}
              {loads.some(l => days.includes(l.day) && !alreadyOn.has(l.day) && l.capacity != null && l.registered >= l.capacity) && (
                <div className="alert alert-warning" style={{ marginBottom: 0 }}>
                  <AlertTriangle size={15} />
                  <div>A chosen day is full. The guest can still be added; the day will be over capacity.</div>
                </div>
              )}
            </div>
          )}
        </div>

        <div className="form-group">
          <label>Registered by</label>
          <select value={registeredBy} onChange={e => setRegisteredBy(e.target.value)}>
            <option value="">— Not recorded —</option>
            {staffChoices.map(s => <option key={s.id} value={s.id}>{s.full_name}</option>)}
          </select>
        </div>
        <div className="form-group">
          <label>Notes</label>
          <textarea rows={2} value={notes} onChange={e => setNotes(e.target.value)} placeholder="e.g. VEG, Free Sock" />
        </div>
      </div>
    </Modal>
  );
};

export default GuestModal;
