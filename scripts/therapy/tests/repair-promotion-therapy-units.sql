-- The promotion therapy repair (scripts/therapy/repair-promotion-therapy-units.sql),
-- run against fixtures shaped as production was on 9 Oct 2026 (document and
-- unit numbers only; every name is invented):
--   UTP-0000006 on INV-2026-0160 and UTP-0000012 on INV-2026-0304, unused units
--   of promotion lines on refunded invoices, close as refunded;
--   UTP-0000002 on INV-2026-0086, a detached second unit of a promotion that
--   grants one, closes as cancelled, and UTP-0000003 on the line stays;
--   a bystander's unit is untouched; a unit that has started is refused with
--   nothing changed; a second run changes nothing. The dry run
--   (repair-promotion-therapy-units-dry-run.sql) reads the three units and
--   changes nothing.
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;

do $$
declare o uuid := gen_random_uuid(); st uuid; c uuid; c2 uuid; pm uuid; pc uuid; tpu uuid; pa uuid;
  inv uuid; n int; k text; u uuid;
begin
  insert into auth.users(id, email) values (o, 'trp-owner@tests.invalid');
  insert into profiles(id, full_name, email, role, is_active) values (o, 'TRP Owner', 'trp-owner@tests.invalid', 'owner', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name, code, country_code) values ('TRP Store', 'TRPS', 'SG') returning id into st;
  insert into customers(full_name, phone) values ('TRP Buyer', '+61491572983') returning id into c;
  insert into customers(full_name, phone) values ('TRP Other', '+61491573087') returning id into c2;
  insert into payment_methods(name, is_active) values ('TRP Cash', true) returning id into pm;
  insert into products(name, sku, product_type) values ('TRP Corset', 'TRPC', 'own') returning id into pc;
  insert into store_inventory(store_id, product_id, current_qty) values (st, pc, 100);
  perform set_product_prices(st, pc, 200, 200, 'available');
  insert into unlimited_therapy_packages(name, duration_months, is_active, entitlement_kind)
    values ('TRP 6 Months', 6, true, 'unlimited') returning id into tpu;
  insert into promotions(name, code) values ('TRP Bundle', 'TRP-A') returning id into pa;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (pa, 'product', pc, 1);
  insert into promotion_items(promotion_id, item_type, therapy_package_id, quantity) values (pa, 'therapy', tpu, 1);
  perform set_promotion_prices(pa, st, 610, 610, true);
  -- Four paid bundles: three as production had them, one a bystander's.
  foreach k in array array['INV-2026-0160', 'INV-2026-0304', 'INV-2026-0086', 'INV-2026-9086'] loop
    inv := create_invoice_with_details(st, case when k = 'INV-2026-9086' then c2 else c end,
      jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pa, 'quantity', 1)),
      jsonb_build_object('business_date', sg_today()::text));
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 610)), gen_random_uuid());
    update invoices set invoice_no = k where id = inv;
    select count(*) into n from purchased_therapy_entitlements where invoice_id = inv;
    if n <> 1 then raise exception 'Fixture: % granted % units', k, n; end if;
    update purchased_therapy_entitlements set entitlement_no = case k when 'INV-2026-0160' then 'UTP-0000006'
      when 'INV-2026-0304' then 'UTP-0000012' when 'INV-2026-0086' then 'UTP-0000003' else 'UTP-0009086' end
     where invoice_id = inv;
  end loop;
  -- Refunded the old way: the status only, the therapy left open.
  update invoices set status = 'refunded' where invoice_no in ('INV-2026-0160', 'INV-2026-0304');
  -- INV-2026-0086's detached second unit, as the old paid-invoice edit left it.
  insert into purchased_therapy_entitlements
    select (jsonb_populate_record(null::purchased_therapy_entitlements, to_jsonb(e)
              || jsonb_build_object('id', gen_random_uuid(), 'entitlement_no', 'UTP-0000002', 'invoice_item_id', null))).*
      from purchased_therapy_entitlements e where e.entitlement_no = 'UTP-0000003';
  if (select count(*) from purchased_therapy_entitlements where entitlement_no in ('UTP-0000002', 'UTP-0000003', 'UTP-0000006', 'UTP-0000012')
       and status = 'pending_activation') <> 4 then raise exception 'Fixture: the four units are not open'; end if;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ===== 1. A unit that has started: refused, nothing changed =====
savepoint trp_guard;
update purchased_therapy_entitlements set status = 'active', activation_date = sg_today(), expiry_date = sg_today() + 180
 where entitlement_no = 'UTP-0000012';
\set ON_ERROR_STOP off
\ir ../repair-promotion-therapy-units.sql
\set ON_ERROR_STOP on
rollback to savepoint trp_guard;
release savepoint trp_guard;
select set_config('trp.refused', :'LAST_ERROR_MESSAGE', true) as trp_refused \gset
do $$
begin
  if current_setting('trp.refused') not like 'UTP-0000012 is no longer an unused unit on its line; nothing was changed%' then
    raise exception 'FAIL 1: not refused as expected: %', current_setting('trp.refused'); end if;
  if exists (select 1 from purchased_therapy_entitlements where entitlement_no in ('UTP-0000002', 'UTP-0000006', 'UTP-0000012')
              and status <> 'pending_activation') then
    raise exception 'FAIL 1: a refused run closed something'; end if;
  raise notice 'PASS 1: a unit that has started is refused by number and nothing is closed';
end $$;

-- ===== 2. The dry run reads the three units and changes nothing; then the repair =====
create temp table trp_dry as select id, status, updated_at from purchased_therapy_entitlements;
\ir ../repair-promotion-therapy-units-dry-run.sql
select set_config('trp.dry_rows', :'ROW_COUNT', true) as trp_dry_rows \gset
do $$
begin
  if current_setting('trp.dry_rows') <> '3'
     or exists (select id, status, updated_at from purchased_therapy_entitlements except select * from trp_dry) then
    raise exception 'FAIL 2: the dry run did not read the three units, or changed something (% rows)', current_setting('trp.dry_rows'); end if;
end $$;
\ir ../repair-promotion-therapy-units.sql
do $$
begin
  if (select string_agg(entitlement_no || '=' || status, ' ' order by entitlement_no) from purchased_therapy_entitlements)
       <> 'UTP-0000002=cancelled UTP-0000003=pending_activation UTP-0000006=refunded UTP-0000012=refunded UTP-0009086=pending_activation' then
    raise exception 'FAIL 2: %', (select string_agg(entitlement_no || '=' || status, ' ' order by entitlement_no) from purchased_therapy_entitlements); end if;
  if (select count(*) from audit_logs where table_name = 'purchased_therapy_entitlements'
       and action in ('closed_with_invoice', 'duplicate_unit_cancelled')) <> 3 then
    raise exception 'FAIL 2: the three closures were not audited once each'; end if;
  if exists (select 1 from invoices where invoice_no like 'INV-2026-%' and status::text not in ('paid', 'refunded'))
     or (select status::text from invoices where invoice_no = 'INV-2026-0086') <> 'paid' then
    raise exception 'FAIL 2: an invoice changed'; end if;
  raise notice 'PASS 2: the dry run reads the three units and changes nothing; the repair refunds UTP-0000006 and UTP-0000012, cancels UTP-0000002, keeps UTP-0000003 and the bystander, audits each, and changes no invoice';
end $$;

-- ===== 3. Run again: nothing changes =====
create temp table trp_before as select id, status, updated_at from purchased_therapy_entitlements;
\ir ../repair-promotion-therapy-units.sql
do $$
begin
  if exists (select id, status, updated_at from purchased_therapy_entitlements except select * from trp_before)
     or (select count(*) from audit_logs where action in ('closed_with_invoice', 'duplicate_unit_cancelled')) <> 3 then
    raise exception 'FAIL 3: a second run changed something'; end if;
  raise notice 'PASS 3: a second run finds them closed and changes nothing';
end $$;

rollback;
