// What of a cal.com webhook reaches the database (480).

import { assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { classify } from './payload.ts';
import { createdBody, createdEvent, pingBody, UID } from './fixtures.ts';

Deno.test('a booking keeps only the fields the database reads', () => {
  const c = classify(createdBody());
  assertEquals(c, { kind: 'booking', trigger: 'BOOKING_CREATED', event: createdEvent() });
  const kept = JSON.stringify(c);
  for (const dropped of ['Fixture Person"', 'fixture.guest', 'fixture answer', 'private note', 'Fixture Affiliate', 'Fixture Centre',
                         'organiser@', 'video.example', '"bookingId"', '"title"', '"description"']) {
    assertFalse(kept.includes(dropped), dropped);
  }
});

Deno.test('the three booking triggers are bookings; PING is a ping; anything else is ignored', () => {
  for (const t of ['BOOKING_CREATED', 'BOOKING_RESCHEDULED', 'BOOKING_CANCELLED']) {
    assertEquals(classify({ ...createdBody(), triggerEvent: t }).kind, 'booking', t);
  }
  assertEquals(classify(pingBody()), { kind: 'ping' });
  for (const t of ['BOOKING_REJECTED', 'BOOKING_REQUESTED', 'MEETING_ENDED', 'BOOKING_NO_SHOW_UPDATED', 'FORM_SUBMITTED']) {
    assertEquals(classify({ ...createdBody(), triggerEvent: t }), { kind: 'ignored', trigger: t });
  }
  // A trigger that is not cal.com's own word is logged as 'other'.
  assertEquals(classify({ triggerEvent: 'booking created by +61255509001' }), { kind: 'ignored', trigger: 'other' });
});

Deno.test('a reschedule keeps the old uid and its times, in either of cal.com\'s spellings', () => {
  const c = classify({ ...createdBody({ uid: 'fixtureUidNew0002', rescheduleUid: UID, rescheduleStartTime: '2026-10-30T06:00:00Z',
    rescheduleEndTime: '2026-10-30T07:00:00Z' }), triggerEvent: 'BOOKING_RESCHEDULED' });
  if (c.kind !== 'booking') throw new Error(c.kind);
  assertEquals([c.event.payload.uid, c.event.payload.rescheduleUid, c.event.payload.rescheduleStartTime, c.event.payload.rescheduleEndTime],
    ['fixtureUidNew0002', UID, '2026-10-30T06:00:00Z', '2026-10-30T07:00:00Z']);
  const d = classify({ ...createdBody({ fromReschedule: UID }), triggerEvent: 'BOOKING_RESCHEDULED' });
  if (d.kind !== 'booking') throw new Error(d.kind);
  assertEquals(d.event.payload.fromReschedule, UID);
});

Deno.test('answers are read as {value} or as the value itself; anything else is absent', () => {
  const c = classify(createdBody({ responses: { 'WhatsApp-Number': '+61255509004', email: { value: 42 }, smsReminderNumber: ['x'] },
    attendees: 'nobody', smsReminderNumber: ' +61255509005 ', eventTypeId: '1001' }));
  if (c.kind !== 'booking') throw new Error(c.kind);
  assertEquals(c.event.payload.responses, { 'WhatsApp-Number': '+61255509004', smsReminderNumber: null, email: null });
  assertEquals(c.event.payload.attendees, []);
  assertEquals(c.event.payload.smsReminderNumber, '+61255509005');
  assertEquals(c.event.payload.eventTypeId, null);
});

Deno.test('text PostgreSQL cannot keep, or too long, is absent', () => {
  const c = classify(createdBody({ responses: { 'WhatsApp-Number': '+6125550\u00009006', email: 'a\ud800b@example.invalid' },
    type: 'x'.repeat(1001) }));
  if (c.kind !== 'booking') throw new Error(c.kind);
  assertEquals([c.event.payload.responses['WhatsApp-Number'], c.event.payload.responses.email, c.event.payload.type], [null, null, null]);
});

Deno.test('a body without a trigger, a payload or a uid is invalid, naming the field', () => {
  assertEquals(classify('text'), { kind: 'invalid', field: 'body' });
  assertEquals(classify([createdBody()]), { kind: 'invalid', field: 'body' });
  assertEquals(classify({ payload: {} }), { kind: 'invalid', field: 'triggerEvent' });
  assertEquals(classify({ triggerEvent: 'BOOKING_CREATED' }), { kind: 'invalid', field: 'payload' });
  assertEquals(classify(createdBody({ uid: '' })), { kind: 'invalid', field: 'payload.uid' });
  assertEquals(classify(createdBody({ uid: 7 })), { kind: 'invalid', field: 'payload.uid' });
});

Deno.test('a booking without a readable createdAt is invalid (never sent on as null); PING and ignored triggers need none', () => {
  for (const v of [undefined, null, '', '   ', 1793000000000, { at: '2026-10-29T03:00:00Z' }, ['2026-10-29T03:00:00Z'], '2'.repeat(1001), 'a\u0000b']) {
    const body: Record<string, unknown> = createdBody();
    if (v === undefined) delete body.createdAt; else body.createdAt = v;
    for (const t of ['BOOKING_CREATED', 'BOOKING_RESCHEDULED', 'BOOKING_CANCELLED']) {
      assertEquals(classify({ ...body, triggerEvent: t }), { kind: 'invalid', field: 'createdAt' }, `${t} ${JSON.stringify(v)}`);
    }
  }
  assertEquals(classify({ triggerEvent: 'PING' }), { kind: 'ping' });
  assertEquals(classify({ triggerEvent: 'MEETING_ENDED' }), { kind: 'ignored', trigger: 'MEETING_ENDED' });
  // A string the database cannot read still goes on: the database refuses it (22023, a 400).
  const c = classify({ ...createdBody(), createdAt: ' yesterday ' });
  if (c.kind !== 'booking') throw new Error(c.kind);
  assertEquals(c.event.createdAt, 'yesterday');
});
