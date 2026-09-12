# Credit preview, single-customer packages, and the stale invoice

Three reported defects. Each was reproduced before anything was changed, and
one of the three turned out to have a cause that no amount of reading the
application code would have found.

## 1. The credit-removal preview described the wrong quantity

**Reported** (INV-2026-0210): a S$500 package granting S$500 paid + S$25 bonus
credit previewed as *"Remove S$476.19 paid credit, Remove S$23.81 bonus credit"*,
while the actual deduction was correct.

**Root cause.** Those two figures are S$500 — the money — split between the
benefits in proportion to what each was granted:

```
500 × 500/525 = 476.19        500 × 25/525 = 23.81
```

That is `invoice_benefit_values.paid_value`: each benefit's share of the
**price**, which exists to cap a refund at the unused portion. The plan's
summary printed it under the label "credit". The two are different quantities
and were conflated.

Reproduced in an isolated database, which printed 476.19 / 23.81 exactly, and
then executing the refund cleared both lots to zero — confirming the execution
was right and only the description was wrong.

**Fix** (`303`). The plan now derives the credit actually removed using the
engine's own rule, including 299's exact clearing when the whole refundable
value is taken, and keeps four quantities apart:

| | |
|---|---|
| Money returned | what goes back, by payment source |
| Accounting value | the benefit's share of the price — unchanged, still caps the refund |
| Credit removed | the real paid / bonus face value taken back |
| Units revoked | whole unused voucher units |

**Before → after** for the reported case:

```
before   Remove S$476.19 of paid credit.   Remove S$23.81 of bonus credit.
after    Money returned: S$500.00
         Remove S$500.00 of paid credit.   Remove S$25.00 of bonus credit.
```

Credit removed exceeds money returned, correctly: S$525 of credit for S$500,
because the bonus was a gift. No deduction changed.

## 2. Single-customer credit packages and premium bundles could not be sold

**Reported**: both fail with `No price set for "<NULL>" in this store`, while
Split Across Customers works.

**Root cause — a function overload in the live database.** The message comes
from the ordinary *product* pricing branch, reached because the line's kind
matched no branch; it then read `product_id`, which a package line does not
carry, and a NULL product's name renders as `<NULL>`.

Read-only inspection of the live catalogue showed **two** `create_invoice`
functions:

| Overload | Called by the app | Credit package | Premium bundle |
|---|---|---|---|
| `create_invoice(…, jsonb)` — 8 args | **yes** | **NO** | **NO** |
| `create_invoice(…, uuid)` — 7 args | no | yes | yes |

Migration 151, which added those branches, chose what to patch by name alone:

```sql
select pg_get_functiondef(p.oid) into v_def
  from pg_proc p ... where p.proname = v_name;
```

With two overloads installed that reads an arbitrary row. It patched the
7-argument overload nothing calls, reported success, and the function the
application actually calls never gained the branches. A clean install has only
one overload — which is why every test environment passes and only the live
database fails, and why this survived so long.

Split Across Customers was unaffected because it never goes through
`create_invoice`: it calls `create_split_credit_package_invoices`.

**Fix** (`302`). Re-runs 151's patch — identical in what it inserts — over
*every* overload, skipping any that already has the branches and any whose item
loop is not in the expected shape. The same defensive loop migration 244
adopted after hitting this trap. Exposed as
`repair_create_invoice_package_branches()` so it can be re-run and so the test
can prove it repairs the fault.

Nothing was faked to make this pass: no dummy products, no zero prices, no
weakened pricing checks, no client-supplied price trusted. Invalid identifiers
and incomplete voucher selections still fail, now by name rather than `<NULL>`.

**Diagnostic**: `scripts/invoices/check-create-invoice-overloads.sql` — read-only,
one SELECT. Run it before and after 302; the row marked `called_by_app = yes`
must read `yes` for both branches.

## 3. The invoice behind the dialog did not update

**Reported** (INV-2026-0212): the dialog reports a S$15 refund; after Close the
invoice still reads Paid, net S$15, refunded S$0.

**Verified first, not assumed.** `refund-completion.sql` asserts the **stored**
state: a full S$15 refund leaves status `refunded`, net held `0.00`, refunded
`15.00`, with the original payment row intact. The money was always right.

**Root cause.** `openDetail(inv)` takes the invoice **row from the list**. After
an action the callback ran `loadAll()`, which refreshes the list — but the open
`detail` object was still the row as it was when the invoice was opened.

**Fix.** A `refreshDetail(invoiceId)` that re-reads the invoice by its own id
and reloads items, payments, financial position, therapy, revisions and
benefits through the existing path, then refreshes the list behind it. Guarded
so a slow refresh cannot overwrite newer state or reopen an invoice the user has
navigated away from.

Refresh failure is now separate from action failure: the dialog says *"This was
saved"*, warns the figures behind may be out of date, and offers a reload that
**re-reads only** — asserted by a test that counts the RPC calls.

A partial refund reports its real remaining balance and is never called fully
refunded; a cancellation reads Cancelled with the money still shown as due.

## 4. The popup

Steps stay **Action → Items → Reason → Review**. Changes:

- Actions renamed to **Cancel invoice / Full refund / Partial refund**, with
  wording that covers services, vouchers and credits rather than implying goods
  are coming back.
- Invoice number, current status and creation date in the header; a visible
  close control on every step.
- The review is now four separate sections, driven by the plan's `effects`
  rather than one flat list: **Money returned** (with destinations),
  **Credits and benefits cancelled** (real credit and voucher units, by
  recipient), **Stock returned**, **Overrides required**. Sections appear only
  when they apply.
- Final button says what will happen: `Submit refund request`,
  `Confirm S$500.00 refund`, `Confirm cancellation`, or
  `Confirm cancellation and S$200.00 refund`.
- Money returned carries: *"Recording this does not send money anywhere."*
- Tabular figures, wrapping, 44px touch targets, 16px inputs, and a scrollable
  dialog so every field and action stays reachable on a narrow screen.

## Files

| File | Change |
|---|---|
| `supabase/302_create_invoice_package_branches.sql` | **new** — repairs every `create_invoice`/`update_invoice` overload |
| `supabase/303_credit_removal_preview.sql` | **new** — patches `invoice_action_plan` |
| `src/pages/InvoicesPage.tsx` | `refreshDetail`, staleness guards on `openDetail` |
| `src/components/invoices/InvoiceGuidedAction.tsx` | sectioned review, labels, refresh retry |
| `src/components/invoices/invoice-controls.css` | review sections, close control |
| `scripts/invoice-actions/tests/credit-preview.sql` | **new** |
| `scripts/invoice-actions/tests/refund-completion.sql` | **new** |
| `scripts/invoice-packages/tests/create-overload-repair.sql` | **new** |
| `scripts/invoices/check-create-invoice-overloads.sql` | **new**, read-only |
| `scripts/invoice-actions/tests/guided-interaction.test.mjs` | new sections, labels, refresh-retry |
| `scripts/invoice-actions/tests/guided-ui.test.mjs` | new labels, close control |
| `package.json` | `test:invoice-packages` |

No previously deployed migration was edited. No production record was changed;
the live database was read with `SELECT` only.

## Verified

| Command | Environment | Result |
|---|---|---|
| `npm run typecheck` | — | 0 errors |
| `npm run build` | — | succeeds |
| `npm run test:invoice-actions` | node + jsdom | 2 files, 2 passed |
| `npm run test:invoices` | node | 10 passed |
| `npm run test:invoice-actions:concurrency` | 55441 | all checks pass |
| 24 SQL suites | 55441 | 24 passed, 0 failed |
| `sh scripts/commissions/tests/run-local.sh` | 55444 | exit 0, 11 suites |
| `sh scripts/invoice-dates/tests/run-local.sh` | 55445, rebuilt from the complete migration history | exit 0, 69 passes |
| 8 guided + package suites on that clean-room database | 55445 | 8 passed, 0 failed |

The overload fault is not simulated by hand-waving: `create-overload-repair.sql`
strips the branches from the live signature to reproduce
`No price set for "<NULL>" in this store` exactly, then proves the repair fixes
it, is idempotent, and leaves no partial invoice on failure.

## Deployment

Migrations, in the Supabase SQL editor, after the ones already listed in
`GUIDED_REFUND_CANCEL.md`:

```
302_create_invoice_package_branches.sql     (fixes package creation)
303_credit_removal_preview.sql              (requires 296 and 299)
```

Both are idempotent. Deploy the application after them: the review reads the
plan's new `effects` block, and falls back to the flat summary if it is absent,
so an app deployed ahead of 303 degrades rather than breaks.

**Verification that needs the live database** — I could read it but not change it:

1. Run `check-create-invoice-overloads.sql`. Today the `called_by_app = yes`
   row reads `NO / NO`. After 302 it must read `yes / yes`.
2. Create a single-customer S$1,000 credit package and a S$15,000 premium
   bundle with its 150 reward vouchers at Energia Rev 22 (Adelphi); confirm the
   totals and the transition to the payment view.
3. Retest Split Across Customers for both, to confirm no regression.
4. Open a package invoice's Refund/Cancel review and confirm it reads
   *Money returned S$500 · paid credit S$500 · bonus credit S$25*.
5. Refund a S$15 invoice and confirm the invoice behind the dialog reads
   Refunded / S$0 held / S$15 refunded without reopening it.

## Noted, not changed

The stale 7-argument `create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)`
in the live database is called by nothing and is the reason this defect was
possible. 302 patches it along with the rest rather than dropping it: removing a
function from a live database is destructive and outside this task. It is worth
dropping under review — the diagnostic lists it.
