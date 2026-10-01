// The body the website may send, and nothing else.
//
// The signature already says the website sent it; this says it is shaped the
// way the database functions expect. An unknown key anywhere is a refused
// request, not an ignored one, and the order handed to the RPC is rebuilt from
// the whitelisted fields, so nothing unlisted can ride along into the database.
//
// Refusals name the field (a path such as `order.buyer.name`) and never quote
// the value: the value may be a name, an email or a phone number.

export const TICKETS = ['both', 'day1', 'day2'] as const;
export type Ticket = (typeof TICKETS)[number];

export interface PaidOrder {
  channel: string;
  stripe_session_id: string;
  stripe_payment_intent: string | null;
  livemode: boolean;
  ticket: Ticket;
  quantity: number;
  unit_amount_cents: number;
  amount_total_cents: number;
  early_bird: boolean;
  buyer: { name: string; email: string | null; phone: string | null };
  checkout_opened_at: string;
  paid_at: string;
}

export interface NamesOrder {
  channel: string;
  stripe_session_id: string;
  livemode: boolean;
  buyer: { first_name: string; last_name: string; email: string | null; whatsapp: string | null };
  attendees: { name: string; email: string | null; whatsapp: string | null }[];
}

export type OrderRequest =
  | { type: 'paid'; order: PaidOrder }
  | { type: 'names'; order: NamesOrder };

export type Checked<T> = { ok: true; value: T } | { ok: false; field: string };

const REQUEST_FIELDS = ['type', 'order'] as const;
const PAID_FIELDS = [
  'channel', 'stripe_session_id', 'stripe_payment_intent', 'livemode', 'ticket', 'quantity',
  'unit_amount_cents', 'amount_total_cents', 'early_bird', 'buyer', 'checkout_opened_at', 'paid_at',
] as const;
const PAID_BUYER_FIELDS = ['name', 'email', 'phone'] as const;
const NAMES_FIELDS = ['channel', 'stripe_session_id', 'livemode', 'buyer', 'attendees'] as const;
const NAMES_BUYER_FIELDS = ['first_name', 'last_name', 'email', 'whatsapp'] as const;
const ATTENDEE_FIELDS = ['name', 'email', 'whatsapp'] as const;

export const MAX_ATTENDEES = 10;

const SESSION_RE = /^cs_(test|live)_[A-Za-z0-9]{8,200}$/;
const PAYMENT_INTENT_RE = /^pi_[A-Za-z0-9_]{8,200}$/;
// A zone is required: a bare local time would be read in the database's own
// time zone, which is exactly the early-bird ambiguity the dates exist to avoid.
// Postgres takes offsets up to ±15:59; a larger one would fail in the database,
// come back as a retry, and be retried by Stripe for days.
const ISO_RE = /^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d{1,9})?)?(Z|[+-](0\d|1[0-5]):?[0-5]\d)$/;

class Refused extends Error {
  constructor(readonly field: string) {
    super(`invalid field: ${field}`);
    this.name = 'Refused';
  }
}

const at = (path: string, key: string | number) => (path ? `${path}.${key}` : String(key));

function object(value: unknown, path: string, allowed: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Refused(path);
  const extra = Object.keys(value).find(k => !allowed.includes(k));
  if (extra !== undefined) throw new Refused(at(path, extra));
  return value as Record<string, unknown>;
}

// Text Postgres cannot store: U+0000, and half of a surrogate pair. Both arrive
// as JSON escapes (`\u0000`, `\ud800`), which are plain ASCII on the wire and so
// pass the UTF-8 check; jsonb would refuse them, the refusal would come back as
// a retry, and Stripe would retry it for days.
const storable = (s: string) => s.isWellFormed() && !s.includes('\u0000');

function text(value: unknown, path: string, min: number, max: number): string {
  if (typeof value !== 'string' || !storable(value)) throw new Refused(path);
  const clean = value.trim();
  if (clean.length < min || clean.length > max) throw new Refused(path);
  return clean;
}

/** Absent, null and blank all mean "not given". */
function optionalText(value: unknown, path: string, max: number): string | null {
  if (value === undefined || value === null) return null;
  const clean = text(value, path, 0, max);
  return clean || null;
}

function integer(value: unknown, path: string, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) throw new Refused(path);
  return value;
}

function flag(value: unknown, path: string): boolean {
  if (typeof value !== 'boolean') throw new Refused(path);
  return value;
}

function pattern(value: unknown, path: string, re: RegExp): string {
  if (typeof value !== 'string' || !re.test(value)) throw new Refused(path);
  return value;
}

function isoTime(value: unknown, path: string): string {
  const match = typeof value === 'string' ? ISO_RE.exec(value) : null;
  if (!match || Number.isNaN(Date.parse(value as string))) throw new Refused(path);
  // Date.parse rolls 30 Feb over into March; the database would refuse it.
  const [y, m, d] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const day = new Date(Date.UTC(y, m - 1, d));
  if (day.getUTCFullYear() !== y || day.getUTCMonth() !== m - 1 || day.getUTCDate() !== d) throw new Refused(path);
  return value as string;
}

/** The session id, and a livemode that agrees with it. */
function session(body: Record<string, unknown>): { stripe_session_id: string; livemode: boolean } {
  const id = pattern(body.stripe_session_id, 'order.stripe_session_id', SESSION_RE);
  const livemode = flag(body.livemode, 'order.livemode');
  if (livemode !== id.startsWith('cs_live_')) throw new Refused('order.livemode');
  return { stripe_session_id: id, livemode };
}

function paidOrder(value: unknown): PaidOrder {
  const o = object(value, 'order', PAID_FIELDS);
  const channel = text(o.channel, 'order.channel', 1, 64);
  const { stripe_session_id, livemode } = session(o);
  // Blank means none, as for the contacts: a session with nothing to pay has no intent.
  const intent = optionalText(o.stripe_payment_intent, 'order.stripe_payment_intent', 203);
  const buyer = object(o.buyer, 'order.buyer', PAID_BUYER_FIELDS);
  if (typeof o.ticket !== 'string' || !(TICKETS as readonly string[]).includes(o.ticket)) throw new Refused('order.ticket');

  return {
    channel,
    stripe_session_id,
    stripe_payment_intent: intent === null ? null : pattern(intent, 'order.stripe_payment_intent', PAYMENT_INTENT_RE),
    livemode,
    ticket: o.ticket as Ticket,
    quantity: integer(o.quantity, 'order.quantity', 1, 10),
    unit_amount_cents: integer(o.unit_amount_cents, 'order.unit_amount_cents', 0, 1_000_000),
    amount_total_cents: integer(o.amount_total_cents, 'order.amount_total_cents', 0, 10_000_000),
    early_bird: flag(o.early_bird, 'order.early_bird'),
    buyer: {
      // Required: 372 stores no order without one. Stripe can leave the name
      // out (some payment methods), so the website sends 'Website buyer' then.
      name: text(buyer.name, 'order.buyer.name', 1, 200),
      email: optionalText(buyer.email, 'order.buyer.email', 254),
      phone: optionalText(buyer.phone, 'order.buyer.phone', 40),
    },
    checkout_opened_at: isoTime(o.checkout_opened_at, 'order.checkout_opened_at'),
    paid_at: isoTime(o.paid_at, 'order.paid_at'),
  };
}

function namesOrder(value: unknown): NamesOrder {
  const o = object(value, 'order', NAMES_FIELDS);
  const channel = text(o.channel, 'order.channel', 1, 64);
  const { stripe_session_id, livemode } = session(o);
  const buyer = object(o.buyer, 'order.buyer', NAMES_BUYER_FIELDS);

  if (!Array.isArray(o.attendees) || o.attendees.length < 1 || o.attendees.length > MAX_ATTENDEES) {
    throw new Refused('order.attendees');
  }
  const attendees = o.attendees.map((raw, i) => {
    const path = at('order.attendees', i);
    const a = object(raw, path, ATTENDEE_FIELDS);
    return {
      name: text(a.name, at(path, 'name'), 1, 200),
      email: optionalText(a.email, at(path, 'email'), 254),
      whatsapp: optionalText(a.whatsapp, at(path, 'whatsapp'), 40),
    };
  });

  return {
    channel,
    stripe_session_id,
    livemode,
    buyer: {
      first_name: text(buyer.first_name, 'order.buyer.first_name', 1, 100),
      last_name: text(buyer.last_name ?? '', 'order.buyer.last_name', 0, 100),
      email: optionalText(buyer.email, 'order.buyer.email', 254),
      whatsapp: optionalText(buyer.whatsapp, 'order.buyer.whatsapp', 40),
    },
    attendees,
  };
}

export function validateOrderRequest(body: unknown): Checked<OrderRequest> {
  try {
    const b = object(body, '', REQUEST_FIELDS);
    if (b.type === 'paid') return { ok: true, value: { type: 'paid', order: paidOrder(b.order) } };
    if (b.type === 'names') return { ok: true, value: { type: 'names', order: namesOrder(b.order) } };
    return { ok: false, field: 'type' };
  } catch (error) {
    if (error instanceof Refused) return { ok: false, field: error.field || 'body' };
    throw error;
  }
}
