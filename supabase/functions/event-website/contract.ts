/**
 * EVENT WEBSITE CONTRACT (v1, 20 Oct 2026; planning answers 21 Oct 2026)
 *
 * The single source of truth between an event website (first: the Free Two Day
 * Health Seminar site, healthtalk-rev22energia.vercel.app) and the Energia app
 * (Supabase edge function `event-website`, migration 436).
 *
 * Copy this file VERBATIM into:
 *   - the app:     supabase/functions/event-website/contract.ts   (Deno; the edge function imports its types,
 *                  regexes and limits), and src/components/events/eventWebsiteContract.ts (the Website tab shows
 *                  this file's text, imported with Vite's ?raw, as the code to copy)
 *   - the website: src/lib/event-api-contract.ts
 * A test in each repo compares the copy's md5 with the one recorded beside it, so a drift is a failing test.
 *
 * Plain TypeScript with no imports, so it compiles under Deno, Node 20+ and Next.js alike.
 *
 * NOTHING HERE IS SECRET. The key lives only in the website's server settings (Vercel, ENERGIA_EVENT_API_KEY) and is
 * stored by the app as a SHA-256 hash. Never put real names, phones or emails in tests: phone fixtures are ACMA
 * fictional numbers (+61491570737, +61491572983, +61491573770), emails @example.com.
 */

// ─────────────────────────────────────────────────────────────────────────────
// 1. Transport
// ─────────────────────────────────────────────────────────────────────────────

export const CONTRACT_VERSION = 1 as const;

/** POST https://<project>.supabase.co/functions/v1/event-website (the Website tab shows the full address). */
export const ENDPOINT_PATH = '/functions/v1/event-website';

/** The per-event key, as the Owner copied it from the Website tab. Not "Authorization": the gateway owns that one. */
export const HEADER_KEY = 'x-energia-key';
/** Unix seconds when the request was made. Refused when more than 300 s old or 60 s ahead. */
export const HEADER_TIMESTAMP = 'x-energia-timestamp';
/** A lower-case UUID v4 per logical request. Required on every WRITE message; reuse it when retrying the same request. */
export const HEADER_REQUEST_ID = 'x-energia-request-id';

export const MAX_BODY_BYTES = 16 * 1024;
export const MAX_AGE_SECONDS = 300;
export const MAX_FUTURE_SECONDS = 60;
/** The website waits this long for one answer, then treats it as a passing fault. */
export const CLIENT_TIMEOUT_MS = 8000;
/** A passing fault (503, network, timeout) is tried again after these delays, then given up (and retried by the next sync). */
export const RETRY_DELAYS_MS: readonly number[] = [500, 1500];

/** evk_live_… or evk_test_…, then 43 base64url characters (32 random bytes). */
export const KEY_RE = /^evk_(live|test)_[A-Za-z0-9_-]{43}$/;
export const REQUEST_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
/** The event code shown on the Website tab, e.g. HEALTH-SEMINAR-NOV26. */
export const EVENT_CODE_RE = /^[A-Z0-9][A-Z0-9-]{2,39}$/;
/** Made by the website when the registration form opens (Singapore date, then 8 upper-case hex digits). */
export const REGISTRATION_ID_RE = /^REG-\d{8}-[0-9A-F]{8}$/;
/** Made by the website when a VIP payment is started (online or by transfer). */
export const VIP_ORDER_ID_RE = /^VIP-\d{8}-[0-9A-F]{8}$/;
/** Made by the app, one per registered person; the website puts it in that person's VIP link (/vip/<token>). */
export const UPGRADE_TOKEN_RE = /^vip_[a-z2-7]{26}$/;
/** HitPay payment request and payment ids: lower-case UUIDs (as in web-ticket-order). */
export const HITPAY_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
/** An affiliate's referral code, upper-cased by the website (as on /signup/<code> today). */
export const REFERRAL_CODE_RE = /^[A-Z0-9]{4,16}$/;
export const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
/** A time with a zone (Z or ±hh:mm). A bare local time is refused, as in web-ticket-order. */
export const ISO_TIME_RE = /^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d{1,9})?)?(Z|[+-](0\d|1[0-5]):?[0-5]\d)$/;

/** Every HitPay reference_number this website makes starts with this, so other payments on the account are ignored. */
export const HITPAY_REFERENCE_PREFIX = 'HEALTHTALK26-';
/** reference_number = HITPAY_REFERENCE_PREFIX + order_id, e.g. HEALTHTALK26-VIP-20261101-1A2B3C4D */
export const hitpayReference = (orderId: string): string => `${HITPAY_REFERENCE_PREFIX}${orderId}`;

export const MAX_PEOPLE = 10;
export const LIMITS = {
  first_name: 100,
  last_name: 100,
  /** As the website normalised it (E.164, e.g. +6591234567). The app reads it with its own phone policy too. */
  phone: 20,
  email: 254,
  payer_name: 200,
  reference: 100,
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// 2. Shared shapes
// ─────────────────────────────────────────────────────────────────────────────

/** YYYY-MM-DD, a day of the event (Singapore). */
export type IsoDate = string;
/** An ISO time with a zone. */
export type IsoTime = string;

/**
 * A person's VIP state, as the app sees it now.
 *  none      not VIP, nothing waiting
 *  pending   a VIP payment for them is waiting (checkout open, or a PayNow / bank transfer a Manager has not confirmed,
 *            or a paid order waiting for staff)
 *  paid      VIP: their VIP invoice is paid and not cancelled or refunded
 *  refunded  their VIP invoice was cancelled or refunded (they are a free guest again)
 */
export type VipState = 'none' | 'pending' | 'paid' | 'refunded';

export interface EventDayInfo {
  date: IsoDate;
  /** "Day 1", "Day 2" in date order. */
  label: string;
  /** The day can still be chosen at registration (before its daily end, and the event on sale). */
  open: boolean;
}

export interface Payer {
  name: string;
  email: string;
  phone: string | null;
}

// ─────────────────────────────────────────────────────────────────────────────
// 2b. Planning answers (21 Oct 2026): per person, every question optional. Kept in the app per guest (the source of
//     truth); staff see them on the Event page and may change them on the guest's behalf. Never health conditions.
// ─────────────────────────────────────────────────────────────────────────────

/** Q1 "Any dietary preference?" */
export const FOOD_CHOICES = ['no_preference', 'vegetarian', 'vegan', 'halal', 'no_beef', 'other'] as const;
export type FoodChoice = (typeof FOOD_CHOICES)[number];
export const FOOD_LABELS: Record<FoodChoice, string> = {
  no_preference: 'No preference', vegetarian: 'Vegetarian', vegan: 'Vegan', halal: 'Halal', no_beef: 'No beef', other: 'Other',
};

/** Q5 "Anything we should prepare for you?" (any of them, and access_other). */
export const ACCESS_CHOICES = ['wheelchair', 'walking_help', 'front_seat'] as const;
export type AccessChoice = (typeof ACCESS_CHOICES)[number];
export const ACCESS_LABELS: Record<AccessChoice, string> = {
  wheelchair: 'Wheelchair access', walking_help: 'Help with walking or stairs', front_seat: 'Seat near the front (hearing or sight)',
};

/** Q6 "How did you hear about the seminar?" */
export const HEARD_FROM_CHOICES = ['tiktok', 'facebook', 'instagram', 'google', 'whatsapp', 'friend_family', 'staff', 'email', 'other'] as const;
export type HeardFromChoice = (typeof HEARD_FROM_CHOICES)[number];
export const HEARD_FROM_LABELS: Record<HeardFromChoice, string> = {
  tiktok: 'TikTok', facebook: 'Facebook', instagram: 'Instagram', google: 'Google', whatsapp: 'WhatsApp',
  friend_family: 'Friend or family', staff: 'Rev22 staff or consultant', email: 'Email', other: 'Other',
};

/**
 * Q4 "Which talks interest you most?": offered while the event's own titles are not saved yet (event_info's
 * talk_titles is null). General wellness wording, no medical claims (the owner, 21 Oct 2026). The app's 436 holds the
 * same list (event_web_talk_titles); a test in the app proves the two are identical.
 */
export const SUGGESTED_TALK_TITLES: readonly string[] = [
  'Sleep better, stress less',
  'Healthy joints, back and muscles',
  'Good circulation for everyday energy',
  'Caring for your eyes',
  'Ageing well and staying active',
  'Eating well for long-term health',
  "Women's wellness",
];

/** Characters of each text answer (after trimming); of a talk title (the Website tab's editor keeps to it too); talks. */
export const PLANNING_LIMITS = {
  food_other: 60,
  allergy_details: 120,
  access_other: 120,
  heard_from_other: 60,
  question: 300,
  talk_title: 120,
  talks: 20,
} as const;

/** Arriving and leaving times are HH:MM (Singapore), on TIME_STEP_MINUTES steps from the event's daily start. */
export const TIME_STEP_MINUTES = 30;
export const HHMM_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * The only arriving and leaving times the app accepts for a part of the day, from event_info's daily_start and
 * daily_end. Arriving: the daily start, then every 30 minutes, at the latest 30 minutes before the daily end. Leaving:
 * 30 minutes after the daily start, then every 30 minutes, and the daily end itself. Leaving must be after arriving.
 * 09:00-19:00 gives arriving 09:00 … 18:30 and leaving 09:30 … 19:00 (20 each). No hours: no part-day times.
 */
export function planningTimeOptions(dailyStart: string | null, dailyEnd: string | null): { arrive: string[]; leave: string[] } {
  if (!dailyStart || !dailyEnd || !HHMM_RE.test(dailyStart) || !HHMM_RE.test(dailyEnd)) return { arrive: [], leave: [] };
  const minutes = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
  const hhmm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  const start = minutes(dailyStart);
  const end = minutes(dailyEnd);
  const arrive: string[] = [];
  const leave: string[] = [];
  for (let m = start; m <= end - TIME_STEP_MINUTES; m += TIME_STEP_MINUTES) arrive.push(hhmm(m));
  for (let m = start + TIME_STEP_MINUTES; m < end; m += TIME_STEP_MINUTES) leave.push(hhmm(m));
  if (end - start >= TIME_STEP_MINUTES) leave.push(hhmm(end));
  return { arrive, leave };
}

export interface PlanningDay {
  /** A day the person is coming now (a VIP comes every day). */
  date: IsoDate;
  /**
   * true: "Whole day" (arrive and leave null). false: "Part of the day": arrive and leave both from
   * planningTimeOptions, arrive before leave. A part of the day from the daily start to the daily end is kept as the
   * whole day.
   */
  whole_day: boolean;
  arrive: string | null;
  leave: string | null;
}

/**
 * One person's answers. Every field is sent every time; null or [] = not answered. A text that goes with a choice is
 * sent only with it (food_other with 'other', allergy_details with 'yes', heard_from_other with 'other'). An empty
 * text is null, never "".
 */
export interface PlanningAnswers {
  food: FoodChoice | null;
  food_other: string | null;
  allergy: 'no' | 'yes' | null;
  /** May stay null with 'yes' (staff still see that there is an allergy). */
  allergy_details: string | null;
  /** At most one per day, by date. A day left out was not answered. */
  timing: PlanningDay[];
  /** Titles as text, distinct (a later edit of the event's titles never changes answers already kept). */
  talks: string[];
  access: AccessChoice[];
  access_other: string | null;
  heard_from: HeardFromChoice | null;
  heard_from_other: string | null;
  /** The only answer that may hold line breaks. */
  question: string | null;
}

export interface PlanningRecord {
  /** 1 at the first save, one more at each change. Send it back as `version` when saving these answers again. */
  version: number;
  answers: PlanningAnswers;
  updated_at: IsoTime;
  /** 'guest': saved from the website; 'staff': changed on the Event page on the guest's behalf. */
  updated_by: 'guest' | 'staff';
}

export type PlanningRefusal =
  | 'person_not_found' // a token the app does not know (or of another event, or of the other kind of key)
  | 'person_cancelled' // not registered any more (taken off the list, or the registration closed by staff)
  | 'day_not_chosen' // a timing day that is not one of the person's days now
  | 'outside_hours' // a time not in planningTimeOptions for the event's hours now (or the event has no hours)
  | 'talk_not_offered' // a talk that is not one of the event's titles now (and was not kept for them before)
  | 'changed_meanwhile'; // other answers were kept since `version` (staff may have changed them): see `planning`

/** Why a whole planning_answers call is closed. The website switched Off or the event off sale do not stop answers. */
export type PlanningClosedReason = 'ended' | 'event_deleted';

// ─────────────────────────────────────────────────────────────────────────────
// 3. Requests (the body is JSON; any field not listed here is a refused request, not an ignored one)
// ─────────────────────────────────────────────────────────────────────────────

/** READ. The event as the website shows it. Never any capacity, count or seats left. Cache it for at most 60 s. */
export interface EventInfoRequest {
  type: 'event_info';
  event: string;
}

/** READ. Whose referral code this is (for "You've been invited by …"). Same answer as the app's own /r/<code> page. */
export interface ReferralInfoRequest {
  type: 'referral_info';
  event: string;
  code: string;
}

export interface RegisterPerson {
  /** 1..n, in the order the form lists them. Person 1 is the one who filled in the form. */
  position: number;
  first_name: string;
  /** May be empty. */
  last_name: string;
  phone: string;
  email: string;
  /** At least one; each a day of the event that is still open. */
  days: IsoDate[];
  /** The person wants VIP now: the website starts a VIP payment for them right after this answer. */
  vip: boolean;
}

/** WRITE. Free registration of 1..10 people. Everyone registers free; VIP is paid for afterwards (vip_checkout / vip_transfer). */
export interface RegisterRequest {
  type: 'register';
  event: string;
  registration: {
    /** REG-YYYYMMDD-XXXXXXXX, made when the form opened; the same id on every resubmit of that form. */
    registration_id: string;
    submitted_at: IsoTime;
    /** From /signup/<code> or ?ref=<code> (the website keeps it in a cookie until the event ends). */
    referral_code: string | null;
    people: RegisterPerson[];
  };
}

/** READ. One person, by the token in their VIP link, for the upgrade page. */
export interface PersonRequest {
  type: 'person';
  event: string;
  upgrade_token: string;
}

/**
 * WRITE. A VIP payment is about to open in HitPay. The app checks that each person can become VIP, prices it (the VIP
 * ticket's price per person, no early bird) and keeps the order as pending. Open HitPay only after status 'ok', for
 * exactly total_cents, with reference_number = hitpayReference(order_id) and expires_after 60 mins.
 */
export interface VipCheckoutRequest {
  type: 'vip_checkout';
  event: string;
  order: {
    /** VIP-YYYYMMDD-XXXXXXXX, made by the website for this payment. */
    order_id: string;
    /** 1..10 people: the tokens the website kept from its own register answers, or the one in /vip/<token> (person
     *  never gives out another person's token). One payer may pay for several. */
    upgrade_tokens: string[];
    payer: Payer;
    /** false in the HitPay sandbox. A live key refuses a sandbox order; a test key refuses a live one. */
    livemode: boolean;
    checkout_opened_at: IsoTime;
  };
}

/**
 * WRITE. HitPay says the payment request is completed, and the website has READ IT BACK from HitPay's API (the webhook
 * body and the redirect are never trusted on their own). Sent by the webhook, and again by /vip/done and by the sync
 * for any VIP payment whose answer is missing. upgrade_tokens and payer repeat what vip_checkout sent, so the app can
 * still record the payment if that call was lost.
 */
export interface VipPaidRequest {
  type: 'vip_paid';
  event: string;
  payment: {
    order_id: string;
    provider: 'hitpay';
    payment_request_id: string;
    payment_id: string | null;
    amount_cents: number;
    currency: 'SGD';
    livemode: boolean;
    /** When HitPay took the payment (the website's hitpayPaidAt reading, as today). */
    paid_at: IsoTime;
    upgrade_tokens: string[];
    payer: Payer;
  };
}

/**
 * WRITE. VIP paid by PayNow or bank transfer: the buyer paid, then entered the reference. The order waits on the Event
 * page's Website orders tab until a Manager confirms the money arrived (Create invoices). Never invoiced by itself.
 */
export interface VipTransferRequest {
  type: 'vip_transfer';
  event: string;
  order: {
    order_id: string;
    upgrade_tokens: string[];
    payer: Payer;
    method: 'paynow' | 'bank';
    /** The bank's or PayNow's reference, as the buyer typed it. */
    reference: string;
    /** The Singapore day they paid; never after today. */
    paid_on: IsoDate;
    /** What they say they paid. A different amount still goes through, flagged for the Manager. */
    amount_cents: number;
    submitted_at: IsoTime;
  };
}

/**
 * WRITE. HitPay says the payment was refunded, in full or in part (its charge.updated event; the website reads the
 * charge back from HitPay first). The app only RECORDS it: the Website orders tab then tells a Manager to cancel or
 * refund the VIP invoice(s) with the app's own refund flow. refunded_cents_total is the total refunded so far, not
 * this refund alone, so a repeat changes nothing.
 */
export interface VipRefundRequest {
  type: 'vip_refund';
  event: string;
  refund: {
    order_id: string;
    payment_request_id: string;
    payment_id: string | null;
    refunded_cents_total: number;
    refunded_at: IsoTime;
    livemode: boolean;
  };
}

/** READ (notes the time). Everything the website's Google Sheet tab lists. At most once a minute per key. */
export interface SyncRequest {
  type: 'sync';
  event: string;
}

export interface PlanningPersonAnswers {
  /** The person's own upgrade token (from the website's register answer, or the one in /vip/<token>; never another's). */
  upgrade_token: string;
  /** The PlanningRecord.version the page was showing (0 when it showed none). */
  version: number;
  answers: PlanningAnswers;
}

/**
 * WRITE. Each person's planning answers, replacing what was kept for them (section 6, PLANNING ANSWERS). Allowed
 * while the person is registered and until the event has ended. A test key checks everything and keeps nothing.
 */
export interface PlanningAnswersRequest {
  type: 'planning_answers';
  event: string;
  planning: {
    /** When Save was pressed (to the second). Its shape is checked; the app keeps nothing of it. */
    submitted_at: IsoTime;
    /** 1..MAX_PEOPLE people, distinct tokens. */
    people: PlanningPersonAnswers[];
  };
}

export type EventWebsiteRequest =
  | EventInfoRequest
  | ReferralInfoRequest
  | RegisterRequest
  | PersonRequest
  | VipCheckoutRequest
  | VipPaidRequest
  | VipTransferRequest
  | VipRefundRequest
  | SyncRequest
  | PlanningAnswersRequest;

export type MessageType = EventWebsiteRequest['type'];

/** These need HEADER_REQUEST_ID; the app answers a repeat of the same request id + body with its first answer. */
export const WRITE_TYPES = ['register', 'vip_checkout', 'vip_paid', 'vip_transfer', 'vip_refund', 'planning_answers'] as const;
export const READ_TYPES = ['event_info', 'referral_info', 'person', 'sync'] as const;
export const isWriteType = (t: MessageType): boolean => (WRITE_TYPES as readonly string[]).includes(t);

// ─────────────────────────────────────────────────────────────────────────────
// 4. Answers (HTTP 200: { ok: true, ... }; anything else: ErrorAnswer)
// ─────────────────────────────────────────────────────────────────────────────

interface Answered {
  ok: true;
  /** true when the key is a TEST key: nothing reached customers, guests, invoices or stock (see section 6). */
  test: boolean;
}

export interface EventInfoAnswer extends Answered {
  status: 'ok';
  event: {
    code: string;
    title: string;
    days: EventDayInfo[];
    /** HH:MM, Singapore. */
    daily_start: string | null;
    daily_end: string | null;
    time_zone: 'Asia/Singapore';
    /** null until the Owner sets it: the website shows "Venue to be announced". */
    venue: string | null;
    registration_open: boolean;
    /** Why registration is closed, when it is. */
    closed_reason: ClosedReason | null;
    /**
     * The talks to ask about (Q4), in order: null until an Owner, Admin or Manager saves the event's own titles (offer
     * SUGGESTED_TALK_TITLES); [] = do not ask about talks.
     */
    talk_titles: string[] | null;
    /** Planning answers can be saved: the event is not deleted and has not ended. Off and off sale do not stop them. */
    planning_open: boolean;
    vip: {
      price_cents: number;
      currency: 'SGD';
      on_sale: boolean;
      /** VIP is per person and covers every day of the event. */
      covers: 'all_days';
    };
  };
}

export type ClosedReason = 'website_off' | 'off_sale' | 'ended' | 'event_deleted';

export interface ReferralInfoAnswer extends Answered {
  status: 'ok';
  valid: boolean;
  /** The affiliate's first name, as the app's /r/<code> page shows it. */
  first_name: string | null;
  /** false while the affiliate's link is switched off: the registration still goes through, unreferred. */
  accepting: boolean;
}

export interface RegisteredPerson {
  position: number;
  /** null when already_registered under ANOTHER email (see already_registered). */
  person_id: string | null;
  /** null when already_registered under another email: send no VIP link and keep no token for this person. */
  upgrade_token: string | null;
  /** The person's days now (a repeat registration adds days, never removes them); null as person_id. */
  days: IsoDate[] | null;
  /**
   * This phone and name (same words) were already registered for the event: no second record was made. With the
   * email they registered with, their own details come back (and new days are added while they are on the list); with
   * any other email everything else is null: tell them they are already registered and to check the confirmation email
   * they had (anyone could type someone's phone and name).
   */
  already_registered: boolean;
  /** null as person_id. */
  vip: VipState | null;
}

export interface RegisterProblem {
  /** null for a problem with the registration as a whole. */
  position: number | null;
  field: 'first_name' | 'last_name' | 'phone' | 'email' | 'days' | 'people' | 'registration_id';
  code:
    | 'phone_not_accepted' // the app's phone policy cannot read it
    | 'day_closed' // that day has ended, or is not a day of the event
    | 'same_person_twice' // two people in one form with the same phone and name
    | 'id_reused'; // the registration id was used before with other people
  /** Plain English, safe to show the person. */
  message: string;
}

/**
 * register never says whether anyone was matched to, or made into, a customer, or whether the referral counted
 * (as the QR survey since 433, and /signup today). Staff see that on the Event page.
 */
export type RegisterAnswer =
  | (Answered & { status: 'registered'; registration_id: string; people: RegisteredPerson[] })
  | (Answered & { status: 'invalid'; problems: RegisterProblem[] })
  | (Answered & { status: 'closed'; reason: ClosedReason });

export interface PersonView {
  person_id: string;
  upgrade_token: string;
  first_name: string;
  days: IsoDate[];
  vip: VipState;
  can_upgrade: boolean;
  /** Why not, when can_upgrade is false. */
  reason: 'already_vip' | 'payment_waiting' | 'cancelled' | 'vip_off_sale' | 'closed' | null;
}

/** Another person on the same form, as the VIP page may show them: never their link or person id. */
export interface GroupMember {
  /** Their place on that form (1..10), to pair them with the token the website kept from its register answer. */
  position: number;
  first_name: string;
  days: IsoDate[];
  vip: VipState;
  can_upgrade: boolean;
}

export type PersonAnswer =
  | (Answered & {
      status: 'ok';
      person: PersonView;
      /** The others registered on the same form (first names only). To pay for them too, use the tokens the website
       *  kept from that form; a link opens its own person only. */
      group: GroupMember[];
      vip_price_cents: number;
      /** This person's own planning answers, null while none. Group members never carry answers. */
      planning: PlanningRecord | null;
      /** This person can save planning answers now: registered, and the event not ended or deleted. */
      planning_open: boolean;
    })
  | (Answered & { status: 'not_found' });

export type VipRefusal =
  | 'vip_off_sale' // the VIP ticket, or the event, is off sale
  | 'closed' // the event has ended, is deleted, or the website is off
  | 'already_vip'
  | 'payment_waiting' // another VIP payment for this person is open or waiting for a Manager
  | 'person_cancelled'
  | 'person_not_found' // a token the app does not know (or of another event)
  | 'livemode_mismatch' // a sandbox payment with the live key, or a live one with the test key
  | 'id_reused'; // the order id was used before with other people or another amount

export type VipCheckoutAnswer =
  | (Answered & {
      status: 'ok';
      order_id: string;
      unit_price_cents: number;
      total_cents: number;
      currency: 'SGD';
      /** Open HitPay with expires_after 60 mins; the app keeps the order pending until then (plus 10 min). */
      expires_at: IsoTime;
      people: { person_id: string; first_name: string }[];
    })
  | (Answered & { status: 'refused'; reason: VipRefusal; person_ids: string[] });

/**
 * What became of a VIP payment.
 *  invoiced      one invoice per person, each paid, vouchers issued to each person's own account
 *  recorded      kept; no invoice yet (a PayNow / bank transfer waiting for a Manager, or the website set to record only)
 *  needs_review  kept; waiting for staff, with the reason (amount differs, a person not matched yet, already VIP, …)
 *  refused       not kept as a sale (a sandbox payment with the live key, the website switched off …): see review_reason
 *  dismissed     a Manager set it aside (never paid, a test, a duplicate) or closed it as refunded outside the app
 *  test          TEST key: checked and recorded as a test only; test_note says what a live key would have done
 */
export type VipOrderStatus = 'invoiced' | 'recorded' | 'needs_review' | 'refused' | 'dismissed' | 'test';

export interface VipOrderAnswer extends Answered {
  status: VipOrderStatus;
  order_id: string;
  /** Safe to log and to show staff; never names, phones or emails. */
  review_reason: string | null;
  /** Set when status is 'refused' because of one of the checks vip_checkout also makes (else null). */
  reason: VipRefusal | null;
  test_note: string | null;
  people: { person_id: string; first_name: string; invoice_no: string | null; vip: VipState }[];
}

/**
 * vip_paid: money was taken, so a payment that fails a vip_checkout check (already VIP, off sale, …) is KEPT as
 * needs_review for a Manager, not refused; only a sandbox payment with the live key, or the website switched off,
 * is 'refused'. vip_transfer: a failed check is 'refused' with `reason` when nothing was paid yet is plausible
 * (person_not_found, id_reused, livemode_mismatch, closed); anything else is kept as needs_review.
 */
export type VipPaidAnswer = VipOrderAnswer;
export type VipTransferAnswer = VipOrderAnswer;

export type VipRefundAnswer =
  | (Answered & { status: 'noted'; order_id: string; refunded_cents_total: number })
  | (Answered & { status: 'not_found'; order_id: string });

export interface PlanningResult {
  /** null only for person_not_found. */
  person_id: string | null;
  status: 'saved' | 'test' | 'refused';
  reason: PlanningRefusal | null;
  /**
   * saved: what is kept now (answers equal to what was kept: nothing written, the same version). test: what would be
   * kept (nothing was: keep sending the version you had). refused: what is kept now, or null (changed_meanwhile: show
   * these, then let the person save again with their version).
   */
  planning: PlanningRecord | null;
}

export type PlanningAnswersAnswer =
  | (Answered & {
      status: 'ok';
      /** One per person, in the order sent. */
      people: PlanningResult[];
    })
  | (Answered & { status: 'closed'; reason: PlanningClosedReason });

export interface SyncPerson {
  /** Stable row key: the person_id of a website registration; GUEST-<first 8 hex of the guest id, upper case> for a
   *  free guest staff added on the Event page; TICKET-<same> for a ticket sold at the counter. (12 hex digits when an
   *  earlier row of the event has the same 8, as 382's FREE- keys.) */
  key: string;
  source: 'website' | 'staff' | 'counter';
  registration_id: string | null;
  position: number | null;
  group_size: number | null;
  registered_at: IsoTime;
  name: string;
  phone: string | null;
  email: string | null;
  days: IsoDate[];
  status: 'registered' | 'cancelled';
  cancelled_reason: string | null;
  vip: VipState;
  vip_invoice_no: string | null;
  vip_method: 'HitPay' | 'PayNow' | 'Bank Transfer' | null;
  vip_order_id: string | null;
  referral_code: string | null;
  /** The staff member who added a staff guest, or registered a counter sale. */
  registered_by: string | null;
  /**
   * A website person's planning answers (by person), null while none. Always null for a staff or counter guest and for
   * a test key: their answers stay in the app (the sheet does not list them). A staff edit on the Event page reaches
   * the sheet this way.
   */
  planning: PlanningRecord | null;
}

export interface SyncVipOrder {
  order_id: string;
  provider: 'hitpay' | 'paynow' | 'bank';
  status: VipOrderStatus | 'pending';
  amount_cents: number;
  paid_at: IsoTime | null;
  paid_on: IsoDate | null;
  reference: string | null;
  invoice_nos: string[];
  refunded_cents_total: number;
  person_ids: string[];
}

export type SyncAnswer =
  | (Answered & { status: 'too_soon' })
  | (Answered & {
      status: 'ok';
      event: { code: string; title: string; days: IsoDate[]; venue: string | null };
      people: SyncPerson[];
      vip_orders: SyncVipOrder[];
    });

export type AnswerFor<T extends MessageType> = T extends 'event_info'
  ? EventInfoAnswer
  : T extends 'referral_info'
    ? ReferralInfoAnswer
    : T extends 'register'
      ? RegisterAnswer
      : T extends 'person'
        ? PersonAnswer
        : T extends 'vip_checkout'
          ? VipCheckoutAnswer
          : T extends 'vip_paid'
            ? VipPaidAnswer
            : T extends 'vip_transfer'
              ? VipTransferAnswer
              : T extends 'vip_refund'
                ? VipRefundAnswer
                : T extends 'planning_answers'
                  ? PlanningAnswersAnswer
                  : SyncAnswer;

// ─────────────────────────────────────────────────────────────────────────────
// 5. Errors
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Not 200. The website retries ONLY the ones marked retry (after RETRY_DELAYS_MS); every other one is final for this
 * request: log the code (and field), never the body.
 */
export const ERRORS = {
  invalid_json: { http: 400, retry: false },
  /** A field is missing, has the wrong shape, or is not allowed; `field` names its path (never its value). */
  invalid_request: { http: 400, retry: false },
  /** The key is missing, malformed, unknown or revoked. One answer for all four. */
  bad_key: { http: 401, retry: false },
  /** HEADER_TIMESTAMP missing, malformed, older than 300 s or more than 60 s ahead. */
  bad_timestamp: { http: 401, retry: false },
  /** The key is not this event's (the body's `event` is another code). */
  wrong_event: { http: 403, retry: false },
  method_not_allowed: { http: 405, retry: false },
  /** The same request id came with a different body. A bug in the website: make a new request id per request. */
  request_conflict: { http: 409, retry: false },
  payload_too_large: { http: 413, retry: false },
  unsupported_media_type: { http: 415, retry: false },
  /**
   * Too many requests of one budget from this key in 10 minutes: sign-ups, checkouts and transfers 120; HitPay's
   * vip_paid and vip_refund notices 600; planning_answers 300. Each budget is its own, so sign-ups never block a
   * payment and answers never block either. `retry_after_seconds` (and the Retry-After header) says when: try again
   * then (a webhook answers HitPay with a 5xx so it delivers again; a form asks the person to try again in a few
   * minutes).
   */
  too_many_requests: { http: 429, retry: true },
  /** A passing fault (database busy, network): try again. */
  retry: { http: 503, retry: true },
  /** The function has no database settings. Try again later. */
  not_configured: { http: 503, retry: true },
} as const;

export type ErrorCode = keyof typeof ERRORS;

export interface ErrorAnswer {
  ok: false;
  error: ErrorCode;
  field?: string;
  retry_after_seconds?: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Rules both sides keep (the app enforces them; the website must not rely on anything else)
// ─────────────────────────────────────────────────────────────────────────────
//
// IDEMPOTENCY
//  * Same request id + same body (byte for byte) -> the first answer again, for 7 days. Same id, other body ->
//    409 request_conflict.
//  * Business keys are idempotent too: registration_id and order_id are unique per event. A new request id with the
//    same registration_id and the same people answers as the first did; with other people it is
//    { status: 'invalid', problems: [{ code: 'id_reused' }] }. The same for order_id ('refused', 'id_reused'); for
//    vip_transfer "the same" is the same people, method, amount, reference and day (submitted_at and the payer may
//    differ).
//  * vip_paid for an order already invoiced answers 'invoiced' with its invoice numbers. vip_refund carries a total.
//
// TEST MODE (a key made as "test" on the Website tab)
//  * Every answer has test: true. register answers exactly like a live one (person ids, tokens), but no customer is
//    matched or made, no guest is added, no referral is applied. vip_* answer status 'test' with a test_note; no
//    invoice, payment, voucher or commission is made. Staff see each test row, and what a live key would have done,
//    on the Website tab, and an Owner or Manager clears them there.
//  * A test key must be used with HitPay's sandbox (livemode false); a live key with HitPay production (livemode true).
//    The other way round is refused ('livemode_mismatch'); a live payment that reaches the test key is kept for a
//    Manager (needs_review), because money was taken.
//
// PRIVACY
//  * No answer ever says whether a phone or email belongs to a customer, or carries a capacity, a count of guests,
//    or anyone's details beyond what the website itself sent (sync excepted: it lists the event's people, as
//    web-ticket-order's sync does today, for the Google Sheet the team keeps).
//  * Logs on both sides: type, event code, request id, status/error, field path, durations. Never a name, phone,
//    email, upgrade token, key, planning answer or HitPay payload.
//
// TIMES
//  * The app judges every day in Asia/Singapore. A day can be chosen until its daily end; VIP is sold until the end
//    of the last day. "Tickets on sale" off (the whole event) closes both; the VIP ticket's "On sale" off closes VIP.
//
// PLANNING ANSWERS (21 Oct 2026)
//  * planning_answers replaces each person's answers (all eleven fields, every time). People are independent: one
//    refused never stops another, and `people` answers in the order sent. A body over MAX_BODY_BYTES is sent as
//    several calls of whole people (each its own request id, the same submitted_at).
//  * Same request id + same body -> the first answer again, as every write. version: send the PlanningRecord.version
//    the page was showing (0 when none). When other answers were kept since, the person is refused 'changed_meanwhile'
//    with what is kept (staff may have changed them by phone): show those, then save again with their version.
//    Answers equal to what is kept are 'saved' whatever the version, and nothing is written.
//  * The app keeps one form and answers with it: texts trimmed, a one-line text's inner whitespace made one space (the
//    question keeps its line breaks); a text that goes with a choice only with it; a part of the day from the daily
//    start to the daily end is the whole day; days by date; talks in the list's order, spelled as the list spells
//    them. Show what the answer returns.
//  * The app checks each person's timing days against their own days now, the times against planningTimeOptions for
//    the event's hours now, and the talks against the event's titles now (event_info.talk_titles, or
//    SUGGESTED_TALK_TITLES while that is null). A day's timing or a talk already kept for the person passes again as
//    it is, so a later change of the hours or the titles never blocks a save.
//  * Open while the person is registered and until the event has ended (event_info.planning_open, and the person
//    answer's planning_open); the website switched Off or the event off sale do not stop answers. 'closed' (the event
//    has ended or was deleted) answers the whole call.
//  * Answers go back only to whoever names the person's own token (planning_answers, person), and to the sync
//    (website people only).
//  * Test key: each person 'test' with what would be kept; nothing is kept or audited (keep sending the version you
//    had). Staff edits on the Event page are audited (who, when, the old answers); website saves as the website.

// ─────────────────────────────────────────────────────────────────────────────
// 7. Reference client (the Website tab shows this as the code to copy; the website's src/lib/event-api.ts wraps it)
// ─────────────────────────────────────────────────────────────────────────────

export interface EventApiConfig {
  /** https://<project>.supabase.co/functions/v1/event-website (ENERGIA_EVENT_API_URL) */
  url: string;
  /** evk_live_… or evk_test_… (ENERGIA_EVENT_API_KEY). Server side only, never sent to a browser. */
  key: string;
  /** e.g. HEALTH-SEMINAR-NOV26 (ENERGIA_EVENT_CODE) */
  event: string;
}

export class EventApiError extends Error {
  constructor(
    readonly code: ErrorCode | 'network' | 'timeout' | 'unexpected_answer',
    readonly httpStatus: number | null,
    readonly field: string | undefined,
    readonly retryable: boolean,
    /** too_many_requests: how long to wait before trying again. */
    readonly retryAfterSeconds?: number,
  ) {
    super(`event-website ${code}${field ? ` (${field})` : ''}${httpStatus ? ` HTTP ${httpStatus}` : ''}`);
    this.name = 'EventApiError';
  }
}

type BodyOf<T extends MessageType> = Omit<Extract<EventWebsiteRequest, { type: T }>, 'type' | 'event'>;

/**
 * One call to the app. For a WRITE message pass a requestId kept for that logical request (make it once, reuse it on
 * every retry, e.g. stored with the registration); for a READ message it may be omitted.
 */
export async function callEventApi<T extends MessageType>(
  config: EventApiConfig,
  type: T,
  body: BodyOf<T>,
  options: { requestId?: string; now?: () => number; timeoutMs?: number } = {},
): Promise<AnswerFor<T>> {
  const now = options.now ?? Date.now;
  if (isWriteType(type) && !(options.requestId && REQUEST_ID_RE.test(options.requestId))) {
    throw new Error(`${type} needs a lower-case UUID v4 request id`);
  }
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    [HEADER_KEY]: config.key,
    [HEADER_TIMESTAMP]: String(Math.floor(now() / 1000)),
  };
  if (options.requestId) headers[HEADER_REQUEST_ID] = options.requestId;

  let response: Response;
  try {
    response = await fetch(config.url, {
      method: 'POST',
      headers,
      body: JSON.stringify({ type, event: config.event, ...body }),
      signal: AbortSignal.timeout(options.timeoutMs ?? CLIENT_TIMEOUT_MS),
      cache: 'no-store',
    } as RequestInit);
  } catch (error) {
    const timedOut = error instanceof Error && (error.name === 'TimeoutError' || error.name === 'AbortError');
    throw new EventApiError(timedOut ? 'timeout' : 'network', null, undefined, true);
  }

  const answer: unknown = await response.json().catch(() => null);
  if (answer !== null && typeof answer === 'object' && (answer as { ok?: unknown }).ok === true && response.status === 200) {
    return answer as AnswerFor<T>;
  }
  const failed = (answer ?? {}) as Partial<ErrorAnswer>;
  const code = typeof failed.error === 'string' && failed.error in ERRORS ? (failed.error as ErrorCode) : null;
  if (!code) throw new EventApiError('unexpected_answer', response.status, undefined, response.status >= 500);
  const wait = typeof failed.retry_after_seconds === 'number' ? failed.retry_after_seconds : undefined;
  throw new EventApiError(code, response.status, failed.field, ERRORS[code].retry, wait);
}

/**
 * Retries a call on a passing fault only (503, network, timeout), after RETRY_DELAYS_MS. A 429 is retryable too, but
 * only later: when its retry_after_seconds is longer than the next delay it is thrown at once (still retryable), for
 * the caller to try again after that wait (a webhook answers 5xx; the sync tries again on its next run).
 */
export async function withEventApiRetries<R>(call: () => Promise<R>, delaysMs: readonly number[] = RETRY_DELAYS_MS): Promise<R> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await call();
    } catch (error) {
      const retryable = error instanceof EventApiError && error.retryable;
      if (!retryable || attempt >= delaysMs.length) throw error;
      if (error instanceof EventApiError && (error.retryAfterSeconds ?? 0) * 1000 > (delaysMs[attempt] ?? 0)) throw error;
      await new Promise((resolve) => setTimeout(resolve, delaysMs[attempt]));
    }
  }
}

/** A lower-case UUID v4 for HEADER_REQUEST_ID. */
export const newRequestId = (): string => crypto.randomUUID();

/** REG-/VIP- ids: the Singapore date, then 8 upper-case hex digits. */
export function newBusinessId(prefix: 'REG' | 'VIP', at: Date = new Date()): string {
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(at)
    .replaceAll('-', '');
  const hex = Array.from(crypto.getRandomValues(new Uint8Array(4)), (b) => b.toString(16).padStart(2, '0')).join('');
  return `${prefix}-${day}-${hex.toUpperCase()}`;
}
