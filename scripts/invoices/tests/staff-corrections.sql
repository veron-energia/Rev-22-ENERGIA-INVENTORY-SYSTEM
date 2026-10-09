-- Staff correct paid and part-paid invoices; money edits stay with an Owner or
-- Manager (377).
--
--   S1 A staff member corrects a paid invoice of their own store: a line's
--      quantity, the customer, the referrer, the service staff, a payment's
--      method, the business date, the notes and the instalment details. Each
--      is audited like an Owner's correction: a revision with the reason and
--      an audit row, both by the staff member.
--   S2 And a part-paid invoice, and under today's unpaid-invoice rules a
--      manual discount (with its reason), FOC (with its reason) and a
--      discount voucher.
--   S3 Staff are refused, and the invoice is left as it was: another store's
--      invoice; a cancelled, refunded, refund-requested,
--      cancellation-requested or FOC-completed invoice; an unpaid invoice
--      with payment history; an exchange, refund top-up or voucher-claim
--      document (a voucher claim stays a paid S$0 hand-over: no line added,
--      no customer changed); an invoice with a refund request waiting; a
--      price override; a payment's amount or date; a payment removed as
--      recorded by mistake; a split; a store move, even to another store
--      they work at; who raised it; no reason.
--   S4 A refusal that needs an Owner's or Manager's review or action tells
--      staff to ask one, on a paid invoice and on an unpaid one: all five
--      such refusals carry the hint (four are also driven: historical stock,
--      voucher units, issued credit, therapy, the wallet). The Owner's,
--      Manager's, Admin's and Inventory Manager's messages are word for word
--      as before.
--   S5 The payment lock: staff change a settled payment's method only on an
--      invoice they may correct; its amount stays locked for everyone.
--   S6 Owners and Managers are unchanged: each kept-back change still works
--      for them, on a cancelled invoice too, and with a request waiting.
--   S7 Admin and Inventory Manager are still refused, with the old message;
--      a deactivated staff member has no access, and a deleted one may not
--      correct; staff still edit an unpaid invoice as before.
--   S8 staff_may_correct_invoice answers only for staff, and only signed-in
--      users may call it.
--   S9 A saved price stays with what was sold (371's rule, carried by 377):
--      staff swapping a saved line to another product, voucher, credit
--      package, special product, or a rental's other length or rate, while
--      sending its saved price, are refused as a price override, with stock
--      untouched; sent without the saved price, the new item is charged at
--      its catalogue price. An Owner's swap is as before.
--   S10 Adding units to a saved line at its saved price. A special price an
--      Owner or Manager set, as the line shows it: staff may not add units
--      at it; they may lower the quantity or remove the line. A saved price
--      below today's catalogue price (an old lower price, or a special price
--      the line cannot show): staff are told to add the units as a new line
--      at today's price, which they may; they may still lower the quantity.
--      At a saved price equal to or above today's they add units. The
--      "Manual Override" mark counts; a line sold at its recorded catalogue
--      price that has since gone down does not. A ticket's price is its
--      price on the invoice's date (370), but never below its price on the
--      date the invoice had before its first correction: staff who back-date
--      the invoice into the early bird, in the same save or an earlier one,
--      still may not add a person at a price below the price of that date
--      (an earlier change that saved no invoice snapshot does not count as
--      the first correction), nor after moving an early-bird invoice's date
--      forward. Changes that keep the quantity are not refused: staff still
--      give FOC with its reason, apply a line voucher or change a rental's
--      return date on a line at a special or below-today price. Owners and
--      Managers as before.
--   S11 Staff change only the method of a payment that stands: not a
--      correction's reversal, not a reversed receipt, not a refunded
--      payment, not a payment of an invoice with an older refund that names
--      no payment. The replacement may be changed; an Owner as before.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 377 (install it after "begin;" on a
-- database that does not have it yet). Fixtures are invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true) $$;
-- The invoice's lines as the correction form sends them back: each saved line
-- with its id and its saved unit price.
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$$ select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text,
     'product_id', product_id, 'voucher_id', voucher_id, 'promotion_id', promotion_id,
     'therapy_service_id', therapy_service_id, 'therapy_package_id', therapy_package_id,
     'credit_package_id', credit_package_id, 'premium_bundle_id', premium_bundle_id,
     'special_product_id', special_product_id, 'rental_rate_type', rental_rate_type, 'rental_periods', rental_periods,
     'rental_start_date', rental_start_date, 'rental_return_date', rental_return_date,
     'quantity', quantity, 'unit_price', unit_price,
     'foc_quantity', nullif(foc_quantity, 0), 'foc_reason', foc_reason)) order by id)
     from public.invoice_items where invoice_id = inv $$;
-- The same lines with the first one's fields replaced; a null drops a field
-- (unit_price null: the line is sent without its saved price).
create function pg_temp.line0(inv uuid, patch jsonb) returns jsonb language sql as
$$ select jsonb_set(pg_temp.lines(inv), '{0}', jsonb_strip_nulls((pg_temp.lines(inv)->0) || patch)) $$;
-- The same lines with the first one's quantity changed (the price stays the saved one).
create function pg_temp.with_qty(inv uuid, q int) returns jsonb language sql as
$$ select jsonb_set(pg_temp.lines(inv), '{0,quantity}', to_jsonb(q)) $$;
-- A correction as the page saves it; null when it was saved, else the refusal.
-- A refusal rolls back everything it did.
create function pg_temp.try(inv uuid, items jsonb, hdr jsonb, reason text default 'Keyed wrongly at the till') returns text language plpgsql as
$$begin perform public.correct_invoice(inv, items, hdr, reason, gen_random_uuid()); return null;
exception when others then return sqlerrm; end$$;
-- A sale of the test product at a store, made and paid (in cash) by the Owner.
create function pg_temp.sale(st text, qty int, paid numeric default null, cust text default 'c1') returns uuid language plpgsql as
$$declare inv uuid;
begin
  perform pg_temp.as_user('o');
  inv := public.create_invoice(pg_temp.fx(st), pg_temp.fx(cust), null,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('prod'),'quantity',qty)));
  if coalesce(paid, qty * 100) > 0 then
    perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', coalesce(paid, qty * 100))));
  end if;
  return inv;
end$$;
create function pg_temp.pay(inv uuid) returns uuid language sql as
$$ select id from public.invoice_payments where invoice_id = inv and entry_kind = 'receipt' order by created_at limit 1 $$;
create function pg_temp.pay_date(p uuid) returns date language sql as
$$ select (coalesce(effective_at, created_at) at time zone 'Asia/Singapore')::date from public.invoice_payments where id = p $$;
-- What a refusal must leave untouched.
create function pg_temp.untouched(inv uuid) returns boolean language sql as
$$ select coalesce(i.edit_count, 0) = 0 and not exists (select 1 from public.invoice_revisions r where r.invoice_id = inv)
     and (select count(*) from public.invoice_payments p where p.invoice_id = inv) = 1
     and (select quantity from public.invoice_items it where it.invoice_id = inv order by id limit 1) = 1
     from public.invoices i where i.id = inv $$;
-- Shelf stock of a test product at a store, and a test voucher's stock at A.
create function pg_temp.stock(st text, p text) returns int language sql as
$$ select current_qty from public.store_inventory where store_id = pg_temp.fx(st) and product_id = pg_temp.fx(p) $$;
create function pg_temp.vstock(v text) returns int language sql as
$$ select current_qty from public.voucher_store_stock where store_id = pg_temp.fx('A') and voucher_id = pg_temp.fx(v) $$;
-- A sale of one line (a jsonb invoice line) at store A, made by the Owner and
-- paid in cash (all of it, or the amount given).
create function pg_temp.sale_of(line jsonb, paid numeric) returns uuid language plpgsql as
$$declare inv uuid;
begin
  perform pg_temp.as_user('o');
  inv := public.create_invoice(pg_temp.fx('A'), pg_temp.fx('c1'), null, jsonb_build_array(line));
  if paid > 0 then
    perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', paid)));
  end if;
  return inv;
end$$;

-- ═════ Fixtures (invented) ═════
do $$
declare o uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); s2 uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); im uuid:=gen_random_uuid(); sx uuid:=gen_random_uuid(); sd uuid:=gen_random_uuid();
 sfx text:=lower(substr(md5(random()::text||clock_timestamp()::text),1,6)); ph text:=lpad((floor(random()*900000))::int::text,6,'0');
 st_a uuid; st_b uuid; st_c uuid; prod uuid; cash uuid; card uuid; c1 uuid; c2 uuid; r1 uuid; r2 uuid; aff1 uuid; aff2 uuid; dv uuid;
 mat uuid; v40 uuid; v400 uuid; cp100 uuid; cp1000 uuid; chair uuid; bed uuid;
 pr50 uuid; pr500 uuid; ts30 uuid; ts300 uuid; tp150 uuid; tp1500 uuid; b200 uuid; b2000 uuid;
begin
 insert into auth.users(id,email) values
   (o,'s377-o-'||sfx||'@tests.invalid'),(m,'s377-m-'||sfx||'@tests.invalid'),(s,'s377-s-'||sfx||'@tests.invalid'),
   (s2,'s377-s2-'||sfx||'@tests.invalid'),(a,'s377-a-'||sfx||'@tests.invalid'),(im,'s377-im-'||sfx||'@tests.invalid'),
   (sx,'s377-sx-'||sfx||'@tests.invalid'),(sd,'s377-sd-'||sfx||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (o,'S377 Owner','s377-o-'||sfx||'@tests.invalid','owner'),
   (m,'S377 Manager','s377-m-'||sfx||'@tests.invalid','manager'),
   (s,'S377 Staff','s377-s-'||sfx||'@tests.invalid','staff'),
   (s2,'S377 Other Staff','s377-s2-'||sfx||'@tests.invalid','staff'),
   (a,'S377 Admin','s377-a-'||sfx||'@tests.invalid','admin'),
   (im,'S377 Inventory','s377-im-'||sfx||'@tests.invalid','inventory_manager'),
   (sx,'S377 Former Staff','s377-sx-'||sfx||'@tests.invalid','staff'),
   (sd,'S377 Deleted Staff','s377-sd-'||sfx||'@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('S377 Store A '||sfx,'S377A'||sfx,'SG') returning id into st_a;
 insert into stores(name,code,country_code) values('S377 Store B '||sfx,'S377B'||sfx,'SG') returning id into st_b;
 insert into stores(name,code,country_code) values('S377 Store C '||sfx,'S377C'||sfx,'SG') returning id into st_c;
 -- The staff member works at A and B; the other staff member at C only.
 insert into user_store_assignments(user_id,store_id) values(s,st_a),(s,st_b),(s2,st_c),(m,st_a),(m,st_b),(im,st_a),(sx,st_a),(sd,st_a);
 update profiles set is_active = false where id = sx;
 -- Deleted but never deactivated: store access alone still lets this profile in.
 update profiles set deleted_at = now() where id = sd;
 insert into payment_methods(name) values('S377 Cash '||sfx) returning id into cash;
 insert into payment_methods(name) values('S377 Card '||sfx) returning id into card;
 insert into products(name,sku,product_type) values('S377 Socks','S377-'||sfx,'own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st_a,prod,500),(st_b,prod,500),(st_c,prod,500);
 perform set_product_prices(st_a,prod,100,100,'available');
 perform set_product_prices(st_b,prod,100,100,'available');
 perform set_product_prices(st_c,prod,100,100,'available');
 insert into customers(full_name,phone) values('S377 Buyer One','+6591'||ph) returning id into c1;
 insert into customers(full_name,phone) values('S377 Buyer Two','+6592'||ph) returning id into c2;
 insert into customers(full_name,phone) values('S377 Referrer One','+6593'||ph) returning id into r1;
 insert into customers(full_name,phone) values('S377 Referrer Two','+6594'||ph) returning id into r2;
 insert into customer_affiliates(customer_id,status,store_id,activated_at) values(r1,'active',st_a,now()) returning id into aff1;
 insert into customer_affiliates(customer_id,status,store_id,activated_at) values(r2,'active',st_a,now()) returning id into aff2;
 insert into vouchers(name,code,voucher_kind,discount_amount) values('S377 Ten Off','S377D'||sfx,'fixed_discount',10) returning id into dv;
 -- For the catalogue swaps (S9) and special prices (S10): a dearer product,
 -- and two of each other kind a line can be: gift vouchers, credit packages,
 -- special products, promotions, therapy sessions and packages, premium
 -- bundles.
 insert into products(name,sku,product_type) values('S377 Mattress','S377M-'||sfx,'own') returning id into mat;
 insert into store_inventory(store_id,product_id,current_qty) values(st_a,mat,50);
 perform set_product_prices(st_a,mat,3000,3000,'available');
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('S377 Gift 40','S377G40'||sfx,'normal',40,'limited') returning id into v40;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('S377 Gift 400','S377G400'||sfx,'normal',400,'limited') returning id into v400;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v40,st_a,20),(v400,st_a,20);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v40,st_a,40,true),(v400,st_a,400,true);
 insert into credit_packages(name,customer_price,paid_credit_amount) values('S377 Credit 100 '||sfx,100,100) returning id into cp100;
 insert into credit_packages(name,customer_price,paid_credit_amount) values('S377 Credit 1000 '||sfx,1000,1000) returning id into cp1000;
 insert into special_products(name,sku,sale_price,rate_day,rate_week) values('S377 Chair','S377CH'||sfx,500,20,100) returning id into chair;
 insert into special_products(name,sku,sale_price,rate_day,rate_week) values('S377 Bed','S377BD'||sfx,5000,200,1000) returning id into bed;
 insert into promotions(name,code,promo_type,fixed_price) values('S377 Promo 50','S377P50'||sfx,'bundle',50) returning id into pr50;
 insert into promotions(name,code,promo_type,fixed_price) values('S377 Promo 500','S377P500'||sfx,'bundle',500) returning id into pr500;
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(pr50,st_a,50,true),(pr500,st_a,500,true);
 insert into therapy_services(service_code,name,standard_price,duration_minutes,is_active) values('S377S30'||sfx,'S377 Session 30',30,30,true) returning id into ts30;
 insert into therapy_services(service_code,name,standard_price,duration_minutes,is_active) values('S377S300'||sfx,'S377 Session 300',300,60,true) returning id into ts300;
 insert into therapy_service_stores(service_id,store_id) values(ts30,st_a),(ts300,st_a);
 insert into unlimited_therapy_packages(name,duration_months) values('S377 Therapy 1m',1) returning id into tp150;
 insert into unlimited_therapy_packages(name,duration_months) values('S377 Therapy 12m',12) returning id into tp1500;
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store) values(tp150,st_a,150,true),(tp1500,st_a,1500,true);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount) values('S377 Bundle 200 '||sfx,200,200) returning id into b200;
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount) values('S377 Bundle 2000 '||sfx,2000,2000) returning id into b2000;
 insert into fx values('o',o),('m',m),('s',s),('s2',s2),('a',a),('im',im),('sx',sx),('sd',sd),('A',st_a),('B',st_b),('C',st_c),
   ('prod',prod),('cash',cash),('card',card),('c1',c1),('c2',c2),('aff1',aff1),('aff2',aff2),('dv',dv),
   ('mat',mat),('v40',v40),('v400',v400),('cp100',cp100),('cp1000',cp1000),('chair',chair),('bed',bed),
   ('pr50',pr50),('pr500',pr500),('ts30',ts30),('ts300',ts300),('tp150',tp150),('tp1500',tp1500),('b200',b200),('b2000',b2000);
end $$;
do $$
declare inv uuid := pg_temp.sale('A', 1);
begin
  perform pg_temp.check((select status from public.invoices where id = inv) = 'paid'
      and (select locked_at is not null from public.invoice_payments where id = pg_temp.pay(inv)),
    'S0 a paid sale is paid and its payment is locked (the checks below rely on it)');
end $$;

-- ═════ S1 Staff correct a paid invoice of their own store ═════
do $$
declare inv uuid; e text; before_qty int; after_qty int;
begin
  -- A line's quantity, at the saved price.
  inv := pg_temp.sale('A', 2);
  select current_qty into before_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx('prod');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 3), jsonb_build_object('expected_edit_count', 0), 'Customer took a third pair');
  select current_qty into after_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx('prod');
  perform pg_temp.check(e is null, 'S1 staff change a line''s quantity on a paid invoice of their store, got ' || coalesce(e, 'saved'));
  perform pg_temp.check((select (status, total_amount, paid_amount, edit_count, edited_by)
                           = ('partially_paid'::invoice_status, 300.00::numeric, 200.00::numeric, 1, pg_temp.fx('s'))
                           from public.invoices where id = inv)
      and (select unit_price from public.invoice_items where invoice_id = inv) = 100
      and before_qty - after_qty = 1,
    'S1 the invoice is now 3 at S$100.00, S$300.00 with S$200.00 paid (part-paid), one more pair left the shelf, edited by the staff member');
  perform pg_temp.check(exists (select 1 from public.invoice_revisions r where r.invoice_id = inv and r.edited_by = pg_temp.fx('s')
                                   and r.edit_reason = 'Customer took a third pair' and r.after_snapshot is not null
                                   and (r.snapshot->'invoice'->>'total_amount')::numeric = 200)
      and exists (select 1 from public.audit_logs l where l.record_id = inv and l.action = 'invoice_corrected'
                     and l.changed_by = pg_temp.fx('s') and l.actor_role = 'staff' and l.reason = 'Customer took a third pair'),
    'S1 it is audited: a revision with the reason and the before and after, and an audit row by the staff member');

  -- The customer.
  inv := pg_temp.sale('A', 1);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')), 'Wrong customer picked');
  perform pg_temp.check(e is null and (select customer_id from public.invoices where id = inv) = pg_temp.fx('c2')
      and exists (select 1 from public.audit_logs l where l.record_id = inv and l.action = 'invoice_corrected' and l.changed_by = pg_temp.fx('s')),
    'S1 staff change the customer (audited), got ' || coalesce(e, 'saved'));

  -- The referrer: added where there was none, then changed.
  inv := pg_temp.sale('A', 1);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('affiliate_id', pg_temp.fx('aff1')), 'Referrer missed at the till');
  e := coalesce(e, pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('affiliate_id', pg_temp.fx('aff2')), 'Wrong referrer'));
  perform pg_temp.check(e is null and (select affiliate_id from public.invoices where id = inv) = pg_temp.fx('aff2')
      and (select count(*) from public.invoice_revisions r where r.invoice_id = inv and r.edited_by = pg_temp.fx('s')) = 2,
    'S1 staff add and change the referrer (two revisions), got ' || coalesce(e, 'saved'));

  -- The service staff.
  inv := pg_temp.sale('A', 1);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('service_staff', jsonb_build_array(pg_temp.fx('s'))), 'Served by me');
  perform pg_temp.check(e is null and exists (select 1 from public.invoice_service_staff where invoice_id = inv and staff_id = pg_temp.fx('s')),
    'S1 staff set the service staff, got ' || coalesce(e, 'saved'));

  -- The business date, the notes and the instalment details, in one save.
  inv := pg_temp.sale('A', 1);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('business_date', '2026-09-15', 'notes', 'Gift wrapped',
         'instalment_category', 'in_house', 'instalment_method_id', pg_temp.fx('card'), 'instalment_months', 6), 'Back-dated sale and notes');
  perform pg_temp.check(e is null and (select (business_date, notes, instalment_category, instalment_method_id, instalment_months)
                                          = ('2026-09-15'::date, 'Gift wrapped', 'in_house', pg_temp.fx('card'), 6)
                                          from public.invoices where id = inv),
    'S1 staff change the business date, the notes and the instalment details, got ' || coalesce(e, 'saved'));
end $$;

-- A payment's method (the page sends a method-only change as payment_methods).
do $$
declare inv uuid; p uuid; e text;
begin
  inv := pg_temp.sale('A', 1);
  p := pg_temp.pay(inv);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv),
         jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p, 'payment_method_id', pg_temp.fx('card')))),
         'Paid by card, keyed as cash');
  perform pg_temp.check(e is null and (select (payment_method_id, amount, locked_at is not null) = (pg_temp.fx('card'), 100.00::numeric, true)
                                          from public.invoice_payments where id = p)
      and (select count(*) from public.invoice_payments where invoice_id = inv) = 1,
    'S1 staff change a settled payment''s method in place: same payment, same amount, no new entries, got ' || coalesce(e, 'saved'));
  perform pg_temp.check(exists (select 1 from public.audit_logs l where l.record_id = inv and l.action = 'payment_method_corrected'
                                   and l.changed_by = pg_temp.fx('s') and l.reason = 'Paid by card, keyed as cash')
      and exists (select 1 from public.invoice_revisions r where r.invoice_id = inv and r.edited_by = pg_temp.fx('s')),
    'S1 the method change is audited (payment_method_corrected) with a revision, by the staff member');
end $$;

-- ═════ S2 A part-paid invoice; discount, FOC and voucher as on an unpaid edit ═════
do $$
declare inv uuid; e text;
begin
  inv := pg_temp.sale('A', 2, 50);
  perform pg_temp.check((select status from public.invoices where id = inv) = 'partially_paid', 'S2 fixture: a part-paid invoice');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 1), jsonb_build_object('notes', 'One pair only'), 'Customer kept one pair');
  perform pg_temp.check(e is null and (select (total_amount, paid_amount, status) = (100.00::numeric, 50.00::numeric, 'partially_paid'::invoice_status)
                                          from public.invoices where id = inv),
    'S2 staff correct a part-paid invoice (S$100.00, S$50.00 paid), got ' || coalesce(e, 'saved'));

  -- A manual discount needs its reason, for staff as at the till.
  inv := pg_temp.sale('A', 2);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('manual_discount', 20), 'Promised a discount');
  perform pg_temp.check(e like 'MANUAL_DISCOUNT_REASON_REQUIRED%', 'S2 a staff manual discount without its reason is refused, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('manual_discount', 20, 'manual_discount_reason', 'Loyal customer'), 'Promised a discount');
  perform pg_temp.check(e is null and (select (manual_discount, total_amount, manual_discount_reason) = (20.00::numeric, 180.00::numeric, 'Loyal customer')
                                          from public.invoices where id = inv),
    'S2 staff give a manual discount with its reason (S$200.00 less S$20.00), as they may on an unpaid invoice, got ' || coalesce(e, 'saved'));

  -- FOC on a line, with its reason.
  inv := pg_temp.sale('A', 2);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0}', pg_temp.lines(inv)->0 || jsonb_build_object('foc_quantity', 1, 'foc_reason', 'Second pair free')),
         '{}'::jsonb, 'Second pair was free');
  perform pg_temp.check(e is null and (select (foc_quantity, foc_amount, line_total) = (1, 100.00::numeric, 100.00::numeric)
                                          from public.invoice_items where invoice_id = inv),
    'S2 staff make one of two pairs FOC with a reason, as they may on an unpaid invoice, got ' || coalesce(e, 'saved'));

  -- A discount voucher.
  inv := pg_temp.sale('A', 2);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('discount_voucher_id', pg_temp.fx('dv')), 'Customer had a voucher');
  perform pg_temp.check(e is null and (select (discount_voucher_id, total_amount) = (pg_temp.fx('dv'), 190.00::numeric)
                                          from public.invoices where id = inv),
    'S2 staff apply a discount voucher (S$10.00 off), as they may on an unpaid invoice, got ' || coalesce(e, 'saved'));
end $$;

-- ═════ S3 What staff are refused, and the invoice is left as it was ═════
do $$
declare inv uuid; p uuid; e text; staff_says text := 'Only an Owner or Manager can correct this invoice. Staff can correct%';
begin
  -- Another store's invoice.
  inv := pg_temp.sale('C', 1);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e = 'No access to this invoice' and pg_temp.untouched(inv), 'S3 staff are refused another store''s invoice, got ' || coalesce(e, 'saved'));

  -- Cancelled (recorded by the Owner).
  inv := pg_temp.sale('A', 1);
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  perform pg_temp.check((select status from public.invoices where id = inv) = 'cancelled', 'S3 fixture: a cancelled invoice');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e like staff_says, 'S3 staff are refused a cancelled invoice, and told why, got ' || coalesce(e, 'saved'));
end $$;

-- The other closed states. Only the status matters to the rule, so it is set directly.
do $$
declare inv uuid; e text; st text; staff_says text := 'Only an Owner or Manager can correct this invoice. Staff can correct%';
begin
  foreach st in array array['refunded','refund_requested','cancellation_requested','completed_foc'] loop
    inv := pg_temp.sale('A', 1);
    update public.invoices set status = st::invoice_status where id = inv;
    perform pg_temp.as_user('s');
    e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
    perform pg_temp.check(e like staff_says and pg_temp.untouched(inv), 'S3 staff are refused a ' || st || ' invoice, got ' || coalesce(e, 'saved'));
  end loop;

  -- An exchange invoice (the system makes those).
  inv := pg_temp.sale('A', 1);
  update public.invoices set is_exchange = true where id = inv;
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e like staff_says and pg_temp.untouched(inv), 'S3 staff are refused an exchange invoice, got ' || coalesce(e, 'saved'));

  -- A refund top-up invoice (the system makes those too).
  inv := pg_temp.sale('A', 1);
  update public.invoices set is_topup = true where id = inv;
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e like staff_says and pg_temp.untouched(inv), 'S3 staff are refused a refund top-up invoice, and told why, got ' || coalesce(e, 'saved'));
  perform pg_temp.check(not public.staff_may_correct_invoice(inv), 'S3 staff_may_correct_invoice says no for a refund top-up invoice');

  -- A voucher-claim document (the system makes those too).
  inv := pg_temp.sale('A', 1);
  update public.invoices set is_voucher_claim = true where id = inv;
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e like staff_says and pg_temp.untouched(inv), 'S3 staff are refused a voucher-claim document, and told why, got ' || coalesce(e, 'saved'));
  perform pg_temp.check(not public.staff_may_correct_invoice(inv), 'S3 staff_may_correct_invoice says no for a voucher-claim document');
end $$;

-- A voucher claim as the system writes it: a S$0 "paid" record of a hand-over,
-- with no lines and no payments. Adding a line would turn it into a sale.
do $$
declare inv uuid; e text; s0 int; staff_says text := 'Only an Owner or Manager can correct this invoice. Staff can correct%';
begin
  perform pg_temp.as_user('o');
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, discount_total, total_amount, paid_amount, is_voucher_claim, notes)
    values ('S377-VC-' || substr(md5(random()::text), 1, 8), pg_temp.fx('A'), pg_temp.fx('c1'), pg_temp.fx('s'), 'paid', 0, 0, 0, 0, true, 'Voucher claim (test)')
    returning id into inv;
  s0 := pg_temp.stock('A', 'prod');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('prod'),'quantity',1)),
         jsonb_build_object('customer_id', pg_temp.fx('c2')), 'Customer also took socks');
  perform pg_temp.check(e like staff_says
      and (select (status, total_amount, customer_id, coalesce(edit_count, 0)) = ('paid'::invoice_status, 0.00::numeric, pg_temp.fx('c1'), 0) from public.invoices where id = inv)
      and not exists (select 1 from public.invoice_items where invoice_id = inv) and pg_temp.stock('A', 'prod') = s0,
    'S3 staff may not add a line to a voucher claim or change its customer: it stays a paid S$0 hand-over, got ' || coalesce(e, 'saved'));
end $$;

do $$
declare inv uuid; p uuid; e text; req uuid; staff_says text := 'Only an Owner or Manager can correct this invoice. Staff can correct%';
begin
  -- Unpaid with payment history: the Owner took the payment out as recorded by mistake.
  inv := pg_temp.sale('A', 1);
  perform public.remove_invoice_payment(pg_temp.pay(inv), 'Recorded on the wrong invoice', gen_random_uuid());
  perform pg_temp.check((select status from public.invoices where id = inv) = 'unpaid', 'S3 fixture: unpaid with payment history');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e like staff_says and coalesce((select edit_count from public.invoices where id = inv), 0) = 0,
    'S3 staff are refused an unpaid invoice with payment history, got ' || coalesce(e, 'saved'));

  -- A refund request waiting; once it is decided, staff may correct again.
  inv := pg_temp.sale('A', 1);
  insert into public.approval_requests(request_type, status, requested_by, related_record_id, reason, payload)
    values ('invoice_refund', 'pending', pg_temp.fx('s'), inv, 'Customer wants a refund', jsonb_build_object('request_id', gen_random_uuid()))
    returning id into req;
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e like staff_says and pg_temp.untouched(inv), 'S3 staff are refused while a refund request is waiting, got ' || coalesce(e, 'saved'));
  update public.approval_requests set status = 'rejected' where id = req;
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'After the request was turned down'));
  perform pg_temp.check(e is null, 'S3 and may correct it once the request is decided, got ' || coalesce(e, 'saved'));
end $$;

do $$
declare inv uuid; p uuid; e text;
begin
  inv := pg_temp.sale('A', 1);
  p := pg_temp.pay(inv);
  perform pg_temp.as_user('s');

  -- A unit price change on a saved line, and a new line at a typed price.
  e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0,unit_price}', '80'), '{}'::jsonb);
  perform pg_temp.check(e = 'Only an Owner or Manager can override invoice prices', 'S3 staff are refused a unit price change, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv) || jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('prod'),'quantity',1,'unit_price',50)), '{}'::jsonb);
  perform pg_temp.check(e = 'Only an Owner or Manager can override invoice prices', 'S3 staff are refused a new line at a typed price, got ' || coalesce(e, 'saved'));

  -- A payment's amount, its date, removing it, splitting it.
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 90, 'date', pg_temp.pay_date(p), 'payment_method_id', pg_temp.fx('cash')))));
  perform pg_temp.check(e = 'Only an Owner or Manager can correct a payment', 'S3 staff are refused a payment amount change, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 100, 'date', pg_temp.pay_date(p) - 3, 'payment_method_id', pg_temp.fx('cash')))));
  perform pg_temp.check(e = 'Only an Owner or Manager can correct a payment', 'S3 staff are refused a payment date change, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 100, 'date', pg_temp.pay_date(p) - 3, 'payment_method_id', pg_temp.fx('card')))));
  perform pg_temp.check(e = 'Only an Owner or Manager can correct a payment', 'S3 staff are refused a date change that also changes the method, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_removals', jsonb_build_array(p)));
  perform pg_temp.check(e = 'Only an Owner or Manager can remove a payment', 'S3 staff are refused removing a payment as recorded by mistake, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'parts', jsonb_build_array(
           jsonb_build_object('amount', 60, 'date', pg_temp.pay_date(p), 'payment_method_id', pg_temp.fx('cash')),
           jsonb_build_object('amount', 40, 'date', pg_temp.pay_date(p), 'payment_method_id', pg_temp.fx('card')))))));
  perform pg_temp.check(e = 'Only an Owner or Manager can split a payment', 'S3 staff are refused splitting a payment, got ' || coalesce(e, 'saved'));

  -- A store move, to another store they work at and to one they do not.
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('store_id', pg_temp.fx('B')));
  perform pg_temp.check(e = 'Only an Owner or Manager can move an invoice to another store', 'S3 staff are refused moving the invoice to another store they work at, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('store_id', pg_temp.fx('C')));
  perform pg_temp.check(e = 'Only an Owner or Manager can move an invoice to another store', 'S3 and to a store they do not work at, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('store_id', pg_temp.fx('A'), 'notes', 'Same store'), 'Same store is not a move');
  perform pg_temp.check(e is null, 'S3 sending the invoice''s own store is not a move, got ' || coalesce(e, 'saved'));

  -- Who raised it; a correction with no reason.
  inv := pg_temp.sale('A', 1);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('created_by', pg_temp.fx('s')));
  perform pg_temp.check(e = 'Only an Owner or Manager can correct invoice attribution', 'S3 staff are refused changing who raised the invoice, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'), '  ');
  perform pg_temp.check(e = 'A correction reason is required', 'S3 a staff correction needs a reason, got ' || coalesce(e, 'saved'));
  perform pg_temp.check(pg_temp.untouched(inv), 'S3 the refused attempts left the invoice, its lines and its payment as they were');
end $$;
select pg_temp.check((select (p.amount, p.payment_method_id, i.store_id, i.total_amount, i.status)
                = (100.00::numeric, pg_temp.fx('cash'), pg_temp.fx('A'), 100.00::numeric, 'paid'::invoice_status)
           from public.invoices i join public.invoice_payments p on p.invoice_id = i.id
          where i.store_id = pg_temp.fx('A') and i.notes = 'Same store'),
  'S3 after the refusals, the one allowed save changed only its notes: payment, price, store and status as they were');

-- ═════ S4 A refusal that needs an Owner's or Manager's review says so ═════
do $$
declare v uuid; inv uuid; inv2 uuid; it uuid; e text; e_owner text;
begin
  perform pg_temp.as_user('o');
  insert into public.vouchers(name,code,voucher_kind,selling_price,qty_type)
    values('S377 Gift Voucher','S377V'||substr(md5(random()::text),1,6),'normal',40,'limited') returning id into v;
  insert into public.voucher_store_stock(voucher_id,store_id,current_qty) values(v,pg_temp.fx('A'),20);
  insert into public.voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,pg_temp.fx('A'),40,true);
  -- An invoice from before stock snapshots.
  inv := public.create_invoice(pg_temp.fx('A'), pg_temp.fx('c1'), null, jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1)));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 40)));
  update public.invoices set stock_snapshot_version = null where id = inv;
  delete from public.invoice_stock_components where invoice_item_id in (select id from public.invoice_items where invoice_id = inv);
  e_owner := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.check(e = 'Historical component snapshots need review before changing stock or selections; metadata can still be corrected. Only an Owner or Manager can do this, so ask one to do it first',
    'S4 staff refused for a historical stock review are told to ask an Owner or Manager, got ' || coalesce(e, 'saved'));
  perform pg_temp.check(e_owner = 'Historical component snapshots need review before changing stock or selections; metadata can still be corrected',
    'S4 the Owner''s message is word for word as before, got ' || coalesce(e_owner, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'Metadata only'));
  perform pg_temp.check(e is null, 'S4 and, as the message says, staff can still correct its notes, got ' || coalesce(e, 'saved'));

  -- A voucher sold before issued units were recorded.
  perform pg_temp.as_user('o');
  inv2 := public.create_invoice(pg_temp.fx('A'), pg_temp.fx('c1'), null, jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1)));
  perform public.pay_invoice(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 40)));
  select id into it from public.invoice_items where invoice_id = inv2;
  delete from public.invoice_benefit_values where invoice_item_id = it;
  delete from public.customer_reward_vouchers where source_type = 'invoice_voucher_sale' and source_id = it;
  e_owner := pg_temp.try(inv2, pg_temp.lines(inv2), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv2, pg_temp.lines(inv2), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.check(e = 'Review the original issued voucher units before changing their customer, store or invoice allocation. Only an Owner or Manager can do this, so ask one to do it first'
      and e_owner = 'Review the original issued voucher units before changing their customer, store or invoice allocation',
    'S4 the voucher-evidence review: staff are told to ask an Owner or Manager; the Owner''s message is as before, got ' || coalesce(e, 'saved') || ' / ' || coalesce(e_owner, 'saved'));
end $$;

-- The other three: issued credit, consumed therapy, a wallet-funded payment.
do $$
declare inv uuid; e text; e_owner text; pkg uuid; w uuid; lot uuid;
  ask text := '. Only an Owner or Manager can do this, so ask one to do it first';
  credit text := 'Issued credit allocation requires reconciliation before changing its line or recipient';
  therapy text := 'Resolve the consumed therapy entitlement before changing its customer, store or invoice lines';
  wallet text := 'Restore the original customer’s wallet-funded payment before changing the invoice customer';
begin
  -- A paid credit package has issued its credit; its line is then changed.
  inv := pg_temp.sale_of(jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp100'),'quantity',1), 100);
  perform pg_temp.check((select credit_issued_at is not null from public.invoice_items where invoice_id = inv), 'S4 fixture: the paid credit package has issued its credit');
  e_owner := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('credit_package_id', pg_temp.fx('cp1000'), 'unit_price', null)), '{}'::jsonb);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('credit_package_id', pg_temp.fx('cp1000'), 'unit_price', null)), '{}'::jsonb);
  perform pg_temp.check(e = credit || ask and e_owner = credit,
    'S4 issued credit: staff are told to ask an Owner or Manager; the Owner''s message is as before, got ' || coalesce(e, 'saved') || ' / ' || coalesce(e_owner, 'saved'));

  -- A therapy entitlement from this sale is in use.
  inv := pg_temp.sale('A', 1);
  insert into public.unlimited_therapy_packages(name, duration_months) values ('S377 Therapy', 1) returning id into pkg;
  insert into public.purchased_therapy_entitlements(entitlement_no, customer_id, store_id, package_id, invoice_id, package_name,
      duration_months, price_snapshot, purchase_date, activation_deadline, activation_date, expiry_date, status)
    values ('S377-PTE-' || substr(md5(random()::text), 1, 8), pg_temp.fx('c1'), pg_temp.fx('A'), pkg, inv, 'S377 Therapy',
      1, 100, current_date, current_date + 30, current_date, current_date + 30, 'active');
  e_owner := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.check(e = therapy || ask and e_owner = therapy,
    'S4 consumed therapy: staff are told to ask an Owner or Manager; the Owner''s message is as before, got ' || coalesce(e, 'saved') || ' / ' || coalesce(e_owner, 'saved'));

  -- Part of this sale was paid from the customer's wallet.
  inv := pg_temp.sale('A', 1);
  select id into w from public.customer_credit_wallets where customer_id = pg_temp.fx('c1');
  if w is null then insert into public.customer_credit_wallets(customer_id) values (pg_temp.fx('c1')) returning id into w; end if;
  insert into public.customer_credit_lots(wallet_id, customer_id, category, original_amount, remaining_amount, source_type)
    values (w, pg_temp.fx('c1'), 'paid', 10, 0, 'S377 fixture') returning id into lot;
  insert into public.invoice_line_credit_allocations(invoice_id, lot_id, customer_id, category, amount)
    values (inv, lot, pg_temp.fx('c1'), 'paid', 10);
  e_owner := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')));
  perform pg_temp.check(e = wallet || ask and e_owner = wallet,
    'S4 wallet-funded payment: staff are told to ask an Owner or Manager; the Owner''s message is as before, got ' || coalesce(e, 'saved') || ' / ' || coalesce(e_owner, 'saved'));
end $$;

-- Every refusal that needs an Owner or Manager carries the hint (all five).
select pg_temp.check((select bool_and(position(m || '%'', v377_ask' in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) > 0)
                        from unnest(array[
                          'Review the original issued voucher units before changing their customer, store or invoice allocation',
                          'Historical component snapshots need review before changing stock or selections; metadata can still be corrected',
                          'Resolve the consumed therapy entitlement before changing its customer, store or invoice lines',
                          'Issued credit allocation requires reconciliation before changing its line or recipient',
                          'Restore the original customer’s wallet-funded payment before changing the invoice customer']) m),
  'S4 all five refusals an Owner or Manager must resolve carry the "ask an Owner or Manager" hint');

-- On an unpaid invoice too: staff get the hint; every other role the old words.
do $$
declare inv uuid; e text; r text; other text := '';
  snap text := 'Historical component snapshots need review before changing stock or selections; metadata can still be corrected';
begin
  inv := pg_temp.sale_of(jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('v40'),'quantity',1), 0);
  update public.invoices set stock_snapshot_version = null where id = inv;
  delete from public.invoice_stock_components where invoice_item_id in (select id from public.invoice_items where invoice_id = inv);
  perform pg_temp.check((select status from public.invoices where id = inv) = 'unpaid', 'S4 fixture: an unpaid voucher sale from before stock snapshots');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')), null);
  perform pg_temp.check(e = snap || '. Only an Owner or Manager can do this, so ask one to do it first',
    'S4 staff editing an unpaid invoice are told to ask an Owner or Manager too, got ' || coalesce(e, 'saved'));
  foreach r in array array['o','m','a','im'] loop
    perform pg_temp.as_user(r);
    e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('customer_id', pg_temp.fx('c2')), null);
    if e is distinct from snap then other := other || r || ': ' || coalesce(e, 'saved') || '; '; end if;
  end loop;
  perform pg_temp.check(other = '', 'S4 the Owner, Manager, Admin and Inventory Manager get the unpaid refusal word for word as before ' || other);
end $$;

-- ═════ S5 The payment lock ═════
do $$
declare inv uuid; inv_c uuid; p uuid; pc uuid; e text;
begin
  inv := pg_temp.sale('A', 1); p := pg_temp.pay(inv);
  inv_c := pg_temp.sale('C', 1); pc := pg_temp.pay(inv_c);
  perform pg_temp.as_user('s');
  begin
    update public.invoice_payments set amount = 1 where id = p; e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'A payment on a settled invoice cannot be edited' and (select amount from public.invoice_payments where id = p) = 100,
    'S5 a settled payment''s amount stays locked for staff, got ' || coalesce(e, 'changed'));
  begin
    update public.invoice_payments set payment_method_id = pg_temp.fx('card') where id = pc; e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'A payment on a settled invoice cannot be edited', 'S5 staff cannot change the method of a payment on an invoice they may not correct, got ' || coalesce(e, 'changed'));
  begin
    delete from public.invoice_payments where id = p; e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'A payment on a settled invoice cannot be deleted', 'S5 a settled payment still cannot be deleted, got ' || coalesce(e, 'deleted'));
  perform pg_temp.as_user('o');
  begin
    update public.invoice_payments set amount = 1 where id = p; e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'A payment on a settled invoice cannot be edited', 'S5 and for an Owner, got ' || coalesce(e, 'changed'));
end $$;
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.invoice_payments'::regclass)
    and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoice_payments' and cmd in ('UPDATE','DELETE','ALL')),
  'S5 no policy lets a signed-in user change a payment row directly; staff reach a method only through a correction');

-- ═════ S6 Owners and Managers are unchanged ═════
do $$
declare inv uuid; p uuid; e text; n int;
begin
  -- A price override (Owner).
  inv := pg_temp.sale('A', 1);
  e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0,unit_price}', '80'), '{}'::jsonb, 'Agreed price');
  perform pg_temp.check(e is null and (select unit_price from public.invoice_items where invoice_id = inv) = 80,
    'S6 an Owner still overrides a price, got ' || coalesce(e, 'saved'));

  -- A payment's amount and its date (Manager).
  inv := pg_temp.sale('A', 1); p := pg_temp.pay(inv);
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 90, 'date', pg_temp.pay_date(p), 'payment_method_id', pg_temp.fx('cash')))), 'Took S$90');
  perform pg_temp.check(e is null and (select (paid_amount, status) = (90.00::numeric, 'partially_paid'::invoice_status) from public.invoices where id = inv),
    'S6 a Manager still corrects a payment''s amount, got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale('A', 1); p := pg_temp.pay(inv);
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 100, 'date', pg_temp.pay_date(p) - 3, 'payment_method_id', pg_temp.fx('cash')))), 'Paid three days earlier');
  perform pg_temp.check(e is null and exists (select 1 from public.invoice_payments where invoice_id = inv and entry_kind = 'correction_replacement'
                                                 and (effective_at at time zone 'Asia/Singapore')::date = pg_temp.pay_date(p) - 3),
    'S6 a Manager still corrects a payment''s date, got ' || coalesce(e, 'saved'));

  -- Removing a payment (Owner) and splitting one (Manager).
  inv := pg_temp.sale('A', 1); p := pg_temp.pay(inv);
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_removals', jsonb_build_array(p)), 'Recorded by mistake');
  perform pg_temp.check(e is null and (select status from public.invoices where id = inv) = 'unpaid', 'S6 an Owner still removes a payment, got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale('A', 1); p := pg_temp.pay(inv);
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'parts', jsonb_build_array(
           jsonb_build_object('amount', 60, 'date', pg_temp.pay_date(p), 'payment_method_id', pg_temp.fx('cash')),
           jsonb_build_object('amount', 40, 'date', pg_temp.pay_date(p), 'payment_method_id', pg_temp.fx('card')))))), 'Part cash, part card');
  select count(*) into n from public.invoice_payments where invoice_id = inv and entry_kind = 'correction_replacement';
  perform pg_temp.check(e is null and n = 2, 'S6 a Manager still splits a payment, got ' || coalesce(e, 'saved'));

  -- A store move, who raised it, a method change (Owner and Manager).
  inv := pg_temp.sale('A', 1);
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('store_id', pg_temp.fx('B')), 'Sold at B');
  perform pg_temp.check(e is null and (select store_id from public.invoices where id = inv) = pg_temp.fx('B'), 'S6 an Owner still moves an invoice to another store, got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale('A', 1);
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('created_by', pg_temp.fx('s')), 'Raised by the staff member');
  perform pg_temp.check(e is null and (select created_by from public.invoices where id = inv) = pg_temp.fx('s'), 'S6 a Manager still changes who raised it (the server allows it), got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale('A', 1); p := pg_temp.pay(inv);
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.lines(inv),
         jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p, 'payment_method_id', pg_temp.fx('card')))), 'Card');
  perform pg_temp.check(e is null and (select payment_method_id from public.invoice_payments where id = p) = pg_temp.fx('card'),
    'S6 a Manager still changes a payment''s method, got ' || coalesce(e, 'saved'));

  -- A cancelled invoice, and one with a request waiting.
  inv := pg_temp.sale('A', 1);
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'Cancelled at the counter'), 'Note');
  perform pg_temp.check(e is null and (select (status, notes) = ('cancelled'::invoice_status, 'Cancelled at the counter') from public.invoices where id = inv),
    'S6 a Manager still corrects a cancelled invoice, which stays cancelled, got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale('A', 1);
  insert into public.approval_requests(request_type, status, requested_by, related_record_id, reason, payload)
    values ('invoice_refund', 'pending', pg_temp.fx('s'), inv, 'Customer wants a refund', jsonb_build_object('request_id', gen_random_uuid()));
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'While the request waits'), 'Note');
  perform pg_temp.check(e is null, 'S6 an Owner still corrects an invoice with a request waiting, got ' || coalesce(e, 'saved'));
end $$;

-- ═════ S7 Admin, Inventory Manager, a deactivated staff member; the unpaid path ═════
do $$
declare inv uuid; e text;
begin
  inv := pg_temp.sale('A', 1);
  perform pg_temp.as_user('a');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e = 'Only an Owner or Manager can correct this invoice' and pg_temp.untouched(inv),
    'S7 an Admin is still refused a paid invoice, with the old message, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('im');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e = 'Only an Owner or Manager can correct this invoice' and pg_temp.untouched(inv),
    'S7 an Inventory Manager at the store is still refused, with the old message, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('sx');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e = 'No access to this invoice' and pg_temp.untouched(inv), 'S7 a deactivated staff member has no access, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('sd');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  -- Since 406 a deleted profile has no staff role at all (current_user_role()
  -- is null), so it gets the plain refusal rather than the staff one.
  perform pg_temp.check(e like 'Only an Owner or Manager can correct this invoice%' and pg_temp.untouched(inv),
    'S7 a deleted staff profile that still has store access may not correct a paid invoice, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s2');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'x'));
  perform pg_temp.check(e = 'No access to this invoice' and pg_temp.untouched(inv), 'S7 a staff member of another store has no access, got ' || coalesce(e, 'saved'));

  -- An unpaid invoice: staff edit it as before, with no reason needed.
  inv := pg_temp.sale('A', 1, 0);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, null);
  perform pg_temp.check(e is null and (select (status, total_amount) = ('unpaid'::invoice_status, 200.00::numeric) from public.invoices where id = inv),
    'S7 staff still edit an unpaid invoice as before (no reason needed), got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('store_id', pg_temp.fx('B')), null);
  perform pg_temp.check(e is null and (select store_id from public.invoices where id = inv) = pg_temp.fx('B'),
    'S7 and the unpaid path keeps its old store rule (a store they work at), got ' || coalesce(e, 'saved'));
end $$;

-- ═════ S8 The rule itself ═════
do $$
declare inv uuid; inv_c uuid; ok_staff boolean; ok_other boolean; ok_owner boolean; ok_mgr boolean; ok_admin boolean; ok_im boolean; ok_gone boolean; ok_deleted boolean;
begin
  inv := pg_temp.sale('A', 1);
  inv_c := pg_temp.sale('C', 1);
  perform pg_temp.as_user('s');  ok_staff := public.staff_may_correct_invoice(inv); ok_other := public.staff_may_correct_invoice(inv_c);
  perform pg_temp.as_user('o');  ok_owner := public.staff_may_correct_invoice(inv);
  perform pg_temp.as_user('m');  ok_mgr := public.staff_may_correct_invoice(inv);
  perform pg_temp.as_user('a');  ok_admin := public.staff_may_correct_invoice(inv);
  perform pg_temp.as_user('im'); ok_im := public.staff_may_correct_invoice(inv);
  perform pg_temp.as_user('sx'); ok_gone := public.staff_may_correct_invoice(inv);
  perform pg_temp.as_user('sd'); ok_deleted := public.staff_may_correct_invoice(inv);
  perform pg_temp.check(ok_staff and not ok_other and not ok_owner and not ok_mgr and not ok_admin and not ok_im and not ok_gone and not ok_deleted,
    format('S8 staff_may_correct_invoice: yes for staff at the store; no at another store, for Owner, Manager, Admin, Inventory Manager, or a deactivated or deleted staff member (got %s %s %s %s %s %s %s %s)',
      ok_staff, ok_other, ok_owner, ok_mgr, ok_admin, ok_im, ok_gone, ok_deleted));
  perform pg_temp.as_user('s');
  perform pg_temp.check(not public.staff_may_correct_invoice(gen_random_uuid()), 'S8 and no for an invoice that does not exist');
  update public.invoices set deleted_at = now() where id = inv;
  perform pg_temp.check(not public.staff_may_correct_invoice(inv), 'S8 and no for a deleted invoice');
end $$;
select pg_temp.check(has_function_privilege('authenticated', 'public.staff_may_correct_invoice(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.staff_may_correct_invoice(uuid)', 'execute')
    and (select prosecdef from pg_proc where oid = 'public.staff_may_correct_invoice(uuid)'::regprocedure)
    and not has_function_privilege('authenticated', 'public.correct_invoice_payment_methods(uuid,jsonb,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', 'execute'),
  'S8 signed-in users may ask the rule, signed-out visitors may not; the two relaxed internals are still reached only through correct_invoice');

-- ═════ S9 A saved price stays with what was sold (371's rule, carried by 377) ═════
do $$
declare inv uuid; e text; s0 int; m0 int; override text := 'Only an Owner or Manager can override invoice prices';
  k text; f text; a text; b text; paid numeric; dear numeric;
begin
  -- A product: the S$100.00 socks swapped for the S$3,000.00 mattress.
  inv := pg_temp.sale('A', 1);
  s0 := pg_temp.stock('A', 'prod'); m0 := pg_temp.stock('A', 'mat');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('product_id', pg_temp.fx('mat'))), '{}'::jsonb, 'Took the mattress instead');
  perform pg_temp.check(e = override and pg_temp.untouched(inv)
      and (select product_id from public.invoice_items where invoice_id = inv) = pg_temp.fx('prod')
      and pg_temp.stock('A', 'prod') = s0 and pg_temp.stock('A', 'mat') = m0,
    'S9 staff are refused swapping a paid line to another product at its saved price (the mattress for S$100.00); line and stock untouched, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('product_id', pg_temp.fx('mat'), 'unit_price', null)), '{}'::jsonb, 'Took the mattress instead');
  perform pg_temp.check(e is null
      and (select (product_id, unit_price, line_total) = (pg_temp.fx('mat'), 3000.00::numeric, 3000.00::numeric) from public.invoice_items where invoice_id = inv)
      and (select (total_amount, paid_amount, status) = (3000.00::numeric, 100.00::numeric, 'partially_paid'::invoice_status) from public.invoices where id = inv)
      and pg_temp.stock('A', 'prod') = s0 + 1 and pg_temp.stock('A', 'mat') = m0 - 1,
    'S9 sent without its saved price, the swap is charged at the catalogue price (S$3,000.00, part-paid) and the stock follows, got ' || coalesce(e, 'saved'));

  -- A gift voucher: S$40.00 for the S$400.00 one.
  inv := pg_temp.sale_of(jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('v40'),'quantity',1), 40);
  s0 := pg_temp.vstock('v40'); m0 := pg_temp.vstock('v400');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('voucher_id', pg_temp.fx('v400'))), '{}'::jsonb, 'Wrong voucher keyed');
  perform pg_temp.check(e = override and coalesce((select edit_count from public.invoices where id = inv), 0) = 0
      and (select (voucher_id, unit_price) = (pg_temp.fx('v40'), 40.00::numeric) from public.invoice_items where invoice_id = inv)
      and pg_temp.vstock('v40') = s0 and pg_temp.vstock('v400') = m0,
    'S9 staff are refused swapping a paid voucher line to another voucher at its saved price; line and voucher stock untouched, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('voucher_id', pg_temp.fx('v400'), 'unit_price', null)), '{}'::jsonb, 'Wrong voucher keyed');
  perform pg_temp.check(e is null
      and (select (voucher_id, unit_price) = (pg_temp.fx('v400'), 400.00::numeric) from public.invoice_items where invoice_id = inv)
      and (select total_amount from public.invoices where id = inv) = 400,
    'S9 sent without its saved price, the voucher swap is charged at the catalogue price (S$400.00), got ' || coalesce(e, 'saved'));

  -- A credit package, part-paid so its credit is not issued yet: S$100.00 for the S$1,000.00 one.
  inv := pg_temp.sale_of(jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp100'),'quantity',1), 50);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('credit_package_id', pg_temp.fx('cp1000'))), '{}'::jsonb, 'Wrong package keyed');
  perform pg_temp.check(e = override and coalesce((select edit_count from public.invoices where id = inv), 0) = 0
      and (select (credit_package_id, unit_price) = (pg_temp.fx('cp100'), 100.00::numeric) from public.invoice_items where invoice_id = inv),
    'S9 staff are refused swapping a credit package to another at its saved price; the line is untouched, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('credit_package_id', pg_temp.fx('cp1000'), 'unit_price', null)), '{}'::jsonb, 'Wrong package keyed');
  perform pg_temp.check(e is null
      and (select (credit_package_id, unit_price) = (pg_temp.fx('cp1000'), 1000.00::numeric) from public.invoice_items where invoice_id = inv)
      and (select (total_amount, status) = (1000.00::numeric, 'partially_paid'::invoice_status) from public.invoices where id = inv),
    'S9 sent without its saved price, the package swap is charged at the catalogue price (S$1,000.00), got ' || coalesce(e, 'saved'));

  -- A special product: the S$500.00 chair for the S$5,000.00 bed.
  inv := pg_temp.sale_of(jsonb_build_object('kind','special_product','special_product_id',pg_temp.fx('chair'),'quantity',1), 500);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('special_product_id', pg_temp.fx('bed'))), '{}'::jsonb, 'Took the bed');
  perform pg_temp.check(e = override and (select special_product_id from public.invoice_items where invoice_id = inv) = pg_temp.fx('chair'),
    'S9 staff are refused swapping a special product to another at its saved price, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('special_product_id', pg_temp.fx('bed'), 'unit_price', null)), '{}'::jsonb, 'Took the bed');
  perform pg_temp.check(e is null and (select total_amount from public.invoices where id = inv) = 5000,
    'S9 sent without its saved price, the special product swap is charged at the catalogue price (S$5,000.00), got ' || coalesce(e, 'saved'));

  -- A rental of the chair for 2 days at S$20.00 a day: kept longer, or by the week, at the saved S$40.00.
  inv := pg_temp.sale_of(jsonb_build_object('kind','rental','special_product_id',pg_temp.fx('chair'),'quantity',1,
           'rental_rate_type','day','rental_periods',2,'rental_start_date',current_date), 40);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('rental_periods', 5)), '{}'::jsonb, 'Kept it longer');
  perform pg_temp.check(e = override and (select (rental_periods, unit_price) = (2, 40.00::numeric) from public.invoice_items where invoice_id = inv),
    'S9 staff are refused keeping a rental 5 days at the 2-day price, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('rental_rate_type', 'week')), '{}'::jsonb, 'Weekly rate');
  perform pg_temp.check(e = override, 'S9 and changing it to a weekly rate at the daily price, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('rental_periods', 5, 'unit_price', null)), '{}'::jsonb, 'Kept it longer');
  perform pg_temp.check(e is null and (select (rental_periods, unit_price) = (5, 100.00::numeric) from public.invoice_items where invoice_id = inv),
    'S9 sent without its saved price, 5 days are charged at the catalogue rate (S$100.00), got ' || coalesce(e, 'saved'));

  -- Every other kind a line can be: a promotion, a therapy session, a therapy
  -- package (S$150.00 for S$1,500.00 each time, ten times the price) and a
  -- premium bundle (part-paid, so its credit is not issued yet).
  for k, f, a, b, paid, dear in select * from (values
      ('promotion', 'promotion_id', 'pr50', 'pr500', 50, 500),
      ('therapy', 'therapy_service_id', 'ts30', 'ts300', 30, 300),
      ('therapy', 'therapy_package_id', 'tp150', 'tp1500', 150, 1500),
      ('premium_bundle', 'premium_bundle_id', 'b200', 'b2000', 100, 2000)) x
  loop
    inv := pg_temp.sale_of(jsonb_build_object('kind', k, f, pg_temp.fx(a), 'quantity', 1), paid);
    perform pg_temp.as_user('s');
    e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object(f, pg_temp.fx(b))), '{}'::jsonb, 'Wrong item keyed');
    perform pg_temp.check(e = override and coalesce((select edit_count from public.invoices where id = inv), 0) = 0
        and (select to_jsonb(it)->>f from public.invoice_items it where it.invoice_id = inv) = pg_temp.fx(a)::text,
      format('S9 staff are refused swapping a %s line (%s) to another at its saved price; the line is untouched, got %s', k, f, coalesce(e, 'saved')));
    e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object(f, pg_temp.fx(b), 'unit_price', null)), '{}'::jsonb, 'Wrong item keyed');
    perform pg_temp.check(e is null and (select total_amount from public.invoices where id = inv) = dear
        and (select (to_jsonb(it)->>f, unit_price) = (pg_temp.fx(b)::text, dear) from public.invoice_items it where it.invoice_id = inv),
      format('S9 sent without its saved price, the %s swap (%s) is charged at the catalogue price (S$%s), got %s', k, f, dear, coalesce(e, 'saved')));
  end loop;

  -- An Owner's swap is as before: at the saved price it is the Owner's override; without it, the catalogue price.
  inv := pg_temp.sale('A', 1);
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('product_id', pg_temp.fx('mat'))), '{}'::jsonb, 'The mattress at the socks price, agreed');
  perform pg_temp.check(e is null
      and (select (product_id, unit_price) = (pg_temp.fx('mat'), 100.00::numeric) from public.invoice_items where invoice_id = inv)
      and (select (total_amount, status) = (100.00::numeric, 'paid'::invoice_status) from public.invoices where id = inv),
    'S9 an Owner still swaps a line at its saved price (an Owner''s override), got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale_of(jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp100'),'quantity',1), 50);
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('credit_package_id', pg_temp.fx('cp1000'))), '{}'::jsonb, 'The bigger package at the same price, agreed');
  perform pg_temp.check(e is null and (select (credit_package_id, unit_price) = (pg_temp.fx('cp1000'), 100.00::numeric) from public.invoice_items where invoice_id = inv),
    'S9 and so does a Manager, got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale('A', 1);
  e := pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('product_id', pg_temp.fx('mat'), 'unit_price', null)), '{}'::jsonb, 'Took the mattress');
  perform pg_temp.check(e is null and (select unit_price from public.invoice_items where invoice_id = inv) = 3000,
    'S9 an Owner''s swap without the saved price is at the catalogue price, got ' || coalesce(e, 'saved'));
end $$;

-- ═════ S10 Adding units to a saved line at its saved price ═════
do $$
declare inv uuid; e text; special text := 'Only an Owner or Manager can add units at a special price.';
  below text := 'Add the extra units as a new line at today''s price, or ask an Owner or Manager.';
begin
  -- The Owner sells two pairs at a special S$60.00 each (the catalogue says S$100.00).
  inv := pg_temp.sale('A', 2);
  e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0,unit_price}', '60'), '{}'::jsonb, 'Special price for a regular');
  perform pg_temp.check(e is null and (select (unit_price, line_total) = (60.00::numeric, 120.00::numeric) from public.invoice_items where invoice_id = inv),
    'S10 fixture: the Owner set a special price of S$60.00 on two pairs, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 3), '{}'::jsonb, 'Customer took a third pair');
  perform pg_temp.check(e = special
      and (select (quantity, unit_price) = (2, 60.00::numeric) from public.invoice_items where invoice_id = inv)
      and (select edit_count from public.invoices where id = inv) = 1,
    'S10 staff may not add a pair at the Owner''s special price; the invoice is as the Owner left it, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 1), '{}'::jsonb, 'One pair after all');
  perform pg_temp.check(e is null and (select (quantity, unit_price, line_total) = (1, 60.00::numeric, 60.00::numeric) from public.invoice_items where invoice_id = inv),
    'S10 staff may lower the quantity, at the special price, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'Two pairs again');
  perform pg_temp.check(e = special, 'S10 the price is still special after the staff member''s own change: adding the pair back is refused, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 3), '{}'::jsonb, 'Three pairs at the special price');
  perform pg_temp.check(e is null and (select (quantity, unit_price, line_total) = (3, 60.00::numeric, 180.00::numeric) from public.invoice_items where invoice_id = inv),
    'S10 a Manager still adds units at the special price, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 4), '{}'::jsonb, 'Four pairs at the special price');
  perform pg_temp.check(e is null and (select (quantity, line_total) = (4, 240.00::numeric) from public.invoice_items where invoice_id = inv),
    'S10 and so does an Owner, got ' || coalesce(e, 'saved'));

  -- Staff may remove a line at a special price.
  perform pg_temp.as_user('o');
  inv := public.create_invoice(pg_temp.fx('A'), pg_temp.fx('c1'), null, jsonb_build_array(
    jsonb_build_object('kind','product','product_id',pg_temp.fx('prod'),'quantity',2),
    jsonb_build_object('kind','product','product_id',pg_temp.fx('mat'),'quantity',1)));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 3200)));
  e := pg_temp.try(inv, (select jsonb_agg(case when x->>'product_id' = pg_temp.fx('prod')::text then x || '{"unit_price": 60}'::jsonb else x end)
                           from jsonb_array_elements(pg_temp.lines(inv)) x), '{}'::jsonb, 'Special price on the socks');
  perform pg_temp.as_user('s');
  e := coalesce(e, pg_temp.try(inv, (select jsonb_agg(x) from jsonb_array_elements(pg_temp.lines(inv)) x where x->>'product_id' = pg_temp.fx('mat')::text),
                               '{}'::jsonb, 'The socks were not taken'));
  perform pg_temp.check(e is null and not exists (select 1 from public.invoice_items where invoice_id = inv and product_id = pg_temp.fx('prod'))
      and (select total_amount from public.invoices where id = inv) = 3000,
    'S10 staff may remove a line at a special price, got ' || coalesce(e, 'saved'));

  -- Pairs sold at S$100.00 at store B; the catalogue price there then goes up
  -- to S$120.00. The old lower price is below today's: staff may not add a
  -- pair at it, and are told to add it as a new line at today's price, which
  -- they may; lowering the quantity is still theirs. An Owner and a Manager
  -- add a pair at the old price as before.
  declare inv_o uuid; inv_m uuid; inv_low uuid; inv_up uuid;
  begin
    inv := pg_temp.sale('B', 2); inv_low := pg_temp.sale('B', 2);
    inv_o := pg_temp.sale('B', 1); inv_m := pg_temp.sale('B', 1); inv_up := pg_temp.sale('B', 1);
    perform public.set_product_prices(pg_temp.fx('B'), pg_temp.fx('prod'), 120, 120, 'available');
    perform pg_temp.as_user('s');
    e := pg_temp.try(inv, pg_temp.with_qty(inv, 3), '{}'::jsonb, 'A third pair');
    perform pg_temp.check(e = below and coalesce((select edit_count from public.invoices where id = inv), 0) = 0
        and (select (quantity, unit_price) = (2, 100.00::numeric) from public.invoice_items where invoice_id = inv),
      'S10 staff may not add a pair at a price below today''s (sold at S$100.00, now S$120.00): told to add it as a new line; the invoice is untouched, got ' || coalesce(e, 'saved'));
    e := pg_temp.try(inv, pg_temp.lines(inv) || jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('prod'),'quantity',1)),
           '{}'::jsonb, 'A third pair');
    perform pg_temp.check(e is null
        and (select string_agg(quantity || 'x' || unit_price, ' ' order by unit_price) from public.invoice_items where invoice_id = inv) = '2x100.00 1x120.00'
        and (select (total_amount, status) = (320.00::numeric, 'partially_paid'::invoice_status) from public.invoices where id = inv),
      'S10 as the message says, staff add the pair as a new line at today''s price (2 x S$100.00 + 1 x S$120.00), got ' || coalesce(e, 'saved'));
    e := pg_temp.try(inv_low, pg_temp.with_qty(inv_low, 1), '{}'::jsonb, 'One pair after all');
    perform pg_temp.check(e is null and (select (quantity, unit_price, line_total) = (1, 100.00::numeric, 100.00::numeric) from public.invoice_items where invoice_id = inv_low),
      'S10 staff may still lower the quantity of a line at an old lower price, got ' || coalesce(e, 'saved'));
    perform pg_temp.as_user('o');
    e := pg_temp.try(inv_o, pg_temp.with_qty(inv_o, 2), '{}'::jsonb, 'A second pair at the old price');
    perform pg_temp.check(e is null and (select (quantity, unit_price) = (2, 100.00::numeric) from public.invoice_items where invoice_id = inv_o),
      'S10 an Owner still adds a pair at the old lower price, got ' || coalesce(e, 'saved'));
    perform pg_temp.as_user('m');
    e := pg_temp.try(inv_m, pg_temp.with_qty(inv_m, 2), '{}'::jsonb, 'A second pair at the old price');
    perform pg_temp.check(e is null and (select (quantity, unit_price) = (2, 100.00::numeric) from public.invoice_items where invoice_id = inv_m),
      'S10 and so does a Manager, got ' || coalesce(e, 'saved'));
    -- The price then falls to S$80.00: a pair sold at S$100.00 is above
    -- today's price, and staff add a pair at it.
    perform pg_temp.as_user('o');
    perform public.set_product_prices(pg_temp.fx('B'), pg_temp.fx('prod'), 80, 80, 'available');
    perform pg_temp.as_user('s');
    e := pg_temp.try(inv_up, pg_temp.with_qty(inv_up, 2), '{}'::jsonb, 'A second pair');
    perform pg_temp.check(e is null and (select (quantity, unit_price, line_total) = (2, 100.00::numeric, 200.00::numeric) from public.invoice_items where invoice_id = inv_up),
      'S10 a line sold at its catalogue price, which has gone down since, is not a special price: staff add a pair at the saved S$100.00, got ' || coalesce(e, 'saved'));
    perform pg_temp.as_user('o');
    perform public.set_product_prices(pg_temp.fx('B'), pg_temp.fx('prod'), 100, 100, 'available');
  end;

  -- A line sold at its non-member price (before membership was removed) is
  -- not a special price either.
  inv := pg_temp.sale('A', 1);
  update public.invoice_items set member_price_snapshot = 90 where invoice_id = inv;
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'A second pair');
  perform pg_temp.check(e is null and (select quantity from public.invoice_items where invoice_id = inv) = 2,
    'S10 a line sold at its recorded non-member price is not a special price, got ' || coalesce(e, 'saved'));

  -- The printed "Manual Override" mark counts, even at the catalogue price.
  inv := pg_temp.sale('A', 1);
  update public.invoice_items set price_overridden = true, override_reason = 'Old price-mode override' where invoice_id = inv;
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'A second pair');
  perform pg_temp.check(e = special, 'S10 a line printed as a Manual Override counts as a special price, got ' || coalesce(e, 'saved'));

  -- No recorded catalogue price (a special product): today's catalogue price
  -- decides. Below it (the Owner's S$400.00 for the S$500.00 chair), staff are
  -- told to add it as a new line; above it (S$600.00), they add one.
  inv := pg_temp.sale_of(jsonb_build_object('kind','special_product','special_product_id',pg_temp.fx('chair'),'quantity',1), 500);
  e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0,unit_price}', '400'), '{}'::jsonb, 'Special price on the chair');
  perform pg_temp.as_user('s');
  e := coalesce(e, pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'A second chair'));
  perform pg_temp.check(e = below and (select (quantity, unit_price) = (1, 400.00::numeric) from public.invoice_items where invoice_id = inv),
    'S10 staff may not add a special product at a price the Owner set below its catalogue price (none recorded on the line): told to add it as a new line, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'A second chair at the same price');
  perform pg_temp.check(e is null and (select (quantity, unit_price) = (2, 400.00::numeric) from public.invoice_items where invoice_id = inv),
    'S10 a Manager still adds one at that price, got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale_of(jsonb_build_object('kind','special_product','special_product_id',pg_temp.fx('chair'),'quantity',1), 500);
  e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0,unit_price}', '600'), '{}'::jsonb, 'Chair with delivery');
  perform pg_temp.as_user('s');
  e := coalesce(e, pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'A second chair'));
  perform pg_temp.check(e is null and (select (quantity, unit_price, line_total) = (2, 600.00::numeric, 1200.00::numeric) from public.invoice_items where invoice_id = inv),
    'S10 staff add a special product at a saved price above its catalogue price (the Owner''s S$600.00 for the S$500.00 chair), got ' || coalesce(e, 'saved'));
  inv := pg_temp.sale_of(jsonb_build_object('kind','special_product','special_product_id',pg_temp.fx('chair'),'quantity',1), 500);
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'A second chair');
  perform pg_temp.check(e is null and (select total_amount from public.invoices where id = inv) = 1000,
    'S10 at its catalogue price staff add one, got ' || coalesce(e, 'saved'));
end $$;

-- Every other kind staff can add units to, sold at its catalogue price, which
-- then goes up: staff are told to add a new line at today's price; with the
-- price back where it was (the saved price equals today's), they add one. A
-- Manager adds one at the old lower price.
do $$
declare inv uuid; inv_m uuid; e text; k text; line jsonb; paid numeric;
  below text := 'Add the extra units as a new line at today''s price, or ask an Owner or Manager.';
begin
  foreach k in array array['voucher', 'promotion', 'therapy session', 'rental'] loop
    line := case k
      when 'voucher' then jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('v40'),'quantity',1)
      when 'promotion' then jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('pr50'),'quantity',1)
      when 'therapy session' then jsonb_build_object('kind','therapy','therapy_service_id',pg_temp.fx('ts30'),'quantity',1)
      else jsonb_build_object('kind','rental','special_product_id',pg_temp.fx('chair'),'quantity',1,
             'rental_rate_type','day','rental_periods',2,'rental_start_date',current_date) end;
    paid := case k when 'voucher' then 40 when 'promotion' then 50 when 'therapy session' then 30 else 40 end;
    inv := pg_temp.sale_of(line, paid); inv_m := pg_temp.sale_of(line, paid);
    -- Up by a quarter.
    if k = 'voucher' then update public.voucher_store_prices set selling_price = 50 where voucher_id = pg_temp.fx('v40') and store_id = pg_temp.fx('A');
    elsif k = 'promotion' then update public.promotion_store_prices set selling_price = 62.5 where promotion_id = pg_temp.fx('pr50') and store_id = pg_temp.fx('A');
    elsif k = 'therapy session' then update public.therapy_services set standard_price = 37.5 where id = pg_temp.fx('ts30');
    else update public.special_products set rate_day = 25 where id = pg_temp.fx('chair'); end if;
    perform pg_temp.as_user('s');
    e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'One more');
    perform pg_temp.check(e = below and coalesce((select edit_count from public.invoices where id = inv), 0) = 0
        and (select (quantity, unit_price) = (1, paid) from public.invoice_items where invoice_id = inv),
      format('S10 staff may not add a %s at its old lower price (S$%s, dearer today): told to add a new line, got %s', k, paid, coalesce(e, 'saved')));
    perform pg_temp.as_user('m');
    e := pg_temp.try(inv_m, pg_temp.with_qty(inv_m, 2), '{}'::jsonb, 'One more at the old price');
    perform pg_temp.check(e is null and (select (quantity, unit_price) = (2, paid) from public.invoice_items where invoice_id = inv_m),
      format('S10 a Manager still adds a %s at its old lower price, got %s', k, coalesce(e, 'saved')));
    -- Back to the price it was sold at.
    if k = 'voucher' then update public.voucher_store_prices set selling_price = 40 where voucher_id = pg_temp.fx('v40') and store_id = pg_temp.fx('A');
    elsif k = 'promotion' then update public.promotion_store_prices set selling_price = 50 where promotion_id = pg_temp.fx('pr50') and store_id = pg_temp.fx('A');
    elsif k = 'therapy session' then update public.therapy_services set standard_price = 30 where id = pg_temp.fx('ts30');
    else update public.special_products set rate_day = 20 where id = pg_temp.fx('chair'); end if;
    perform pg_temp.as_user('s');
    e := pg_temp.try(inv, pg_temp.with_qty(inv, 2), '{}'::jsonb, 'One more');
    perform pg_temp.check(e is null and (select (quantity, unit_price, line_total) = (2, paid, 2 * paid) from public.invoice_items where invoice_id = inv),
      format('S10 at today''s price again staff add a %s at the saved S$%s, got %s', k, paid, coalesce(e, 'saved')));
  end loop;
end $$;

-- An event ticket's price depends on the invoice's date (370): the early-bird
-- price a Manager gave on a back-dated invoice is not below its price; a
-- price the Owner typed below it is, and one above it is not.
create function pg_temp.ticket_back(inv uuid, extra text default null) returns jsonb language sql as
$$ select jsonb_agg(jsonb_build_object('kind', 'event_ticket', 'invoice_item_id', ii.id,
     'event_ticket_option_id', ii.event_ticket_option_id, 'unit_price', ii.unit_price, 'event_days', to_jsonb(ii.event_days),
     'quantity', ii.quantity + case when extra is null then 0 else 1 end,
     'attendees', (select jsonb_agg(jsonb_build_object('guest_id', g.id, 'name', g.name) order by g.line_position)
                     from public.event_guests g where g.invoice_item_id = ii.id and g.status = 'registered')
                  || case when extra is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('name', extra)) end))
   from public.invoice_items ii where ii.invoice_id = inv $$;
do $$
declare ev uuid; opt uuid; inv uuid; e text;
begin
  perform pg_temp.as_user('m');
  ev := public.event_save(jsonb_build_object('name', 'S377 Open Day',
    'early_bird_until', public.sg_today() - 5, 'early_bird_percent', 50,
    'days', jsonb_build_array(jsonb_build_object('day', public.sg_today())),
    'store_ids', jsonb_build_array(pg_temp.fx('A')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 60))));
  select id into opt from public.event_ticket_options where event_id = ev;
  -- The Manager records a sale dated in the early bird: two people at S$30.00.
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c1'),
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', opt, 'quantity', 2,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'S377 Guest One'), jsonb_build_object('name', 'S377 Guest Two')))),
    jsonb_build_object('business_date', (public.sg_today() - 10)::text));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 60)));
  perform pg_temp.check((select (unit_price, quantity) = (30.00::numeric, 2) from public.invoice_items where invoice_id = inv)
      and (select status from public.invoices where id = inv) = 'paid',
    'S10 fixture: a Manager sold two early-bird tickets at S$30.00 on a paid invoice dated in the early bird');
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Guest Three'), '{}'::jsonb, 'A third person came');
  perform pg_temp.check(e is null and (select (unit_price, quantity) = (30.00::numeric, 3) from public.invoice_items where invoice_id = inv),
    'S10 staff add a person at the early-bird price of the invoice''s date: not a special price (370), got ' || coalesce(e, 'saved'));
  -- The Owner gives S$20.00, below the S$30.00 of the invoice's date: staff
  -- may not add a person at it, and are told to add a new line.
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, jsonb_set(pg_temp.ticket_back(inv), '{0,unit_price}', '20'), '{}'::jsonb, 'Group price');
  perform pg_temp.as_user('s');
  e := coalesce(e, pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Guest Four'), '{}'::jsonb, 'A fourth person came'));
  perform pg_temp.check(e = 'Add the extra units as a new line at today''s price, or ask an Owner or Manager.'
      and (select (unit_price, quantity) = (20.00::numeric, 3) from public.invoice_items where invoice_id = inv),
    'S10 staff may not add a person at a ticket price the Owner set below the price of the invoice''s date, got ' || coalesce(e, 'saved'));
  -- At S$45.00, above the S$30.00 of the invoice's date (though below
  -- today's S$60.00, which is not this invoice's price), staff add a person.
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, jsonb_set(pg_temp.ticket_back(inv), '{0,unit_price}', '45'), '{}'::jsonb, 'Price with lunch');
  perform pg_temp.as_user('s');
  e := coalesce(e, pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Guest Four'), '{}'::jsonb, 'A fourth person came'));
  perform pg_temp.check(e is null
      and (select (unit_price, quantity) = (45.00::numeric, 4) from public.invoice_items where invoice_id = inv),
    'S10 staff add a person at a ticket price above the price of the invoice''s date (S$45.00 over S$30.00), got ' || coalesce(e, 'saved'));
end $$;

-- The date that sets a ticket's price is one staff cannot move: the higher of
-- its price on the invoice's date now and on the date before the invoice's
-- first correction. Moving the invoice into the early bird, in the same save
-- or an earlier one, does not let staff add a person at a special price
-- below the price of the date it was sold on.
do $$
declare ev uuid; opt uuid; inv uuid; e text; today date := public.sg_today();
  below text := 'Add the extra units as a new line at today''s price, or ask an Owner or Manager.';
begin
  perform pg_temp.as_user('m');
  ev := public.event_save(jsonb_build_object('name', 'S377 Late Day',
    'early_bird_until', today - 5, 'early_bird_percent', 50,
    'days', jsonb_build_array(jsonb_build_object('day', today)),
    'store_ids', jsonb_build_array(pg_temp.fx('A')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 60))));
  select id into opt from public.event_ticket_options where event_id = ev;
  insert into fx values ('late_opt', opt);

  -- The Owner sells two tickets today, after the early bird (S$60.00 each),
  -- then gives them S$40.00 each: above the S$30.00 early-bird price, below
  -- the S$60.00 of the day they were sold.
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c1'),
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', opt, 'quantity', 2,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'S377 Late One'), jsonb_build_object('name', 'S377 Late Two')))),
    jsonb_build_object('business_date', today::text));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 120)));
  e := pg_temp.try(inv, jsonb_set(pg_temp.ticket_back(inv), '{0,unit_price}', '40'), '{}'::jsonb, 'Group price');
  perform pg_temp.check(e is null and (select (unit_price, quantity) = (40.00::numeric, 2) from public.invoice_items where invoice_id = inv),
    'S10 fixture: the Owner sold two tickets today at S$60.00 and set S$40.00 each, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s');
  -- Back-dated into the early bird and a person added, in one save.
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Late Three'),
         jsonb_build_object('business_date', (today - 10)::text), 'A third person came, dated in the early bird');
  perform pg_temp.check(e = below
      and (select (unit_price, quantity) = (40.00::numeric, 2) from public.invoice_items where invoice_id = inv)
      and (select (business_date, edit_count) = (today, 1) from public.invoices where id = inv)
      and (select count(*) from public.event_guests where invoice_id = inv and status = 'registered') = 2,
    'S10 staff may not back-date a ticket invoice into the early bird and add a person at the Owner''s S$40.00 in the same save; the invoice is untouched, got ' || coalesce(e, 'saved'));
  -- An Owner as before: the same save goes through.
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Late Three'),
         jsonb_build_object('business_date', (today - 10)::text), 'A third person came, dated in the early bird');
  perform pg_temp.check(e is null
      and (select (unit_price, quantity) = (40.00::numeric, 3) from public.invoice_items where invoice_id = inv)
      and (select business_date from public.invoices where id = inv) = today - 10,
    'S10 an Owner still back-dates the invoice and adds a person at S$40.00 in one save, got ' || coalesce(e, 'saved'));

  -- Back-dated in one save, people added in a later one (the Owner's S$35.00).
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c1'),
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', opt, 'quantity', 2,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'S377 Late Four'), jsonb_build_object('name', 'S377 Late Five')))),
    jsonb_build_object('business_date', today::text));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 120)));
  e := pg_temp.try(inv, jsonb_set(pg_temp.ticket_back(inv), '{0,unit_price}', '35'), '{}'::jsonb, 'Group price');
  perform pg_temp.as_user('s');
  e := coalesce(e, pg_temp.try(inv, pg_temp.ticket_back(inv), jsonb_build_object('business_date', (today - 10)::text), 'Sold in the early bird'));
  perform pg_temp.check(e is null and (select business_date from public.invoices where id = inv) = today - 10,
    'S10 staff may back-date a ticket invoice on its own (the date is theirs to correct), got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Late Six'), '{}'::jsonb, 'A third person came');
  perform pg_temp.check(e = below
      and (select (unit_price, quantity) = (35.00::numeric, 2) from public.invoice_items where invoice_id = inv)
      and (select edit_count from public.invoices where id = inv) = 2,
    'S10 and in a later save may not add a person at the Owner''s S$35.00: the price of the date it was sold on (S$60.00) still counts, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Late Six'), '{}'::jsonb, 'A third person came');
  perform pg_temp.check(e is null and (select (unit_price, quantity) = (35.00::numeric, 3) from public.invoice_items where invoice_id = inv),
    'S10 a Manager still adds that person at S$35.00, got ' || coalesce(e, 'saved'));

  -- Staff choose the first date themselves: they create the invoice dated in
  -- the early bird (pass 2 still charges them today's S$60.00), move it to
  -- today, and the Owner then gives the group S$40.00 on an invoice dated
  -- today. The early-bird date staff chose does not count: pass 2 never
  -- charged them its price.
  perform pg_temp.as_user('s');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c1'),
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', opt, 'quantity', 2,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'S377 Late Ten'), jsonb_build_object('name', 'S377 Late Eleven')))),
    jsonb_build_object('business_date', (today - 10)::text));
  perform pg_temp.check((select (unit_price, quantity) = (60.00::numeric, 2) from public.invoice_items where invoice_id = inv),
    'S10 fixture: staff create a ticket invoice dated in the early bird and are charged today''s S$60.00');
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 120)));
  e := pg_temp.try(inv, pg_temp.ticket_back(inv), jsonb_build_object('business_date', today::text), 'Wrong date');
  perform pg_temp.as_user('o');
  e := coalesce(e, pg_temp.try(inv, jsonb_set(pg_temp.ticket_back(inv), '{0,unit_price}', '40'), '{}'::jsonb, 'Group price'));
  perform pg_temp.check(e is null
      and (select business_date from public.invoices where id = inv) = today
      and (select (unit_price, quantity) = (40.00::numeric, 2) from public.invoice_items where invoice_id = inv),
    'S10 fixture: staff moved it to today and the Owner set S$40.00 each, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Late Twelve'),
         jsonb_build_object('business_date', (today - 10)::text), 'A third person came, dated in the early bird');
  perform pg_temp.check(e = below
      and (select (unit_price, quantity) = (40.00::numeric, 2) from public.invoice_items where invoice_id = inv)
      and (select business_date from public.invoices where id = inv) = today,
    'S10 staff who created the invoice in the early bird may not back-date it again and add a person at the Owner''s S$40.00, got ' || coalesce(e, 'saved'));

  -- The affiliate chosen while the invoice was unpaid writes a revision with
  -- no invoice in it. It is not the invoice's first correction: the date
  -- before the Owner's correction still counts.
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c1'),
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', opt, 'quantity', 2,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'S377 Late Seven'), jsonb_build_object('name', 'S377 Late Eight')))),
    jsonb_build_object('business_date', today::text));
  perform public.set_invoice_affiliate(inv, pg_temp.fx('aff1'));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 120)));
  e := pg_temp.try(inv, jsonb_set(pg_temp.ticket_back(inv), '{0,unit_price}', '40'), '{}'::jsonb, 'Group price');
  perform pg_temp.check(e is null
      and (select count(*) from public.invoice_revisions r where r.invoice_id = inv and not r.snapshot ? 'invoice') = 1
      and (select not snapshot ? 'invoice' from public.invoice_revisions where invoice_id = inv order by revision_no limit 1),
    'S10 fixture: the invoice''s first revision is the affiliate''s, with no invoice in it, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Late Nine'),
         jsonb_build_object('business_date', (today - 10)::text), 'A third person came, dated in the early bird');
  perform pg_temp.check(e = below
      and (select (unit_price, quantity) = (40.00::numeric, 2) from public.invoice_items where invoice_id = inv)
      and (select business_date from public.invoices where id = inv) = today,
    'S10 staff may not back-date and add a person at S$40.00 on an invoice whose first revision is the affiliate''s, got ' || coalesce(e, 'saved'));

  -- Moved the other way: an invoice dated in the early bird (S$30.00), moved
  -- to today, where the ticket is S$60.00. The price of the date now counts
  -- too: staff may not add a person at S$30.00.
  perform pg_temp.as_user('m');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c1'),
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', opt, 'quantity', 2,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'S377 Late Ten'), jsonb_build_object('name', 'S377 Late Eleven')))),
    jsonb_build_object('business_date', (today - 10)::text));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 60)));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.ticket_back(inv, 'S377 Late Twelve'),
         jsonb_build_object('business_date', today::text), 'A third person came, dated today');
  perform pg_temp.check(e = below
      and (select (unit_price, quantity) = (30.00::numeric, 2) from public.invoice_items where invoice_id = inv)
      and (select business_date from public.invoices where id = inv) = today - 10,
    'S10 staff may not move an early-bird invoice to today and add a person at S$30.00 (S$60.00 today), got ' || coalesce(e, 'saved'));
end $$;

-- A change that keeps the quantity adds no units: on a line at a special
-- price and on one below today's price, staff still give FOC with its
-- reason, apply a line voucher, or change a rental's return date.
do $$
declare inv uuid; e text; k text;
begin
  -- The Owner's special S$60.00 on two pairs (S$100.00 in the catalogue).
  foreach k in array array['FOC', 'line voucher'] loop
    inv := pg_temp.sale('A', 2);
    e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0,unit_price}', '60'), '{}'::jsonb, 'Special price for a regular');
    perform pg_temp.as_user('s');
    e := coalesce(e, pg_temp.try(inv, pg_temp.line0(inv, case k
           when 'FOC' then jsonb_build_object('foc_quantity', 1, 'foc_reason', 'Second pair free')
           else jsonb_build_object('line_voucher_id', pg_temp.fx('dv')) end), '{}'::jsonb, 'Keyed wrongly at the till'));
    perform pg_temp.check(e is null
        and (select (quantity, unit_price) = (2, 60.00::numeric)
                and case k when 'FOC' then (foc_quantity, line_total) = (1, 60.00::numeric)
                           else (line_voucher_id, line_discount) = (pg_temp.fx('dv'), 10.00::numeric) end
               from public.invoice_items where invoice_id = inv),
      format('S10 staff %s on a line at the Owner''s special S$60.00, at the same quantity, got %s',
             case k when 'FOC' then 'give FOC with its reason' else 'apply a line voucher' end, coalesce(e, 'saved')));
  end loop;

  -- Pairs sold at S$100.00 at store B; the price there is now S$120.00.
  declare inv_foc uuid; inv_lv uuid;
  begin
    inv_foc := pg_temp.sale('B', 2); inv_lv := pg_temp.sale('B', 2);
    perform pg_temp.as_user('o');
    perform public.set_product_prices(pg_temp.fx('B'), pg_temp.fx('prod'), 120, 120, 'available');
    perform pg_temp.as_user('s');
    e := pg_temp.try(inv_foc, pg_temp.line0(inv_foc, jsonb_build_object('foc_quantity', 1, 'foc_reason', 'Second pair free')), '{}'::jsonb, 'Second pair was free');
    perform pg_temp.check(e is null
        and (select (quantity, unit_price, foc_quantity, line_total) = (2, 100.00::numeric, 1, 100.00::numeric) from public.invoice_items where invoice_id = inv_foc),
      'S10 staff give FOC on a line below today''s price (S$100.00, now S$120.00), at the same quantity, got ' || coalesce(e, 'saved'));
    e := pg_temp.try(inv_lv, pg_temp.line0(inv_lv, jsonb_build_object('line_voucher_id', pg_temp.fx('dv'))), '{}'::jsonb, 'Customer had a voucher');
    perform pg_temp.check(e is null
        and (select (quantity, unit_price, line_voucher_id, line_discount) = (2, 100.00::numeric, pg_temp.fx('dv'), 10.00::numeric)
               from public.invoice_items where invoice_id = inv_lv),
      'S10 staff apply a line voucher on a line below today''s price, at the same quantity, got ' || coalesce(e, 'saved'));
    perform pg_temp.as_user('o');
    perform public.set_product_prices(pg_temp.fx('B'), pg_temp.fx('prod'), 100, 100, 'available');
  end;

  -- A 2-day rental of the chair (S$20.00 a day): at the Owner's special
  -- S$30.00, and at the saved S$40.00 after the day rate went up to S$25.00.
  foreach k in array array['special', 'below'] loop
    inv := pg_temp.sale_of(jsonb_build_object('kind','rental','special_product_id',pg_temp.fx('chair'),'quantity',1,
             'rental_rate_type','day','rental_periods',2,'rental_start_date',current_date), 40);
    if k = 'special' then
      e := pg_temp.try(inv, jsonb_set(pg_temp.lines(inv), '{0,unit_price}', '30'), '{}'::jsonb, 'Special rental price');
    else
      update public.special_products set rate_day = 25 where id = pg_temp.fx('chair');
    end if;
    perform pg_temp.as_user('s');
    e := coalesce(e, pg_temp.try(inv, pg_temp.line0(inv, jsonb_build_object('rental_return_date', current_date + 2)), '{}'::jsonb, 'Chair returned'));
    perform pg_temp.check(e is null
        and (select (quantity, unit_price, rental_return_date) = (1, case k when 'special' then 30.00 else 40.00 end::numeric, current_date + 2)
               from public.invoice_items where invoice_id = inv),
      format('S10 staff record a rental''s return date at %s, at the same quantity, got %s',
             case k when 'special' then 'the Owner''s special S$30.00' else 'a price below today''s (S$40.00, now S$50.00)' end, coalesce(e, 'saved')));
    update public.special_products set rate_day = 20 where id = pg_temp.fx('chair');
    e := null;
  end loop;
end $$;

-- ═════ S11 Staff change only the method of a payment that stands ═════
do $$
declare inv uuid; p uuid; rev uuid; rep uuid; e text;
  nostand text := 'Only an Owner or Manager can change the method of a reversal, or of a payment that was reversed or refunded';
begin
  -- The Owner corrected a payment's date: the receipt is reversed and replaced.
  inv := pg_temp.sale('A', 1); p := pg_temp.pay(inv);
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 100, 'date', pg_temp.pay_date(p) - 3, 'payment_method_id', pg_temp.fx('cash')))), 'Paid three days earlier');
  select id into rev from public.invoice_payments where invoice_id = inv and entry_kind = 'correction_reversal';
  select id into rep from public.invoice_payments where invoice_id = inv and entry_kind = 'correction_replacement';
  perform pg_temp.check(e is null and rev is not null and rep is not null and (select status from public.invoices where id = inv) = 'paid',
    'S11 fixture: the Owner corrected a payment''s date (a reversal and a replacement), got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', rev, 'payment_method_id', pg_temp.fx('card')))), 'Reversal was by card');
  perform pg_temp.check(e = nostand and (select payment_method_id from public.invoice_payments where id = rev) = pg_temp.fx('cash'),
    'S11 staff are refused the method of a correction''s reversal, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p, 'payment_method_id', pg_temp.fx('card')))), 'Receipt was by card');
  perform pg_temp.check(e = nostand and (select payment_method_id from public.invoice_payments where id = p) = pg_temp.fx('cash'),
    'S11 and of the receipt that correction reversed, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', rep, 'payment_method_id', pg_temp.fx('card')))), 'Paid by card');
  perform pg_temp.check(e is null and (select payment_method_id from public.invoice_payments where id = rep) = pg_temp.fx('card')
      and (select count(*) from public.invoice_payments where invoice_id = inv and payment_method_id = pg_temp.fx('cash')) = 2,
    'S11 staff change the method of the replacement, the payment that stands; the reversed pair stays cash, got ' || coalesce(e, 'saved'));
  -- An Owner as before.
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', rev, 'payment_method_id', pg_temp.fx('card')))), 'Reversal was by card');
  perform pg_temp.check(e is null and (select payment_method_id from public.invoice_payments where id = rev) = pg_temp.fx('card'),
    'S11 an Owner still changes the method of a reversal, got ' || coalesce(e, 'saved'));

  -- A payment with money refunded against it.
  inv := pg_temp.sale('A', 2); p := pg_temp.pay(inv);
  insert into public.invoice_refunds(invoice_id, amount, reason, refunded_by, payment_id) values (inv, 50, 'Part refunded in cash', pg_temp.fx('o'), p);
  perform pg_temp.as_user('s');
  perform pg_temp.check(public.staff_may_correct_invoice(inv), 'S11 fixture: staff may correct the invoice with a part refund');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p, 'payment_method_id', pg_temp.fx('card')))), 'Paid by card');
  perform pg_temp.check(e = nostand and (select payment_method_id from public.invoice_payments where id = p) = pg_temp.fx('cash'),
    'S11 staff are refused the method of a payment with money refunded against it, got ' || coalesce(e, 'saved'));
end $$;

-- An older refund that names no payment: its money may have come from any
-- payment on the invoice, so none of them stands for staff.
do $$
declare inv uuid; p uuid; inv2 uuid; p2 uuid; e text;
  nostand text := 'Only an Owner or Manager can change the method of a reversal, or of a payment that was reversed or refunded';
begin
  inv := pg_temp.sale('A', 2); p := pg_temp.pay(inv);
  inv2 := pg_temp.sale('A', 1); p2 := pg_temp.pay(inv2);
  insert into public.invoice_refunds(invoice_id, amount, reason, refunded_by, payment_id) values (inv, 50, 'Older refund, no payment named', pg_temp.fx('o'), null);
  perform pg_temp.as_user('s');
  perform pg_temp.check(public.staff_may_correct_invoice(inv) and (select status from public.invoices where id = inv) = 'paid',
    'S11 fixture: staff may correct the paid invoice with an older refund that names no payment');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p, 'payment_method_id', pg_temp.fx('card')))), 'Paid by card');
  perform pg_temp.check(e = nostand and (select payment_method_id from public.invoice_payments where id = p) = pg_temp.fx('cash'),
    'S11 staff are refused the method of a payment on an invoice with an older refund that names no payment, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv2, pg_temp.lines(inv2), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p2, 'payment_method_id', pg_temp.fx('card')))), 'Paid by card');
  perform pg_temp.check(e is null and (select payment_method_id from public.invoice_payments where id = p2) = pg_temp.fx('card'),
    'S11 that refund does not stop staff changing the method on another invoice, got ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p, 'payment_method_id', pg_temp.fx('card')))), 'Paid by card');
  perform pg_temp.check(e is null and (select payment_method_id from public.invoice_payments where id = p) = pg_temp.fx('card'),
    'S11 an Owner still changes it, got ' || coalesce(e, 'saved'));
end $$;

-- A refund that names its payment holds back that payment only: on an
-- invoice paid in two parts, staff still change the method of the other.
do $$
declare inv uuid; p1 uuid; p2 uuid; e text;
  nostand text := 'Only an Owner or Manager can change the method of a reversal, or of a payment that was reversed or refunded';
begin
  inv := pg_temp.sale('A', 2, 120);
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 80)));
  select id into p1 from public.invoice_payments where invoice_id = inv and amount = 120;
  select id into p2 from public.invoice_payments where invoice_id = inv and amount = 80;
  insert into public.invoice_refunds(invoice_id, amount, reason, refunded_by, payment_id) values (inv, 50, 'Part refund of the first payment', pg_temp.fx('o'), p1);
  perform pg_temp.as_user('s');
  perform pg_temp.check(public.staff_may_correct_invoice(inv) and p1 is not null and p2 is not null,
    'S11 fixture: staff may correct an invoice paid in two parts, with a refund against the first');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p1, 'payment_method_id', pg_temp.fx('card')))), 'Paid by card');
  perform pg_temp.check(e = nostand and (select payment_method_id from public.invoice_payments where id = p1) = pg_temp.fx('cash'),
    'S11 staff are refused the method of the payment the refund names, got ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('payment_methods', jsonb_build_array(jsonb_build_object('payment_id', p2, 'payment_method_id', pg_temp.fx('card')))), 'Paid by card');
  perform pg_temp.check(e is null and (select payment_method_id from public.invoice_payments where id = p2) = pg_temp.fx('card'),
    'S11 and change the method of the other payment, which the refund does not name, got ' || coalesce(e, 'saved'));
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All staff correction checks passed.';
end $$;
rollback;
