-- Part payments earn staff and affiliate commission as the money arrives (357).
--
-- Before 357 a part payment earned nothing until the invoice settled, and a
-- payment correction on a part-paid invoice earned early AND let settlement
-- earn again (INV-2026-0282). Every check goes through the real entry points —
-- record_invoice_payment, correct_invoice_payment, remove_invoice_payment,
-- cancel_invoice_recorded, create_staff_commission_payout,
-- record_affiliate_payout, apply_commission_rebase_all, the exchange creator —
-- because that is where staff meet it.
--
-- The rule every check comes back to: whatever happens on the way, an invoice
-- ends with exactly what full settlement alone would pay.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create function pg_temp.staff_live(inv uuid) returns numeric language sql as
$$ select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=inv and status in ('earned','paid') $$;
create function pg_temp.aff(inv uuid, st text default 'earned,paid') returns numeric language sql as
$$ select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and status::text = any(string_to_array(st,',')) $$;
create function pg_temp.layer(inv uuid, basis text) returns numeric language sql as
$$ select coalesce((select sum(commission_amount) from staff_commissions where invoice_id=inv and earning_basis=basis and status in ('earned','paid')),0)
        + coalesce((select sum(commission_amount) from commissions where invoice_id=inv and earning_basis=basis and status in ('earned','paid')),0) $$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;

-- ═════ Fixtures, and invoices part-paid BEFORE the owner turns it on ═════
do $$
declare own uuid:=gen_random_uuid(); s1 uuid:=gen_random_uuid(); s2 uuid:=gen_random_uuid(); s3 uuid:=gen_random_uuid();
 st uuid; buyer uuid; ref uuid; ref2 uuid; buyer5 uuid; ref5 uuid; m uuid; p uuid; cp uuid; pb uuid;
 l1 uuid; l2 uuid; l3 uuid; l4 uuid; pay uuid;
begin
 insert into auth.users(id,email) values(own,'ppe-own@tests.invalid'),(s1,'ppe-s1@tests.invalid'),(s2,'ppe-s2@tests.invalid'),(s3,'ppe-s3@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'PPE Owner','ppe-own@tests.invalid','owner'),
   (s1,'PPE Staff A','ppe-s1@tests.invalid','staff'),(s2,'PPE Staff B','ppe-s2@tests.invalid','staff'),(s3,'PPE Staff C','ppe-s3@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PPE Store','PPES','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(s1,st),(s2,st),(s3,st);
 insert into customers(full_name,phone) values('PPE Tier2','+6598917003') returning id into ref2;
 insert into customers(full_name,phone,referred_by) values('PPE Referrer','+6598917002',ref2) returning id into ref;
 insert into customers(full_name,phone,referred_by) values('PPE Buyer','+6598917001',ref) returning id into buyer;
 insert into customers(full_name,phone) values('PPE Referrer5','+6598917005') returning id into ref5;
 insert into customers(full_name,phone,referred_by) values('PPE Buyer5','+6598917004',ref5) returning id into buyer5;
 insert into customer_affiliates(customer_id,status) values(ref,'active'),(ref2,'active'),(ref5,'active');
 insert into payment_methods(name,is_active) values('PPE Cash',true) returning id into m;
 insert into products(name,sku,product_type) values('PPE Item','PPEI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50);
 perform set_product_prices(st,p,1000,1000,'available');
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('PPE Package',1000,1000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
   values('PPE Bundle',2000,2000,200,0,false) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values(pb,st);
 update app_settings set staff_commission_rate=3, commission_tier1_own_rate=15, commission_tier2_own_rate=35,
   commission_tier1_third_rate=4.5, commission_tier2_third_rate=35, instalment_commission_from=null where id=true;

 perform pg_temp.check((select instalment_commission_from from app_settings where id=true) is null, 'fixture: the switch starts off');

 -- L1: product, 250 of 1000 paid.
 l1:=create_invoice_with_details(st,buyer,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(l1,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',250)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l1)=0 and pg_temp.aff(l1)=0,
   'switch off: a part payment registers nothing yet (it waits for the owner to review the backfill)');

 -- L2: product, 400 paid, carrying the 3 rows the old correction path wrote (the INV-2026-0282 state).
 l2:=create_invoice_with_details(st,buyer,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(l2,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',400)),gen_random_uuid());
 insert into staff_commissions(invoice_id,staff_id,store_id,invoice_total,share_ratio,rate,commission_amount,status,invoice_paid_date)
 select l2, x, st, 400, 0.333333, 3, 4.00, 'earned', sg_today() from unnest(array[s1,s2,s3]) x;

 -- L3: credit package 300 of 1000.  L4: premium bundle 500 of 2000.
 l3:=create_invoice(st,buyer,null::uuid,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)),0::numeric,null::text,null::uuid,'[]'::jsonb);
 perform record_invoice_payment(l3,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',300)),gen_random_uuid());
 l4:=create_invoice(st,buyer,null::uuid,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'voucher_selection','[]'::jsonb)),0::numeric,null::text,null::uuid,'[]'::jsonb);
 perform record_invoice_payment(l4,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',500)),gen_random_uuid());
 perform pg_temp.check((select credit_issued_at from invoice_items where invoice_id=l4) is null
    and not exists(select 1 from premium_bundle_sales where invoice_id=l4) and not exists(select 1 from credit_package_sales where invoice_id=l3),
   'part-paid package and bundle are not sold yet (no sale row to earn settlement commission early)');

 insert into fx values('own',own),('s1',s1),('s2',s2),('s3',s3),('st',st),('m',m),('p',p),('l1',l1),('l2',l2),('l3',l3),('l4',l4),
   ('buyer',buyer),('ref',ref),('ref2',ref2),('ref5',ref5),('buyer5',buyer5),('cp',cp),('pb',pb);
end $$;

-- ═════ Re-running the migration: patches stay put, the old rows are relabelled ═════
\ir ../../../supabase/357_part_payments_earn_commission.sql
select set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);

do $$
declare l2 uuid:=pg_temp.fx('l2'); m uuid:=pg_temp.fx('m'); pay uuid; d text;
begin
 d := pg_get_functiondef('public.reconcile_invoice_commissions(uuid,text)'::regprocedure);
 perform pg_temp.check((length(d)-length(replace(d,'sync_instalment_commissions','')))/length('sync_instalment_commissions')=1,
   're-running 357 does not patch reconcile twice');
 perform pg_temp.check((select count(*) from staff_commissions where invoice_id=l2 and earning_basis='instalment' and status='earned')=3
    and pg_temp.staff_live(l2)=12, 'the 3 rows the old correction path wrote are relabelled instalment; amounts unchanged');

 -- THE DOUBLE-PAY PATH: a same-amount correction on the part-paid invoice.
 select id into pay from invoice_payments where invoice_id=l2;
 perform correct_invoice_payment(pay,400,sg_today(),m,'typo check',gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l2)=12 and pg_temp.aff(l2)=0 and pg_temp.layer(l2,'settlement')=0,
   'a correction on a part-paid invoice no longer earns settlement commission');
 -- ...and settling it (switch still off) pays exactly full settlement, not 12.00 more.
 perform record_invoice_payment(l2,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',600)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l2)=30 and pg_temp.aff(l2)=202.50,
   format('INV-2026-0282 case settles at 30.00 staff / 202.50 affiliate (was 42.00), got %s / %s', pg_temp.staff_live(l2), pg_temp.aff(l2)));
 perform pg_temp.check((select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=l2 and earning_basis='instalment' and status in ('earned','paid'))=12
    and (select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=l2 and earning_basis='settlement' and status in ('earned','paid'))=18,
   'the 12.00 stays with the staff who earned it; settlement pays only the other 18.00');
end $$;

-- ═════ The owner reviews, then registers, the earlier part payments ═════
do $$
declare v_staff numeric; v_aff numeric; n_staff int; n_aff int; n_audit int; s1 uuid:=pg_temp.fx('s1');
begin
 select count(*) into n_staff from staff_commissions;
 select count(*) into n_aff from commissions;
 select count(*) into n_audit from audit_logs;
 select coalesce(sum(earned_amount) filter (where ledger='staff'),0), coalesce(sum(earned_amount) filter (where ledger='affiliate'),0)
   into v_staff, v_aff from commission_instalment_backfill(false) where invoice_id in (pg_temp.fx('l1'),pg_temp.fx('l3'),pg_temp.fx('l4'));
 perform pg_temp.check(v_staff=31.50, format('review: staff 31.50 (L1 7.50 + package 9.00 + bundle 15.00), got %s', v_staff));
 perform pg_temp.check(v_aff=99.24, format('review: affiliate 99.24 (L1 37.50+13.13, package 13.50+4.73, bundle 22.50+7.88), got %s', v_aff));
 perform pg_temp.check((select count(*) from staff_commissions)=n_staff and (select count(*) from commissions)=n_aff
    and (select count(*) from audit_logs)=n_audit, 'the review writes nothing, not even an audit row');
 perform pg_temp.check((select count(*) from commission_instalment_backfill(false) where ledger='staff' and invoice_id=pg_temp.fx('l1'))=3,
   'the review lists each staff member per invoice');

 -- Who may do it.
 perform set_config('request.jwt.claim.sub', s1::text, true);
 begin
   perform * from commission_instalment_backfill(false);
   raise exception 'FAIL: a staff member could review part-payment commission';
 exception when others then
   if sqlerrm like 'FAIL:%' then raise; end if;
   raise notice 'PASS  a staff member cannot review or register it';
 end;
 perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);

 -- Refusals that protect what the owner read.
 begin
   perform * from commission_instalment_backfill(true, null, 999);
   raise exception 'FAIL: a stale total was accepted';
 exception when others then
   if sqlerrm not like 'The part-payment total is now%' then raise; end if;
   raise notice 'PASS  registering refuses a total that differs from the review';
 end;
 begin
   perform * from commission_instalment_backfill(true, (date_trunc('month', sg_today()::timestamp) - interval '1 day')::date, v_staff+v_aff);
   raise exception 'FAIL: a credit date in an earlier month was accepted';
 exception when others then
   if sqlerrm not like 'The credit date must be%' then raise; end if;
   raise notice 'PASS  registering refuses a credit date outside the current month';
 end;
 perform pg_temp.check((select instalment_commission_from from app_settings where id=true) is null, 'refusals leave the switch off');

 -- Commission and the staff-sales receipts are confirmed separately (358).
 select coalesce(sum(earned_amount) filter (where ledger<>'sales'),0), coalesce(sum(earned_amount) filter (where ledger='sales'),0)
   into v_staff, v_aff from commission_instalment_backfill(false);
 perform * from commission_instalment_backfill(true, null, v_staff, v_aff);
 perform pg_temp.check((select instalment_commission_from from app_settings where id=true)=sg_today(), 'registering turns part-payment commission on');
 perform pg_temp.check(pg_temp.staff_live(pg_temp.fx('l1'))=7.50 and pg_temp.aff(pg_temp.fx('l1'))=50.63,
   'L1 now holds 7.50 staff and 37.50+13.13 affiliate');
 perform pg_temp.check((select count(*) from staff_commissions where invoice_id=pg_temp.fx('l1') and staff_id=s1)=1
    and (select count(*) from staff_commissions where invoice_id=pg_temp.fx('l1'))=3, 'the staff share is split among the 3 store staff');
 perform pg_temp.check((select count(*) from commission_instalment_backfill(false))=0, 'a second review finds nothing left to register');
 perform pg_temp.check(not exists(select 1 from staff_commissions where earning_basis='instalment' and invoice_paid_date<>sg_today()
                                    and invoice_id in (pg_temp.fx('l1'),pg_temp.fx('l3'),pg_temp.fx('l4'))),
   'every registered row is dated on the credit date');
 perform pg_temp.check(exists(select 1 from audit_logs where action='instalment_commission_backfilled'), 'registering is audited');
end $$;

-- ═════ Live: more money, corrections, removal ═════
do $$
declare l1 uuid:=pg_temp.fx('l1'); m uuid:=pg_temp.fx('m'); pay uuid; n int; a int;
begin
 perform record_invoice_payment(l1,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',350)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l1)=18 and pg_temp.aff(l1)=121.50,
   'a further 350 (600/1000) earns proportionally: staff 18.00, affiliate 90.00+31.50');
 select count(*) into n from staff_commissions;
 select count(*) into a from audit_logs where action='instalment_commission_synced';
 perform * from sync_instalment_commissions(l1,'rerun');
 perform * from sync_instalment_commissions(l1,'rerun');
 perform pg_temp.check((select count(*) from staff_commissions)=n and pg_temp.staff_live(l1)=18 and pg_temp.aff(l1)=121.50
    and (select count(*) from audit_logs where action='instalment_commission_synced')=a,
   'idempotent: re-running writes nothing, not even an audit row');
 select id into pay from invoice_payments where invoice_id=l1 and amount=350;
 perform correct_invoice_payment(pay,350,sg_today(),m,'same amount',gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l1)=18 and pg_temp.aff(l1)=121.50 and pg_temp.layer(l1,'settlement')=0,
   'a same-amount correction changes nothing and earns no settlement rows');
 select id into pay from invoice_payments where invoice_id=l1 and entry_kind='correction_replacement';
 perform remove_invoice_payment(pay,'bounced',gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l1)=7.50 and pg_temp.aff(l1)=50.63, 'removing the 350 takes it back proportionally (250/1000)');
 -- Each staff member held 2.50 + 3.50 on this date; each gives back 3.50 of it
 -- (in proportion to what they hold there), their rows reversed and 2.50 written again.
 perform pg_temp.check(not exists(select 1 from staff_commissions where invoice_id=l1 and commission_amount<0)
    and (select count(distinct staff_id) from staff_commissions where invoice_id=l1 and status='reversed')=3
    and (select array_agg(t order by t) from (select sum(commission_amount) t from staff_commissions
          where invoice_id=l1 and status in ('earned','paid') group by staff_id) q)=array[2.50,2.50,2.50]::numeric[]
    and not exists(select 1 from staff_commissions where invoice_id=l1 and status in ('earned','paid')
                    and invoice_paid_date<>sg_today()),
   'money leaving takes the unpaid rows back where they stand, shared by every holder (2.50 each left); no negative rows');
 perform pg_temp.check(not exists(select 1 from commissions where invoice_id=l1 and commission_amount<0),
   'affiliate: the same, unpaid rows reversed in place');
end $$;

-- ═════ A payout, then settlement ═════
do $$
declare l1 uuid:=pg_temp.fx('l1'); m uuid:=pg_temp.fx('m'); s1 uuid:=pg_temp.fx('s1'); v_paid jsonb; pid uuid;
begin
 pid:=create_staff_commission_payout(s1, sg_today(), m, 'ppe', null);
 select jsonb_agg(to_jsonb(sc) order by id) into v_paid from staff_commissions sc where payout_id=pid;
 perform pg_temp.check(v_paid is not null, 'staff A was paid out part-payment commission');
 perform record_invoice_payment(l1,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',750)),gen_random_uuid());
 perform pg_temp.check((select status from invoices where id=l1)='paid', 'L1 settled');
 perform pg_temp.check(pg_temp.staff_live(l1)=30 and pg_temp.aff(l1)=202.50,
   'part payments + settlement = 30.00 staff / 202.50 affiliate = full settlement alone');
 perform pg_temp.check((select coalesce(sum(commission_amount),0) from commissions where invoice_id=l1 and earning_basis='instalment' and status in ('earned','paid'))=0,
   'affiliate: the part-payment rows close to zero; settlement pays the full amount to the same people');
 perform pg_temp.check((select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=l1 and earning_basis='instalment' and status in ('earned','paid'))=7.50
    and (select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=l1 and earning_basis='settlement' and status in ('earned','paid'))=22.50,
   'staff: the 7.50 part payments registered stays; settlement pays the other 22.50');
 perform pg_temp.check(v_paid=(select jsonb_agg(to_jsonb(sc) order by id) from staff_commissions sc where payout_id=pid),
   'rows in the staff payout are byte-for-byte unchanged');
 perform pg_temp.check(not exists(select 1 from staff_commissions where invoice_id=l1 and staff_id=s1 and commission_amount<0)
    and (select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=l1 and staff_id=s1 and status in ('earned','paid'))=10,
   'staff A keeps the 2.50 paid out and gets 7.50 of the rest: 10.00, nothing taken back');
 perform pg_temp.check(
   (select jsonb_agg(jsonb_build_array(referrer_customer_id,tier::text,product_type,invoice_item_id,line_amount,rate,commission_amount,status::text) order by tier, commission_amount)
      from commissions where invoice_id=l1 and earning_basis='settlement')
   = (select jsonb_agg(jsonb_build_array(o_referrer,o_tier,o_product_type,o_invoice_item_id,o_line_amount,o_rate,o_amount,o_status) order by o_tier, o_amount)
        from invoice_affiliate_commission_preview(l1)),
   'the preview is exactly what earn_invoice_commission wrote');
 perform correct_invoice_payment((select id from invoice_payments where invoice_id=l1 and amount=750),750,sg_today(),m,'same',gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l1)=30 and pg_temp.aff(l1)=202.50, 'a later reconcile on the settled invoice keeps 30.00 / 202.50');
 perform apply_commission_rebase_all();
 perform pg_temp.check(pg_temp.staff_live(l1)=30, 'the staff rebase keeps 30.00 (it leaves the instalment layer alone)');
end $$;

-- ═════ Packages and bundles settle consistently ═════
do $$
declare l3 uuid:=pg_temp.fx('l3'); l4 uuid:=pg_temp.fx('l4'); m uuid:=pg_temp.fx('m');
begin
 perform record_invoice_payment(l3,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',700)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l3)=30 and pg_temp.aff(l3)=60.75,
   format('credit package: part + settlement = 30.00 staff / 45.00+15.75 affiliate, got %s / %s', pg_temp.staff_live(l3), pg_temp.aff(l3)));
 perform record_invoice_payment(l4,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1500)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l4)=60 and pg_temp.aff(l4)=121.50,
   format('premium bundle: part + settlement = 60.00 staff / 90.00+31.50 affiliate, got %s / %s', pg_temp.staff_live(l4), pg_temp.aff(l4)));
 perform pg_temp.check((select coalesce(sum(commission_amount),0) from commissions where invoice_id in (l3,l4) and earning_basis='instalment' and status in ('earned','paid'))=0,
   'both affiliate part-payment layers closed; staff part-payment shares stay (9.00 + 15.00)');
end $$;

-- ═════ An earlier month already paid out ═════
do $$
declare st uuid:=pg_temp.fx('st'); p uuid:=pg_temp.fx('p'); m uuid:=pg_temp.fx('m');
 buyer5 uuid:=pg_temp.fx('buyer5'); ref5 uuid:=pg_temp.fx('ref5'); s1 uuid:=pg_temp.fx('s1');
 l5 uuid; prev date := (date_trunc('month', sg_today()::timestamp) - interval '1 month')::date + 14; prev_m date; pid uuid; apid uuid;
 v_staff jsonb; v_aff jsonb; cur_m date := date_trunc('month', sg_today()::timestamp)::date;
begin
 prev_m := date_trunc('month', prev::timestamp)::date;
 l5:=create_invoice_with_details(st,buyer5,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(l5,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',400)),gen_random_uuid());
 -- as if this part payment had been registered last month
 update staff_commissions set invoice_paid_date=prev where invoice_id=l5;
 update commissions set invoice_paid_date=prev where invoice_id=l5;
 pid:=create_staff_commission_payout(s1, prev, m, 'prev month', null);
 apid:=((record_affiliate_payout(ref5, prev_m, 40, m, sg_today(), 'part of 60', null, gen_random_uuid()))->>'id')::uuid;
 select jsonb_agg(to_jsonb(x) order by id) into v_staff from staff_commissions x where payout_id=pid;
 select jsonb_agg(to_jsonb(x) order by id) into v_aff from commission_payout_allocations x where payout_id=apid;
 perform record_invoice_payment(l5,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',600)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l5)=30 and pg_temp.aff(l5)=150, 'cross-month: the total is still exactly full settlement (30.00 / 150.00)');
 perform pg_temp.check(v_staff=(select jsonb_agg(to_jsonb(x) order by id) from staff_commissions x where payout_id=pid)
   and v_aff=(select jsonb_agg(to_jsonb(x) order by id) from commission_payout_allocations x where payout_id=apid),
   'last month''s staff and affiliate payouts are untouched');
 if date_trunc('month', (now() at time zone 'UTC')) <> date_trunc('month', sg_today()::timestamp) then
   -- Settlement rows are dated on the UTC date (a known, accepted split): in the
   -- first 8 hours of a Singapore month they fall in the previous month.
   raise notice 'SKIP  month split checks: run between 00:00 and 07:59 on the 1st (Singapore)';
   return;
 end if;
 perform pg_temp.check((select balance from affiliate_month_balances() where referrer=ref5 and month=prev_m)=20,
   'last month: 60 earned, 40 paid out, 20 still payable where it was earned');
 perform pg_temp.check((select balance from affiliate_month_balances() where referrer=ref5 and month=cur_m)=90,
   'this month: settlement 150 less the 60 already registered = 90');
 perform pg_temp.check((select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=l5 and invoice_paid_date between prev_m and prev)=12
   and (select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=l5 and invoice_paid_date>=cur_m)=18,
   'staff: 12.00 stays in last month, 18.00 lands this month');
end $$;

-- ═════ Cancelling a part-paid invoice ═════
do $$
declare st uuid:=pg_temp.fx('st'); p uuid:=pg_temp.fx('p'); m uuid:=pg_temp.fx('m'); buyer5 uuid:=pg_temp.fx('buyer5'); l6 uuid;
begin
 l6:=create_invoice_with_details(st,buyer5,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(l6,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',300)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l6)=9 and pg_temp.aff(l6)=45, 'L6 300/1000 earns 9.00 / 45.00');
 perform cancel_invoice_recorded(l6,'customer withdrew',gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(l6)=0 and pg_temp.aff(l6)=0, 'cancelling a part-paid invoice takes it all back');
 perform pg_temp.check(not exists(select 1 from staff_commissions where invoice_id=l6 and commission_amount<0)
    and not exists(select 1 from commissions where invoice_id=l6 and commission_amount<0),
   'unpaid part-payment rows are reversed where they stand, so no earlier month keeps them');
end $$;

-- ═════ Wallet credit, roster changes, referrers who are not activated ═════
do $$
declare st uuid:=pg_temp.fx('st'); p uuid:=pg_temp.fx('p'); m uuid:=pg_temp.fx('m'); own uuid:=pg_temp.fx('own');
 s1 uuid:=pg_temp.fx('s1'); s3 uuid:=pg_temp.fx('s3'); buyer uuid:=pg_temp.fx('buyer'); wpm uuid; inv uuid; lot uuid;
 ref_na uuid; buyer2 uuid;
begin
 select id into wpm from payment_methods where wallet_category='paid' and is_system limit 1;
 -- wallet credit never earns; cash does
 lot:=grant_customer_credit(buyer,'paid',400,'opening_balance',null,st,sg_today(),null,'test',null,null,own,null);
 inv:=create_invoice_with_details(st,buyer,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',wpm,'amount',400)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(inv)=0 and pg_temp.aff(inv)=0, '400 of wallet credit on 1000 earns nothing');
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',300)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(inv)=9 and pg_temp.aff(inv)=60.75,
   format('+300 cash earns on the cash only: 9.00 / 45.00+15.75 (300 of the 600 cash due), got %s / %s', pg_temp.staff_live(inv), pg_temp.aff(inv)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',300)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(inv)=18 and pg_temp.aff(inv)=121.50, 'settled: 18.00 / 90.00+31.50 = full settlement on the 600 cash');

 -- the roster on the day the money arrives shares it
 inv:=create_invoice_with_details(st,buyer,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',300)),gen_random_uuid());
 update profiles set is_active=false where id=s3;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',300)),gen_random_uuid());
 perform pg_temp.check((select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=inv and staff_id=s3)=3
    and (select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=inv and staff_id=s1)=7.50,
   'staff C shares only the payment made while C was on the roster (3.00); A gets 3.00+4.50');
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',400)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(inv)=30, 'settled with a changed roster: the total is still 30.00');
 perform pg_temp.check((select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=inv and staff_id=s3 and status in ('earned','paid'))=3
    and (select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id=inv and staff_id=s1 and status in ('earned','paid'))=13.50,
   'after settlement C keeps the 3.00 earned while on the roster; A and B share the rest (3.00+4.50+6.00 each)');
 update profiles set is_active=true where id=s3;

 -- not activated: recorded as blocked, never payable, not duplicated
 insert into customers(full_name,phone) values('PPE NotActivated','+6598917006') returning id into ref_na;
 insert into customers(full_name,phone,referred_by) values('PPE Buyer2','+6598917007',ref_na) returning id into buyer2;
 inv:=create_invoice_with_details(st,buyer2,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',500)),gen_random_uuid());
 perform pg_temp.check(pg_temp.aff(inv)=0 and pg_temp.aff(inv,'blocked')=75, 'not-activated referrer: 75.00 recorded as blocked, 0 payable');
 perform * from sync_instalment_commissions(inv,'rerun');
 perform pg_temp.check((select count(*) from commissions where invoice_id=inv)=1, 'blocked rows are not duplicated on a re-run');
 insert into customer_affiliates(customer_id,status) values(ref_na,'active');
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',200)),gen_random_uuid());
 perform pg_temp.check(pg_temp.aff(inv)=105 and pg_temp.aff(inv,'blocked')=0, 'activated mid-way: 105.00 earned (70% of 150), blocked replaced');
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',300)),gen_random_uuid());
 perform pg_temp.check(pg_temp.aff(inv)=150 and pg_temp.aff(inv,'blocked')=0, 'settled: 150.00 = full settlement alone');
end $$;

-- ═════ A settled invoice that falls back to part-paid, then is paid again ═════
do $$
declare st uuid:=pg_temp.fx('st'); p uuid:=pg_temp.fx('p'); m uuid:=pg_temp.fx('m'); buyer uuid:=pg_temp.fx('buyer'); inv uuid; pay uuid;
begin
 inv:=create_invoice_with_details(st,buyer,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',400)),gen_random_uuid());
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',600)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(inv)=30 and pg_temp.aff(inv)=202.50, 'settled: 30.00 / 202.50');
 select id into pay from invoice_payments where invoice_id=inv and amount=600;
 perform remove_invoice_payment(pay,'cheque bounced',gen_random_uuid());
 perform pg_temp.check((select status from invoices where id=inv)='partially_paid' and pg_temp.staff_live(inv)=12 and pg_temp.aff(inv)=81,
   format('bounced back to 400/1000: 12.00 / 81.00 on the money still held, got %s / %s', pg_temp.staff_live(inv), pg_temp.aff(inv)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',600)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(inv)=30 and pg_temp.aff(inv)=202.50,
   format('paid again: exactly full settlement once (was 42.00 / 283.50 before), got %s / %s', pg_temp.staff_live(inv), pg_temp.aff(inv)));
end $$;

-- ═════ Rounding, stores with no staff, registering twice ═════
do $$
declare own uuid:=pg_temp.fx('own'); m uuid:=pg_temp.fx('m'); st7 uuid; st0 uuid; p uuid; c uuid; inv uuid; i int; x uuid; n int;
begin
 insert into stores(name,code,country_code) values('PPE Seven','PPE7','SG') returning id into st7;
 insert into stores(name,code,country_code) values('PPE Empty','PPE0','SG') returning id into st0;
 for i in 1..7 loop
   x := gen_random_uuid();
   insert into auth.users(id,email) values(x,'ppe7-'||i||'@tests.invalid');
   insert into profiles(id,full_name,email,role) values(x,'PPE Seven '||i,'ppe7-'||i||'@tests.invalid','staff');
   insert into user_store_assignments(user_id,store_id) values(x,st7);
 end loop;
 insert into customers(full_name,phone) values('PPE Seven Buyer','+6598917011') returning id into c;
 insert into products(name,sku,product_type) values('PPE Small','PPES7','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st7,p,50),(st0,p,50);
 perform set_product_prices(st7,p,100,100,'available');
 perform set_product_prices(st0,p,100,100,'available');
 inv:=create_invoice_with_details(st7,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1.37)),gen_random_uuid());
 perform pg_temp.check(pg_temp.staff_live(inv)=0.04 and not exists(select 1 from staff_commissions where invoice_id=inv and commission_amount<0),
   '4 cents among 7 staff: one cent each to four people, nobody gets a negative row');
 inv:=create_invoice_with_details(st0,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',30)),gen_random_uuid());
 perform * from sync_instalment_commissions(inv,'rerun');
 perform * from sync_instalment_commissions(inv,'rerun');
 select count(*) into n from audit_logs where record_id=inv and action='staff_commission_skipped_no_staff';
 perform pg_temp.check(n=1, format('a store with no commission staff is noted once, not on every sync (got %s)', n));
 begin
   perform * from commission_instalment_backfill(true, null, 0, 0);
   raise exception 'FAIL: registering a second time was accepted';
 exception when others then
   if sqlerrm like 'FAIL:%' then raise; end if;
   if sqlerrm not like '%already on%' then raise; end if;
   raise notice 'PASS  registering again once it is on is refused';
 end;
 perform pg_temp.check((select count(*) from commission_instalment_backfill(false))=0, 'and the review is empty once it is on');
end $$;

-- ═════ An exchange top-up paid in part ═════
do $$
declare st uuid:=pg_temp.fx('st'); m uuid:=pg_temp.fx('m'); s1 uuid:=pg_temp.fx('s1'); cust uuid; p uuid; p2 uuid;
 inv uuid; res jsonb; ex uuid; exinv uuid; pos jsonb; arr uuid;
begin
 insert into customers(full_name,phone) values('PPE Exchanger','+6598917008') returning id into cust;
 insert into products(name,sku,product_type) values('PPE Old','PPEO','own') returning id into p;
 insert into products(name,sku,product_type) values('PPE New','PPEN','own') returning id into p2;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50),(st,p2,50);
 perform set_product_prices(st,p,500,500,'available');
 perform set_product_prices(st,p2,1500,1500,'available');
 inv:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',500)),gen_random_uuid());
 res:=create_exchange_with_details('product',jsonb_build_object(
   'original_invoice_id',inv,'processing_store_id',st,
   'returned',jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)),
   'replacement',jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',1)),
   'payments',jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',100)),
   'arrangements',jsonb_build_array(jsonb_build_object('key','plan','category','in_house','method_id',m,'months',12,'covered_amount',900)),
   'reason','Upgrade','served_by',jsonb_build_array(s1::text)));
 ex:=(res->>'id')::uuid;
 select id into exinv from invoices where exchange_id=ex and is_exchange;
 perform pg_temp.check((select status from invoices where id=exinv)='partially_paid', 'exchange: the replacement invoice is part paid');
 perform pg_temp.check(pg_temp.staff_live(exinv)=3, format('exchange: the 100 received earns 3.00 staff (the 900 promised earns nothing), got %s', pg_temp.staff_live(exinv)));
 pos:=exchange_payment_position(ex);
 select arrangement_id::uuid into arr from jsonb_to_recordset(pos->'arrangements') as t(arrangement_id text) limit 1;
 res:=record_invoice_settlement(exinv,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','m1','payment_method_id',m,'amount',900)),
   'arrangements',jsonb_build_array(jsonb_build_object('arrangement_id',arr,'receipt_key','m1'))),gen_random_uuid());
 perform pg_temp.check((select status from invoices where id=exinv)='paid' and pg_temp.staff_live(exinv)=30,
   format('exchange settled: 30.00 staff, exactly full settlement, got %s', pg_temp.staff_live(exinv)));
end $$;

rollback;
