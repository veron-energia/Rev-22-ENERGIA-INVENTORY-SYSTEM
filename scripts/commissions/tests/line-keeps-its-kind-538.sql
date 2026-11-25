-- An invoice line keeps the commission kind it first earned as; an Owner corrects an invoice's
-- kept rates and line kinds, with a reason, a preview and an audit entry (538; security audit of
-- 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type", "Owner repair, recorded").
--
-- Every call is made as the pages make it: a signed-in login (the authenticated role, its JWT)
-- calling the page's server function; what only the server runs (earning, reconcile, payouts) is
-- called as the database owner with the Owner's claims. The logins: an Owner, a Manager, an
-- Inventory Manager, an Admin, Staff. Rates pinned to production's (15 / 4.5 / 35 / 35).
--
--   B  (install mode) Before 538: an invoice whose own product (paid out) is since third party, an
--      invoice with a no-commission line. B0: a line whose standing rows carry two kinds makes 538
--      refuse. The backfill keeps own for the changed product; worked out again after 538 (each
--      rolled back), every invoice with kept rates earns exactly what it stands at (net per
--      referrer, tier and kind); before 538 the changed one would have been re-priced.
--   K  With 538: kinds kept from the first earning. A product made third party by a Manager
--      (save_product), and a correction or a reconcile keeps own (15.00 / 5.25), a new invoice is
--      third party (4.50 / 1.58). A no-commission line stays at nothing when the product is made
--      own. A part payment after the change keeps own (S$700: 105.00 / 36.75). A promotion keeps
--      its own and third-party split when an item's type changes (11.25 + 3.38 / 3.94 + 1.18). A
--      special product keeps its machine's kind when the machine is made third party (489). A
--      line added later by a correction takes its kind then and keeps it.
--   R  The Owner repair: a Manager, an Inventory Manager, an Admin, Staff and the secret key are
--      refused, with the sentence; the preview shows before and after per tier and changes
--      nothing; no reason, a bad rate, a bad kind, a line not on the invoice, nothing different,
--      an invoice that keeps no rates: each refused; the Owner's correction (a kind, own to third
--      party, on a line paid out) works the commission out again with 410's netting, and the audit
--      entry has the old and new values, the totals and the reason; a repeat with the same
--      request id changes nothing more.
--   G  538's fixed parts: AFTER md5s and grants; the table and helpers postgres's alone; the
--      relied-on functions unchanged; installed here, only those functions changed.
--   U  scripts/commissions/undo-538.sql puts everything back exactly; 538 again makes the same.
--   M  538 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Every name and number is invented
-- (M538 …, @example.invalid; phones +61 491 570 nnn). Run it on a copy of production without 538
-- (after 535; it applies 538, then again); with -v skip_install=1 where 538 is in (B, U and M
-- skipped, G in part); with -v control=1 on a copy WITHOUT 538 (it skips B, G, U and M and fails
-- on exactly the checks 538 makes pass).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/commissions/tests/line-keeps-its-kind-538.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
select to_regclass('public.invoice_line_commission_kinds') is not null as had538 \gset
\if :{?control}
\if :had538
\echo control: 538 is in on this copy; run -v control=1 on a copy without it
select 1/0;
\endif
\set mode control
\elif :{?skip_install}
\if :had538
\else
\echo 538 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had538
\echo 538 is already in: run with -v skip_install=1
select 1/0;
\else
\set mode install
\endif
select :'mode' = 'install' as by_us, :'mode' = 'control' as is_control \gset

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.put(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
create temp table sfx as select lower(substr(md5(gen_random_uuid()::text), 1, 6)) as s, (floor(random() * 900))::int as ph;
create function pg_temp.sfx() returns text language sql as $$ select s from sfx $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+61491570' || lpad((((select ph from sfx) + n) % 1000)::text, 3, '0') $$;
create function pg_temp.s(key text) returns text language sql as $$
  select case key
    when 'owner' then 'Only an Owner can correct an invoice''s kept commission rates or line kinds.'
    when 'reason' then 'Give the reason for the correction.'
    when 'none' then 'This invoice has earned no affiliate commission yet, so it keeps no rates or line kinds to correct.'
    when 'rate' then 'A rate is tier1_own, tier1_third, tier2_own or tier2_third, each a number from 0 to 100.'
    when 'line' then 'That line is not on this invoice, or it is a package, a bundle or a late fee (they have no kind of their own).'
    when 'kind' then 'A line''s kind is own, third_party or no_commission.'
    when 'same' then 'Nothing would change: these are the rates and kinds this invoice keeps.' end $$;
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    if who = 'service' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'service_role', true);
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    elsif who like 'pg:%' then
      perform set_config('request.jwt.claim.sub', pg_temp.fx(substr(who, 4))::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(substr(who, 4)), 'role', 'authenticated')::text, true);
    else
      perform set_config('request.jwt.claim.sub', pg_temp.fx(who)::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute q into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR ' || s || ' ' || m;
  end;
end $f$;
create function pg_temp.must(who text, q text) returns text language plpgsql as $f$
declare t text := pg_temp.as_(who, q);
begin
  if t not like 'ok:%' then raise exception 'FIXTURE (%): % -> %', who, q, t; end if;
  return substr(t, 4);
end $f$;

-- ═════ Fixtures (invented), as the database owner ═════
insert into public.app_settings(id) values (true) on conflict do nothing;
update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
  commission_tier2_own_rate = 35, commission_tier2_third_rate = 35, staff_commission_rate = 3,
  instalment_commission_from = public.sg_today() - 100,
  machine_commission_from = coalesce(machine_commission_from, now() - interval '30 days')
 where id = true;
do $fx$
declare r record; u uuid; s text := pg_temp.sfx(); st uuid; wh uuid;
begin
  for r in select * from (values ('own', 'owner'), ('mgr', 'manager'), ('invm', 'inventory_manager'), ('adm', 'admin'), ('stf', 'staff')) t(k, role) loop
    insert into auth.users(id, email, email_confirmed_at) values (gen_random_uuid(), 'm538-' || r.k || '-' || s || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active) values (u, 'M538 ' || r.k, 'm538-' || r.k || '-' || s || '@example.invalid', r.role::public.user_role, true);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.stores(name, code, country_code) values ('M538 Store', 'M538' || s, 'SG') returning id into st; perform pg_temp.put('st', st);
  insert into public.warehouses(name, code) values ('M538 Warehouse', 'M538W' || s) returning id into wh; perform pg_temp.put('wh', wh);
  insert into public.user_store_assignments(user_id, store_id)
  values (pg_temp.fx('own'), st), (pg_temp.fx('mgr'), st), (pg_temp.fx('invm'), st), (pg_temp.fx('stf'), st);
  insert into public.payment_methods(name, is_active) values ('M538 Cash ' || s, true) returning id into u; perform pg_temp.put('m', u);
  for r in select * from (values ('p', 'own', 100), ('p2', 'own', 100), ('p3', 'third_party', 100), ('pk', 'own', 1000),
                                 ('pa', 'own', 100), ('pb', 'third_party', 100), ('mach', 'own', 1000)) t(k, ty, price) loop
    insert into public.products(name, sku, product_type) values ('M538 ' || r.k, 'M538-' || r.k || '-' || s, r.ty::public.product_type) returning id into u;
    perform pg_temp.put(r.k, u);
    insert into public.store_inventory(store_id, product_id, current_qty) values (st, u, 500);
  end loop;
  insert into public.products(name, sku, product_type) values ('M538 Session', 'M538-pz-' || s, 'no_commission') returning id into u; perform pg_temp.put('pz', u);
  insert into public.special_products(name, sku, sale_price, rate_month, is_active, product_id)
    values ('M538 SP Machine', 'M538SP' || s, 1000, 100, true, pg_temp.fx('mach')) returning id into u; perform pg_temp.put('sp', u);
  insert into public.special_product_stock(special_product_id, warehouse_id, current_qty) values (u, wh, 10);
  insert into public.promotions(name, code) values ('M538 Promo', 'M538PR-' || s) returning id into u; perform pg_temp.put('pr', u);
  insert into public.promotion_items(promotion_id, item_type, product_id, quantity) values (u, 'product', pg_temp.fx('pa'), 1), (u, 'product', pg_temp.fx('pb'), 1);
  insert into public.promotion_store_prices(promotion_id, store_id, selling_price) values (u, st, 150);
end $fx$;
select pg_temp.must('pg:own', format('select public.set_product_prices(%L, %L, %s, %s, %L)::text', pg_temp.fx('st'), pg_temp.fx(k), pr, pr, 'available'))
  from (values ('p', 100), ('p2', 100), ('p3', 100), ('pk', 1000), ('pa', 100), ('pb', 100), ('pz', 50), ('mach', 1000)) t(k, pr);
create function pg_temp.pin_rates() returns void language sql as $$
  update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
    commission_tier2_own_rate = 35, commission_tier2_third_rate = 35 where id = true $$;
create function pg_temp.chain(key text, n int) returns void language plpgsql as $$
declare t2 uuid; t1 uuid; b uuid;
begin
  insert into public.customers(full_name, phone) values ('M538 ' || key || ' T2', pg_temp.ph(n * 3)) returning id into t2;
  insert into public.customers(full_name, phone, referred_by) values ('M538 ' || key || ' T1', pg_temp.ph(n * 3 + 1), t2) returning id into t1;
  insert into public.customers(full_name, phone, referred_by) values ('M538 ' || key || ' Buyer', pg_temp.ph(n * 3 + 2), t1) returning id into b;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at)
  values (t2, 'active', pg_temp.fx('st'), now()), (t1, 'active', pg_temp.fx('st'), now());
  perform pg_temp.put('c:' || key, b); perform pg_temp.put('t1:' || key, t1);
end $$;
-- An invoice: product keys, 'pr' the promotion, 'sp' the special product.
create function pg_temp.inv(key text, chain text, kinds text[]) returns uuid language plpgsql as $$
declare items jsonb := '[]'::jsonb; k text; v uuid;
begin
  foreach k in array kinds loop
    items := items || case k
      when 'pr' then jsonb_build_object('kind','promotion','promotion_id',pg_temp.fx('pr'),'quantity',1)
      when 'sp' then jsonb_build_object('kind','special_product','special_product_id',pg_temp.fx('sp'),'quantity',1)
      else jsonb_build_object('kind','product','product_id',pg_temp.fx(k),'quantity',1) end;
  end loop;
  v := pg_temp.must('pg:own', format('select public.create_invoice_with_details(%L, %L, %L::jsonb, %L::jsonb)::text',
         pg_temp.fx('st'), pg_temp.fx('c:' || chain), items, jsonb_build_object('business_date', public.sg_today()::text)))::uuid;
  return pg_temp.put('i:' || key, v);
end $$;
create function pg_temp.pay(key text, amount numeric) returns text language sql as $$
  select pg_temp.must('pg:own', format('select public.record_invoice_payment(%L, %L::jsonb, %L)::text', pg_temp.fx('i:' || key),
    jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('m'), 'amount', amount)), gen_random_uuid())) $$;
create function pg_temp.reconcile(key text) returns text language sql as $$
  select pg_temp.as_('pg:own', format('select public.reconcile_invoice_commissions(%L, %L)::text', pg_temp.fx('i:' || key), 'M538 worked out again')) $$;
create function pg_temp.amt(key text, which text) returns numeric language sql as $$
  select coalesce(sum(c.commission_amount), 0) from public.commissions c
   where c.invoice_id = pg_temp.fx('i:' || key) and c.tier::text = $2 and c.status in ('earned','paid') $$;
create function pg_temp.amts(key text) returns text language sql as $$
  select pg_temp.amt(key, 'tier1') || '/' || pg_temp.amt(key, 'tier2') $$;
-- The kinds of an invoice's standing rows (tier 1), as "kind:amount" per row.
create function pg_temp.kinds_of(key text) returns text language sql as $$
  select coalesce(string_agg(c.product_type || ':' || c.commission_amount, ' ' order by c.product_type, c.commission_amount), '-')
    from public.commissions c where c.invoice_id = pg_temp.fx('i:' || key) and c.tier = 'tier1'
     and c.status in ('earned','paid') and c.adjusts_commission_id is null and c.commission_amount > 0 $$;
-- What an invoice's referrers hold at tier 1 per kind (earned and paid rows, part payments included).
create function pg_temp.knet(key text) returns text language sql as $$
  select coalesce(string_agg(k || ':' || a, ' ' order by k), '-') from (
    select c.product_type as k, sum(c.commission_amount) as a from public.commissions c
     where c.invoice_id = pg_temp.fx('i:' || key) and c.tier = 'tier1' and c.status in ('earned','paid')
     group by c.product_type having sum(c.commission_amount) <> 0) q $$;
create function pg_temp.kept(key text, item text) returns text language plpgsql as $$
declare t text;
begin
  if to_regclass('public.invoice_line_commission_kinds') is null then return 'no table'; end if;
  execute 'select k.kind || case when k.backfilled then '' backfilled'' else '''' end from public.invoice_line_commission_kinds k
             join public.invoice_items ii on ii.id = k.invoice_item_id
            where ii.invoice_id = $1 and coalesce(ii.product_id::text, ii.promotion_id::text, ii.special_product_id::text) = $2'
    into t using pg_temp.fx('i:' || key), pg_temp.fx(item)::text;
  return coalesce(t, '-');
end $$;
create function pg_temp.set_type(k text, ty text) returns void language sql as $$
  update public.products set product_type = ty::public.product_type where id = pg_temp.fx(k) $$;
-- A payout of what a referrer has earned this month (the Owner's, as the Commissions page records it).
create function pg_temp.pay_out(who text, amount numeric) returns text language sql as $$
  select pg_temp.must('pg:own', format('select public.affiliate_payout_save(null, null, %L, %L::date, %s, %L, %L::date, %L, null, null, %L)::text',
    pg_temp.fx(who), date_trunc('month', public.sg_today()::timestamp)::date, amount, pg_temp.fx('m'), public.sg_today(), 'M538 payout', gen_random_uuid())) $$;

-- ═════ B Before 538 (install mode only): the backfill and its neutrality ═════
-- Net per invoice: what each referrer holds per tier and kind (earned and paid rows).
create temp table seen(phase text, inv uuid, net text, primary key (phase, inv));
create function pg_temp.net(v uuid) returns text language sql as $$
  select coalesce(string_agg(r, ' ' order by r), '-') from (
    select c.referrer_customer_id || '|' || c.tier || '|' || c.product_type || '|' || sum(c.commission_amount) as r
      from public.commissions c where c.invoice_id = v and c.status in ('earned','paid')
     group by c.referrer_customer_id, c.tier, c.product_type having sum(c.commission_amount) <> 0) q $$;
-- p_rework: each invoice with kept rates worked out again (reconcile), in a step rolled back by itself.
create function pg_temp.look(p_phase text, p_rework boolean) returns int language plpgsql as $$
declare v uuid; t text; n int := 0;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);
  for v in select r.invoice_id from public.invoice_affiliate_rates r loop
    if p_rework then
      t := null;
      begin
        perform public.reconcile_invoice_commissions(v, 'M538 rehearsal');
        t := pg_temp.net(v);
        raise exception 'M538_ROLLBACK';
      exception when others then
        if sqlerrm <> 'M538_ROLLBACK' then t := 'ERR ' || sqlerrm; end if;
      end;
    else
      t := pg_temp.net(v);
    end if;
    insert into seen values (p_phase, v, t); n := n + 1;
  end loop;
  return n;
end $$;
\if :by_us
select pg_temp.chain('B1', 1), pg_temp.chain('B2', 2);
select pg_temp.inv('B1', 'B1', array['p']), pg_temp.inv('B2', 'B2', array['p', 'pz']);
select pg_temp.pay('B1', 100), pg_temp.pay('B2', 150);
select pg_temp.pay_out('t1:B1', 15);
select pg_temp.set_type('p', 'third_party');
-- B0 a line whose standing rows carry two kinds: 538 refuses, changing nothing.
savepoint b0;
insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
select c.invoice_id, c.invoice_item_id, c.buyer_customer_id, c.referrer_customer_id, c.tier, 'third_party', c.line_amount, 4.5, 1, 'earned', c.invoice_paid_date
  from public.commissions c where c.invoice_id = pg_temp.fx('i:B2') and c.tier = 'tier1' and c.status = 'earned' limit 1;
\set ON_ERROR_STOP off
\ir ../../../supabase/538_an_invoice_line_keeps_the_commission_kind_it_first_earned_as.sql
\set ON_ERROR_STOP on
rollback to savepoint b0;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '538: 1 line(s) on 1 invoice(s) have standing commission rows of more than one kind%'
                     and to_regclass('public.invoice_line_commission_kinds') is null,
  'B0 a line whose standing rows carry two kinds makes 538 refuse, changing nothing: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.look('standing', false);
select pg_temp.look('reworked before 538', true);
\ir ../../../supabase/538_an_invoice_line_keeps_the_commission_kind_it_first_earned_as.sql
create temp table fn1 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
select pg_temp.look('reworked after 538', true);
select pg_temp.check(pg_temp.kept('B1', 'p') = 'own backfilled' and pg_temp.kept('B2', 'p') = 'own backfilled' and pg_temp.kept('B2', 'pz') = 'no_commission backfilled',
  'B1 the backfill keeps own for the product made third party since (its rows'' kind), and each other line''s kind: '
  || pg_temp.kept('B1', 'p') || ' / ' || pg_temp.kept('B2', 'p') || ' / ' || pg_temp.kept('B2', 'pz'));
select pg_temp.check((select count(*) from public.invoice_line_commission_kinds)
                     = (select count(*) from public.invoice_items ii join public.invoice_affiliate_rates r on r.invoice_id = ii.invoice_id
                         where ii.line_kind::text not in ('credit_package','premium_bundle','late_fee')),
  'B2 every line of every invoice with kept rates is backfilled');
select pg_temp.check(not exists (select 1 from seen a join seen b on b.inv = a.inv and b.phase = 'reworked after 538'
                                  where a.phase = 'standing' and a.net is distinct from b.net)
                     and (select count(*) from seen where phase = 'reworked after 538') = (select count(*) from seen where phase = 'standing'),
  'B3 every invoice with kept rates, worked out again after 538 (rolled back), earns exactly what it stands at, per referrer, tier and kind ('
  || (select count(*) from seen where phase = 'standing') || ' invoices)');
select pg_temp.check((select net from seen where phase = 'reworked before 538' and inv = pg_temp.fx('i:B1'))
                     is distinct from (select net from seen where phase = 'standing' and inv = pg_temp.fx('i:B1')),
  'B4 before 538, the same rework re-priced the invoice whose product became third party (the fault)');
\else
create temp table fn1 as select * from fn0;
\echo NOTE  B is skipped (538 was not installed by this file)
\endif

-- ═════ K Kinds kept from the first earning ═════
select pg_temp.chain('KA', 11), pg_temp.chain('KN', 12), pg_temp.chain('KZ', 13), pg_temp.chain('KC', 14),
       pg_temp.chain('KP', 15), pg_temp.chain('KS', 16), pg_temp.chain('KL', 17);
select pg_temp.inv('KA', 'KA', array['p2']), pg_temp.inv('KZ', 'KZ', array['p3', 'pz']), pg_temp.inv('KC', 'KC', array['pk']),
       pg_temp.inv('KP', 'KP', array['pr']), pg_temp.inv('KS', 'KS', array['sp']), pg_temp.inv('KL', 'KL', array['p2']);
select pg_temp.pay('KA', 100), pg_temp.pay('KZ', 150), pg_temp.pay('KC', 400), pg_temp.pay('KP', 150), pg_temp.pay('KS', 1000), pg_temp.pay('KL', 100);
select pg_temp.check(pg_temp.amts('KA') = '15.00/5.25' and pg_temp.amts('KZ') = '4.50/1.58' and pg_temp.amts('KC') = '60.00/21.00'
                     and pg_temp.amts('KP') = '14.63/5.12' and pg_temp.amts('KS') = '150.00/52.50',
  'K0 the first earnings: own S$100 15.00/5.25; third-party S$100 and a no-commission line 4.50/1.58; S$400 of S$1000 60.00/21.00; '
  || 'the promotion S$150 half own, half third party 14.63/5.12; the special product on an own machine 150.00/52.50: '
  || pg_temp.amts('KA') || ' ' || pg_temp.amts('KZ') || ' ' || pg_temp.amts('KC') || ' ' || pg_temp.amts('KP') || ' ' || pg_temp.amts('KS'));
\if :is_control
\else
select pg_temp.check(pg_temp.kept('KA', 'p2') = 'own' and pg_temp.kept('KZ', 'pz') = 'no_commission' and pg_temp.kept('KZ', 'p3') = 'third_party'
                     and pg_temp.kept('KC', 'pk') = 'own' and pg_temp.kept('KP', 'pr') = 'own' and pg_temp.kept('KS', 'sp') = 'own',
  'K1 every line keeps its kind once the invoice earns (no-commission lines too; the part-paid one; the promotion; the special product)');
\endif
-- The catalogue changes: a Manager makes p2 third party (the products page), and the rest by hand.
select pg_temp.as_('mgr', format('select public.save_product(%L, %L::jsonb, null, null)::text', pg_temp.fx('p2'), '{"product_type":"third_party"}')) as k2 \gset
select pg_temp.check((select product_type::text from public.products where id = pg_temp.fx('p2')) = 'third_party',
  'K2 a Manager makes the product third party on the products page: ' || left(:'k2', 80));
select pg_temp.set_type('pz', 'own'), pg_temp.set_type('pk', 'third_party'), pg_temp.set_type('pb', 'own'), pg_temp.set_type('mach', 'third_party');
do $K$
declare t text;
begin
  t := pg_temp.reconcile('KA');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KA') = '15.00/5.25' and pg_temp.kinds_of('KA') = 'own:15.00',
    'K3 reconciled after the change, the old invoice keeps own: ' || pg_temp.amts('KA') || ' ' || pg_temp.kinds_of('KA'));
  t := pg_temp.reconcile('KZ');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KZ') = '4.50/1.58',
    'K4 the no-commission line made own earns nothing on the old invoice: ' || pg_temp.amts('KZ'));
  perform pg_temp.pay('KC', 300);
  perform pg_temp.check(pg_temp.amts('KC') = '105.00/36.75', 'K5 the next part payment keeps own (S$700: 105.00/36.75): ' || pg_temp.amts('KC'));
  t := pg_temp.reconcile('KP');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KP') = '14.63/5.12',
    'K6 the promotion keeps its own and third-party split when an item becomes own: ' || pg_temp.amts('KP') || ' ' || pg_temp.kinds_of('KP'));
  t := pg_temp.reconcile('KS');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KS') = '150.00/52.50',
    'K7 the special product keeps its machine''s kind when the machine becomes third party (489): ' || pg_temp.amts('KS'));
end $K$;
select pg_temp.inv('KN', 'KN', array['p2']);
select pg_temp.pay('KN', 100);
select pg_temp.check(pg_temp.amts('KN') = '4.50/1.58', 'K8 a new invoice of the product earns as third party now: ' || pg_temp.amts('KN'));
-- K9 a line added later by a correction (KL: p2 own when it earned; p added, now third party)
create function pg_temp.lines_plus(inv uuid, extra jsonb) returns jsonb language sql as $$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind::text, 'quantity', it.quantity,
           'product_id', it.product_id, 'unit_price', it.unit_price)) order by it.id) || extra
    from public.invoice_items it where it.invoice_id = inv $$;
select pg_temp.as_('pg:own', format('select public.correct_invoice(%L, %L::jsonb, %L::jsonb, %L, %L)::text', pg_temp.fx('i:KL'),
  pg_temp.lines_plus(pg_temp.fx('i:KL'), jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p3'), 'quantity', 1))),
  jsonb_build_object('expected_edit_count', (select coalesce(edit_count, 0) from public.invoices where id = pg_temp.fx('i:KL'))),
  'M538 a line added', gen_random_uuid())) as k9 \gset
select pg_temp.pay('KL', 100) where (select total_amount - paid_amount from public.invoices where id = pg_temp.fx('i:KL')) = 100;
select pg_temp.set_type('p3', 'own');
select pg_temp.reconcile('KL');
\if :is_control
\else
select pg_temp.check(pg_temp.kept('KL', 'p2') = 'own' and pg_temp.kept('KL', 'p3') = 'third_party' and pg_temp.knet('KL') = 'own:15.00 third_party:4.50',
  'K9 a line added by a correction keeps the kind it first earned as (third party), the old line its own: '
  || pg_temp.kept('KL', 'p3') || ' ' || pg_temp.knet('KL') || ' (' || left(:'k9', 40) || ')');
\endif
select pg_temp.set_type('p3', 'third_party');

-- ═════ R The Owner's correction ═════
do $R$
declare t text; v uuid := pg_temp.fx('i:KA'); item uuid; n0 int; j jsonb; c0 text; d text;
begin
  select id into item from public.invoice_items where invoice_id = v and product_id = pg_temp.fx('p2');
  d := format('select public.correct_invoice_commission_basis(%L, %L::jsonb, %L::jsonb, %L, null)::text', v, '{}',
              jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'kind', 'third_party')), 'M538 test');
  for t in select x from unnest(array['mgr', 'invm', 'adm', 'stf', 'service']) x loop
    c0 := pg_temp.as_(t, d);
    perform pg_temp.check(c0 = 'ERR 42501 ' || pg_temp.s('owner'), 'R1 ' || t || ' cannot correct an invoice''s kept rates or kinds: ' || c0);
  end loop;
  c0 := pg_temp.as_('mgr', format('select public.invoice_commission_kept_basis(%L)::text', v));
  perform pg_temp.check(c0 = 'ERR 42501 ' || pg_temp.s('owner'), 'R1b nor read the window: ' || c0);
  -- the preview: before and after per tier, nothing changes
  select string_agg(c.id::text || c.status || c.commission_amount, ',' order by c.id) into c0 from public.commissions c where c.invoice_id = v;
  t := pg_temp.as_('own', format('select public.preview_invoice_commission_correction(%L, %L::jsonb, %L::jsonb)::text', v, '{}',
       jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'kind', 'third_party'))));
  j := case when t like 'ok:%' then substr(t, 4)::jsonb end;
  perform pg_temp.check(j -> 'before' = '{"tier1": 15.00, "tier2": 5.25}'::jsonb and j -> 'after' = '{"tier1": 4.50, "tier2": 1.58}'::jsonb
      and (select string_agg(c.id::text || c.status || c.commission_amount, ',' order by c.id) from public.commissions c where c.invoice_id = v) = c0
      and pg_temp.kept('KA', 'p2') = 'own',
    'R2 the preview: tier 1 15.00 to 4.50, tier 2 5.25 to 1.58, and nothing changes: ' || left(t, 200));
  -- refusals
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, null, %L, null)::text', v, '{"tier1_own": 14}', '  '));
  perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('reason'), 'R3 no reason: ' || t);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, null, %L, null)::text', v, '{"tier1_own": 150}', 'M538'));
  perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('rate'), 'R3b a rate of 150: ' || t);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, null, %L, null)::text', v, '{"tier3": 1}', 'M538'));
  perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('rate'), 'R3c a rate that is not one of the four: ' || t);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, null, %L::jsonb, %L, null)::text', v,
       jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'kind', 'partner')), 'M538'));
  perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('kind'), 'R3d a kind out of place: ' || t);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, null, %L::jsonb, %L, null)::text', v,
       jsonb_build_array(jsonb_build_object('invoice_item_id', gen_random_uuid(), 'kind', 'own')), 'M538'));
  perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('line'), 'R3e a line not on the invoice: ' || t);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, null, %L, null)::text', v, '{"tier1_own": 15}', 'M538'));
  perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('same'), 'R3f nothing different: ' || t);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, null, %L, null)::text',
       (select i.id from public.invoices i where i.customer_id = pg_temp.fx('c:KA') and false union all select pg_temp.fx('st')), '{"tier1_own": 14}', 'M538'));
  perform pg_temp.check(t like 'ERR P0001 Invoice not found.%', 'R3g not an invoice: ' || t);
end $R$;
-- R4 an invoice that keeps no rates: KZ2, paid by a buyer with no referrer
do $R4$
declare v uuid; t text; b uuid;
begin
  insert into public.customers(full_name, phone) values ('M538 Lone Buyer', pg_temp.ph(70)) returning id into b;
  perform pg_temp.put('c:lone', b);
  v := pg_temp.inv('lone', 'lone', array['p']);
  perform pg_temp.pay('lone', 100);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, null, %L, null)::text', v, '{"tier1_own": 14}', 'M538'));
  perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('none'), 'R4 an invoice that keeps no rates: ' || t);
end $R4$;
-- R5 the Owner corrects a paid-out line: own to third party, with a reason; 410 nets what was paid
select pg_temp.pay_out('t1:KA', pg_temp.amt('KA', 'tier1'));
do $R5$
declare t text; v uuid := pg_temp.fx('i:KA'); item uuid; rq uuid := gen_random_uuid(); n0 int; j jsonb;
begin
  select id into item from public.invoice_items where invoice_id = v and product_id = pg_temp.fx('p2');
  n0 := (select count(*) from public.audit_logs where action = 'invoice_commission_basis_corrected' and record_id = v);
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, %L::jsonb, %L, %L)::text', v, '{}',
       jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'kind', 'third_party')), 'M538 sold as a partner product', rq));
  j := case when t like 'ok:%' then substr(t, 4)::jsonb end;
  perform pg_temp.check(j -> 'after' = '{"tier1": 4.50, "tier2": 1.58}'::jsonb and pg_temp.amts('KA') = '4.50/1.58' and pg_temp.kept('KA', 'p2') = 'third_party',
    'R5 the Owner''s correction: kept third party, the commission worked out again (4.50 / 1.58): ' || left(t, 160) || ' ' || pg_temp.amts('KA'));
  perform pg_temp.check(exists (select 1 from public.commissions c where c.invoice_id = v and c.tier = 'tier1' and c.status = 'earned'
                                   and c.commission_amount < 0 and c.adjusts_commission_id is not null),
    'R5b what was paid out (15.00) is netted against what it earns now (410): a take-back row stands');
  perform pg_temp.check(exists (select 1 from public.audit_logs a where a.record_id = v and a.action = 'invoice_commission_basis_corrected'
                                   and a.reason = 'M538 sold as a partner product' and a.module = 'commission'
                                   and a.old_data -> 'kinds' ->> item::text = 'own' and a.new_data -> 'kinds' ->> item::text = 'third_party'
                                   and a.new_data -> 'before' ->> 'tier1' = '15.00' and a.new_data -> 'after' ->> 'tier1' = '4.50'
                                   and a.changed_by = pg_temp.fx('own') and a.actor_role = 'owner'),
    'R5c the audit entry: old and new kinds, the totals before and after, the reason, the Owner');
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, %L::jsonb, %L, %L)::text', v, '{}',
       jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'kind', 'third_party')), 'M538 sold as a partner product', rq));
  perform pg_temp.check(t like 'ok:%' and (select count(*) from public.audit_logs where action = 'invoice_commission_basis_corrected' and record_id = v) = n0 + 1
      and pg_temp.amts('KA') = '4.50/1.58', 'R5d the same request again returns its first answer and changes nothing: ' || left(t, 60));
  t := pg_temp.as_('own', format('select public.correct_invoice_commission_basis(%L, %L::jsonb, null, %L, null)::text', v, '{"tier1_own": 20, "tier2_third": 40}', 'M538 rates'));
  perform pg_temp.check(t like 'ok:%' and (select tier1_own_rate || '/' || tier2_third_rate from public.invoice_affiliate_rates where invoice_id = v) = '20/40'
      and pg_temp.amts('KA') = '4.50/1.80', 'R6 the Owner corrects kept rates too (tier 2 third party 40: 1.80): ' || pg_temp.amts('KA'));
end $R5$;
select pg_temp.as_('own', format('select public.invoice_commission_kept_basis(%L)::text', pg_temp.fx('i:KA'))) as r7 \gset
select pg_temp.check(:'r7' like 'ok:%' and (substr(:'r7', 4)::jsonb -> 'rates' ->> 'tier1_own') = '20'
                     and jsonb_array_length(substr(:'r7', 4)::jsonb -> 'lines') = 1
                     and (substr(:'r7', 4)::jsonb -> 'lines' -> 0 ->> 'kind') = 'third_party',
  'R7 the Owner''s window reads the kept rates and each line''s kind: ' || left(:'r7', 200));

-- ═════ G 538's fixed parts ═════
\if :is_control
\echo NOTE  G, U and M are skipped (control)
\else
create temp table g538(fn text, after_md5 text, acl text);
insert into g538 values
  ('earn_invoice_commission(uuid)', '8d7ccdee4eae2359b56995ebf60dbcfa', 'postgres=X/postgres,service_role=X/postgres'),
  ('invoice_affiliate_commission_preview(uuid)', 'df92dacb660319a7c4ae44b439b1adaf', 'postgres=X/postgres,service_role=X/postgres'),
  ('earn_credit_package_commission(uuid)', 'd2d6c3a32c89a329852d2680aa66e504', 'postgres=X/postgres,service_role=X/postgres'),
  ('earn_premium_bundle_commission(uuid)', '5bb0f5bf338a73f4b040dac2cf9e905c', 'postgres=X/postgres,service_role=X/postgres'),
  ('sync_instalment_commissions(uuid,text,date,boolean,boolean)', '1f56177897bb6b67c276626128184c86', 'postgres=X/postgres,service_role=X/postgres'),
  ('invoice_line_kinds_for(uuid)', 'bb51dfc8861272bc615dd0630f2a9acf', 'postgres=X/postgres'),
  ('invoice_has_unkept_line_kinds(uuid)', 'c290de63f7dafbee0ac84cfd7c3260a8', 'postgres=X/postgres'),
  ('record_invoice_line_kinds(uuid,jsonb)', '125d4d8fd4311f4b6683e73a99f03425', 'postgres=X/postgres'),
  ('invoice_commission_correction_apply(uuid,jsonb,jsonb,text)', '7eef1a9a0af66041c3c9fda94a168f09', 'postgres=X/postgres'),
  ('invoice_commission_kept_basis(uuid)', '744568fa22216bd52b92810e46a82165', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('preview_invoice_commission_correction(uuid,jsonb,jsonb)', '96d01915bbf6787d773ece636fb654cf', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('correct_invoice_commission_basis(uuid,jsonb,jsonb,text,uuid)', '4e8433353b98a5b824e00b39eda11c18', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres');
select pg_temp.check(not exists (select 1 from g538 g where md5(pg_get_functiondef(to_regprocedure('public.' || g.fn))) is distinct from g.after_md5),
  'G1 the five functions and seven new ones are 538''s (AFTER md5s)');
select pg_temp.check(not exists (select 1 from g538 g where (select coalesce(string_agg(x::text, ',' order by x::text), '')
                                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || g.fn)) is distinct from g.acl),
  'G2 their grants: the helpers postgres''s alone, the Owner''s three for signed-in logins (the Owner test inside), the others as before');
select pg_temp.check((select string_agg(x::text, ',') from pg_class c, unnest(c.relacl) x where c.oid = 'public.invoice_line_commission_kinds'::regclass) = 'postgres=arwdDxtm/postgres'
                     and (select relrowsecurity from pg_class where oid = 'public.invoice_line_commission_kinds'::regclass)
                     and not has_table_privilege('service_role', 'public.invoice_line_commission_kinds', 'insert'),
  'G3 no login and not the service role reads or writes the kept kinds');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                    and pg_get_functiondef(p.oid) ~ 'invoice_line_kinds_for|record_invoice_line_kinds|invoice_has_unkept_line_kinds|invoice_commission_correction_apply'
                                    and p.proname not in ('invoice_line_kinds_for', 'record_invoice_line_kinds', 'invoice_has_unkept_line_kinds',
                                                          'invoice_commission_correction_apply')
                                    and not (p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres')),
  'G4 every function that calls the helpers is a postgres-owned SECURITY DEFINER function');
select pg_temp.check(md5(pg_get_functiondef('public.reconcile_invoice_commissions(uuid,text)'::regprocedure)) = '3c267728e215d17ebeb9cfe9cb7db47c'
    and md5(pg_get_functiondef('public.promotion_commission_items(uuid,uuid,integer,text)'::regprocedure)) = '4cd784251e0c6a5861b004d91e50389c'
    and md5(pg_get_functiondef('public.invoice_affiliate_rates_for(uuid)'::regprocedure)) = '64e6ed85a8f169477fc85bd8452da453'
    and md5(pg_get_functiondef('public.record_invoice_affiliate_rates(uuid,numeric,numeric,numeric,numeric)'::regprocedure)) = 'ae5132e23be0b0acbdec3d92e500bd4c',
  'G5 the relied-on functions (reconcile, a promotion''s items, 535''s helpers) are unchanged');
\if :by_us
select pg_temp.check((select string_agg(coalesce(a.fn, b.fn), ', ' order by coalesce(a.fn, b.fn))
                        from fn0 a full join fn1 b using (fn) where a.md5 is distinct from b.md5)
                     = (select string_agg(fn, ', ' order by fn) from g538),
  'G6 installed here, only the five functions and the seven new ones changed');
-- ═════ U The undo, then 538 again ═════
savepoint u1;
\ir ../undo-538.sql
select pg_temp.check(not exists (select 1 from fn0 a full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) b using (fn)
                                  where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
                     and to_regclass('public.invoice_line_commission_kinds') is null,
  'U1 undo-538 puts every function and grant back exactly and drops the table');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-538.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 538: % is already its version of before 538%', 'U2 the undo a second time refuses: ' || :'LAST_ERROR_MESSAGE');
-- After the undo, KA's line holds a paid own row and, since the Owner's correction, third-party
-- rows: 538 again cannot tell the kind it earned as, and refuses (rolled back). KA's third-party
-- rows are marked reversed here (rolled back below), and 538 goes in again.
savepoint u2b;
\set ON_ERROR_STOP off
\ir ../../../supabase/538_an_invoice_line_keeps_the_commission_kind_it_first_earned_as.sql
\set ON_ERROR_STOP on
rollback to savepoint u2b;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '538: % line(s) on % invoice(s) have standing commission rows of more than one kind%',
  'U2b 538 again after the undo refuses while an Owner-corrected line holds rows of two kinds: ' || :'LAST_ERROR_MESSAGE');
alter table public.commissions disable trigger user;
update public.commissions set status = 'reversed' where invoice_id = pg_temp.fx('i:KA') and product_type = 'third_party';
alter table public.commissions enable trigger user;
\ir ../../../supabase/538_an_invoice_line_keeps_the_commission_kind_it_first_earned_as.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl),
  'U3 538 after the undo makes exactly what it made the first time');
rollback to savepoint u1;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/538_an_invoice_line_keeps_the_commission_kind_it_first_earned_as.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '538 is already in on this database%', 'M1 538 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  G6, U and M are skipped (538 was not installed by this file)
\endif
\endif

select count(*) as n_failed from failed \gset
\if :is_control
\echo control: :n_failed checks failed without 538 (each is one 538 makes pass)
select string_agg(split_part(msg, ' ', 1), ' ' order by n) as control_failed from failed \gset
\echo control failed: :control_failed
rollback;
\else
do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
\endif
