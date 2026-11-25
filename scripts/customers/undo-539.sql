-- UNDO of 539 (with the user's go-ahead). It puts the five functions 539 patched back exactly as
-- they were before 539 (search_customers, therapy_customer_summary, customer_survey_overview,
-- active_affiliates_for_picker, user_admin_list; md5s below), by taking 539's text out again; puts
-- the read rules "read customers" and "read phone history" back to any staff role; gives
-- authenticated and anon their table-wide SELECT on public.profiles back (and takes 539's nine
-- column grants off); drops the three functions 539 made (customer_list_guard, export_customers,
-- my_profile_contact_details). Afterwards every staff role, Inventory Manager included, reads and
-- pages through the whole customer list again with no limit, and every staff login reads every
-- colleague's login email, personal phone and personal email: the security audit's M13 open again.
-- Run scripts/customers/undo-540.sql first if 540 is in.
--
-- The pages of 539 work with or without 539, but their Customers export calls export_customers:
-- after the undo it falls back to paging search_customers, as before 539 (no Audit Log entry).
--
-- WHAT STAYS: the Audit Log keeps its customers_exported entries (it keeps every entry, 536).
--
-- It refuses, with nothing changed, unless every function, rule and grant 539 made or
-- changed is exactly 539's and no other function calls the new ones. One transaction, all or
-- nothing; it waits at most 5 seconds for a lock. The 539 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row or record
-- this UNDO beside it.
do $undo$
declare
  c_sig constant text[] := array[
    'search_customers(text,text,integer,integer,text,date,date)',
    'therapy_customer_summary(text,integer,integer,boolean)',
    'customer_survey_overview(text,text,integer,integer)',
    'active_affiliates_for_picker()',
    'user_admin_list()'];
  c_before constant text[] := array[
    'a7403700638459c6567a039ddab398f9',
    'af030b297c6ab5dc2c64bde101722279',
    'd0301231179b3d05107e3309264692ff',
    '95316cbb02a3ecc6c078c8b877b14d6d',
    '4d770ec592c3e96644602f196b4f7ce2'];
  c_539 constant text[] := array['25f9a33395ad17f7d6b8f63252bd34ab', '93c046a23c15684aa88a67b2dd3f5c34', '42b98e0787c27efa66f4b32c0272c8dc', 'a75fa8c401202112d4abf0b478b0e59a', 'ab6167ddfea14ecc4b1140ce4221a0d4'];
  c_acl constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_fn constant int[] := array[1, 2, 3, 4, 5, 5];
  c_anchor constant text[] := array[
$a$AS $function$
  -- 398: the Customers page's list$a$,
$a$  select public.require_active_staff();  -- 406: active staff only
  with vouchers as ($a$,
$a$  select public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff only; 419: not Inventory Managers (health data)
$a$,
$a$  select public.require_active_staff();  -- 406: active staff only
  select a.id, a.customer_id, c.full_name, c.phone, a.store_id$a$,
$a$  select p.id, p.full_name, p.email, p.role, p.is_active, p.invitation_status,$a$,
$a$         p.work_phone, p.personal_phone, p.personal_email,$a$];
  c_new constant text[] := array[
$n$AS $function$
  -- 539 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026): an Inventory Manager gets no
  -- customer list, and anyone but an Owner or a Manager at most 50 customers a call (they page on).
  select public.customer_list_guard(p_limit);
  -- 398: the Customers page's list$n$,
$n$  select public.require_active_staff();  -- 406: active staff only
  -- 539 (security audit of 17 Nov 2026, M13): no Inventory Manager; at most 50 a call but for an
  -- Owner or a Manager.
  select public.customer_list_guard(p_limit);
  with vouchers as ($n$,
$n$  select public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff only; 419: not Inventory Managers (health data)
  -- 539 (security audit of 17 Nov 2026, M13): at most 50 a call but for an Owner or a Manager
  -- (who keep 200, below).
  select public.customer_list_guard(p_limit);
$n$,
$n$  select public.require_active_staff();  -- 406: active staff only
  -- 539 (security audit of 17 Nov 2026, M13): no Inventory Manager (no customer list for them).
  select public.customer_list_guard(null);
  select a.id, a.customer_id, c.full_name, c.phone, a.store_id$n$,
$n$  -- 539 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026): the login email, personal
  -- phone and personal email for an Owner or a Manager, and for each person their own; empty
  -- for anyone else (an Admin).
  select p.id, p.full_name,
         case when public.current_user_role() in ('owner', 'manager') or p.id = auth.uid() then p.email end,
         p.role, p.is_active, p.invitation_status,$n$,
$n$         p.work_phone,
         case when public.current_user_role() in ('owner', 'manager') or p.id = auth.uid() then p.personal_phone end,
         case when public.current_user_role() in ('owner', 'manager') or p.id = auth.uid() then p.personal_email end,$n$];
  c_pol_before constant text := '((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))';
  c_pol_before_src constant text := '(deleted_at is null) and ((select public.current_user_role()) is not null)';
  c_pol_539 constant text := '((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) = ANY (ARRAY[''owner''::user_role, ''admin''::user_role, ''manager''::user_role, ''staff''::user_role])))';
  c_ph_before constant text := '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)';
  c_ph_before_src constant text := '((select public.current_user_role()) is not null)';
  c_ph_539 constant text := '(( SELECT current_user_role() AS current_user_role) = ANY (ARRAY[''owner''::user_role, ''admin''::user_role, ''manager''::user_role, ''staff''::user_role]))';
  c_prof_acl_before constant text := 'anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres';
  c_prof_acl_539 constant text := 'anon=awdDxtm/postgres,authenticated=awdDxtm/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres';
  c_prof_read constant text[] := array['id', 'full_name', 'role', 'is_active', 'deleted_at', 'created_at', 'updated_at', 'work_phone', 'invitation_status'];
  c_new_sig constant text[] := array[
    'customer_list_guard(integer)',
    'export_customers(text,text,text,text,date,date,date,date)',
    'my_profile_contact_details()'];
  c_new_md5 constant text[] := array['de5cfaa12b667a4df0d45721b9531141', '1d0eb73a09a49a939f353582844c1fd5', '6ae2834b13b1ab52653da4cf342b99df'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[5]);
  v_n int;
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  -- 540 builds on 539: its undo goes first.
  if to_regprocedure('public.inventory_manager_guard(text)') is not null then
    raise exception 'undo 539: 540 is in; run scripts/customers/undo-540.sql first. Nothing was changed.'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'undo 539: public.% is missing. Nothing was changed.', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_before[i] then
      raise exception 'undo 539: public.% is already its version of before 539; 539 is not in. Nothing was changed.', c_sig[i]; end if;
    if md5(d) <> c_539[i] then
      raise exception 'undo 539: public.% is not 539''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception 'undo 539: the grants of public.% are not the tested ones. Nothing was changed.', c_sig[i]; end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception 'undo 539: public.% is missing or not 539''s. Nothing was changed.', c_new_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
         where p.oid = to_regprocedure('public.' || c_new_sig[i]))
       is distinct from (case when c_new_sig[i] = 'customer_list_guard(integer)' then 'postgres=X/postgres'
                              else 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres' end) then
      raise exception 'undo 539: the grants of public.% are not 539''s. Nothing was changed.', c_new_sig[i]; end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and p.oid not in (select to_regprocedure('public.' || x) from unnest(c_sig || c_new_sig) x)
     and pg_get_functiondef(p.oid) ~ 'customer_list_guard|export_customers|my_profile_contact_details';
  if d is not null then
    raise exception 'undo 539: 539''s functions are also used by %. Nothing was changed.', d; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.customers'::regclass and p.polname = 'read customers') is distinct from c_pol_539 then
    raise exception 'undo 539: the read rule of public.customers is not 539''s. Nothing was changed.'; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.customer_phone_history'::regclass and p.polname = 'read phone history') is distinct from c_ph_539 then
    raise exception 'undo 539: the read rule of public.customer_phone_history is not 539''s. Nothing was changed.'; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_class c, unnest(c.relacl) x
       where c.oid = 'public.profiles'::regclass) is distinct from c_prof_acl_539
     or (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a
          where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and a.attacl::text = '{authenticated=r/postgres}')
        is distinct from (select string_agg(x, ',' order by x) from unnest(c_prof_read) x)
     or (select count(*) from pg_attribute a where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and a.attacl is not null)
        <> cardinality(c_prof_read) then
    raise exception 'undo 539: the grants on public.profiles are not 539''s. Nothing was changed.'; end if;
  for i in reverse cardinality(c_fn) .. 1 loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 539: 539''s text % is not found exactly once in public.%. Nothing was changed.', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'undo 539: public.% without 539''s text is not its version of before 539 (md5 %). Nothing was changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;
  select count(*) into v_n from public.audit_logs where action = 'customers_exported';
  raise notice 'undo 539: the Audit Log keeps its % customers_exported entr(y/ies).', v_n;

  -- 2. Put back (the patched functions first: they call customer_list_guard)
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  execute format('alter policy %I on public.customers using (%s)', 'read customers', c_pol_before_src);
  execute format('alter policy %I on public.customer_phone_history using (%s)', 'read phone history', c_ph_before_src);
  for i in reverse cardinality(c_new_sig) .. 1 loop
    execute format('drop function public.%s', c_new_sig[i]);
  end loop;
  execute format('revoke select (%s) on table public.profiles from authenticated',
                 (select string_agg(quote_ident(x), ', ') from unnest(c_prof_read) x));
  grant select on table public.profiles to authenticated, anon;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception 'undo 539: public.% is not as before 539 after putting it back', c_sig[i]; end if;
  end loop;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.customers'::regclass and p.polname = 'read customers') is distinct from c_pol_before then
    raise exception 'undo 539: the read rule of public.customers is not as before 539 after putting it back'; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.customer_phone_history'::regclass and p.polname = 'read phone history') is distinct from c_ph_before then
    raise exception 'undo 539: the read rule of public.customer_phone_history is not as before 539 after putting it back'; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_class c, unnest(c.relacl) x
       where c.oid = 'public.profiles'::regclass) is distinct from c_prof_acl_before
     or exists (select 1 from pg_attribute a where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and a.attacl is not null) then
    raise exception 'undo 539: the grants on public.profiles are not as before 539 after putting them back'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
