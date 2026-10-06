-- 397_old_rental_return_revoked.sql
--
-- APPLY AFTER THE NEW SPECIAL PAGE IS LIVE (the front end that calls
-- return_rental_with_fee, 396), and after every open copy of the old page
-- has had a chance to reload. Applied earlier, the old page's Return button
-- fails with "permission denied for function return_rental".
--
-- WHAT WAS WRONG (found 6 Oct 2026)
--
--   return_rental, the old Return on the Special page's Rentals tab (23b),
--   is still callable by every signed-in member of staff. It charges a late
--   fee as a figure on the rental with no invoice, counts late days to today
--   only, and ticked it writes the retired special_product_stock even for a
--   rental released from real stock (and fails for one released from a
--   store). 396 replaced it with return_rental_with_fee and left it granted,
--   so the page live at the time kept working until the new page was
--   deployed.
--
-- WHAT THIS DOES
--
--   return_rental(uuid,return_condition,boolean,uuid,text,text) is revoked
--   from public, anon and authenticated and granted to service_role only
--   (339): an endpoint for nobody. Its text is not changed.
--
-- NOT CHANGED
--
--   return_rental_with_fee (the Return) and every other function; no data.
--
-- SAFETY
--
-- Apart from the lock timeout, one DO block, so atomic. It refuses unless 396
-- is installed (return_rental_with_fee has 396's AFTER md5) and return_rental
-- is the version read from production on 6 Oct 2026. Revoking twice changes
-- nothing, so a re-run is a no-op. Afterwards it checks no client role can
-- call return_rental and staff can still call return_rental_with_fee.
--
-- md5 of pg_get_functiondef, unchanged by this migration:
--   return_rental(uuid,return_condition,boolean,uuid,text,text)  bea2613abd698d1bcb7466d8d2edc88f
--   return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)
--                                                                659a74da796b7360a3730347730e0d65
--
-- Test: scripts/rentals/tests/return-late-fee.sql (test 2).

set lock_timeout = '5s';

do $mig$
declare
  c_old constant text := 'public.return_rental(uuid,return_condition,boolean,uuid,text,text)';
  c_new constant text := 'public.return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)';
begin
  if to_regprocedure(c_new) is null
     or md5(pg_get_functiondef(to_regprocedure(c_new))) <> '659a74da796b7360a3730347730e0d65' then
    raise exception '397: apply 396 (and deploy the page that uses it) first: % is missing or not 396''s', c_new; end if;
  if to_regprocedure(c_old) is null
     or md5(pg_get_functiondef(to_regprocedure(c_old))) <> 'bea2613abd698d1bcb7466d8d2edc88f' then
    raise exception '397: % is missing or not the version read on 6 Oct 2026', c_old; end if;

  execute 'revoke all on function ' || c_old || ' from public, anon, authenticated';
  execute 'grant execute on function ' || c_old || ' to service_role';

  if has_function_privilege('anon', c_old, 'execute') or has_function_privilege('authenticated', c_old, 'execute') then
    raise exception '397: % is still callable by a client role', c_old; end if;
  if not has_function_privilege('authenticated', c_new, 'execute') then
    raise exception '397: % is not callable by staff', c_new; end if;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
