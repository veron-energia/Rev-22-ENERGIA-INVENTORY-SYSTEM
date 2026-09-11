# Affiliate payouts and invoice controls — setup and recovery

Prepared from baseline `d3738d5`. No production database was read or changed, and no application deployment, commit or push was performed. Existing unrelated files and the committed Stock History work remain intact.

## Changes

- `Record payout` accepts part of an affiliate/month balance. The summary shows positive earned commission, signed adjustments, effective payments and remaining payable. Negative balances are shown as overpaid adjustments; months requiring evidence review cannot be paid.
- Owners and Managers can correct payment amount, method, Singapore payment date, reference and notes. A reason and expected record version are required. Affiliate/month remain fixed. Original values, every revision, actor, timestamp and allocation changes are retained. Editing records does not transfer or recover money.
- A searchable payment-method control uses active supported methods. An existing inactive method can remain on its historical record, with its saved name. Customer wallet-credit methods cannot be selected for new payouts.
- Invoice `Refund / Cancel` is red, with hover/focus/disabled styles. Its chooser shows invoice identity, status, funds still held and refunds, explains unavailable choices, and opens the existing protected workflows. Escape, focus containment and return to the originating button are supported.
- The shared selector accepts exact selling-price searches, including `72`, `72.00`, `$72`, `S$72`, spaces, grouping commas and cents. Exact matches rank ahead of text matches; numeric codes still work. Only invoice catalogue options opt into price matching. Products, vouchers, promotions, sessions, therapy packages, credit packages, premium bundles, special products and available rental rates are covered. Credit face value and internal cost are excluded. Store changes refresh searchable prices. Searching does not change saved invoice prices, FOC data or component selections.

## Accounting model

`commission_payout_allocations` stores signed, append-only allocation events. New money is allocated to the oldest eligible positive entry by invoice paid date, creation timestamp and commission UUID, and can partially pay that entry. Negative commission adjustments reduce the month cap; they are never paid as new positive commissions. Active adjustments against an original entry also remove its reversed portion from eligibility for new payments.

A reduction appends releases against that payout's most recent allocations. An increase consumes only the extra available balance. A metadata-only correction adds no allocation events. Other payouts remain intact. All amounts use existing `numeric(12,2)` values; the API rejects non-positive, non-finite or over-precision amounts before storing them.

Once a commission has been allocated, its existing `status='paid'` and `payout_id` become a **historical anchor**. The original commission amount and IDs remain unchanged. These fields no longer mean that its entire amount has been paid. This is necessary for the existing invoice reconciliation functions to retain paid history and add their separate linked adjustments. Allocation sums measure payment; the monthly balance is active economic earnings plus adjustments minus active effective payout totals. Do not build new balances from `status='earned'` alone or rewrite an anchor after a release.

The existing earning/rate calculations and staff payouts are unchanged. Affiliate summary/history, exports, directories and portal reports use the allocation/effective-payment model. Portal purchase totals also exclude superseded reversal rows. Existing paid commission offsets remain separate; repeated invoice recalculation does not accumulate them.

Payout operations and commission writes share a transaction advisory lock. The payout writer never locks invoice rows, avoiding the opposite invoice/commission lock order. This deliberately serializes affiliate payout/earning writes across affiliates. Expected versions prevent lost corrections; request UUIDs deduplicate both payments and edits. A UUID reused with different details or by another actor is rejected. Direct authenticated table writes and calls to private helpers are revoked.

The old `create_commission_payout` signature remains only to return an actionable refresh message. It cannot bypass the amount/date/request validation with an old full-payment client. New callers must use `record_affiliate_payout` or `correct_affiliate_payout` and retain their request UUID on retries.

The interface closes a confirmed save before refreshing. If refresh fails, it retains the saved payout ID and disables further payment edits/creation until refreshed. An uncertain save keeps the same request and freezes its details; `Retry same save` recovers the original result. A pending request is kept in this browser tab's session storage when available, including across reloads. Do not clear a pending request and manually re-enter the payment without checking its history.

## Name lookup diagnosis

The repository's migration 201 defines `public.commission_referrer_names(p_ids uuid[])`, matching the caller. The previous frontend discarded that RPC's error, leaving a dash when ordinary customer RLS could not return a historical customer. The reported PGRST202 indicates the API could not resolve that signature in its schema cache. The repository alone cannot establish whether the running database missed migration 201 or its API cache was stale; that remains a deployment verification item.

Migration 281 recreates the exact function and argument signature, grants authenticated execution, denies anonymous execution, and notifies PostgREST to reload its schema. It checks an active, non-deleted Owner/Manager/Admin profile and returns only requested identities referenced by commissions or payouts. It can read the existing inactive or soft-deleted customer row within that scope. It does not guess names or broaden ordinary customer-table access. The page keeps affected financial rows, displays `Name unavailable · <ID prefix>` when needed, retains the full ID in exports and row tooltips, and provides a visible retry action for lookup failures.

## Migration order and historical review

Prerequisite: the current project schema through migration 272, including the existing customer/profile/payment-method and invoice accounting migrations. Use a backup and a staging copy of the actual target database first. Do not rerun `00_complete_setup.sql`, `UPGRADE_to_current.sql`, or the test bootstrap against an existing business database.

New migrations, in order:

1. `supabase/280_affiliate_payout_allocations.sql`: original payout snapshots, Singapore payment dates, method names, allocation/operation/audit tables, serialization and evidence-based legacy backfill.
2. `supabase/281_affiliate_payout_api.sql`: transactional record/correct/read/history APIs, access controls and name lookup/cache notification.
3. `supabase/282_affiliate_payout_reports.sql`: allocation-aware affiliate reports and portal totals.

Use the generated **single transaction** for this release so an error in any migration rolls back all three. The builder only prints SQL; it never connects to a database:

```sh
python3 scripts/commissions/build-migration-bundle.py > /tmp/energia-payout-280-282.sql
```

Before installation, export the read-only legacy preflight report using a database-owner connection to the staging copy (and, later, the authorized target). `REVIEW_DATABASE_URL` must be deliberately chosen by the operator:

```sh
psql "$REVIEW_DATABASE_URL" -X -qAt -v ON_ERROR_STOP=1 \
  -f scripts/commissions/review-payouts.sql > payout-review-before.json
```

That script refuses a database already using the allocation ledger. After installation, use `review-payouts-after.sql` instead.

Backfill accepts only explicit `commissions.payout_id` evidence with the same affiliate/month, paid status and exact total/Tier 1/Tier 2 reconciliation. Verified old negative adjustment allocations are preserved as signed historical evidence. Every original payout is snapshotted. No name/date proximity matching, inferred invoice assignment or deletion is used. Missing links, mismatched months/affiliates, orphan paid entries and inconsistent totals are flagged. Both the parent payout's month and an incorrectly linked commission's own month are blocked when necessary. Missing commission dates require review. Metadata on an active historical payout can be corrected while its amount remains fixed.

After reviewing the preflight report, schedule a brief maintenance window for commission-affecting writes. Apply the generated bundle with `ON_ERROR_STOP`, then update the application in the same release window and require older tabs to reload. These are deployment instructions only; they have **not** been executed against production:

```sh
psql "$REVIEW_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f /tmp/energia-payout-280-282.sql
psql "$REVIEW_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f scripts/commissions/verify-install.sql
psql "$REVIEW_DATABASE_URL" -X -qAt -v ON_ERROR_STOP=1 \
  -f scripts/commissions/review-payouts-after.sql > payout-review-after.json
```

The bundle has a 15-second lock timeout; a busy system fails without partial changes. Review any failure and retry the whole bundle only after confirming it rolled back. Once committed, record all three migration filenames in your deployment log and do not apply them again.

## Verification on the target

- `verify-install.sql` should show all six named RPC signatures, including `commission_referrer_names(uuid[])` with input `p_ids`. Authenticated execute should be true; anonymous execute false. Private writer execute and direct payout/allocation table writes should be false. The commission serialization trigger must be enabled.
- The post-install JSON report's `allocation_total_mismatches` must be empty for verified payouts. Investigate review/negative-balance lists; do not erase historical payouts to make them disappear.
- In the browser, sign in with an active Owner/Manager/Admin. A read-only `commission_referrer_names` call with `{ "p_ids": [] }` must return an empty array rather than PGRST202. Check a known permitted active and historical customer ID. Inspect the Network tab's URL and payload to ensure this application is pointing to the intended Supabase project. Staff and anonymous calls must be denied.
- If the exact function and grants exist but PGRST202 persists, run `NOTIFY pgrst, 'reload schema';` in that database, wait for the API reload, then retry. Confirm the exposed API schema is `public`. If multiple conflicting overloads exist, review them explicitly; do not drop unknown business functions speculatively.
- On staging only, verify 300 → 150 paid / 150 remaining, correction to 100 → 200 remaining, and another 200 → zero. Check correction history, effective date filters and export totals. Opening an invoice chooser must issue no financial mutation.

No production names, payout conflicts or schema-cache state were examined in this task. Actual unresolved historical records must be identified by the target's preflight report.

## Manual resolution and recovery

For each review record, obtain the original payment evidence and the original commission/invoice links. Compare affiliate, commission month, tier, amount and any invoice reversal. Keep the original snapshot and explain the resolution in an auditable follow-up migration. Do not simply set `allocation_state='verified'`, fabricate allocations, merge identities, or change the payout amount to make a total match. The release deliberately provides no automatic historical repair action. Continue unrelated work or correct metadata while the financial issue is reviewed.

A negative balance after a refund/cancellation can be valid: cash already paid exceeds current entitlement. It is shown separately and creates no new payable amount. A correction may reduce a mistaken recorded payment, but it does not claim that money was recovered.

If installation fails before the bundle commits, PostgreSQL rolls it back; retain the error and retry after fixing the cause. If the bundle committed but application verification fails, pause payout writes and keep the financial tables/audits intact while correcting the deployment. For an emergency pause, a database owner can revoke authenticated EXECUTE on the two new write RPCs (and the already-disabled legacy RPC); restore only the intended grants from migration 281 after verification.

After any new payment, correction or invoice adjustment, **do not drop the new tables or restore the old paid/unpaid functions**. Doing so loses partial-payment evidence and makes old screens misleading. Prefer a reviewed forward fix. A pre-release database restore is safe only when no post-backup business writes have occurred, or after those writes have been explicitly reconciled and preserved. A frontend rollback alone must keep commission payout screens unavailable until the allocation-aware client is restored. Other financial records and linked invoices must not be removed as a rollback shortcut.

## Local test setup and results

All writes used the dedicated `.commission-test/data` PostgreSQL cluster, Unix socket `/tmp`, port 55444, database `energia_commission_test`. Other project test clusters were left untouched. If creating it on another workstation:

```sh
mkdir -p .commission-test
printf '*\n' > .commission-test/.gitignore
initdb -D .commission-test/data -U postgres -A trust
pg_ctl -D .commission-test/data -l .commission-test/postgres.log \
  -o "-p 55444 -k /tmp -h 127.0.0.1" start
createdb -h /tmp -p 55444 -U postgres energia_commission_test
```

Use this fixture only for synthetic data. The runner checks the exact database, host, port and project-owned server data directory before rebuilding its schema:

```sh
scripts/commissions/tests/run-local.sh
node --test scripts/commissions/tests/presentation.test.mjs
node scripts/commissions/tests/browser.mjs
node scripts/commissions/tests/invoice-price-browser.mjs
node scripts/invoices/tests/invoice-actions-browser.mjs
npm run typecheck
npm run build
```

After testing, stop this dedicated server with `pg_ctl -D .commission-test/data -m fast stop`. Its data remains available for review; restart it with the `pg_ctl ... start` command above, without running `initdb` again. The fixture was stopped after this task’s checks.

Browser scripts use `esbuild` and Playwright, with `PLAYWRIGHT_MODULE` and `CHROME_EXECUTABLE` overrides for workstation paths. They intercept all application requests and use synthetic fixtures; they do not sign into a live application. The tested host used Node 25.1.0; the project specifies Node 22.x, which should also be used in the deployment pipeline.

Completed checks:

- Strict replay of 197 preceding migrations, followed by the atomic three-migration release bundle: passed.
- Historical fixture: 2 payouts, 1 verified, 1 requiring review; 2 orphan/mismatched commission entries affecting 3 review months; zero allocation-total mismatches for verified payouts. These counts are **synthetic test results**, not production findings. JSON reports and install verification are under `.commission-test/` and are intentionally ignored by Git.
- Payout SQL checks: partial entries, separate payouts, deterministic cross-tier allocation, signed adjustments, upward/downward/metadata corrections, subsequent payments, amount/date/method validation, replay, stale versions, originals/audits, historical names, role checks and direct-write denial: passed.
- Real independent sessions: six simultaneous S$100 requests against S$300 produced exactly three successes. Duplicate payment/edit retries created one operation; concurrent conflicting edits allowed one version; adjustment/payment races retained consistent balances: passed.
- Actual invoice payment/refund/correction/cancellation and repeated commission reconciliation after partial/full payouts, plus affiliate portal totals: passed. Existing invoice regression and commission-refund-basis suites also passed, including stock, credit, FOC, historical prices and payment retries.
- Payout browser checks: name failure/retry, searchable methods, Singapore date default, partial/corrected summaries, history, date filters, confirmed-save/failed-refresh recovery, uncertain-save retry, and mobile form: passed.
- Invoice browser: 116 existing action checks at 375px/320px, plus 45 price/store/historical-price/FOC/red-chooser checks: passed. Four currency/search/export unit tests passed.
- TypeScript and application build passed. Vite retains its existing large-bundle warning; this release does not change application bundling.

## Changed source files

Application: `src/pages/CommissionsPage.tsx`, `src/components/commissions/AffiliatePayoutPanel.tsx`, `src/lib/affiliatePayoutPresentation.ts`, `src/lib/cataloguePriceSearch.ts`, `src/components/SearchSelect.tsx`, `src/pages/InvoicesPage.tsx`, `src/components/invoices/InvoiceRefundCancelChooser.tsx`, and `src/components/invoices/invoice-controls.css`.

Database: new migrations 280, 281 and 282. No previously deployed migration was edited.

Tooling and documentation: `.gitignore` excludes the disposable fixture; `scripts/commissions/` (bootstrap, atomic bundle builder, read-only review/install checks and focused tests), the updated chooser label in `scripts/invoices/tests/invoice-actions-browser.mjs`, this guide and `docs/COMMISSION_PAYOUT_COORDINATION.md`.
