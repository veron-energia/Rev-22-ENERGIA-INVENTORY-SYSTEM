# Coordination note — Agent Two (TikTok settlement periods and financials)

Scope: TikTok settlement imports and classification, TikTok reporting periods,
and TikTok revenue / fee / settlement / expense / income figures, plus the
related report tables, filters, exports, reconciliation and tests.

**Not touched:** invoices, payments, refunds, the invoice sales-date rules, the
dashboard's invoice figures, or anything in the customer-phone, health-survey,
Auth-email, Xero or commission work.

## Migration number

Agent one's invoice series is at **184**. My earlier work took 200 and 201.
This work takes **210**, leaving 185–199 free for the invoice series to keep
growing and 202–209 clear as well.

- `supabase/210_tiktok_settlement_periods.sql` — new functions only. It adds no
  column to an existing table and changes no existing function that anything
  outside TikTok calls.

## Files I own / create

- `src/lib/tiktok/settlementPeriod.mjs` + `.d.mts` — the last-Wednesday period
  rule, shared by the two pages and mirrored by the migration.
- `src/lib/tiktok/classification.mjs` + `.d.mts` — financial category per
  transaction, and the money arithmetic (integer cents).
- `scripts/tiktok/tests/*.test.mjs` — period, classification and totals tests
  against a **sanitized** fixture, not the user's private export.
- `scripts/tiktok/tests/prior-state.sql` — the database as migration 210 finds
  it: a reduced schema plus the three report functions copied verbatim from
  migrations 66 and 67. Added after the migration failed on the real database
  with `42P13: cannot change return type of existing function`, which the tests
  had missed by applying 210 to a database where those functions had never
  existed. It contains no production data.
- `supabase/210_tiktok_settlement_periods.sql`.
- `TIKTOK_SETTLEMENT_MAPPING.md` — field mapping, classification and evidence.

## Shared files — please review before editing the same lines

| File | My change | Overlap risk |
|---|---|---|
| `src/pages/TikTokImportPage.tsx` | period selector, summary cards, preview detail | **None** — clean in the working tree, no agent-one changes |
| `src/pages/ReportsPage.tsx` | the TikTok section only | **Low** — agent one has 29 insertions here, and their diff contains **zero** TikTok mentions, so we are in disjoint regions of the file |
| `package.json` | one script: `test:tiktok` | scripts block only, no dependency change |

If `ReportsPage.tsx` needs committing while agent one is still mid-edit, stage
per-hunk (`git diff -U0`, drop hunks belonging to the other agent, then
`git apply --cached --unidiff-zero`) rather than committing the whole file —
the same approach used for `XeroExport.tsx`.

## Deliberately NOT changed

- `public.tiktok_txn_class` — still returns its existing four values, because
  migration 66's constraint and existing rows depend on them. The richer
  financial category is a **new, separate** function layered on top rather than a
  redefinition of the old one.
- Stock and the order lifecycle. Settlement processing moves no inventory;
  `tiktok_adjust_product_stock` / `tiktok_adjust_voucher_stock` are untouched.
- The order import (`tiktok_order_rows`) and its operational figures.
- Invoice reporting functions, including agent one's `183_invoice_reporting_consumers`.

## Isolated test database

Port **55442**, database `energia_auth_email_test` (already used by my earlier
work; reused rather than adding a third cluster). Agent one's is 55441 and is
untouched. No production database is contacted.

## Source files read, not modified

`~/Downloads/income_20260908180508(UTC+8).xlsx` and
`~/Downloads/All order-2026-09-08-12_03 (1).xlsx` are read-only references. The
committed fixture is sanitized; the user's full export is not committed.
