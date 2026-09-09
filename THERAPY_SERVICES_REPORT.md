# THERAPY SERVICES · CREDIT SPENDING RULES · PACKAGE COMMISSION

| | |
|---|---|
| Migrations | `240`–`245`, additive, each idempotent |
| Tests | `npm run test:therapy-services:db` — **105 assertions, passing, repeatable** |
| Existing suites | therapy 76, users 60, tiktok 35 (database); therapy 19, tiktok 33, xero 8, survey 26, phones 9 (node) — **all passing** |
| Clean room | database dropped and rebuilt; all four database suites pass in **four different orders** |
| `npm run typecheck` / `npm run build` | **0 errors / build succeeds** |
| Committed, pushed, deployed | **none** — stopped for review |
| Production data changed | **none** |

---

## 1. The defect worth reading first

Both credit packages and premium bundles are meant to commission at the
**third-party** rate. Premium bundles did. Credit packages did not.

`credit_packages.commission_classification` defaulted to `'own'`, the sale
snapshotted that default, and `earn_credit_package_commission` chose the rate
from the snapshot:

| | rate used | on a S$1,000 sale |
|---|---|---|
| Before | `commission_tier1_own_rate` — 15% | **S$150** |
| After | `commission_tier1_third_rate` — 4.5% | **S$45** |

Verified by running the real function on the same sale before and after.
The test asserts it against a sale that still carries an `'own'` snapshot,
because that is what every historical row carries.

**What was already correct, and should not be "fixed":** both functions
commission on `external_paid` only. No commission on issued credit face value,
none on bonus credit, and none again when that credit is later spent.

**Migration 243 removes the choice rather than changing the default.** A setting
that can contradict a mandatory rule is a defect waiting to recur, so
`commission_classification` is forced to `third_party` and a check constraint
refuses `'own'`. The snapshot is still recorded and still shown; it simply no
longer selects a rate.

**The one thing it does rewrite, and why.** Existing catalogue rows still saying
`'own'` are corrected to `third_party`, with the old value recorded in the audit
log. This was not the original plan — the constraint was added `NOT VALID` on the
belief that it would leave those rows alone. It does not: a `NOT VALID` check
skips rows already in the table but still binds every later **update** to them,
so a package left saying `'own'` would have become **uneditable** — renaming it
or changing its price would fail with a constraint violation, for a reason
nobody at the counter could work out. Verified by reproducing it.

This corrects a **setting**, not money: `classification_snapshot` on past sales
is untouched, no commission row is read or written, and the commission functions
no longer consult the column at all.

### Historical sales — read, not rewritten

`package_commission_diagnostic()` lists every package sale that commissioned at
the own-brand rate, with what the third-party rate would have produced and the
difference. `package_classification_gaps()` lists catalogue rows that still
disagree with the rule.

**Neither changes a commission, a payout or an amount.** No historical repair is
included: rewriting settled commission affects money already paid to real
people, and that needs a decision and a reviewed plan, not a migration. Run the
diagnostic against production to see the size of it.

---

## 2. What a therapy service is (240)

`therapy_services` — one row per sellable session. Standard price, duration, and
a **structured** frequency rule. Not free text: something has to enforce it.

| Field | Meaning |
|---|---|
| `frequency_kind` | `per_day` / `per_week` / `per_month` / `per_hours` / `unrestricted` |
| `frequency_max_per_period` | how many within that period |
| `frequency_interval_hours` | for `per_hours`, measured **start to start** |

Boundaries are Singapore's: a fixed +08:00 with no daylight saving, and a
Monday-based week. `therapy_service_frequency_ok()` decides; the sentence a
person reads is generated from the same three fields, so the two cannot drift.

The rule also exists in `src/lib/therapy/frequency.mjs` for the browser. **A
database test compares them on every case** — including the two that matter: a
5-hour rule blocks at +4h and allows at +5h, and Foot Detox and Power Recharge
do not block each other, because history is kept per service.

`therapy_service_stores` holds where a service is offered and any price
override. No row means not offered there.

**An active service cannot be saved without a duration** — a service with no
duration cannot go in a calendar, and the person saving it should be told now.

Archiving deactivates and keeps the row: a service that has been sold is part of
somebody's invoice and part of an issued voucher's snapshot.

### Bugs this work found in passing

`assertInstant` in `frequency.mjs` rejected a number, but the function returns
epoch milliseconds and the period helpers are called with its own output. Every
calendar-period check (`per_day`, `per_week`, `per_month`) threw; only the
hourly path worked. Fixed, and covered.

Two defects in my own migrations, both found by writing the suite rather than by
reading the code: 243 was not re-runnable (after patching, its anchor is gone,
and the absence looked like a rewritten function), and 244 chose the wrong
`create_invoice` overload. Both fixed and covered.

The test fixture also had to be corrected three times over: it created shared
tables with fewer columns than the sibling therapy suite needs, and because
`create table if not exists` does nothing against an existing table, whichever
fixture ran second silently lost its columns. The two fixtures now build an
identical schema in either order, checked by diffing
`information_schema.columns` from a fresh database both ways.

---

## 3. What a therapy voucher gives (241)

A reward voucher previously said only "a voucher". It can now say what it gives,
structurally. A voucher is the sum of its components:

* **fixed** — this service, this many times
* **choice** — this many sessions, chosen from a named set

Every combination the brief names is expressible with no special case:

| Wanted | Components |
|---|---|
| One fixed Power Recharge | 1 fixed |
| One of Power Recharge or Foot Detox | 1 choice of two |
| Two flexible sessions | 1 choice, quantity 2 |
| One Power Recharge **and** one Foot Detox | 2 fixed |
| Fixed sessions **plus** a choice group | 1 fixed + 1 choice |

**Nothing defaults to "any two therapies."** A voucher with no definition is not
a therapy voucher and reads as exactly that.

### Issuance freezes the terms

When a voucher is issued, `therapy_voucher_issues` stores the whole definition —
services with the names and codes they had that day, quantities, choice groups,
repeat rules, price and validity. Reads answer from the snapshot, never the
catalogue.

Tested by renaming the service and redefining the voucher afterwards: the
customer's rights do not move.

**Vouchers issued before this existed are not backfilled.** They were sold on
terms this table cannot know, so `therapy_vouchers_without_rights()` lists them
and a Manager applies rights one at a time via
`apply_therapy_voucher_rights_retrospectively()`, which records that they were
applied after the fact.

Nothing here redeems a session. Session redemption is out of scope; the
remaining-session model exists and the only thing that currently reduces it is
the existing whole-voucher status.

---

## 4. Selling one session on an invoice (244)

`create_invoice` could sell an unlimited-therapy **package**, not a session.

**How it was changed:** not by restating it. Its installed definition is read
back with `pg_get_functiondef` and a session branch is inserted **ahead of** the
package branch in both loops, which are left untouched. If the anchors are not
found the migration **stops** rather than guessing — inserting a branch in the
wrong place in that function would mis-price invoices.

**It selects the overload by content, not by position.** `create_invoice` exists
in more than one overload: successive migrations added arguments, and `create or
replace` with a new argument list creates a *new* function rather than replacing
the old one, so the six-argument version from migration 09 still sits beside the
current one. My first version picked the lowest oid, which is decided by
creation history and not by which one is live — so it could patch a function
nothing calls and leave the real one untouched, appearing to succeed while
changing nothing. It now patches every overload that actually contains the
therapy branches and leaves the others alone. The test fixture reproduces both
overloads and asserts exactly that.

A test asserts those two anchors still appear verbatim in
`61_phase12_foc.sql`, the migration that last defined `create_invoice`, so the
patch going stale is caught rather than assumed away.

A session line carries `therapy_service_id` and no `therapy_package_id` — the
discriminator, enforced by a check constraint. On payment,
`customer_therapy_sessions` records what was bought, idempotently. Cancelling or
refunding the invoice takes back only what has not been used.

---

## 5. Where credit may be spent (242)

Enforced **inside the real allocation function**, not in a parallel copy of the
rules. `allocate_invoice_wallet_credit` is patched with one extra condition.

| Credit | May pay for | May not |
|---|---|---|
| Credit package — **paid** | therapy sessions, therapy vouchers | products of any kind, unlimited therapy |
| Credit package — **bonus** | own-brand products | third-party products, therapy, vouchers |
| Premium bundle | anything except new credit | credit packages, premium bundles |
| Other recognised sources | anything except new credit | credit packages, premium bundles |
| **Unidentifiable** | **nothing** | everything, until reviewed |

Classification is read from the actual models — `products.product_type`,
`vouchers.voucher_kind`, and whether a therapy line names a service — never from
a name. Composite promotions are checked component by component.

**No credit of any kind may buy more credit.**

### The hole this closed

`credit_lot_allows` treated a lot it could not identify as spendable on
anything. A restricted balance with a missing source record quietly became cash.
Such lots are now held: `credit_lots_needing_review()` lists them, and **their
amounts are untouched** — being unable to identify a balance is not a reason to
change it.

`customer_credit_eligibility()` tells a customer what each balance may pay for
and, when it cannot be spent, why.

**One test of mine passed for the wrong reason first.** The "package credit
should refuse a third-party product" case passed while the wrong lot was paying;
I had truncated the lot ids in the output. Checking *which* row, not just that
one existed, is what found it. The test now asserts the lot.

---

## 6. What a customer can actually take (245)

Rights now come from three unrelated places and are not interchangeable.
Reading them separately is how somebody gets told they have "four therapies
left" when three are Foot Detox and they want Power Recharge.

`therapy_customer_entitlements()` returns all three in one shape, and the field
that matters is `eligibility`:

| | |
|---|---|
| `any_service` | an unlimited period — the catalogue is the limit |
| `fixed` | this one service |
| `choice` | one of a named set |
| `unrecorded` | a voucher nobody described — counted nowhere |

`remaining` is a count for sessions and voucher units, and **null** for an
unlimited period, because "how many" is the wrong question there.

`therapy_customer_service_summary()` totals them, keeping purchased sessions and
voucher sessions apart and holding unrecorded vouchers **out** of the totals.
`therapy_customer_overview()` composes with 222's `therapy_customer_detail`
rather than rewriting it.

### Read models for a calendar that does not exist yet

`therapy_calendar_services(store)` and `therapy_booking_options(...)` answer for
the **caller**: store access is applied inside the database, not left to a page.
A caller without access gets a refusal from the booking read, not an empty list —
an empty list reads as "nothing available", which is a different answer.

Frequency and entitlement are reported **separately**. Holding a right but being
blocked by frequency today is a different conversation from holding nothing, and
collapsing them would hide which one it is.

Session history is an **argument**, not a lookup. There is no authoritative
record of completed sessions, so a function that went looking for one would be
answering from nothing.

---

## 7. The page

**Therapy Services** — `/therapy-services`, Owner and Manager only, in the
sidebar under Therapy.

* **Services** — search by name, code or description; filter Active / Not active
  / Archived / All; a store selector that switches the table to that store's
  price and availability. Create and edit with structured frequency fields and
  the enforced sentence generated live beneath them. A per-store availability
  and price-override editor. Archive.
* **What a voucher gives** — pick a voucher, build its contents from fixed
  sessions and choice groups, set validity and repeat. Each component shows what
  it reads as while it is being built.

Verified in the preview harness (`vite.therapy-services-preview.config.mts`,
port 5197) at desktop and at 375px: the page body does not scroll horizontally,
the frequency rule and store count move under the service name on a phone rather
than off the right-hand edge, and the component editor stacks.

Unlimited-therapy packages stay on the existing Therapy page. Nothing there was
touched.

---

## 8. Setting up the catalogue

The two example services are **fixtures**, not production data. No migration
seeds a service, and none should — durations and prices are a business decision.

To set them up, on **Therapy Services → Add Service**:

| | Power Recharge | Foot Detox |
|---|---|---|
| Code | e.g. `PR` | e.g. `FD` |
| Standard price | *your price* | *your price* |
| Duration | *your duration* | *your duration* |
| How often | Every so many hours → **5** | Per calendar day → **1** |
| Active | tick once the duration is set | tick once the duration is set |

Then **Stores** on each row: tick the stores that offer it, and enter a price
only where that store differs.

The 5-hour rule is the one that was described; the rest are placeholders for
someone who knows the business to fill in.

---

## 9. Files

**New migrations** — apply in order:

| | |
|---|---|
| `supabase/240_therapy_services.sql` | the service catalogue and frequency rules |
| `supabase/241_therapy_voucher_services.sql` | what a voucher gives; issuance snapshots |
| `supabase/242_credit_spending_rules.sql` | the credit matrix, enforced in allocation |
| `supabase/243_package_commission_classification.sql` | the commission fix and diagnostics |
| `supabase/244_therapy_session_sales.sql` | selling and fulfilling one session |
| `supabase/245_therapy_entitlement_read_models.sql` | unified and permission-aware reads |

240 and 242 must precede 244; 241 and 244 must precede 245. Each is idempotent
and safe to re-run.

**New application files**

* `src/pages/TherapyServicesPage.tsx`
* `src/lib/therapy/frequency.mjs` + `.d.mts`
* `scripts/therapy-services/tests/{prior-state.sql,database.mjs}`
* `scripts/therapy-services/preview/*`, `vite.therapy-services-preview.config.mts`

**Edited**

* `src/App.tsx` — one route
* `src/components/AppLayout.tsx` — one navigation entry
* `src/components/therapy/therapy.css` — appended, all selectors `.therapy-*`
* `package.json` — one test script
* `.claude/launch.json` — one preview entry

### Rollback

Nothing is destructive. To undo:

1. `drop` the new tables (`therapy_services`, `therapy_service_stores`,
   `therapy_voucher_*`, `customer_therapy_sessions`) and the new functions.
2. Re-run the migrations that own the patched functions, which restores each to
   its unpatched definition:
   * `61_phase12_foc.sql` — `create_invoice` (removes the session branch)
   * `82_phase29_wallet_payments_refunds.sql` — `allocate_invoice_wallet_credit`
   * `79_phase27_credit_packages.sql` — `earn_credit_package_commission`,
     `credit_lot_allows`
   * `80_phase28_premium_bundles.sql` — `earn_premium_bundle_commission`

   Re-running 61 also reverts any later patch to `create_invoice` from another
   migration, so check what else has patched it before doing this.
3. Drop the `credit_packages_third_party_commission` and
   `premium_bundles_third_party_commission` constraints if the old `'own'`
   setting is wanted back. The previous value of every corrected row is in
   `audit_logs` under `commission_classification_corrected`.

The added `invoice_items` columns are nullable and can be left in place.

---

## 10. Coordination

Invoice work is in progress in the same checkout. This work:

* touched **no** file in `src/components/XeroExport.tsx`,
  `src/pages/{Approvals,Dashboard,Invoices,Reports}Page.tsx`;
* **did not restate** `create_invoice`, `allocate_invoice_wallet_credit`, or
  either commission function — each is patched from its own installed
  definition, so whatever else has landed in them is preserved;
* appended to `therapy.css` under `.therapy-*` selectors only, changing no
  shared class;
* took migration numbers 240–245.

`invoice_items` gains three nullable columns (`therapy_service_id` from 242,
`therapy_service_name_snapshot` and `therapy_service_minutes_snapshot` from
244) and one check constraint added `not valid`, so existing rows are not
scanned and no existing insert path is affected.

---

## 11. Not done

* No appointment booking, customer portal, automatic appointment detection, or
  session-redemption action — all explicitly out of scope. `quantity_used` and
  `sessions_used` exist and nothing increments them.
* No historical commission repair (§1).
* No production catalogue data (§8).
