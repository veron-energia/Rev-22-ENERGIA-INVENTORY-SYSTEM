-- An invoice line issues its vouchers once (344).
--
-- issue_sold_vouchers_for_invoice guards itself with an unlocked
-- "if exists ... then continue", which stops a sequential replay and not two
-- settlements landing together. The database now refuses the second set
-- outright. This drives the real issuance, then attempts the duplicate the
-- race would produce.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid();
  st uuid; c uuid; pm uuid; v uuid; inv uuid; item uuid;
  v_units int; v_rows int; v_msg text;
begin
  insert into auth.users(id,email) values (own,'io-owner@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'IO Owner','io-owner@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('IO Store','IOS','SG') returning id into st;
  insert into customers(full_name,phone) values ('IO Buyer','+6591115001') returning id into c;
  insert into payment_methods(name) values ('IO Cash') returning id into pm;
  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
    values ('IO Voucher','IOV','normal','limited',60,true) returning id into v;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v,st,50);
  perform set_voucher_prices(v, st, 60, 60, true);

  -- Sell the voucher and settle, which is what issues the units.
  inv := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object(
           'kind','voucher','voucher_id',v,'quantity',2)));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',120)));

  select id into item from invoice_items where invoice_id = inv and voucher_id = v limit 1;
  if item is null then raise exception 'FIXTURE: the invoice has no voucher line'; end if;

  select count(*), coalesce(sum(quantity),0) into v_rows, v_units
    from customer_reward_vouchers
   where source_type = 'invoice_voucher_sale' and source_id = item;
  if v_rows <> 1 or v_units <> 2 then
    raise exception 'FIXTURE: expected one issuance row of 2 units, got % row(s) of %', v_rows, v_units; end if;

  -- The race: a second settlement inserting the same issuance again.
  begin
    insert into customer_reward_vouchers(customer_id, voucher_id, store_id, quantity,
                                         source_type, source_id, status)
    values (c, v, st, 2, 'invoice_voucher_sale', item, 'held');
    raise exception 'FAIL: the same invoice line issued its vouchers twice';
  exception when unique_violation then
    null;   -- exactly what should happen
  when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    raise exception 'FAIL: the duplicate was refused for the wrong reason (%)', v_msg;
  end;

  -- The customer still has what they bought, and only that.
  select coalesce(sum(quantity),0) into v_units from customer_reward_vouchers
   where source_type = 'invoice_voucher_sale' and source_id = item;
  if v_units <> 2 then
    raise exception 'FAIL: the customer now holds % units for a line of 2', v_units; end if;

  -- A different voucher on the same line is a different issuance, not a duplicate.
  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
    values ('IO Second','IOV2','normal','limited',60,true) returning id into v;
  insert into customer_reward_vouchers(customer_id, voucher_id, store_id, quantity,
                                       source_type, source_id, status)
  values (c, v, st, 1, 'invoice_voucher_sale', item, 'held');

  raise notice 'PASS: an invoice line issues each voucher once; a replay is refused and the customer keeps exactly what was bought';
end $$;
rollback;
