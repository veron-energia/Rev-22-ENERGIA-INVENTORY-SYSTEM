-- The Therapy report is for Owners, Admins and Managers, and the Discounts
-- report survives a retired voucher (366).
--
--   * report_therapy: an Owner sees every store's therapy; a Manager only the
--     stores assigned to them; staff and a login with no staff profile (an
--     affiliate-portal account) see nothing. Before 366 every login saw all.
--   * report_discounts: the Voucher column is what the invoice was given, and
--     the report still loads after that voucher is deactivated, deleted or
--     expired. Before 366 it recalculated through voucher_discount_amount,
--     which raised, and the whole report failed.
--
-- Disposable database only; everything is rolled back. Run with
--   ENERGIA_INVOICE_DB=energia_integration_test sh scripts/invoices/local-sql.sh -f scripts/reports/tests/therapy-and-discounts.sql
begin;
-- Local databases still carry an older user_has_store_access that lets every
-- Manager see every store, which would hide a missing store filter. For the
-- length of this (rolled back) test, use production's rule (28 Sep 2026):
-- Owners and Admins see every store, anyone else only their assigned stores.
create or replace function public.user_has_store_access(target_store_id uuid)
 returns boolean language sql security definer set search_path to 'public' as $f$
  select exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner','admin'))
  or exists (select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true)
$f$;
do $$
declare o uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); a uuid:=gen_random_uuid();
 ad uuid:=gen_random_uuid(); mi uuid:=gen_random_uuid(); vp uuid; vl uuid; inv_m uuid;
 tag text:=substr(md5(random()::text),1,6); sa uuid; sb uuid; ca uuid; cb uuid; pm uuid; p uuid; pk uuid;
 inv_a uuid; inv_b uuid; inv_v uuid; v uuid; n int; r record;
begin
 insert into auth.users(id,email) values (o,'rt-o-'||tag||'@tests.invalid'),(m,'rt-m-'||tag||'@tests.invalid'),
   (s,'rt-s-'||tag||'@tests.invalid'),(a,'rt-a-'||tag||'@tests.invalid'),
   (ad,'rt-ad-'||tag||'@tests.invalid'),(mi,'rt-mi-'||tag||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values (o,'RT Owner','rt-o-'||tag||'@tests.invalid','owner'),
   (m,'RT Manager','rt-m-'||tag||'@tests.invalid','manager'),(s,'RT Staff','rt-s-'||tag||'@tests.invalid','staff'),
   (ad,'RT Admin','rt-ad-'||tag||'@tests.invalid','admin'),(mi,'RT Former Manager','rt-mi-'||tag||'@tests.invalid','manager');
 update profiles set is_active=false where id=mi;
 -- a: signed in, no staff profile — how every affiliate-portal login looks.
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('RT Store A '||tag,'RTA'||tag,'SG') returning id into sa;
 insert into stores(name,code,country_code) values('RT Store B '||tag,'RTB'||tag,'SG') returning id into sb;
 insert into user_store_assignments(user_id,store_id) values (m,sa),(s,sa),(mi,sa);
 insert into customers(full_name,phone) values('RT Customer A','+659123'||lpad((floor(random()*10000))::int::text,4,'0')) returning id into ca;
 insert into customers(full_name,phone) values('RT Customer B','+659123'||lpad((floor(random()*10000))::int::text,4,'0')) returning id into cb;
 insert into payment_methods(name) values('RT Cash '||tag) returning id into pm;
 insert into products(name,sku,product_type) values('RT Item','RT-'||tag,'own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(sa,p,10),(sb,p,10);
 perform set_product_prices(sa,p,100,100,'available'); perform set_product_prices(sb,p,100,100,'available');
 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('RT Package '||tag,3,true,'unlimited') returning id into pk;
 inv_a:=create_invoice_with_details(sa,ca,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),jsonb_build_object('business_date',current_date::text));
 inv_b:=create_invoice_with_details(sb,cb,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),jsonb_build_object('business_date',current_date::text));
 insert into purchased_therapy_entitlements(entitlement_no,customer_id,store_id,package_id,invoice_id,package_name,
   duration_months,price_snapshot,purchase_date,activation_deadline)
 values ('RT-PA-'||tag,ca,sa,pk,inv_a,'RT Package',3,0,current_date,current_date+30),
        ('RT-PB-'||tag,cb,sb,pk,inv_b,'RT Package',3,0,current_date,current_date+30);
 insert into therapy_entitlements(entitlement_no,customer_id,store_id,package_name,entitlement_kind,
   qualifying_amount,qualified_value,activation_deadline)
 values ('RT-LA-'||tag,ca,sa,'RT Legacy','unlimited',0,0,current_date+30),
        ('RT-LB-'||tag,cb,sb,'RT Legacy','unlimited',0,0,current_date+30);

 -- ---- report_therapy ------------------------------------------------------
 select count(*) into n from report_therapy() where entitlement_no like 'RT-%-'||tag;
 if n <> 4 then raise exception 'An Owner should see all 4 fixture rows, saw %', n; end if;
 if (select count(*) from report_therapy())
    <> (select count(*) from purchased_therapy_entitlements) + (select count(*) from therapy_entitlements) then
   raise exception 'An Owner should see every therapy row in every store'; end if;

 -- A Manager sees the stores assigned to them (store A), both kinds of therapy.
 perform set_config('request.jwt.claim.sub',m::text,true);
 select count(*) into n from report_therapy() where entitlement_no like 'RT-%-'||tag;
 if n <> 2 then raise exception 'A Manager of store A should see its 2 rows only, saw %', n; end if;
 if exists (select 1 from report_therapy() where entitlement_no in ('RT-PB-'||tag,'RT-LB-'||tag)) then
   raise exception 'A Manager saw therapy from a store not assigned to them'; end if;

 perform set_config('request.jwt.claim.sub',ad::text,true);
 select count(*) into n from report_therapy() where entitlement_no like 'RT-%-'||tag;
 if n <> 4 then raise exception 'An Admin should see every store, saw % of 4 rows', n; end if;

 perform set_config('request.jwt.claim.sub',mi::text,true);
 if exists (select 1 from report_therapy()) then raise exception 'A deactivated Manager can read the therapy report'; end if;

 perform set_config('request.jwt.claim.sub',s::text,true);
 if exists (select 1 from report_therapy()) then raise exception 'Staff can read the therapy report'; end if;

 perform set_config('request.jwt.claim.sub',a::text,true);
 if exists (select 1 from report_therapy()) then
   raise exception 'A login with no staff profile (affiliate portal) can read the therapy report'; end if;

 -- ---- report_discounts ----------------------------------------------------
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into vouchers(name,code,voucher_kind,discount_amount,qty_type,is_active)
   values ('RT 10 off','RT10-'||tag,'fixed_discount',10,'unlimited',true) returning id into v;
 inv_v:=create_invoice_with_details(sa,ca,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('discount_voucher_id',v,'business_date',current_date::text));
 perform record_invoice_payment(inv_v,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',
   (select total_amount from invoices where id=inv_v))),gen_random_uuid());
 select * into r from report_discounts() where invoice_id=inv_v;
 if r.voucher_discount is distinct from 10::numeric or r.total_discount is distinct from 10::numeric then
   raise exception 'Voucher column should be the S$10 given, got voucher % total %', r.voucher_discount, r.total_discount; end if;

 -- Retire the voucher every way the Vouchers page can.
 update vouchers set is_active=false, valid_until=current_date-1, deleted_at=now() where id=v;
 begin
   select * into r from report_discounts() where invoice_id=inv_v;
 exception when others then
   raise exception 'Retiring a used voucher breaks the Discounts report: %', sqlerrm;
 end;
 if r.voucher_discount is distinct from 10::numeric then
   raise exception 'After retiring the voucher the report should still show S$10, got %', r.voucher_discount; end if;
 if exists (select 1 from report_discounts() where voucher_discount < 0) then
   raise exception 'A negative voucher discount was reported'; end if;

 -- The voucher is only part of the discount: S$200 of goods, a S$20 manual
 -- discount, a S$5 line voucher, and a 10% invoice voucher. The till applies the
 -- 10% to what is left (200 - 20 - 5 = 175), so the invoice was given S$17.50.
 -- The old column recalculated 10% of the S$200 subtotal (S$20); reporting the
 -- whole discount as the voucher would say S$42.50.
 insert into vouchers(name,code,voucher_kind,discount_percent,qty_type,is_active)
   values ('RT 10 pct','RTP-'||tag,'percentage_discount',10,'unlimited',true) returning id into vp;
 insert into vouchers(name,code,voucher_kind,discount_amount,qty_type,is_active)
   values ('RT line 5 off','RTL-'||tag,'fixed_discount',5,'unlimited',true) returning id into vl;
 inv_m:=create_invoice_with_details(sa,cb,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',2,'line_voucher_id',vl)),
   jsonb_build_object('discount_voucher_id',vp,'manual_discount',20,'manual_discount_reason','RT test','business_date',current_date::text));
 perform record_invoice_payment(inv_m,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',
   (select total_amount from invoices where id=inv_m))),gen_random_uuid());
 select * into r from report_discounts() where invoice_id=inv_m;
 if r.manual_discount is distinct from 20::numeric or r.line_discount is distinct from 5::numeric
    or r.total_discount is distinct from 42.50::numeric then
   raise exception 'Fixture is not the discount mix intended: manual % line % total %', r.manual_discount, r.line_discount, r.total_discount; end if;
 if r.voucher_discount is distinct from 17.50::numeric then
   raise exception 'The Voucher column should be the S$17.50 the till gave, got %', r.voucher_discount; end if;

 raise notice 'PASS: therapy report is Owner/Admin/Manager only and store-scoped (owner and admin all, manager only store A, deactivated manager 0, staff 0, affiliate login 0); discounts report shows the voucher discount the till gave (S$10; S$17.50 alongside manual and line discounts) and still loads after the voucher is retired';
end $$;
rollback;
