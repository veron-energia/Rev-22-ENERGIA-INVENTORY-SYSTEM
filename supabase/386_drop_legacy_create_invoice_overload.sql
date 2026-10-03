-- 386_drop_legacy_create_invoice_overload.sql
--
-- WHAT WAS WRONG (found 3 Oct 2026, after 385)
--
--   Production holds two functions named create_invoice:
--
--     create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   8 args
--       the one create_invoice_with_details calls, which is what the invoice
--       screen uses. It carries the invoice rules: the manual discount and its
--       reason (331/335), one Discount per line (385), therapy, rentals,
--       tickets, service staff.
--
--     create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)         7 args
--       an old overload, left behind because "create or replace" with a new
--       argument list makes a new function instead of replacing the old one.
--       It is SECURITY DEFINER and granted to authenticated. It writes
--       p_discount_total straight into discount_total and never sets
--       manual_discount, so the reason trigger (which looks only at
--       manual_discount) does not ask for a reason, and none of 385's line
--       rules apply. It knows none of the newer line kinds either.
--
--   Nothing calls it, and as things stand nothing can: the 8-argument one
--   gives its eighth argument a default, so any call with seven arguments or
--   fewer, by position or by name, matches both and PostgreSQL refuses it as
--   ambiguous ("function public.create_invoice(...) is not unique"); the API
--   server refuses the same call before that, because two functions match
--   the names sent. Checked read-only on 3 Oct 2026:
--     * no function in the database calls it: create_invoice_with_details
--       passes all eight arguments; the other bodies that name create_invoice
--       only mention it in comments, or (302's repair helper) loop over every
--       overload by name;
--     * nothing depends on it (pg_depend), no cron job names it;
--     * src/ and supabase/functions/ never call it (scripts/ only from the
--       local SQL test suites), and the deployed web-ticket-order edge
--       function calls only the web_order_* functions;
--     * the API and database logs of the last 24 hours show
--       create_invoice_with_details only.
--   So it is not a working hole today. It is one default away from being
--   one: should the 8-argument function ever lose that default, every
--   seven-argument call from a signed-in user would land here. And while it
--   exists, a migration that patches "the" create_invoice by name can patch
--   it instead of the live one, which is how single-customer packages broke
--   (302).
--
-- WHAT THIS CHANGES
--
--   The 7-argument create_invoice is dropped.
--
--   A call with four to seven arguments, which today fails as ambiguous,
--   reaches the 8-argument function afterwards, with its default service
--   staff ('[]'). Nothing in the application makes such a call; only the
--   local SQL test suites do.
--
-- NOT CHANGED
--
--   The 8-argument create_invoice, create_invoice_with_details, the reason
--   trigger and every grant on them. No data is touched.
--
-- SAFETY
--
-- Apart from the lock timeout set first (which installs nothing), the whole
-- migration is ONE statement (a single DO block), so it is atomic whatever
-- runs it. Before dropping anything it checks that the function is the
-- version read from production (md5(prosrc), 3 Oct 2026), and that the
-- 8-argument function is there with the same first seven argument types and
-- defaults for the last four, so every call the old one could have answered
-- has somewhere to go. The drop is RESTRICT: it fails if anything has come to
-- depend on the function. Afterwards exactly one create_invoice must remain.
-- Run again once the function is gone, it changes nothing.
--
-- Rollback, if ever needed: production's definition and grants are
-- reproduced byte for byte by this migration's local test,
-- scripts/invoices/tests/legacy-create-invoice-dropped.sql.
--
-- AFTER (once applied, for later guards):
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)        absent
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)  unchanged
--     (production md5(prosrc) bf0f627b032aa11d680e1a09738c2edf, 3 Oct 2026)

set lock_timeout = '5s';

do $mig$
declare
  v_old  regprocedure := to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)');
  v_live regprocedure := to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)');
  v text; n int;
begin
  -- ── 0. Guards: nothing is dropped unless all of these pass ───────────────
  if v_live is null then
    raise exception '386: create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb) is missing'; end if;
  select pronargdefaults into n from pg_proc where oid = v_live;
  if n <> 4 then
    raise exception '386: the 8-argument create_invoice has % defaults, not 4 (p_discount_total, p_notes, p_discount_voucher_id, p_service_staff)', n; end if;

  if v_old is null then
    raise notice '386: the 7-argument create_invoice is already gone; nothing to do.';
  else
    select md5(prosrc) into v from pg_proc where oid = v_old;
    if v <> 'b1d529eae8a5445b3311fcd9a07af903' then
      raise exception '386: create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid) is not the version this was tested against (md5 %)', v; end if;

    -- ── 1. Drop it (RESTRICT: refused if anything depends on it) ───────────
    drop function public.create_invoice(uuid, uuid, uuid, jsonb, numeric, text, uuid) restrict;
  end if;

  select count(*) into n from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'create_invoice';
  if n <> 1 then
    raise exception '386: expected exactly one create_invoice afterwards, found %', n; end if;

  -- The API server reloads its schema on a drop by itself (pgrst_drop_watch);
  -- asking again is harmless.
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
