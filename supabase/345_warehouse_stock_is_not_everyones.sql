begin;
-- =====================================================================
-- WAREHOUSE STOCK IS NOT EVERYONE'S TO SPEND
--
-- record_stock_use writes off stock at a store or at a warehouse. It checks
-- the caller for one of those two and not the other:
--
--     if p_location_type = 'store' and not public.user_has_store_access(p_location_id) then
--       raise exception 'No access to this store'; end if;
--
-- The warehouse branch then deducts warehouse_inventory with no check at all.
-- Nothing else stops it: the function is SECURITY DEFINER owned by the table
-- owner, so warehouse_inventory's own write policy — which does ask
-- can_manage_warehouse_stock() — is bypassed inside it, and there is no trigger
-- on that table that would object. The function is granted to signed-in users
-- because staff legitimately use it for a store.
--
-- So any signed-in member of staff, of any role and at any branch, could write
-- off any quantity of any product from any warehouse, with an audit trail
-- naming them and no way to refuse it.
--
-- The fix is the permission the rest of the application already uses for
-- warehouse stock, applied to the branch that was missing it. No screen
-- changes: the stock-use screen only ever passes 'store', so the people who
-- use this function every day are unaffected.
--
-- Anchored on the installed text and idempotent.
-- =====================================================================
do $$
declare
  f record;
  v_src text; v_new text; v_fixed int := 0;
  v_anchor constant text :=
    '  if p_location_type = ''store'' and not public.user_has_store_access(p_location_id) then
    raise exception ''No access to this store''; end if;';
  v_fix constant text :=
    '  if p_location_type = ''store'' and not public.user_has_store_access(p_location_id) then
    raise exception ''No access to this store''; end if;
  -- Warehouse stock has its own permission, and this branch never asked for
  -- it. Same rule as the warehouse screens and the warehouse write policy.
  if p_location_type = ''warehouse'' and not public.can_manage_warehouse_stock() then
    raise exception ''You do not have permission to use stock from a warehouse''; end if;';
begin
  for f in
    select p.oid, p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'record_stock_use'
  loop
    v_src := pg_get_functiondef(f.oid);
    if v_src ~ 'can_manage_warehouse_stock' then
      raise notice '345: % already checks the warehouse permission', f.sig;
      continue;
    end if;
    if position(v_anchor in v_src) = 0 then
      raise exception '345: % does not contain the store check this migration anchors on; add the warehouse check by hand', f.sig;
    end if;
    v_new := replace(v_src, v_anchor, v_fix);
    execute v_new;
    v_fixed := v_fixed + 1;
  end loop;

  if v_fixed > 0 then
    raise notice '345: % overload(s) of record_stock_use now require the warehouse permission for a warehouse write-off', v_fixed;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'record_stock_use'
       and p.prosrc !~ 'can_manage_warehouse_stock') then
    raise exception '345: a record_stock_use overload still deducts warehouse stock without a permission check';
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
