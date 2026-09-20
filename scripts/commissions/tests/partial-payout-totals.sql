-- "Paid Out" is the money that left, not the commissions ticked off.
--
-- affiliate_payout_save allocates least(remaining, available) and then sets the
-- whole commission row to 'paid'. So after a part payment the commission reads
-- as paid while most of it is still owed. The Reports page summed
-- commission_amount for every row whose status was 'paid' and therefore showed
-- the full amount as paid out — disagreeing with the Commissions page and the
-- payout panel, which both read the payout records.
--
-- This asserts the invariant the Reports page now relies on: after a part
-- payment, report_affiliates().paid is the cash, and it is less than the
-- commission that the status calls paid.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid();
  st uuid; ref uuid; buyer uuid; pm uuid; prod uuid; inv uuid;
  v_earned numeric; v_paid numeric; v_status_paid numeric; v_reported_paid numeric;
  v_part numeric;
begin
  insert into auth.users(id,email) values (own,'pp-owner@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'PP Owner','pp-owner@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name,code,country_code) values ('PP Store','PPS','SG') returning id into st;
  insert into payment_methods(name) values ('PP Cash') returning id into pm;
  insert into customers(full_name,phone) values ('PP Referrer','+6591116001') returning id into ref;
  insert into customer_affiliates(customer_id, store_id, status, activated_at)
    values (ref, st, 'active', now());
  insert into customers(full_name,phone,referred_by) values ('PP Buyer','+6591116002',ref) returning id into buyer;

  insert into products(name,sku) values ('PP Item','PP-1') returning id into prod;
  insert into store_inventory(store_id,product_id,current_qty) values (st,prod,100);
  perform set_product_prices(st, prod, 1000, 1000, 'available');

  inv := create_invoice(st, buyer, null, jsonb_build_array(jsonb_build_object(
           'kind','product','product_id',prod,'quantity',1)));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)));

  select coalesce(sum(commission_amount),0) into v_earned
    from commissions where referrer_customer_id = ref and status in ('earned','paid');
  if v_earned <= 0 then
    raise exception 'FIXTURE: the paid invoice earned no commission for the referrer'; end if;

  -- Pay a fifth of it, which is what a part payment looks like.
  v_part := round(v_earned / 5, 2);
  perform public.affiliate_payout_save(
    null, null, ref, date_trunc('month', current_date)::date, v_part, pm, current_date,
    'PP-REF', 'part payment', 'testing part payments', gen_random_uuid());

  -- What the status says, which is what the report used to sum.
  select coalesce(sum(commission_amount),0) into v_status_paid
    from commissions where referrer_customer_id = ref and status = 'paid';
  -- What actually left, which is what the report now shows.
  select coalesce(paid,0) into v_reported_paid
    from report_affiliates() where customer_id = ref;

  if v_status_paid <= v_part then
    raise exception 'FIXTURE: this part payment did not mark more commission paid than it settled (status %, paid %)',
      v_status_paid, v_part; end if;

  if v_reported_paid <> v_part then
    raise exception 'FAIL: report_affiliates() says % was paid out; the payment was %',
      v_reported_paid, v_part; end if;

  if v_reported_paid >= v_status_paid then
    raise exception 'FAIL: the reported payout (%) is not less than the commission the status calls paid (%)',
      v_reported_paid, v_status_paid; end if;

  raise notice 'PASS: a part payment of % marks % of commission as paid, and the report shows % — the cash, not the ticked-off rows',
    v_part, v_status_paid, v_reported_paid;
end $$;
rollback;
