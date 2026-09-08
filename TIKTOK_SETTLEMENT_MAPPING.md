# TikTok settlement — periods, field mapping and classification

Reference export: `income_20260908180508(UTC+8).xlsx`, read but never modified.
44 transactions covering 1 Aug – 8 Sep 2026 — a **partial** source for both
reporting periods it touches.

> **Status: implemented and tested; nothing deployed.** Migration 210 has not been
> applied to production, no production data has been changed, and nothing has
> been committed.

---

## 1. Settlement periods

A reporting month **ends on the last Wednesday of that month** and **starts the
day after the previous month's last Wednesday**. Both displayed dates are
inclusive, and consecutive periods tile the calendar with no gap and no overlap,
so every settled transaction falls in exactly one month.

| Reporting month | Period (SGT) |
|---|---|
| August 2026 | 30 Jul – 26 Aug |
| September 2026 | 27 Aug – 30 Sep |
| October 2026 | 1 Oct – 28 Oct |

September ends **on** a Wednesday, which is why the start is defined as "the day
after the previous period's end" rather than "the previous month's last
Thursday" — the naive reading would overlap the neighbouring period by a week.

Implemented twice, deliberately: `src/lib/tiktok/settlementPeriod.mjs` for the
interface and `public.tiktok_settlement_period()` for the backend. A database
test asserts the two agree on **all 84 periods from 2024 to 2030**, because two
implementations that are never compared will drift.

**Timestamp filtering** uses the Singapore start-of-day, half-open through the
start of the day after the period ends. Half-open on purpose: a closed range
written as `<= 23:59:59` silently drops the final second.

---

## 2. Which date decides the period

**Order settled time.** Nothing else — not order created time, not customer paid
time, not the upload date, not a withdrawal date. TikTok's own Fee explanation
sheet defines it as *the time when the payout of this order is credited to your
account balance*, which is exactly what a payment report should be struck on.

This is a real change. In the reference export, **24 of 44 rows** have a created
date differing from the settled date, and **7 rows change reporting period**.
The existing reports read `coalesce(order_created_time, settled_time)` — created
date *preferred* — and the daily report defaulted to `p_basis = 'created'`.
Migration 210 removes that basis rather than re-defaulting it: a toggle that
produces a figure which cannot tie to what TikTok paid invites someone to use it.

**Parsing.** The export is stamped UTC+8 and writes times with no offset, so a
bare `2026/08/01` is Singapore wall time and its date stands as written — no
conversion, and deliberately no `new Date(s)`, whose behaviour on non-ISO strings
is engine-dependent. A value that *does* carry an offset is converted properly:
`2026-08-26T17:00:00Z` is 27 August in Singapore and belongs to September.

**A missing or unparseable settled date is never guessed.** The row goes on a
review list, is counted in `undated_count`, and sets `needs_review`, so the
totals are visibly incomplete rather than quietly smaller.

---

## 3. The five figures

| Figure | Definition |
|---|---|
| **Total Revenue** | Sales proceeds after seller discounts and customer refunds, before platform fees and operating expenses |
| **Total Fee** | Net transaction fees and deductions, excluding customer refunds and operating expenses |
| **Total Settlement** | Revenue − Fee (**before** operating expenses) |
| **Total Expense** | Advertising and other identifiable operating payments, net of reversals |
| **Total Income** | Settlement − Expense |

**Total Settlement is intentionally not TikTok's "Total settlement amount"**,
which already has advertising deducted. Both are shown and labelled:

- *Total Settlement* — revenue less fees, before expenses
- *Total Income* — settlement less expenses
- *TikTok reported net settlement* — imported source total, used for reconciliation

None is cash in the bank. Withdrawals happen separately and are listed on their
own sheet.

Money is **integer cents** end to end. Floating point drifts over a few hundred
rows, and a report that is a cent out sends someone looking for a cent that was
never lost.

---

## 4. Field mapping

| Source column | Used for |
|---|---|
| Order/Adjustment ID | Identity, **kept as a string** — these are 19 digits and exceed 2^53, so a JS number would corrupt them |
| Transaction type | Financial category |
| Order settled time | The period. The only date that decides it |
| Order created time | Displayed only; never a reporting basis |
| Currency | Kept explicit; more than one blocks a single total |
| **Total Revenue** | Revenue, taken **once** |
| Subtotal after seller discounts | Detail; reconciles to Revenue with the refund |
| Refund subtotal after seller discounts | Detail only — **already inside Total Revenue** |
| **Total Fees** | Fee, sign-converted to a positive cost |
| Individual fee components | Display only; never added on top of Total Fees |
| **Adjustment amount** | Advertising expense, taken **once** |
| Total settlement amount | TikTok's own figure, for reconciliation only |
| Related order ID | Links a correction to its original |

**Revenue is taken once.** In this file `Total Revenue` already includes customer
refunds: 5,205.67 (subtotal after discounts) + −455.99 (signed refund) = 4,749.68.
The refund column is shown as explanation and is **not subtracted again**. Orders
that were fully refunded show net revenue of zero — subtracting their refund a
second time would push the total negative.

**Fees are taken once.** `Total Fees` is a signed net deduction; individual
components are nested inside it (Seller shipping fee contains its own
sub-components) and adding them would double-count.

**Advertising is taken once.** "GMV payment for TikTok Ads" rows carry zero
revenue and zero fees, and the same negative amount appears in **both** `Total
settlement amount` and `Adjustment amount`. It is counted once, from the
adjustment, as Expense — never also as a fee or a revenue reduction. In this
sample `GMV Max ad fee` totals 0.00, so no advertising is embedded in Total Fees;
the classifier still separates embedded ad components where a file has them.

---

## 5. Classification

Finer than the stored `txn_class`, which has four values and cannot tell an
advertising payment from a bank transfer — both are `finance`. `txn_class` is
**left exactly as it is**: migration 66's check constraint and every stored row
depend on it. The finer category is a new function beside it.

| Category | Effect |
|---|---|
| `sale` | Revenue and its fees |
| `sale_refund` | Reduces revenue **in the period it settles in**, not the original order's month |
| `fee` / `fee_reversal` | Cost, and cost coming back |
| `ad_expense` / `expense_reversal` | Expense, and expense coming back |
| `balance_movement` | **Nothing.** Withdrawals, transfers, reserves, financing |
| `unknown` | **Nothing**, and blocks any "reconciled" claim |

Classified by documented economic meaning, not by whether a label contains a
word. **"Affiliate Shop Ads commission" is a fee, not advertising** — it is
commission on a sale. Matching on "ads" would move real commission into
advertising spend and overstate it. This was caught by a test during development,
not by inspection.

Reversals **reduce** costs rather than adding to them. `Math.abs` is never
applied row-by-row: it would turn every rebate into another charge.

Balance movements are excluded because the money they describe is already
represented by the transactions that produced it. The Withdrawal records sheet
(39 rows in this export) is **never added to the financial totals** for the same
reason.

---

## 6. Repeated transactions

Rows 44 and 45 of the export share Order/Adjustment ID `585244041338652508` and
the same settled date, with different valid amounts:

| Row | Revenue | Fees | Settlement |
|---|---:|---:|---:|
| 44 | 141.12 | −23.32 | 117.80 |
| 45 | 310.46 | −50.92 | 259.54 |

**Both count** — together 451.58 revenue and 377.34 settlement. Order ID alone is
therefore *not* transaction identity, and confirming one row must not supersede
the other. Tested in both the JavaScript and the database suites.

---

## 7. Verified sample results

Reproduced by the shipping modules and independently by the migration, then
checked against the workbook's own Reports sheet.

| Reporting period | Rows | Revenue | Fee | Settlement | Expense | Income |
|---|---:|---:|---:|---:|---:|---:|
| August 2026 (30 Jul – 26 Aug) | 30 | 2,770.17 | 596.73 | 2,173.44 | 565.35 | 1,608.09 |
| September 2026 (27 Aug – 30 Sep) | 14 | 1,979.51 | 317.63 | 1,661.88 | 886.91 | 774.97 |
| Entire file | 44 | 4,749.68 | 914.36 | 3,835.32 | 1,452.26 | 2,383.06 |

Independent column checks, all matching:

| Check | Value |
|---|---:|
| Subtotal after seller discounts | 5,205.67 |
| Signed refund subtotal | −455.99 |
| Net Revenue | 4,749.68 |
| Signed Total Fees | −914.36 |
| Advertising adjustments | −1,452.26 |
| TikTok exported Total settlement amount | 2,383.06 |

**Total Income (2,383.06) equals TikTok's exported net settlement.** That is a
reconciliation for this file, not a definition — another file containing
transfers, reserves or financing may legitimately differ, and the interface
states the difference rather than inventing an expense to close it.

Totals are **not hardcoded anywhere in application logic**. They live only in
tests, computed from a sanitized fixture.

---

## 8. Historical data

`public.tiktok_settlement_diagnostic(store_id)` is a read-only dry run reporting:

- rows moving between reporting periods under the last-Wednesday rule;
- advertising reclassified from settlement adjustments into Expense;
- missing or invalid settled dates;
- missing revenue/fee data;
- unknown transaction classifications, with the offending type names;
- balance movements now excluded;
- currencies present;
- rows that require reimporting an original settlement file.

It rewrites nothing and invents nothing. Raw imports, original values, versions
and audit history are untouched — the new rules are applied at read time over
retained raw data rather than by rewriting immutable source records.

---

## 9. Deployment order

1. **Apply `supabase/210_tiktok_settlement_periods.sql`** in the SQL editor. Its
   verification block raises if any period, classification or basis is wrong.
2. **Run the diagnostic** per store and read it before trusting any figure:
   `select public.tiktok_settlement_diagnostic(null);`
3. **Deploy the frontend.**

Order matters: the pages call `tiktok_settlement_totals`, so deploying the
frontend first shows an error where the figures should be.

### Why the migration drops three functions before creating them

`report_tiktok_settlement`, `report_tiktok_settlement_daily` and
`report_tiktok_settlement_by_store` already exist, from migrations 66 and 67.
This migration changes what they return — a `finance_category` column on the
first, `expense` and `income` on the other two — and PostgreSQL will not let
`create or replace` change a function's output columns:

```
ERROR:  42P13: cannot change return type of existing function
DETAIL:  Row type defined by OUT parameters is different.
HINT:  Use DROP FUNCTION report_tiktok_settlement(uuid,date,date) first.
```

So each one is dropped first. This is safe here and worth stating plainly,
because dropping a function is not always safe: nothing else in the schema
references these three — no view, function, trigger or policy — and the
`grant execute ... to authenticated` for all three is reissued at the end of
the same file, so the permissions a drop would otherwise discard come straight
back. The only callers are the two frontend pages, which is why the frontend
deploys after the migration and not before.

`report_tiktok_settlement_daily` is dropped in both its shapes: the
4-argument form from migration 67 that carried the `p_basis` toggle, and the
3-argument form this migration installs. Dropping the second is what makes the
file safe to run twice.

### Rollback

Migration 210 is additive except for the report-basis change, so rollback is:

```sql
-- The same restriction applies in reverse: migrations 66 and 67 cannot simply
-- be re-run over these, or they hit the identical 42P13. Drop first.
drop function if exists public.report_tiktok_settlement(uuid,date,date);
drop function if exists public.report_tiktok_settlement_daily(uuid,date,date);
drop function if exists public.report_tiktok_settlement_by_store(date,date);

-- Then re-run migrations 66 and 67 to restore the created-date basis, and drop
-- the objects this migration introduced:
drop function if exists public.tiktok_settlement_totals(integer,integer,uuid);
drop function if exists public.tiktok_settlement_daily(integer,integer,uuid);
drop function if exists public.tiktok_settlement_diagnostic(uuid);
drop function if exists public.tiktok_settlement_eligible(uuid);
drop function if exists public.tiktok_reporting_month(timestamptz);
drop function if exists public.tiktok_settlement_period_range(integer,integer);
drop function if exists public.tiktok_settlement_period(integer,integer);
drop function if exists public.tiktok_last_wednesday(integer,integer);
drop function if exists public.tiktok_finance_category(text,numeric);
```

With the three drops above done first, re-running migrations 66 and 67 restores
`report_tiktok_settlement`, `report_tiktok_settlement_daily` (with `p_basis`)
and `report_tiktok_settlement_by_store` to their previous definitions. The
frontend must be rolled back in the same change, since it no longer passes
`p_basis` and reads `expense`/`income` columns that the old functions do not
return.

**No data is written by any of this**, so a rollback loses nothing but the
figures themselves.
