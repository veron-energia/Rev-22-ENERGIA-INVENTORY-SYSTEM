# Calendar readiness

**Scope.** Preparation only. Nothing was built: no calendar screen, no Google
OAuth, no API credentials, no external events and no synchronisation job were
added, and none should be added on the strength of this document alone — the
decisions near the end come first. This assesses readiness for a **therapy
booking** feature. A separate Google Calendar integration already runs in
production for the ads lead pipeline; the next section explains what it is and
why it does not do this job.

The appointment scope this assesses is the one that was set: **customer, store,
therapy service, assigned staff, appointment duration, and the voucher or
therapy entitlement used**. Rooms and equipment are out of scope and are
recorded here only as a possible later extension.

## Correction, 2026-09-20

**An earlier draft of this document said there is no calendar and no appointment
table. That is true of this repository and false of your production database.**

Production carries an `ads` lead pipeline that this repository does not contain:
12 tables and 34 functions, applied over 19 migrations on 19 and 20 September.
It includes a **live Google Calendar integration** and a table called
`ads_appointments` holding 29 rows. Everything below was written against the
repository and the local databases, where none of that exists. The section that
follows describes what is actually there and what it does and does not change.

## What already exists in production

`ads_appointments` is a **one-way mirror of Google Calendar**, not a booking
system. Its 22 columns are calendar bookkeeping and lead matching:

| Purpose | Columns |
| --- | --- |
| Which Google event this is | `calendar_id`, `event_id`, `recurring_event_id`, `colour_id`, `summary`, `version`, `first_seen_at`, `last_seen_at` |
| Who it might be | `lead_id`, `customer_id`, `matched_phone_e164`, `match_method` |
| When | `starts_at`, `ends_at`, `appt_date_sgt` |
| What happened | `status`, `cancel_signal`, `attended`, `attendance_source`, `is_repeat_booking` |

Events arrive through `ads_ingest_calendar_event(ev jsonb, …)`, which takes a
raw Google event, and reach it from Pabbly Connect calling `ads_rpc_calendar_event`
with a service-role key. Google is the source of truth; the database follows.

**It does not meet the appointment scope in this document, at all.** Across all
twelve `ads` tables there are **zero** columns for a store, a staff member, a
therapy service, an entitlement or a voucher. It cannot say who would deliver a
session, where, or what it would consume.

Two things about its current state are worth knowing before building on it:

- All 29 appointments were matched by `phone_in_event_text` — scraping a phone
  number out of the event's own text — and **none of them has matched a customer
  record**. `customer_id` is null on all 29.
- **No attendance has been recorded on any of them.** `attended` is null
  throughout.

So the integration exists and runs, but the link from a calendar event to a
person in your database is not yet working, and this is exactly the hazard this
document warns about below: up to three customers may legitimately share one
phone number, so a phone scraped from an event title cannot identify a customer
on its own.

## The short answer

For the **therapy booking** feature this document was asked to assess, the
database was built in anticipation. Duration, per-store service availability,
structured frequency rules, a unified entitlement view and a permission-aware
booking probe already exist, and migration 245 says why they were built early:
so that when a calendar is built, the permission question is already settled in
the database rather than re-decided in a page.

What is missing is precisely the thing a therapy appointment feature would
create: **a record that a session was actually taken, at a time, against a named
entitlement**. `ads_appointments` does not do that — it records that a calendar
event existed. The two columns meant to count consumption have still never been
incremented by anything.

So the work ahead is still mostly business decisions. But one of those decisions
is now larger than it looks: whether therapy booking extends the calendar
integration that already exists, or sits beside it.

## 1. Identifiers and relationships

Every one of the six things an appointment must point at is a UUID primary key
with real foreign keys behind it.

| Concept | Table | Key |
| --- | --- | --- |
| Customer | `customers` | `id`, soft-deleted with `deleted_at` |
| Store | `stores` | `id`, `code` unique |
| Therapy service | `therapy_services` | `id` |
| Staff | `profiles` | `id`, shared with `auth.users` |
| Service offered at a store | `therapy_service_stores` | `(service_id, store_id)` |
| Staff assigned to a store | `user_store_assignments` | unique `(user_id, store_id)` |

Entitlements come from three deliberately separate sources: unlimited periods in
`purchased_therapy_entitlements`, counted sessions in
`customer_therapy_sessions`, and voucher units in `customer_reward_vouchers`
with `therapy_voucher_issues`. They are not interchangeable and migration 245
says so. An appointment should carry exactly one of the three pointers rather
than a fourth idea of a balance.

Two things about identity matter more than they look.

**A phone number is not an identity here, by policy.** `customers.phone` is
required but not unique, and the built-in duplicate detector only reports a
number once **four or more** customers share it, because families share numbers
on purpose. A booking flow that finds a customer by phone will eventually book
the wrong member of a household. It must resolve to `customers.id`.

**Merging customers rewrites ids safely, and generically.**
`merge_customer_records` repoints foreign keys by walking `pg_constraint` at
runtime, so a future `appointments.customer_id` foreign key is repointed with no
code change. It locks both rows in id order and replays by `request_id`. One
caveat: the replay check runs before the lock, which leaves a narrow race.

**A gap worth knowing now.** `invoice_service_staff` records which staff served
an invoice, but only per invoice, not per line, and its write paths do not check
that the staff member works at that invoice's store. Two sibling paths do check
it, which makes the omission look accidental rather than intended. If
appointments reuse that table for attribution, they inherit the gap.

## 2. Duration and eligible services

`therapy_services.duration_minutes` exists, is bounded to 1–1440, and is
protected by a constraint that is the load-bearing fact for booking:

```
therapy_service_active_is_complete
  CHECK (NOT is_active OR (duration_minutes IS NOT NULL AND frequency_kind IS NOT NULL))
```

Verified installed. **An active, bookable service cannot exist without a
duration.** Only inactive drafts may leave it null, so the nullable column is
not a readiness problem.

Duration is also snapshotted at the point of sale
(`invoice_items.therapy_service_minutes_snapshot`,
`customer_therapy_sessions.service_minutes_snapshot`) and re-snapshotted on
correction, so history stays truthful when a service is later reconfigured. An
appointment should follow the same convention: read the live duration while it
is still in the future, snapshot it when the session is completed.

Eligible services are fully modelled per store, per voucher and per package, and
the voucher definition is frozen into `therapy_voucher_issues.definition_snapshot`
at issue, so a later change to the catalogue cannot rewrite what a customer was
given.

**What is missing is a start time for a THERAPY session.** No table in the
therapy model stores one: `customer_therapy_sessions` records only
`purchased_at`, and `duration_months` on an entitlement is the length of an
unlimited period, not the length of a session. `ads_appointments.starts_at`
exists, but it is the start of a Google Calendar event in the lead pipeline,
carries no service, staff member, store or entitlement, and is matched to a
customer by scraping a phone number from the event text — currently matching
none. It is not a therapy session record and should not be read as one.

## 3. Staff and store access

One function carries this across the whole application:
`user_has_store_access(store_id)` returns true for an owner, admin or active
manager, or for an active user assigned to that store. It already gates the two
functions that were written for a calendar — `therapy_calendar_services` and
`therapy_booking_options` — and the latter **raises rather than returning an
empty list**, because an empty list reads as "nothing available", which is a
different and more misleading answer.

Three gaps stand between that and assigning appointments:

1. `user_has_store_access` answers only for the caller. Nothing asks "does staff
   member X work at store Y", which is the question booking someone else needs.
   The predicate is a one-line `exists` on `user_store_assignments`; the pattern
   already exists in the invoice-attribution correction.
2. `invoice_service_staff` writes do not check the store, as above.
3. `can_change_therapy_dates` uses the singular "my assigned store", the exact
   narrowing that migration 96 fixed elsewhere for multi-store staff. Appointment
   rescheduling would inherit it if it copies that function.

## 4. Frequency rules

These are already structured and evaluable, not free text.
`therapy_services.frequency_kind` is one of `per_day`, `per_week`, `per_month`,
`per_hours` or `unrestricted`, with `frequency_max_per_period` and, for
`per_hours`, a required `frequency_interval_hours`.

`therapy_service_frequency_ok(service_id, at, history)` returns whether a session
is allowed, why not, how many fall in the period and when the next one may be.
Periods resolve in Singapore time with Monday-based weeks. It fails closed on an
unusable rule. A JavaScript mirror exists with a parity test against the SQL.

The signature is the point: **history is a parameter, with an empty default.**
Migration 240 explains that there is no authoritative session table yet, so a
function that went looking for one would be answering from nothing, and that when
that table exists its caller passes it here and the function needs no change.
The gate is wired and waiting for data.

Two things to note. There is no concept of a gap in **days** — only
`per_hours` with an interval. And the voucher-level repeat rule
(`therapy_voucher_definitions.repeat_kind` and friends) is stored, displayed and
snapshotted, but nothing evaluates it, even though the migration that introduced
it says both rules must allow a session and the stricter one decides. Voucher
frequency limits are currently unenforced.

## 5. Entitlement validity, activation and closures

Mature and unusually well decomposed. An entitlement runs from
`activation_date` to `expiry_date` inclusive, with the lifecycle
`pending_activation → scheduled → active → expired/cancelled/refunded` and an
`activation_deadline` bounding the claim window.

Expiry is not a single opaque date. `therapy_adjusted_expiry` walks the
applicable business closures, adds a day for each, skips Sundays so a Sunday
closure takes no working day away, and re-runs because added days can reveal new
closures. The result is stored decomposed — `base_expiry_date`,
`closure_days_added`, `expiry_calculated_at`, `holiday_country` — and every
movement is recorded in `therapy_expiry_adjustments`, a queryable table rather
than an audit blob.

The holiday country is snapshotted at activation rather than joined live, on the
stated reasoning that a customer correcting their phone number later must not
silently move an expiry they were already given. That reasoning applies directly
to appointments and is reinforced in the timezone decision below.

There is also an existing change-control precedent for moving dates:
`therapy_date_change_requests` with request, approve and reject functions. An
appointment reschedule that changes an entitlement date should go through that
shape rather than inventing a second one.

## 6. Redemption and provenance

This splits three ways, and conflating them is the main risk in the whole
feature.

**Issuance provenance is strong.** A voucher sold on an invoice line carries
`source_type = 'invoice_voucher_sale'` and `source_id` equal to that
`invoice_items.id`. Paid and granted value is recorded per line in
`invoice_benefit_values`, with partial unique indexes giving one benefit row per
voucher and per credit lot. Customer reassignment preserves the origin.

**`voucher_redemptions` is not session redemption.** It records a discount
voucher applied to an invoice. It has no `invoice_item_id`, no link to the issued
voucher row, a nullable `invoice_id`, and no unique constraint — the original
migration says outright that it has no reuse check. It is discount accounting.
It must not be adopted as the session ledger.

**There is no consumption record at all, on purpose.** Both counters exist and
nothing increments them, which I verified by searching every migration:
`customer_therapy_sessions.quantity_used` and
`therapy_voucher_issues.sessions_used`. The comments say the columns are there so
that the balance is already shaped for a redemption action that does not yet
exist.

So the appointment feature is not reusing a redemption record. It is the thing
that finally writes one, into shapes already built to receive it, with
`quantity_used <= quantity_purchased` and `sessions_used <= sessions_total`
checks that only become real overdraw protection once something increments them.

## 7. Audit and concurrency

`write_audit` and `write_audit_ex` write to `audit_logs` with the actor's id and
role, and optionally a module, reason and store. Reading is manager-and-above and
there is no insert policy, so writes go only through the definer helpers. Two
caveats: most call sites pass null for the previous state, so full before-and-
after snapshots exist mainly in the newer invoice-correction paths; and
`audit_logs` has no policy preventing update or delete.

Locking on entitlements is good. Every therapy claim path takes the entitlement
row `for update` first, with comments explaining that two tabs or a retried
request must not both claim the last one. Voucher stock, credit lots and invoices
are locked before mutation.

Idempotency has an established house pattern that transfers directly to booking
and to replayed Google webhooks: a `request_id` plus a `request_hash`, backed by
partial unique indexes, returning "already done" when the hash matches and
**raising** when the same request id arrives with different details. Optimistic
concurrency via an expected version or edit count is also in use.

Three gaps are worth listing because a booking flow would sit next to them:
promotion voucher issuance checks then inserts with no lock and no unique index
behind it; therapy session creation does the same and is saved only by a unique
index added later; and the credit consumption function pre-checks availability
without a lock and returns success unconditionally.

## How an appointment would reuse this

The rule to hold onto: **an appointment is a scheduling fact plus a pointer. It
is never a second copy of a balance.**

This sketch describes the shape a therapy appointment needs. Whether that shape
becomes new columns on `ads_appointments` or a separate table is decision 6
below, and it is not this document's to make.

An appointment row would carry the customer, store, service, staff and start
time, the duration, exactly one benefit pointer — a purchased entitlement, a
counted session row, or a reward voucher — a status, the Google event and
calendar ids, and a request id and hash.

It would **not** carry a remaining count, a copied expiry date, a copied price,
or a second redemption row. Balances stay computed by the existing entitlement
functions; validity stays computed from `base_expiry_date` and
`closure_days_added`.

Consumption becomes an increment of the two existing counters inside a
transaction that takes the entitlement row `for update` first, following the
pattern the deferred voucher claims already use. `voucher_redemptions` is left
alone.

Frequency needs no new logic: the appointment table finally supplies the history
argument the existing function already accepts. Permission needs almost none:
`therapy_booking_options` already refuses on store access and already returns the
duration, the price, the frequency verdict and the usable entitlements. The one
genuinely new predicate is "does this staff member work at this store".

Audit and idempotency reuse the house patterns rather than inventing new ones.

## Decisions required before implementation

These are business decisions. None of them were made here, and none should be
inferred from the schema.

1. **Does booking consume the benefit, or does attendance?** Consuming at booking
   keeps the balance simple but burns a session on a no-show. Consuming only at
   completion is accurate but lets a customer hold ten bookings against one
   remaining session. A reserved-then-consumed pair is the most accurate and
   requires widening existing status checks, which today allow only
   `held/redeemed/revoked` and `available/used/cancelled/refunded`.

2. **Must overlapping staff appointments be impossible?** A database exclusion
   constraint on staff and time range would refuse them outright, using a
   technique already present in this schema. An application warning allows
   deliberate overlap. An explicit confirm flag is a middle path the codebase
   already uses elsewhere.

3. **When is a benefit reserved, and when consumed?** At booking, at check-in, at
   completion, or on a manual confirmation. This interacts with the first
   decision and with frequency: a reserved future appointment either does or does
   not count toward the period limit.

4. **Cancellation and no-show.** Always restore, never restore, or restore when
   cancelled more than a set notice period ahead. Separately: does a no-show
   consume the session, and may goodwill extend an expiry? The extension
   machinery could record that, but only if the business wants it to.

5. **Which system owns an appointment change?** This application authoritative
   with the calendar as a mirror keeps entitlement rules enforced. Calendar
   authoritative is natural for staff but lets a dragged event move a session past
   an entitlement's expiry with nothing to stop it. Field-level ownership is the
   most usable and the most complex.

   **This is already answered one way in production, and the two answers
   conflict.** `ads_appointments` is Calendar-authoritative: Google holds the
   truth and the database mirrors it. If therapy booking is
   application-authoritative, your staff will be working two calendars with
   opposite rules on the same screen. Deciding this is now a choice between
   changing the ads direction, accepting two directions, or having therapy
   booking follow Google's lead and losing the entitlement guard.

6. **Extend `ads_appointments`, or add a second table?** A new decision, created
   by what already exists. Extending it means one row type for every kind of
   appointment and one sync path, at the cost of a table that is currently a
   faithful Google mirror growing business columns Google knows nothing about,
   and of a `customer_id` that is presently null on every row. A separate
   therapy table keeps the mirror clean and the booking rules strict, at the cost
   of two tables that both mean "an appointment" and a staff view that has to
   merge them. Whoever owns the ads pipeline should make this call, not this
   document.

7. **Calendar mapping and sync direction.** One calendar per store, per staff
   member, or one shared calendar. Per-staff matches how people read their day;
   per-store matches the existing permission model; multi-store staff make this a
   real choice. Push-only, pull-only or two-way, and polling versus Google push
   channels, which expire and must be renewed. Also what goes in the event body:
   a customer's name in the title is convenient and is personal data sitting in a
   third-party calendar other staff can see. A reference number is an option.

   Note the ads pipeline has already chosen: it reads a phone number out of the
   event text to identify a person. That is the mapping decision made implicitly,
   and it is currently matching nobody.

8. **Retry and conflict handling.** Reuse the request id and hash so a redelivered
   webhook is a no-op, and put a unique index on the Google event id. Decide the
   conflict rule — last writer wins, this system wins, or queue for human review,
   for which the therapy date-change request flow is the precedent. Decide whether
   a deleted Google event cancels the appointment or is drift to be re-pushed.

   **There is now a working precedent to copy rather than invent.**
   `ads_appointments` already handles redelivery with `event_id` plus a `version`
   and `last_seen_at`, and has an explicit `ads_mark_event_deleted` path and a
   `cancel_signal` column. Whatever therapy booking does should match it.

9. **Timezone.** The business timezone is Asia/Singapore and it is already
   hardcoded throughout: "today" is Singapore's today, and frequency periods
   resolve in Singapore time with Monday-based weeks. There is no timezone column
   on `stores`. Store the start time as `timestamptz` and render in Singapore
   time.

   **An appointment's timezone must not be inferred from the customer's phone
   country code.** This needs saying because the codebase contains exactly that
   pattern for a different purpose: an entitlement's holiday country may be
   derived from a phone number, recorded as `holiday_country_source = 'phone'`.
   That drives public-holiday closure extensions for a customer who observes
   another country's holidays. It is not a location and not a timezone. A
   Malaysian mobile number attending a Singapore store is a Singapore
   appointment.

   The ads pipeline agrees with this already: `ads_appointments.appt_date_sgt`
   stores the Singapore calendar date alongside the `timestamptz`, which is the
   convention to follow.

## Current defects that would affect appointments

Severity below is assessed from schema and logic. The disposable integration
database is a near-empty fixture — one customer, one invoice, no therapy
services — so it cannot tell you how many production rows are affected. Each row
gives the query to run against production when you choose to look. **No
production data was read or repaired during this task.**

| Defect | Severity | Why it matters for appointments |
| --- | --- | --- |
| No session-attendance record exists anywhere | Blocking | Frequency rules and both usage counters have no data source. This is the feature's core deliverable, not a bug to fix first. |
| Vouchers held with no recorded therapy rights | Blocking for those customers | They report as unrecorded, are excluded from every total, and cannot be booked against. Count with `therapy_vouchers_without_rights()`. |
| Voucher lines sold before migration 254 issued nothing, and were deliberately not backfilled | High | Those customers hold paid-for vouchers the system cannot see. Count with `invoice_untracked_voucher_lines()`. |
| Several customers may share one phone number, by policy | High | Any booking flow that identifies by phone will attach sessions to the wrong person. Sweep `customer_phone_collisions()` and a stricter duplicate check. **This is no longer hypothetical:** the live calendar integration identifies people by scraping a phone from the event text (`match_method = 'phone_in_event_text'`), and across 29 ingested appointments it has matched a customer record zero times. |
| The live calendar mirror records no attendance | Medium, and blocking if relied on | `ads_appointments.attended` is null on all 29 rows. Whatever else is true, attendance is not being captured today, so it cannot yet be a source for the frequency history that `therapy_service_frequency_ok` expects. |
| `invoice_service_staff` does not verify the staff member works at the invoice's store | Medium | Cross-store attribution is possible if appointments reuse it. |
| Active entitlements with no holiday country get no closure extension | Medium | An appointment booked near expiry could be invalidated by a later recalculation. |
| The voucher repeat rule is stored but never evaluated | Medium | Voucher-level frequency limits are currently unenforced, contrary to the documented intent. |
| `voucher_redemptions` has no line link, no unique constraint and no reuse check | Medium, High if reused | Safe as discount accounting. Dangerous if mistaken for a session ledger. |
| Issuance dedupe is check-then-insert with no unique index behind it | Medium | A replayed trigger can double-issue. |
| `can_change_therapy_dates` uses a single assigned store | Low to Medium | Multi-store staff would hit the same narrowing when rescheduling. |

None of these were repaired during this task, which was the instruction. The
first four are the ones to resolve before booking goes live; the rest can be
addressed alongside the feature.

## What this assessment rests on

**Originally written against this repository and two local databases, then
corrected against production on 2026-09-20.** That correction matters: the
repository does not contain the `ads` lead pipeline, so the first draft's
central claim — that no calendar and no appointment table exist — was true of
everything I could see and false of the system you actually run. The production
facts in the correction and in the defects table were read directly from the
live database, read-only.

Read-only inspection of the migrations in `supabase/`, of `src/`, and of the
effective definitions installed in the local Docker database and the disposable
integration database. Function bodies and constraints were read from the
catalogue rather than from the migration files where the two could differ,
because later migrations rewrite earlier functions.

The claims this document leans on hardest were re-checked directly: the
active-service completeness constraint, the absence of any appointment, booking
or calendar table other than the public-holiday coverage table, the fact that
nothing anywhere increments either usage counter, and the frequency function's
history parameter.

This is an assessment of readiness, not a guarantee. It does not claim the
system is free of defects, and the production row counts behind the table above
have not been taken.
