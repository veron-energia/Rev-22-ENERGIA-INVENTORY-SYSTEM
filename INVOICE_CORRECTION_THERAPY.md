# A correction settles the therapy it changes (362)

**State, 26 Sep 2026:** built to the owner's rules, tested locally on
production-equivalent code, and **applied to production** at the owner's
go-ahead (migration `20260926081436 a_correction_settles_the_therapy_it_changes`).
The frontend notice deploys when the branch is pushed.

Files:

- `supabase/362_a_correction_settles_the_therapy_it_changes.sql`: the migration
  (md5-guarded, as 359 and 360 are)
- `scripts/invoice-correction/tests/promotion-therapy-correction.sql`: the suite
  (begin/rollback, 16 sections)
- `scripts/invoice-correction/tests/therapy-note.test.mjs`: the form's notice
- `src/pages/InvoicesPage.tsx`: after a correction is saved, a dismissible notice
  names the units it closed, moved or issued
- `scripts/permissions/tests/function-grants.sql`: the new functions are listed
  as internal

It is numbered 362 because 361 went to production the same day as
`a_promotion_refund_lists_its_stock`. That 361 changed only `invoice_action_plan`
and added `invoice_line_stock_products`, neither of which 362 patches or calls.
The promotion-refund therapy work is now numbered 363 and remains unapplied.

The number 362 is shared with `362_merge_leaves_phone_capture_with_retired_record.sql`,
which another session applied later the same day. The two touch no function in
common. This file keeps 362 because the functions it installed in production
carry "362:" markers.

## The gap

A promotion or a therapy line issues purchased therapy units against its
invoice line when the invoice is paid. `correct_invoice` →
`update_invoice_internal` deletes every line missing from the new payload.
`purchased_therapy_entitlements.invoice_item_id` is `ON DELETE SET NULL`, so
swapping a therapy promotion out left its unit `pending_activation` on no line,
where it could still be claimed. This includes a kind change, because the form
clears the line id.

Three related problems:

- A line kept under its id but changed (another promotion, a lower quantity)
  kept units it no longer grants.
- Therapy swapped in on a paid invoice was never issued.
- The correction was refused only while a unit was `active` or `expired`. A
  choice-package unit whose vouchers were collected stays `pending_activation`,
  so that check never saw it.

INV-2026-0086's extra unit (UTP-0000002) arose this way, by an older edit path.

## The owner's rules (26 Sep 2026)

| Case | Outcome |
|---|---|
| A line the correction removes or changes no longer grants a unit, and the unit is unused | Closed: `cancelled`, audited (`closed_by_invoice_correction`, with the line and the correction's request id). Vouchers not yet collected are withdrawn. |
| As above, but the unit has been used (started, ended, or vouchers collected, per `therapy_unit_consumed`) | The correction is refused: "Keep that line, or end the therapy with Refund / Cancel on the invoice first." |
| Several units on the line and fewer granted now (quantity lowered) | Unused units close first. Used ones are kept while the line still grants them. |
| The line still grants the unit's package (for example, promotion A swapped for A2, both with 3 months' therapy) | Kept: same number, deadline, booked start and choice. |
| Therapy swapped in, and the invoice is still paid (or FOC) after the correction | Issued at the correction, on a sale's terms: one year to activate from the invoice's payment date. |
| Therapy swapped in, and the correction leaves a balance | Issued when the balance is paid (the existing paid trigger). |

**Confirmed by the owner the same day.** Deleting a line and adding the same
package back as a new line moves the unit to the new line, audited as
`moved_by_invoice_correction`. It is not closed and re-issued, so a booked start
or a choice already made is not lost.

**Only the lines a correction removes or rewrites are settled.** What a
promotion grants is read from the live catalogue (`promotion_items`), not from a
snapshot. Settling every line would let an unrelated correction close or issue
therapy on an untouched line after the promotion was edited (tested).

## Not changed

- The existing refusal of any line, customer or store change while any unit on
  the invoice is `active` or `expired`.
- A unit already on no line (UTP-0000002) is left alone. Its repair stays in
  `scripts/therapy/repair-promotion-therapy-units.sql`, awaiting sign-off.
- A closed unit leaves its line, as a deleted line's unit already does; the
  audit row keeps the line. This lets the line grant that package again later.
  Refunded units stay on their line, so they are never issued twice.

## Found, not changed

1. **A correction cannot change which therapy a promotion's choice group
   picked.** `invoice_line_matches` compares selections by product and voucher
   only. Such an edit is silently not saved, so 362 never sees it.
2. **A rewritten therapy line is refused while its own unit is current.**
   `update_invoice_internal` refuses a rewritten therapy line whose package the
   customer already holds, even when the unit is that line's own (as noted in
   360). This also blocks swapping a promotion for a therapy line of the same
   package.
3. **The correction preview cannot warn beforehand.** `preview_invoice_correction`
   receives only the header, not the lines, so it cannot say before saving that
   therapy will close. The notice appears after saving.

## What 362 changes

| Function | Production md5 before | After |
|---|---|---|
| `correct_invoice` | `d1db5369ed8c579ca206ff65eb15f1f6` | `44cccc9944780bd6c22b7a0d739de33b` |
| `create_purchased_therapy_for_invoice(uuid)` (now calls the new one with null) | `09ac9be8a09071d64e631c03e3a504ec` | `4f9933521854a2d034ca295e0a8ac38d` |
| `create_purchased_therapy_for_invoice(uuid,uuid[])` (new; service_role only) | none | `3c031fb3b2e63818e2095962c4459e25` |
| `therapy_units_before_correction` (new; service_role only) | none | `ab7379226983960deeadd8ab164ed1c6` |
| `settle_corrected_therapy_units` (new; service_role only) | none | `ee23ad6815ea82caef716215a5addd5c` |
| `issue_therapy_of_corrected_lines` (new; service_role only) | none | `59910d11cec48a2edeafab74a94d3a89` |

Migration file md5: `8c729a98a78e61ac8d77d87e3ab72269`.

The migration changes functions only; it changes no data. A second run changes
nothing (tested). The correction locks the units and their voucher allowances
before it checks for use, matching the locks taken by `claim_entitlement_vouchers`
and `activate_purchased_therapy`. `correct_invoice`'s result, its revision's
after-snapshot and its audit row carry `therapy: {closed, moved, issued}`.

## Tests

- **The new suite fails without 362 and passes with it.** Without 362 it fails
  at section 1 (the reported gap). Five deliberately broken copies of 362 each
  fail at the section guarding that behaviour:
  - the refusal removed;
  - no move;
  - no issuing;
  - every line settled;
  - used units not kept first.
- **The existing SQL suites are unaffected.** Each of the 85 suites with
  begin/rollback and no commit was run with and without 362. Results were
  identical except for the new suite: 73 pass with 362, 72 without. The same 12
  fail both ways for reasons unrelated to 362: fixture collisions with local
  data, local drift, and known local failures. `choice-packages`, run again with
  a unique SKU, passes both ways. `function-grants` passes both ways.
- **The UI checks pass.** `therapy-note.test.mjs`, the other invoice UI tests
  and `tsc --noEmit` all pass.
- **How the runs matched production.** The shared local DB matched production
  for every function 362 patches or calls, except `user_has_store_access` and
  `trg_promotion_choice_option_valid`. The runner installed production's bodies
  of those two inside each suite's transaction, checked md5 for md5.

## Rollout (26 Sep 2026)

1. Done: the owner confirmed the delete-and-re-add move.
2. Done: before applying, every public function on production was diffed
   against the morning's snapshot. Only `invoice_action_plan` had changed, and
   `invoice_line_stock_products` was new (both from 361). The two guarded
   functions and the triggers on `invoices`, `invoice_items` and
   `purchased_therapy_entitlements` matched what was tested. 362 was then
   applied.
3. Done: all six "after" md5s match on production. The new functions are
   service_role only, and `correct_invoice` keeps its grants. The 12 therapy
   units were unchanged, and no correction audit rows had been written yet.
4. Still to do: push the frontend (the correction-form notice). The server
   change does not need it: the old form ignores the new `therapy` field.
