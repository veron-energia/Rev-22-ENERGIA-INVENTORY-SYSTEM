begin;
-- =====================================================================
-- A FUNCTION IS NOT AN ENDPOINT UNTIL SOMEONE SAYS SO
--
-- PostgreSQL grants EXECUTE on a new function to PUBLIC, and Supabase gives
-- the anon and authenticated roles USAGE on this schema. So every function
-- written here has been callable, over HTTP, by anyone holding the anon key —
-- and the anon key ships inside the browser bundle. Measured on production
-- before this migration: of 794 application functions in this schema, 637 were
-- callable by anon; 514 of those are SECURITY DEFINER, so they run as the
-- owner and row-level security does not stop them; and 79 of those are
-- volatile and contain no authorization check of any kind. Among them
-- approve_transfer,
-- refund_credit_purchase, refund_invoice_line, sell_credit_package_with_vouchers,
-- earn_staff_commission, tiktok_adjust_product_stock,
-- revoke_unclaimed_entitlement_vouchers and the next_*_no allocators.
--
-- Some functions already carry the right grants: 326, 336 and 337 each end with
-- "revoke all from public, anon; grant execute to authenticated". That is the
-- convention. This applies it to every function at once.
--
-- Functions belonging to an extension (btree_gist and pg_trgm put 219 type and
-- index support functions in this schema) are left alone: they are not
-- application code, they are owned by supabase_admin rather than by the role
-- running migrations, and revoking them would fail.
--
-- Three kinds, decided at apply time so the result is correct on whichever
-- database this runs against:
--
--   public     the five endpoints a signed-out visitor legitimately reaches —
--              the token-gated health survey and the referral landing page.
--              anon + authenticated.
--   client     everything the application actually calls, including the names
--              it builds at run time (reports, the affiliate portal, price
--              editors, stock history, tiktok staging). authenticated only.
--   internal   every other SECURITY DEFINER function: helpers reached only
--              from inside another function, which runs as the owner and so
--              needs no grant of its own. Nobody.
--
-- A SECURITY INVOKER function keeps its grant: it runs with the caller's own
-- rights, so row-level security already decides what it may do, and revoking
-- it would break the direct table writes whose triggers call it. Trigger
-- functions are revoked from everyone — PostgreSQL checks EXECUTE when a
-- trigger is CREATED, not when it fires, and calling one directly only ever
-- raises "trigger functions can only be called as triggers".
--
-- No role gains anything here. Every role loses reach it should not have had.
-- =====================================================================

do $$
declare
  v_public text[] := array[
    'survey_link_info', 'submit_health_survey', 'active_customer_source_options', 'public_affiliate_referral_info', 'affiliate_referral_signup'
  ];
  v_client text[] := array[
    'activate_purchased_therapy', 'activate_rental', 'active_affiliates_for_picker', 'active_customer_source_options', 'active_foc_reasons',
    'add_consultant_note', 'add_customer_remark', 'add_legacy_credit', 'add_promotion_item', 'add_survey_attachment',
    'adjust_customer_credit', 'affiliate_admin_directory', 'affiliate_legacy_day_summary', 'affiliate_payout_history', 'affiliate_payout_overview',
    'affiliate_pending_claims', 'affiliate_portal_dashboard', 'affiliate_portal_earnings', 'affiliate_portal_me', 'affiliate_portal_network',
    'affiliate_portal_payouts', 'affiliate_portal_purchases', 'affiliate_portal_referral_info', 'affiliate_referral_signup', 'affiliate_rejected_claims',
    'affiliate_staff_directory', 'apply_commission_rebase_all', 'apply_line_foc', 'archive_therapy_service', 'assignable_roles',
    'assignable_store_ids', 'auth_email_record_outcome', 'auth_email_reserve', 'auth_email_user_state', 'backfill_legacy_qualification',
    'bundle_line_components', 'cancel_invoice_recorded', 'cancel_rental', 'cancel_special_sale', 'cancel_transfer_request',
    'change_customer_phone', 'choose_therapy_benefit', 'claim_entitlement_vouchers', 'claim_legacy_therapy', 'clear_therapy_voucher_definition',
    'commission_outside_rebase_scope', 'commission_referrer_names', 'commission_totals_reconciliation', 'complete_affiliate_onboarding', 'confirm_foc_invoice',
    'confirm_tiktok_batch', 'confirm_tiktok_settlement_batch', 'consultant_notes_for', 'correct_affiliate_payout', 'correct_invoice',
    'correct_invoice_payment', 'correct_tiktok_row', 'create_customer_quick', 'create_exchange_with_details', 'create_invoice_with_details',
    'create_rental', 'create_special_sale', 'create_split_credit_package_invoices', 'create_split_premium_bundle_invoices', 'create_staff_commission_payout',
    'create_staff_transfer_request', 'create_transfer_request', 'credit_package_benefit_preview', 'credit_package_effective_rules', 'credit_packages_for_store',
    'credit_spendable_categories', 'customer_credit_balances', 'customer_credit_statement', 'customer_match_candidates', 'customer_overview',
    'customer_profile_stats', 'customer_purchase_timeline', 'customer_survey_overview', 'daily_payments_by_method', 'dashboard_alerts_summary',
    'dashboard_credit_by_store', 'dashboard_credit_spend', 'dashboard_sales', 'dashboard_sales_by_store', 'dashboard_summary',
    'delete_affiliate_account_claim', 'delete_customer', 'delete_invoice', 'delete_survey_attachment', 'delete_therapy_closure_date',
    'delete_tiktok_batch', 'delete_tiktok_row', 'edit_transfer_request', 'entitlement_voucher_state', 'exchange_ineligibility_reason',
    'exchange_invoice_details', 'exchange_original_context', 'exchange_payment_position', 'fulfil_special_doc', 'health_survey_detail',
    -- The three invitation functions an administrator calls AS THEMSELVES, through
    -- the admin-invite-user function's caller client (230 granted them to
    -- authenticated; 231 re-granted cancel). They are spelled callerRpc('...')
    -- rather than supabase.rpc('...'), which is why a grep for the latter missed
    -- them. Each still gates itself on user_admin_role()/can_assign_role().
    -- invite_user_accept is deliberately NOT here: 230 and 231 revoked it from
    -- authenticated on purpose, it is called only by the service role, and it
    -- takes the user id and email as arguments instead of reading auth.uid(),
    -- so granting it to signed-in users would let anyone accept somebody else's
    -- invitation and activate their profile.
    'invite_user_begin', 'invite_user_prepare_resend', 'invite_user_cancel',
    'invoice_action_plan', 'invoice_action_request_detail', 'invoice_benefit_review_options', 'invoice_bill_to_source',
    'invoice_credit_reward_entitlements', 'invoice_effective_affiliate', 'invoice_financial_position', 'invoice_legacy_entitlements', 'invoice_list_page',
    'invoice_refund_options', 'invoice_rentals_awaiting_return', 'invoice_reopen_preview', 'invoice_revision_history', 'invoice_sales_ledger',
    'invoice_stock_component_evidence', 'invoice_therapy_summary', 'invoice_transferable_benefits', 'legacy_qualification_diagnose', 'legacy_reward_options',
    'legacy_reward_options_diagnostic', 'legacy_reward_voucher_options', 'legacy_setup_status', 'list_deleted_customers', 'my_assigned_store_id',
    'my_assigned_stores', 'pay_rental', 'pay_special_with_credit', 'payment_methods_in_range', 'premium_bundle_benefit_preview',
    'premium_bundles_for_store', 'preview_commission_rebase_effect', 'preview_credit_package_policy_change', 'preview_invoice_correction', 'products_available_as_special',
    'promotion_original_total', 'public_affiliate_referral_info', 'purchased_therapy_unit_state', 'purchased_therapy_units', 'reactivate_affiliate',
    'reassign_customer_referrer', 'rebuild_invoice_stock_components', 'receive_returned_rental', 'receive_transfer', 'record_affiliate_payout',
    'record_document_send', 'record_invoice_benefit_values', 'record_invoice_settlement', 'record_stock_use', 'referrer_downline',
    'referrer_earnings', 'referrer_list', 'refresh_tiktok_staging', 'refund_invoice_recorded', 'refund_purchased_therapy',
    'reject_affiliate_account_claim', 'reject_transfer', 'remove_line_foc', 'reopen_invoice', 'reorder_customer_source_options',
    'report_affiliates', 'report_customer_sources', 'report_discounts', 'report_exchange_invoices', 'report_foc_lines',
    'report_foc_summary', 'report_pricing', 'report_sales_reconciliation', 'report_therapy', 'report_tiktok_imports',
    'report_tiktok_orders_by_status', 'report_tiktok_qty_sold', 'report_tiktok_recon_exceptions', 'report_tiktok_settlement', 'report_tiktok_settlement_by_store',
    'report_tiktok_settlement_daily', 'report_tiktok_settlement_summary', 'report_tiktok_unmatched_skus', 'report_transfer_discrepancies', 'report_transfer_receipts',
    'report_transfers_overdue', 'request_inventory_adjustment', 'request_invoice_action', 'request_invoice_action_v2', 'reschedule_purchased_therapy',
    'resolve_affiliate_account_claim', 'resolve_inventory_adjustment', 'resolve_invoice_action_v2', 'resolve_invoice_credit_rewards', 'resolve_tiktok_physical_return',
    'resolve_transfer_discrepancy', 'restore_customer_with_phone', 'return_rental', 'review_and_dispatch_transfer', 'review_health_survey',
    'search_customers', 'set_catalogue_reward', 'set_catalogue_sku', 'set_commission_rates', 'set_credit_package_spending_rules',
    'set_customer_source', 'set_customer_source_option_active', 'set_invoice_affiliate', 'set_invoice_fulfilment_warehouse', 'set_invoice_instalment_label',
    'set_low_stock_threshold', 'set_product_important', 'set_product_prices', 'set_promotion_price_all_stores', 'set_promotion_prices',
    'set_staff_commission_rate', 'set_therapy_calendar_coverage', 'set_therapy_service_store', 'set_tiktok_status_mapping_active', 'set_unlimited_therapy_price',
    'set_voucher_price_all_stores', 'set_voucher_prices', 'special_docs_awaiting_fulfilment', 'special_product_availability', 'special_stock_in',
    'stage_tiktok_orders', 'stage_tiktok_settlement', 'stock_history_options', 'stock_history_page', 'stock_history_table',
    'stock_transfer_details', 'store_commission_staff', 'submit_health_survey', 'survey_link_info', 'suspend_affiliate',
    'switch_therapy_benefit', 'therapy_apply_recalculation', 'therapy_calendar_gaps', 'therapy_closure_impact', 'therapy_customer_detail',
    'therapy_customer_summary', 'therapy_map_entitlement_tier', 'therapy_recalculation_preview', 'therapy_reward_mapping_preview', 'therapy_service_catalogue',
    'therapy_voucher_definition', 'tiktok_negative_stock_alerts', 'tiktok_settlement_totals', 'transfer_invoice_unused_benefit', 'transfer_product_sourcing',
    'transfer_receipt_alerts', 'transfer_request_sourcing', 'transfer_revisions', 'update_pending_rental', 'update_survey_particulars',
    'upsert_consultant_survey', 'upsert_credit_package', 'upsert_customer_source_option', 'upsert_legacy_rule', 'upsert_premium_bundle',
    'upsert_special_product_from_product', 'upsert_therapy_closure_date', 'upsert_therapy_package_choice', 'upsert_therapy_service', 'upsert_therapy_voucher_definition',
    'upsert_tiktok_sku_alias', 'upsert_tiktok_status_mapping', 'upsert_unlimited_therapy_package', 'user_admin_list', 'verify_invoice_credit_sale_sources',
    'voucher_stock_in', 'warehouse_stock_in', 'write_audit'
  ];
  v_invoker_src text;
  v_evaluated text;
  f record;
  n_public int := 0; n_client int := 0; n_internal int := 0; n_invoker int := 0; n_trigger int := 0;
  v_has_anon boolean := exists (select 1 from pg_roles where rolname = 'anon');
  v_has_auth boolean := exists (select 1 from pg_roles where rolname = 'authenticated');
  v_has_svc  boolean := exists (select 1 from pg_roles where rolname = 'service_role');
begin
  -- Every SECURITY INVOKER body, so a helper called from one keeps its grant:
  -- inside an invoker function the current role is still the staff member.
  select coalesce(string_agg(p.prosrc, E'\n'), '') into v_invoker_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and not p.prosecdef
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');

  -- And everything the database itself evaluates as whoever is asking: a
  -- row-level security policy, a check constraint, a column default, an index
  -- expression. user_has_store_access is the one that matters most — it is in
  -- the SELECT policy of nearly every table, so revoking it from staff would
  -- not lock down an endpoint, it would empty the application.
  select coalesce(string_agg(t, ' '), '') into v_evaluated from (
    select coalesce(pol.qual, '') || ' ' || coalesce(pol.with_check, '') as t
      from pg_policies pol where pol.schemaname = 'public'
    union all
    select pg_get_constraintdef(c.oid) from pg_constraint c
      join pg_namespace n on n.oid = c.connamespace where n.nspname = 'public'
    union all
    select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d
      join pg_class c on c.oid = d.adrelid
      join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'
    union all
    select pg_get_expr(i.indexprs, i.indrelid) from pg_index i
      join pg_class c on c.oid = i.indrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and i.indexprs is not null
  ) x;

  for f in
    select p.oid::regprocedure::text as sig, p.proname, p.prosecdef,
           pg_catalog.format_type(p.prorettype, null) = 'trigger' as is_trigger
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     order by p.proname
  loop
    -- Nothing is reached through the default PUBLIC grant any more.
    execute format('revoke all on function %s from public', f.sig);
    if v_has_anon then execute format('revoke all on function %s from anon', f.sig); end if;
    if v_has_auth then execute format('revoke all on function %s from authenticated', f.sig); end if;
    -- The trusted server-side role keeps its reach: the edge functions use it.
    if v_has_svc then execute format('grant execute on function %s to service_role', f.sig); end if;

    if f.is_trigger then
      n_trigger := n_trigger + 1;                       -- fired by the table, never called
    elsif f.proname = any(v_public) then
      if v_has_anon then execute format('grant execute on function %s to anon', f.sig); end if;
      if v_has_auth then execute format('grant execute on function %s to authenticated', f.sig); end if;
      n_public := n_public + 1;
    elsif f.proname = any(v_client) then
      if v_has_auth then execute format('grant execute on function %s to authenticated', f.sig); end if;
      n_client := n_client + 1;
    elsif not f.prosecdef
          or v_invoker_src ~ ('\m' || f.proname || '\M')
          or v_evaluated ~ ('\m' || f.proname || '\M') then
      -- Runs as the caller, is called from something that does, or is part of a
      -- policy/constraint/default the database evaluates as the caller. Leaving
      -- it reachable changes nothing: it already only ever answers about the
      -- person asking. Revoking it would break reads and writes, not close a door.
      if v_has_auth then execute format('grant execute on function %s to authenticated', f.sig); end if;
      n_invoker := n_invoker + 1;
    else
      n_internal := n_internal + 1;                     -- reached only from inside another function
    end if;
  end loop;

  raise notice '339: % public, % client, % caller-evaluated, % internal (no grant), % trigger',
    n_public, n_client, n_invoker, n_internal, n_trigger;

  -- What this migration exists to guarantee.
  if v_has_anon and exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and has_function_privilege('anon', p.oid, 'execute')
       and not (p.proname = any(v_public))) then
    raise exception '339: a function outside the public allowlist is still callable by anon';
  end if;
  if v_has_auth and exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f' and p.proname = any(v_client)
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and not has_function_privilege('authenticated', p.oid, 'execute')) then
    raise exception '339: a function the application calls is no longer callable by staff';
  end if;
end $$;

-- A function added after this migration still inherits PostgreSQL's built-in
-- default, which grants EXECUTE to PUBLIC. That default cannot be withdrawn:
-- ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC reports
-- success and changes nothing, because a stored default ACL is applied on top
-- of the built-in one rather than in place of it (checked on PostgreSQL 14 and
-- 17: a function created afterwards still carries "=X/owner"). So every
-- migration that adds a function must say who may call it, exactly as 326, 336
-- and 337 do:
--
--     revoke all on function public.f(...) from public, anon;
--     grant execute on function public.f(...) to authenticated;   -- if staff call it
--
-- scripts/permissions/tests/function-grants.sql fails the moment one does not:
-- it asks the catalogue which functions anon can reach and compares that with
-- the five endpoints below, so a forgotten grant is caught by the test rather
-- than by a stranger with the anon key.

comment on schema public is
  'Application schema. Functions are not endpoints by default: since 339 no function is reachable with the anon key unless its migration grants it, and a privileged helper is granted to nobody and reached only from inside another SECURITY DEFINER function. New functions are callable by authenticated and by no one else until said otherwise.';

-- PostgREST decides what to expose per role from a cached view of the
-- catalogue. This migration changes nothing but grants, so without this the
-- API could keep answering from the reach it had before.
notify pgrst, 'reload schema';

notify pgrst, 'reload schema';
commit;
