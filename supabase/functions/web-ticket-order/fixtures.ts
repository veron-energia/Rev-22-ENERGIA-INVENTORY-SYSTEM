// Fake orders for the tests. Fixture data only: this repository is public.

import type { NamesOrder, PaidOrder } from './validate.ts';

export const SECRET = 'test-signing-secret';
export const SESSION_ID = 'cs_test_a1B2c3D4e5F6g7H8';

export const paidOrder = (): PaidOrder => ({
  channel: 'alaric-birthday-2026',
  stripe_session_id: SESSION_ID,
  stripe_payment_intent: 'pi_3TestIntent0001',
  livemode: false,
  ticket: 'both',
  quantity: 2,
  unit_amount_cents: 4700,
  amount_total_cents: 9400,
  early_bird: true,
  buyer: { name: 'Guest One', email: 'guest.one@tests.invalid', phone: '+65 9123 0001' },
  checkout_opened_at: '2026-10-05T02:00:00.000Z',
  paid_at: '2026-10-05T02:03:10.000Z',
});

export const namesOrder = (): NamesOrder => ({
  channel: 'alaric-birthday-2026',
  stripe_session_id: SESSION_ID,
  livemode: false,
  buyer: { first_name: 'Guest', last_name: 'One', email: 'guest.one@tests.invalid', whatsapp: '+65 9123 0001' },
  attendees: [
    { name: 'Guest One', email: 'guest.one@tests.invalid', whatsapp: '+65 9123 0001' },
    { name: 'Guest Two', email: null, whatsapp: '+65 9123 0002' },
  ],
});

// 376: a HitPay order, with HitPay's payment request and payment ids where Stripe's go.
export const HITPAY_REQUEST_ID = '9e9be41b-2866-4307-8621-e35c633c431f';
export const HITPAY_PAYMENT_ID = '9e9be41c-2869-4b8c-8701-6c44af86b7d0';

export const hitpayPaidOrder = (): PaidOrder => ({
  ...paidOrder(),
  provider: 'hitpay',
  stripe_session_id: HITPAY_REQUEST_ID,
  stripe_payment_intent: HITPAY_PAYMENT_ID,
  livemode: true,
});

export const hitpayNamesOrder = (): NamesOrder => ({
  ...namesOrder(),
  provider: 'hitpay',
  stripe_session_id: HITPAY_REQUEST_ID,
  livemode: true,
});
