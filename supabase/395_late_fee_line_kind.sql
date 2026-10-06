-- 395_late_fee_line_kind.sql
--
-- WHAT THIS IS FOR (the Owner, 6 Oct 2026)
--
-- A rental returned after its due date may now be charged a late fee, and the
-- fee is invoiced and paid at the return: an invoice of its own, with one
-- line, numbered like every other invoice. That line is neither a product nor
-- a rental, so invoice lines need a kind for it. 396 builds the Return on it.
--
-- WHAT THIS DOES
--
--   * Adds 'late_fee' to invoice_line_kind, after the nine kinds there are
--     today: product, voucher, promotion, therapy, credit_package,
--     premium_bundle, special_product, rental, event_ticket.
--
-- It is a migration of its own because a value added to an enum cannot be
-- used in the transaction that added it: 396 and the app use it only after
-- this one is committed. Apply 395, then 396.
--
-- NOT CHANGED
--
--   * Every existing line, and every function. Nothing writes the new kind
--     until 396 is applied; 396 also makes sure nothing but the rental's
--     Return ever does.
--
-- SAFETY
--
-- One statement that does nothing when the value is already there, so a
-- re-run changes nothing. An enum value cannot be removed again once
-- committed (there is no ALTER TYPE ... DROP VALUE); an unused value is
-- harmless. The check after it confirms the list.
--
-- Test: scripts/rentals/tests/return-late-fee.sql.

set lock_timeout = '5s';

alter type public.invoice_line_kind add value if not exists 'late_fee';

do $mig$
declare v text[];
begin
  -- Read from the catalogue: the new value cannot be cast to before commit.
  select array_agg(e.enumlabel::text order by e.enumsortorder) into v
    from pg_enum e where e.enumtypid = 'public.invoice_line_kind'::regtype;
  if not ('late_fee' = any (v)) then
    raise exception '395: invoice_line_kind has no late_fee value (it has %)', v; end if;
  raise notice '395: invoice_line_kind is %', v;
end $mig$;
