-- The check of 538's backfill, on a copy WITHOUT 538 (after 535) (security audit of 17 Nov 2026,
-- M12; the user, 25 Nov 2026: "Keep each line's type"). Everything is in one transaction and
-- rolled back; it prints counts and sums only, never a customer, a name or an invoice number.
--
--   1. The standing commission rows (earned, paid or blocked, adjusting no other row, above 0) on
--      lines with a product: how many carry their product's type now, and how many do not.
--   2. For every invoice with kept rates (535): what its referrers hold now, per referrer, tier and
--      kind (earned and paid rows).
--   3. The same after a reconcile of each, before 538 (each rolled back by itself): an invoice
--      whose product's type changed since it earned is re-priced (the fault 538 closes).
--   4. 538 is applied (in this transaction): how many lines it kept, and how many keep a kind other
--      than their product's type now.
--   5. The same reconcile after 538 (each rolled back): every invoice must earn what it stands at in
--      2, or (where its standing rows came from an older rule) what the rework gave before 538 in 3;
--      and the sums per tier, standing, after and reworked before.
-- It fails (and still rolls back) if an invoice matches neither in 5.
--
-- Production, read only on 25 Nov 2026: 125 invoices with kept rates, 245 standing rows, 140 of
-- them on lines with no product; exactly 1 differs from its product's type now (own, now
-- third_party; 1 invoice, paid out, S$103.20). Locally, -v seed=1 first makes two made-up invoices
-- of that shape (one paid out whose product is then made third party, one with a no-commission
-- line). Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 [-v seed=1] -f scripts/commissions/tests/backfill-rehearsal-538.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '0';
do $$ begin
  if to_regclass('public.invoice_affiliate_rates') is null then
    raise exception 'rehearsal: 535 is not in on this copy; 538 builds on it'; end if;
  if to_regclass('public.invoice_line_commission_kinds') is not null then
    raise exception 'rehearsal: 538 is already in on this copy; run it on a copy without 538'; end if;
end $$;

\if :{?seed}
do $seed$
declare own uuid := gen_random_uuid(); st uuid; m uuid; p uuid; pz uuid; t2 uuid; t1 uuid; b uuid; n int; v uuid;
        s text := lower(substr(md5(gen_random_uuid()::text), 1, 6)); ph int := (floor(random() * 900))::int;
begin
  insert into auth.users(id, email) values (own, 'r538-owner-' || s || '@example.invalid');
  insert into public.profiles(id, full_name, email, role) values (own, 'R538 Owner', 'r538-owner-' || s || '@example.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into public.app_settings(id) values (true) on conflict do nothing;
  update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
    commission_tier2_own_rate = 35, commission_tier2_third_rate = 35 where id = true;
  insert into public.stores(name, code, country_code) values ('R538 Store', 'R538' || s, 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (own, st);
  insert into public.payment_methods(name, is_active) values ('R538 Cash ' || s, true) returning id into m;
  insert into public.products(name, sku, product_type) values ('R538 Item', 'R538-I-' || s, 'own') returning id into p;
  insert into public.products(name, sku, product_type) values ('R538 Session', 'R538-S-' || s, 'no_commission') returning id into pz;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 50);
  perform public.set_product_prices(st, p, 100, 100, 'available');
  perform public.set_product_prices(st, pz, 50, 50, 'available');
  for n in 1 .. 2 loop
    insert into public.customers(full_name, phone) values ('R538 T2 ' || n, '+61491570' || lpad(((ph + n * 3) % 1000)::text, 3, '0')) returning id into t2;
    insert into public.customers(full_name, phone, referred_by) values ('R538 T1 ' || n, '+61491570' || lpad(((ph + n * 3 + 1) % 1000)::text, 3, '0'), t2) returning id into t1;
    insert into public.customers(full_name, phone, referred_by) values ('R538 Buyer ' || n, '+61491570' || lpad(((ph + n * 3 + 2) % 1000)::text, 3, '0'), t1) returning id into b;
    insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (t2, 'active', st, now()), (t1, 'active', st, now());
    v := public.create_invoice(st, b, null, case when n = 1 then jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', p, 'quantity', 1))
                                                else jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', p, 'quantity', 1),
                                                                       jsonb_build_object('kind', 'product', 'product_id', pz, 'quantity', 1)) end,
                               0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', m, 'amount', case when n = 1 then 100 else 150 end)), gen_random_uuid());
    if n = 1 then
      perform public.affiliate_payout_save(null, null, t1, date_trunc('month', public.sg_today()::timestamp)::date, 15, m, public.sg_today(), 'R538 payout', null, null, gen_random_uuid());
    end if;
  end loop;
  update public.products set product_type = 'third_party' where id = p;
end $seed$;
\endif

-- 1. The standing rows against their products' types now
select 'standing rows on product lines: ' || count(*) || '; at their product''s type now ' || count(*) filter (where c.product_type::text = coalesce(p.product_type::text, 'own'))
       || ', other ' || count(*) filter (where c.product_type::text is distinct from coalesce(p.product_type::text, 'own'))
       || ' (' || coalesce(sum(c.commission_amount) filter (where c.product_type::text is distinct from coalesce(p.product_type::text, 'own')), 0) || ' S$, on '
       || count(distinct c.invoice_id) filter (where c.product_type::text is distinct from coalesce(p.product_type::text, 'own')) || ' invoice(s))' as line
  from public.commissions c
  join public.invoice_items ii on ii.id = c.invoice_item_id and ii.line_kind::text = 'product'
  left join public.products p on p.id = ii.product_id
 where c.status::text in ('earned','paid','blocked') and c.adjusts_commission_id is null and c.commission_amount > 0;

create temp table seen(phase text, inv uuid, net text, t1 numeric, t2 numeric, primary key (phase, inv));
create function pg_temp.net(v uuid) returns text language sql as $$
  select coalesce(string_agg(r, ' ' order by r), '-') from (
    select c.referrer_customer_id || '|' || c.tier || '|' || c.product_type || '|' || sum(c.commission_amount) as r
      from public.commissions c where c.invoice_id = v and c.status in ('earned','paid')
     group by c.referrer_customer_id, c.tier, c.product_type having sum(c.commission_amount) <> 0) q $$;
create function pg_temp.tot(v uuid, t text) returns numeric language sql as $$
  select coalesce(sum(c.commission_amount), 0) from public.commissions c where c.invoice_id = v and c.status in ('earned','paid') and c.tier::text = t $$;
create function pg_temp.look(p_phase text, p_rework boolean) returns int language plpgsql as $$
declare v uuid; t text; a1 numeric; a2 numeric; n int := 0;
begin
  for v in select r.invoice_id from public.invoice_affiliate_rates r loop
    t := null; a1 := null; a2 := null;
    if p_rework then
      begin
        perform public.reconcile_invoice_commissions(v, 'Rehearsal 538 (rolled back)');
        t := pg_temp.net(v); a1 := pg_temp.tot(v, 'tier1'); a2 := pg_temp.tot(v, 'tier2');
        raise exception 'R538_ROLLBACK';
      exception when others then
        if sqlerrm <> 'R538_ROLLBACK' then t := 'ERR ' || sqlerrm; a1 := null; a2 := null; end if;
      end;
    else
      t := pg_temp.net(v); a1 := pg_temp.tot(v, 'tier1'); a2 := pg_temp.tot(v, 'tier2');
    end if;
    insert into seen values (p_phase, v, t, a1, a2); n := n + 1;
  end loop;
  return n;
end $$;
select 'invoices with kept rates, standing: ' || pg_temp.look('standing', false) as line;
select 'reworked before 538: ' || pg_temp.look('before', true) || ' invoices' as line;
select 'of them re-priced by the rework before 538: '
       || (select count(*) from seen b join seen s on s.inv = b.inv and s.phase = 'standing' where b.phase = 'before' and b.net is distinct from s.net) as line;

-- 4. 538, in this transaction
\ir ../../../supabase/538_an_invoice_line_keeps_the_commission_kind_it_first_earned_as.sql

select 'reworked after 538: ' || pg_temp.look('after', true) || ' invoices' as line;
select 'after 538, identical to standing: '
       || (select count(*) from seen a join seen s on s.inv = a.inv and s.phase = 'standing' where a.phase = 'after' and a.net is not distinct from s.net)
       || '; identical to the rework before 538: ' || (select count(*) from seen a join seen b on b.inv = a.inv and b.phase = 'before' where a.phase = 'after' and a.net is not distinct from b.net)
       || '; matching neither: ' || (select count(*) from seen a join seen s on s.inv = a.inv and s.phase = 'standing' join seen b on b.inv = a.inv and b.phase = 'before'
                                      where a.phase = 'after' and a.net is distinct from s.net and a.net is distinct from b.net) as line;
select 'totals: tier 1 ' || sum(t1) filter (where phase = 'standing') || ' S$ standing, ' || sum(t1) filter (where phase = 'after') || ' S$ after 538, '
       || sum(t1) filter (where phase = 'before') || ' S$ reworked before 538; tier 2 ' || sum(t2) filter (where phase = 'standing') || ' / '
       || sum(t2) filter (where phase = 'after') || ' / ' || sum(t2) filter (where phase = 'before') as line
  from seen;
do $$ begin
  -- An invoice must earn after 538 what it stands at (its kept kinds are its rows' kinds), or, where
  -- its standing rows came from an older rule, what a rework gave before 538 (538 changes nothing
  -- else).
  if exists (select 1 from seen a join seen s on s.inv = a.inv and s.phase = 'standing' join seen b on b.inv = a.inv and b.phase = 'before'
              where a.phase = 'after' and a.net is distinct from s.net and a.net is distinct from b.net)
     or (select count(*) from seen where phase = 'after') <> (select count(*) from seen where phase = 'standing') then
    raise exception 'rehearsal: some invoice would earn after 538 neither what it stands at nor what a rework gave before (rolled back)'; end if;
  raise notice 'rehearsal: every invoice with kept rates earns after 538 what it stands at, or what a rework gave before 538 (rolled back)';
end $$;
rollback;
