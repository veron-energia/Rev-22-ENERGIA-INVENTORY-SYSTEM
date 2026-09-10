# Invoice corrections: deployment and review

This change has not been deployed or applied to a production database. Customer-phone migrations 161–163 and the survey implementation are preserved.

## What changed

- New audited correction entry point for invoice edits, stable invoice-item IDs, no-op detection, saved prices and FOC reasons, explicit affiliate clearing, business dates and instalment metadata.
- Separate payment amount/date correction with original receipt, reversal and replacement. New payments and refunds carry request IDs for retry safety.
- Refund allocation to original payment sources, unused paid-value benefits and actual stock deductions. Sellable, damaged and not-returned quantities remain distinguishable. Line refunds release the corresponding invoice charge; overpayment refunds do not create an extra charge reduction.
- Cancellation reverses outstanding stock deductions at their actual source locations and revokes unused benefits. Refunds remain separate from cancellation.
- Explicit reopening previews net payments, replacement stock and revoked benefits. Original voucher records survive; replacement vouchers have their own records and links. Benefits are restored only after settlement.
- Paid commission payout records stay intact; future commission adjustment rows offset them. Affiliate-only edits preserve item rows and stock.
- Shared receipt/refund sales events use invoice business dates, while payment collections use actual payment dates. Invoice exports, dashboard totals, store/staff sales, reconciliation and affiliate purchase reports use the revised basis.
- Invoice-specific searchable payment methods, instalment fields, finance controls and narrow-screen promotion controls.

## Findings and limits of the diagnosis

The saved FOC note was explicitly cleared by the old editor loader. It now loads the stored selection and text. An inactive historical reason survives unchanged allocation; a changed allocation must satisfy current reason validation.

The old correction builder reconstructed every line, causing needless stock movement and exposing historical invoices to current catalogue values. It now compares saved lines and preserves unchanged rows, prices and selections. Product and promotion stock requirements are captured for new invoices and returns link to actual sale movements.

The reported `edit_paid_invoice` / SQLSTATE 23502 was **not reproduced on the assembled repository baseline**. The replacement builder always supplies the validated invoice ID to inserts, and the regression exercises the exact RPC with an affiliate-only change. This is not proof of the deployed database's original failure mechanism. Compare the deployed definitions and triggers with `scripts/invoices/diagnose-local-definition.sql` before claiming a confirmed production root cause. Integrity constraints were not loosened.

## Required historical review before rollout

Run `scripts/invoices/diagnose-historical-data.sql` with a read-only database role on an approved snapshot. It works before or after these migrations and makes no data changes. Save the result privately, for example:

```sh
psql -X --csv -v ON_ERROR_STOP=1 -f scripts/invoices/diagnose-historical-data.sql > invoice-review.csv
psql -X --csv -v ON_ERROR_STOP=1 -f scripts/invoices/diagnose-local-definition.sql > invoice-function-review.csv
```

Connection details should come from the operator's approved PostgreSQL environment. Do not paste credentials into reports or commit customer data.

The report lists customer/invoice IDs and names, original creation-date suggestions, missing business dates, unknown refund payment sources, unlinked historical wallet allocations and unlinked stock returns. It compares actual eligible receipts by payment month with invoice-date sales and identifies the amount pending date review. Refund reductions remain on refund dates. This is a date-basis comparison; it does not pretend to reconstruct every historical reporting bug.

No historical business date is automatically inferred from creation or payment timestamps. Missing dates stay NULL and are excluded from dated receipt sales until reviewed. Use the audited Correct Invoice date field to apply a supported date. An actual production-data dry run has not been performed in this task; no production report counts are asserted.

After applying 170–187 to the isolated review snapshot, also run `scripts/invoices/diagnose-benefit-review.sql`. It lists untracked voucher lines, missing benefit mappings, original paid/bonus lot evidence, and the provenance of unused-benefit transfers. The synthetic report generated during this task is not a production customer review.

Legacy compound-benefit paid values must come from original evidence. The Owner/Manager RPC `record_invoice_benefit_values(p_item_id, p_allocations, p_evidence)` validates original lots/vouchers and keeps an audit event. The database rejects incomplete mappings, omitted known bonus lots, ambiguous repeated-package lines and totals that fail to reconcile to original recorded external payment. Each allocation supplies exactly one `lot_id` or `reward_voucher_id`, plus `paid_value` and `granted_value`. Do not allocate using current catalogue prices or guess between recipients. Ambiguous source mappings require a separately reviewed data repair; no automatic cleanup is provided.

## Correcting an unused recipient

Open the invoice, choose **Correct unused benefit recipient**, select the original recipient's available credit/voucher allocation, choose the correct recipient and benefit store, enter a reason and confirm the displayed move. The database rechecks the unused amount while holding locks. Repeating or concurrently submitting the request cannot move it twice.

For credit, the original lot and spending references remain unchanged; its unused balance is removed with a ledger entry and posted to a new, linked lot. The new lot keeps the original category, eligibility restrictions and purchase date. Bonus value retains the original paid-to-granted ratio. Held vouchers are revoked and replaced with linked units; destination stock must exist for a store change. Redeemed vouchers cannot move. Cancellation/refund/reopening follows the replacement allocation and retains original history.

This action does not change the invoice buyer. If the buyer or selling store also needs correction, edit the invoice separately and explicitly confirm the reviewed benefit recipients. A refund or transfer in between edits increments the invoice version so a stale editor cannot overwrite the later state.

## Remaining workflow boundaries / release gates

These are explicit limitations, not scenarios claimed as verified:

- Replacing an issued package/bundle definition or changing its promised quantities remains guarded. Price-only corrections now preserve grant snapshots, and the invoice finance panel can move an actual unused credit/voucher balance to another recipient/store without moving consumed history. A buyer/store header correction requires explicit acknowledgement of the recorded recipients. Repricing followed by additional receipts needs allocation review before treating the added receipts as refundable package benefits; recorded original paid-value caps are not silently rewritten.
- Consumed/active therapy and active rentals must be resolved in their existing operational screens before changing their operational invoice allocation. Full special-product/rental document reconciliation across every correction/refund combination is not yet covered by the new automated tests.
- Ordinary sold vouchers and promotion voucher units lack a complete issuance/redemption mapping in the existing application. Their refunds, paid cancellation and operational corrections now fail with a review message. Other eligible lines can still be refunded. This is a guarded pending workflow, not a completed sold-voucher redemption implementation. Historical qualification rewards also need separate source and consumption review.
- Historical promotion/limited-voucher stock without original snapshots or linked returns remains a review case. The migration does not invent old component allocations.
- The reported production 23502 definition/trigger chain and a real iOS Safari session remain unverified. Chromium testing uses actual components and synthetic data, not a logged-in production session.

Do not treat this branch as a completed production rollout until these release gates are resolved or a narrower release scope is explicitly accepted.

## Migration order

1. Back up schema and data, including invoice revisions, payments, refunds, stock movements, credit lots/ledger, benefit records and commissions/payouts. Test restoration on a separate database.
2. Confirm baseline migrations through 163, plus any independently reviewed survey migrations. Reserve 164–169 for survey work. No survey migration was renamed.
3. Run the read-only historical diagnostics and review discrepancies. Do not switch reporting while required business dates remain unresolved without an explicitly reviewed rollout decision.
4. In a maintenance window on staging, apply the new numbered migrations **170 through 187 in order, exactly once**. They include transactional DDL and deliberate function-definition checks. A changed anchor fails instead of silently applying an incomplete function patch. Stop on the first failure.
5. Run the regression suite and application build. Check grants using representative authenticated roles. Test a historical FOC invoice, a mixed promotion invoice, wallet refunds, a multi-recipient benefit invoice and reports against the reviewed staging data.
6. Publish database and application changes as a coordinated release only after approval. This task does not perform this step.

The local fixture replays `00_complete_setup.sql`, `UPGRADE_to_current.sql`, then numbered migrations 24–163. Existing migration **130** has an unrelated TikTok-settlement patch-anchor failure against that assembled baseline and is explicitly excluded by the isolated bootstrap; later settlement fixes 131/132 apply. This is a pre-existing baseline limitation, not permission to skip migration 130 in production. Verify the deployed migration history separately.

## Verification commands

Use an exclusively owned PostgreSQL cluster; do not reset a database used by another agent. `scripts/invoices/bootstrap-local.py` refuses targets outside the project-owned `.invoice-test/data` cluster and fixed local database/port. It is destructive **only to that disposable fixture** and is not a deployment tool.

```sh
npm run typecheck
npm run build
npm run test:customer-phones
npm run test:survey
scripts/invoices/local-sql.sh -f scripts/invoices/regression.sql
scripts/invoices/local-sql.sh -f scripts/invoices/tests/extended.sql
scripts/invoices/local-sql.sh -f scripts/invoices/tests/benefit-corrections.sql
node scripts/invoices/tests/concurrency.mjs
node scripts/invoices/tests/browser.mjs
```

The browser test needs Playwright and Chrome. Override `PLAYWRIGHT_MODULE` and `CHROME_EXECUTABLE` for another workstation. It intercepts all network traffic and supplies synthetic invoice data. Screenshots go into the ignored `.invoice-test/browser` folder. Database concurrency fixtures persist only in the disposable cluster; rebuild it before repeating the concurrency fixture.

## Rollback and recovery

Before traffic resumes: if a migration fails, its own transaction rolls back. Earlier numbered migrations may have committed, so retain maintenance mode, inspect the error and either fix forward or restore the verified pre-change staging/production backup as a unit. Do not manually drop individual ledger columns/tables or rerun already committed migrations blindly.

After new transactions have been recorded: use a forward repair preserving the new reversal/refund/stock/benefit evidence. Returning to old refund or payment code can misinterpret correction entries and reissue value. An application-only rollback is not safe against the new ledger semantics. If disaster recovery requires restoring a backup, reconcile and replay every legitimate transaction since that backup before reopening access.

Never reverse a customer refund merely to roll back software. Never delete payouts, payment originals, linked invoices, consumed benefit history or stock dispositions. Preserve the coordination note and the phone/survey work.

---

# Agent two continuation — 10 September 2026

Everything above is agent one's and is preserved. This section corrects what has
since changed, and supersedes the migration range and the limitations list.

**Still not deployed. No production database was read or written.**

## The actual migrations

Invoice: **170–191 and 193**. There is no 192 and nothing references one.

Therapy-service integration, written after the section above: **250–253**
(credit transfer policy, therapy-voucher snapshots, session reconciliation,
refund commission basis). Agent two added **254** (sold-voucher issuance).

These depend on work outside the invoice range, which the older instructions did
not mention. Apply in numeric order:

```
… 130 …                          (fixed; see below)
170 … 191, 193                   invoice
200, 201, 210                    auth email, commission visibility, TikTok
220 … 226                        therapy
230, 231                         user invitations
240 … 245                        therapy services, credit rules, commission
250 … 255                        invoice ↔ therapy integration, rentals
```

251 requires 184, 186, 190, 241 and 245. 252 requires 244. 254 requires 174,
178, 179, 184, 186 and 187. 255 requires 179. Numeric order satisfies all of them.

## The combined history now builds

`scripts/integration/bootstrap-integration.py` applies the entire history to
`energia_integration_test` and records failures instead of skipping them.

**192 migrations applied, 0 failures**, reproducibly from an empty database.

```sh
createdb energia_integration_test
PGHOST=/tmp PGPORT=55441 PGUSER=postgres PGDATABASE=energia_integration_test \
  python3 scripts/integration/bootstrap-integration.py
```

`scripts/invoices/bootstrap-local.py` is unchanged and still builds agent one's
pre-170 fixture.

## Migration 130 was never a baseline failure

It was excluded as one. In fact migration **66 already contains its fix**, and
130's own idempotence guard tested a comment sentence — `same type, related
order AND amount` — that 66 words differently. The guard missed, the block fell
through to a replace whose anchor no longer existed, and it raised.

The guard now tests the rule itself
(`r.related_order_id is not distinct from v_related`). 130 applies cleanly and
idempotently and needs no exclusion.

## Two defects found by building the combined history

**Saving a credit package was broken.** Migration 243 neutralises the
classification parameter on the package upsert functions, looking them up by the
signatures from 79 and 80. Migration **94** redefines `upsert_credit_package`
with twelve more arguments, so the lookup matched nothing and silently skipped.
The function kept honouring the caller's classification, the Therapy page sends
`own` by default, and 243's check constraint then rejected the row. 243 now
resolves by name across every overload and raises rather than leaving a function
that writes a value the constraint rejects.

**A voucher line could be refunded without revoking the voucher.** The
benefit-revocation block inside `refund_invoice_recorded` is gated on
`line_kind in ('credit_package','premium_bundle')`. A voucher line's `benefits`
allocation was accepted and ignored: the money went back and the customer kept
the voucher. 254 widens the gate to voucher lines with issued units and refuses
an unallocated voucher refund.

## Limitations reassessed

Each was inspected against the effective implementation and tested, not carried
forward.

| Limitation as documented | Now |
|---|---|
| Combined migration history untested | **Resolved.** 191 applied, 0 failures, reproducible |
| Migration 130 known baseline failure | **Resolved.** Was a false alarm; guard fixed |
| Ordinary sold vouchers lack an issuance/redemption mapping | **Resolved for new sales** by 254 — and it was never only a historical problem: a voucher sold under the current code could not be refunded either. Lines with no recorded units still need review, which is the genuine historical case |
| Promotion voucher units | **Still a review case, narrowed.** A voucher's share of a bundled price is not derivable; record allocations with `record_invoice_benefit_values` |
| Consumed/active therapy | **Resolved** by 252 and covered by tests; sessions reconcile through correction, refund, cancellation and reopening |
| Active rentals / special products | **Resolved, and a defect found doing it.** An overdue rental did not block cancellation, correction or reopening, and an unfulfilled rental was left live after its invoice was cancelled. Fixed in **255**; covered by `rental-lifecycle.sql` |
| Issued package/bundle replacement, changed promised quantities | **Still guarded.** Price-only corrections preserve snapshots; unused balances move by explicit transfer |
| Historical stock/benefit allocations without snapshots | **Still a review case.** No old allocation is invented |
| Production 23502 root cause | **Still unproven.** No production access. Do not claim a confirmed cause without comparing deployed definitions |
| Real iOS Safari | **Still untested.** Chromium covers 320/375/390/430 px with the real components; no iOS device was available |

## A decision for the business

Two independent gates now decide what package credit may buy: the per-package
`allow_product` / `allow_therapy` / … flags a package was sold with, **and** the
mandatory matrix from 242. A package sold permitting *products only* can no
longer spend its **paid** balance at all — the matrix forbids products from a
paid balance and the package forbids therapy. Customers already holding such
credit are affected. Decide whether those packages should be amended to permit
therapy, or whether the affected balances should be reviewed individually.

## Verification

| Suite | Result |
|---|---|
| Combined migration build | 192 applied, **0 failed** |
| Invoice + integration SQL (13 files) | **23 named assertions, all passing** |
| `concurrency.mjs` | 2 passing |
| `browser.mjs` (320/375/390/430 px) | 4 passing |
| `benefit-review-browser.mjs` | 1 passing |
| `report-helpers` + `xero-sales` | 18 passing |
| therapy-services / therapy / users / tiktok (database) | 105 / 76 / 60 / 35 |
| therapy / tiktok / xero / survey / phones (node) | 19 / 33 / 8 / 26 / 9 |
| typecheck / build | 0 errors / succeeds |

```sh
PGHOST=/tmp PGPORT=55441 PGUSER=postgres PGDATABASE=energia_integration_test \
  python3 scripts/integration/bootstrap-integration.py
export ENERGIA_INVOICE_DB=energia_integration_test
for f in scripts/invoices/regression.sql scripts/invoices/tests/*.sql \
         scripts/integration/tests/cross-feature.sql; do
  scripts/invoices/local-sql.sh -q -f "$f" || echo "FAILED $f"
done
node scripts/invoices/tests/concurrency.mjs
node scripts/invoices/tests/browser.mjs
```

`concurrency.mjs` leaves fixtures behind; rebuild before another run.

## Rollback

Nothing here is destructive, and no financial or entitlement history is deleted
by any of it.

- **254** — drop the `issue_sold_vouchers_on_paid` trigger and
  `issue_sold_vouchers_for_invoice`, then re-run 187 to restore the blanket
  `invoice_untracked_voucher()` and re-run 174/187/191/252 in order to restore
  `refund_invoice_recorded` without the widened gate. Issued
  `customer_reward_vouchers` and `invoice_benefit_values` rows should be **kept**:
  they record what customers were actually given.
- **243** — drop `credit_packages_third_party_commission` and
  `premium_bundles_third_party_commission`, then re-run 94 and 96 to restore the
  upsert functions. Previous classification values are in `audit_logs` under
  `commission_classification_corrected`.
- **255** — re-run 179, then 180–193 and 252 in order, to restore the narrower
  rental guards. Rentals already cancelled with their invoice should be **kept**
  cancelled; `audit_logs` records each under `rental_cancelled_with_invoice`.
- **130** — no rollback needed; it is a no-op where the rule is already present.

Historical commission paid at the wrong rate is **not** repaired by any
migration. `scripts/therapy-services/commission-diagnostic.sql` measures it
read-only, including tier 2, and works in the SQL editor where the gated
`package_commission_diagnostic()` returns nothing.
