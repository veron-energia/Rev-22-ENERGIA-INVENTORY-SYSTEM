# Correction form: affiliate search, and the money itself

Two changes to the paid-invoice correction form.

## Affiliate is found by search

The "Referrer / affiliate" field is the same type-ahead the unpaid-invoice
panel already had: type a name, phone or email; "Clear selection" is None.
Behaviour on save is unchanged (an explicit choice, including None, reverses
and re-earns the affiliate commission).

## Payments: amount, date received, method — or "recorded by mistake"

Each recorded payment (except wallet credit) shows its amount, the date the
money was received, and its method, all editable; a **Remove** button marks a
receipt that should never have been recorded. A running line says what the
payments will total against the form's live total and what that means:
still settles the invoice / goes back to partially paid with S$x outstanding /
stays paid with S$x refund due / goes back to unpaid.

Everything saves in the one correction, with its one reason, and the preview
describes each payment change and the resulting state before anything is
written:

| Change | What is recorded |
| --- | --- |
| Amount or date (method too, if changed) | The original receipt stays; a reversal and a replacement carry the correction's reason (`correct_invoice_payment`, as the per-payment button does). No refund is recorded. |
| Method only | Changed in place, as before (`correct_invoice_payment_methods`). |
| Remove | A reversal with the reason and **no replacement** — new rule `remove_invoice_payment`. No refund is recorded, because no money went back. |

| Split (337) | "+ Split across methods" adds a part row under the payment: 22 cash becomes 20 PayNow + 2 cash. The original receipt stays; one reversal and one replacement per part are recorded (`split_invoice_payment`), all pointing at the receipt. Parts may total more or less than the original; the running line and the preview say what that does. A payment with refunds against it is not split. |

After the save the invoice's paid amount and status are recomputed (paid /
partially paid / unpaid; refund due if overpaid), commission is reconciled
(it follows the money received, as 253 already decided), and audit rows
`payment_corrected` / `payment_removed` / `payment_split` sit alongside
`invoice_corrected`.

Request ids: each payment change gets one derived from the correction's, so a
replayed correction cannot apply it twice; within a split, the reversal carries
that id and each part carries one derived from it (171's retry index allows
one entry per id and kind).

Refused — in the preview, before the save, and again by the rules themselves:
a wallet-credit payment (it consumed credit; the payment list's own button
has the lot checks), a payment already corrected (change the current
replacement), an amount of zero, an amount below refunds already issued,
removing a payment with refunds against it, and anyone who is not an Owner or
Manager.

Reversed entries and the receipts they superseded are no longer offered in
the form as payments to edit (they were listed before, as if editable).

## Files

- `supabase/336_payments_corrected_within_the_correction.sql` — `remove_invoice_payment`;
  `correct_invoice` takes `payment_corrections` / `payment_removals` in the header
  (anchored patch, replay-safe request ids derived from the correction's own);
  `preview_invoice_correction` describes them. Idempotent.
- `supabase/337_a_payment_split_across_methods.sql` — `split_invoice_payment`; a
  `payment_corrections` entry may carry `parts: [{amount, date, payment_method_id}, …]`
  (one part = 336's plain correction, two or more = a split); the preview
  describes a split and checks each part. Anchored on 336's text. Idempotent.
- `src/pages/InvoicesPage.tsx` — the form; `src/components/invoices/CorrectionPreview.tsx` — "Payments" area label.
- Tests: `scripts/invoice-correction/tests/payment-corrections.sql` (in `npm run test:invoice-correction`),
  `scripts/ui/tests/invoice-payment-correction-source.test.mjs` (in `npm run test:password-ui`).

## Verified

- SQL suite on the integration cluster (PG 14) and the Docker stack (PG 17):
  preview effects and blocking, the save's ledger rows, replay, superseded
  payment refused, overpayment → paid with refund due, zero refused, wallet
  refused both ways, method-only stays in place, no-op still detected,
  removing the last payment → unpaid, staff refused, anon has no execute.
- Existing invoice-correction, discount and invoice regression suites still pass.
- Browser (Docker stack, owner): a S$1,000 invoice paid 600 cash + 400 card;
  affiliate found by typing "Aishah"; cash corrected to 500 on 10 Sep, card
  marked recorded by mistake; the preview listed the affiliate change, both
  payment changes and "goes back to partially paid with S$500.00 outstanding";
  after saving, the detail shows the reversal/replacement ledger, Partially
  Paid, S$500 outstanding, and Record Payment is offered again. The fixture
  invoice INV-2026-0010 ("Browser Fixture Buyer") remains on the local Docker
  data; settled payments cannot be deleted, so it was left in place.
- Split (337), same invoice: "+ Split across methods" on the S$500 cash
  replacement, 300 Cash + 200 Master Card; the preview read "Cash S$500.00 →
  Cash S$300.00 + Master Card S$200.00 … 2 replacements totalling S$500.00";
  after saving, the ledger holds one reversal of the 500 and the two parts,
  each with its own "Correct amount / date" button; net S$500, still
  partially paid, `payment_split` audited. The split suite (preview,
  ledger, per-part request ids, replay, re-split refused, single part = plain
  correction, over/under totals, zero and wallet parts, staff, anon) passes on
  PG 14 and PG 17.

## Production (337)

337 is **not** applied to production. Apply it after 336 (already there):

```bash
psql "$PRODUCTION_URL" -f supabase/337_a_payment_split_across_methods.sql
```

Then deploy the frontend; until then the old form sends no `parts`.

## Production

336 was applied on 2026-09-18 through the Supabase SQL tool (file contents
verbatim). Verified afterwards: `correct_invoice` and
`preview_invoice_correction` on production hash-identical to the local build,
`remove_invoice_payment` present, executable by `authenticated`, not by `anon`.

Still to do: deploy the frontend. Until then the old form keeps working
against the new function (it sends only `payment_methods`).
