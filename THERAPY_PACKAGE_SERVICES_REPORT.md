# Therapy packages cover therapy services, and Purchased is claimed like Legacy

Status on 25 Sep 2026: migration 359 is **applied to production**. After applying, all 11 functions it creates or changes matched the tested local version exactly. The frontend goes live when it is pushed.

## What you decided

- **What a package grants:** each package decides — unlimited therapy, vouchers, or the customer's choice of unlimited therapy OR N vouchers. The 14 existing packages stay unlimited-only until you edit them.
- **Linking services:** unlimited and choice packages can be linked to one or more Therapy Services in the package window. A vouchers-only package covers what its voucher covers.
- **What linking means:** the customer may take any linked service as often as they like while the package runs. Each service's own limit still applies (PowerRecharge: at most once every 5 hours).
  - Nothing records a visit, so this is shown, not enforced: on the Packages list, the Purchased tab, the Claim window and the customer's page ("Unlimited until 25 Dec 2026: MEOL, 3-in-1").
- **Claim:** one window on Purchased, like Legacy. It offers unlimited therapy with a start date and holiday country, or vouchers from the package's own list (session vouchers only).
  - Vouchers can be collected a few at a time up to N.
  - An Owner or Manager can switch the choice while nothing has been used.
  - A scheduled package can be claimed again to start it today or move its start.
- **Refund:** once any voucher has been collected, the refund works like therapy that has started. On the invoice, Refund / Cancel requires an Owner or Manager to state the amount and a reason. Vouchers not yet collected are withdrawn.
- **Promotions:** packages sold inside a promotion are claimed later on Purchased.
- **Units already sold:** the 12 units keep the terms they were sold with.

## What changed

- `supabase/359_packages_cover_services_and_claim_in_one_step.sql`. Its header lists every function it adds or patches. Each patch is guarded by the production fingerprint it was tested against, and applying it twice is safe.
- The Therapy page: the package window, the Packages list, and the Purchased tab. The Claim button replaces Choose benefit, Activate and Claim vouchers.
- New files:
  - `src/components/therapy/PurchasedClaimPanel.tsx`: the Claim window.
  - `src/components/therapy/coverage.tsx`: coverage wording.
- The customer's page:
  - The Therapy holdings detail.
  - The Customers overview: coverage is shown, closed units show their status first, and units taken as vouchers are no longer listed as unlimited therapy.
- The Therapy Services page lists, for each service, the packages and vouchers that include it.
- The invoice Refund / Cancel screen asks for the amount when an override needs one. Before this, the override for therapy that had started could not be completed from the app at all.
  - A refund that needs amounts on two lines is done one line at a time (Partial refund).
- Also fixed along the way:
  - A SKU typed on a new unlimited or voucher package was dropped.
  - A choice package showed as plain "Unlimited" in the list.
  - The choice-package voucher list offered discount vouchers.

## Tests (local)

- The new `scripts/therapy-choices/tests/package-services-and-claim.sql` passes. It covers:
  - package saving and the SKU;
  - coverage with limits;
  - one-step claim;
  - the overlap question (which leaves the unit itself out);
  - starting early and moving a start;
  - two units of the same package never sharing days;
  - both refund paths;
  - the repurchase rule;
  - the customer-page lists.
- These existing suites pass: therapy-choice, voucher-claim, invoice-action, therapy-invoice, permissions, integration, credit and part-payment. The UI tests pass (57 of 57).
- Failures that are not caused by 359:
  - `invoice-actions/guided-actions.sql` fails the same way with 359 removed (the creation-time rule).
  - Two promotion suites need the unapplied 350/351 work.
  - Two suites collide with stale local test data.

## To go live (needs your go-ahead)

1. Apply 359 to Supabase **before** the new frontend is deployed. The new screens call `save_therapy_package` and `claim_purchased_therapy`, which do not exist until then.
2. Push the frontend.

## Follow-up: 360, decided 25 Sep 2026

- **Handing over purchased vouchers:** any staff member can now hand them over from the Claim window, as on Legacy Claim. This is an app-only change; the server already allowed it. Switching a choice stays Owner/Manager.
- **Buying the same package again:** `supabase/360_a_package_taken_as_vouchers_can_be_bought_again.sql` lets a customer buy a package again while an earlier unit of it was taken as vouchers. That covers vouchers-only packages too.
  - For vouchers-only packages this needed the no-overlap constraint changed: those units are marked active with no end date, so the constraint treated them as running for ever and payment for the second one failed.
  - A voucher unit cannot then be switched back to unlimited therapy while a later purchase of the same package is current.
  - Units bought together on one invoice are unaffected.
- **Tests:** the suites above still pass.
- **Production:** 360 was **applied on 25 Sep 2026**. All 7 functions it creates or changes matched the tested local version exactly.

## For you to decide or do

- **MEOL and 3-in-1 are not Therapy Services.** They exist only as vouchers. Add them on Therapy Services (price, duration, how often) before linking the MEOL and 3-in-1 packages.
- **Set up the packages** that should offer the choice: the voucher count and the voucher list for each.
- **The Legacy "Vouchers" button** is used to collect a voucher reward a few at a time.
  - For a purchased package's vouchers, which are also listed there, any staff member can now use it.
  - For credit-package and premium-bundle voucher rewards it is still Owner/Manager-only. Should those open up too?
- **Older problems found, not fixed:**
  - Refunding a promotion line never closes its therapy unit (UTP-0000006 on the refunded INV-2026-0160).
  - INV-2026-0086 has an orphan UTP-0000002 next to UTP-0000003.
  - Reschedule moves only the scheduled date, not a start already fixed. Claim is now the way to move a start.
  - The refund screen matches an override amount by override type, not by invoice line (hence one line at a time).
