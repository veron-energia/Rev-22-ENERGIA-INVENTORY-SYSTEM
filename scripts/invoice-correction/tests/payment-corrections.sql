-- A correction carries its payment changes (336).
--
-- Amount, date and method corrections and removals ride in the correction's
-- header, run through the per-payment rules inside the same transaction, and
-- are described by the preview first. Money already paid out, wallet credit
-- and superseded payments are refused before the save, not after.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); staff_id uuid:=gen_random_uuid(); st uuid; buyer uuid; refr uuid; affr uuid;
 cash uuid; bank uuid; wallet uuid; prod uuid; inv uuid; it uuid; items jsonb; r jsonb; req uuid;
 pay_cash uuid; pay_bank uuid; pay_wallet uuid; repl uuid; n int; fin jsonb; before_rows int;
begin
 insert into auth.users(id,email) values(own,'pcf-owner@tests.invalid'),(staff_id,'pcf-staff@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'PCF Owner','pcf-owner@tests.invalid','owner'),(staff_id,'PCF Staff','pcf-staff@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PCF Store','PCF','SG') returning id into st;
 insert into customers(full_name,phone) values('PCF Referrer','+6598938000') returning id into refr;
 insert into customers(full_name,phone,referred_by) values('PCF Buyer','+6598938001',refr) returning id into buyer;
 insert into customer_affiliates(customer_id,status,store_id,activated_at) values(refr,'active',st,now()) returning id into affr;
 insert into payment_methods(name) values('PCF Cash') returning id into cash;
 insert into payment_methods(name) values('PCF Bank') returning id into bank;
 insert into payment_methods(name,is_wallet_credit) values('PCF Wallet',true) returning id into wallet;
 insert into products(name,sku,product_type) values('PCF Item','PCF-1','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,50);
 perform set_product_prices(st,prod,100,100,'available');

 -- 100 paid as 60 cash + 40 bank.
 inv:=create_invoice(st,buyer,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',60),jsonb_build_object('payment_method_id',bank,'amount',40)));
 select id into it from invoice_items where invoice_id=inv;
 items:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1));
 select id into pay_cash from invoice_payments where invoice_id=inv and payment_method_id=cash;
 select id into pay_bank from invoice_payments where invoice_id=inv and payment_method_id=bank;
 if (select status from invoices where id=inv)<>'paid' then raise exception 'FIXTURE: not paid'; end if;
 if (select count(*) from commissions where invoice_id=inv and status='earned')=0 then raise exception 'FIXTURE: no commission'; end if;

 -- ---- the preview describes both changes and the consequence ------------
 r:=preview_invoice_correction(inv,jsonb_build_object(
   'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_cash,'amount',50,'date','2026-09-10','payment_method_id',bank)),
   'payment_removals',jsonb_build_array(pay_bank)));
 if (r->>'blocking')::boolean then raise exception 'FAIL: a valid payment change is blocked: %', r->'needs_review'; end if;
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'area'='payments' and e->>'change'='corrected'
                  and e->>'from' like 'PCF Cash S$60.00 on %' and e->>'to' like 'PCF Bank S$50.00 on 10 Sep 2026') then
  raise exception 'FAIL: the corrected payment is not described: %', r->'effects'; end if;
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'area'='payments' and e->>'change'='removed' and e->>'from' like 'PCF Bank S$40.00 on %') then
  raise exception 'FAIL: the removed payment is not described: %', r->'effects'; end if;
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'area'='payments' and e->>'change'='partially paid' and e->>'detail' like 'Payments will total S$50.00 of S$100.00%S$50.00 outstanding%') then
  raise exception 'FAIL: the consequence is not stated: %', r->'effects'; end if;

 -- ---- and the save does exactly that, in one transaction ----------------
 req:=gen_random_uuid();
 r:=correct_invoice(inv,items,jsonb_build_object('expected_edit_count',0,
   'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_cash,'amount',50,'date','2026-09-10','payment_method_id',bank)),
   'payment_removals',jsonb_build_array(pay_bank)),'Keyed the wrong amounts',req);
 if coalesce((r->>'unchanged')::boolean,false) then raise exception 'FAIL: a payments-only save was treated as a no-op'; end if;
 if (select status from invoices where id=inv)<>'partially_paid' or (select paid_amount from invoices where id=inv)<>50 then
  raise exception 'FAIL: paid amount/status after the save: % %', (select status from invoices where id=inv), (select paid_amount from invoices where id=inv); end if;
 -- 2 receipts kept, 2 reversals, 1 replacement of 50 by bank on the given date.
 select count(*) into n from invoice_payments where invoice_id=inv and entry_kind='receipt'; if n<>2 then raise exception 'FAIL: receipts rewritten (%)', n; end if;
 select count(*) into n from invoice_payments where invoice_id=inv and entry_kind='correction_reversal'; if n<>2 then raise exception 'FAIL: reversals (%)', n; end if;
 select id into repl from invoice_payments where invoice_id=inv and entry_kind='correction_replacement';
 if (select amount from invoice_payments where id=repl)<>50 or (select payment_method_id from invoice_payments where id=repl)<>bank
    or (select (effective_at at time zone 'Asia/Singapore')::date from invoice_payments where id=repl)<>'2026-09-10' then
  raise exception 'FAIL: the replacement does not carry the corrected details'; end if;
 if not exists (select 1 from invoice_payments where invoice_id=inv and entry_kind='correction_reversal' and corrects_payment_id=pay_bank and correction_reason='Keyed the wrong amounts') then
  raise exception 'FAIL: the removal is not a reversal with the reason'; end if;
 if exists (select 1 from invoice_payments where invoice_id=inv and entry_kind='correction_replacement' and corrects_payment_id=pay_bank) then
  raise exception 'FAIL: a removal must not write a replacement'; end if;
 if exists (select 1 from invoice_refunds where invoice_id=inv) then raise exception 'FAIL: a correction recorded a refund'; end if;
 if not exists (select 1 from audit_logs where action='payment_corrected' and record_id=pay_cash) or not exists (select 1 from audit_logs where action='payment_removed' and record_id=pay_bank) then
  raise exception 'FAIL: audit rows for the two payment changes'; end if;
 if not exists (select 1 from invoice_revisions where invoice_id=inv and edit_reason='Keyed the wrong amounts') then raise exception 'FAIL: no revision'; end if;
 -- Commission followed the invoice through its reconciliation, and money is reported on the corrected date.
 if (select count(*) from commissions where invoice_id=inv and status='earned')=0 then raise exception 'FAIL: commission not re-earned'; end if;
 if invoice_net_sales_between(inv,'2026-09-10','2026-09-10')<>50 then raise exception 'FAIL: the corrected receipt date is not what reports use'; end if;
 fin:=invoice_financial_position(inv);
 if (fin->>'outstanding')::numeric<>50 or (fin->>'refund_due')::numeric<>0 then raise exception 'FAIL: financial position %', fin; end if;

 -- ---- the same request again writes nothing -------------------------------
 select count(*) into before_rows from invoice_payments where invoice_id=inv;
 r:=correct_invoice(inv,items,jsonb_build_object('expected_edit_count',0,
   'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_cash,'amount',50,'date','2026-09-10','payment_method_id',bank)),
   'payment_removals',jsonb_build_array(pay_bank)),'Keyed the wrong amounts',req);
 if not coalesce((r->>'replayed')::boolean,false) then raise exception 'FAIL: replay not detected'; end if;
 if (select count(*) from invoice_payments where invoice_id=inv)<>before_rows then raise exception 'FAIL: replay wrote payment rows'; end if;

 -- ---- a superseded payment cannot be corrected twice ----------------------
 r:=preview_invoice_correction(inv,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_cash,'amount',55,'date','2026-09-10','payment_method_id',bank))));
 if not (r->>'blocking')::boolean or not exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%already corrected%') then
  raise exception 'FAIL: preview does not stop a second correction of the original: %', r->'needs_review'; end if;
 begin
  perform correct_invoice(inv,items,jsonb_build_object('expected_edit_count',1,
    'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_cash,'amount',55,'date','2026-09-10','payment_method_id',bank))),'Again',gen_random_uuid());
  raise exception 'FAIL: the original was corrected a second time';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%current replacement%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;

 -- ---- correcting the replacement above the total: paid, refund due ------
 r:=preview_invoice_correction(inv,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',repl,'amount',120,'date','2026-09-10','payment_method_id',bank))));
 if (r->>'blocking')::boolean or not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'change'='still paid' and e->>'detail' like '%S$120.00 against a total of S$100.00%S$20.00 is shown as refund due%') then
  raise exception 'FAIL: overpayment consequence: %', r; end if;
 perform correct_invoice(inv,items,jsonb_build_object('expected_edit_count',1,
   'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',repl,'amount',120,'date','2026-09-10','payment_method_id',bank))),'Actually paid more',gen_random_uuid());
 fin:=invoice_financial_position(inv);
 if (select status from invoices where id=inv)<>'paid' or (fin->>'refund_due')::numeric<>20 then raise exception 'FAIL: overpayment not reflected: % %', (select status from invoices where id=inv), fin; end if;

 -- ---- what is refused, before and at the save ----------------------------
 select id into repl from invoice_payments where invoice_id=inv and entry_kind='correction_replacement' and amount=120;
 r:=preview_invoice_correction(inv,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',repl,'amount',0,'date','2026-09-10','payment_method_id',bank))));
 if not (r->>'blocking')::boolean or not exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%positive corrected amount%') then
  raise exception 'FAIL: zero amount not stopped by the preview'; end if;
 begin
  perform correct_invoice(inv,items,jsonb_build_object('expected_edit_count',2,
    'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',repl,'amount',0,'date','2026-09-10','payment_method_id',bank))),'Zero',gen_random_uuid());
  raise exception 'FAIL: a zero amount was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%positive corrected amount%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 -- ---- a method-only change still goes in place, with no reversal ---------
 select count(*) into before_rows from invoice_payments where invoice_id=inv;
 perform correct_invoice(inv,items,jsonb_build_object('expected_edit_count',2,
   'payment_methods',jsonb_build_array(jsonb_build_object('payment_id',repl,'payment_method_id',cash))),'Was cash',gen_random_uuid());
 if (select payment_method_id from invoice_payments where id=repl)<>cash then raise exception 'FAIL: method-only change not applied'; end if;
 if (select count(*) from invoice_payments where invoice_id=inv)<>before_rows then raise exception 'FAIL: a method-only change wrote payment rows'; end if;

 -- ---- nothing to do is still nothing to do -------------------------------
 r:=correct_invoice(inv,items,jsonb_build_object('expected_edit_count',3,'payment_corrections','[]'::jsonb,'payment_removals','[]'::jsonb,'payment_methods','[]'::jsonb),'Nothing',gen_random_uuid());
 if not coalesce((r->>'unchanged')::boolean,false) then raise exception 'FAIL: empty payment arrays are not a no-op'; end if;

 -- ---- removing the last payment: unpaid, and staff cannot ---------------
 r:=preview_invoice_correction(inv,jsonb_build_object('payment_removals',jsonb_build_array(repl)));
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'change'='unpaid' and e->>'detail' like 'No payment is left%') then
  raise exception 'FAIL: unpaid consequence: %', r->'effects'; end if;
 perform set_config('request.jwt.claim.sub',staff_id::text,true);
 begin
  perform remove_invoice_payment(repl,'Staff try',gen_random_uuid());
  raise exception 'FAIL: staff removed a payment';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%Owner or Manager%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform correct_invoice(inv,items,jsonb_build_object('expected_edit_count',3,'payment_removals',jsonb_build_array(repl)),'Never paid',gen_random_uuid());
 if (select status from invoices where id=inv)<>'unpaid' or (select paid_amount from invoices where id=inv)<>0 then
  raise exception 'FAIL: removing the last payment: % %', (select status from invoices where id=inv), (select paid_amount from invoices where id=inv); end if;
 if has_function_privilege('anon','public.remove_invoice_payment(uuid,text,uuid)','execute') then raise exception 'FAIL: anonymous can remove payments'; end if;

 -- ---- a wallet-credit payment: refused here in both directions ----------
 -- (last, and never deleted: the lock on a settled invoice's payments holds)
 insert into invoice_payments(invoice_id,payment_method_id,amount,received_by) values(inv,wallet,10,own) returning id into pay_wallet;
 r:=preview_invoice_correction(inv,jsonb_build_object('payment_removals',jsonb_build_array(pay_wallet)));
 if not (r->>'blocking')::boolean or not exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%wallet credit%') then
  raise exception 'FAIL: wallet removal not stopped by the preview: %', r->'needs_review'; end if;
 begin
  perform remove_invoice_payment(pay_wallet,'Mistake',gen_random_uuid());
  raise exception 'FAIL: a wallet payment was removed';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%wallet credit%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;


 raise notice 'PASS: a correction carries payment amount, date and method changes and removals through the per-payment rules in one transaction; the preview describes each change and the invoice''s state afterwards; superseded, zero, wallet and staff attempts are refused before and at the save; replay and no-op are still detected';
end $$;
rollback;
