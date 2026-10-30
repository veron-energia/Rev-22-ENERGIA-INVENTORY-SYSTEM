// Made-up cal.com webhooks for the tests. Fixture data only: this repository is
// public (invented names, @example.invalid addresses, ACMA's fictional phones).

import type { BookingEvent } from './payload.ts';

export const SECRET = 'test-calcom-webhook-secret';
export const UID = 'fixtureUid0001AbCd';

/** A BOOKING_CREATED body shaped like cal.com's, with the personal fields the function must drop. */
export const createdBody = (overrides: Record<string, unknown> = {}) => ({
  triggerEvent: 'BOOKING_CREATED',
  createdAt: '2026-10-29T03:00:00.000Z',
  payload: {
    type: 'free',
    title: 'Fixture Person +61255509001 Fixture Centre Free Fixture Bundle',
    description: 'fixture description',
    additionalNotes: 'fixture private note',
    startTime: '2026-10-31T06:00:00Z',
    endTime: '2026-10-31T07:00:00Z',
    organizer: { id: 1, name: 'Fixture Organiser', email: 'organiser@example.invalid', timeZone: 'Asia/Singapore' },
    responses: {
      name: { label: 'your_name', value: 'Fixture Person' },
      email: { label: 'email_address', value: 'fixture.person@example.invalid' },
      'WhatsApp-Number': { label: 'WhatsApp Number', value: '+61255509001' },
      smsReminderNumber: { label: 'Phone number', value: '+61255509002' },
      notes: { label: 'Notes', value: 'fixture answer' },
      affiliate: { label: 'Referred by', value: '(Fixture Affiliate) ' },
    },
    attendees: [
      { name: 'Fixture Person', email: 'fixture.person@example.invalid', phoneNumber: '+61255509003', timeZone: 'Asia/Singapore' },
      { name: 'Fixture Guest', email: 'fixture.guest@example.invalid', timeZone: 'Asia/Singapore' },
    ],
    location: 'Fixture Centre',
    eventTypeId: 1001,
    uid: UID,
    bookingId: 42,
    status: 'ACCEPTED',
    metadata: { videoCallUrl: 'https://video.example.invalid/fixture' },
    ...overrides,
  },
});

/** What reaches the database for createdBody(): the kept fields only. */
export const createdEvent = (): BookingEvent => ({
  triggerEvent: 'BOOKING_CREATED',
  createdAt: '2026-10-29T03:00:00.000Z',
  payload: {
    uid: UID,
    rescheduleUid: null,
    fromReschedule: null,
    startTime: '2026-10-31T06:00:00Z',
    endTime: '2026-10-31T07:00:00Z',
    rescheduleStartTime: null,
    rescheduleEndTime: null,
    eventTypeId: 1001,
    type: 'free',
    responses: { 'WhatsApp-Number': '+61255509001', smsReminderNumber: '+61255509002', email: 'fixture.person@example.invalid' },
    attendees: [{ phoneNumber: '+61255509003', email: 'fixture.person@example.invalid' }],
    smsReminderNumber: null,
  },
});

/** cal.com's PING (sent by "Ping test" in its webhook settings). */
export const pingBody = () => ({
  triggerEvent: 'PING',
  createdAt: '2026-10-29T03:00:00.000Z',
  payload: { type: 'Test', title: 'Test trigger event', startTime: '2026-10-29T03:00:00.000Z', endTime: '2026-10-29T03:00:00.000Z' },
});
