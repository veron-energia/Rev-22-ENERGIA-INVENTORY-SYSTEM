-- The Reports page shows what it says (367).
--
--   A1 Sales Reconciliation's TikTok line is TikTok sales (revenue less fees,
--      sale rows only), dated by the Singapore date TikTok settled the row.
--   A2 The FOC cards total the FOC lines listed beneath them.
--   A3 Pricing names promotion lines instead of "item".
--   A4 An ad payment (Settlement = Adjustment) is not a reconciliation warning
--      in any report or on the Dashboard, and staging stores new ones as
--      reconciled; a real gap is still flagged.
--   A5 The Therapy report returns a legacy entitlement's activation and expiry.
--   A6 Periods on Exchange Invoices, Transfer receipts and Sources are
--      Singapore dates (00:30 on 1 Sep in Singapore is 31 Aug in UTC).
--   A7 Wallet credit not counted is net of wallet credit refunded; the report
--      still adds up to revenue.
--   A8 A deleted referred customer is not a referral.
--   A9 A manual line's discrepancy is listed.
--   A10 Receipts name every source of a multi-source dispatch, and count
--       catalogue units only.
--
-- Every check runs, then the file fails if any did, so a run on the pre-367
-- functions lists everything 367 changes. Disposable database only; everything
-- is rolled back. Fixtures carry a random suffix so the file can run beside
-- other suites on a shared database.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- Production's user_has_store_access (29 Sep 2026): Owners and Admins see every
-- store, anyone else only their assigned stores. Local databases may carry an
-- older one; this keeps the run faithful and is rolled back with the rest.
create or replace function public.user_has_store_access(target_store_id uuid)
 returns boolean language sql security definer set search_path to 'public' as $f$
  select exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner','admin'))
  or exists (select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true)
$f$;
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k=key $$;
-- A free fixture phone, +65 9123 xxxx.
create function pg_temp.phone() returns text language sql volatile as $$
  select '+659123' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
   where not exists (select 1 from public.customers c
                      where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = '659123' || lpad(n::text, 4, '0'))
   order by random() limit 1
$$;

-- ═════ Fixtures ═════
do $$
declare o uuid:=gen_random_uuid(); sfx text:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
 st uuid; cust uuid; cash uuid; wpm uuid; p uuid; p2 uuid; promo uuid; b uuid;
 inv_f uuid; inv_p uuid; inv_w uuid; it uuid; pay uuid; mv uuid;
 x uuid; y1 uuid; y2 uuid; z1 uuid; z2 uuid; w1 uuid; w2 uuid; t1 uuid; t2 uuid; l1 uuid; l2 uuid; opt uuid;
begin
 insert into auth.users(id,email) values(o,'r367-o-'||lower(sfx)||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'R367 Owner','r367-o-'||lower(sfx)||'@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('R367 Store '||sfx,'R367'||sfx,'SG') returning id into st;
 insert into customers(full_name,phone) values('R367 Buyer',pg_temp.phone()) returning id into cust;
 insert into payment_methods(name,is_active) values('R367 Cash '||sfx,true) returning id into cash;
 select id into wpm from payment_methods where wallet_category='paid' and is_system limit 1;
 insert into products(name,sku,product_type) values('R367 Item','R367-A-'||sfx,'own') returning id into p;
 insert into products(name,sku,product_type) values('R367 Half','R367-B-'||sfx,'own') returning id into p2;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50),(st,p2,50);
 perform set_product_prices(st,p,100,100,'available');
 perform set_product_prices(st,p2,50,50,'available');
 insert into tx values('sfx',sfx),('store_name','R367 Store '||sfx);

 -- A1 + A4: confirmed settlement rows, stored as staging stored them before 367.
 -- 16:30 UTC on 10 Aug is 00:30 on 11 Aug in Singapore. The Dashboard counts
 -- every store, so note its count first.
 insert into tx values('mismatches_before',dashboard_alerts_summary()->'tiktok'->>'settlement_mismatches');
 insert into tiktok_import_batches(store_id,file_kind,file_name,uploaded_by,status)
   values(st,'settlement','r367.xlsx',o,'confirmed') returning id into b;
 insert into tiktok_settlement_rows(batch_id,store_id,row_no,order_id,transaction_type,txn_class,
   settlement_amount,revenue_amount,fee_amount,adjustment_amount,currency,order_created_time,settled_time,
   match_status,matched_order_id,staging_status,excluded,confirmed,is_current,version_no,reconciled) values
  -- a sale: revenue 100, fees 20
  (b,st,1,'R367-O1-'||sfx,'Order','order',80,100,-20,0,'SGD','2026-08-05 16:00+00','2026-08-10 16:30+00',
   'matched','R367-O1-'||sfx,'New — Matched',false,true,true,1,true),
  -- a refund of a sale: 30 back, 5 of fees returned
  (b,st,2,'R367-R1-'||sfx,'Refund','refund',-25,-30,5,0,'SGD','2026-08-05 16:00+00','2026-08-11 16:00+00',
   'pending',null,'New — Pending Order',false,true,true,1,true),
  -- an ad payment: the whole amount in Settlement and in Adjustment
  (b,st,3,'R367-A1-'||sfx,'GMV payment for TikTok Ads','finance',-50,0,0,-50,'SGD',null,'2026-08-10 16:30+00',
   'no_match_needed',null,'New — No Match Needed',false,true,true,1,false),
  -- money moved to the seller's bank: not a sale, and not a warning either
  (b,st,4,'R367-T1-'||sfx,'Transfer to bank account','finance',-200,0,0,-200,'SGD',null,'2026-08-10 16:30+00',
   'no_match_needed',null,'New — No Match Needed',false,true,true,1,false),
  -- a sale whose figures do not agree (a real warning)
  (b,st,5,'R367-M1-'||sfx,'Order','order',10,12,-1,0,'SGD','2026-09-01 04:00+00','2026-09-02 04:00+00',
   'pending',null,'New — Pending Order',false,true,true,1,false),
  -- an ad payment whose figures do not agree (still a warning)
  (b,st,6,'R367-F2-'||sfx,'GMV payment for TikTok Ads','finance',-40,0,0,-30,'SGD',null,'2026-09-02 04:00+00',
   'no_match_needed',null,'New — No Match Needed',false,true,true,1,false),
  -- a bank transfer with only its Settlement cell filled in: nothing to
  -- reconcile against, so no verdict (stored null) and no warning
  (b,st,7,'R367-N1-'||sfx,'Transfer to bank account','finance',-300,null,null,null,'SGD',null,'2026-08-10 16:30+00',
   'no_match_needed',null,'New — No Match Needed',false,true,true,1,null);

 -- A2: 2 x 100 with one free, and 1 x 50: normal 250, FOC 100, charged 150.
 inv_f:=create_invoice_with_details(st,cust,jsonb_build_array(
   jsonb_build_object('kind','product','product_id',p,'quantity',2),
   jsonb_build_object('kind','product','product_id',p2,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv_f and product_id=p;
 perform apply_line_foc(it,1,null,'R367 sample');
 perform record_invoice_payment(inv_f,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',
   (select total_amount from invoices where id=inv_f))),gen_random_uuid());

 -- A3: a promotion line.
 insert into promotions(name,code) values('R367 Promo','R367-P-'||sfx) returning id into promo;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(promo,'product',p2,1);
 insert into promotion_store_prices(promotion_id,store_id,selling_price) values(promo,st,80);
 inv_p:=create_invoice_with_details(st,cust,jsonb_build_array(
   jsonb_build_object('kind','promotion','promotion_id',promo,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv_p,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',
   (select total_amount from invoices where id=inv_p))),gen_random_uuid());

 -- A5: a legacy entitlement with its own dates.
 insert into therapy_entitlements(entitlement_no,customer_id,store_id,package_name,entitlement_kind,
   qualifying_amount,qualified_value,activation_deadline,activation_date,expiry_date,status)
 values('R367-L-'||sfx,cust,st,'R367 Legacy','unlimited',0,0,'2026-10-31','2026-09-01','2026-12-01','active');

 -- A6: an exchange and a survey at 01:00 on 1 Sep in Singapore (17:00 UTC on 31 Aug).
 insert into product_exchanges(exchange_no,original_invoice_id,customer_id,processing_store_id,created_at)
   values('R367-X-'||sfx,inv_f,cust,st,'2026-08-31 17:00+00');
 insert into customer_source_options(label,is_active,sort_order) values('R367 Source '||sfx,true,9999) returning id into opt;
 insert into health_surveys(survey_no,full_name,source_option_id,submitted_at)
   values('R367-S-'||sfx,'R367 Survey',opt,'2026-08-31 17:00+00');

 -- A7: 2 x 100 paid entirely with wallet credit, then one unit refunded to the wallet.
 perform grant_customer_credit(cust,'paid',200,'opening_balance',null,st,sg_today(),null,'test',null,null,o,null);
 inv_w:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv_w,jsonb_build_array(jsonb_build_object('payment_method_id',wpm,'amount',200)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv_w;
 select id into pay from invoice_payments where invoice_id=inv_w;
 select id into mv from stock_movements where invoice_id=inv_w and movement_type='store_sale';
 perform refund_invoice_recorded(inv_w,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),
   jsonb_build_array(jsonb_build_object('movement_id',mv,'sellable_quantity',1)),'R367 one unit back to the wallet',gen_random_uuid());

 -- A8: X referred Y1 and Y2; Y1 referred Z1, Y2 referred Z2; then Y2 was deleted.
 insert into customers(full_name,phone) values('R367 Referrer',pg_temp.phone()) returning id into x;
 insert into customers(full_name,phone,referred_by) values('R367 Referred One',pg_temp.phone(),x) returning id into y1;
 insert into customers(full_name,phone,referred_by) values('R367 Referred Two',pg_temp.phone(),x) returning id into y2;
 insert into customers(full_name,phone,referred_by) values('R367 Second One',pg_temp.phone(),y1) returning id into z1;
 insert into customers(full_name,phone,referred_by) values('R367 Second Two',pg_temp.phone(),y2) returning id into z2;
 update customers set deleted_at=now() where id=y2;

 -- A6 + A9 + A10: a receipt drawn from two warehouses, with a manual line,
 -- received at 01:00 on 1 Sep in Singapore; and a manual line short on arrival.
 insert into warehouses(name,code) values('R367 WH A '||sfx,'R367A'||sfx) returning id into w1;
 insert into warehouses(name,code) values('R367 WH B '||sfx,'R367B'||sfx) returning id into w2;
 insert into transfer_requests(transfer_type,source_type,source_id,dest_type,dest_id,status,requested_by,
   dispatched_at,received_at,received_by,has_discrepancy,discrepancy_resolved)
 values('warehouse_to_store','warehouse',w1,'store',st,'received',o,'2026-08-30 02:00+00','2026-08-31 17:00+00',o,false,false)
 returning id into t1;
 insert into transfer_request_lines(transfer_request_id,product_id,quantity,approved_quantity,in_transit_quantity,received_quantity,line_kind)
   values(t1,p,5,5,5,5,'product') returning id into l1;
 insert into transfer_request_lines(transfer_request_id,product_id,quantity,approved_quantity,in_transit_quantity,received_quantity,line_kind)
   values(t1,p2,3,3,3,3,'product') returning id into l2;
 insert into transfer_request_lines(transfer_request_id,quantity,approved_quantity,in_transit_quantity,received_quantity,line_kind,manual_item_name,manual_uom)
   values(t1,7,7,7,7,'manual','R367 Poster','Unit');
 insert into transfer_line_sources(line_id,source_type,source_id,quantity) values(l1,'warehouse',w1,5),(l2,'warehouse',w2,3);
 insert into transfer_requests(transfer_type,source_type,source_id,dest_type,dest_id,status,requested_by,
   dispatched_at,received_at,received_by,has_discrepancy,discrepancy_resolved)
 values('warehouse_to_store','warehouse',w1,'store',st,'received_with_discrepancy',o,now()-interval '1 day',now(),o,true,false)
 returning id into t2;
 insert into transfer_request_lines(transfer_request_id,quantity,approved_quantity,in_transit_quantity,received_quantity,
   discrepancy_quantity,discrepancy_reason,line_kind,manual_item_name,manual_uom)
   values(t2,4,4,4,2,-2,'R367 two missing','manual','R367 Tape','Roll');

 insert into fx values('o',o),('st',st),('cust',cust),('p',p),('inv_f',inv_f),('inv_p',inv_p),('inv_w',inv_w),
   ('x',x),('t1',t1),('t2',t2),('opt',opt),('w1',w1),('w2',w2);
end $$;

-- ═════ A1: the TikTok line is TikTok sales ═════
do $$
declare st uuid:=pg_temp.fx('st'); r record;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx('o')::text,true);
 select * into r from report_sales_reconciliation(st,null,null) where channel='tiktok_settlement';
 perform pg_temp.check(r.transactions = 3 and r.amount = 66,
   format('A1 all time: the sale, the refund and the mismatched sale, revenue less fees = 3 / 66.00 (not the 6 rows'' settlement -225.00), got %s / %s', r.transactions, r.amount));
 select * into r from report_sales_reconciliation(st,'2026-08-11','2026-08-11') where channel='tiktok_settlement';
 perform pg_temp.check(r.transactions = 1 and r.amount = 80,
   format('A1 11 Aug: the sale settled at 00:30 that day in Singapore = 1 / 80.00 (not by its order date, not in UTC), got %s / %s', r.transactions, r.amount));
 select * into r from report_sales_reconciliation(st,'2026-08-10','2026-08-10') where channel='tiktok_settlement';
 perform pg_temp.check(r.transactions = 0 and r.amount = 0,
   format('A1 10 Aug: nothing settled that day in Singapore, got %s / %s', r.transactions, r.amount));
 select * into r from report_sales_reconciliation(st,'2026-08-27','2026-09-30') where channel='tiktok_settlement';
 perform pg_temp.check(r.transactions = 1 and r.amount = 11,
   format('A1 TikTok''s September (27 Aug-30 Sep): the one sale settled then = 1 / 11.00, got %s / %s', r.transactions, r.amount));
 select * into r from report_sales_reconciliation(st,'2026-08-01','2026-08-31') where channel='tiktok_settlement';
 perform pg_temp.check(r.transactions = 2 and r.amount = 55,
   format('A1 August: the sale and its refund = 2 / 55.00; the ad payment and the bank transfer are not sales, got %s / %s', r.transactions, r.amount));
 perform pg_temp.check((select amount from report_sales_reconciliation(st,null,null) where channel='tiktok_settlement')
     = (select sum((tiktok_settlement_totals(y, m, st)->>'settlement')::numeric) from (values (2026,8),(2026,9)) v(y,m)),
   'A1 the line equals the TikTok tab''s Settlement for the same months');
end $$;

-- ═════ A2: the FOC cards total the FOC lines ═════
do $$
declare st uuid:=pg_temp.fx('st'); s jsonb; l record;
begin
 s := report_foc_summary(null,null,st);
 select coalesce(sum(normal_value),0) n, coalesce(sum(foc_value),0) f, coalesce(sum(charged_value),0) c, count(*) k,
        count(distinct invoice_id) i into l from report_foc_lines(null,null,st);
 perform pg_temp.check((s->>'normal_value')::numeric = 200 and (s->>'foc_value')::numeric = 100 and (s->>'charged_value')::numeric = 100
     and (s->>'foc_units')::numeric = 1,
   format('A2 cards over the FOC line: normal 200, FOC 100, charged 100, 1 unit (not 250 / 150 for the whole invoice), got %s / %s / %s / %s',
     s->>'normal_value', s->>'foc_value', s->>'charged_value', s->>'foc_units'));
 perform pg_temp.check((s->>'normal_value')::numeric = l.n and (s->>'foc_value')::numeric = l.f and (s->>'charged_value')::numeric = l.c,
   format('A2 the cards equal the FOC lines table (%s / %s / %s)', l.n, l.f, l.c));
 perform pg_temp.check((s->>'invoice_count')::int = 1 and (s->>'mixed_foc_invoices')::int = 1 and (s->>'full_foc_invoices')::int = 0
     and l.i = 1 and s ? 'by_kind' and s ? 'by_reason' and s ? 'from',
   'A2 invoice counts and the other keys are unchanged');
end $$;

-- ═════ A3: Pricing names the line ═════
do $$
declare r record;
begin
 select * into r from report_pricing() where invoice_id=pg_temp.fx('inv_p');
 perform pg_temp.check(r.item_name = 'R367 Promo', format('A3 a promotion line is named "R367 Promo", not "item", got %s', r.item_name));
 select * into r from report_pricing() where invoice_id=pg_temp.fx('inv_f') and quantity=2;
 perform pg_temp.check(r.item_name = 'R367 Item', format('A3 a product line keeps its name, got %s', r.item_name));
end $$;

-- ═════ A4: an ad payment is not a reconciliation warning ═════
do $$
declare st uuid:=pg_temp.fx('st'); sfx text:=pg_temp.tx('sfx'); n int; s record; bt uuid;
begin
 select count(*) into n from report_tiktok_settlement(st,null,null) where reconciled is false;
 perform pg_temp.check(n = 2, format('A4 settlement list: only the two real gaps are unreconciled (not 4), got %s', n));
 perform pg_temp.check((select reconciled from report_tiktok_settlement(st,null,null) where order_adjustment_id='R367-A1-'||sfx)
     and (select reconciled from report_tiktok_settlement(st,null,null) where order_adjustment_id='R367-T1-'||sfx),
   'A4 the ad payment and the bank transfer reconcile on their Adjustment');
 perform pg_temp.check((select reconciled is false from report_tiktok_settlement(st,null,null) where order_adjustment_id='R367-F2-'||sfx)
     and (select reconciled is false from report_tiktok_settlement(st,null,null) where order_adjustment_id='R367-M1-'||sfx),
   'A4 an ad payment and a sale that do not add up are still flagged');
 select * into s from report_tiktok_settlement_summary(st,null,null);
 perform pg_temp.check(s.unreconciled_count = 2, format('A4 summary card: 2 reconciliation warnings, got %s', s.unreconciled_count));
 select unreconciled_count into n from report_tiktok_settlement_by_store(null,null) where store_name=pg_temp.tx('store_name');
 perform pg_temp.check(n = 2, format('A4 by store: 2 warnings, got %s', n));
 select count(*) into n from report_tiktok_recon_exceptions(st) where kind='reconciliation_difference';
 perform pg_temp.check(n = 2, format('A4 exceptions: 2 reconciliation differences, got %s', n));
 perform pg_temp.check((select reconciled is null from report_tiktok_settlement(st,null,null) where order_adjustment_id='R367-N1-'||sfx),
   'A4 a bank transfer with only a Settlement figure keeps no verdict (not a warning)');
 select * into s from report_tiktok_recon_exceptions(st) where kind='reconciliation_difference' and order_id='R367-F2-'||sfx;
 perform pg_temp.check(s.amount = -10 and s.detail like 'settlement -40.00 vs revenue+fees+adjustment -30.00',
   format('A4 exceptions: the flagged ad payment shows its real gap (-10 against revenue+fees+adjustment), got %s / %s', s.detail, s.amount));
 n := (dashboard_alerts_summary()->'tiktok'->>'settlement_mismatches')::int - pg_temp.tx('mismatches_before')::int;
 perform pg_temp.check(n = 2, format('A4 Dashboard: this store adds 2 settlement mismatches (not 4), got %s', n));
 select count(*) into n from tiktok_settlement_rows where store_id=st and confirmed and is_current and reconciled is false;
 perform pg_temp.check(n = 4, 'A4 the 4 stored verdicts are left as they were (the reports read the rule)');

 -- Staging stores new rows by the rule (unconfirmed, so no report above sees them).
 bt := stage_tiktok_settlement(st,'r367-new.xlsx','Settlement',jsonb_build_array(
   jsonb_build_object('order_id','R367-S1-'||sfx,'transaction_type','GMV payment for TikTok Ads','settlement_amount','-12.34',
     'revenue_amount','0','fee_amount','0','adjustment_amount','-12.34','currency','SGD'),
   jsonb_build_object('order_id','R367-S2-'||sfx,'transaction_type','Order','settlement_amount','17',
     'revenue_amount','20','fee_amount','-3','adjustment_amount','0','currency','SGD'),
   jsonb_build_object('order_id','R367-S3-'||sfx,'transaction_type','GMV payment for TikTok Ads','settlement_amount','-9',
     'revenue_amount','0','fee_amount','0','adjustment_amount','-8','currency','SGD')));
 perform pg_temp.check((select reconciled from tiktok_settlement_rows where batch_id=bt and order_id='R367-S1-'||sfx),
   'A4 staging stores a new ad payment as reconciled');
 perform pg_temp.check((select reconciled from tiktok_settlement_rows where batch_id=bt and order_id='R367-S2-'||sfx)
     and (select reconciled is false from tiktok_settlement_rows where batch_id=bt and order_id='R367-S3-'||sfx),
   'A4 staging: a sale that adds up reconciles, an ad payment that does not is flagged');
end $$;

-- ═════ A5: legacy therapy dates ═════
do $$
declare r record;
begin
 select * into r from report_therapy() where entitlement_no='R367-L-'||pg_temp.tx('sfx');
 perform pg_temp.check(r.activation_date = '2026-09-01' and r.expiry_date = '2026-12-01' and r.is_legacy
     and r.activation_deadline = '2026-10-31',
   format('A5 a legacy entitlement shows activation 2026-09-01 and expiry 2026-12-01, got %s / %s', r.activation_date, r.expiry_date));
end $$;

-- ═════ A6: periods are Singapore dates ═════
do $$
declare st uuid:=pg_temp.fx('st'); sfx text:=pg_temp.tx('sfx'); n int;
begin
 select count(*) into n from report_exchange_invoices(st,'2026-09-01','2026-09-01') where exchange_no='R367-X-'||sfx;
 perform pg_temp.check(n = 1, format('A6 an exchange at 01:00 on 1 Sep (Singapore) is in 1 Sep, got %s', n));
 select count(*) into n from report_exchange_invoices(st,'2026-08-31','2026-08-31') where exchange_no='R367-X-'||sfx;
 perform pg_temp.check(n = 0, format('A6 ... and not in 31 Aug, got %s', n));
 select count(*) into n from report_transfer_receipts('2026-09-01','2026-09-01') where transfer_id=pg_temp.fx('t1');
 perform pg_temp.check(n = 1, format('A6 a receipt at 01:00 on 1 Sep (Singapore) is in 1 Sep, got %s', n));
 select count(*) into n from report_transfer_receipts('2026-08-31','2026-08-31') where transfer_id=pg_temp.fx('t1');
 perform pg_temp.check(n = 0, format('A6 ... and not in 31 Aug, got %s', n));
 select surveys_count into n from report_customer_sources('2026-09-01','2026-09-01') where source_label='R367 Source '||sfx;
 perform pg_temp.check(n = 1, format('A6 a survey submitted at 01:00 on 1 Sep (Singapore) counts in 1 Sep, got %s', n));
 select surveys_count into n from report_customer_sources('2026-08-31','2026-08-31') where source_label='R367 Source '||sfx;
 perform pg_temp.check(n = 0, format('A6 ... and not in 31 Aug, got %s', n));
 select surveys_count into n from report_customer_sources(null,null) where source_label='R367 Source '||sfx;
 perform pg_temp.check(n = 1, format('A6 with no period the survey counts once, got %s', n));
end $$;

-- ═════ A7: wallet credit net of refunds; the report still adds up ═════
do $$
declare st uuid:=pg_temp.fx('st'); r jsonb;
begin
 r := report_sales_by_service_staff(sg_today(),sg_today(),st);
 perform pg_temp.check((r->>'wallet_credit_not_counted')::numeric = 100,
   format('A7 200 spent from the wallet, 100 refunded to it: 100 not counted (not 200), got %s', r->>'wallet_credit_not_counted'));
 perform pg_temp.check((r->>'difference')::numeric = 0 and (r->>'staff_total')::numeric = (r->>'revenue')::numeric,
   format('A7 staff total still equals revenue (%s = %s)', r->>'staff_total', r->>'revenue'));
 r := report_sales_by_service_staff(null,null,st);
 perform pg_temp.check((r->>'wallet_credit_not_counted')::numeric = 100 and (r->>'difference')::numeric = 0,
   format('A7 all time: 100 not counted, difference 0, got %s / %s', r->>'wallet_credit_not_counted', r->>'difference'));
 r := report_sales_by_service_staff(sg_today()-40,sg_today()-35,st);
 perform pg_temp.check((r->>'wallet_credit_not_counted')::numeric = 0,
   format('A7 a period without the purchase or the refund: 0, got %s', r->>'wallet_credit_not_counted'));
end $$;

-- ═════ A8: a deleted customer is not a referral ═════
do $$
declare r record;
begin
 select * into r from report_affiliates() where customer_id=pg_temp.fx('x');
 perform pg_temp.check(r.direct_referrals = 1, format('A8 direct referrals: the live one only (1, not 2), got %s', r.direct_referrals));
 perform pg_temp.check(r.downline = 2, format('A8 downline: the live referral and the one they referred (2, not 4), got %s', r.downline));
end $$;

-- ═════ A9 + A10: transfers ═════
do $$
declare sfx text:=pg_temp.tx('sfx'); r record; n int;
begin
 select count(*) into n from report_transfer_discrepancies() where transfer_id=pg_temp.fx('t2');
 perform pg_temp.check(n = 1, format('A9 a manual line''s discrepancy is listed, got %s rows', n));
 select * into r from report_transfer_discrepancies() where transfer_id=pg_temp.fx('t2');
 perform pg_temp.check(r.product_name = 'R367 Tape (manual)' and r.product_id is null and r.discrepancy = -2,
   format('A9 named "R367 Tape (manual)", got %s', r.product_name));
 select * into r from report_transfer_receipts(null,null) where transfer_id=pg_temp.fx('t1');
 perform pg_temp.check(r.source_name = 'R367 WH A '||sfx||', R367 WH B '||sfx,
   format('A10 From names both warehouses the dispatch drew from, got %s', r.source_name));
 perform pg_temp.check(r.received_units = 8 and r.line_count = 3,
   format('A10 units: 5 + 3 catalogue units, the 7 posters not added in (8, not 15); 3 lines, got %s / %s', r.received_units, r.line_count));
 select * into r from report_transfer_receipts(null,null) where transfer_id=pg_temp.fx('t2');
 perform pg_temp.check(r.source_name = 'R367 WH A '||sfx and r.received_units = 0,
   format('A10 a single-source receipt still names its source, and its 2 manual units are not stock units, got %s / %s', r.source_name, r.received_units));
end $$;

-- ═════ Grants: the new rule is internal ═════
do $$
begin
 perform pg_temp.check(to_regprocedure('public.tiktok_settlement_row_reconciled(boolean,text,text,numeric,numeric,numeric,numeric)') is not null
     and not has_function_privilege('authenticated','public.tiktok_settlement_row_reconciled(boolean,text,text,numeric,numeric,numeric,numeric)','execute')
     and not has_function_privilege('anon','public.tiktok_settlement_row_reconciled(boolean,text,text,numeric,numeric,numeric,numeric)','execute'),
   'the reconciliation rule exists and no client role can call it');
end $$;

do $$
declare k int; msgs text;
begin
 select count(*), string_agg(f.msg, E'\n  ' order by f.n) into k, msgs from failed f;
 if k > 0 then raise exception 'FAIL: % check(s) failed:%', k, E'\n  ' || msgs; end if;
 raise notice 'PASS: 367 — TikTok sales by settled date, FOC cards = FOC lines, named pricing lines, ad payments reconcile (reports, dashboard, staging), legacy therapy dates, Singapore-date periods, wallet credit net of refunds, live referrals only, manual discrepancies listed, every source and catalogue units on receipts';
end $$;
rollback;
