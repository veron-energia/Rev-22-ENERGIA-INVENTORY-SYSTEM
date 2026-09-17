-- A credit package releases its paid credit as it is paid for.
--
-- Until 327 a package gave nothing until the invoice was settled: S$1,000 paid
-- toward a S$5,000 package bought the customer nothing at all. Paid credit is
-- money already handed over, so it is now usable as it arrives. Bonus credit,
-- vouchers, the sale record and commission are rewards for completing the
-- purchase and still wait for the last payment.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare
 own uuid := gen_random_uuid();
 st uuid; c uuid; pm uuid; cp uuid; prod uuid; inv uuid; it uuid;
 paid numeric; bonus numeric; sales int; released numeric; n int;
begin
 insert into auth.users(id,email) values(own,'rp-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rp-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RP Store','RPS','SG') returning id into st;
 insert into customers(full_name,phone) values('RP Buyer','+6598911777') returning id into c;
 insert into payment_methods(name) values('RP Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,
                             allow_product,allow_therapy)
   values('RP Package',5000,5000,true,'fixed',500,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 inv := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 select id into it from invoice_items where invoice_id=inv and line_kind='credit_package';

 -- ---- nothing paid, nothing released ------------------------------------
 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid';
 if paid <> 0 then raise exception 'FAIL: % credit released before any payment', paid; end if;

 -- ---- S$1,000 of S$5,000 -> exactly S$1,000 usable -----------------------
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());

 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 1000 then raise exception 'FAIL: expected 1000 paid credit, got %', paid; end if;

 select coalesce(sum(original_amount),0) into bonus
   from customer_credit_lots where customer_id=c and category='bonus' and status<>'reversed';
 if bonus <> 0 then raise exception 'FAIL: bonus credit released at %, before full payment', bonus; end if;

 select count(*) into sales from credit_package_sales where invoice_id=inv;
 if sales <> 0 then raise exception 'FAIL: sale record written before full payment'; end if;

 select count(*) into n from commissions where invoice_id=inv and status='earned';
 if n <> 0 then raise exception 'FAIL: % commission earned on a part-paid package', n; end if;

 -- ---- a second S$1,500 -> 2,500 in total, not 1,500 ----------------------
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1500)),gen_random_uuid());
 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 2500 then raise exception 'FAIL: expected 2500 after two payments, got %', paid; end if;

 -- ---- releasing twice for the same money is not possible -----------------
 perform release_credit_package_paid_credit(inv);
 perform release_credit_package_paid_credit(inv);
 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 2500 then raise exception 'FAIL: re-running release changed the total to %', paid; end if;

 -- ---- the balance -> exactly 5000 paid credit, and now the rewards -------
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',2500)),gen_random_uuid());

 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 5000 then
   raise exception 'FAIL: expected exactly 5000 paid credit after full payment, got %', paid; end if;

 select coalesce(sum(original_amount),0) into bonus
   from customer_credit_lots where customer_id=c and category='bonus' and status<>'reversed';
 if bonus <> 500 then raise exception 'FAIL: expected 500 bonus on full payment, got %', bonus; end if;

 select count(*) into sales from credit_package_sales where invoice_id=inv;
 if sales <> 1 then raise exception 'FAIL: expected one sale record, got %', sales; end if;

 raise notice 'PASS: 1000 of 5000 released 1000; 2500 after two payments; exactly 5000 and the bonus at the end';
end $$;
rollback;

-- ---------------------------------------------------------------------
-- A package sharing an invoice with a product: the package is settled first,
-- so money toward a package releases credit rather than paying off the goods.
-- ---------------------------------------------------------------------
begin;
do $$
declare
 own uuid := gen_random_uuid();
 st uuid; c uuid; pm uuid; cp uuid; prod uuid; inv uuid; paid numeric;
begin
 insert into auth.users(id,email) values(own,'rp2-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rp2-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RP2 Store','RP2','SG') returning id into st;
 insert into customers(full_name,phone) values('RP2 Buyer','+6598911778') returning id into c;
 insert into payment_methods(name) values('RP2 Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('RP2 Package',5000,5000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 insert into products(name,sku,product_type) values('RP2 Widget','RP2-W','own') returning id into prod;
 insert into store_product_prices(store_id,product_id,selling_price) values(st,prod,200);
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,50);

 inv := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1),
   jsonb_build_object('kind','product','product_id',prod,'quantity',1)));

 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());

 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 1000 then
   raise exception 'FAIL: package should be settled first — expected 1000 credit, got %', paid; end if;

 raise notice 'PASS: on a mixed invoice the credit package is paid off first';
end $$;
rollback;

-- ---------------------------------------------------------------------
-- Cancelling after credit has been released. Before 327 this could not arise.
-- What is unspent comes back; what is already spent is written off, because
-- the goods are gone and reverse_credit_lot refuses a spent lot outright.
-- ---------------------------------------------------------------------
begin;
do $$
declare
 own uuid := gen_random_uuid();
 st uuid; c uuid; pm uuid; cp uuid; inv uuid; remaining numeric; n int; ev jsonb;
begin
 insert into auth.users(id,email) values(own,'rp3-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rp3-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RP3 Store','RP3','SG') returning id into st;
 insert into customers(full_name,phone) values('RP3 Buyer','+6598911779') returning id into c;
 insert into payment_methods(name) values('RP3 Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('RP3 Package',5000,5000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 inv := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());

 -- The customer spends 600 of the 1000 released. Found through the link, so
 -- the fixture does not care what source the lot carries.
 update customer_credit_lots set remaining_amount = remaining_amount - 600
  where id in (select lot_id from credit_package_progress_lots where invoice_id=inv);

 perform cancel_invoice_recorded(inv,'Customer changed their mind',gen_random_uuid());

 select coalesce(sum(remaining_amount),0) into remaining
   from customer_credit_lots where customer_id=c;
 if remaining <> 0 then
   raise exception 'FAIL: % credit still spendable after cancelling', remaining; end if;

 select count(*) into n from customer_credit_ledger
  where source_type='invoice_cancel_released_credit' and amount=400;
 if n <> 1 then raise exception 'FAIL: the 400 unspent was not reclaimed (% entries)', n; end if;

 select new_data into ev from audit_logs
  where action='released_credit_cancel' and record_id=inv order by created_at desc limit 1;
 if ev is null then raise exception 'FAIL: no audit entry for the write-off'; end if;
 if (ev->>'written_off')::numeric <> 600 then
   raise exception 'FAIL: expected 600 written off, audit says %', ev->>'written_off'; end if;
 if (ev->>'reclaimed')::numeric <> 400 then
   raise exception 'FAIL: expected 400 reclaimed, audit says %', ev->>'reclaimed'; end if;

 raise notice 'PASS: cancelling reclaimed the unspent 400 and wrote off the spent 600, on the record';
end $$;
rollback;

-- ---------------------------------------------------------------------
-- Released credit follows a customer correction. A lot granted against the
-- invoice line is found by invoice_credit_lot_ids the same way any other
-- invoice credit is, so reassigning a part-paid package moves it.
-- ---------------------------------------------------------------------
begin;
do $$
declare
 own uuid := gen_random_uuid();
 st uuid; c1 uuid; c2 uuid; pm uuid; cp uuid; inv uuid; held numeric; moved numeric;
begin
 insert into auth.users(id,email) values(own,'rp4-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rp4-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RP4 Store','RP4','SG') returning id into st;
 insert into customers(full_name,phone) values('RP4 Buyer','+6598911780') returning id into c1;
 insert into customers(full_name,phone) values('RP4 Other','+6598911781') returning id into c2;
 insert into payment_methods(name) values('RP4 Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('RP4 Package',5000,5000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 inv := create_invoice(st,c1,null,jsonb_build_array(
   jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());

 select coalesce(sum(remaining_amount),0) into held
   from customer_credit_lots where customer_id=c1 and status<>'reversed';
 if held <> 1000 then raise exception 'FAIL: expected 1000 held before the move, got %', held; end if;

 perform move_invoice_benefits_to_customer(inv,c2,st,'Invoice reassigned in a test');

 select coalesce(sum(remaining_amount),0) into moved
   from customer_credit_lots where customer_id=c2 and status<>'reversed';
 select coalesce(sum(remaining_amount),0) into held
   from customer_credit_lots where customer_id=c1 and status<>'reversed';
 if moved <> 1000 then
   raise exception 'FAIL: released credit did not follow the customer — new holder has %', moved; end if;
 if held <> 0 then
   raise exception 'FAIL: the original customer still holds % after the move', held; end if;

 raise notice 'PASS: credit released before settlement follows a customer correction';
end $$;
rollback;

-- ---------------------------------------------------------------------
-- Backfilling invoices that were already part paid when 327 arrived.
-- 327 releases on payment, so money received before it was installed released
-- nothing. The backfill calls the same function a payment would, which is what
-- makes it safe to run twice and impossible for it to invent a different
-- amount from the one the rule gives.
-- ---------------------------------------------------------------------
begin;
do $$
declare
 own uuid := gen_random_uuid();
 st uuid; c uuid; pm uuid; cp uuid; inv uuid; old_inv uuid; paid numeric; n int;
begin
 insert into auth.users(id,email) values(own,'rp5-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rp5-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RP5 Store','RP5','SG') returning id into st;
 insert into customers(full_name,phone) values('RP5 Buyer','+6598911782') returning id into c;
 insert into payment_methods(name) values('RP5 Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,
                             allow_product,allow_therapy)
   values('RP5 Package',5000,5000,true,'fixed',500,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 inv := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));

 -- Reproduce a pre-327 invoice: money received, nothing released. The credit
 -- ledger is append-only by design, so the state is created by taking the
 -- payment with the trigger off rather than by deleting what it wrote.
 alter table invoices disable trigger create_therapy_on_paid;
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());
 alter table invoices enable trigger create_therapy_on_paid;
 update invoices set business_date = current_date - 400 where id = inv;

 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 0 then raise exception 'FAIL: fixture did not reproduce the pre-327 state (%)', paid; end if;

 -- An age cutoff shorter than the invoice leaves it alone.
 if (current_date - (select coalesce(business_date, created_at::date) from invoices where id=inv)) <= 180 then
   raise exception 'FAIL: fixture invoice is not old enough to test the cutoff'; end if;

 -- The backfill, for invoices up to a year old: this one is 400 days old.
 for old_inv in
   select i.id from invoices i
    join invoice_items it on it.invoice_id=i.id and it.line_kind='credit_package'
   where i.deleted_at is null and i.status not in ('cancelled','refunded','draft')
     and it.credit_issued_at is null and coalesce(i.paid_amount,0) > 0
     and (current_date - coalesce(i.business_date, i.created_at::date)) <= 365
 loop
   perform release_credit_package_paid_credit(old_inv);
 end loop;

 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 0 then
   raise exception 'FAIL: a 400-day-old invoice was released under a 365-day cutoff (%)', paid; end if;

 -- The backfill with no cutoff reaches it.
 for old_inv in
   select i.id from invoices i
    join invoice_items it on it.invoice_id=i.id and it.line_kind='credit_package'
   where i.deleted_at is null and i.status not in ('cancelled','refunded','draft')
     and it.credit_issued_at is null and coalesce(i.paid_amount,0) > 0
 loop
   perform release_credit_package_paid_credit(old_inv);
 end loop;

 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 1000 then
   raise exception 'FAIL: backfill should have released 1000, released %', paid; end if;

 -- Running it a second time must not pay the customer twice.
 perform release_credit_package_paid_credit(inv);
 select coalesce(sum(original_amount),0) into paid
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if paid <> 1000 then
   raise exception 'FAIL: a second backfill run released again, total now %', paid; end if;

 -- And the rewards are still waiting for the last payment.
 select count(*) into n from customer_credit_lots
  where customer_id=c and category='bonus' and status<>'reversed';
 if n <> 0 then raise exception 'FAIL: backfill released bonus credit'; end if;
 select count(*) into n from credit_package_sales where invoice_id=inv;
 if n <> 0 then raise exception 'FAIL: backfill wrote a sale record'; end if;

 raise notice 'PASS: backfill honours the age cutoff, releases 1000 once, never twice, and grants no rewards';
end $$;
rollback;

-- ---------------------------------------------------------------------
-- Released credit must look like credit from its package, or it buys nothing.
-- 327 stamped released lots with an invented source and the invoice LINE as
-- their record, so 242's policy matrix could not place them and 309 could not
-- find the package's rules: a customer holding S$3,000 was told "Only 0 of the
-- requested 521.00 could be funded by eligible credit". 328 gives a released
-- lot the same provenance as a full issuance and keeps the way back to its
-- invoice in credit_package_progress_lots.
-- ---------------------------------------------------------------------
begin;
do $$
declare
 own uuid := gen_random_uuid();
 st uuid; c uuid; pm uuid; wpm_paid uuid; cp uuid; svc uuid; inv uuid; it uuid; spend uuid;
 lot public.customer_credit_lots%rowtype; total numeric;
begin
 insert into auth.users(id,email) values(own,'rp6-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rp6-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RP6 Store','RP6','SG') returning id into st;
 insert into customers(full_name,phone) values('RP6 Buyer','+6598911783') returning id into c;
 insert into payment_methods(name) values('RP6 Cash') returning id into pm;
 select id into wpm_paid from payment_methods where wallet_category='paid' and is_system limit 1;
 svc:=(upsert_therapy_service(null,'RP6-PR','RP6 Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('RP6 Package',5000,5000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 inv := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 select id into it from invoice_items where invoice_id=inv and line_kind='credit_package';
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());

 select l.* into lot from customer_credit_lots l
   join credit_package_progress_lots p on p.lot_id=l.id where p.invoice_item_id=it;
 if lot.id is null then raise exception 'FAIL: the released lot is not linked to its line'; end if;
 if lot.source_type <> 'credit_package' or lot.source_record_id <> cp then
   raise exception 'FAIL: released lot carries source %/% — 242 and 309 will not recognise it',
     lot.source_type, lot.source_record_id; end if;
 if credit_lot_policy_for(lot.id) <> 'package_paid' then
   raise exception 'FAIL: policy for released credit is %, expected package_paid', credit_lot_policy_for(lot.id); end if;
 if not exists (select 1 from invoice_credit_lot_ids(inv) where lot_id=lot.id) then
   raise exception 'FAIL: invoice_credit_lot_ids cannot find the released lot — refunds and reassignment would miss it'; end if;

 -- The production failure, now expected to succeed.
 spend := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(
   jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=lot.id) <> 950 then
   raise exception 'FAIL: released paid credit could not fund a therapy session (remaining %)',
     (select remaining_amount from customer_credit_lots where id=lot.id); end if;

 -- Settling the package still lands on exactly its paid credit: the issuer
 -- grants the remainder, never a second 1000.
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',4000)),gen_random_uuid());
 select coalesce(sum(original_amount),0) into total
   from customer_credit_lots where customer_id=c and category='paid' and status<>'reversed';
 if total <> 5000 then raise exception 'FAIL: expected 5000 paid credit granted in total, got %', total; end if;

 raise notice 'PASS: released credit carries its package, is found from its invoice, and buys a therapy session';
end $$;
rollback;

-- ---------------------------------------------------------------------
-- Repairing a lot exactly as 327 left it in production: old source, the line
-- as its record, partly spent, no link row. A posted lot cannot be edited, so
-- the repair reverses the unspent part and grants it again under the package.
-- ---------------------------------------------------------------------
begin;
do $$
declare
 own uuid := gen_random_uuid();
 st uuid; c uuid; pm uuid; wpm_paid uuid; cp uuid; svc uuid; inv uuid; it uuid; spend uuid;
 old_lot uuid; old_eff date; new_lot public.customer_credit_lots%rowtype; r jsonb;
begin
 insert into auth.users(id,email) values(own,'rp7-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rp7-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RP7 Store','RP7','SG') returning id into st;
 insert into customers(full_name,phone) values('RP7 Buyer','+6598911784') returning id into c;
 insert into payment_methods(name) values('RP7 Cash') returning id into pm;
 select id into wpm_paid from payment_methods where wallet_category='paid' and is_system limit 1;
 svc:=(upsert_therapy_service(null,'RP7-PR','RP7 Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('RP7 Package',5000,5000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 inv := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 select id into it from invoice_items where invoice_id=inv and line_kind='credit_package';

 -- 1000 paid with the trigger off, then the lot granted the way 327 did.
 alter table invoices disable trigger create_therapy_on_paid;
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());
 alter table invoices enable trigger create_therapy_on_paid;
 old_lot := grant_customer_credit(c,'paid',1000,'credit_package_progress',it,st,sg_today(),null,
   'Credit package (paid so far): RP7 Package',null,null,own,
   jsonb_build_object('allowed_purposes',credit_package_purposes(cp),'source','credit_package'));
 select effective_date into old_eff from customer_credit_lots where id=old_lot;

 -- Useless as it stands: the bug is reproduced, not assumed.
 if credit_lot_policy_for(old_lot) <> 'needs_review' then
   raise exception 'FIXTURE: expected the old-source lot to be needs_review, got %', credit_lot_policy_for(old_lot); end if;
 spend := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 begin
   perform record_invoice_payment(spend,jsonb_build_array(
     jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
   raise exception 'FIXTURE: the old-source lot funded a spend; the bug is not reproduced';
 exception when others then if sqlerrm not like '%eligible credit%' then raise; end if; end;

 -- 300 of it was spent before anyone noticed.
 update customer_credit_lots set remaining_amount = 700 where id = old_lot;

 r := repair_credit_package_progress_lots();
 if (r->>'linked')::int <> 1 or (r->>'regranted')::int <> 1 or (r->>'regranted_amount')::numeric <> 700 then
   raise exception 'FAIL: repair reported %', r; end if;

 if (select status from customer_credit_lots where id=old_lot) <> 'reversed'
    or (select remaining_amount from customer_credit_lots where id=old_lot) <> 0 then
   raise exception 'FAIL: the old lot was not reversed'; end if;
 select l.* into new_lot from customer_credit_lots l
   join credit_package_progress_lots p on p.lot_id=l.id where p.replaces_lot_id=old_lot;
 if new_lot.id is null then raise exception 'FAIL: no replacement lot was granted'; end if;
 if new_lot.source_type <> 'credit_package' or new_lot.source_record_id <> cp then
   raise exception 'FAIL: replacement carries source %/%', new_lot.source_type, new_lot.source_record_id; end if;
 if new_lot.original_amount <> 700 or new_lot.remaining_amount <> 700 then
   raise exception 'FAIL: replacement must carry exactly the unspent 700, got %/%', new_lot.original_amount, new_lot.remaining_amount; end if;
 if new_lot.effective_date <> old_eff then
   raise exception 'FAIL: replacement lost its place in the queue (% vs %)', new_lot.effective_date, old_eff; end if;
 if credit_lot_policy_for(new_lot.id) <> 'package_paid' then
   raise exception 'FAIL: replacement policy is %', credit_lot_policy_for(new_lot.id); end if;
 if credit_package_released_paid_credit(it) <> 1000 then
   raise exception 'FAIL: released on record must still be 1000, got % — the next payment would re-release', credit_package_released_paid_credit(it); end if;
 if (select count(*) from invoice_credit_lot_ids(inv) where lot_id in (old_lot,new_lot.id)) <> 2 then
   raise exception 'FAIL: the invoice cannot see both its old and replacement lots'; end if;
 if not exists (select 1 from customer_credit_ledger where lot_id=old_lot and entry_type='reverse'
                  and amount=700 and source_type='credit_lot_provenance_repair') then
   raise exception 'FAIL: the reversal is not on the ledger'; end if;

 -- And now it spends.
 spend := create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(
   jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=new_lot.id) <> 650 then
   raise exception 'FAIL: the replacement lot could not fund a therapy session'; end if;

 -- The next payment releases only the new money: 500 more paid, 500 more
 -- credit — not the 300 that was spent, not the 700 that was re-granted.
 perform record_invoice_payment(inv,jsonb_build_array(
   jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 if credit_package_released_paid_credit(it) <> 1500 then
   raise exception 'FAIL: expected 1500 released on record after another 500, got %', credit_package_released_paid_credit(it); end if;
 if (select count(*) from credit_package_progress_lots where invoice_item_id=it and released_amount=500) <> 1 then
   raise exception 'FAIL: the further payment did not release exactly 500'; end if;

 -- Running the repair again finds nothing to do.
 r := repair_credit_package_progress_lots();
 if (r->>'linked')::int <> 0 then raise exception 'FAIL: the repair is not idempotent: %', r; end if;

 raise notice 'PASS: a 327-era lot is reversed and re-granted under its package for the unspent part only, still counts once, and spends';
end $$;
rollback;
