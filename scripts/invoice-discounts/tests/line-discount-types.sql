-- One Discount per invoice line (384).
--
--   L1 The voucher lists: a discount voucher is a Voucher, Birthday or Staff
--      voucher (Voucher when none is given); a sold voucher is on none; a
--      Birthday voucher needs its rule, and only it keeps one.
--   L2 Every option on every kind of line, made with create_invoice_with_details:
--      FOC on every line but a credit package or premium bundle; Vouchers,
--      Birthday and Staff on our own products only (third-party, promotion,
--      sold voucher, therapy session and package, special product, rental,
--      event ticket, credit package and premium bundle refused, each with a
--      sentence staff can act on); Manual and Percentage on every line but a
--      credit package or premium bundle. Each allowed line stores its option,
--      voucher, percentage, internal reason, amount, who gave it and when, and
--      the invoice adds up.
--   L3 One per line: FOC and a discount on one line are refused, made and
--      edited; a line moves from a discount to FOC and back in a correction;
--      Make FOC refuses a discounted line (a voucher saved before 384 too); a
--      line saved before 384 with FOC and a voucher is kept as it is when
--      sent back unchanged, refused when changed without picking one, and
--      saved when one is picked; Undo FOC still leaves its voucher.
--   L4 Birthday: no date of birth, the day itself (and 29 Feb, kept on 28 Feb
--      in other years), the birth month; one birthday-discount invoice per
--      customer per year, with any number of birthday lines on it; cancelled,
--      refunded and deleted invoices do not count, nor an edit of the same
--      invoice, nor last year; a line saved before 384 and an invoice-level
--      Birthday voucher count; a correction to another customer or date
--      checks it again. A Staff discount asks nothing of the customer.
--   L5 Bounds and rounding: Percentage more than 0 and at most 100, worked
--      out to the cent on the line's value; Manual more than S$0 and at most
--      the line's value; a reason for both, trimmed; the reason trigger.
--   L6 Who: an Inventory Manager may give Manual and Percentage, not the
--      voucher options; staff correcting a paid invoice (377) may give the
--      new options, and keep who gave a Discount that stays the same.
--   L7 A line voucher sent with no option is that voucher's category; an
--      option that is not the voucher's list is refused.
--   L8 A change of Discount alone moves no stock.
--   L9 refresh_invoice_discount_total adds up as create_invoice does: subtotal
--      100, manual 20, a 10% invoice voucher gives 8 when made, after an edit
--      and after an FOC change; with third-party value too.
--   L10 Special product and rental lines keep their FOC, made and edited.
--   L11 Confirm FOC reprices a percentage line with its value.
--   L12 The Discounts report: a column per option, a line saved before 384
--      under its voucher's category, exchange credit on its own, and the
--      parts add up to the total.
--   L13 An Owner's price-only correction of a therapy session: a percentage
--      follows the corrected price, a manual amount above it is refused, one
--      within it stays.
--   L14 A Discount alone given in a correction is not a sale again: a paid
--      therapy package keeps its therapy, an ended promotion and a ticket
--      line take it, stock does not move; a change of more than the Discount
--      is still refused; an old FOC-and-voucher line can drop its voucher
--      alone; a new reason is the corrector's.
--   L15 A Birthday voucher as the invoice's own discount voucher: date of
--      birth, birth month, once a year, checked when picked in a correction
--      or moved to another customer, not when kept as saved before 384.
--   L16 A birthday line saved before 384 is checked again when the invoice
--      moves to another customer.
--   L17 A manual amount is rounded to the cent before its bounds.
--   L18 A correction of a note leaves the money of an invoice edited before
--      384 alone; a change of service staff works the voucher out again.
--   L19 An invoice saved before 384 whose special product FOC is not on its
--      line: a note is saved, a correction that would charge it again is
--      refused, one that gives the line its FOC again repairs it.
--   L20 Every invoice made here adds up: subtotal = its lines, total =
--      subtotal - discounts.
--   L21 Running 384 again changes nothing, and fills the list of a discount
--      voucher that has none from its name.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 384 (install it after "begin;" on a
-- database that does not have it yet). Fixtures are invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
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
create temp table made(id uuid primary key);
-- An invoice as the invoice page makes it: {"id": ...}, or {"err": the refusal}.
create function pg_temp.mk(cust uuid, items jsonb, hdr jsonb default '{}'::jsonb) returns jsonb language plpgsql as
$$declare v uuid;
begin
  v := public.create_invoice_with_details(pg_temp.fx('A'), cust, items,
         jsonb_build_object('business_date', public.sg_today()::text) || hdr);
  insert into made values (v) on conflict do nothing;
  return jsonb_build_object('id', v);
exception when others then return jsonb_build_object('err', sqlerrm);
end$$;
-- A correction as the page saves it; null when it was saved, else the refusal.
create function pg_temp.fix(inv uuid, items jsonb, hdr jsonb default '{}'::jsonb, reason text default 'Keyed wrongly') returns text language plpgsql as
$$begin perform public.correct_invoice(inv, items, hdr, reason, gen_random_uuid()); return null;
exception when others then return sqlerrm; end$$;
-- The invoice's lines as the correction form sends them back, Discount and FOC included.
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$$ select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text,
     'product_id', product_id, 'voucher_id', voucher_id, 'promotion_id', promotion_id,
     'therapy_service_id', therapy_service_id, 'therapy_package_id', therapy_package_id,
     'credit_package_id', credit_package_id, 'premium_bundle_id', premium_bundle_id,
     'special_product_id', special_product_id, 'rental_rate_type', rental_rate_type, 'rental_periods', rental_periods,
     'rental_start_date', rental_start_date, 'rental_return_date', rental_return_date,
     'event_ticket_option_id', event_ticket_option_id, 'event_days', event_days,
     'quantity', quantity, 'unit_price', unit_price,
     'foc_quantity', nullif(foc_quantity, 0), 'foc_reason', case when foc_quantity > 0 then foc_reason end,
     'line_discount_type', line_discount_type, 'line_voucher_id', line_voucher_id,
     'line_discount_amount', case when line_discount_type = 'manual' then line_discount end,
     'line_discount_percent', line_discount_percent, 'line_discount_reason', line_discount_reason)) order by id)
     from public.invoice_items where invoice_id = inv $$;
-- Those lines with one of them (by id) changed; a JSON null drops a key.
create function pg_temp.patch(inv uuid, item uuid, p jsonb) returns jsonb language sql as
$$ select jsonb_agg(case when (x->>'invoice_item_id')::uuid = item then jsonb_strip_nulls(x || p) else x end)
     from jsonb_array_elements(pg_temp.lines(inv)) x $$;
create function pg_temp.item(inv uuid, kind text default 'product') returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv and line_kind::text = kind order by id limit 1 $$;
create function pg_temp.li(item uuid) returns public.invoice_items language sql as
$$ select * from public.invoice_items where id = item $$;
create function pg_temp.inv(i uuid) returns public.invoices language sql as
$$ select * from public.invoices where id = i $$;
create function pg_temp.customer(dob date) returns uuid language plpgsql as
$$declare c uuid;
begin
  -- A phone no customer has (a shared one would ask for a review).
  insert into public.customers(full_name, phone, date_of_birth)
  values ('Test Buyer',
          (select '+659123' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
            where not exists (select 1 from public.customers x
                               where regexp_replace(coalesce(x.phone, ''), '\D', '', 'g') = '659123' || lpad(n::text, 4, '0'))
            order by random() limit 1), dob) returning id into c;
  return c;
end$$;
-- A line of each kind (one unit), and each option as the page sends it.
create function pg_temp.ln(kind text) returns jsonb language sql as
$$ select case kind
     when 'own' then jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',2)
     when 'own2' then jsonb_build_object('kind','product','product_id',pg_temp.fx('own2'),'quantity',1)
     when 'third' then jsonb_build_object('kind','product','product_id',pg_temp.fx('third'),'quantity',1)
     when 'promotion' then jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('promo'),'quantity',1)
     when 'voucher' then jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('gift'),'quantity',1)
     when 'session' then jsonb_build_object('kind','therapy','therapy_service_id',pg_temp.fx('session'),'quantity',1)
     when 'package' then jsonb_build_object('kind','therapy','therapy_package_id',pg_temp.fx('package'),'quantity',1)
     when 'special' then jsonb_build_object('kind','special_product','special_product_id',pg_temp.fx('chair'),'quantity',1)
     when 'rental' then jsonb_build_object('kind','rental','special_product_id',pg_temp.fx('chair'),'quantity',1,
                          'rental_rate_type','day','rental_periods',2,
                          'rental_start_date',public.sg_today()::text,'rental_return_date',(public.sg_today()+2)::text)
     when 'ticket' then jsonb_build_object('kind','event_ticket','event_ticket_option_id',pg_temp.fx('opt'),'quantity',1,
                          'event_days',jsonb_build_array(public.sg_today()::text),
                          'attendees',jsonb_build_array(jsonb_build_object('name','Test Guest')))
     when 'credit' then jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('credit'),'quantity',1)
     when 'bundle' then jsonb_build_object('kind','premium_bundle','premium_bundle_id',pg_temp.fx('bundle'),'quantity',1)
   end $$;
create function pg_temp.opt(o text) returns jsonb language sql as
$$ select case o
     when 'foc' then jsonb_build_object('foc_quantity',1,'foc_reason','Test goodwill')
     when 'voucher' then jsonb_build_object('line_discount_type','voucher','line_voucher_id',pg_temp.fx('v10'))
     when 'birthday' then jsonb_build_object('line_discount_type','birthday','line_voucher_id',pg_temp.fx('bday_day'))
     when 'staff' then jsonb_build_object('line_discount_type','staff','line_voucher_id',pg_temp.fx('staff50'))
     when 'manual' then jsonb_build_object('line_discount_type','manual','line_discount_amount',5,'line_discount_reason','Scuffed box')
     when 'percentage' then jsonb_build_object('line_discount_type','percentage','line_discount_percent',10,'line_discount_reason','Regular customer')
   end $$;
create function pg_temp.manual(amount numeric, reason text default 'Scuffed box') returns jsonb language sql as
$$ select jsonb_build_object('line_discount_type','manual','line_discount_amount',amount,'line_discount_reason',reason) $$;
create function pg_temp.pct(p numeric, reason text default 'Regular customer') returns jsonb language sql as
$$ select jsonb_build_object('line_discount_type','percentage','line_discount_percent',p,'line_discount_reason',reason) $$;
create function pg_temp.bday(v text) returns jsonb language sql as
$$ select jsonb_build_object('line_discount_type','birthday','line_voucher_id',pg_temp.fx(v)) $$;
-- Paid in cash, in full.
create function pg_temp.pay(inv uuid) returns void language sql as
$$ select public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', (select total_amount from public.invoices where id = inv)))) $$;

-- ═════ Fixtures (invented) ═════
do $$
declare o uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); im uuid:=gen_random_uuid();
 sfx text:=lower(substr(md5(random()::text||clock_timestamp()::text),1,6));
 st uuid; v uuid; e uuid;
begin
 insert into auth.users(id,email) values (o,'l384-o-'||sfx||'@tests.invalid'),(s,'l384-s-'||sfx||'@tests.invalid'),(im,'l384-im-'||sfx||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (o,'L384 Owner','l384-o-'||sfx||'@tests.invalid','owner'),
   (s,'L384 Staff','l384-s-'||sfx||'@tests.invalid','staff'),
   (im,'L384 Inventory','l384-im-'||sfx||'@tests.invalid','inventory_manager');
 insert into fx values ('o',o),('s',s),('im',im);
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('L384 Store '||sfx,'L384'||sfx,'SG') returning id into st;
 insert into fx values ('A',st);
 insert into user_store_assignments(user_id,store_id) values(s,st),(im,st);
 insert into payment_methods(name) values('L384 Cash '||sfx) returning id into v; insert into fx values ('cash',v);
 insert into products(name,sku,product_type) values('L384 Lamp','L384L-'||sfx,'own') returning id into v; insert into fx values ('own',v);
 insert into store_inventory(store_id,product_id,current_qty) values(st,v,500);
 perform set_product_prices(st,v,100,100,'available');
 insert into products(name,sku,product_type) values('L384 Kettle','L384K-'||sfx,'own') returning id into v; insert into fx values ('own2',v);
 insert into store_inventory(store_id,product_id,current_qty) values(st,v,500);
 perform set_product_prices(st,v,33.33,33.33,'available');
 insert into products(name,sku,product_type) values('L384 Partner Tea','L384T-'||sfx,'third_party') returning id into v; insert into fx values ('third',v);
 insert into store_inventory(store_id,product_id,current_qty) values(st,v,500);
 perform set_product_prices(st,v,50,50,'available');
 insert into promotions(name,code,promo_type,fixed_price) values('L384 Promo','L384P'||sfx,'bundle',80) returning id into v; insert into fx values ('promo',v);
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(v,st,80,true);
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('L384 Gift 40','L384G'||sfx,'normal',40,'limited') returning id into v; insert into fx values ('gift',v);
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,50);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,40,true);
 insert into therapy_services(service_code,name,standard_price,duration_minutes,is_active) values('L384S'||sfx,'L384 Session',30,30,true) returning id into v; insert into fx values ('session',v);
 insert into therapy_service_stores(service_id,store_id) values(v,st);
 insert into unlimited_therapy_packages(name,duration_months) values('L384 Therapy 1m',1) returning id into v; insert into fx values ('package',v);
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store) values(v,st,150,true);
 insert into special_products(name,sku,sale_price,rate_day,rate_week) values('L384 Chair','L384CH'||sfx,500,20,100) returning id into v; insert into fx values ('chair',v);
 insert into credit_packages(name,customer_price,paid_credit_amount) values('L384 Credit '||sfx,100,100) returning id into v; insert into fx values ('credit',v);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount) values('L384 Bundle '||sfx,200,200) returning id into v; insert into fx values ('bundle',v);
 -- The discount vouchers: a 10% Voucher, a S$15 Voucher, Birthday on the day
 -- (20%) and in the month (10%), Staff 50%, and a sold voucher.
 insert into vouchers(name,code,voucher_kind,discount_percent,discount_category) values('L384 Ten Percent','L384V10'||sfx,'percentage_discount',10,'voucher') returning id into v; insert into fx values ('v10',v);
 insert into vouchers(name,code,voucher_kind,discount_amount) values('L384 Fifteen Off','L384V15'||sfx,'fixed_discount',15) returning id into v; insert into fx values ('v15',v);
 insert into vouchers(name,code,voucher_kind,discount_percent,discount_category,birthday_rule) values('L384 Birthday Day','L384BD'||sfx,'percentage_discount',20,'birthday','actual_date') returning id into v; insert into fx values ('bday_day',v);
 insert into vouchers(name,code,voucher_kind,discount_percent,discount_category,birthday_rule) values('L384 Birthday Month','L384BM'||sfx,'percentage_discount',10,'birthday','whole_month') returning id into v; insert into fx values ('bday_month',v);
 insert into vouchers(name,code,voucher_kind,discount_percent,discount_category) values('L384 Staff Half','L384ST'||sfx,'percentage_discount',50,'staff') returning id into v; insert into fx values ('staff50',v);
 -- An event at the store, today and tomorrow, S$60 a day.
 e := public.event_save(jsonb_build_object('name', 'L384 Talk '||sfx,
   'days', jsonb_build_array(jsonb_build_object('day', public.sg_today()), jsonb_build_object('day', public.sg_today() + 1)),
   'store_ids', jsonb_build_array(st),
   'options', jsonb_build_array(jsonb_build_object('name', 'Day Pass', 'days_count', 1, 'price', 60))));
 insert into fx select 'opt', id from public.event_ticket_options where event_id = e;
 -- Customers: one whose birthday is today, one with no date of birth.
 insert into fx values ('today', pg_temp.customer(make_date(1988, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int)));
 insert into fx values ('nodob', pg_temp.customer(null));
end $$;

-- ═════ L1 The voucher lists ═════
do $$
declare v uuid; e text;
begin
  insert into public.vouchers(name,code,voucher_kind,discount_amount) values('L384 No List','L384NL'||gen_random_uuid(),'fixed_discount',5) returning id into v;
  perform pg_temp.check((select discount_category from public.vouchers where id = v) = 'voucher',
    'L1 a discount voucher given no list is a Voucher');
  insert into public.vouchers(name,code,voucher_kind,selling_price,discount_category,birthday_rule) values('L384 Sold','L384SD'||gen_random_uuid(),'normal',20,'staff','actual_date') returning id into v;
  perform pg_temp.check((select (discount_category, birthday_rule) is not distinct from (null::text, null::text) from public.vouchers where id = v),
    'L1 a sold voucher is on no list and has no birthday rule');
  begin
    insert into public.vouchers(name,code,voucher_kind,discount_percent,discount_category) values('L384 Bday No Rule','L384BN'||gen_random_uuid(),'percentage_discount',5,'birthday');
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e ~ 'birthday itself or the whole birth month', 'L1 a Birthday voucher needs its rule: ' || coalesce(e, 'saved'));
  update public.vouchers set discount_category = 'staff' where id = pg_temp.fx('bday_month');
  perform pg_temp.check((select discount_category = 'staff' and birthday_rule is null from public.vouchers where id = pg_temp.fx('bday_month')),
    'L1 a voucher moved off the Birthday list loses its rule');
  update public.vouchers set discount_category = 'birthday', birthday_rule = 'whole_month' where id = pg_temp.fx('bday_month');
  begin
    update public.vouchers set discount_category = 'gift' where id = pg_temp.fx('v15');
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e ~ 'vouchers_discount_category_check', 'L1 there is no fourth list: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L2 Every option on every kind of line ═════
do $$
declare k text; o text; r jsonb; ok boolean; want text; li public.invoice_items; inv public.invoices;
  cust uuid; val numeric; amt numeric;
begin
  perform pg_temp.as_user('o');
  foreach k in array array['own','third','promotion','voucher','session','package','special','rental','ticket','credit','bundle'] loop
    foreach o in array array['foc','voucher','birthday','staff','manual','percentage'] loop
      -- A birthday is once a year, so each one is a new customer born today.
      cust := case when o = 'birthday' then pg_temp.customer(make_date(1992, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int))
                   else pg_temp.fx('nodob') end;
      r := pg_temp.mk(cust, jsonb_build_array(pg_temp.ln(k) || pg_temp.opt(o)));
      ok := case o when 'foc' then k not in ('credit','bundle')
                   when 'manual' then k not in ('credit','bundle')
                   when 'percentage' then k not in ('credit','bundle')
                   else k = 'own' end;
      if not ok then
        want := case
          when o = 'foc' then 'cannot be made FOC when the invoice is created'
          when o in ('manual','percentage') then 'cannot take a line discount\. Use the invoice''s manual discount or discount voucher instead'
          when k = 'third' then 'cannot be used on a third-party product \("L384 Partner Tea"\)\. Use a manual or percentage discount'
          when k = 'ticket' then 'line voucher cannot discount an event ticket'
          when k = 'credit' then 'line voucher cannot discount a credit package'
          when k = 'bundle' then 'line voucher cannot discount a premium bundle'
          else 'is for our own products only\. Use a manual or percentage discount on' end;
        perform pg_temp.check(r ? 'err' and r->>'err' ~ want,
          format('L2 %s on a %s line is refused (%s): %s', o, k, want, coalesce(r->>'err', 'saved')));
        continue;
      end if;
      if r ? 'err' then
        perform pg_temp.check(false, format('L2 %s on a %s line is saved: %s', o, k, r->>'err')); continue; end if;
      select * into li from public.invoice_items where invoice_id = (r->>'id')::uuid;
      select * into inv from public.invoices where id = (r->>'id')::uuid;
      val := li.unit_price * li.quantity + coalesce(li.topup_amount, 0);
      amt := case o when 'voucher' then round(val * 0.10, 2) when 'birthday' then round(val * 0.20, 2)
                    when 'staff' then round(val * 0.50, 2) when 'manual' then 5 when 'percentage' then round(val * 0.10, 2) else 0 end;
      if o = 'foc' then
        -- One unit free (of the own product's two).
        amt := round(val / li.quantity, 2);
        perform pg_temp.check(li.foc_quantity = 1 and li.foc_amount = amt and li.line_total = val - amt and li.line_discount = 0
            and li.line_discount_type is null and inv.subtotal = val - amt and inv.foc_total = amt and inv.total_amount = val - amt,
          format('L2 FOC on a %s line: one unit free (S$%s of S$%s), no discount', k, amt, val));
      else
        perform pg_temp.check(li.line_discount_type = o and li.line_discount = amt and li.line_total = val
            and li.foc_quantity = 0
            and li.line_voucher_id is not distinct from case o when 'voucher' then pg_temp.fx('v10') when 'birthday' then pg_temp.fx('bday_day')
                                                               when 'staff' then pg_temp.fx('staff50') end
            and li.line_discount_percent is not distinct from case o when 'percentage' then 10::numeric end
            and li.line_discount_reason is not distinct from case o when 'manual' then 'Scuffed box' when 'percentage' then 'Regular customer' end
            and li.line_discount_by = pg_temp.fx('o') and li.line_discount_at is not null
            and inv.subtotal = val and inv.discount_total = amt and inv.total_amount = val - amt,
          format('L2 %s on a %s line: S$%s off S$%s, stored with its option, voucher, percentage, reason and who (got %s %s off %s, total %s)',
                 o, k, amt, val, li.line_discount_type, li.line_discount, li.line_total, inv.total_amount));
      end if;
    end loop;
  end loop;
end $$;

-- ═════ L3 One per line ═════
do $$
declare r jsonb; inv uuid; it uuid; e text; li public.invoice_items;
begin
  perform pg_temp.as_user('o');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('foc') || pg_temp.manual(5)));
  perform pg_temp.check(r->>'err' ~ 'A line can be FOC or have a discount, not both\. Choose one for "L384 Lamp"',
    'L3 FOC and a manual discount on one line are refused when made: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('foc') || pg_temp.opt('voucher')));
  perform pg_temp.check(r->>'err' ~ 'not both', 'L3 FOC and a voucher on one line are refused when made: ' || coalesce(r->>'err', 'saved'));

  -- A discounted line becomes FOC in a correction, and back.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(30)))->>'id')::uuid;
  it := pg_temp.item(inv);
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('foc_quantity', 1, 'foc_reason', 'Test goodwill')));
  perform pg_temp.check(e ~ 'not both', 'L3 a correction adding FOC beside the discount is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('foc_quantity', 1, 'foc_reason', 'Test goodwill',
         'line_discount_type', null, 'line_discount_amount', null, 'line_discount_reason', null)));
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.foc_quantity = 1 and li.line_discount_type is null and li.line_discount = 0
      and li.line_discount_reason is null and li.line_discount_by is null and li.line_total = 100
      and (pg_temp.inv(inv)).total_amount = 100,
    'L3 picking FOC instead takes the discount off the line: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('foc_quantity', null, 'foc_reason', null) || pg_temp.pct(25)));
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.foc_quantity = 0 and li.foc_amount = 0 and li.line_discount_type = 'percentage'
      and li.line_discount = 50 and (pg_temp.inv(inv)).total_amount = 150,
    'L3 and back to a discount (25% of S$200): ' || coalesce(e, 'saved'));

  -- Make FOC on a discounted line, and on a line voucher saved before 384.
  begin perform public.apply_line_foc(it, 1, null, 'Test goodwill'); e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.check(e ~ 'already has a discount\. A line can be FOC or have a discount, not both',
    'L3 Make FOC refuses a discounted line: ' || coalesce(e, 'made FOC'));
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('voucher')))->>'id')::uuid;
  it := pg_temp.item(inv);
  update public.invoice_items set line_discount_type = null where id = it;   -- as saved before 384
  begin perform public.apply_line_foc(it, 1, null, 'Test goodwill'); e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.check(e ~ 'already has a discount', 'L3 Make FOC refuses a line voucher saved before 384: ' || coalesce(e, 'made FOC'));

  -- A line saved before 384 with FOC and a voucher (1 of 2 free, 10% off the
  -- other): kept as it is when sent back unchanged.
  update public.invoice_items set foc_quantity = 1, foc_amount = 100, foc_reason = 'Old goodwill', line_total = 100,
         foc_original_unit_price = 100, line_discount = 10 where id = it;
  perform public.recalc_invoice_foc(inv);
  perform pg_temp.check((pg_temp.inv(inv)).total_amount = 90, 'L3 fixture: the old line is S$100 with S$10 off');
  e := pg_temp.fix(inv, pg_temp.lines(inv) || jsonb_build_array(pg_temp.ln('own2')));
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.foc_quantity = 1 and li.line_voucher_id = pg_temp.fx('v10') and li.line_discount = 10
      and li.line_discount_type is null and (pg_temp.inv(inv)).total_amount = 123.33,
    'L3 a line saved before 384 with FOC and a voucher is kept untouched when sent back unchanged: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('quantity', 3)));
  perform pg_temp.check(e ~ 'not both', 'L3 changing it without picking one is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('quantity', 3, 'foc_quantity', null, 'foc_reason', null,
         'line_discount_type', 'voucher')));
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.foc_quantity = 0 and li.line_discount_type = 'voucher' and li.line_discount = 30
      and li.line_total = 300,
    'L3 changing it and keeping the voucher saves it as a Voucher line (10% of S$300): ' || coalesce(e, 'saved'));

  -- Undo FOC on an old FOC-and-voucher line keeps the voucher, worked out again.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('voucher')))->>'id')::uuid;
  it := pg_temp.item(inv);
  update public.invoice_items set line_discount_type = null, foc_quantity = 1, foc_amount = 100, foc_reason = 'Old goodwill',
         line_total = 100, foc_original_unit_price = 100, line_discount = 10 where id = it;
  perform public.recalc_invoice_foc(inv);
  perform public.remove_line_foc(it, 'Not free after all');
  li := pg_temp.li(it);
  perform pg_temp.check(li.foc_quantity = 0 and li.line_discount = 20 and li.line_voucher_id = pg_temp.fx('v10')
      and (pg_temp.inv(inv)).total_amount = 180,
    'L3 Undo FOC on an old FOC-and-voucher line leaves its voucher, on the full value');
  insert into fx values ('legacy_inv', inv);
end $$;

-- ═════ L4 Birthday ═════
do $$
declare r jsonb; c uuid; a uuid; b uuid; d uuid; it uuid; e text; mo date; ano text;
begin
  perform pg_temp.as_user('o');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r->>'err' = 'Add the customer''s date of birth to give a Birthday discount.',
    'L4 no date of birth: ' || coalesce(r->>'err', 'saved'));
  -- On the day: tomorrow's birthday is refused today.
  c := pg_temp.customer(make_date(1984, extract(month from public.sg_today() + 1)::int, extract(day from public.sg_today() + 1)::int));
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r->>'err' ~ '"L384 Birthday Day" is for the customer''s birthday only \(.*\)\. This invoice is dated ',
    'L4 "on the birthday" only on the day: ' || coalesce(r->>'err', 'saved'));
  -- In the month: any day of it, not another month.
  c := pg_temp.customer(make_date(1985, extract(month from public.sg_today())::int, 1));
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_month')));
  perform pg_temp.check(r ? 'id' and (select line_discount from public.invoice_items where invoice_id = (r->>'id')::uuid) = 20,
    'L4 "in the birth month" on another day of the month: ' || coalesce(r->>'err', '10% given'));
  mo := public.sg_today() + 45;
  c := pg_temp.customer(make_date(1985, extract(month from mo)::int, 1));
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_month')));
  perform pg_temp.check(r->>'err' ~ 'is for the customer''s birth month only',
    'L4 not in another month: ' || coalesce(r->>'err', 'saved'));

  -- 29 Feb: on 28 Feb in a year without one, on 29 Feb in a leap year.
  c := pg_temp.customer(date '1992-02-29');
  perform public.invoice_birthday_check(c, date '2027-02-28', null, pg_temp.fx('bday_day'));
  perform pg_temp.check(true, 'L4 born 29 Feb: the birthday is 28 Feb in 2027');
  begin perform public.invoice_birthday_check(c, date '2027-03-01', null, pg_temp.fx('bday_day')); e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.check(e ~ 'birthday only \(28 Feb\)', 'L4 and not 1 Mar 2027: ' || coalesce(e, 'given'));
  perform public.invoice_birthday_check(c, date '2028-02-29', null, pg_temp.fx('bday_day'));
  begin perform public.invoice_birthday_check(c, date '2028-02-28', null, pg_temp.fx('bday_day')); e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.check(e ~ 'birthday only \(29 Feb\)', 'L4 in 2028 it is 29 Feb, not 28 Feb: ' || coalesce(e, 'given'));

  -- Once a year: several birthday lines on one invoice are one use.
  c := pg_temp.customer(make_date(1980, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int));
  a := (pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day'), pg_temp.ln('own2') || pg_temp.bday('bday_day')))->>'id')::uuid;
  perform pg_temp.check(a is not null and (pg_temp.inv(a)).discount_total = 46.67,
    'L4 two birthday lines on one invoice (20% of S$200 and of S$33.33)');
  select invoice_no into ano from public.invoices where id = a;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_month')));
  perform pg_temp.check(r->>'err' = 'Birthday discount already used this year on ' || ano || '.',
    'L4 a second birthday invoice this year is refused, naming the first: ' || coalesce(r->>'err', 'saved'));
  -- The same invoice, edited, does not count against itself.
  it := pg_temp.item(a);
  e := pg_temp.fix(a, pg_temp.patch(a, it, jsonb_build_object('quantity', 3)) || jsonb_build_array(pg_temp.ln('own2') || pg_temp.bday('bday_day')));
  perform pg_temp.check(e is null and (select count(*) from public.invoice_items where invoice_id = a and line_discount_type = 'birthday') = 3,
    'L4 an edit of that invoice may change and add birthday lines: ' || coalesce(e, 'saved'));
  -- Cancelled, refunded and deleted invoices do not count.
  update public.invoices set status = 'cancelled' where id = a;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r ? 'id', 'L4 a cancelled birthday invoice does not count: ' || coalesce(r->>'err', 'saved'));
  b := (r->>'id')::uuid;
  update public.invoices set status = 'refunded' where id = b;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r ? 'id', 'L4 nor a refunded one: ' || coalesce(r->>'err', 'saved'));
  d := (r->>'id')::uuid;
  update public.invoices set deleted_at = now() where id = d;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r ? 'id', 'L4 nor a deleted one: ' || coalesce(r->>'err', 'saved'));
  d := (r->>'id')::uuid;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r->>'err' ~ 'already used this year on', 'L4 the one that stands counts again: ' || coalesce(r->>'err', 'saved'));
  -- Last year's does not count.
  update public.invoices set business_date = business_date - interval '1 year' where id = d;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r ? 'id', 'L4 last year''s birthday invoice does not count this year: ' || coalesce(r->>'err', 'saved'));

  -- A birthday line saved before 384 counts, and so does an invoice-level Birthday voucher.
  c := pg_temp.customer(make_date(1976, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int));
  a := (pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')))->>'id')::uuid;
  update public.invoice_items set line_discount_type = null where invoice_id = a;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(r->>'err' ~ 'already used this year on', 'L4 a birthday line saved before 384 counts: ' || coalesce(r->>'err', 'saved'));
  -- An older invoice with no business date counts by the Singapore day it was made.
  c := pg_temp.customer(make_date(1974, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int));
  a := (pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')))->>'id')::uuid;
  update public.invoices set business_date = null where id = a;
  select invoice_no into ano from public.invoices where id = a;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check((select business_date from public.invoices where id = a) is null
                        and r->>'err' = 'Birthday discount already used this year on ' || ano || '.',
    'L4 an invoice with no business date counts by the day it was made: ' || coalesce(r->>'err', 'saved'));
  c := pg_temp.customer(make_date(1972, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int));
  a := (pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own')), jsonb_build_object('discount_voucher_id', pg_temp.fx('bday_month')))->>'id')::uuid;
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')));
  perform pg_temp.check(a is not null and r->>'err' ~ 'already used this year on',
    'L4 an invoice whose own discount voucher is a Birthday voucher counts: ' || coalesce(r->>'err', 'saved'));

  -- A correction to another customer or date checks it again.
  c := pg_temp.customer(make_date(1968, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int));
  a := (pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')))->>'id')::uuid;
  e := pg_temp.fix(a, pg_temp.lines(a), jsonb_build_object('customer_id', pg_temp.fx('nodob')));
  perform pg_temp.check(e = 'Add the customer''s date of birth to give a Birthday discount.'
      and (pg_temp.inv(a)).customer_id = c, 'L4 moving a birthday invoice to a customer with no date of birth is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(a, pg_temp.lines(a), jsonb_build_object('business_date', (public.sg_today() - 1)::text));
  perform pg_temp.check(e ~ 'birthday only', 'L4 moving it off the birthday is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(a, pg_temp.lines(a), jsonb_build_object('customer_id', pg_temp.customer(make_date(1964, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int))));
  perform pg_temp.check(e is null, 'L4 moving it to another customer born today is saved: ' || coalesce(e, 'saved'));

  -- Staff: no question about the customer.
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('staff')));
  perform pg_temp.check(r ? 'id', 'L4 a Staff discount for a customer who is not staff: ' || coalesce(r->>'err', 'saved'));
end $$;

-- ═════ L5 Bounds, rounding and the reason ═════
do $$
declare r jsonb; li public.invoice_items; e text; it uuid;
begin
  perform pg_temp.as_user('o');
  foreach e in array array['0','-5','100.0001','101','0.0004'] loop
    r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.pct(e::numeric)));
    perform pg_temp.check(r->>'err' = 'The percentage discount on "L384 Lamp" must be more than 0% and at most 100%.',
      format('L5 a %s%% discount is refused: %s', e, coalesce(r->>'err', 'saved')));
  end loop;
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.pct(100)));
  perform pg_temp.check((pg_temp.inv((r->>'id')::uuid)).total_amount = 0, 'L5 100% is the whole line: ' || coalesce(r->>'err', 'S$0 to pay'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('line_discount_type','percentage','line_discount_reason','x')));
  perform pg_temp.check(r->>'err' ~ 'must be more than 0% and at most 100%', 'L5 a percentage needs its number: ' || coalesce(r->>'err', 'saved'));
  -- Rounding: 15% of S$33.33 is 4.9995, so 5.00; 12.5% of 3 x 33.33 is 12.49875, so 12.50; a percentage keeps 3 decimals.
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own2'),'quantity',1) || pg_temp.pct(15)));
  perform pg_temp.check((select line_discount from public.invoice_items where invoice_id = (r->>'id')::uuid) = 5.00, 'L5 15% of S$33.33 is S$5.00');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own2'),'quantity',3) || pg_temp.pct(12.5)));
  perform pg_temp.check((select line_discount from public.invoice_items where invoice_id = (r->>'id')::uuid) = 12.50
      and (pg_temp.inv((r->>'id')::uuid)).total_amount = 87.49, 'L5 12.5% of 3 x S$33.33 is S$12.50, leaving S$87.49');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.pct(12.3456)));
  select * into li from public.invoice_items where invoice_id = (r->>'id')::uuid;
  perform pg_temp.check(li.line_discount_percent = 12.346 and li.line_discount = 24.69, 'L5 12.3456% is kept as 12.346%, S$24.69 off S$200');
  -- Manual: more than S$0 and at most the line's value, to the cent.
  foreach e in array array['0','-1','0.004'] loop
    r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(e::numeric)));
    perform pg_temp.check(r->>'err' = 'Enter the discount on "L384 Lamp" in S$ (more than 0).',
      format('L5 a manual S$%s is refused: %s', e, coalesce(r->>'err', 'saved')));
  end loop;
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(200.01)));
  perform pg_temp.check(r->>'err' = 'The discount on "L384 Lamp" (S$200.01) cannot be more than the line''s value (S$200.00).',
    'L5 more than the line is refused: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(200)));
  perform pg_temp.check((pg_temp.inv((r->>'id')::uuid)).total_amount = 0, 'L5 the whole line is allowed: ' || coalesce(r->>'err', 'S$0 to pay'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(12.345)));
  perform pg_temp.check((select line_discount from public.invoice_items where invoice_id = (r->>'id')::uuid) = 12.35, 'L5 S$12.345 is S$12.35');
  -- The reason: required for both, whitespace is none, kept trimmed.
  foreach e in array array['manual','percentage'] loop
    r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || case e when 'manual' then pg_temp.manual(5, '   ') else pg_temp.pct(5, '') end));
    perform pg_temp.check(r->>'err' = 'Give the reason for the discount on "L384 Lamp". It stays on the invoice for staff and is never printed.',
      format('L5 a %s discount needs a reason: %s', e, coalesce(r->>'err', 'saved')));
  end loop;
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(5, '  Display model  ')));
  it := pg_temp.item((r->>'id')::uuid);
  perform pg_temp.check((pg_temp.li(it)).line_discount_reason = 'Display model', 'L5 the reason is kept trimmed');
  -- The reason trigger, for any other path.
  begin update public.invoice_items set line_discount_reason = ' ' where id = it; e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'Give the reason for the line discount. It stays on the invoice for staff and is never printed.',
    'L5 the trigger refuses a manual discount with no reason: ' || coalesce(e, 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('voucher') || jsonb_build_object('line_discount_reason', 'ignored')));
  perform pg_temp.check((select line_discount_reason from public.invoice_items where invoice_id = (r->>'id')::uuid) is null,
    'L5 a voucher line keeps no reason');
  begin update public.invoice_items set foc_quantity = 1 where id = it; e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.check(e ~ 'invoice_items_line_discount_or_foc', 'L5 the table refuses FOC beside a discount: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L6 Who ═════
do $$
declare r jsonb; inv uuid; it uuid; e text; li public.invoice_items;
begin
  perform pg_temp.as_user('im');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('voucher')));
  perform pg_temp.check(r->>'err' = 'Inventory Manager cannot give a voucher, Birthday or Staff discount',
    'L6 an Inventory Manager may not give a voucher: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('foc')));
  perform pg_temp.check(r->>'err' = 'Inventory Manager cannot apply FOC', 'L6 nor FOC (as before): ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(10), pg_temp.ln('third') || pg_temp.pct(10)));
  perform pg_temp.check(r ? 'id' and (pg_temp.inv((r->>'id')::uuid)).discount_total = 15,
    'L6 but may give manual and percentage discounts: ' || coalesce(r->>'err', 'saved'));

  -- Staff correct a paid invoice of their store (377) with the new options.
  perform pg_temp.as_user('o');
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(20, 'Owner said so')))->>'id')::uuid;
  perform pg_temp.pay(inv);
  it := pg_temp.item(inv);
  perform pg_temp.as_user('s');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('quantity', 3)), '{}'::jsonb, 'Customer took a third');
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.quantity = 3 and li.line_discount = 20 and li.line_discount_by = pg_temp.fx('o'),
    'L6 staff change the quantity of a discounted line on a paid invoice; the discount keeps who gave it: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, pg_temp.pct(10, 'Loyalty')), '{}'::jsonb, 'Percentage instead');
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.line_discount_type = 'percentage' and li.line_discount = 30 and li.line_discount_by = pg_temp.fx('s')
      and (pg_temp.inv(inv)).total_amount = 270 and (pg_temp.inv(inv)).edit_count = 2,
    'L6 staff give a percentage discount in a correction, now theirs: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('line_discount_type', 'staff', 'line_voucher_id', pg_temp.fx('staff50'),
         'line_discount_percent', null, 'line_discount_reason', null)), '{}'::jsonb, 'Staff purchase');
  perform pg_temp.check(e is null and (pg_temp.li(it)).line_discount = 150, 'L6 and a Staff discount: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L7 A line voucher with no option ═════
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('o');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('line_voucher_id', pg_temp.fx('staff50'))));
  perform pg_temp.check((select line_discount_type from public.invoice_items where invoice_id = (r->>'id')::uuid) = 'staff',
    'L7 a line voucher sent with no option is its voucher''s list (Staff): ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('line_voucher_id', pg_temp.fx('bday_day'))));
  perform pg_temp.check(r->>'err' ~ 'date of birth', 'L7 and a Birthday voucher sent that way is checked as one: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('line_discount_type','staff','line_voucher_id', pg_temp.fx('bday_day'))));
  perform pg_temp.check(r->>'err' = '"L384 Birthday Day" is not on the Staff discount list. Choose one from that list.',
    'L7 an option that is not the voucher''s list is refused: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('line_discount_type','voucher')));
  perform pg_temp.check(r->>'err' = 'Choose which voucher to use on "L384 Lamp".', 'L7 a voucher option needs its voucher: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('line_discount_type','loyalty')));
  perform pg_temp.check(r->>'err' = 'Choose the line''s discount from the list.', 'L7 an unknown option is refused: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('line_discount_type','voucher','line_voucher_id',pg_temp.fx('gift'))));
  perform pg_temp.check(r->>'err' = 'Voucher "L384 Gift 40" is not a discount voucher', 'L7 a sold voucher is no discount: ' || coalesce(r->>'err', 'saved'));
end $$;

-- ═════ L8 A Discount alone moves no stock ═════
do $$
declare inv uuid; it uuid; e text; q0 int; m0 int;
begin
  perform pg_temp.as_user('o');
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own')))->>'id')::uuid;
  perform pg_temp.pay(inv);
  it := pg_temp.item(inv);
  select current_qty into q0 from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx('own');
  select count(*) into m0 from public.stock_movements where invoice_id = inv;
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, pg_temp.manual(25)), '{}'::jsonb, 'Forgot the discount');
  perform pg_temp.check(e is null and (pg_temp.inv(inv)).total_amount = 175
      and (select current_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx('own')) = q0
      and (select count(*) from public.stock_movements where invoice_id = inv) = m0
      and exists (select 1 from public.invoice_revisions where invoice_id = inv),
    'L8 a discount given in a correction is a revision, and moves no stock: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L9 The invoice voucher adds up the same way after an edit ═════
do $$
declare inv uuid; it uuid; e text;
begin
  perform pg_temp.as_user('o');
  -- Subtotal 100, manual 20, a 10% invoice voucher: 8 off when made.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',1)),
          jsonb_build_object('manual_discount', 20, 'manual_discount_reason', 'Price match', 'discount_voucher_id', pg_temp.fx('v10')))->>'id')::uuid;
  perform pg_temp.check((pg_temp.inv(inv)).discount_total = 28, 'L9 made: S$20 manual and S$8 voucher');
  it := pg_temp.item(inv);
  e := pg_temp.fix(inv, pg_temp.lines(inv) || jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own2'),'quantity',1,
         'foc_quantity',1,'foc_reason','Test goodwill')), jsonb_build_object('manual_discount', 20, 'discount_voucher_id', pg_temp.fx('v10')));
  perform pg_temp.check(e is null and (pg_temp.inv(inv)).discount_total = 28 and (pg_temp.inv(inv)).total_amount = 72,
    'L9 after an edit (a free line added) still S$8 voucher, S$28 in all: ' || coalesce(e, 'saved') || ' / ' || (pg_temp.inv(inv)).discount_total);
  perform public.apply_line_foc((select id from public.invoice_items where invoice_id = inv and product_id = pg_temp.fx('own2')), 1, null, 'Still free');
  perform pg_temp.check((pg_temp.inv(inv)).discount_total = 28, 'L9 after an FOC change still S$28: ' || (pg_temp.inv(inv)).discount_total);
  -- With third-party value: S$100 own + S$50 third-party, manual 20, 10%:
  -- the voucher is on 100 - 20 = 80, so 8.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',1), pg_temp.ln('third')),
          jsonb_build_object('manual_discount', 20, 'manual_discount_reason', 'Price match', 'discount_voucher_id', pg_temp.fx('v10')))->>'id')::uuid;
  perform pg_temp.check((pg_temp.inv(inv)).discount_total = 28, 'L9 with third-party value, made: S$28');
  e := pg_temp.fix(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'note', 'manual_discount', 20, 'discount_voucher_id', pg_temp.fx('v10'),
         'service_staff', jsonb_build_array(pg_temp.fx('s'))));
  perform pg_temp.check(e is null and (pg_temp.inv(inv)).discount_total = 28,
    'L9 and after an edit: S$28 (it was S$35 before 384): ' || coalesce(e, 'saved') || ' / ' || (pg_temp.inv(inv)).discount_total);
  -- A line discount on a third-party line is not taken off the voucher's base.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',1),
            pg_temp.ln('third') || pg_temp.manual(10)), jsonb_build_object('discount_voucher_id', pg_temp.fx('v10')))->>'id')::uuid;
  perform pg_temp.check((pg_temp.inv(inv)).discount_total = 20, 'L9 a manual S$10 on the third-party line leaves the voucher at S$10 (made)');
  e := pg_temp.fix(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'note 2', 'discount_voucher_id', pg_temp.fx('v10'), 'service_staff', jsonb_build_array(pg_temp.fx('o'))));
  perform pg_temp.check(e is null and (pg_temp.inv(inv)).discount_total = 20, 'L9 and after an edit: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L10 Special product and rental lines keep their FOC ═════
do $$
declare inv uuid; e text; sp uuid; rn uuid;
begin
  perform pg_temp.as_user('o');
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(
            pg_temp.ln('special') || jsonb_build_object('quantity', 2, 'foc_quantity', 1, 'foc_reason', 'Test goodwill'),
            pg_temp.ln('rental') || pg_temp.opt('foc'), pg_temp.ln('own')))->>'id')::uuid;
  sp := pg_temp.item(inv, 'special_product'); rn := pg_temp.item(inv, 'rental');
  perform pg_temp.check((pg_temp.li(sp)).foc_quantity = 1 and (pg_temp.li(sp)).foc_amount = 500 and (pg_temp.li(sp)).line_total = 500
      and (pg_temp.li(rn)).foc_quantity = 1 and (pg_temp.li(rn)).line_total = 0
      and (pg_temp.inv(inv)).subtotal = 700 and (pg_temp.inv(inv)).foc_total = 540,
    'L10 made: the special line has 1 of 2 free, the rental is free, and the subtotal is what the lines say');
  e := pg_temp.fix(inv, pg_temp.patch(inv, pg_temp.item(inv), jsonb_build_object('quantity', 1)));
  perform pg_temp.check(e is null and (pg_temp.li(sp)).foc_quantity = 1 and (pg_temp.li(rn)).foc_quantity = 1
      and (pg_temp.inv(inv)).subtotal = 600 and (pg_temp.inv(inv)).total_amount = 600,
    'L10 an edit of another line keeps them: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, sp, jsonb_build_object('quantity', 3)));
  perform pg_temp.check(e is null and (pg_temp.li(sp)).foc_quantity = 1 and (pg_temp.li(sp)).line_total = 1000
      and (pg_temp.inv(inv)).subtotal = 1100,
    'L10 an edit of the special line itself keeps its FOC: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, rn, jsonb_build_object('rental_periods', 3, 'unit_price', null)));
  perform pg_temp.check(e is null and (pg_temp.li(rn)).foc_quantity = 1 and (pg_temp.li(rn)).foc_amount = 60 and (pg_temp.li(rn)).line_total = 0,
    'L10 and of the rental: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L11 Confirm FOC reprices a percentage line with its value ═════
do $$
declare inv uuid; r jsonb; it uuid;
begin
  perform pg_temp.as_user('o');
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || jsonb_build_object('foc_quantity', 2, 'foc_reason', 'Test goodwill'),
            jsonb_build_object('kind','product','product_id',pg_temp.fx('own2'),'quantity',1) || pg_temp.pct(100)))->>'id')::uuid;
  it := (select id from public.invoice_items where invoice_id = inv and product_id = pg_temp.fx('own2'));
  perform pg_temp.check((pg_temp.inv(inv)).total_amount = 0 and (pg_temp.inv(inv)).has_foc, 'L11 fixture: an FOC line and a 100% line, nothing to pay');
  perform set_product_prices(pg_temp.fx('A'), pg_temp.fx('own2'), 40, 40, 'available');
  r := public.confirm_foc_invoice(inv, null);
  perform pg_temp.check((r->>'review_required')::boolean and (pg_temp.li(it)).line_total = 40 and (pg_temp.li(it)).line_discount = 40
      and (pg_temp.inv(inv)).total_amount = 0,
    'L11 the new price is shown for review and the 100% discount follows it (S$40 off S$40)');
  perform set_product_prices(pg_temp.fx('A'), pg_temp.fx('own2'), 33.33, 33.33, 'available');
end $$;

-- ═════ L12 The Discounts report ═════
do $$
declare a uuid; b uuid; c uuid; x record; ex uuid;
begin
  perform pg_temp.as_user('o');
  -- One of each option on one invoice, with a manual discount and an invoice voucher.
  a := (pg_temp.mk(pg_temp.customer(make_date(1960, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int)),
         jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('voucher'), pg_temp.ln('own') || pg_temp.bday('bday_day'),
           pg_temp.ln('own') || pg_temp.opt('staff'), pg_temp.ln('third') || pg_temp.manual(5), pg_temp.ln('own') || pg_temp.pct(25),
           pg_temp.ln('own') || pg_temp.opt('foc')),
         jsonb_build_object('manual_discount', 10, 'manual_discount_reason', 'Opening day', 'discount_voucher_id', pg_temp.fx('v15')))->>'id')::uuid;
  perform pg_temp.pay(a);
  select * into x from public.report_discounts() where invoice_id = a;
  perform pg_temp.check(x.line_voucher_discount = 20 and x.birthday_discount = 40 and x.staff_discount = 100
      and x.line_manual_discount = 5 and x.line_percentage_discount = 50 and x.exchange_credit = 0
      and x.manual_discount = 10 and x.voucher_discount = 15 and x.line_discount = 215
      and x.total_discount = x.line_voucher_discount + x.birthday_discount + x.staff_discount + x.line_manual_discount
                             + x.line_percentage_discount + x.exchange_credit + x.manual_discount + x.voucher_discount + x.save_earth,
    format('L12 a column per option, and they add up to the total (%s)', row_to_json(x)));
  -- Saved before 384: a line voucher counts under its voucher's list; a
  -- discount with neither (exchange credit) on its own.
  b := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('staff'), pg_temp.ln('own') || pg_temp.opt('voucher'),
         pg_temp.ln('own')))->>'id')::uuid;
  update public.invoice_items set line_discount_type = null where invoice_id = b;
  ex := (select id from public.invoice_items where invoice_id = b and line_voucher_id is null);
  update public.invoice_items set line_discount = 12 where id = ex;
  perform public.refresh_invoice_discount_total(b);
  update public.invoices set total_amount = subtotal - discount_total where id = b;
  perform pg_temp.pay(b);
  select * into x from public.report_discounts() where invoice_id = b;
  perform pg_temp.check(x.staff_discount = 100 and x.line_voucher_discount = 20 and x.exchange_credit = 12
      and x.line_manual_discount = 0 and x.total_discount = 132,
    format('L12 lines saved before 384 count under their voucher''s list, exchange credit on its own (%s)', row_to_json(x)));
end $$;

-- ═════ L13 An Owner corrects only the price of a discounted therapy session ═════
do $$
declare inv uuid; it uuid; e text; li public.invoice_items;
begin
  perform pg_temp.as_user('o');
  -- Two sessions at S$30 with 10% (S$6), corrected to S$50 each: 10% of S$100.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('session') || jsonb_build_object('quantity', 2) || pg_temp.pct(10)))->>'id')::uuid;
  it := pg_temp.item(inv, 'therapy');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('unit_price', 50)));
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.unit_price = 50 and li.line_total = 100 and li.line_discount = 10
      and li.line_discount_percent = 10 and (pg_temp.inv(inv)).total_amount = 90,
    format('L13 a percentage follows a corrected session price (10%% of S$100, S$90 to pay): %s; got S$%s off, S$%s to pay',
      coalesce(e, 'saved'), li.line_discount, (pg_temp.inv(inv)).total_amount));
  -- 50% of S$30, corrected to S$20.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('session') || pg_temp.pct(50)))->>'id')::uuid;
  it := pg_temp.item(inv, 'therapy');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('unit_price', 20)));
  perform pg_temp.check(e is null and (pg_temp.li(it)).line_discount = 10 and (pg_temp.inv(inv)).total_amount = 10,
    'L13 and when the price goes down (50% of S$20): ' || coalesce(e, 'saved'));
  -- A manual S$25 cannot stay on a session corrected to S$20.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('session') || pg_temp.manual(25)))->>'id')::uuid;
  it := pg_temp.item(inv, 'therapy');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('unit_price', 20)));
  perform pg_temp.check(e = 'The discount on "L384 Session" (S$25.00) cannot be more than the line''s value (S$20.00).'
      and (pg_temp.li(it)).unit_price = 30 and (pg_temp.li(it)).line_discount = 25,
    'L13 a manual discount above the corrected price is refused: ' || coalesce(e, 'saved'));
  -- A manual S$10 stays, with who gave it.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('session') || pg_temp.manual(10)))->>'id')::uuid;
  it := pg_temp.item(inv, 'therapy');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('unit_price', 20)));
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.line_total = 20 and li.line_discount = 10 and li.line_discount_type = 'manual'
      and li.line_discount_by = pg_temp.fx('o') and (pg_temp.inv(inv)).total_amount = 10,
    'L13 a manual discount within the corrected price stays: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L14 A Discount given in a correction to a line that could not be sold again today ═════
do $$
declare inv uuid; it uuid; e text; ent uuid; m0 int; li public.invoice_items;
begin
  perform pg_temp.as_user('o');
  -- A paid therapy package (its therapy issued on payment), then 10% off.
  inv := (pg_temp.mk(pg_temp.customer(null), jsonb_build_array(pg_temp.ln('package')))->>'id')::uuid;
  perform pg_temp.pay(inv);
  it := pg_temp.item(inv, 'therapy');
  select id into ent from public.purchased_therapy_entitlements where invoice_item_id = it and status not in ('cancelled','refunded');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, pg_temp.pct(10)), '{}'::jsonb, 'Forgot the loyalty discount');
  perform pg_temp.check(e is null and ent is not null and (pg_temp.li(it)).line_discount = 15 and (pg_temp.inv(inv)).total_amount = 135
      and (select array_agg(id) from public.purchased_therapy_entitlements where invoice_item_id = it and status not in ('cancelled','refunded')) = array[ent],
    'L14 10% on a paid therapy package keeps its therapy as it is: ' || coalesce(e, 'saved'));
  -- A paid promotion that has since ended: S$5 off, and no stock moves.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('promotion')))->>'id')::uuid;
  perform pg_temp.pay(inv);
  it := pg_temp.item(inv, 'promotion');
  update public.promotions set end_date = public.sg_today() - 1 where id = pg_temp.fx('promo');
  select count(*) into m0 from public.stock_movements where invoice_id = inv;
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, pg_temp.manual(5)));
  perform pg_temp.check(e is null and (pg_temp.li(it)).line_discount = 5 and (pg_temp.inv(inv)).total_amount = 75
      and (select count(*) from public.stock_movements where invoice_id = inv) = m0,
    'L14 S$5 off a paid promotion that has since ended: ' || coalesce(e, 'saved'));
  -- Changing more than its Discount sells it again, refused as before.
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('quantity', 2) || pg_temp.manual(5)));
  perform pg_temp.check(e ~ 'has ended', 'L14 but a quantity change on it is still refused: ' || coalesce(e, 'saved'));
  update public.promotions set end_date = null where id = pg_temp.fx('promo');
  -- A promotion with a pick (one Kettle): the pick stays with the line.
  insert into public.promotions(name,code,promo_type,fixed_price) values('L384 Pick Promo','L384PP'||gen_random_uuid(),'bundle',90)
    returning id into it;
  insert into fx values ('pick_promo', it);
  insert into public.promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(it,pg_temp.fx('A'),90,true);
  insert into public.promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values(it,'Pick one','product',1) returning id into it;
  insert into fx values ('pick_group', it);
  insert into public.promotion_choice_options(group_id,product_id) values(it,pg_temp.fx('own2'));
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('pick_promo'),'quantity',1,
           'selections',jsonb_build_array(jsonb_build_object('group_id',pg_temp.fx('pick_group'),
             'options',jsonb_build_array(jsonb_build_object('product_id',pg_temp.fx('own2'),'quantity',1)))))))->>'id')::uuid;
  perform pg_temp.pay(inv);
  it := pg_temp.item(inv, 'promotion');
  e := pg_temp.fix(inv, (select jsonb_agg(x || jsonb_build_object('selections', jsonb_build_array(jsonb_build_object('group_id',pg_temp.fx('pick_group'),
           'options',jsonb_build_array(jsonb_build_object('product_id',pg_temp.fx('own2'),'quantity',1))))) || pg_temp.manual(9))
         from jsonb_array_elements(pg_temp.lines(inv)) x));
  perform pg_temp.check(e is null and (pg_temp.li(it)).line_discount = 9
      and (select count(*) from public.invoice_promotion_selections where invoice_item_id = it and product_id = pg_temp.fx('own2')) = 1,
    'L14 S$9 off a promotion line keeps its pick: ' || coalesce(e, 'saved'));
  -- A ticket line keeps its person, renamed in the same correction.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('ticket')))->>'id')::uuid;
  it := pg_temp.item(inv, 'event_ticket');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, pg_temp.pct(10) || jsonb_build_object('attendees', jsonb_build_array(
         jsonb_build_object('guest_id', (select id from public.event_guests where invoice_item_id = it), 'name', 'Test Guest Renamed')))));
  perform pg_temp.check(e is null and (pg_temp.li(it)).line_discount = 6
      and (select string_agg(name, ',') from public.event_guests where invoice_item_id = it and status = 'registered') = 'Test Guest Renamed',
    'L14 10% on a ticket line keeps its person on the guest list, renamed with it: ' || coalesce(e, 'saved'));
  -- A line saved before 384 with FOC and a voucher: taking the voucher off alone keeps its FOC.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.opt('voucher')))->>'id')::uuid;
  it := pg_temp.item(inv);
  update public.invoice_items set line_discount_type = null, foc_quantity = 1, foc_amount = 100, foc_reason = 'Old goodwill',
         line_total = 100, foc_original_unit_price = 100, line_discount = 10 where id = it;
  perform public.recalc_invoice_foc(inv);
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('line_voucher_id', null)));
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.foc_quantity = 1 and li.foc_amount = 100 and li.line_voucher_id is null
      and li.line_discount = 0 and (pg_temp.inv(inv)).total_amount = 100,
    'L14 an old FOC-and-voucher line keeps its FOC when only the voucher is taken off: ' || coalesce(e, 'saved'));
  -- A new reason alone is a new Discount: now the corrector's, on a paid invoice.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(20, 'Owner said so')))->>'id')::uuid;
  perform pg_temp.pay(inv);
  it := pg_temp.item(inv);
  select count(*) into m0 from public.stock_movements where invoice_id = inv;
  perform pg_temp.as_user('s');
  e := pg_temp.fix(inv, pg_temp.patch(inv, it, jsonb_build_object('line_discount_reason', 'Dented box')), '{}'::jsonb, 'Better reason');
  li := pg_temp.li(it);
  perform pg_temp.check(e is null and li.line_discount_reason = 'Dented box' and li.line_discount = 20 and li.line_discount_by = pg_temp.fx('s')
      and (select count(*) from public.stock_movements where invoice_id = inv) = m0,
    'L14 staff change only the reason of a paid line''s discount: ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('o');
end $$;

-- ═════ L15 A Birthday voucher as the invoice's own discount voucher ═════
do $$
declare r jsonb; c uuid; a uuid; b uuid; e text;
begin
  perform pg_temp.as_user('o');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own')), jsonb_build_object('discount_voucher_id', pg_temp.fx('bday_day')));
  perform pg_temp.check(r->>'err' = 'Add the customer''s date of birth to give a Birthday discount.',
    'L15 no date of birth: ' || coalesce(r->>'err', 'saved'));
  c := pg_temp.customer(make_date(1958, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int));
  a := (pg_temp.mk(c, jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',1)),
          jsonb_build_object('discount_voucher_id', pg_temp.fx('bday_month')))->>'id')::uuid;
  perform pg_temp.check((pg_temp.inv(a)).discount_total = 10, 'L15 in the birth month: S$10 off S$100');
  r := pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own')), jsonb_build_object('discount_voucher_id', pg_temp.fx('bday_month')));
  perform pg_temp.check(r->>'err' = 'Birthday discount already used this year on ' || (pg_temp.inv(a)).invoice_no || '.',
    'L15 once a year: ' || coalesce(r->>'err', 'saved'));
  -- A correction that picks it is checked; one that keeps it (saved before 384) is not.
  b := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own')))->>'id')::uuid;
  e := pg_temp.fix(b, pg_temp.lines(b), jsonb_build_object('discount_voucher_id', pg_temp.fx('bday_day')));
  perform pg_temp.check(e = 'Add the customer''s date of birth to give a Birthday discount.' and (pg_temp.inv(b)).discount_voucher_id is null,
    'L15 picked in a correction: ' || coalesce(e, 'saved'));
  update public.invoices set discount_voucher_id = pg_temp.fx('bday_month') where id = b;
  e := pg_temp.fix(b, pg_temp.patch(b, pg_temp.item(b), jsonb_build_object('quantity', 3)), jsonb_build_object('discount_voucher_id', pg_temp.fx('bday_month')));
  perform pg_temp.check(e is null and (pg_temp.li(pg_temp.item(b))).quantity = 3,
    'L15 kept in a correction of an invoice saved before 384: ' || coalesce(e, 'saved'));
  -- Moved to another customer: checked again.
  e := pg_temp.fix(a, pg_temp.lines(a), jsonb_build_object('customer_id', pg_temp.fx('nodob')));
  perform pg_temp.check(e = 'Add the customer''s date of birth to give a Birthday discount.' and (pg_temp.inv(a)).customer_id = c,
    'L15 moved to a customer with no date of birth: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L16 A birthday line saved before 384 is checked again when its invoice moves ═════
do $$
declare c uuid; a uuid; e text;
begin
  perform pg_temp.as_user('o');
  c := pg_temp.customer(make_date(1946, extract(month from public.sg_today())::int, extract(day from public.sg_today())::int));
  a := (pg_temp.mk(c, jsonb_build_array(pg_temp.ln('own') || pg_temp.bday('bday_day')))->>'id')::uuid;
  update public.invoice_items set line_discount_type = null where invoice_id = a;   -- as saved before 384
  e := pg_temp.fix(a, (select jsonb_agg(x - 'line_discount_type') from jsonb_array_elements(pg_temp.lines(a)) x),
         jsonb_build_object('customer_id', pg_temp.fx('nodob')));
  perform pg_temp.check(e = 'Add the customer''s date of birth to give a Birthday discount.' and (pg_temp.inv(a)).customer_id = c,
    'L16 moved to a customer with no date of birth: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(a, (select jsonb_agg(x - 'line_discount_type') from jsonb_array_elements(pg_temp.lines(a)) x),
         jsonb_build_object('notes', 'Called the customer'));
  perform pg_temp.check(e is null, 'L16 a note on it is saved: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L17 A manual amount is kept to the cent, and its bounds hold for what is kept ═════
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('o');
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(200.004)));
  perform pg_temp.check(r ? 'id' and (select line_discount from public.invoice_items where invoice_id = (r->>'id')::uuid) = 200
      and (pg_temp.inv((r->>'id')::uuid)).total_amount = 0,
    'L17 S$200.004 on a S$200 line is S$200.00: ' || coalesce(r->>'err', 'saved'));
  r := pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(pg_temp.ln('own') || pg_temp.manual(200.005)));
  perform pg_temp.check(r->>'err' = 'The discount on "L384 Lamp" (S$200.01) cannot be more than the line''s value (S$200.00).',
    'L17 S$200.005 is S$200.01, more than the line: ' || coalesce(r->>'err', 'saved'));
end $$;

-- ═════ L18 A correction of notes, dates or payments leaves the money alone ═════
do $$
declare inv uuid; e text;
begin
  perform pg_temp.as_user('o');
  -- Edited before 384, when refresh_invoice_discount_total gave its 10% voucher
  -- S$10 rather than S$8, and paid at that.
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',1)),
          jsonb_build_object('manual_discount', 20, 'manual_discount_reason', 'Price match', 'discount_voucher_id', pg_temp.fx('v10')))->>'id')::uuid;
  update public.invoices set discount_total = 30, total_amount = 70 where id = inv;
  perform pg_temp.pay(inv);
  -- The screen sends the service staff with every correction.
  e := pg_temp.fix(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'Called the customer', 'service_staff', '[]'::jsonb), 'Note added');
  perform pg_temp.check(e is null and (pg_temp.inv(inv)).notes = 'Called the customer' and (pg_temp.inv(inv)).discount_total = 30
      and (pg_temp.inv(inv)).total_amount = 70 and (pg_temp.inv(inv)).status = 'paid',
    'L18 a note leaves an invoice edited before 384 at what was paid: ' || coalesce(e, 'saved'));
  -- A change of service staff goes through the money: the voucher as when made.
  e := pg_temp.fix(inv, pg_temp.lines(inv), jsonb_build_object('service_staff', jsonb_build_array(pg_temp.fx('s'))), 'Staff added');
  perform pg_temp.check(e is null and (pg_temp.inv(inv)).discount_total = 28 and (pg_temp.inv(inv)).total_amount = 72
      and (pg_temp.inv(inv)).status = 'partially_paid',
    'L18 a change of service staff works the voucher out as when made (S$8): ' || coalesce(e, 'saved'));
end $$;

-- ═════ L19 Special product FOC lost by an invoice saved before 384 ═════
do $$
declare inv uuid; sp uuid; e text;
begin
  perform pg_temp.as_user('o');
  inv := (pg_temp.mk(pg_temp.fx('nodob'), jsonb_build_array(
            pg_temp.ln('special') || jsonb_build_object('quantity', 2, 'foc_quantity', 1, 'foc_reason', 'Test goodwill'),
            jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',1)))->>'id')::uuid;
  sp := pg_temp.item(inv, 'special_product');
  -- As create_invoice saved it before 384: the FOC in the invoice's totals, not on the line.
  update public.invoice_items set foc_quantity = 0, is_foc = false, foc_amount = 0, foc_original_unit_price = null,
         foc_reason_id = null, foc_reason = null, foc_by = null, foc_at = null, line_total = 1000 where id = sp;
  perform pg_temp.pay(inv);
  perform pg_temp.check((pg_temp.inv(inv)).subtotal = 600 and (pg_temp.inv(inv)).foc_total = 500 and (pg_temp.inv(inv)).status = 'paid',
    'L19 fixture: S$600 paid, S$500 of FOC not on its line');
  e := pg_temp.fix(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'Delivered', 'service_staff', '[]'::jsonb));
  perform pg_temp.check(e is null and (pg_temp.inv(inv)).total_amount = 600 and (pg_temp.inv(inv)).status = 'paid',
    'L19 a note is saved and charges nothing again: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, pg_temp.item(inv), jsonb_build_object('quantity', 2)));
  perform pg_temp.check(e = 'S$500.00 of this invoice''s FOC was not saved on its special product or rental line, so this correction would charge it again. Give that line its FOC again in this correction, or ask the Owner to repair the invoice.'
      and (pg_temp.inv(inv)).total_amount = 600,
    'L19 a correction that would charge it again is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, pg_temp.patch(inv, sp, jsonb_build_object('foc_quantity', 1, 'foc_reason', 'Test goodwill')));
  perform pg_temp.check(e is null and (pg_temp.li(sp)).foc_quantity = 1 and (pg_temp.li(sp)).line_total = 500
      and (pg_temp.inv(inv)).subtotal = 600 and (pg_temp.inv(inv)).foc_total = 500 and (pg_temp.inv(inv)).status = 'paid',
    'L19 giving the line its FOC again in a correction repairs it: ' || coalesce(e, 'saved'));
end $$;

-- ═════ L20 Every invoice made here adds up ═════
select pg_temp.check(not exists (
    select 1 from public.invoices i where i.id in (select id from made) and (
      i.subtotal <> (select coalesce(sum(line_total), 0) from public.invoice_items where invoice_id = i.id)
      or i.total_amount <> greatest(0, i.subtotal - i.discount_total)
      or i.discount_total < (select coalesce(sum(line_discount), 0) from public.invoice_items where invoice_id = i.id)
      or i.foc_total <> (select coalesce(sum(foc_amount), 0) from public.invoice_items where invoice_id = i.id)
      or exists (select 1 from public.invoice_items ii where ii.invoice_id = i.id and ii.line_discount > ii.line_total))),
  'L20 every invoice made here: subtotal = its lines, total = subtotal - discounts, FOC = its lines, no line discount above its line');

-- ═════ L21 Running 384 again ═════
-- Only while 384's versions are installed: a later migration that patches the
-- same functions makes a second run refuse, by design. So does one that
-- patches a function 384 relies on unchanged: confirm_foc_invoice (387).
\set ON_ERROR_STOP off
select (select count(*) from pg_proc where oid = 'public.invoice_line_matches(uuid,jsonb)'::regprocedure
          and md5(prosrc) = '3b24939e07962d6ac3de82813bc3a83a') = 1
   and (select count(*) from pg_proc where oid = 'public.confirm_foc_invoice(uuid,text)'::regprocedure
          and md5(prosrc) = '50104e9fca42a618270c0d37ff05084f') = 1 as rerun \gset
\set ON_ERROR_STOP on
\if :rerun
create temp table before384 as
  select p.oid::regprocedure::text fn, md5(p.prosrc) h from pg_proc p where p.pronamespace = 'public'::regnamespace;
-- A discount voucher with no list, as every one was before 384.
alter table public.vouchers drop constraint vouchers_discount_category_check;
alter table public.vouchers disable trigger voucher_discount_category;
insert into public.vouchers(name,code,voucher_kind,discount_percent) values
  ('Birthday Treat - Actual Date (5 %)','L384R1'||gen_random_uuid(),'percentage_discount',5),
  ('Birthday Treat - Whole Month (5 %)','L384R2'||gen_random_uuid(),'percentage_discount',5),
  ('Birthday Treat (5 %)','L384R3'||gen_random_uuid(),'percentage_discount',5),
  ('Staff Test Rate (5%)','L384R4'||gen_random_uuid(),'percentage_discount',5),
  ('Test Twenty Off','L384R5'||gen_random_uuid(),'percentage_discount',5);
alter table public.vouchers enable trigger voucher_discount_category;
set client_min_messages = warning;
\ir ../../../supabase/385_invoice_line_discount_types.sql
reset client_min_messages;
select pg_temp.check(not exists (
    select 1 from pg_proc p full join before384 b on b.fn = p.oid::regprocedure::text
     where (p.pronamespace = 'public'::regnamespace or p.oid is null) and (b.h is distinct from md5(p.prosrc))),
  'L21 running 384 again changes no function');
select pg_temp.check(
  (select string_agg(name || '=' || coalesce(discount_category, '-') || '/' || coalesce(birthday_rule, '-'), '; ' order by left(code, 6))
     from public.vouchers where code like 'L384R%')
  = 'Birthday Treat - Actual Date (5 %)=birthday/actual_date; Birthday Treat - Whole Month (5 %)=birthday/whole_month; Birthday Treat (5 %)=voucher/-; Staff Test Rate (5%)=staff/-; Test Twenty Off=voucher/-',
  'L21 and fills each list from the name: "Birthday ... Actual Date" and "... Whole Month" with their rule, "Staff ..." is Staff, the rest are Vouchers');
\else
select pg_temp.check(true, 'L21 skipped: a later migration has replaced 384''s versions');
\endif

do $$ begin
  if exists (select 1 from failed) then
    raise exception 'FAIL: % check(s) failed: %', (select count(*) from failed), (select string_agg(msg, ' | ' order by n) from failed); end if;
  raise notice 'ALL PASS: one Discount per invoice line (384)';
end $$;
rollback;
