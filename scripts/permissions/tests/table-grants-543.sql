-- A signed-in login and the public key cannot empty a table, point a foreign key at it or put a
-- trigger on it; a table or view postgres makes in public gets none of the three either (543;
-- security audit of 17 Nov 2026, L15, its first half).
--
--   B  (install mode) before 543: a signed-in login empties a table and puts a trigger on one.
--   G1 no relation of public gives anon or authenticated TRUNCATE, REFERENCES or TRIGGER
--      (has_table_privilege, every table and view; sequences have none of the three).
--   G2 a table and a view made here as postgres give anon and authenticated SELECT, INSERT, UPDATE,
--      DELETE and MAINTAIN, and none of the three. (Covered: postgres, the role every relation of
--      public is owned by. Not covered: supabase_admin, whose default privileges in public Supabase
--      does not let a project change; a table it makes would show here as a G1 failure.)
--   G3 every other grant on every relation is as before (grantee, grantor, privilege, grant
--      option), nothing is granted that was not, rules (RLS) on and off as before.
--   G4 the default privileges of postgres in public: tables as before but for the three; functions
--      and sequences as before; supabase_admin's as they were.
--   G5 no function changed.
--   A  a signed-in login is refused TRUNCATE and CREATE TRIGGER (42501).
--   U  scripts/permissions/undo-543.sql puts every relation's grants back exactly (in the same
--      order) and the default privileges; a second undo refuses; 543 again makes the same.
--   M  543 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Made-up names only (t543_...). Run it
-- on a copy of production without 543 (it applies 543, then again); with -v skip_install=1 where
-- 543 is in (B, U and M skipped).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/permissions/tests/table-grants-543.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table acl0 as
  select c.oid, c.relname, c.relkind, c.relacl::text as acl, c.relrowsecurity as rls
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f');
create temp table ent0 as
  select c.relname, e.grantee::regrole::text as grantee, e.grantor::regrole::text as grantor, e.privilege_type as priv, e.is_grantable as opt
    from pg_class c, aclexplode(c.relacl) e where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f');
create temp table def0 as select d.defaclrole::regrole::text as role, d.defaclobjtype as kind, d.defaclacl::text as acl
  from pg_default_acl d where d.defaclnamespace = 'public'::regnamespace;
create temp table fp0 as select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*) as fp
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
select (select defaclacl::text from pg_default_acl where defaclrole = 'postgres'::regrole and defaclnamespace = 'public'::regnamespace and defaclobjtype = 'r')
       = '{postgres=arwdDxtm/postgres,anon=arwdm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}' as had543 \gset
\if :{?skip_install}
\if :had543
\else
\echo 543 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had543
\echo 543 is already in: run with -v skip_install=1
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
-- A login's call, rolled back: 'ok' or 'ERR <sqlstate>'. The login is any authenticated JWT.
create function pg_temp.as_login(q text) returns text language plpgsql as $f$
declare s text;
begin
  begin
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
    execute 'set local role authenticated';
    execute q;
    raise exception using errcode = 'P0999', message = 'ok';
  exception
    when sqlstate 'P0999' then return 'ok';
    when others then get stacked diagnostics s = returned_sqlstate; return 'ERR ' || s;
  end;
end $f$;
-- A table a login could empty, no foreign key points at, and with no rows to lose (rolled back).
select c.relname as t_trunc from pg_class c
 where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
   and exists (select 1 from ent0 e where e.relname = c.relname and e.grantee = 'authenticated' and e.priv = 'INSERT')
   and (:'mode' = 'skip' or exists (select 1 from ent0 e where e.relname = c.relname and e.grantee = 'authenticated' and e.priv = 'TRUNCATE'))
   and not exists (select 1 from pg_constraint k where k.confrelid = c.oid)
 order by c.relname limit 1 \gset
select format('truncate table public.%I', :'t_trunc') as q_trunc,
       format('create trigger t543_probe before update on public.%I for each row execute function suppress_redundant_updates_trigger()', :'t_trunc') as q_trig \gset

\if :by_us
select pg_temp.as_login(:'q_trunc') as b_trunc, pg_temp.as_login(:'q_trig') as b_trig \gset
select pg_temp.check(:'b_trunc' = 'ok' and :'b_trig' = 'ok', 'B1 before 543 a signed-in login empties ' || :'t_trunc' || ' and puts a trigger on it: ' || :'b_trunc' || ' / ' || :'b_trig');
select pg_temp.check((select count(*) from ent0 where grantee in ('anon', 'authenticated') and priv in ('TRUNCATE', 'REFERENCES', 'TRIGGER')) = 806,
  'B2 before 543 anon and authenticated hold 806 of the three');
\ir ../../../supabase/543_api_roles_cannot_truncate_reference_or_trigger_tables.sql
\endif

-- ═════ G ═════
select pg_temp.check(count(*) = 0, 'G1 no relation of public gives anon or authenticated TRUNCATE, REFERENCES or TRIGGER: ' || coalesce(string_agg(x, ', '), 'none'))
  from (select c.relname || ':' || g || ':' || p as x
          from pg_class c, unnest(array['anon', 'authenticated']) g, unnest(array['TRUNCATE', 'REFERENCES', 'TRIGGER']) p
         where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f') and has_table_privilege(g, c.oid, p)) s;
create table public.t543_new (id int primary key);
create view public.t543_view as select 1 as x;
select pg_temp.check(not has_table_privilege(g, ('public.' || t)::regclass, p), 'G2 ' || t || ' made as postgres: ' || g || ' has no ' || p)
  from unnest(array['t543_new', 't543_view']) t, unnest(array['anon', 'authenticated']) g, unnest(array['TRUNCATE', 'REFERENCES', 'TRIGGER']) p;
select pg_temp.check(has_table_privilege(g, 'public.t543_new', 'SELECT') and has_table_privilege(g, 'public.t543_new', 'INSERT')
                     and has_table_privilege(g, 'public.t543_new', 'UPDATE') and has_table_privilege(g, 'public.t543_new', 'DELETE')
                     and has_table_privilege(g, 'public.t543_new', 'MAINTAIN')
                     and has_table_privilege('service_role', 'public.t543_new', 'TRUNCATE'),
  'G2b ' || g || ' keeps SELECT, INSERT, UPDATE, DELETE and MAINTAIN on a new table; service_role keeps TRUNCATE')
  from unnest(array['anon', 'authenticated']) g;
drop view public.t543_view;
drop table public.t543_new;
select pg_temp.check(not exists (select relname, grantee, grantor, priv, opt from ent0 where not (grantee in ('anon', 'authenticated') and priv in ('TRUNCATE', 'REFERENCES', 'TRIGGER'))
                                 except
                                 select c.relname, e.grantee::regrole::text, e.grantor::regrole::text, e.privilege_type, e.is_grantable
                                   from pg_class c, aclexplode(c.relacl) e where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f'))
                 and not exists (select c.relname, e.grantee::regrole::text, e.grantor::regrole::text, e.privilege_type, e.is_grantable
                                   from pg_class c, aclexplode(c.relacl) e where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f')
                                 except select relname, grantee, grantor, priv, opt from ent0),
  'G3 every other grant on every relation is as before, and nothing new is granted')
 where :'mode' = 'install';
select pg_temp.check(not exists (select relname, rls from acl0 except select c.relname, c.relrowsecurity from pg_class c
                                  where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f'))
                 and (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f')) = (select count(*) from acl0),
  'G3b the same relations, rules on and off as before');
select pg_temp.check((select acl from def0 where role = 'postgres' and kind = 'r') = case when :'mode' = 'install'
                       then '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'
                       else '{postgres=arwdDxtm/postgres,anon=arwdm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}' end
                 and (select d.defaclacl::text from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r')
                     = '{postgres=arwdDxtm/postgres,anon=arwdm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}',
  'G4 postgres''s default privileges on tables in public: as before but for the three');
select pg_temp.check(not exists (select role, kind, acl from def0 where not (role = 'postgres' and kind = 'r')
                                 except select d.defaclrole::regrole::text, d.defaclobjtype, d.defaclacl::text from pg_default_acl d where d.defaclnamespace = 'public'::regnamespace)
                 and (select count(*) from pg_default_acl d where d.defaclnamespace = 'public'::regnamespace) = (select count(*) from def0),
  'G4b the other default privileges in public (functions, sequences, supabase_admin''s) as they were');
select pg_temp.check((select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*)
                        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select fp from fp0),
  'G5 no function changed: ' || (select fp from fp0));

-- ═════ A what a signed-in login is refused ═════
select pg_temp.check(pg_temp.as_login(:'q_trunc') = 'ERR 42501', 'A1 a signed-in login may not empty ' || :'t_trunc' || ': ' || pg_temp.as_login(:'q_trunc'));
select pg_temp.check(pg_temp.as_login(:'q_trig') = 'ERR 42501', 'A2 a signed-in login may not put a trigger on it: ' || pg_temp.as_login(:'q_trig'));
select pg_temp.check(pg_temp.as_login(format('select count(*) from public.%I', :'t_trunc')) = 'ok', 'A3 reading it is as before (its rules decide the rows)');

\if :by_us
-- ═════ U the undo, and M ═════
savepoint u1;
\ir ../undo-543.sql
select pg_temp.check(not exists (select relname, acl, rls from acl0 except select c.relname, c.relacl::text, c.relrowsecurity from pg_class c
                                  where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f'))
                 and not exists (select role, kind, acl from def0 except select d.defaclrole::regrole::text, d.defaclobjtype, d.defaclacl::text from pg_default_acl d where d.defaclnamespace = 'public'::regnamespace),
  'U1 the undo puts every relation''s grants back exactly, in the same order, and the default privileges');
select pg_temp.check(pg_temp.as_login(:'q_trunc') = 'ok', 'U2 after the undo a login empties the table again (the old state)');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-543.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 543: the grants are already as before 543%', 'U3 a second undo refuses: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/543_api_roles_cannot_truncate_reference_or_trigger_tables.sql
select pg_temp.check(not exists (select 1 from pg_class c, unnest(array['anon', 'authenticated']) g, unnest(array['TRUNCATE', 'REFERENCES', 'TRIGGER']) p
                                  where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f') and has_table_privilege(g, c.oid, p)),
  'U4 543 after the undo makes the same again');
rollback to savepoint u1;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/543_api_roles_cannot_truncate_reference_or_trigger_tables.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '543 is already in on this database%', 'M1 543 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  B, G3, U and M are skipped (543 was not installed by this file)
\endif

do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
