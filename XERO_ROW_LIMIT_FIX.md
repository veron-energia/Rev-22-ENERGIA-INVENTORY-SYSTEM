# "Walk-in customer" ON INVOICES THAT HAVE A CUSTOMER

Frontend only — **no migration**.

| Check | Result |
|---|---|
| Cause | **PostgREST's 1000-row cap, silently truncating** |
| Pagination verified at boundaries | **0, 1, 999, 1000, 1001, 2500, 16672 — all exact** |
| `npm run typecheck` / `npm run build` | **0 errors / build succeeds** |
| Render-time `setState` guard | **0** |
| Deployment | **none — stopped for manual approval** |

## The cause

I fetched the customer book in one call:

```ts
supabase.from('customers').select('id,full_name,email,phone,address')
```

PostgREST returns at most **1000 rows** per request. Energia has far more, so
only the first page came back. Any invoice whose customer was not in that page
found nothing in the lookup and fell through to "Walk-in customer".

Nothing errored — the request succeeded and simply returned less than it should
have, which is why it looked like a naming problem rather than a missing-data
one.

## The worse instance in the same file

`invoice_items` was fetched the same way. A month of trading can easily exceed
1000 line items, so **invoices would have imported into Xero with lines missing
and totals short** — silently, and into the accounts. That is a materially worse
outcome than a wrong contact name, and you would likely have found it only when
something failed to reconcile.

The invoice query itself had the same cap, so a long enough date range would
have dropped invoices entirely.

## Fixed

- A paginated reader now loops until a short page is returned. Verified at the
  awkward boundaries, including **exactly 1000**, where a naive loop stops one
  page early.
- Customers are fetched **only for the invoices being exported**, in chunks of
  200 ids — lighter than reading the whole book and immune to the cap.
- Invoice items, invoices and every catalogue read go through the same path.

## The same bug elsewhere, found by looking

The **Payment Summary** export calls an RPC returning one row per day *per
method*. A year across three methods is 1,095 rows — over the cap:

```
 31 days x 4 methods =   124 rows
365 days x 3 methods =  1095 rows   <- OVER THE 1000 CAP
365 days x 6 methods =  2190 rows   <- OVER THE 1000 CAP
```

A year-long summary would have quietly lost its later days. Now paginated too.
A month-long range was always fine, which is why it has not shown up.

## Files changed

- `src/components/XeroExport.tsx`
- `src/components/PaymentSummaryExport.tsx`

## Manual deployment steps

`npm install` → `npm run typecheck` (0 errors) → `npm run build` (succeeds) →
deploy **manually**.

**Worth re-checking:** any Xero file already exported may have had lines or
whole invoices missing. Re-export the same range and compare the invoice count
and total against the Invoices page before importing anything into Xero.
