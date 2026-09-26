-- A correction settles the therapy of the lines it changes (362).
--
-- A promotion or therapy line issues purchased therapy units against its
-- invoice line. correct_invoice deleted a removed line, and the foreign key
-- (ON DELETE SET NULL) left its unit pending and claimable on no line: how
-- INV-2026-0086 came to hold UTP-0000002 as well as UTP-0000003. A line kept
-- under its id but changed kept units it no longer grants, and therapy swapped
-- in on a paid invoice was never issued.
--
-- The owner's rule (26 Sep 2026): therapy a correction takes away closes if
-- unused ('cancelled', audited, uncollected vouchers withdrawn) and the
-- correction is refused if any of it was used; therapy it adds is issued at
-- the correction when the invoice is still paid; a unit whose package the line
-- still grants is kept.
--
-- Needs 362. Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;

create function pg_temp.sell(p_store uuid, p_customer uuid, p_items jsonb, p_pm uuid, p_amount numeric)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := create_invoice_with_details(p_store, p_customer, p_items, jsonb_build_object('business_date', sg_today()::text));
  if p_amount > 0 then
    perform record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', p_pm, 'amount', p_amount)), gen_random_uuid());
  end if;
  return v;
end $$;

create function pg_temp.promo(p_item uuid, p_promotion uuid, p_qty int default 1) returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('invoice_item_id', p_item, 'kind', 'promotion',
           'promotion_id', p_promotion, 'quantity', p_qty)) $$;

create function pg_temp.unit_of(p_invoice uuid) returns uuid language sql as $$
  select id from purchased_therapy_entitlements where invoice_id = p_invoice $$;

do $$
declare own uuid := gen_random_uuid();
 st uuid; pm uuid; pc uuid; pbelt uuid; v1 uuid;
 tpu uuid; tpu2 uuid; tpc uuid; tpt uuid; tpt2 uuid;
 pa uuid; pa2 uuid; pb uuid; pn uuid; pch uuid; pdear uuid; pg uuid; grp uuid;
 c uuid[] := '{}'; cid uuid; k int;
 inv uuid; it uuid; it2 uuid; u uuid; u2 uuid; n uuid; ent uuid; req uuid;
 r jsonb; r2 jsonb; cnt int; ec int; no text;
begin
 insert into auth.users(id,email) values(own,'ptc-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','ptc-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PTC Store','PTCS','SG') returning id into st;
 -- One buyer per section: two units of one package never share days, and a
 -- customer holding a current unit cannot buy that package again on its own.
 for k in 1..16 loop
  insert into customers(full_name,phone) values('PTC Buyer '||k,'+659893'||lpad((5000+k)::text,4,'0')) returning id into cid;
  c := c || cid;
 end loop;
 insert into payment_methods(name,is_active) values('PTC Cash',true) returning id into pm;
 insert into products(name,sku,product_type) values('PTC Corset','PTCC','own') returning id into pc;
 insert into store_inventory(store_id,product_id,current_qty) values(st,pc,100);
 perform set_product_prices(st,pc,200,200,'available');
 insert into products(name,sku,product_type) values('PTC Belt','PTCB','own') returning id into pbelt;
 insert into store_inventory(store_id,product_id,current_qty) values(st,pbelt,100);
 perform set_product_prices(st,pbelt,150,150,'available');
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
   values('PTC Facial','PTCF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,100);

 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('PTC 3 Months',3,true,'unlimited') returning id into tpu;
 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('PTC 6 Months',6,true,'unlimited') returning id into tpu2;
 tpc := upsert_therapy_package_choice(null,'PTC Choice','PTC-CH',null,true,1,10,array[v1],null);
 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('PTC Own Line',6,true,'unlimited') returning id into tpt;
 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('PTC Own Line Long',12,true,'unlimited') returning id into tpt2;
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
   values(tpt,st,600,true),(tpt2,st,600,true);

 -- A: corset + 3 months. A2: belt + 3 months (same package, other goods).
 -- B: corset + 6 months. N: belt, no therapy. CH: corset + the choice package.
 -- DEAR: like B at a higher price. G: belt + a therapy the customer picks.
 insert into promotions(name,code) values('PTC Bundle A','PTC-A') returning id into pa;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pa,'product',pc,1);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pa,'therapy',tpu,1);
 perform set_promotion_prices(pa,st,610,610,true);
 insert into promotions(name,code) values('PTC Bundle A2','PTC-A2') returning id into pa2;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pa2,'product',pbelt,1);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pa2,'therapy',tpu,1);
 perform set_promotion_prices(pa2,st,610,610,true);
 insert into promotions(name,code) values('PTC Bundle B','PTC-B') returning id into pb;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pb,'product',pc,1);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pb,'therapy',tpu2,1);
 perform set_promotion_prices(pb,st,610,610,true);
 insert into promotions(name,code) values('PTC Belt Only','PTC-N') returning id into pn;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pn,'product',pbelt,1);
 perform set_promotion_prices(pn,st,610,610,true);
 insert into promotions(name,code) values('PTC Choice Bundle','PTC-CHB') returning id into pch;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pch,'product',pc,1);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pch,'therapy',tpc,1);
 perform set_promotion_prices(pch,st,610,610,true);
 insert into promotions(name,code) values('PTC Bundle B Dear','PTC-BD') returning id into pdear;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pdear,'product',pc,1);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pdear,'therapy',tpu2,1);
 perform set_promotion_prices(pdear,st,800,800,true);
 insert into promotions(name,code) values('PTC Pick A Therapy','PTC-G') returning id into pg;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pg,'product',pbelt,1);
 insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values(pg,'Therapy','therapy',1) returning id into grp;
 insert into promotion_choice_options(group_id,therapy_package_id) values(grp,tpu),(grp,tpu2);
 perform set_promotion_prices(pg,st,610,610,true);

 -- ---- 1. the reported gap: a therapy promotion swapped for one without ------
 inv := pg_temp.sell(st,c[1],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 if u is null or (select status from invoices where id=inv)<>'paid' then raise exception '1: fixture: no unit issued'; end if;
 req := gen_random_uuid();
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pn)),'{}'::jsonb,'Customer wanted the belt bundle',req);
 if (select promotion_id from invoice_items where id=it) is distinct from pn then raise exception '1: fixture: the swap did not save'; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled' then
  raise exception '1: the swapped-out promotion''s therapy is still open (the INV-2026-0086 gap): %',
    (select status from purchased_therapy_entitlements where id=u); end if;
 if (select invoice_item_id from purchased_therapy_entitlements where id=u) is not null then
  raise exception '1: the closed unit still sits on the line'; end if;
 if not exists(select 1 from audit_logs where table_name='purchased_therapy_entitlements' and record_id=u
                and action='closed_by_invoice_correction' and new_data->>'request_id'=req::text
                and old_data->>'invoice_item_id'=it::text and old_data->>'status'='pending_activation'
                and (new_data->>'line_removed')::boolean=false and reason='Customer wanted the belt bundle') then
  raise exception '1: closing the unit was not audited with its line and the correction'; end if;
 no := (select entitlement_no from purchased_therapy_entitlements where id=u);
 if r->'therapy'->'closed' is distinct from jsonb_build_array(no) or r->'therapy' ? 'issued' then
  raise exception '1: the result does not say what closed: %',r->'therapy'; end if;
 if (select after_snapshot->'therapy'->'closed' from invoice_revisions where invoice_id=inv and request_id=req) is distinct from jsonb_build_array(no) then
  raise exception '1: the revision does not record the therapy'; end if;
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv)<>1 then raise exception '1: something was issued'; end if;
 if (select status from invoices where id=inv)<>'paid' then raise exception '1: invoice status moved'; end if;
 begin
  perform claim_purchased_therapy(u,'unlimited',sg_today());
  raise exception '1: the closed unit could still be claimed';
 exception when others then if sqlerrm not like '%cancelled%nothing can be claimed%' then raise; end if; end;
 -- a replay of the same correction changes nothing more
 r2 := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pn)),'{}'::jsonb,'Customer wanted the belt bundle',req);
 if not coalesce((r2->>'replayed')::boolean,false) then raise exception '1: the replay was not recognised: %',r2; end if;
 if (select count(*) from audit_logs where record_id=u and action='closed_by_invoice_correction')<>1 then
  raise exception '1: the replay closed it again'; end if;

 -- ---- 2. the line's kind changed: the form sends it without its id --------
 inv := pg_temp.sell(st,c[2],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 r := correct_invoice(inv,jsonb_build_array(jsonb_build_object('kind','product','product_id',pc,'quantity',1)),
   '{}'::jsonb,'Sold the corset alone',gen_random_uuid());
 if exists(select 1 from invoice_items where id=it) then raise exception '2: fixture: the promotion line is still there'; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled' then raise exception '2: therapy of a deleted line left open'; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='closed_by_invoice_correction'
                and old_data->>'invoice_item_id'=it::text and (new_data->>'line_removed')::boolean) then
  raise exception '2: the audit does not keep the deleted line'; end if;

 -- ---- 3. swapped for a promotion with another package: closed and issued --
 inv := pg_temp.sell(st,c[3],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pb)),'{}'::jsonb,'Wrong bundle keyed',gen_random_uuid());
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled' then raise exception '3: the old package stayed open'; end if;
 select id into n from purchased_therapy_entitlements where invoice_id=inv and id<>u;
 if n is null then raise exception '3: the swapped-in promotion''s therapy was not issued'; end if;
 if (select (package_id,invoice_item_id,status,price_snapshot) from purchased_therapy_entitlements where id=n)
    is distinct from (tpu2,it,'pending_activation'::text,0::numeric) then
  raise exception '3: the new unit is not the 6-month package, pending, on the line, at 0: %',
    (select to_jsonb(e) from purchased_therapy_entitlements e where id=n); end if;
 if (select activation_deadline from purchased_therapy_entitlements where id=n)
    <> ((select paid_at from invoices where id=inv) at time zone 'Asia/Singapore')::date + interval '1 year' then
  raise exception '3: the new unit''s deadline is not a year from the payment date'; end if;
 if r->'therapy'->'issued' is distinct from jsonb_build_array((select entitlement_no from purchased_therapy_entitlements where id=n))
    or jsonb_array_length(r->'therapy'->'closed')<>1 then
  raise exception '3: the result does not say what closed and what was issued: %',r->'therapy'; end if;
 if not exists(select 1 from audit_logs where table_name='invoices' and record_id=inv and action='therapy_entitlements_created') then
  raise exception '3: issuing was not audited'; end if;
 -- correcting it again, unchanged, issues nothing twice
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pb)),'{}'::jsonb,'No change',gen_random_uuid());
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv)<>2 then raise exception '3: an unchanged correction issued again'; end if;

 -- ---- 4. swapped for a promotion with the same package: the unit is kept ---
 inv := pg_temp.sell(st,c[4],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 no := (select entitlement_no from purchased_therapy_entitlements where id=u);
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pa2)),'{}'::jsonb,'Belt instead of corset',gen_random_uuid());
 if (select (status,invoice_item_id,entitlement_no) from purchased_therapy_entitlements where id=u)
    is distinct from ('pending_activation'::text,it,no) then
  raise exception '4: the unit the new promotion also grants was not kept as it was'; end if;
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv)<>1 then raise exception '4: a second unit was issued'; end if;
 if exists(select 1 from audit_logs where record_id=u and action in ('closed_by_invoice_correction','moved_by_invoice_correction')) then
  raise exception '4: a kept unit was touched'; end if;
 if r->'therapy'<>'{}'::jsonb then raise exception '4: the result reports therapy changes: %',r->'therapy'; end if;

 -- ---- 5. line deleted and the same package added back: the unit moves -----
 inv := pg_temp.sell(st,c[5],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 perform claim_purchased_therapy(u,'unlimited',sg_today()+30);   -- a start booked ahead: scheduled, not used
 if (select status from purchased_therapy_entitlements where id=u)<>'scheduled' or therapy_unit_consumed(u) then
  raise exception '5: fixture: expected a scheduled, unused unit'; end if;
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(null,pa2)),'{}'::jsonb,'Re-keyed the bundle',gen_random_uuid());
 select id into it2 from invoice_items where invoice_id=inv;
 if it2=it then raise exception '5: fixture: the line kept its id'; end if;
 if (select (status,invoice_item_id,activation_date) from purchased_therapy_entitlements where id=u)
    is distinct from ('scheduled'::text,it2,sg_today()+30) then
  raise exception '5: the unit did not move to the new line with its booked start: %',
    (select to_jsonb(e) from purchased_therapy_entitlements e where id=u); end if;
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv)<>1 then raise exception '5: a unit was issued as well'; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='moved_by_invoice_correction'
                and old_data->>'invoice_item_id'=it::text and new_data->>'invoice_item_id'=it2::text) then
  raise exception '5: the move was not audited'; end if;
 if r->'therapy'->'moved' is distinct from jsonb_build_array((select entitlement_no from purchased_therapy_entitlements where id=u)) then
  raise exception '5: the result does not say it moved: %',r->'therapy'; end if;

 -- ---- 6. used therapy refuses the correction ------------------------------
 -- vouchers collected: the unit stays pending, so the existing active/expired
 -- guard never saw it
 inv := pg_temp.sell(st,c[6],jsonb_build_array(pg_temp.promo(null,pch)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 perform claim_purchased_therapy(u,'voucher',null,null,null,false,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)));
 if (select status from purchased_therapy_entitlements where id=u)<>'pending_activation' or not therapy_unit_consumed(u) then
  raise exception '6: fixture: expected a pending unit with vouchers collected'; end if;
 ec := (select edit_count from invoices where id=inv);
 begin
  perform correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pn)),'{}'::jsonb,'Swap it',gen_random_uuid());
  raise exception '6: therapy with collected vouchers was swapped out';
 exception when others then
  if sqlerrm not like '%vouchers from it were collected ('||(select entitlement_no from purchased_therapy_entitlements where id=u)||')%Refund / Cancel%' then raise; end if;
 end;
 if (select (status,invoice_item_id) from purchased_therapy_entitlements where id=u) is distinct from ('pending_activation'::text,it)
    or (select promotion_id from invoice_items where id=it)<>pch
    or (select edit_count from invoices where id=inv) is distinct from ec then
  raise exception '6: a refused correction changed something'; end if;
 -- nor may the line be deleted
 begin
  perform correct_invoice(inv,jsonb_build_array(jsonb_build_object('kind','product','product_id',pc,'quantity',1)),'{}'::jsonb,'Corset alone',gen_random_uuid());
  raise exception '6: the line holding used therapy was deleted';
 exception when others then if sqlerrm not like '%vouchers from it were collected%' then raise; end if; end;
 -- but a correction that leaves that line alone still goes through
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pch),jsonb_build_object('kind','product','product_id',pbelt,'quantity',1)),
   '{}'::jsonb,'Added a belt',gen_random_uuid());
 if (select (status,invoice_item_id) from purchased_therapy_entitlements where id=u) is distinct from ('pending_activation'::text,it) then
  raise exception '6: an untouched line''s used unit was changed'; end if;
 -- started therapy: refused, as before 362
 inv := pg_temp.sell(st,c[7],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 perform claim_purchased_therapy(u,'unlimited',sg_today());
 if (select status from purchased_therapy_entitlements where id=u)<>'active' then raise exception '6: fixture: not started'; end if;
 begin
  perform correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pn)),'{}'::jsonb,'Swap it',gen_random_uuid());
  raise exception '6: started therapy was swapped out';
 exception when others then
  if sqlerrm not like '%Resolve the consumed therapy entitlement%' and sqlerrm not like '%has been started%' then raise; end if;
 end;
 if (select status from purchased_therapy_entitlements where id=u)<>'active' then raise exception '6: refused but changed'; end if;

 -- ---- 7. quantity lowered: unused units close first -----------------------
 inv := pg_temp.sell(st,c[8],jsonb_build_array(pg_temp.promo(null,pch,2)),pm,1220);
 select id into it from invoice_items where invoice_id=inv;
 select id into u from purchased_therapy_entitlements where invoice_id=inv and unit_index=1;
 select id into u2 from purchased_therapy_entitlements where invoice_id=inv and unit_index=2;
 if u is null or u2 is null then raise exception '7: fixture: expected two units'; end if;
 -- the second one issued is the one used
 perform claim_purchased_therapy(u2,'voucher',null,null,null,false,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)));
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pch,1)||jsonb_build_object('unit_price',1220)),'{}'::jsonb,
   'One bundle at the agreed price',gen_random_uuid());
 if (select quantity from invoice_items where id=it)<>1 then raise exception '7: fixture: quantity not saved'; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled'
    or (select (status,invoice_item_id) from purchased_therapy_entitlements where id=u2) is distinct from ('pending_activation'::text,it) then
  raise exception '7: expected the unused unit closed and the used one kept'; end if;
 -- lowering again would need the used one: refused
 begin
  perform correct_invoice(inv,jsonb_build_array(jsonb_build_object('kind','product','product_id',pc,'quantity',1)),'{}'::jsonb,'None',gen_random_uuid());
  raise exception '7: the used unit was closed';
 exception when others then if sqlerrm not like '%vouchers from it were collected%' then raise; end if; end;

 -- ---- 8. quantity raised on a paid invoice: issued at the correction ------
 inv := pg_temp.sell(st,c[9],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pa,2)||jsonb_build_object('unit_price',305)),'{}'::jsonb,
   'Two bundles at the same total',gen_random_uuid());
 if (select status from invoices where id=inv)<>'paid' then raise exception '8: fixture: invoice not paid after the correction'; end if;
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv and invoice_item_id=it and status='pending_activation')<>2
    or (select status from purchased_therapy_entitlements where id=u)<>'pending_activation' then
  raise exception '8: expected the first unit kept and a second one issued'; end if;
 if jsonb_array_length(coalesce(r->'therapy'->'issued','[]'))<>1 then raise exception '8: result: %',r->'therapy'; end if;

 -- ---- 9. a correction that leaves a balance: issued when it is paid -------
 inv := pg_temp.sell(st,c[10],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pdear)),'{}'::jsonb,'The dearer bundle',gen_random_uuid());
 if (select status from invoices where id=inv)<>'partially_paid' then raise exception '9: fixture: expected a balance'; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled' then raise exception '9: the old package stayed open'; end if;
 if exists(select 1 from purchased_therapy_entitlements where invoice_id=inv and id<>u) then
  raise exception '9: therapy was issued before the balance was paid'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',190)),gen_random_uuid());
 if (select status from invoices where id=inv)<>'paid'
    or (select count(*) from purchased_therapy_entitlements where invoice_id=inv and package_id=tpu2 and invoice_item_id=it and status='pending_activation')<>1 then
  raise exception '9: paying the balance did not issue the new package'; end if;

 -- ---- 10. lines the correction leaves alone keep what they issued --------
 -- What a promotion grants is read from the live catalogue. After the
 -- catalogue changes, a correction elsewhere on the invoice must neither
 -- close nor issue therapy on the untouched lines.
 inv := pg_temp.sell(st,c[11],jsonb_build_array(pg_temp.promo(null,pa),pg_temp.promo(null,pn),
          jsonb_build_object('kind','product','product_id',pc,'quantity',2)),pm,1620);
 select id into it from invoice_items where invoice_id=inv and promotion_id=pa;
 select id into it2 from invoice_items where invoice_id=inv and promotion_id=pn;
 u := pg_temp.unit_of(inv);
 delete from promotion_items where promotion_id=pa and therapy_package_id=tpu;
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pn,'therapy',tpu2,1);
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pa),pg_temp.promo(it2,pn),
        (select jsonb_build_object('invoice_item_id',id,'kind','product','product_id',pc,'quantity',1) from invoice_items where invoice_id=inv and line_kind='product')),
        '{}'::jsonb,'One corset, not two',gen_random_uuid());
 if (select quantity from invoice_items where invoice_id=inv and line_kind='product')<>1 then raise exception '10: fixture: not saved'; end if;
 if (select (status,invoice_item_id) from purchased_therapy_entitlements where id=u) is distinct from ('pending_activation'::text,it) then
  raise exception '10: an untouched line''s therapy was closed after a catalogue edit'; end if;
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv)<>1 then
  raise exception '10: therapy was issued for an untouched line after a catalogue edit'; end if;
 -- a correction of the header alone touches nothing either
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pa),pg_temp.promo(it2,pn),
        (select jsonb_build_object('invoice_item_id',id,'kind','product','product_id',pc,'quantity',1) from invoice_items where invoice_id=inv and line_kind='product')),
        jsonb_build_object('notes','Header only'),'Note',gen_random_uuid());
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv)<>1
    or (select status from purchased_therapy_entitlements where id=u)<>'pending_activation' then
  raise exception '10: a header correction touched therapy'; end if;
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pa,'therapy',tpu,1);
 delete from promotion_items where promotion_id=pn and therapy_package_id=tpu2;

 -- ---- 11. a unit already on no line is left as it is ----------------------
 -- UTP-0000002's shape: detached by an older path. Its repair is separate.
 inv := pg_temp.sell(st,c[12],jsonb_build_array(pg_temp.promo(null,pa)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 update purchased_therapy_entitlements set invoice_item_id=null where id=u;
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pb)),'{}'::jsonb,'Swap',gen_random_uuid());
 if (select (status,invoice_item_id) from purchased_therapy_entitlements where id=u) is distinct from ('pending_activation'::text,null::uuid) then
  raise exception '11: the unit on no line was changed'; end if;
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv and package_id=tpu2 and invoice_item_id=it)<>1 then
  raise exception '11: the swapped-in package was not issued'; end if;

 -- ---- 12. therapy sold on its own line, package changed -------------------
 inv := pg_temp.sell(st,c[13],jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',tpt,'quantity',1)),pm,600);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 if (select price_snapshot from purchased_therapy_entitlements where id=u)<>600 then raise exception '12: fixture'; end if;
 r := correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','therapy','therapy_package_id',tpt2,'quantity',1)),
   '{}'::jsonb,'The 12-month package was sold',gen_random_uuid());
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled' then raise exception '12: the old package stayed open'; end if;
 if (select (package_id,invoice_item_id,price_snapshot,status) from purchased_therapy_entitlements where invoice_id=inv and id<>u)
    is distinct from (tpt2,it,600::numeric,'pending_activation'::text) then
  raise exception '12: the new package was not issued at the line''s price'; end if;

 -- ---- 13. therapy the customer picked in a choice group -------------------
 inv := pg_temp.sell(st,c[14],jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg,'quantity',1,
          'selections',jsonb_build_array(jsonb_build_object('group_id',grp,'options',
            jsonb_build_array(jsonb_build_object('therapy_package_id',tpu,'quantity',1)))))),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 if (select package_id from purchased_therapy_entitlements where id=u) is distinct from tpu then raise exception '13: fixture: the pick was not issued'; end if;
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pn)),'{}'::jsonb,'No therapy after all',gen_random_uuid());
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled' then raise exception '13: the picked therapy stayed open'; end if;

 -- ---- 14. taken as vouchers, none collected: closed, allowance withdrawn --
 inv := pg_temp.sell(st,c[15],jsonb_build_array(pg_temp.promo(null,pch)),pm,610);
 select id into it from invoice_items where invoice_id=inv;
 u := pg_temp.unit_of(inv);
 perform choose_therapy_benefit(u,'voucher',null,'Vouchers please');
 ent := (select voucher_entitlement_id from purchased_therapy_entitlements where id=u);
 if ent is null or therapy_unit_consumed(u) then raise exception '14: fixture: expected unused vouchers'; end if;
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pn)),'{}'::jsonb,'No therapy after all',gen_random_uuid());
 if (select status from purchased_therapy_entitlements where id=u)<>'cancelled' then raise exception '14: unit left open'; end if;
 if coalesce((entitlement_voucher_state(ent)->>'remaining')::int,-1)<>0 then
  raise exception '14: the vouchers were not withdrawn: %',entitlement_voucher_state(ent); end if;

 -- ---- 15. an unpaid invoice: nothing to settle, nothing issued early ------
 inv := pg_temp.sell(st,c[16],jsonb_build_array(pg_temp.promo(null,pa)),pm,0);
 select id into it from invoice_items where invoice_id=inv;
 r := correct_invoice(inv,jsonb_build_array(pg_temp.promo(it,pb)),'{}'::jsonb,null,gen_random_uuid());
 if exists(select 1 from purchased_therapy_entitlements where invoice_id=inv) then raise exception '15: therapy issued on an unpaid invoice'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 if (select count(*) from purchased_therapy_entitlements where invoice_id=inv and package_id=tpu2)<>1
    or (select count(*) from purchased_therapy_entitlements where invoice_id=inv)<>1 then
  raise exception '15: payment did not issue what the corrected invoice grants'; end if;

 -- ---- 16. the new functions are not endpoints (339) -----------------------
 if has_function_privilege('authenticated','public.therapy_units_before_correction(uuid,jsonb)','execute')
    or has_function_privilege('authenticated','public.settle_corrected_therapy_units(uuid,jsonb,text,uuid)','execute')
    or has_function_privilege('authenticated','public.issue_therapy_of_corrected_lines(uuid,jsonb)','execute')
    or has_function_privilege('authenticated','public.create_purchased_therapy_for_invoice(uuid,uuid[])','execute')
    or has_function_privilege('anon','public.create_purchased_therapy_for_invoice(uuid,uuid[])','execute') then
  raise exception '16: a 362 function is callable by signed-in or signed-out users'; end if;

 raise notice 'PASS: a correction closes the unused therapy of lines it removes or changes (refused if used), keeps or moves units still granted, issues added therapy when paid, and leaves untouched lines alone';
end $$;
rollback;
