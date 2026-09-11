# THE INVOICE LIST READS IN INVOICE-NUMBER ORDER

| Check | Result |
|---|---|
| `scripts/invoices/tests/invoice-order.test.mjs` | **12 assertions, passing** |
| `scripts/invoices/tests/invoice-list-paging.test.mjs` | **13 assertions, passing** |
| `npm run test:invoices` | **10 tests, 0 failing** |
| Reverting the comparator | test fails: `9999, 10001, 10000` vs expected `10001, 10000, 9999` |
| `npm run typecheck` / `npm run build` | **0 errors / build succeeds** |
| Database changes | **none — this is interface ordering only** |
| Deployment | **none — stopped for manual approval** |

## What was wrong

One day's invoices came out **0168, 0169, 0172, 0171**.

The list was ordered by `business_date` descending and then by `id`. Every
invoice on that screen shared 02/09/2026, so the date decided nothing and the
tiebreaker took over — and `id` is a uuid, which is effectively random.

## What it does now

Ordered by `invoice_no`, newest number first: **0172, 0171, 0169, 0168**.

That is the same reading direction the list always had (newest at the top), so
nothing else about the page moves. To read oldest-first instead, drop the
argument swap in `byInvoiceNoDesc` — it is a one-line change.

## Two formats, both sorted correctly

```
INV-2026-0172               normal invoices, sequence padded to 4
SG-ADL-EX-INV-2026-00001    exchange invoices, padded to 5, numbered per store
```

A plain text sort is right for nearly all of this and wrong in one place: when a
year outgrows its padding the sequence gains a digit, and `INV-2026-10000` sorts
*before* `INV-2026-9999` because `'1' < '9'`. `compareInvoiceNo` compares digit
runs as numbers and everything else as text, so the sequence is correct at any
length while the two formats still group apart by their prefix, and each store's
exchange run stays with its own store code.

This is not a hypothetical: the test asserts `'INV-2026-10000' < 'INV-2026-9999'`
is genuinely true as strings, so the bug is real and the guard is meaningful.
Your current numbering is at 0172, so nothing is misplaced today.

## The part that was not just cosmetic

`loadInvoiceList` pages through invoices 500 at a time with `.range()`. Paging is
only safe when the server's order is a **total** order — otherwise a page
boundary landing inside a group of equal values can repeat a row on one page and
drop it from the next.

The old key was `business_date, id`. `business_date` is nullable, and the
fallback was a uuid. The new key is `invoice_no`, which is `NOT NULL` and
`UNIQUE` — verified against the schema — so it cannot tie and cannot lose a row.

`invoice-list-paging.test.mjs` builds 1,203 invoices behind a stub that honours
`.order()` and `.range()` exactly as PostgREST does, then asserts all 1,203 come
back, none repeated, strictly descending the whole way — not merely correct at
the ends. It also covers an exactly-full final page, the padding overflow, and
a failing page being surfaced as an error rather than a short list.

## Where the sort happens, and why in both places

- **Server side** — `.order('invoice_no', { ascending: false })` makes paging
  safe and returns the rows very nearly in the right order already.
- **Client side** — `rows.sort(byInvoiceNoDesc)` after the final page. PostgREST
  can only order that column as text, which misplaces a sequence past its
  padding width. Every page has been fetched by that point, so sorting the whole
  set is complete rather than per-page.

## What did not change

No migration, no database function, no payment, invoice or audit record. The
page's filters, search and status handling are untouched — `InvoicesPage` never
sorted anything itself, so the loader was the only place this lived.
