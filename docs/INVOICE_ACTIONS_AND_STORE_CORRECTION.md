# Invoice actions, payment entry, and the INV-2026-0183 store change

Agent two, continuing the invoice implementation. **Nothing is committed, pushed
or deployed, and no production data was read or written.**

| | |
|---|---|
| New migrations | `256`, `257` |
| Combined history | **194 applied, 0 failures**, from an empty database |
| Database tests | **14 files, 24 named assertions**, all passing |
| Browser tests | 4 widths + **102 interface checks**, all passing |
| `npm run typecheck` / `npm run build` | 0 errors / build succeeds |

---

## 1. The store-change failure

### What is proven

Reproduced in an isolated fixture, and the mechanism is exact.

Migration 177 added `invoice_stock_components` and gave
`invoices.stock_snapshot_version` a **default** of 1. A default binds new rows
only. Every invoice created before 177 was applied still has `NULL` there and no
component rows, and 172's guard reads:

```sql
v_stock_change := not invoice_operational_lines_match(...) or n.store_id <> i.store_id;
if v_operational and i.stock_snapshot_version is null
   and exists(... line_kind in ('promotion','voucher')) then raise ...
```

A store change sets `v_stock_change`, so the guard fires; metadata corrections
do not, so they still work. That is exactly the reported behaviour, message
included.

**The guard is right to refuse.** Moving an invoice between stores moves stock,
and it will not do that against components it cannot see.

### A second defect, found while reproducing the first

177 renamed the original expansion to `invoice_required_stock_legacy`, whose
`quantity` is **bigint** (it comes from a `sum()`), and declared the new
`invoice_required_stock` with `quantity integer`. The fallback branch — taken
for exactly the invoices in question — returns the legacy rows straight through:

```
without a snapshot: FAILS -> structure of query does not match function result type
```

So `invoice_required_stock()` has been failing for **every pre-177 invoice**,
and with it `confirm_foc_invoice`, `ensure_invoice_stock_deducted`,
`invoice_stock_to_deduct` and every stock diagnostic. It went unnoticed because
the invoice fixtures only ever create new invoices, which take the snapshot
branch. Fixed with one cast in 256.

### What is a hypothesis

I have no access to INV-2026-0183, so the reproduction is representative, not
that record.

One inference is worth stating and is **not proven**: migration 187 adds an
*earlier* guard to the same function that refuses an operational correction when
a sold voucher has no issued-unit evidence, with a different message. Since the
reported message is the stock-snapshot one, INV-2026-0183 most likely carries a
**promotion** line, or voucher lines whose units are recorded. Confirm against
the record before relying on it.

### What it is not

Not an affiliate or payment-method correction misclassified. A store change is
correctly classified as operational.

---

## 2. The store-correction workflow

`invoice_store_change_preview(invoice, destination)` — read-only. Source and
destination, required stock, shortages at the destination, voucher locations,
whether review is required, and what the save would do to stock and commission.

`invoice_stock_component_evidence(invoice)` — read-only, per line:

| Status | Meaning | Source |
|---|---|---|
| `captured` | already recorded | recorded at sale |
| `reconstructable` | the original records answer it completely | the invoice line; `invoice_promotion_selections`; corroborated by `invoice_voucher_movements` |
| `needs_confirmation` | only today's promotion definition is available | shown, never applied on its own |
| `not_applicable` | the line consumes no tracked stock | — |
| `missing` | nothing on record answers it | — |

`rebuild_invoice_stock_components(invoice, reason, confirmations, request_id)` —
Owner or Manager, reason required, replay-safe. Rebuilds what is evidenced,
refuses while any line is `missing` or unconfirmed, and names those lines.
Provenance is recorded in `invoice_stock_component_rebuilds` and the audit log,
including who confirmed what.

**The fixed contents of a promotion as it stood on the day are not recorded
anywhere.** `promotion_stock_items()` answers from today's catalogue, so it is
displayed for a person to confirm and never applied silently. That is the one
genuine evidence gap, and it stays a gap.

Components are written with the `component_source` values 177's capture trigger
manages, and the version is set to 1 — so `invoice_required_stock` and the
trigger keep working on that invoice exactly as on any other. Provenance lives
in the rebuild row, not in the version number.

In the application: a correction refused with this message now opens the review
inside the correction form, showing the evidence line by line. After recording
it, the same Save Changes goes through the ordinary protected correction.

Verified end to end: refusal → preview → evidence → rebuild → the store changes,
with the saved price and the payment history intact.

---

## 3. Interface changes

**Refund and cancel** are one **Refund / Cancel** footer action, beside Correct
Invoice or Edit Invoice. It opens a labelled dialog with two explicit choices
and hands over to the existing workflow unchanged. Opening it sends nothing to
the server. Refund is disabled with "No refundable payment." when no money or
credit is held. Focus moves into the dialog, Escape closes it, and focus returns
to the button. The old standalone buttons are gone from the finance panel; the
summary line stays.

**One edit action.** Derived from recorded financial and lifecycle state, not
from `paid_amount`: settled history, refunds and the topup/exchange flags all
count. A refunded invoice has its paid amount back at zero and no longer falls
into the ordinary unpaid-edit path. The duplicate correction button at the top
of the detail body is gone; correction is offered once, in the footer.

**Payment correction** moved to the Payments Recorded list, beside the payment
it corrects, still opening the audited reversal-and-replacement workflow with
its required reason and role check.

**Instalments** moved out of the top of the creation form into Record Payment,
and are persisted by `record_invoice_payment_with_instalment` **in the same
transaction as the payment** — so the invoice can never carry an arrangement for
a payment that failed. They remain invoice-level metadata; choosing them records
no payment. On a correction they stay in the form with their saved values.

**Payment entry starts blank.** No method is selected, for the first row or any
split row; the amount is prefilled from the actual outstanding balance. Record
Payment is disabled until every filled row has a method and a positive amount
and the instalment details are complete, and it says which of those is missing.
**A positive amount with no method is refused, not silently dropped.**

**After recording**, the invoice is reloaded and stays open with its real status
and balance; a part payment clears the method selections and prefills the new
outstanding amount. A failed *refresh* is reported as a display problem — "the
payment was recorded … do not record the payment again" — never as a failed
payment. Each payment uses a fresh request id.

**After creating**, the form closes and the new invoice's own detail view opens.
If it cannot be loaded, the id is kept and a retry offered; creation is never
reported as failed, and a second click cannot create a second invoice.

**Correction form order**: audited notice and required reason, then the business
date, then the rest. A missing historical date stays missing and says so.

### A regression I introduced and fixed

Adding the correction button to each payment row overflowed `.modal-body` at
320px. Caught by agent one's browser test, which passes at HEAD and failed after
my change. The row now wraps.

---

## 4. Tests

| Suite | Result |
|---|---|
| Combined migration build | **194 applied, 0 failed** |
| Invoice + integration SQL (14 files) | **24 named assertions**, all passing |
| `historical-stock-review.sql` (new) | refusal reproduced, review, rebuild, resumption, promotion confirmation, and a line with no evidence staying refused while writing nothing |
| `invoice-actions-browser.mjs` (new) | **102 checks** at 375px and 320px |
| `browser.mjs` | 320 / 375 / 390 / 430 px |
| `concurrency.mjs` · `benefit-review-browser.mjs` | 2 · 1 |
| `report-helpers` + `xero-sales` | 18 |
| therapy-services / therapy / users / tiktok (database) | 105 / 76 / 60 / 35 |
| therapy / tiktok / xero / survey / phones (node) | 19 / 33 / 8 / 26 / 9 |

Two assertions in the new browser test were initially written so that they could
not fail (`evaluate(() => true)`, and a refresh-failure flag the mock ignored).
Both were replaced with real ones: two payments are compared for distinct
request ids, and the mock now genuinely fails the reload.

### Not verified

- **INV-2026-0183 itself.** No production access; the reproduction is a
  representative fixture.
- **Real iOS Safari.** Chromium at 320/375/390/430 px with the real components.
- The **creation → payment view** transition is asserted through the handler's
  behaviour and the created-invoice fallback, not by driving the whole creation
  form in the browser.
- **Role restrictions in the browser.** The browser harness signs in as an
  Owner, so the non-manager path (Request Refund rather than Refund / Cancel) is
  covered by the role checks in the database suites, not by a second bundle.

---

## 5. Files and migrations

**New migrations** — apply in numeric order after 255:

| | |
|---|---|
| `supabase/256_invoice_historical_stock_review.sql` | the `invoice_required_stock` cast; evidence, audited rebuild, store-change preview |
| `supabase/257_invoice_payment_instalment.sql` | `record_invoice_payment_with_instalment` |

256 requires 172, 177 and 187. 257 requires 171.

**New application files**

* `src/components/invoices/InvoiceRefundCancelChooser.tsx`
* `src/components/invoices/InvoiceStockEvidenceReview.tsx`
* `scripts/invoices/tests/historical-stock-review.sql`
* `scripts/invoices/tests/invoice-actions-browser.mjs`

**Edited**

* `src/pages/InvoicesPage.tsx` — footer actions, action derivation, payment
  entry, creation and payment continuation, correction form order
* `src/components/invoices/InvoiceFinancePanel.tsx` — standalone refund/cancel
  and payment-correction buttons removed; opens on external request
* `src/components/invoices/InvoiceSearchSelect.tsx` — placeholder support
* `src/components/invoices/invoice-controls.css` — appended, all `.invoice-*`
* `scripts/invoices/tests/browser.mjs` — payment correction's new location

---

## 6. Deployment

Apply in numeric order, after the migrations already listed in
`INVOICE_DEPLOYMENT_AND_REVIEW.md`:

```
256_invoice_historical_stock_review.sql
257_invoice_payment_instalment.sql
```

256 prints `invoice_required_stock now works for invoices with no snapshot` on
first run. If it instead raises *"Unexpected invoice_required_stock fallback"*,
the function has been changed elsewhere — add the cast by hand rather than
letting it guess.

### Historical review, per invoice

There is **no bulk backfill**, deliberately: rebuilding every historical
invoice's components in one pass would apply today's promotion definitions to
sales made under older ones.

1. Open the invoice and choose Correct Invoice.
2. Change the store and press Save Changes. If the invoice predates snapshots,
   the evidence review opens in place of the error.
3. Read what each line's evidence is and where it came from. Confirm any
   promotion whose contents can only be shown from today's definition.
4. Enter a reason and record it. Press Save Changes again.

To inspect without touching anything:

```sql
select * from public.invoice_stock_component_evidence('<invoice id>');
select public.invoice_store_change_preview('<invoice id>', '<destination store id>');
```

Both are read-only. A line reported as `missing` is a genuine gap: find the
original evidence, or leave the store as it is.

### Rollback

- **257** — drop `record_invoice_payment_with_instalment`. `record_invoice_payment`
  is untouched, and arrangements already saved stay on their invoices.
- **256** — re-run 177 to restore `invoice_required_stock` (reintroducing the
  bigint defect), then drop the three new functions. Keep
  `invoice_stock_component_rebuilds` and the rebuilt
  `invoice_stock_components` rows: they record what a person confirmed, and
  invoices whose version was set to 1 behave like any tracked invoice.

No financial or entitlement history is deleted by either migration.
