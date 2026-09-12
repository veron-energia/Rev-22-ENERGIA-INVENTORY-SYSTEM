# Refund popup, instalment payments, and exchange attribution

## What changed, and why

| § | Item | State |
|---|---|---|
| 2 | Refund/Cancel popup made compact and consistent | **done** |
| 3 | Instalment as a payment-method selection | **done** |
| 4 | Mixed normal + instalment payments on one invoice | **done** |
| 5 | Exchange staff, affiliate, raised-by, date, original context | **done** |
| 6 | Exchange commission attribution | **done** |
| 7 | Exchange payment handling | **done** — see *Exchange instalments* below |
| 8 | Missing customer name | **done** |

Three defects found while working that nobody had reported are marked **(found)**.

## 8 — the missing customer name

**Root cause.** `findInvoice` never fetched the invoice's customer. The page
resolved names from a list loaded once at page load:

```js
supabase.from('customers').select('*').is('deleted_at', null)
```

capped at 1000 rows by PostgREST and excluding deleted rows. An invoice
belonging to any customer outside that set showed `Customer: —`, even though
the invoice named them perfectly well. An existing top-up covered customers of
*existing exchanges*, not the invoice you had just looked up.

**Fix.** The invoice's own customer is read by id with `fetchCustomersByIds`,
which does not filter deleted rows and so reaches historical customers. Nothing
is guessed from a similar name or number: when the record genuinely cannot be
read the screen says *"Customer record unavailable"* and keeps the invoice link.
Re-searching clears the customer, items, returns, bundle components, staff,
affiliate and payments before loading the new invoice.

## 2 — the popup

Header, scrolling body and footer are now three separate regions, so **Back and
the confirming action stay reachable** however long the review runs; only the
middle scrolls. Colours come from the app's own `--primary` teal — the dialog
had been using a second blue palette (`#1b4d89`). The close control is a
normal-sized glyph in a 44px target, and the focus ring is a 2px teal outline
rather than a 3px halo.

Invoice number appears once, prominently, with status and creation date
beneath. Steps read **Action → Items → Reason → Review**. Actions are compact
cards: *Cancel invoice*, *Full refund*, *Partial refund*, with wording that
covers services, vouchers and credits rather than implying goods are coming
back. Abandoning typed input goes through the project's existing `confirm()`;
closing a finished success message is immediate.

Everything the previous rounds established is untouched and still asserted:
five-day and used-benefit overrides, staff requests and approval, refund
ceilings, return conditions, the separated review sections, the accurate
paid/bonus credit preview, revised-plan confirmation, and the post-refund
refresh of the same invoice.

## 3 and 4 — how an instalment portion is represented

Instalment appears in the searchable payment selector and reveals the actual
method, category, duration and amounts. The separate invoice-wide checkbox is
gone. **Instalment is never sent as a payment method**: it is a sentinel in the
interface only.

The model is a new table, because a promise and a receipt are different things:

| | |
|---|---|
| `invoice_payments` | money that actually arrived. Unchanged, still the only thing `invoice_net_received` counts, still carrying the real method |
| `invoice_payment_arrangements` | the terms for the rest — category, the real underlying method, months, covered amount. Links to a payment row when money has been received under it, and to nothing when it has not |

So *S$100 cash + S$900 over twelve months* is one payment row of 100 and one
arrangement row covering 900. The invoice reads **total 1000 · received 100 ·
remaining 900 · covered 900** and its status stays `partially_paid`. An in-house
promise creates no payment row at all, so nothing can mark the invoice paid for
money nobody has.

`record_invoice_settlement(invoice, {receipts, arrangements}, request_id)` writes
both in one transaction. It is a new name, not another argument on
`record_invoice_payment`: adding arguments creates an overload, and this
repository has been broken twice by exactly that.

**Historical arrangements.** The three columns on `invoices` are not dropped and
not migrated. `invoice_instalment_summary` returns them separately as
`legacy_arrangement`, scoped *"whole invoice"*, with a note explaining they
predate payment-level terms. No payment-level association is fabricated for
them — asserted.

## 5 and 6 — original and exchange attribution, kept apart

`product_exchange_service_staff` records who served **this** exchange.
`invoice_service_staff` continues to record who served the original sale.
Neither is copied into the other; an exchange naming no staff is refused rather
than inheriting yesterday's. Staff must be assigned to the processing store
(owners and managers reach every store). `raised_by` records the issuer and is
deliberately not service staff. `exchange_date` defaults to today in Singapore
and the original invoice's date is never touched, so its five-day window cannot
restart. The original sale is shown as read-only context via
`exchange_original_context`.

**(found) The exchange affiliate could never have worked.**
`product_exchanges.affiliate_id` references the legacy `affiliates` table while
`invoices.affiliate_id` references `customer_affiliates`. The two can never hold
the same value, so the exchange's affiliate silently never reached the
replacement invoice. 305 adds `exchange_affiliate_id` in the invoice's own model
and leaves the historical column exactly as it was.

**Explicit None.** Mirrors `invoices.affiliate_selection_explicit`: choosing None
is recorded as a decision, and a later "inherit" does not resurrect a referrer.

### How additional-payment commission is calculated

The **basis was already correct** and is not changed: both engines see the paid
top-up only — affiliate on the allocated top-up per line, staff on
`invoices.total_amount`, which for a replacement invoice *is* the top-up. So the
brief's example holds: S$100 carried forward plus S$20 paid earns commission on
S$20 alone, and an equal-value exchange earns none while still recording who
handled it.

**(found) What was wrong was who it landed on.** `create_exchange_invoice`
credited `v_ex.created_by` — whoever created the exchange record. With 305
recording who actually served it, crediting the issuer means changing who types
the document changes who is paid. 306 credits
`product_exchange_service_staff`, and falls back to `created_by` only for
exchanges recorded before 305, so their history is read as written rather than
reinterpreted.

## Files and migrations

| File | Change |
|---|---|
| `supabase/304_payment_level_instalments.sql` | **new** — `invoice_payment_arrangements`, `record_invoice_settlement`, `invoice_instalment_summary` |
| `supabase/305_exchange_attribution.sql` | **new** — exchange staff table, `raised_by`, `exchange_date`, `exchange_affiliate_id`, `affiliate_selection_explicit`, `set_exchange_details`, `create_exchange_with_details`, `exchange_original_context` |
| `supabase/306_exchange_commission_attribution.sql` | **new** — patches `create_exchange_invoice` |
| `src/components/invoices/InstalmentPortionFields.tsx` | **new** |
| `src/components/invoices/InvoiceGuidedAction.tsx` | header/body/footer, teal, labels, unsaved-change confirm |
| `src/components/invoices/invoice-controls.css` | popup restyle, instalment portion, exchange attribution |
| `src/pages/InvoicesPage.tsx` | Instalment in the selector, receipts/arrangements split |
| `src/pages/ExchangesPage.tsx` | customer lookup, attribution fields, original context |
| `scripts/invoice-payments/tests/*` | **new** — 2 suites |
| `scripts/exchanges/tests/*` | **new** — 2 suites |
| `scripts/invoice-actions/tests/guided-*.mjs` | new labels, layout and unsaved-change checks |
| `package.json` | `test:invoice-payments`, `test:exchanges` |

No previously deployed migration was edited.

## Tests run

| Command | Environment | Result |
|---|---|---|
| `npm run typecheck` | — | 0 errors |
| `npm run build` | — | succeeds |
| 27 SQL suites | 55441 | **27 passed, 0 failed** |
| `npm run test:invoice-actions` | node + jsdom | 2 files, 2 passed |
| `instalment-fields.test.mjs` | node + jsdom | pass |
| `concurrency.mjs` | 55441 | pass |
| `sh scripts/commissions/tests/run-local.sh` | 55444 | **exit 0**, 11 suites |
| `sh scripts/invoice-dates/tests/run-local.sh` | 55445, rebuilt from the complete migration history | **exit 0**, 69 passes |
| 10 payment/exchange/guided suites on that clean-room database | 55445 | 10 passed, 0 failed |

New suites: `instalment-portions.sql`, `instalment-fields.test.mjs`,
`attribution.sql`, `commission.sql`, plus layout and unsaved-change checks added
to `guided-interaction.test.mjs`.

## Deployment and historical compatibility

In the Supabase SQL editor, after the migrations already listed in the earlier
reports:

```
304_payment_level_instalments.sql      additive; no existing row is altered
305_exchange_attribution.sql           additive; the legacy affiliate_id column is untouched
306_exchange_commission_attribution.sql  requires 305
```

All idempotent. Deploy the application **after** them — the payment panel calls
`record_invoice_settlement` and the exchange form calls
`create_exchange_with_details`, both introduced by these migrations.

Nothing is backfilled. Invoices with the old invoice-wide instalment keep
displaying it; exchanges recorded before 305 keep crediting their creator.

## Remaining

1. **§7 — instalment on an exchange's additional payment.** Exchange payments go
   to `product_exchange_payments`, which has no arrangement model;
   `record_invoice_settlement` covers invoices only. The exchange payment path
   is otherwise unchanged and still correct: equal-value exchanges require no
   payment, the top-up is shown and taken through the existing searchable
   methods, and creation stays separate from payment confirmation. What is
   missing is offering Instalment there. Doing it properly means either
   extending `product_exchange_payments` the same way, or routing the top-up
   through the replacement invoice so it inherits the invoice model — a
   decision worth making deliberately rather than in passing.
2. **Browser testing against a real backend** remains blocked by the
   environment recorded in `GUIDED_REFUND_CANCEL.md` (no Supabase CLI, Docker
   daemon down). The popup's layout, labels, validation and unsaved-change
   behaviour are driven for real in jsdom; the payment and exchange paths are
   covered by database suites.
3. **The legacy `affiliates` table** now has a successor column on
   `product_exchanges`. Retiring the old column is a separate, reviewable change.

---

# Second round: exchange instalments, settlement integrity, real browser testing

## Issue-by-issue

| § | Item | State |
|---|---|---|
| 2 | Instalment on all three exchange types | **done** |
| 3 | One authoritative payment path, chosen and documented | **done** |
| 4 | Later receipts under an arrangement | **done** |
| 5A | Receipt association | **fixed** — linked the *wrong* receipt |
| 5B | Request identity | **fixed** — merged real portions, accepted altered replays |
| 5C | Coverage limits | **fixed** — 1000 invoice took 1500 of arrangements |
| 5D | Permissions and lifecycle | **fixed** — cancelled invoices took new terms |
| 6 | Commission on receipts only | **done**, and the document's claim corrected |
| 7 | Payment displays | **done** |
| 8 | Real browser-to-backend testing | **done** — the limitation was stale |
| 9 | Regression tests | **done** |
| 10 | Legacy affiliate column | **unchanged, deliberately** |

## §5 — every concern was real, and reproduced first

Measured against migration 304 before any change:

| | Behaviour observed |
|---|---|
| A | Two receipts written in one statement share `created_at` to the microsecond, so ordering by it fell back to uuid and `receipt_index: 1` **linked the wrong payment**. An out-of-range index was silently ignored. |
| B | Two legitimate identical portions (two 6-month plans of 100) **merged into one**. The same request id replayed with 24 months/500 instead of 6 months/100 was **accepted as new**. |
| C | A 1000 invoice accumulated **1500** of arrangements across calls. |
| D | A **cancelled** invoice accepted new terms; no role or lifecycle check at all. |

Migration **307** fixes each at its cause: every receipt carries a caller key and
is written through its own derived request id, so the payment it produced is
found exactly; arrangements carry `(request_id, portion_key)` with a unique
index plus a content hash; coverage is measured against what is still owed, net
of receipts already taken under the same portions; cancelled, refunded and
fully settled invoices refuse new terms.

## §3 — the authoritative payment path, and why

**The replacement invoice.** Three reasons:

- the receipts are *already* `invoice_payments` rows — `create_exchange_invoice`
  projects `product_exchange_payments` into them — so the invoice was already
  the authoritative record;
- commission is computed on the replacement invoice, keeping money and
  commission in one place;
- `invoice_payment_arrangements`, and everything 307 hardened, applies unchanged.

`product_exchange_payments` keeps its role as what was taken at the counter and
is projected into the invoice exactly as before — one authoritative receipt per
payment, not two.

The strongest argument for it only appeared afterwards: because exchange money
flows through the invoice, a **later instalment earns its commission through
`record_invoice_payment`, the path that was already correct**. No new commission
machinery exists at all.

## §6 — a correction to this document's earlier claim

The first round said the additional-charge basis was "already correct". The
basis is right; the *timing* was not, and that distinction matters exactly as
§6 warned. `create_exchange_invoice` earned commission unconditionally — harmless
while every exchange was settled in full on the spot, and wrong the moment part
of the top-up is owed, because it would pay commission on a promise.

`invoice_record_payments_internal` earns commission **only in its fully-paid
branch**; a partially paid invoice earns nothing. Migration **308** makes the
replacement invoice behave identically. So:

- carried-forward value never earns again (the invoice is worth the top-up only);
- an unpaid arrangement earns nothing;
- the receipt that completes the charge earns it, once, through the ordinary path;
- an equal-value exchange records its staff and affiliate and earns nothing.

**A divergence from the brief's example, stated plainly.** §6 describes
*progressive* recognition — S$5 received of S$20 earning commission on S$5.
This system does not recognise commission progressively anywhere: ordinary
invoices earn on full payment. Applying progressive recognition to exchanges
alone would make them inconsistent with every other invoice, and doing it
everywhere means changing the shared earn engine's basis — an accounting policy
change, not a bug fix. What is implemented never pays on money not received.

## §8 — the environment limitation was stale

Re-checked rather than assumed, as instructed. **Docker started on request.** A
full local Supabase stack now runs, with the repository's **219 migrations**
applied, a synthetic owner, and the app pointed at `http://127.0.0.1:54321` —
verified in the network panel before any action. Reproducible steps:
`scripts/local-backend/README.md` and `apply.py` (which refuses any non-loopback
database).

**Browser testing found a defect the database and jsdom tests could not.**
`paymentBlocker()` refused to enable *Record Payment* — *"Enter an amount for
every selected payment method"* — because an in-house instalment line
legitimately has nothing received today. The feature was unreachable through the
interface while passing every headless test, because those bypass the blocker.
Fixed, then re-driven through the real UI:

```
Invoice INV-2026-0001   total 1000.00   status partially_paid   paid 100.00
Receipts                Cash 100.00                    (only real money)
Arrangement             in_house · 12 months · 900.00 covered · via Master Card
```

and the screen refreshed without a page reload to
*Partially Paid · Net payments held S$100.00 · Outstanding S$900.00*.

`.env.local` was deleted afterwards so the dev server returns to its configured
endpoint.

## §2 and §7 — what a person sees

Instalment appears in the exchange payment selector for all three exchange
types, revealing the actual method (wallet credit and Instalment itself are
excluded — verified in the live selector, which offered only Cash and Master
Card), category, 3/6/9/12 or a custom duration, the amount covered and the
amount received now.

Labels corrected: *"Top-up paid"* displayed `topup_amount` whether or not a
penny had arrived. Now **Additional charge · Received · Outstanding · instalment
terms**, in the form, the list, the detail panel and the printed receipt, read
from `exchange_payment_position()`.

## §10 — the legacy affiliate column

`product_exchanges.affiliate_id` still references the legacy `affiliates` table
and is **not dropped, and no ids are migrated between the two tables** — they
identify different things and any mapping would be a guess. New attribution uses
`exchange_affiliate_id` in the invoice's own model; explicit None stays None;
historical rows read exactly as written. **No reliable mapping exists for
historical rows, and none is invented.**

## Files and migrations

| File | Change |
|---|---|
| `supabase/307_settlement_integrity.sql` | **new** — receipt keys, portion identity, coverage, lifecycle, `invoice_arrangement_receipts`, `invoice_arrangement_balances` |
| `supabase/308_exchange_instalments.sql` | **new** — part payment of the top-up, truthful replacement-invoice status, arrangements on exchanges, `exchange_payment_position`, commission gated on receipt |
| `src/pages/InvoicesPage.tsx` | receipt/portion keys; `paymentBlocker` allows a zero-receipt instalment |
| `src/pages/ExchangesPage.tsx` | Instalment in the exchange selector, arrangements on submit, corrected labels and detail figures |
| `scripts/invoice-payments/tests/settlement-integrity.sql` | **new** |
| `scripts/exchanges/tests/instalments.sql` | **new** |
| `scripts/local-backend/{README.md,apply.py}` | **new** — reproducible local stack |

## Tests actually run, and results

| Command | Environment | Result |
|---|---|---|
| `npm run typecheck` / `npm run build` | — | 0 errors / succeeds |
| 29 SQL suites | 55441 | **29 passed, 0 failed** |
| `npm run test:invoice-actions` | node + **jsdom, stubbed RPC** | 2 files, 2 passed |
| `npm run test:invoice-payments` | node + **jsdom, stubbed RPC** | 1 passed |
| `npm run test:invoice-actions:concurrency` | 55441, independent psql sessions | pass |
| `npm run test:invoice-payments:concurrency` | 55441, independent psql sessions | **11 checks, all pass** |
| `sh scripts/commissions/tests/run-local.sh` | 55444 | **exit 0**, 11 suites |
| `sh scripts/invoice-dates/tests/run-local.sh` | 55445, rebuilt from the complete migration history | **exit 0**, 69 passes |
| 12 payment/exchange/guided suites on that clean-room database | 55445 | 12 passed, 0 failed |
| **Real browser → real API** | **local Supabase stack, 219 migrations, synthetic owner** | **mixed cash + instalment recorded and verified in the database** |

Scope, stated accurately: the jsdom suites drive the real components with a
**stubbed** Supabase client — they cover what a person sees and is stopped from
doing, not the API. The SQL suites cover the database. Only the local-stack run
above exercises browser → HTTP → PostgREST → database.

## Deployment order

After the migrations already listed above:

```
307_settlement_integrity.sql     (requires 304)
308_exchange_instalments.sql     (requires 305, 306, 307)
```

Both idempotent and additive. **Deploy the application after them** — the
payment panel and exchange form call functions these introduce.

**A contract change to note.** `record_invoice_settlement` now requires a `key`
on every receipt and portion. It was introduced in 304 in this same unreleased
series and the only caller is this application, so nothing in production depends
on the old shape — but a client deployed *before* 307 would fail against it.
Deploy migrations first, then the app, and the window does not arise.

## Recovery

1. Redeploy the previous application build.
2. Restore the prior definitions of `record_invoice_settlement`,
   `create_exchange_invoice`, `create_exchange_with_details` and the three
   exchange creators. Dropping 307's unique index and
   `invoice_arrangement_receipts` restores 304's behaviour, defects included.
3. **Executed effects stay**: receipts, arrangements, commissions and audit rows
   are history. Correct them through the supported audited operations.

## Remaining limitations

1. **Progressive commission recognition** is not implemented — see §6 above. It
   is a policy decision about the shared earn engine, not an oversight.
2. **Browser coverage is partial.** The ordinary invoice mixed payment was
   driven end to end against the real API. The exchange flows, refunds and
   mobile/keyboard passes were verified through the database and jsdom suites,
   not clicked through the live stack; the stack and steps are committed so that
   is now a short task rather than an environment problem.
3. **Concurrency is covered.** `scripts/invoice-payments/tests/concurrency.mjs`
   runs independent psql sessions released together: three identical
   submissions settle once (one arrangement, one receipt, coverage not
   multiplied); two competing 700 arrangements on a 1000 invoice never exceed
   what is owed; and a later receipt racing a cancellation leaves money and
   terms consistent. No deadlocks.
