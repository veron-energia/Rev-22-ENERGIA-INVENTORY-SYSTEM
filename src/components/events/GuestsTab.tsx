import React, { useMemo, useState } from 'react';
import { ClipboardList, Copy, Crown, Pencil, RotateCcw, Search, UserPlus, UserX, Users } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { ReasonModal } from '../ui';
import { ExcelColumn, ExcelExportButton } from '../ExcelExport';
import { GuestModal, GuestSaved } from './GuestModal';
import { RegistrationHoldsPanel } from './RegistrationHoldsPanel';
import { GuestPlanningModal } from './GuestPlanningModal';
import {
  DayLoad, EventPlanning, EventRow, EventWebExtras, Guest, GuestExtra, ONLINE_PAYMENT_NOT_PAID, PLAN_BADGE_CLASS, PlanningState, SIGNED_UP_AGAIN,
  StaffOption, TWO_VIP_PAYMENTS, VIP_PERKS,
  VIP_PROVIDER_LABELS, accessCell, allergyCell, answersUpdatedCell, dayLabel, extraOf, fmtDayMonth, fmtTime, fmtWeekday, foodCell,
  fmtDayList, guestDay, heardFromCell, invoiceStatusLabel, isVipDouble, isVipGuest, normalizeGuestRestored, paymentLabel, paymentTone, planningBadges,
  planningOf, slug, talksCell, timingCell, vipCheckoutText, vipLink,
} from './model';

type TypeFilter = 'all' | 'ticket' | 'free';
type StatusFilter = 'registered' | 'cancelled' | 'all';
// 436: the event's own website: VIPs, people who registered there, people waiting to be matched.
type WebFilter = 'all' | 'vip' | 'website' | 'match';
const WEB_FILTERS: { value: WebFilter; label: string }[] = [
  { value: 'all', label: 'All guests' }, { value: 'vip', label: 'VIP' }, { value: 'website', label: 'Website' },
  { value: 'match', label: 'To match' },
];
// 449: To match also shows the cancelled row of someone taken off the list who signed up again (they wait there too).
const webShown = (g: Guest, x: GuestExtra | null, f: WebFilter) =>
  f === 'all' || (f === 'vip' ? isVipGuest(g, x) : f === 'website' ? !!x?.website : !!x?.hold || !!x?.signed_up_again);

/** The cell of an answer column while the answers could not be read (K14: never left out silently). */
export const NOT_LOADED = 'Not loaded';

/**
 * 436 round 7 (S2): the guests' planning answers, after the website columns,
 * worded as the website's sheet words them (DESIGN_R7_FINAL section 5). They
 * are added when the event has a website or any answers, and also when the
 * answers could not be read (every cell then says Not loaded), so an export
 * never drops them without saying so. A database without round 7: none.
 */
export function planningExportColumns(event: EventRow, hasWebsite: boolean, planning: EventPlanning | null,
  state: PlanningState): ExcelColumn<Guest>[] {
  const answered = Object.keys(planning?.guests ?? {}).length > 0;
  const unread = state === 'error' || (state === 'loading' && hasWebsite);
  if (state === 'none' || (!unread && !(hasWebsite || answered))) return [];
  const hours = planning?.hours ?? { start: null, end: null };
  const cell = (f: (p: NonNullable<ReturnType<typeof planningOf>>) => string) => (g: Guest) => {
    if (unread || !planning) return NOT_LOADED;
    const p = planningOf(planning, g);
    return p ? f(p) : '';
  };
  return [
    { header: 'Food', value: cell(p => foodCell(p.answers)) },
    { header: 'Allergies', value: cell(p => allergyCell(p.answers)) },
    ...[...event.days].sort((a, b) => a.day.localeCompare(b.day)).map(d => ({
      header: `${dayLabel(event, d.day)} timing (${fmtDayMonth(d.day)})`, value: cell(p => timingCell(p, d.day, hours)),
    })),
    { header: 'Talks', value: cell(p => talksCell(p.answers)) },
    { header: 'Access needs', value: cell(p => accessCell(p.answers)) },
    { header: 'Heard from', value: cell(p => heardFromCell(p.answers)) },
    { header: 'Question for speakers', value: cell(p => p.answers.question ?? '') },
    { header: 'Answers updated', value: cell(p => answersUpdatedCell(p)) },
  ];
}

/**
 * The guest list export: the guest, then coming / attended / code for each
 * day. 380: with the email, the website order (its checkout or staff-link id)
 * and how the invoice was paid, so it lists every registration however it came.
 * 436 round 7: then the planning answers (planningExportColumns).
 */
export function guestExportColumns(event: EventRow, extras: EventWebExtras | null = null,
  planning: EventPlanning | null = null, planningState: PlanningState = 'none'): ExcelColumn<Guest>[] {
  // 436: with the event's website, who is VIP, where they registered, their gift and the link they came by.
  const web: ExcelColumn<Guest>[] = extras?.settings ? [
    // 444: a checkout opened and not paid is not a payment waiting.
    { header: 'VIP', value: g => (isVipGuest(g, extraOf(extras, g)) ? 'Y' : extraOf(extras, g)?.vip_waiting ? 'Waiting'
      : extraOf(extras, g)?.vip_checkout && g.status === 'registered' ? ONLINE_PAYMENT_NOT_PAID : '') },
    { header: 'Registration', value: g => { const x = extraOf(extras, g); return x?.registration_id ? `${x.registration_id} · ${x.position} of ${x.group_size}` : ''; } },
    { header: 'Gift', value: g => { const x = extraOf(extras, g); return x?.gift ? `${x.gift.product_name} · ${x.gift.use_no ?? ''}` : ''; } },
    { header: 'Referral code', value: g => extraOf(extras, g)?.referral?.code ?? '' },
    { header: 'Referral note', value: g => extraOf(extras, g)?.referral?.note ?? '' },
  ] : [];
  return [
    { header: 'Name', value: g => g.name },
    { header: 'Phone', value: g => g.phone ?? '' },
    { header: 'Email', value: g => g.email ?? '' },
    { header: 'Customer', value: g => g.customer_name ?? '' },
    { header: 'Type', value: g => (g.source === 'ticket' ? 'Ticket' : 'Free') },
    { header: 'Ticket option', value: g => g.ticket_option_name ?? '' },
    { header: 'Invoice no', value: g => g.invoice_no ?? '' },
    { header: 'Order ID', value: g => g.order_id ?? '' },
    { header: 'Invoice status', value: g => invoiceStatusLabel(g.invoice_status) },
    { header: 'Paid', value: g => (g.source === 'ticket' && g.invoice_paid != null ? g.invoice_paid : null) },
    { header: 'Payment method', value: g => g.payment_methods ?? '' },
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
    ...web,
    ...planningExportColumns(event, !!extras?.settings, planning, planningState),
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
  /** 436: what the event's website adds to each guest, or null for an event without one. */
  extras?: EventWebExtras | null;
  /** 436 round 7: the guests' planning answers (null until read, or from a database without round 7). */
  planning?: EventPlanning | null;
  planningState?: PlanningState;
  /** A guest's answers were saved here: read them again. */
  onPlanningSaved?: () => void;
}> = ({ event, guests, loading, loads, staff, currentUserId, currentUserName, onSaved, onReload, extras = null,
  planning = null, planningState = 'none', onPlanningSaved }) => {
  const [search, setSearch] = useState('');
  const [day, setDay] = useState('');
  const [type, setType] = useState<TypeFilter>('all');
  const [status, setStatus] = useState<StatusFilter>('registered');
  const [editing, setEditing] = useState<{ guest: Guest | null } | null>(null);
  const [cancelling, setCancelling] = useState<Guest | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [webFilter, setWebFilter] = useState<WebFilter>('all');
  const [copied, setCopied] = useState<string | null>(null);
  const [answering, setAnswering] = useState<Guest | null>(null);
  const [planNotice, setPlanNotice] = useState<string | null>(null);
  const hasWeb = !!extras?.settings;
  const siteUrl = extras?.settings?.site_url ?? null;

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    // Digits are matched against phones only when the search looks like a
    // phone number, so "INV-2026-0002" does not find a phone ending 0002.
    const qDigits = /^[\d\s+()-]+$/.test(q) ? q.replace(/\D/g, '') : '';
    return guests.filter(g => {
      const x = extraOf(extras, g);
      // 436: a VIP's parked free record is their own: shown only with the cancelled ones.
      if (x?.parked && status === 'registered') return false;
      if (!webShown(g, x, webFilter)) return false;
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
  }, [guests, search, day, type, status, extras, webFilter]);

  const registered = guests.filter(g => g.status === 'registered');
  const counts = {
    registered: registered.length,
    ticket: registered.filter(g => g.source === 'ticket').length,
    free: registered.filter(g => g.source === 'free').length,
    cancelled: guests.length - registered.length,
    vip: registered.filter(g => isVipGuest(g, extraOf(extras, g))).length,
    match: extras?.holds.length ?? 0,
  };

  // 436: the person's link to buy VIP, for WhatsApp.
  const copyVipLink = async (g: Guest, link: string) => {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(`${g.name}'s VIP link is copied: ${link}`);
    } catch {
      setCopied(`Copy ${g.name}'s VIP link by hand: ${link}`);
    }
  };

  // Cancelling answers an error to keep the reason window open on; restoring
  // shows what the server answers, as adding a guest does (415): days the
  // event no longer has are taken off, and a day now over capacity warns.
  const setCancelled = async (g: Guest, cancelled: boolean, reason: string | null): Promise<string | null> => {
    setErr(null); setBusyId(g.guest_id);
    const { data, error } = await supabase.rpc('event_set_guest_cancelled', {
      p_guest_id: g.guest_id, p_cancelled: cancelled, p_reason: reason,
    });
    setBusyId(null);
    if (error) return error.message;
    if (cancelled) { await onReload(); return null; }
    const r = normalizeGuestRestored(data);
    onSaved({ guest_id: g.guest_id, name: g.name, action: 'restored', ...r });
    return null;
  };
  const restore = async (g: Guest) => {
    const failure = await setCancelled(g, false, null);
    if (failure) setErr(failure);
  };

  return (
    <div>
      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
      {copied && (
        <div className="alert alert-info" role="status"><span>✓</span><div style={{ flex: 1, overflowWrap: 'anywhere' }}>{copied}</div>
          <button className="btn btn-secondary btn-sm" onClick={() => setCopied(null)}>Dismiss</button></div>
      )}
      {planNotice && (
        <div className="alert alert-info" role="status" data-plan-notice><span>✓</span><div style={{ flex: 1 }}>{planNotice}</div>
          <button className="btn btn-secondary btn-sm" onClick={() => setPlanNotice(null)}>Dismiss</button></div>
      )}

      {hasWeb && extras && (
        <RegistrationHoldsPanel holds={extras.holds} canClose={extras.can_close_holds} onChanged={() => { void onReload(); }}
          guests={guests} extras={extras} />
      )}
      {hasWeb && (
        <div className="events-seg events-web-filter" role="group" aria-label="Website filter">
          {WEB_FILTERS.map(f => (
            <button key={f.value} type="button" aria-pressed={webFilter === f.value}
              className={`btn btn-sm ${webFilter === f.value ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setWebFilter(f.value)}>
              {f.label}{f.value === 'vip' ? ` (${counts.vip})` : f.value === 'match' ? ` (${counts.match})` : ''}
            </button>
          ))}
        </div>
      )}

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
        {planningState === 'error' && (
          <div className="alert alert-warning events-plan-export-warning" role="alert" data-plan-export-warning>
            <span>⚠</span>
            <div>The guests' answers (food, allergies, timing) could not be loaded, so the export's answer columns say
              {' '}{NOT_LOADED}. Refresh to try again before exporting.</div>
          </div>
        )}
        <div style={{ display: 'flex', gap: 8, marginLeft: 'auto', flexWrap: 'wrap' }}>
          <ExcelExportButton rows={filtered} columns={guestExportColumns(event, extras, planning, planningState)}
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
          {hasWeb ? ` · ${counts.vip} VIP` : ''}
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
                {filtered.map(g => {
                  const x = extraOf(extras, g);
                  const vip = isVipGuest(g, x);
                  const double = isVipDouble(extras, g);
                  const link = x?.upgrade_token ? vipLink(siteUrl, x.upgrade_token) : null;
                  const plan = planningOf(planning, g);
                  const badges = planningBadges(plan, event, planning?.hours);
                  return (
                  <tr key={g.guest_id} data-guest={g.guest_id} className={g.status === 'cancelled' ? 'events-row-cancelled' : undefined}>
                    <td>
                      <strong>{g.name}</strong>
                      {(double || (x && (vip || x.vip_waiting || x.hold || x.signed_up_again || x.website))) && (
                        <div className="events-badges">
                          {vip && <span className="badge events-badge-vip" title={VIP_PERKS}><Crown size={11} /> VIP</span>}
                          {double && (
                            <span className="badge badge-danger events-badge-vip-double" data-vip-double
                              title="This customer holds two VIP payments for this event (paid or waiting). Refund one.">
                              {TWO_VIP_PAYMENTS}
                            </span>
                          )}
                          {!vip && x?.vip_waiting && (
                            <span className="badge badge-accent" title="A VIP payment of theirs waits on Website orders">
                              VIP waiting · {VIP_PROVIDER_LABELS[x.vip_waiting]}
                            </span>
                          )}
                          {/* 444 (the owner, 21 Oct 2026): a HitPay checkout opened and left without paying */}
                          {!vip && !x?.vip_waiting && x?.vip_checkout && g.status === 'registered' && (
                            <span className="badge badge-muted" data-vip-checkout
                              title="They opened the online payment (HitPay) for VIP and have not paid. An Owner or Manager may still close the registration; the checkout closes with it.">
                              {vipCheckoutText(x.vip_checkout)}
                            </span>
                          )}
                          {x?.hold && <span className="badge badge-danger" title="Waiting for staff to link them to a customer">To match</span>}
                          {/* 449 (the owner, 22 Oct 2026): taken off, then signed up again on the website: staff decide under To match */}
                          {x?.signed_up_again && g.status === 'cancelled' && (
                            <span className="badge badge-danger" data-signed-up-again
                              title={`${SIGNED_UP_AGAIN}${x.signed_up_again.days.length ? `, asking for ${fmtDayList(x.signed_up_again.days)}` : ''}. Put them back on the list (Restore, or To match above), or an Owner or Manager closes it there.`}>
                              Signed up again
                            </span>
                          )}
                          {x?.website && (
                            <span className="badge badge-muted" title={x.registration_id ? `${x.registration_id} · ${x.position} of ${x.group_size}` : undefined}>
                              Website
                            </span>
                          )}
                          {x?.gift && <span className="events-sub"> Gift: {x.gift.product_name}{x.gift.use_no ? ` · ${x.gift.use_no}` : ''}</span>}
                        </div>
                      )}
                      {badges.length > 0 && (
                        <div className="events-badges events-plan-badges" data-plan-badges>
                          {badges.map((b, i) => (
                            <span key={i} data-plan-badge={b.kind} title={b.title} aria-label={b.title} className={PLAN_BADGE_CLASS[b.kind]}>{b.text}</span>
                          ))}
                        </div>
                      )}
                      {vip && <div className="events-sub events-vip-perks">{VIP_PERKS}</div>}
                      {g.customer_id && <div className="events-sub">Customer: {g.customer_name ?? 'linked'}</div>}
                      {x?.referral?.note && <div className="events-sub" data-referral-note>{x.referral.note}</div>}
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
                          {planning && (hasWeb || plan) && (
                            <button className="btn btn-secondary btn-sm" title="Food, allergies, timing, talks…" aria-label={`Answers of ${g.name}`}
                              data-answers={g.guest_id} onClick={() => { setPlanNotice(null); setAnswering(g); }}>
                              <ClipboardList size={13} /> Answers
                            </button>
                          )}
                          {g.source === 'free' && g.status === 'registered' && (() => {
                            // 415: a day someone attended stays, so a guest who
                            // has checked in is not cancelled.
                            const checkedIn = g.days.some(d => d.attended_at);
                            return (
                              <button className="btn btn-secondary btn-sm" disabled={busyId === g.guest_id || checkedIn}
                                title={checkedIn ? 'Checked in. Undo the check-in first if they did not come.' : undefined}
                                onClick={() => setCancelling(g)}><UserX size={13} /> Cancel</button>
                            );
                          })()}
                          {g.source === 'free' && g.status === 'cancelled' && !x?.parked && (
                            <button className="btn btn-secondary btn-sm" disabled={busyId === g.guest_id}
                              onClick={() => void restore(g)}><RotateCcw size={13} /> Restore</button>
                          )}
                          {x?.upgrade_token && g.status === 'registered' && (
                            <button className="btn btn-secondary btn-sm" disabled={!link}
                              title={link ? 'Copy the link where they can buy VIP, to send on WhatsApp' : 'Set the website sync URL on the Website tab first'}
                              onClick={() => { if (link) void copyVipLink(g, link); }}><Copy size={13} /> Copy VIP link</button>
                          )}
                        </div>
                      )}
                    </td>
                  </tr>
                  );
                })}
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
      {answering && planning && (
        <GuestPlanningModal event={event} guest={answering} row={planningOf(planning, answering)} titles={planning.talk_titles}
          hours={planning.hours} canEdit={event.can_run} onClose={() => setAnswering(null)}
          onSaved={r => {
            setPlanNotice(r.changed ? `${answering.name}'s answers are saved.` : 'Nothing changed.');
            setAnswering(null);
            onPlanningSaved?.();
          }} />
      )}
      {cancelling && (
        <ReasonModal title={`Cancel ${cancelling.name}`} label="Reason (optional)" required={false}
          placeholder="e.g. Cannot come after all" confirmLabel="Cancel guest"
          onClose={() => setCancelling(null)}
          onSubmitAsync={reason => setCancelled(cancelling, true, reason || null)} />
      )}
    </div>
  );
};

export default GuestsTab;
