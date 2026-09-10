# Invoice takeover checklist — agent two

Ownership of the invoice work passed to agent two on 10 September 2026. Agent
one is stopped. Nothing was reset, stashed, discarded or rebuilt: the working
tree was inspected and continued.

**Nothing is committed, pushed or deployed. No production data was touched.**

## What the handover state actually was

The notes were behind the folder, so every observation below was checked rather
than accepted.

| Claim in the notes | Verified state |
|---|---|
| Invoice migrations occupy 170–187 | **170–191 and 193** exist; 188–191 and 193 were written after the notes were last updated. **192 does not exist** and nothing references it — a numbering gap, not a missing file |
| Therapy integration is a separate future check | **250–253 already exist**, written 10 September, integrating credit transfer policy, therapy-voucher snapshots, session reconciliation and refund commission basis |
| Migration 130 is a known baseline failure | **False.** Migration 66 already contains 130's fix; 130's own idempotence guard tested a comment sentence that 66 words differently, so it fell through and raised. Fixed |
| Combined migration history untested | Confirmed untested. Agent one's fixture stops before 170 and never applied 200+; a combined build had never been attempted |
| Invoice changes uncommitted | Confirmed: 5 tracked files modified, invoice components/migrations/tests untracked. All preserved |

## The checklist

| Requirement | Existing implementation | Verification evidence | Remaining gap | Next action |
|---|---|---|---|---|
| Combined migration history builds | Agent one's fixture built pre-170 only | **191 migrations applied, 0 failures**, from an empty database, reproducibly (`scripts/integration/bootstrap-integration.py`) | None | — |
| Correction workflow across statuses | 170–173, 179–182 (agent one) | `regression.sql` — metadata edits across nine statuses, stable item IDs, saved prices/FOC | None found | — |
| 23502 on `edit_paid_invoice` | Replacement builder always supplies the validated invoice ID | Exercised by `regression.sql` with an affiliate-only change | **Original production cause still unproven** — no production access | Run `diagnose-local-definition.sql` against the deployed database |
| Payments, refunds, cancellation, reopening | 174–175, 179, 184 (agent one) | 12 SQL test files, 22 named assertions, all passing on the combined history | None found | — |
| Concurrency and request replay | 185, 188 (agent one) | `concurrency.mjs` — 2 checks, concurrent refunds and four-way retries | None found | — |
| Mobile promotion controls | `invoice-controls.css`, components (agent one) | `browser.mjs` — real components at **320, 375, 390, 430 px**, all passing | **Real iOS Safari untested** — no device available | Manual check on a device before rollout |
| Credit eligibility matrix through invoicing | 242 (agent two, therapy) + 250 (agent one) | `cross-feature.sql` — matrix enforced through the real payment path, over and above per-package permissions | None found | — |
| Package/bundle commission basis | 243 (agent two) + 253 (agent one) | `cross-feature.sql` — third-party rate on money received; redeeming credit earns nothing further | Historical over-payment not repaired (deliberate) | Run `commission-diagnostic.sql` on an approved snapshot |
| Therapy session reconciliation | 244–245 (agent two) + 252 (agent one) | `therapy-session-reconciliation.sql`; `regression.sql` now refunds a session and reconciles the entitlement | None found | — |
| Therapy voucher snapshots | 241 (agent two) + 251 (agent one) | `therapy-voucher-snapshots.sql` — terms survive transfer and reopening | None found | — |
| **Saving a credit package** | 243 patched the upsert functions by signature | **Was broken.** Migration 94 redefines `upsert_credit_package` with twelve more arguments, so 243 matched nothing, the function kept honouring the caller's classification and the new constraint rejected the save | Fixed in 243 — patches by name across every overload | — |
| **Selling and refunding a voucher** | Refused for every voucher line | **Was incomplete, not merely historical:** a voucher sold entirely under the current code could not be refunded either | Completed in **254** | — |
| Rentals and special products | 106, 179 (agent one) | **Was defective.** An *overdue* rental — the item still out with the customer — did not block cancellation, correction or reopening; and an unfulfilled rental was left standing after its invoice was cancelled | Fixed in **255**, covered by `rental-lifecycle.sql` | — |
| Promotion-embedded vouchers | 187 review workflow | Still pending review | **Genuine evidence gap** — a voucher's share of a bundled price is not derivable | Record allocations via `record_invoice_benefit_values` |
| Historical data review | `diagnose-historical-data.sql`, `diagnose-benefit-review.sql` | Scripts read-only and unchanged | Needs an approved snapshot | Operator runs them before rollout |

## What agent two changed

**Defects fixed**

1. **`243` patched nothing** (production-breaking). Signature lookup from migration 79 against functions redefined by 94/96. Now resolved by name across every overload, and it refuses rather than leaving a function that writes a value the constraint rejects. Without this, saving any credit package from the Therapy page failed.
2. **`130` false baseline failure.** Guard now tests the rule (`r.related_order_id is not distinct from v_related`) rather than a comment sentence. Applies cleanly and idempotently; the documented exclusion is gone.
3. **Sold vouchers were never issued** (`254`, new). Paying an invoice now records the units sold into `customer_reward_vouchers` with a matching `invoice_benefit_values` row, so refunds, cancellation, transfer and reopening all work through machinery that already existed. `invoice_untracked_voucher()` became evidence-based instead of blanket.
4. **A voucher line could be refunded without revoking the voucher.** The benefit-revocation block in `refund_invoice_recorded` is gated on `line_kind in ('credit_package','premium_bundle')`, so a voucher line's allocation was accepted and ignored — money back, voucher kept. The gate now includes voucher lines with issued units, and an unallocated voucher refund is refused.
5. **Rentals outlived their invoices** (`255`, new). 179 guarded only `active` and `paid`. An **overdue** rental could have its invoice cancelled — the record of what was rented simply gone — and an **unfulfilled** one was left live after cancellation. The rule is now: a rental the customer *has* blocks; a rental they have *not received* is cancelled with the invoice, audited and once only.
6. **Dead controls on the Therapy page.** The commission-classification dropdowns offered a choice 243 makes impossible. Replaced with the stated rule.

**Tests**

- `scripts/integration/bootstrap-integration.py` — builds the entire history into `energia_integration_test`, recording failures rather than skipping them.
- `scripts/integration/tests/cross-feature.sql` — the guarantees that exist only between the two agents' work.
- `scripts/invoices/tests/sold-voucher-issuance.sql` — the workflow completed in 254.
- `scripts/invoices/tests/rental-lifecycle.sql` — special products and rentals through correction, refund and cancellation.
- Three of agent one's fixtures updated to the current credit rules, with the reason recorded in each.
- `local-sql.sh` accepts the integration database through a fixed allowlist, so it still cannot reach production.

## Findings worth a decision

**Two independent gates now decide what package credit may buy.** The per-package `allow_product` / `allow_therapy` / … flags, and the mandatory matrix from 242. A package sold permitting *products only* can no longer spend its **paid** balance at all: the matrix forbids products from a paid balance, and the package forbids therapy. Existing customers holding such credit are affected. This is the third setting found that can contradict a mandatory rule.

## Test results

| Suite | Result |
|---|---|
| Combined migration build | **192 applied, 0 failed** |
| Invoice + integration SQL | **13 files, 23 named assertions, all passing** |
| `concurrency.mjs` | 2 passing |
| `browser.mjs` | 320 / 375 / 390 / 430 px, all passing |
| `benefit-review-browser.mjs` | 320 px passing |
| `report-helpers` + `xero-sales` | 18 passing |
| therapy-services / therapy / users / tiktok (database) | 105 / 76 / 60 / 35 passing |
| therapy / tiktok / xero / survey / phones (node) | 19 / 33 / 8 / 26 / 9 passing |
| `npm run typecheck` / `npm run build` | 0 errors / build succeeds |

A passing build is not production readiness. The unproven items are listed above.
