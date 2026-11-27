-- 543_api_roles_cannot_truncate_reference_or_trigger_tables.sql
--
-- A SIGNED-IN LOGIN AND THE PUBLIC KEY CANNOT EMPTY A TABLE, POINT A FOREIGN KEY AT IT OR PUT A
-- TRIGGER ON IT; NEW TABLES MADE BY POSTGRES IN PUBLIC GET NONE OF THE THREE EITHER
--
--   From the security audit of 17 Nov 2026 (Low finding L15, its first half: table grants). Grants
--   only: no function, rule or table changes. The checks below are those of production after 541,
--   542 and 544 (head 20261126172814; function fingerprint 8763c2671addf9c45a03b13a4f24ac3b/1462).
--   If production differs when this is applied, it refuses and changes nothing. It does not
--   depend on 545 or 546, and they do not depend on it.
--   (The number 543 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in scripts/permissions/undo-543.sql and in the suite's name and path.)
--
-- GO-LIVE: any time; no page and no Edge Function needs to change. No page, function or server
--   job truncates a table, makes a foreign key or a trigger as anon or authenticated: those are
--   done by migrations, as postgres.
--
-- WHAT WAS WRONG
--
--   Supabase's default grants give anon and authenticated every table privilege on every table
--   made in public. Rules (RLS) still decide which rows they read and write, but TRUNCATE ignores
--   rules, and REFERENCES and TRIGGER are privileges no app login needs. On production, 138 of the
--   243 relations in public (228 tables, 4 views, 11 sequences) give anon and authenticated some of
--   the three: 806 grants in all. Sequences have none of them. None goes through PUBLIC, and none
--   carries a grant option.
--
-- WHAT THIS DOES
--
--   * For every table and view in public, it revokes TRUNCATE, REFERENCES and TRIGGER from anon
--     and authenticated where they hold them. The list is made when it runs, and must be exactly
--     the 806 grants on 138 relations read from production (md5 below); otherwise it refuses.
--   * ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE TRUNCATE, REFERENCES,
--     TRIGGER ON TABLES FROM anon, authenticated: a table or view postgres makes in public from now
--     on gives anon and authenticated SELECT, INSERT, UPDATE, DELETE and MAINTAIN, as today, and
--     none of the three.
--   * Checks after: no relation in public gives anon or authenticated any of the three; every other
--     grant on every relation is as before (grantee, grantor, privilege, grant option); the
--     default privileges of postgres in public are as before but for the three; no function
--     changed (the function fingerprint is the same before and after).
--
-- WHICH CREATING ROLE IS COVERED (default privileges belong to the role that makes the table)
--
--   * postgres: covered. Every one of the 243 relations in public is owned by postgres today; the
--     routes that make tables here run as postgres: migrations applied with the Supabase CLI or the
--     MCP apply_migration, and the SQL editor.
--   * supabase_admin: NOT covered, and it cannot be. Its default privileges in public (all table
--     privileges to anon and authenticated) are Supabase's, and Supabase does not let a project
--     change them ("Can't change the default privileges of supabase_admin in the public schema").
--     Anything Supabase itself makes in public as supabase_admin (an extension installed into public,
--     a platform upgrade, a table made through a Supabase tool that runs as supabase_admin) gets
--     the three again. The extensions in public today, btree_gist and pg_trgm, make functions,
--     types and operators only, no tables. The suite's first check (G1) finds any such table; it
--     is fixed with the same REVOKE.
--   * Other schemas (storage, auth, realtime, graphql, extensions, cron, vault) are not touched.
--
-- WHAT STAYS
--
--   * SELECT, INSERT, UPDATE, DELETE and MAINTAIN for anon and authenticated wherever they have them
--     (the read and write rules decide the rows, as today); service_role and postgres keep every
--     privilege; sequences as they are; the default privileges for functions and sequences.
--   * The order of the entries in each table's ACL: a revoke edits an entry in place. (Production's
--     order-sensitive table-acl md5 b7e18c676dff46a5e5e5f3783474b075 and a local copy's differ in
--     the order of the entries of 8 tables only, so the guard compares each table's entries
--     sorted: c_acl_before below, the same on both.)
--
-- UNDO
--
--   scripts/permissions/undo-543.sql (it refuses unless the grants are exactly 543's): grants the
--   806 back, by name, and puts the three back in postgres's default privileges in public.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/table-grants-543.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Every relation in public, its ACL entries sorted, and whether rules are on (production after
  -- 544): before and after.
  c_acl_before constant text := 'ec936b58f1505de33c44dc74a8bda00b';
  c_acl_after constant text := '5135847bdbb4c61b0499028772f2e78a';
  c_rel_count constant int := 243;
  -- The grants revoked: 'relation:role:privilege', sorted (production after 544).
  c_revoke_md5 constant text := '19160d84f7978cdcffc3ff7e91c0919e';
  c_revoke_rows constant int := 806;
  c_revoke_rels constant int := 138;
  -- The default privileges of postgres on tables in public: before and after.
  c_def_before constant text := '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}';
  c_def_after constant text := '{postgres=arwdDxtm/postgres,anon=arwdm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}';
  c_three constant text[] := array['TRUNCATE', 'REFERENCES', 'TRIGGER'];

  v_lock text := current_setting('lock_timeout');
  v_fp_before text; v_rest_before text; v_acl text; v_md5 text; v_rows int; v_rels int; v_def text;
  r record;
begin
  -- A busy table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  select md5(string_agg(c.relname || '=' || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(c.relacl) a), '')
                        || '/' || c.relrowsecurity, '|' order by c.relname)), count(*)
    into v_acl, v_rows
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f');
  select d.defaclacl::text into v_def from pg_default_acl d
   where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r';
  if v_acl = c_acl_after and v_def = c_def_after then
    raise exception '543 is already in on this database; nothing was changed.'; end if;
  if v_acl is distinct from c_acl_before or v_rows <> c_rel_count then
    raise exception '543: the grants on the tables of public are not the ones this was tested against (% relations, md5 %). Re-read them before applying; nothing was changed.', v_rows, v_acl; end if;
  if v_def is distinct from c_def_before then
    raise exception '543: the default privileges of postgres on tables in public are not the tested ones (%). Re-read them before applying; nothing was changed.', v_def; end if;
  select md5(coalesce(string_agg(x, '|' order by x), '')), count(*), count(distinct t) into v_md5, v_rows, v_rels
    from (select c.relname as t, c.relname || ':' || g || ':' || p as x
            from pg_class c, unnest(array['anon', 'authenticated']) g, unnest(c_three) p
           where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')
             and exists (select 1 from aclexplode(c.relacl) e where e.grantee = g::regrole and e.privilege_type = p)) s;
  if v_md5 <> c_revoke_md5 or v_rows <> c_revoke_rows or v_rels <> c_revoke_rels then
    raise exception '543: the grants to revoke are not the tested ones (% on % relations, md5 %). Nothing was changed.', v_rows, v_rels, v_md5; end if;
  if exists (select 1 from pg_class c, aclexplode(c.relacl) e
              where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f')
                and e.privilege_type = any (c_three) and (e.grantee = 0 or (e.grantee in ('anon'::regrole, 'authenticated'::regrole) and e.is_grantable))) then
    raise exception '543: a grant of one of the three goes through PUBLIC or carries a grant option. Re-read them before applying; nothing was changed.'; end if;
  -- What must not change: every other grant, and every function.
  select md5(string_agg(c.relname || ':' || e.grantee::regrole::text || ':' || e.grantor::regrole::text || ':' || e.privilege_type || ':' || e.is_grantable,
                        '|' order by c.relname, e.grantee::regrole::text, e.grantor::regrole::text, e.privilege_type))
    into v_rest_before
    from pg_class c, aclexplode(c.relacl) e
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f')
     and not (e.grantee in ('anon'::regrole, 'authenticated'::regrole) and e.privilege_type = any (c_three));
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*) into v_fp_before
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';

  -- 2. The revokes, one statement per relation and role, and the default privileges
  for r in select c.relname, g, string_agg(p, ', ' order by p) as privs
             from pg_class c, unnest(array['anon', 'authenticated']) g, unnest(c_three) p
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')
              and exists (select 1 from aclexplode(c.relacl) e where e.grantee = g::regrole and e.privilege_type = p)
            group by c.relname, g order by c.relname, g loop
    execute format('revoke %s on table public.%I from %I', r.privs, r.relname, r.g);
  end loop;
  alter default privileges for role postgres in schema public revoke truncate, references, trigger on tables from anon, authenticated;

  -- 3. Checks after
  if exists (select 1 from pg_class c, unnest(array['anon', 'authenticated']) g, unnest(c_three) p
              where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f')
                and has_table_privilege(g, c.oid, p)) then
    raise exception '543: anon or authenticated still holds one of the three on a relation of public'; end if;
  if (select md5(string_agg(c.relname || ':' || e.grantee::regrole::text || ':' || e.grantor::regrole::text || ':' || e.privilege_type || ':' || e.is_grantable,
                            '|' order by c.relname, e.grantee::regrole::text, e.grantor::regrole::text, e.privilege_type))
        from pg_class c, aclexplode(c.relacl) e
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f')) is distinct from v_rest_before then
    raise exception '543: a grant other than the three changed'; end if;
  select md5(string_agg(c.relname || '=' || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(c.relacl) a), '')
                        || '/' || c.relrowsecurity, '|' order by c.relname)) into v_acl
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S', 'p', 'f');
  select d.defaclacl::text into v_def from pg_default_acl d
   where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r';
  if v_acl is distinct from c_acl_after or v_def is distinct from c_def_after then
    raise exception '543: the grants after are not the tested ones (acl %, default %)', v_acl, v_def; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*)
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') is distinct from v_fp_before then
    raise exception '543: a function changed'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
