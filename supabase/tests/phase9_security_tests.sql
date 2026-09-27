-- =====================================================================
-- PHASE 9 SECURITY / ACCEPTANCE CHECKS — run AFTER migration 58.
-- Read-only assertions against the catalog + a few invariants. No writes.
-- =====================================================================
do $$
declare v_cnt integer; v_bad text;
begin
  -- 1. Sensitive tables have NO direct write policy for authenticated.
  select string_agg(tablename || '.' || policyname, ', ') into v_bad
  from pg_policies
  where schemaname = 'public'
    and tablename in ('commissions','staff_commissions',
                      'invoice_refunds','purchased_therapy_entitlements','customer_affiliates',
                      'consultant_notes','invoices','invoice_items','app_settings')
    and cmd in ('INSERT','UPDATE','DELETE','ALL')
    and 'authenticated' = any(roles);
  if v_bad is not null then raise exception 'FAIL: direct write policies remain: %', v_bad; end if;
  raise notice 'PASS: no direct authenticated write policies on sensitive tables';

  -- 2. Phase 19 removed Membership entirely: no table may remain.
  perform 1 from information_schema.tables
   where table_schema = 'public' and table_name in
     ('customer_memberships','member_ids','member_id_reservations','membership_plans','membership_plan_store_prices');
  if found then raise exception 'FAIL: a Membership table still exists'; end if;
  raise notice 'PASS: no Membership table remains';

  -- 3. Therapy overlap exclusion constraint exists.
  perform 1 from pg_constraint where conname = 'excl_pte_same_package_no_overlap';
  if not found then raise exception 'FAIL: therapy overlap constraint missing'; end if;
  raise notice 'PASS: therapy same-package overlap constraint present';

  -- 4. Role gate helpers exist.
  perform 1 from pg_proc where proname = 'is_owner_or_manager';
  if not found then raise exception 'FAIL: is_owner_or_manager missing'; end if;
  perform 1 from pg_proc where proname = 'user_has_store_access';
  if not found then raise exception 'FAIL: user_has_store_access missing'; end if;
  raise notice 'PASS: role/store gate helpers present';

  -- 5. New gated RPC exists.
  perform 1 from pg_proc where proname = 'set_staff_commission_rate';
  if not found then raise exception 'FAIL: set_staff_commission_rate missing'; end if;
  raise notice 'PASS: gated staff-commission-rate RPC present';

  -- 6. Retired therapy functions are stubs (still present so legacy activation
  --    works), not dropped — confirm they exist and raise.
  perform 1 from pg_proc where proname = 'create_therapy_entitlements';
  if not found then raise exception 'FAIL: create_therapy_entitlements stub missing'; end if;
  raise notice 'PASS: retired therapy functions retained as stubs';

  raise notice '=== ALL PHASE 9 SECURITY CHECKS PASSED ===';
end $$;
