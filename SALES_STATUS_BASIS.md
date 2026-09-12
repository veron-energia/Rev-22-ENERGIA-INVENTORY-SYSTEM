# A CANCELLED INVOICE WAS STILL A SALE

| Check | Result |
|---|---|
| `supabase/294_sales_exclude_voided_invoices.sql` | applies, **idempotent**, clean-room verified |
| `scripts/invoices/tests/sales-status-basis.sql` | **16 assertions, passing** |
| Invoice suites (15 test files + regression) | **16 passed, 0 failed** |
| Date + commission runner, database rebuilt from scratch | **all passing** |
| Reverting the fix | test fails with `A cancelled invoice must leave Sales, got 100.00` |
| `npm run typecheck` / `npm run build` | **0 errors / build succeeds** |
| Deployment | **none — stopped for manual approval** |

## What you reported, measured

> "I think refunded, cancelled and not paid invoice are in the sale."

One invoice per status, in an isolated database, before any change:

| Status | In Sales? | |
|---|---|---|
| `unpaid` | **0.00** | already excluded — it has no payments at all |
| `partially_paid` | 150.00 | correct, this is money received |
| `cancelled` | **100.00** | **counted, and counted forever** |
| `refunded` | 0.00 net | but **100.00 left in the original month**, −100.00 dropped into the refund month |

So of the three you named, **one was genuinely wrong**. `unpaid` never counted.
`refunded` was wrong about *when*, not about *how much*.

## Why cancelled invoices kept selling

Cancelling an invoice deliberately leaves its payments alone —
`cancel_invoice_recorded` returns, in its own words, *"Payments remain recorded.
Record any actual refund separately."* That is correct: cancelling a document
must not silently delete a record of money.

But `invoice_sales_ledger()` — the single basis every sales figure in the system
reads — never looked at the invoice's status. It counted every receipt whose
invoice was not deleted. So cancelling removed the invoice from the business
without removing its money from Sales.

The rule already existed elsewhere on the same dashboard:

```sql
-- dashboard_summary.discount_today, long before this change
where deleted_at is null and status in ('paid','partially_paid','completed_foc')
```

The sales ledger was the outlier. That is why one tile disagreed with another.

## Which statuses count now

**Counted** — money received and still held:

- `paid`, `partially_paid`
- `completed_foc` — a zero-value invoice. Contributes 0 either way; kept so that
  a receipt recorded against one can never be silently dropped, and so this
  matches the `discount_today` rule that was already there.
- `cancellation_requested`, `refund_requested` — a **request is not a decision**.
  The money is still held, and `resolve_invoice_action()` puts the invoice
  straight back to `paid` / `partially_paid` when the request is refused.
  Excluding these would make a month's sales fall the moment staff click
  "request cancellation" and rise again when a manager refuses it.

**Not counted:**

- `draft`, `unpaid` — nothing was received; these already contributed 0.
- `cancelled` — voided. Its receipts stop counting.
- `refunded` — fully returned. The receipt *and* the refund both stop counting,
  so a refund given in a later month no longer leaves a sale sitting in one
  month and a bare negative in another. Across all time the total is unchanged.

## The case a blunt fix would have destroyed

A **partial** refund does not reach this rule at all — such an invoice keeps
status `paid`. Verified: 400 received, 100 refunded, status `paid`, **300 still
counted**. If the filter had simply been "status = paid or partially_paid"
applied to the invoice's total, money genuinely kept after a partial refund
would have vanished. It does not.

## The one consequence to be aware of

If an invoice was cancelled while the business **kept** the customer's money and
no refund was ever recorded, that money now leaves Sales. Sales will be lower
than cash banked by exactly that amount.

That is the intended reading — a cancelled invoice is not a sale — but it is a
real difference, so it is reported rather than hidden:

```sql
select * from report_cancelled_retained_receipts();
```

Every row is money held against an invoice that has been voided. Each needs
either a recorded refund or the invoice reopening. **An empty result means the
change costs you nothing.**

## What deliberately did NOT change

**Affiliate settled spend.** `_aff_settled_spend()` measures what the customer
actually paid the business, and it drives affiliate commission and tier
qualification. A reporting rule about Sales must not quietly change what
somebody gets paid. Asserted explicitly in `report-dates.sql`.

**Staff commission and payouts.** Nothing on those paths reads the sales ledger —
traced through all seven of its consumers.

**The detail reports** (`report_pricing`, `report_discounts`, `report_foc_lines`,
`affiliate_portal_purchases`). These describe the *document* — what was billed,
at what price, with what discount — not what was sold.

**Every payment, refund, invoice and audit record.** 294 changes reporting only.
It is reversible by restoring two function definitions.

## Where the filter went

One place, covering all seven sales consumers at once:

```sql
create or replace function public.invoice_counts_as_sale(p_status text)
returns boolean language sql immutable as $$
 select coalesce(p_status,'') in
   ('paid','partially_paid','completed_foc','cancellation_requested','refund_requested')
$$;
```

applied inside `invoice_sales_ledger()` on **both** branches — receipts and
refunds — so a cancelled invoice loses its receipt *and* its refund and cannot
swing negative. `sales_between`, `invoice_net_sales_between`, `dashboard_sales`,
`dashboard_sales_by_store`, `dashboard_sales_series`, `dashboard_summary` and
`report_sales_reconciliation` all follow from that one edit.

`items_sold` and `discount_total` in `dashboard_sales` got the same status test,
so a cancelled invoice cannot leave its items behind in a month its money has
left. (293 had already put them on the same *date*; this puts them on the same
*status*.)

## Check it against your own data

Before applying 294, in the Supabase SQL editor:

```
scripts/invoices/check-sales-by-status.sql
```

Edit the two dates at the top and run. Read-only, one `SELECT`. It reports how
much of your current Sales figure each status contributes, what the change
removes, and lists any cancelled invoice whose money you kept. Run it again
after applying 294 to confirm the excluded rows have gone to zero.

`scripts/invoices/diagnose-sales-difference-supabase.sql` has been updated to
the same rule, so it will keep agreeing with the dashboard.

## To apply

`git push` does not run SQL. In the Supabase SQL editor, in order:

```
supabase/292_sales_on_payment_date.sql
supabase/293_dashboard_sales_basis.sql
supabase/294_sales_exclude_voided_invoices.sql
```

Each is idempotent — re-running a migration already applied prints a notice and
changes nothing.
