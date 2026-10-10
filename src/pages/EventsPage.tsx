import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { CalendarDays, Clock, PartyPopper, Plus, RefreshCw, Store, Ticket, Users } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isManagerOrAbove, isOwnerOrAdmin } from '../types';
import { NoAccess } from '../components/ui';
import { useSingaporeToday } from '../lib/useSingaporeToday';
import { EventEditor } from '../components/events/EventEditor';
import { EventView } from '../components/events/EventView';
import {
  EventRow, STATUS_BADGE, StaffOption, StoreOption, eventStatus, fmtDayList, fmtDayMonth, fmtHours,
  fmtWeekday, loadText, loadTone, money, normalizeEvent,
} from '../components/events/model';
import '../components/events/events.css';

/*
 * Events: days at one or more stores, sold as tickets on invoices.
 *
 * Owners, Admins and Managers set an event up (days, stores, ticket options,
 * early bird). Staff at an event's store run it: the guest list, free guests,
 * check-in at the door, and its sales. The server enforces all of that; this
 * page only hides what the person cannot do.
 */

type ListFilter = 'upcoming' | 'past' | 'all';

// Anyone who can register a guest, as the server accepts them.
const REGISTERING_ROLES = ['owner', 'admin', 'manager', 'staff'];

const EventsPage: React.FC = () => {
  const { profile } = useAuth();
  const role = profile?.role;
  // Access is decided after the hooks below; returning before them would call
  // a different number of hooks from one render to the next.
  const hasAccess = isManagerOrAbove(role) || role === 'staff';
  const isManager = isManagerOrAbove(role);
  // Read again every minute and when the window comes back, so a door device
  // left open overnight moves to the new day (EVENTS-2).
  const today = useSingaporeToday();

  const [events, setEvents] = useState<EventRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [loaded, setLoaded] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [filter, setFilter] = useState<ListFilter>('upcoming');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [staff, setStaff] = useState<StaffOption[]>([]);
  const [stores, setStores] = useState<StoreOption[]>([]);
  const [storesErr, setStoresErr] = useState<string | null>(null);
  const [editor, setEditor] = useState<{ event: EventRow | null } | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const loadEvents = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('events_list');
    setLoading(false);
    if (error) { setErr(error.message); return; }
    setErr(null);
    setEvents((Array.isArray(data) ? data : []).map(normalizeEvent));
    setLoaded(true);
  }, []);

  useEffect(() => { if (hasAccess) void loadEvents(); }, [hasAccess, loadEvents]);

  // The staff who can be named as having registered a guest.
  useEffect(() => {
    if (!hasAccess) return;
    let cancelled = false;
    void supabase.from('profiles').select('id,full_name,role,is_active').is('deleted_at', null).eq('is_active', true)
      .then(({ data }) => {
        if (cancelled) return;
        setStaff(((data as StaffOption[]) ?? [])
          .filter(p => REGISTERING_ROLES.includes(p.role))
          .sort((a, b) => (a.full_name ?? '').localeCompare(b.full_name ?? '')));
      });
    return () => { cancelled = true; };
  }, [hasAccess]);

  // The stores an event can be held at: every active store for an Owner or
  // Admin, the person's own stores for anyone else.
  useEffect(() => {
    if (!isManager) return;
    let cancelled = false;
    (async () => {
      if (isOwnerOrAdmin(role)) {
        const { data, error } = await supabase.from('stores').select('id,name').is('deleted_at', null).eq('is_active', true).order('name');
        if (cancelled) return;
        setStoresErr(error ? error.message : null);
        setStores(((data as StoreOption[]) ?? []).map(s => ({ id: s.id, name: s.name })));
      } else {
        const { data, error } = await supabase.rpc('my_assigned_stores');
        if (cancelled) return;
        setStoresErr(error ? error.message : null);
        setStores(((data as { store_id: string; store_name: string }[]) ?? [])
          .map(s => ({ id: s.store_id, name: s.store_name })));
      }
    })();
    return () => { cancelled = true; };
  }, [isManager, role]);

  const shown = useMemo(() => {
    const isPast = (e: EventRow) => !!e.last_day && e.last_day < today;
    if (filter === 'upcoming') {
      return events.filter(e => !isPast(e))
        .sort((a, b) => (a.first_day ?? '9999').localeCompare(b.first_day ?? '9999'));
    }
    if (filter === 'past') return events.filter(isPast);
    return events;
  }, [events, filter, today]);

  const selected = selectedId ? events.find(e => e.id === selectedId) ?? null : null;

  const onSaved = async (id: string) => {
    const isNew = !editor?.event;
    setEditor(null);
    await loadEvents();
    if (id) setSelectedId(id);
    setNotice(isNew ? 'Event created.' : 'Event saved.');
  };

  if (!hasAccess) {
    return <NoAccess message="Events are run by store staff and set up by Owners, Admins and Managers." />;
  }

  const editorModal = editor && (
    <EventEditor event={editor.event} stores={stores} storesError={storesErr} canChangeAnyStore={isOwnerOrAdmin(role)}
      onClose={() => setEditor(null)} onSaved={id => { void onSaved(id); }} />
  );

  if (selectedId) {
    return (
      <div className="events-scope">
        {notice && (
          <div className="alert alert-info" role="status">
            <span>✓</span><div style={{ flex: 1 }}>{notice}</div>
            <button className="btn btn-secondary btn-sm" onClick={() => setNotice(null)}>Dismiss</button>
          </div>
        )}
        {selected ? (
          <EventView key={selected.id} event={selected} today={today}
            canManage={isManager && selected.can_manage}
            staff={staff} currentUserId={profile?.id ?? null} currentUserName={profile?.full_name ?? null}
            onBack={() => { setSelectedId(null); setNotice(null); void loadEvents(); }}
            onEdit={() => setEditor({ event: selected })}
            onDeleted={() => { setSelectedId(null); setNotice('Event deleted.'); void loadEvents(); }}
            onChanged={() => { void loadEvents(); }} />
        ) : (
          <>
            <button className="btn btn-secondary btn-sm events-back" onClick={() => setSelectedId(null)}>← All events</button>
            {err
              ? <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>
              : <div className="card empty-state"><p>{loading ? 'Loading the event…' : 'This event is not available.'}</p></div>}
          </>
        )}
        {editorModal}
      </div>
    );
  }

  return (
    <div className="events-scope">
      <div className="page-header">
        <div>
          <h2>Events</h2>
          <p>Event days at your stores. Tickets are sold on invoices; everyone on a ticket joins the guest list by themselves.</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={() => void loadEvents()}>
            <RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh
          </button>
          {isManager && (
            <button className="btn btn-primary" onClick={() => setEditor({ event: null })}><Plus size={16} /> New event</button>
          )}
        </div>
      </div>

      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
      {notice && (
        <div className="alert alert-info" role="status">
          <span>✓</span><div style={{ flex: 1 }}>{notice}</div>
          <button className="btn btn-secondary btn-sm" onClick={() => setNotice(null)}>Dismiss</button>
        </div>
      )}

      <div className="events-toolbar">
        <div className="events-seg" role="group" aria-label="Show">
          {(['upcoming', 'past', 'all'] as ListFilter[]).map(f => (
            <button key={f} className={`btn btn-sm ${filter === f ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setFilter(f)}>
              {f === 'upcoming' ? 'Upcoming' : f === 'past' ? 'Past' : 'All'}
            </button>
          ))}
        </div>
      </div>

      {!loaded ? (
        <div className="card empty-state">
          {err ? <p>The events could not be loaded.</p> : <RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} />}
        </div>
      ) : shown.length === 0 ? (
        <div className="card empty-state">
          <PartyPopper size={34} style={{ opacity: 0.3, marginBottom: 8 }} />
          <p style={{ fontWeight: 600 }}>
            {events.length === 0 ? 'No events yet' : filter === 'upcoming' ? 'No upcoming events' : 'No past events'}
          </p>
          <p style={{ fontSize: 13 }}>
            {events.length === 0
              ? (isManager ? 'Create one with New event.' : 'Events at your store will show here once a manager sets one up.')
              : 'Choose All to see every event.'}
          </p>
        </div>
      ) : (
        <div className="events-list">
          {shown.map(e => {
            const status = eventStatus(e, today);
            const hours = fmtHours(e.daily_start, e.daily_end);
            return (
              <div key={e.id} className="card events-card" role="button" tabIndex={0}
                aria-label={`Open ${e.name}`}
                onClick={() => { setNotice(null); setSelectedId(e.id); }}
                onKeyDown={ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); setNotice(null); setSelectedId(e.id); } }}>
                <div className="events-card-head">
                  <div className="events-card-name">{e.name}</div>
                  <span className={STATUS_BADGE[status].cls}>{STATUS_BADGE[status].label}</span>
                </div>
                <div className="events-line"><CalendarDays size={14} /><span>{fmtDayList(e.days.map(d => d.day))}</span></div>
                {hours && <div className="events-line"><Clock size={14} /><span>{hours}</span></div>}
                <div className="events-line"><Store size={14} /><span>{e.stores.map(s => s.name).join(', ') || 'No store'}</span></div>
                <div className="events-line">
                  <Ticket size={14} />
                  <div className="events-chips">
                    {e.options.length === 0 && <span className="events-muted">No ticket options</span>}
                    {e.options.map(o => (
                      <span key={o.id} className={`events-chip events-chip-price${o.is_active ? '' : ' events-chip-off'}`}
                        title={o.is_active ? undefined : 'Off sale'}>
                        {o.name} {money(o.price)}
                        {o.early_bird_price != null && e.early_bird_until
                          ? ` · early bird ${money(o.early_bird_price)} until ${fmtDayMonth(e.early_bird_until)}` : ''}
                      </span>
                    ))}
                  </div>
                </div>
                <div className="events-line">
                  <Users size={14} />
                  <div className="events-chips">
                    {e.days.map(d => {
                      const tone = loadTone(d);
                      return (
                        <span key={d.day} className={`events-chip${tone === 'over' ? ' events-chip-over' : tone === 'full' ? ' events-chip-full' : ''}`}>
                          {fmtWeekday(d.day)}: {loadText(d)}{tone === 'over' ? ' · over capacity' : tone === 'full' ? ' · full' : ''}
                        </span>
                      );
                    })}
                  </div>
                </div>
                <div className="events-sub">
                  {e.guests} guest{e.guests === 1 ? '' : 's'} ({e.ticket_guests} ticket, {e.free_guests} free)
                </div>
              </div>
            );
          })}
        </div>
      )}
      {editorModal}
    </div>
  );
};

export default EventsPage;
