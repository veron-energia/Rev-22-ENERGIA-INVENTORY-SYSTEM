# Historical invoice date recovery

Prepared locally on 11 September 2026. **No production database was read or changed; no commit, push, application deployment, or production recovery was performed.** The completed commission work remains intact, including the user's staged changes.

## Cause confirmed in the repository

Migration `171_invoice_business_metadata.sql` added nullable `invoices.business_date`, then gave **new** invoices a Singapore-today default. It deliberately left historical rows NULL. `displayInvoiceDate` in `src/lib/invoices/business.ts` renders NULL as “Date pending review”. The current invoice query selects `*`, so it does not omit the column.

Before commit `04cc588`, `InvoicesPage.tsx` displayed and exported `created_at` using the browser's locale/timezone. The newer outputs correctly use `business_date`, but the list still searched and sorted by creation time. Migration 176's receipt sales ledger excludes NULL business dates. These changes explain the repository behavior; deployed schema/data and the number of affected real invoices remain unverified.

Normal invoice creation uses the database creation timestamp. The inspected correction paths preserve `created_at`. Exchange conversion in migration 62 explicitly copies the **original exchange creation timestamp** into the new invoice; the recovery planner verifies that link before using its creation-date fallback. No general historical invoice-import path was found in the current application. TikTok imports have an independent settlement model. External/manual imports cannot be ruled out from repository code alone.

The policy below supersedes the older “No historical business date is automatically inferred” paragraph in `INVOICE_DEPLOYMENT_AND_REVIEW.md`, as explicitly requested for this task.

## Files and behavior

- `supabase/290_invoice_date_recovery.sql`: transactional installation of preview, guarded recovery/reversal, version tracking and audit tables. **Installing it does not backfill any business date.** No previously deployed migration was edited.
- `scripts/invoice-dates/diagnose.sql`: pre-install read-only schema/function/trigger and missing-date diagnostics.
- `scripts/invoice-dates/preview.sql`: one row per invoice, counts, proposed dates/sources, conflicts and estimated sales effect in one repeatable-read, read-only snapshot.
- `scripts/invoice-dates/review.py`: turns that JSON into `invoices.csv`, `uncertain.csv`, `eligible.json` and `summary.md`. Optionally prepares separate apply/reverse SQL files; it never connects to a database.
- `reconciliation.sql`, `compare-reconciliation.py`, `report-totals.sql`: operational hashes and separate sales/collection comparisons.
- Application: business-date search, date range, confirmed/pending filter, business-date ordering, complete invoice pagination, visible refresh errors, explicit date in details, and a separately labelled Singapore “Created on” reference for unresolved invoices. PDF, image, printed copies and outgoing message support the separate reference. Excel uses date-only comparisons and Singapore date shortcuts.

Existing Edit Invoice/Correct Invoice permissions, required correction reasons, instalments, saved prices, invoice IDs, customers, payments, benefits and commission/payout features remain in place. The UI never guesses a business date. New invoices still default to Singapore today and retain a selected backdate. Refresh the list and reopen details after recovery; a stale editor is rejected by the existing `expected_edit_count` check.

## Recovery decisions

1. Preserve **every non-null business date**, including backdated dates. These rows are classified `already_valid` and are never updated by recovery.
2. Prefer consistent explicit `business_date` evidence in invoice audit/revision headers. A reliably ordered intentional correction takes precedence over earlier dates. Full audit header copies matching exactly one revision use that revision's sequence; unmatched conflicting records with indistinguishable ordering remain manual.
3. If no authoritative business date survives, use the original creation timestamp's **Asia/Singapore calendar date**, provided there is no evidence of import-time substitution, backdating, changed creation timestamps, or an unsupported original-date field. Date-only business values are parsed directly, without timezone conversion.
4. Unsupported/invalid dates, non-finite or zone-less creation timestamps, conflicting records, later explicit date clearing, incomplete later edit snapshots, and unverified exchange timestamps stay `manual_review` with a NULL business date. The preview includes suggestions where possible, observed business dates, and reasons; a suggestion is not authorization to save it.

The known provenance fields checked are `notes`, `source`, `origin`, `imported_at`, `import_batch_id`, `original_invoice_date`, `original_created_at` and `invoice_date`, plus audit action/module/reason and invoice header snapshots. Import/backdating markers cause review rather than assuming an import timestamp is original. An explicit, unambiguous business date can still resolve an imported invoice. Unknown custom provenance outside this schema must be inspected before approving fallback rows. Absence of an import marker is not proof that no outside import ever happened.

The planner does not use today, `updated_at`, `paid_at`, payment dates, or invoice-number patterns as recovery sources. A later payment by itself is normal and does not make a date ambiguous. Paid, unpaid, partially paid, refunded, cancelled, draft and FOC records use the same date-only path. Deleted invoices can be reviewed/recovered, but remain excluded from ordinary invoice listings and sales.

## Safety and audit

Only active, non-deleted Owners/Managers can preview, recover or reverse, subject to existing store access. The internal collector/planner/writer are not callable by `authenticated` or `anon`. Recovery/audit tables allow no direct client writes.

Apply accepts 1–500 distinct invoice IDs and their reviewed date/hash. It locks each invoice in deterministic order, re-reads evidence, checks eligibility and preserves any date now present. Changed evidence/proposals are skipped for a fresh review. The hash is a staleness token, not an authorization mechanism. Invoice audit/revision writes share the parent invoice lock, so evidence cannot change between the final read and date update. Batches serialize by their unique ID; the same request returns its original result. Reusing an ID with different arguments is rejected. Unexpected errors roll back that entire batch; reported skips can coexist with successful eligible rows in a completed batch.

The writer updates only `business_date` and established edit metadata (`edit_count`, `edited_by`, `edited_at`). A trigger increments `business_date_version` only when the date actually changes. It records old/new dates, evidence/hash/source, reason, actor, time, batch, and reversal linkage in `invoice_date_recovery_events`, plus a normal `invoice_revisions` entry and `write_audit_ex` event. It never calls create/pay/refund/correct/reconcile functions.

The effective pre-existing triggers were inspected in the complete local schema through migration 282. General UPDATE triggers (`create_therapy_on_paid`, `legacy_refund_guard`, `lock_on_settle`, `fulfil_from_warehouse`, `issue_sold_vouchers_on_paid`) act on changes to status or money. Stock guarantees, benefit/session/voucher reopening and finance request completion are `UPDATE OF status` triggers. A date-only UPDATE does not execute their operational actions. Triggers are never disabled. **Compare the deployed definitions with `diagnose.sql`; unknown custom triggers require a staging review before recovery.**

## Reporting reconciliation

> **Superseded by migration 292.** Sales are now reported on the day the money
> was received, not on the invoice's business date. Recovering a date therefore
> **moves no money at all** — the section below describes the behaviour before
> 292 and is kept for anyone reading batches recorded under the old rule. The
> preview's `sales_to_add` is now always zero and says so; `eligible_received_amount`
> still reports what the invoice has actually taken.
>
> This changes what recovery is *for*. An invoice with no business date already
> reports its receipts correctly, because payments carry their own dates.
> Recovering the date fixes the **document** — what the invoice shows, what the
> date filter and sorting use — not the financial period.

`invoice_sales_ledger()` reads existing eligible external receipts/reversal entries on the confirmed invoice business date. Refunds remain negative entries on their Singapore refund dates. `daily_payments_by_method()` retains actual effective/recorded payment dates. Wallet credit does not become cash sales. Thus recovering a S$300 invoice with S$150 received adds **S$150**, not S$300, to the recovered period; an existing S$10 refund stays on its refund date.

Dashboard, store/staff reports, Xero, reconciliation and affiliate purchase reports already consume confirmed business dates/the shared ledger. No report SQL or TikTok settlement rule was changed. No stored sales aggregate requiring rebuild was found. Ordinary page refresh re-queries the ledger; already downloaded files must be regenerated. The existing send flow regenerates a document when explicitly re-sent; recovery itself does not resend anything or touch document storage.

Operational reconciliation hashes every non-audit table and all invoice fields except the date/version/edit metadata. It includes stock, payments/refunds, credits, vouchers, sessions, qualifications, earned commissions, payout corrections/allocations, and TikTok records. Run in a quiet window; concurrent legitimate transactions can change hashes and must be reconciled rather than dismissed. The full-table hashing queries can be expensive: rehearse on staging.

## Deployment and recovery order (prepared, not executed on production)

Commands below run from the repository root. Connection configuration comes from the operator's approved environment; no credentials belong in these files. Use the actual authorized Owner/Manager profile UUID as `OWNER_PROFILE_UUID`, not a synthetic test identity. The operator connection must be permitted to set role `authenticated`; ordinary clients can instead call the RPCs with their own verified Supabase session.

1. Verify deployed migration history and backup/restore procedures. Preserve completed commission migrations 280–282 and all other required numeric migrations. Rehearse against a staging snapshot. Run pre-install diagnostics with an approved read-only connection:

   ```sh
   psql -X -v ON_ERROR_STOP=1 -f scripts/invoice-dates/diagnose.sql > private-invoice-date-diagnostics.txt
   ```

2. In staging first, install **290 once**, after the current combined baseline through 282. It adds tools and audit/version infrastructure only. It is wrapped in a transaction; stop on any error. The application change can then be released with these tools available. This task did neither production step.

   ```sh
   psql -X -v ON_ERROR_STOP=1 -f supabase/290_invoice_date_recovery.sql
   ```

3. Generate and review the complete read-only preview. Keep reports in a private directory outside source control (the local example directory is ignored).

   ```sh
   psql -X -qAt -v ON_ERROR_STOP=1 -v actor=OWNER_PROFILE_UUID \
     -f scripts/invoice-dates/preview.sql > /private/approved-review/preview.json
   python3 scripts/invoice-dates/review.py \
     /private/approved-review/preview.json /private/approved-review/rendered
   ```

   Review the eligible rows as well as `uncertain.csv`, especially possible outside imports, intentionally backdated records and conflicting audits. An empty uncertain list is not assumed. Owner/Manager should inspect originals and use existing audited **Correct Invoice** (or Edit Invoice for ordinary unpaid records) for genuinely unresolved dates. Leave dates blank if reliable evidence is unavailable. Do not manufacture audit evidence or change invoice status merely to qualify a record.

4. After reviewing the preview, prepare batches. Optional `--ids /private/approved-review/approved-ids.txt` selects a reviewed subset of eligible UUIDs; without it, all eligible rows are included. Existing valid and manual-review rows cannot be selected. Each prepared batch has a unique ID and a separate reversal file.

   ```sh
   python3 scripts/invoice-dates/review.py /private/approved-review/preview.json \
     /private/approved-review/prepared --prepare-apply \
     --reason 'Original invoice dates reviewed against the retained source records'
   ```

5. Capture before-recovery checks using the approved operator connection:

   ```sh
   psql -X -qAt -v ON_ERROR_STOP=1 -f scripts/invoice-dates/reconciliation.sql > /private/approved-review/before.jsonl
   psql -X -qAt -v ON_ERROR_STOP=1 -v actor=OWNER_PROFILE_UUID \
     -f scripts/invoice-dates/report-totals.sql > /private/approved-review/sales-before.json
   ```

6. Review and execute **one specific generated apply file at a time**. Do not glob all `.sql` files: the directory also contains reversal scripts. Retain the exact file and result; retry with the same ID/payload after an uncertain response. A new preview is needed for `evidence_changed`, `proposal_changed` or `requires_manual_review` skips; never replace a hash just to force an update.

   ```sh
   psql -X -qAt -v ON_ERROR_STOP=1 -f /private/approved-review/prepared/SELECTED-APPLY-FILE.sql > /private/approved-review/selected-result.json
   ```

7. Repeat the before queries to `after.jsonl` and `sales-after.json`. Compare operational hashes and actual ledger changes with the successfully recovered rows' proposed dates/received amounts, not blindly with the entire preview if some rows were skipped:

   ```sh
   python3 scripts/invoice-dates/compare-reconciliation.py \
     /private/approved-review/before.jsonl /private/approved-review/after.jsonl
   ```

   Collections must be unchanged; report `event_rows` must equal `distinct_events`. Existing refunds keep their dates. Refresh/reopen invoice screens, regenerate selected outputs, and check a partial payment, refund, backdated invoice and pending case. Generate a fresh preview to capture remaining manual work.

## Reversal and rollback

To inspect a recovery batch before reversing it, use an authorized Owner/Manager session:

```sql
select e.invoice_id, i.invoice_no, e.old_date, e.new_date, i.business_date current_date,
       e.date_version recovered_version, i.business_date_version current_version,
       e.source, e.reason, e.created_at,
       exists(select 1 from public.invoice_date_recovery_events r where r.reverses_event_id=e.id) already_reversed
from public.invoice_date_recovery_events e join public.invoices i on i.id=e.invoice_id
where e.batch_id='RECOVERY_BATCH_UUID' order by e.invoice_id;
```

After reviewing that result, execute the **specific generated `-reverse.sql` file**, with its own new request ID and a meaningful reason. It calls `reverse_invoice_date_recovery(original_batch, new_request_id, reason)`. Reverse only intended recovery batches; do not reverse real payments/refunds/payouts. Keep the file and result for retries.

Reversal restores the audited original date only when the current date **and version** still equal that recovery event. Subsequent date changes, including A→B→A, are skipped as `date_changed_since_recovery`. Unrelated edits survive. Already-reversed events are skipped. No history is deleted. Reversed NULL dates remain pending manual review instead of being automatically re-recovered. Repeat the operational/report reconciliation afterwards.

If installation of 290 fails, its transaction rolls back; do not proceed with recovery. If the UI must be rolled back, the additive database tools and audit tables can remain; the prior invoice code already reads `business_date`. Keep the date-version/audit infrastructure whenever recoveries have occurred. Do not drop these tables or clear dates with an unrestricted UPDATE. Prefer a forward repair; any full backup restoration requires reconciliation of legitimate transactions since that backup and is outside this date-only reversal procedure.

## Verification actually performed

- Complete isolated schema replay: **202 migration scripts, zero failures**, including 280–282, 290 and 291; no skipped failing migrations.
- SQL recovery and evidence tests: creation/date-only evidence, SG midnight, existing backdates, conflicting/incomplete/import history, invalid/missing timestamps, latest intentional correction and exact audit pairing, historical statuses, defaults, roles, staleness, repeat execution and guarded reversal.
- Independent PostgreSQL sessions: five overlapping batches recover once; concurrent retry creates one revision; a manual date or new evidence committed while recovery waits wins; stale normal editor cannot clear a recovered date.
- Rich existing invoice/commission fixtures: recovery/reversal preserves all operational table hashes, including original credits, therapy sessions, stock and partial payout/correction histories. Existing invoice refund/commission regressions also pass.
- Real Chromium with synthetic data: **21 invoice-date checks**, actual print/PDF/image/Excel output, range/search/pending behavior, saving/reopening a new backdate, preserving a date on unrelated correction, and a pending invoice beyond 1,000 rows. Browser timezone was America/Los_Angeles; a 375px pending view was visually inspected.
- Generated preview/batch/reversal workflow rehearsed locally: 12 synthetic invoices, 5 already valid, 2 eligible, 5 manual. Apply adds exactly S$150 in sales with unchanged collections/operational hashes; reversal restores the previous date counts and keeps audit history.

### Re-verified at handover, 11 September 2026

Everything above was re-run after migration 291 (credit-package reward
resolution) entered the schema, on a fixture rebuilt from nothing:

- **202 migrations, zero failures.** 290 and 291 coexist; neither touches the
  other's tables or functions.
- The whole date suite passes unchanged, including the rich invoice and
  commission integrity fixtures and the five concurrency checks.
- The documented preview reproduces **exactly**: 5 already valid, 2 eligible,
  5 manual review across 12 rows, S$150 expected, split 2020-02-01 S$150 and
  2019-10-01 S$0.
- Apply and reversal reproduce **5/7 → 7/5 → 5/7**, retaining two recovery and
  two reversal events.
- Reconciliation on a clean fixture: every operational table hash unchanged;
  sales moved from nothing to **S$150 on 2020-02-01**, with
  `distinct_events = event_rows = 1` — counted once — while collections stayed
  identical on their actual payment date of 2020-03-01. That is §6's worked
  example (S$300 invoice, S$150 received) confirmed end to end.

**A property worth knowing before you operate this.** After a recovery is
reversed, those invoices are reclassified as **manual review**, not eligible.
The reversal leaves audit history showing the date was set and then cleared, and
the planner treats that as a later intentional decision — so a second run cannot
silently re-apply a date a person deliberately took back. Recovering such an
invoice afterwards is a deliberate manual act, which is the intended behaviour.

The example is in `INVOICE_DATE_RECOVERY_EXAMPLE.md`. Production data counts, actual missing-date causes, outside import provenance, custom deployed triggers and a physical Safari session remain unverified. The recovery code intentionally leaves uncertain records for manual review.

### Reproduce locally

The test bootstrap refuses any database except `energia_invoice_date_test`, socket `/tmp`, port `55445`, and this checkout's `.invoice-date-test/data`. It rebuilds **only that disposable fixture**. Do not use it for deployment or against another test cluster.

```sh
mkdir -p .invoice-date-test
initdb -D .invoice-date-test/data -U postgres -A trust --no-locale
pg_ctl -D .invoice-date-test/data -l .invoice-date-test/server.log -o '-p 55445 -k /tmp -h 127.0.0.1' start
createdb -h /tmp -p 55445 -U postgres energia_invoice_date_test
scripts/invoice-dates/tests/run-local.sh
npm run test:invoice-dates
node scripts/invoice-dates/tests/browser.mjs
node --test scripts/commissions/tests/presentation.test.mjs
node scripts/commissions/tests/browser.mjs
node scripts/commissions/tests/invoice-price-browser.mjs
node scripts/invoices/tests/invoice-actions-browser.mjs
npm run test:xero
npm run typecheck
npm run build
```

Use existing dependencies; browser scripts support `PLAYWRIGHT_MODULE` and `CHROME_EXECUTABLE`. They intercept network requests and use no credentials. If the dedicated cluster already exists, start it without rerunning initdb/createdb. Stop only this cluster with `pg_ctl -D .invoice-date-test/data stop` after verification.
