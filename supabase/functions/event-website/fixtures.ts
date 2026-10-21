// Fake messages for the tests (436). Fixture data only: this repository is
// public. Phones are ACMA's fictional numbers, emails @example.com.

import type { EventWebsiteRequest } from './contract.ts';

export const EVENT = 'HEALTH-SEMINAR-NOV26';
export const LIVE_KEY = 'evk_live_' + 'A'.repeat(21) + '-_' + 'b'.repeat(20);
export const TEST_KEY = 'evk_test_' + 'Z'.repeat(43);
export const REQUEST_ID = '0b9a2f0e-3c4d-4e5f-8a6b-7c8d9e0f1a2b';
export const TOKEN_1 = 'vip_abcdefghijklmnopqrstuvwxyz';
export const TOKEN_2 = 'vip_234567abcdefghijklmnopqrst';
export const PAYMENT_REQUEST_ID = '9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d';
export const PAYMENT_ID = '1f2e3d4c-5b6a-4978-8a9b-0c1d2e3f4a5b';

export const payer = () => ({ name: 'Payer One', email: 'payer.one@example.com', phone: '+61491570737' });

export function messages(): { [T in EventWebsiteRequest['type']]: Extract<EventWebsiteRequest, { type: T }> } {
  return {
    event_info: { type: 'event_info', event: EVENT },
    referral_info: { type: 'referral_info', event: EVENT, code: 'ABCD1234' },
    register: {
      type: 'register', event: EVENT,
      registration: {
        registration_id: 'REG-20261101-1A2B3C4D', submitted_at: '2026-11-01T02:00:00.000Z', referral_code: null,
        people: [
          { position: 1, first_name: 'Ada', last_name: 'Example', phone: '+61491570737', email: 'ada@example.com',
            days: ['2026-11-23', '2026-11-24'], vip: true },
          { position: 2, first_name: 'Ben', last_name: '', phone: '+61491572983', email: 'ben@example.com',
            days: ['2026-11-24'], vip: false },
        ],
      },
    },
    person: { type: 'person', event: EVENT, upgrade_token: TOKEN_1 },
    vip_checkout: {
      type: 'vip_checkout', event: EVENT,
      order: { order_id: 'VIP-20261101-1A2B3C4D', upgrade_tokens: [TOKEN_1, TOKEN_2], payer: payer(), livemode: true,
               checkout_opened_at: '2026-11-01T02:05:00+08:00' },
    },
    vip_paid: {
      type: 'vip_paid', event: EVENT,
      payment: { order_id: 'VIP-20261101-1A2B3C4D', provider: 'hitpay', payment_request_id: PAYMENT_REQUEST_ID,
                 payment_id: PAYMENT_ID, amount_cents: 14400, currency: 'SGD', livemode: true,
                 paid_at: '2026-11-01T02:09:00.000Z', upgrade_tokens: [TOKEN_1, TOKEN_2], payer: payer() },
    },
    vip_transfer: {
      type: 'vip_transfer', event: EVENT,
      order: { order_id: 'VIP-20261101-5E6F7A8B', upgrade_tokens: [TOKEN_1], payer: { ...payer(), phone: null },
               method: 'paynow', reference: 'PN 778899', paid_on: '2026-11-01', amount_cents: 7200,
               submitted_at: '2026-11-01T03:00:00Z' },
    },
    vip_refund: {
      type: 'vip_refund', event: EVENT,
      refund: { order_id: 'VIP-20261101-1A2B3C4D', payment_request_id: PAYMENT_REQUEST_ID, payment_id: null,
                refunded_cents_total: 7200, refunded_at: '2026-11-02T01:00:00Z', livemode: true },
    },
    sync: { type: 'sync', event: EVENT },
    planning_answers: {
      type: 'planning_answers', event: EVENT,
      planning: {
        submitted_at: '2026-11-01T02:01:00.000Z',
        people: [
          { upgrade_token: TOKEN_1, version: 0, answers: {
              food: 'vegetarian', food_other: null, allergy: 'no', allergy_details: null,
              timing: [{ date: '2026-11-23', whole_day: true, arrive: null, leave: null },
                       { date: '2026-11-24', whole_day: false, arrive: '14:00', leave: '19:00' }],
              talks: ['Sleep better, stress less', 'Caring for your eyes'], access: [], access_other: null,
              heard_from: 'tiktok', heard_from_other: null, question: null } },
          { upgrade_token: TOKEN_2, version: 3, answers: {
              food: null, food_other: null, allergy: 'yes', allergy_details: 'Peanuts',
              timing: [], talks: [], access: ['wheelchair'], access_other: null,
              heard_from: 'other', heard_from_other: 'Community centre notice',
              question: 'Is it good to walk every day?\nHow long for?' } },
        ],
      },
    },
  };
}
