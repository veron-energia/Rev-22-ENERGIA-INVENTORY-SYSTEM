# GUIDED REFUNDS AND CANCELLATIONS

Supersedes the earlier version of this file, which overstated several things.
Corrections are marked **[corrected]** and explained rather than quietly dropped.

## Issue-by-issue completion

| # | Issue | Root cause | Fix | State |
|---|---|---|---|---|
| 1 | Activated therapy was a hard blocker | `refund_invoice_recorded` raised `Consumed or activated therapy cannot be refunded`; no termination path existed | 296 gives the engine an authorized termination; the plan reports it as an override needing a stated amount | **done** |
| 2 | Approvals bypassed the validated workflow | `ApprovalsPage` called the pre-295 `resolve_invoice_action`: no window check, no override reason, no confirmed goods, no revalidation | 297 + UI: Approvals opens the same guided review; the legacy function now delegates or refuses | **done** |
| 3 | Cancellation executed an unreviewed plan | the cancel branch re-derived a fresh `refund_full` plan at execution; the reviewed cancel plan carried `refund_amount = 0`, so the hash never covered the money | 296: the cancel plan derives and hashes the whole combined effect; execution uses only the reviewed plan | **done** |
| 4 | The refund result was discarded | `v_result` was overwritten by the cancellation's result | 296 returns `refund` and `cancellation` separately, plus `refund_recorded`, `goods_returned`, `refund_still_due` | **done** |
| 5 | Confirmed stock conditions were thrown away on cancellation | `cancel_invoice_recorded` → `restore_invoice_stock` restores **all** outstanding units as sellable and knows nothing of condition | 296 adds `record_invoice_stock_return`, written before the cancellation so nothing outstanding remains to restore | **done** |
| 6 | No authorized larger refund | every benefit line was capped at its unused paid value | 296: the excess is allowed with an override and recorded as `authorized_excess`; benefit reversals stay capped at what is genuinely unused | **done** |
| 7 | Rentals could not be cancelled while out | `cancel_invoice_recorded` refused; `cancel_invoice_rentals` only touched unfulfilled rentals | 300: cancelling leaves the rental **awaiting return** with stock untouched; `receive_returned_rental` takes destination and condition | **done** |
| 8 | No destination/condition selection | not in the guided flow | destination + condition selectors in the dialog, wired to `receive_returned_rental` | **done** |
| 9 | Premium bundles untested | only credit packages were covered | `premium-bundle.sql` — and it found a real defect (#15) | **done** |
| 10 | No parallel-session tests | only single-session repeats | `concurrency.mjs` — independent psql sessions released together; found a real race (#14) | **done** |
| 11 | Commission runner failed | `run-local.sh --through 272` ran `scripts/invoices/regression.sql`, which has expected 292's payment-date rule since 292 | bootstrap gained `--from/--no-reset`; the runner pins 272 for the historical checks, then upgrades to the complete set for the current ones | **done** |
| 12 | Reporting-basis conflict | — | no conflict: resolved by the user on the record (see below) | **evidence** |
| 13 | `created_at` immutability overstated | the claim rested on the column being used, not protected | verified unprotected, then **made true** by 301 | **done** |
| 14 | *(found)* duplicate requests under load | the uniqueness checks were unlocked `SELECT`s | 298: two partial unique indexes plus a `unique_violation` handler | **done** |
| 15 | *(found)* a cent survived a full reversal | money→units→money at 2 dp rounds twice | 299: taking the whole refundable value clears the balance exactly | **done** |
| 16 | *(found)* cancelled invoices reported no refund due | `invoice_charge_total` reduces for refunds only, never for cancellation | 296 applies cancellation where the position is presented | **done** |
| 17 | *(found)* plan total and line amounts disagreed | the payment ceiling capped the total but not the lines | 296 caps lines and their benefit allocations with it | **done** |

## [corrected] The financial engines DID need changes

The earlier version said *"the refund and cancellation engines were already
correct and complete… Nothing about how money moves was changed."* That was
true of 295 and wrong as a general claim. Completing the authorized behaviour
required changing `refund_invoice_recorded` itself, three times:

- an authorized termination path for activated therapy (296);
- an authorized excess above the unused-benefit cap (296);
- exact clearing of a benefit balance on a full reversal (299).

All three are anchored patches that keep the function's signature identical, so
no overload is created and every existing caller is unaffected — the failure
mode migration 243 in this repo hit by adding arguments.

## [corrected] The runner failure and "all passing"

The earlier version claimed all suites passed and separately recorded a failing
commission runner. Both cannot be true. The runner genuinely failed; it is now
fixed at its cause (#11) and reported below with its actual exit code.

## [corrected] `created_at` is now genuinely protected

The claim that the window could not be restarted "because the column cannot be
moved" was not earned. Measured before changing anything:

```
triggers protecting invoices.created_at   0
functions writing invoices.created_at     0
RLS update policies on invoices           none
a plain UPDATE moving it                  succeeded
```

301 adds `invoice_created_at_immutable`, which refuses any change to
`created_at` from a non-superuser. Verified in both directions: a role with
`UPDATE` and `BYPASSRLS` is refused; a superuser (a DBA at the console, and the
fixtures that must age an invoice to test the boundary) may still do it
deliberately. Application roles have no direct `UPDATE` on `invoices` at all and
reach it only through security-definer functions, none of which write the
column — `guided-actions.sql` now asserts both facts so a future change cannot
silently reintroduce the hole.

## [corrected] Rollback does not undo executed money

The earlier version said restoring two functions "restores the previous
behaviour exactly". It restores the *code*. It does not undo a refund that has
been paid, stock that has been put back, credit that has been revoked, or an
entitlement that has been terminated. Three separate things:

1. **Reverting code** — re-run the prior definitions (see Recovery). Immediate,
   and changes no data.
2. **Executed financial and audit history** — refunds, stock dispositions,
   credit ledger entries, terminations and audit rows **stay**. They are records
   of things that happened.
3. **Correcting a business transaction** — through the supported audited
   operations (`correct_invoice`, `correct_invoice_payment`, `reopen_invoice`,
   a compensating refund), never by editing tables.

**Do not** restore the pre-295 `complete_invoice_finance_request` as a recovery
step. That version marks *every* pending refund request approved on *any*
refund insert; it is the defect 295 fixed, and reinstating it would tell
requesters their requests were granted when nothing happened.

## §10 — the reporting basis, with evidence

No business question is outstanding. Earlier in this conversation the user set
the rule and then confirmed it:

> "Created in last month and payment done in this month. For this situation,
> the money should update on the payment date."

and, asked directly about a late payment, chose *"count it this month"*.
Migration 292 implements exactly that. **The tests exercise payment-date
attribution for receipts and refund-date for reductions.** Cancellation and a
later refund do not reduce sales twice — the cancellation removes the invoice
from Sales (294) and the refund reduces its own period only. TikTok settlement
rules and the completed payout functionality are untouched.

## The rule matrix

| Item type | Five-day rule | Reversed automatically | Owner/Manager override |
|---|---|---|---|
| Products | Yes | outstanding deductions, defaulted to the store they left | outside the window |
| Vouchers (issued) | Yes | unused units revoked; tracked stock restored | any unit redeemed |
| Promotions | Yes | the components actually issued on that invoice | as for their components |
| Purchased therapy | Yes | unused entitlements cancelled | **activated — terminated on an override with a stated amount** |
| Therapy Services | Yes | undelivered sessions; capped at the unused portion | any session delivered |
| Credit packages | Yes | remaining paid and bonus credit | any credit spent |
| Premium bundles | Yes | paid credit, bonus credit, vouchers, therapy, goods | any bundled benefit used |
| Special products | Yes | stock, once destination and condition are confirmed | outside the window |
| **Rentals** | **No** | cancelling leaves the item **awaiting return**; stock moves only on confirmed receipt | standard approval only |

Mixed invoices: the rental exemption applies only to rental lines; any
non-rental line keeps the window. An override waives **time or usage** only —
never authorization, the payment ceiling, duplicate-refund protection or
truthful stock handling.

## Changed objects

**New migrations** (290–295 and everything earlier are untouched):

| Migration | Objects |
|---|---|
| `296_authorized_refund_exceptions.sql` | patches `refund_invoice_recorded`; replaces `refund_purchased_therapy`, `invoice_action_plan`, `resolve_invoice_action_v2`, `invoice_financial_position`; adds `record_invoice_stock_return` |
| `297_approvals_surface.sql` | adds `invoice_action_request_detail`; replaces `resolve_invoice_action` |
| `298_request_uniqueness.sql` | adds two partial unique indexes on `approval_requests`; patches `request_invoice_action_v2`; closes pre-existing duplicates as superseded |
| `299_benefit_reversal_rounding.sql` | patches `refund_invoice_recorded` |
| `300_rental_and_special_returns.sql` | adds `rental_awaiting_return`, `invoice_rentals_awaiting_return`, `receive_returned_rental`; replaces `cancel_invoice_rentals`; patches `cancel_invoice_recorded` |
| `301_protect_invoice_creation_time.sql` | adds `guard_invoice_created_at` + trigger `invoice_created_at_immutable` |

**Application**: `InvoiceGuidedAction.tsx` (approval mode, rental destinations,
truthful completion messages), `ApprovalsPage.tsx` (opens the guided review;
inventory adjustments unchanged), `invoice-controls.css`, `package.json`.

**Tests**: five SQL suites and three Node suites under `scripts/invoice-actions/tests/`;
`scripts/invoices/tests/rental-lifecycle.sql` and `sales-status-basis.sql`
restated for the new rules; `scripts/commissions/bootstrap-local.py` and
`scripts/commissions/tests/run-local.sh`.

## Commands run, and what they returned

All on isolated local clusters. No production database was contacted.

| Command | Environment | Result |
|---|---|---|
| `npm run typecheck` | — | 0 errors |
| `npm run build` | — | succeeds |
| `npm run test:invoice-actions` | node | 2 files, 2 passed, 0 failed |
| `npm run test:invoices` | node | 10 passed, 0 failed |
| `npm run test:invoice-actions:concurrency` | 55441 | 22 checks, all pass |
| 21 SQL suites (`scripts/invoices/tests/*`, `regression.sql`, `scripts/invoice-actions/tests/*`) | 55441 | 21 passed, 0 failed |
| `sh scripts/commissions/tests/run-local.sh` | 55444 | **exit 0**, 11 suites pass |
| `sh scripts/invoice-dates/tests/run-local.sh` | 55445, rebuilt from the complete migration history | **exit 0**, 69 passes |
| 5 guided SQL suites on that clean-room database | 55445 | 5 passed, 0 failed |

New assertions: `guided-actions.sql` 27, `cancel-refund-combined.sql` 26,
`therapy-termination.sql` 25, `premium-bundle.sql` 18, `override-paths.sql` 17,
`concurrency.mjs` 22, `guided-interaction.test.mjs` 27, `guided-ui.test.mjs` 10.

Both installation paths are verified: **upgrade** from the current baseline
(296–301 applied to an already-migrated 55441) and **install from the complete
history** (55445 rebuilt from scratch, all migrations, then the suites re-run).

## Environment limitation — no local Supabase stack

Full browser-level testing against a working backend could not be run here:

```
supabase CLI   not installed
docker         present, daemon not running
.env           points at the production project
```

Driving the real app therefore means driving production, which this task
forbids. Instead `guided-interaction.test.mjs` mounts the real component in
jsdom and drives it with real DOM events against a stubbed RPC layer — stepping,
validation, submission payloads, the revised-plan path, retry, refund-due
wording and blocked invoices are all asserted (27 checks). The database side
those calls reach is covered by the SQL suites.

To close this gap when Docker is available:

```bash
brew install supabase/tap/supabase && docker desktop start && supabase start
```

then point `.env.local` at the printed local URL and anon key, apply
`supabase/*.sql` in order, and exercise: staff partial refund → Approvals
approval → rejection visibility → activated-therapy override → bundle reversal →
rental awaiting return and receipt → revised-plan confirmation → refund due then
actual refund, at 375px and by keyboard.

## Deployment order

`git push` ships files; it does not run SQL. In the Supabase SQL editor:

```
292_sales_on_payment_date.sql
293_dashboard_sales_basis.sql
294_sales_exclude_voided_invoices.sql
295_guided_invoice_actions.sql
296_authorized_refund_exceptions.sql      (requires 295)
297_approvals_surface.sql                 (requires 295, 296)
298_request_uniqueness.sql                (requires 295)
299_benefit_reversal_rounding.sql         (requires 296)
300_rental_and_special_returns.sql        (requires 295)
301_protect_invoice_creation_time.sql     (requires 295)
```

Each is idempotent and re-running one already applied prints a notice. Deploy
the application **after** the migrations: the guided flow calls functions that
296–301 introduce.

**298 changes data.** It closes duplicate *pending* requests as superseded
before adding its indexes. Pending requests have changed nothing by definition;
approved and rejected requests are never touched. Run
`select * from approval_requests where response_note='Closed by migration 298'`
afterwards to see exactly what it closed.

## Recovery

1. **Application** — redeploy the previous build.
2. **Database code** — restore the prior definitions of the objects listed under
   *Changed objects*. `pg_get_functiondef` output taken before deployment is the
   safest source. Dropping 298's two indexes restores the old (racy) behaviour;
   dropping 301's trigger restores the unprotected column.
3. **Executed effects stay.** Refunds, stock dispositions, credit ledger
   entries, terminated entitlements, received rentals and audit rows are
   history. Correct them through `correct_invoice`,
   `correct_invoice_payment`, `reopen_invoice` or a compensating refund.
4. **Never** reinstate the pre-295 `complete_invoice_finance_request`.

## Still outstanding

- **Browser testing against a real backend** — blocked by the environment above;
  steps given.
- **Special-product *sale* returns (not rentals)** reuse the ordinary product
  path (outstanding deductions, condition, damaged/not-returned tracked
  separately). The dedicated warehouse destination selector is wired for
  rentals; a special product sold outright returns to the store it left, which
  is the existing behaviour and is covered by `rental-lifecycle.sql`.
- **Multiple benefit recipients on a bundle** — `transfer_invoice_unused_benefit`
  moves a benefit to another customer and the plan follows the source-linked
  allocation, but the combination *transferred-then-refunded* has no dedicated
  test.
