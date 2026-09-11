# Sales are reported on the day the money arrived

Migration **292**. Nothing is committed, pushed or deployed, and no production
data was changed.

## What changed

Until now a receipt was reported against the **invoice's** business date, and an
invoice with no business date contributed nothing to any dated report. Two
consequences the business actually hit:

- an invoice raised in August and paid in September put the money in **August**,
  which is not when it arrived;
- every historical invoice without a business date was missing from dated sales
  entirely — which is what made recovering those dates look urgent.

Received money now belongs to the day it was received. Refunds already reduced
sales on the refund date and are unchanged, so both directions follow the actual
movement of money.

## Three things this delivers

**1. No more "Date pending review".** An invoice with no recorded date now shows
the Singapore calendar date it was created on — one date, in the list, the
detail, print, PDF, image, email and Excel. The separate "Created on" line is
gone everywhere, and so is the export column. One definition, `invoiceDate()`,
so the list, filters, sorting and outputs cannot disagree.

**2. Money follows the payment.** `invoice_sales_ledger()` attributes each
receipt to `coalesce(effective_at, created_at)` in Singapore, and no longer
excludes invoices whose own date is unknown. Every dated report reads that one
ledger, so dashboards, store and staff reports, reconciliation and affiliate
summaries all follow without separate changes. TikTok settlement rules are
untouched.

**3. Payments can be backdated.** Record Payment carries a **Date received**
field, defaulting to today in Singapore. Each payment row may carry
`payment_date`; the server refuses a future date. Correcting an existing
payment's date already worked and is unchanged.

## What this changes in past figures

Any invoice whose payment fell on a different day from its invoice date moves,
by the difference between those dates. Totals over a long enough window are
unchanged; **period boundaries are not**. Run
`scripts/invoice-dates/report-totals.sql` before and after on real data before
anyone relies on the new figures.

**Correcting an invoice's date no longer moves its sales.** To move money
between periods you now correct the *payment* date, which is the audited
reversal-and-replacement workflow, not the invoice date.

## Deployment

Apply **`292_sales_on_payment_date.sql`** after 291.

It requires 171. Where 290 is installed its preview is corrected too — that
preview used to predict a sales movement which can no longer happen; where 290
is absent, that step is skipped and reports so.

The migration creates, alters and deletes no payment, refund, commission or
payout. It changes only which date existing money is reported under.

### Rollback

Re-run the definitions 292 replaced: `invoice_sales_ledger`, `invoice_sales_at`
and `invoice_received_sales_amount` from their owning migrations, then re-run
290 to restore its preview. Payments recorded with a backdated `effective_at`
keep that date — it records when the money actually arrived, and the correction
workflow already stored dates that way.

## Verification

| | |
|---|---|
| Combined history | **203 migrations, 0 failures**, from an empty database |
| Invoice SQL | 15 files, **25 assertions** |
| Invoice-date suite | full run, **0 errors**, including the rich invoice and commission integrity fixtures and 5 concurrency checks |
| Commission suite | regression, invoice-adjustments, legacy-check — all passing, including on a fixture without 290 |
| Browser | 4 widths · 116 invoice-action checks · **23 invoice-date checks** |
| Unit | 19 passing |
| typecheck / build | 0 errors / succeeds |

`scripts/invoice-dates/tests/payment-date-sales.sql` covers the reported case
directly: raised last month and paid today puts the money on today; a payment
can be dated to the day it arrived; a future date is refused; an invoice with no
business date still reports its receipts; only received amounts count; and a
refund stays on the refund date.

Six existing assertions encoded the old rule and were updated to state the new
one rather than deleted — including two that asserted correcting the invoice
date moves sales, which it no longer does.

**Not verified:** production figures. The size of the movement on real data is
unknown until `report-totals.sql` is run before and after on an approved
snapshot.
