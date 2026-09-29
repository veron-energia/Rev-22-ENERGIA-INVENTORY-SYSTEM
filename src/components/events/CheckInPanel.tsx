import React, { useMemo, useState } from 'react';
import { Check, Search, Undo2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import {
  EventRow, Guest, fmtTime, fmtWeekday, guestDay, loadText, loadTone, normalizeGuestDay,
  paymentLabel, paymentTone, DayLoad,
} from './model';

/*
 * The door: pick the day, find the person, tick them in with the day's code.
 * Each row is updated from what the server returns, so the list never waits
 * for a reload between two people at the door.
 */

type Show = 'all' | 'waiting' | 'in';

export const CheckInPanel: React.FC<{
  event: EventRow;
  guests: Guest[];
  loads: DayLoad[];
  today: string;
  currentUserName: string | null;
  onGuestChange: (g: Guest) => void;
}> = ({ event, guests, loads, today, currentUserName, onGuestChange }) => {
  const [day, setDay] = useState<string>(() =>
    event.days.some(d => d.day === today) ? today : (event.days[0]?.day ?? ''));
  const [search, setSearch] = useState('');
  const [show, setShow] = useState<Show>('all');
  const [codes, setCodes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<Record<string, boolean>>({});
  const [errors, setErrors] = useState<Record<string, string>>({});

  const onDay = useMemo(() => guests
    .filter(g => g.status === 'registered' && !!guestDay(g, day))
    .sort((a, b) => a.name.localeCompare(b.name)), [guests, day]);

  const q = search.trim().toLowerCase();
  const qDigits = /^[\d\s+()-]+$/.test(q) ? q.replace(/\D/g, '') : '';
  const shown = onDay.filter(g => {
    const done = !!guestDay(g, day)?.attended_at;
    if (show === 'waiting' && done) return false;
    if (show === 'in' && !done) return false;
    if (!q) return true;
    return g.name.toLowerCase().includes(q)
      || (g.phone ?? '').toLowerCase().includes(q)
      || (qDigits.length >= 3 && (g.phone ?? '').replace(/\D/g, '').includes(qDigits))
      || (g.invoice_no ?? '').toLowerCase().includes(q);
  });

  const load = loads.find(l => l.day === day);
  const checkedIn = onDay.filter(g => !!guestDay(g, day)?.attended_at).length;

  const codeOf = (g: Guest) => codes[`${g.guest_id}|${day}`] ?? guestDay(g, day)?.check_in_code ?? '';
  const setCode = (g: Guest, v: string) => setCodes(c => ({ ...c, [`${g.guest_id}|${day}`]: v }));

  const checkIn = async (g: Guest, attended: boolean) => {
    const k = `${g.guest_id}|${day}`;
    setBusy(b => ({ ...b, [k]: true }));
    setErrors(e => { const n = { ...e }; delete n[k]; return n; });
    const code = codeOf(g).trim();
    const { data, error } = await supabase.rpc('event_check_in', {
      p_guest_id: g.guest_id, p_day: day, p_attended: attended, p_code: attended ? (code || null) : null,
    });
    setBusy(b => ({ ...b, [k]: false }));
    if (error) { setErrors(e => ({ ...e, [k]: error.message })); return; }
    const r = normalizeGuestDay({ ...(data ?? {}), day: (data as any)?.day ?? day });
    const before = guestDay(g, day);
    onGuestChange({
      ...g,
      days: g.days.map(d => d.day !== day ? d : {
        ...d,
        attended_at: r.attended_at,
        check_in_code: r.check_in_code,
        checked_in_by_name: r.attended_at ? (before?.attended_at ? before.checked_in_by_name : currentUserName) : null,
      }),
    });
    setCodes(c => { const n = { ...c }; delete n[k]; return n; });
  };

  if (event.days.length === 0) return <div className="empty-state"><p>This event has no days.</p></div>;

  return (
    <div className="events-checkin">
      <div className="events-checkin-days" role="group" aria-label="Day">
        {loads.map(l => (
          <button key={l.day} type="button" className={`events-checkin-day${l.day === day ? ' active' : ''}`}
            aria-pressed={l.day === day} onClick={() => setDay(l.day)}>
            <strong>{fmtWeekday(l.day)}{l.day === today ? ' · today' : ''}</strong>
            <span className="events-sub">{l.attended} in · {loadText(l)}</span>
          </button>
        ))}
      </div>

      <div className="events-checkin-search">
        <Search size={20} />
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Find a name or phone…"
          aria-label="Find a guest" autoComplete="off" />
      </div>

      <div className="events-counter">
        <span>Checked in <strong>{checkedIn}</strong> of {onDay.length} registered
          {load?.capacity != null ? ` (capacity ${load.capacity})` : ''}</span>
        {load && loadTone(load) !== 'open' && (
          <span className={`events-chip ${loadTone(load) === 'over' ? 'events-chip-over' : 'events-chip-full'}`}>
            {loadTone(load) === 'over' ? 'Over capacity' : 'Full'}
          </span>
        )}
        <span className="events-seg" style={{ marginLeft: 'auto' }}>
          {(['all', 'waiting', 'in'] as Show[]).map(s => (
            <button key={s} type="button" className={`btn btn-sm ${show === s ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setShow(s)}>
              {s === 'all' ? 'Everyone' : s === 'waiting' ? 'Not in yet' : 'Checked in'}
            </button>
          ))}
        </span>
      </div>

      {shown.length === 0 ? (
        <div className="card empty-state">
          <p style={{ fontWeight: 600 }}>{onDay.length === 0 ? 'Nobody is registered for this day' : 'Nobody matches'}</p>
          {onDay.length > 0 && <p style={{ fontSize: 13 }}>Check the spelling, or search by phone.</p>}
        </div>
      ) : (
        <div className="events-checkin-list">
          {shown.map(g => {
            const gd = guestDay(g, day);
            const done = !!gd?.attended_at;
            const k = `${g.guest_id}|${day}`;
            const code = codeOf(g);
            const codeChanged = done && code.trim() !== (gd?.check_in_code ?? '');
            return (
              <div key={g.guest_id} className={`events-checkin-row${done ? ' done' : ''}`} data-guest={g.guest_id}>
                <div style={{ minWidth: 0 }}>
                  <div className="events-checkin-name">{g.name}</div>
                  <div className="events-sub">
                    {g.phone ?? 'No phone'}
                    {' · '}
                    {g.source === 'ticket'
                      ? <>{g.ticket_option_name ?? 'Ticket'}{g.invoice_no ? ` · ${g.invoice_no}` : ''} · <span className={`events-pay-${paymentTone(g.invoice_status)}`}>{paymentLabel(g.invoice_status)}</span></>
                      : 'Free'}
                  </div>
                  {g.notes && <div className="events-sub" style={{ color: 'var(--text-secondary)' }}>Note: {g.notes}</div>}
                  {done && (
                    <div className="events-checkin-status">
                      ✓ In at {fmtTime(gd?.attended_at)}{gd?.check_in_code ? ` · ${gd.check_in_code}` : ''}
                      {gd?.checked_in_by_name ? <span className="events-sub"> · by {gd.checked_in_by_name}</span> : null}
                    </div>
                  )}
                </div>
                <input value={code} onChange={e => setCode(g, e.target.value)} placeholder="Code"
                  aria-label={`Code for ${g.name}`}
                  onKeyDown={e => { if (e.key === 'Enter' && (!done || codeChanged)) void checkIn(g, true); }} />
                <div className="events-checkin-actions">
                  {!done && (
                    <button className="btn btn-primary events-big-btn" disabled={!!busy[k]} onClick={() => void checkIn(g, true)}>
                      <Check size={18} /> {busy[k] ? 'Checking in…' : 'Check in'}
                    </button>
                  )}
                  {done && codeChanged && (
                    <button className="btn btn-primary events-big-btn" disabled={!!busy[k]} onClick={() => void checkIn(g, true)}>
                      Save code
                    </button>
                  )}
                  {done && (
                    <button className="btn btn-secondary events-big-btn" disabled={!!busy[k]} onClick={() => void checkIn(g, false)}>
                      <Undo2 size={16} /> Undo
                    </button>
                  )}
                </div>
                {errors[k] && <div className="events-inline-error" role="alert">{errors[k]}</div>}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default CheckInPanel;
