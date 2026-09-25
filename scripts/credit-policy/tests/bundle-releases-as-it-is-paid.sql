-- A premium bundle releases its paid credit as it is paid for (356).
--
-- Until 356 a part-paid bundle released nothing until the last payment. On
-- production a customer who had paid $1,963 of an $11,006 bundle held no credit,
-- and staff handed it over by hand as opening balance to make up for it.
--
-- The owner's rule: paid credit follows the money 1:1; bonus credit and the free
-- vouchers wait for full payment. This mirrors releases-as-it-is-paid.sql (the
-- credit-package test from 327) so bundles are held to the same standard.
--
-- Sections H-L (round 2, 356 section 3b) follow the released credit down every
-- other path: a line removed in a correction, refunds and cancellation after
-- settlement, cancel then reopen, a move to another customer, and a payment
-- corrected down or removed. Each goes through the real entry points.
--
-- Each scenario has its own customer. Fixture codes, names and phones carry a
-- random suffix because other suites share the database. Disposable database
-- only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

create function pg_temp.sfx() returns text language sql volatile as
$$ select substr(md5(random()::text || clock_timestamp()::text), 1, 8) $$;
-- A valid Singapore mobile: +659 then 7 digits, the first 0-8 (99xxxxxx is not a mobile range).
create function pg_temp.phone() returns text language sql volatile as
$$ select '+659' || floor(random() * 9)::int::text || lpad(floor(random() * 1000000)::int::text, 6, '0') $$;

do $$
declare
  own uuid := gen_random_uuid(); sfx text := pg_temp.sfx();
  st uuid; pm uuid; wpm uuid; v uuid; pb uuid; cp uuid; svc uuid;
  c uuid; c2 uuid; inv uuid; it uuid; inv2 uuid;
  paid numeric; bonus numeric; held numeric; vouchers numeric; sales int; n int; v_msg text; ev jsonb;
begin
  insert into auth.users(id,email) values (own,'brp-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'BRP Owner','brp-'||sfx||'@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('BRP Store','BRP-'||sfx,'SG') returning id into st;
  insert into payment_methods(name) values ('BRP Cash '||sfx) returning id into pm;
  select id into wpm from payment_methods where wallet_category = 'paid' and is_system limit 1;

  insert into vouchers(name,code,qty_type,reward_eligible) values ('BRP V','BRP-V-'||sfx,'limited',true) returning id into v;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v,st,500);
  insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values (v,st,20,true);

  insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
    values ('BRP $5,000 bundle',5000,5000,500,20,true) returning id into pb;
  insert into premium_bundle_stores(bundle_id,store_id) values (pb,st);
  insert into premium_bundle_vouchers(bundle_id,voucher_id) values (pb,v);

  svc := (upsert_therapy_service(null,'BRP-S-'||sfx,'BRP Session',60,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);

  -- ── A. paid credit follows the money; bonus and vouchers wait ────────────
  insert into customers(full_name,phone) values ('BRP A',pg_temp.phone()) returning id into c;
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object(
           'kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
           'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',20)))),
         0::numeric, null::text, null::uuid, '[]'::jsonb);
  select id into it from invoice_items where invoice_id = inv and line_kind = 'premium_bundle';

  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 0 then raise exception 'FAIL A: % credit released before any payment', paid; end if;

  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 1000 then raise exception 'FAIL A: expected 1000 paid credit after paying 1000, got %', paid; end if;

  select coalesce(sum(original_amount),0) into bonus from customer_credit_lots where customer_id = c and category = 'bonus';
  if bonus <> 0 then raise exception 'FAIL A: bonus released at %, before full payment', bonus; end if;
  select coalesce(sum(quantity),0) into vouchers from customer_reward_vouchers where customer_id = c;
  if vouchers <> 0 then raise exception 'FAIL A: % vouchers issued before full payment', vouchers; end if;
  select count(*) into sales from premium_bundle_sales where invoice_id = inv;
  if sales <> 0 then raise exception 'FAIL A: a bundle sale record was written before full payment'; end if;

  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1500)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 2500 then raise exception 'FAIL A: expected 2500 after two payments, got %', paid; end if;

  -- Re-running the release changes nothing.
  perform release_credit_package_paid_credit(inv);
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 2500 then raise exception 'FAIL A: re-running the release moved the total to %', paid; end if;
  raise notice 'PASS A: paid credit released per payment (1000, then 2500); no bonus, vouchers or sale yet; re-run is a no-op';

  -- ── B. released bundle credit is actually spendable ──────────────────────
  inv2 := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object(
            'kind','therapy','therapy_service_id',svc,'quantity',1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
  begin
    perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id',wpm,'amount',60)), gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL B: released bundle credit could not pay for therapy: %', v_msg;
  end;
  raise notice 'PASS B: released bundle credit spends at the till';

  -- ── C. settling grants exactly the entitlement, and the bonus and vouchers ─
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',2500)), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then
    raise exception 'FAIL C: the bundle did not settle'; end if;
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 5000 then
    raise exception 'FAIL C: expected exactly 5000 paid credit after full payment, got % — released credit was granted twice', paid; end if;
  select coalesce(sum(original_amount),0) into bonus from customer_credit_lots where customer_id = c and category = 'bonus';
  if bonus <> 500 then raise exception 'FAIL C: expected 500 bonus at full payment, got %', bonus; end if;
  select coalesce(sum(quantity),0) into vouchers from customer_reward_vouchers where customer_id = c;
  if vouchers <> 20 then raise exception 'FAIL C: expected 20 vouchers at full payment, got %', vouchers; end if;
  select count(*) into sales from premium_bundle_sales where invoice_id = inv;
  if sales <> 1 then raise exception 'FAIL C: expected one bundle sale record, got %', sales; end if;
  raise notice 'PASS C: settlement tops up to exactly 5000 paid, plus 500 bonus and 20 vouchers';

  -- ── D. cancelling a part-paid bundle takes back what was not spent ───────
  insert into customers(full_name,phone) values ('BRP D',pg_temp.phone()) returning id into c;
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object(
           'kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'voucher_selection','[]'::jsonb)),
         0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)), gen_random_uuid());
  -- The customer spends 600 of the 1000 released.
  update customer_credit_lots set remaining_amount = remaining_amount - 600
   where id in (select lot_id from credit_package_progress_lots where invoice_id = inv);
  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  select coalesce(sum(remaining_amount),0) into held from customer_credit_lots where customer_id = c;
  if held <> 0 then raise exception 'FAIL D: % bundle credit still spendable after cancelling', held; end if;
  select new_data into ev from audit_logs
   where action = 'released_credit_cancel' and record_id = inv order by created_at desc limit 1;
  if ev is null then raise exception 'FAIL D: no audit entry for the write-off'; end if;
  if (ev->>'reclaimed')::numeric <> 400 or (ev->>'written_off')::numeric <> 600 then
    raise exception 'FAIL D: expected 400 reclaimed and 600 written off, audit says %', ev; end if;
  raise notice 'PASS D: cancelling a part-paid bundle reclaimed the unspent 400 and wrote off the spent 600';

  -- ── E. a discounted, part-paid bundle never releases more than was paid ──
  -- INV-2026-0292's shape: $15,000 bundle, S$3,994 discount, paid in parts.
  insert into customers(full_name,phone) values ('BRP E',pg_temp.phone()) returning id into c;
  update premium_bundles set customer_payment_amount = 15000, paid_credit_amount = 15000,
         bonus_credit_amount = 2000, free_voucher_qty = 0 where id = pb;
  inv := create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
           'kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'voucher_selection','[]'::jsonb)),
         jsonb_build_object('business_date', current_date::text, 'manual_discount', 3994,
                            'manual_discount_reason', 'upgrade'));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)), gen_random_uuid());
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',636)),  gen_random_uuid());
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',327)),  gen_random_uuid());
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 1963 then raise exception 'FAIL E: after 1,963 received, % paid credit released', paid; end if;
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',9043)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 11006 then
    raise exception 'FAIL E: a discounted bundle ended with % paid credit, expected exactly 11,006', paid; end if;
  raise notice 'PASS E: INV-2026-0292 shape releases 1,963 as paid, settles to exactly 11,006';

  -- ── F. package-only invoices behave exactly as before 356 ────────────────
  insert into customers(full_name,phone) values ('BRP F',pg_temp.phone()) returning id into c;
  insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
    values ('BRP Package',2000,2000,true,true) returning id into cp;
  insert into credit_package_stores(package_id,store_id) values (cp,st);
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object(
           'kind','credit_package','credit_package_id',cp,'quantity',1)),
         0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',800)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 800 then raise exception 'FAIL F: a part-paid package now releases % instead of 800', paid; end if;
  raise notice 'PASS F: package-only invoices release exactly as they did before';

  -- ── G. a bundle and a package on one invoice never share the same money ─
  insert into customers(full_name,phone) values ('BRP G',pg_temp.phone()) returning id into c;
  update premium_bundles set customer_payment_amount = 1000, paid_credit_amount = 1000,
         bonus_credit_amount = 0 where id = pb;
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(
           jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'voucher_selection','[]'::jsonb),
           jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)),
         0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1500)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into paid from customer_credit_lots where customer_id = c and category = 'paid';
  if paid <> 1500 then
    raise exception 'FAIL G: 1,500 paid toward a bundle and a package released % in total — money counted twice or lost', paid; end if;
  raise notice 'PASS G: 1,500 across a bundle and a package releases exactly 1,500 between them';

  raise notice 'PASS: a part-paid premium bundle releases its paid credit as the money arrives, and nothing is granted twice.';
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Round 2 (356 section 3b): released credit stays right on every other path.
-- ═════════════════════════════════════════════════════════════════════════════
create temp table brp_fx(k text primary key, v uuid);
create function pg_temp.fx(p_key text) returns uuid language sql stable as
$$ select f.v from brp_fx f where f.k = p_key $$;
-- Credit the customer can still spend, by category.
create function pg_temp.held(p_customer uuid, p_category text default 'paid') returns numeric language sql stable as
$$ select coalesce(sum(l.remaining_amount),0) from customer_credit_lots l
    where l.customer_id = p_customer and l.category = p_category and l.status <> 'reversed' $$;
-- Credit granted to the customer and not reversed, by category.
create function pg_temp.granted(p_customer uuid, p_category text default 'paid') returns numeric language sql stable as
$$ select coalesce(sum(l.original_amount),0) from customer_credit_lots l
    where l.customer_id = p_customer and l.category = p_category and l.status <> 'reversed' $$;
create function pg_temp.vouchers_held(p_customer uuid) returns numeric language sql stable as
$$ select coalesce(sum(r.quantity),0) from customer_reward_vouchers r where r.customer_id = p_customer and r.status = 'held' $$;
create function pg_temp.customer(p_name text) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into customers(full_name, phone) values (p_name, pg_temp.phone()) returning id into v_id;
  return v_id;
end $$;
create function pg_temp.bundle(p_price numeric, p_bonus numeric, p_vouchers int) returns uuid language plpgsql as $$
declare v_pb uuid;
begin
  insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
    values ('BRP2 bundle '||p_price||' '||pg_temp.sfx(), p_price, p_price, p_bonus, p_vouchers, p_vouchers > 0)
    returning id into v_pb;
  insert into premium_bundle_stores(bundle_id,store_id) values (v_pb, pg_temp.fx('st'));
  if p_vouchers > 0 then
    insert into premium_bundle_vouchers(bundle_id,voucher_id) values (v_pb, pg_temp.fx('v')); end if;
  return v_pb;
end $$;
create function pg_temp.package(p_price numeric) returns uuid language plpgsql as $$
declare v_cp uuid;
begin
  insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
    values ('BRP2 package '||p_price||' '||pg_temp.sfx(), p_price, p_price, true, true) returning id into v_cp;
  insert into credit_package_stores(package_id,store_id) values (v_cp, pg_temp.fx('st'));
  return v_cp;
end $$;
create function pg_temp.bundle_line(p_pb uuid, p_vouchers int default 0) returns jsonb language sql stable as
$$ select jsonb_build_object('kind','premium_bundle','premium_bundle_id',p_pb,'quantity',1,
     'voucher_selection', case when p_vouchers > 0
       then jsonb_build_array(jsonb_build_object('voucher_id',pg_temp.fx('v'),'quantity',p_vouchers))
       else '[]'::jsonb end) $$;
create function pg_temp.invoice(p_customer uuid, p_lines jsonb) returns uuid language sql as
$$ select create_invoice(pg_temp.fx('st'), p_customer, null::uuid, p_lines, 0::numeric, null::text, null::uuid, '[]'::jsonb) $$;
create function pg_temp.pay(p_invoice uuid, p_amount numeric) returns void language plpgsql as $$
begin
  perform record_invoice_payment(p_invoice, jsonb_build_array(jsonb_build_object(
    'payment_method_id',pg_temp.fx('pm'),'amount',p_amount)), gen_random_uuid());
end $$;
-- The customer spends released credit for real: therapy at S$100 a session, paid from the wallet.
create function pg_temp.spend(p_customer uuid, p_sessions int) returns uuid language plpgsql as $$
declare v_inv uuid;
begin
  v_inv := pg_temp.invoice(p_customer, jsonb_build_array(jsonb_build_object(
             'kind','therapy','therapy_service_id',pg_temp.fx('svc'),'quantity',p_sessions)));
  perform record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id',pg_temp.fx('wpm'),'amount',100 * p_sessions)), gen_random_uuid());
  return v_inv;
end $$;
-- The receipt of that amount on the invoice (payments in one transaction share created_at).
create function pg_temp.receipt(p_invoice uuid, p_amount numeric) returns uuid language sql stable as
$$ select p.id from invoice_payments p where p.invoice_id = p_invoice and p.amount = p_amount
      and p.entry_kind = 'receipt' order by p.id limit 1 $$;
create function pg_temp.line(p_invoice uuid, p_kind text) returns uuid language sql stable as
$$ select x.id from invoice_items x where x.invoice_id = p_invoice and x.line_kind::text = p_kind order by x.id limit 1 $$;
create function pg_temp.progress_lot(p_item uuid) returns uuid language sql stable as
$$ select pl.lot_id from credit_package_progress_lots pl where pl.invoice_item_id = p_item
    order by pl.created_at, pl.lot_id limit 1 $$;
-- Sum of one field of the refund options' benefits, by benefit kind (paid, bonus, voucher).
create function pg_temp.benefit_sum(p_options jsonb, p_kind text, p_field text) returns numeric language sql immutable as
$$ select coalesce(sum((b->>p_field)::numeric),0) from jsonb_array_elements(p_options->'benefits') b
    where b->>'benefit_kind' = p_kind $$;
-- Refund every unused benefit of the invoice's credit line at its full refundable value,
-- from the invoice's own payments. Returns the amount refunded.
create function pg_temp.refund_all_unused(p_invoice uuid, p_item uuid) returns numeric language plpgsql as $$
declare v_opt jsonb; v_total numeric; v_left numeric; v_take numeric; v_sources jsonb := '[]'::jsonb; s jsonb;
begin
  v_opt := invoice_refund_options_before_sessions(p_invoice);
  select coalesce(sum((b->>'max_refund')::numeric),0) into v_total
    from jsonb_array_elements(v_opt->'benefits') b where (b->>'max_refund')::numeric > 0;
  v_left := v_total;
  for s in select x from jsonb_array_elements(v_opt->'sources') x
            where not (x->>'wallet')::boolean order by (x->>'remaining')::numeric desc loop
    exit when v_left <= 0;
    v_take := least(v_left, (s->>'remaining')::numeric);
    v_sources := v_sources || jsonb_build_array(jsonb_build_object('payment_id', s->>'payment_id', 'amount', v_take));
    v_left := v_left - v_take;
  end loop;
  perform refund_invoice_recorded(p_invoice,
    jsonb_build_array(jsonb_build_object('invoice_item_id', p_item, 'amount', v_total,
      'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                     from jsonb_array_elements(v_opt->'benefits') b where (b->>'max_refund')::numeric > 0))),
    v_sources, '[]'::jsonb, 'Refund everything unused', gen_random_uuid());
  return v_total;
end $$;

-- Round-2 fixtures: their own owner, store, cash method, voucher, S$100 session and S$200 product.
do $$
declare own uuid := gen_random_uuid(); sfx text := pg_temp.sfx();
  st uuid; pm uuid; wpm uuid; v uuid; svc uuid; prod uuid;
begin
  insert into auth.users(id,email) values (own,'brp2-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'BRP2 Owner','brp2-'||sfx||'@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('BRP2 Store','BRP2-'||sfx,'SG') returning id into st;
  insert into payment_methods(name) values ('BRP2 Cash '||sfx) returning id into pm;
  select id into wpm from payment_methods where wallet_category = 'paid' and is_system limit 1;
  insert into vouchers(name,code,qty_type,reward_eligible) values ('BRP2 V','BRP2-V-'||sfx,'limited',true) returning id into v;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v,st,500);
  insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values (v,st,20,true);
  svc := (upsert_therapy_service(null,'BRP2-S-'||sfx,'BRP2 Session',100,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  insert into products(name,sku,product_type) values ('BRP2 Item','BRP2-I-'||sfx,'own') returning id into prod;
  insert into store_inventory(store_id,product_id,current_qty) values (st,prod,50);
  perform set_product_prices(st,prod,200,200,'available');
  insert into brp_fx(k,v) values ('own',own),('st',st),('pm',pm),('wpm',wpm),('v',v),('svc',svc),('prod',prod);
end $$;

-- ── H. a part-paid credit line removed in a correction takes its credit with it ─
-- Before 356 the release record was cascaded away with the line: the customer
-- kept bundle A's released credit, and bundle B released the same money again.
do $$
declare c uuid; c2 uuid; pa uuid; pbb uuid; inv uuid; ita uuid; itb uuid; lot_a uuid; cpa uuid; cpb uuid;
  ev jsonb; v_msg text; n int;
begin
  pa  := pg_temp.bundle(5000, 500, 0);
  pbb := pg_temp.bundle(3000, 300, 0);

  -- H1: A replaced by B while A is part-paid and nothing was spent.
  c := pg_temp.customer('BRP H1');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pa)));
  ita := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  lot_a := pg_temp.progress_lot(ita);
  if pg_temp.held(c) <> 1000 or lot_a is null then
    raise exception 'FAIL H1 (fixture): expected 1000 released for bundle A, customer holds %', pg_temp.held(c); end if;

  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbb)), '{}'::jsonb,
    'Customer chose the smaller bundle', gen_random_uuid());
  if exists (select 1 from invoice_items x where x.id = ita) then
    raise exception 'FAIL H1: bundle A''s line survived the correction'; end if;
  select count(*) into n from credit_package_progress_lots pl where pl.invoice_item_id = ita;
  if n <> 0 then raise exception 'FAIL H1: % release record(s) of the removed line survive', n; end if;
  if (select l.remaining_amount from customer_credit_lots l where l.id = lot_a) <> 0 then
    raise exception 'FAIL H1: bundle A''s released lot still holds % after its line was removed',
      (select l.remaining_amount from customer_credit_lots l where l.id = lot_a); end if;
  if not exists (select 1 from customer_credit_ledger g where g.lot_id = lot_a
                   and g.source_type = 'invoice_line_removed_released_credit' and g.amount = 1000) then
    raise exception 'FAIL H1: no ledger entry reclaiming the 1000 released for the removed line'; end if;
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_reclaimed_line_removed' and a.record_id = inv order by a.created_at desc limit 1;
  if ev is null or (ev->>'reclaimed')::numeric <> 1000 then
    raise exception 'FAIL H1: the reclaim is not on the audit log as 1000 (audit %)', ev; end if;
  itb := pg_temp.line(inv, 'premium_bundle');
  if pg_temp.held(c) > 1000 then
    raise exception 'FAIL H1: after the swap the customer holds % — A''s credit and B''s for the same 1000', pg_temp.held(c); end if;
  -- (Fixed in 356 g; was a known defect) the 1000 already received counts toward bundle B
  -- (credit_package_money_toward_line(itb) = 1000), but nothing of B is released
  -- until the NEXT payment: the customer holds 0 in between. correct_invoice
  -- rewrites status/paid_amount to the same values, so the payment trigger's
  -- release never fires, and neither correct_invoice nor update_invoice_internal
  -- calls release_credit_package_paid_credit. Same for packages (H3: 0 held after
  -- the swap with 800 received). Paid credit should follow the money 1:1.
  if pg_temp.held(c) <> 1000 or credit_package_released_paid_credit(itb) <> 1000 then
    raise exception 'FAIL H1: after the swap the 1000 already received released % of bundle B (customer holds %), expected 1000',
      credit_package_released_paid_credit(itb), pg_temp.held(c); end if;
  perform pg_temp.pay(inv, 2000);
  if (select i.status::text from invoices i where i.id = inv) <> 'paid' then
    raise exception 'FAIL H1: bundle B did not settle at 3000 received'; end if;
  if pg_temp.held(c) <> 3000 or pg_temp.granted(c) <> 3000 then
    raise exception 'FAIL H1: settlement ended with % paid credit held (% granted), expected exactly bundle B''s 3000',
      pg_temp.held(c), pg_temp.granted(c); end if;
  if pg_temp.held(c, 'bonus') <> 300 then
    raise exception 'FAIL H1: expected bundle B''s 300 bonus, got %', pg_temp.held(c, 'bonus'); end if;
  raise notice 'PASS H1: removing part-paid bundle A reclaimed its 1000 and its release record; B settled at exactly 3000 + 300';

  -- H2: the same swap after 300 of A's released credit was spent is refused.
  c := pg_temp.customer('BRP H2');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pa)));
  ita := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform pg_temp.spend(c, 3);
  if pg_temp.held(c) <> 700 then raise exception 'FAIL H2 (fixture): expected 700 left after spending 300, got %', pg_temp.held(c); end if;
  begin
    perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbb)), '{}'::jsonb,
      'Swap after spending', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if v_msg not like 'CREDIT_ALREADY_SPENT%' then
    raise exception 'FAIL H2: removing a line whose released credit was spent should be refused with CREDIT_ALREADY_SPENT, got: %', v_msg; end if;
  if not exists (select 1 from invoice_items x where x.id = ita)
     or credit_package_released_paid_credit(ita) <> 1000 or pg_temp.held(c) <> 700 then
    raise exception 'FAIL H2: the refused correction still changed something (line %, released %, held %)',
      exists (select 1 from invoice_items x where x.id = ita), credit_package_released_paid_credit(ita), pg_temp.held(c); end if;
  raise notice 'PASS H2: removing a part-paid bundle whose released credit was partly spent is refused (CREDIT_ALREADY_SPENT)';

  -- H3: the package variant — package 2000 replaced by package 1500 after 800 paid.
  cpa := pg_temp.package(2000);
  cpb := pg_temp.package(1500);
  c := pg_temp.customer('BRP H3');
  inv := pg_temp.invoice(c, jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cpa,'quantity',1)));
  ita := pg_temp.line(inv, 'credit_package');
  perform pg_temp.pay(inv, 800);
  perform correct_invoice(inv, jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cpb,'quantity',1)),
    '{}'::jsonb, 'Customer chose the smaller package', gen_random_uuid());
  select count(*) into n from credit_package_progress_lots pl where pl.invoice_item_id = ita;
  if n <> 0 then raise exception 'FAIL H3: % release record(s) of the removed package line survive', n; end if;
  perform pg_temp.pay(inv, 700);
  if (select i.status::text from invoices i where i.id = inv) <> 'paid' then
    raise exception 'FAIL H3: package B did not settle at 1500 received'; end if;
  if pg_temp.held(c) <> 1500 or pg_temp.granted(c) <> 1500 then
    raise exception 'FAIL H3: expected exactly package B''s 1500 paid credit, customer holds % (granted %)',
      pg_temp.held(c), pg_temp.granted(c); end if;
  raise notice 'PASS H3: the package variant reclaims the removed line''s 800 and settles at exactly 1500';

  -- H4: the invoice was first moved to another customer; the reclaim follows the
  -- released lot to its replacement.
  c := pg_temp.customer('BRP H4 wrong');
  c2 := pg_temp.customer('BRP H4 right');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pa)));
  ita := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  lot_a := pg_temp.progress_lot(ita);
  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pa) || jsonb_build_object('invoice_item_id', ita)),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  if pg_temp.held(c2) <> 1000 or credit_lot_current(lot_a) = lot_a then
    raise exception 'FAIL H4 (fixture): the released credit did not move (new customer holds %)', pg_temp.held(c2); end if;
  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbb)), '{}'::jsonb,
    'Customer chose the smaller bundle', gen_random_uuid());
  -- A's replacement lot is reclaimed; the 1000 received then counts toward B at
  -- once (356 g), released to the invoice's customer, the new one.
  if (select l.remaining_amount from customer_credit_lots l where l.id = credit_lot_current(lot_a)) <> 0
     or pg_temp.held(c2) <> 1000 or pg_temp.held(c) <> 0 then
    raise exception 'FAIL H4: after removing the moved line, A''s replacement lot holds %, the new customer %, the old %; expected 0, 1000 (for B), 0',
      (select l.remaining_amount from customer_credit_lots l where l.id = credit_lot_current(lot_a)), pg_temp.held(c2), pg_temp.held(c); end if;
  perform pg_temp.pay(inv, 2000);
  if pg_temp.held(c2) <> 3000 or pg_temp.granted(c2) <> 3000 or pg_temp.held(c) <> 0 then
    raise exception 'FAIL H4: settlement left the new customer % (granted %) and the old one %; expected exactly 3000 and 0',
      pg_temp.held(c2), pg_temp.granted(c2), pg_temp.held(c); end if;
  raise notice 'PASS H4: after a move, removing the line reclaims the replacement lot; B settles at exactly 3000 for the new customer';
end $$;

-- ── I. refunds and cancellation after a bundle that released credit settles ─
-- Released lots carry a benefit value like the settlement lot, so a customer
-- who paid in parts is valued, and refunded, exactly like one who paid at once.
do $$
declare pbv uuid; pbn uuid; cparts uuid; conce uuid; inv_p uuid; inv_o uuid; it_p uuid; it_o uuid; rel_lot uuid;
  opt_p jsonb; opt_o jsonb; k text; refund_p numeric; refund_o numeric;
  c uuid; inv uuid; it uuid; v_msg text;
begin
  -- 4000 paid credit, 800 bonus and 10 vouchers at S$20: 5000 of weight, so
  -- every benefit is worth exactly 80% of its face value.
  pbv := pg_temp.bundle(4000, 800, 10);

  -- In parts: 1500, spend 300 of the released credit, then 2500 settles.
  cparts := pg_temp.customer('BRP I parts');
  inv_p := pg_temp.invoice(cparts, jsonb_build_array(pg_temp.bundle_line(pbv, 10)));
  it_p := pg_temp.line(inv_p, 'premium_bundle');
  perform pg_temp.pay(inv_p, 1500);
  rel_lot := pg_temp.progress_lot(it_p);
  perform pg_temp.spend(cparts, 3);
  perform pg_temp.pay(inv_p, 2500);
  if (select i.status::text from invoices i where i.id = inv_p) <> 'paid' then
    raise exception 'FAIL I1 (fixture): the bundle paid in parts did not settle'; end if;

  -- At once: 4000, then the same 300 spent.
  conce := pg_temp.customer('BRP I once');
  inv_o := pg_temp.invoice(conce, jsonb_build_array(pg_temp.bundle_line(pbv, 10)));
  it_o := pg_temp.line(inv_o, 'premium_bundle');
  perform pg_temp.pay(inv_o, 4000);
  perform pg_temp.spend(conce, 3);

  opt_p := invoice_refund_options_before_sessions(inv_p);
  opt_o := invoice_refund_options_before_sessions(inv_o);
  if not exists (select 1 from jsonb_array_elements(opt_p->'benefits') x where (x->>'lot_id')::uuid = rel_lot) then
    raise exception 'FAIL I1: the credit released before settlement is not listed among the refundable benefits: %', opt_p->'benefits'; end if;
  if pg_temp.benefit_sum(opt_p, 'paid', 'granted_value') <> 4000 then
    raise exception 'FAIL I1: the paid credit benefits of the part-paid bundle grant %, expected 4000 (released 1500 + settled 2500)',
      pg_temp.benefit_sum(opt_p, 'paid', 'granted_value'); end if;
  foreach k in array array['paid','bonus','voucher'] loop
    if pg_temp.benefit_sum(opt_p, k, 'paid_value') <> pg_temp.benefit_sum(opt_o, k, 'paid_value')
       or pg_temp.benefit_sum(opt_p, k, 'max_refund') <> pg_temp.benefit_sum(opt_o, k, 'max_refund') then
      raise exception 'FAIL I1: % benefits are valued % (refundable %) when paid in parts but % (refundable %) when paid at once',
        k, pg_temp.benefit_sum(opt_p, k, 'paid_value'), pg_temp.benefit_sum(opt_p, k, 'max_refund'),
        pg_temp.benefit_sum(opt_o, k, 'paid_value'), pg_temp.benefit_sum(opt_o, k, 'max_refund'); end if;
  end loop;
  if pg_temp.benefit_sum(opt_p, 'paid', 'paid_value') <> 3200 or pg_temp.benefit_sum(opt_p, 'bonus', 'paid_value') <> 640
     or pg_temp.benefit_sum(opt_p, 'voucher', 'paid_value') <> 160 then
    raise exception 'FAIL I1: expected benefit values 3200 paid / 640 bonus / 160 vouchers, got % / % / %',
      pg_temp.benefit_sum(opt_p, 'paid', 'paid_value'), pg_temp.benefit_sum(opt_p, 'bonus', 'paid_value'),
      pg_temp.benefit_sum(opt_p, 'voucher', 'paid_value'); end if;
  raise notice 'PASS I1: released credit is a listed benefit, and paying in parts values every benefit exactly as paying at once (3200/640/160)';

  -- 3700 unused paid credit at 80% + 640 bonus + 160 vouchers.
  refund_o := pg_temp.refund_all_unused(inv_o, it_o);
  if refund_o <> 3760 or pg_temp.held(conce) <> 0 or pg_temp.held(conce, 'bonus') <> 0 or pg_temp.vouchers_held(conce) <> 0 then
    raise exception 'FAIL I2: refunding everything unused for the one-payment customer paid % (expected 3760) and left %/%/% (paid/bonus/vouchers)',
      refund_o, pg_temp.held(conce), pg_temp.held(conce, 'bonus'), pg_temp.vouchers_held(conce); end if;
  raise notice 'PASS I2 (one payment): refunding everything unused pays 3760 and leaves nothing held';

  -- (Fixed in 356 f; was a known defect) the same refund for the customer who paid in parts used to be refused.
  -- refund_invoice_recorded -> reconcile_invoice_commissions ->
  -- earn_premium_bundle_commission -> invoice_package_retained_commission_basis
  -- -> invoice_commission_benefit_source(benefit of the RELEASED lot) raises
  -- "Commission review required: resolve the original paid/bonus lot or voucher
  -- source for benefit ... before recalculating this refund." It only knows a
  -- sale's paid_credit_lot_id / bonus_credit_lot_id and its vouchers, not lots in
  -- credit_package_progress_lots, which 356 section 3b(d) now gives benefit rows.
  -- Refunding the settlement lot alone works; any refund that includes the
  -- released lot fails, so the credit released before settlement cannot be
  -- refunded. Re-enable these checks when invoice_commission_benefit_source maps
  -- a released lot (via credit_package_progress_lots.invoice_item_id) to the sale.
  refund_p := pg_temp.refund_all_unused(inv_p, it_p);
  if refund_p <> refund_o or refund_p <> 3760 then
    raise exception 'FAIL I2: refunding everything unused paid % to the part-paying customer and % to the one-payment customer (expected 3760 each)',
      refund_p, refund_o; end if;
  if pg_temp.held(cparts) <> 0 or pg_temp.held(cparts, 'bonus') <> 0 or pg_temp.vouchers_held(cparts) <> 0 then
    raise exception 'FAIL I2: after refunding everything unused, the part-paying customer holds %/%/% (paid/bonus/vouchers)',
      pg_temp.held(cparts), pg_temp.held(cparts, 'bonus'), pg_temp.vouchers_held(cparts); end if;
  if (select l.remaining_amount from customer_credit_lots l where l.id = rel_lot) <> 0 then
    raise exception 'FAIL I2: the refund left the released lot holding %',
      (select l.remaining_amount from customer_credit_lots l where l.id = rel_lot); end if;
  raise notice 'PASS I2 (in parts): refunding everything unused pays the same 3760, and takes the released credit back too';

  -- I3: a bundle with no bonus and no vouchers, fully released before the
  -- invoice settled (a product was still owed), can be cancelled. Its
  -- settlement grants nothing new, so before 356 it had no benefit value and
  -- cancelling was refused.
  pbn := pg_temp.bundle(1000, 0, 0);
  c := pg_temp.customer('BRP I3');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pbn),
           jsonb_build_object('kind','product','product_id',pg_temp.fx('prod'),'quantity',1)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  if (select i.status::text from invoices i where i.id = inv) <> 'partially_paid'
     or credit_package_released_paid_credit(it) <> 1000 or pg_temp.held(c) <> 1000 then
    raise exception 'FAIL I3 (fixture): expected the bundle fully released (1000) on a partly paid invoice, released % held % status %',
      credit_package_released_paid_credit(it), pg_temp.held(c), (select i.status from invoices i where i.id = inv); end if;
  perform pg_temp.pay(inv, 200);
  if (select i.status::text from invoices i where i.id = inv) <> 'paid' then
    raise exception 'FAIL I3 (fixture): the invoice did not settle'; end if;
  if pg_temp.granted(c) <> 1000 then
    raise exception 'FAIL I3: settlement of a fully released bundle granted % in total, expected 1000', pg_temp.granted(c); end if;
  if not exists (select 1 from invoice_benefit_values bv where bv.invoice_item_id = it and bv.lot_id = pg_temp.progress_lot(it)
                   and bv.granted_value = 1000 and bv.paid_value = 1000) then
    raise exception 'FAIL I3: the fully released lot has no benefit value (1000 granted / 1000 paid)'; end if;
  begin
    perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL I3: a fully released bundle could not be cancelled: %', v_msg;
  end;
  if (select i.status::text from invoices i where i.id = inv) <> 'cancelled' or pg_temp.held(c) <> 0 then
    raise exception 'FAIL I3: after cancelling, status % and the customer still holds %',
      (select i.status from invoices i where i.id = inv), pg_temp.held(c); end if;
  raise notice 'PASS I3: a no-bonus, no-voucher bundle fully released before settlement cancels, and its 1000 is taken back';

  -- I4: reopening that cancelled invoice gives the released credit back through
  -- its benefit row, once.
  perform reopen_invoice(inv, 'The cancellation was a mistake', gen_random_uuid());
  if (select i.status::text from invoices i where i.id = inv) <> 'paid' or pg_temp.held(c) <> 1000 or pg_temp.granted(c) <> 1000 then
    raise exception 'FAIL I4: reopened as % with % held (% granted); expected paid with exactly 1000',
      (select i.status from invoices i where i.id = inv), pg_temp.held(c), pg_temp.granted(c); end if;
  raise notice 'PASS I4: reopening restores exactly the 1000 released before settlement';
end $$;

-- ── J. cancel, then reopen, a part-paid bundle ──────────────────────────────
-- The reclaimed credit goes back to the release record, so the reopened
-- invoice releases it again as its money is counted — once.
do $$
declare pbc uuid; c uuid; inv uuid; it uuid;
begin
  pbc := pg_temp.bundle(5000, 500, 0);

  -- J1: nothing spent.
  c := pg_temp.customer('BRP J1');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pbc)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform cancel_invoice_recorded(inv, 'Cancelled in error', gen_random_uuid());
  if pg_temp.held(c) <> 0 then raise exception 'FAIL J1: % still held after cancelling', pg_temp.held(c); end if;
  perform reopen_invoice(inv, 'The cancellation was a mistake', gen_random_uuid());
  if (select i.status::text from invoices i where i.id = inv) <> 'partially_paid' then
    raise exception 'FAIL J1: reopened as %, expected partially_paid', (select i.status from invoices i where i.id = inv); end if;
  if pg_temp.held(c) <> 1000 or credit_package_released_paid_credit(it) <> 1000 then
    raise exception 'FAIL J1: after reopening, the customer holds % with % released on record; expected 1000 for the 1000 received',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  perform pg_temp.pay(inv, 4000);
  if (select i.status::text from invoices i where i.id = inv) <> 'paid' then
    raise exception 'FAIL J1: the reopened bundle did not settle'; end if;
  if pg_temp.held(c) <> 5000 or pg_temp.granted(c) <> 5000 or pg_temp.held(c, 'bonus') <> 500 then
    raise exception 'FAIL J1: after paying the rest the customer holds % paid (granted %) and % bonus; expected exactly 5000 and 500',
      pg_temp.held(c), pg_temp.granted(c), pg_temp.held(c, 'bonus'); end if;
  raise notice 'PASS J1: cancel then reopen releases the 1000 again, and paying the rest lands on exactly 5000 + 500';

  -- J2: 300 spent before the cancel. The spent 300 was written off, the
  -- reclaimed 700 comes back, and what is held plus what was spent is the entitlement.
  c := pg_temp.customer('BRP J2');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pbc)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform pg_temp.spend(c, 3);
  perform cancel_invoice_recorded(inv, 'Cancelled in error', gen_random_uuid());
  perform reopen_invoice(inv, 'The cancellation was a mistake', gen_random_uuid());
  if pg_temp.held(c) <> 700 or credit_package_released_paid_credit(it) <> 1000 then
    raise exception 'FAIL J2: after reopening, the customer holds % with % released on record; expected 700 held (300 spent) and 1000 released',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  perform pg_temp.pay(inv, 4000);
  if pg_temp.held(c) <> 4700 then
    raise exception 'FAIL J2: after paying the rest the customer holds %, expected 4700 (5000 less the 300 spent)', pg_temp.held(c); end if;
  raise notice 'PASS J2: with 300 spent before the cancel, reopening and paying the rest leaves 4700 held + 300 spent = 5000';
end $$;

-- ── K. moved to another customer, then cancelled ────────────────────────────
-- The move empties the released lot and issues a replacement to the new
-- customer. Before 356 the cancel looked at the emptied lot, "wrote off" the
-- 1000 and left the replacement spendable.
do $$
declare pbd uuid; cpk uuid; c1 uuid; c2 uuid; inv uuid; it uuid; lot uuid; repl uuid; ev jsonb;
begin
  pbd := pg_temp.bundle(5000, 500, 0);

  -- K1: bundle, nothing spent.
  c1 := pg_temp.customer('BRP K1 wrong');
  c2 := pg_temp.customer('BRP K1 right');
  inv := pg_temp.invoice(c1, jsonb_build_array(pg_temp.bundle_line(pbd)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  lot := pg_temp.progress_lot(it);
  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbd) || jsonb_build_object('invoice_item_id', it)),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  repl := credit_lot_current(lot);
  if pg_temp.held(c1) <> 0 or pg_temp.held(c2) <> 1000 or repl = lot
     or (select l.customer_id from customer_credit_lots l where l.id = repl) <> c2 then
    raise exception 'FAIL K1 (fixture): after the move the old customer holds %, the new one % (replacement lot %)',
      pg_temp.held(c1), pg_temp.held(c2), repl; end if;
  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  if pg_temp.held(c2) <> 0 or pg_temp.held(c1) <> 0 then
    raise exception 'FAIL K1: after cancelling, the new customer still holds % (old customer %)', pg_temp.held(c2), pg_temp.held(c1); end if;
  if (select l.status from customer_credit_lots l where l.id = repl) <> 'reversed' then
    raise exception 'FAIL K1: the replacement lot was not closed by the cancel'; end if;
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_cancel' and a.record_id = inv order by a.created_at desc limit 1;
  if ev is null or (ev->>'reclaimed')::numeric <> 1000 or (ev->>'written_off')::numeric <> 0 then
    raise exception 'FAIL K1: expected the audit to say 1000 reclaimed and 0 written off, it says %', ev; end if;
  raise notice 'PASS K1: after a move, cancelling reclaims the replacement lot — audit: 1000 reclaimed, 0 written off';

  -- K2: the new customer spends 300 of the replacement first.
  c1 := pg_temp.customer('BRP K2 wrong');
  c2 := pg_temp.customer('BRP K2 right');
  inv := pg_temp.invoice(c1, jsonb_build_array(pg_temp.bundle_line(pbd)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbd) || jsonb_build_object('invoice_item_id', it)),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  perform pg_temp.spend(c2, 3);
  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_cancel' and a.record_id = inv order by a.created_at desc limit 1;
  if pg_temp.held(c2) <> 0 or ev is null or (ev->>'reclaimed')::numeric <> 700 or (ev->>'written_off')::numeric <> 300 then
    raise exception 'FAIL K2: expected 700 reclaimed and 300 written off with nothing left held; held %, audit %', pg_temp.held(c2), ev; end if;
  raise notice 'PASS K2: with 300 spent by the new customer, the cancel reclaims 700 and writes off 300';

  -- K3: the package variant.
  cpk := pg_temp.package(2000);
  c1 := pg_temp.customer('BRP K3 wrong');
  c2 := pg_temp.customer('BRP K3 right');
  inv := pg_temp.invoice(c1, jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cpk,'quantity',1)));
  it := pg_temp.line(inv, 'credit_package');
  perform pg_temp.pay(inv, 800);
  perform correct_invoice(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','credit_package','credit_package_id',cpk,'quantity',1)),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  if pg_temp.held(c2) <> 800 then raise exception 'FAIL K3 (fixture): the package credit did not move (new customer holds %)', pg_temp.held(c2); end if;
  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_cancel' and a.record_id = inv order by a.created_at desc limit 1;
  if pg_temp.held(c2) <> 0 or ev is null or (ev->>'reclaimed')::numeric <> 800 or (ev->>'written_off')::numeric <> 0 then
    raise exception 'FAIL K3: expected 800 reclaimed and 0 written off with nothing left held; held %, audit %', pg_temp.held(c2), ev; end if;
  raise notice 'PASS K3: the package variant reclaims the moved 800 on cancel';

  -- K4: moved, then paid in full: settlement follows the replacement lot, so the
  -- new customer ends on exactly the entitlement and the replacement is a benefit.
  c1 := pg_temp.customer('BRP K4 wrong');
  c2 := pg_temp.customer('BRP K4 right');
  inv := pg_temp.invoice(c1, jsonb_build_array(pg_temp.bundle_line(pbd)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  lot := pg_temp.progress_lot(it);
  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbd) || jsonb_build_object('invoice_item_id', it)),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  repl := credit_lot_current(lot);
  perform pg_temp.pay(inv, 4000);
  if (select i.status::text from invoices i where i.id = inv) <> 'paid'
     or pg_temp.held(c2) <> 5000 or pg_temp.granted(c2) <> 5000 or pg_temp.held(c2, 'bonus') <> 500 or pg_temp.held(c1) <> 0 then
    raise exception 'FAIL K4: after moving and settling, the new customer holds % paid (granted %) and % bonus, the old one %; expected 5000 + 500 and 0',
      pg_temp.held(c2), pg_temp.granted(c2), pg_temp.held(c2, 'bonus'), pg_temp.held(c1); end if;
  if not exists (select 1 from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') x
                  where (x->>'lot_id')::uuid = repl and (x->>'customer_id')::uuid = c2 and (x->>'granted_value')::numeric = 1000) then
    raise exception 'FAIL K4: the replacement lot is not listed as the new customer''s 1000 benefit'; end if;
  raise notice 'PASS K4: moved then settled — the new customer holds exactly 5000 + 500, and the replacement lot is a benefit';

  -- K5: moved, then a payment removed: the trim follows the replacement lot.
  c1 := pg_temp.customer('BRP K5 wrong');
  c2 := pg_temp.customer('BRP K5 right');
  inv := pg_temp.invoice(c1, jsonb_build_array(pg_temp.bundle_line(pbd)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform pg_temp.pay(inv, 600);
  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbd) || jsonb_build_object('invoice_item_id', it)),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  perform remove_invoice_payment(pg_temp.receipt(inv, 600), 'Recorded twice', gen_random_uuid());
  if pg_temp.held(c2) <> 1000 or pg_temp.held(c1) <> 0 or credit_package_released_paid_credit(it) <> 1000 then
    raise exception 'FAIL K5: after moving and removing the 600, the new customer holds %, the old one %, % released; expected 1000, 0, 1000',
      pg_temp.held(c2), pg_temp.held(c1), credit_package_released_paid_credit(it); end if;
  raise notice 'PASS K5: moved then a payment removed — the 600 is taken back from the new customer''s replacement lot';
end $$;

-- ── L. a payment corrected down, or removed, on a part-paid bundle ──────────
-- Unspent credit released for money no longer recorded goes back; credit
-- already spent stays (credit ahead of payment, squared at settlement);
-- nothing is refused.
do $$
declare pbe uuid; cpe uuid; c uuid; inv uuid; it uuid; spent_inv uuid; v_msg text;
begin
  pbe := pg_temp.bundle(5000, 500, 0);

  -- L1: 1000 + 1200 received, 300 spent; the 1200 is corrected to 500, then the 1000 is removed.
  c := pg_temp.customer('BRP L1');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pbe)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform pg_temp.pay(inv, 1200);
  spent_inv := pg_temp.spend(c, 3);
  if pg_temp.held(c) <> 1900 then raise exception 'FAIL L1 (fixture): expected 1900 held (2200 released, 300 spent), got %', pg_temp.held(c); end if;
  begin
    perform correct_invoice_payment(pg_temp.receipt(inv, 1200), 500, sg_today(), pg_temp.fx('pm'),
      'Keyed 1200 instead of 500', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL L1: correcting a payment down on a part-paid bundle was refused: %', v_msg;
  end;
  if pg_temp.held(c) <> 1200 or credit_package_released_paid_credit(it) <> 1500 then
    raise exception 'FAIL L1: after correcting 1200 down to 500 (1500 received, 300 spent) the customer holds % with % released; expected 1200 and 1500',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  if not exists (select 1 from customer_credit_ledger g where g.source_record_id = inv
                   and g.source_type = 'invoice_payment_released_credit' and g.entry_type = 'adjust_decrease') then
    raise exception 'FAIL L1: the credit taken back is not on the ledger'; end if;
  begin
    perform remove_invoice_payment(pg_temp.receipt(inv, 1000), 'Recorded twice', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL L1: removing a payment on a part-paid bundle was refused: %', v_msg;
  end;
  if pg_temp.held(c) <> 200 or credit_package_released_paid_credit(it) <> 500 then
    raise exception 'FAIL L1: after removing the 1000 (500 received, 300 spent) the customer holds % with % released; expected 200 and 500',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  if (select coalesce(sum(a.amount - a.reversed_amount),0) from invoice_line_credit_allocations a where a.invoice_id = spent_inv) <> 300 then
    raise exception 'FAIL L1: the 300 already spent was disturbed'; end if;
  perform pg_temp.pay(inv, 4500);
  if (select i.status::text from invoices i where i.id = inv) <> 'paid' or pg_temp.held(c) <> 4700 or pg_temp.held(c, 'bonus') <> 500 then
    raise exception 'FAIL L1: after paying the rest the customer holds % paid and % bonus (status %); expected 4700 (5000 less 300 spent) and 500',
      pg_temp.held(c), pg_temp.held(c, 'bonus'), (select i.status from invoices i where i.id = inv); end if;
  raise notice 'PASS L1: correcting 1200 to 500 took back 700, removing the 1000 took back 1000 more; spent 300 untouched; settles at 4700 + 300 spent';

  -- L2: more spent than the money left — only the unspent part goes back, not refused.
  c := pg_temp.customer('BRP L2');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pbe)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform pg_temp.pay(inv, 1200);
  spent_inv := pg_temp.spend(c, 15);
  begin
    perform remove_invoice_payment(pg_temp.receipt(inv, 1200), 'Cheque bounced', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL L2: removing a payment whose credit was already spent was refused: %', v_msg;
  end;
  if pg_temp.held(c) <> 0 or credit_package_released_paid_credit(it) <> 1500 then
    raise exception 'FAIL L2: with 1500 spent and 1000 still received, the customer holds % with % released; expected 0 and 1500 (500 ahead of payment)',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  if (select coalesce(sum(a.amount - a.reversed_amount),0) from invoice_line_credit_allocations a where a.invoice_id = spent_inv) <> 1500 then
    raise exception 'FAIL L2: the 1500 already spent was disturbed'; end if;
  perform pg_temp.pay(inv, 4000);
  if pg_temp.held(c) <> 3500 or pg_temp.held(c, 'bonus') <> 500 then
    raise exception 'FAIL L2: settlement left % paid and % bonus; expected 3500 (5000 less the 1500 spent) and 500',
      pg_temp.held(c), pg_temp.held(c, 'bonus'); end if;
  raise notice 'PASS L2: removing a payment after 1500 was spent takes back only the unspent 500; settlement squares it at 3500 + 1500 spent';

  -- L3: the package variant — 800 + 600 received, 300 spent, the 600 removed.
  cpe := pg_temp.package(2000);
  c := pg_temp.customer('BRP L3');
  inv := pg_temp.invoice(c, jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cpe,'quantity',1)));
  it := pg_temp.line(inv, 'credit_package');
  perform pg_temp.pay(inv, 800);
  perform pg_temp.pay(inv, 600);
  perform pg_temp.spend(c, 3);
  perform remove_invoice_payment(pg_temp.receipt(inv, 600), 'Recorded twice', gen_random_uuid());
  if pg_temp.held(c) <> 500 or credit_package_released_paid_credit(it) <> 800 then
    raise exception 'FAIL L3: after removing the 600 (800 received, 300 spent) the package customer holds % with % released; expected 500 and 800',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  raise notice 'PASS L3: the package variant takes back the unspent credit of a removed payment';

  -- L4: the same two fixes made from the invoice edit form (correct_invoice with
  -- payment_corrections and payment_removals) behave the same way.
  c := pg_temp.customer('BRP L4');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pbe)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform pg_temp.pay(inv, 1200);
  perform pg_temp.spend(c, 3);
  begin
    perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pbe) || jsonb_build_object('invoice_item_id', it)),
      jsonb_build_object(
        'payment_corrections', jsonb_build_array(jsonb_build_object('payment_id', pg_temp.receipt(inv, 1200), 'amount', 500,
                                 'date', sg_today()::text, 'payment_method_id', pg_temp.fx('pm'))),
        'payment_removals', jsonb_build_array(pg_temp.receipt(inv, 1000)::text)),
      'Payments keyed wrongly', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL L4: fixing the payments from the edit form was refused: %', v_msg;
  end;
  if pg_temp.held(c) <> 200 or credit_package_released_paid_credit(it) <> 500 then
    raise exception 'FAIL L4: after the edit form left 500 received (300 spent) the customer holds % with % released; expected 200 and 500',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  raise notice 'PASS L4: the edit form''s payment correction and removal take back the same unspent credit';

  raise notice 'PASS: released credit stays right when a line is removed, after settlement, on cancel/reopen, after a move, and when payments go down.';
end $$;
rollback;
