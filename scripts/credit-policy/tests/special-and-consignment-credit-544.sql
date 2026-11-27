-- 544: wallet credit pays special products and consignment products (the owner, 26 Nov 2026).
-- supabase/544_wallet_credit_pays_special_and_consignment_products.sql
--
-- Every step goes through the app's own calls where the app has one: the invoice form
-- (create_invoice_with_details), the Pay dialog (record_invoice_settlement), Record Payment
-- (record_invoice_payment) and its wallet methods' "available" amounts
-- (invoice_wallet_availability), Cancel (cancel_invoice_recorded), "Record refund paid" and the
-- Finance panel's refund by line (refund_invoice_recorded), an Owner's opening balance
-- (add_legacy_credit), the Rules screen (credit_spendable_categories,
-- preview_credit_package_policy_change, set_credit_package_spending_rules,
-- credit_package_effective_rules). Special and consignment products are paid on their invoice
-- lines only: 544 drops pay_special_with_credit (the old Special page's wallet payment, which
-- nothing calls).
--
--   S. Where it starts: production after 540 (541 and 542 may be in too); 544 in (installed here,
--      or already in with -v nomig=1). The fixture: a special product (S$100) and a consignment
--      product (S$80), each with stock at a warehouse; a Premium Bundle and a Credit Package
--      (S$300 of paid credit each, no bonus, no vouchers); one customer per case.
--   C. Categories: purchase_category gives special_product / consignment_product for a special
--      product's line, unknown with no special product, unknown for a rental; four-argument calls
--      as before; the grants (signed-in logins and the service role, not anon).
--   B. Premium Bundle credit pays a special line and a consignment line: each method's
--      "available", the line checks, Record Payment, a retried payment (the same request id)
--      taking nothing more, the allocations on the bundle's lot.
--   O. Other credit (an Owner's opening balance) pays them too, through the 'other' paid method.
--   P. Credit Package credit pays neither by default (available 0, a wallet payment refused);
--      the Rules screen offers both; ticking special products lets it pay the special line only,
--      ticking consignment products too lets it pay both; the rules as read back.
--   R. Rentals: no credit pays a rental line (bundle, other, a package that ticked both).
--   X. Credit never buys credit: an invoice with a credit package line is not payable by any
--      wallet method; no rule can name credit_package, premium_bundle or unknown; the category
--      check refuses them for every lot.
--   F. Refunds: a whole refund (Cancel, then "Record refund paid") gives each lot back exactly
--      what it gave (a bundle lot and an other lot on one invoice); a refund by line gives the
--      consignment line's S$80 back to the bundle lot alone.
--   W. No other route: pay_special_with_credit is gone and nothing calls it; refund_special_credit
--      and consume_customer_credit are as they were (the service role's alone; a special sale's
--      wallet payment through consume_customer_credit is still refused); no special document
--      takes credit.
--   E. What each lot may pay, as listed (customer_credit_eligibility, credit_lot_spending_summary).
--
-- Run on a copy of production at 540 (with or without 541 and 542):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/credit-policy/tests/special-and-consignment-credit-544.sql
-- It installs 544 itself inside its transaction. Where 544 is in already, add -v nomig=1. With
-- -v mig=<file> it installs that file instead (for the mutation checks). Each check prints
-- "PASS <label>" or "FAIL <label>"; at the end it prints the counts and stops with an error when
-- any check failed. Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction (ACMA,
-- +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first, as this file pins
-- md5s of functions it changes (only their search path); this run only, rolled back with the rest.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
create temp table t544(k text primary key, id uuid);
create temp table t544_results(n serial, label text, ok boolean);
create function pg_temp.t544_id(p_k text) returns uuid language sql as $f$ select id from t544 where k = p_k $f$;
create function pg_temp.t544_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t544 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t544_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  insert into t544_results(label, ok) values (p_label, coalesce(p_ok, false));
  if coalesce(p_ok, false) then raise notice 'PASS %', p_label; else raise notice 'FAIL %', p_label; end if;
end $f$;
-- Runs a statement; null when it worked, else its error (and nothing it did stays).
create function pg_temp.t544_try(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $f$;
create function pg_temp.t544_fp() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f' $f$;

-- S. Where it starts ------------------------------------------------------------------------
select 'S: before 544 ' || pg_temp.t544_fp() as fingerprint;
\if :{?nomig}
\else
\if :{?mig}
\i :mig
\else
\ir ../../../supabase/544_wallet_credit_pays_special_and_consignment_products.sql
\endif
\endif
select 'S: with 544 ' || pg_temp.t544_fp() as fingerprint;
-- Set these after installing (a guard refusing must stop the run, not be counted).
\set ON_ERROR_STOP on

do $$
declare own uuid := gen_random_uuid(); st uuid; wh uuid; pm uuid; sp uuid; cp uuid; pb uuid; pk uuid; v uuid;
begin
  insert into auth.users(id, email) values (own, 't544-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T544 Owner', 't544-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T544 Store', 'T544S1', 'SG') returning id into st;
  insert into warehouses(name, code) values ('T544 Warehouse', 'T544W1') returning id into wh;
  insert into payment_methods(name, is_active) values ('T544 Cash', true) returning id into pm;
  insert into special_products(name, sku, sale_price, rate_month, is_active, is_consignment)
    values ('T544 Massage Chair', 'T544-SP', 100, 30, true, false) returning id into sp;
  insert into special_product_stock(special_product_id, warehouse_id, current_qty) values (sp, wh, 20);
  insert into special_products(name, sku, sale_price, rate_month, is_active, is_consignment)
    values ('T544 Partner Lamp', 'T544-CP', 80, 20, true, true) returning id into cp;
  insert into special_product_stock(special_product_id, warehouse_id, current_qty) values (cp, wh, 20);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T544 Bundle S$300', 300, 300, 0, 0, false) returning id into pb;
  insert into premium_bundle_stores(bundle_id, store_id) values (pb, st);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('T544 Package S$300', 300, 300, false, true, true, false) returning id into pk;
  insert into credit_package_stores(package_id, store_id) values (pk, st);
  insert into t544 values ('own', own), ('store', st), ('wh', wh), ('pm', pm), ('sp', sp), ('cp', cp), ('pb', pb), ('pk', pk),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null)),
    ('kwallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null));
  -- The 'other' paid method (production: 'Wallet — Paid Credit'); a copy without it gets one.
  select id into v from payment_methods
   where is_wallet_credit and deleted_at is null and is_active and wallet_category = 'paid'
     and public.wallet_method_source_filter(wallet_category, wallet_source) = 'other' limit 1;
  if v is null then
    insert into payment_methods(name, is_active, is_wallet_credit, wallet_category)
      values ('T544 Wallet Paid Credit', true, true, 'paid') returning id into v;
  end if;
  perform pg_temp.t544_put('owallet', v);
  perform pg_temp.t544_check(pg_temp.t544_id('bwallet') is not null and pg_temp.t544_id('kwallet') is not null
    and public.wallet_method_source_filter('paid', null) = 'other', 'S1 setup: the wallet methods (443) are there');
end $$;

-- A customer of one case.
create sequence t544_phone;
create function pg_temp.t544_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T544 ' || p_k, '+61491570' || lpad((nextval('t544_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t544_put(p_k, c);
end $f$;
-- The invoice form with these lines, not paid.
create function pg_temp.t544_invoice(p_cust uuid, p_lines jsonb) returns uuid language sql as $f$
  select create_invoice_with_details(pg_temp.t544_id('store'), p_cust, p_lines, jsonb_build_object('business_date', sg_today()::text)) $f$;
create function pg_temp.t544_line(p_kind text, p_key text default null) returns jsonb language sql as $f$
  select case p_kind
    when 'sp' then jsonb_build_object('kind', 'special_product', 'special_product_id', pg_temp.t544_id('sp'), 'quantity', 1)
    when 'cp' then jsonb_build_object('kind', 'special_product', 'special_product_id', pg_temp.t544_id('cp'), 'quantity', 1)
    when 'rent' then jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.t544_id('sp'), 'quantity', 1,
                                        'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', sg_today()::text)
    when 'pb' then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t544_id('pb'), 'quantity', 1)
    when 'pk' then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t544_id('pk'), 'quantity', 1)
  end $f$;
-- A Premium Bundle ('pb') or the Credit Package ('pk') bought and paid in cash in the Pay dialog;
-- the customer's lot from it.
create function pg_temp.t544_buy(p_cust uuid, p_what text) returns uuid language plpgsql as $f$
declare inv uuid; l uuid;
begin
  inv := pg_temp.t544_invoice(p_cust, jsonb_build_array(pg_temp.t544_line(p_what)));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t544_id('pm'), 'amount', (select total_amount from invoices where id = inv),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  select id into l from customer_credit_lots
   where customer_id = p_cust and status = 'active' and category = 'paid'
     and source_type = case p_what when 'pb' then 'premium_bundle' else 'credit_package' end
   order by created_at desc limit 1;
  if l is null then raise exception 'T544: no lot from %', p_what; end if;
  return l;
end $f$;
-- An Owner's opening balance for an old client (other credit, 'open').
create function pg_temp.t544_opening(p_cust uuid, p_amount numeric) returns uuid language sql as $f$
  select add_legacy_credit(p_cust, 'paid', p_amount, sg_today(), pg_temp.t544_id('store'), null, 'T544 opening balance',
                           null, gen_random_uuid()) $f$;
-- What a wallet method could pay of an invoice now (Record Payment's "available").
create function pg_temp.t544_avail(p_inv uuid, p_method text) returns numeric language sql as $f$
  select (m ->> 'available')::numeric from jsonb_array_elements(invoice_wallet_availability(p_inv) -> 'methods') m
   where m ->> 'payment_method_id' = pg_temp.t544_id(p_method)::text $f$;
-- Record Payment with a wallet method.
create function pg_temp.t544_pay(p_inv uuid, p_method text, p_amount numeric, p_request uuid default gen_random_uuid())
  returns void language sql as $f$
  select record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t544_id(p_method),
    'amount', p_amount)), p_request) $f$;
create function pg_temp.t544_item(p_inv uuid, p_special text) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv
     and (p_special = 'rent' and line_kind::text = 'rental'
          or p_special in ('sp', 'cp') and line_kind::text = 'special_product' and special_product_id = pg_temp.t544_id(p_special)) $f$;
create function pg_temp.t544_rem(p_lot uuid) returns numeric language sql as $f$
  select remaining_amount from customer_credit_lots where id = p_lot $f$;
-- What lot p_lot gave line p_item, less what was given back.
create function pg_temp.t544_alloc(p_item uuid, p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(a.amount - a.reversed_amount), 0) from invoice_line_credit_allocations a
   where a.invoice_item_id = p_item and a.lot_id = p_lot $f$;
-- The receipts that still hold p_amount between them, as the Finance panel splits a refund.
create function pg_temp.t544_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
declare src jsonb := '[]'; left_ numeric := p_amount; p record;
begin
  for p in select id, invoice_payment_remaining(id) as rem from invoice_payments
            where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement') and invoice_payment_remaining(id) > 0
            order by created_at, id loop
    exit when left_ <= 0;
    src := src || jsonb_build_array(jsonb_build_object('payment_id', p.id, 'amount', least(p.rem, left_)));
    left_ := left_ - least(p.rem, left_);
  end loop;
  return src;
end $f$;

-- C. Categories -----------------------------------------------------------------------------
do $$
begin
  perform pg_temp.t544_check(purchase_category('special_product', null, null, null, pg_temp.t544_id('sp')) = 'special_product',
    'C1 a special product''s line is special_product');
  perform pg_temp.t544_check(purchase_category('special_product', null, null, null, pg_temp.t544_id('cp')) = 'consignment_product',
    'C2 a consignment product''s line is consignment_product');
  perform pg_temp.t544_check(purchase_category('special_product') = 'unknown'
    and purchase_category('special_product', null, null, null, gen_random_uuid()) = 'unknown',
    'C3 a special product''s line with no (or no such) special product is unknown');
  perform pg_temp.t544_check(purchase_category('rental', null, null, null, pg_temp.t544_id('sp')) = 'unknown'
    and purchase_category('rental') = 'unknown' and purchase_category('late_fee') = 'unknown',
    'C4 a rental and a late fee stay unknown');
  perform pg_temp.t544_check(purchase_category('therapy', null, null, gen_random_uuid()) = 'therapy_session'
    and purchase_category('credit_package') = 'credit_package' and purchase_category('premium_bundle') = 'premium_bundle'
    and purchase_category('event') = 'event_ticket',
    'C5 four-argument calls as before');
  perform pg_temp.t544_check(to_regprocedure('public.purchase_category(text,uuid,uuid,uuid)') is null
    and (select count(*) from pg_proc where proname = 'purchase_category' and pronamespace = 'public'::regnamespace) = 1,
    'C6 one purchase_category, with five arguments');
  perform pg_temp.t544_check(has_function_privilege('authenticated', 'public.purchase_category(text,uuid,uuid,uuid,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.purchase_category(text,uuid,uuid,uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.purchase_category(text,uuid,uuid,uuid,uuid)', 'execute'),
    'C7 purchase_category: signed-in logins and the service role, not anon');
  perform pg_temp.t544_check(credit_spendable_categories() @> array['special_product', 'consignment_product']
    and credit_package_default_rules() = jsonb_build_object('paid', jsonb_build_array('therapy_session'),
                                                            'bonus', jsonb_build_array('own_product', 'third_party_product')),
    'C8 the Rules screen offers both; the package defaults are unchanged');
end $$;

-- B. Premium Bundle credit --------------------------------------------------------------------
do $$
declare c uuid := pg_temp.t544_cust('B'); lot uuid; inv uuid; sp_i uuid; cp_i uuid; rq uuid := gen_random_uuid(); e text;
begin
  lot := pg_temp.t544_put('B/lot', pg_temp.t544_buy(c, 'pb'));
  perform pg_temp.t544_check((select usage_restrictions -> 'allowed_purposes' from customer_credit_lots where id = lot)
    = '["product", "voucher", "promotion", "therapy", "rental"]'::jsonb,
    'B0 the bundle lot keeps the fixed list its sale gives (no special_product)');
  inv := pg_temp.t544_put('B/inv', pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('sp'), pg_temp.t544_line('cp'))));
  sp_i := pg_temp.t544_item(inv, 'sp'); cp_i := pg_temp.t544_item(inv, 'cp');
  perform pg_temp.t544_check(credit_lot_line_allowed(lot, sp_i) and credit_lot_line_allowed(lot, cp_i)
    and credit_lot_line_reason(lot, sp_i) is null and credit_lot_line_reason(lot, cp_i) is null,
    'B1 the bundle lot may pay the special line and the consignment line');
  perform pg_temp.t544_check(credit_lot_snapshot_allows(lot, (select usage_restrictions from customer_credit_lots where id = lot), 'special_product', null),
    'B2 the bundle lot''s fixed list no longer stops a special product''s line');
  perform pg_temp.t544_check(pg_temp.t544_avail(inv, 'bwallet') = 180 and pg_temp.t544_avail(inv, 'kwallet') = 0
    and pg_temp.t544_avail(inv, 'owallet') = 0,
    'B3 Record Payment: Premium Bundle Paid has S$180 available (both lines), the others S$0');
  perform pg_temp.t544_pay(inv, 'bwallet', 180, rq);
  perform pg_temp.t544_check((select status::text from invoices where id = inv) = 'paid' and pg_temp.t544_rem(lot) = 120
    and pg_temp.t544_alloc(sp_i, lot) = 100 and pg_temp.t544_alloc(cp_i, lot) = 80,
    'B4 paid with bundle credit: S$100 + S$80 from the bundle lot, S$120 left');
  e := pg_temp.t544_try(format('select pg_temp.t544_pay(%L::uuid, %L, 180, %L::uuid)', inv, 'bwallet', rq));
  perform pg_temp.t544_check(pg_temp.t544_rem(lot) = 120
    and (select count(*) from invoice_line_credit_allocations where invoice_id = inv) = 2
    and (select count(*) from customer_credit_ledger where lot_id = lot and entry_type = 'use') = 2,
    'B5 the same payment sent again (same request id) takes nothing more' || coalesce(' (' || e || ')', ''));
  e := pg_temp.t544_try(format('select pg_temp.t544_pay(%L::uuid, %L, 10)', inv, 'bwallet'));
  perform pg_temp.t544_check(e is not null and pg_temp.t544_rem(lot) = 120,
    'B6 a further wallet payment on the paid invoice is refused and takes nothing');
end $$;

-- O. Other credit -------------------------------------------------------------------------------
do $$
declare c uuid := pg_temp.t544_cust('O'); lot uuid; inv uuid; sp_i uuid; cp_i uuid;
begin
  lot := pg_temp.t544_put('O/lot', pg_temp.t544_opening(c, 200));
  perform pg_temp.t544_check(credit_lot_policy_for(lot) = 'open' and credit_lot_source_group(lot) = 'other',
    'O0 an opening balance is other credit (open)');
  inv := pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('sp'), pg_temp.t544_line('cp')));
  sp_i := pg_temp.t544_item(inv, 'sp'); cp_i := pg_temp.t544_item(inv, 'cp');
  perform pg_temp.t544_check(credit_lot_line_allowed(lot, sp_i) and credit_lot_line_allowed(lot, cp_i),
    'O1 other credit may pay the special line and the consignment line');
  perform pg_temp.t544_check(pg_temp.t544_avail(inv, 'owallet') = 180 and pg_temp.t544_avail(inv, 'bwallet') = 0,
    'O2 Record Payment: the other paid method has S$180 available');
  perform pg_temp.t544_pay(inv, 'owallet', 180);
  perform pg_temp.t544_check((select status::text from invoices where id = inv) = 'paid' and pg_temp.t544_rem(lot) = 20
    and pg_temp.t544_alloc(sp_i, lot) = 100 and pg_temp.t544_alloc(cp_i, lot) = 80,
    'O3 paid with other credit: S$180 from the opening balance, S$20 left');
end $$;
do $$
declare c uuid := pg_temp.t544_cust('O/listed'); lot uuid; inv uuid;
begin
  -- A stand-in: other credit with a purpose list of its own (production has none; the app gives
  -- manual credit an empty list). 544 does not widen it: an 'open' lot keeps its own list.
  lot := grant_customer_credit(c, 'paid', 200, 'manual', null, pg_temp.t544_id('store'), sg_today(), null, 'T544 listed', null, null,
                               pg_temp.t544_id('own'), jsonb_build_object('allowed_purposes', jsonb_build_array('product')));
  inv := pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('sp')));
  perform pg_temp.t544_check(credit_lot_policy_for(lot) = 'open' and credit_lot_line_allowed(lot, pg_temp.t544_item(inv, 'sp'))
    and pg_temp.t544_avail(inv, 'owallet') = 0,
    'O4 other credit with its own list (products only) is still held to it');
end $$;

-- P. Credit Package credit ---------------------------------------------------------------------
do $$
declare c uuid := pg_temp.t544_cust('P'); lot uuid; inv uuid; sp_i uuid; cp_i uuid; e text; r jsonb;
begin
  lot := pg_temp.t544_put('P/lot', pg_temp.t544_buy(c, 'pk'));
  inv := pg_temp.t544_put('P/inv', pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('sp'), pg_temp.t544_line('cp'))));
  sp_i := pg_temp.t544_item(inv, 'sp'); cp_i := pg_temp.t544_item(inv, 'cp');
  perform pg_temp.t544_check(not credit_lot_line_allowed(lot, sp_i) and not credit_lot_line_allowed(lot, cp_i)
    and credit_lot_line_reason(lot, sp_i) is not null,
    'P1 by default package credit may pay neither (with a reason)');
  perform pg_temp.t544_check(pg_temp.t544_avail(inv, 'kwallet') = 0, 'P2 Credit Package Paid has S$0 available');
  e := pg_temp.t544_try(format('select pg_temp.t544_pay(%L::uuid, %L, 100)', inv, 'kwallet'));
  perform pg_temp.t544_check(e is not null and pg_temp.t544_rem(lot) = 300, 'P3 a package wallet payment is refused, nothing taken');
  -- The Owner ticks special products for this package's paid credit.
  r := preview_credit_package_policy_change(pg_temp.t544_id('pk'), array['therapy_session', 'special_product'], array['own_product']);
  perform pg_temp.t544_check(r ? 'after', 'P4 the Rules preview accepts special_product');
  perform set_credit_package_spending_rules(pg_temp.t544_id('pk'), array['therapy_session', 'special_product'], array['own_product'],
                                            'T544 special products too');
  perform pg_temp.t544_check(credit_lot_line_allowed(lot, sp_i) and not credit_lot_line_allowed(lot, cp_i)
    and pg_temp.t544_avail(inv, 'kwallet') = 100,
    'P5 special products ticked: the special line (S$100) only, not the consignment line');
  perform set_credit_package_spending_rules(pg_temp.t544_id('pk'), array['therapy_session', 'consignment_product'], array['own_product'],
                                            'T544 consignment only');
  perform pg_temp.t544_check(not credit_lot_line_allowed(lot, sp_i) and credit_lot_line_allowed(lot, cp_i)
    and pg_temp.t544_avail(inv, 'kwallet') = 80,
    'P6 consignment products ticked alone: the consignment line (S$80) only');
  perform set_credit_package_spending_rules(pg_temp.t544_id('pk'), array['therapy_session', 'special_product', 'consignment_product'],
                                            array['own_product'], 'T544 both');
  r := credit_package_effective_rules(pg_temp.t544_id('pk'));
  perform pg_temp.t544_check(r -> 'paid' @> '["special_product", "consignment_product"]'::jsonb and r ->> 'source' = 'configured',
    'P7 the rules read back name both');
  perform pg_temp.t544_check(pg_temp.t544_avail(inv, 'kwallet') = 180, 'P8 both ticked: S$180 available');
  perform pg_temp.t544_pay(inv, 'kwallet', 180);
  perform pg_temp.t544_check((select status::text from invoices where id = inv) = 'paid' and pg_temp.t544_rem(lot) = 120
    and pg_temp.t544_alloc(sp_i, lot) = 100 and pg_temp.t544_alloc(cp_i, lot) = 80,
    'P9 paid with package credit once ticked');
  perform pg_temp.t544_check(credit_package_effective_rules(gen_random_uuid()) - 'source'
    = credit_package_default_rules(),
    'P10 a package with no rules of its own still gets the defaults (neither category)');
end $$;

-- R. Rentals -----------------------------------------------------------------------------------
do $$
declare inv uuid; r_i uuid; e text; c uuid := pg_temp.t544_cust('R'); blot uuid; olot uuid; klot uuid; sale uuid;
begin
  blot := pg_temp.t544_buy(c, 'pb'); olot := pg_temp.t544_opening(c, 200); klot := pg_temp.t544_buy(c, 'pk');
  inv := pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('rent')));
  r_i := pg_temp.t544_item(inv, 'rent');
  perform pg_temp.t544_check(r_i is not null and not credit_lot_line_allowed(blot, r_i) and not credit_lot_line_allowed(olot, r_i)
    and not credit_lot_line_allowed(klot, r_i),
    'R1 no credit may pay a rental line (bundle, other, a package with both ticked)');
  perform pg_temp.t544_check(pg_temp.t544_avail(inv, 'bwallet') = 0 and pg_temp.t544_avail(inv, 'owallet') = 0
    and pg_temp.t544_avail(inv, 'kwallet') = 0,
    'R2 Record Payment: S$0 available for a rental by every method');
  e := pg_temp.t544_try(format('select pg_temp.t544_pay(%L::uuid, %L, 10)', inv, 'bwallet'));
  perform pg_temp.t544_check(e is not null and pg_temp.t544_rem(blot) = 300, 'R3 a wallet payment for a rental is refused');
end $$;

-- X. Credit never buys credit ------------------------------------------------------------------
do $$
declare inv uuid; c uuid := pg_temp.t544_cust('X'); blot uuid; olot uuid; klot uuid; e text; a jsonb; l uuid; cat text;
begin
  blot := pg_temp.t544_buy(c, 'pb'); olot := pg_temp.t544_opening(c, 500); klot := pg_temp.t544_buy(c, 'pk');
  inv := pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('pk'), pg_temp.t544_line('sp')));
  a := invoice_wallet_availability(inv);
  perform pg_temp.t544_check((a ->> 'credit_line')::boolean and not (a ->> 'payable')::boolean
    and pg_temp.t544_avail(inv, 'bwallet') = 0 and pg_temp.t544_avail(inv, 'owallet') = 0,
    'X1 an invoice selling a credit package is not payable by wallet credit (even its special line)');
  e := pg_temp.t544_try(format('select pg_temp.t544_pay(%L::uuid, %L, 100)', inv, 'owallet'));
  perform pg_temp.t544_check(e is not null and pg_temp.t544_rem(olot) = 500, 'X2 a wallet payment on it is refused');
  foreach l in array array[blot, olot, klot] loop
    foreach cat in array array['credit_package', 'premium_bundle', 'unknown'] loop
      if credit_lot_allows_category(l, cat) then
        perform pg_temp.t544_check(false, 'X3 ' || credit_lot_policy_for(l) || ' credit may buy ' || cat); end if;
    end loop;
  end loop;
  perform pg_temp.t544_check(true, 'X3 no lot may buy credit_package, premium_bundle or unknown');
  e := pg_temp.t544_try(format('select preview_credit_package_policy_change(%L::uuid, array[''credit_package'',''special_product''], array[]::text[])',
                               pg_temp.t544_id('pk')));
  perform pg_temp.t544_check(e like 'Not a category%', 'X4 no rule may name credit_package' || coalesce(' (' || e || ')', ''));
  e := pg_temp.t544_try(format('select preview_credit_package_policy_change(%L::uuid, array[''rental''], array[''unknown''])',
                               pg_temp.t544_id('pk')));
  perform pg_temp.t544_check(e like 'Not a category%', 'X5 no rule may name rental or unknown');
end $$;

-- F. Refunds give credit back to the lot it came from -------------------------------------------
do $$
declare c uuid := pg_temp.t544_cust('F'); blot uuid; olot uuid; inv uuid; sp_i uuid; cp_i uuid; due numeric;
begin
  blot := pg_temp.t544_buy(c, 'pb'); olot := pg_temp.t544_opening(c, 200);
  inv := pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('sp'), pg_temp.t544_line('cp')));
  sp_i := pg_temp.t544_item(inv, 'sp'); cp_i := pg_temp.t544_item(inv, 'cp');
  -- S$100 from the bundle (it pays the first line, the special one), S$80 from other credit.
  perform pg_temp.t544_pay(inv, 'bwallet', 100);
  perform pg_temp.t544_pay(inv, 'owallet', 80);
  perform pg_temp.t544_check((select status::text from invoices where id = inv) = 'paid'
    and pg_temp.t544_rem(blot) = 200 and pg_temp.t544_rem(olot) = 120
    and pg_temp.t544_alloc(sp_i, blot) + pg_temp.t544_alloc(cp_i, blot) = 100
    and pg_temp.t544_alloc(sp_i, olot) + pg_temp.t544_alloc(cp_i, olot) = 80,
    'F1 paid from two lots: S$100 bundle, S$80 other');
  perform cancel_invoice_recorded(inv, 'T544 cancel', gen_random_uuid());
  due := (invoice_financial_position(inv) ->> 'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(inv, 'cancel', '[]') ->> 'refund_due')::numeric; end if;
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t544_sources(inv, due), '[]'::jsonb,
    'T544 refund paid', gen_random_uuid());
  perform pg_temp.t544_check(due = 180 and pg_temp.t544_rem(blot) = 300 and pg_temp.t544_rem(olot) = 200
    and pg_temp.t544_alloc(sp_i, blot) + pg_temp.t544_alloc(cp_i, blot) = 0
    and pg_temp.t544_alloc(sp_i, olot) + pg_temp.t544_alloc(cp_i, olot) = 0,
    'F2 cancelled and refunded: S$100 back to the bundle lot, S$80 back to the other lot, nothing more'
    || ' (due ' || coalesce(due::text, 'null') || ', bundle ' || pg_temp.t544_rem(blot) || ', other ' || pg_temp.t544_rem(olot) || ')');
end $$;
do $$
declare c uuid := pg_temp.t544_cust('F/line'); blot uuid; olot uuid; inv uuid; sp_i uuid; cp_i uuid; e text;
begin
  blot := pg_temp.t544_buy(c, 'pb'); olot := pg_temp.t544_opening(c, 50);
  inv := pg_temp.t544_invoice(c, jsonb_build_array(pg_temp.t544_line('sp'), pg_temp.t544_line('cp')));
  sp_i := pg_temp.t544_item(inv, 'sp'); cp_i := pg_temp.t544_item(inv, 'cp');
  perform pg_temp.t544_pay(inv, 'bwallet', 180);
  -- The Finance panel's refund by line: the consignment line's S$80, to its wallet payment.
  e := pg_temp.t544_try(format('select refund_invoice_recorded(%L::uuid, %L::jsonb, %L::jsonb, ''[]''::jsonb, ''T544 by line'', %L::uuid)',
    inv, jsonb_build_array(jsonb_build_object('invoice_item_id', cp_i, 'amount', 80)), pg_temp.t544_sources(inv, 80), gen_random_uuid()));
  perform pg_temp.t544_check(e is null and pg_temp.t544_rem(blot) = 200 and pg_temp.t544_rem(olot) = 50
    and pg_temp.t544_alloc(cp_i, blot) + pg_temp.t544_alloc(sp_i, blot) = 100,
    'F3 a refund by line of the consignment line gives S$80 back to the bundle lot alone'
    || coalesce(' (' || e || ')', '') || ' (bundle ' || pg_temp.t544_rem(blot) || ')');
  -- KNOWN, before 544 and not changed by it: a wallet refund gives back the refunded payment's
  -- allocations in the order of their ids (refund_invoice_recorded: "order by id", random uuids),
  -- not the refunded line's. So the S$80 is marked against whichever line's allocation comes
  -- first: the consignment line's, or S$80 of the special line's. The money and the lot are right
  -- here (one lot paid both lines); which line's allocation is marked is not certain.
  perform pg_temp.t544_check((pg_temp.t544_alloc(sp_i, blot), pg_temp.t544_alloc(cp_i, blot)) in ((100::numeric, 0::numeric), (20::numeric, 80::numeric)),
    'K1 KNOWN (before 544): the S$80 is marked against the first allocation by id, either line''s'
    || format(' (special %s, consignment %s)', pg_temp.t544_alloc(sp_i, blot), pg_temp.t544_alloc(cp_i, blot)));
end $$;

-- W. No other route than the invoice ---------------------------------------------------------
do $$
declare c uuid := pg_temp.t544_cust('W'); blot uuid; s1 uuid; e text; n0 bigint := (select count(*) from special_credit_allocations);
begin
  perform pg_temp.t544_check((select count(*) from pg_proc where proname = 'pay_special_with_credit') = 0,
    'W1 pay_special_with_credit is gone (no overload of that name)');
  perform pg_temp.t544_check(not exists (select 1 from pg_proc p where p.prosrc ~ 'pay_special_with_credit\s*\('),
    'W2 no function calls pay_special_with_credit');
  perform pg_temp.t544_check(md5(pg_get_functiondef('public.refund_special_credit(text,uuid)'::regprocedure)) = '42e436aa44046d4cb1748641cd8a5257'
    and has_function_privilege('service_role', 'public.refund_special_credit(text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.refund_special_credit(text,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.refund_special_credit(text,uuid)', 'execute'),
    'W3 refund_special_credit as it was, the service role''s alone');
  blot := pg_temp.t544_buy(c, 'pb');
  s1 := create_special_sale(pg_temp.t544_id('sp'), pg_temp.t544_id('wh'), c, 1, pg_temp.t544_id('pm'), null, 'T544 sale');
  e := pg_temp.t544_try(format('select consume_customer_credit(%L::uuid, 100, ''special_sale'', %L::uuid, %L::uuid, null, ''T544'', ''special_product'', null)',
                               c, s1, pg_temp.t544_id('store')));
  perform pg_temp.t544_check(md5(pg_get_functiondef('public.consume_customer_credit(uuid,numeric,text,uuid,uuid,text,text,text,uuid)'::regprocedure))
      = 'fa07fb9251a38f41d42899a3f2a0ba61'
    and e like 'Insufficient credit%' and pg_temp.t544_rem(blot) = 300,
    'W4 consume_customer_credit as it was: a special sale''s wallet payment is still refused' || coalesce(' (' || e || ')', ''));
  perform pg_temp.t544_check((select count(*) from special_credit_allocations) = n0
    and not exists (select 1 from special_sales where credit_funded <> 0)
    and not exists (select 1 from rentals where credit_funded <> 0),
    'W5 no special document took credit');
end $$;

-- E. What each lot may pay, as listed ------------------------------------------------------------
do $$
declare blot uuid := pg_temp.t544_id('B/lot'); olot uuid := pg_temp.t544_id('O/lot'); klot uuid := pg_temp.t544_id('P/lot');
begin
  -- The package's rules as P left them name both; back to the defaults for E3.
  delete from credit_package_spending_rules where package_id = pg_temp.t544_id('pk');
  perform pg_temp.t544_check((select allowed_categories from customer_credit_eligibility(pg_temp.t544_id('B')) where lot_id = blot)
    @> array['special_product', 'consignment_product'],
    'E1 a bundle lot lists special and consignment products');
  perform pg_temp.t544_check((select allowed_categories from customer_credit_eligibility(pg_temp.t544_id('O')) where lot_id = olot)
    @> array['special_product', 'consignment_product'],
    'E2 an other lot lists them');
  perform pg_temp.t544_check(not ((select allowed_categories from customer_credit_eligibility(pg_temp.t544_id('P')) where lot_id = klot)
    && array['special_product', 'consignment_product']),
    'E3 a package lot on the default rules lists neither');
  perform pg_temp.t544_check(credit_lot_spending_summary(blot) -> 'allowed' @> '["special_product", "consignment_product"]'::jsonb,
    'E4 the bundle''s spending summary lists both');
end $$;

-- The counts; any FAIL stops the run.
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t544_results;
do $$
begin
  if exists (select 1 from t544_results where not ok) then
    raise exception 'T544: % check(s) failed: %', (select count(*) from t544_results where not ok),
      (select string_agg(label, '; ' order by n) from t544_results where not ok);
  end if;
end $$;
rollback;
