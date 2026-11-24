-- UNDO of 532 (with the user's go-ahead). It makes the 33 write rules 532 dropped again, and the
-- store-assets rules "store-assets update" and "store-assets delete", exactly as they were
-- (command, role, test); puts "store-assets write", "update stores" and "insert stores" back to an
-- Owner or Manager for every store, and soft_delete_store, restore_store and set_store_policy_text
-- back to their text before 532 (md5 61020273…, a29cb102…, b7793f4b…); and drops the trigger
-- audit_direct_change from the twelve tables and profiles, the trigger
-- payment_method_wallet_locked, and the functions trg_audit_direct_change() (md5 b2ac8670…) and
-- trg_payment_method_wallet_locked() (md5 3b6d9b85…). Afterwards a change made straight on a
-- store, a warehouse, a payment method, a promotion and its parts, a special product, a survey
-- link, a brand, a category, a supplier or a staff profile is no longer recorded, any Manager
-- changes any store, its images and adds stores, a payment method's wallet settings can be
-- changed, and the rules no page uses are open again (the security audit's M7 and M8 open again).
-- The audit rows written while 532 was in stay.
--
-- FIRST put back the Stores page and src/lib/storeAssets.ts of before 532 (they offer a Manager
-- only their own stores, and upload a new file each time).
--
-- It refuses, with nothing changed, unless the two functions, the fourteen triggers, the store
-- and store-assets rules and the three store functions are exactly 532's, no other trigger uses
-- the two functions, and none of the dropped rules is there again (so a later version is never
-- overwritten and nothing that now uses them is broken). One transaction, all or nothing; it waits
-- at most 5 seconds for a lock. The 532 row in supabase_migrations.schema_migrations stays; with
-- the user's OK, remove that one row (found by its name,
-- 532_changes_made_straight_on_the_tables_are_recorded) or record this UNDO beside it.
do $undo$
declare
  c_fn_sig constant text[] := array['trg_audit_direct_change()', 'trg_payment_method_wallet_locked()'];
  c_fn_md5 constant text[] := array['b2ac8670825d1daf73a27c74e64bd66a', '3b6d9b8590d7bdec9df746cff62024f5'];
  c_trg_name constant text := 'audit_direct_change';
  c_trg_table constant text[] := array[
    'stores', 'warehouses', 'payment_methods',
    'promotions', 'promotion_choice_groups', 'promotion_choice_options', 'promotion_items',
    'special_products', 'survey_links',
    'brands', 'categories', 'suppliers',
    'profiles'];
  c_trg_ops constant text[] := array[
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE'];
  c_trg_def constant text := 'CREATE TRIGGER audit_direct_change AFTER %s ON public.%s FOR EACH ROW WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) EXECUTE FUNCTION trg_audit_direct_change()';
  c_pm_trg_def constant text := 'CREATE TRIGGER payment_method_wallet_locked BEFORE INSERT OR UPDATE ON public.payment_methods FOR EACH ROW WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) EXECUTE FUNCTION trg_payment_method_wallet_locked()';
  -- The store rules: 532's, and as they were.
  c_st_upd_532 constant text :=
    '((( SELECT current_user_role() AS current_user_role) = ''owner''::user_role) OR (( SELECT is_owner_or_manager() AS is_owner_or_manager) AND (id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))';
  c_st_ins_532 constant text := '(( SELECT current_user_role() AS current_user_role) = ''owner''::user_role)';
  -- The store-assets rules: 532's write rule, and the three as they were.
  c_sa_write_532 constant text :=
    '((bucket_id = ''store-assets''::text) AND ( SELECT is_owner_or_manager() AS is_owner_or_manager) AND (survey_attachment_store(name) = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))';
  c_sa_src constant text := '((bucket_id = ''store-assets''::text) AND (select public.is_owner_or_manager()))';
  c_sa_before constant text := '((bucket_id = ''store-assets''::text) AND ( SELECT is_owner_or_manager() AS is_owner_or_manager))';
  -- The store functions: 532's, as they were, and 532's text taken out again.
  c_sig constant text[] := array['soft_delete_store(uuid)', 'restore_store(uuid)', 'set_store_policy_text(uuid,text)'];
  c_532 constant text[] := array['3bf8f7b89f34cffae2d46c97a8462c07', '54c3b5e1275429b73b6e6506a2b31ddd', '807d49611ca6fb2896cde9ee9413def9'];
  c_before_532 constant text[] := array['61020273511f69bac2dd86d530d38d2e', 'a29cb102c967cc5a2939a1a334e86b07', 'b7793f4b636e7cccf96b7e80e03cfb03'];
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres'];
  c_anchor constant text[] := array[
$a$  if not found then raise exception 'Store not found'; end if;
$a$,
$a$  if not found then raise exception 'Store not found'; end if;
$a$,
$a$  update public.stores set policy_text = nullif(trim(coalesce(p_text,'')),'') where id = p_store_id;
$a$];
  c_new constant text[] := array[
$n$  if not found then raise exception 'Store not found'; end if;
  -- 532 (security audit of 17 Nov 2026, M7; the user, 20 Nov 2026: "Managers: own stores
  -- only"): an Owner deletes any store, a Manager only a store they work at.
  if v_role = 'manager' and not (p_store_id = any (public.current_user_store_ids())) then
    raise exception 'A Manager can delete only the stores they work at.' using errcode = '42501'; end if;
$n$,
$n$  if not found then raise exception 'Store not found'; end if;
  -- 532 (security audit of 17 Nov 2026, M7; the user, 20 Nov 2026: "Managers: own stores
  -- only"): an Owner restores any store, a Manager only a store they work at.
  if v_role = 'manager' and not (p_store_id = any (public.current_user_store_ids())) then
    raise exception 'A Manager can restore only the stores they work at.' using errcode = '42501'; end if;
$n$,
$n$  -- 532 (security audit of 17 Nov 2026, M7: "every change is recorded"): the policy text before
  -- and after, as a change made straight on the table is recorded (trg_audit_direct_change).
  with o as (select s.id, s.policy_text from public.stores s where s.id = p_store_id for update),
       u as (update public.stores s set policy_text = nullif(trim(coalesce(p_text,'')),'') from o
              where s.id = o.id returning s.id, o.policy_text as old_text, s.policy_text as new_text)
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, store_id)
  select 'stores', u.id, 'store_updated', jsonb_build_object('policy_text', u.old_text),
         jsonb_build_object('policy_text', u.new_text), (select p.id from public.profiles p where p.id = auth.uid()),
         coalesce(public.current_user_role()::text, nullif(current_setting('role', true), 'none')), u.id
    from u where u.old_text is distinct from u.new_text;
$n$];
  -- The 33 rules as they were before 532: table, name, command, and the tests as written and as
  -- pg_get_expr prints them.
  c_om_src constant text := '(select public.is_owner_or_manager())';
  c_ep_src constant text := '(select public.can_edit_products())';
  c_om constant text := '( SELECT is_owner_or_manager() AS is_owner_or_manager)';
  c_ep constant text := '( SELECT can_edit_products() AS can_edit_products)';
  c_pol_table constant text[] := array[
    'health_surveys',
    'health_symptom_options', 'health_symptom_options', 'health_symptom_options',
    'product_categories', 'product_suppliers',
    'products', 'products',
    'promotion_items', 'promotion_items',
    'special_products', 'special_products',
    'store_product_prices', 'store_product_prices', 'store_product_prices',
    'promotion_store_prices', 'promotion_store_prices', 'promotion_store_prices',
    'voucher_store_prices', 'voucher_store_prices', 'voucher_store_prices',
    'voucher_store_stock', 'voucher_store_stock', 'voucher_store_stock',
    'brands', 'categories', 'suppliers', 'payment_methods', 'promotions', 'survey_links', 'vouchers',
    'promotion_choice_groups', 'promotion_choice_options'];
  c_pol_name constant text[] := array[
    'update surveys',
    'insert symptom options', 'update symptom options', 'delete symptom options',
    'product_categories write', 'product_suppliers write',
    'insert products', 'update products',
    'insert promotion items', 'update promotion items',
    'insert special products', 'delete special products',
    'insert store prices', 'update store prices', 'delete store prices',
    'insert promotion prices', 'update promotion prices', 'delete promotion prices',
    'insert voucher prices', 'update voucher prices', 'delete voucher prices',
    'insert voucher stock', 'update voucher stock', 'delete voucher stock',
    'brands delete', 'categories delete', 'suppliers delete', 'delete payment methods', 'delete promotions',
    'delete survey links', 'delete vouchers',
    'update choice groups', 'update choice options'];
  c_pol_cmd constant text[] := array[
    'w',
    'a', 'w', 'd',
    '*', '*',
    'a', 'w',
    'a', 'w',
    'a', 'd',
    'a', 'w', 'd',
    'a', 'w', 'd',
    'a', 'w', 'd',
    'a', 'w', 'd',
    'd', 'd', 'd', 'd', 'd', 'd', 'd',
    'w', 'w'];
  -- 'om' an Owner or Manager, 'ep' can edit products.
  c_pol_who constant text[] := array[
    'om',
    'om', 'om', 'om',
    'ep', 'ep',
    'ep', 'ep',
    'om', 'om',
    'om', 'om',
    'om', 'om', 'om',
    'om', 'om', 'om',
    'om', 'om', 'om',
    'om', 'om', 'om',
    'om', 'om', 'om', 'om', 'om', 'om', 'om',
    'om', 'om'];
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  d text; i int; v_src text; v_txt text; v_q text; v_c text;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_fn_sig) loop
    if to_regprocedure('public.' || c_fn_sig[i]) is null then
      raise exception 'undo 532: public.% is not there; 532 is not in. Nothing was changed.', c_fn_sig[i]; end if;
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_fn_sig[i]))) <> c_fn_md5[i] then
      raise exception 'undo 532: public.% is not 532''s version (md5 %). Nothing was changed.', c_fn_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_fn_sig[i]))); end if;
  end loop;
  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ') into d
    from pg_trigger t
   where (t.tgfoid = to_regprocedure('public.' || c_fn_sig[1])
          and not (t.tgname = c_trg_name and t.tgrelid = any (array(select to_regclass('public.' || x) from unnest(c_trg_table) x))))
      or (t.tgfoid = to_regprocedure('public.' || c_fn_sig[2])
          and not (t.tgname = 'payment_method_wallet_locked' and t.tgrelid = 'public.payment_methods'::regclass));
  if d is not null then
    raise exception 'undo 532: 532''s functions are also used by %. Nothing was changed.', d; end if;
  for i in 1 .. cardinality(c_trg_table) loop
    select pg_get_triggerdef(t.oid) into d from pg_trigger t
     where t.tgrelid = to_regclass('public.' || c_trg_table[i]) and t.tgname = c_trg_name;
    if d is distinct from format(c_trg_def, c_trg_ops[i], c_trg_table[i]) then
      raise exception 'undo 532: the trigger on public.% is not 532''s (%). Nothing was changed.', c_trg_table[i], coalesce(d, 'missing'); end if;
  end loop;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
       where t.tgrelid = 'public.payment_methods'::regclass and t.tgname = 'payment_method_wallet_locked') is distinct from c_pm_trg_def then
    raise exception 'undo 532: the trigger payment_method_wallet_locked is not 532''s. Nothing was changed.'; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) || ' / ' || pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
       where p.polrelid = 'public.stores'::regclass and p.polname = 'update stores') is distinct from c_st_upd_532 || ' / ' || c_st_upd_532
     or (select pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
          where p.polrelid = 'public.stores'::regclass and p.polname = 'insert stores') is distinct from c_st_ins_532 then
    raise exception 'undo 532: the store rules are not 532''s. Nothing was changed.'; end if;
  if (select pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
       where p.polrelid = 'storage.objects'::regclass and p.polname = 'store-assets write') is distinct from c_sa_write_532
     or exists (select 1 from pg_policy p where p.polrelid = 'storage.objects'::regclass
                 and p.polname in ('store-assets update', 'store-assets delete')) then
    raise exception 'undo 532: the store-assets rules are not 532''s. Nothing was changed.'; end if;
  for i in 1 .. cardinality(c_sig) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_532[i] then
      raise exception 'undo 532: public.% is not 532''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (length(d) - length(replace(d, c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 532: 532''s text in public.% is not found exactly once', c_sig[i]; end if;
    v_def[i] := replace(d, c_new[i], c_anchor[i]);
    if md5(v_def[i]) <> c_before_532[i] then
      raise exception 'undo 532: public.% would not be put back exactly (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    if exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]) then
      raise exception 'undo 532: a rule "%" is on public.% again. Re-read it; nothing was changed.', c_pol_name[i], c_pol_table[i]; end if;
  end loop;

  -- 2. Undo
  for i in 1 .. cardinality(c_trg_table) loop
    execute format('drop trigger %I on public.%I', c_trg_name, c_trg_table[i]);
  end loop;
  execute 'drop trigger payment_method_wallet_locked on public.payment_methods';
  for i in 1 .. cardinality(c_fn_sig) loop
    execute format('drop function public.%s', c_fn_sig[i]);
  end loop;
  execute format('alter policy %I on public.stores using (%s) with check (%s)', 'update stores', c_om_src, c_om_src);
  execute format('alter policy %I on public.stores with check (%s)', 'insert stores', c_om_src);
  execute format('alter policy %I on storage.objects with check (%s)', 'store-assets write', c_sa_src);
  execute format('create policy %I on storage.objects as permissive for update to authenticated using (%s)', 'store-assets update', c_sa_src);
  execute format('create policy %I on storage.objects as permissive for delete to authenticated using (%s)', 'store-assets delete', c_sa_src);
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    v_src := case c_pol_who[i] when 'om' then c_om_src else c_ep_src end;
    execute format('create policy %I on public.%I as permissive for %s to authenticated%s%s',
      c_pol_name[i], c_pol_table[i],
      case c_pol_cmd[i] when 'a' then 'insert' when 'w' then 'update' when 'd' then 'delete' else 'all' end,
      case when c_pol_cmd[i] <> 'a' then format(' using (%s)', v_src) else '' end,
      case when c_pol_cmd[i] <> 'd' then format(' with check (%s)', v_src) else '' end);
  end loop;

  -- 3. Checks after: each rule and function as it was
  for i in 1 .. cardinality(c_pol_table) loop
    v_txt := case c_pol_who[i] when 'om' then c_om else c_ep end;
    v_q := case when c_pol_cmd[i] <> 'a' then v_txt end;
    v_c := case when c_pol_cmd[i] <> 'd' then v_txt end;
    if not exists (select 1 from pg_policy p
                    where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]
                      and p.polcmd = c_pol_cmd[i]::"char" and p.polpermissive
                      and p.polroles = array['authenticated'::regrole::oid]
                      and pg_get_expr(p.polqual, p.polrelid) is not distinct from v_q
                      and pg_get_expr(p.polwithcheck, p.polrelid) is not distinct from v_c) then
      raise exception 'undo 532: the rule "%" on public.% was not made as it was', c_pol_name[i], c_pol_table[i]; end if;
  end loop;
  if (select pg_get_expr(p.polqual, p.polrelid) || ' / ' || pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
       where p.polrelid = 'public.stores'::regclass and p.polname = 'update stores') is distinct from c_om || ' / ' || c_om
     or (select pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
          where p.polrelid = 'public.stores'::regclass and p.polname = 'insert stores') is distinct from c_om then
    raise exception 'undo 532: the store rules were not put back as they were'; end if;
  if (select string_agg(p.polname || ' ' || p.polcmd::text || ' ' || p.polroles::regrole[]::text || ' '
                        || coalesce(pg_get_expr(p.polqual, p.polrelid), '-') || ' / ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'), '; ' order by p.polname)
        from pg_policy p where p.polrelid = 'storage.objects'::regclass and p.polname in ('store-assets write', 'store-assets update', 'store-assets delete'))
     is distinct from 'store-assets delete d {authenticated} ' || c_sa_before || ' / -; store-assets update w {authenticated} ' || c_sa_before
                      || ' / -; store-assets write a {authenticated} - / ' || c_sa_before then
    raise exception 'undo 532: the store-assets rules were not put back as they were'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before_532[i] then
      raise exception 'undo 532: public.% was not put back exactly', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 532: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if exists (select 1 from pg_trigger t where t.tgname in (c_trg_name, 'payment_method_wallet_locked') and not t.tgisinternal) then
    raise exception 'undo 532: a trigger of 532 is still there'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
