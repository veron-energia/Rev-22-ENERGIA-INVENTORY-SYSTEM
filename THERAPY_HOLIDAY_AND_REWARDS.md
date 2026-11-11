# Therapy: closure extensions, holiday calendars and reward choices

> **10 Nov 2026: Legacy Therapy and Qualification removed (migration 502).**
> Same-day qualification earns nothing any more. The unclaimed Legacy rewards
> were cancelled at go-live, and the Therapy page lost its Legacy Therapy and
> Qualification tabs. Section 1 (reward choices: `legacy_reward_options`,
> `claim_legacy_therapy`) and the reward-tier part of section 3 describe what
> no page uses any more; they are kept as history. Sections 2 (closure
> extension), 4 (customer voucher balances) and 5 (multiple unlimited
> packages) still apply. The holiday calendars and the expiry recalculation
> preview are on **Therapy → Holidays** (Owners and Managers). Credit
> Package, Premium Bundle and therapy-package vouchers are handed over on
> **Therapy → Vouchers to hand over**.

## Legacy Therapy retired (502, the user's decisions of 10 Nov 2026)

### What was decided

* **Earning stops at go-live**, the moment migration 502 commits, for
  customers and for affiliates. Paying, part-paying, correcting, reopening,
  cancelling or refunding an invoice no longer recounts anyone's day, and
  "Re-check paid days" refuses.
* **Nothing is deleted.** Every reward, its invoice links
  (`therapy_entitlement_invoices`), the rules and the audit rows stay as
  history.
* **Unclaimed rewards are cancelled at go-live:** 102 one-month rewards (43
  customers) and 1 affiliate reward of 10 vouchers. The 50 vouchers already
  handed over to 3 customers stay with them as ordinary vouchers.
* **New Credit Package sales give credit only.** The vouchers still owed from
  earlier sales (100, to 2 customers) can still be handed over, and refunding
  or cancelling one of those sales still opens the reward review first. One
  earlier sale was not paid off yet: see "The earlier part-paid Credit Package
  sale" below.
* **Premium Bundle free vouchers are not Legacy** and work exactly as before,
  including a blank bundle threshold falling back to S$994 now that the rules
  are off.
* **The refund guard is gone.** The trigger `legacy_refund_guard` on
  `invoices` is dropped; its two functions stay, attached to nothing. The one
  paid invoice whose day earned the only free month ever used can now be
  refunded like any other, and the month already used is not taken back.
* **Deleting a customer:** of their rewards, only vouchers still owed to them
  block it: a Credit Package, Premium Bundle or therapy-package reward still
  waiting with vouchers left, within its collect-by date, on a sale not
  refunded, cancelled or deleted (or a live unlimited period). Legacy rows
  never do, and nor does a reward fully handed over or withdrawn. So the 3
  customers holding the 50 vouchers are no longer kept from being deleted by
  their old rewards (vouchers a customer holds never blocked a delete).
* **`LEG-` numbers stay** for new voucher rows: `next_legacy_entitlement_no()`
  is unchanged.

### What staff see

| Where | Since 502 |
|---|---|
| Therapy | Purchased · **Vouchers to hand over** (the Credit Package, Premium Bundle and therapy-package vouchers still owed, with the Vouchers button); for Owners and Managers also **Holidays** (holiday calendars and company closures, and the expiry recalculation preview) · Credit Packages · Premium Bundles · Packages. The Credit Package window has no reward section, and every save switches the package's reward off (the saved threshold and voucher list stay in the database, unchanged). |
| Invoices | No Legacy box. Refunding or cancelling an older Credit Package sale lists its reward vouchers in plain words: those not handed over are withdrawn with it, those handed over stay with the customer. Moving its unused credit to another customer ("Correct unused benefit recipient") is refused until the review "This Credit Package came with reward vouchers" is recorded. |
| Customers → View | **Vouchers to hand over**: only what is still owed, with what is left and the collect-by date. The wallet's Legacy credit (an opening balance) is another thing and is unchanged. |
| Reports → Therapy | The packages bought and the reward vouchers, typed "Purchased" or "Reward vouchers". |
| Dashboard | Nothing changes on screen. The alert "Refunded or cancelled sales still holding credit or rewards" no longer follows the old same-day rewards (none was flagged through them on 10 Nov 2026); what else it counts is unchanged. |

### The recount functions are retired: never run them by hand

After 502 nothing calls these four, and no signed-in login can:

* `recompute_legacy_qualification(uuid,uuid,date)`
* `recompute_affiliate_legacy_qualification(uuid,date)`
* `recompute_affiliates_for_customer_day(uuid,date)`
* `recompute_legacy_qualification_for_invoice(uuid)`

**Never run them by hand**, not as the service role and not from the SQL
editor either. A recount deletes the day's rows in
`therapy_entitlement_invoices` and puts back only those of rewards that are not
cancelled. After go-live every unclaimed reward is cancelled, so a single run
drops the record of which invoices earned a reward, for good. 502 puts a
comment on each of the four saying so.

### Before the window

1. Run `scripts/therapy/golive-preview-502.sql` on production. It only reads
   (a read-only transaction, counts only, no names). Each row has a kind:
   * **constant**: the figure production has now, next to the name of the
     constant that must equal it when the scripts run. `expected` is the
     constant as written on 10 Nov 2026, so `ok` false means the figure has
     moved since. Figures do move: Legacy rewards are earned until 502
     commits, and hand-overs change the counts too.
   * **stop**: a stop sign (see 3 below).
   * **check**: what a step checks when it runs. Before 502 the "502 in" rows
     show the old md5s, and before step 2a the "2a in" rows read as before it.
     That is expected.
2. If a figure has moved, tell the user the new figure. Only with their OK,
   change that constant in every file the preview's note names (steps 2a and
   2b, undo 2b, undo 2a, the earlier-sale script), then run the go-live suite
   (`scripts/therapy/tests/legacy-retired-golive-502.sql`) again. The suite
   checks that the constants repeated across the files still agree, and runs
   the scripts with its own figures, so it tests them whatever the constants
   say. Change nothing without the user's OK.
3. **Stop signs.** If one of these shows anything, stop and tell the user. No
   constant can fix it: the scripts refuse, or would do what was not decided,
   until the code changes.
   * A Legacy month booked or running.
   * A waiting Legacy reward that step 2b leaves out (part handed over, no
     rule, from a sale).
   * A waiting reward that is neither a customer's one-month reward nor an
     affiliate's voucher reward, or affiliate rewards with different numbers
     of vouchers.
   * A rule on for one store only, rules with different amounts, or a rule
     the rule form would refuse or change.
   * A Credit Package with the reward on that is deleted. Step 2a refuses.
   * A Credit Package sale split between customers, not paid off, that still
     carries reward vouchers. Step 2a refuses, counting each such sale once and
     naming its invoices: paid off later, it would still give them.
   * An earlier sale owed a reward that is split between customers, or
     earlier sales that differ in rewards, threshold or price.
   * A Credit Package sale with the reward on, not paid off, on a draft or on
     an invoice waiting for a cancel or refund. Step 2a does not keep its
     reward.
4. Run the preview again just before the window.

### Go-live order

One quiet window, outside opening hours, in this order:

1. **Migration 502** (`supabase/502_legacy_therapy_retired.sql`), with its row
   in the migration history, in the same transaction. From the moment it
   commits, nothing new is earned.
2. **Step 2a: `scripts/therapy/credit-package-credit-only-502.sql`.** It
   switches the reward off on the 3 Credit Packages, and records in the Audit
   Log the one earlier part-paid sale still owed its reward, with the values
   it would have got.
   * If it refuses, do not open with 502 alone: fix the cause and run it
     again, or undo 502. No Credit Package may have its reward on when the
     shop opens.
3. **Step 2b: `scripts/therapy/legacy-retired-golive-502.sql`.** It cancels the
   103 unclaimed rewards and switches the 3 rules off. It refuses unless step
   2a has run. Run on its own, if it refuses, step 2a still stands. A voucher
   hand-over at the same moment waits for it and is then refused (the reward
   is cancelled by then).
4. **The pages**: commit, push and deploy. Then **every till and office PC
   reloads the app**. A page left open from before keeps the old screens: an
   old refund window, for one, does not open the reward review.

**No Credit Package may be paid between 502 and step 2a.** One paid off in
between still gets reward vouchers, and step 2b then refuses. The safe way is
**one transaction**: 502 with its history row, the recording account, step 2a
and step 2b, then commit. Nothing can fall between them, and if anything
refuses, all of it rolls back, 502 included.

To run it as one transaction, as the database owner: `begin;` and
`set local lock_timeout = '5s';`; then refuse if 502 is already in the
migration history (`supabase_migrations.schema_migrations`) or if the newest
migration there is not 501's (`20261107085301`); then the whole 502 file; then
its history row (a version from the clock, the name
`502_legacy_therapy_retired`, and the file's text as its one statement); then
the recording account (step 2a's header says how); then the step 2a file and
the step 2b file as they are; then `commit;`. With psql, run it as
`psql -X -v ON_ERROR_STOP=1 -f <file>`: a refusal then stops psql before the
commit, and the transaction rolls back whole. Without `ON_ERROR_STOP` it still
rolls back whole, but psql ends with exit code 0, which looks like success.

**Never push the pages before 502, step 2a and step 2b are in.** The new
pages ask the server for lists that only 502 has, and they no longer show the
Legacy rewards that step 2b cancels.

Both steps write to the Audit Log under a recording account, which must be an
active Owner or Manager (each script's header says how to set it).

### Rollback order

Only in this order:

1. Revert the pages and deploy them again.
2. Undo step 2b: `scripts/therapy/undo-legacy-retired-golive-502.sql`
3. Undo step 2a: `scripts/therapy/undo-credit-package-credit-only-502.sql`
4. `scripts/therapy/undo-502.sql`. It reminds you that the pages must already
   be reverted: the new Therapy page asks for a list ("vouchers") that the
   server before 502 does not have.

Then every till and office PC reloads the app again.

### Rollback limits

* **Paid days are not recounted.** While 502 was in, paying, refunding or
  cancelling an invoice recounted nothing, and `undo-502.sql` does not recount
  either. With the user's OK, an Owner or Manager runs "Re-check paid days"
  (`backfill_legacy_qualification`) from the go-live date to today, for all
  stores (it works again once `undo-502.sql` has run). It only recounts days
  that still have a paid or part-paid invoice, so list the days whose invoices
  were all refunded or cancelled meanwhile, and ask the user.
* **The 502 row in the migration history stays.** The history still says 502
  is in, so applying 502 again with its history row is refused (it is already
  recorded). With the user's OK, remove that one row (found by its name and
  the md5 of its stored statements), or leave it and record the undo beside
  it.
* **The time of last change is not put back** (`updated_at`) on the 3 rules
  and the 3 Credit Packages: the undo saves them again. Everything else in
  them is as before.
* **Undo 2a refuses once the earlier part-paid S$1,000 sale is paid off.**
  Its reward vouchers are then given, or still owed, and undoing step 2a would
  lose the record of them. A full rollback then needs the user's decision.
* **The earlier-sale script has no UNDO file.** If its vouchers were given by
  mistake, the reward review on that invoice (Owner or Manager) withdraws the
  reward only while none of its vouchers has been handed over; once any has,
  the review keeps the reward, and the rest can still be handed over. The
  review opens on the invoice's Finance panel when "Correct unused benefit
  recipient" (moving its unused credit) is refused because of those vouchers;
  recording the decision moves nothing. Refund / Cancel does not open it: a
  refund or cancellation withdraws the vouchers not handed over as part of the
  action. Or an Owner or Manager calls `resolve_invoice_credit_rewards` for
  that invoice. Ask the user first.
* The UNDOs carry the same constants as steps 2a and 2b. If those were changed
  at go-live, these were changed with them (the go-live suite checks that
  they agree).

### The earlier part-paid Credit Package sale

One Credit Package sold before go-live was not paid off on 10 Nov 2026. It
keeps the terms it was sold with:

* When it is paid off, it is issued as any sale is now: credit only, because
  the package's reward is off by then.
* Its 10 reward vouchers are then given by
  `scripts/therapy/credit-package-presale-reward-502.sql`, on the terms
  recorded for it at go-live (step 2a above).
* That script is run **only with the user's OK, asked for fresh at that
  time**. Nothing about it is automatic.

---

*The report below was written on 9 Sep 2026, before those migrations went live.*

Migrations 220–224, `src/lib/therapy/`, `src/components/therapy/`.
Nothing here is committed, deployed, or applied to production data.

---

## 1. Why the claim dialog only ever offered unlimited therapy

> History since 502 (10 Nov 2026): no page offers this claim any more,
> nothing new is earned to claim, and signed-in logins can no longer call
> `legacy_reward_options`, `legacy_reward_options_diagnostic` or
> `claim_legacy_therapy` (their bodies stay). See the note at the top.

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

### One convention — a correction

An earlier version of this document said purchased and Legacy therapy used
different calendar-month rules, and that a 29 February start differed by a day
between them. **That was wrong**, and migration 225 corrects it.

`membership_expiry()` is not installed. Phase 19 dropped it, and migration 72
exists precisely because activating a purchased therapy then failed with

```
function public.membership_expiry(date, integer) does not exist
```

— it replaced the call with `therapy_expiry()`. So every purchased and Legacy
expiry in this database was computed with one rule: `start + months - 1 day`,
inclusive.

The claim survived my tests because the local fixture created
`membership_expiry` by copying it out of migration 45 — a migration this
database never ran. The fixture now mirrors what is installed, and reproduces
the production error without migration 225.

`therapy_adjusted_expiry` still accepts a convention argument so migrations
221–223 keep working unchanged. It no longer selects anything, and a check in
migration 225 plus a database test assert both values stay identical — if
`membership_expiry` is ever reinstalled, that check fails and points at the
function to revisit.

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
| Reward tier mapping (no longer on any page) | `therapy_reward_mapping_preview()` | Attach any tier automatically; alter a qualifying amount; touch a claimed unit |
| Calendar impact | `therapy_closure_impact(date)` | Shorten anyone when a date is removed |
| Successor reconciliation | `therapy_successor_reconciliation()` | Move a start date a member of staff chose |

**Shortening.** `therapy_apply_recalculation` lengthens freely and refuses to
shorten. Removing a calendar entry reports `skipped_would_shorten` and leaves the
granted expiry standing; an Owner or Manager must pass `p_allow_shortening` with
a reason, which is stored with both dates.

**An earned entitlement stays claimable when the rules change** (migration 226).
Raising a threshold changes who qualifies from then on; it does not take back
what was already granted. Options resolve in this order:

1. An explicit tier mapping, if someone made one.
2. **The tier of the rule the entitlement was actually created from**
   (`therapy_entitlements.rule_id`). This is a record, not a guess — it is the
   rule that granted the entitlement, so its siblings are the alternatives that
   were genuinely offered at the time, including any since retired, which are
   returned flagged rather than hidden.
3. Rules at the same qualifying amount, as before.
4. **The entitlement's own snapshot, always**, so a claim is never blocked.

In the ordinary case — raising S$794 to S$994 by editing the existing rules —
`rule_id` still points at them, so **both alternatives come back with nothing to
configure**. Where the originating rule is gone entirely, the entitlement is
still claimable as exactly what it was granted, with no rule at all, which is
what `claim_legacy_therapy` has always done when given no `p_rule_id`.

**Mapping** remains for the case that genuinely needs a person: attaching an
entitlement to a tier at a *different* threshold. A rule at a different
threshold is a different promise, so that still requires a reason. The
qualifying amount is never rewritten — verified by a test that reads it back as
`794.00` after a claim.

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
6. `supabase/225_therapy_expiry_base_correction.sql` — **required.** Without it
   every expiry calculation raises `function public.membership_expiry(date,
   integer) does not exist`.
7. `supabase/226_therapy_historical_claims.sql`
8. **Read the previews before touching anything:**
   ```sql
   select * from public.therapy_recalculation_preview(null, null);
   select * from public.therapy_reward_mapping_preview();
   ```
9. Deploy the frontend.
10. In the Therapy page, confirm the Singapore calendar for each year against the
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

> **Superseded by 502. Do not run: it would bring back the Legacy reward
> functions.** To undo 502, follow "Rollback order" at the top.

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
| `npm run test:therapy:db` | 76 checks passed |
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
