/**
 * Class (the Owner, 27 Nov 2026; migration 548): the four class vouchers, shown here and no longer on the
 * Vouchers page. For each class: its details and dates (from the poster), who bought it (read from live
 * invoices; a unit of a voucher line is a seat), the one date each seat chose where the class has dates to
 * choose from (skin care: at most 6 a date; the Lymphatic Class: no limit), and who attended each date.
 *
 * Who: every member of staff but an Inventory Manager sees the page and records dates and attendance for
 * the invoices of their stores (an Owner or Manager for every store). Only Owners and Managers add, change or
 * remove a date and edit the details. The database decides all of it again; this page only hides what a role
 * may not do and shows the database's sentence when a refusal gets through.
 *
 * The four vouchers left the Vouchers page, so their own Edit voucher (name, price, ...) and Prices (per store)
 * are here: the very same window and store-price editor the Vouchers page uses, for the same people
 * (Owners and Managers, as the Vouchers page and the database have it).
 */
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Modal, NoAccess } from '../components/ui';
import { canMakeInvoices } from '../lib/permissions/customers';
import { isOwnerOrManager, type Store } from '../types';
import StorePriceEditor from '../components/StorePriceEditor';
import { VoucherEditModal, type VoucherRow } from '../components/VoucherEditModal';
import { shownPhone } from '../lib/customers/shownPhone.mjs';
import { dayText } from '../lib/catalogue/pageRules.mjs';
import { GraduationCap, Plus, Pencil, Trash2, RefreshCw } from 'lucide-react';

interface ClassSession {
  id: string; seq: number; title: string; kind: 'lesson' | 'revision' | 'graduation' | 'class_day';
  session_date: string; starts_at: string | null; ends_at: string | null; mode: 'in_person' | 'zoom';
  venue: string | null; must_attend: boolean; taken: number;
}
interface ClassDetails { fee_note?: string; time_text?: string; venue_text?: string; format_text?: string; learn?: string[]; notes?: string[] }
interface ClassInfo {
  voucher_id: string; code: string; name: string; price: number; is_active: boolean;
  seat_mode: 'all_sessions' | 'choose_date'; capacity_per_date: number | null; sort_order: number;
  summary: string | null; details: ClassDetails; seats_sold: number; sessions: ClassSession[];
}
interface ClassSeat {
  voucher_id: string; invoice_item_id: string; seat_no: number; seats_on_line: number;
  invoice_id: string; invoice_no: string; invoice_status: string; business_date: string | null;
  store_id: string; store_name: string; customer_id: string | null; customer_name: string | null; customer_phone: string | null;
  session_id: string | null; attended: string[];
}
interface ClassPageData { can_edit: boolean; classes: ClassInfo[]; seats: ClassSeat[] }

const money = (n: number) => `S$${Number(n).toLocaleString('en-SG', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/** "Fri 29 Jan 2027", the weekday of the written date itself (no time zone shift). */
const dateText = (d: string) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(d);
  return m ? `${WEEKDAYS[new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).getDay()]} ${dayText(d)}` : d;
};
/** "8:00 PM" from "20:00:00". */
const clock = (t: string | null) => {
  const m = /^(\d{2}):(\d{2})/.exec(t ?? '');
  if (!m) return '';
  const h = Number(m[1]);
  return `${h % 12 === 0 ? 12 : h % 12}:${m[2]} ${h < 12 ? 'AM' : 'PM'}`;
};
const timeText = (s: ClassSession) => (s.starts_at && s.ends_at ? `${clock(s.starts_at)} – ${clock(s.ends_at)}` : clock(s.starts_at));
const where = (s: ClassSession) => (s.mode === 'zoom' ? 'Zoom' : s.venue ? `In person · ${s.venue}` : 'In person · venue to be confirmed');
const STATUS_TEXT: Record<string, string> = {
  unpaid: 'Unpaid', partially_paid: 'Part paid', paid: 'Paid', completed_foc: 'Free of charge',
  cancellation_requested: 'Cancellation requested', refund_requested: 'Refund requested',
};
const KIND_TEXT: Record<string, string> = { lesson: 'Lesson', revision: 'Revision & test', graduation: 'Graduation', class_day: 'Class day' };
const lines = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string' && x.trim() !== '') : []);

const blankSession = (c: ClassInfo, s?: ClassSession) => ({
  title: s?.title ?? (c.seat_mode === 'choose_date' ? 'Class day' : ''), kind: s?.kind ?? (c.seat_mode === 'choose_date' ? 'class_day' : 'lesson'),
  session_date: s?.session_date ?? '', starts_at: (s?.starts_at ?? '').slice(0, 5), ends_at: (s?.ends_at ?? '').slice(0, 5),
  mode: s?.mode ?? 'in_person', venue: s?.venue ?? '', must_attend: s?.must_attend ?? false,
});

const ClassPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below (an early return would change the number of hooks between renders).
  const hasAccess = canMakeInvoices(profile?.role);
  const [data, setData] = useState<ClassPageData | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [chosen, setChosen] = useState<string | null>(null);   // the class shown (voucher id)
  const [attendSession, setAttendSession] = useState<Record<string, string>>({});  // all-sessions class: the session being ticked
  const [search, setSearch] = useState('');
  const [sessionModal, setSessionModal] = useState<{ cls: ClassInfo; session: ClassSession | null } | null>(null);
  const [sessionForm, setSessionForm] = useState(blankSession({ seat_mode: 'choose_date' } as ClassInfo));
  const [detailsModal, setDetailsModal] = useState<ClassInfo | null>(null);
  const [detailsForm, setDetailsForm] = useState({ summary: '', fee_note: '', time_text: '', venue_text: '', format_text: '', learn: '', notes: '', capacity: '' });
  const [modalErr, setModalErr] = useState<string | null>(null);
  // The Vouchers page's own edit window and Prices editor, for the class's voucher (Owners and Managers).
  const mayEditVouchers = isOwnerOrManager(profile?.role);
  const [stores, setStores] = useState<Store[]>([]);
  const [voucherEdit, setVoucherEdit] = useState<VoucherRow | null>(null);
  const [pricesFor, setPricesFor] = useState<{ id: string; name: string } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data: d, error } = await supabase.rpc('class_page_data');
    if (error) { setLoadErr(error.message); setData(null); }
    else { setLoadErr(null); setData(d as ClassPageData); }
    setLoading(false);
  }, []);
  useEffect(() => { if (hasAccess) void load(); else setLoading(false); }, [load, hasAccess]);
  useEffect(() => {
    if (!hasAccess || !mayEditVouchers) return;
    void (async () => {
      const { data: st } = await supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name');
      setStores((st as Store[]) ?? []);
    })();
  }, [hasAccess, mayEditVouchers]);

  const classes = useMemo(() => data?.classes ?? [], [data]);
  const cls = classes.find(c => c.voucher_id === chosen) ?? classes[0] ?? null;
  const seats = useMemo(() => (data?.seats ?? []).filter(s => s.voucher_id === cls?.voucher_id), [data, cls]);
  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? seats.filter(s => `${s.customer_name ?? ''} ${s.customer_phone ?? ''} ${s.invoice_no}`.toLowerCase().includes(q)) : seats;
  }, [seats, search]);

  if (!hasAccess) return <NoAccess message="An Inventory Manager works with stock only." />;

  const run = async (key: string, fn: () => PromiseLike<{ error: { message: string } | null }>) => {
    setBusy(key); setErr(null);
    const { error } = await fn();
    setBusy(null);
    if (error) { setErr(error.message); return false; }
    await load();
    return true;
  };
  const chooseDate = (s: ClassSeat, sessionId: string) => run(`d:${s.invoice_item_id}:${s.seat_no}`, () =>
    supabase.rpc('class_choose_date', { p_invoice_item_id: s.invoice_item_id, p_seat_no: s.seat_no, p_session_id: sessionId || null }));
  const tick = (s: ClassSeat, sessionId: string, attended: boolean) => run(`a:${s.invoice_item_id}:${s.seat_no}`, () =>
    supabase.rpc('class_set_attendance', { p_session_id: sessionId, p_invoice_item_id: s.invoice_item_id, p_seat_no: s.seat_no, p_attended: attended }));

  const canEdit = !!data?.can_edit;
  const editVoucher = async (c: ClassInfo) => {
    setErr(null);
    const { data: row, error } = await supabase.from('vouchers').select('*').eq('id', c.voucher_id).maybeSingle();
    if (error || !row) { setErr(error?.message ?? 'The voucher could not be read.'); return; }
    setVoucherEdit(row as VoucherRow);
  };
  const openSession = (c: ClassInfo, s: ClassSession | null) => { setSessionForm(blankSession(c, s ?? undefined)); setModalErr(null); setSessionModal({ cls: c, session: s }); };
  const saveSession = async () => {
    if (!sessionModal) return;
    const f = sessionForm;
    if (!f.session_date) { setModalErr('Choose the day.'); return; }
    if (!f.title.trim()) { setModalErr('Give the date a title.'); return; }
    setBusy('session'); setModalErr(null);
    const { error } = await supabase.rpc('class_save_session', {
      p_voucher_id: sessionModal.cls.voucher_id, p_session_id: sessionModal.session?.id ?? null,
      p_data: { title: f.title.trim(), kind: f.kind, session_date: f.session_date, starts_at: f.starts_at || null, ends_at: f.ends_at || null,
        mode: f.mode, venue: f.venue.trim() || null, must_attend: f.must_attend },
    });
    setBusy(null);
    if (error) { setModalErr(error.message); return; }
    setSessionModal(null); await load();
  };
  const removeSession = async (c: ClassInfo, s: ClassSession) => {
    if (!window.confirm(`Remove the date ${dateText(s.session_date)} from ${c.name}?`)) return;
    await run(`rm:${s.id}`, () => supabase.rpc('class_remove_session', { p_session_id: s.id }));
  };
  const openDetails = (c: ClassInfo) => {
    const d = c.details ?? {};
    setDetailsForm({ summary: c.summary ?? '', fee_note: d.fee_note ?? '', time_text: d.time_text ?? '', venue_text: d.venue_text ?? '',
      format_text: d.format_text ?? '', learn: lines(d.learn).join('\n'), notes: lines(d.notes).join('\n'), capacity: c.capacity_per_date == null ? '' : String(c.capacity_per_date) });
    setModalErr(null); setDetailsModal(c);
  };
  const saveDetails = async () => {
    if (!detailsModal) return;
    const f = detailsForm;
    const split = (t: string) => t.split('\n').map(x => x.trim()).filter(Boolean);
    const details: Record<string, unknown> = {};
    if (f.fee_note.trim()) details.fee_note = f.fee_note.trim();
    if (f.time_text.trim()) details.time_text = f.time_text.trim();
    if (f.venue_text.trim()) details.venue_text = f.venue_text.trim();
    if (f.format_text.trim()) details.format_text = f.format_text.trim();
    if (split(f.learn).length) details.learn = split(f.learn);
    if (split(f.notes).length) details.notes = split(f.notes);
    const body: Record<string, unknown> = { summary: f.summary.trim(), details };
    if (detailsModal.seat_mode === 'choose_date') {
      if (f.capacity.trim() !== '' && !/^[1-9][0-9]*$/.test(f.capacity.trim())) { setModalErr('The capacity is a whole number of seats, or empty for no limit.'); return; }
      body.capacity_per_date = f.capacity.trim() === '' ? null : Number(f.capacity.trim());
    }
    setBusy('details'); setModalErr(null);
    const { error } = await supabase.rpc('class_save_details', { p_voucher_id: detailsModal.voucher_id, p_data: body });
    setBusy(null);
    if (error) { setModalErr(error.message); return; }
    setDetailsModal(null); await load();
  };

  // The session being ticked for an all-sessions class: the one picked, else the next one on or after today, else the last.
  const todayIso = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });
  const sessionToTick = (c: ClassInfo): ClassSession | null => {
    const picked = c.sessions.find(s => s.id === attendSession[c.voucher_id]);
    return picked ?? c.sessions.find(s => s.session_date >= todayIso) ?? c.sessions[c.sessions.length - 1] ?? null;
  };

  const classHeader = (c: ClassInfo) => {
    const d = c.details ?? {};
    return (
      <div className="card" style={{ padding: 16, marginBottom: 14 }} data-testid="class-details">
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
          <div style={{ minWidth: 0 }}>
            <h3 style={{ fontSize: 17, margin: 0 }}>{c.name}</h3>
            {c.summary && <p style={{ color: 'var(--text-muted)', margin: '2px 0 0', fontSize: 13 }}>{c.summary}</p>}
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontWeight: 700, fontSize: 16 }}>{money(c.price)}</div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{c.code} · {c.seats_sold} {c.seats_sold === 1 ? 'seat' : 'seats'} sold (all stores)</div>
          </div>
        </div>
        <dl style={{ margin: '12px 0 0', display: 'grid', gridTemplateColumns: 'minmax(90px, max-content) 1fr', gap: '4px 14px', fontSize: 13 }}>
          {d.fee_note && <><dt style={{ color: 'var(--text-muted)' }}>Fee</dt><dd style={{ margin: 0 }}>{d.fee_note}</dd></>}
          {d.time_text && <><dt style={{ color: 'var(--text-muted)' }}>When</dt><dd style={{ margin: 0 }}>{d.time_text}</dd></>}
          {d.venue_text && <><dt style={{ color: 'var(--text-muted)' }}>Where</dt><dd style={{ margin: 0 }}>{d.venue_text}</dd></>}
          {d.format_text && <><dt style={{ color: 'var(--text-muted)' }}>How</dt><dd style={{ margin: 0 }}>{d.format_text}</dd></>}
          {c.capacity_per_date != null && <><dt style={{ color: 'var(--text-muted)' }}>Capacity</dt><dd style={{ margin: 0 }}>At most {c.capacity_per_date} seats on each date</dd></>}
          {lines(d.learn).length > 0 && <><dt style={{ color: 'var(--text-muted)' }}>You learn</dt><dd style={{ margin: 0 }}>{lines(d.learn).join(' · ')}</dd></>}
          {lines(d.notes).length > 0 && <><dt style={{ color: 'var(--text-muted)' }}>Notes</dt><dd style={{ margin: 0 }}>{lines(d.notes).map((n, i) => <div key={i}>{n}</div>)}</dd></>}
        </dl>
        {(canEdit || mayEditVouchers) && (
          <div style={{ marginTop: 12, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {canEdit && <button className="btn btn-secondary btn-sm" onClick={() => openDetails(c)}><Pencil size={13} /> Edit details</button>}
            {mayEditVouchers && <button className="btn btn-secondary btn-sm" onClick={() => void editVoucher(c)}><Pencil size={13} /> Edit voucher</button>}
            {mayEditVouchers && <button className="btn btn-secondary btn-sm" title="Per-store selling prices" onClick={() => setPricesFor({ id: c.voucher_id, name: c.name })}>Prices</button>}
          </div>
        )}
      </div>
    );
  };

  const schedule = (c: ClassInfo) => (
    <div className="card" style={{ marginBottom: 14 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 16px 0' }}>
        <h3 style={{ fontSize: 15, margin: 0 }}>{c.seat_mode === 'choose_date' ? 'Dates to choose from' : 'Sessions'}</h3>
        {canEdit && <button className="btn btn-secondary btn-sm" onClick={() => openSession(c, null)}><Plus size={13} /> Add date</button>}
      </div>
      <div className="table-wrap">
        {c.sessions.length === 0
          ? <div className="empty-state" style={{ padding: 20 }}><p style={{ margin: 0 }}>No dates yet.{canEdit ? ' Add the dates a seat can choose from.' : ' An Owner or Manager adds them.'}</p></div>
          : (
            <table data-testid="class-sessions">
              <thead><tr><th>Date</th><th>Session</th><th>Time</th><th>Where</th>{c.seat_mode === 'choose_date' && <th>Seats taken</th>}{canEdit && <th></th>}</tr></thead>
              <tbody>
                {c.sessions.map(s => (
                  <tr key={s.id}>
                    <td><strong>{dateText(s.session_date)}</strong></td>
                    <td>{s.title}{s.kind !== 'lesson' && s.kind !== 'class_day' && <span className="badge badge-muted" style={{ marginLeft: 6 }}>{KIND_TEXT[s.kind]}</span>}
                      {s.must_attend && <span className="badge badge-accent" style={{ marginLeft: 6 }}>Must attend</span>}</td>
                    <td style={{ fontSize: 12.5 }}>{timeText(s)}</td>
                    <td style={{ fontSize: 12.5 }}>{where(s)}</td>
                    {c.seat_mode === 'choose_date' && <td>{s.taken}{c.capacity_per_date != null ? ` of ${c.capacity_per_date}` : ''}
                      {c.capacity_per_date != null && s.taken >= c.capacity_per_date && <span className="badge badge-danger" style={{ marginLeft: 6 }}>Full</span>}</td>}
                    {canEdit && <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm btn-icon" aria-label={`Edit ${dateText(s.session_date)}`} onClick={() => openSession(c, s)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" aria-label={`Remove ${dateText(s.session_date)}`} onClick={() => removeSession(c, s)}><Trash2 size={13} /></button>
                    </div></td>}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
      </div>
    </div>
  );

  const buyers = (c: ClassInfo) => {
    const tickSession = c.seat_mode === 'all_sessions' ? sessionToTick(c) : null;
    return (
      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, flexWrap: 'wrap', padding: '12px 16px 0' }}>
          <h3 style={{ fontSize: 15, margin: 0 }}>Who bought it <span style={{ fontWeight: 400, color: 'var(--text-muted)', fontSize: 13 }}>({seats.length} {seats.length === 1 ? 'seat' : 'seats'} shown)</span></h3>
          <input aria-label="Search buyers" value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name, phone or invoice…" style={{ maxWidth: 280 }} />
        </div>
        {tickSession && (
          <div style={{ padding: '10px 16px 0', display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
            <label htmlFor="class-tick-session" style={{ fontSize: 13 }}>Tick attendance for</label>
            <select id="class-tick-session" value={tickSession.id} onChange={e => setAttendSession(a => ({ ...a, [c.voucher_id]: e.target.value }))} style={{ maxWidth: 320 }}>
              {c.sessions.map(s => <option key={s.id} value={s.id}>{dateText(s.session_date)} · {s.title}</option>)}
            </select>
          </div>
        )}
        <div className="table-wrap">
          {loading && !data ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : shown.length === 0 ? <div className="empty-state" style={{ padding: 24 }}><p style={{ margin: 0 }}>{seats.length === 0 ? 'Nobody you can see has bought this class yet.' : 'No buyer matches the search.'}</p></div>
          : (
            <table data-testid="class-seats">
              <thead><tr><th>Customer</th><th>Invoice</th><th>Seat</th>
                {c.seat_mode === 'choose_date' ? <><th>Chosen date</th><th>Attended</th></> : <th>{tickSession ? `Attended ${dateText(tickSession.session_date)}` : 'Attended'}</th>}</tr></thead>
              <tbody>
                {shown.map(s => {
                  const key = `${s.invoice_item_id}:${s.seat_no}`;
                  const phone = shownPhone(s.customer_phone);
                  const onChosen = s.session_id != null && s.attended.includes(s.session_id);
                  return (
                    <tr key={key} data-testid="class-seat">
                      <td><strong>{s.customer_name ?? '—'}</strong>{phone && <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{phone}</div>}</td>
                      <td style={{ fontSize: 12.5 }}>{s.invoice_no}<div style={{ color: 'var(--text-muted)' }}>{STATUS_TEXT[s.invoice_status] ?? s.invoice_status} · {s.store_name}</div></td>
                      <td>{s.seat_no} of {s.seats_on_line}</td>
                      {c.seat_mode === 'choose_date' ? (
                        <>
                          <td>
                            <select aria-label={`Date for ${s.customer_name ?? 'customer'}, seat ${s.seat_no} of ${s.seats_on_line}, ${s.invoice_no}`}
                              value={s.session_id ?? ''} disabled={busy === `d:${key}`} style={{ minWidth: 190 }}
                              onChange={e => void chooseDate(s, e.target.value)}>
                              <option value="">{c.sessions.length === 0 ? 'No dates yet' : 'Not chosen yet'}</option>
                              {c.sessions.map(x => {
                                const full = c.capacity_per_date != null && x.taken >= c.capacity_per_date && x.id !== s.session_id;
                                return <option key={x.id} value={x.id} disabled={full}>{dateText(x.session_date)}{c.capacity_per_date != null ? ` · ${x.taken} of ${c.capacity_per_date}${full ? ' (full)' : ''}` : ` · ${x.taken} chosen`}</option>;
                              })}
                            </select>
                          </td>
                          <td><label style={{ display: 'inline-flex', gap: 6, alignItems: 'center', fontWeight: 400 }}>
                            <input type="checkbox" style={{ width: 'auto' }} checked={onChosen} disabled={!s.session_id || busy === `a:${key}`}
                              aria-label={`Attended, ${s.customer_name ?? 'customer'}, seat ${s.seat_no}, ${s.invoice_no}`}
                              onChange={e => s.session_id && void tick(s, s.session_id, e.target.checked)} /></label></td>
                        </>
                      ) : (
                        <td><label style={{ display: 'inline-flex', gap: 6, alignItems: 'center', fontWeight: 400 }}>
                          <input type="checkbox" style={{ width: 'auto' }} disabled={!tickSession || busy === `a:${key}`}
                            checked={!!tickSession && s.attended.includes(tickSession.id)}
                            aria-label={`Attended, ${s.customer_name ?? 'customer'}, seat ${s.seat_no}, ${s.invoice_no}`}
                            onChange={e => tickSession && void tick(s, tickSession.id, e.target.checked)} />
                          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{s.attended.length} of {c.sessions.length} sessions</span></label></td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>
    );
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Class</h2><p>The classes and workshops: their dates, who bought each, the date each seat chose and who attended.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={() => void load()}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
        </div>
      </div>

      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
      {loadErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>The Class page could not be loaded: {loadErr}</div></div>}

      {classes.length > 0 && (
        <div role="tablist" aria-label="Classes" style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 14 }}>
          {classes.map(c => (
            <button key={c.voucher_id} role="tab" aria-selected={cls?.voucher_id === c.voucher_id}
              className={`btn btn-sm ${cls?.voucher_id === c.voucher_id ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => { setChosen(c.voucher_id); setSearch(''); }}>{c.name}</button>
          ))}
        </div>
      )}

      {!loading && !loadErr && classes.length === 0 && (
        <div className="card"><div className="empty-state"><GraduationCap size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No classes yet</p></div></div>
      )}

      {cls && <>{classHeader(cls)}{schedule(cls)}{buyers(cls)}</>}

      {voucherEdit && <VoucherEditModal voucher={voucherEdit} onClose={() => setVoucherEdit(null)} onChanged={() => void load()} />}
      {pricesFor && <StorePriceEditor kind="voucher" targetId={pricesFor.id} targetName={pricesFor.name} stores={stores} onClose={() => setPricesFor(null)} />}

      {sessionModal && (
        <Modal title={sessionModal.session ? 'Change date' : 'Add date'} maxWidth={520} onClose={() => setSessionModal(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setSessionModal(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={() => void saveSession()} disabled={busy === 'session'}>{busy === 'session' ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {modalErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{modalErr}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label htmlFor="cs-date">Day *</label>
                <input id="cs-date" type="date" value={sessionForm.session_date} onChange={e => setSessionForm(f => ({ ...f, session_date: e.target.value }))} /></div>
              <div className="form-group"><label htmlFor="cs-title">Title *</label>
                <input id="cs-title" value={sessionForm.title} onChange={e => setSessionForm(f => ({ ...f, title: e.target.value }))} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label htmlFor="cs-start">Starts</label>
                <input id="cs-start" type="time" value={sessionForm.starts_at} onChange={e => setSessionForm(f => ({ ...f, starts_at: e.target.value }))} /></div>
              <div className="form-group"><label htmlFor="cs-end">Ends</label>
                <input id="cs-end" type="time" value={sessionForm.ends_at} onChange={e => setSessionForm(f => ({ ...f, ends_at: e.target.value }))} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label htmlFor="cs-kind">Kind</label>
                <select id="cs-kind" value={sessionForm.kind} onChange={e => setSessionForm(f => ({ ...f, kind: e.target.value as ClassSession['kind'] }))}>
                  {Object.entries(KIND_TEXT).map(([k, t]) => <option key={k} value={k}>{t}</option>)}
                </select></div>
              <div className="form-group"><label htmlFor="cs-mode">Held</label>
                <select id="cs-mode" value={sessionForm.mode} onChange={e => setSessionForm(f => ({ ...f, mode: e.target.value as ClassSession['mode'] }))}>
                  <option value="in_person">In person</option><option value="zoom">On Zoom</option>
                </select></div>
            </div>
            <div className="form-group"><label htmlFor="cs-venue">Venue (in person)</label>
              <input id="cs-venue" value={sessionForm.venue} onChange={e => setSessionForm(f => ({ ...f, venue: e.target.value }))} placeholder="Empty = to be confirmed" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 400 }}>
              <input type="checkbox" style={{ width: 'auto' }} checked={sessionForm.must_attend} onChange={e => setSessionForm(f => ({ ...f, must_attend: e.target.checked }))} />
              <span style={{ fontSize: 13 }}>Must attend</span></label>
          </div>
        </Modal>
      )}

      {detailsModal && (
        <Modal title={`Edit details · ${detailsModal.name}`} maxWidth={560} onClose={() => setDetailsModal(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setDetailsModal(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={() => void saveDetails()} disabled={busy === 'details'}>{busy === 'details' ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {modalErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{modalErr}</div></div>}
            <div className="form-group"><label htmlFor="cd-summary">Summary</label>
              <input id="cd-summary" value={detailsForm.summary} onChange={e => setDetailsForm(f => ({ ...f, summary: e.target.value }))} /></div>
            <div className="form-group"><label htmlFor="cd-fee">Fee</label>
              <input id="cd-fee" value={detailsForm.fee_note} onChange={e => setDetailsForm(f => ({ ...f, fee_note: e.target.value }))} /></div>
            <div className="form-grid-2">
              <div className="form-group"><label htmlFor="cd-time">When</label>
                <input id="cd-time" value={detailsForm.time_text} onChange={e => setDetailsForm(f => ({ ...f, time_text: e.target.value }))} /></div>
              <div className="form-group"><label htmlFor="cd-venue">Where</label>
                <input id="cd-venue" value={detailsForm.venue_text} onChange={e => setDetailsForm(f => ({ ...f, venue_text: e.target.value }))} /></div>
            </div>
            <div className="form-group"><label htmlFor="cd-format">How</label>
              <textarea id="cd-format" rows={2} value={detailsForm.format_text} onChange={e => setDetailsForm(f => ({ ...f, format_text: e.target.value }))} /></div>
            <div className="form-group"><label htmlFor="cd-learn">You learn (one per line)</label>
              <textarea id="cd-learn" rows={3} value={detailsForm.learn} onChange={e => setDetailsForm(f => ({ ...f, learn: e.target.value }))} /></div>
            <div className="form-group"><label htmlFor="cd-notes">Notes (one per line)</label>
              <textarea id="cd-notes" rows={3} value={detailsForm.notes} onChange={e => setDetailsForm(f => ({ ...f, notes: e.target.value }))} /></div>
            {detailsModal.seat_mode === 'choose_date' && (
              <div className="form-group"><label htmlFor="cd-cap">Seats per date (empty = no limit)</label>
                <input id="cd-cap" inputMode="numeric" value={detailsForm.capacity} onChange={e => setDetailsForm(f => ({ ...f, capacity: e.target.value }))} /></div>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
};

export default ClassPage;
