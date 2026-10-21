// The body an event's website may send, and nothing else (436).
//
// Every message is checked against contract.ts: an unknown key anywhere is a
// refused request, not an ignored one, and the body handed to the database is
// rebuilt from the whitelisted fields, so nothing unlisted rides along.
// Refusals name the field (a path such as `registration.people.2.email`) and
// never quote the value: it may be a name, an email or a phone number.

import {
  ACCESS_CHOICES, EVENT_CODE_RE, FOOD_CHOICES, HEARD_FROM_CHOICES, HHMM_RE, HITPAY_ID_RE, ISO_DATE_RE, ISO_TIME_RE, LIMITS,
  MAX_PEOPLE, PLANNING_LIMITS, REFERRAL_CODE_RE, REGISTRATION_ID_RE, UPGRADE_TOKEN_RE, VIP_ORDER_ID_RE,
  type EventWebsiteRequest, type MessageType,
} from './contract.ts';

export type Checked<T> = { ok: true; value: T } | { ok: false; field: string };

const TYPES: readonly MessageType[] = [
  'event_info', 'referral_info', 'register', 'person', 'vip_checkout', 'vip_paid', 'vip_transfer', 'vip_refund', 'sync',
  'planning_answers',
];
export const MAX_CENTS = 10_000_000;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^[+0-9 ()-]+$/;

class Refused extends Error {
  constructor(readonly field: string) {
    super(`invalid field: ${field}`);
    this.name = 'Refused';
  }
}

const at = (path: string, key: string | number) => (path ? `${path}.${key}` : String(key));

function object(value: unknown, path: string, allowed: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Refused(path || 'body');
  const extra = Object.keys(value).find((k) => !allowed.includes(k));
  if (extra !== undefined) throw new Refused(at(path, extra));
  for (const k of allowed) {
    // Every listed field is required (null where the contract allows it).
    if (!(k in value)) throw new Refused(at(path, k));
  }
  return value as Record<string, unknown>;
}

// Text Postgres cannot store: U+0000, and half of a surrogate pair (both
// arrive as JSON escapes and pass the UTF-8 check; jsonb refuses them).
const storable = (s: string) => s.isWellFormed() && !s.includes('\u0000') && !/[\u0001-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(s);

function text(value: unknown, path: string, min: number, max: number): string {
  if (typeof value !== 'string' || !storable(value)) throw new Refused(path);
  const clean = value.trim();
  if (clean.length < min || clean.length > max) throw new Refused(path);
  return clean;
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

function email(value: unknown, path: string): string {
  const v = text(value, path, 3, LIMITS.email);
  if (!EMAIL_RE.test(v)) throw new Refused(path);
  return v;
}

function phone(value: unknown, path: string): string {
  const v = text(value, path, 1, LIMITS.phone);
  if (!PHONE_RE.test(v) || !/\d/.test(v)) throw new Refused(path);
  return v;
}

// Date.parse rolls 30 Feb over into March; the database would refuse it.
function realDay(y: number, m: number, d: number, path: string): void {
  const day = new Date(Date.UTC(y, m - 1, d));
  if (day.getUTCFullYear() !== y || day.getUTCMonth() !== m - 1 || day.getUTCDate() !== d) throw new Refused(path);
}

function isoDate(value: unknown, path: string): string {
  if (typeof value !== 'string' || !ISO_DATE_RE.test(value)) throw new Refused(path);
  const [y, m, d] = value.split('-').map(Number);
  realDay(y, m, d, path);
  return value;
}

/** A time with a zone; a bare local time is refused (as in web-ticket-order). */
function isoTime(value: unknown, path: string): string {
  const match = typeof value === 'string' ? ISO_TIME_RE.exec(value) : null;
  if (!match || Number.isNaN(Date.parse(value as string))) throw new Refused(path);
  realDay(Number(match[1]), Number(match[2]), Number(match[3]), path);
  return value as string;
}

function tokens(value: unknown, path: string): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_PEOPLE) throw new Refused(path);
  const list = value.map((t, i) => pattern(t, at(path, i), UPGRADE_TOKEN_RE));
  if (new Set(list).size !== list.length) throw new Refused(path);
  return list;
}

function payer(value: unknown, path: string) {
  const p = object(value, path, ['name', 'email', 'phone']);
  return {
    name: text(p.name, at(path, 'name'), 1, LIMITS.payer_name),
    email: email(p.email, at(path, 'email')),
    phone: p.phone === null ? null : phone(p.phone, at(path, 'phone')),
  };
}

function person(value: unknown, path: string, position: number) {
  const p = object(value, path, ['position', 'first_name', 'last_name', 'phone', 'email', 'days', 'vip']);
  if (integer(p.position, at(path, 'position'), 1, MAX_PEOPLE) !== position) throw new Refused(at(path, 'position'));
  if (!Array.isArray(p.days) || p.days.length < 1 || p.days.length > 31) throw new Refused(at(path, 'days'));
  const days = p.days.map((d, i) => isoDate(d, at(at(path, 'days'), i)));
  if (new Set(days).size !== days.length) throw new Refused(at(path, 'days'));
  return {
    position,
    first_name: text(p.first_name, at(path, 'first_name'), 1, LIMITS.first_name),
    last_name: text(p.last_name, at(path, 'last_name'), 0, LIMITS.last_name),
    phone: phone(p.phone, at(path, 'phone')),
    email: email(p.email, at(path, 'email')),
    days,
    vip: flag(p.vip, at(path, 'vip')),
  };
}

function register(b: Record<string, unknown>) {
  const r = object(b.registration, 'registration', ['registration_id', 'submitted_at', 'referral_code', 'people']);
  if (!Array.isArray(r.people) || r.people.length < 1 || r.people.length > MAX_PEOPLE) throw new Refused('registration.people');
  return {
    registration_id: pattern(r.registration_id, 'registration.registration_id', REGISTRATION_ID_RE),
    submitted_at: isoTime(r.submitted_at, 'registration.submitted_at'),
    referral_code: r.referral_code === null ? null : pattern(r.referral_code, 'registration.referral_code', REFERRAL_CODE_RE),
    people: r.people.map((p, i) => person(p, at('registration.people', i), i + 1)),
  };
}

function vipCheckout(b: Record<string, unknown>) {
  const o = object(b.order, 'order', ['order_id', 'upgrade_tokens', 'payer', 'livemode', 'checkout_opened_at']);
  return {
    order_id: pattern(o.order_id, 'order.order_id', VIP_ORDER_ID_RE),
    upgrade_tokens: tokens(o.upgrade_tokens, 'order.upgrade_tokens'),
    payer: payer(o.payer, 'order.payer'),
    livemode: flag(o.livemode, 'order.livemode'),
    checkout_opened_at: isoTime(o.checkout_opened_at, 'order.checkout_opened_at'),
  };
}

function vipPaid(b: Record<string, unknown>) {
  const p = object(b.payment, 'payment', ['order_id', 'provider', 'payment_request_id', 'payment_id', 'amount_cents', 'currency',
    'livemode', 'paid_at', 'upgrade_tokens', 'payer']);
  if (p.provider !== 'hitpay') throw new Refused('payment.provider');
  if (p.currency !== 'SGD') throw new Refused('payment.currency');
  return {
    order_id: pattern(p.order_id, 'payment.order_id', VIP_ORDER_ID_RE),
    provider: 'hitpay' as const,
    payment_request_id: pattern(p.payment_request_id, 'payment.payment_request_id', HITPAY_ID_RE),
    payment_id: p.payment_id === null ? null : pattern(p.payment_id, 'payment.payment_id', HITPAY_ID_RE),
    amount_cents: integer(p.amount_cents, 'payment.amount_cents', 0, MAX_CENTS),
    currency: 'SGD' as const,
    livemode: flag(p.livemode, 'payment.livemode'),
    paid_at: isoTime(p.paid_at, 'payment.paid_at'),
    upgrade_tokens: tokens(p.upgrade_tokens, 'payment.upgrade_tokens'),
    payer: payer(p.payer, 'payment.payer'),
  };
}

function vipTransfer(b: Record<string, unknown>) {
  const o = object(b.order, 'order', ['order_id', 'upgrade_tokens', 'payer', 'method', 'reference', 'paid_on', 'amount_cents',
    'submitted_at']);
  if (o.method !== 'paynow' && o.method !== 'bank') throw new Refused('order.method');
  return {
    order_id: pattern(o.order_id, 'order.order_id', VIP_ORDER_ID_RE),
    upgrade_tokens: tokens(o.upgrade_tokens, 'order.upgrade_tokens'),
    payer: payer(o.payer, 'order.payer'),
    method: o.method as 'paynow' | 'bank',
    reference: text(o.reference, 'order.reference', 1, LIMITS.reference),
    paid_on: isoDate(o.paid_on, 'order.paid_on'),
    amount_cents: integer(o.amount_cents, 'order.amount_cents', 0, MAX_CENTS),
    submitted_at: isoTime(o.submitted_at, 'order.submitted_at'),
  };
}

function vipRefund(b: Record<string, unknown>) {
  const r = object(b.refund, 'refund', ['order_id', 'payment_request_id', 'payment_id', 'refunded_cents_total', 'refunded_at', 'livemode']);
  return {
    order_id: pattern(r.order_id, 'refund.order_id', VIP_ORDER_ID_RE),
    payment_request_id: pattern(r.payment_request_id, 'refund.payment_request_id', HITPAY_ID_RE),
    payment_id: r.payment_id === null ? null : pattern(r.payment_id, 'refund.payment_id', HITPAY_ID_RE),
    refunded_cents_total: integer(r.refunded_cents_total, 'refund.refunded_cents_total', 0, MAX_CENTS),
    refunded_at: isoTime(r.refunded_at, 'refund.refunded_at'),
    livemode: flag(r.livemode, 'refund.livemode'),
  };
}

// Planning answers (21 Oct 2026). The database checks the token, the person's days, the event's hours, the talks and
// the version; here only the shapes, the choices and the limits. A text may hold line breaks (the database makes the
// one-line answers one line); "" after trimming is refused: the website sends null.
const optText = (value: unknown, path: string, max: number): string | null =>
  value === null ? null : text(value, path, 1, max);

function choice<T extends string>(value: unknown, path: string, list: readonly T[]): T {
  if (typeof value !== 'string' || !(list as readonly string[]).includes(value)) throw new Refused(path);
  return value as T;
}

const optChoice = <T extends string>(value: unknown, path: string, list: readonly T[]): T | null =>
  value === null ? null : choice(value, path, list);

function distinct(list: readonly string[], path: string): void {
  if (new Set(list).size !== list.length) throw new Refused(path);
}

function planningDay(value: unknown, path: string) {
  const d = object(value, path, ['date', 'whole_day', 'arrive', 'leave']);
  const date = isoDate(d.date, at(path, 'date'));
  if (flag(d.whole_day, at(path, 'whole_day'))) {
    if (d.arrive !== null) throw new Refused(at(path, 'arrive'));
    if (d.leave !== null) throw new Refused(at(path, 'leave'));
    return { date, whole_day: true, arrive: null, leave: null };
  }
  const arrive = pattern(d.arrive, at(path, 'arrive'), HHMM_RE);
  const leave = pattern(d.leave, at(path, 'leave'), HHMM_RE);
  // Zero-padded HH:MM compares as text.
  if (leave <= arrive) throw new Refused(at(path, 'leave'));
  return { date, whole_day: false, arrive, leave };
}

function planningAnswers(value: unknown, path: string) {
  const a = object(value, path, ['food', 'food_other', 'allergy', 'allergy_details', 'timing', 'talks', 'access',
    'access_other', 'heard_from', 'heard_from_other', 'question']);
  const food = optChoice(a.food, at(path, 'food'), FOOD_CHOICES);
  const food_other = optText(a.food_other, at(path, 'food_other'), PLANNING_LIMITS.food_other);
  if (food_other !== null && food !== 'other') throw new Refused(at(path, 'food_other'));
  const allergy = optChoice(a.allergy, at(path, 'allergy'), ['no', 'yes'] as const);
  const allergy_details = optText(a.allergy_details, at(path, 'allergy_details'), PLANNING_LIMITS.allergy_details);
  if (allergy_details !== null && allergy !== 'yes') throw new Refused(at(path, 'allergy_details'));
  if (!Array.isArray(a.timing) || a.timing.length > 31) throw new Refused(at(path, 'timing'));
  const timing = a.timing.map((d, i) => planningDay(d, at(at(path, 'timing'), i)));
  distinct(timing.map((d) => d.date), at(path, 'timing'));
  if (!Array.isArray(a.talks) || a.talks.length > PLANNING_LIMITS.talks) throw new Refused(at(path, 'talks'));
  const talks = a.talks.map((t, i) => text(t, at(at(path, 'talks'), i), 1, PLANNING_LIMITS.talk_title));
  distinct(talks, at(path, 'talks'));
  if (!Array.isArray(a.access) || a.access.length > ACCESS_CHOICES.length) throw new Refused(at(path, 'access'));
  const access = a.access.map((x, i) => choice(x, at(at(path, 'access'), i), ACCESS_CHOICES));
  distinct(access, at(path, 'access'));
  const access_other = optText(a.access_other, at(path, 'access_other'), PLANNING_LIMITS.access_other);
  const heard_from = optChoice(a.heard_from, at(path, 'heard_from'), HEARD_FROM_CHOICES);
  const heard_from_other = optText(a.heard_from_other, at(path, 'heard_from_other'), PLANNING_LIMITS.heard_from_other);
  if (heard_from_other !== null && heard_from !== 'other') throw new Refused(at(path, 'heard_from_other'));
  const question = optText(a.question, at(path, 'question'), PLANNING_LIMITS.question);
  return { food, food_other, allergy, allergy_details, timing, talks, access, access_other, heard_from, heard_from_other,
    question };
}

function planningSave(b: Record<string, unknown>) {
  const p = object(b.planning, 'planning', ['submitted_at', 'people']);
  if (!Array.isArray(p.people) || p.people.length < 1 || p.people.length > MAX_PEOPLE) throw new Refused('planning.people');
  const people = p.people.map((x, i) => {
    const path = at('planning.people', i);
    const o = object(x, path, ['upgrade_token', 'version', 'answers']);
    return {
      upgrade_token: pattern(o.upgrade_token, at(path, 'upgrade_token'), UPGRADE_TOKEN_RE),
      version: integer(o.version, at(path, 'version'), 0, 1_000_000),
      answers: planningAnswers(o.answers, at(path, 'answers')),
    };
  });
  distinct(people.map((x) => x.upgrade_token), 'planning.people');
  return { submitted_at: isoTime(p.submitted_at, 'planning.submitted_at'), people };
}

/** The request as the database gets it: { type, event, …its own fields, rebuilt }. */
export function validateRequest(body: unknown): Checked<EventWebsiteRequest> {
  try {
    const type = body !== null && typeof body === 'object' && !Array.isArray(body)
      ? (body as Record<string, unknown>).type : undefined;
    if (typeof type !== 'string' || !(TYPES as readonly string[]).includes(type)) return { ok: false, field: 'type' };
    const t = type as MessageType;
    const own: Record<MessageType, string[]> = {
      event_info: [], sync: [], referral_info: ['code'], person: ['upgrade_token'], register: ['registration'],
      vip_checkout: ['order'], vip_paid: ['payment'], vip_transfer: ['order'], vip_refund: ['refund'],
      planning_answers: ['planning'],
    };
    const b = object(body, '', ['type', 'event', ...own[t]]);
    const event = pattern(b.event, 'event', EVENT_CODE_RE);
    switch (t) {
      case 'event_info':
      case 'sync':
        return { ok: true, value: { type: t, event } };
      case 'referral_info':
        return { ok: true, value: { type: t, event, code: pattern(b.code, 'code', REFERRAL_CODE_RE) } };
      case 'person':
        return { ok: true, value: { type: t, event, upgrade_token: pattern(b.upgrade_token, 'upgrade_token', UPGRADE_TOKEN_RE) } };
      case 'register':
        return { ok: true, value: { type: t, event, registration: register(b) } };
      case 'vip_checkout':
        return { ok: true, value: { type: t, event, order: vipCheckout(b) } };
      case 'vip_paid':
        return { ok: true, value: { type: t, event, payment: vipPaid(b) } };
      case 'vip_transfer':
        return { ok: true, value: { type: t, event, order: vipTransfer(b) } };
      case 'planning_answers':
        return { ok: true, value: { type: t, event, planning: planningSave(b) } };
      default:
        return { ok: true, value: { type: t, event, refund: vipRefund(b) } };
    }
  } catch (error) {
    if (error instanceof Refused) return { ok: false, field: error.field || 'body' };
    throw error;
  }
}

/** What a request is about, for the logs: the business id, never a person's details. */
export function aboutOf(request: EventWebsiteRequest): Record<string, string> {
  switch (request.type) {
    case 'register': return { registration_id: request.registration.registration_id };
    case 'vip_checkout': case 'vip_transfer': return { order_id: request.order.order_id };
    case 'vip_paid': return { order_id: request.payment.order_id };
    case 'vip_refund': return { order_id: request.refund.order_id };
    // planning_answers has no business id; never a token or an answer.
    default: return {};
  }
}
