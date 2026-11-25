-- The local check of 535's backfill, on a copy WITHOUT 535 (security audit of 17 Nov 2026, M12;
-- the user, 24 Nov 2026: "Design it so that today's amounts do not change on production data").
-- Everything is in one transaction and rolled back; it prints counts and sums only, never a
-- customer, a name or an invoice number.
--
-- No rehearsal on production data is needed: production, read only on 24 Nov 2026, has 125
-- invoices with commission rows (122 with earned, paid or blocked rows); every earned, paid and
-- blocked row's rate is today's settings rate for its tier and kind (tier 1 own 15, third party
-- 4.5; tier 2 35 and 35), only 2 reversed rows (10 Sep 2026) carry tier 2 own 5, and every sale's
-- snapshot rate is null. The backfill keeps today's settings, so it is neutral by construction.
-- This file proves the same on made-up rows of that shape (-v seed=1), and can be run on any
-- local copy.
--
--   1. How the commission rows' rates stand against the settings today: per status class (live =
--      earned or paid; blocked; reversed) and tier, how many rows carry the settings rate for their
--      tier and kind, and how many do not (package and bundle rows with their own snapshot rate
--      are counted apart).
--   2. For every invoice with a commission row: what the two previews say and what a reconcile
--      earns, each in a step rolled back by itself, before 535.
--   3. 535 is applied (in this transaction): how many invoices it backfilled, and that each has
--      the settings rates.
--   4. The same per invoice after 535, compared: identical, different, and refused alike (an
--      invoice whose reconcile refuses for its own reasons, before and after); and the sums of
--      what the reconciles earn per tier, before and after.
-- It fails (and still rolls back) if any invoice differs.
--
-- A reconcile here is a rolled-back check per invoice, never a refresh: nothing it writes stays.
-- Locally, -v seed=1 first makes three made-up invoices (one paid, one whose only rows are
-- reversed at tier 2 own 5%, one paid in part), as the suite does. Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 [-v seed=1] -f scripts/commissions/tests/backfill-rehearsal-535.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '0';
do $$ begin
  if to_regclass('public.invoice_affiliate_rates') is not null then
    raise exception 'rehearsal: 535 is already in on this copy; run it on a copy without 535'; end if;
end $$;

\if :{?seed}
do $seed$
declare own uuid := gen_random_uuid(); st uuid; m uuid; p uuid; pk uuid; t2 uuid; t1 uuid; b uuid; n int; v uuid;
        s text := lower(substr(md5(gen_random_uuid()::text), 1, 6)); ph int := (floor(random() * 900))::int;
begin
  insert into auth.users(id, email) values (own, 'r535-owner-' || s || '@example.invalid');
  insert into public.profiles(id, full_name, email, role) values (own, 'R535 Owner', 'r535-owner-' || s || '@example.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into public.app_settings(id) values (true) on conflict do nothing;
  update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
    commission_tier2_own_rate = 35, commission_tier2_third_rate = 35, staff_commission_rate = 3,
    instalment_commission_from = public.sg_today() - 100 where id = true;
  insert into public.stores(name, code, country_code) values ('R535 Store', 'R535' || s, 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (own, st);
  insert into public.payment_methods(name, is_active) values ('R535 Cash ' || s, true) returning id into m;
  insert into public.products(name, sku, product_type) values ('R535 Item', 'R535-I-' || s, 'own') returning id into p;
  insert into public.products(name, sku, product_type) values ('R535 Chair', 'R535-C-' || s, 'own') returning id into pk;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 50), (st, pk, 50);
  perform public.set_product_prices(st, p, 100, 100, 'available');
  perform public.set_product_prices(st, pk, 1000, 1000, 'available');
  for n in 1 .. 3 loop
    insert into public.customers(full_name, phone) values ('R535 T2 ' || n, '+61491570' || lpad(((ph + n * 3) % 1000)::text, 3, '0')) returning id into t2;
    insert into public.customers(full_name, phone, referred_by) values ('R535 T1 ' || n, '+61491570' || lpad(((ph + n * 3 + 1) % 1000)::text, 3, '0'), t2) returning id into t1;
    insert into public.customers(full_name, phone, referred_by) values ('R535 Buyer ' || n, '+61491570' || lpad(((ph + n * 3 + 2) % 1000)::text, 3, '0'), t1) returning id into b;
    insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (t2, 'active', st, now()), (t1, 'active', st, now());
    v := public.create_invoice(st, b, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', case when n = 3 then pk else p end, 'quantity', 1)),
                               0::numeric, null::text, null::uuid, '[]'::jsonb);
    if n = 2 then update public.app_settings set commission_tier2_own_rate = 5 where id = true; end if;
    perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', m, 'amount', case when n = 3 then 400 else 100 end)), gen_random_uuid());
    if n = 2 then
      update public.app_settings set commission_tier2_own_rate = 35 where id = true;
      update public.commissions set status = 'reversed', reversed_at = now(), reversal_reason = 'R535 reversed' where invoice_id = v;
    end if;
  end loop;
end $seed$;
\endif

-- 1. The rows' rates against the settings today
select 'rows ' || cls || ' ' || tier || ': ' || count(*) || ' rows, ' || coalesce(sum(commission_amount), 0) || ' S$; at the settings rate '
       || count(*) filter (where at_settings) || ', own package/bundle rate ' || count(*) filter (where own_rate)
       || ', other ' || count(*) filter (where not at_settings and not own_rate) as line
  from (select case when c.status in ('earned','paid') then 'live' else c.status::text end as cls, c.tier::text as tier, c.commission_amount,
               c.rate = case when c.tier = 'tier1' and c.product_type::text = 'third_party' then a.commission_tier1_third_rate
                             when c.tier = 'tier1' then a.commission_tier1_own_rate
                             when c.product_type::text = 'third_party' then a.commission_tier2_third_rate
                             else a.commission_tier2_own_rate end as at_settings,
               exists (select 1 from public.credit_package_sales s where s.invoice_id = c.invoice_id
                         and c.rate = coalesce(case when c.tier = 'tier1' then s.tier1_rate_snapshot else s.tier2_rate_snapshot end, -1))
               or exists (select 1 from public.premium_bundle_sales s where s.invoice_id = c.invoice_id
                         and c.rate = coalesce(case when c.tier = 'tier1' then s.tier1_rate_snapshot else s.tier2_rate_snapshot end, -1)) as own_rate
          from public.commissions c cross join public.app_settings a
         where a.id and c.adjusts_commission_id is null and c.commission_amount > 0) q
 group by cls, tier order by cls, tier;

-- 2. and 4. Per invoice: the previews and a rolled-back reconcile
create temp table seen(phase text, inv uuid, preview text, reearned text, t1 numeric, t2 numeric, primary key (phase, inv));
create function pg_temp.look(p_phase text) returns int language plpgsql as $$
declare v uuid; pv text; re text; a1 numeric; a2 numeric; n int := 0;
begin
  for v in select distinct c.invoice_id from public.commissions c where c.invoice_id is not null loop
    select coalesce(string_agg(concat_ws('|', o_invoice_item_id, o_referrer, o_tier, o_product_type, o_line_amount, o_rate, o_amount, o_status), ' ' order by 1), '-')
      into pv from (select * from public.invoice_affiliate_commission_preview(v)
                    union all select * from public.invoice_package_commission_preview(v)) q;
    re := null; a1 := null; a2 := null;
    begin
      perform public.reconcile_invoice_commissions(v, 'Rehearsal 535 (rolled back)');
      select coalesce(string_agg(concat_ws('|', c.referrer_customer_id, c.tier, c.product_type, c.invoice_item_id, c.line_amount,
                                           c.rate, c.commission_amount, c.status, c.block_reason, c.invoice_paid_date, c.earning_basis,
                                           c.adjusts_commission_id is not null, split_part(coalesce(c.reversal_reason, ''), ':', 1)), ' ' order by 1), '-'),
             sum(c.commission_amount) filter (where c.tier = 'tier1' and c.status in ('earned','paid')),
             sum(c.commission_amount) filter (where c.tier = 'tier2' and c.status in ('earned','paid'))
        into re, a1, a2 from public.commissions c where c.invoice_id = v and c.status in ('earned','paid','blocked');
      raise exception 'R535_ROLLBACK';
    exception when others then
      if sqlerrm <> 'R535_ROLLBACK' then re := 'ERR ' || sqlerrm; a1 := null; a2 := null; end if;
    end;
    insert into seen values (p_phase, v, pv, re, a1, a2);
    n := n + 1;
  end loop;
  return n;
end $$;
select 'invoices with commission rows, looked at before 535: ' || pg_temp.look('before') as line;

-- 3. 535, in this transaction
\ir ../../../supabase/535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own.sql
select 'backfilled: ' || count(*) || ' invoices; with the settings rates: '
       || count(*) filter (where (r.tier1_own_rate, r.tier1_third_rate, r.tier2_own_rate, r.tier2_third_rate)
                                 = (a.commission_tier1_own_rate, a.commission_tier1_third_rate, a.commission_tier2_own_rate, a.commission_tier2_third_rate))
       || '; marked backfilled: ' || count(*) filter (where r.backfilled) as line
  from public.invoice_affiliate_rates r cross join public.app_settings a where a.id;

select 'invoices looked at after 535: ' || pg_temp.look('after') as line;
select 'per invoice: ' || count(*) || ' compared; identical ' || count(*) filter (where (a.preview, a.reearned) is not distinct from (b.preview, b.reearned))
       || ' (of which refused alike by reconcile ' || count(*) filter (where b.reearned like 'ERR %' and a.reearned is not distinct from b.reearned) || ')'
       || '; previews differ ' || count(*) filter (where a.preview is distinct from b.preview)
       || '; reconcile differs ' || count(*) filter (where a.reearned is distinct from b.reearned) as line
  from seen b join seen a on a.inv = b.inv and a.phase = 'after' where b.phase = 'before';
select 'reconciled, live tier 1: ' || coalesce(sum(t1) filter (where phase = 'before'), 0) || ' S$ before, ' || coalesce(sum(t1) filter (where phase = 'after'), 0)
       || ' S$ after; tier 2: ' || coalesce(sum(t2) filter (where phase = 'before'), 0) || ' S$ before, ' || coalesce(sum(t2) filter (where phase = 'after'), 0) || ' S$ after' as line
  from seen;
do $$ begin
  if (select count(*) from seen where phase = 'before') <> (select count(*) from seen where phase = 'after')
     or exists (select 1 from seen b join seen a on a.inv = b.inv and a.phase = 'after'
                 where b.phase = 'before' and (a.preview, a.reearned) is distinct from (b.preview, b.reearned)) then
    raise exception 'rehearsal: some invoice would be worked out differently after 535 (rolled back)'; end if;
  raise notice 'rehearsal: every invoice is worked out the same before and after 535 (rolled back)';
end $$;
rollback;
