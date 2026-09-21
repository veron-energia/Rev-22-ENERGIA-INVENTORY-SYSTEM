begin;
-- =====================================================================
-- ONE CANDIDATE FOR A TRANSFER REQUEST
--
-- Creating a transfer request failed with HTTP 300 from the moment 339 was
-- applied to production: six attempts at 02:26 on 2026-09-21, all refused
-- before reaching the database.
--
-- create_transfer_request has two overloads with IDENTICAL parameter names:
--
--   (text, location_type, uuid, location_type, uuid, jsonb, text)
--       2,983 chars — the pre-migration-12 form. It never received the manual
--       transfer lines from 159, nor the stock-history safeguards from 272.
--   (text, text, uuid, text, uuid, jsonb, text)
--       4,634 chars — the live one, which has both.
--
-- It arose because "create or replace function" with different parameter types
-- creates a NEW function rather than replacing: 05 declared the enum form, 12
-- re-declared it as text, and the enum form was never dropped. PostgREST
-- resolves an overload by the SET of parameter names, and these two are
-- identical, so with both callable it cannot choose and answers PGRST203,
-- "Could not choose the best candidate function".
--
-- 339 CAUSED THIS. Its allowlist matches on the function NAME, so granting
-- 'create_transfer_request' granted BOTH overloads and put a second candidate
-- in front of PostgREST where there had been one. The lesson is recorded in
-- 339 itself, which now skips anything marked DEPRECATED.
--
-- The function is left in place rather than dropped: this codebase patches
-- function bodies by matching installed text, and a hard drop could strand such
-- a patch. Revoking is enough, because PostgREST only considers functions the
-- role may execute.
-- =====================================================================
comment on function public.create_transfer_request(text, public.location_type, uuid, public.location_type, uuid, jsonb, text) is
  'DEPRECATED. Superseded by the (text,text,...) form in migration 12; it never received the manual lines from 159 or the stock-history safeguards from 272. Not called by the application. Revoked from authenticated in 348 because two candidates with identical parameter names make PostgREST refuse the call outright (PGRST203). Do not grant it again.';

revoke all on function public.create_transfer_request(text, public.location_type, uuid, public.location_type, uuid, jsonb, text)
  from public, anon, authenticated;

do $$
declare v_candidates int; v_live boolean;
begin
  select count(*) into v_candidates
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_transfer_request'
     and has_function_privilege('authenticated', p.oid, 'execute');
  if v_candidates <> 1 then
    raise exception '348: % overload(s) of create_transfer_request are callable by staff; PostgREST needs exactly one', v_candidates;
  end if;

  select (p.prosrc like '%stock_history%') into v_live
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_transfer_request'
     and has_function_privilege('authenticated', p.oid, 'execute');
  if not coalesce(v_live, false) then
    raise exception '348: the overload left callable is the stale one, which lacks the 272 stock-history safeguards';
  end if;

  raise notice '348: exactly one create_transfer_request is callable by staff, and it is the current one';
end $$;

notify pgrst, 'reload schema';
commit;
