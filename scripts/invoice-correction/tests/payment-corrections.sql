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
 paynow uuid; inv2 uuid; it2 uuid; items2 jsonb; pay_c uuid; part_pn uuid; part_cash uuid; req2 uuid;
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
 insert into payment_methods(name) values('PCF PayNow') returning id into paynow;
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

 -- an invoice that is already partially paid "stays" so; it does not "go back"
 r:=preview_invoice_correction(inv,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',repl,'amount',40,'date','2026-09-10','payment_method_id',bank))));
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'change'='partially paid' and e->>'detail' like 'Payments will total S$40.00 of S$100.00: the invoice stays partially paid with S$60.00 outstanding%') then
  raise exception 'FAIL: partially-paid wording: %', r->'effects'; end if;

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



 -- ================================================================
 -- 337: one payment, several methods. A second invoice: 100 keyed as
 -- cash, really 60 by PayNow and 40 in cash.
 -- ================================================================
 perform set_config('request.jwt.claim.sub',own::text,true);
 inv2:=create_invoice(st,buyer,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
 perform pay_invoice(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',100)));
 select id into it2 from invoice_items where invoice_id=inv2;
 items2:=jsonb_build_array(jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',prod,'quantity',1));
 select id into pay_c from invoice_payments where invoice_id=inv2;

 -- the preview describes the split and the unchanged consequence
 r:=preview_invoice_correction(inv2,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_c,'parts',
   jsonb_build_array(jsonb_build_object('amount',60,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',40,'date','2026-09-10','payment_method_id',cash))))));
 if (r->>'blocking')::boolean then raise exception 'FAIL: a valid split is blocked: %', r->'needs_review'; end if;
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'change'='split' and e->>'from' like 'PCF Cash S$100.00 on %'
                  and e->>'to'='PCF PayNow S$60.00 on 10 Sep 2026 + PCF Cash S$40.00 on 10 Sep 2026' and e->>'detail' like '%2 replacements totalling S$100.00%') then
  raise exception 'FAIL: the split is not described: %', r->'effects'; end if;
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'change'='still paid' and e->>'detail' like 'Payments will total S$100.00, which still settles%') then
  raise exception 'FAIL: split consequence: %', r->'effects'; end if;

 -- the save: one reversal, two replacements of the same receipt, nothing else changes
 req2:=gen_random_uuid();
 r:=correct_invoice(inv2,items2,jsonb_build_object('expected_edit_count',0,'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_c,'parts',
   jsonb_build_array(jsonb_build_object('amount',60,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',40,'date','2026-09-10','payment_method_id',cash))))),'Really PayNow and cash',req2);
 if coalesce((r->>'unchanged')::boolean,false) then raise exception 'FAIL: a split was treated as a no-op'; end if;
 if (select status from invoices where id=inv2)<>'paid' or (select paid_amount from invoices where id=inv2)<>100 then
  raise exception 'FAIL: split changed the invoice''s money: % %', (select status from invoices where id=inv2), (select paid_amount from invoices where id=inv2); end if;
 if (select count(*) from invoice_payments where invoice_id=inv2 and entry_kind='correction_reversal' and corrects_payment_id=pay_c)<>1 then raise exception 'FAIL: one reversal expected'; end if;
 select id into part_pn from invoice_payments where invoice_id=inv2 and entry_kind='correction_replacement' and corrects_payment_id=pay_c and payment_method_id=paynow and amount=60;
 select id into part_cash from invoice_payments where invoice_id=inv2 and entry_kind='correction_replacement' and corrects_payment_id=pay_c and payment_method_id=cash and amount=40;
 if part_pn is null or part_cash is null then raise exception 'FAIL: the two parts were not recorded as replacements of the receipt'; end if;
 -- the reversal carries the correction's derived request id; each part carries its own, derived from that
 if (select correction_request_id from invoice_payments where invoice_id=inv2 and entry_kind='correction_reversal' and corrects_payment_id=pay_c)<>md5(req2::text||'/split/'||pay_c::text)::uuid then
  raise exception 'FAIL: the split reversal does not carry the correction''s request id'; end if;
 if (select count(distinct correction_request_id) from invoice_payments where invoice_id=inv2 and corrects_payment_id=pay_c)<>3 then
  raise exception 'FAIL: the split rows must each carry a request id of their own'; end if;
 if (select (effective_at at time zone 'Asia/Singapore')::date from invoice_payments where id=part_pn)<>'2026-09-10' then raise exception 'FAIL: part date'; end if;
 if not exists (select 1 from audit_logs where action='payment_split' and record_id=pay_c) then raise exception 'FAIL: no payment_split audit row'; end if;
 if exists (select 1 from invoice_refunds where invoice_id=inv2) then raise exception 'FAIL: a split recorded a refund'; end if;
 if invoice_net_sales_between(inv2,'2026-09-10','2026-09-10')<>100 then raise exception 'FAIL: split parts are not reported on their date'; end if;
 if invoice_payment_remaining(part_pn)<>60 or invoice_payment_remaining(part_cash)<>40 then raise exception 'FAIL: each part stands on its own for refunds'; end if;

 -- the same request again writes nothing; a different answer under it is refused
 select count(*) into before_rows from invoice_payments where invoice_id=inv2;
 r:=correct_invoice(inv2,items2,jsonb_build_object('expected_edit_count',0,'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_c,'parts',
   jsonb_build_array(jsonb_build_object('amount',60,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',40,'date','2026-09-10','payment_method_id',cash))))),'Really PayNow and cash',req2);
 if not coalesce((r->>'replayed')::boolean,false) or (select count(*) from invoice_payments where invoice_id=inv2)<>before_rows then raise exception 'FAIL: split replay'; end if;
 begin
  perform split_invoice_payment(pay_c,jsonb_build_array(jsonb_build_object('amount',70,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',cash)),'Really PayNow and cash',md5(req2::text||'/split/'||pay_c::text)::uuid);
  raise exception 'FAIL: a reused request with different parts was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%already used for different payment details%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;

 -- the original cannot be split again; a part can be corrected as one payment, or split further
 r:=preview_invoice_correction(inv2,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',pay_c,'parts',
   jsonb_build_array(jsonb_build_object('amount',50,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',50,'date','2026-09-10','payment_method_id',cash))))));
 if not (r->>'blocking')::boolean or not exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%already corrected%') then
  raise exception 'FAIL: a second split of the original is not stopped: %', r->'needs_review'; end if;
 -- one part in "parts" is the plain correction: exactly one replacement, audited as a correction
 perform correct_invoice(inv2,items2,jsonb_build_object('expected_edit_count',1,'payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',part_cash,'parts',
   jsonb_build_array(jsonb_build_object('amount',45,'date','2026-09-11','payment_method_id',cash))))),'Cash was 45',gen_random_uuid());
 if (select count(*) from invoice_payments where invoice_id=inv2 and entry_kind='correction_replacement' and corrects_payment_id=part_cash)<>1
    or not exists (select 1 from audit_logs where action='payment_corrected' and record_id=part_cash) then
  raise exception 'FAIL: a single part did not go through the plain correction'; end if;
 fin:=invoice_financial_position(inv2);
 if (select status from invoices where id=inv2)<>'paid' or (fin->>'refund_due')::numeric<>5 then raise exception 'FAIL: 60 + 45 should be paid with 5 refund due: %', fin; end if;
 -- a further split of the PayNow part, totalling less: partially paid
 r:=preview_invoice_correction(inv2,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',part_pn,'parts',
   jsonb_build_array(jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',20,'date','2026-09-10','payment_method_id',bank))))));
 if not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'change'='partially paid' and e->>'detail' like 'Payments will total S$95.00 of S$100.00%') then
  raise exception 'FAIL: a smaller split''s consequence: %', r->'effects'; end if;

 -- what a split refuses: a zero part, a wallet part, staff
 r:=preview_invoice_correction(inv2,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',part_pn,'parts',
   jsonb_build_array(jsonb_build_object('amount',0,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',60,'date','2026-09-10','payment_method_id',bank))))));
 if not (r->>'blocking')::boolean or not exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like 'Each part of the % payment needs a positive amount%') then
  raise exception 'FAIL: a zero part not stopped: %', r->'needs_review'; end if;
 begin
  perform split_invoice_payment(part_pn,jsonb_build_array(jsonb_build_object('amount',0,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',60,'date','2026-09-10','payment_method_id',bank)),'Zero part',gen_random_uuid());
  raise exception 'FAIL: a zero part was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%positive amount%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 r:=preview_invoice_correction(inv2,jsonb_build_object('payment_corrections',jsonb_build_array(jsonb_build_object('payment_id',part_pn,'parts',
   jsonb_build_array(jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',wallet),jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',cash))))));
 if not (r->>'blocking')::boolean or not exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%cannot be wallet credit%') then
  raise exception 'FAIL: a wallet part not stopped: %', r->'needs_review'; end if;
 begin
  perform split_invoice_payment(part_pn,jsonb_build_array(jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',wallet),jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',cash)),'Wallet part',gen_random_uuid());
  raise exception 'FAIL: a wallet part was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%wallet credit%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 perform set_config('request.jwt.claim.sub',staff_id::text,true);
 begin
  perform split_invoice_payment(part_pn,jsonb_build_array(jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',paynow),jsonb_build_object('amount',30,'date','2026-09-10','payment_method_id',cash)),'Staff try',gen_random_uuid());
  raise exception 'FAIL: staff split a payment';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%Owner or Manager%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 perform set_config('request.jwt.claim.sub',own::text,true);
 if has_function_privilege('anon','public.split_invoice_payment(uuid,jsonb,text,uuid)','execute') then raise exception 'FAIL: anonymous can split payments'; end if;

 raise notice 'PASS: a correction carries payment amount, date and method changes and removals through the per-payment rules in one transaction; the preview describes each change and the invoice''s state afterwards; superseded, zero, wallet and staff attempts are refused before and at the save; replay and no-op are still detected; a payment splits into several methods as replacements of one receipt, with the same checks';
end $$;
rollback;
