import { INVOICE_STATUS_LABELS, InvoiceStatus } from '../../types';
import { calendarDate } from '../../lib/calendarDates';

/*
 * Events: the shapes the server returns (370_events.sql) and the few rules the
 * page applies to them. Numbers can arrive as numbers or numeric strings, so
 * every row passes through a normaliser before the page touches it.
 */

export interface EventDay { day: string; capacity: number | null; registered: number; attended: number; }
export interface EventStore { id: string; name: string; }
export interface EventOption {
  id: string; name: string; days_count: number; price: number; is_active: boolean;
  sort_order: number; early_bird_price: number | null; sold: boolean;
}
export interface EventRow {
  id: string; name: string; description: string | null;
  daily_start: string | null; daily_end: string | null;
  early_bird_until: string | null; early_bird_percent: number | null;
  is_active: boolean; notes: string | null; created_at: string | null;
  first_day: string | null; last_day: string | null;
  days: EventDay[]; stores: EventStore[]; options: EventOption[];
  guests: number; ticket_guests: number; free_guests: number;
  can_manage: boolean; can_run: boolean;
}

export type GuestSource = 'ticket' | 'free';
export type GuestStatus = 'registered' | 'cancelled';
export interface GuestDay {
  day: string; attended_at: string | null; check_in_code: string | null; checked_in_by_name: string | null;
}
export interface Guest {
  guest_id: string; name: string; phone: string | null;
  customer_id: string | null; customer_name: string | null;
  source: GuestSource; status: GuestStatus; cancelled_reason: string | null; notes: string | null;
  registered_by: string | null; registered_by_name: string | null;
  ticket_option_id: string | null; ticket_option_name: string | null;
  invoice_id: string | null; invoice_no: string | null; invoice_status: string | null;
  invoice_total: number | null; invoice_paid: number | null; invoice_store_id: string | null;
  created_at: string | null; days: GuestDay[];
}

export type SaleSource = 'event_day' | 'ticket' | 'staff';
export interface EventInvoice {
  invoice_id: string; invoice_no: string; business_date: string | null;
  store_id: string | null; store_name: string | null;
  customer_id: string | null; customer_name: string | null;
  status: string; total_amount: number; paid_amount: number; source: SaleSource;
  ticket_people: number; ticket_total: number;
}

export interface OverCapacity { day: string; capacity: number; registered: number; }
export interface StaffOption { id: string; full_name: string; role: string; }
export interface StoreOption { id: string; name: string; }

// Website orders (372_website_orders_become_invoices.sql): tickets bought on
// the event's website, recorded at payment and made into invoices.
export type WebOrderMode = 'off' | 'record_only' | 'live';
export type WebOrderStatus = 'invoiced' | 'recorded' | 'needs_review' | 'refused';
export interface WebOrderChannel {
  key: string; mode: WebOrderMode; allow_test: boolean;
  store_name: string | null; acting_name: string | null; payment_method_name: string | null;
}
export interface WebOrderPerson { name: string; email: string | null; whatsapp: string | null; }
export interface WebOrderCandidate {
  customer_id: string; full_name: string; phone: string | null; email: string | null; last_invoice_at: string | null;
}
export interface WebOrder {
  id: string; stripe_session_id: string; livemode: boolean; status: WebOrderStatus;
  ticket: string; ticket_label: string; quantity: number; unit_amount: number; amount_total: number; early_bird: boolean;
  buyer_name: string; buyer_email: string | null; buyer_phone: string | null;
  checkout_opened_at: string | null; paid_at: string | null;
  attendees: WebOrderPerson[] | null; names_at: string | null;
  invoice_id: string | null; invoice_no: string | null; review_reason: string | null;
  candidates: WebOrderCandidate[]; created_at: string | null;
}
export interface WebOrderList { channel: WebOrderChannel | null; can_switch: boolean; orders: WebOrder[]; }
/** What web_order_resolve answers. */
export interface WebOrderOutcome { status: WebOrderStatus; invoice_no: string | null; review_reason: string | null; }

// ── normalisers ────────────────────────────────────────────────────────────
const num = (v: unknown): number => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const numOrNull = (v: unknown): number | null => {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v); return Number.isFinite(n) ? n : null;
};
const str = (v: unknown): string | null => (v === null || v === undefined || v === '' ? null : String(v));
const dateOnly = (v: unknown): string | null => (v ? String(v).slice(0, 10) : null);
const hhmm = (v: unknown): string | null => (v ? String(v).slice(0, 5) : null);
const arr = (v: unknown): any[] => (Array.isArray(v) ? v : []);

export function normalizeEvent(r: any): EventRow {
  const days: EventDay[] = arr(r?.days).map(d => ({
    day: dateOnly(d?.day) ?? '', capacity: numOrNull(d?.capacity),
    registered: num(d?.registered), attended: num(d?.attended),
  })).filter(d => d.day).sort((a, b) => a.day.localeCompare(b.day));
  return {
    id: String(r?.id ?? ''), name: String(r?.name ?? ''), description: str(r?.description),
    daily_start: hhmm(r?.daily_start), daily_end: hhmm(r?.daily_end),
    early_bird_until: dateOnly(r?.early_bird_until), early_bird_percent: numOrNull(r?.early_bird_percent),
    is_active: !!r?.is_active, notes: str(r?.notes), created_at: str(r?.created_at),
    first_day: dateOnly(r?.first_day) ?? days[0]?.day ?? null,
    last_day: dateOnly(r?.last_day) ?? (days.length ? days[days.length - 1].day : null),
    days,
    stores: arr(r?.stores).map(s => ({ id: String(s?.id ?? ''), name: String(s?.name ?? '') })),
    options: arr(r?.options).map(o => ({
      id: String(o?.id ?? ''), name: String(o?.name ?? ''), days_count: num(o?.days_count), price: num(o?.price),
      is_active: !!o?.is_active, sort_order: num(o?.sort_order), early_bird_price: numOrNull(o?.early_bird_price),
      sold: !!o?.sold,
    })).sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name)),
    guests: num(r?.guests), ticket_guests: num(r?.ticket_guests), free_guests: num(r?.free_guests),
    can_manage: !!r?.can_manage, can_run: r?.can_run === undefined ? true : !!r?.can_run,
  };
}

export function normalizeGuestDay(d: any): GuestDay {
  return {
    day: dateOnly(d?.day) ?? '', attended_at: str(d?.attended_at),
    check_in_code: str(d?.check_in_code), checked_in_by_name: str(d?.checked_in_by_name),
  };
}

export function normalizeGuest(r: any): Guest {
  return {
    guest_id: String(r?.guest_id ?? ''), name: String(r?.name ?? ''), phone: str(r?.phone),
    customer_id: str(r?.customer_id), customer_name: str(r?.customer_name),
    source: r?.source === 'ticket' ? 'ticket' : 'free',
    status: r?.status === 'cancelled' ? 'cancelled' : 'registered',
    cancelled_reason: str(r?.cancelled_reason), notes: str(r?.notes),
    registered_by: str(r?.registered_by), registered_by_name: str(r?.registered_by_name),
    ticket_option_id: str(r?.ticket_option_id), ticket_option_name: str(r?.ticket_option_name),
    invoice_id: str(r?.invoice_id), invoice_no: str(r?.invoice_no), invoice_status: str(r?.invoice_status),
    invoice_total: numOrNull(r?.invoice_total), invoice_paid: numOrNull(r?.invoice_paid),
    invoice_store_id: str(r?.invoice_store_id), created_at: str(r?.created_at),
    days: arr(r?.days).map(normalizeGuestDay).filter(d => d.day).sort((a, b) => a.day.localeCompare(b.day)),
  };
}

export function normalizeInvoice(r: any): EventInvoice {
  const source = r?.source === 'ticket' || r?.source === 'staff' ? r.source : 'event_day';
  return {
    invoice_id: String(r?.invoice_id ?? ''), invoice_no: String(r?.invoice_no ?? ''),
    business_date: dateOnly(r?.business_date), store_id: str(r?.store_id), store_name: str(r?.store_name),
    customer_id: str(r?.customer_id), customer_name: str(r?.customer_name), status: String(r?.status ?? ''),
    total_amount: num(r?.total_amount), paid_amount: num(r?.paid_amount), source,
    ticket_people: num(r?.ticket_people), ticket_total: num(r?.ticket_total),
  };
}

export function normalizeOverCapacity(v: unknown): OverCapacity[] {
  return arr(v).map(o => ({ day: dateOnly(o?.day) ?? '', capacity: num(o?.capacity), registered: num(o?.registered) }))
    .filter(o => o.day);
}

const WEB_ORDER_MODES: WebOrderMode[] = ['off', 'record_only', 'live'];
const WEB_ORDER_STATUSES: WebOrderStatus[] = ['invoiced', 'recorded', 'needs_review', 'refused'];
const webOrderMode = (v: unknown): WebOrderMode => (WEB_ORDER_MODES.includes(v as WebOrderMode) ? v as WebOrderMode : 'off');
// A status the page does not know is shown as needing a look, never as done.
const webOrderStatus = (v: unknown): WebOrderStatus =>
  (WEB_ORDER_STATUSES.includes(v as WebOrderStatus) ? v as WebOrderStatus : 'needs_review');

export function normalizeWebOrder(r: any): WebOrder {
  return {
    id: String(r?.id ?? ''), stripe_session_id: String(r?.stripe_session_id ?? ''), livemode: r?.livemode === true,
    status: webOrderStatus(r?.status), ticket: String(r?.ticket ?? ''),
    ticket_label: str(r?.ticket_label) ?? String(r?.ticket ?? ''),
    quantity: num(r?.quantity), unit_amount: num(r?.unit_amount), amount_total: num(r?.amount_total),
    early_bird: !!r?.early_bird,
    buyer_name: String(r?.buyer_name ?? ''), buyer_email: str(r?.buyer_email), buyer_phone: str(r?.buyer_phone),
    checkout_opened_at: str(r?.checkout_opened_at), paid_at: str(r?.paid_at),
    // Null until the buyer registers the names.
    attendees: Array.isArray(r?.attendees)
      ? r.attendees.map((a: any) => ({ name: String(a?.name ?? ''), email: str(a?.email), whatsapp: str(a?.whatsapp) }))
      : null,
    names_at: str(r?.names_at),
    invoice_id: str(r?.invoice_id), invoice_no: str(r?.invoice_no), review_reason: str(r?.review_reason),
    candidates: arr(r?.candidates).map(c => ({
      customer_id: String(c?.customer_id ?? ''), full_name: String(c?.full_name ?? ''), phone: str(c?.phone),
      email: str(c?.email), last_invoice_at: str(c?.last_invoice_at),
    })).filter(c => c.customer_id),
    created_at: str(r?.created_at),
  };
}

export function normalizeWebOrderList(v: any): WebOrderList {
  const c = v?.channel;
  return {
    channel: c && typeof c === 'object' ? {
      key: String(c.key ?? ''), mode: webOrderMode(c.mode), allow_test: !!c.allow_test,
      store_name: str(c.store_name), acting_name: str(c.acting_name), payment_method_name: str(c.payment_method_name),
    } : null,
    can_switch: v?.can_switch === true,
    orders: arr(v?.orders).map(normalizeWebOrder),
  };
}

export function normalizeWebOrderOutcome(v: any): WebOrderOutcome {
  return { status: webOrderStatus(v?.status), invoice_no: str(v?.invoice_no), review_reason: str(v?.review_reason) };
}

// ── formatting ─────────────────────────────────────────────────────────────
// Dates are calendar days, never instants: they are split by hand so no time
// zone can move them a day.
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function dayParts(d: string) {
  const [y, m, dd] = d.split('-').map(Number);
  const wd = new Date(Date.UTC(y, (m || 1) - 1, dd || 1)).getUTCDay();
  return { y, m: (m || 1) - 1, d: dd || 1, wd };
}

/** "Mon 19 Oct 2026" */
export function fmtDate(d: string | null | undefined): string {
  if (!d) return '—';
  const p = dayParts(d);
  return `${WEEKDAYS[p.wd]} ${p.d} ${MONTHS[p.m]} ${p.y}`;
}
/** "Mon 19 Oct" */
export function fmtWeekday(d: string): string {
  const p = dayParts(d);
  return `${WEEKDAYS[p.wd]} ${p.d} ${MONTHS[p.m]}`;
}
/** "19 Oct" */
export function fmtDayMonth(d: string): string {
  const p = dayParts(d);
  return `${p.d} ${MONTHS[p.m]}`;
}
/** "Mon 19 Oct & Tue 20 Oct 2026" — the year once when every day shares it. */
export function fmtDayList(days: string[]): string {
  if (days.length === 0) return 'No days set';
  const sorted = [...days].sort();
  const sameYear = sorted.every(d => d.slice(0, 4) === sorted[0].slice(0, 4));
  const parts = sameYear ? sorted.map(fmtWeekday) : sorted.map(fmtDate);
  const joined = parts.length === 1 ? parts[0]
    : `${parts.slice(0, -1).join(', ')} & ${parts[parts.length - 1]}`;
  return sameYear ? `${joined} ${sorted[0].slice(0, 4)}` : joined;
}
export function fmtHours(start: string | null, end: string | null): string {
  if (!start && !end) return '';
  return `${start ?? '?'}–${end ?? '?'}`;
}

const timeFormat = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Singapore', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
/** The Singapore clock time of a timestamp, "10:32". */
export function fmtTime(ts: string | null | undefined): string {
  if (!ts) return '';
  const d = new Date(ts);
  return Number.isFinite(d.getTime()) ? timeFormat.format(d) : '';
}
/** The Singapore day and clock time of a timestamp, "Mon 5 Oct 2026, 14:30". */
export function fmtDateTime(ts: string | null | undefined): string {
  const day = calendarDate(ts, 'Asia/Singapore');
  return day ? `${fmtDate(day)}, ${fmtTime(ts)}` : '—';
}
/** The Singapore day of a date or a timestamp, "Mon 5 Oct 2026". */
export function fmtSgDate(v: string | null | undefined): string {
  return fmtDate(calendarDate(v, 'Asia/Singapore') || null);
}
/** A timestamp for a spreadsheet, where it sorts: "2026-10-05 14:30". */
export function sgStamp(ts: string | null | undefined): string {
  const day = calendarDate(ts, 'Asia/Singapore');
  return day ? `${day} ${fmtTime(ts)}` : '';
}

export const money = (n: number | null | undefined) => `S$${Number(n ?? 0).toFixed(2)}`;

/** The early-bird price, rounded to the cent as the server rounds it. */
export function earlyBirdPrice(price: number, percent: number): number {
  return Math.round(Number((price * (100 - percent)).toFixed(6))) / 100;
}

export type EventStatus = 'on_sale' | 'off_sale' | 'ended';
export function eventStatus(e: Pick<EventRow, 'last_day' | 'is_active'>, today: string): EventStatus {
  if (e.last_day && e.last_day < today) return 'ended';
  return e.is_active ? 'on_sale' : 'off_sale';
}
export const STATUS_BADGE: Record<EventStatus, { label: string; cls: string }> = {
  on_sale: { label: 'On sale', cls: 'badge badge-success' },
  off_sale: { label: 'Off sale', cls: 'badge badge-accent' },
  ended: { label: 'Ended', cls: 'badge badge-muted' },
};

export function invoiceStatusLabel(status: string | null | undefined): string {
  if (!status) return '';
  return INVOICE_STATUS_LABELS[status as InvoiceStatus] ?? status;
}
/** How a ticket stands: Paid, Part-paid or Unpaid, else the invoice's status. */
export function paymentLabel(status: string | null | undefined): string {
  switch (status) {
    case 'paid': return 'Paid';
    case 'partially_paid': return 'Part-paid';
    case 'unpaid': return 'Unpaid';
    case 'completed_foc': return 'FOC';
    default: return invoiceStatusLabel(status) || '—';
  }
}
export function paymentTone(status: string | null | undefined): 'ok' | 'warn' | 'bad' | 'muted' {
  if (status === 'paid' || status === 'completed_foc') return 'ok';
  if (status === 'partially_paid') return 'warn';
  if (status === 'unpaid' || status === 'draft') return 'bad';
  return 'muted';
}

export const SALE_SOURCE_LABELS: Record<SaleSource, string> = {
  event_day: 'Event day', ticket: 'Ticket', staff: 'Marked by staff',
};

/** Statuses left out of the Sales totals. */
export const NOT_COUNTED_STATUSES = ['cancelled', 'refunded'];

export interface DayLoad { day: string; capacity: number | null; registered: number; attended: number; }
/**
 * People registered and checked in per day. Once the guest list is loaded it
 * is counted from the list, so the numbers follow every change on screen;
 * until then the event's own counts are used.
 */
export function dayLoads(event: EventRow, guests: Guest[] | null): DayLoad[] {
  if (!guests) return event.days.map(d => ({ ...d }));
  return event.days.map(d => {
    let registered = 0, attended = 0;
    for (const g of guests) {
      if (g.status !== 'registered') continue;
      const gd = g.days.find(x => x.day === d.day);
      if (!gd) continue;
      registered++;
      if (gd.attended_at) attended++;
    }
    return { day: d.day, capacity: d.capacity, registered, attended };
  });
}
export type LoadTone = 'open' | 'full' | 'over';
export function loadTone(l: { capacity: number | null; registered: number }): LoadTone {
  if (l.capacity == null) return 'open';
  if (l.registered > l.capacity) return 'over';
  return l.registered === l.capacity ? 'full' : 'open';
}
export function loadText(l: { capacity: number | null; registered: number }): string {
  return l.capacity == null ? `${l.registered} registered` : `${l.registered} / ${l.capacity}`;
}
export function overCapacityText(list: OverCapacity[]): string {
  return list.map(o => `${fmtDayMonth(o.day)} is over capacity: ${o.registered} of ${o.capacity}`).join('; ');
}

export function guestDay(g: Guest, day: string): GuestDay | undefined {
  return g.days.find(d => d.day === day);
}

export const WEB_ORDER_MODE_LABELS: Record<WebOrderMode, string> = {
  off: 'Off', record_only: 'Record only — no invoices yet', live: 'Live — invoices are created',
};
export const WEB_ORDER_MODE_BADGE: Record<WebOrderMode, string> = {
  off: 'badge badge-muted', record_only: 'badge badge-accent', live: 'badge badge-success',
};
export const WEB_ORDER_STATUS_LABELS: Record<WebOrderStatus, string> = {
  invoiced: 'Invoiced', recorded: 'Recorded', needs_review: 'Needs review', refused: 'Refused',
};
export const WEB_ORDER_STATUS_BADGE: Record<WebOrderStatus, string> = {
  invoiced: 'badge badge-success', recorded: 'badge badge-primary',
  needs_review: 'badge badge-accent', refused: 'badge badge-danger',
};
/** "Invoiced · INV-…", "Recorded", "Needs review: <reason>" or "Refused: <reason>". */
export function webOrderStatusText(o: Pick<WebOrder, 'status' | 'invoice_no' | 'review_reason'>): string {
  const label = WEB_ORDER_STATUS_LABELS[o.status];
  if (o.status === 'invoiced') return o.invoice_no ? `${label} · ${o.invoice_no}` : label;
  if (o.status === 'recorded') return label;
  return o.review_reason ? `${label}: ${o.review_reason}` : label;
}
/** An order still waiting for its invoice. */
export const webOrderIsOpen = (o: Pick<WebOrder, 'status'>) => o.status === 'recorded' || o.status === 'needs_review';
/**
 * A Stripe test payment is invoiced only while its channel accepts test
 * orders (372 refuses it otherwise), so no money that was never taken ends up
 * on an invoice. Without a channel, nothing accepts it.
 */
export const webOrderTestRefused = (o: Pick<WebOrder, 'livemode'>, channel: Pick<WebOrderChannel, 'allow_test'> | null) =>
  !o.livemode && channel?.allow_test !== true;
/** An open order whose invoice staff can create here. */
export const webOrderCanInvoice = (o: Pick<WebOrder, 'status' | 'livemode'>, channel: Pick<WebOrderChannel, 'allow_test'> | null) =>
  webOrderIsOpen(o) && !webOrderTestRefused(o, channel);

/** A file-name-safe version of an event's name. */
export function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'event';
}
