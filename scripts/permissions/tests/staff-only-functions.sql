-- Staff data is for active staff (406, 407).
--
-- A signed-in login is not a member of staff: every affiliate signs in, anyone
-- could make a login at /affiliate/join, and a deactivated employee keeps their
-- password. Before 406 the database took every login for staff, and 48 server
-- functions behind the staff pages handed customers, health notes, purchases
-- and business figures to any of them. This test holds the line in two ways.
--
--   1. EVERY function a signed-in login may call is called as five logins
--      that are not staff (one with no profile, an affiliate, a deactivated
--      employee, a pending invitee and a cancelled invitee), three times: with
--      every argument null; with the fixture's own ids for the arguments whose
--      names say what they are (customer, invoice, store, survey and so on),
--      'SOFX' for text, a page of 50 and today's date; and with those ids
--      alone. Each call must be refused with SQLSTATE 42501, the answer of
--      require_active_staff() and of a revoked grant, unless the function is
--      named below, by its full signature, with the reason it may answer
--      otherwise:
--        * a SECURITY INVOKER function runs as the caller, under the table
--          rules, so it can do nothing the login could not do directly;
--        * the five signed-out endpoints and the affiliate portal;
--        * functions that answer only about the caller (the policy helpers);
--        * functions that refuse such a login with their own message, or that
--          return only rows of the caller's stores or role (the inventory of
--          9 Oct 2026 checked each one).
--      Whatever any function returns to these logins must hold none of the
--      fixture's customers, phones, emails, stores or products, and no call
--      may write a row (but the signed-out endpoints and the affiliate portal).
--      A function added without a check, or a new overload of a named one,
--      fails this test until it refuses.
--      Add require_active_staff() as its first statement (or revoke it, if no
--      page calls it), not its name to a list.
--   2. The functions each page calls answer each role that can open the page,
--      with real fixture rows: Owner, Admin, Manager, Inventory Manager, Staff
--      at one store, Staff at two stores; and refuse the roles the page leaves
--      out. The affiliate portal answers its affiliate, the public survey and
--      referral endpoints a signed-out visitor, and the server (the service
--      role, and no login at all) passes the checks. Then the tables, the
--      invoice PDF folder, approval requests, the profile rules, and a payment
--      recorded by Staff, which reaches the checks again through the payment
--      triggers, and what a deactivated employee may no longer do with their
--      own records.
--
-- It needs a database with production's schema and 406 and 407 applied: the
-- lists name production's functions by signature, so a database whose
-- functions differ (the shared local ones lag production) reports each
-- difference. That is why it is not part of npm run test:permissions; run it
-- with npm run test:permissions:staff-only once the integration database
-- carries production's schema.
-- Disposable database only; everything is rolled back. Fixture names carry
-- SOFX, phones +65914001xx, emails @sig.invalid; nothing real is read or printed.
\set ON_ERROR_STOP on
begin;

create temp table sof(k text primary key, id uuid not null);
create temp table sof_fail(n serial, msg text);
create temp table sof_tally(k text primary key, n int not null default 0);

create function pg_temp.sof_id(p text) returns uuid language sql stable as
  $f$ select id from sof where k = p $f$;

-- Run p_sql as one of the fixture's logins and say what happened:
--   'ok' and the result as text, or the SQLSTATE and the message.
-- p_who is a login key, 'anon' (the public key, signed out), 'service' (the
-- service role) or 'server' (no request at all: pg_cron, migrations).
create function pg_temp.sof_try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    if p_who = 'server' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
    elsif p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    elsif p_who = 'service' then
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.sof_id(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    perform set_config('energia.profile_privilege_change', '', true);
    execute p_sql into v_out;
    execute 'reset role';
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || chr(9) || v_msg;
  end;
end $f$;

create function pg_temp.sof_fail(p text) returns void language sql as
  $f$ insert into sof_fail(msg) values (p) $f$;

create function pg_temp.sof_count(p text) returns void language sql as
  $f$ insert into sof_tally(k, n) values (p, 1) on conflict (k) do update set n = sof_tally.n + 1 $f$;

-- Fixture data in an answer: the leak this test exists to catch.
create function pg_temp.sof_leaks(p text) returns boolean language sql immutable as
  $f$ select coalesce(p, '') ~* '(sofx|6591400|sig\.invalid)' $f$;

-- ── Fixture ──────────────────────────────────────────────────────────────────
do $$
declare
  k text; v uuid; st_a uuid; st_b uuid; wh uuid; c1 uuid; c2 uuid; ca uuid; aff uuid;
  prod uuid; s1 uuid; inv_a uuid; inv_b uuid; item_a uuid; cash uuid;
begin
  -- No request: the fixture is written as the server would.
  perform set_config('request.jwt.claims', '', true);

  foreach k in array array['owner','admin','manager','invman','staff1','staff2',
                           'inactive','pending','cancelled','nostaff','affiliate'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 'sofx-' || k || '@sig.invalid') returning id into v;
    insert into sof values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status, created_at, updated_at)
  select s.id, 'SOFX ' || s.k, 'sofx-' || s.k || '@sig.invalid', x.role::public.user_role, x.active, x.inv, now(), now()
    from sof s join (values ('owner','owner',true,null), ('admin','admin',true,null), ('manager','manager',true,null),
                            ('invman','inventory_manager',true,null), ('staff1','staff',true,null),
                            ('staff2','staff',true,'accepted'), ('inactive','staff',false,null),
                            ('pending','staff',false,'pending'), ('cancelled','staff',false,'cancelled'))
                    x(k, role, active, inv) on x.k = s.k;

  insert into public.stores(name, code, country_code) values ('SOFX Store A', 'SOFXA', 'SG') returning id into st_a;
  insert into public.stores(name, code, country_code) values ('SOFX Store B', 'SOFXB', 'SG') returning id into st_b;
  insert into public.warehouses(name, code) values ('SOFX Warehouse', 'SOFXW') returning id into wh;
  insert into sof values ('store_a', st_a), ('store_b', st_b), ('warehouse', wh);
  insert into public.user_store_assignments(user_id, store_id)
  select pg_temp.sof_id(x.k), x.st
    from (values ('manager', st_a), ('manager', st_b), ('invman', st_a), ('staff1', st_a),
                 ('staff2', st_a), ('staff2', st_b), ('inactive', st_a), ('pending', st_a),
                 ('cancelled', st_a)) x(k, st);

  insert into public.customers(full_name, phone, email) values ('SOFX Customer One', '+6591400101', 'sofx-c1@sig.invalid') returning id into c1;
  insert into public.customers(full_name, phone, email) values ('SOFX Customer Two', '+6591400102', 'sofx-c2@sig.invalid') returning id into c2;
  insert into public.customers(full_name, phone, email) values ('SOFX Affiliate', '+6591400103', 'sofx-ca@sig.invalid') returning id into ca;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at)
    values (ca, 'active', st_a, now()) returning id into aff;
  insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
    values (pg_temp.sof_id('affiliate'), ca, aff, 'claimed');
  update public.customers set referred_by = ca where id = c2;
  insert into sof values ('c1', c1), ('c2', c2), ('ca', ca), ('aff', aff);

  insert into public.products(name, sku, default_cost_price, supplier_name) values ('SOFX Product', 'SOFX-1', 10, 'SOFX Supplier') returning id into prod;
  insert into public.store_product_prices(store_id, product_id, selling_price) values (st_a, prod, 100), (st_b, prod, 100);
  insert into public.store_inventory(store_id, product_id, current_qty) values (st_a, prod, 5), (st_b, prod, 5);
  insert into public.payment_methods(name, is_active) values ('SOFX Cash', true) returning id into cash;
  insert into sof values ('product', prod), ('cash', cash);

  insert into public.health_surveys(survey_no, customer_id, full_name, phone, source, store_id, submitted_at)
    values ('SOFX-HS-1', c1, 'SOFX Customer One', '+6591400101', 'consultant', st_a, now()) returning id into s1;
  insert into public.consultant_notes(survey_id, customer_id, acidity_result, health_goals, created_by)
    values (s1, c1, 'green', 'SOFX goal', pg_temp.sof_id('owner'));
  insert into sof values ('survey', s1);

  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('SOFX-INV-A', st_a, c1, pg_temp.sof_id('owner'), 'unpaid', 100, 100, public.sg_today()) returning id into inv_a;
  insert into public.invoice_items(invoice_id, product_id, line_kind, quantity, unit_price, line_total)
    values (inv_a, prod, 'product', 1, 100, 100) returning id into item_a;
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('SOFX-INV-B', st_b, c2, pg_temp.sof_id('owner'), 'unpaid', 100, 100, public.sg_today()) returning id into inv_b;
  insert into sof values ('inv_a', inv_a), ('inv_b', inv_b), ('item_a', item_a);

  -- Own records: the deactivated employee's, and Staff's (X-5).
  insert into public.transfer_requests(transfer_type, dest_type, dest_id, status, requested_by)
    values ('warehouse_to_store', 'store', st_a, 'pending', pg_temp.sof_id('inactive')) returning id into v;
  insert into sof values ('treq', v);
  insert into public.transfer_requests(transfer_type, dest_type, dest_id, status, requested_by)
    values ('warehouse_to_store', 'store', st_a, 'pending', pg_temp.sof_id('staff1')) returning id into v;
  insert into sof values ('treq_staff1', v);
  insert into public.approval_requests(request_type, status, requested_by, payload)
    values ('adjustment', 'pending', pg_temp.sof_id('inactive'), '{}'), ('adjustment', 'pending', pg_temp.sof_id('staff1'), '{}');
  insert into public.staff_commissions(invoice_id, staff_id, store_id, invoice_total, share_ratio, rate, commission_amount)
    values (inv_a, pg_temp.sof_id('inactive'), st_a, 100, 1, 0.03, 3), (inv_a, pg_temp.sof_id('staff1'), st_a, 100, 1, 0.03, 3);
  insert into public.staff_commission_payouts(payout_month, staff_id, total_amount)
    values (date_trunc('month', now())::date, pg_temp.sof_id('inactive'), 3),
           (date_trunc('month', now())::date, pg_temp.sof_id('staff1'), 3);

  insert into storage.objects(bucket_id, name) values
    ('invoice-pdfs', st_a || '/invoice/SOFX-INV-A-fixture.pdf'),
    ('invoice-pdfs', st_b || '/invoice/SOFX-INV-B-fixture.pdf');
end $$;

-- ── 1. Every function, as logins that are not staff ─────────────────────────
-- Some functions talk (notices) when called; only the result matters here.
set local client_min_messages = warning;

-- Fixture data in an answer to a call made with the fixture's own ids and
-- 'SOFX' as text: the fixture's names, numbers, phones and emails, not merely
-- the text the call itself passed in.
create function pg_temp.sof_leaks_data(p text) returns boolean language sql immutable as
  $f$ select coalesce(p, '') ~* '(sofx (customer|affiliate|store|warehouse|product|supplier|cash|goal|owner|admin|manager|invman|staff|inactive|pending|cancelled|nostaff)|sofx-(inv|hs|1)|6591400|sig\.invalid)' $f$;

-- Rows written (or tried) in this transaction so far, in every real table.
create function pg_temp.sof_writes() returns bigint language sql volatile as
  $f$ select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0)::bigint from pg_stat_xact_all_tables
       where schemaname not in ('pg_catalog', 'information_schema') and schemaname !~ '^pg_(temp|toast)' $f$;

-- An argument for a call. Variant 1: null. Variant 2: the fixture's id for an
-- id whose name says what it is, 'SOFX' for text, a page of 50 from the
-- start, today's date. Variant 3: those ids, and null for everything else.
create function pg_temp.sof_arg(p_name text, p_type oid, p_variant int) returns text language plpgsql stable as $f$
declare n text := lower(coalesce(p_name, '')); t text := format_type(p_type, null); k text;
begin
  if p_variant = 1 then return 'null::' || t; end if;
  if t in ('uuid', 'uuid[]') then
    k := case
      when n ~ 'survey' then 'survey'
      when n ~ 'invoice|(^|_)doc' then 'inv_a'
      when n ~ 'warehouse' then 'warehouse'
      when n ~ 'store|location' then 'store_a'
      when n ~ 'product|sku' then 'product'
      when n ~ 'affiliate' then 'aff'
      when n ~ 'item|line' then 'item_a'
      when n ~ 'transfer|request' then 'treq'
      when n ~ 'user|staff|profile|owner|_by$' then 'staff1'
      else 'c1' end;
    return case when t = 'uuid' then quote_literal(pg_temp.sof_id(k)) || '::uuid'
                else 'array[' || quote_literal(pg_temp.sof_id(k)) || ']::uuid[]' end;
  end if;
  if p_variant = 3 then return 'null::' || t; end if;
  if t in ('text', 'character varying') then return '''SOFX''::' || t; end if;
  if t in ('integer', 'bigint', 'smallint') then
    return case when n ~ 'limit|size' then '50' when n ~ 'offset|page' then '0' else 'null' end || '::' || t;
  end if;
  if t = 'date' then return 'public.sg_today()'; end if;
  if t like 'timestamp%' then return 'now()::' || t; end if;
  return 'null::' || t;
end $f$;

do $$
declare
  -- Each list names functions by their full signature, so a new overload of a
  -- named function is not named: it must refuse like any new function.
  -- The five signed-out endpoints (339; function-grants.sql check 2).
  c_public constant text[] := array[
      'active_customer_source_options()', 'affiliate_referral_signup(text,text,text,text,text,text)',
      'public_affiliate_referral_info(text)', 'submit_health_survey(text,jsonb,jsonb,text)',
      'survey_link_info(text)'];
  -- The affiliate portal: the signed-in affiliate's own figures (each starts
  -- from current_affiliate_customer_id() and refuses anyone else).
  c_affiliate constant text[] := array[
      'affiliate_portal_campaign_progress()', 'affiliate_portal_dashboard()',
      'affiliate_portal_earnings()', 'affiliate_portal_me()', 'affiliate_portal_network()',
      'affiliate_portal_payouts()', 'affiliate_portal_purchases()', 'affiliate_portal_referral_info()',
      'complete_affiliate_onboarding(text,text,text,boolean)'];
  -- Answer only about the caller: the policy helpers and their kin. Rules on
  -- tables call several of them, so signed-in logins keep them
  -- (function-grants.sql check 4).
  c_caller constant text[] := array[
      'assignable_roles()', 'assignable_store_ids()', 'can_manage_warehouse_stock()',
      'can_view_customer_credit()', 'current_user_role()', 'invoice_date_recovery_access()',
      'is_manager_or_above()', 'is_owner_or_admin()', 'is_owner_or_manager()', 'my_assigned_store_id()',
      'my_assigned_stores()', 'staff_may_correct_invoice(uuid)', 'stock_history_global()',
      'stock_history_location(text,uuid)', 'stock_history_movement(uuid,uuid,uuid,uuid,uuid,uuid)',
      'stock_history_transfer(uuid)', 'user_admin_role()', 'user_has_store_access(uuid)'];
  -- Refuse a login that is not staff with their own message: their own role or
  -- store test, or a helper they call first (inventory of 9 Oct 2026).
  c_own constant text[] := array[
      'activate_purchased_therapy(uuid,date,text,text,text,boolean)', 'activate_rental(uuid)',
      'add_consultant_note(uuid,uuid,text,text,text,text,jsonb)',
      'add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)',
      'add_promotion_item(uuid,promotion_item_type,uuid,uuid,uuid,text,integer,text,uuid,uuid)',
      'add_survey_attachment(uuid,text,text,text,integer,text)',
      'adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)',
      'affiliate_admin_directory()', 'affiliate_pending_claims()', 'affiliate_rejected_claims()',
      'apply_commission_rebase_all()', 'apply_line_foc(uuid,integer,uuid,text)',
      'archive_therapy_service(uuid,text)', 'backfill_legacy_qualification(date,date,uuid)',
      'cancel_invoice_recorded(uuid,text,uuid)', 'cancel_rental(uuid,boolean,text)',
      'cancel_special_sale(uuid,boolean,text)', 'change_customer_phone(uuid,text,text)',
      'choose_therapy_benefit(uuid,text,uuid,text)',
      'claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)',
      'clear_invoice_event(uuid)', 'clear_therapy_voucher_definition(uuid)',
      'commission_instalment_backfill(boolean,date,numeric,numeric)', 'confirm_foc_invoice(uuid,text)',
      'confirm_tiktok_batch(uuid,jsonb,boolean,text)', 'confirm_tiktok_settlement_batch(uuid,jsonb)',
      'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
      'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
      'correct_tiktok_row(uuid,integer,text)', 'create_exchange_with_details(text,jsonb)',
      'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
      'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
      'create_rental(uuid,uuid,uuid,integer,special_rate_type,integer,date,date,text)',
      'create_special_sale(uuid,uuid,uuid,integer,uuid,text,text)',
      'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text)',
      'create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text)',
      'create_staff_commission_payout(uuid,date,uuid,text,text)',
      'create_staff_transfer_request(jsonb,text,uuid)',
      'create_transfer_request(text,text,uuid,text,uuid,jsonb,text)', 'customer_credit_balances(uuid)',
      'customer_credit_statement(uuid,date,date)', 'delete_affiliate_account_claim(uuid)',
      'delete_customer(uuid,text,text)', 'delete_invoice(uuid)', 'delete_survey_attachment(uuid)',
      'delete_therapy_closure_date(uuid,text)', 'delete_tiktok_batch(uuid)', 'delete_tiktok_row(uuid)',
      'edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)',
      -- 415: event_check_in (now five arguments) and event_set_guest_cancelled
      -- start with require_active_staff(), so they are in the strict group.
      'event_delete(uuid,text)', 'event_guest_list(uuid)',
      'event_invoices(uuid)', 'event_save(jsonb)', 'event_save_guest(jsonb)',
      'event_ticket_options_for_sale(uuid,date)',
      'exchange_original_context(uuid)', 'exchange_payment_position(uuid)',
      'fulfil_special_doc(text,uuid,uuid,text)', 'include_tiktok_settlement_rows(uuid[],text)',
      'invoice_action_plan(uuid,text,jsonb)', 'invoice_action_request_detail(uuid)',
      'invoice_benefit_review_options(uuid)', 'invoice_event_guests(uuid)',
      'invoice_financial_position(uuid)', 'invoice_goods_status(uuid)', 'invoice_refund_options(uuid)',
      'invoice_reopen_preview(uuid)', 'lend_stock(text,uuid,jsonb,date,uuid,text,text,uuid)',
      'list_deleted_customers(text,integer)', 'pay_rental(uuid,uuid,text)',
      'preview_invoice_correction(uuid,jsonb)', 'purchased_therapy_unit_state(uuid)',
      'reactivate_affiliate(uuid)', 'reassign_customer_referrer(uuid,uuid,text)',
      'receive_returned_rental(uuid,uuid,text,text,uuid)', 'receive_transfer(uuid,jsonb,text,boolean)',
      'record_invoice_benefit_values(uuid,jsonb,text)', 'record_invoice_settlement(uuid,jsonb,uuid)',
      'record_stock_use(text,uuid,uuid,integer,text,text)',
      'record_stock_uses(text,uuid,jsonb,text,text,uuid)', 'refresh_tiktok_staging(uuid)',
      'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
      'refund_purchased_therapy(uuid,text)', 'reject_affiliate_account_claim(uuid,text)',
      'reject_transfer(uuid,text)', 'remove_line_foc(uuid,text)', 'reopen_invoice(uuid,text,uuid)',
      'reorder_customer_source_options(jsonb)', 'report_events(date,date)',
      'report_sales_by_service_staff(date,date,uuid)',
      'request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)',
      'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)',
      'reschedule_purchased_therapy(uuid,date,text)', 'resolve_inventory_adjustment(uuid,boolean,text)',
      'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
      'resolve_transfer_discrepancy(uuid,jsonb,text)', 'restore_customer_with_phone(uuid,text,text)',
      'return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)',
      'review_and_dispatch_transfer(uuid,jsonb,text)', 'review_health_survey(uuid,text,text,text,text)',
      'save_therapy_package(uuid,text,text,text,boolean,text,integer,integer,uuid,uuid[],uuid[])',
      'set_catalogue_reward(text,uuid,boolean)', 'set_catalogue_sku(text,uuid,text)',
      'set_commission_rates(numeric,numeric,numeric,numeric)',
      'set_customer_source(uuid,uuid,text,text)', 'set_customer_source_option_active(uuid,boolean)',
      'set_invoice_affiliate(uuid,uuid)', 'set_invoice_event(uuid,uuid,text)',
      'set_invoice_fulfilment_warehouse(uuid,uuid)', 'set_invoice_instalment_label(uuid,uuid,integer)',
      'set_low_stock_threshold(location_type,uuid,uuid,integer)', 'set_product_important(uuid,boolean)',
      'set_product_prices(uuid,uuid,numeric,numeric,text)',
      'set_promotion_price_all_stores(uuid,numeric,boolean)',
      'set_promotion_prices(uuid,uuid,numeric,numeric,boolean)', 'set_staff_commission_rate(numeric)',
      'set_therapy_calendar_coverage(text,integer,text,boolean,text,text,text)',
      'set_therapy_service_store(uuid,uuid,boolean,numeric)',
      'set_tiktok_status_mapping_active(uuid,boolean)',
      'set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)',
      'set_voucher_price_all_stores(uuid,numeric,boolean)',
      'set_voucher_prices(uuid,uuid,numeric,numeric,boolean)',
      'special_stock_in(uuid,uuid,integer,text)', 'stage_tiktok_orders(uuid,text,text,jsonb)',
      'stage_tiktok_settlement(uuid,text,text,jsonb)',
      'stage_tiktok_settlement_file(uuid,text,text,jsonb,jsonb)',
      'stock_history_options(text,text,integer)',
      'stock_history_page(jsonb,integer,integer,timestamp with time zone)',
      'stock_history_table(jsonb,integer,integer,timestamp with time zone)',
      'stock_loans_at(text,uuid,boolean)', 'stock_transfer_details(uuid)',
      'suspend_affiliate(uuid,text)', 'therapy_apply_recalculation(text,uuid,boolean,text)',
      'therapy_map_entitlement_tier(uuid,text,text)', 'tiktok_bank_payouts(date,date)',
      'tiktok_batch_balance_counts(uuid)', 'tiktok_left_out_settlement(uuid,date,date)',
      'tiktok_xero_payouts(integer,integer)',
      'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
      'update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text)',
      'update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)',
      'update_survey_particulars(uuid,text,text,text,text,date,text,text,text,uuid,text,boolean,boolean,boolean,boolean,text,jsonb)',
      'upsert_credit_package(uuid,text,numeric,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,numeric,text,uuid[],uuid[],boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,numeric)',
      'upsert_customer_source_option(text,integer,boolean,boolean,uuid)',
      'upsert_legacy_rule(uuid,uuid,text,numeric,text,integer,integer,integer,boolean,date,text)',
      'upsert_premium_bundle(uuid,text,numeric,numeric,numeric,integer,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,text,uuid[],uuid[])',
      'upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)',
      'upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)',
      'upsert_therapy_package_choice(uuid,text,text,text,boolean,integer,integer,uuid[],uuid[])',
      'upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)',
      'upsert_therapy_voucher_definition(uuid,jsonb,text,integer,text,integer,numeric,text)',
      'upsert_tiktok_sku_alias(uuid,text,text,uuid)',
      'upsert_tiktok_status_mapping(text,text,boolean,boolean)',
      'upsert_unlimited_therapy_package(uuid,text,integer,text,boolean,text,integer,uuid)',
      'verify_invoice_credit_sale_sources(uuid,uuid,boolean,text)',
      'voucher_stock_in(uuid,uuid,integer,text)',
      'warehouse_stock_in(uuid,uuid,integer,text,text,text)', 'web_order_apply_names(uuid)',
      'web_order_channel_set_mode(text,text)', 'web_order_dismiss(uuid,text,boolean)',
      'web_order_link_invoice(uuid,text)', 'web_order_link_preview(uuid,text)',
      'web_order_resolve(uuid,uuid,boolean)', 'web_orders_list(uuid)'];
  -- Return only rows of the caller's stores or role, so nothing to a login that
  -- is not staff: they filter on current_user_role(), user_has_store_access(),
  -- stock_history_*(), user_admin_role() and the like (inventory of 9 Oct 2026).
  c_filtered constant text[] := array[
      'credit_lot_allows_category(uuid,text)', 'credit_lot_policy_for(uuid)',
      'customer_stock_loans(uuid)', 'daily_payments_by_method(date,date,uuid)',
      'dashboard_sales(text,date,date,uuid)', 'dashboard_sales_by_store(text,date,date)',
      'events_list()', 'health_survey_detail(uuid)',
      'invite_user_begin(text,text,text,user_role,text,text,text,uuid[])',
      'invite_user_cancel(uuid,text)', 'invite_user_prepare_resend(uuid)',
      'invoice_credit_reward_entitlements(uuid,uuid)', 'invoice_display_names(uuid)',
      'invoice_effective_affiliate(uuid)', 'invoice_events(uuid[])', 'invoice_list_goods_out(uuid[])',
      'invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)',
      'invoice_rentals_awaiting_return(uuid)', 'invoice_sales_ledger()',
      'invoice_stock_component_evidence(uuid)', 'payment_methods_in_range(date,date,uuid)',
      'purchased_therapy_units(uuid,uuid,boolean)', 'referrer_list()', 'report_affiliates()',
      'report_discounts()', 'report_exchange_invoices(uuid,date,date)',
      'report_foc_lines(date,date,uuid)', 'report_foc_summary(date,date,uuid)', 'report_pricing()',
      'report_sales_reconciliation(uuid,date,date)', 'report_therapy()',
      'report_tiktok_imports(uuid,date,date)', 'report_tiktok_orders_by_status(uuid)',
      'report_tiktok_qty_sold(uuid,date,date)', 'report_tiktok_recon_exceptions(uuid)',
      'report_tiktok_settlement(uuid,date,date)', 'report_tiktok_settlement_by_store(date,date)',
      'report_tiktok_settlement_daily(uuid,date,date)',
      'report_tiktok_settlement_summary(uuid,date,date)', 'report_tiktok_unmatched_skus(uuid)',
      'report_transfer_discrepancies()', 'report_transfer_receipts(date,date)',
      'report_transfers_overdue(integer)', 'search_customers(text,text,integer,integer,text,date,date)',
      'therapy_closure_impact(date,text,text)', 'therapy_recalculation_preview(text,uuid)',
      'therapy_reward_mapping_preview()', 'tiktok_settlement_totals(integer,integer,uuid)',
      'transfer_product_sourcing(uuid,uuid)', 'transfer_receipt_alerts()',
      'transfer_request_sourcing(uuid)', 'transfer_revisions(uuid)', 'user_admin_list()'];
  c_logins constant text[] := array['nostaff', 'affiliate', 'inactive', 'pending', 'cancelled'];
  r record; v_args text; v_sql text; v_out text; v_login text; v_state text; v_named text[];
  v_allowed boolean; v_variant int; v_w bigint; v_wrote boolean;
  n_fn int := 0; n_refused int := 0; n_named int := 0; n_invoker int := 0; n_calls int := 0;
begin
  v_named := c_public || c_affiliate || c_caller || c_own || c_filtered;
  if (select count(*) from unnest(v_named) x) <> (select count(distinct x) from unnest(v_named) x) then
    perform pg_temp.sof_fail('1: a function is named in two lists');
  end if;
  -- A name that no longer matches a function is a list out of date.
  perform pg_temp.sof_fail('1: named but not a function signed-in logins can call: ' || x)
     from unnest(v_named) x
    where to_regprocedure('public.' || x) is null
       or not has_function_privilege('authenticated', to_regprocedure('public.' || x), 'execute');
  for r in
    select p.oid, p.proname, p.oid::regprocedure::text as sig, p.prosecdef,
           p.prorettype = 'void'::regtype as is_void,
           coalesce(p.proallargtypes, p.proargtypes::oid[]) as types,
           p.proargmodes as modes, p.proargnames as names
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and has_function_privilege('authenticated', p.oid, 'execute')
     order by 3
  loop
    n_fn := n_fn + 1;
    -- A SECURITY INVOKER function runs as the caller, under the table rules.
    v_allowed := not r.prosecdef or r.sig = any (v_named);
    if not r.prosecdef then n_invoker := n_invoker + 1;
    elsif v_allowed then n_named := n_named + 1;
    else n_refused := n_refused + 1; end if;
    for v_variant in 1 .. 3 loop
      select string_agg(case when coalesce(r.modes[i], 'i') = 'v' then 'variadic null::' || format_type(t, null)
                             else pg_temp.sof_arg(r.names[i], t, v_variant) end, ', ' order by i)
        into v_args
        from unnest(r.types) with ordinality a(t, i)
       where coalesce(r.modes[i], 'i') in ('i', 'b', 'v');
      v_sql := case when r.is_void
        then format('select count(*)::text || chr(9) from (select public.%I(%s)) x', r.proname, coalesce(v_args, ''))
        else format('select count(*)::text || chr(9) || coalesce(string_agg(to_jsonb(x)::text, '' | ''), '''') '
                    || 'from public.%I(%s) x', r.proname, coalesce(v_args, '')) end;
      foreach v_login in array c_logins loop
        v_w := pg_temp.sof_writes();
        v_out := pg_temp.sof_try(v_login, v_sql);
        v_wrote := pg_temp.sof_writes() <> v_w;
        v_state := split_part(v_out, chr(9), 1);
        n_calls := n_calls + 1;
        if not v_allowed and v_state <> '42501' then
          perform pg_temp.sof_fail(format('1: %s answered %s (not staff) with %s, not 42501 (arguments %s)',
                                          r.sig, v_login, v_state, v_variant));
        elsif v_state = 'ok' and (case when v_variant = 1 then pg_temp.sof_leaks(v_out) else pg_temp.sof_leaks_data(v_out) end)
              and not (v_login = 'affiliate' and r.sig = any (c_affiliate)) then
          perform pg_temp.sof_fail(format('1: %s returned fixture data to %s (not staff) (arguments %s)',
                                          r.sig, v_login, v_variant));
        elsif v_state = 'ok' and v_wrote and not (r.sig = any (c_public || c_affiliate)) then
          perform pg_temp.sof_fail(format('1: %s wrote rows as %s (not staff) (arguments %s)',
                                          r.sig, v_login, v_variant));
        end if;
      end loop;
    end loop;
  end loop;
  insert into sof_tally values ('1 functions called', n_fn), ('1 refused with 42501', n_refused),
                               ('1 named with a reason', n_named), ('1 security invoker', n_invoker),
                               ('1 calls', n_calls);
  -- Every function 406 guards, and its new one, are in the strict group.
  if exists (select 1 from unnest(v_named) s
              where split_part(s, '(', 1) = any (array['customer_survey_overview', 'consultant_notes_for',
               'customer_overview', 'customer_profile_stats', 'customer_purchase_timeline', 'therapy_customer_summary',
               'therapy_customer_detail', 'active_affiliates_for_picker', 'affiliate_legacy_day_summary',
               'store_commission_staff', 'special_docs_awaiting_fulfilment', 'upsert_consultant_survey',
               'add_customer_remark', 'record_document_send', 'pay_special_with_credit',
               'record_document_printed', 'dashboard_summary', 'resolve_tiktok_physical_return',
               'cancel_transfer_request', 'return_stock_loan'])) then
    perform pg_temp.sof_fail('1: a function 406 guards is named in an allow list');
  end if;
  -- The server-only functions 406 revoked stay revoked.
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('write_audit', 'auth_email_user_state', 'auth_email_reserve',
                                'auth_email_record_outcome', 'commission_outside_rebase_scope',
                                'commission_totals_reconciliation', 'preview_commission_rebase_effect',
                                'validate_bundle_voucher_selection', 'require_active_staff',
                                'require_store_access')
              and has_function_privilege('authenticated', p.oid, 'execute')) then
    perform pg_temp.sof_fail('1: a function 406 made server-only is callable by signed-in logins again');
  end if;
end $$;

-- @key@ in a statement is the fixture's id for that key.
create function pg_temp.sof_sql(p text) returns text language plpgsql stable as $f$
declare r record;
begin
  for r in select k, id from sof loop
    p := replace(p, '@' || r.k || '@', quote_literal(r.id) || '::uuid');
  end loop;
  return p;
end $f$;

-- ── 2. The pages' functions, as each role ───────────────────────────────────
-- Who may: all = every staff role; a = staff of store A (every staff role:
-- Admins and Owners reach every store, the rest work there); b = staff of store
-- B (Owner, Admin, Manager, Staff at two stores); om = Owner and Manager (the
-- pages' isOwnerOrManager); mup = Owner, Admin, Manager (isManagerOrAbove);
-- notinv = every staff role but Inventory Manager. Every other login, the
-- affiliate, the login with no profile and the deactivated employee included,
-- must be refused with 42501; a trailing ~ marks a function from before 406
-- that refuses them its own way, and they must get none of the fixture's rows
-- from it. ok: the call must also succeed outright (not just get past the
-- check); data: what it returns to those who may must hold the fixture's rows,
-- so the check did not cost them their data.
do $$
declare
  c_staff constant text[] := array['owner', 'admin', 'manager', 'invman', 'staff1', 'staff2'];
  c_everyone constant text[] := c_staff || array['affiliate', 'nostaff', 'inactive'];
  r record; v_who text; v_may text[]; v_out text; v_state text; n int := 0;
begin
  for r in select * from (values
    -- Dashboard (every role)
    ('dashboard alerts',       'all',    true,  false, 'select public.dashboard_alerts_summary()::text'),
    ('negative stock',         'all',    true,  false, 'select count(*)::text from public.tiktok_negative_stock_alerts()'),
    ('top sources',            'all',    true,  false, 'select count(*)::text from public.report_customer_sources(null, null)'),
    ('credit by store',        'all',    true,  false, 'select count(*)::text from public.dashboard_credit_by_store(''day'', null, null)'),
    ('credit spend',           'all',    true,  false, 'select public.dashboard_credit_spend(''day'', null, null, null)::text'),
    ('transfer alerts',        'all~',   true,  false, 'select public.transfer_receipt_alerts()::text'),
    ('summary cards',          'mup',    true,  false, 'select public.dashboard_summary()::text'),
    -- Customers
    ('customer view',          'all',    true,  true,  'select public.customer_overview(@c1@)::text || (select full_name from public.customers where id = @c1@)'),
    ('customer search',        'all~',   true,  true,  'select string_agg(to_jsonb(x)::text, '','') from public.search_customers(''SOFX'', null, 25, 0, null, null, null) x'),
    ('profile figures',        'om',     true,  false, 'select public.customer_profile_stats(@c1@)::text'),
    ('purchase history',       'om',     true,  true,  'select public.customer_purchase_timeline(@c1@)::text'),
    -- Surveys
    ('survey list',            'all',    true,  true,  'select string_agg(to_jsonb(x)::text, '','') from public.customer_survey_overview(null, ''all'', 50, 0) x'),
    ('consultant notes',       'notinv', true,  true,  'select string_agg(to_jsonb(x)::text, '','') from public.consultant_notes_for(@survey@, null) x'),
    ('open a survey',          'notinv', true,  false, 'select public.upsert_consultant_survey(@c1@)::text'),
    ('start a survey',         'notinv', true,  false, 'select public.upsert_consultant_survey(@c2@)::text'),
    ('add a remark',           'om',     true,  false, 'select public.add_customer_remark(@c1@, ''SOFX remark'', ''consultation'', @survey@)::text'),
    -- Invoices: the invoice's store
    ('bill-to, store A',       'a',      true,  true,  'select public.invoice_bill_to_source(@inv_a@) || (select invoice_no from public.invoices where id = @inv_a@)'),
    ('bill-to, store B',       'b',      true,  false, 'select public.invoice_bill_to_source(@inv_b@)'),
    ('revisions',              'a',      true,  false, 'select count(*)::text from public.invoice_revision_history(@inv_a@)'),
    ('therapy summary',        'a',      true,  false, 'select public.invoice_therapy_summary(@inv_a@)::text'),
    ('therapy summary, B',     'b',      true,  false, 'select public.invoice_therapy_summary(@inv_b@)::text'),
    ('transferable benefits',  'a',      true,  false, 'select count(*)::text from public.invoice_transferable_benefits(@inv_a@)'),
    ('legacy entitlements',    'a',      true,  false, 'select count(*)::text from public.invoice_legacy_entitlements(@inv_a@)'),
    ('exchange details',       'a',      true,  false, 'select public.exchange_invoice_details(@inv_a@)::text'),
    ('qualification, A',       'a',      true,  false, 'select public.legacy_qualification_diagnose(@c1@, @store_a@, null)::text'),
    ('qualification, B',       'b',      true,  false, 'select public.legacy_qualification_diagnose(@c2@, @store_b@, null)::text'),
    ('print, A',               'a',      true,  false, 'select public.record_document_printed(''invoice'', @inv_a@)::text'),
    ('print, B',               'b',      true,  false, 'select public.record_document_printed(''invoice'', @inv_b@)::text'),
    ('send log',               'all',    true,  false, 'select public.record_document_send(''invoice'', ''SOFX-INV-A'', ''whatsapp'', @inv_a@, @c1@, ''+6591400101'', null, ''sent'', null)::text'),
    ('affiliate picker',       'all',    true,  true,  'select string_agg(to_jsonb(x)::text, '','') from public.active_affiliates_for_picker() x'),
    ('FOC reasons',            'all',    true,  false, 'select count(*)::text from public.active_foc_reasons()'),
    ('credit packages',        'all',    true,  false, 'select count(*)::text from public.credit_packages_for_store(@store_a@, null)'),
    ('premium bundles',        'all',    true,  false, 'select count(*)::text from public.premium_bundles_for_store(@store_a@, null)'),
    ('reward vouchers',        'all',    true,  false, 'select count(*)::text from public.legacy_reward_voucher_options(@store_a@)'),
    ('package preview',        'all',    true,  false, 'select public.credit_package_benefit_preview(null, @store_a@)::text'),
    ('bundle preview',         'all',    true,  false, 'select public.premium_bundle_benefit_preview(null, @store_a@)::text'),
    ('financial position',     'a~',     true,  false, 'select public.invoice_financial_position(@inv_a@)::text'),
    -- Exchanges
    ('service staff picker',   'all',    true,  true,  'select string_agg(to_jsonb(x)::text, '','') from public.store_commission_staff(@store_a@) x'),
    ('exchange eligibility',   'all',    true,  false, 'select public.exchange_ineligibility_reason(@inv_a@)'),
    ('bundle components',      'all',    true,  false, 'select count(*)::text from public.bundle_line_components(@item_a@)'),
    ('promotion total',        'all',    true,  false, 'select public.promotion_original_total(null, @store_a@)::text'),
    -- Therapy
    ('therapy customers',      'all',    true,  false, 'select count(*)::text from public.therapy_customer_summary(null, 50, 0, false)'),
    ('therapy customer',       'all',    true,  true,  'select public.therapy_customer_detail(@c1@)::text'),
    ('qualification setup',    'all',    true,  false, 'select public.legacy_setup_status()::text'),
    ('day summary',            'om',     true,  false, 'select count(*)::text from public.affiliate_legacy_day_summary(null)'),
    ('spending rules',         'all',    true,  false, 'select public.credit_package_effective_rules(null)::text'),
    ('reward options',         'all',    true,  false, 'select count(*)::text from public.legacy_reward_options(gen_random_uuid())'),
    ('reward diagnostic',      'all',    true,  false, 'select public.legacy_reward_options_diagnostic(gen_random_uuid())::text'),
    ('voucher state',          'all',    false, false, 'select public.entitlement_voucher_state(gen_random_uuid())::text'),
    ('claim vouchers',         'all',    false, false, 'select public.claim_entitlement_vouchers(gen_random_uuid(), ''[]'', null)::text'),
    ('claim legacy therapy',   'all',    false, false, 'select public.claim_legacy_therapy(gen_random_uuid(), null, null, ''[]'', null, null)::text'),
    -- Therapy Services, Special, TikTok
    ('service catalogue',      'mup',    true,  false, 'select count(*)::text from public.therapy_service_catalogue(null, false)'),
    ('special queue',          'om',     true,  false, 'select count(*)::text from public.special_docs_awaiting_fulfilment()'),
    ('special products',       'om',     true,  true,  'select string_agg(to_jsonb(x)::text, '','') from public.products_available_as_special() x'),
    ('special availability',   'om',     true,  false, 'select count(*)::text from public.special_product_availability(null)'),
    ('wallet payment (S$0)',   'om',     true,  false, 'select public.pay_special_with_credit(''special_sale'', null, @c1@, 0, @store_a@)::text'),
    ('physical return',        'all',    false, false, 'select public.resolve_tiktok_physical_return(gen_random_uuid(), false, null, null)::text'),
    -- Commissions (414): Mark as settled and its Void, Owners and Managers (no
    -- deduction and no settlement in the fixture, so each answers its own
    -- refusal, never 42501, to those who may)
    ('mark as settled',        'om',     false, false, 'select public.record_affiliate_deduction_settlement(@c1@, 1, current_date, ''written_off'', ''SOFX'', gen_random_uuid())::text'),
    ('void a settlement',      'om',     false, false, 'select public.void_affiliate_deduction_settlement(gen_random_uuid(), ''SOFX'', gen_random_uuid())::text'),
    -- Transfers and stock loans (the person's own records, X-5)
    ('cancel a transfer',      'all',    false, false, 'select public.cancel_transfer_request(gen_random_uuid())::text'),
    ('take back a loan',       'all',    false, false, 'select public.return_stock_loan(gen_random_uuid(), ''[]'', null, null)::text'),
    ('default store',          'all~',   true,  false, 'select coalesce(public.my_assigned_store_id()::text, '''')')
  ) x(label, who, must_ok, shows_data, sql)
  loop
    v_may := case rtrim(r.who, '~')
      when 'all' then c_staff
      when 'a' then c_staff
      when 'b' then array['owner', 'admin', 'manager', 'staff2']
      when 'om' then array['owner', 'manager']
      when 'mup' then array['owner', 'admin', 'manager']
      when 'notinv' then array['owner', 'admin', 'manager', 'staff1', 'staff2'] end;
    foreach v_who in array c_everyone loop
      v_out := pg_temp.sof_try(v_who, pg_temp.sof_sql(r.sql));
      v_state := split_part(v_out, chr(9), 1);
      n := n + 1;
      if v_who = any (v_may) then
        if v_state = '42501' then
          perform pg_temp.sof_fail(format('2: %s refused %s, who may (%s)', r.label, v_who, split_part(v_out, chr(9), 2)));
        elsif r.must_ok and v_state <> 'ok' then
          perform pg_temp.sof_fail(format('2: %s failed for %s: %s %s', r.label, v_who, v_state, split_part(v_out, chr(9), 2)));
        elsif r.shows_data and not pg_temp.sof_leaks(v_out) then
          perform pg_temp.sof_fail(format('2: %s showed %s none of the fixture''s rows', r.label, v_who));
        end if;
      elsif right(r.who, 1) = '~' then
        if v_state = 'ok' and pg_temp.sof_leaks(v_out) then
          perform pg_temp.sof_fail(format('2: %s gave %s (not staff) the fixture''s rows', r.label, v_who));
        end if;
      elsif v_state <> '42501' then
        perform pg_temp.sof_fail(format('2: %s answered %s with %s, not 42501', r.label, v_who, v_state));
      end if;
    end loop;
  end loop;
  insert into sof_tally values ('2 page calls', n);

  -- The consultant's findings: an Owner or Manager only.
  v_out := pg_temp.sof_try('staff1', pg_temp.sof_sql('select public.upsert_consultant_survey(@c1@, ''SOFX finding'')::text'));
  if split_part(v_out, chr(9), 1) <> '42501' then
    perform pg_temp.sof_fail('2: Staff wrote the consultant''s findings');
  end if;
  v_out := pg_temp.sof_try('manager', pg_temp.sof_sql('select public.upsert_consultant_survey(@c1@, ''SOFX finding'')::text'));
  if split_part(v_out, chr(9), 1) <> 'ok' then
    perform pg_temp.sof_fail('2: a Manager could not write the consultant''s findings: ' || v_out);
  end if;
  -- A remark's survey must be the customer's.
  v_out := pg_temp.sof_try('owner', pg_temp.sof_sql('select public.add_customer_remark(@c2@, ''SOFX'', ''consultation'', @survey@)::text'));
  if split_part(v_out, chr(9), 1) = 'ok' then
    perform pg_temp.sof_fail('2: a remark was filed under another customer''s survey');
  end if;
  -- consultant_notes_for never lists every note.
  v_out := pg_temp.sof_try('owner', 'select count(*)::text from public.consultant_notes_for(null, null)');
  if v_out <> 'ok' || chr(9) || '0' then
    perform pg_temp.sof_fail('2: consultant_notes_for(null, null) still lists notes: ' || v_out);
  end if;
  -- A page of the survey list is at most 200 rows.
  if position('least(greatest(coalesce(p_limit,50),1), 200)' in
              pg_get_functiondef('public.customer_survey_overview(text,text,integer,integer)'::regprocedure)) = 0 then
    perform pg_temp.sof_fail('2: customer_survey_overview has no page cap');
  end if;
  -- The print audit row is the printed invoice's, written as the person.
  if not exists (select 1 from public.audit_logs a where a.record_id = pg_temp.sof_id('inv_a')
                  and a.action = 'invoice_printed' and a.changed_by = pg_temp.sof_id('staff1')
                  and a.new_data ->> 'invoice_no' = 'SOFX-INV-A') then
    perform pg_temp.sof_fail('2: record_document_printed left no audit row');
  end if;
  if split_part(pg_temp.sof_try('staff1', pg_temp.sof_sql('select public.record_document_printed(''receipt'', @inv_a@)::text')), chr(9), 1) <> '22023' then
    perform pg_temp.sof_fail('2: record_document_printed took a kind it does not know');
  end if;
end $$;

-- ── 3. The affiliate portal, the signed-out pages and the server ────────────
do $$
declare r record; v_out text; v_state text;
begin
  for r in select * from (values
    ('affiliate', 'select public.affiliate_portal_me()::text'),
    ('affiliate', 'select public.affiliate_portal_dashboard()::text'),
    ('affiliate', 'select public.affiliate_portal_network()::text'),
    ('affiliate', 'select public.affiliate_portal_earnings()::text'),
    ('affiliate', 'select public.affiliate_portal_payouts()::text'),
    ('affiliate', 'select public.affiliate_portal_referral_info()::text'),
    ('affiliate', 'select public.affiliate_portal_campaign_progress()::text'),
    ('anon',      'select public.survey_link_info(''sofx-no-such-link'')::text'),
    ('anon',      'select count(*)::text from public.active_customer_source_options()'),
    ('anon',      'select public.public_affiliate_referral_info(''SOFX-NO-CODE'')::text'),
    ('anon',      'select count(*)::text from public.health_symptom_options'),
    -- The server: website orders and Edge Functions (service role), pg_cron and
    -- migrations (no request), which reach these through payments and orders.
    ('service',   'select count(*)::text from public.credit_packages_for_store(@store_a@, null)'),
    ('service',   'select count(*)::text from public.premium_bundles_for_store(@store_a@, null)'),
    ('service',   'select count(*)::text from public.store_commission_staff(@store_a@)'),
    ('service',   'select public.credit_package_effective_rules(null)::text'),
    ('service',   'select public.invoice_bill_to_source(@inv_b@)'),
    ('server',    'select count(*)::text from public.store_commission_staff(@store_a@)'),
    ('server',    'select public.credit_package_effective_rules(null)::text'),
    ('server',    'select public.dashboard_summary()::text')
  ) x(who, sql)
  loop
    v_out := pg_temp.sof_try(r.who, pg_temp.sof_sql(r.sql));
    v_state := split_part(v_out, chr(9), 1);
    if v_state <> 'ok' then
      perform pg_temp.sof_fail(format('3: %s failed for %s: %s', r.sql, r.who, v_out));
    end if;
  end loop;
  -- The affiliate sees its own account.
  if not pg_temp.sof_leaks(pg_temp.sof_try('affiliate', 'select public.affiliate_portal_me()::text')) then
    perform pg_temp.sof_fail('3: the affiliate portal did not show the affiliate its own account');
  end if;
  -- A signed-out visitor's bad link is refused by the survey itself, not 42501.
  v_out := pg_temp.sof_try('anon', 'select public.submit_health_survey(''sofx-no-such-link'', ''{}'', ''[]'', null)::text');
  if split_part(v_out, chr(9), 1) = '42501' then
    perform pg_temp.sof_fail('3: the public survey was refused as a permission problem: ' || v_out);
  end if;
end $$;

-- ── 4. Tables (407): staff read them, nobody else ───────────────────────────
do $$
declare
  c_tables constant text[] := array[
    'app_settings', 'brands', 'categories', 'credit_package_spending_rules', 'credit_package_split_allocations',
    'credit_package_split_groups', 'credit_package_stores', 'credit_package_vouchers', 'credit_packages',
    'foc_reasons', 'payment_methods', 'premium_bundle_split_allocations', 'premium_bundle_split_groups',
    'premium_bundle_stores', 'premium_bundle_vouchers', 'premium_bundles', 'product_categories',
    'product_suppliers', 'products', 'promotion_choice_groups', 'promotion_choice_options', 'promotion_items',
    'promotion_store_prices', 'promotions', 'special_product_stock', 'special_products', 'store_product_prices',
    'stores', 'suppliers', 'therapy_calendar_coverage', 'therapy_closure_dates', 'therapy_holiday_countries',
    'therapy_package_rules', 'therapy_package_services', 'therapy_package_vouchers', 'therapy_service_stores',
    'therapy_services', 'therapy_voucher_component_services', 'therapy_voucher_components',
    'therapy_voucher_definitions', 'unlimited_therapy_packages', 'unlimited_therapy_store_prices',
    'voucher_redemptions', 'voucher_store_prices', 'voucher_store_stock', 'vouchers', 'warehouses'];
  -- Tables the fixture fills, so staff must see at least one row.
  c_filled constant text[] := array['products', 'stores', 'store_product_prices', 'payment_methods', 'warehouses'];
  t text; v_who text; v_out text; n int := 0;
begin
  foreach t in array c_tables loop
    foreach v_who in array array['owner', 'admin', 'manager', 'invman', 'staff1', 'staff2',
                                 'affiliate', 'nostaff', 'inactive', 'pending', 'anon'] loop
      v_out := pg_temp.sof_try(v_who, format('select count(*)::text from public.%I', t));
      n := n + 1;
      if v_who in ('owner', 'admin', 'manager', 'invman', 'staff1', 'staff2') then
        if split_part(v_out, chr(9), 1) <> 'ok' then
          perform pg_temp.sof_fail(format('4: %s could not read %s: %s', v_who, t, v_out));
        elsif t = any (c_filled) and split_part(v_out, chr(9), 2)::int = 0 then
          perform pg_temp.sof_fail(format('4: %s read no row of %s', v_who, t));
        end if;
      elsif v_out not in ('ok' || chr(9) || '0') and split_part(v_out, chr(9), 1) <> '42501' then
        perform pg_temp.sof_fail(format('4: %s (not staff) read %s rows of %s', v_who, split_part(v_out, chr(9), 2), t));
      end if;
    end loop;
  end loop;
  -- The rest of the customer record stays closed too (342, 343; X-5 for the
  -- deactivated employee).
  foreach t in array array['customers', 'health_surveys', 'consultant_notes', 'invoices', 'invoice_items',
                           'profiles', 'audit_logs', 'document_sends', 'approval_requests',
                           'staff_commissions', 'staff_commission_payouts', 'transfer_requests'] loop
    foreach v_who in array array['affiliate', 'nostaff', 'inactive', 'pending', 'cancelled'] loop
      v_out := pg_temp.sof_try(v_who, format('select count(*)::text from public.%I where id <> %L', t,
                                             coalesce(pg_temp.sof_id(v_who), gen_random_uuid())));
      n := n + 1;
      if v_out <> 'ok' || chr(9) || '0' and split_part(v_out, chr(9), 1) <> '42501' then
        perform pg_temp.sof_fail(format('4: %s (not staff) read %s', v_who, t));
      end if;
    end loop;
  end loop;
  insert into sof_tally values ('4 table reads', n);
end $$;

-- ── 5. The invoice PDF folder (407) ─────────────────────────────────────────
do $$
declare v_out text; a text := pg_temp.sof_id('store_a')::text; b text := pg_temp.sof_id('store_b')::text;
begin
  -- Reading: each login sees the PDFs of its stores; Managers and up see all.
  if pg_temp.sof_try('staff1', 'select count(*)::text from storage.objects where bucket_id = ''invoice-pdfs'' and name like ''%SOFX%''')
     <> 'ok' || chr(9) || '1' then
    perform pg_temp.sof_fail('5: Staff at store A do not see exactly store A''s PDF');
  end if;
  if pg_temp.sof_try('staff2', 'select count(*)::text from storage.objects where bucket_id = ''invoice-pdfs'' and name like ''%SOFX%''')
     <> 'ok' || chr(9) || '2' then
    perform pg_temp.sof_fail('5: Staff at both stores do not see both PDFs');
  end if;
  if pg_temp.sof_try('manager', 'select count(*)::text from storage.objects where bucket_id = ''invoice-pdfs'' and name like ''%SOFX%''')
     <> 'ok' || chr(9) || '2' then
    perform pg_temp.sof_fail('5: a Manager does not see both PDFs');
  end if;
  foreach v_out in array array['affiliate', 'nostaff', 'inactive'] loop
    if pg_temp.sof_try(v_out, 'select count(*)::text from storage.objects where bucket_id = ''invoice-pdfs''')
       <> 'ok' || chr(9) || '0' then
      perform pg_temp.sof_fail('5: ' || v_out || ' (not staff) sees invoice PDFs');
    end if;
  end loop;
  -- Uploading: into one's own store, not another's, and never as a non-staff login.
  if split_part(pg_temp.sof_try('staff1', format('insert into storage.objects(bucket_id, name) values (''invoice-pdfs'', %L) returning 1', a || '/invoice/SOFX-new-a.pdf')), chr(9), 1) <> 'ok' then
    perform pg_temp.sof_fail('5: Staff could not upload a PDF for their own store');
  end if;
  if split_part(pg_temp.sof_try('staff1', format('insert into storage.objects(bucket_id, name) values (''invoice-pdfs'', %L) returning 1', b || '/invoice/SOFX-new-b.pdf')), chr(9), 1) <> '42501' then
    perform pg_temp.sof_fail('5: Staff uploaded a PDF for a store they do not work at');
  end if;
  if split_part(pg_temp.sof_try('affiliate', format('insert into storage.objects(bucket_id, name) values (''invoice-pdfs'', %L) returning 1', a || '/invoice/SOFX-forged.pdf')), chr(9), 1) <> '42501' then
    perform pg_temp.sof_fail('5: an affiliate uploaded an invoice PDF');
  end if;
  -- Replacing a PDF already sent: an Owner's or Manager's, as deleting one;
  -- not even its own store's Staff (the pages never replace a file now).
  if pg_temp.sof_try('staff1', format('with u as (update storage.objects set metadata = ''{"forged": true}'' where bucket_id = ''invoice-pdfs'' and name = %L returning 1) select count(*)::text from u', a || '/invoice/SOFX-INV-A-fixture.pdf'))
     <> 'ok' || chr(9) || '0' then
    perform pg_temp.sof_fail('5: Staff replaced a PDF of their own store');
  end if;
  if pg_temp.sof_try('manager', format('with u as (update storage.objects set metadata = ''{"checked": true}'' where bucket_id = ''invoice-pdfs'' and name = %L returning 1) select count(*)::text from u', a || '/invoice/SOFX-INV-A-fixture.pdf'))
     <> 'ok' || chr(9) || '1' then
    perform pg_temp.sof_fail('5: a Manager could not replace a PDF');
  end if;
  -- The pages live before the new front end upload with upsert, as the storage
  -- server does it: a first send still goes; replacing an earlier send is
  -- refused to Staff.
  if split_part(pg_temp.sof_try('staff1', format('insert into storage.objects(bucket_id, name, version, metadata) values (''invoice-pdfs'', %L, ''1'', ''{}'') on conflict (name, bucket_id) do update set metadata = excluded.metadata, version = excluded.version returning 1', a || '/invoice/SOFX-upsert-new.pdf')), chr(9), 1) <> 'ok' then
    perform pg_temp.sof_fail('5: Staff could not make a first send with the old pages'' upload');
  end if;
  if split_part(pg_temp.sof_try('staff1', format('insert into storage.objects(bucket_id, name, version, metadata) values (''invoice-pdfs'', %L, ''1'', ''{}'') on conflict (name, bucket_id) do update set metadata = excluded.metadata, version = excluded.version returning 1', a || '/invoice/SOFX-INV-A-fixture.pdf')), chr(9), 1) <> '42501' then
    perform pg_temp.sof_fail('5: Staff replaced a sent PDF with the old pages'' upload');
  end if;
  if split_part(pg_temp.sof_try('staff1', format('insert into storage.objects(bucket_id, name) values (''invoice-pdfs'', %L) returning 1', a || '/invoice/SOFX-INV-A-fixture.pdf')), chr(9), 1) = 'ok' then
    perform pg_temp.sof_fail('5: Staff filed a second PDF under a sent PDF''s name');
  end if;
  -- Replacing another store's PDF changes nothing.
  if pg_temp.sof_try('staff1', format('with u as (update storage.objects set metadata = ''{"forged": true}'' where bucket_id = ''invoice-pdfs'' and name = %L returning 1) select count(*)::text from u', b || '/invoice/SOFX-INV-B-fixture.pdf'))
     <> 'ok' || chr(9) || '0' then
    perform pg_temp.sof_fail('5: Staff replaced another store''s PDF');
  end if;
  if pg_temp.sof_try('affiliate', format('with u as (update storage.objects set metadata = ''{"forged": true}'' where bucket_id = ''invoice-pdfs'' and name = %L returning 1) select count(*)::text from u', a || '/invoice/SOFX-INV-A-fixture.pdf'))
     <> 'ok' || chr(9) || '0' then
    perform pg_temp.sof_fail('5: an affiliate replaced an invoice PDF');
  end if;
  -- PDFs only, of at most 10 MB.
  if not exists (select 1 from storage.buckets where id = 'invoice-pdfs' and file_size_limit = 10485760
                  and allowed_mime_types = array['application/pdf']) then
    perform pg_temp.sof_fail('5: the invoice-pdfs bucket takes more than PDFs of up to 10 MB');
  end if;
end $$;

-- ── 6. Approval requests, the audit log and the send log (407) ──────────────
do $$
declare v_who text; v_out text;
begin
  foreach v_who in array array['staff1', 'manager', 'owner', 'affiliate'] loop
    v_out := pg_temp.sof_try(v_who, format('insert into public.approval_requests(request_type, status, requested_by, payload) values (''adjustment'', ''pending'', %L, ''{}'') returning 1', pg_temp.sof_id(v_who)));
    if split_part(v_out, chr(9), 1) <> '42501' then
      perform pg_temp.sof_fail('6: ' || v_who || ' wrote an approval request directly: ' || v_out);
    end if;
    v_out := pg_temp.sof_try(v_who, 'insert into public.audit_logs(table_name, action) values (''invoices'', ''invoice_cancelled'') returning 1');
    if split_part(v_out, chr(9), 1) <> '42501' then
      perform pg_temp.sof_fail('6: ' || v_who || ' wrote an audit entry directly');
    end if;
    v_out := pg_temp.sof_try(v_who, 'select public.write_audit(''invoices'', null, ''invoice_cancelled'', null, null)::text');
    if split_part(v_out, chr(9), 1) <> '42501' then
      perform pg_temp.sof_fail('6: ' || v_who || ' wrote an audit entry through write_audit');
    end if;
  end loop;
  -- Staff still read their requests' list (the Adjustments and Approvals pages).
  if split_part(pg_temp.sof_try('staff1', 'select count(*)::text from public.approval_requests'), chr(9), 1) <> 'ok' then
    perform pg_temp.sof_fail('6: Staff can no longer read approval requests');
  end if;
end $$;

-- ── 7. Profiles: Managers' edits, and what nobody edits from a page (407) ───
do $$
declare v_out text; v_state text;
begin
  -- The deactivated employee still reads their own row, so the app can tell
  -- them they are deactivated, and has no role.
  if pg_temp.sof_try('inactive', 'select count(*)::text || coalesce(public.current_user_role()::text, '''') from public.profiles')
     <> 'ok' || chr(9) || '1' then
    perform pg_temp.sof_fail('7: a deactivated login does not read exactly its own profile, or has a role');
  end if;
  -- A Manager's edit of a Staff member saves (ADMIN-AUTH-2)...
  if pg_temp.sof_try('manager', format('with u as (update public.profiles set work_phone = ''+6591400199'' where id = %L returning 1) select count(*)::text from u', pg_temp.sof_id('staff2')))
     <> 'ok' || chr(9) || '1' then
    perform pg_temp.sof_fail('7: a Manager''s edit of a Staff member saved nothing');
  end if;
  if pg_temp.sof_try('manager', format('with u as (update public.profiles set is_active = false where id = %L returning 1) select count(*)::text from u', pg_temp.sof_id('invman')))
     <> 'ok' || chr(9) || '1' then
    perform pg_temp.sof_fail('7: a Manager could not deactivate an Inventory Manager');
  end if;
  -- ...but not of an Owner, and not to a Manager's role.
  if pg_temp.sof_try('manager', format('with u as (update public.profiles set work_phone = ''x'' where id = %L returning 1) select count(*)::text from u', pg_temp.sof_id('owner')))
     <> 'ok' || chr(9) || '0' then
    perform pg_temp.sof_fail('7: a Manager edited an Owner');
  end if;
  v_state := split_part(pg_temp.sof_try('manager', format('update public.profiles set role = ''manager'' where id = %L returning 1', pg_temp.sof_id('staff2'))), chr(9), 1);
  if v_state <> '42501' then
    perform pg_temp.sof_fail('7: a Manager made someone a Manager (' || v_state || ')');
  end if;
  -- Staff edit their own name, but not who they are (ADMIN-AUTH-M3).
  if pg_temp.sof_try('staff1', format('with u as (update public.profiles set full_name = ''SOFX Staff One'' where id = %L returning 1) select count(*)::text from u', pg_temp.sof_id('staff1')))
     <> 'ok' || chr(9) || '1' then
    perform pg_temp.sof_fail('7: Staff could not edit their own name');
  end if;
  foreach v_out in array array['deleted_at = now()', 'invitation_status = ''cancelled''',
                               'email = ''sofx-other@sig.invalid''', 'created_at = now() - interval ''1 year'''] loop
    v_state := split_part(pg_temp.sof_try('staff1', format('update public.profiles set %s where id = %L returning 1', v_out, pg_temp.sof_id('staff1'))), chr(9), 1);
    if v_state <> '42501' then
      perform pg_temp.sof_fail('7: Staff changed their own ' || v_out || ' (' || v_state || ')');
    end if;
    v_state := split_part(pg_temp.sof_try('owner', format('update public.profiles set %s where id = %L returning 1', v_out, pg_temp.sof_id('staff1'))), chr(9), 1);
    if v_state <> '42501' then
      perform pg_temp.sof_fail('7: an Owner changed someone''s ' || v_out || ' from a page (' || v_state || ')');
    end if;
  end loop;
  -- An invitee is switched on by accepting, not by ticking Active (ADMIN-AUTH-13).
  v_state := split_part(pg_temp.sof_try('owner', format('update public.profiles set is_active = true where id = %L returning 1', pg_temp.sof_id('pending'))), chr(9), 1);
  if v_state <> '42501' then
    perform pg_temp.sof_fail('7: an Owner activated a pending invitee (' || v_state || ')');
  end if;
  -- The server still can (the invitation functions declare their intent).
  perform set_config('energia.profile_privilege_change', 'on', true);
  update public.profiles set is_active = true, invitation_status = 'accepted' where id = pg_temp.sof_id('pending');
  perform set_config('energia.profile_privilege_change', '', true);
  if pg_temp.sof_try('pending', 'select coalesce(public.current_user_role()::text, ''none'')') <> 'ok' || chr(9) || 'staff' then
    perform pg_temp.sof_fail('7: an accepted invitee has no role');
  end if;
end $$;

-- ── 7b. A deactivated employee's own records (406, 407; X-5) ────────────────
do $$
declare v_out text;
begin
  -- Their own pending transfer request stays theirs no longer to cancel...
  v_out := pg_temp.sof_try('inactive', pg_temp.sof_sql('select public.cancel_transfer_request(@treq@)::text'));
  if split_part(v_out, chr(9), 1) <> '42501'
     or (select status::text from public.transfer_requests where id = pg_temp.sof_id('treq')) <> 'pending' then
    perform pg_temp.sof_fail('7b: a deactivated employee cancelled their transfer request: ' || v_out);
  end if;
  -- ...while active Staff still cancel theirs.
  v_out := pg_temp.sof_try('staff1', pg_temp.sof_sql('select public.cancel_transfer_request(@treq_staff1@)::text'));
  if split_part(v_out, chr(9), 1) <> 'ok'
     or (select status::text from public.transfer_requests where id = pg_temp.sof_id('treq_staff1')) <> 'cancelled' then
    perform pg_temp.sof_fail('7b: Staff could not cancel their own transfer request: ' || v_out);
  end if;
  -- A take-back is not replayed for them.
  v_out := pg_temp.sof_try('inactive', 'select public.return_stock_loan(gen_random_uuid(), ''[]'', null, gen_random_uuid())::text');
  if split_part(v_out, chr(9), 1) <> '42501' then
    perform pg_temp.sof_fail('7b: return_stock_loan answered a deactivated employee: ' || v_out);
  end if;
  -- No default store for them; Staff keep theirs.
  if pg_temp.sof_try('inactive', 'select coalesce(public.my_assigned_store_id()::text, ''none'')') <> 'ok' || chr(9) || 'none' then
    perform pg_temp.sof_fail('7b: a deactivated employee still has a default store');
  end if;
  if pg_temp.sof_try('staff1', 'select public.my_assigned_store_id()::text') <> 'ok' || chr(9) || pg_temp.sof_id('store_a')::text then
    perform pg_temp.sof_fail('7b: Staff lost their default store');
  end if;
  -- Their own requests, commissions and payouts are not read any more; Staff
  -- still read their own, and only their own.
  if pg_temp.sof_try('inactive', 'select ((select count(*) from public.approval_requests) + (select count(*) from public.staff_commissions) + (select count(*) from public.staff_commission_payouts))::text')
     <> 'ok' || chr(9) || '0' then
    perform pg_temp.sof_fail('7b: a deactivated employee still reads their own requests, commissions or payouts');
  end if;
  if pg_temp.sof_try('staff1', format('select (select count(*) from public.approval_requests where requested_by = %1$L)::text || (select count(*) from public.staff_commissions where staff_id = %1$L)::text || (select count(*) from public.staff_commission_payouts where staff_id = %1$L)::text', pg_temp.sof_id('staff1')))
     <> 'ok' || chr(9) || '111' then
    perform pg_temp.sof_fail('7b: Staff no longer read their own requests, commissions and payouts');
  end if;
  if pg_temp.sof_try('staff1', format('select ((select count(*) from public.approval_requests where requested_by <> %1$L) + (select count(*) from public.staff_commissions where staff_id <> %1$L) + (select count(*) from public.staff_commission_payouts where staff_id <> %1$L))::text', pg_temp.sof_id('staff1')))
     <> 'ok' || chr(9) || '0' then
    perform pg_temp.sof_fail('7b: Staff read someone else''s requests, commissions or payouts');
  end if;
  -- Managers still read everyone's.
  if pg_temp.sof_try('manager', format('select ((select count(*) from public.approval_requests where requested_by in (%1$L, %2$L)) + (select count(*) from public.staff_commissions where staff_id in (%1$L, %2$L)) + (select count(*) from public.staff_commission_payouts where staff_id in (%1$L, %2$L)))::text', pg_temp.sof_id('staff1'), pg_temp.sof_id('inactive')))
     <> 'ok' || chr(9) || '6' then
    perform pg_temp.sof_fail('7b: a Manager no longer reads every request, commission and payout');
  end if;
end $$;

-- ── 8. A payment recorded by Staff still runs its triggers ──────────────────
-- Paying an invoice earns staff commission (store_commission_staff) and issues
-- what was bought; those run inside the payment as the person paying, so they
-- meet the checks again.
do $$
declare v_out text;
begin
  v_out := pg_temp.sof_try('staff1', pg_temp.sof_sql(
    'select public.record_invoice_settlement(@inv_a@, jsonb_build_object(''receipts'', jsonb_build_array('
    || 'jsonb_build_object(''key'', ''r1'', ''payment_method_id'', @cash@, ''amount'', 100))), gen_random_uuid())::text'));
  if split_part(v_out, chr(9), 1) <> 'ok' then
    perform pg_temp.sof_fail('8: Staff could not take a payment: ' || v_out);
  elsif (select status from public.invoices where id = pg_temp.sof_id('inv_a')) <> 'paid' then
    perform pg_temp.sof_fail('8: the invoice is not paid after a full payment');
  end if;
end $$;

-- ── Result ──────────────────────────────────────────────────────────────────
set local client_min_messages = notice;
do $$
declare v_fail text; v_tally text;
begin
  select string_agg(msg, E'\n  ' order by n) into v_fail from sof_fail;
  select string_agg(k || ': ' || n, ', ' order by k) into v_tally from sof_tally;
  if v_fail is not null then
    raise exception E'FAIL (%):\n  %', (select count(*) from sof_fail), v_fail;
  end if;
  raise notice 'PASS: every function a signed-in login may call refuses logins that are not staff, or is named with its reason; each page''s functions answer the roles that can open it and refuse the rest; tables, invoice PDFs, approval requests and profiles hold; a deactivated employee''s own records are closed to them; Staff still take payments. (%)', v_tally;
end $$;
rollback;
