# Affiliate commission: production was running the wrong function

**Reported as:** the affiliate put on INV-2026-0222 did not earn anything.

**Actual fault:** production's `earn_invoice_commission` is the 5D2-era body from
migration file 19, not the current one. Everything around it is current.

## What the old build does

| Rule | Old build (file 19) | Current build |
| --- | --- | --- |
| Who is tier 1 | always the buyer's profile referrer | the affiliate selected on the invoice, else the referrer |
| Explicit "None" on the invoice | ignored; referrer still paid | nothing earned |
| Person not an activated affiliate | paid as `earned` | row kept but `blocked` with a reason, never paid |
| Rates | fixed 15 / 4.5 / 5 | `app_settings` (tier 2 is 35 on production) |
| Wallet-funded value, `no_commission` products, package lines | commissioned | excluded |
| Discounts | prorated from `discount_total` | line discounts first, invoice-level share after |

INV-2026-0222 hit the first row: Mariam has no referrer, so the old build
returned before looking at the affiliate the correction had just set. The
correction itself worked (audit `invoice_corrected`, revision 1, staff
commission re-earned); only the affiliate half was computed by the wrong code.

## How it was found

- `pg_get_functiondef` on production vs three independent local builds of the
  repository (Docker PG 17, the integration cluster, and a clean bootstrap of
  all 244 migrations on the commission fixture). All three agree with each
  other; production differs on exactly five functions in the commission path
  and on nothing else around it (24 helpers hash-identical).
- Migration 182 patches `earn_invoice_commission` by anchored replace and
  raises `Unexpected affiliate commission definition` when the body is not the
  one it expects. That is what happened on production: 182 never landed, so
  `set_invoice_affiliate`, `invoice_effective_affiliate`,
  `earn_credit_package_commission` and `earn_premium_bundle_commission` are
  also missing its change. 243 and 253 (after it) are present.
- Every one of the 38 commission rows ever written on production is consistent
  with the old build: no `blocked` row, every tier 2 row at 5 %, and the two
  invoices with a selected affiliate whose buyer has no referrer have no rows.
  The old build has been there since the feature went live (first row
  2026-08-06). How file 19's body got there is not recorded anywhere I can
  read; 19 was last edited on 2026-08-21 for an unrelated stock fix.

## The fix

### `supabase/334_commission_functions_reinstalled.sql`

Installs the five functions in full, exactly as the clean build produces them,
then checks the marker each patch left (so a partial apply raises). Idempotent;
a no-op on a database that already has them. Applied to the Docker stack, the
integration cluster and the commission fixture; **not applied to production**.

### `scripts/commissions/reearn-affiliate-commissions.sql`

Walks paid invoices and asks the reinstalled functions what they earn now,
inside a savepoint per invoice:

- same answer → savepoint rolled back, invoice untouched (not even a timestamp);
- different answer → unpaid rows reversed with a reason, new rows written,
  audit row `commission_reearned` with before/after — what a correction on the
  invoice does today;
- commission already paid out or allocated → nothing changed, listed for review.

Dry run by default; `-v apply=yes` commits; `-v only=` / `-v skip=` take
invoice numbers; `-v actor=` attributes the audit rows. Refuses to run on the
old build. Staff commission is never read or written.

### Tests

`npm run test:commission-reinstall` (`scripts/commissions/tests/reinstall-reearn.sh`)
installs file 19's body on the commission fixture, writes fixtures shaped like
the production invoices below, applies 334 twice, then runs the script three
times: rehearsal (must change nothing), real, real again (must find nothing).
Passes on the PG 14 fixture; the same steps were run by hand on the PG 17
Docker stack with identical outcomes. The existing commission,
invoice-adjustment, refund-basis, invoice-correction and invoice regression
suites pass with 334 installed.

## Found on the way: 335, a correction could not add a manual discount

Running the invoice regression suite against 334 exposed a fault in 331
(applied to production on 17 Sep). `correct_invoice` writes the discount
reason in its first update, before the amount changes; on an invoice that had
no manual discount the 331 trigger's "no discount, no reason to keep" branch
clears it right there, and the second update — the one that changes the
amount — is refused with `MANUAL_DISCOUNT_REASON_REQUIRED` even though the
reason was given. Raising an existing discount worked (what 331's test
covered); adding one to an invoice that had none did not.

`supabase/335_correction_can_add_a_manual_discount.sql` makes `correct_invoice`
hand the reason over for the transaction (331's own convention for inserts)
and lets the trigger's update branch accept the hand-off; it is cleared again
straight after. Covered in `scripts/invoice-discounts/tests/manual-discount-reason.sql`;
`scripts/invoices/regression.sql` now sends the reason with its discount
correction. **335 is not applied to production either**; apply it with 334.

## What the re-earn will do on production (from the data as read on 2026-09-18)

Rates as configured now (tier 1 own 15, tier 2 35). The dry run prints the
exact figures; this is the shape.

| Invoice | Now | After |
| --- | --- | --- |
| INV-2026-0222 | nothing | 11.55 earned to Marlinah (Guoco Tower) — the selected affiliate |
| INV-2026-0220 | nothing | 9.15 × 2 earned to Aishah Angullia — selected; buyer's referrer is not an affiliate |
| INV-2026-0227 | 3.30 earned to "Alaric" (not activated, duplicate record) | reversed; 3.30 earned to Alaric Ong — selected |
| INV-2026-0158 | tier 2 5.60 earned to Chiao Hsia Tan at 5 % | tier 2 at 35 %, `blocked` (not activated); tier 1 to Zoe re-created at the same 112.05 + 9.15 |
| INV-2026-0181 | 60.65 + 7.91 earned to "Lynn (Alaric) Tan" (not activated) | reversed; earned to the buyer's current referrer Lynn Jue Li (Apollo) Tan — the records look like the same person twice |
| INV-2026-0167, 0185 | nothing | earned to Aishah Angullia / Felicia Kuek (NEX): the referrer was recorded after payment |
| INV-2026-0101, 0112, 0157 | nothing | `blocked` rows to Chiao Hsia Tan (not activated) — visible, never paid |
| INV-2026-0045 | five rows paid out to Rosa | expected unchanged; if the new math differs by cents it is listed for review, not changed |
| INV-2026-0151, 0215, 0218, 0221, 0233, 0235, EX-…00002 | correct person, same figures | untouched |
| INV-2026-0028 (refunded) | reversed rows | out of scope |

Two of these deserve a decision before applying: 0181 moves money between two
records of one person; 0167 and 0185 pay a referral that was recorded after
the sale. Both are what the system does on any correction today; `-v skip=`
leaves them out if you would rather not.

## Applied to production on 2026-09-18

334 and 335 were applied by the owner. The re-earn was run through the
Supabase SQL tool with the script's exact logic (rehearsal first, then the
real run, actor = the owner profile): 20 invoices looked at, 10 changed, 7
unchanged, 3 left for review (INV-2026-0020, 0027, 0045 — rows already paid
out), no errors. INV-2026-0222 carries 11.55 earned to Marlinah (Guoco
Tower). One `commission_reearned` audit row per changed invoice.

## Steps for production

```bash
psql "$PRODUCTION_URL" -f supabase/334_commission_functions_reinstalled.sql
psql "$PRODUCTION_URL" -f supabase/335_correction_can_add_a_manual_discount.sql
psql "$PRODUCTION_URL" -f scripts/commissions/reearn-affiliate-commissions.sql            # dry run, read it
psql "$PRODUCTION_URL" -v apply=yes -v actor='<owner profile uuid>' -f scripts/commissions/reearn-affiliate-commissions.sql
```

No frontend change is needed. Once 334 is in, the affiliate picker on an
invoice, the correction form's affiliate field, and payment-time earning all
behave as the current code (and its tests) already assume.

### Undo

334 needs no undo: the old body is the fault. A re-earned invoice can be put
back from its `commission_reearned` audit row (before/after are recorded) by
reversing the new rows and clearing `reversed_at` / `reversal_reason` /
`status='earned'` on the old ones — but it should not be needed, since the
script only writes where the current rules give a different answer.

## Other production functions that differ from the repository (not fixed here)

Found by the same hash comparison, outside the commission path. Each needs its
own look before anything is reinstalled — some may be production-only hotfixes
that the repository should adopt rather than overwrite:

- `user_has_store_access`: production grants all stores to `owner, admin`;
  the repository also grants `manager`. Managers on production only see their
  assigned stores.
- `upsert_credit_package`, `upsert_premium_bundle`, `set_invoice_service_staff`
  (the last does not exist in the repository at all).
- `health_survey_detail`, `update_survey_particulars`, `diagnose_survey_name_edit`
  (the last is production-only).
- `confirm_tiktok_settlement_batch`, `stage_tiktok_settlement`, `tiktok_settlement_match`.
- Production-only leftovers: `create_invoice` (7-argument overload),
  `record_document_send` (7-argument overload), `credit_package_price_for`,
  `report_uncorrectable_invoices`.

The local Docker stack and integration cluster also drift from the clean build
in places (`sell_premium_bundle`, `update_invoice_internal`, the tiktok trio,
missing 318 on Docker); production is right on the first two. A clean bootstrap
(`scripts/commissions/bootstrap-local.py`) is the reference to compare against.
