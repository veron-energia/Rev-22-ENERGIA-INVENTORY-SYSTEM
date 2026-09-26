# Refunding a promotion closes the therapy it granted (363)

**State, 26 Sep 2026:** designed, reviewed in four independent rounds, and
tested locally on production-equivalent code. **Not applied to production.**
Three owner decisions are open (A–C below). A data repair for two existing
units is proposed separately and needs the owner's sign-off.

**Numbering.** It is 363. Three neighbouring migrations come from other sessions:

- 360 (`a_package_taken_as_vouchers_can_be_bought_again`) is on production.
- 361 (`a_promotion_refund_lists_its_stock`) is on production and lists a
  promotion's goods in the refund plan. 363 is written on top of 361's version
  of `invoice_action_plan` and needs it. 361's file is not yet in the
  repository; it sits untracked in the main checkout.
- 362 (`a_correction_settles_the_therapy_it_changes`, branch
  `claude/vibrant-swanson-c65496`) is not applied. It patches `correct_invoice`
  and `create_purchased_therapy_for_invoice`, none of 363's functions. The two
  were tested in both orders, and each one's suite passes with the other
  installed.

Files:

- `supabase/363_a_promotion_refund_closes_its_therapy.sql`: the migration
  (md5-guarded, as 359 is)
- `scripts/invoice-actions/tests/promotion-therapy.sql`: the test suite, 21
  sections, begin/rollback
- `scripts/therapy/repair-promotion-therapy-units.sql`: the proposed repair
  (dry run + commented apply)
- `src/components/invoices/InvoiceGuidedAction.tsx`: "Therapy closed" and
  "Therapy left running" in the review step; each override has its own reason
  and amount per line
- `scripts/invoice-actions/tests/guided-interaction.test.mjs`: 13 new checks

## The gap

A promotion that includes a therapy package grants purchased therapy units
through `invoice_therapy_entitlements_due`, from
`promotion_items.therapy_package_id` and `invoice_promotion_selections`. The
units link to the **promotion** line and are priced at 0.
`refund_invoice_recorded` closes units only for `line_kind = 'therapy'`. For a
promotion line it moves stock and nothing else. All 12 purchased units in
production came from promotion lines.

Two more defects in the same path, which 363 also fixes:

1. **Cancelling without recording the refund ignored the therapy override.**
   The plan asked the approver to authorize ending started therapy, and to
   state an amount. Then `cancel_invoice_recorded` left the therapy running on
   the cancelled invoice. This affects therapy sold on its own line too.
2. **A direct cancellation closed a unit whose vouchers were collected as if it
   were unused.** 359 defines that unit as used.

A third, that a guided refund of any promotion with goods was refused, is
fixed by 361.

## The rule: unchanged, now applied to promotions

The rule is already set for therapy sold on its own (296, 359): unused units
are refunded with their line. Used units (started, ended, or vouchers
collected, per `therapy_unit_consumed`) end only on the Owner/Manager
`therapy_activated` override with a reason and an amount. Their history is
kept, and vouchers not yet collected are withdrawn.

| Action | Unused unit | Used unit |
|---|---|---|
| Guided full refund, guided cancellation, or a guided refund that takes what is left of the line | closed (`refunded`), no override | ended on the override with an amount; history kept |
| Guided part refund, N of M copies | its share closes, unused first **(B)** | as above, if the share reaches it |
| Guided refund where the payments held leave the line at S$0 | closed | ended on the override with S$0 stated |
| A line whose refund is fixed by the vouchers or credit it issued | closed | ended on the override; a reason, no amount |
| Finance panel: refund of the whole line | closed | **refused**: "use Refund / Cancel" |
| Finance panel: part refund by amount | **kept (A)** | kept (A) |
| Finance panel: cancellation | closed (as before) | **refused (C)**: "use Refund / Cancel" |
| Unit on no line (a correction deleted its line): cancellation, full refund, or a refund that closes the invoice | closed | left running, as before 363, and shown as such; never blocks |
| A line with nothing left to refund (a free line) | untouched by a refund; closed by a cancellation, as before | as for its invoice's cancellation |

The guided flow closes **exactly the units the reviewed plan lists**, before any
money moves, and tells the refund engine so; the engine then closes nothing of
its own on those lines. The units are part of the plan's line, so the plan
hash covers them. If therapy is started between the request and the approval,
the approver is shown the changed plan and must confirm it (tested). Units and
their voucher allowances are locked before anything checks whether they have
been used, so a start or a voucher collection at the same moment is seen, not
missed.

No price is invented for therapy inside a promotion. Unused units close at no
separate value, because they were sold at 0. For used ones, the Owner or
Manager states the refund amount for the whole promotion line. Commission
follows the money, as for any promotion refund.

## Owner decisions

Each one is encoded as the recommended default, and each is a one-line change
in 363.

- **A. A part refund by amount leaves the therapy with the customer.** For
  example, a S$100 price adjustment on a S$610 bundle in the Finance panel.
  - Recommended: keep it. Nothing in an amount says which part came back.
  - Alternative: refuse such a refund until it names the units that close.
  - Switch: the condition `v_amount>=greatest(v_line_paid-v_refunded,0)` in
    363 §4.
- **B. A guided part refund of N of M copies closes ceil(units the line granted
  × N ÷ M) units, unused first. A refund that takes what is left of the line
  closes all of them.**
  - Recommended: as described. Unused units go first, so a customer returning
    the bundle they never used is not asked for an override.
  - Alternatives: round down, or take used units first.
  - This only matters for multi-copy lines. All 12 production units are on
    1-copy lines.
  - Switch: the `ceil(...)` and the `order by` in 363 §2.
- **C. A direct cancellation (Finance panel) is refused while therapy on a line
  has been used.** This includes therapy sold on its own line, and therapy
  that expired unclaimed (359 counts it as used).
  - Before 363: started therapy kept running on the cancelled invoice, and
    units with collected vouchers were closed silently.
  - Recommended: refuse, and point to Refund / Cancel, where the amount is
    stated.
  - Alternative: leave used units running, but stop the silent close.
  - A used unit that no line holds is left as it is and does not block the
    cancellation (as before 363).
  - Switch: the `raise` in 363 §5.

Other changes in outcome. Each follows from the existing rule; they are listed
so the owner sees them:

- A guided cancellation without recording the refund now really ends started
  therapy on a therapy line. The approver was already asked to authorize this.
- Stock to confirm is one row per movement. A product line and a promotion
  that share a movement produced two rows, and the dialog kept only one, so
  goods shown as coming back stayed recorded as sold. Before 361, two lines of
  one product did the same.
- A line the payments held leave at S$0 is no longer sent to the refund engine,
  which refused it. Its used therapy ends on the override with S$0 stated. The
  amount box is pre-filled with the line's figure after the payments cap. It
  used to show the uncapped figure, which could not be taken. This applies to
  therapy sold on its own line too.
- Two lines whose therapy has been used each get their own reason and amount.
  An override now names its line. The dialog used to send such an invoice
  away, telling the approver to refund one line at a time, which left no way
  to cancel it. An override that names no line still serves every line with
  its code, so requests and dialogs from before 363 still work. Its amount
  never lands on a line whose refund is fixed by vouchers or credit.
- A stated amount that pays back all of a line is refused when the reviewed
  plan closes only part of its therapy. Refund it with Full refund instead.
- The dialog now requires a reason for every override, not only those with an
  amount. On a cancellation it compares a stated amount with the refund due,
  and names that amount on the confirm button.

## What 363 changes

A preflight requires the four patched functions to be either all at their
tested production version or all already patched by 363 (each carries its own
mark), never a mix. Every patch is guarded by its production md5 and by anchors
that must each match once. A second run changes nothing (tested).

| Function | Production md5 before | After |
|---|---|---|
| `invoice_action_plan` (after 361) | `1c8fa5626062d09ba0cc1a4dca9d0e93` | `07434476a54f1b5fcc71e3db75d702f4` |
| `resolve_invoice_action_v2` | `67e3cc6b44eb8d259d92ae5e27a304ee` | `27107618d30813515e48f4deed6a3837` |
| `refund_invoice_recorded` | `7dd62acaef1c995cc5e12effff6640fb` | `c54ff24fc0d7515bb0860dad01a63af8` |
| `cancel_invoice_recorded` | `c84a8a4f259cfc2c52ab92f80cac5e17` | `1f3204c1b2e997f277532320a9ae4903` |
| `close_invoice_therapy_units` (new; service_role only; checks store access) | none | `819fca4f3453b326bd3d53d17b1f8f37` |

Migration file md5: `55638bbcec236da8dfd0716b0e55c328`.

363 also drops one clause of 361 in `invoice_action_plan`. 361 skipped a stock
movement that an earlier line had already listed, so when a product line was
read before a promotion drawing on the same movement, the promotion's goods
went unlisted. Line order depends on the query plan. Every line now offers its
share, and 363's merge adds the shares and caps them at what is outstanding.
Both read orders are tested.

A plan's hash changes only where the plan itself changes: lines that close
therapy, invoices holding units no line holds, one movement drawn on by two
lines, and a therapy override whose line the payments cap. On 26 Sep, one
invoice request was pending on production (INV-2026-0314, a refund of a
promotion with goods and no therapy). None of these apply to it, so 363 does
not change its plan.

## Found in 361 (for the session that owns it)

Found while testing 363 on top of 361. 363 does not change 361's goods logic,
apart from merging duplicate rows and dropping the order-dependent skip
(above):

1. **Goods chosen per copy.** For a promotion where each copy chose a different
   product (corset for one, belt for the other), a part refund of one copy
   offers both garments back as sellable. 361 takes each movement's share on
   its own, and nothing records which copy chose which product.
2. **A shared movement.** A promotion's share of a movement is taken from the
   whole movement, including units that belong to another line. So a part
   refund of just the promotion can offer back the corset bought on its own
   line. It should be the promotion's own quantity of that product × the
   copies taken.
3. **Later part refunds.** A promotion's share is taken from what is still
   outstanding but divided by the original number of copies. After an earlier
   part refund, the last copy offers back too little.

## Found, not changed (for the owner)

1. **A correction still detaches therapy.** Swapping a promotion for another
   item with `correct_invoice` deletes the line. The FK sets the unit's
   `invoice_item_id` to null, and the unit stays open and claimable. This was
   reproduced on production's code. It is how INV-2026-0086's duplicate arose,
   by the older edit path. It needs a rule: should a correction close the
   unused therapy of a line it removes?
2. **An ended period still blocks the same package.** The no-overlap constraint
   from migration 53, and 359's Claim check, treat a refunded or terminated
   unit's dates as taken. So a customer whose therapy was ended cannot start
   the same package over those days. The 53 predicate is
   `… status in ('active','scheduled','expired') = false or status = 'active'`.
   Migration 360 left that part alone; it only added
   `and benefit_choice is distinct from 'voucher'`.
3. **INV-2026-0160's money record.** It is `refunded`, but it still records
   S$610 received and nothing returned (no `invoice_refunds` row).
4. **Decision B counts units given up elsewhere.** The share of a part refund
   counts every unit the line granted. If some were given up on the Therapy
   page first (`refund_purchased_therapy`, which moves no money), returning N
   of M copies can take therapy the kept copies would have had.
5. **Two rare lock waits can end in a deadlock that Postgres resolves by
   cancelling one side.** One is a refund at the same moment as a first-time
   voucher choice or a benefit switch on the same invoice; the approver then
   retries. Therapy lines had the same wait before 363.
6. **Stating S$0 when there is nothing else to refund.** A full refund where
   every line states S$0 is refused ("nothing left to refund"). Cancel instead.
7. **A stated amount cannot exceed the money held, even when cancelling
   without recording a refund.** This check predates 363; with no money
   moving it could be relaxed. Also predating 363: when a cancellation records
   a smaller stated refund, the result reports nothing still due, while the
   invoice's financial position shows the rest.

## Tests

The new suite, `promotion-therapy.sql`, has 21 sections. It **fails without
363** at section 1 (the reported gap) and **passes with it**. Each defect the
reviews found has a section, except the concurrency ones, which were checked by
reading the lock order and in two-session runs that were rolled back.

Every run was on production-equivalent code, most recently on 26 Sep after 361
reached production:

- The shared local database matches production for every therapy and
  invoice-action function, `invoice_action_plan` included (361's version).
- Four functions on or beside the refund path still differed locally:
  `user_has_store_access`, `trg_promotion_choice_option_valid`,
  `preview_invoice_correction` and `create_credit_purchase_invoice`. Inside
  each suite's rolled-back transaction, the runner installed production's
  bodies of those four (fetched read-only), then 363.
- Nothing was committed locally.

Results:

- 81 existing self-contained suites: identical results with and without 363.
  70 pass. The same 11 fail in both modes for reasons unrelated to this work:
  fixture collisions with local data, `preview_customer_merge` missing locally,
  the created-at guard needing a real superuser, and known local failures.
- Suites that stop early, run again past those failures:
  - `guided-actions` (as `supabase_admin`): passes both ways.
  - `choice-packages` (unique SKUs): passes both ways.
- UI:
  - `guided-interaction.test.mjs` (13 new checks), `guided-ui.test.mjs` and
    `tsc --noEmit` all pass.
  - The review step was also rendered in the browser against a stubbed server.

Four review rounds, each finding checked by a separate skeptic who tried to
refute it by reproduction:

- **Round 1:** 12 confirmed; they collapse into seven defects.
- **Round 2:** confirmed all seven fixes; 9 new, smaller findings.
- **Round 3:** 5 confirmed; one of them was the collision with 361.
- **Round 4:** the rebase onto 361. 5 low findings; the four in 363's own code
  are fixed (line order, old dialogs' overrides in either order, the cancel
  lock order, labels), and the rest are listed above.

All confirmed findings are fixed or listed above.

To run the suite without changing the shared database (363 rolls back with it):

```bash
{ echo '\set ON_ERROR_STOP on'; echo 'begin;'; echo '\i supabase/363_a_promotion_refund_closes_its_therapy.sql'; echo '\i scripts/invoice-actions/tests/promotion-therapy.sql'; } | psql postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

## Proposed repair (owner sign-off; not run)

`scripts/therapy/repair-promotion-therapy-units.sql`:

- **UTP-0000006 on INV-2026-0160 → `refunded`.**
  - The invoice was refunded on 1 Sep 2026 ("Duplicated Data") by the
    pre-guided approval path, which never looked at therapy.
  - The same customer's INV-2026-0161 (same bundle) holds UTP-0000007.
- **UTP-0000002 on INV-2026-0086 → `cancelled`. UTP-0000003 is kept.**
  - The pre-guided paid-invoice edit of 27 Aug 2026 (Singlet → Hat 3XL)
    replaced the promotion line, which detached UTP-0000002. Re-paying then
    issued UTP-0000003.
  - The bundle grants one unit. Both units are unused, with identical terms
    (bought 22 Aug 2026, activate by 22 Aug 2027).
  - The kept unit is the one on the line, which every refund, cancel and
    correction path can find.

Dry run on production, 25 Sep (read-only): both rows `ok = true`. The apply step
was tested on a rolled-back fixture:

- It closes both units with audit rows and keeps UTP-0000003.
- It refuses a second run.
- It refuses if the bundle stops granting therapy after the dry run.

Money is not touched.

## Rollout, when instructed

1. The owner answers A–C. If an answer differs from the default, edit 363 and
   re-run the suite.
2. Commit 361's file (the other session's) so the repository matches
   production. 362 (correction) and 363 can be applied in either order.
3. Push the frontend together with, or before, 363. The dialog sends each
   override with its line. An old dialog still works, one line at a time.
4. Apply 363 with the Supabase migration tool. The preflight and md5 guards
   refuse if production has moved.
5. Check that the five md5s above match.
6. With the owner's sign-off, run the repair: step 1, then step 2.
