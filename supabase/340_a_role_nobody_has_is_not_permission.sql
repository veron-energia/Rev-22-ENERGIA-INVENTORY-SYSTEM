begin;
-- =====================================================================
-- A ROLE NOBODY HAS IS NOT PERMISSION TO PROCEED
--
-- current_user_role() reads the caller's row from profiles:
--
--     select role from public.profiles where id = auth.uid()
--
-- A signed-in affiliate has no profiles row — that is the whole distinction
-- the portal rests on (AuthContext resolves an actor to staff OR affiliate,
-- never both). So for an affiliate the function returns NULL, and eight
-- guards were written like this:
--
--     if public.current_user_role() not in ('owner','manager') then
--       raise exception 'Only Owners and Managers can ...';
--     end if;
--
-- In SQL, NULL not in ('owner','manager') is NULL, not true. PL/pgSQL takes
-- the false branch on NULL, so the raise never happens and the caller walks
-- straight through the check that was written to stop them. The same holds for
-- the <> 'owner' form.
--
-- Anyone holding an affiliate login could therefore delete a TikTok import
-- batch, rewrite the customer-source options, change TikTok status mappings,
-- or reattribute an invoice to a different member of staff. 339 does not cover
-- this: these are functions the application calls, so they are granted to
-- authenticated, and an affiliate session is an ordinary authenticated session.
--
-- The rewrite is the smallest one that restores the intent: compare a value
-- that is never NULL. A caller with no role now fails every one of these
-- checks, which is what each message already claims to do.
--
-- Anchored on the installed text, applied to every function that carries the
-- pattern, and idempotent: a body already fixed no longer matches.
-- =====================================================================
do $$
declare
  f record;
  v_src text;
  v_new text;
  v_fixed int := 0;
  v_names text := '';
begin
  for f in
    select p.oid, p.oid::regprocedure::text as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.prosrc ~ 'current_user_role\(\)\s*(not in|<>|!=)'
     order by p.proname
  loop
    v_src := pg_get_functiondef(f.oid);
    v_new := regexp_replace(
               v_src,
               'public\.current_user_role\(\)\s*(not in|<>|!=)',
               'coalesce(public.current_user_role()::text, '''') \1',
               'g');
    if v_new = v_src then
      raise exception '340: % matched the unsafe pattern but could not be rewritten', f.sig;
    end if;
    execute v_new;
    v_fixed := v_fixed + 1;
    v_names := v_names || f.proname || ' ';
  end loop;

  if v_fixed = 0 then
    raise notice '340: no function compares current_user_role() without handling NULL (already fixed)';
  else
    raise notice '340: % function(s) now refuse a caller with no role: %', v_fixed, v_names;
  end if;

  -- Nothing may be left comparing the role in a way that a NULL slips through.
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.prosrc ~ 'public\.current_user_role\(\)\s*(not in|<>|!=)') then
    raise exception '340: a guard still compares current_user_role() without handling NULL';
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
