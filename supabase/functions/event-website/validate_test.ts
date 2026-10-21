// What the website may send (436): every message of the contract, its
// whitelist at every level, and every field's shape.

import { assertEquals } from 'jsr:@std/assert@1';
import { validateRequest } from './validate.ts';
import { messages, TOKEN_1 } from './fixtures.ts';
import { LIMITS, MAX_PEOPLE } from './contract.ts';

const clone = <T>(v: T): T => structuredClone(v);
// deno-lint-ignore no-explicit-any
type Any = any;
const refused = (body: unknown) => validateRequest(body) as { ok: false; field: string };

Deno.test('every message of the contract passes as the website sends it, and comes back the same', () => {
  for (const [type, body] of Object.entries(messages())) {
    const checked = validateRequest(clone(body));
    assertEquals(checked, { ok: true, value: body }, type);
  }
});

Deno.test('an unknown type, or none, is refused on type', () => {
  assertEquals(refused({ type: 'paid', event: 'HEALTH-SEMINAR-NOV26' }), { ok: false, field: 'type' });
  assertEquals(refused({ event: 'HEALTH-SEMINAR-NOV26' }), { ok: false, field: 'type' });
  assertEquals(refused([]), { ok: false, field: 'type' });
  assertEquals(refused(null), { ok: false, field: 'type' });
});

Deno.test('an unknown key at any level is refused, naming its path', () => {
  const m = messages();
  assertEquals(refused({ ...m.event_info, extra: 1 }), { ok: false, field: 'extra' });
  const reg: Any = clone(m.register);
  reg.registration.note = 'x';
  assertEquals(refused(reg), { ok: false, field: 'registration.note' });
  const reg2: Any = clone(m.register);
  reg2.registration.people[1].dob = '1990-01-01';
  assertEquals(refused(reg2), { ok: false, field: 'registration.people.1.dob' });
  const paid: Any = clone(m.vip_paid);
  paid.payment.payer.address = 'x';
  assertEquals(refused(paid), { ok: false, field: 'payment.payer.address' });
  // A key of another message is not allowed either.
  assertEquals(refused({ ...m.sync, code: 'ABCD1234' }), { ok: false, field: 'code' });
});

Deno.test('every listed field is required; null only where the contract allows it', () => {
  const m = messages();
  const reg: Any = clone(m.register);
  delete reg.registration.referral_code;
  assertEquals(refused(reg), { ok: false, field: 'registration.referral_code' });
  const checkout: Any = clone(m.vip_checkout);
  checkout.order.payer.phone = null;
  assertEquals(validateRequest(checkout).ok, true);
  const checkout2: Any = clone(m.vip_checkout);
  checkout2.order.payer.email = null;
  assertEquals(refused(checkout2), { ok: false, field: 'order.payer.email' });
  const paid: Any = clone(m.vip_paid);
  paid.payment.payment_id = null;
  assertEquals(validateRequest(paid).ok, true);
  assertEquals(refused({ type: 'person', event: m.person.event }), { ok: false, field: 'upgrade_token' });
});

Deno.test("the ids and codes have the contract's shapes", () => {
  const m = messages();
  assertEquals(refused({ ...m.event_info, event: 'health-seminar' }), { ok: false, field: 'event' });
  assertEquals(refused({ ...m.referral_info, code: 'abcd1234' }), { ok: false, field: 'code' });
  assertEquals(refused({ ...m.person, upgrade_token: 'vip_ABCDEFGHIJKLMNOPQRSTUVWXYZ' }), { ok: false, field: 'upgrade_token' });
  const reg: Any = clone(m.register);
  reg.registration.registration_id = 'REG-20261101-1a2b3c4d';
  assertEquals(refused(reg), { ok: false, field: 'registration.registration_id' });
  const checkout: Any = clone(m.vip_checkout);
  checkout.order.order_id = 'VIP-2026110-1A2B3C4D';
  assertEquals(refused(checkout), { ok: false, field: 'order.order_id' });
  const paid: Any = clone(m.vip_paid);
  paid.payment.payment_request_id = paid.payment.payment_request_id.toUpperCase();
  assertEquals(refused(paid), { ok: false, field: 'payment.payment_request_id' });
  const paid2: Any = clone(m.vip_paid);
  paid2.payment.currency = 'MYR';
  assertEquals(refused(paid2), { ok: false, field: 'payment.currency' });
  const paid3: Any = clone(m.vip_paid);
  paid3.payment.provider = 'stripe';
  assertEquals(refused(paid3), { ok: false, field: 'payment.provider' });
  const transfer: Any = clone(m.vip_transfer);
  transfer.order.method = 'cash';
  assertEquals(refused(transfer), { ok: false, field: 'order.method' });
});

Deno.test('people: 1 to 10, positions 1..n in order, each with a name, phone, email and days', () => {
  const m = messages();
  const reg: Any = clone(m.register);
  reg.registration.people[1].position = 3;
  assertEquals(refused(reg), { ok: false, field: 'registration.people.1.position' });
  const none: Any = clone(m.register);
  none.registration.people = [];
  assertEquals(refused(none), { ok: false, field: 'registration.people' });
  const many: Any = clone(m.register);
  many.registration.people = Array.from({ length: MAX_PEOPLE + 1 }, (_, i) => ({ ...m.register.registration.people[0], position: i + 1 }));
  assertEquals(refused(many), { ok: false, field: 'registration.people' });
  const ten: Any = clone(m.register);
  ten.registration.people = Array.from({ length: MAX_PEOPLE }, (_, i) => ({ ...m.register.registration.people[0], position: i + 1 }));
  assertEquals(validateRequest(ten).ok, true);
  for (const [field, value] of [['first_name', ' '], ['first_name', 'x'.repeat(LIMITS.first_name + 1)],
    ['last_name', 'x'.repeat(LIMITS.last_name + 1)], ['phone', 'call me'], ['phone', '+'.repeat(3)],
    ['phone', '+6'.repeat(11)], ['email', 'not-an-email'], ['email', 'a@b'], ['vip', 'yes'], ['days', []],
    ['days', ['2026-11-23', '2026-11-23']], ['days', ['2026-02-30']], ['days', ['23/11/2026']]] as [string, unknown][]) {
    const bad: Any = clone(m.register);
    bad.registration.people[0][field] = value;
    const r = refused(bad);
    assertEquals(r.ok, false, `${field} ${JSON.stringify(value)}`);
    assertEquals(r.field.startsWith(`registration.people.0.${field}`), true, r.field);
  }
});

Deno.test('text is trimmed, and text Postgres cannot store is refused', () => {
  const m = messages();
  const reg: Any = clone(m.register);
  reg.registration.people[0].first_name = '  Ada  ';
  const ok = validateRequest(reg) as Any;
  assertEquals(ok.value.registration.people[0].first_name, 'Ada');
  for (const bad of ['Ada\u0000', 'Ada\ud800', 'A\u0007da']) {
    const r: Any = clone(m.register);
    r.registration.people[0].first_name = bad;
    assertEquals(refused(r), { ok: false, field: 'registration.people.0.first_name' });
  }
});

Deno.test('times need a zone and a real day; tokens are 1..10 and distinct; amounts are whole cents', () => {
  const m = messages();
  const checkout: Any = clone(m.vip_checkout);
  checkout.order.checkout_opened_at = '2026-11-01T10:05:00';
  assertEquals(refused(checkout), { ok: false, field: 'order.checkout_opened_at' });
  const checkout2: Any = clone(m.vip_checkout);
  checkout2.order.checkout_opened_at = '2026-02-30T10:05:00Z';
  assertEquals(refused(checkout2), { ok: false, field: 'order.checkout_opened_at' });
  const dup: Any = clone(m.vip_checkout);
  dup.order.upgrade_tokens = [TOKEN_1, TOKEN_1];
  assertEquals(refused(dup), { ok: false, field: 'order.upgrade_tokens' });
  const none: Any = clone(m.vip_checkout);
  none.order.upgrade_tokens = [];
  assertEquals(refused(none), { ok: false, field: 'order.upgrade_tokens' });
  const paid: Any = clone(m.vip_paid);
  paid.payment.amount_cents = 72.5;
  assertEquals(refused(paid), { ok: false, field: 'payment.amount_cents' });
  const paid2: Any = clone(m.vip_paid);
  paid2.payment.amount_cents = -1;
  assertEquals(refused(paid2), { ok: false, field: 'payment.amount_cents' });
  const transfer: Any = clone(m.vip_transfer);
  transfer.order.reference = ' ';
  assertEquals(refused(transfer), { ok: false, field: 'order.reference' });
  const transfer2: Any = clone(m.vip_transfer);
  transfer2.order.reference = 'x'.repeat(LIMITS.reference + 1);
  assertEquals(refused(transfer2), { ok: false, field: 'order.reference' });
  const transfer3: Any = clone(m.vip_transfer);
  transfer3.order.paid_on = '2026-13-01';
  assertEquals(refused(transfer3), { ok: false, field: 'order.paid_on' });
  const refund: Any = clone(m.vip_refund);
  refund.refund.livemode = 'true';
  assertEquals(refused(refund), { ok: false, field: 'refund.livemode' });
});
