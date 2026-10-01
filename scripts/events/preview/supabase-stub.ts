// A stand-in for src/lib/supabase, used only by the preview harness.
//
// It answers every call the Events page makes from an in-memory copy of the
// event tables, shaped as 370_events.sql returns them, and applies the same
// rules the server does where they show on screen (who may set events up, a
// sold option or a busy day stays, a ticket guest's days come from the
// invoice, a full day only warns). Saves and check-ins change the memory, so
// the page can be clicked through. Website orders (372) come in every status,
// and Create invoice and the mode switch change them too. It talks to nothing.
//
// Every name, phone and email here is invented. ?role= picks the user (see
// auth-stub.tsx); ?fail=<rpc name> makes that call fail; ?allow_test=0 stops
// the website channel accepting Stripe test orders.
import { PREVIEW_USERS, previewRole } from './auth-stub';

type Day = { day: string; capacity: number | null };
type Option = { id: string; name: string; days_count: number; price: number; is_active: boolean; sort_order: number };
type Ev = {
  id: string; name: string; description: string | null; daily_start: string | null; daily_end: string | null;
  early_bird_until: string | null; early_bird_percent: number | null; is_active: boolean; notes: string | null;
  created_at: string; deleted: boolean; days: Day[]; store_ids: string[]; options: Option[];
};
type Line = { option_id: string; days: string[]; quantity: number; line_total: number };
type Inv = {
  id: string; invoice_no: string; business_date: string; store_id: string; customer_id: string | null;
  status: string; total_amount: number; paid_amount: number; lines: Line[]; marked_event_id?: string;
};
type GDay = { day: string; attended_at: string | null; check_in_code: string | null; checked_in_by: string | null };
type G = {
  id: string; event_id: string; name: string; phone: string | null; customer_id: string | null;
  source: 'ticket' | 'free'; invoice_id: string | null; ticket_option_id: string | null;
  registered_by: string | null; notes: string | null; status: 'registered' | 'cancelled';
  cancelled_reason: string | null; created_at: string; days: GDay[];
};

// ── dates ──────────────────────────────────────────────────────────────────
const sgToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const addDays = (day: string, n: number) => {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
};
// A time on a Singapore calendar day, as an ISO instant.
const at = (day: string, hhmm: string) => new Date(`${day}T${hhmm}:00+08:00`).toISOString();

const TODAY = sgToday();
const D1 = TODAY, D2 = addDays(TODAY, 1);          // the main event is on now: today and tomorrow
const PAST = addDays(TODAY, -17);

// ── people and places ──────────────────────────────────────────────────────
const role = previewRole();
const me = PREVIEW_USERS[role];

const STORES = [
  { id: 'st-north', name: 'North Store', is_active: true, deleted_at: null },
  { id: 'st-south', name: 'South Store', is_active: true, deleted_at: null },
  { id: 'st-east', name: 'East Store', is_active: true, deleted_at: null },
];
const PROFILES = [
  { id: 'u-owner', full_name: 'Preview Owner', role: 'owner', is_active: true, deleted_at: null },
  { id: 'u-manager', full_name: 'Preview Manager', role: 'manager', is_active: true, deleted_at: null },
  { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true, deleted_at: null },
  { id: 'u-staff2', full_name: 'Staff Two', role: 'staff', is_active: true, deleted_at: null },
  { id: 'u-inv', full_name: 'Stock Keeper', role: 'inventory_manager', is_active: true, deleted_at: null },
];
// Who works where. Owners see every store.
const ASSIGNED: Record<string, string[]> = {
  'u-manager': ['st-north', 'st-south'], 'u-staff': ['st-north'], 'u-staff2': ['st-north'],
};
const CUSTOMERS = Array.from({ length: 8 }, (_, i) => ({
  id: `c-0${i + 1}`, full_name: `Customer ${['One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight'][i]}`,
  phone: `+65 9123 00${String(i + 1).padStart(2, '0')}`, email: `customer${i + 1}@tests.invalid`, notes: null, deleted_at: null,
}));
// Two customers who share a phone, so a website order from it waits for staff.
CUSTOMERS.push(
  { id: 'c-09', full_name: 'Customer Nine', phone: '+65 9123 0020', email: 'customer9@tests.invalid', notes: null, deleted_at: null },
  { id: 'c-10', full_name: 'Customer Ten', phone: '+65 9123 0020', email: 'customer10@tests.invalid', notes: null, deleted_at: null },
);

const isOwnerOrAdmin = role === 'owner';
const isManager = role === 'owner' || role === 'manager';
const hasStore = (storeId: string) => isOwnerOrAdmin || (ASSIGNED[me.id] ?? []).includes(storeId);

// ── the events ─────────────────────────────────────────────────────────────
const events: Ev[] = [
  {
    id: 'ev-open-days', name: 'Anniversary Open Days', description: 'Two days of talks, demos and tea at the store.',
    daily_start: '10:00', daily_end: '19:00', early_bird_until: addDays(TODAY, -10), early_bird_percent: 50,
    is_active: true, notes: 'Door gift for every guest.', created_at: at(addDays(TODAY, -40), '09:00'), deleted: false,
    days: [{ day: D1, capacity: null }, { day: D2, capacity: 10 }], store_ids: ['st-north', 'st-south'],
    options: [
      { id: 'op-1day', name: '1 Day', days_count: 1, price: 61, is_active: true, sort_order: 1 },
      { id: 'op-2days', name: '2 Days', days_count: 2, price: 94, is_active: true, sort_order: 2 },
    ],
  },
  {
    id: 'ev-tea', name: 'Mid-Autumn Tea Morning', description: null,
    daily_start: '09:30', daily_end: '12:30', early_bird_until: null, early_bird_percent: null,
    is_active: false, notes: null, created_at: at(addDays(TODAY, -60), '09:00'), deleted: false,
    days: [{ day: PAST, capacity: 20 }], store_ids: ['st-south'],
    options: [{ id: 'op-entry', name: 'Entry', days_count: 1, price: 20, is_active: false, sort_order: 1 }],
  },
];

const eb = (price: number) => Math.round(price * 50) / 100;
const invoices: Inv[] = [
  { id: 'inv-1', invoice_no: 'INV-2026-9001', business_date: addDays(TODAY, -14), store_id: 'st-north', customer_id: 'c-01',
    status: 'paid', total_amount: eb(94) * 2, paid_amount: eb(94) * 2,
    lines: [{ option_id: 'op-2days', days: [D1, D2], quantity: 2, line_total: eb(94) * 2 }] },
  { id: 'inv-2', invoice_no: 'INV-2026-9002', business_date: addDays(TODAY, -5), store_id: 'st-north', customer_id: 'c-02',
    status: 'partially_paid', total_amount: 61, paid_amount: 30,
    lines: [{ option_id: 'op-1day', days: [D1], quantity: 1, line_total: 61 }] },
  { id: 'inv-3', invoice_no: 'INV-2026-9003', business_date: addDays(TODAY, -3), store_id: 'st-south', customer_id: 'c-04',
    status: 'unpaid', total_amount: 183, paid_amount: 0,
    lines: [{ option_id: 'op-1day', days: [D2], quantity: 3, line_total: 183 }] },
  { id: 'inv-4', invoice_no: 'INV-2026-9004', business_date: addDays(TODAY, -2), store_id: 'st-north', customer_id: 'c-05',
    status: 'paid', total_amount: 94 + 120, paid_amount: 94 + 120,
    lines: [{ option_id: 'op-2days', days: [D1, D2], quantity: 1, line_total: 94 }] },
  { id: 'inv-5', invoice_no: 'INV-2026-9005', business_date: addDays(TODAY, -1), store_id: 'st-north', customer_id: 'c-06',
    status: 'cancelled', total_amount: 61, paid_amount: 0,
    lines: [{ option_id: 'op-1day', days: [D1], quantity: 1, line_total: 61 }] },
  { id: 'inv-6', invoice_no: 'INV-2026-9006', business_date: TODAY, store_id: 'st-north', customer_id: 'c-07',
    status: 'paid', total_amount: 250, paid_amount: 250, lines: [] },
  { id: 'inv-7', invoice_no: 'INV-2026-9007', business_date: addDays(TODAY, -4), store_id: 'st-east', customer_id: 'c-08',
    status: 'paid', total_amount: 88, paid_amount: 88, lines: [], marked_event_id: 'ev-open-days' },
  { id: 'inv-8', invoice_no: 'INV-2026-8990', business_date: PAST, store_id: 'st-south', customer_id: 'c-03',
    status: 'paid', total_amount: 140, paid_amount: 140, lines: [] },
];

let seq = 100;
const newId = (p: string) => `${p}-${++seq}`;
const gday = (day: string, attended?: string, code?: string, by = 'u-staff'): GDay =>
  ({ day, attended_at: attended ? at(day, attended) : null, check_in_code: code ?? null, checked_in_by: attended ? by : null });
const guest = (g: Partial<G> & Pick<G, 'name' | 'days'>): G => ({
  id: newId('g'), event_id: 'ev-open-days', phone: null, customer_id: null, source: 'free', invoice_id: null,
  ticket_option_id: null, registered_by: 'u-staff', notes: null, status: 'registered', cancelled_reason: null,
  created_at: at(addDays(TODAY, -6), '12:00'), ...g,
});
const guests: G[] = [
  guest({ name: 'Guest One', phone: '+65 9123 0001', customer_id: 'c-01', source: 'ticket', invoice_id: 'inv-1', ticket_option_id: 'op-2days',
    days: [gday(D1, '10:04', 'CD 12'), gday(D2)] }),
  guest({ name: 'Guest Two', phone: '+65 9123 0002', source: 'ticket', invoice_id: 'inv-1', ticket_option_id: 'op-2days',
    days: [gday(D1, '10:05', 'CD 12'), gday(D2)] }),
  guest({ name: 'Guest Three', phone: '+65 9123 0003', customer_id: 'c-02', source: 'ticket', invoice_id: 'inv-2', ticket_option_id: 'op-1day',
    days: [gday(D1)], registered_by: 'u-staff2' }),
  guest({ name: 'Guest Four', phone: '+65 9123 0004', customer_id: 'c-04', source: 'ticket', invoice_id: 'inv-3', ticket_option_id: 'op-1day',
    days: [gday(D2)], registered_by: 'u-manager' }),
  guest({ name: 'Guest Five', source: 'ticket', invoice_id: 'inv-3', ticket_option_id: 'op-1day', days: [gday(D2)], registered_by: 'u-manager' }),
  guest({ name: 'Guest Six', source: 'ticket', invoice_id: 'inv-3', ticket_option_id: 'op-1day', days: [gday(D2)], registered_by: 'u-manager' }),
  guest({ name: 'Guest Seven', phone: '+65 9123 0007', customer_id: 'c-05', source: 'ticket', invoice_id: 'inv-4', ticket_option_id: 'op-2days',
    days: [gday(D1, '11:20'), gday(D2)] }),
  // Their invoice was cancelled, so they are too.
  guest({ name: 'Guest Eight', phone: '+65 9123 0008', source: 'ticket', invoice_id: 'inv-5', ticket_option_id: 'op-1day',
    days: [gday(D1)], status: 'cancelled', cancelled_reason: 'Invoice cancelled' }),
  guest({ name: 'Guest Nine', phone: '+65 9123 0009', notes: 'VEG', days: [gday(D1, '10:30', 'CD 13'), gday(D2)] }),
  guest({ name: 'Guest Ten', phone: '+65 9123 0010', notes: 'Free Sock', days: [gday(D2)], registered_by: 'u-staff2' }),
  guest({ name: 'Guest Eleven', phone: '+65 9123 0011', customer_id: 'c-03', days: [gday(D1)] }),
  guest({ name: 'Guest Twelve', phone: '+65 9123 0012', days: [gday(D2)], registered_by: 'u-manager' }),
  guest({ name: 'Guest Thirteen', phone: '+65 9123 0013', notes: 'Wheelchair access', days: [gday(D2)] }),
  guest({ name: 'Guest Fourteen', phone: '+65 9123 0014', days: [gday(D1)], status: 'cancelled', cancelled_reason: 'Cannot come after all' }),
  // The past event.
  guest({ event_id: 'ev-tea', name: 'Guest Fifteen', phone: '+65 9123 0015', days: [gday(PAST, '09:40', 'MA 1')] }),
  guest({ event_id: 'ev-tea', name: 'Guest Sixteen', days: [gday(PAST, '09:45', 'MA 2')] }),
  guest({ event_id: 'ev-tea', name: 'Guest Seventeen', notes: 'Brings a friend', days: [gday(PAST)] }),
];

// ── website orders (372) ───────────────────────────────────────────────────
type WebPerson = { name: string; email: string | null; whatsapp: string | null };
type WebOrder = {
  id: string; channel: string; stripe_session_id: string; livemode: boolean;
  status: 'recorded' | 'invoiced' | 'needs_review' | 'refused';
  ticket: 'both' | 'day1' | 'day2'; quantity: number; unit_amount: number; amount_total: number; early_bird: boolean;
  buyer_name: string; buyer_email: string | null; buyer_phone: string | null;
  checkout_opened_at: string; paid_at: string; attendees: WebPerson[] | null; names_at: string | null;
  invoice_id: string | null; customer_id: string | null; review_reason: string | null; candidate_ids: string[];
};
// ?allow_test=0 previews the channel once it no longer accepts Stripe test
// orders: the test order recorded before then cannot be invoiced.
const webChannels = [{
  key: 'preview-open-days-2026', event_id: 'ev-open-days', mode: 'record_only',
  allow_test: new URLSearchParams(typeof location === 'undefined' ? '' : location.search).get('allow_test') !== '0',
  store_id: 'st-north', acting_profile_id: 'u-owner', payment_method_name: 'Stripe (online)',
}];
const PASSES = {
  both: { label: 'Both days', option_id: 'op-2days', days: [D1, D2] },
  day1: { label: 'Day 1 only', option_id: 'op-1day', days: [D1] },
  day2: { label: 'Day 2 only', option_id: 'op-1day', days: [D2] },
};
const person = (name: string, n: string): WebPerson => ({ name, email: `guest${n}@tests.invalid`, whatsapp: `+65 9123 00${n}` });
const webOrder = (o: Partial<WebOrder> & Pick<WebOrder, 'id' | 'ticket' | 'quantity' | 'unit_amount' | 'buyer_name' | 'paid_at'>): WebOrder => ({
  channel: 'preview-open-days-2026', stripe_session_id: `cs_live_preview${o.id.replace(/\W/g, '')}0000`, livemode: true,
  status: 'recorded', amount_total: o.unit_amount * o.quantity, early_bird: false, buyer_email: null, buyer_phone: null,
  checkout_opened_at: o.paid_at, attendees: null, names_at: null, invoice_id: null, customer_id: null, review_reason: null,
  candidate_ids: [], ...o,
});
invoices.push({ id: 'inv-web-1', invoice_no: 'INV-2026-9010', business_date: addDays(TODAY, -12), store_id: 'st-north',
  customer_id: 'c-03', status: 'paid', total_amount: eb(61) * 2, paid_amount: eb(61) * 2,
  lines: [{ option_id: 'op-1day', days: [D1], quantity: 2, line_total: eb(61) * 2 }] });
const webOrders: WebOrder[] = [
  webOrder({ id: 'wo-1', status: 'invoiced', ticket: 'day1', quantity: 2, unit_amount: eb(61), early_bird: true,
    buyer_name: 'Guest Twenty', buyer_phone: '+65 9123 0003', buyer_email: 'guest30@tests.invalid',
    checkout_opened_at: at(addDays(TODAY, -12), '20:41'), paid_at: at(addDays(TODAY, -12), '20:44'),
    attendees: [person('Guest Twenty', '30'), person('Guest Twenty-Five', '31')], names_at: at(addDays(TODAY, -12), '20:50'),
    invoice_id: 'inv-web-1', customer_id: 'c-03' }),
  // Two customers have this phone.
  webOrder({ id: 'wo-2', status: 'needs_review', ticket: 'both', quantity: 1, unit_amount: eb(94), early_bird: true,
    buyer_name: 'Guest Twenty-Two', buyer_phone: '+65 9123 0020', buyer_email: 'guest32@tests.invalid',
    checkout_opened_at: at(addDays(TODAY, -11), '09:58'), paid_at: at(addDays(TODAY, -11), '10:02'),
    attendees: [person('Guest Twenty-Two', '32')], names_at: at(addDays(TODAY, -11), '10:05'),
    review_reason: '2 customers have this phone', candidate_ids: ['c-09', 'c-10'] }),
  webOrder({ id: 'wo-3', status: 'refused', ticket: 'day2', quantity: 1, unit_amount: 10,
    buyer_name: 'Guest Twenty-Three', buyer_phone: '+65 9123 0033', paid_at: at(addDays(TODAY, -4), '13:15'),
    review_reason: 'The amount paid does not match the pass price' }),
  // Recorded while the channel only records; nobody has this phone yet.
  webOrder({ id: 'wo-4', ticket: 'day2', quantity: 3, unit_amount: 61,
    buyer_name: 'Guest Twenty-One', buyer_phone: '+65 9123 0035', buyer_email: 'guest35@tests.invalid',
    paid_at: at(addDays(TODAY, -2), '18:30') }),
  // A Stripe test order from Customer One's phone.
  webOrder({ id: 'wo-5', livemode: false, stripe_session_id: 'cs_test_preview00000005', ticket: 'day1', quantity: 1, unit_amount: 61,
    buyer_name: 'Guest Twenty-Four', buyer_phone: '+65 9123 0001', paid_at: at(addDays(TODAY, -1), '11:05'),
    attendees: [person('Guest Twenty-Four', '34')], names_at: at(addDays(TODAY, -1), '11:09') }),
];
// The invoiced order's people, on the guest list from its invoice.
guests.push(...webOrders[0].attendees!.map(a => guest({ name: a.name, phone: a.whatsapp, customer_id: a.name === 'Guest Twenty' ? 'c-03' : null,
  source: 'ticket', invoice_id: 'inv-web-1', ticket_option_id: 'op-1day', registered_by: null, days: [gday(D1)] })));

// ── the rules, as the server applies them ──────────────────────────────────
class Refused extends Error {}
const refuse = (msg: string): never => { throw new Refused(msg); };
const fmt = (day: string) => {
  const [y, m, d] = day.split('-').map(Number);
  return `${String(d).padStart(2, '0')} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1]} ${y}`;
};
const canRun = (e: Ev) => e.store_ids.some(hasStore);
const findEvent = (id: string) => events.find(e => e.id === id && !e.deleted) ?? refuse('Event not found');
const mustRun = (e: Ev) => { if (!canRun(e)) refuse('You do not have access to this event'); };
const nameOf = (id: string | null) => PROFILES.find(p => p.id === id)?.full_name ?? null;
const optionSold = (optId: string) => invoices.some(i => i.lines.some(l => l.option_id === optId));

function dayLoad(e: Ev) {
  return [...e.days].sort((a, b) => a.day.localeCompare(b.day)).map(d => {
    const on = guests.filter(g => g.event_id === e.id && g.status === 'registered')
      .map(g => g.days.find(x => x.day === d.day)).filter(Boolean) as GDay[];
    return { day: d.day, capacity: d.capacity, registered: on.length, attended: on.filter(x => x.attended_at).length };
  });
}

function summary(e: Ev) {
  const days = dayLoad(e);
  const reg = guests.filter(g => g.event_id === e.id && g.status === 'registered');
  return {
    id: e.id, name: e.name, description: e.description, daily_start: e.daily_start, daily_end: e.daily_end,
    early_bird_until: e.early_bird_until, early_bird_percent: e.early_bird_percent, is_active: e.is_active, notes: e.notes,
    created_at: e.created_at, first_day: days[0]?.day ?? null, last_day: days[days.length - 1]?.day ?? null, days,
    stores: e.store_ids.map(id => STORES.find(s => s.id === id)!).filter(Boolean).map(s => ({ id: s.id, name: s.name }))
      .sort((a, b) => a.name.localeCompare(b.name)),
    options: [...e.options].sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name)).map(o => ({
      ...o, price: o.price.toFixed(2),   // numeric arrives as a string, as PostgREST sends it
      early_bird_price: e.early_bird_until && e.early_bird_percent != null
        ? (Math.round(o.price * (100 - e.early_bird_percent)) / 100).toFixed(2) : null,
      sold: optionSold(o.id),
    })),
    guests: reg.length, ticket_guests: reg.filter(g => g.source === 'ticket').length,
    free_guests: reg.filter(g => g.source === 'free').length,
    can_manage: isManager, can_run: canRun(e),
  };
}

function membership(inv: Inv): { event_id: string; source: 'staff' | 'event_day' | 'ticket' } | null {
  if (inv.marked_event_id) return { event_id: inv.marked_event_id, source: 'staff' };
  const onDay = events.find(e => !e.deleted && e.store_ids.includes(inv.store_id) && e.days.some(d => d.day === inv.business_date));
  if (onDay) return { event_id: onDay.id, source: 'event_day' };
  const byTicket = events.find(e => !e.deleted && inv.lines.some(l => e.options.some(o => o.id === l.option_id)));
  return byTicket ? { event_id: byTicket.id, source: 'ticket' } : null;
}

const rpcs: Record<string, (a: any) => unknown> = {
  // As 96 defines it, a Manager is offered every active store, while
  // event_save accepts only stores they work in: picking East Store as the
  // Manager shows that refusal.
  my_assigned_stores: () => STORES.filter(s => hasStore(s.id) || role === 'manager')
    .map((s, i) => ({ store_id: s.id, store_name: s.name, is_default: i === 0 })),

  events_list: () => events.filter(e => !e.deleted && canRun(e))
    .sort((a, b) => (b.days[0]?.day ?? '').localeCompare(a.days[0]?.day ?? ''))
    .map(summary),

  event_save: ({ p_event: p }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can set up events');
    if (!String(p.name ?? '').trim()) refuse('Give the event a name');
    const days: Day[] = (p.days ?? []).map((d: any) => ({ day: d.day, capacity: d.capacity ?? null }));
    if (days.length === 0) refuse('Give the event at least one day');
    if (new Set(days.map(d => d.day)).size !== days.length) refuse('A day is listed twice');
    const storeIds: string[] = p.store_ids ?? [];
    if (storeIds.length === 0) refuse('Choose the store(s) the event is at');
    if (storeIds.some(s => !hasStore(s))) refuse('You can only hold events at stores you work in');
    const opts: any[] = p.options ?? [];
    if (opts.length === 0) refuse('Give the event at least one ticket option');
    for (const o of opts) {
      if (!(o.days_count >= 1 && o.days_count <= days.length)) refuse(`The "${o.name}" ticket must cover between 1 and ${days.length} day(s)`);
    }
    let e = p.id ? findEvent(p.id) : null;
    if (e) {
      mustRun(e);
      const gone = dayLoad(e).filter(l => !days.some(d => d.day === l.day) && l.registered > 0);
      if (gone.length) refuse(`People are registered for ${gone.map(l => fmt(l.day)).join(', ')}, so that day cannot be removed. Cancel or move them first.`);
      const removed = e.options.filter(o => !opts.some(x => x.id === o.id) && optionSold(o.id));
      if (removed.length) refuse(`"${removed.map(o => o.name).join(', ')}" has been sold, so it cannot be removed. Take it off sale instead.`);
      for (const x of opts) {
        const old = e.options.find(o => o.id === x.id);
        if (old && optionSold(old.id) && old.days_count !== x.days_count) {
          refuse(`The "${x.name}" ticket has been sold, so the number of days it covers cannot change. Add a new option instead.`);
        }
      }
    } else {
      e = { id: newId('ev'), created_at: new Date().toISOString(), deleted: false } as Ev;
      events.push(e);
    }
    Object.assign(e, {
      name: String(p.name).trim(), description: p.description ?? null, daily_start: p.daily_start ?? null, daily_end: p.daily_end ?? null,
      early_bird_until: p.early_bird_until ?? null, early_bird_percent: p.early_bird_percent ?? null,
      is_active: p.is_active ?? true, notes: p.notes ?? null, days, store_ids: storeIds,
      options: opts.map(o => ({ id: o.id ?? newId('op'), name: String(o.name).trim(), days_count: Number(o.days_count),
        price: Number(o.price), is_active: o.is_active ?? true, sort_order: Number(o.sort_order ?? 0) })),
    });
    return e.id;
  },

  event_delete: ({ p_event_id, p_reason }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can delete events');
    const e = findEvent(p_event_id); mustRun(e);
    if (!String(p_reason ?? '').trim()) refuse('Give a reason for deleting the event');
    if (e.options.some(o => optionSold(o.id))) refuse(`Tickets to "${e.name}" are on invoices, so it cannot be deleted. Take it off sale instead.`);
    e.deleted = true; e.is_active = false;
    return null;
  },

  event_guest_list: ({ p_event_id }) => {
    const e = findEvent(p_event_id); mustRun(e);
    return guests.filter(g => g.event_id === e.id)
      .sort((a, b) => a.status.localeCompare(b.status) || a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
      .map(g => {
        const inv = invoices.find(i => i.id === g.invoice_id);
        return {
          guest_id: g.id, name: g.name, phone: g.phone, customer_id: g.customer_id,
          customer_name: CUSTOMERS.find(c => c.id === g.customer_id)?.full_name ?? null,
          source: g.source, status: g.status, cancelled_reason: g.cancelled_reason, notes: g.notes,
          registered_by: g.registered_by, registered_by_name: nameOf(g.registered_by),
          ticket_option_id: g.ticket_option_id, ticket_option_name: e.options.find(o => o.id === g.ticket_option_id)?.name ?? null,
          invoice_id: g.invoice_id, invoice_no: inv?.invoice_no ?? null, invoice_status: inv?.status ?? null,
          invoice_total: inv ? inv.total_amount.toFixed(2) : null, invoice_paid: inv ? inv.paid_amount.toFixed(2) : null,
          invoice_store_id: inv?.store_id ?? null, created_at: g.created_at,
          days: g.days.map(d => ({ day: d.day, attended_at: d.attended_at, check_in_code: d.check_in_code,
            checked_in_by_name: nameOf(d.checked_in_by) })),
        };
      });
  },

  event_save_guest: ({ p_guest: p }) => {
    const existing = p.id ? guests.find(g => g.id === p.id) ?? refuse('Guest not found') : null;
    const e = findEvent(existing?.event_id ?? p.event_id); mustRun(e);
    if (!String(p.name ?? '').trim()) refuse('Give the guest\'s name');
    let days: string[] = [];
    if (!existing || existing.source === 'free') {
      days = [...new Set<string>(p.days ?? [])].sort();
      if (days.length === 0) refuse('Choose the day(s) the guest is coming');
      if (days.some(d => !e.days.some(x => x.day === d))) refuse('A chosen day is not a day of this event');
    } else if ('days' in p && JSON.stringify([...p.days].sort()) !== JSON.stringify(existing.days.map(d => d.day).sort())) {
      refuse('A ticket guest\'s days come from their invoice. Correct the invoice to change them.');
    }
    const fields = {
      name: String(p.name).trim(), phone: String(p.phone ?? '').trim() || null, customer_id: p.customer_id || null,
      notes: String(p.notes ?? '').trim() || null,
    };
    let g: G;
    if (!existing) {
      g = guest({ ...fields, event_id: e.id, registered_by: p.registered_by || me.id, created_at: new Date().toISOString(),
        days: days.map(d => gday(d)) });
      guests.push(g);
    } else {
      g = existing;
      Object.assign(g, fields, { registered_by: p.registered_by || g.registered_by });
      if (g.source === 'free') {
        const lost = g.days.find(d => d.attended_at && !days.includes(d.day));
        if (lost) refuse(`${g.name} has already checked in on a day being removed. Keep that day.`);
        g.days = days.map(d => g.days.find(x => x.day === d) ?? gday(d));
      }
    }
    return {
      guest_id: g.id,
      over_capacity: dayLoad(e).filter(l => l.capacity != null && l.registered > l.capacity && g.days.some(d => d.day === l.day))
        .map(l => ({ day: l.day, capacity: l.capacity, registered: l.registered })),
    };
  },

  event_set_guest_cancelled: ({ p_guest_id, p_cancelled, p_reason }) => {
    const g = guests.find(x => x.id === p_guest_id) ?? refuse('Guest not found');
    mustRun(findEvent(g.event_id));
    if (g.source !== 'free') refuse('A ticket guest comes from an invoice. Cancel or correct the invoice to remove them.');
    g.status = p_cancelled ? 'cancelled' : 'registered';
    g.cancelled_reason = p_cancelled ? (String(p_reason ?? '').trim() || null) : null;
    return null;
  },

  event_check_in: ({ p_guest_id, p_day, p_attended, p_code }) => {
    const g = guests.find(x => x.id === p_guest_id) ?? refuse('Guest not found');
    mustRun(findEvent(g.event_id));
    if (g.status !== 'registered') refuse(`${g.name} is not registered (cancelled)`);
    const d = g.days.find(x => x.day === p_day) ?? refuse(`${g.name} is not registered for ${fmt(p_day)}`);
    if (p_attended) {
      d.attended_at = d.attended_at ?? new Date().toISOString();
      d.checked_in_by = d.checked_in_by ?? me.id;
      d.check_in_code = String(p_code ?? '').trim() || null;
    } else {
      d.attended_at = null; d.checked_in_by = null; d.check_in_code = null;
    }
    return { guest_id: g.id, day: d.day, attended_at: d.attended_at, check_in_code: d.check_in_code };
  },

  event_invoices: ({ p_event_id }) => {
    const e = findEvent(p_event_id); mustRun(e);
    return invoices
      .map(inv => ({ inv, m: membership(inv) }))
      .filter(x => x.m?.event_id === e.id && hasStore(x.inv.store_id))
      .sort((a, b) => b.inv.business_date.localeCompare(a.inv.business_date) || b.inv.invoice_no.localeCompare(a.inv.invoice_no))
      .map(({ inv, m }) => {
        const ticketLines = inv.lines.filter(l => e.options.some(o => o.id === l.option_id));
        return {
          invoice_id: inv.id, invoice_no: inv.invoice_no, business_date: inv.business_date, store_id: inv.store_id,
          store_name: STORES.find(s => s.id === inv.store_id)?.name ?? null, customer_id: inv.customer_id,
          customer_name: CUSTOMERS.find(c => c.id === inv.customer_id)?.full_name ?? null, status: inv.status,
          total_amount: inv.total_amount.toFixed(2), paid_amount: inv.paid_amount.toFixed(2), source: m!.source,
          ticket_people: ticketLines.reduce((s, l) => s + l.quantity, 0),
          ticket_total: ticketLines.reduce((s, l) => s + l.line_total, 0).toFixed(2),
        };
      });
  },

  // Owners, Admins and Managers see the orders; only the Owner switches the
  // channel. Create invoice matches by phone exactly as a live order is.
  web_orders_list: ({ p_event_id }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can see website orders');
    const e = findEvent(p_event_id);
    const ch = webChannels.find(c => c.event_id === e.id);
    if (!ch) return { channel: null, can_switch: role === 'owner', orders: [] };
    const lastInvoice = (customerId: string) => invoices.filter(i => i.customer_id === customerId)
      .map(i => i.business_date).sort().at(-1) ?? null;
    return {
      channel: { key: ch.key, mode: ch.mode, allow_test: ch.allow_test, store_name: STORES.find(s => s.id === ch.store_id)?.name ?? null,
        acting_name: nameOf(ch.acting_profile_id), payment_method_name: ch.payment_method_name },
      can_switch: role === 'owner',
      orders: webOrders.filter(o => o.channel === ch.key).sort((a, b) => b.paid_at.localeCompare(a.paid_at)).map(o => ({
        id: o.id, stripe_session_id: o.stripe_session_id, livemode: o.livemode, status: o.status, ticket: o.ticket,
        ticket_label: PASSES[o.ticket].label, quantity: o.quantity, unit_amount: o.unit_amount, amount_total: o.amount_total,
        early_bird: o.early_bird, buyer_name: o.buyer_name, buyer_email: o.buyer_email, buyer_phone: o.buyer_phone,
        checkout_opened_at: o.checkout_opened_at, paid_at: o.paid_at, attendees: o.attendees, names_at: o.names_at,
        invoice_id: o.invoice_id, invoice_no: invoices.find(i => i.id === o.invoice_id)?.invoice_no ?? null,
        review_reason: o.review_reason,
        candidates: o.status === 'needs_review' ? o.candidate_ids.map(id => CUSTOMERS.find(c => c.id === id)!).filter(Boolean)
          .map(c => ({ customer_id: c.id, full_name: c.full_name, phone: c.phone, email: c.email, last_invoice_at: lastInvoice(c.id) })) : [],
        created_at: o.paid_at,
      })),
    };
  },

  web_order_apply_names: ({ p_order_id }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can put a website order\'s names on its invoice');
    const o = webOrders.find(x => x.id === p_order_id) ?? refuse('Website order not found');
    if (o.status !== 'invoiced') refuse('Only an invoiced order\'s names can be put on its invoice');
    o.review_reason = null;
    return { status: o.status, invoice_no: null, review_reason: null };
  },
  web_order_resolve: ({ p_order_id, p_customer_id, p_new_customer }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can invoice website orders');
    const o = webOrders.find(x => x.id === p_order_id) ?? refuse('Website order not found');
    if (o.status === 'invoiced') refuse('This order already has an invoice');
    if (o.status === 'refused') refuse('A refused order cannot be invoiced');
    const ch = webChannels.find(c => c.key === o.channel)!;
    // A Stripe test payment is invoiced only while the channel accepts test orders.
    if (!o.livemode && !ch.allow_test) {
      Object.assign(o, { status: 'refused', review_reason: 'A Stripe test payment', candidate_ids: [] });
      return { status: 'refused', invoice_no: null, review_reason: o.review_reason };
    }
    const digits = (p: string | null) => String(p ?? '').replace(/\D/g, '');
    const newCustomer = () => {
      const c = { id: newId('c'), full_name: o.buyer_name, phone: o.buyer_phone ?? '', email: o.buyer_email ?? '', notes: null, deleted_at: null };
      CUSTOMERS.push(c);
      return c.id;
    };
    let customerId: string;
    if (p_customer_id) customerId = CUSTOMERS.find(c => c.id === p_customer_id)?.id ?? refuse('Customer not found');
    else if (p_new_customer) customerId = newCustomer();
    else {
      const same = o.buyer_phone ? CUSTOMERS.filter(c => digits(c.phone) === digits(o.buyer_phone)) : [];
      if (same.length > 1) {
        Object.assign(o, { status: 'needs_review', review_reason: `${same.length} customers have this phone`, candidate_ids: same.map(c => c.id) });
        return { status: 'needs_review', invoice_no: null, review_reason: o.review_reason };
      }
      customerId = same[0]?.id ?? newCustomer();
    }
    const pass = PASSES[o.ticket];
    const inv: Inv = {
      id: newId('inv'), invoice_no: `INV-2026-9${String(++seq).padStart(3, '0')}`,
      // Dated when the checkout opened, so an early bird paid just after the cut-off keeps it.
      business_date: new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' })
        .format(new Date(o.checkout_opened_at)),
      store_id: ch.store_id, customer_id: customerId, status: 'paid', total_amount: o.amount_total, paid_amount: o.amount_total,
      lines: [{ option_id: pass.option_id, days: pass.days, quantity: o.quantity, line_total: o.amount_total }],
    };
    invoices.push(inv);
    for (let i = 0; i < o.quantity; i++) {
      const a = o.attendees?.[i];
      guests.push(guest({ name: a?.name ?? (i === 0 ? o.buyer_name : `${o.buyer_name} +${i}`), phone: a?.whatsapp ?? (i === 0 ? o.buyer_phone : null),
        customer_id: i === 0 ? customerId : null, source: 'ticket', invoice_id: inv.id, ticket_option_id: pass.option_id,
        registered_by: null, created_at: new Date().toISOString(), days: pass.days.map(d => gday(d)) }));
    }
    Object.assign(o, { status: 'invoiced', invoice_id: inv.id, customer_id: customerId, review_reason: null, candidate_ids: [] });
    return { status: 'invoiced', invoice_no: inv.invoice_no, review_reason: null };
  },

  web_order_channel_set_mode: ({ p_key, p_mode }) => {
    if (role !== 'owner') refuse('Only the Owner can switch website orders');
    if (!['off', 'record_only', 'live'].includes(p_mode)) refuse('Choose off, record_only or live');
    const ch = webChannels.find(c => c.key === p_key) ?? refuse('Website channel not found');
    ch.mode = p_mode;
    return null;
  },
};

// ── the client surface the page uses ───────────────────────────────────────
const failing = new Set(new URLSearchParams(typeof location === 'undefined' ? '' : location.search).getAll('fail'));
const TABLES: Record<string, any[]> = { stores: STORES, profiles: PROFILES, customers: CUSTOMERS };
const clone = <T,>(v: T): T => (v === undefined ? v : JSON.parse(JSON.stringify(v)));
const delay = () => new Promise(r => setTimeout(r, 120));

function rpc(name: string, args: any = {}) {
  return delay().then(() => {
    if (failing.has(name)) return { data: null, error: { message: `Preview: ${name} failed` } };
    const fn = rpcs[name];
    if (!fn) return { data: null, error: { message: `The preview has no ${name}` } };
    try { return { data: clone(fn(args)), error: null }; }
    catch (e) { if (e instanceof Refused) return { data: null, error: { message: e.message } }; throw e; }
  });
}

class Query {
  private filters: ((r: any) => boolean)[] = [];
  private orderBy: string | null = null;
  private cap = Infinity;
  private single = false;
  constructor(private table: string) {}
  select() { return this; }
  eq(col: string, v: unknown) { this.filters.push(r => r[col] === v); return this; }
  is(col: string, v: unknown) { this.filters.push(r => (r[col] ?? null) === v); return this; }
  in(col: string, vs: unknown[]) { this.filters.push(r => vs.includes(r[col])); return this; }
  // Only the shape CustomerSearchSelect sends: "col.ilike.%text%,…".
  or(expr: string) {
    const terms = expr.split(',').map(t => t.split('.')).filter(t => t[1] === 'ilike');
    this.filters.push(r => terms.some(([col, , pat]) => String(r[col] ?? '').toLowerCase().includes(pat.replace(/%/g, '').toLowerCase())));
    return this;
  }
  order(col: string) { this.orderBy = col; return this; }
  limit(n: number) { this.cap = n; return this; }
  maybeSingle() { this.single = true; return this; }
  then(res: (v: any) => unknown, rej?: (e: unknown) => unknown) {
    return delay().then(() => {
      let rows = (TABLES[this.table] ?? []).filter(r => this.filters.every(f => f(r)));
      if (this.orderBy) { const c = this.orderBy; rows = [...rows].sort((a, b) => String(a[c]).localeCompare(String(b[c]))); }
      rows = rows.slice(0, this.cap);
      return { data: clone(this.single ? rows[0] ?? null : rows), error: null };
    }).then(res, rej);
  }
}

export const supabase = { rpc, from: (table: string) => new Query(table) } as any;
export default supabase;
