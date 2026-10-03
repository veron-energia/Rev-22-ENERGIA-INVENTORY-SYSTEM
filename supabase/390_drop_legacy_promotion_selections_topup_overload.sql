-- 390_drop_legacy_promotion_selections_topup_overload.sql
--
-- WHAT WAS WRONG (found 3 Oct 2026, after 386 and 388)
--
--   Production holds two functions named promotion_selections_topup:
--
--     promotion_selections_topup(uuid,uuid,jsonb,boolean)   4 args
--       the one 84 defines last: the top-up a promotion line's out-of-group
--       picks pay. It honours a group's base_mode ('highest' baseline),
--       prices through product_price_for, and refuses a pick with no price
--       at the store. create_invoice, update_invoice_internal and
--       reprice_invoice_lines all call it, each with four arguments.
--
--     promotion_selections_topup(uuid,uuid,jsonb)           3 args
--       the form 21 and 21b created, before 48b added p_is_member. Adding an
--       argument made a second function instead of replacing this one. It
--       follows the old rules: always the cheapest baseline, read straight
--       from store_product_prices, and a pick with no price silently adds
--       nothing. It is SECURITY DEFINER and executable by service_role only
--       (not by anon or authenticated), so it is no endpoint.
--
--   Nothing calls it, and as things stand nothing can: the 4-argument one
--   gives p_is_member a default, so a call with three arguments, by position
--   or by name, matches both and PostgreSQL refuses it as ambiguous
--   ("function public.promotion_selections_topup(...) is not unique").
--   Checked read-only on 3 Oct 2026:
--     * the three functions above are the only bodies in any schema that
--       name it, and each passes four arguments; no dynamic SQL builds the
--       name; nothing depends on it (pg_depend), and no cron job names it;
--     * src/ names it only in comments; scripts/ and supabase/functions/
--       never name it;
--     * seven days of API and database logs never mention it.
--   So it decides no price today. But while it exists, a patch to "the"
--   promotion_selections_topup by name can patch it instead of the live one
--   (the 302 pattern, see 386), and a caller written with three arguments
--   fails instead of getting the current rules.
--
-- WHAT THIS CHANGES
--
--   The 3-argument promotion_selections_topup is dropped.
--
--   A call with three arguments, which today fails as ambiguous, reaches the
--   4-argument function afterwards, as a member price (p_is_member default
--   true), the way reprice_invoice_lines already asks. Nothing makes such a
--   call.
--
-- NOT CHANGED
--
--   The 4-argument promotion_selections_topup and its grants, its three
--   callers, and every invoice and price. No data is touched.
--
--   Re-running 21, 21b or UPGRADE_to_current.sql would create the 3-argument
--   form again; function-grants.sql check 8 then fails.
--
-- SAFETY
--
-- Apart from the lock timeout set first (which installs nothing), the whole
-- migration is ONE statement (a single DO block), so it is atomic whatever
-- runs it. Before dropping anything it checks that the function is the
-- version read from production (md5(prosrc), 3 Oct 2026), and that the
-- 4-argument function is there, with the same first three parameter names
-- and a default for its fourth, so every call the old one could have
-- answered, by position or by name, has somewhere to go. The drop is
-- RESTRICT: it fails if anything has come to depend on the function.
-- Afterwards exactly one promotion_selections_topup must remain. Run again
-- once the function is gone, it changes nothing.
--
-- Rollback, if ever needed: production's definition and grants are
-- reproduced byte for byte by this migration's local test,
-- scripts/promotions/tests/legacy-topup-dropped.sql.
--
-- AFTER (once applied, for later guards):
--   promotion_selections_topup(uuid,uuid,jsonb)          absent
--   promotion_selections_topup(uuid,uuid,jsonb,boolean)  unchanged
--     (production md5(prosrc) aaf305556bbdf72978e94e3d3b235728, 3 Oct 2026)

set lock_timeout = '5s';

do $mig$
declare
  v_old  regprocedure := to_regprocedure('public.promotion_selections_topup(uuid,uuid,jsonb)');
  v_live regprocedure := to_regprocedure('public.promotion_selections_topup(uuid,uuid,jsonb,boolean)');
  v text; n int;
begin
  -- ── 0. Guards: nothing is dropped unless all of these pass ───────────────
  if v_live is null then
    raise exception '390: promotion_selections_topup(uuid,uuid,jsonb,boolean) is missing'; end if;
  select pronargdefaults into n from pg_proc where oid = v_live;
  if n <> 1 then
    raise exception '390: the 4-argument promotion_selections_topup has % defaults, not 1 (p_is_member)', n; end if;
  select array_to_string(proargnames[1:3], ',') into v from pg_proc where oid = v_live;
  if v is distinct from 'p_promotion_id,p_store_id,p_selections' then
    raise exception '390: the 4-argument promotion_selections_topup does not start with the 3-argument one''s parameter names (%)', v; end if;

  if v_old is null then
    raise notice '390: the 3-argument promotion_selections_topup is already gone; nothing to do.';
  else
    select md5(prosrc) into v from pg_proc where oid = v_old;
    if v <> '96a78cad1688ca6d35a2fa36cf74d681' then
      raise exception '390: promotion_selections_topup(uuid,uuid,jsonb) is not the version this was tested against (md5 %)', v; end if;

    -- ── 1. Drop it (RESTRICT: refused if anything depends on it) ───────────
    drop function public.promotion_selections_topup(uuid, uuid, jsonb) restrict;
  end if;

  select count(*) into n from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'promotion_selections_topup';
  if n <> 1 then
    raise exception '390: expected exactly one promotion_selections_topup afterwards, found %', n; end if;

  -- The API server reloads its schema on a drop by itself (pgrst_drop_watch);
  -- asking again is harmless.
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
