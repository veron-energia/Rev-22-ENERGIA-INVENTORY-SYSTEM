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
