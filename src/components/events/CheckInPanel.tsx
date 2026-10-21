import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, Check, Crown, Gift, Search, Undo2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal, ReasonModal } from '../ui';
import {
  EventPlanning, EventRow, EventWebExtras, Guest, GuestGift, PLAN_BADGE_CLASS, VIP_PERKS, doorBadges, extraOf, fmtTime,
  fmtWeekday, guestDay, isVipGuest, loadText, loadTone, normalizeCheckInResult, paymentLabel, paymentTone, planningOf, DayLoad,
} from './model';

/*
 * The door: pick the day, find the person, tick them in with the day's code.
 * Each row is updated from what the server returns, so the list never waits
 * for a reload between two people at the door.
 *
 * 415: two door devices may work on one guest. A check-in never changes one
 * already made: the server answers who checked the guest in, when, and with
 * which code, and the row says so. Only Save code changes a code. Undo asks
 * first, naming what it clears. The day follows the Singapore date while
 * nobody has picked one by hand, so a device left open overnight moves to the
 * new day; once a day is picked by hand, the panel offers to switch instead.
 *
 * 436: a VIP (their VIP ticket, from the website or the counter) has a VIP
 * badge and their perks. Once they are checked in and have no gift yet, the
 * gifts appear with the store's stock: the one they pick is taken out of the
 * store's stock there and then (Record use: a USE number). Later hides it for
 * now. An Owner or Manager can mark a gift undone (the item goes back through
 * an adjustment request).
 *
 * 436 round 7 (S3): the guest's allergy (red, never cut), food and access
 * needs show on their row, from their planning answers. The page reads those
 * at most every 2 minutes while Check-in is open (EventView); a failed read
 * keeps the last badges.
 */

type Show = 'all' | 'waiting' | 'in';
type Action = 'in' | 'code' | 'undo';

export const CheckInPanel: React.FC<{
  event: EventRow;
  guests: Guest[];
  loads: DayLoad[];
  today: string;
  currentUserName: string | null;
  onGuestChange: (g: Guest) => void;
  /** 436: what the event's website adds to each guest (VIP, gift), or null. */
  extras?: EventWebExtras | null;
  /** 436: a gift was given or undone: read the extras again. */
  onExtrasChanged?: () => void;
  /** 436 round 7: the guests' planning answers, or null. */
  planning?: EventPlanning | null;
}> = ({ event, guests, loads, today, currentUserName, onGuestChange, extras = null, onExtrasChanged, planning = null }) => {
  const isEventDay = (d: string) => event.days.some(x => x.day === d);
  const [day, setDay] = useState<string>(() => (isEventDay(today) ? today : (event.days[0]?.day ?? '')));
  // Whether someone chose the day by hand; until then it follows today.
  const [picked, setPicked] = useState(false);
  const [search, setSearch] = useState('');
  const [show, setShow] = useState<Show>('all');
  const [codes, setCodes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<Record<string, boolean>>({});
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [undoing, setUndoing] = useState<Guest | null>(null);
  const [otherDay, setOtherDay] = useState<Guest | null>(null);
  // "today|day" once someone confirmed checking in on a day that is not today.
  const [otherDayOk, setOtherDayOk] = useState<string | null>(null);
  // 436: gifts given here before the extras are read again, VIPs whose gift is
  // for later, and the gift being undone.
  const [given, setGiven] = useState<Record<string, GuestGift | null>>({});
  // 436: one request id per guest's gift, kept until the server answers for
  // certain, so a tap again after a lost answer is the same gift (the server
  // replays it), never a second one out of stock.
  const giftRequest = useRef<Record<string, string>>({});
  const [later, setLater] = useState<Record<string, boolean>>({});
  const [undoGift, setUndoGift] = useState<{ guest: Guest; gift: GuestGift } | null>(null);
  const giftOf = (g: Guest): GuestGift | null => (g.guest_id in given ? given[g.guest_id] : extraOf(extras, g)?.gift ?? null);

  // The date moved on (a device left open overnight): follow it, unless a day
  // was picked by hand. A day the event no longer has goes back to the default.
  const dayKeys = event.days.map(d => d.day).join(',');
  useEffect(() => {
    const days = dayKeys ? dayKeys.split(',') : [];
    if (!days.includes(day)) {
      setDay(days.includes(today) ? today : (days[0] ?? ''));
      setPicked(false);
      return;
    }
    if (!picked && days.includes(today) && day !== today) setDay(today);
  }, [today, dayKeys, day, picked]);

  const pickDay = (d: string) => { setDay(d); setPicked(d !== today); };

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

  const keyOf = (g: Guest) => `${g.guest_id}|${day}`;
  const codeOf = (g: Guest) => codes[keyOf(g)] ?? guestDay(g, day)?.check_in_code ?? '';
  const setCode = (g: Guest, v: string) => setCodes(c => ({ ...c, [keyOf(g)]: v }));
  const without = (k: string) => (m: Record<string, string>) => { const n = { ...m }; delete n[k]; return n; };

  const send = async (g: Guest, action: Action) => {
    const k = keyOf(g);
    setBusy(b => ({ ...b, [k]: true }));
    setErrors(without(k)); setNotes(without(k));
    const code = codeOf(g).trim();
    const { data, error } = await supabase.rpc('event_check_in', {
      p_guest_id: g.guest_id, p_day: day, p_attended: action !== 'undo',
      p_code: action === 'undo' ? null : (code || null),
      // Only Save code changes the code of a guest who is in (415).
      ...(action === 'code' ? { p_save_code: true } : {}),
    });
    setBusy(b => ({ ...b, [k]: false }));
    if (error) { setErrors(e => ({ ...e, [k]: error.message })); return; }
    const r = normalizeCheckInResult(data, day);
    const before = guestDay(g, day);
    // The server names who checked the guest in. A database without 415 does
    // not, so then the person here is named for a new check-in.
    const named = !!data && typeof data === 'object' && 'checked_in_by_name' in (data as object);
    const checker = !r.attended_at ? null
      : named ? r.checked_in_by_name
      : (before?.attended_at ? before.checked_in_by_name : currentUserName);
    onGuestChange({
      ...g,
      days: g.days.map(d => d.day !== day ? d : {
        ...d, attended_at: r.attended_at, check_in_code: r.check_in_code, checked_in_by_name: checker,
      }),
    });
    setCodes(without(k));
    if (r.already_in) {
      setNotes(n => ({
        ...n,
        [k]: `Already checked in at ${fmtTime(r.attended_at)}${checker ? ` by ${checker}` : ''}`
          + `${r.check_in_code ? ` (code ${r.check_in_code})` : ''}. Nothing was changed.`,
      }));
    }
  };

  // 436: the VIP gift. Its request id is kept for the guest until the server
  // answers for certain: a tap again after a lost answer (the network) is the
  // same gift; after a refusal (none left, already given) the next is new.
  const giveGift = async (g: Guest, productId: string) => {
    const k = keyOf(g);
    const requestId = giftRequest.current[g.guest_id] ?? crypto.randomUUID();
    giftRequest.current[g.guest_id] = requestId;
    setBusy(b => ({ ...b, [k]: true }));
    setErrors(without(k)); setNotes(without(k));
    const { data, error } = await supabase.rpc('event_vip_gift_give', {
      p_guest_id: g.guest_id, p_product_id: productId, p_day: day, p_request_id: requestId,
    });
    setBusy(b => ({ ...b, [k]: false }));
    if (error) {
      // An answer from the database has a code; a lost one (the network) has none.
      if (error.code) delete giftRequest.current[g.guest_id];
      setErrors(e => ({ ...e, [k]: error.message }));
      return;
    }
    delete giftRequest.current[g.guest_id];
    const r = (data ?? {}) as { gift_id?: string; use_no?: string; product_id?: string; product_name?: string };
    setGiven(m => ({ ...m, [g.guest_id]: {
      gift_id: String(r.gift_id ?? ''), product_id: String(r.product_id ?? productId), product_name: String(r.product_name ?? ''),
      use_no: r.use_no ?? null, day, given_at: new Date().toISOString(), given_by_name: currentUserName,
    } }));
    onExtrasChanged?.();
  };
  const undoGiftNow = async (reason: string): Promise<string | null> => {
    if (!undoGift) return null;
    const { data, error } = await supabase.rpc('event_vip_gift_undo', { p_gift_id: undoGift.gift.gift_id, p_reason: reason });
    if (error) return error.message;
    const g = undoGift.guest;
    setGiven(m => ({ ...m, [g.guest_id]: null }));
    setNotes(n => ({ ...n, [keyOf(g)]: String((data as { message?: string } | null)?.message ?? 'The gift is undone.') }));
    onExtrasChanged?.();
    return null;
  };

  // A check-in on a day that is not today is asked once per day.
  const checkIn = (g: Guest) => {
    if (day !== today && otherDayOk !== `${today}|${day}`) { setOtherDay(g); return; }
    void send(g, 'in');
  };

  if (event.days.length === 0) return <div className="empty-state"><p>This event has no days.</p></div>;

  const undoDay = undoing ? guestDay(undoing, day) : undefined;

  return (
    <div className="events-checkin">
      <div className="events-checkin-days" role="group" aria-label="Day">
        {loads.map(l => (
          <button key={l.day} type="button" className={`events-checkin-day${l.day === day ? ' active' : ''}`}
            aria-pressed={l.day === day} onClick={() => pickDay(l.day)}>
            <strong>{fmtWeekday(l.day)}{l.day === today ? ' · today' : ''}</strong>
            <span className="events-sub">{l.attended} in · {loadText(l)}</span>
          </button>
        ))}
      </div>

      {day !== today && isEventDay(today) && (
        <div className="alert alert-warning events-checkin-today" role="status">
          <AlertTriangle size={15} />
          <div style={{ flex: 1 }}>It is now {fmtWeekday(today)}. This list is for {fmtWeekday(day)}.</div>
          <button type="button" className="btn btn-primary btn-sm" onClick={() => pickDay(today)}>
            Switch to {fmtWeekday(today)}
          </button>
        </div>
      )}

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
            const k = keyOf(g);
            const code = codeOf(g);
            const codeChanged = done && code.trim() !== (gd?.check_in_code ?? '');
            const vip = isVipGuest(g, extraOf(extras, g));
            const gift = vip ? giftOf(g) : null;
            const choices = extras?.gift_choices ?? [];
            const badges = doorBadges(planningOf(planning, g), event, planning?.hours);
            return (
              <div key={g.guest_id} className={`events-checkin-row${done ? ' done' : ''}${vip ? ' vip' : ''}`} data-guest={g.guest_id}>
                <div style={{ minWidth: 0 }}>
                  <div className="events-checkin-name">
                    {g.name}
                    {vip && <> <span className="badge events-badge-vip" title={VIP_PERKS}><Crown size={11} /> VIP</span></>}
                  </div>
                  {vip && <div className="events-sub events-vip-perks">{VIP_PERKS}</div>}
                  {badges.length > 0 && (
                    <div className="events-badges events-plan-badges" data-plan-badges>
                      {badges.map((b, i) => (
                        <span key={i} data-plan-badge={b.kind} title={b.title} aria-label={b.title} className={PLAN_BADGE_CLASS[b.kind]}>{b.text}</span>
                      ))}
                    </div>
                  )}
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
                  onKeyDown={e => {
                    if (e.key !== 'Enter' || busy[k]) return;
                    if (!done) checkIn(g); else if (codeChanged) void send(g, 'code');
                  }} />
                <div className="events-checkin-actions">
                  {!done && (
                    <button className="btn btn-primary events-big-btn" disabled={!!busy[k]} onClick={() => checkIn(g)}>
                      <Check size={18} /> {busy[k] ? 'Checking in…' : 'Check in'}
                    </button>
                  )}
                  {done && codeChanged && (
                    <button className="btn btn-primary events-big-btn" disabled={!!busy[k]} onClick={() => void send(g, 'code')}>
                      Save code
                    </button>
                  )}
                  {done && (
                    <button className="btn btn-secondary events-big-btn" disabled={!!busy[k]} onClick={() => setUndoing(g)}>
                      <Undo2 size={16} /> Undo
                    </button>
                  )}
                </div>
                {vip && gift && (
                  <div className="events-gift" data-gift={gift.gift_id}>
                    <Gift size={14} /> Gift: {gift.product_name}{gift.use_no ? ` · ${gift.use_no}` : ''}
                    {extras?.can_undo_gifts && gift.gift_id && (
                      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setUndoGift({ guest: g, gift })}>Undo gift</button>
                    )}
                  </div>
                )}
                {vip && !gift && done && !later[g.guest_id] && choices.length > 0 && (
                  <div className="events-gift events-gift-picker" role="group" aria-label={`Gift for ${g.name}`}>
                    <Gift size={14} /> <span>Gift:</span>
                    {choices.map(c => (
                      <button key={c.product_id} type="button" className="btn btn-primary btn-sm" disabled={!!busy[k] || c.stock <= 0}
                        title={c.stock <= 0 ? 'None left at the store' : undefined}
                        onClick={() => void giveGift(g, c.product_id)}>{c.name} ({c.stock})</button>
                    ))}
                    <button type="button" className="btn btn-secondary btn-sm" onClick={() => setLater(m => ({ ...m, [g.guest_id]: true }))}>Later</button>
                  </div>
                )}
                {notes[k] && <div className="events-inline-note" role="status">{notes[k]}</div>}
                {errors[k] && <div className="events-inline-error" role="alert">{errors[k]}</div>}
              </div>
            );
          })}
        </div>
      )}

      {undoing && (
        <Modal title={`Undo ${undoing.name}'s check-in?`} maxWidth={440} onClose={() => setUndoing(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setUndoing(null)}>Keep it</button>
            <button className="btn btn-danger" onClick={() => { const g = undoing; setUndoing(null); void send(g, 'undo'); }}>
              Undo check-in
            </button>
          </>}>
          <div className="form-grid events-undo-detail">
            <div>
              {undoing.name} · {fmtWeekday(day)}
              {undoDay?.attended_at ? ` · in at ${fmtTime(undoDay.attended_at)}` : ''}
              {undoDay?.checked_in_by_name ? ` · by ${undoDay.checked_in_by_name}` : ''}
              {undoDay?.check_in_code ? ` · code ${undoDay.check_in_code}` : ''}
            </div>
            <div className="events-sub">
              Only undo a check-in made by mistake. The time, who checked them in and the code are cleared (the
              audit log keeps them).
            </div>
          </div>
        </Modal>
      )}

      {undoGift && (
        <ReasonModal title={`Undo ${undoGift.guest.name}'s gift`} label="Why is it undone?" confirmLabel="Undo gift"
          placeholder="e.g. Given by mistake, wrong size" minLength={3}
          onClose={() => setUndoGift(null)} onSubmitAsync={undoGiftNow} />
      )}

      {otherDay && (
        <Modal title={`Check in for ${fmtWeekday(day)}?`} maxWidth={440} onClose={() => setOtherDay(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setOtherDay(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={() => {
              const g = otherDay; setOtherDay(null); setOtherDayOk(`${today}|${day}`); void send(g, 'in');
            }}>
              Check in for {fmtWeekday(day)}
            </button>
          </>}>
          <div className="form-grid">
            <div>Today is {fmtWeekday(today)}. {otherDay.name} will be checked in for {fmtWeekday(day)}.</div>
            <div className="events-sub">You will not be asked again for {fmtWeekday(day)} today.</div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default CheckInPanel;
