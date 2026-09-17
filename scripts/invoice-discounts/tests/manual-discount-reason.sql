-- A manual discount carries its reason (331).
--
-- Required whenever a positive manual discount is set or changed; enforced by
-- a trigger so no path around the two named functions can avoid it. History
-- is not asked to invent one. Disposable database only; all rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; prod uuid; inv uuid; it uuid; r jsonb; msg text;
 items jsonb; hdr jsonb;
begin
 insert into auth.users(id,email) values(own,'mdr-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','mdr-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('MDR Store','MDR','SG') returning id into st;
 insert into customers(full_name,phone) values('MDR Buyer','+6598913001') returning id into c;
 insert into products(name,sku,product_type) values('MDR Item','MDR-1','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,1000);
 perform set_product_prices(st,prod,100,100,'available');
 items:=jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1));

 -- ---- creation ------------------------------------------------------------
 begin
  perform create_invoice_with_details(st,c,items,jsonb_build_object('business_date',sg_today(),'manual_discount',10));
  raise exception 'FAIL: a positive discount with no reason was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%MANUAL_DISCOUNT_REASON_REQUIRED%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 begin
  perform create_invoice_with_details(st,c,items,jsonb_build_object('business_date',sg_today(),'manual_discount',10,'manual_discount_reason','   '));
  raise exception 'FAIL: whitespace passed as a reason';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%MANUAL_DISCOUNT_REASON_REQUIRED%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 inv:=create_invoice_with_details(st,c,items,jsonb_build_object('business_date',sg_today(),'manual_discount',10,'manual_discount_reason','  Loyalty  '));
 if (select manual_discount_reason from invoices where id=inv) is distinct from 'Loyalty' then
  raise exception 'FAIL: reason not stored trimmed: %', (select manual_discount_reason from invoices where id=inv); end if;
 if (select manual_discount from invoices where id=inv)<>10 then raise exception 'FAIL: discount not stored'; end if;

 inv:=create_invoice_with_details(st,c,items,jsonb_build_object('business_date',sg_today()));
 if (select manual_discount_reason from invoices where id=inv) is not null then raise exception 'FAIL: a zero discount stored a reason'; end if;
 -- A discount that is not manual — a voucher or promotion writes discount_total,
 -- never manual_discount — asks for nothing.
 update invoices set discount_total=5, total_amount=95 where id=inv;
 if (select manual_discount_reason from invoices where id=inv) is not null then raise exception 'FAIL: non-manual discount touched the reason'; end if;

 -- ---- history: an invoice discounted before the column existed -----------
 -- Written the way it would have been before 331: through the older
 -- create_invoice, which never knew the column, with the guard off.
 alter table invoices disable trigger invoice_manual_discount_reason;
 inv:=create_invoice(st,c,null,items,10,null,null,'[]'::jsonb);
 update invoices set business_date=sg_today() where id=inv;
 alter table invoices enable trigger invoice_manual_discount_reason;
 if (select manual_discount_reason from invoices where id=inv) is not null then raise exception 'FIXTURE: historical row has a reason'; end if;
 select id into it from invoice_items where invoice_id=inv;
 items:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1));

 -- An unrelated correction, sending the unchanged amount and a blank reason
 -- exactly as the form does, is not asked to invent one.
 perform correct_invoice(inv,items,jsonb_build_object('notes','delivery note','manual_discount',10,'manual_discount_reason',''),'notes only',gen_random_uuid());
 if (select notes from invoices where id=inv)<>'delivery note' then raise exception 'FAIL: unrelated correction did not apply'; end if;
 if (select manual_discount_reason from invoices where id=inv) is not null then raise exception 'FAIL: unrelated correction invented a reason'; end if;

 -- Changing the amount to a positive one does need a reason.
 begin
  perform correct_invoice(inv,items,jsonb_build_object('manual_discount',15,'manual_discount_reason',''),'raise it',gen_random_uuid());
  raise exception 'FAIL: a changed positive discount without a reason was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%MANUAL_DISCOUNT_REASON_REQUIRED%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 perform correct_invoice(inv,items,jsonb_build_object('manual_discount',15,'manual_discount_reason','Price match'),'raise it',gen_random_uuid());
 if (select manual_discount from invoices where id=inv)<>15 or (select manual_discount_reason from invoices where id=inv)<>'Price match' then
  raise exception 'FAIL: changed discount and reason not stored'; end if;

 -- An unrelated edit that does not mention the reason leaves it alone.
 perform correct_invoice(inv,items,jsonb_build_object('notes','second note'),'notes again',gen_random_uuid());
 if (select manual_discount_reason from invoices where id=inv)<>'Price match' then raise exception 'FAIL: reason erased by an unrelated edit'; end if;

 -- The audit trail names who changed it and what it was. Existing conventions:
 -- the correction writes a revision snapshot and an invoices audit row.
 if not exists (select 1 from invoice_revisions where invoice_id=inv and snapshot::text like '%Price match%'
                   or (invoice_id=inv and after_snapshot::text like '%Price match%')) then
  raise exception 'FAIL: revision history does not carry the reason'; end if;
 if not exists (select 1 from audit_logs where table_name='invoices' and record_id=inv and action='invoice_corrected'
                   and new_data::text like '%Price match%' and changed_by=own) then
  raise exception 'FAIL: audit row lacks the reason or the actor'; end if;

 -- Removing the discount clears the reason from the invoice; history keeps it.
 perform correct_invoice(inv,items,jsonb_build_object('manual_discount',0,'manual_discount_reason','Price match'),'remove it',gen_random_uuid());
 if (select manual_discount from invoices where id=inv)<>0 or (select manual_discount_reason from invoices where id=inv) is not null then
  raise exception 'FAIL: removing the discount did not clear the reason'; end if;
 if not exists (select 1 from invoice_revisions where invoice_id=inv and snapshot::text like '%Price match%') then
  raise exception 'FAIL: the removed discount''s reason is gone from history'; end if;

 -- ---- bypass: the older RPC and a bare statement are refused too ---------
 begin
  perform update_invoice(inv,c,null,items,25,null,null,'[]'::jsonb,'bypass');
  raise exception 'FAIL: update_invoice set a discount with no reason';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%MANUAL_DISCOUNT_REASON_REQUIRED%' then raise exception 'FAIL: wrong refusal from update_invoice: %', sqlerrm; end if;
 end;
 begin
  update invoices set manual_discount=30 where id=inv;
  raise exception 'FAIL: a bare update set a discount with no reason';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%MANUAL_DISCOUNT_REASON_REQUIRED%' then raise exception 'FAIL: wrong refusal from update: %', sqlerrm; end if;
 end;

 raise notice 'PASS: a positive manual discount needs a real reason on creation and on any change, not for a voucher discount, not for an unchanged historical one; the reason survives unrelated edits, is cleared with the discount, stays in the revision and audit history with its actor, and the older RPC and a bare statement are refused';
end $$;
rollback;
