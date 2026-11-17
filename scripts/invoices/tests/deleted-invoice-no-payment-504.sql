-- A deleted invoice takes no payment (504).
--
-- delete_invoice only sets deleted_at and leaves the status unpaid, and
-- recording a payment never looked at deleted_at. This raises an invoice,
-- deletes it and tries to pay it; the payment must be refused and nothing may
-- move. A second invoice, not deleted, is paid as before. The backstop trigger
-- refuses a receipt written straight into invoice_payments on a deleted
-- invoice, and still lets a payment that reached a deleted invoice before 504
-- be corrected, split and removed (the repair for those invoices).
--
--   sh scripts/invoices/local-sql.sh -f scripts/invoices/tests/deleted-invoice-no-payment-504.sql
-- 504 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (D504, @example.invalid, the fictional +6149157xxxx).
\set ON_ERROR_STOP on
begin;
select position('504:' in pg_get_functiondef('public.invoice_record_payments_internal(uuid,jsonb)'::regprocedure)) > 0
   and to_regprocedure('public.trg_invoice_payment_not_on_deleted_invoice()') is not null as m504_in \gset
\if :m504_in
\else
\ir ../../../supabase/504_a_deleted_invoice_takes_no_payment.sql
\endif
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; cust uuid; prod uuid; inv1 uuid; inv2 uuid; inv3 uuid; pm uuid; pay uuid; v_msg text;
begin
  insert into auth.users(id, email, email_confirmed_at) values (own, 'd504-owner@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values (own, 'D504 Owner', 'd504-owner@example.invalid', 'owner', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('D504 Store', 'D504', 'SG') returning id into st;
  insert into public.customers(full_name, phone) values ('D504 Customer', '+61491578504') returning id into cust;
  insert into public.products(name, sku) values ('D504 Item', 'D504-1') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, prod, 10);
  perform public.set_product_prices(st, prod, 50, 50, 'available');
  select id into pm from public.payment_methods
   where is_active and deleted_at is null and not coalesce(is_wallet_credit, false) order by name limit 1;
  if pm is null then insert into public.payment_methods(name) values ('D504 Cash') returning id into pm; end if;

  inv1 := public.create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
  inv2 := public.create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
  inv3 := public.create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));

  -- 1. deleted, then paid: refused, and nothing moves
  perform public.delete_invoice(inv1, 'D504 check');
  begin
    perform public.record_invoice_settlement(inv1, jsonb_build_object('receipts', jsonb_build_array(
      jsonb_build_object('key','r1','payment_method_id',pm,'amount',(select total_amount from public.invoices where id = inv1)))), gen_random_uuid());
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm; end;
  perform pg_temp.check(v_msg = 'This invoice was deleted, so it cannot take a payment.',
    '1 a payment on a deleted invoice is refused with its own message: ' || v_msg);
  perform pg_temp.check((select status::text = 'unpaid' and deleted_at is not null and coalesce(paid_amount, 0) = 0 from public.invoices where id = inv1)
    and not exists (select 1 from public.invoice_payments where invoice_id = inv1)
    and (select current_qty from public.store_inventory where store_id = st and product_id = prod) = 10,
    '1 the deleted invoice stays unpaid, has no payment row and took no stock');

  -- 2. an invoice that was not deleted is paid as before
  perform public.record_invoice_settlement(inv2, jsonb_build_object('receipts', jsonb_build_array(
    jsonb_build_object('key','r1','payment_method_id',pm,'amount',(select total_amount from public.invoices where id = inv2)))), gen_random_uuid());
  perform pg_temp.check((select status::text = 'paid' from public.invoices where id = inv2)
    and (select current_qty from public.store_inventory where store_id = st and product_id = prod) = 9,
    '2 an invoice that was not deleted is paid and takes its stock');

  -- 3. the backstop: a receipt written straight into invoice_payments on a deleted invoice
  begin
    insert into public.invoice_payments(invoice_id, payment_method_id, amount, received_by) values (inv1, pm, 1, own);
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm; end;
  perform pg_temp.check(v_msg = 'This invoice was deleted, so it cannot take a payment.',
    '3 the trigger refuses a receipt written straight into invoice_payments on a deleted invoice: ' || v_msg);
  perform pg_temp.check(not exists (select 1 from public.invoice_payments where invoice_id = inv1), '3 and nothing was written');

  -- 4. an invoice paid and deleted before 504 (deleted_at set by hand here, as no route
  --    deletes a paid invoice now) can still be put right: correct, split, remove
  perform public.record_invoice_settlement(inv3, jsonb_build_object('receipts', jsonb_build_array(
    jsonb_build_object('key','r1','payment_method_id',pm,'amount',(select total_amount from public.invoices where id = inv3)))), gen_random_uuid());
  update public.invoices set deleted_at = now() where id = inv3;
  select id into pay from public.invoice_payments where invoice_id = inv3 and entry_kind = 'receipt';
  perform public.correct_invoice_payment(pay, (select amount from public.invoice_payments where id = pay), public.sg_today(), pm, 'D504 correction', gen_random_uuid());
  perform pg_temp.check((select count(*) from public.invoice_payments where invoice_id = inv3 and entry_kind in ('correction_reversal','correction_replacement')) = 2,
    '4 a payment on a deleted invoice can be corrected (reversal and replacement written)');
  select id into pay from public.invoice_payments where invoice_id = inv3 and entry_kind = 'correction_replacement';
  perform public.split_invoice_payment(pay, jsonb_build_array(
    jsonb_build_object('payment_method_id', pm, 'amount', 20, 'date', public.sg_today()),
    jsonb_build_object('payment_method_id', pm, 'amount', (select amount from public.invoice_payments where id = pay) - 20, 'date', public.sg_today())),
    'D504 split', gen_random_uuid());
  perform pg_temp.check((select count(*) from public.invoice_payments where invoice_id = inv3 and entry_kind = 'correction_replacement') = 3,
    '4 it can be split (two more replacement rows)');
  select id into pay from public.invoice_payments p where invoice_id = inv3 and entry_kind = 'correction_replacement' and amount = 20
     and not exists (select 1 from public.invoice_payments r where r.corrects_payment_id = p.id and r.entry_kind = 'correction_reversal');
  perform public.remove_invoice_payment(pay, 'D504 removal', gen_random_uuid());
  perform pg_temp.check(exists (select 1 from public.invoice_payments where corrects_payment_id = pay and entry_kind = 'correction_reversal'),
    '4 and a part can be removed (reversal written)');
  perform pg_temp.check((select count(*) from public.invoice_payments where invoice_id = inv3 and entry_kind = 'receipt') = 1,
    '4 no new receipt reached the deleted invoice');
end $$;
rollback;
