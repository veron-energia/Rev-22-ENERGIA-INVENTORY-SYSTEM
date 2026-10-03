-- The seven-argument create_invoice is dropped (386).
--
--   C1 The overload installed below is production's, byte for byte (the md5
--      386 guards on), granted to staff and not to anon, as it was.
--   C2 Beside the eight-argument create_invoice no call reaches it: four or
--      seven arguments, by position or by name, are refused as ambiguous.
--   C3 386 refuses a version of it that is not production's, and changes
--      nothing then.
--   C4 386 drops it, and only it: every other public function keeps its body
--      and its grants, and one create_invoice is left.
--   C5 A call with four or seven arguments now reaches the eight-argument
--      function.
--   C6 Running 386 again changes nothing.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Works whether or not the database already has
-- 386: the old overload is installed after "begin;" either way.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
-- Every public function as signature, body and grants.
create function pg_temp.fns() returns table(fn text, h text) language sql as
$$ select p.oid::regprocedure::text, md5(p.prosrc) || ':' || coalesce(p.proacl::text, '')
     from pg_proc p where p.pronamespace = 'public'::regnamespace $$;
-- The SQLSTATE and message a call ends with ('' when it returns).
create function pg_temp.outcome(sql text) returns text language plpgsql as
$$begin execute sql; return '';
exception when others then return sqlstate || ' ' || sqlerrm; end$$;

-- Production's create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid), read
-- 3 Oct 2026, with its grants.
create or replace function public.create_invoice(p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid, p_items jsonb, p_discount_total numeric default 0, p_notes text default null::text, p_discount_voucher_id uuid default null::uuid)
returns uuid language plpgsql security definer set search_path = public as $legacy$
declare
  v_gross numeric;
  v_sel jsonb;
  v_pj jsonb;
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_discount numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
begin
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;

    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;
      v_price := v_promo.fixed_price;
    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers
        where id = v_voucher_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'Voucher not found or inactive'; end if;
    elsif v_kind = 'credit_package' then
      if v_qty <> 1 then raise exception 'A credit package line must have quantity 1'; end if;
      if coalesce(nullif(v_item->>'foc_quantity','')::integer, 0) > 0
         or coalesce(nullif(v_item->>'is_foc','')::boolean, false) then
        raise exception 'A credit package cannot be made FOC when the invoice is created. Save the invoice and use Make FOC, or give a manual discount.'; end if;
      if nullif(v_item->>'line_voucher_id','') is not null then
        raise exception 'A line voucher cannot discount a credit package. Use a manual discount or an invoice discount voucher.'; end if;
      v_product_id := (v_item->>'credit_package_id')::uuid;
      if not exists (select 1 from public.credit_packages where id = v_product_id and deleted_at is null) then
        raise exception 'Credit package not found'; end if;
      if not exists (select 1 from public.credit_packages_for_store(p_store_id) x where x.id = v_product_id) then
        raise exception 'Credit package "%" is not available at this store',
          (select name from public.credit_packages where id = v_product_id); end if;
      select customer_price into v_price from public.credit_packages where id = v_product_id;
      v_gross := v_price * v_qty;

    elsif v_kind = 'premium_bundle' then
      if v_qty <> 1 then raise exception 'A premium bundle line must have quantity 1'; end if;
      if coalesce(nullif(v_item->>'foc_quantity','')::integer, 0) > 0
         or coalesce(nullif(v_item->>'is_foc','')::boolean, false) then
        raise exception 'A premium bundle cannot be made FOC when the invoice is created. Save the invoice and use Make FOC, or give a manual discount.'; end if;
      if nullif(v_item->>'line_voucher_id','') is not null then
        raise exception 'A line voucher cannot discount a premium bundle. Use a manual discount or an invoice discount voucher.'; end if;
      v_product_id := (v_item->>'premium_bundle_id')::uuid;
      if not exists (select 1 from public.premium_bundles where id = v_product_id and deleted_at is null) then
        raise exception 'Premium bundle not found'; end if;
      if not exists (select 1 from public.premium_bundles_for_store(p_store_id) x where x.id = v_product_id) then
        raise exception 'Premium bundle "%" is not available at this store',
          (select name from public.premium_bundles where id = v_product_id); end if;
      v_sel := coalesce(v_item->'voucher_selection', '[]'::jsonb);
      v_pj := public.validate_bundle_voucher_selection(v_product_id, p_store_id, v_sel);
      if (v_pj->>'selected_qty')::int > (v_pj->>'required_qty')::int then
        raise exception 'That is more reward voucher(s) than the allowance of % for "%" — % chosen',
          v_pj->>'required_qty',
          (select name from public.premium_bundles where id = v_product_id),
          v_pj->>'selected_qty'; end if;
      if not (v_pj->>'stock_ok')::boolean then
        raise exception 'Not enough voucher stock for "%": %',
          (select name from public.premium_bundles where id = v_product_id),
          array_to_string(array(select jsonb_array_elements_text(v_pj->'shortages')), '; '); end if;
      select customer_payment_amount into v_price from public.premium_bundles where id = v_product_id;
      v_gross := v_price * v_qty;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'No price set for a product in this store'; end if;
    end if;
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  -- Spec rule: discount vouchers can never be used on bundle invoices.
  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'Discount vouchers cannot be used on an invoice that contains a promotion/bundle';
  end if;

  if p_discount_voucher_id is not null then
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_subtotal - v_discount);
  end if;
  if v_discount > v_subtotal then v_discount := v_subtotal; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, total_amount, paid_amount, notes, discount_voucher_id)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id)
  returning id into v_invoice_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select fixed_price into v_price from public.promotions where id = v_promo_id;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, v_line_total);
    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers where id = v_voucher_id;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_line_total);
    elsif v_kind = 'credit_package' then
      v_product_id := (v_item->>'credit_package_id')::uuid;
      select customer_price into v_price from public.credit_packages where id = v_product_id;
      v_line_total := round(v_price * v_qty, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id,
         store_id_snapshot, original_price, credit_package_id,
         credit_paid_snapshot, credit_voucher_qty_snapshot, plan_name_snapshot)
      select v_invoice_id, 'credit_package'::public.invoice_line_kind, 1, v_price, v_line_total, 'credit_package', v_product_id,
             p_store_id, v_price, v_product_id, pk.paid_credit_amount, null, pk.name
        from public.credit_packages pk where pk.id = v_product_id;

    elsif v_kind = 'premium_bundle' then
      v_product_id := (v_item->>'premium_bundle_id')::uuid;
      v_sel := coalesce(v_item->'voucher_selection', '[]'::jsonb);
      select customer_payment_amount into v_price from public.premium_bundles where id = v_product_id;
      v_line_total := round(v_price * v_qty, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id,
         store_id_snapshot, original_price, premium_bundle_id,
         credit_paid_snapshot, credit_bonus_snapshot, credit_voucher_qty_snapshot,
         bundle_voucher_selection, plan_name_snapshot)
      select v_invoice_id, 'premium_bundle'::public.invoice_line_kind, 1, v_price, v_line_total, 'premium_bundle', v_product_id,
             p_store_id, v_price, v_product_id, b.paid_credit_amount, b.bonus_credit_amount,
             b.free_voucher_qty, v_sel, b.name
        from public.premium_bundles b where b.id = v_product_id;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'discount_voucher', p_discount_voucher_id));
  return v_invoice_id;
end; $legacy$;
revoke all on function public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid) from public;
grant execute on function public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid) to authenticated, service_role;

select pg_temp.check(
  (select md5(prosrc) from pg_proc where oid = 'public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)'::regprocedure)
    = 'b1d529eae8a5445b3311fcd9a07af903'
  and has_function_privilege('authenticated', 'public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)', 'execute'),
  'C1 the old create_invoice is production''s, callable by staff and not by anon');

create temp table calls(k text primary key, sql text);
insert into calls values
  ('four', $c$select public.create_invoice(gen_random_uuid(), null::uuid, null::uuid, '[{"kind":"product","quantity":1}]'::jsonb)$c$),
  ('seven', $c$select public.create_invoice(gen_random_uuid(), null::uuid, null::uuid, '[{"kind":"product","quantity":1}]'::jsonb, 5::numeric, null::text, null::uuid)$c$),
  ('named', $c$select public.create_invoice(p_store_id => gen_random_uuid(), p_customer_id => null, p_affiliate_id => null,
     p_items => '[{"kind":"product","quantity":1}]'::jsonb, p_discount_total => 5, p_notes => null, p_discount_voucher_id => null)$c$);

select pg_temp.check(
  (select bool_and(pg_temp.outcome(sql) like '42725 function public.create_invoice(%) is not unique') from calls)
  and to_regproc('public.create_invoice') is null,
  'C2 beside the eight-argument one, no call with four or seven arguments, by position or by name, reaches it');

create temp table before386 as select * from pg_temp.fns();

-- C3: a version that is not production's.
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
savepoint c3;
do $$begin execute regexp_replace(pg_get_functiondef('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)'::regprocedure),
  '\$function\$\s*$', E'-- changed\n$function$'); end$$;
\echo 'C3: the ERROR below is expected (386 refusing a changed create_invoice)'
\ir ../../../supabase/386_drop_legacy_create_invoice_overload.sql
\set c3_error :LAST_ERROR_MESSAGE
select count(*) = 2 as c3_both from pg_proc where pronamespace = 'public'::regnamespace and proname = 'create_invoice' \gset
rollback to savepoint c3;
release savepoint c3;
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP on
select pg_temp.check(:'c3_error' like '386: create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid) is not the version this was tested against (md5 %)'
    and :'c3_both',
  'C3 386 refuses a create_invoice that is not production''s, and leaves both');

-- C4: the real thing.
set client_min_messages = warning;
\ir ../../../supabase/386_drop_legacy_create_invoice_overload.sql
reset client_min_messages;
select pg_temp.check(
  to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)') is null
  and (select array_agg(fn) from (select fn, h from before386 except select fn, h from pg_temp.fns()) gone)
      = array['create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)']
  and not exists (select fn, h from pg_temp.fns() except select fn, h from before386)
  and to_regproc('public.create_invoice')::oid = 'public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)'::regprocedure::oid,
  'C4 386 drops the old create_invoice and nothing else: every other public function keeps its body and grants, and one create_invoice is left');

select pg_temp.check(
  (select bool_and(pg_temp.outcome(sql) not like '42725 %' and pg_temp.outcome(sql) not like '42883 %') from calls),
  'C5 a call with four or seven arguments, by position or by name, now reaches the eight-argument create_invoice');

create temp table after386 as select * from pg_temp.fns();
set client_min_messages = warning;
\ir ../../../supabase/386_drop_legacy_create_invoice_overload.sql
reset client_min_messages;
select pg_temp.check(
  not exists ((select * from after386 except select * from pg_temp.fns())
              union all (select * from pg_temp.fns() except select * from after386)),
  'C6 running 386 again changes nothing');

do $$ begin
  if exists (select 1 from failed) then
    raise exception 'FAIL: % check(s) failed: %', (select count(*) from failed), (select string_agg(msg, ' | ' order by n) from failed); end if;
  raise notice 'ALL PASS: the seven-argument create_invoice is dropped (386)';
end $$;
rollback;
