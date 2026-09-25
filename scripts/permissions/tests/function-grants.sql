-- Functions are not endpoints by default (339).
--
-- Three things must hold on any database the application runs against, and all
-- three are read from the catalogue rather than from the migration's own
-- bookkeeping. PostgreSQL still grants EXECUTE on every new function to PUBLIC
-- and that built-in default cannot be withdrawn (see 339), so this test is
-- what enforces the convention: add a function without revoking it from anon
-- and the first check below names it.
--
-- Disposable local database only; this test writes nothing.
\set ON_ERROR_STOP on
do $$
declare
  v_public text[] := array['survey_link_info','submit_health_survey','active_customer_source_options',
                           'public_affiliate_referral_info','affiliate_referral_signup'];
  -- Reached only from inside another SECURITY DEFINER function, which runs as
  -- the owner. A staff member calling any of these directly could earn a
  -- commission twice, approve their own transfer, or burn an invoice number.
  v_internal text[] := array['approve_transfer','approve_transfer_multi','earn_invoice_commission',
                             'earn_staff_commission','earn_credit_package_commission','earn_premium_bundle_commission',
                             'reverse_invoice_commission','reverse_staff_commission','refund_credit_purchase',
                             'refund_credit_funded_item','refund_invoice_line','sell_credit_package_with_vouchers',
                             'sell_premium_bundle','consume_customer_credit','deduct_invoice_stock',
                             'restore_invoice_stock','revoke_unclaimed_entitlement_vouchers',
                             'revoke_affiliate_reward_vouchers','tiktok_adjust_product_stock',
                             'tiktok_adjust_voucher_stock','merge_customer_records','next_invoice_no',
                             'issue_credit_lines_for_invoice','lock_settled_invoice','correct_invoice_created_by',
                             -- 357/358: part-payment commission and staff-sales credit
                             'sync_instalment_commissions','trg_sync_instalment_commissions',
                             'invoice_instalment_commission_targets','invoice_instalment_commission_active',
                             'invoice_affiliate_commission_preview','invoice_package_commission_preview',
                             'invoice_sales_credit_split','invoice_staff_sales_ledger','commission_unpaid_amount',
                             -- 356: released credit follows its lot
                             'credit_lot_chain','credit_lot_current','trim_released_paid_credit',
                             'reclaim_released_credit_of_removed_lines','refuse_settled_credit_line_raise',
                             -- 359: package coverage and the refund rule's "used"
                             'therapy_services_coverage','therapy_unit_consumed'];
  bad text; n int;
begin
  -- 1. Nothing outside the five signed-out endpoints is callable with the anon
  --    key, which ships in the browser bundle.
  select string_agg(p.proname, ', ' order by p.proname) into bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'execute')
     and not (p.proname = any(v_public));
  if bad is not null then
    raise exception 'FAIL: callable by anon outside the public allowlist: %', bad; end if;

  -- 2. The five are still reachable, or the public survey and the referral
  --    landing page stop working for signed-out visitors.
  select string_agg(x, ', ') into bad from unnest(v_public) x
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = x
                        and has_function_privilege('anon', p.oid, 'execute'));
  if bad is not null then raise exception 'FAIL: signed-out endpoint no longer reachable: %', bad; end if;

  -- 3. Privileged internals are endpoints for nobody.
  select string_agg(p.proname, ', ' order by p.proname) into bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any(v_internal)
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if bad is not null then
    raise exception 'FAIL: internal helper is callable by a client role: %', bad; end if;

  -- 4. Anything the database evaluates as the person asking — a row-level
  --    security policy, a check constraint, a column default, an index
  --    expression — must stay reachable by staff. user_has_store_access is in
  --    the SELECT policy of nearly every table: revoking it does not lock down
  --    an endpoint, it empties the application for everyone.
  select coalesce(string_agg(t, ' '), '') into bad from (
    select coalesce(pol.qual,'')||' '||coalesce(pol.with_check,'') t from pg_policies pol where pol.schemaname='public'
    union all select pg_get_constraintdef(c.oid) from pg_constraint c join pg_namespace n2 on n2.oid=c.connamespace where n2.nspname='public'
    union all select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_class c on c.oid=d.adrelid
      join pg_namespace n2 on n2.oid=c.relnamespace where n2.nspname='public'
  ) x;
  select string_agg(p.proname, ', ' order by p.proname) into bad
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and bad ~ ('\m' || p.proname || '\M')
     and not has_function_privilege('authenticated', p.oid, 'execute');
  if bad is not null then
    raise exception 'FAIL: a function the database evaluates as the caller is not reachable by staff, so policies and constraints will fail: %', bad; end if;

  select count(*) into n from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'execute');
  raise notice 'PASS: only the 5 signed-out endpoints are callable by anon; % application functions remain callable by staff; the named privileged internals are callable by neither', n;
end $$;
