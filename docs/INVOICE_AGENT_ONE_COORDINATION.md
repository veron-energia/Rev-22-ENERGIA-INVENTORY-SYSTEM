# Invoice work ownership

Agent one owns invoice corrections, payments/refunds, inventory/credit reconciliation, invoice sales dates and invoice mobile controls. Agent two owns survey exit confirmation, validation focus and survey usability. Completed phone changes are preserved.

Invoice files: src/pages/InvoicesPage.tsx, invoice-specific components/lib/styles, invoice report/print consumers; new SQL migrations 170+ and scripts/invoices tests/diagnostics. Database functions include update_invoice, edit_paid_invoice, pay_invoice, refund/cancel/reopen, stock/entitlement helpers and sales/commission summaries.

No active survey implementation task was discoverable at initial inspection. This note is not a lock. Shared types, ui/SearchSelect, global styles/navigation and package scripts will be avoided; coordinate before any overlapping edit. No branch switch/reset/stash/cleanup. Existing untracked reports and tests are preserved. Invoice tests use a new /tmp/energia-invoice-* cluster, never an existing test or production database.

Final scope additions: ApprovalsPage routes invoice refund requests to the detailed invoice review; XeroExport changes invoice date fields only. Shared types, survey components, global styles and navigation guards are unchanged. New migrations occupy 170–184. The current exclusive test cluster is `.invoice-test/data`, socket `/tmp`, port 55441, database `energia_invoice_test`; the old temporary-cluster note above is historical. No production deployment or data cleanup occurred.


Continuation on 9 September: invoice migrations now occupy **170–187**. New files include `185_invoice_price_and_retry_integrity.sql`, `186_invoice_unused_benefit_transfers.sql`, `187_invoice_historical_benefit_review.sql`, `scripts/invoices/tests/benefit-corrections.sql`, and `scripts/invoices/diagnose-benefit-review.sql`. The invoice finance component reuses the existing customer picker without editing it; styling stays invoice-scoped.

Read `THERAPY_COORDINATION.md`: therapy owns 220–224, TherapyPage, its new components, shared therapy types and package test scripts. Those changes were preserved. Invoice migrations/components do not call `activate_purchased_therapy` or `claim_legacy_therapy`, so the changed return type/signature has no direct invoice caller to update. The invoice test fixture excludes 220–224 and uses its own cluster. Testing the fully combined migration history remains a separate integration check; neither agent's database was reset by the other.


## Ownership transferred — 10 September 2026

**Agent two now owns the invoice work.** Agent one is stopped. This note is kept
as the record of what agent one held; it is no longer the current ownership
statement.

Agent two owns: invoice corrections, payments/refunds/cancellation/reopening,
inventory and credit reconciliation, invoice sales dates, invoice mobile
controls, and migrations 170–191, 193 and 250–254 — plus the therapy, therapy
service, credit and commission work (220–226, 240–245) it already owned. Both
sides of the integration are therefore under one owner and the coordination
boundary that produced this file no longer applies.

Nothing was reset, stashed, discarded or rebuilt. Agent one's five modified
tracked files and every untracked component, migration, script and report were
preserved.

Corrections to the statements above, verified against the folder:

- Invoice migrations are **170–191 and 193**, not 170–187. There is no 192 and
  nothing references one.
- **250–253 already existed** at handover; the therapy integration had begun.
  Agent two added **254**.
- "The invoice test fixture excludes 220–224" is still true of
  `scripts/invoices/bootstrap-local.py`, which stops before 170 and never
  applied 200+. The combined history is now built separately by
  `scripts/integration/bootstrap-integration.py`, which applies everything.
- 251 renames and replaces `snapshot_therapy_voucher_issue` from 241. That is
  intended: a replacement voucher continues recorded rights rather than being
  re-snapshotted at today's catalogue terms.

See `INVOICE_TAKEOVER_CHECKLIST.md` for the verified state and remaining gaps.
