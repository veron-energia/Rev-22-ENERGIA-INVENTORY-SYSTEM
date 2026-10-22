import { INVOICE_STATUS_LABELS, InvoiceStatus } from '../../types';
import { calendarDate } from '../../lib/calendarDates';

/*
 * Events: the shapes the server returns (370_events.sql) and the few rules the
 * page applies to them. Numbers can arrive as numbers or numeric strings, so
 * every row passes through a normaliser before the page touches it.
 */

export interface EventDay {
  day: string; capacity: number | null; registered: number; attended: number;
  /** 415: ticket lines on invoices that are not deleted covering the day. They hold it, as people do. */
  ticket_lines: number;
}
export interface EventStore { id: string; name: string; }
export interface EventOption {
  id: string; name: string; days_count: number; price: number; is_active: boolean;
  sort_order: number; early_bird_price: number | null;
  /** 415: on an invoice that is not deleted, so the days it covers stay. */
  sold: boolean;
  /** 415: on any invoice, a deleted one too, so it cannot be removed (the invoice line keeps it). */
  on_any_invoice: boolean;
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
  /** 415: the mode of the event's website channel, or null when it has none. */
  web_channel_mode: WebOrderMode | null;
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
  /** 380: the customer's email, else the website order's; the website order
   *  whose invoice this is; the invoice's payment methods, comma-joined. */
  email: string | null; order_id: string | null; payment_methods: string | null;
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
// 376: who took the payment. 380: 'door' is the website's staff link, paid in
// cash, by PayNow or by bank transfer, and invoiced only by a Manager.
export type WebOrderProvider = 'stripe' | 'hitpay' | 'door';
export const webOrderProviderName = (p: WebOrderProvider) => (p === 'hitpay' ? 'HitPay' : p === 'door' ? 'Staff link' : 'Stripe');
/** 380: how a staff-link registration was paid, as its form says. */
export type WebOrderDoorMethod = 'cash' | 'paynow' | 'bank';
export const WEB_ORDER_DOOR_METHOD_LABELS: Record<WebOrderDoorMethod, string> = {
  cash: 'Cash', paynow: 'PayNow', bank: 'Bank Transfer',
};
/** Where a payment that took no money was made. */
export const webOrderTestPlace = (p: WebOrderProvider) => (p === 'hitpay' ? 'HitPay\'s sandbox' : 'Stripe\'s test mode');
// 380: 'dismissed' is a staff-link registration a Manager set aside, such as a test.
// 415: or an order an Owner or Manager closed because its payment was refunded outside the app.
export type WebOrderStatus = 'invoiced' | 'recorded' | 'needs_review' | 'refused' | 'dismissed';
export interface WebOrderChannel {
  key: string; mode: WebOrderMode; allow_test: boolean;
  store_name: string | null; acting_name: string | null; payment_method_name: string | null;
  /** 376: the method a HitPay order's invoice is paid with. */
  hitpay_payment_method_name: string | null;
}
export interface WebOrderPerson { name: string; email: string | null; whatsapp: string | null; }
export interface WebOrderCandidate {
  customer_id: string; full_name: string; phone: string | null; email: string | null; last_invoice_at: string | null;
}
export interface WebOrder {
  /** Stripe's checkout session id, or HitPay's payment request id (provider). */
  id: string; provider: WebOrderProvider; stripe_session_id: string; livemode: boolean; status: WebOrderStatus;
  ticket: string; ticket_label: string; quantity: number; unit_amount: number; amount_total: number; early_bird: boolean;
  buyer_name: string; buyer_email: string | null; buyer_phone: string | null;
  /** 403: the name parts the buyer registered with on the website (null until they do). */
  buyer_first_name: string | null; buyer_last_name: string | null;
  /** 403: whether the phone policy can read buyer_phone, so the buyer can be matched or made by it. */
  buyer_phone_readable: boolean;
  /** 403: the payment gave no phone, and buyer_phone is the WhatsApp the buyer registered with. */
  buyer_phone_from_registration: boolean;
  checkout_opened_at: string | null; paid_at: string | null;
  attendees: WebOrderPerson[] | null; names_at: string | null;
  invoice_id: string | null; invoice_no: string | null; review_reason: string | null;
  candidates: WebOrderCandidate[]; created_at: string | null;
  /** 380, staff-link orders only: the form's method, reference and date paid,
   *  and the staff member it credits. */
  door_method: WebOrderDoorMethod | null; payment_reference: string | null; paid_on: string | null;
  staff_profile_id: string | null; staff_name: string | null;
  /** 380: for an order that can still be linked, invoices made by hand for the
   *  event with the buyer's phone (the number only at a store the person works in). */
  hand_invoices: WebOrderHandInvoice[];
}
export interface WebOrderHandInvoice { invoice_no: string | null; store: string | null; }
export interface WebOrderList { channel: WebOrderChannel | null; can_switch: boolean; orders: WebOrder[]; }
/** What web_order_resolve and web_order_link_invoice answer. */
export interface WebOrderOutcome { status: WebOrderStatus; invoice_no: string | null; review_reason: string | null; }
/** 380: what web_order_link_preview shows of the invoice an order would be linked to. */
export interface WebOrderLinkPreview {
  invoice_no: string; store: string | null; date: string | null; customer_name: string | null;
  total: number; paid: number; methods: string | null; people: number; warnings: string[];
}

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
/** A comma-joined list, whether it arrives joined or as an array. */
const joined = (v: unknown): string | null =>
  (Array.isArray(v) ? str(v.filter(x => x !== null && x !== undefined && x !== '').join(', ')) : str(v));

const WEB_ORDER_MODES: WebOrderMode[] = ['off', 'record_only', 'live'];

export function normalizeEvent(r: any): EventRow {
  const days: EventDay[] = arr(r?.days).map(d => ({
    day: dateOnly(d?.day) ?? '', capacity: numOrNull(d?.capacity),
    registered: num(d?.registered), attended: num(d?.attended), ticket_lines: num(d?.ticket_lines),
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
      // Before 415, 'sold' meant on any invoice.
      on_any_invoice: o?.on_any_invoice === undefined ? !!o?.sold : !!o.on_any_invoice,
    })).sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name)),
    guests: num(r?.guests), ticket_guests: num(r?.ticket_guests), free_guests: num(r?.free_guests),
    can_manage: !!r?.can_manage, can_run: r?.can_run === undefined ? true : !!r?.can_run,
    web_channel_mode: WEB_ORDER_MODES.includes(r?.web_channel_mode) ? r.web_channel_mode : null,
  };
}

export function normalizeGuestDay(d: any): GuestDay {
  return {
    day: dateOnly(d?.day) ?? '', attended_at: str(d?.attended_at),
    check_in_code: str(d?.check_in_code), checked_in_by_name: str(d?.checked_in_by_name),
  };
}

/**
 * 415: what event_check_in answers. A check-in never changes one already made:
 * a second one answers already_in, with the time, who checked the guest in and
 * the code. `changed` says whether anything was written.
 */
export interface CheckInResult extends GuestDay {
  checked_in_by: string | null; already_in: boolean; changed: boolean;
}
export function normalizeCheckInResult(d: any, day: string): CheckInResult {
  return {
    ...normalizeGuestDay({ ...(d ?? {}), day: d?.day ?? day }),
    checked_in_by: str(d?.checked_in_by), already_in: d?.already_in === true, changed: d?.changed !== false,
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
    email: str(r?.email), order_id: str(r?.order_id), payment_methods: joined(r?.payment_methods),
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

/**
 * 415: what restoring a free guest answers: the days dropped (the event no longer has them) and any day now over capacity.
 * 449: someone who signed up again on the website after being taken off the list also gets the days they asked for then
 * (days_added; none before 449, or when they had them already).
 */
export interface GuestRestored { days_dropped: string[]; over_capacity: OverCapacity[]; days_added: string[]; }
export function normalizeGuestRestored(v: any): GuestRestored {
  return {
    days_dropped: arr(v?.days_dropped).map(d => dateOnly(d) ?? '').filter(Boolean),
    over_capacity: normalizeOverCapacity(v?.over_capacity),
    days_added: arr(v?.days_added).map(d => dateOnly(d) ?? '').filter(Boolean),
  };
}

const WEB_ORDER_STATUSES: WebOrderStatus[] = ['invoiced', 'recorded', 'needs_review', 'refused', 'dismissed'];
const WEB_ORDER_DOOR_METHODS: WebOrderDoorMethod[] = ['cash', 'paynow', 'bank'];
const webOrderMode = (v: unknown): WebOrderMode => (WEB_ORDER_MODES.includes(v as WebOrderMode) ? v as WebOrderMode : 'off');
// A status the page does not know is shown as needing a look, never as done.
const webOrderStatus = (v: unknown): WebOrderStatus =>
  (WEB_ORDER_STATUSES.includes(v as WebOrderStatus) ? v as WebOrderStatus : 'needs_review');

export function normalizeWebOrder(r: any): WebOrder {
  return {
    id: String(r?.id ?? ''), provider: r?.provider === 'hitpay' || r?.provider === 'door' ? r.provider : 'stripe',
    stripe_session_id: String(r?.stripe_session_id ?? ''), livemode: r?.livemode === true,
    status: webOrderStatus(r?.status), ticket: String(r?.ticket ?? ''),
    ticket_label: str(r?.ticket_label) ?? String(r?.ticket ?? ''),
    quantity: num(r?.quantity), unit_amount: num(r?.unit_amount), amount_total: num(r?.amount_total),
    early_bird: !!r?.early_bird,
    buyer_name: String(r?.buyer_name ?? ''), buyer_email: str(r?.buyer_email), buyer_phone: str(r?.buyer_phone),
    // 403's fields; a database without it says nothing, and any phone is taken as readable.
    buyer_first_name: str(r?.buyer_first_name), buyer_last_name: str(r?.buyer_last_name),
    buyer_phone_readable: typeof r?.buyer_phone_readable === 'boolean' ? r.buyer_phone_readable : !!str(r?.buyer_phone),
    buyer_phone_from_registration: r?.buyer_phone_from_registration === true,
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
    door_method: WEB_ORDER_DOOR_METHODS.includes(r?.door_method) ? r.door_method : null,
    payment_reference: str(r?.payment_reference), paid_on: dateOnly(r?.paid_on),
    staff_profile_id: str(r?.staff_profile_id), staff_name: str(r?.staff_name),
    hand_invoices: arr(r?.hand_invoices).map(h => ({ invoice_no: str(h?.invoice_no), store: str(h?.store) }))
      .filter(h => h.invoice_no || h.store),
  };
}

export function normalizeWebOrderList(v: any): WebOrderList {
  const c = v?.channel;
  return {
    channel: c && typeof c === 'object' ? {
      key: String(c.key ?? ''), mode: webOrderMode(c.mode), allow_test: !!c.allow_test,
      store_name: str(c.store_name), acting_name: str(c.acting_name), payment_method_name: str(c.payment_method_name),
      hitpay_payment_method_name: str(c.hitpay_payment_method_name),
    } : null,
    can_switch: v?.can_switch === true,
    orders: arr(v?.orders).map(normalizeWebOrder),
  };
}

export function normalizeWebOrderOutcome(v: any): WebOrderOutcome {
  return { status: webOrderStatus(v?.status), invoice_no: str(v?.invoice_no), review_reason: str(v?.review_reason) };
}

export function normalizeWebOrderLinkPreview(v: any): WebOrderLinkPreview {
  return {
    invoice_no: String(v?.invoice_no ?? ''), store: str(v?.store), date: dateOnly(v?.date),
    customer_name: str(v?.customer_name), total: num(v?.total), paid: num(v?.paid), methods: joined(v?.methods),
    people: num(v?.people), warnings: arr(v?.warnings).map(w => String(w ?? '')).filter(Boolean),
  };
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

export interface DayLoad {
  day: string; capacity: number | null; registered: number; attended: number; ticket_lines: number;
}
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
    return { day: d.day, capacity: d.capacity, registered, attended, ticket_lines: d.ticket_lines };
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
  invoiced: 'Invoiced', recorded: 'Recorded', needs_review: 'Needs review', refused: 'Refused', dismissed: 'Dismissed',
};
export const WEB_ORDER_STATUS_BADGE: Record<WebOrderStatus, string> = {
  invoiced: 'badge badge-success', recorded: 'badge badge-primary',
  needs_review: 'badge badge-accent', refused: 'badge badge-danger', dismissed: 'badge badge-muted',
};
/** "Invoiced · INV-…", "Recorded", or "Needs review", "Refused" or "Dismissed" with its reason. */
export function webOrderStatusText(o: Pick<WebOrder, 'status' | 'invoice_no' | 'review_reason'>): string {
  const label = WEB_ORDER_STATUS_LABELS[o.status];
  if (o.status === 'invoiced') return o.invoice_no ? `${label} · ${o.invoice_no}` : label;
  if (o.status === 'recorded') return label;
  return o.review_reason ? `${label}: ${o.review_reason}` : label;
}
/** An order still waiting for its invoice. */
export const webOrderIsOpen = (o: Pick<WebOrder, 'status'>) => o.status === 'recorded' || o.status === 'needs_review';
/**
 * A test payment (Stripe's test mode, or HitPay's sandbox) is invoiced only
 * while its channel accepts test orders (372 and 376 refuse it otherwise), so
 * no money that was never taken ends up on an invoice. Without a channel,
 * nothing accepts it.
 */
export const webOrderTestRefused = (o: Pick<WebOrder, 'livemode'>, channel: Pick<WebOrderChannel, 'allow_test'> | null) =>
  !o.livemode && channel?.allow_test !== true;
/** An open order whose invoice staff can create here. */
export const webOrderCanInvoice = (o: Pick<WebOrder, 'status' | 'livemode'>, channel: Pick<WebOrderChannel, 'allow_test'> | null) =>
  webOrderIsOpen(o) && !webOrderTestRefused(o, channel);
/** 380: why a staff-link registration sent while the channel was off is refused. */
export const WEB_ORDER_OFF_REFUSAL = 'The website channel is off';
/**
 * 380, 415: an order refused while the channel was off, from the website or
 * the staff link alike: staff invoice it by hand, then link it.
 */
export const webOrderOffRefused = (o: Pick<WebOrder, 'status' | 'review_reason'>) =>
  o.status === 'refused' && o.review_reason === WEB_ORDER_OFF_REFUSAL;
/**
 * 380: an open order that was already invoiced by hand is linked to that
 * invoice instead of getting a second one, and so is an order refused while
 * the channel was off (415: a website payment too). A test payment took no
 * money, so no real invoice is its.
 */
export const webOrderCanLink = (o: Pick<WebOrder, 'status' | 'livemode' | 'provider' | 'review_reason'>) =>
  (webOrderIsOpen(o) || webOrderOffRefused(o)) && o.livemode;
/**
 * 380: a staff-link registration whose amount is not the price of its pass.
 * Create invoice never makes an invoice for other than what was paid, so such
 * a one is invoiced by hand and linked.
 */
export const webOrderAmountDiffers = (o: Pick<WebOrder, 'provider' | 'review_reason'>) =>
  o.provider === 'door' && /\bS\$[\d,.]+ was paid\b/.test(o.review_reason ?? '');
/** 380: only a staff-link registration is set aside (a test, say) or brought back. */
export const webOrderCanDismiss = (o: Pick<WebOrder, 'status' | 'provider'>) => o.provider === 'door' && webOrderIsOpen(o);
export const webOrderCanRestore = (o: Pick<WebOrder, 'status' | 'provider' | 'review_reason'>) =>
  o.provider === 'door' && o.status === 'dismissed' && !webOrderClosedRefunded(o);
/**
 * 415 (the Owner, 9 Oct 2026): an Owner or Manager closes an order whose
 * payment was refunded outside the app, with a reason, so its event can be
 * deleted. The server keeps the reason after this.
 */
export const WEB_ORDER_REFUNDED_PREFIX = 'Refunded outside the app: ';
/**
 * 415: closed because its payment was refunded outside the app. Reopen undoes
 * it: the order is put back as it was before the close (a payment refused
 * while the channel was off is refused again; any other waits in Needs
 * review). The staff link's Restore does not bring it back, and a Dismiss
 * reason may not start with this prefix, so the prefix marks a close.
 */
export const webOrderClosedRefunded = (o: Pick<WebOrder, 'status' | 'review_reason'>) =>
  o.status === 'dismissed' && (o.review_reason ?? '').startsWith(WEB_ORDER_REFUNDED_PREFIX);
/**
 * 415: what holds its event (event_delete) can be closed: a website order
 * waiting for its invoice, or a payment refused while the channel was off
 * that took real money. A staff-link registration still waiting is set
 * aside with Dismiss instead.
 */
export const webOrderCanClose = (o: Pick<WebOrder, 'status' | 'provider' | 'livemode' | 'review_reason'>) =>
  (o.provider !== 'door' && webOrderIsOpen(o)) || (webOrderOffRefused(o) && o.livemode);

/** 403: the name the website sends when the payment (Stripe or HitPay) gave none. */
export const WEB_ORDER_PLACEHOLDER_BUYER = 'Website buyer';
/**
 * 403: the buyer's name: the payment's, or, where the payment gave none (the
 * website's "Website buyer"), the name the buyer registered with, once they have.
 */
export function webOrderBuyerName(o: Pick<WebOrder, 'buyer_name' | 'buyer_first_name' | 'buyer_last_name'>): string {
  const registered = [o.buyer_first_name, o.buyer_last_name].map(s => (s ?? '').trim()).filter(Boolean).join(' ');
  return o.buyer_name.trim() === WEB_ORDER_PLACEHOLDER_BUYER && registered ? registered : o.buyer_name;
}
/** 403: the buyer's name is the one they registered with, the payment having given none. */
export const webOrderNamedAtRegistration = (o: Pick<WebOrder, 'buyer_name' | 'buyer_first_name' | 'buyer_last_name'>) =>
  webOrderBuyerName(o) !== o.buyer_name;

/** Where the order came from: the website's checkout or its staff link. */
export const webOrderSource = (o: Pick<WebOrder, 'provider'>) => (o.provider === 'door' ? 'Staff link' : 'Website');
/** Stripe or HitPay for a website order; Cash, PayNow or Bank Transfer for a staff-link one. */
export function webOrderPaidThrough(o: Pick<WebOrder, 'provider' | 'door_method'>): string {
  if (o.provider === 'door' && o.door_method) return WEB_ORDER_DOOR_METHOD_LABELS[o.door_method];
  return webOrderProviderName(o.provider);
}
/** The day the money was paid: the staff link's Date paid, else the Singapore day of the payment. */
export function webOrderDatePaid(o: Pick<WebOrder, 'provider' | 'paid_on' | 'paid_at'>): string | null {
  return o.provider === 'door' ? o.paid_on : (calendarDate(o.paid_at, 'Asia/Singapore') || null);
}

/** A file-name-safe version of an event's name. */
export function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'event';
}

// ── 436: an event's own website (registrations, VIP, the Website tab) ──────
// The shapes event_web_settings_get, event_web_guest_extras and
// event_vip_orders_list answer (436_event_website_registrations_and_vip.sql).

export type VipState = 'none' | 'pending' | 'paid' | 'refunded';
export type VipProvider = 'hitpay' | 'paynow' | 'bank';
export type HoldReason = 'phone_in_use' | 'email_in_use' | 'phone_and_email_in_use' | 'several_name_matches' | 'legacy_ambiguous'
  | 'affiliate_name' | 'signed_up_again';
const VIP_STATES: VipState[] = ['none', 'pending', 'paid', 'refunded'];
const VIP_PROVIDERS: VipProvider[] = ['hitpay', 'paynow', 'bank'];
const vipState = (v: unknown): VipState => (VIP_STATES.includes(v as VipState) ? v as VipState : 'none');
const vipProvider = (v: unknown): VipProvider | null => (VIP_PROVIDERS.includes(v as VipProvider) ? v as VipProvider : null);
const bool = (v: unknown): boolean => v === true;

export const VIP_PROVIDER_LABELS: Record<VipProvider, string> = { hitpay: 'HitPay', paynow: 'PayNow', bank: 'Bank transfer' };
export const HOLD_REASON_LABELS: Record<HoldReason, string> = {
  phone_in_use: 'Their phone number belongs to a customer under another name.',
  email_in_use: 'Their email belongs to a customer with another phone number.',
  phone_and_email_in_use: 'Their phone number and email are already on file under another name.',
  several_name_matches: 'Their name matches more than one customer with this phone number.',
  legacy_ambiguous: 'An old record with the same name has a phone that could be this one.',
  // 436 (the owner, 21 Oct 2026): through an affiliate's link, her name on a phone and email not on her record.
  affiliate_name: 'Their name is the affiliate\'s (whose link was used), on a phone and email not on her record.',
  // 449 (the owner, 22 Oct 2026): staff took them off the guest list, and they signed up again on the website.
  signed_up_again: 'Signed up again after being taken off the list.',
};
/**
 * 449 (the owner, 22 Oct 2026: "Hold for staff to decide"): someone staff took off the guest list who signed up again on
 * the website (their own email) waits under To match until staff put them back on the list (any staff: their days and
 * the days they asked for now) or an Owner or Manager closes it (they stay off; signing up again shows them here
 * again). The website told them their place will be confirmed; they cannot buy VIP meanwhile.
 */
export interface SignedUpAgain {
  /** When they first signed up again since being taken off (the hold's start). */
  held_at: string | null;
  /** Every day they asked for since (added when they are put back). */
  days: string[];
  /** Why and when staff took them off (their guest record's cancellation); null on the guest list's row. */
  removed_reason: string | null;
  removed_at: string | null;
}
export const SIGNED_UP_AGAIN = 'Signed up again after being taken off the list';
function normalizeSignedUpAgain(v: any): SignedUpAgain | null {
  if (!v || typeof v !== 'object') return null;
  return {
    held_at: str(v.held_at), days: arr(v.days).map(d => dateOnly(d) ?? '').filter(Boolean),
    removed_reason: str(v.removed_reason), removed_at: str(v.removed_at),
  };
}
/** "Taken off the list (Cannot come · Wed 21 Oct 2026, 14:05); signed up again Thu 22 Oct 2026, 09:10, asking for Mon 23 Nov & Tue 24 Nov 2026." */
export function signedUpAgainText(s: SignedUpAgain): string {
  const removed = [s.removed_reason, s.removed_at ? fmtDateTime(s.removed_at) : null].filter(Boolean).join(' · ');
  return `Taken off the list${removed ? ` (${removed})` : ''}; signed up again${s.held_at ? ` ${fmtDateTime(s.held_at)}` : ''}`
    + `${s.days.length ? `, asking for ${fmtDayList(s.days)}` : ''}.`;
}
/**
 * What staff do after Put back: the website sends them nothing (no email, no personal link) and told them the team would
 * confirm their place on WhatsApp and send their personal link then.
 */
export const PUT_BACK_TELL_THEM = 'The website sends them nothing: let them know on WhatsApp that their place is confirmed, and send their'
  + ' VIP link (Guests tab, Copy VIP link) so they can buy VIP or change their answers.';
/** What "Put back on the list" does, for its window. */
export function putBackText(name: string, s: SignedUpAgain): string {
  return `${name} comes back on the guest list for the days they had${s.days.length ? ` and the days they asked for now (${fmtDayList(s.days)})` : ''}`
    + ` (days the event no longer has are left out). They can then buy VIP and save their answers on the website. ${PUT_BACK_TELL_THEM}`;
}
/** What Close does to a signed-up-again hold, for its window. */
export const SIGNED_UP_AGAIN_CLOSE_TEXT = 'They stay off the guest list (their registration stays as it is). If they sign up again, they show here again.';
/**
 * 444 (the owner, 21 Oct 2026: "Staff can close it"): a HitPay checkout opened and left without paying (HitPay has
 * reported no payment for it), still open until expires_at. The page says "Online payment started, not paid (until
 * HH:MM)", not "VIP payment waiting"; an Owner or Manager closing the registration closes it too, and Website orders
 * closes it on its own.
 */
export interface VipCheckout {
  order_id: string; opened_at: string | null; expires_at: string | null;
  /** How many people the checkout is for (it closes for all of them); null when the server did not say. */
  people: number | null;
}
export const ONLINE_PAYMENT_NOT_PAID = 'Online payment started, not paid';
/** "Online payment started, not paid (until 14:35)" (Singapore time), or null when there is none. */
export function vipCheckoutText(c: VipCheckout | null | undefined): string | null {
  if (!c) return null;
  const until = fmtTime(c.expires_at);
  return until ? `${ONLINE_PAYMENT_NOT_PAID} (until ${until})` : ONLINE_PAYMENT_NOT_PAID;
}
function normalizeVipCheckout(v: any): VipCheckout | null {
  if (!v || typeof v !== 'object' || !v.order_id) return null;
  return { order_id: String(v.order_id), opened_at: str(v.opened_at), expires_at: str(v.expires_at), people: numOrNull(v.people) };
}
/** 444: "It is one checkout for 3 people: …" when a checkout is for more than one person, else ''. */
export function vipCheckoutGroupText(people: number | null | undefined): string {
  return people != null && people > 1
    ? ` It is one checkout for ${people} people: it closes for all of them (the others stay registered and can start a new one).`
    : '';
}
/** 444: what closing a registration does to their unpaid checkout, for the Close dialog under To match. */
export function vipCheckoutCloseNote(c: VipCheckout): string {
  return `${vipCheckoutText(c)}: their HitPay checkout ${c.order_id} is closed too${c.people == null ? ' (for everyone on it)' : ''}.`
    + `${vipCheckoutGroupText(c.people)} If HitPay reports a payment for it later, it waits on Website orders to be refunded.`;
}
/** The perks a VIP gets, as the guest list and the door show them (the owner, 20 Oct 2026). */
export const VIP_PERKS = 'Priority for the free therapies · personalised seating · VIP name tag · dinner with the founder, Ms Veronica';

export interface GuestGift {
  gift_id: string; product_id: string; product_name: string; use_no: string | null; day: string | null;
  given_at: string | null; given_by_name: string | null;
}
/** What the Guests and Check-in tabs add to one guest (event_web_guest_extras). */
export interface GuestExtra {
  guest_id: string; person_id: string | null; website: boolean; is_test: boolean;
  registration_id: string | null; position: number | null; group_size: number | null;
  /** The person's own free record while their VIP record stands. */
  parked: boolean;
  vip: VipState;
  /** A registered ticket guest of the VIP option: a VIP at the door. */
  vip_guest: boolean;
  vip_invoice_no: string | null;
  /** A VIP payment of theirs waiting for a Manager (Website orders), by its provider. */
  vip_waiting: VipProvider | null;
  /** 444: an online payment started and not paid (a HitPay checkout still open), else null (and before 444). */
  vip_checkout: VipCheckout | null;
  hold: { reason: HoldReason; held_at: string | null } | null;
  /** 449: on a cancelled free record while its person, taken off the list, signed up again and waits under To match. */
  signed_up_again: { held_at: string | null; days: string[] } | null;
  closed: boolean;
  /** note: the plain note on the referral: the affiliate themself (not referred, no commission); an existing customer
   *  (not referred again, their referral stands); someone else on the affiliate's phone or email (held, waiting for an
   *  Owner's or Manager's check, or checked). Null when there is nothing to say. */
  referral: { code: string | null; state: string | null; outcome: string | null; affiliate_name: string | null; note: string | null } | null;
  /** For "Copy VIP link": set while the person is not VIP. */
  upgrade_token: string | null;
  gift: GuestGift | null;
  /** Round 8 (the owner, 21 Oct 2026: P1): their customer holds two VIP payments for this event (paid or waiting). */
  vip_double: boolean;
}
/** One VIP payment a customer holds for the event: paid (with its invoice number, for those with the store's access) or waiting. */
export interface VipHeld { state: 'paid' | 'waiting'; invoice_no: string | null; }
/** A customer holding two (or more) VIP payments for the event: one to refund (round 8). */
export interface VipDouble { customer_id: string; full_name: string; vips: VipHeld[]; }
export interface HoldCandidate {
  customer_id: string; full_name: string; phone: string | null; email: string | null; created_at: string | null;
  phone_matches: boolean; email_matches: boolean; name_matches: boolean;
  /** Round 8: already a guest of this event (their days and VIP payments), else null. */
  guest: { days: string[]; vips: VipHeld[] } | null;
  /** 439 (the owner, 21 Oct 2026): the records they were held for that a merge has since folded into this one
   *  (their own phone and email, and whether each matched what the person typed); empty when none. */
  merged_from: MergedFromRecord[];
}
/** 439: a retired record a held person was held for, now merged into the candidate listed. */
export interface MergedFromRecord {
  customer_id: string; full_name: string; phone: string | null; email: string | null; phone_matches: boolean; email_matches: boolean;
}
/** A registered person held for staff instead of being matched (433's rules). */
export interface RegistrationHold {
  person_id: string; guest_id: string | null; registration_id: string; position: number; group_size: number;
  held_at: string | null; reason: HoldReason; full_name: string; phone: string | null; email: string | null;
  days: string[]; vip_waiting: boolean; candidates: HoldCandidate[];
  /** Round 8: a VIP payment of theirs (paid, or a transfer sent) waits for them to be matched (not a checkout left unpaid). */
  vip_payment: boolean;
  /** 444: an online payment started and not paid (a HitPay checkout still open), else null. */
  vip_checkout: VipCheckout | null;
  /** 444: the server says which checkouts are open (false before 444: vip_waiting alone, which counts a checkout). */
  vip_checkout_known: boolean;
  /** Set when they came through an affiliate's link and are that affiliate (not referred), or share the affiliate's
   *  phone or email under another name (what linking or making a customer does). */
  referral_note: string | null;
  /** R6-4 (the owner, 21 Oct 2026): for an affiliate_name hold, the affiliate whose name they gave (when the server
   *  names her; else the page takes the candidate with the same name, or their own name). */
  affiliate_name: string | null;
  /** 449: taken off the list and signed up again (reason signed_up_again; on a To match entry too), else null. */
  signed_up_again: SignedUpAgain | null;
}
export interface GiftChoice { product_id: string; name: string; stock: number; }
export interface EventWebExtras {
  settings: {
    store_id: string; store_name: string | null; vip_option_id: string | null; mode: WebOrderMode; code: string;
    venue: string | null; site_url: string | null; gift_store_access: boolean;
  } | null;
  guests: Record<string, GuestExtra>;
  holds: RegistrationHold[];
  gift_choices: GiftChoice[];
  can_close_holds: boolean;
  can_undo_gifts: boolean;
  /** Round 8: customers holding two VIP payments for this event (paid or waiting). */
  vip_doubles: VipDouble[];
}

function normalizeGift(g: any): GuestGift | null {
  if (!g || typeof g !== 'object' || !g.gift_id) return null;
  return {
    gift_id: String(g.gift_id), product_id: String(g.product_id ?? ''), product_name: String(g.product_name ?? ''),
    use_no: str(g.use_no), day: dateOnly(g.day), given_at: str(g.given_at), given_by_name: str(g.given_by_name),
  };
}

export function normalizeWebExtras(v: any): EventWebExtras {
  const s = v?.settings;
  const guests: Record<string, GuestExtra> = {};
  for (const g of arr(v?.guests)) {
    if (!g?.guest_id) continue;
    guests[String(g.guest_id)] = {
      guest_id: String(g.guest_id), person_id: str(g.person_id), website: bool(g.website), is_test: bool(g.is_test),
      registration_id: str(g.registration_id), position: numOrNull(g.position), group_size: numOrNull(g.group_size),
      parked: bool(g.parked), vip: vipState(g.vip), vip_guest: bool(g.vip_guest), vip_invoice_no: str(g.vip_invoice_no),
      vip_waiting: vipProvider(g.vip_waiting), vip_checkout: normalizeVipCheckout(g.vip_checkout),
      hold: g.hold && typeof g.hold === 'object' ? { reason: g.hold.reason as HoldReason, held_at: str(g.hold.held_at) } : null,
      // 449: absent before 449.
      signed_up_again: g.signed_up_again && typeof g.signed_up_again === 'object'
        ? { held_at: str(g.signed_up_again.held_at), days: arr(g.signed_up_again.days).map(d => dateOnly(d) ?? '').filter(Boolean) } : null,
      closed: bool(g.closed),
      referral: g.referral && typeof g.referral === 'object' ? {
        code: str(g.referral.code), state: str(g.referral.state), outcome: str(g.referral.outcome),
        affiliate_name: str(g.referral.affiliate_name), note: str(g.referral.note),
      } : null,
      upgrade_token: str(g.upgrade_token), gift: normalizeGift(g.gift), vip_double: bool(g.vip_double),
    };
  }
  return {
    settings: s && typeof s === 'object' ? {
      store_id: String(s.store_id ?? ''), store_name: str(s.store_name), vip_option_id: str(s.vip_option_id),
      mode: WEB_ORDER_MODES.includes(s.mode) ? s.mode : 'off', code: String(s.code ?? ''), venue: str(s.venue),
      site_url: str(s.site_url), gift_store_access: s.gift_store_access !== false,
    } : null,
    guests,
    holds: arr(v?.holds).map(h => ({
      person_id: String(h?.person_id ?? ''), guest_id: str(h?.guest_id), registration_id: String(h?.registration_id ?? ''),
      position: num(h?.position), group_size: num(h?.group_size), held_at: str(h?.held_at),
      reason: h?.reason as HoldReason, full_name: String(h?.full_name ?? ''), phone: str(h?.phone), email: str(h?.email),
      days: arr(h?.days).map(d => dateOnly(d) ?? '').filter(Boolean), vip_waiting: bool(h?.vip_waiting),
      candidates: arr(h?.candidates).map(c => ({
        customer_id: String(c?.customer_id ?? ''), full_name: String(c?.full_name ?? ''), phone: str(c?.phone),
        email: str(c?.email), created_at: str(c?.created_at), phone_matches: bool(c?.phone_matches),
        email_matches: bool(c?.email_matches), name_matches: bool(c?.name_matches),
        guest: c?.guest && typeof c.guest === 'object'
          ? { days: arr(c.guest.days).map(d => dateOnly(d) ?? '').filter(Boolean), vips: normalizeVipsHeld(c.guest.vips) } : null,
        // 439: absent before 439 (and when nothing was merged into the candidate).
        merged_from: arr(c?.merged_from).map((m: any) => ({
          customer_id: String(m?.customer_id ?? ''), full_name: String(m?.full_name ?? ''), phone: str(m?.phone), email: str(m?.email),
          phone_matches: bool(m?.phone_matches), email_matches: bool(m?.email_matches),
        })).filter((m: MergedFromRecord) => m.customer_id),
      })).filter(c => c.customer_id),
      // An older 436 (before round 8) has no vip_payment: its vip_waiting stands in.
      vip_payment: h?.vip_payment === undefined ? bool(h?.vip_waiting) : bool(h?.vip_payment),
      // 444: absent before 444.
      vip_checkout: normalizeVipCheckout(h?.vip_checkout), vip_checkout_known: typeof h === 'object' && h !== null && 'vip_checkout' in h,
      referral_note: str(h?.referral_note),
      affiliate_name: str(h?.affiliate_name),
      // 449: absent before 449; a signed_up_again entry from a server that sent no details still gets them (empty).
      signed_up_again: normalizeSignedUpAgain(h?.signed_up_again)
        ?? (h?.reason === 'signed_up_again' ? { held_at: str(h?.held_at), days: [], removed_reason: null, removed_at: null } : null),
    })).filter(h => h.person_id),
    gift_choices: arr(v?.gift_choices).map(c => ({ product_id: String(c?.product_id ?? ''), name: String(c?.name ?? ''), stock: num(c?.stock) }))
      .filter(c => c.product_id),
    can_close_holds: bool(v?.can_close_holds),
    can_undo_gifts: bool(v?.can_undo_gifts),
    vip_doubles: normalizeVipDoubles(v?.vip_doubles),
  };
}

// ── Round 8 (the owner, 21 Oct 2026: P1): two VIP payments for one customer ──
export const TWO_VIP_PAYMENTS = 'Two VIP payments: refund one';
export function normalizeVipsHeld(v: unknown): VipHeld[] {
  return arr(v).map((x: any) => ({ state: x?.state === 'paid' ? 'paid' as const : 'waiting' as const, invoice_no: str(x?.invoice_no) }));
}
export function normalizeVipDoubles(v: unknown): VipDouble[] {
  return arr(v).map((d: any) => ({ customer_id: String(d?.customer_id ?? ''), full_name: String(d?.full_name ?? d?.name ?? ''),
    vips: normalizeVipsHeld(d?.vips) })).filter(d => d.customer_id);
}
/** "VIP paid (INV-0001)", "VIP paid", "VIP payment waiting"; several joined with " + ". */
export function vipHeldText(vips: VipHeld[]): string {
  return vips.map(v => v.state === 'paid' ? `VIP paid${v.invoice_no ? ` (${v.invoice_no})` : ''}`
    : `VIP payment waiting${v.invoice_no ? ` (${v.invoice_no})` : ''}`).join(' + ');
}
/**
 * 444: the To match badge: "VIP payment waiting" for a payment taken or a transfer sent; "Online payment started, not
 * paid (until HH:MM)" for a checkout left unpaid; nothing for one that expired. Before 444 the server could not tell
 * them apart, so its vip_waiting says "VIP payment waiting" as it did.
 */
export function holdVipBadge(h: Pick<RegistrationHold, 'vip_waiting' | 'vip_payment' | 'vip_checkout' | 'vip_checkout_known'>):
  { kind: 'payment' | 'checkout'; text: string } | null {
  if (h.vip_payment) return { kind: 'payment', text: 'VIP payment waiting' };
  if (h.vip_checkout) return { kind: 'checkout', text: vipCheckoutText(h.vip_checkout)! };
  if (!h.vip_checkout_known && h.vip_waiting) return { kind: 'payment', text: 'VIP payment waiting' };
  return null;
}
/** A To match candidate already on this event's guest list: "Already a guest: <days> · VIP paid (INV-…)". */
export function candidateGuestText(c: HoldCandidate): string | null {
  if (!c.guest) return null;
  const days = c.guest.days.length ? fmtDayList(c.guest.days) : 'no day now';
  return `Already a guest: ${days}${c.guest.vips.length ? ` · ${vipHeldText(c.guest.vips)}` : ''}`;
}
/**
 * 439: "Merged from Fay Holder, who had this phone" for a candidate that a merge folded the record they were held for
 * into (the kept record may not have that phone or email itself); null when nothing was merged into it.
 */
export function candidateMergedText(c: HoldCandidate): string | null {
  if (!c.merged_from?.length) return null;
  return 'Merged from ' + c.merged_from.map(m => {
    const had = [m.phone_matches ? 'phone' : null, m.email_matches ? 'email' : null].filter(Boolean).join(' and ');
    return had ? `${m.full_name}, who had this ${had}` : m.full_name;
  }).join('; ');
}
/** The warning before linking a held person who paid (or waits on) a VIP to a customer who already holds one. */
export function doubleVipWarning(h: RegistrationHold, c: HoldCandidate | null): string | null {
  if (!c || !h.vip_payment || !c.guest || c.guest.vips.length === 0) return null;
  return `Linking gives ${c.full_name} two VIP payments for this event. Refund one after linking.`;
}
/**
 * "Find another customer…" (the review of round 8, 21 Oct 2026): the customer staff picked, read from the guest list
 * the page already has, as a To match candidate (their registered rows: the days, and each VIP payment paid or
 * waiting; the server's list when they already hold two), so the Link window says "Already a guest" and warns as it
 * does for a listed candidate. Null when nobody is picked or they are not a guest of this event.
 */
export function pickedCustomerCandidate(customerId: string, guests: Guest[], extras: EventWebExtras | null): HoldCandidate | null {
  if (!customerId) return null;
  const rows = guests.filter(g => g.customer_id === customerId && g.status === 'registered');
  const dbl = extras?.vip_doubles.find(d => d.customer_id === customerId) ?? null;
  if (rows.length === 0 && !dbl) return null;
  const vips: VipHeld[] = dbl ? dbl.vips : rows.flatMap((g): VipHeld[] => {
    const x = extraOf(extras, g);
    if (!x || x.is_test || x.closed) return [];
    if (x.vip_guest) return x.vip === 'paid' ? [{ state: 'paid', invoice_no: x.vip_invoice_no }]
      : x.vip === 'pending' ? [{ state: 'waiting', invoice_no: x.vip_invoice_no }] : [];
    return x.vip_waiting ? [{ state: 'waiting', invoice_no: null }] : [];
  });
  const days = [...new Set(rows.flatMap(g => g.days.map(d => d.day)))].sort();
  return {
    customer_id: customerId, full_name: rows[0]?.customer_name ?? rows[0]?.name ?? dbl?.full_name ?? 'this customer',
    phone: null, email: null, created_at: null, phone_matches: false, email_matches: false, name_matches: false,
    guest: { days, vips }, merged_from: [],
  };
}
/** A guest row (not a cancelled one: the review of round 8) whose customer holds two VIP payments for the event. */
export const isVipDouble = (extras: EventWebExtras | null, g: Pick<Guest, 'guest_id' | 'customer_id' | 'status'>): boolean =>
  g.status !== 'cancelled'
  && (!!extraOf(extras, g)?.vip_double || (!!g.customer_id && !!extras?.vip_doubles.some(d => d.customer_id === g.customer_id)));

/** A guest's extras, or none (a guest the website does not know of). */
export const extraOf = (extras: EventWebExtras | null, g: Pick<Guest, 'guest_id'>): GuestExtra | null =>
  extras?.guests[g.guest_id] ?? null;
/** A VIP at the door: their VIP record (website or counter), registered. */
export const isVipGuest = (g: Guest, x: GuestExtra | null): boolean => !!x?.vip_guest && g.status === 'registered';
/** The person's link to buy VIP: <site>/vip/<token>, or null without a site address. */
export function vipLink(siteUrl: string | null | undefined, token: string | null | undefined): string | null {
  if (!siteUrl || !token) return null;
  return `${siteUrl.replace(/\/+$/, '')}/vip/${token}`;
}

// The Website tab (event_web_settings_get).
export interface WebSettings {
  event_id: string; code: string; mode: WebOrderMode; venue: string | null;
  store_id: string; store_name: string | null; acting_profile_id: string; acting_name: string | null;
  vip_option_id: string | null; vip_option_name: string | null; vip_voucher_ids: string[]; gift_product_ids: string[];
  hitpay_payment_method_id: string | null; paynow_payment_method_id: string | null; bank_payment_method_id: string | null;
  source_option_id: string | null; source_label: string | null; source_details: string | null;
  sync_url: string | null; site_url: string | null; last_sync_at: string | null; last_test_sync_at: string | null;
}
export interface WebKey {
  id: string; kind: 'live' | 'test'; key_hint: string; label: string | null; created_at: string | null;
  created_by_name: string | null; last_used_at: string | null; revoked_at: string | null; revoked_by_name: string | null;
  revoked_reason: string | null;
}
export interface WebRequestRow { type: string; received_at: string | null; outcome: string | null; kind: 'live' | 'test'; is_write: boolean; }
export interface WebTestPerson {
  person_id: string; position: number; full_name: string; phone: string | null; email: string | null; days: string[];
  vip: VipState; test_outcome: { match: string | null; hold_reason: string | null; referral: string | null } | null;
  /** The note a live key's registration would have left: the affiliate through her own link. */
  referral_note: string | null;
}
export interface WebTestRegistration {
  registration_id: string; submitted_at: string | null; created_at: string | null; referral_code: string | null;
  referral_state: string | null; people: WebTestPerson[];
}
export interface WebTestOrder {
  id: string; order_id: string; provider: VipProvider; status: string; livemode: boolean | null; amount_total: number;
  amount_paid: number | null; test_note: string | null; test_would: string | null; review_reason: string | null; created_at: string | null;
}
export interface Choice { id: string; name: string; }
export interface WebSettingsView {
  event_id: string; event_name: string;
  settings: WebSettings | null;
  readiness: { blocking: string[]; errors: string[]; warnings: string[] };
  endpoint_path: string;
  keys: WebKey[];
  requests: WebRequestRow[];
  test: { registrations: WebTestRegistration[]; orders: WebTestOrder[] };
  choices: {
    stores: Choice[]; profiles: (Choice & { role: string })[];
    options: (Choice & { days_count: number; price: number; is_active: boolean })[];
    vouchers: (Choice & { code: string; priced_at_store: boolean })[];
    products: (Choice & { sku: string | null; stock: number | null })[];
    methods: Choice[]; sources: (Choice & { requires_details: boolean })[];
  };
  can_manage: boolean; can_clear_tests: boolean; can_set_venue: boolean;
  /** 436 round 7 (S4): the talk titles the website asks about (Q4), the suggested list until saved; null from a
   *  database without round 7 (then the tab has no Talk titles card). */
  talks: { titles: string[]; saved: boolean; suggested: string[] } | null;
  /** Owner, Admin or Manager, once the website settings are saved (event_web_set_talks). */
  can_set_talks: boolean;
}

const strings = (v: unknown): string[] => arr(v).map(x => String(x ?? '')).filter(Boolean);
const choice = (c: any): Choice => ({ id: String(c?.id ?? ''), name: String(c?.name ?? c?.full_name ?? c?.label ?? '') });

export function normalizeWebSettingsView(v: any): WebSettingsView {
  const s = v?.settings;
  const c = v?.choices ?? {};
  return {
    event_id: String(v?.event_id ?? ''), event_name: String(v?.event_name ?? ''),
    settings: s && typeof s === 'object' ? {
      event_id: String(s.event_id ?? ''), code: String(s.code ?? ''),
      mode: WEB_ORDER_MODES.includes(s.mode) ? s.mode : 'off', venue: str(s.venue),
      store_id: String(s.store_id ?? ''), store_name: str(s.store_name),
      acting_profile_id: String(s.acting_profile_id ?? ''), acting_name: str(s.acting_name),
      vip_option_id: str(s.vip_option_id), vip_option_name: str(s.vip_option_name),
      vip_voucher_ids: strings(s.vip_voucher_ids), gift_product_ids: strings(s.gift_product_ids),
      hitpay_payment_method_id: str(s.hitpay_payment_method_id), paynow_payment_method_id: str(s.paynow_payment_method_id),
      bank_payment_method_id: str(s.bank_payment_method_id), source_option_id: str(s.source_option_id),
      source_label: str(s.source_label), source_details: str(s.source_details), sync_url: str(s.sync_url),
      site_url: str(s.site_url), last_sync_at: str(s.last_sync_at), last_test_sync_at: str(s.last_test_sync_at),
    } : null,
    readiness: { blocking: strings(v?.readiness?.blocking), errors: strings(v?.readiness?.errors), warnings: strings(v?.readiness?.warnings) },
    endpoint_path: String(v?.endpoint_path ?? '/functions/v1/event-website'),
    keys: arr(v?.keys).map(k => ({
      id: String(k?.id ?? ''), kind: k?.kind === 'test' ? 'test' : 'live', key_hint: String(k?.key_hint ?? ''), label: str(k?.label),
      created_at: str(k?.created_at), created_by_name: str(k?.created_by_name), last_used_at: str(k?.last_used_at),
      revoked_at: str(k?.revoked_at), revoked_by_name: str(k?.revoked_by_name), revoked_reason: str(k?.revoked_reason),
    } as WebKey)).filter(k => k.id),
    requests: arr(v?.requests).map(r => ({
      type: String(r?.type ?? ''), received_at: str(r?.received_at), outcome: str(r?.outcome),
      kind: r?.kind === 'test' ? 'test' : 'live', is_write: bool(r?.is_write),
    } as WebRequestRow)),
    test: {
      registrations: arr(v?.test?.registrations).map(r => ({
        registration_id: String(r?.registration_id ?? ''), submitted_at: str(r?.submitted_at), created_at: str(r?.created_at),
        referral_code: str(r?.referral_code), referral_state: str(r?.referral_state),
        people: arr(r?.people).map(p => ({
          person_id: String(p?.person_id ?? ''), position: num(p?.position), full_name: String(p?.full_name ?? ''),
          phone: str(p?.phone), email: str(p?.email), days: arr(p?.days).map(d => dateOnly(d) ?? '').filter(Boolean),
          vip: vipState(p?.vip),
          test_outcome: p?.test_outcome && typeof p.test_outcome === 'object'
            ? { match: str(p.test_outcome.match), hold_reason: str(p.test_outcome.hold_reason), referral: str(p.test_outcome.referral) } : null,
          referral_note: str(p?.referral_note),
        })),
      })),
      orders: arr(v?.test?.orders).map(o => ({
        id: String(o?.id ?? ''), order_id: String(o?.order_id ?? ''), provider: vipProvider(o?.provider) ?? 'hitpay',
        status: String(o?.status ?? ''), livemode: typeof o?.livemode === 'boolean' ? o.livemode : null,
        amount_total: num(o?.amount_total), amount_paid: numOrNull(o?.amount_paid), test_note: str(o?.test_note),
        test_would: str(o?.test_would), review_reason: str(o?.review_reason), created_at: str(o?.created_at),
      })),
    },
    choices: {
      stores: arr(c.stores).map(choice),
      profiles: arr(c.profiles).map(p => ({ ...choice(p), role: String(p?.role ?? '') })),
      options: arr(c.options).map(o => ({ ...choice(o), days_count: num(o?.days_count), price: num(o?.price), is_active: bool(o?.is_active) })),
      vouchers: arr(c.vouchers).map(o => ({ ...choice(o), code: String(o?.code ?? ''), priced_at_store: bool(o?.priced_at_store) })),
      products: arr(c.products).map(o => ({ ...choice(o), sku: str(o?.sku), stock: numOrNull(o?.stock) })),
      methods: arr(c.methods).map(choice),
      sources: arr(c.sources).map(o => ({ ...choice(o), requires_details: bool(o?.requires_details) })),
    },
    can_manage: bool(v?.can_manage), can_clear_tests: bool(v?.can_clear_tests), can_set_venue: bool(v?.can_set_venue),
    talks: v?.talks && typeof v.talks === 'object'
      ? { titles: strings(v.talks.titles), saved: bool(v.talks.saved), suggested: strings(v.talks.suggested) } : null,
    can_set_talks: bool(v?.can_set_talks),
  };
}

/** What a test key's registration says a live key would have done with a person. */
export function testOutcomeText(o: WebTestPerson['test_outcome']): string {
  if (!o) return '';
  const match = o.match === 'exact' ? 'linked to the customer with this phone and name'
    : o.match === 'same_words' ? 'linked to the customer with this phone and the same name in other words'
    : o.match === 'held' ? `held for staff to match (${HOLD_REASON_LABELS[o.hold_reason as HoldReason] ?? o.hold_reason})`
    : o.match === 'new_customer' ? 'made a new customer' : (o.match ?? '');
  const referral = o.referral === 'created' ? ', referred by the link'
    : o.referral === 'already_customer' ? ', not referred (already a customer)'
    : o.referral === 'self' && o.match === 'held' ? ', not referred (whether staff link her record or make someone else with her name a customer)'
    : o.referral === 'self' ? ', not referred (the affiliate themself)'
    : o.referral === 'held' ? ', referral decided when staff match them'
    : o.referral === 'link_off' ? ', not referred (the link is switched off)'
    : o.referral === 'unknown_code' ? ', not referred (unknown code)' : '';
  return `A live key would have ${match}${referral}.`;
}

// Website orders: the VIP orders (event_vip_orders_list).
export type VipOrderStatus = 'pending' | 'recorded' | 'invoiced' | 'needs_review' | 'refused' | 'dismissed' | 'test';
const VIP_ORDER_STATUSES: VipOrderStatus[] = ['pending', 'recorded', 'invoiced', 'needs_review', 'refused', 'dismissed', 'test'];
export const VIP_ORDER_STATUS_LABELS: Record<VipOrderStatus, string> = {
  pending: 'Checkout open', recorded: 'Recorded', invoiced: 'Invoiced', needs_review: 'Needs review',
  refused: 'Refused', dismissed: 'Dismissed', test: 'Test',
};
export const VIP_ORDER_STATUS_BADGE: Record<VipOrderStatus, string> = {
  pending: 'badge badge-muted', recorded: 'badge badge-primary', invoiced: 'badge badge-success',
  needs_review: 'badge badge-accent', refused: 'badge badge-danger', dismissed: 'badge badge-muted', test: 'badge badge-accent',
};
export interface VipOrderPerson {
  person_id: string; position: number; name: string; phone: string | null; email: string | null; match: string | null;
  hold_reason: string | null; customer_id: string | null; customer_name: string | null; days: string[];
  invoice_id: string | null; invoice_no: string | null; invoice_status: string | null;
}
export interface VipOrder {
  id: string; order_id: string; provider: VipProvider; status: VipOrderStatus; is_test: boolean; livemode: boolean | null;
  unit_amount: number; quantity: number; amount_total: number; amount_paid: number | null;
  payer_name: string | null; payer_email: string | null; payer_phone: string | null;
  checkout_opened_at: string | null; expires_at: string | null; expired: boolean; paid_at: string | null; paid_on: string | null;
  reference: string | null; hitpay_payment_request_id: string | null; hitpay_payment_id: string | null;
  review_reason: string | null; refusal: string | null; waiting_for_match: boolean; test_note: string | null; test_would: string | null;
  refunded_total: number; refund_noted_at: string | null; refund_covered: boolean; created_at: string | null;
  people: VipOrderPerson[];
}
export interface VipOrderList {
  settings: { mode: WebOrderMode; code: string; store_name: string | null; hitpay_method_name: string | null;
    paynow_method_name: string | null; bank_method_name: string | null } | null;
  can_close: boolean;
  orders: VipOrder[];
}
export function normalizeVipOrderList(v: any): VipOrderList {
  const s = v?.settings;
  return {
    settings: s && typeof s === 'object' ? {
      mode: WEB_ORDER_MODES.includes(s.mode) ? s.mode : 'off', code: String(s.code ?? ''), store_name: str(s.store_name),
      hitpay_method_name: str(s.hitpay_method_name), paynow_method_name: str(s.paynow_method_name), bank_method_name: str(s.bank_method_name),
    } : null,
    can_close: bool(v?.can_close),
    orders: arr(v?.orders).map(o => ({
      id: String(o?.id ?? ''), order_id: String(o?.order_id ?? ''), provider: vipProvider(o?.provider) ?? 'hitpay',
      // A status the page does not know is shown as needing a look, never as done.
      status: VIP_ORDER_STATUSES.includes(o?.status) ? o.status : 'needs_review',
      is_test: bool(o?.is_test), livemode: typeof o?.livemode === 'boolean' ? o.livemode : null,
      unit_amount: num(o?.unit_amount), quantity: num(o?.quantity), amount_total: num(o?.amount_total),
      amount_paid: numOrNull(o?.amount_paid), payer_name: str(o?.payer_name), payer_email: str(o?.payer_email),
      payer_phone: str(o?.payer_phone), checkout_opened_at: str(o?.checkout_opened_at), expires_at: str(o?.expires_at),
      expired: bool(o?.expired), paid_at: str(o?.paid_at), paid_on: dateOnly(o?.paid_on), reference: str(o?.reference),
      hitpay_payment_request_id: str(o?.hitpay_payment_request_id), hitpay_payment_id: str(o?.hitpay_payment_id),
      review_reason: str(o?.review_reason), refusal: str(o?.refusal), waiting_for_match: bool(o?.waiting_for_match),
      test_note: str(o?.test_note), test_would: str(o?.test_would), refunded_total: num(o?.refunded_total),
      refund_noted_at: str(o?.refund_noted_at), refund_covered: bool(o?.refund_covered), created_at: str(o?.created_at),
      people: arr(o?.people).map(p => ({
        person_id: String(p?.person_id ?? ''), position: num(p?.position), name: String(p?.name ?? ''), phone: str(p?.phone),
        email: str(p?.email), match: str(p?.match), hold_reason: str(p?.hold_reason), customer_id: str(p?.customer_id),
        customer_name: str(p?.customer_name), days: arr(p?.days).map(d => dateOnly(d) ?? '').filter(Boolean),
        invoice_id: str(p?.invoice_id), invoice_no: str(p?.invoice_no), invoice_status: str(p?.invoice_status),
      })),
    })).filter(o => o.id),
  };
}
export const VIP_REFUNDED_PREFIX = 'Refunded outside the app: ';
export const vipOrderClosedRefunded = (o: Pick<VipOrder, 'status' | 'review_reason'>) =>
  o.status === 'dismissed' && (o.review_reason ?? '').startsWith(VIP_REFUNDED_PREFIX);
/** Waiting for its invoices: a Manager confirms the money arrived (a transfer), or creates them after a look. */
export const vipOrderCanInvoice = (o: Pick<VipOrder, 'status' | 'is_test'>) =>
  !o.is_test && (o.status === 'recorded' || o.status === 'needs_review');
/** A transfer or a test is set aside with a reason; a HitPay payment took money and never is. */
export const vipOrderCanDismiss = (o: Pick<VipOrder, 'status' | 'is_test' | 'provider'>) =>
  (o.provider !== 'hitpay' || o.is_test) && ['recorded', 'needs_review', 'test'].includes(o.status);
/**
 * 444 (the owner, 21 Oct 2026): a HitPay checkout opened and not paid (HitPay has reported nothing of a payment for
 * it), open or expired: an Owner or Manager closes it with a reason (event_vip_order_dismiss; the owner, 22 Oct 2026:
 * not an Admin).
 */
export const vipOrderUnpaidCheckout = (o: Pick<VipOrder, 'provider' | 'status' | 'hitpay_payment_id' | 'hitpay_payment_request_id' | 'paid_at' | 'amount_paid'>) =>
  o.provider === 'hitpay' && o.status === 'pending' && !o.hitpay_payment_id && !o.hitpay_payment_request_id && !o.paid_at
  && o.amount_paid == null;
export const VIP_CHECKOUT_CLOSED_PREFIX = 'Checkout closed: ';
/** 444: a checkout closed by staff (it is never restored: the person starts a new one). */
export const vipOrderCheckoutClosed = (o: Pick<VipOrder, 'provider' | 'status' | 'review_reason'>) =>
  o.provider === 'hitpay' && o.status === 'dismissed' && (o.review_reason ?? '').startsWith(VIP_CHECKOUT_CLOSED_PREFIX);
export const vipOrderCanRestore = (o: Pick<VipOrder, 'status' | 'review_reason' | 'provider'>) =>
  o.status === 'dismissed' && !vipOrderClosedRefunded(o) && !vipOrderCheckoutClosed(o);
/** 415's rule: an order still waiting with money taken is closed as refunded outside the app (Owner or Manager). */
export const vipOrderCanClose = (o: Pick<VipOrder, 'status' | 'livemode' | 'amount_paid'>) =>
  o.status === 'recorded' || o.status === 'needs_review' || (o.status === 'refused' && o.livemode === true && (o.amount_paid ?? 0) > 0);
/** HitPay's refund notice still to act on: refunded there, not yet covered here (invoices cancelled or refunded, or that much recorded as refunded on them). */
export const vipOrderRefundOpen = (o: Pick<VipOrder, 'refunded_total' | 'refund_covered'>) => o.refunded_total > 0 && !o.refund_covered;

// ── 436 round 7: planning answers (the owner, 21 Oct 2026: Q1-Q7, S1-S4) ────
// What event_planning_list and event_planning_summary answer, and how the page
// words them. The labels, the limits and the time rule are the contract's
// (eventWebsiteContract.ts). The page cannot import the contract (tsconfig
// excludes it), so they are copied here, and planning.test.mjs compares the
// two copies.

/** Q1 "Any dietary preference?" */
export const FOOD_CHOICES = ['no_preference', 'vegetarian', 'vegan', 'halal', 'no_beef', 'other'] as const;
export type FoodChoice = (typeof FOOD_CHOICES)[number];
export const FOOD_LABELS: Record<FoodChoice, string> = {
  no_preference: 'No preference', vegetarian: 'Vegetarian', vegan: 'Vegan', halal: 'Halal', no_beef: 'No beef', other: 'Other',
};
/** Q5 "Anything we should prepare for you?" */
export const ACCESS_CHOICES = ['wheelchair', 'walking_help', 'front_seat'] as const;
export type AccessChoice = (typeof ACCESS_CHOICES)[number];
export const ACCESS_LABELS: Record<AccessChoice, string> = {
  wheelchair: 'Wheelchair access', walking_help: 'Help with walking or stairs', front_seat: 'Seat near the front (hearing or sight)',
};
/** The badges' short forms. */
export const ACCESS_SHORT: Record<AccessChoice, string> = { wheelchair: 'Wheelchair', walking_help: 'Walking help', front_seat: 'Front seat' };
/** Q6 "How did you hear about the seminar?" */
export const HEARD_FROM_CHOICES = ['tiktok', 'facebook', 'instagram', 'google', 'whatsapp', 'friend_family', 'staff', 'email', 'other'] as const;
export type HeardFromChoice = (typeof HEARD_FROM_CHOICES)[number];
export const HEARD_FROM_LABELS: Record<HeardFromChoice, string> = {
  tiktok: 'TikTok', facebook: 'Facebook', instagram: 'Instagram', google: 'Google', whatsapp: 'WhatsApp',
  friend_family: 'Friend or family', staff: 'Rev22 staff or consultant', email: 'Email', other: 'Other',
};
/** The contract's limits, plus the staff note (event_planning_save: 200). */
export const PLANNING_LIMITS = {
  food_other: 60, allergy_details: 120, access_other: 120, heard_from_other: 60, question: 300, talk_title: 120, talks: 20, note: 200,
} as const;
export const TIME_STEP_MINUTES = 30;
const PLAN_HHMM_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * The arriving and leaving times a part of the day may have: the contract's
 * planningTimeOptions, copied (planning.test.mjs proves them equal). Arriving:
 * the daily start, then every 30 minutes, at the latest 30 minutes before the
 * daily end. Leaving: 30 minutes after the start, then every 30 minutes, and
 * the daily end itself. No hours: no part-day times.
 */
export function timeOptions(start: string | null, end: string | null): { arrive: string[]; leave: string[] } {
  if (!start || !end || !PLAN_HHMM_RE.test(start) || !PLAN_HHMM_RE.test(end)) return { arrive: [], leave: [] };
  const minutes = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
  const hm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  const s = minutes(start), e = minutes(end);
  const arrive: string[] = [], leave: string[] = [];
  for (let m = s; m <= e - TIME_STEP_MINUTES; m += TIME_STEP_MINUTES) arrive.push(hm(m));
  for (let m = s + TIME_STEP_MINUTES; m < e; m += TIME_STEP_MINUTES) leave.push(hm(m));
  if (e - s >= TIME_STEP_MINUTES) leave.push(hm(e));
  return { arrive, leave };
}

export interface PlanningDay { date: string; whole_day: boolean; arrive: string | null; leave: string | null; }
export interface PlanningAnswers {
  food: FoodChoice | null; food_other: string | null; allergy: 'no' | 'yes' | null; allergy_details: string | null;
  timing: PlanningDay[]; talks: string[]; access: AccessChoice[]; access_other: string | null;
  heard_from: HeardFromChoice | null; heard_from_other: string | null; question: string | null;
}
/** One guest record's answers (a VIP's free and VIP records both carry them). */
export interface GuestPlanning {
  guest_id: string; plan_id: string;
  /** The days the answers are about now (a VIP comes every day). */
  days: string[];
  /** Send it back with a staff edit: an edit based on an older one is refused. */
  version: number;
  answers: PlanningAnswers;
  updated_at: string | null; updated_by: 'guest' | 'staff'; staff_name: string | null;
}
export interface EventPlanning {
  /** The titles the website asks about now (the suggested list until saved). */
  talk_titles: string[]; talk_titles_saved: boolean;
  /** The event's daily hours now (HH:MM), or null. */
  hours: { start: string | null; end: string | null };
  guests: Record<string, GuestPlanning>;
}
/** 'none': a database without round 7; 'loaded': read; 'error': nothing could be read; 'loading': not answered yet. */
export type PlanningState = 'none' | 'loaded' | 'error' | 'loading';

export const emptyAnswers = (): PlanningAnswers => ({
  food: null, food_other: null, allergy: null, allergy_details: null, timing: [], talks: [], access: [], access_other: null,
  heard_from: null, heard_from_other: null, question: null,
});

const planTime = (v: unknown): string | null => { const t = hhmm(v); return t && PLAN_HHMM_RE.test(t) ? t : null; };
const oneOf = <T extends string>(list: readonly T[], v: unknown): T | null => (list.includes(v as T) ? v as T : null);

/** Tolerant: codes the page does not know are dropped, texts kept as sent (the question with its line breaks). */
export function normalizeAnswers(a: any): PlanningAnswers {
  const access = arr(a?.access).filter((x: unknown) => ACCESS_CHOICES.includes(x as AccessChoice)) as AccessChoice[];
  const seen = new Set<string>();
  return {
    food: oneOf(FOOD_CHOICES, a?.food), food_other: str(a?.food_other),
    allergy: a?.allergy === 'yes' || a?.allergy === 'no' ? a.allergy : null, allergy_details: str(a?.allergy_details),
    timing: arr(a?.timing).map(t => ({
      date: dateOnly(t?.date) ?? '', whole_day: t?.whole_day !== false, arrive: planTime(t?.arrive), leave: planTime(t?.leave),
    })).filter(t => t.date && !seen.has(t.date) && (seen.add(t.date), true)).sort((x, y) => x.date.localeCompare(y.date)),
    talks: strings(a?.talks),
    access: ACCESS_CHOICES.filter(c => access.includes(c)),
    access_other: str(a?.access_other),
    heard_from: oneOf(HEARD_FROM_CHOICES, a?.heard_from), heard_from_other: str(a?.heard_from_other),
    question: str(a?.question),
  };
}

export function normalizePlanning(v: any): EventPlanning {
  const guests: Record<string, GuestPlanning> = {};
  for (const g of arr(v?.guests)) {
    if (!g?.guest_id) continue;
    guests[String(g.guest_id)] = {
      guest_id: String(g.guest_id), plan_id: String(g.plan_id ?? ''),
      days: arr(g.days).map(d => dateOnly(d) ?? '').filter(Boolean).sort(),
      version: num(g.version), answers: normalizeAnswers(g.answers),
      updated_at: str(g.updated_at), updated_by: g.updated_by === 'staff' ? 'staff' : 'guest', staff_name: str(g.staff_name),
    };
  }
  return {
    talk_titles: strings(v?.talk_titles), talk_titles_saved: bool(v?.talk_titles_saved),
    hours: { start: planTime(v?.hours?.daily_start), end: planTime(v?.hours?.daily_end) },
    guests,
  };
}

/** A guest record's answers, or none. */
export const planningOf = (p: EventPlanning | null, g: Pick<Guest, 'guest_id'>): GuestPlanning | null => p?.guests[g.guest_id] ?? null;

/** '14:00' -> '2:00 pm', '09:30' -> '9:30 am', '12:00' -> '12:00 pm'. */
export function fmtClock(t: string | null | undefined): string {
  if (!t) return '';
  const m = /^(\d{1,2}):(\d{2})/.exec(t);
  if (!m) return t;
  const h = Number(m[1]);
  return `${h % 12 === 0 ? 12 : h % 12}:${m[2]} ${h < 12 ? 'am' : 'pm'}`;
}
/** 'Day 1' by the event's day order (else the weekday). */
export function dayLabel(event: Pick<EventRow, 'days'>, day: string): string {
  const i = event.days.map(d => d.day).sort().indexOf(day);
  return i >= 0 ? `Day ${i + 1}` : fmtWeekday(day);
}
/** "21 Oct 2026, 10:05 am", Singapore time. */
export function fmtStamp(ts: string | null | undefined): string {
  const day = calendarDate(ts, 'Asia/Singapore');
  if (!day) return '';
  const p = dayParts(day);
  return `${p.d} ${MONTHS[p.m]} ${p.y}, ${fmtClock(fmtTime(ts))}`;
}

/**
 * One day's timing, as the sheet, the export and the badges word it: 'Whole
 * day'; 'Until 3:00 pm' (arriving at the start); 'From 2:00 pm' (leaving at the
 * end); else '2:00 pm – 4:00 pm' (also when the hours are not known).
 */
export function timingText(d: PlanningDay, start: string | null, end: string | null): string {
  if (d.whole_day) return 'Whole day';
  if (!d.arrive || !d.leave) return 'Part of the day';
  if (start && end && d.arrive === start) return `Until ${fmtClock(d.leave)}`;
  if (start && end && d.leave === end) return `From ${fmtClock(d.arrive)}`;
  return `${fmtClock(d.arrive)} – ${fmtClock(d.leave)}`;
}

// The cells (DESIGN_R7_FINAL section 5): the same words in the export, the detail and the website's sheet.
export function foodCell(a: PlanningAnswers): string {
  if (!a.food) return '';
  if (a.food === 'other') return a.food_other ? `Other: ${a.food_other}` : 'Other';
  return FOOD_LABELS[a.food];
}
export function allergyCell(a: PlanningAnswers): string {
  if (a.allergy === 'no') return 'No';
  if (a.allergy === 'yes') return a.allergy_details ? `Yes: ${a.allergy_details}` : 'Yes';
  return '';
}
/** A day's timing: blank when they are not coming that day or did not answer for it. */
export function timingCell(p: GuestPlanning, day: string, hours: EventPlanning['hours']): string {
  if (!p.days.includes(day)) return '';
  const t = p.answers.timing.find(x => x.date === day);
  return t ? timingText(t, hours.start, hours.end) : '';
}
export const talksCell = (a: PlanningAnswers): string => a.talks.join('; ');
export function accessCell(a: PlanningAnswers): string {
  return [...a.access.map(x => ACCESS_LABELS[x]), ...(a.access_other ? [`Other: ${a.access_other}`] : [])].join('; ');
}
export function heardFromCell(a: PlanningAnswers): string {
  if (!a.heard_from) return '';
  if (a.heard_from === 'other') return a.heard_from_other ? `Other: ${a.heard_from_other}` : 'Other';
  return HEARD_FROM_LABELS[a.heard_from];
}
/** The export's "Answers updated": when, and by the website or the staff member. */
export function answersUpdatedCell(p: GuestPlanning): string {
  if (!p.updated_at) return '';
  return `${sgStamp(p.updated_at)} · ${p.updated_by === 'staff' ? (p.staff_name ?? 'Staff') : 'Website'}`;
}
/** One line for a notice: food, allergies, access. */
export function planningLine(a: PlanningAnswers): string {
  return [foodCell(a) && `Food: ${foodCell(a)}`, allergyCell(a) && `Allergies: ${allergyCell(a)}`, accessCell(a) && `Access: ${accessCell(a)}`]
    .filter(Boolean).join(' · ');
}

export interface PlanningBadge { kind: 'food' | 'allergy' | 'time' | 'access'; text: string; title: string }
/** A badge's text is cut at this many characters, except an allergy's (never cut: K2). */
export const PLAN_BADGE_MAX = 40;
const cutBadge = (s: string) => (s.length > PLAN_BADGE_MAX ? `${s.slice(0, PLAN_BADGE_MAX - 1)}…` : s);

/**
 * S1: the compact badges under a guest's name, in this order: food (not "No
 * preference"), allergy (red, never cut), each part-day time of a day they
 * are coming, access needs. `title` is the full text (the page also puts it in
 * aria-label). `full`: the food and access badges show their full text too (the
 * door: a phone has no hover and the Check-in row no Answers button).
 */
export function planningBadges(p: GuestPlanning | null, event: Pick<EventRow, 'days'>, hours: EventPlanning['hours'] | null | undefined,
  opts: { full?: boolean } = {}): PlanningBadge[] {
  if (!p) return [];
  const a = p.answers;
  const out: PlanningBadge[] = [];
  if (a.food && a.food !== 'no_preference') {
    const full = a.food === 'other' ? (a.food_other ? `Food: ${a.food_other}` : 'Food: other') : FOOD_LABELS[a.food];
    out.push({ kind: 'food', text: opts.full ? full : cutBadge(full), title: a.food === 'other' ? full : `Food: ${full}` });
  }
  if (a.allergy === 'yes') {
    const full = a.allergy_details ? `Allergy: ${a.allergy_details}` : 'Allergy (not said which)';
    out.push({ kind: 'allergy', text: full, title: full });
  }
  for (const d of a.timing) {
    if (d.whole_day || !p.days.includes(d.date)) continue;
    const t = timingText(d, hours?.start ?? null, hours?.end ?? null);
    const label = dayLabel(event, d.date);
    const short = t.startsWith('From ') ? `${label} from ${t.slice(5)}`
      : t.startsWith('Until ') ? `${label} until ${t.slice(6)}` : `${label} ${t}`;
    out.push({ kind: 'time', text: cutBadge(short), title: `${short} (${fmtWeekday(d.date)})` });
  }
  if (a.access.length > 0 || a.access_other) {
    const short = [...a.access.map(x => ACCESS_SHORT[x]), ...(a.access_other ? [a.access_other] : [])].join(', ');
    out.push({ kind: 'access', text: opts.full ? `Access: ${accessCell(a)}` : cutBadge(`Access: ${short}`), title: `Access: ${accessCell(a)}` });
  }
  return out;
}
/** S3: at the door, allergy first, then food, then access, each in full (never cut); no timing. */
export function doorBadges(p: GuestPlanning | null, event: Pick<EventRow, 'days'>, hours: EventPlanning['hours'] | null | undefined): PlanningBadge[] {
  const order: Record<PlanningBadge['kind'], number> = { allergy: 0, food: 1, access: 2, time: 3 };
  return planningBadges(p, event, hours, { full: true }).filter(b => b.kind !== 'time').sort((x, y) => order[x.kind] - order[y.kind]);
}
/** The app's badge classes (K3). */
export const PLAN_BADGE_CLASS: Record<PlanningBadge['kind'], string> = {
  food: 'badge badge-success', allergy: 'badge badge-danger events-badge-allergy', time: 'badge badge-accent', access: 'badge badge-primary',
};

// The Planning tab (event_planning_summary).
export interface PlanPerson { guest_id: string; name: string; vip: boolean }
export type FoodCounts = Record<FoodChoice | 'not_said', number>;
export interface PlanningSummaryDay {
  day: string; label: string; registered: number; answered: number; food: FoodCounts;
  food_other: (PlanPerson & { text: string })[];
  allergies: (PlanPerson & { text: string | null })[];
  late: (PlanPerson & { time: string })[];
  early: (PlanPerson & { time: string })[];
  access: (PlanPerson & { needs: AccessChoice[]; other: string | null })[];
}
export interface PlanningSummary {
  event_id: string; hours: { start: string | null; end: string | null }; registered: number; answered: number;
  days: PlanningSummaryDay[];
  /** Null when the event has no website settings (no VIP ticket to count). */
  vip: { count: number; answered: number; waiting: number; food: FoodCounts; food_other: (PlanPerson & { text: string })[];
    allergies: (PlanPerson & { text: string | null })[];
    /** Round 8: customers holding two VIP payments for this event, counted once above. */
    doubles: VipDouble[] } | null;
  talks: { title: string; count: number; listed: boolean }[];
  heard_from: Record<HeardFromChoice | 'not_said', number>;
  heard_from_other: (PlanPerson & { text: string })[];
  questions: (PlanPerson & { text: string })[];
}

const planPerson = (x: any): PlanPerson => ({ guest_id: String(x?.guest_id ?? ''), name: String(x?.name ?? ''), vip: bool(x?.vip) });
const foodCounts = (v: any): FoodCounts => {
  const out = { not_said: num(v?.not_said) } as FoodCounts;
  for (const c of FOOD_CHOICES) out[c] = num(v?.[c]);
  return out;
};
const withText = (v: unknown) => arr(v).map(x => ({ ...planPerson(x), text: String(x?.text ?? '') }));

export function normalizePlanningSummary(v: any): PlanningSummary {
  const heard = { not_said: num(v?.heard_from?.not_said) } as PlanningSummary['heard_from'];
  for (const c of HEARD_FROM_CHOICES) heard[c] = num(v?.heard_from?.[c]);
  const vip = v?.vip && typeof v.vip === 'object' ? v.vip : null;
  return {
    event_id: String(v?.event_id ?? ''),
    hours: { start: planTime(v?.hours?.daily_start), end: planTime(v?.hours?.daily_end) },
    registered: num(v?.registered), answered: num(v?.answered),
    days: arr(v?.days).map(d => ({
      day: dateOnly(d?.day) ?? '', label: String(d?.label ?? ''), registered: num(d?.registered), answered: num(d?.answered),
      food: foodCounts(d?.food), food_other: withText(d?.food_other),
      allergies: arr(d?.allergies).map(x => ({ ...planPerson(x), text: str(x?.text) })),
      late: arr(d?.late).map(x => ({ ...planPerson(x), time: planTime(x?.time) ?? '' })),
      early: arr(d?.early).map(x => ({ ...planPerson(x), time: planTime(x?.time) ?? '' })),
      access: arr(d?.access).map(x => ({ ...planPerson(x),
        needs: ACCESS_CHOICES.filter(c => arr(x?.needs).includes(c)), other: str(x?.other) })),
    })).filter(d => d.day),
    vip: vip ? {
      count: num(vip.count), answered: num(vip.answered), waiting: num(vip.waiting), food: foodCounts(vip.food),
      food_other: withText(vip.food_other), allergies: arr(vip.allergies).map(x => ({ ...planPerson(x), text: str(x?.text) })),
      doubles: normalizeVipDoubles(vip.doubles),
    } : null,
    talks: arr(v?.talks).map(t => ({ title: String(t?.title ?? ''), count: num(t?.count), listed: t?.listed !== false })).filter(t => t.title),
    heard_from: heard,
    heard_from_other: withText(v?.heard_from_other),
    questions: withText(v?.questions).filter(q => q.text),
  };
}
