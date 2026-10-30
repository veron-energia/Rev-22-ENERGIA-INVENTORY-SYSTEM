// What of a cal.com webhook reaches the database (480).
//
// cal.com's body is {triggerEvent, createdAt, payload}; a booking's payload
// carries everything about it (names, answers, notes, the title, the location,
// the organiser, video links). Only what calcom_booking_ingest reads is passed
// on: the booking's uid and the uid it was rescheduled from, its times, its
// event type, and the phone and email the database matches
// a customer by (the WhatsApp-Number, smsReminderNumber and email answers, the
// first attendee's phone and email). Everything else is dropped here, so it is
// never sent anywhere. The database decides what the values mean; this file
// only picks them. A booking without a readable createdAt is refused: the
// database orders a booking's events by it, and cal.com always sends it.

/** The triggers stored; anything else is answered and ignored. */
export const BOOKING_TRIGGERS = ['BOOKING_CREATED', 'BOOKING_RESCHEDULED', 'BOOKING_CANCELLED'] as const;
export type BookingTrigger = (typeof BOOKING_TRIGGERS)[number];

export interface BookingEvent {
  triggerEvent: BookingTrigger;
  createdAt: string;
  payload: {
    uid: string;
    rescheduleUid: string | null;
    fromReschedule: string | null;
    startTime: string | null;
    endTime: string | null;
    rescheduleStartTime: string | null;
    rescheduleEndTime: string | null;
    eventTypeId: number | null;
    type: string | null;
    responses: { 'WhatsApp-Number': string | null; smsReminderNumber: string | null; email: string | null };
    attendees: { phoneNumber: string | null; email: string | null }[];
    smsReminderNumber: string | null;
  };
}

export type Classified =
  | { kind: 'ping' }
  | { kind: 'ignored'; trigger: string }
  | { kind: 'booking'; trigger: BookingTrigger; event: BookingEvent }
  | { kind: 'invalid'; field: string };

const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);

// A string PostgreSQL cannot keep in jsonb (a NUL) or that is not text (a lone
// surrogate) is treated as absent, as is anything that is not a string.
// deno-lint-ignore no-control-regex
const UNSTORABLE = /\u0000|[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/;
const MAX_TEXT = 1000;

function text(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  if (!t || t.length > MAX_TEXT || UNSTORABLE.test(t)) return null;
  return t;
}

/** A booking answer: {label, value} or the value itself. */
const answer = (v: unknown): string | null => (isObject(v) ? text(v.value) : text(v));

/** The trigger, and for a booking only the fields the database reads. */
export function classify(body: unknown): Classified {
  if (!isObject(body)) return { kind: 'invalid', field: 'body' };
  const trigger = typeof body.triggerEvent === 'string' ? body.triggerEvent : null;
  if (!trigger) return { kind: 'invalid', field: 'triggerEvent' };
  if (trigger === 'PING') return { kind: 'ping' };
  if (!(BOOKING_TRIGGERS as readonly string[]).includes(trigger)) return { kind: 'ignored', trigger: safeTrigger(trigger) };

  const p = body.payload;
  if (!isObject(p)) return { kind: 'invalid', field: 'payload' };
  const uid = text(p.uid);
  if (!uid) return { kind: 'invalid', field: 'payload.uid' };
  // Never sent on as null: the database would take a booking without it as
  // sent now, newer than anything stored. A string it cannot read goes on and
  // is refused there (22023, a 400).
  const createdAt = text(body.createdAt);
  if (!createdAt) return { kind: 'invalid', field: 'createdAt' };
  const responses = isObject(p.responses) ? p.responses : {};
  const first = Array.isArray(p.attendees) && isObject(p.attendees[0]) ? p.attendees[0] : null;

  return {
    kind: 'booking',
    trigger: trigger as BookingTrigger,
    event: {
      triggerEvent: trigger as BookingTrigger,
      createdAt,
      payload: {
        uid,
        rescheduleUid: text(p.rescheduleUid),
        fromReschedule: text(p.fromReschedule),
        startTime: text(p.startTime),
        endTime: text(p.endTime),
        rescheduleStartTime: text(p.rescheduleStartTime),
        rescheduleEndTime: text(p.rescheduleEndTime),
        eventTypeId: typeof p.eventTypeId === 'number' && Number.isSafeInteger(p.eventTypeId) && p.eventTypeId >= 0 ? p.eventTypeId : null,
        type: text(p.type),
        responses: {
          'WhatsApp-Number': answer(responses['WhatsApp-Number']),
          smsReminderNumber: answer(responses.smsReminderNumber),
          email: answer(responses.email),
        },
        attendees: first ? [{ phoneNumber: text(first.phoneNumber), email: text(first.email) }] : [],
        smsReminderNumber: text(p.smsReminderNumber),
      },
    },
  };
}

/** A trigger name for the logs: cal.com's own words only (upper case and _), else 'other'. */
export const safeTrigger = (t: string): string => (/^[A-Z_]{1,40}$/.test(t) ? t : 'other');
