# Stock History and shared transfer notes

Implementation is local only. No production database, inventory quantity, deployment, commit or push was performed. Existing invoice/therapy work, including the later `a83f7ba` invoice fix, is preserved.

## Access and reporting behavior

Stock History is available in staff navigation. An active, non-deleted staff member sees movements involving **any currently assigned store**, regardless of who recorded them. Assignment removal takes effect on the next request. No assignment produces an access message and empty records, choices and counts. Owner, Admin, Manager and Inventory Manager retain global reporting access.

Database policies and checked reporting functions enforce the scope. A permitted movement can include its counterpart's name, but summary rows contain only authorized locations. Source staff on a split transfer see their source allocations and quantities; the complete aggregate line is withheld from the raw table API. Destination staff can see the incoming transfer's lines. Shared notes require access to that transfer, and line notes require access to that line. Complete profile records, audit payloads and revision snapshots are not sent to staff to populate this feature.

Legacy inventory availability, sourcing, transfer-report and alert endpoints are also scoped. Existing authorized sourced-request creation and editing still use private stock validation; an error does not disclose an unauthorized source balance. Existing approval/receipt/stock mutation checks remain in place. Direct writes to transfer tables are closed; the application already performs those actions through its authorized audited functions.

The **History** tab retains Date, Type, Product/SKU, Movement, Quantity, By and Notes. Transfer rows with an exact stored request link open the shared details. Search includes product name/SKU, both location names, recorded-by name, raw/readable type, notes, quantity, `DD/MM/YYYY` and `YYYY-MM-DD`. Matching is a literal, case-insensitive substring, including older records beyond 5,000 rows.

Products, Locations, Recorded by and Movement type have searchable multi-select lists, individual removal chips and a visible filter summary. Values within one filter use OR; different filters, search and dates use AND. Locations match either side of a movement, within the authorized scope. Empty selections mean all permitted values. Clear search preserves filters. Clear filters resets selections and the default dates while preserving search. Switching tabs preserves filters. Options are paged in groups of 100 and return only IDs and labels.

History pages contain 100 records, with event time and unique movement ID determining stable order. Table pages contain 100 product/location rows. Counts are calculated before paging. A captured cutoff persists while paging; Refresh, filter changes or tab changes establish a new cutoff. New movement record times prevent later backdated document entries entering an earlier cutoff. Access is rechecked for every request.

Both exports fetch the full permitted matching result set in pages of up to 1,000, using a common cutoff. They reject failed, missing, duplicate or changed-count pages instead of writing a partial workbook. Date/timezone, filter context, balance definitions and warnings accompany the rows. Untrusted text is forced to text, including formula-like values. This is not a long-lived database transaction: edits to existing records or assignments during export require refreshing; do not use a concurrently changing export as a closed accounting snapshot.

## Balance definitions

The initial range is the current **Singapore calendar month through today**. Boundaries use `Asia/Singapore`: opening is immediately before the start date; closing is immediately before the next day begins, or the captured report time for today.

The Table tab has a section per product/SKU and one row per permitted selected location. All stock quantities are product units. Different products are never added into one quantity.

Migration 271 locks inventory and movements while it records the existing inventory values as a baseline and installs inventory observation triggers. This is an observation of the system's stock, not a physical stocktake. It **does not update inventory quantities**. Later committed inventory changes append their before/after values, delta, actual observation time, actor and transaction ID. A missing row in the complete initial inventory snapshot represents zero at that snapshot, rather than an assumption based on the first movement.

For date boundaries after observation begins, actual balances are baseline plus all observed deltas up to the boundary. This includes existing sale, return, cancellation, correction, reopening, stock-use, transfer and adjustment writers, including writers without a complete historical movement trail. Rollbacks roll back their observations too.

Without search/person/type filters, inbound and outbound use observed positive and negative stock changes after the baseline, plus identifiable older movement effects for the portion before observation began. A fully evidenced period reconciles as:

`Actual opening + inbound - outbound = actual closing`

When search, person or type filters are active, inbound/outbound use only the matching movement effects. Opening/closing still use all actual inventory observations. **Other movement net** explains the excluded effects; it is unknown when the opening cannot be established. Product/location filters choose summary rows; they do not turn a filtered movement sum into a balance.

Dispatch deducts only its source; the destination is descriptive until a separate receipt. Receipt adds only the quantity actually received. Discrepancy corrections follow their existing writer's source/destination effect, including acknowledgement-only resolutions that change no stock. Sales/stock use are outbound. Only confirmed sellable invoice returns are inbound; damaged and not-returned quantities remain excluded. Cancellation/reopening/correction regression tests verify existing behavior is preserved.

Incoming and outgoing In Transit are separate, excluded from sellable closing stock, and are determined as of the selected end. Exactly linked dispatch legs remain in transit until the request's receipt is confirmed, even when the eventual receipt occurred in a later period. Receipt discrepancies are reported separately; they do not keep the whole received transfer in transit. Unlinked old dispatches cause a warning: the known linked transit total may be incomplete. Duplicate dispatch/receipt links are diagnostic review items, never automatically repaired.

New stock movements have a separate actual record timestamp. Existing `created_at` values are not rewritten. Legacy records retain their original event times. This avoids interpreting a new stock effect using an old document/transaction start date.

## Historical limitations and review

Opening/closing boundaries **before migration 271's observation start are Unknown** unless a separately verified historical baseline is implemented later. In particular, the first month's opening normally remains unknown after deployment; this is intentional. Known movement totals remain available with the warning. No first-movement zero balance or synthetic historical snapshot is created.

If current inventory no longer equals the baseline plus recorded observations, affected actual balances become Unknown. This can indicate a disabled trigger, privileged manual changes or missing evidence. Movement-to-observation differences also display a review warning, including missing or duplicated movement effects. Reporting does not adjust inventory to make an equation reconcile.

Run `scripts/stock-history/diagnose.sql` using an approved **read-only operator connection**, preferably on a secured restored snapshot after the new migrations. It runs inside a read-only transaction and reports:

- Observation start and historical periods lacking opening evidence.
- Current inventory versus baseline plus observed deltas.
- Observed deltas versus identifiable movement effects.
- Unresolved transfer discrepancies.
- Unlinked transfer effects and invoice returns without original sale links.
- Repeated dispatch/receipt links requiring review.

The diagnostic contains operational record IDs. Keep its output with the private deployment review. There is no production diagnostic result in this delivery: only the isolated fixture was examined. Historical gaps and conflicts must be reviewed against independent records; this task provides no automatic repair or data cleanup.

## Transfer notes

The same read-only chronological history is shown in expanded transfer details, Review, Receive, Resolve and Edit dialogs, and from Stock History's transfer link. It includes request text, dispatch/approval reasons, receipt text, per-line receipt discrepancy reasons, rejection, resolution and relevant edit reasons/new text. Entries show the stored author and time in Singapore time, with product context on line entries.

Audit entries take precedence over dedicated fields/revision copies to avoid duplicate notes. A receipt's original per-line reason is recovered from its receipt audit even after a later resolution replaces the line's current reason. The earliest revision snapshot can preserve original request text. Missing attribution is labeled **Author unavailable** or **Time unavailable**; it is not guessed. Historical movement notes remain on their movement rows. An old movement without an exact transfer link is not automatically matched to a request by product/date/quantity.

The feature adds no messaging or historical-note editing permission. Original audit records, invoices and transfer relationships remain intact.

## Manual deployment order

1. Back up the database/schema, including current function definitions, policies and grants. Record the installed migration range. This implementation was verified against the repository history through 257 (including migration 160's sourcing-column fix), then 270–272. Do not rerun older migrations over a live schema merely to match that list.
2. Restore the backup into an isolated staging database. Apply these new migrations **in this order**, stopping on any error:
   - `supabase/270_stock_history_access_and_transfer_notes.sql`
   - `supabase/271_stock_history_search_and_balances.sql`
   - `supabase/272_stock_history_reporting_safeguards.sql`
3. Run the read-only diagnostic on staging. Review the historical warnings and verify representative assigned staff, multiple assignments, no assignment, split source and destination roles. Compare a current summary with existing inventory without changing either. Migration 272 also fixes the existing migration-159 integrity report's untyped UNION-null mismatch so that report can execute.
4. Run the tests/build below against an isolated fixture. Confirm database availability for the maintenance window: baseline capture and index creation lock tables, and the initial baseline should not race application writes. Ensure deployment roles can create the observation tables, triggers, policies and functions.
5. In the separately approved deployment window, pause application writes, apply 270 → 271 → 272, verify all three succeeded and the API schema cache reloaded, then release the matching application build. Each file is transactional; a failed file rolls back its own changes. Keep maintenance mode until all files and the matching application are ready. The new frontend requires the new reporting endpoints.
6. Re-enable writes. Check an ordinary transfer review/receipt and both Stock History tabs using real authorized test accounts. Verify source-only split details, no-assignment behavior, full exports, shared notes and displayed observation start/warnings. Run the read-only diagnostic again. Investigate findings without automated stock adjustments.

These are instructions for a future deployment; none were run against production here.

## Rollback

Prefer an application rollback while keeping the new database read restrictions and observation journal. Remove/revert only the feature's three application edits and new stock-history components using the saved pre-release version. Do not overwrite unrelated invoice/therapy commits or use a repository-wide reset. The older management Stock History page remains usable; staff navigation can be removed while the feature is unavailable.

Keep `stock_history_observation`, `stock_history_baselines`, `stock_history_inventory_changes`, their triggers and `stock_history_recorded_at`. Dropping or clearing them destroys evidence accumulated since deployment. They do not change the quantities held in inventory. Keep the new access restrictions unless a reviewed rollback explicitly restores the previous permissions; the previous warehouse/transfer endpoints were broader.

If database code must also be rolled back, use the **pre-deployment schema backup** to prepare a reviewed transaction restoring only the changed existing definitions and their original grants/policies:

- `location_available_qty` (four-argument implementation), `transfer_request_sourcing`, `transfer_product_sourcing`, `transfer_revisions`, `search_stock_movements`.
- `transfer_receipt_alerts`, `report_transfers_in_transit`, `report_transfer_discrepancies`, `report_multi_source_stock_drift`, `report_transfer_stock_integrity`, `report_transfer_receipts`, `report_transfers_overdue`.
- The text-argument `create_transfer_request` and current nine-argument `edit_transfer_request` definitions.
- The additional `stock_history_*` SELECT policies on stock movements, inventory and transfer tables, and the transfer-table DML grants revoked in 270.

Restore exact saved signatures rather than replacing every overload or replaying complete older migrations. Renamed `stock_private_*` functions are implementation copies and remain non-callable by application roles; remove them only after checking dependencies. New report functions may remain unused and private observation data should remain preserved. Validate the rollback on the restored staging database first, then run invoice/transfer regressions. Never restore old inventory quantities or erase audit/history records as a reporting rollback.

## Verification and repeatable local tests

The tests use **only** `.stock-history-test/data`, Unix socket `/tmp`, port `55443`, database `energia_stock_history_test`. The bootstrap checks the exact data directory and refuses any other target. It rebuilds this disposable schema and stops at the first failing migration. Do not point this bootstrap at a deployed database.

On a new developer machine with PostgreSQL available, create the isolated cluster once (skip initialization if it already exists):

```sh
mkdir -p .stock-history-test
initdb -D .stock-history-test/data -U postgres --auth=trust
pg_ctl -D .stock-history-test/data -l .stock-history-test/postgres.log -o "-k /tmp -p 55443 -c listen_addresses=''" start
createdb -h /tmp -p 55443 -U postgres energia_stock_history_test
PGHOST=/tmp PGPORT=55443 PGUSER=postgres PGDATABASE=energia_stock_history_test python3 scripts/stock-history/bootstrap-local.py
```

Then run from the project root:

```sh
scripts/stock-history/local-sql.sh -f scripts/stock-history/tests/database.sql
scripts/stock-history/local-sql.sh -f scripts/stock-history/tests/lifecycle.sql
scripts/stock-history/local-sql.sh -f supabase/tests/phase57_transfer_review_rework_tests.sql
scripts/stock-history/local-sql.sh -f scripts/invoices/regression.sql
scripts/stock-history/local-sql.sh -f scripts/stock-history/diagnose.sql
node --test scripts/stock-history/tests/report.test.mjs
node scripts/stock-history/tests/browser.mjs
npm run test:customer-phones
npm run test:survey
npm run typecheck
npm run build
```

The browser script runs the real page/components with an offline API fixture and intercepts all network requests. It uses local Playwright and Chrome; `PLAYWRIGHT_MODULE` and `CHROME_EXECUTABLE` can override their paths. SQL tests exercise the actual PostgreSQL role and effective migration functions, not an API mock. Fixtures roll back. Screenshots/logs stay under `.stock-history-test`; keep that folder ignored and private.

See `STOCK_HISTORY_TEST_RESULTS.md` for final results and remaining verification limits. Stop the disposable server when finished with `pg_ctl -D .stock-history-test/data stop`.

## Changed files

- Existing application files: `src/components/AppLayout.tsx`, `src/pages/StockMovementsPage.tsx`, `src/pages/TransfersPage.tsx`, `src/components/ExcelExport.tsx` (visible export failure handling).
- New components/helpers/styles: `src/components/stock-history/StockHistoryFilter.tsx`, `TransferNoteHistory.tsx`, `report.ts`, `stock-history.css`.
- Database migrations: the three 270–272 files listed above.
- Diagnostic/fixture tooling: `scripts/stock-history/diagnose.sql`, `bootstrap-local.py`, `local-sql.sh`.
- Tests: `scripts/stock-history/tests/database.sql`, `lifecycle.sql`, `report.test.mjs`, `browser.mjs`.
- Documentation: `docs/STOCK_HISTORY_COORDINATION.md`, this guide and `docs/STOCK_HISTORY_TEST_RESULTS.md`.

The existing workbook layout, financial/therapy implementation, earlier migrations and other untracked reports are preserved. The shared export button now catches a failed full-report request and shows its error rather than leaving a rejected promise without a user-facing explanation.
