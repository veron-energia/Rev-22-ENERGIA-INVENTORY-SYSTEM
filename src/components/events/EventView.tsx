import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowLeft, CalendarDays, ClipboardCheck, Clock, Globe, Pencil, Receipt, RefreshCw, Store, Ticket, Trash2, Users,
} from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../context/AuthContext';
import { isManagerOrAbove } from '../../types';
import { ReasonModal } from '../ui';
import { GuestsTab } from './GuestsTab';
import { CheckInPanel } from './CheckInPanel';
import { SalesTab } from './SalesTab';
import { WebOrdersTab } from './WebOrdersTab';
import { GuestSaved } from './GuestModal';
import {
  EventRow, Guest, STATUS_BADGE, StaffOption, dayLoads, eventStatus, fmtDate, fmtDayList, fmtDayMonth,
  fmtHours, fmtWeekday, loadText, loadTone, money, normalizeGuest, overCapacityText,
} from './model';

type Tab = 'guests' | 'checkin' | 'sales' | 'web';

/**
 * 415: while Check-in is open and the page is in sight, the guest list is read
 * again this often, so a second door device sees who the first checked in.
 */
export const CHECK_IN_REFRESH_MS = 25_000;

export const EventView: React.FC<{
  event: EventRow;
  today: string;
  canManage: boolean;
  staff: StaffOption[];
  currentUserId: string | null;
  currentUserName: string | null;
  onBack: () => void;
  onEdit: () => void;
  onDeleted: () => void;
  onChanged: () => void;
}> = ({ event, today, canManage, staff, currentUserId, currentUserName, onBack, onEdit, onDeleted, onChanged }) => {
  const { profile } = useAuth();
  // Website orders carry buyers' contacts and make invoices: Owners, Admins
  // and Managers only, as the server allows.
  const seesWebOrders = isManagerOrAbove(profile?.role);
  const [tab, setTab] = useState<Tab>('guests');
  const [guests, setGuests] = useState<Guest[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ tone: 'warning' | 'info'; text: string } | null>(null);
  const [deleting, setDeleting] = useState(false);

  // Each load is numbered, so an older answer never replaces a newer one; and
  // a load that was on its way while a row changed here (a check-in) is read
  // again, so it cannot put back what the row showed before.
  const loadSeq = useRef(0);
  const changeSeq = useRef(0);
  const loadGuests = useCallback(async (): Promise<void> => {
    for (;;) {
      const mine = ++loadSeq.current;
      const changesBefore = changeSeq.current;
      setLoading(true);
      const { data, error } = await supabase.rpc('event_guest_list', { p_event_id: event.id });
      if (mine !== loadSeq.current) return;
      if (changeSeq.current !== changesBefore) continue;
      setLoading(false);
      if (error) { setErr(error.message); return; }
      setErr(null);
      setGuests((Array.isArray(data) ? data : []).map(normalizeGuest));
      return;
    }
  }, [event.id]);
  useEffect(() => { void loadGuests(); }, [loadGuests]);

  // 415: the door list follows the other door devices while Check-in is open:
  // every CHECK_IN_REFRESH_MS while the page is in sight, and when it comes back
  // into sight. Codes being typed are kept (they are held apart from the list).
  useEffect(() => {
    if (tab !== 'checkin') return;
    const visible = () => document.visibilityState !== 'hidden';
    const timer = window.setInterval(() => { if (visible()) void loadGuests(); }, CHECK_IN_REFRESH_MS);
    const onBack = () => { if (visible()) void loadGuests(); };
    window.addEventListener('focus', onBack);
    document.addEventListener('visibilitychange', onBack);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener('focus', onBack);
      document.removeEventListener('visibilitychange', onBack);
    };
  }, [tab, loadGuests]);

  const loads = useMemo(() => dayLoads(event, guests), [event, guests]);
  const status = eventStatus(event, today);

  const onGuestSaved = async (r: GuestSaved) => {
    const done = `${r.name} is ${r.action ?? 'saved'}.`;
    // 415: a restored guest loses the days the event no longer has.
    const dropped = r.days_dropped?.length
      ? ` ${fmtDayList(r.days_dropped)} ${r.days_dropped.length === 1 ? 'is' : 'are'} no longer an event day, so ${r.days_dropped.length === 1 ? 'it was' : 'they were'} taken off.`
      : '';
    setNotice(r.over_capacity.length || dropped
      ? { tone: 'warning', text: `${done}${dropped}${r.over_capacity.length ? ` ${overCapacityText(r.over_capacity)}.` : ''}` }
      : { tone: 'info', text: done });
    await loadGuests();
    onChanged();
  };

  const onGuestChange = (g: Guest) => {
    changeSeq.current += 1;
    setGuests(list => (list ?? []).map(x => (x.guest_id === g.guest_id ? g : x)));
  };

  // The window stays open until the event is deleted, showing why if it is not.
  const remove = async (reason: string): Promise<string | null> => {
    const { error } = await supabase.rpc('event_delete', { p_event_id: event.id, p_reason: reason });
    if (error) return error.message;
    onDeleted();
    return null;
  };

  return (
    <div>
      <button className="btn btn-secondary btn-sm events-back" onClick={onBack}><ArrowLeft size={14} /> All events</button>

      <div className="card events-head">
        <div className="events-head-top">
          <h2>{event.name} <span className={STATUS_BADGE[status].cls}>{STATUS_BADGE[status].label}</span></h2>
          <div className="events-head-actions">
            <button className="btn btn-secondary btn-sm" onClick={() => { void loadGuests(); onChanged(); }}>
              <RefreshCw size={13} className={loading ? 'spin' : ''} /> Refresh
            </button>
            {canManage && (
              <>
                <button className="btn btn-secondary btn-sm" onClick={onEdit}><Pencil size={13} /> Edit</button>
                <button className="btn btn-danger btn-sm" onClick={() => setDeleting(true)}><Trash2 size={13} /> Delete</button>
              </>
            )}
          </div>
        </div>
        <div className="events-line"><CalendarDays size={14} /><span>{fmtDayList(event.days.map(d => d.day))}</span></div>
        {fmtHours(event.daily_start, event.daily_end) && (
          <div className="events-line"><Clock size={14} /><span>Daily {fmtHours(event.daily_start, event.daily_end)}</span></div>
        )}
        <div className="events-line"><Store size={14} /><span>{event.stores.map(s => s.name).join(', ') || 'No store'}</span></div>
        <div className="events-line">
          <Ticket size={14} />
          <div className="events-chips">
            {event.options.map(o => (
              <span key={o.id} className={`events-chip events-chip-price${o.is_active ? '' : ' events-chip-off'}`}
                title={o.is_active ? undefined : 'Off sale'}>
                {o.name} {money(o.price)}
                {o.early_bird_price != null && event.early_bird_until
                  ? ` · early bird ${money(o.early_bird_price)} until ${fmtDayMonth(event.early_bird_until)}` : ''}
              </span>
            ))}
          </div>
        </div>
        <div className="events-line">
          <Users size={14} />
          <div className="events-chips">
            {loads.map(l => {
              const tone = loadTone(l);
              return (
                <span key={l.day} className={`events-chip${tone === 'over' ? ' events-chip-over' : tone === 'full' ? ' events-chip-full' : ''}`}>
                  {fmtWeekday(l.day)}: {loadText(l)}{tone === 'over' ? ' · over capacity' : tone === 'full' ? ' · full' : ''} · {l.attended} in
                </span>
              );
            })}
          </div>
        </div>
        {event.early_bird_until && event.early_bird_percent != null && (
          <div className="events-sub">
            Early bird: {event.early_bird_percent}% off per person on invoices dated on or before {fmtDate(event.early_bird_until)}.
          </div>
        )}
        {event.description && <div style={{ fontSize: 13 }}>{event.description}</div>}
        {event.notes && <div className="events-sub">Notes: {event.notes}</div>}
      </div>

      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
      {notice && (
        <div className={`alert ${notice.tone === 'warning' ? 'alert-warning' : 'alert-info'}`} role="status">
          <span>{notice.tone === 'warning' ? '⚠' : '✓'}</span>
          <div style={{ flex: 1 }}>{notice.text}</div>
          <button className="btn btn-secondary btn-sm" onClick={() => setNotice(null)}>Dismiss</button>
        </div>
      )}

      <div className="events-tabs" role="tablist">
        <button role="tab" aria-selected={tab === 'guests'} className={`events-tab${tab === 'guests' ? ' active' : ''}`}
          onClick={() => setTab('guests')}><Users size={15} /> Guests</button>
        <button role="tab" aria-selected={tab === 'checkin'} className={`events-tab${tab === 'checkin' ? ' active' : ''}`}
          onClick={() => setTab('checkin')}><ClipboardCheck size={15} /> Check-in</button>
        <button role="tab" aria-selected={tab === 'sales'} className={`events-tab${tab === 'sales' ? ' active' : ''}`}
          onClick={() => setTab('sales')}><Receipt size={15} /> Sales</button>
        {seesWebOrders && (
          <button role="tab" aria-selected={tab === 'web'} className={`events-tab${tab === 'web' ? ' active' : ''}`}
            onClick={() => setTab('web')}><Globe size={15} /> Website orders</button>
        )}
      </div>

      {tab === 'guests' && (
        <GuestsTab event={event} guests={guests ?? []} loading={loading} loads={loads} staff={staff}
          currentUserId={currentUserId} currentUserName={currentUserName}
          onSaved={r => { void onGuestSaved(r); }} onReload={async () => { await loadGuests(); onChanged(); }} />
      )}
      {tab === 'checkin' && (
        guests === null
          ? <div className="card empty-state"><p>{loading ? 'Loading the guest list…' : 'The guest list could not be loaded.'}</p></div>
          : <CheckInPanel event={event} guests={guests} loads={loads} today={today}
              currentUserName={currentUserName} onGuestChange={onGuestChange} />
      )}
      {tab === 'sales' && <SalesTab event={event} />}
      {tab === 'web' && seesWebOrders && (
        <WebOrdersTab event={event} onInvoiced={() => { void loadGuests(); onChanged(); }} />
      )}

      {deleting && (
        <ReasonModal title={`Delete ${event.name}`} label="Why is it being deleted?" confirmLabel="Delete event"
          placeholder="e.g. Set up by mistake"
          onClose={() => setDeleting(false)} onSubmitAsync={remove} />
      )}
    </div>
  );
};

export default EventView;
