# Calendar readiness

**Scope.** Preparation only. No calendar screen, no Google OAuth, no API
credentials, no external events and no synchronisation job were added, and none
should be added on the strength of this document alone: the decisions in the
last section come first.

The appointment scope this assesses is the one that was set: **customer, store,
therapy service, assigned staff, appointment duration, and the voucher or
therapy entitlement used**. Rooms and equipment are out of scope and are
recorded here only as a possible later extension.

## The short answer

The database was built in anticipation of this. Duration, per-store service
availability, structured frequency rules, a unified entitlement view and a
permission-aware booking probe already exist, and the migrations that introduced
them say why. Migration 245 puts it plainly:

> There is no calendar and no appointment table. These exist so that when one is
> built the permission question is already settled in the database rather than
> re-decided in a page.

What is missing is precisely the thing an appointment feature would create: **a
record that a session was actually taken, at a time**. Nothing in the system
stores when a therapy session began, and the two columns meant to count
consumption have never been incremented by anything.

So the work ahead is mostly business decisions, not schema archaeology.

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

**What is missing is a start time.** No table stores one.
`customer_therapy_sessions` records only `purchased_at`. `duration_months` on an
entitlement is the length of an unlimited period, not the length of a session.

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

6. **Calendar mapping and sync direction.** One calendar per store, per staff
   member, or one shared calendar. Per-staff matches how people read their day;
   per-store matches the existing permission model; multi-store staff make this a
   real choice. Push-only, pull-only or two-way, and polling versus Google push
   channels, which expire and must be renewed. Also what goes in the event body:
   a customer's name in the title is convenient and is personal data sitting in a
   third-party calendar other staff can see. A reference number is an option.

7. **Retry and conflict handling.** Reuse the request id and hash so a redelivered
   webhook is a no-op, and put a unique index on the Google event id. Decide the
   conflict rule — last writer wins, this system wins, or queue for human review,
   for which the therapy date-change request flow is the precedent. Decide whether
   a deleted Google event cancels the appointment or is drift to be re-pushed.

8. **Timezone.** The business timezone is Asia/Singapore and it is already
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
| Several customers may share one phone number, by policy | High | Any booking flow that identifies by phone will attach sessions to the wrong person. Sweep `customer_phone_collisions()` and a stricter duplicate check. |
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
