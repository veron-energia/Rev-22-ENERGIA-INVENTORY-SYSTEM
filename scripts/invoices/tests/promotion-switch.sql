-- A promotion line's choices belong to that promotion (416: INVOICES-CREATE-4,
-- INVOICES-CREATE-17, SALES-EXTRAS-9).
--
--   P1 Picks of another promotion's group, left over when a cashier switched
--      the line from one bundle to another, are refused on a new invoice.
--   P2 A group of another promotion sent with nothing picked writes nothing
--      and is let through; only the line's own picks are saved.
--   P3 The "Other product" pick (a product priced at the store, not one of
--      the group's options) in the promotion's own group still passes.
--   P4 A line that is not a promotion carries no picks: refused with picks,
--      let through with an empty list or empty groups.
--   P5 The same on Edit Invoice (update_invoice_internal through
--      correct_invoice): switching a saved line to another bundle with the
--      first bundle's picks is refused and the invoice is left as it was;
--      with the new bundle's picks it saves them and drops the old ones.
--   P6 A promotion with no items and no choice groups is not sold, on a new
--      invoice or an edit.
--   P7 Nor chosen inside another promotion; a chosen promotion with items is.
--   P8 Promotion dates are Singapore days. With the session clock set so that
--      its date is not Singapore's (as the UTC database is from midnight to
--      8 am), a promotion starting today and one ending today are sold, one
--      that ended yesterday and one starting tomorrow are not.
--   P9 Neither function compares now()::date any more.
--   P10 A back-dated invoice may use a promotion that ran on its own date
--      (the Owner, 9 Oct 2026), new or edited; one dated outside the run is
--      refused with the date named; today's check is as before; a promotion
--      switched off is refused whatever the date.
--   P11 An undated invoice is edited on the Singapore day it was made: a
--      promotion that ended yesterday or starts tomorrow is refused.
--
-- Needs 416 (psql -v mig=supabase/416_invoice_editing_foc_and_payment_guards.sql
-- installs it after "begin;"). Disposable database only; everything is rolled
-- back. Fixtures are invented.
\set ON_ERROR_STOP on
begin;
\if :{?prelude}
\i :prelude
\endif
\if :{?mig}
\i :mig
\endif
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
-- A new invoice of these lines at the test store, or the refusal.
create function pg_temp.make(items jsonb) returns jsonb language plpgsql as
$$declare v uuid;
begin
  v := public.create_invoice(pg_temp.fx('A'), pg_temp.fx('c'), null, items);
  return jsonb_build_object('id', v);
exception when others then return jsonb_build_object('error', sqlerrm);
end$$;
-- A correction as the page saves it; null when saved, else the refusal.
create function pg_temp.fix(inv uuid, items jsonb) returns text language plpgsql as
$$begin
  perform public.correct_invoice(inv, items, '{}'::jsonb, 'Keyed wrongly', gen_random_uuid()); return null;
exception when others then return sqlerrm;
end$$;
-- A promotion line with picks: [[group key, product key, quantity], ...].
create function pg_temp.promo(p text, picks jsonb) returns jsonb language sql as
$$ select jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx(p),'quantity',1,'selections',
     coalesce((select jsonb_agg(jsonb_build_object('group_id', pg_temp.fx(x->>0), 'options',
        case when x->>1 is null then '[]'::jsonb
             else jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx(x->>1), 'quantity', (x->>2)::int)) end))
       from jsonb_array_elements(picks) x), '[]'::jsonb)) $$;
create function pg_temp.picks(inv uuid) returns text language sql as
$$ select coalesce(string_agg(k.k, ',' order by k.k), '') from public.invoice_promotion_selections s
     join public.invoice_items it on it.id = s.invoice_item_id
     join fx k on k.v = s.group_id where it.invoice_id = inv $$;

do $$
declare o uuid := gen_random_uuid(); st uuid; c uuid; v uuid; g uuid; sfx text := left(md5(random()::text), 6);
begin
  insert into auth.users(id,email) values (o,'ps416-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (o,'PS Owner','ps416-'||sfx||'@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name,code,country_code) values ('PS Store','PS'||sfx,'SG') returning id into st;
  insert into customers(full_name,phone) values ('PS Buyer','+61491570156') returning id into c;
  insert into fx values ('o',o),('A',st),('c',c);
  -- Three products priced at the store: two are options, one is not.
  insert into products(name,sku,product_type) values ('PS Kettle','PSK-'||sfx,'own') returning id into v; insert into fx values ('kettle',v);
  perform set_product_prices(st,v,30,30,'available');
  insert into products(name,sku,product_type) values ('PS Mug','PSM-'||sfx,'own') returning id into v; insert into fx values ('mug',v);
  perform set_product_prices(st,v,10,10,'available');
  insert into products(name,sku,product_type) values ('PS Teapot','PST-'||sfx,'own') returning id into v; insert into fx values ('teapot',v);
  perform set_product_prices(st,v,25,25,'available');
  -- Bundle A (pick a kettle) and Bundle B (pick a mug).
  insert into promotions(name,code,promo_type,fixed_price) values ('PS Bundle A','PSA'||sfx,'bundle',50) returning id into v; insert into fx values ('pA',v);
  insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values (v,st,50,true);
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values (v,'A: pick a kettle','product',1) returning id into g; insert into fx values ('gA',g);
  insert into promotion_choice_options(group_id,product_id) values (g,pg_temp.fx('kettle'));
  insert into promotions(name,code,promo_type,fixed_price) values ('PS Bundle B','PSB'||sfx,'bundle',60) returning id into v; insert into fx values ('pB',v);
  insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values (v,st,60,true);
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values (v,'B: pick a mug','product',1) returning id into g; insert into fx values ('gB',g);
  insert into promotion_choice_options(group_id,product_id) values (g,pg_temp.fx('mug'));
  -- A fixed bundle (one kettle), an empty one, and a parent offering either.
  insert into promotions(name,code,promo_type,fixed_price) values ('PS Fixed','PSF'||sfx,'bundle',30) returning id into v; insert into fx values ('pF',v);
  insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values (v,st,30,true);
  insert into promotion_items(promotion_id,item_type,product_id,quantity) values (v,'product',pg_temp.fx('kettle'),1);
  insert into promotions(name,code,promo_type,fixed_price) values ('PS Empty','PSE'||sfx,'bundle',20) returning id into v; insert into fx values ('pE',v);
  insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values (v,st,20,true);
  insert into promotions(name,code,promo_type,fixed_price) values ('PS Parent','PSP'||sfx,'bundle',70) returning id into v; insert into fx values ('pP',v);
  insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values (v,st,70,true);
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values (v,'P: pick a bundle','promotion',1) returning id into g; insert into fx values ('gP',g);
  insert into promotion_choice_options(group_id,child_promotion_id) values (g,pg_temp.fx('pF')),(g,pg_temp.fx('pE'));
end $$;

do $$
declare k text; s date; e date; v uuid;
begin
  for k, s, e in select * from (values
      ('pStartToday', public.sg_today(), null::date),
      ('pEndToday', null::date, public.sg_today()),
      ('pEndedYesterday', null::date, public.sg_today() - 1),
      ('pStartsTomorrow', public.sg_today() + 1, null::date)) x
  loop
    insert into promotions(name,code,promo_type,fixed_price,start_date,end_date)
    values ('PS '||k, 'PS'||k||left(md5(random()::text),4), 'bundle', 30, s, e) returning id into v;
    insert into fx values (k, v);
    insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values (v,pg_temp.fx('A'),30,true);
    insert into promotion_items(promotion_id,item_type,product_id,quantity) values (v,'product',pg_temp.fx('kettle'),1);
  end loop;
end $$;

-- ═════ P1–P4 New invoice ═════
do $$
declare r jsonb; foreign_group text := 'Picks from another promotion were sent with "PS Bundle B". Remove the line and add it again.';
  not_promo text := 'Choices were sent with a line that is not a promotion. Remove the line and add it again.';
begin
  r := pg_temp.make(jsonb_build_array(pg_temp.promo('pB', '[["gA","kettle",1],["gB","mug",1]]')));
  perform pg_temp.check(r->>'error' = foreign_group and not exists (select 1 from public.invoices where customer_id = pg_temp.fx('c')),
    'P1 Bundle B sent with Bundle A''s kettle pick is refused, and no invoice is made: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.make(jsonb_build_array(pg_temp.promo('pB', '[["gA",null,0],["gB","mug",1]]')));
  perform pg_temp.check(r->>'id' is not null and pg_temp.picks((r->>'id')::uuid) = 'gB',
    'P2 an empty group of Bundle A writes nothing; only Bundle B''s pick is saved: ' || coalesce(r->>'error', pg_temp.picks((r->>'id')::uuid)));
  insert into fx values ('inv2', (r->>'id')::uuid);
  r := pg_temp.make(jsonb_build_array(pg_temp.promo('pB', '[["gB","teapot",1]]')));
  perform pg_temp.check(r->>'id' is not null and pg_temp.picks((r->>'id')::uuid) = 'gB',
    'P3 the "Other product" pick in Bundle B''s own group still passes: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('mug'),'quantity',1,
         'selections', jsonb_build_array(jsonb_build_object('group_id', pg_temp.fx('gA'),
           'options', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('kettle'), 'quantity', 1)))))));
  perform pg_temp.check(r->>'error' = not_promo, 'P4 a product line with a pick is refused: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('mug'),'quantity',1,'selections','[]'::jsonb)));
  perform pg_temp.check(r->>'id' is not null, 'P4 a product line with an empty list passes: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('mug'),'quantity',1,
         'selections', jsonb_build_array(jsonb_build_object('group_id', pg_temp.fx('gA'), 'options', '[]'::jsonb)))));
  perform pg_temp.check(r->>'id' is not null, 'P4 and with an empty group: ' || coalesce(r->>'error', 'made'));
end $$;

-- ═════ P5 Edit Invoice ═════
do $$
declare inv uuid := pg_temp.fx('inv2'); it uuid; e text; before_total numeric;
  foreign_group text := 'Picks from another promotion were sent with "PS Bundle A". Remove the line and add it again.';
begin
  select id into it from public.invoice_items where invoice_id = inv;
  select total_amount into before_total from public.invoices where id = inv;
  -- Switched to Bundle A with Bundle B's pick still in the payload.
  e := pg_temp.fix(inv, jsonb_build_array(pg_temp.promo('pA', '[["gA","kettle",1],["gB","mug",1]]') || jsonb_build_object('invoice_item_id', it)));
  perform pg_temp.check(e = foreign_group and pg_temp.picks(inv) = 'gB'
      and (select promotion_id from public.invoice_items where id = it) = pg_temp.fx('pB')
      and (select (total_amount, coalesce(edit_count, 0)) = (before_total, 0) from public.invoices where id = inv),
    'P5 an edit switching to Bundle A with Bundle B''s pick is refused, and the invoice is as it was: ' || coalesce(e, 'saved'));
  e := pg_temp.fix(inv, jsonb_build_array(pg_temp.promo('pA', '[["gA","kettle",1],["gB",null,0]]') || jsonb_build_object('invoice_item_id', it)));
  perform pg_temp.check(e is null and pg_temp.picks(inv) = 'gA'
      and (select promotion_id from public.invoice_items where id = it) = pg_temp.fx('pA'),
    'P5 with Bundle A''s own pick it saves, and Bundle B''s pick is gone: ' || coalesce(e, pg_temp.picks(inv)));
  e := pg_temp.fix(inv, jsonb_build_array(pg_temp.promo('pA', '[["gA","kettle",1]]') || jsonb_build_object('invoice_item_id', it),
         jsonb_build_object('kind','product','product_id',pg_temp.fx('mug'),'quantity',1,
           'selections', jsonb_build_array(jsonb_build_object('group_id', pg_temp.fx('gB'),
             'options', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('mug'), 'quantity', 1)))))));
  perform pg_temp.check(e = 'Choices were sent with a line that is not a promotion. Remove the line and add it again.',
    'P5 an added product line carrying a pick is refused on an edit too: ' || coalesce(e, 'saved'));
end $$;

-- ═════ P6–P7 Empty promotions ═════
do $$
declare r jsonb; e text; inv uuid;
begin
  r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('pE'),'quantity',1)));
  perform pg_temp.check(r->>'error' = 'Promotion "PS Empty" has nothing in it, so it cannot be sold. Ask an Owner or Manager to add its items.',
    'P6 a promotion with nothing in it is not sold: ' || coalesce(r->>'error', 'made'));
  inv := pg_temp.fx('inv2');
  e := pg_temp.fix(inv, jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('pE'),'quantity',1)));
  perform pg_temp.check(e = 'Promotion "PS Empty" has nothing in it, so it cannot be sold. Ask an Owner or Manager to add its items.',
    'P6 nor added on an edit: ' || coalesce(e, 'saved'));
  r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('pP'),'quantity',1,
         'selections', jsonb_build_array(jsonb_build_object('group_id', pg_temp.fx('gP'),
           'options', jsonb_build_array(jsonb_build_object('child_promotion_id', pg_temp.fx('pE'), 'quantity', 1)))))));
  perform pg_temp.check(r->>'error' = '"PS Empty" in "P: pick a bundle" has nothing in it, so it cannot be chosen. Ask an Owner or Manager to add its items.',
    'P7 nor chosen inside another promotion: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('pP'),'quantity',1,
         'selections', jsonb_build_array(jsonb_build_object('group_id', pg_temp.fx('gP'),
           'options', jsonb_build_array(jsonb_build_object('child_promotion_id', pg_temp.fx('pF'), 'quantity', 1)))))));
  perform pg_temp.check(r->>'id' is not null, 'P7 a chosen promotion with an item is sold: ' || coalesce(r->>'error', 'made'));
end $$;

-- ═════ P8 Singapore days ═════
do $$
declare zone text; r jsonb; e text; inv uuid := pg_temp.fx('inv2'); k text; ok text;
begin
  -- A clock whose date is not Singapore's at this moment (UTC-10 is 18 hours
  -- behind Singapore, UTC+14 six hours ahead), as UTC is before 8 am.
  zone := case when (now() at time zone 'Pacific/Honolulu')::date <> public.sg_today() then 'Pacific/Honolulu' else 'Pacific/Kiritimati' end;
  perform set_config('TimeZone', zone, true);
  perform pg_temp.check(now()::date <> public.sg_today(), 'P8 fixture: the session''s date (' || zone || ') is not Singapore''s');
  for k, ok in select * from (values ('pStartToday', null), ('pEndToday', null),
                                     ('pEndedYesterday', 'Promotion "PS pEndedYesterday" has ended'),
                                     ('pStartsTomorrow', 'Promotion "PS pStartsTomorrow" has not started yet')) x
  loop
    r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx(k),'quantity',1)));
    perform pg_temp.check(r->>'error' is not distinct from ok,
      format('P8 new invoice, %s: %s', k, coalesce(r->>'error', 'made')));
    e := pg_temp.fix(inv, jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx(k),'quantity',1)));
    perform pg_temp.check(e is not distinct from ok, format('P8 edit, %s: %s', k, coalesce(e, 'saved')));
  end loop;
  perform set_config('TimeZone', 'UTC', true);
end $$;

-- ═════ P9 ═════
do $$ begin
  perform pg_temp.check(pg_get_functiondef('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)'::regprocedure) !~ 'now\(\)::date [<>]'
      and pg_get_functiondef('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'::regprocedure) !~ 'now\(\)::date [<>]',
    'P9 neither create_invoice nor update_invoice_internal compares now()::date');
end $$;

-- ═════ P10 A back-dated invoice (the Owner, 9 Oct 2026) ═════
-- A promotion that ran from 40 to 20 days ago may be used on an invoice
-- dated inside that run, new or edited; not on one dated after it ended or
-- before it started, and not today. The refusal names the invoice date.
do $$
declare v uuid; r uuid; e text; it uuid; d_in date := public.sg_today() - 30;
  ended text; started text;
begin
  insert into promotions(name,code,promo_type,fixed_price,start_date,end_date)
  values ('PS Ran Last Month','PSRLM'||left(md5(random()::text),4),'bundle',30,public.sg_today() - 40,public.sg_today() - 20) returning id into v;
  insert into fx values ('pRan', v);
  insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values (v,pg_temp.fx('A'),30,true);
  insert into promotion_items(promotion_id,item_type,product_id,quantity) values (v,'product',pg_temp.fx('kettle'),1);
  ended := format('Promotion "PS Ran Last Month" had ended by the invoice date, %s.', to_char(public.sg_today() - 10, 'DD/MM/YYYY'));
  started := format('Promotion "PS Ran Last Month" had not started on the invoice date, %s.', to_char(public.sg_today() - 45, 'DD/MM/YYYY'));

  r := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'),
         jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',v,'quantity',1)),
         jsonb_build_object('business_date', d_in::text));
  perform pg_temp.check(r is not null and (select business_date from public.invoices where id = r) = d_in,
    'P10 a new invoice dated while the promotion ran may use it');
  insert into fx values ('invRan', r);
  begin
    perform public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'),
      jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',v,'quantity',1)),
      jsonb_build_object('business_date', (public.sg_today() - 10)::text));
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e is not distinct from ended, 'P10 not one dated after it ended: ' || coalesce(e, 'made'));
  begin
    perform public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'),
      jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',v,'quantity',1)),
      jsonb_build_object('business_date', (public.sg_today() - 45)::text));
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e is not distinct from started, 'P10 nor one dated before it started: ' || coalesce(e, 'made'));
  begin
    perform public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'),
      jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',v,'quantity',1)),
      jsonb_build_object('business_date', public.sg_today()::text));
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e is not distinct from 'Promotion "PS Ran Last Month" has ended', 'P10 nor one dated today, as before: ' || coalesce(e, 'made'));

  -- Edit Invoice: the line changed (quantity 1 -> 2) is sold again on the
  -- invoice's own date, so it saves.
  select id into it from public.invoice_items where invoice_id = r;
  e := pg_temp.fix(r, jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','promotion','promotion_id',v,'quantity',2)));
  perform pg_temp.check(e is null and (select quantity from public.invoice_items where invoice_id = r) = 2,
    'P10 an edit of the back-dated invoice sells the changed line on its own date: ' || coalesce(e, 'saved'));
  -- The same edit moving the date past the promotion's end is refused, and
  -- nothing changes.
  begin
    perform public.correct_invoice(r, jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','promotion','promotion_id',v,'quantity',3)),
      jsonb_build_object('business_date', (public.sg_today() - 10)::text), 'Keyed wrongly', gen_random_uuid());
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e is not distinct from ended
      and (select (business_date, (select quantity from public.invoice_items where invoice_id = r)) = (d_in, 2) from public.invoices where id = r),
    'P10 an edit dating it after the promotion ended is refused, and the invoice is as it was: ' || coalesce(e, 'saved'));
  -- A promotion switched off is refused whatever the date, as before.
  update promotions set is_active = false where id = v;
  begin
    perform public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'),
      jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',v,'quantity',1)),
      jsonb_build_object('business_date', d_in::text));
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e is not distinct from 'Promotion "PS Ran Last Month" is not active',
    'P10 a promotion switched off is refused on its own dates too: ' || coalesce(e, 'made'));
end $$;

-- ═════ P11 An undated invoice ═════
-- An invoice saved with no date (before dates were required) is edited on
-- the Singapore day it was made: a promotion that ended yesterday, or starts
-- tomorrow, is refused as on a new invoice today.
do $$
declare r jsonb; inv uuid; it uuid; e text; k text; ok text;
begin
  r := pg_temp.make(jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('kettle'),'quantity',1)));
  inv := (r->>'id')::uuid;
  update public.invoices set business_date = null where id = inv;
  select id into it from public.invoice_items where invoice_id = inv;
  for k, ok in select * from (values ('pEndedYesterday', 'Promotion "PS pEndedYesterday" has ended'),
                                     ('pStartsTomorrow', 'Promotion "PS pStartsTomorrow" has not started yet'),
                                     ('pEndToday', null)) x
  loop
    e := pg_temp.fix(inv, jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',pg_temp.fx('kettle'),'quantity',1),
                                            jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx(k),'quantity',1)));
    perform pg_temp.check(e is not distinct from ok
        and (select business_date from public.invoices where id = inv) is null
        and (select count(*) from public.invoice_items where invoice_id = inv) = case when ok is null then 2 else 1 end,
      format('P11 undated invoice edited to add %s: %s', k, coalesce(e, 'saved')));
  end loop;
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All promotion choice checks passed.';
end $$;
rollback;
