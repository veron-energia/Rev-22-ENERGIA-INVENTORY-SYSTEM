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
// the website channel accepting Stripe test orders; ?planning=fail makes the
// guests' answers fail to load (round 7's warning), ?planning=none answers as a
// database without round 7.
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
// 436: the customer whose phone a website registration also gave (ACMA's fictional mobile range).
CUSTOMERS.push({ id: 'c-11', full_name: 'Customer Eleven', phone: '+61 491 570 737', email: 'customer11@tests.invalid', notes: null, deleted_at: null });

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
  status: 'recorded' | 'invoiced' | 'needs_review' | 'refused' | 'dismissed';
  // 380: 'door' is the website's staff link (cash, PayNow or bank transfer).
  provider: 'stripe' | 'hitpay' | 'door'; door_method: 'cash' | 'paynow' | 'bank' | null;
  payment_reference: string | null; paid_on: string | null; staff_profile_id: string | null;
  ticket: 'both' | 'day1' | 'day2'; quantity: number; unit_amount: number; amount_total: number; early_bird: boolean;
  buyer_name: string; buyer_email: string | null; buyer_phone: string | null;
  checkout_opened_at: string; paid_at: string; attendees: WebPerson[] | null; names_at: string | null;
  invoice_id: string | null; customer_id: string | null; review_reason: string | null; candidate_ids: string[];
  // 403: the name parts the buyer registered with, and a phone taken from the registration.
  buyer_first_name?: string | null; buyer_last_name?: string | null; phone_from_registration?: boolean;
  // 415: what a close as refunded changed (the server reads it from the close's audit row).
  closedFrom?: { status: WebOrder['status']; review_reason: string | null };
};
// ?allow_test=0 previews the channel once it no longer accepts Stripe test
// orders: the test order recorded before then cannot be invoiced.
const webChannels = [{
  key: 'preview-open-days-2026', event_id: 'ev-open-days', mode: 'record_only',
  allow_test: new URLSearchParams(typeof location === 'undefined' ? '' : location.search).get('allow_test') !== '0',
  store_id: 'st-north', acting_profile_id: 'u-owner', payment_method_name: 'Stripe (online)',
}];
// The pass price on a date paid: half until the early-bird day, as the server prices it.
const EARLY_UNTIL = addDays(TODAY, -10);
const priced = (full: number) => (day: string) => (day <= EARLY_UNTIL ? eb(full) : full);
const PASSES = {
  both: { label: 'Both days', option_id: 'op-2days', days: [D1, D2], price: priced(94) },
  day1: { label: 'Day 1 only', option_id: 'op-1day', days: [D1], price: priced(61) },
  day2: { label: 'Day 2 only', option_id: 'op-1day', days: [D2], price: priced(61) },
};
const person = (name: string, n: string): WebPerson => ({ name, email: `guest${n}@tests.invalid`, whatsapp: `+65 9123 00${n}` });
const webOrder = (o: Partial<WebOrder> & Pick<WebOrder, 'id' | 'ticket' | 'quantity' | 'unit_amount' | 'buyer_name' | 'paid_at'>): WebOrder => ({
  channel: 'preview-open-days-2026', stripe_session_id: `cs_live_preview${o.id.replace(/\W/g, '')}0000`, livemode: true,
  status: 'recorded', amount_total: o.unit_amount * o.quantity, early_bird: false, buyer_email: null, buyer_phone: null,
  checkout_opened_at: o.paid_at, attendees: null, names_at: null, invoice_id: null, customer_id: null, review_reason: null,
  candidate_ids: [], provider: 'stripe', door_method: null, payment_reference: null, paid_on: null, staff_profile_id: null, ...o,
});
// 380: "02 Oct 2026", as the server words its reasons.
function dayLabel(day: string) {
  const [y, m, d] = day.split('-').map(Number);
  return `${String(d).padStart(2, '0')} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1]} ${y}`;
}
// 380: a staff-link registration, as the website's staff form sends it.
const doorOrder = (o: Partial<WebOrder> & Pick<WebOrder, 'id' | 'ticket' | 'quantity' | 'unit_amount' | 'buyer_name' | 'paid_at'>) =>
  webOrder({ provider: 'door', stripe_session_id: `OFF-20261002-${o.id.replace(/\D/g, '').padStart(6, '0')}`,
    door_method: 'paynow', paid_on: o.paid_at.slice(0, 10), ...o });
// Made by hand at the counter for a staff-link buyer, before staff-link orders came in.
invoices.push({ id: 'inv-hand-1', invoice_no: 'INV-2026-9020', business_date: addDays(TODAY, -1), store_id: 'st-north',
  customer_id: 'c-01', status: 'paid', total_amount: 61, paid_amount: 61,
  lines: [{ option_id: 'op-1day', days: [D1], quantity: 1, line_total: 61 }] });
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
  // 380: staff-link registrations. Recorded, waiting for a Manager to check the money.
  doorOrder({ id: 'wo-6', ticket: 'both', quantity: 2, unit_amount: 94, buyer_name: 'Guest Twenty-Six',
    buyer_phone: '+65 9123 0036', buyer_email: 'guest36@tests.invalid', paid_at: at(TODAY, '10:12'),
    payment_reference: 'PN 0042', staff_profile_id: 'u-staff',
    attendees: [person('Guest Twenty-Six', '36'), person('Guest Twenty-Seven', '37')], names_at: at(TODAY, '10:12') }),
  // The amount on the form is not the price on the date paid.
  doorOrder({ id: 'wo-7', status: 'needs_review', ticket: 'day1', quantity: 1, unit_amount: 50, door_method: 'cash',
    buyer_name: 'Guest Twenty-Eight', buyer_phone: '+65 9123 0038', paid_at: at(TODAY, '11:30'),
    attendees: [person('Guest Twenty-Eight', '38')], names_at: at(TODAY, '11:30'),
    review_reason: `S$50.00 was paid, but 1 × "1 Day" paid on ${dayLabel(TODAY)} costs S$61.00` }),
  // Its buyer was already invoiced by hand (INV-2026-9020): link it rather than invoice it again.
  doorOrder({ id: 'wo-8', ticket: 'day1', quantity: 1, unit_amount: 61, door_method: 'bank',
    buyer_name: 'Customer One', buyer_phone: '+65 9123 0001', paid_at: at(addDays(TODAY, -1), '16:05'),
    payment_reference: 'DBS 7781', attendees: [person('Customer One', '01')], names_at: at(addDays(TODAY, -1), '16:05') }),
  // A test registration a Manager set aside.
  doorOrder({ id: 'wo-9', status: 'dismissed', ticket: 'day2', quantity: 1, unit_amount: 61, door_method: 'cash',
    buyer_name: 'Test Buyer', buyer_phone: '+65 9123 0039', paid_at: at(addDays(TODAY, -2), '09:00'),
    attendees: [person('Test Buyer', '39')], names_at: at(addDays(TODAY, -2), '09:00'),
    review_reason: 'A test registration' }),
  // 403: HitPay gave no name and no phone; the buyer registered without a WhatsApp.
  webOrder({ id: 'wo-10', provider: 'hitpay', stripe_session_id: '5f1c2a7e-0d4b-4c39-9a51-000000000010', status: 'needs_review',
    ticket: 'day1', quantity: 1, unit_amount: 61, buyer_name: 'Website buyer', buyer_email: 'guest40@tests.invalid',
    buyer_first_name: 'Guest', buyer_last_name: 'Forty', paid_at: at(TODAY, '08:40'),
    attendees: [{ name: 'Guest Forty', email: null, whatsapp: null }], names_at: at(TODAY, '09:15'),
    review_reason: 'The buyer\'s phone number could not be read, so the customer must be chosen' }),
  // 403: HitPay gave no phone; the WhatsApp the buyer registered with is shared by two customers.
  webOrder({ id: 'wo-11', provider: 'hitpay', stripe_session_id: '5f1c2a7e-0d4b-4c39-9a51-000000000011', status: 'needs_review',
    ticket: 'day2', quantity: 1, unit_amount: 61, buyer_name: 'Website buyer', buyer_phone: '+6591230020',
    buyer_first_name: 'Guest', buyer_last_name: 'Forty-One', phone_from_registration: true, paid_at: at(TODAY, '07:50'),
    attendees: [{ name: 'Guest Forty-One', email: null, whatsapp: null }], names_at: at(TODAY, '08:05'),
    review_reason: '2 customers share the buyer\'s phone, so the customer must be chosen', candidate_ids: ['c-09', 'c-10'] }),
];
// The invoiced order's people, on the guest list from its invoice.
guests.push(...webOrders[0].attendees!.map(a => guest({ name: a.name, phone: a.whatsapp, customer_id: a.name === 'Guest Twenty' ? 'c-03' : null,
  source: 'ticket', invoice_id: 'inv-web-1', ticket_option_id: 'op-1day', registered_by: null, days: [gday(D1)] })));

// ── the rules, as the server applies them ──────────────────────────────────
class Refused extends Error {}
const refuse = (msg: string): never => { throw new Refused(msg); };
// 380 helpers: hand invoices with the buyer's phone, the link rules, emails and methods.
const phoneDigits = (p: string | null | undefined) => String(p ?? '').replace(/\D/g, '');
const linked = (invId: string) => webOrders.some(o => o.invoice_id === invId);
function handInvoices(o: WebOrder) {
  const ids = CUSTOMERS.filter(c => o.buyer_phone && phoneDigits(c.phone) === phoneDigits(o.buyer_phone)).map(c => c.id);
  return invoices.filter(i => ids.includes(i.customer_id) && !linked(i.id) && i.lines.some(l => l.option_id.startsWith('op-')))
    .map(i => ({ invoice_no: i.invoice_no, store: STORES.find(s => s.id === i.store_id)?.name ?? null }));
}
function linkTarget(orderId: string, invoiceNo: string) {
  const o = webOrders.find(x => x.id === orderId) ?? refuse('Website order not found');
  // 415: an order refused while the channel was off can be linked too, from the website or the staff link.
  if (o.status !== 'recorded' && o.status !== 'needs_review'
      && !(o.status === 'refused' && o.review_reason === 'The website channel is off')) {
    refuse('Only an order waiting for an invoice can be linked');
  }
  if (!o.livemode) refuse('A test payment is not linked to an invoice');
  const inv = invoices.find(i => i.invoice_no.toLowerCase() === String(invoiceNo ?? '').trim().toLowerCase())
    ?? refuse(`No invoice ${String(invoiceNo ?? '').trim()}`);
  if (linked(inv.id)) refuse(`${inv.invoice_no} is already another website order's invoice`);
  if (!guests.some(g => g.invoice_id === inv.id && g.source === 'ticket') && !inv.lines.some(l => l.option_id.startsWith('op-')))
    refuse(`${inv.invoice_no} has no ticket for this event`);
  return { o, inv };
}
const webPersonEmail = (g: { invoice_id: string | null; name: string }) =>
  webOrders.find(o => o.invoice_id && o.invoice_id === g.invoice_id)?.attendees?.find(a => a.name === g.name)?.email ?? null;
const paymentMethodsOf = (invId: string) => {
  const o = webOrders.find(x => x.invoice_id === invId);
  if (!o) return invId === 'inv-hand-1' ? 'Bank Transfer' : 'Cash';
  return o.provider === 'door' ? ({ cash: 'Cash', paynow: 'PayNow', bank: 'Bank Transfer' } as const)[o.door_method!] : 'Stripe (online)';
};
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
    // 415: the ticket lines covering the day (this stub has no deleted invoices).
    const ticketLines = invoices.flatMap(i => i.lines)
      .filter(l => e.options.some(o => o.id === l.option_id) && l.days.includes(d.day)).length;
    return { day: d.day, capacity: d.capacity, registered: on.length, attended: on.filter(x => x.attended_at).length,
      ticket_lines: ticketLines };
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
      sold: optionSold(o.id), on_any_invoice: optionSold(o.id),
    })),
    guests: reg.length, ticket_guests: reg.filter(g => g.source === 'ticket').length,
    free_guests: reg.filter(g => g.source === 'free').length,
    can_manage: isManager, can_run: canRun(e),
    web_channel_mode: webChannels.find(c => c.event_id === e.id)?.mode ?? null,
  };
}

// 415 (EVENTS-4): the ticket's event first, then the event on that day at that store.
function membership(inv: Inv): { event_id: string; source: 'staff' | 'event_day' | 'ticket' } | null {
  if (inv.marked_event_id) return { event_id: inv.marked_event_id, source: 'staff' };
  const onDay = events.find(e => !e.deleted && e.store_ids.includes(inv.store_id) && e.days.some(d => d.day === inv.business_date));
  const byTicket = events.find(e => !e.deleted && inv.lines.some(l => e.options.some(o => o.id === l.option_id)));
  const chosen = byTicket ?? onDay;
  if (!chosen) return null;
  return { event_id: chosen.id, source: onDay && onDay.id === chosen.id ? 'event_day' : 'ticket' };
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
          // 380: the customer's email (else the website order's), the order, the invoice's payment methods.
          email: CUSTOMERS.find(c => c.id === g.customer_id)?.email || webPersonEmail(g) || null,
          order_id: webOrders.find(o => o.invoice_id && o.invoice_id === g.invoice_id)?.stripe_session_id ?? null,
          payment_methods: inv ? paymentMethodsOf(inv.id) : null,
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

  // 415: a guest who has checked in is not cancelled; a restore drops the days
  // the event no longer has and answers the days now over capacity.
  event_set_guest_cancelled: ({ p_guest_id, p_cancelled, p_reason }) => {
    const g = guests.find(x => x.id === p_guest_id) ?? refuse('Guest not found');
    const e = findEvent(g.event_id);
    mustRun(e);
    if (g.source !== 'free') refuse('A ticket guest comes from an invoice. Cancel or correct the invoice to remove them.');
    if (p_cancelled && g.status === 'registered' && g.days.some(d => d.attended_at)) {
      refuse(`${g.name} has already checked in. Undo the check-in first if they did not come.`);
    }
    let dropped: string[] = [];
    if (!p_cancelled && g.status === 'cancelled') {
      dropped = g.days.filter(d => !e.days.some(x => x.day === d.day)).map(d => d.day);
      if (dropped.length === g.days.length) refuse(`None of ${g.name}'s days are still days of this event. Add them again with the right day.`);
      g.days = g.days.filter(d => !dropped.includes(d.day));
    }
    g.status = p_cancelled ? 'cancelled' : 'registered';
    g.cancelled_reason = p_cancelled ? (String(p_reason ?? '').trim() || null) : null;
    return {
      guest_id: g.id, status: g.status, days_dropped: dropped,
      over_capacity: p_cancelled ? [] : dayLoad(e)
        .filter(l => l.capacity != null && l.registered > l.capacity && g.days.some(d => d.day === l.day))
        .map(l => ({ day: l.day, capacity: l.capacity, registered: l.registered })),
    };
  },

  // 415: a check-in never changes one already made (already_in); only Save
  // code (p_save_code) changes a code; Undo clears the check-in.
  event_check_in: ({ p_guest_id, p_day, p_attended, p_code, p_save_code }) => {
    const g = guests.find(x => x.id === p_guest_id) ?? refuse('Guest not found');
    mustRun(findEvent(g.event_id));
    if (g.status !== 'registered') refuse(`${g.name} is not registered (cancelled)`);
    const d = g.days.find(x => x.day === p_day) ?? refuse(`${g.name} is not registered for ${fmt(p_day)}`);
    const wasIn = !!d.attended_at;
    const code = String(p_code ?? '').trim() || null;
    let changed = false;
    if (p_save_code) {
      if (!p_attended) refuse('A code is saved with a check-in, not with an undo');
      if (!wasIn) refuse(`${g.name} is not checked in for ${fmt(p_day)} yet. Check them in first.`);
      changed = d.check_in_code !== code;
      d.check_in_code = code;
    } else if (p_attended) {
      if (!wasIn) { d.attended_at = new Date().toISOString(); d.checked_in_by = me.id; d.check_in_code = code; changed = true; }
    } else if (wasIn || d.check_in_code) {
      d.attended_at = null; d.checked_in_by = null; d.check_in_code = null; changed = true;
    }
    return {
      guest_id: g.id, day: d.day, attended_at: d.attended_at, check_in_code: d.check_in_code,
      checked_in_by: d.checked_in_by, checked_in_by_name: nameOf(d.checked_in_by),
      already_in: !!p_attended && !p_save_code && wasIn, changed,
    };
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
        // 403
        buyer_first_name: o.buyer_first_name ?? null, buyer_last_name: o.buyer_last_name ?? null,
        buyer_phone_readable: !!o.buyer_phone, buyer_phone_from_registration: !!o.phone_from_registration,
        checkout_opened_at: o.checkout_opened_at, paid_at: o.paid_at, attendees: o.attendees, names_at: o.names_at,
        invoice_id: o.invoice_id, invoice_no: invoices.find(i => i.id === o.invoice_id)?.invoice_no ?? null,
        review_reason: o.review_reason,
        candidates: o.status === 'needs_review' ? o.candidate_ids.map(id => CUSTOMERS.find(c => c.id === id)!).filter(Boolean)
          .map(c => ({ customer_id: c.id, full_name: c.full_name, phone: c.phone, email: c.email, last_invoice_at: lastInvoice(c.id) })) : [],
        created_at: o.paid_at,
        provider: o.provider, door_method: o.door_method, payment_reference: o.payment_reference, paid_on: o.paid_on,
        staff_profile_id: o.staff_profile_id, staff_name: nameOf(o.staff_profile_id),
        hand_invoices: o.status === 'recorded' || o.status === 'needs_review' ? handInvoices(o) : [],
      })),
    };
  },

  // 380: link a staff-link order to an invoice made by hand, after a preview.
  web_order_link_preview: ({ p_order_id, p_invoice_no }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can link a website order');
    const { o, inv } = linkTarget(p_order_id, p_invoice_no);
    const people = guests.filter(g => g.invoice_id === inv.id && g.source === 'ticket').length;
    const warnings: string[] = [];
    if (inv.total_amount !== o.amount_total) warnings.push(`The invoice is S$${inv.total_amount.toFixed(2)} but the order says S$${o.amount_total.toFixed(2)}`);
    if (people !== o.quantity) warnings.push(`The invoice has ${people} ticket people but the order has ${o.quantity}`);
    return { invoice_no: inv.invoice_no, store: STORES.find(s => s.id === inv.store_id)?.name ?? null, date: inv.business_date,
      customer_name: CUSTOMERS.find(c => c.id === inv.customer_id)?.full_name ?? null, total: inv.total_amount, paid: inv.paid_amount,
      methods: 'Bank Transfer', people, warnings };
  },
  web_order_link_invoice: ({ p_order_id, p_invoice_no }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can link a website order');
    const { o, inv } = linkTarget(p_order_id, p_invoice_no);
    Object.assign(o, { status: 'invoiced', invoice_id: inv.id, customer_id: inv.customer_id, review_reason: null, candidate_ids: [] });
    return { status: 'invoiced', invoice_no: inv.invoice_no, review_reason: null };
  },
  web_order_dismiss: ({ p_order_id, p_reason, p_dismiss }) => {
    if (!isManager) refuse('Only an Owner, Admin or Manager can dismiss a staff-link registration');
    const o = webOrders.find(x => x.id === p_order_id) ?? refuse('Website order not found');
    if (o.provider !== 'door') refuse('Only a staff-link registration can be dismissed');
    if (p_dismiss === false) {
      if (o.status !== 'dismissed') refuse('This registration is not dismissed');
      // 415: one closed as refunded is reopened with Reopen, not restored.
      if (o.closedFrom) refuse('This order was closed as refunded. Use Reopen instead.');
      Object.assign(o, { status: 'recorded', review_reason: null });
    } else {
      if (o.status !== 'recorded' && o.status !== 'needs_review') refuse('Only a registration waiting for an invoice can be dismissed');
      if (String(p_reason ?? '').trim().length < 3) refuse('Say why it is dismissed');
      if (String(p_reason).trim().startsWith('Refunded outside the app:'))
        refuse('Start the reason another way. "Refunded outside the app:" marks an order closed as refunded.');
      Object.assign(o, { status: 'dismissed', review_reason: String(p_reason).trim() });
    }
    return { status: o.status, invoice_no: null, review_reason: o.review_reason };
  },
  // 415: an Owner or Manager closes an order refunded outside the app, or reopens it.
  web_order_close_refunded: ({ p_order_id, p_reason, p_close }) => {
    if (!isManager) refuse('Your role cannot do this.');
    const reason = String(p_reason ?? '').trim();
    if (reason.length < 3) refuse('Give the reason (at least 3 characters)');
    const o = webOrders.find(x => x.id === p_order_id) ?? refuse('Website order not found');
    if (p_close === false) {
      const before = o.closedFrom;
      if (o.status !== 'dismissed' || !String(o.review_reason ?? '').startsWith('Refunded outside the app: ') || !before)
        return refuse('Only an order closed as refunded can be reopened');
      // 415: put back as it was before the close: refused again, or waiting in Needs review.
      if (before.status === 'refused') Object.assign(o, { status: 'refused', review_reason: before.review_reason });
      else Object.assign(o, { status: 'needs_review',
        review_reason: 'Reopened after it was closed as refunded. Check the payment, then create or link its invoice.' });
      o.closedFrom = undefined;
    } else {
      const waits = o.status === 'recorded' || o.status === 'needs_review'
        || (o.status === 'refused' && o.livemode && o.review_reason === 'The website channel is off');
      if (!waits) refuse('Only an order waiting for its invoice, or a payment refused while the channel was off, can be closed');
      o.closedFrom = { status: o.status, review_reason: o.review_reason };
      Object.assign(o, { status: 'dismissed', review_reason: `Refunded outside the app: ${reason}` });
    }
    return { status: o.status, invoice_no: null, review_reason: o.review_reason };
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
    if (o.status === 'dismissed') refuse('A dismissed registration is not invoiced; restore it first');
    const ch = webChannels.find(c => c.key === o.channel)!;
    if (o.provider === 'door' && o.amount_total !== PASSES[o.ticket].price(o.paid_on!) * o.quantity) {
      Object.assign(o, { status: 'needs_review' });
      refuse(`The invoice would be S$${(PASSES[o.ticket].price(o.paid_on!) * o.quantity).toFixed(2)} but S$${o.amount_total.toFixed(2)} was paid, so nothing was invoiced`);
    }
    // A Stripe test payment is invoiced only while the channel accepts test orders.
    if (!o.livemode && !ch.allow_test) {
      Object.assign(o, { status: 'refused', review_reason: 'A Stripe test payment', candidate_ids: [] });
      return { status: 'refused', invoice_no: null, review_reason: o.review_reason };
    }
    const digits = (p: string | null) => String(p ?? '').replace(/\D/g, '');
    const newCustomer = () => {
      const c = { id: newId('c'), full_name: [o.buyer_first_name, o.buyer_last_name].filter(Boolean).join(' ') || o.buyer_name, phone: o.buyer_phone ?? '', email: o.buyer_email ?? '', notes: null, deleted_at: null };
      CUSTOMERS.push(c);
      return c.id;
    };
    // A new customer, or a match, needs the buyer's phone (web_order_customer).
    if (!p_customer_id && !digits(o.buyer_phone)) {
      Object.assign(o, { status: 'needs_review', review_reason: 'The buyer\'s phone number could not be read, so the customer must be chosen', candidate_ids: [] });
      return { status: 'needs_review', invoice_no: null, review_reason: o.review_reason };
    }
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
      business_date: o.paid_on ?? new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' })
        .format(new Date(o.checkout_opened_at)),
      store_id: ch.store_id, customer_id: customerId, status: 'paid', total_amount: o.amount_total, paid_amount: o.amount_total,
      lines: [{ option_id: pass.option_id, days: pass.days, quantity: o.quantity, line_total: o.amount_total }],
    };
    invoices.push(inv);
    for (let i = 0; i < o.quantity; i++) {
      const a = o.attendees?.[i];
      guests.push(guest({ name: a?.name ?? (i === 0 ? o.buyer_name : `${o.buyer_name} +${i}`), phone: a?.whatsapp ?? (i === 0 ? o.buyer_phone : null),
        customer_id: i === 0 ? customerId : null, source: 'ticket', invoice_id: inv.id, ticket_option_id: pass.option_id,
        registered_by: o.staff_profile_id, created_at: new Date().toISOString(), days: pass.days.map(d => gday(d)) }));
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

  // 436: the event's own website, for Anniversary Open Days: its first ticket
  // guest is a VIP, one person waits to be matched, two VIP orders, the
  // Website tab's settings, keys and test rows. Gifts and keys change memory.
  event_web_guest_extras: ({ p_event_id }) => {
    if (p_event_id !== 'ev-open-days') return { settings: null, guests: [], holds: [], gift_choices: [], can_close_holds: isManager, can_undo_gifts: isManager };
    const vip = guests.find(g => g.event_id === p_event_id && g.source === 'ticket' && g.status === 'registered');
    return {
      settings: { store_id: 'st-north', store_name: 'North Store', vip_option_id: null, mode: 'record_only', code: 'OPEN-DAYS-2026',
        venue: null, site_url: 'https://seminar.example.com', gift_store_access: true },
      guests: vip ? [{ guest_id: vip.id, person_id: null, website: false, is_test: false, registration_id: null, position: null, group_size: null,
        parked: false, vip: 'paid', vip_guest: true, vip_invoice_no: null, vip_waiting: null, hold: null, closed: false, match: null,
        referral: null, upgrade_token: null, gift: previewGifts[vip.id] ?? null }] : [],
      holds: [{ person_id: 'pp-held', guest_id: null, registration_id: 'REG-20261020-PREV0001', position: 1, group_size: 1,
        held_at: new Date().toISOString(), reason: 'phone_in_use', full_name: 'Website Person', phone: '+61 491 570 737', email: 'webperson@tests.invalid',
        days: [D1], vip_waiting: true,
        candidates: CUSTOMERS.filter(c => c.phone === '+61 491 570 737').map(c => ({ customer_id: c.id, full_name: c.full_name, phone: c.phone,
          email: c.email, created_at: '2026-01-01T00:00:00Z', phone_matches: true, email_matches: false, name_matches: false })) },
        // R6-4: someone gave the affiliate's own name (Customer Three's link) on a phone and email not on her record.
        { person_id: 'pp-aff', guest_id: null, registration_id: 'REG-20261021-PREV0002', position: 1, group_size: 1,
          held_at: new Date().toISOString(), reason: 'affiliate_name', full_name: 'Customer Three', phone: '+61 491 572 983',
          email: 'customer.three.new@example.com', days: [D2], vip_waiting: false, affiliate_name: 'Customer Three',
          referral_note: 'Not referred: the same name as Customer Three, the affiliate whose link (AFF003) was used. If this is Customer Three, link her record: she earns no commission from it. If it is someone else, make a new customer: they are not referred through this link either.',
          candidates: CUSTOMERS.filter(c => c.id === 'c-03').map(c => ({ customer_id: c.id, full_name: c.full_name, phone: c.phone,
            email: c.email, created_at: '2026-01-01T00:00:00Z', phone_matches: false, email_matches: false, name_matches: true })) }],
      gift_choices: [{ product_id: 'pr-socks', name: 'Energia Socks - Black', stock: 13 }, { product_id: 'pr-gloves', name: 'Energia Gloves', stock: 0 }],
      can_close_holds: isManager, can_undo_gifts: isManager,
    };
  },
  event_vip_gift_give: ({ p_guest_id, p_product_id }) => {
    previewGifts[p_guest_id] = { gift_id: newId('gift'), product_id: p_product_id, product_name: 'Energia Socks - Black', use_no: 'USE-000123',
      day: D1, given_at: new Date().toISOString(), given_by_name: me.full_name };
    return { ...previewGifts[p_guest_id], remaining: 12, replayed: false };
  },
  event_vip_gift_undo: ({ p_gift_id }) => {
    if (!isManager) refuse('Your role cannot do this.');
    for (const k of Object.keys(previewGifts)) if (previewGifts[k]?.gift_id === p_gift_id) previewGifts[k] = null;
    return { ok: true, message: 'Put the item back with Stock, Adjust (an adjustment request), quoting USE-000123.' };
  },
  event_registration_attach: () => ({ ok: true, vip_orders: [] }),
  event_registration_create_customer: () => ({ ok: true, vip_orders: [] }),
  event_registration_close: () => { if (!isManager) refuse('Your role cannot do this.'); return { ok: true }; },
  event_vip_orders_list: ({ p_event_id }) => (p_event_id !== 'ev-open-days' ? { settings: null, orders: [], can_close: false } : {
    settings: { mode: 'record_only', code: 'OPEN-DAYS-2026', store_name: 'North Store', hitpay_method_name: 'HitPay (online)',
      paynow_method_name: 'PayNow', bank_method_name: 'Bank Transfer' },
    can_close: isManager,
    orders: [
      { id: 'vo-1', order_id: 'VIP-20261020-PREV0001', provider: 'paynow', status: 'needs_review', is_test: false, livemode: true,
        unit_amount: 72, quantity: 1, amount_total: 72, amount_paid: 72, payer_name: 'Website Person', payer_email: 'webperson@tests.invalid',
        payer_phone: '+61 491 570 737', checkout_opened_at: null, expires_at: null, expired: false, paid_at: null, paid_on: D1, reference: 'PN 4455',
        review_reason: 'Person 1 on this order is still to be matched to a customer (Guests, To match)', refusal: null, waiting_for_match: false,
        test_note: null, test_would: null, refunded_total: 0, refund_noted_at: null, refund_covered: false, created_at: new Date().toISOString(),
        people: [{ person_id: 'pp-held', position: 1, name: 'Website Person', match: 'held', customer_id: null, customer_name: null, days: [D1] }] },
      { id: 'vo-2', order_id: 'VIP-20261020-PREV0002', provider: 'hitpay', status: 'recorded', is_test: false, livemode: true,
        unit_amount: 72, quantity: 2, amount_total: 144, amount_paid: 144, payer_name: 'Customer One', payer_email: 'customer1@tests.invalid',
        payer_phone: null, checkout_opened_at: new Date().toISOString(), paid_at: new Date().toISOString(), paid_on: D1,
        reference: null, review_reason: null, refunded_total: 0, refund_covered: false, created_at: new Date().toISOString(),
        people: [{ person_id: 'pp-1', position: 1, name: 'Customer One', match: 'exact', customer_id: 'c-01', customer_name: 'Customer One', days: [D1, D2] },
                 { person_id: 'pp-2', position: 2, name: 'Customer Two', match: 'exact', customer_id: 'c-02', customer_name: 'Customer Two', days: [D2] }] },
    ],
  }),
  event_vip_order_invoice: () => ({ status: 'invoiced', review_reason: null, invoice_nos: ['INV-PREVIEW-0001'] }),
  event_vip_order_dismiss: () => ({ ok: true }),
  event_vip_order_close_refunded: () => { if (!isManager) refuse('Your role cannot do this.'); return { ok: true }; },
  event_web_settings_get: ({ p_event_id }) => ({
    event_id: p_event_id, event_name: events.find(e => e.id === p_event_id)?.name ?? '',
    settings: p_event_id !== 'ev-open-days' ? null : {
      event_id: p_event_id, code: 'OPEN-DAYS-2026', mode: 'record_only', venue: null, store_id: 'st-north', store_name: 'North Store',
      acting_profile_id: 'u-owner', acting_name: 'Preview Owner', vip_option_id: null, vip_option_name: null, vip_voucher_ids: [],
      gift_product_ids: ['pr-socks', 'pr-gloves'], hitpay_payment_method_id: 'pm-hitpay', paynow_payment_method_id: 'pm-paynow',
      bank_payment_method_id: null, source_option_id: null, source_label: null, source_details: null,
      sync_url: 'https://seminar.example.com/api/app/sync', site_url: 'https://seminar.example.com', last_sync_at: null, last_test_sync_at: null },
    readiness: { blocking: [], errors: ['Choose the VIP ticket.'], warnings: ['No live key yet.',
      ...(talkTitles === null ? ['The talk titles are the suggested list: set the real ones under Talk titles once the speakers\' titles are known.'] : [])] },
    endpoint_path: '/functions/v1/event-website',
    keys: previewKeys,
    requests: [{ type: 'event_info', received_at: new Date().toISOString(), outcome: 'ok', kind: 'test', is_write: false }],
    test: { registrations: [], orders: [] },
    choices: {
      stores: STORES.slice(0, 1).map(x => ({ id: x.id, name: x.name })),
      profiles: PROFILES.filter(x => ['owner', 'manager'].includes(x.role)).map(x => ({ id: x.id, full_name: x.full_name, role: x.role })),
      options: (events.find(e => e.id === p_event_id)?.options ?? []).map(o => ({ id: o.id, name: o.name, days_count: o.days_count, price: o.price, is_active: o.is_active })),
      vouchers: [{ id: 'v-72', name: '$72 discount Voucher', code: 'SAVE72', priced_at_store: false }, { id: 'v-3in1', name: '3-in-1 Vouchers', code: '3-in-1', priced_at_store: true }],
      products: [{ id: 'pr-socks', name: 'Energia Socks - Black', sku: 'SOCK-B', stock: 13 }, { id: 'pr-gloves', name: 'Energia Gloves', sku: 'GLOVE', stock: 0 }],
      methods: [{ id: 'pm-hitpay', name: 'HitPay (online)' }, { id: 'pm-paynow', name: 'PayNow' }, { id: 'pm-bank', name: 'Bank Transfer' }],
      sources: [{ id: 'so-1', label: 'Event Name', requires_details: true }],
    },
    can_manage: role === 'owner', can_clear_tests: isManager, can_set_venue: isManager,
    // 436 round 7 (S4).
    talks: { titles: effectiveTitles(), saved: talkTitles !== null, suggested: [...SUGGESTED_TALK_TITLES] },
    can_set_talks: isManager && p_event_id === 'ev-open-days',
  }),
  event_web_settings_save: () => { if (role !== 'owner') refuse('Your role cannot do this.'); return { ok: true }; },
  event_web_set_venue: ({ p_venue }) => ({ ok: true, venue: p_venue }),
  event_web_key_create: ({ p_kind, p_label }) => {
    if (role !== 'owner') refuse('Your role cannot do this.');
    const key = `evk_${p_kind}_${'Prev1ewKey'.repeat(4)}abc`;
    previewKeys.unshift({ id: newId('k'), kind: p_kind, key_hint: `evk_${p_kind}_Prev…eabc`, label: p_label, created_at: new Date().toISOString(),
      created_by_name: me.full_name, last_used_at: null, revoked_at: null, revoked_by_name: null, revoked_reason: null });
    return { key_id: previewKeys[0].id, kind: p_kind, key_hint: previewKeys[0].key_hint, key };
  },
  event_web_key_revoke: ({ p_key_id, p_reason }) => {
    const k = previewKeys.find(x => x.id === p_key_id) ?? refuse('Key not found');
    Object.assign(k, { revoked_at: new Date().toISOString(), revoked_by_name: me.full_name, revoked_reason: p_reason });
    return { ok: true };
  },
  event_web_test_clear: () => ({ registrations: 0, orders: 0, requests: 0 }),

  // 436 round 7: the guests' planning answers (S1-S4).
  event_planning_list: ({ p_event_id }) => {
    const e = findEvent(p_event_id); mustRun(e);
    return {
      talk_titles: effectiveTitles(), talk_titles_saved: talkTitles !== null,
      hours: { daily_start: e.daily_start, daily_end: e.daily_end },
      guests: guests.filter(g => g.event_id === e.id && planAnswers[g.id]).map(g => ({
        guest_id: g.id, plan_id: `plan-${g.id}`, days: g.days.map(d => d.day), ...planRecord(g.id),
      })),
    };
  },
  event_planning_save: ({ p_guest_id, p_answers, p_version, p_note }) => {
    const g = guests.find(x => x.id === p_guest_id) ?? refuse('Guest not found');
    mustRun(findEvent(g.event_id));
    if (String(p_note ?? '').trim().length > 200) refuse('The note is at most 200 characters');
    const cur = planAnswers[g.id];
    if (cur && JSON.stringify(cur.answers) === JSON.stringify(p_answers)) return { ok: true, guest_id: g.id, changed: false, ...planRecord(g.id) };
    if ((cur?.version ?? 0) !== (p_version ?? 0)) {
      refuse(`These answers were changed by ${cur?.updated_by === 'staff' ? nameOf(cur.staff_id) ?? 'staff' : 'the guest on the website'} since you opened them. Close this and open them again.`);
    }
    planAnswers[g.id] = { version: (cur?.version ?? 0) + 1, answers: p_answers, updated_at: new Date().toISOString(), updated_by: 'staff', staff_id: me.id };
    return { ok: true, guest_id: g.id, ...planRecord(g.id) };
  },
  event_planning_summary: ({ p_event_id }) => {
    const e = findEvent(p_event_id); mustRun(e);
    return planningSummary(e);
  },
  event_web_set_talks: ({ p_event_id, p_titles }) => {
    if (!isManager) refuse('Your role cannot do this.');
    if (p_event_id !== 'ev-open-days') refuse('Save the website settings first');
    if (p_titles === null) talkTitles = null;
    else {
      const out: string[] = [];
      for (const x of p_titles as string[]) {
        const t = String(x ?? '').replace(/\s+/g, ' ').trim();
        if (!t) continue;
        if (t.length > 120) refuse(`A talk title is at most 120 characters: ${t.slice(0, 40)}…`);
        if (out.some(y => y.toLowerCase() === t.toLowerCase())) refuse(`Each talk title only once: ${t}`);
        out.push(t);
      }
      if (out.length > 20) refuse('At most 20 talk titles');
      talkTitles = out;
    }
    return { ok: true, talk_titles: effectiveTitles(), saved: talkTitles !== null };
  },
};

// ── 436 round 7: planning answers ──────────────────────────────────────────
// A vegetarian who comes late on Day 2, an allergy (long, never cut) who leaves
// early on Day 1, a wheelchair, the VIP's other food and question, a talk no
// longer listed. Talk titles: the suggested list until a Manager saves some.
const SUGGESTED_TALK_TITLES = ['Sleep better, stress less', 'Healthy joints, back and muscles', 'Good circulation for everyday energy',
  'Caring for your eyes', 'Ageing well and staying active', 'Eating well for long-term health', "Women's wellness"];
let talkTitles: string[] | null = null;
const effectiveTitles = () => [...(talkTitles ?? SUGGESTED_TALK_TITLES)];
type PlanRow = { version: number; answers: any; updated_at: string; updated_by: 'guest' | 'staff'; staff_id: string | null };
const planAnswers: Record<string, PlanRow> = {};
const blank = { food: null, food_other: null, allergy: null, allergy_details: null, timing: [], talks: [], access: [], access_other: null,
  heard_from: null, heard_from_other: null, question: null };
const idOf = (name: string) => guests.find(g => g.event_id === 'ev-open-days' && g.name === name)!.id;
const answered = (name: string, a: any, by: 'guest' | 'staff' = 'guest', version = 1) => {
  planAnswers[idOf(name)] = { version, answers: { ...blank, ...a }, updated_at: at(addDays(TODAY, -2), '10:05'), updated_by: by,
    staff_id: by === 'staff' ? 'u-staff' : null };
};
answered('Guest Nine', { food: 'vegetarian', allergy: 'no', heard_from: 'tiktok', talks: ['Sleep better, stress less', 'Caring for your eyes'],
  timing: [{ date: D1, whole_day: true, arrive: null, leave: null }, { date: D2, whole_day: false, arrive: '14:00', leave: '19:00' }] });
answered('Guest Two', { food: 'no_preference', allergy: 'yes', allergy_details: 'Peanuts and shellfish (carries an EpiPen at all times)',
  timing: [{ date: D1, whole_day: false, arrive: '10:00', leave: '15:00' }], heard_from: 'friend_family',
  talks: ['Healthy joints, back and muscles', 'Managing stress at work'] }, 'staff', 2);
answered('Guest Thirteen', { food: 'halal', allergy: 'no', access: ['wheelchair', 'front_seat'], heard_from: 'staff',
  timing: [{ date: D2, whole_day: true, arrive: null, leave: null }] });
answered('Guest One', { food: 'other', food_other: 'No pork', allergy: 'no', heard_from: 'other', heard_from_other: 'Community centre poster',
  talks: ['Good circulation for everyday energy', 'Sleep better, stress less'],
  question: 'Is it better to walk in the morning or in the evening?\nI usually walk after dinner.' });
answered('Guest Seven', { food: 'vegan', allergy: 'yes', heard_from: 'whatsapp', access: ['walking_help'], access_other: 'Needs a seat near the lift' });

function planRecord(guestId: string) {
  const r = planAnswers[guestId];
  return { version: r.version, answers: r.answers, updated_at: r.updated_at, updated_by: r.updated_by,
    staff_name: r.updated_by === 'staff' ? nameOf(r.staff_id) : null };
}

function planningSummary(e: Ev) {
  const reg = guests.filter(g => g.event_id === e.id && g.status === 'registered');
  const vipId = e.id === 'ev-open-days' ? reg.find(g => g.source === 'ticket')?.id ?? null : null;
  const who = (g: G) => ({ guest_id: g.id, name: g.name, vip: g.id === vipId });
  const ans = (g: G) => planAnswers[g.id]?.answers ?? null;
  const byName = (a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name);
  const foodOf = (list: G[]) => {
    const out: Record<string, number> = { no_preference: 0, vegetarian: 0, vegan: 0, halal: 0, no_beef: 0, other: 0, not_said: 0 };
    for (const g of list) out[ans(g)?.food ?? 'not_said'] += 1;
    return out;
  };
  const allergies = (list: G[]) => list.filter(g => ans(g)?.allergy === 'yes').map(g => ({ ...who(g), text: ans(g).allergy_details })).sort(byName);
  const foodOther = (list: G[]) => list.filter(g => ans(g)?.food === 'other' && ans(g).food_other).map(g => ({ ...who(g), text: ans(g).food_other })).sort(byName);
  const days = [...e.days].sort((a, b) => a.day.localeCompare(b.day)).map((d, i) => {
    const on = reg.filter(g => g.days.some(x => x.day === d.day));
    const part = on.map(g => ({ g, t: (ans(g)?.timing ?? []).find((t: any) => t.date === d.day && !t.whole_day) })).filter(x => x.t);
    return {
      day: d.day, label: `Day ${i + 1}`, registered: on.length, answered: on.filter(ans).length, food: foodOf(on),
      food_other: foodOther(on), allergies: allergies(on),
      late: part.filter(x => x.t.arrive > (e.daily_start ?? '00:00')).map(x => ({ ...who(x.g), time: x.t.arrive })).sort((a, b) => a.time.localeCompare(b.time) || byName(a, b)),
      early: part.filter(x => x.t.leave < (e.daily_end ?? '24:00')).map(x => ({ ...who(x.g), time: x.t.leave })).sort((a, b) => a.time.localeCompare(b.time) || byName(a, b)),
      access: on.filter(g => (ans(g)?.access ?? []).length || ans(g)?.access_other)
        .map(g => ({ ...who(g), needs: ans(g).access, other: ans(g).access_other })).sort(byName),
    };
  });
  const vips = reg.filter(g => g.id === vipId);
  const listed = effectiveTitles();
  const counts: Record<string, number> = Object.fromEntries(listed.map(t => [t, 0]));
  for (const g of reg) for (const t of ans(g)?.talks ?? []) counts[t] = (counts[t] ?? 0) + 1;
  const heard: Record<string, number> = { tiktok: 0, facebook: 0, instagram: 0, google: 0, whatsapp: 0, friend_family: 0, staff: 0, email: 0, other: 0, not_said: 0 };
  for (const g of reg) heard[ans(g)?.heard_from ?? 'not_said'] += 1;
  return {
    event_id: e.id, hours: { daily_start: e.daily_start, daily_end: e.daily_end },
    registered: reg.length, answered: reg.filter(ans).length, days,
    vip: e.id === 'ev-open-days' ? { count: vips.length, answered: vips.filter(ans).length, waiting: 1, food: foodOf(vips),
      food_other: foodOther(vips), allergies: allergies(vips) } : null,
    talks: Object.keys(counts).map(t => ({ title: t, count: counts[t], listed: listed.includes(t) }))
      .sort((a, b) => b.count - a.count || listed.indexOf(a.title) - listed.indexOf(b.title)),
    heard_from: heard,
    heard_from_other: reg.filter(g => ans(g)?.heard_from === 'other' && ans(g).heard_from_other)
      .map(g => ({ ...who(g), text: ans(g).heard_from_other })).sort(byName),
    questions: reg.filter(g => ans(g)?.question).map(g => ({ ...who(g), text: ans(g).question })).sort(byName),
  };
}
// 436: gifts given and keys made in the preview.
const previewGifts: Record<string, any> = {};
const previewKeys: any[] = [];

// ── the client surface the page uses ───────────────────────────────────────
const failing = new Set(new URLSearchParams(typeof location === 'undefined' ? '' : location.search).getAll('fail'));
const TABLES: Record<string, any[]> = { stores: STORES, profiles: PROFILES, customers: CUSTOMERS };
const clone = <T,>(v: T): T => (v === undefined ? v : JSON.parse(JSON.stringify(v)));
const delay = () => new Promise(r => setTimeout(r, 120));

const planningMode = new URLSearchParams(typeof location === 'undefined' ? '' : location.search).get('planning');
function rpc(name: string, args: any = {}) {
  return delay().then(() => {
    if (failing.has(name)) return { data: null, error: { message: `Preview: ${name} failed` } };
    if (name.startsWith('event_planning_') && planningMode === 'none') return { data: null, error: { message: 'Could not find the function', code: 'PGRST202' } };
    if (name === 'event_planning_list' && planningMode === 'fail') return { data: null, error: { message: 'canceling statement due to statement timeout', code: '57014' } };
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
