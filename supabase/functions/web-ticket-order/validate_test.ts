// The body whitelist: what the website may send, and what is refused.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { validateOrderRequest } from './validate.ts';
import { namesOrder, paidOrder } from './fixtures.ts';

// deno-lint-ignore no-explicit-any
type Loose = Record<string, any>;

const paid = (edit: (o: Loose) => void = () => {}) => {
  const order: Loose = paidOrder();
  edit(order);
  return validateOrderRequest({ type: 'paid', order });
};
const names = (edit: (o: Loose) => void = () => {}) => {
  const order: Loose = namesOrder();
  edit(order);
  return validateOrderRequest({ type: 'names', order });
};
const refusedAt = (result: ReturnType<typeof validateOrderRequest>) => (result.ok ? null : result.field);

Deno.test('a well-formed paid order passes through unchanged', () => {
  const result = paid();
  assert(result.ok);
  assertEquals(result.value, { type: 'paid', order: paidOrder() });
});

Deno.test('a well-formed names order passes through unchanged', () => {
  const result = names();
  assert(result.ok);
  assertEquals(result.value, { type: 'names', order: namesOrder() });
});

Deno.test('unknown fields are refused and named, at every level', () => {
  assertEquals(refusedAt(validateOrderRequest({ type: 'paid', order: paidOrder(), role: 'owner' })), 'role');
  assertEquals(refusedAt(paid(o => { o.invoice_id = 'x'; })), 'order.invoice_id');
  assertEquals(refusedAt(paid(o => { o.buyer.customer_id = 'x'; })), 'order.buyer.customer_id');
  assertEquals(refusedAt(names(o => { o.buyer.phone = '+65 9123 0003'; })), 'order.buyer.phone');
  assertEquals(refusedAt(names(o => { o.attendees[1].note = 'x'; })), 'order.attendees.1.note');
  // Each type has its own list: a paid-only field is unknown on a names order.
  assertEquals(refusedAt(names(o => { o.quantity = 2; })), 'order.quantity');
  assertEquals(refusedAt(paid(o => { o.attendees = []; })), 'order.attendees');
});

Deno.test('the envelope itself', () => {
  assertEquals(refusedAt(validateOrderRequest(null)), 'body');
  assertEquals(refusedAt(validateOrderRequest([])), 'body');
  assertEquals(refusedAt(validateOrderRequest({ order: paidOrder() })), 'type');
  assertEquals(refusedAt(validateOrderRequest({ type: 'refund', order: paidOrder() })), 'type');
  assertEquals(refusedAt(validateOrderRequest({ type: 'paid' })), 'order');
  assertEquals(refusedAt(validateOrderRequest({ type: 'paid', order: [paidOrder()] })), 'order');
});

Deno.test('the session id must be a Checkout session, and livemode must agree with it', () => {
  for (const id of ['', 'pi_3TestIntent0001', 'cs_test_short', 'cs_prod_a1B2c3D4e5F6', 'cs_test_a1B2-c3D4e5F6', `cs_test_${'a'.repeat(201)}`]) {
    assertEquals(refusedAt(paid(o => { o.stripe_session_id = id; })), 'order.stripe_session_id', id);
  }
  assertEquals(refusedAt(paid(o => { o.livemode = true; })), 'order.livemode', 'test session claiming live');
  assertEquals(refusedAt(paid(o => { o.stripe_session_id = 'cs_live_a1B2c3D4e5F6'; })), 'order.livemode', 'live session claiming test');
  assert(paid(o => { o.stripe_session_id = 'cs_live_a1B2c3D4e5F6'; o.livemode = true; }).ok);
  assertEquals(refusedAt(paid(o => { o.livemode = 'false'; })), 'order.livemode');
  assertEquals(refusedAt(names(o => { o.livemode = true; })), 'order.livemode');
});

Deno.test('the payment intent is optional but, when given, must look like one', () => {
  // Absent, null and blank all mean none: a session with nothing to pay has no intent.
  for (const none of [null, undefined, '', '   ']) {
    const result = paid(o => { if (none === undefined) delete o.stripe_payment_intent; else o.stripe_payment_intent = none; });
    assert(result.ok && result.value.type === 'paid', String(none));
    assertEquals(result.value.order.stripe_payment_intent, null, String(none));
  }
  for (const pi of ['pi_short', 'ch_3TestCharge0001', 'pi_3Test Intent0001', `pi_${'a'.repeat(201)}`, 42, false]) {
    assertEquals(refusedAt(paid(o => { o.stripe_payment_intent = pi; })), 'order.stripe_payment_intent', String(pi));
  }
});

Deno.test('channel, ticket, counts and amounts stay inside their ranges', () => {
  assertEquals(refusedAt(paid(o => { o.channel = ''; })), 'order.channel');
  assertEquals(refusedAt(paid(o => { o.channel = 'c'.repeat(65); })), 'order.channel');
  assertEquals(refusedAt(paid(o => { o.ticket = 'day3'; })), 'order.ticket');
  for (const ticket of ['both', 'day1', 'day2']) assert(paid(o => { o.ticket = ticket; }).ok, ticket);

  for (const q of [0, 11, 1.5, '2', null]) assertEquals(refusedAt(paid(o => { o.quantity = q; })), 'order.quantity', String(q));
  for (const q of [1, 10]) assert(paid(o => { o.quantity = q; }).ok);

  assert(paid(o => { o.unit_amount_cents = 0; o.amount_total_cents = 0; }).ok, 'a free order is still an order');
  assertEquals(refusedAt(paid(o => { o.unit_amount_cents = -1; })), 'order.unit_amount_cents');
  assertEquals(refusedAt(paid(o => { o.unit_amount_cents = 1_000_001; })), 'order.unit_amount_cents');
  assertEquals(refusedAt(paid(o => { o.amount_total_cents = 10_000_001; })), 'order.amount_total_cents');
  assertEquals(refusedAt(paid(o => { o.amount_total_cents = 94.5; })), 'order.amount_total_cents');
  assertEquals(refusedAt(paid(o => { o.early_bird = 1; })), 'order.early_bird');
});

Deno.test('buyer text is trimmed and bounded, and a blank contact means none', () => {
  const result = paid(o => { o.buyer = { name: '  Guest One ', email: '', phone: '   ' }; });
  assert(result.ok && result.value.type === 'paid');
  assertEquals(result.value.order.buyer, { name: 'Guest One', email: null, phone: null });
  assert(paid(o => { o.buyer = { name: 'Guest One' }; }).ok, 'email and phone may be absent');

  // A paid order needs a buyer name; the website sends 'Website buyer' when Stripe has none.
  for (const name of ['', '   ', null]) assertEquals(refusedAt(paid(o => { o.buyer.name = name; })), 'order.buyer.name', String(name));
  assertEquals(refusedAt(paid(o => { delete o.buyer.name; })), 'order.buyer.name');
  assert(paid(o => { o.buyer.name = 'Website buyer'; }).ok);
  assertEquals(refusedAt(paid(o => { o.buyer.name = 'n'.repeat(201); })), 'order.buyer.name');
  assertEquals(refusedAt(paid(o => { o.buyer.email = `${'e'.repeat(242)}@tests.invalid`; })), 'order.buyer.email');
  assertEquals(refusedAt(paid(o => { o.buyer.phone = '9'.repeat(41); })), 'order.buyer.phone');
  assertEquals(refusedAt(paid(o => { o.buyer.phone = 91230001; })), 'order.buyer.phone');
  assertEquals(refusedAt(paid(o => { o.buyer = 'Guest One'; })), 'order.buyer');
});

Deno.test('times must be real ISO-8601 instants with a zone', () => {
  for (const t of [
    '2026-10-05T10:03:10+08:00', '2026-10-05T02:03Z', '2026-10-05T02:03:10.123456Z', '2026-10-05T10:03:10+0800',
    '2026-10-05T10:03:10+15:59', '2026-10-05T10:03:10-15:59',
  ]) {
    assert(paid(o => { o.paid_at = t; }).ok, t);
  }
  for (const t of [
    '2026-10-05T02:03:10', '2026-10-05', '2026-02-30T00:00:00Z', '2026-10-05T24:00:00Z', 'yesterday', 1_790_000_000,
    // Past what Postgres accepts: refused here rather than retried for days.
    '2026-10-05T10:03:10+16:00', '2026-10-05T10:03:10+23:59', '2026-10-05T10:03:10-1600',
  ]) {
    assertEquals(refusedAt(paid(o => { o.paid_at = t; })), 'order.paid_at', String(t));
  }
  assertEquals(refusedAt(paid(o => { delete o.checkout_opened_at; })), 'order.checkout_opened_at');
});

Deno.test('names: a buyer and one to ten attendees', () => {
  assertEquals(refusedAt(names(o => { o.attendees = []; })), 'order.attendees');
  assertEquals(refusedAt(names(o => { o.attendees = Array.from({ length: 11 }, (_, i) => ({ name: `Guest ${i + 1}` })); })), 'order.attendees');
  assert(names(o => { o.attendees = Array.from({ length: 10 }, (_, i) => ({ name: `Guest ${i + 1}` })); }).ok);
  assertEquals(refusedAt(names(o => { o.attendees = 'Guest One'; })), 'order.attendees');
  assertEquals(refusedAt(names(o => { o.attendees[1] = 'Guest Two'; })), 'order.attendees.1');
  assertEquals(refusedAt(names(o => { o.attendees[0].name = ''; })), 'order.attendees.0.name');
  assertEquals(refusedAt(names(o => { o.attendees[1].whatsapp = '9'.repeat(41); })), 'order.attendees.1.whatsapp');

  assertEquals(refusedAt(names(o => { o.buyer.first_name = ''; })), 'order.buyer.first_name');
  assertEquals(refusedAt(names(o => { o.buyer.first_name = 'f'.repeat(101); })), 'order.buyer.first_name');
  assertEquals(refusedAt(names(o => { o.buyer.last_name = 'l'.repeat(101); })), 'order.buyer.last_name');

  const noLastName = names(o => { delete o.buyer.last_name; });
  assert(noLastName.ok && noLastName.value.type === 'names');
  assertEquals(noLastName.value.order.buyer.last_name, '', 'a last name may be absent or blank');
});

Deno.test('text the database cannot store is refused and named, never echoed', () => {
  // What JSON.parse makes of the escapes `\u0000`, `\ud800` and `\udc00`: plain
  // ASCII on the wire, so the UTF-8 check lets them through, but jsonb cannot hold them.
  const unstorable = [
    'Guest\u0000One', '\u0000', 'Guest One\uD83D', 'Guest\uD800One', '\uDC00Guest One', '\uD800', 'Guest \uDE00\uD83D One',
  ];
  // Every free-text field, required and optional, on both order types.
  const fields: ['paid' | 'names', string][] = [
    ['paid', 'order.channel'],
    ['paid', 'order.stripe_payment_intent'],
    ['paid', 'order.buyer.name'],
    ['paid', 'order.buyer.email'],
    ['paid', 'order.buyer.phone'],
    ['names', 'order.channel'],
    ['names', 'order.buyer.first_name'],
    ['names', 'order.buyer.last_name'],
    ['names', 'order.buyer.email'],
    ['names', 'order.buyer.whatsapp'],
    ['names', 'order.attendees.1.name'],
    ['names', 'order.attendees.1.email'],
    ['names', 'order.attendees.1.whatsapp'],
  ];
  for (const bad of unstorable) {
    for (const [type, path] of fields) {
      const keys = path.split('.').slice(1);
      const last = keys.pop()!;
      const set = (o: Loose) => { keys.reduce((node, k) => node[k], o)[last] = bad; };
      // The whole refusal is the path: nothing of the value, not even escaped.
      assertEquals(type === 'paid' ? paid(set) : names(set), { ok: false, field: path }, `${type} ${path} ${JSON.stringify(bad)}`);
    }
  }

  // A whole pair is one character, not half of one: emoji and other scripts still pass.
  for (const good of ['Guest One 😀', '客人一', 'Khách Một']) {
    const result = paid(o => { o.buyer.name = good; });
    assert(result.ok && result.value.type === 'paid', good);
    assertEquals(result.value.order.buyer.name, good);
  }
});

Deno.test('a refusal names the field and never echoes what was in it', () => {
  const result = paid(o => { o.buyer.email = `guest.one@tests.invalid${'x'.repeat(260)}`; });
  assertEquals(refusedAt(result), 'order.buyer.email');
  assert(!JSON.stringify(result).includes('guest.one'));
});
