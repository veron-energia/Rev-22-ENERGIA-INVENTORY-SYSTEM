# Therapy: closure extensions, holiday calendars and reward choices

Migrations 220–224, `src/lib/therapy/`, `src/components/therapy/`.
Nothing here is committed, deployed, or applied to production data.

---

## 1. Why the claim dialog only ever offered unlimited therapy

Reproduced against the real function before anything was changed.

`legacy_reward_options()` finds a unit's alternatives by matching today's rules
on the amount stored on the entitlement:

```sql
and r.qualifying_amount = e.qualifying_amount
```

An entitlement earned under the old **S$794** threshold matches nothing once the
rules move to **S$994**, so the function returns zero rows. The dialog then falls
back to the kind stored on the entitlement — `unlimited` — and shows one option.

The reproduction, on a database with today's rules configured:

| Entitlement | Options returned |
|---|---|
| S$994 customer | `unlimited: 1 Month Unlimited` · `voucher: 10 Therapy Vouchers` |
| **S$794 customer (historical)** | **none** |
| S$994 affiliate | `voucher: 10 Therapy Vouchers` only |

Three distinct causes, not one:

1. **The amount is the join key.** It is unstable across a threshold change, so
   history silently detaches from its own rules.
2. **The frontend discarded the error.** `const { data: opts } = await
   supabase.rpc(...)` — a failed request and an empty list were indistinguishable,
   and both fell through to unlimited.
3. **Affiliates were barred from unlimited in code**, by
   `and (e.earner_kind <> 'affiliate' or r.entitlement_kind = 'voucher')` and a
   matching `raise` in the claim, regardless of what was configured.

### What changed

* Alternatives are grouped by an explicit `tier_key` on `therapy_package_rules`.
  Existing rules are backfilled to `applies_to:amount:store` — **exactly the
  grouping the old code implied**, so nothing that resolved before resolves
  differently now.
* `legacy_reward_options_diagnostic()` explains an empty or single-option list and
  names the rule an administrator has to create. The dialog shows it and
  **disables claiming when the options fail to load**, so a unit cannot be spent
  on the wrong reward because a request timed out.
* The affiliate restriction is gone from the code. Whether an affiliate may
  choose unlimited therapy is now a property of the configured rules. With only a
  voucher rule present, the diagnostic says:

  > To let affiliates choose unlimited therapy, add an affiliate rule of kind
  > 'unlimited' with the same tier key as the affiliate voucher rule.

* One unit still yields exactly one reward. `claim_legacy_therapy` takes the row
  `for update`, refuses any status other than `pending_activation`, and validates
  the chosen rule against `legacy_reward_options` — the same function the dialog
  reads, so the two cannot disagree. A double-click, a retry and two concurrent
  requests all end with one claim.

---

## 2. The closure extension

### The convention, confirmed

Expiry is **inclusive** — the last day the benefit can be used. That is what
`therapy_expiry()` has always meant (`start + months - 1 day`), and it is
preserved rather than reinterpreted. Activation, remaining duration, status and
display all use it.

### There are two conventions, and both are still live

| Start | Months | `therapy_expiry` (Legacy) | `membership_expiry` (purchased) |
|---|---|---|---|
| 2024-02-29 | 12 | 2025-02-27 | **2025-02-28** |
| everything else | — | identical | identical |

A 29 February start has no anniversary in a non-leap year. `membership_expiry`
treats the clamped 28 February as the full period and does not subtract a day.
Customers hold live entitlements computed both ways, so **neither was replaced**:
the convention travels with the entitlement (`therapy_base_expiry(start, months,
'legacy'|'purchased')`) and the extension is applied on top of whichever base it
was granted under. Flattening these would have moved somebody's expiry by a day.

### The rules

| Case | Days added |
|---|---|
| Ordinary Sunday | 0 — the business is closed anyway |
| Public holiday or closure, Mon–Sat | 1 |
| Holiday **and** closure on one date | 1 |
| The same date recorded twice | 1 |
| Holiday falling on a Sunday | 0 |
| Its observed Monday substitute | 1 |
| A closure uncovered by the extension | extends again, until stable |

Expiry is **not** nudged off a Sunday. Sundays are part of the calendar month
that was sold, not days owed back.

Everything is computed **from the base**, never from the current expiry, so
recalculation is idempotent — running it twice cannot add the same days again.

Dates are Singapore business dates (`sg_today()`), matched date-only. No
timestamps are involved, so no timezone can shift a holiday by a day.

The rule exists twice — `src/lib/therapy/expiry.mjs` for the page, migration 220
for every server path — and the database suite asserts they agree on every case,
including both conventions.

### Country assignment

The suggestion comes from the customer's phone via the existing parser
(`src/lib/customer-phones/normalize.mjs`). It is **not** reimplemented in SQL: a
second dialling-code table would drift, and a phone number is a suggestion, not
proof of residence or attendance.

* The assignment is **frozen onto the entitlement** at activation. A later phone
  change cannot move an expiry that was already granted — there is a test for it.
* No country means **no calendar applies** and the expiry is reported unverified.
  It is never treated as a country with no holidays.
* A country-specific closure applies only to entitlements assigned to that
  country. "All countries" is a separate, explicit choice.
* Countries flagged `requires_region` (MY, IN, AU, GB) are **not** verified until
  a region is chosen. A regional calendar is never guessed from a phone number.
* Correcting an active entitlement needs a reason, shows a before/after preview,
  and writes a row to `therapy_expiry_adjustments`.

### Coverage

`therapy_calendar_coverage` records which country-years somebody has actually
checked against a source. An unfilled year is **not** a year without holidays,
and the UI says so on the entitlement, in the preview, and in the calendar
screen. Migration 224 seeds Singapore 2026–2027 from mom.gov.sg — with the source
on every row — and deliberately **does not** mark coverage verified: a person
confirms that after checking. All 26 gazetted weekdays were recomputed from the
dates before the file was written; all agreed.

The four Sunday holidays and their Monday substitutes are both recorded, so the
explanation can show why the Sunday added nothing and the Monday added a day.

A real twelve-month package starting 8 Sep 2026 gains **11 days**: 11 eligible
gazetted dates, 2 Sundays skipped.

---

## 3. Historical data — previews, not repairs

| Screen | Function | What it will not do |
|---|---|---|
| Expiry recalculation | `therapy_recalculation_preview()` | Touch expired, cancelled or refunded entitlements; shorten a granted expiry; guess a country |
| Reward tier mapping | `therapy_reward_mapping_preview()` | Attach any tier automatically; alter a qualifying amount; touch a claimed unit |
| Calendar impact | `therapy_closure_impact(date)` | Shorten anyone when a date is removed |
| Successor reconciliation | `therapy_successor_reconciliation()` | Move a start date a member of staff chose |

**Shortening.** `therapy_apply_recalculation` lengthens freely and refuses to
shorten. Removing a calendar entry reports `skipped_would_shorten` and leaves the
granted expiry standing; an Owner or Manager must pass `p_allow_shortening` with
a reason, which is stored with both dates.

**Mapping.** A S$794 entitlement is offered candidate tiers ranked by how close
each is to what it already carries, with `threshold_differs` shown plainly.
Mapping requires a reason. The qualifying amount is never rewritten — verified by
a test that reads it back as `794.00` afterwards.

---

## 4. Customer voucher balances

There is already one authoritative record — `customer_reward_vouchers`, with
`source_type`/`source_id`. Nothing here creates a second balance.

* **Remaining** is `status = 'held'`. Redeemed and revoked are shown, not counted.
* `voucher_redemptions` is **history and is never added up** — a redemption
  already shows as a redeemed issuance, so counting both would double count
  every use. Tested.
* An entitlement is shown as the **source** of its vouchers, never as a separate
  grant beside them.
* Therapy vouchers (`voucher_kind = 'normal'`, unit *session*) and money-off
  vouchers (unit *money*) are counted in separate columns. A session and a dollar
  are not addable.
* Totals are computed in SQL over the whole set and only then paged. A page limit
  changes which customers are listed, never what any of them holds — and the row
  reports `total_customers` so the UI can say "showing 50 of 812".
* Two customers sharing one phone number stay separate. Tested.

Reconciliation on the fixture: 16 issued − 3 redeemed − 1 revoked = **12
remaining**, and the per-grant lines sum to the same figures.

---

## 5. Multiple unlimited packages

`therapy_next_available_start()` suggests the day after the latest **adjusted**
expiry, so a closure that lengthened the first package pushes the suggestion too.

`activate_purchased_therapy` returns `requires_confirmation` rather than creating
an overlap by accident; an overlap is allowed when asked for and recorded as
deliberate. Already-active periods are never altered because another package is
added. Successors that are no longer consecutive are listed for review, never
moved automatically.

---

## 6. Deployment order

1. `supabase/220_therapy_holiday_calendars.sql`
2. `supabase/221_therapy_reward_choices.sql`
3. `supabase/222_therapy_customer_summaries.sql`
4. `supabase/223_therapy_activation_and_sequencing.sql`
5. `supabase/224_therapy_singapore_calendar_seed.sql`
6. **Read the previews before touching anything:**
   ```sql
   select * from public.therapy_recalculation_preview(null, null);
   select * from public.therapy_reward_mapping_preview();
   ```
7. Deploy the frontend.
8. In the Therapy page, confirm the Singapore calendar for each year against the
   gazette. Until then those expiries show as unverified — correctly.

Order matters: the page calls functions these migrations create, so a
frontend-first deploy shows errors where the figures belong.

These migrations **drop and recreate** four existing functions —
`legacy_reward_options`, `claim_legacy_therapy` (its 4-argument form),
`activate_purchased_therapy` (its 3-argument form) and
`therapy_customer_voucher_balances`. Each changes its output columns or its
argument list, and PostgreSQL will not change either in place. Grants are
reissued in the same files.

### Rollback

```sql
-- 224: the seeded calendar (this alone changes no expiry)
delete from public.therapy_closure_dates where source = 'mom.gov.sg';

-- 223: restore migration 53's activation
drop function if exists public.activate_purchased_therapy(uuid,date,text,text,text,boolean);
drop function if exists public.therapy_next_available_start(uuid,date);
drop function if exists public.therapy_successor_reconciliation();
-- then re-run section 5 of supabase/53_purchasable_unlimited_therapy.sql

-- 222: read models only, nothing depends on them
drop function if exists public.therapy_customer_detail(uuid);
drop function if exists public.therapy_customer_voucher_balances(uuid);
drop function if exists public.therapy_customer_summary(text,integer,integer,boolean);
drop function if exists public.voucher_unit(public.voucher_kind);

-- 221: restore migration 74's reward options and claim
drop function if exists public.legacy_reward_options(uuid);
drop function if exists public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text);
drop function if exists public.legacy_reward_options_diagnostic(uuid);
drop function if exists public.therapy_reward_mapping_preview();
drop function if exists public.therapy_map_entitlement_tier(uuid,text,text);
-- then re-run section 7 of supabase/74_phase25_affiliate_legacy_qualification.sql
```

Migration 220's tables can stay: they are additive, and dropping them destroys
the audit trail of every expiry correction. The columns it adds to the two
entitlement tables are also additive — `expiry_date` keeps its existing meaning
throughout, so leaving them costs nothing.

**Recovery.** Every expiry movement is in `therapy_expiry_adjustments` with its
old and new value, so an incorrect recalculation can be reversed row by row:

```sql
select entitlement_kind, entitlement_id, old_expiry, new_expiry, reason, created_at
  from public.therapy_expiry_adjustments
 where action = 'recalculated' order by created_at desc;
```

---

## 7. Verification

| Suite | Result |
|---|---|
| `npm run test:therapy` | 19 passed |
| `npm run test:therapy:db` | 68 checks passed |
| typecheck, build | clean |
| Existing suites (tiktok 33, xero 8, survey 26, phones 9, auth-email 17; tiktok db 35) | unchanged |

All of the above were run against a database **destroyed and rebuilt from
nothing**, after the fixture turned out not to be self-contained: it relied on an
enum type and three columns I had added to the test database by hand. A test that
only passes on the machine that grew it is not a test.

`activate_purchased_therapy` returns `jsonb` now, and one of its answers is "no".
`TherapyPage.doActivate` read only `error`, which would have closed the dialog on
a refusal and looked like success — the same defect I had flagged for the invoice
path. Fixed: the dialog shows what is already running and offers either the
suggested consecutive start or a deliberate overlap.

Responsive behaviour was checked by rendering the real components against a stub
(`npx vite --config vite.therapy-preview.config.mts`) at **320, 375, 390 and
430 CSS px**: no horizontal overflow at any width, and no tap target under 36px.

### Not verified

* No migration has been run against production, so the previews have real numbers
  only for the local fixture.
* The Islamic holidays (Hari Raya Puasa, Hari Raya Haji) are gazetted but subject
  to confirmation by sighting and have been revised before.
* Only Singapore has a calendar. Every other country is configurable and reports
  itself unconfigured — deliberately, rather than being invented.
* The claim, activation and calendar screens were exercised through the query
  layer and a stubbed render, not against live data in the running application.
