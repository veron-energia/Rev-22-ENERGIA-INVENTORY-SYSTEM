-- Every owner-rights function of the app searches the session's temporary schema last (546;
-- security audit of 17 Nov 2026, L15, its second half): the 1,019 the user chose ("Change all
-- 1,019", on the audit's count), plus 3 production-only functions of the same kind.
--
--   P  why: an owner-rights function made here with search_path public reads a temporary table a
--      session makes under a public table's name; with public, pg_temp it reads the public table.
--   G1 no owner-rights function of the app (public, owned by postgres, not part of an extension)
--      is left without a search_path that ends in pg_temp.
--   G2 bodies unchanged: every public function's prosrc md5 as before (install mode).
--   G3 only the functions 546 names changed, and each only in its SET search_path line: with that
--      line put back, its definition is as before (install mode); arguments, results, owners,
--      grants, volatility and other settings (invoice_date_evidence's TimeZone) as before.
--   G4 extension functions and the functions running with the caller's rights untouched.
--   G5 no owner-rights function of the app makes a temporary object (create temp, create
--      temporary, pg_temp. in its body); the functions with the caller's rights that do are exactly
--      the known one, ads_resolve_all_attendance(), which anon and authenticated cannot call; and no
--      relation or type in public or pg_catalog is named like a temporary table it makes, so pg_temp
--      last changes nothing for it.
--   A  owner-rights functions still answer: current_user_role(), is_manager_or_above(), a
--      read-only page function (my_assigned_stores), as a signed-in login.
--   U  scripts/permissions/undo-546.sql puts every function back exactly; a second undo refuses;
--      546 again makes the same; it still works after other functions changed (undo-542, undo-541
--      and a new function, with 546 in); with one of its bodies replaced, a real undo refuses, and a
--      test file's (energia.undo546_skip_body_check on) puts the search paths back and leaves the
--      body as it is, then the flag is off again.
--   M  546 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Made-up names only (t546_...). Run it
-- on a copy of production without 546 (it applies 546, then again); with -v skip_install=1 where
-- 546 is in (G2, G3, U and M skipped).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/permissions/tests/search-path-546.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table fn0 as
  select p.oid, p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as def, md5(p.prosrc) as src, p.proacl::text as acl,
         p.proowner, p.provolatile, p.proconfig, p.prosecdef,
         exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e') as ext
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
-- 546 is in when one of its own functions has its search path (G1 below names any function made
-- the old way since).
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as had546
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :{?skip_install}
\if :had546
\else
\echo 546 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had546
\echo 546 is already in: run with -v skip_install=1
select 1/0;
\else
\set mode install
\endif
select :'mode' = 'install' as by_us \gset

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.as_login(uid uuid, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform set_config('request.jwt.claim.sub', uid::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    execute q into v;
    raise exception using errcode = 'P0999', message = coalesce(v, '');
  exception
    when sqlstate 'P0999' then get stacked diagnostics m = message_text; return 'ok:' || m;
    when others then get stacked diagnostics s = returned_sqlstate, m = message_text; return 'ERR ' || s || ' ' || m;
  end;
end $f$;
create temp table targets as
  select fn from fn0 where prosecdef and not ext and proowner = 'postgres'::regrole and 'search_path=public' = any (proconfig);

-- ═════ P why ═════
create table public.t546_shelf (n int);
insert into public.t546_shelf values (1), (2);
create function public.t546_count_old() returns bigint language sql security definer set search_path = public as 'select count(*) from t546_shelf';
create function public.t546_count_new() returns bigint language sql security definer set search_path = public, pg_temp as 'select count(*) from t546_shelf';
create temp table t546_shelf (n int);
insert into t546_shelf select generate_series(1, 9);
select pg_temp.check(public.t546_count_old() = 9 and public.t546_count_new() = 2,
  'P1 with search_path public an owner-rights function reads the session''s temporary table (' || public.t546_count_old()
  || ' rows); with public, pg_temp the public one (' || public.t546_count_new() || ')');
drop table pg_temp.t546_shelf;
drop function public.t546_count_old();
drop function public.t546_count_new();
drop table public.t546_shelf;

\if :by_us
select pg_temp.check((select count(*) from targets) = 1022, 'B1 before 546, 1,022 owner-rights functions of the app have search_path public alone: ' || (select count(*) from targets));
\ir ../../../supabase/546_owner_rights_functions_search_temp_last.sql
\endif

-- ═════ G ═════
select pg_temp.check(count(*) = 0, 'G1 every owner-rights function of the app searches pg_temp last; left: ' || coalesce(string_agg(p.oid::regprocedure::text, ', '), 'none'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proowner = 'postgres'::regrole
   and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
   and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%' and c like '%pg\_temp');
\if :by_us
select pg_temp.check(not exists (select fn, src from fn0 except select p.oid::regprocedure::text, md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace)
                 and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace) = (select count(*) from fn0),
  'G2 every function body is as before (prosrc), and the same functions')
;
select pg_temp.check(count(*) = 1022, 'G3 the 1,022 changed only in their SET search_path line: ' || count(*))
  from fn0 f join pg_proc p on p.oid = f.oid and p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
 where f.fn in (select fn from targets)
   and md5(replace(pg_get_functiondef(p.oid), E' SET search_path TO ''public'', ''pg_temp''\n', E' SET search_path TO ''public''\n')) = f.def
   and md5(pg_get_functiondef(p.oid)) <> f.def
   and p.proacl::text is not distinct from f.acl and p.proowner = f.proowner and p.provolatile = f.provolatile
   and array_remove(p.proconfig, 'search_path=public, pg_temp') = array_remove(f.proconfig, 'search_path=public');
select pg_temp.check(count(*) = 0, 'G3b no other function changed: ' || coalesce(string_agg(f.fn, ', '), 'none'))
  from fn0 f join pg_proc p on p.oid = f.oid and p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
 where f.fn not in (select fn from targets) and md5(pg_get_functiondef(p.oid)) <> f.def;
\endif
select pg_temp.check(exists (select 1 from pg_proc where oid = 'public.invoice_date_evidence(uuid)'::regprocedure
                              and proconfig = array['search_path=public, pg_temp', 'TimeZone=UTC']),
  'G3c invoice_date_evidence keeps its TimeZone setting beside the new search path');
select pg_temp.check(count(*) = 0, 'G4 no extension function and no function with the caller''s rights changed its settings: ' || coalesce(string_agg(f.fn, ', '), 'none'))
  from fn0 f join pg_proc p on p.oid = f.oid and p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
 where (f.ext or not f.prosecdef) and (p.proconfig is distinct from f.proconfig or md5(pg_get_functiondef(p.oid)) <> f.def);
select pg_temp.check(count(*) = 0, 'G5 no owner-rights function of the app makes a temporary object: ' || coalesce(string_agg(p.oid::regprocedure::text, ', '), 'none'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.prosecdef
   and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
   and (p.prosrc ~* 'create\s+(temp|temporary)\M' or p.prosrc ~* 'pg_temp\.');
select pg_temp.check(coalesce(string_agg(p.oid::regprocedure::text, ', ' order by 1), '') = 'ads_resolve_all_attendance()'
                     and bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')),
  'G5b the functions with the caller''s rights that make temporary tables are exactly ads_resolve_all_attendance(), not callable by anon or authenticated: '
  || coalesce(string_agg(p.oid::regprocedure::text, ', '), 'none'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and not p.prosecdef
   and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
   and (p.prosrc ~* 'create\s+(temp|temporary)\M' or p.prosrc ~* 'pg_temp\.');

select pg_temp.check(count(*) = 0, 'G5c no relation or type in public or pg_catalog is named like a temporary table of ads_resolve_all_attendance() ('
  || (select string_agg(distinct lower(m[1]), ', ') from pg_proc p, regexp_matches(p.prosrc, 'create\s+temp(?:orary)?\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)', 'gi') m
       where p.oid = 'public.ads_resolve_all_attendance()'::regprocedure) || '): ' || coalesce(string_agg(n.nspname || '.' || t.name, ', '), 'none'))
  from (select lower(m[1]) as name from pg_proc p, regexp_matches(p.prosrc, 'create\s+temp(?:orary)?\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)', 'gi') m
         where p.oid = 'public.ads_resolve_all_attendance()'::regprocedure) t
  join pg_namespace n on n.nspname in ('public', 'pg_catalog')
 where exists (select 1 from pg_class c where c.relnamespace = n.oid and c.relname = t.name)
    or exists (select 1 from pg_type y where y.typnamespace = n.oid and y.typname = t.name);
select pg_temp.check((select count(*) from pg_proc p, regexp_matches(p.prosrc, 'create\s+temp(?:orary)?\s+table', 'gi') m
                       where p.oid = 'public.ads_resolve_all_attendance()'::regprocedure) = 2,
  'G5d ads_resolve_all_attendance() makes two temporary tables, as read here');

-- ═════ A they still answer ═════
do $fx$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users(id, email, email_confirmed_at) values (u, 't546-' || u || '@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values (u, 'Testing Owner 546', 't546-' || u || '@example.invalid', 'owner', true);
  perform set_config('t546.uid', u::text, true);
end $fx$;
select pg_temp.check(pg_temp.as_login(current_setting('t546.uid')::uuid, 'select public.current_user_role()::text') = 'ok:owner'
                 and pg_temp.as_login(current_setting('t546.uid')::uuid, 'select public.is_manager_or_above()::text') = 'ok:true'
                 and pg_temp.as_login(current_setting('t546.uid')::uuid, 'select (count(*) >= 0)::text from public.my_assigned_stores()') = 'ok:true',
  'A1 owner-rights functions answer a signed-in Owner as before: '
  || pg_temp.as_login(current_setting('t546.uid')::uuid, 'select public.current_user_role()::text') || ' / '
  || pg_temp.as_login(current_setting('t546.uid')::uuid, 'select public.is_manager_or_above()::text') || ' / '
  || pg_temp.as_login(current_setting('t546.uid')::uuid, 'select (count(*) >= 0)::text from public.my_assigned_stores()'));

\if :by_us
-- ═════ U the undo, and M ═════
savepoint u1;
\ir ../undo-546.sql
select pg_temp.check(not exists (select fn, def, acl from fn0 except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), p.proacl::text
                                   from pg_proc p where p.pronamespace = 'public'::regnamespace),
  'U1 the undo puts every function back exactly');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-546.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 546: the functions are already as before 546%', 'U2 a second undo refuses: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/546_owner_rights_functions_search_temp_last.sql
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and 'search_path=public' = any (p.proconfig)),
  'U3 546 after the undo makes the same again');
rollback to savepoint u1;
-- U4: undo-546 looks only at its own functions: after other functions changed (undo-542 and
-- undo-541 run with 546 in, and a function made), it still puts its 1,022 back.
savepoint u4;
\ir ../../invoice-actions/undo-542.sql
\ir ../undo-541.sql
create function public.t546_later() returns int language sql security definer set search_path = public, pg_temp as 'select 1';
\ir ../undo-546.sql
select pg_temp.check((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
                        and p.oid::regprocedure::text in (select fn from targets) and p.proconfig @> array['search_path=public']) = 1022,
  'U4 after undo-542, undo-541 and a new function, undo-546 still puts its 1,022 back');
rollback to savepoint u4;
-- U5: one of its bodies replaced (with 546's search path kept).
savepoint u5;
do $u5$ begin
  execute replace(pg_get_functiondef('public.current_user_role()'::regprocedure), 'AS $function$' || E'\n', 'AS $function$' || E'\n' || '  -- t546 a later body' || E'\n');
end $u5$;
savepoint u5b;
\set ON_ERROR_STOP off
\ir ../undo-546.sql
\set ON_ERROR_STOP on
rollback to savepoint u5b;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 546: the bodies of its functions are not the ones 546 was made with%', 'U5 with one body replaced, a real undo refuses: ' || :'LAST_ERROR_MESSAGE');
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../undo-546.sql
select pg_temp.check((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
                        and p.oid::regprocedure::text in (select fn from targets) and p.proconfig @> array['search_path=public']) = 1022
                     and (select prosrc from pg_proc where oid = 'public.current_user_role()'::regprocedure) like '%t546 a later body%'
                     and coalesce(current_setting('energia.undo546_skip_body_check', true), '') = '',
  'U6 a test file''s undo (the flag on) puts the 1,022 back, leaves the replaced body as it is, and clears the flag');
rollback to savepoint u5;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/546_owner_rights_functions_search_temp_last.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '546 is already in on this database%', 'M1 546 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  B, G2, G3, U and M are skipped (546 was not installed by this file)
\endif

do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
