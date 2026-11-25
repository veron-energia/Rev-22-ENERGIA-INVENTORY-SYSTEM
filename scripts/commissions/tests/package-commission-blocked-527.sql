-- Package and bundle commission is blocked, as a product line's is, when the referrer may not
-- earn (527; security audit of 17 Nov 2026, M2; the user, 18 Nov 2026: "Block them like
-- products").
--
-- Every invoice goes through the app's own calls: the invoice form (create_invoice), Record
-- Payment (record_invoice_payment, in full or in part), Suspend on the affiliate's page
-- (suspend_affiliate), a payout (record_affiliate_payout); a correction, refund or reopening
-- works commission out again by reconcile_invoice_commissions, called here directly.
-- Production's rates (tier 1 15% own, 4.5% third party; tier 2 35% of tier 1); a Credit
-- Package of S$1000 earns tier 1 45.00 and tier 2 15.75, a Premium Bundle of S$2000 90.00 and
-- 31.50, a S$100 product 15.00 and 5.25.
--
--   E  Both tiers eligible affiliates: a package and a bundle earn both tiers 'earned', no
--      reason, the amounts above (as before 527).
--   S  Tier 1 suspended (Suspend, before the payment): its package row 'blocked' with
--      'Affiliate Suspended', as the product line on the same invoice; tier 2 judged on its
--      own: an eligible tier 2 earns. A bundle whose invoice names the affiliate (chosen while
--      active, suspended before payment), whose tier 2 was never activated: both blocked, each
--      with its own reason.
--   N  Tier 1 never approved (a plain customer who referred the buyer): 'Affiliate Not
--      Activated', tier 2 eligible earns. A bundle whose tier 1 is an inactive (deleted)
--      customer: 'Customer Inactive'.
--   T  Tier 1 eligible, tier 2 suspended: tier 1 earned, tier 2 blocked.
--   R  reconcile_invoice_commissions on each of them: every row before is reversed, and the
--      rows earned again have the same tiers, statuses, reasons and amounts.
--   P  Payable: affiliate_month_balances and affiliate_referrer_balances (what the Commissions
--      page and payouts use) count none of a blocked package or bundle row, as none of a
--      blocked product row; an eligible referrer's package and bundle commission counts in full.
--   I  An invoice paid in part (the part-payment layer, 357): a suspended tier 1's share is
--      booked 'blocked' with its reason, an eligible tier 2's 'earned'; paid in full, tier 1
--      holds nothing payable and tier 2 its 15.75. An eligible tier 1 earns its part as before.
--   X  Paid out, then suspended, then worked out again: the package row earned again is
--      blocked, so what was paid out on it is taken back from later commission, exactly as for
--      the product line on the same invoice (before 527 the package part stayed with them).
--   G  527's AFTER md5s, the grants (the service role only), the relied-on functions unchanged.
--   B  The same invoices under the functions of before 527 (undo-527, in a savepoint): an
--      eligible referrer's rows are identical; a blocked one's were 'earned' (the fault).
--   U  scripts/commissions/undo-527.sql puts the three functions back (their BEFORE md5s and
--      grants); 527 again makes them as 527 did.
--   M  527 a second time changes nothing (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.invalid); phones are the fictional +61 491 570 ... range. Run it on a copy of
-- production as it is (after 526): it applies 527 twice; with -v skip_install=1 where 527 is
-- already in; with -v control=1 on a copy WITHOUT 527 (it does not install it, skips G, B, U
-- and M, and fails on exactly the checks 527 makes pass: S1, S2, N1, N2, T1, T2, R2, P1, I1, I3
-- and X2). Every check runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
\if :{?control}
do $$ begin
  if position('-- 527 (security audit' in pg_get_functiondef('public.earn_credit_package_commission(uuid)'::regprocedure)) > 0 then
    raise exception 'control: 527 is in on this copy; run -v control=1 on a copy without it'; end if;
end $$;
\elif :{?skip_install}
\else
\ir ../../../supabase/527_package_commission_blocked_like_products.sql
create temp table m527 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
\ir ../../../supabase/527_package_commission_blocked_like_products.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- The fixture's name of a customer (its key), for readable rows.
create function pg_temp.who(id uuid) returns text language sql as
$$ select coalesce((select k from fx where v = id and k like 'c:%' limit 1), id::text) $$;
-- Fictional phones: +61 491 570 nnn, one block per run.
create function pg_temp.ph(n int) returns text language sql as
$$ select '+61491570' || lpad(((pg_temp.tx('phbase')::int + n) % 1000)::text, 3, '0') $$;
-- A customer, optionally referred by another, optionally an affiliate.
create function pg_temp.cust(key text, n int, ref text, aff boolean) returns uuid language plpgsql as $$
declare c uuid; a uuid;
begin
  insert into public.customers(full_name, first_name, last_name, phone, email, referred_by)
  values ('M527 ' || key, 'M527', key, pg_temp.ph(n), 'm527-' || lower(key) || '-' || pg_temp.tx('sfx') || '@example.invalid',
          case when ref is not null then pg_temp.fx('c:' || ref) end)
  returning id into c;
  insert into fx values ('c:' || key, c);
  if aff then
    insert into public.customer_affiliates(customer_id, status, store_id, activated_at)
    values (c, 'active', pg_temp.fx('st'), now()) returning id into a;
    insert into fx values ('a:' || key, a);
  end if;
  return c;
end $$;
-- An invoice: 'cp' the package, 'pb' the bundle, 'p' the product; the buyer; the affiliate it
-- names (null: none, so the buyer's referrer is tier 1).
create function pg_temp.inv(key text, buyer text, aff text, kinds text[]) returns uuid language plpgsql as $$
declare v uuid; items jsonb := '[]'::jsonb; k text;
begin
  foreach k in array kinds loop
    items := items || case k
      when 'cp' then jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)
      when 'pb' then jsonb_build_object('kind','premium_bundle','premium_bundle_id',pg_temp.fx('pb'),'quantity',1,'voucher_selection','[]'::jsonb)
      when 'p'  then jsonb_build_object('kind','product','product_id',pg_temp.fx('p'),'quantity',1) end;
  end loop;
  v := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('c:' || buyer), case when aff is not null then pg_temp.fx('a:' || aff) end,
                             items, 0::numeric, null::text, null::uuid, '[]'::jsonb);
  insert into fx values ('i:' || key, v);
  return v;
end $$;
create function pg_temp.pay(key text, amount numeric) returns void language sql as $$
  select public.record_invoice_payment(pg_temp.fx('i:' || key),
           jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('m'), 'amount', amount)), gen_random_uuid()) $$;
create function pg_temp.suspend(key text) returns void language sql as $$
  select public.suspend_affiliate(pg_temp.fx('c:' || key), 'M527 test: suspended') $$;
-- An invoice's settlement rows that stand (earned, paid or blocked): referrer:tier:status:reason:amount.
create function pg_temp.rows(key text, basis text default 'settlement') returns text language sql as $$
  select coalesce(string_agg(r, ' ' order by r), '-') from (
    select pg_temp.who(c.referrer_customer_id) || ':' || c.tier || ':' || c.status || ':' || coalesce(c.block_reason, '-')
           || ':' || c.commission_amount || case when c.invoice_item_id is null then '' else ':line' end as r
      from public.commissions c
     where c.invoice_id = pg_temp.fx('i:' || key) and c.earning_basis = basis and c.status in ('earned','paid','blocked')
       and c.adjusts_commission_id is null and c.commission_amount > 0) q $$;
-- The same with every column a payout or report reads, for comparing two runs.
create function pg_temp.full_rows(key text) returns text language sql as $$
  select coalesce(string_agg(r, ' ' order by r), '-') from (
    select concat_ws('|', pg_temp.who(c.referrer_customer_id), pg_temp.who(c.buyer_customer_id), c.tier, c.product_type,
                     c.line_amount, c.rate, c.commission_amount, c.status, coalesce(c.block_reason, '-'), c.invoice_paid_date,
                     c.earning_basis, c.invoice_item_id is not null) as r
      from public.commissions c
     where c.invoice_id = pg_temp.fx('i:' || key) and c.status in ('earned','paid','blocked')) q $$;
-- What a referrer holds that a payout may count (earned or paid), on one invoice or all.
create function pg_temp.live(key text, who text) returns numeric language sql as $$
  select coalesce(sum(c.commission_amount), 0) from public.commissions c
   where c.invoice_id = pg_temp.fx('i:' || key) and c.referrer_customer_id = pg_temp.fx('c:' || who) and c.status in ('earned','paid') $$;
create function pg_temp.owed(who text) returns numeric language sql as $$
  select coalesce((select r.owed from public.affiliate_referrer_balances() r where r.referrer = pg_temp.fx('c:' || who)), 0) $$;
create function pg_temp.payable(who text) returns numeric language sql as $$
  select coalesce((select r.payable from public.affiliate_referrer_balances() r where r.referrer = pg_temp.fx('c:' || who)), 0) $$;
create function pg_temp.month_earned(who text) returns numeric language sql as $$
  select coalesce((select sum(b.earned) from public.affiliate_month_balances() b where b.referrer = pg_temp.fx('c:' || who)), 0) $$;
-- As if the invoice had been settled on day d (as package-commission-paid-date.sql does).
create function pg_temp.settled_on(key text, d date) returns void language plpgsql as $$
declare today date := least(public.sg_today(), (now() at time zone 'UTC')::date);
begin
  update public.invoices set paid_at = (d + time '15:00') at time zone 'Asia/Singapore' where id = pg_temp.fx('i:' || key);
  update public.commissions set invoice_paid_date = d where invoice_id = pg_temp.fx('i:' || key) and invoice_paid_date >= today;
  update public.staff_commissions set invoice_paid_date = d where invoice_id = pg_temp.fx('i:' || key) and invoice_paid_date >= today;
end $$;

-- ═════ Fixtures ═════
-- The Owner (signed in for every call), a store, a payment method, a S$100 product of ours, a
-- S$1000 Credit Package and a S$2000 Premium Bundle; production's rates and part-payment switch.
-- Each case has its own referrers, so balances are theirs alone.
do $$
declare own uuid := gen_random_uuid(); st uuid; m uuid; p uuid; cp uuid; pb uuid;
begin
  insert into tx values ('sfx', lower(substr(md5(gen_random_uuid()::text), 1, 6))),
                        ('phbase', (floor(random() * 900))::int::text);
  insert into auth.users(id, email) values (own, 'm527-owner-' || pg_temp.tx('sfx') || '@example.invalid');
  insert into public.profiles(id, full_name, email, role) values (own, 'M527 Owner', 'm527-owner-' || pg_temp.tx('sfx') || '@example.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into public.stores(name, code, country_code) values ('M527 Store', 'M527' || upper(substr(pg_temp.tx('sfx'), 1, 3)), 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (own, st);
  insert into public.payment_methods(name, is_active) values ('M527 Cash ' || pg_temp.tx('sfx'), true) returning id into m;
  insert into public.products(name, sku, product_type) values ('M527 Item', 'M527-' || pg_temp.tx('sfx'), 'own') returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 50);
  perform public.set_product_prices(st, p, 100, 100, 'available');
  insert into public.credit_packages(name, customer_price, paid_credit_amount, allow_product, allow_therapy)
    values ('M527 Package', 1000, 1000, true, true) returning id into cp;
  insert into public.credit_package_stores(package_id, store_id) values (cp, st);
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('M527 Bundle', 2000, 2000, 200, 0, false) returning id into pb;
  insert into public.premium_bundle_stores(bundle_id, store_id) values (pb, st);
  update public.app_settings set staff_commission_rate = 3, commission_tier1_own_rate = 15, commission_tier2_own_rate = 35,
    commission_tier1_third_rate = 4.5, commission_tier2_third_rate = 35, instalment_commission_from = public.sg_today() - 100
   where id = true;
  insert into fx values ('own', own), ('st', st), ('m', m), ('p', p), ('cp', cp), ('pb', pb);
end $$;

-- The people (referrer chains); a key's last letter says what it is: ...A an eligible affiliate,
-- ...S an affiliate suspended below, ...N never an affiliate, ...D an affiliate whose customer
-- is deleted.
select pg_temp.cust('E2A', 1, null, true),  pg_temp.cust('E1A', 2, 'E2A', true),
       pg_temp.cust('EbuyP', 3, 'E1A', false), pg_temp.cust('EbuyB', 4, 'E1A', false);
select pg_temp.cust('S2A', 10, null, true), pg_temp.cust('S1S', 11, 'S2A', true), pg_temp.cust('Sbuy', 12, 'S1S', false),
       pg_temp.cust('V2N', 13, null, false), pg_temp.cust('V1S', 14, 'V2N', true), pg_temp.cust('Vbuy', 15, null, false);
select pg_temp.cust('N2A', 20, null, true), pg_temp.cust('N1N', 21, 'N2A', false), pg_temp.cust('Nbuy', 22, 'N1N', false),
       pg_temp.cust('D2A', 23, null, true), pg_temp.cust('D1D', 24, 'D2A', true), pg_temp.cust('Dbuy', 25, 'D1D', false);
select pg_temp.cust('T2S', 30, null, true), pg_temp.cust('T1A', 31, 'T2S', true),
       pg_temp.cust('TbuyP', 32, 'T1A', false), pg_temp.cust('TbuyB', 33, 'T1A', false);
select pg_temp.cust('I2A', 40, null, true), pg_temp.cust('I1S', 41, 'I2A', true), pg_temp.cust('Ibuy', 42, 'I1S', false),
       pg_temp.cust('J2A', 43, null, true), pg_temp.cust('J1A', 44, 'J2A', true), pg_temp.cust('Jbuy', 45, 'J1A', false);
select pg_temp.cust('X1A', 50, null, true), pg_temp.cust('Xbuy', 51, 'X1A', false);

-- The invoices (V names V1S's affiliate, chosen while it is active), then the suspensions and
-- the deleted customer, then payment in full (I and J: in part first).
select pg_temp.inv('E/cp', 'EbuyP', null, array['cp']), pg_temp.inv('E/pb', 'EbuyB', null, array['pb']),
       pg_temp.inv('S/cp', 'Sbuy', null, array['cp', 'p']), pg_temp.inv('V/pb', 'Vbuy', 'V1S', array['pb']),
       pg_temp.inv('N/cp', 'Nbuy', null, array['cp']), pg_temp.inv('D/pb', 'Dbuy', null, array['pb']),
       pg_temp.inv('T/cp', 'TbuyP', null, array['cp']), pg_temp.inv('T/pb', 'TbuyB', null, array['pb']),
       pg_temp.inv('I/cp', 'Ibuy', null, array['cp']), pg_temp.inv('J/cp', 'Jbuy', null, array['cp']),
       pg_temp.inv('X/cp', 'Xbuy', null, array['cp', 'p']);
select pg_temp.suspend('S1S'), pg_temp.suspend('V1S'), pg_temp.suspend('T2S'), pg_temp.suspend('I1S');
update public.customers set deleted_at = now() where id = pg_temp.fx('c:D1D');
select pg_temp.pay('E/cp', 1000), pg_temp.pay('E/pb', 2000), pg_temp.pay('S/cp', 1100), pg_temp.pay('V/pb', 2000),
       pg_temp.pay('N/cp', 1000), pg_temp.pay('D/pb', 2000), pg_temp.pay('T/cp', 1000), pg_temp.pay('T/pb', 2000),
       pg_temp.pay('X/cp', 1100);
select pg_temp.check((select count(*) from public.invoices i join fx on fx.v = i.id and fx.k like 'i:%'
                       where fx.k not in ('i:I/cp', 'i:J/cp') and i.status::text = 'paid') = 9
    and (select count(*) from public.credit_package_sales s join fx on fx.v = s.invoice_id and fx.k like 'i:%') = 5
    and (select count(*) from public.premium_bundle_sales s join fx on fx.v = s.invoice_id and fx.k like 'i:%') = 4,
  '0 nine invoices paid in full; five packages and four bundles sold');

-- ═════ E Both tiers eligible ═════
select pg_temp.check(pg_temp.rows('E/cp') = 'c:E1A:tier1:earned:-:45.00 c:E2A:tier2:earned:-:15.75',
  'E1 package, both eligible: tier 1 45.00 and tier 2 15.75, earned, no reason: ' || pg_temp.rows('E/cp'));
select pg_temp.check(pg_temp.rows('E/pb') = 'c:E1A:tier1:earned:-:90.00 c:E2A:tier2:earned:-:31.50',
  'E2 bundle, both eligible: tier 1 90.00 and tier 2 31.50, earned, no reason: ' || pg_temp.rows('E/pb'));

-- ═════ S Tier 1 suspended ═════
select pg_temp.check(pg_temp.rows('S/cp') = 'c:S1S:tier1:blocked:Affiliate Suspended:15.00:line c:S1S:tier1:blocked:Affiliate Suspended:45.00 '
                                         || 'c:S2A:tier2:earned:-:15.75 c:S2A:tier2:earned:-:5.25:line',
  'S1 package (and a product line), tier 1 suspended: the package row blocked, Affiliate Suspended, as the product line; '
  || 'tier 2 eligible earns on both: ' || pg_temp.rows('S/cp'));
select pg_temp.check(pg_temp.rows('V/pb') = 'c:V1S:tier1:blocked:Affiliate Suspended:90.00 c:V2N:tier2:blocked:Affiliate Not Activated:31.50',
  'S2 bundle naming an affiliate suspended before payment, its tier 2 never activated: both blocked, each with its own reason: '
  || pg_temp.rows('V/pb'));

-- ═════ N Never approved / not active ═════
select pg_temp.check(pg_temp.rows('N/cp') = 'c:N1N:tier1:blocked:Affiliate Not Activated:45.00 c:N2A:tier2:earned:-:15.75',
  'N1 package, tier 1 a plain customer never approved: blocked, Affiliate Not Activated; tier 2 eligible earns: ' || pg_temp.rows('N/cp'));
select pg_temp.check(pg_temp.rows('D/pb') = 'c:D1D:tier1:blocked:Customer Inactive:90.00 c:D2A:tier2:earned:-:31.50',
  'N2 bundle, tier 1 an affiliate whose customer is deleted: blocked, Customer Inactive; tier 2 earns: ' || pg_temp.rows('D/pb'));

-- ═════ T Tier 1 eligible, tier 2 suspended ═════
select pg_temp.check(pg_temp.rows('T/cp') = 'c:T1A:tier1:earned:-:45.00 c:T2S:tier2:blocked:Affiliate Suspended:15.75',
  'T1 package: tier 1 earned, tier 2 suspended blocked: ' || pg_temp.rows('T/cp'));
select pg_temp.check(pg_temp.rows('T/pb') = 'c:T1A:tier1:earned:-:90.00 c:T2S:tier2:blocked:Affiliate Suspended:31.50',
  'T2 bundle: tier 1 earned, tier 2 suspended blocked: ' || pg_temp.rows('T/pb'));

-- ═════ R Worked out again ═════
create temp table r527 as
  select k, pg_temp.full_rows(substr(k, 3)) as before,
         (select count(*) from public.commissions c where c.invoice_id = fx.v and c.status in ('earned','blocked')) as n_before
    from fx where k in ('i:E/cp', 'i:E/pb', 'i:S/cp', 'i:V/pb', 'i:N/cp', 'i:D/pb', 'i:T/cp', 'i:T/pb');
select public.reconcile_invoice_commissions(v, 'M527 test: worked out again') from fx
 where k in ('i:E/cp', 'i:E/pb', 'i:S/cp', 'i:V/pb', 'i:N/cp', 'i:D/pb', 'i:T/cp', 'i:T/pb');
select pg_temp.check(bool_and(pg_temp.full_rows(substr(r.k, 3)) = r.before)
    and bool_and((select count(*) from public.commissions c where c.invoice_id = pg_temp.fx(r.k) and c.status = 'reversed'
                    and c.reversal_reason = 'M527 test: worked out again') = r.n_before),
  'R1 reconcile_invoice_commissions on all eight: each row before is reversed, and the rows earned again are the same (tier, status, reason, amounts, date): '
  || coalesce(string_agg(case when pg_temp.full_rows(substr(r.k, 3)) <> r.before then r.k end, ', '), 'none differs'))
  from r527 r;
select pg_temp.check(pg_temp.rows('V/pb') = 'c:V1S:tier1:blocked:Affiliate Suspended:90.00 c:V2N:tier2:blocked:Affiliate Not Activated:31.50'
    and pg_temp.rows('T/cp') = 'c:T1A:tier1:earned:-:45.00 c:T2S:tier2:blocked:Affiliate Suspended:15.75',
  'R2 after it a blocked package or bundle row is still blocked with its reason, an earned one still earned');

-- ═════ P Payable ═════
select pg_temp.check(pg_temp.owed('S1S') = 0 and pg_temp.payable('S1S') = 0 and pg_temp.month_earned('S1S') = 0
    and pg_temp.owed('V1S') = 0 and pg_temp.owed('V2N') = 0 and pg_temp.owed('N1N') = 0 and pg_temp.owed('D1D') = 0
    and pg_temp.owed('T2S') = 0 and pg_temp.payable('T2S') = 0,
  format('P1 a blocked package or bundle row counts nowhere in the balances, as a blocked product row (S1S owed %s payable %s; V1S %s, V2N %s, N1N %s, D1D %s, T2S %s)',
         pg_temp.owed('S1S'), pg_temp.payable('S1S'), pg_temp.owed('V1S'), pg_temp.owed('V2N'), pg_temp.owed('N1N'), pg_temp.owed('D1D'), pg_temp.owed('T2S')));
select pg_temp.check(pg_temp.owed('E1A') = 135 and pg_temp.payable('E1A') = 135 and pg_temp.owed('E2A') = 47.25
    and pg_temp.owed('T1A') = 135 and pg_temp.owed('S2A') = 21 and pg_temp.owed('N2A') = 15.75 and pg_temp.owed('D2A') = 31.50,
  format('P2 an eligible referrer''s package and bundle commission counts in full (E1A %s payable %s, E2A %s, T1A %s, S2A %s, N2A %s, D2A %s)',
         pg_temp.owed('E1A'), pg_temp.payable('E1A'), pg_temp.owed('E2A'), pg_temp.owed('T1A'), pg_temp.owed('S2A'), pg_temp.owed('N2A'), pg_temp.owed('D2A')));

-- ═════ I Paid in part ═════
select pg_temp.pay('I/cp', 400), pg_temp.pay('J/cp', 400);
select pg_temp.check(pg_temp.rows('I/cp', 'instalment') = 'c:I1S:tier1:blocked:Affiliate Suspended:18.00:line c:I2A:tier2:earned:-:6.30:line'
    and pg_temp.live('I/cp', 'I1S') = 0,
  'I1 400 of 1000 paid, tier 1 suspended: its part-payment share blocked (18.00, Affiliate Suspended), never payable; tier 2 earns 6.30: '
  || pg_temp.rows('I/cp', 'instalment'));
select pg_temp.check(pg_temp.rows('J/cp', 'instalment') = 'c:J1A:tier1:earned:-:18.00:line c:J2A:tier2:earned:-:6.30:line',
  'I2 the same with an eligible tier 1: 18.00 and 6.30 earned, as before 527: ' || pg_temp.rows('J/cp', 'instalment'));
select pg_temp.pay('I/cp', 600), pg_temp.pay('J/cp', 600);
select pg_temp.check(pg_temp.rows('I/cp') = 'c:I1S:tier1:blocked:Affiliate Suspended:45.00 c:I2A:tier2:earned:-:15.75'
    and pg_temp.rows('I/cp', 'instalment') = 'c:I2A:tier2:earned:-:6.30:line'
    and pg_temp.live('I/cp', 'I1S') = 0 and pg_temp.live('I/cp', 'I2A') = 15.75 and pg_temp.owed('I1S') = 0,
  format('I3 paid in full: tier 1 blocked 45.00 and nothing payable (its blocked share replaced), tier 2 holds 15.75 in all (%s / %s): %s',
         pg_temp.live('I/cp', 'I1S'), pg_temp.live('I/cp', 'I2A'), pg_temp.rows('I/cp')));
select pg_temp.check(pg_temp.rows('J/cp') = 'c:J1A:tier1:earned:-:45.00 c:J2A:tier2:earned:-:15.75'
    and pg_temp.live('J/cp', 'J1A') = 45 and pg_temp.live('J/cp', 'J2A') = 15.75,
  'I4 the eligible one paid in full: 45.00 and 15.75, as before 527');

-- ═════ X Paid out, then suspended, then worked out again ═════
do $$
declare d date := public.sg_today() - 40; mon date; bal numeric;
begin
  mon := date_trunc('month', d::timestamp)::date;
  perform pg_temp.settled_on('X/cp', d);
  select b.balance into bal from public.affiliate_month_balances() b where b.referrer = pg_temp.fx('c:X1A') and b.month = mon;
  perform pg_temp.check(bal = 60, format('X1 X1A earned 45.00 on the package and 15.00 on the product, paid last month (%s)', bal));
  perform public.record_affiliate_payout(pg_temp.fx('c:X1A'), mon, bal, pg_temp.fx('m'), public.sg_today(), 'M527 payout', null, gen_random_uuid());
  perform pg_temp.suspend('X1A');
  perform public.reconcile_invoice_commissions(pg_temp.fx('i:X/cp'), 'M527 test: corrected after suspension');
  perform pg_temp.check(pg_temp.rows('X/cp') = 'c:X1A:tier1:blocked:Affiliate Suspended:15.00:line c:X1A:tier1:blocked:Affiliate Suspended:45.00 '
                                            || 'c:X1A:tier1:paid:-:15.00:line c:X1A:tier1:paid:-:45.00'
      and pg_temp.live('X/cp', 'X1A') = 0 and pg_temp.owed('X1A') = -60,
    format('X2 the package row earned again is blocked, as the product line''s; the 60.00 paid out is taken back from later commission, '
           || 'the package part as the product part (net on the invoice %s, owed %s): %s',
           pg_temp.live('X/cp', 'X1A'), pg_temp.owed('X1A'), pg_temp.rows('X/cp')));
end $$;

-- ═════ G md5s and grants ═════
\if :{?control}
\else
-- 535 (security audit of 17 Nov 2026, M12) builds on the three functions (and on
-- sync_instalment_commissions and earn_invoice_commission): where it is in, its AFTER md5s
-- stand for them, and B and U take it out first (undo-535), in a savepoint.
select to_regclass('public.invoice_affiliate_rates') is not null as m527_has535 \gset
select pg_temp.check(md5(pg_get_functiondef('public.earn_credit_package_commission(uuid)'::regprocedure)) in ('ad9bbf2183d6e19da85e7f59ce4a4b6e', '44d10e4bcceb9a94080f1802c1da946f')
    and md5(pg_get_functiondef('public.earn_premium_bundle_commission(uuid)'::regprocedure)) in ('39429d3a496274811dce3c3f5f7ca29b', '86ea3b1215ed6fd896bfd63ceba21152')
    and md5(pg_get_functiondef('public.invoice_package_commission_preview(uuid)'::regprocedure)) in ('966e8b7166607aa1d986f20fbbbc1e52', 'ef34e72a6bffaebb33af83f2b38f2ade'),
  'G1 the three functions are 527''s (AFTER md5s), or 535''s where it is in');
select pg_temp.check(bool_and(p.proacl::text = '{postgres=X/postgres,service_role=X/postgres}'
                              and not has_function_privilege('authenticated', p.oid, 'execute')
                              and not has_function_privilege('anon', p.oid, 'execute')),
  'G2 their grants are as before: the service role only')
  from pg_proc p where p.oid in ('public.earn_credit_package_commission(uuid)'::regprocedure,
                                 'public.earn_premium_bundle_commission(uuid)'::regprocedure,
                                 'public.invoice_package_commission_preview(uuid)'::regprocedure);
select pg_temp.check(md5(pg_get_functiondef('public.is_eligible_affiliate(uuid)'::regprocedure)) = '2dfbe1cee8c2be5b5e14a0d19f0553c4'
    and md5(pg_get_functiondef('public.affiliate_block_reason(uuid)'::regprocedure)) = '8cd46c7a29ed2701de7d8358a4d3dc88'
    and md5(pg_get_functiondef('public.customer_affiliate_state(uuid)'::regprocedure)) = '887d0b58f4d1f6670adbaf10591e0f9c'
    and md5(pg_get_functiondef('public.reconcile_invoice_commissions(uuid,text)'::regprocedure)) = '3c267728e215d17ebeb9cfe9cb7db47c'
    and md5(pg_get_functiondef('public.sync_instalment_commissions(uuid,text,date,boolean,boolean)'::regprocedure)) in ('88d7b122778801a0d5eea0b6dd8395b7', '98fbe647100e8890957f098c6d90fca4')
    and md5(pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure)) in ('40b040e35b23940bb19e14e53bdd4daa', '762c06868e2c2256f008b9468b8a255b'),
  'G3 what 527 relies on and what follows it unchanged (eligibility, its reason, reconcile, the part-payment layer, product lines) is as tested');

-- ═════ B The same invoices under the functions of before 527 ═════
savepoint b527;
\if :m527_has535
\ir ../undo-535.sql
\endif
\ir ../undo-527.sql
select public.reconcile_invoice_commissions(v, 'M527 test: before 527') from fx where k in ('i:E/cp', 'i:E/pb', 'i:T/cp', 'i:S/cp');
select pg_temp.check((select bool_and(pg_temp.full_rows(substr(r.k, 3)) = r.before) from r527 r where r.k in ('i:E/cp', 'i:E/pb')),
  'B1 an eligible referrer: the functions of before 527 write exactly the same rows (amounts, rates, dates, status, no reason)');
select pg_temp.check(pg_temp.rows('T/cp') = 'c:T1A:tier1:earned:-:45.00 c:T2S:tier2:earned:-:15.75'
    and pg_temp.rows('S/cp') = 'c:S1S:tier1:blocked:Affiliate Suspended:15.00:line c:S1S:tier1:earned:-:45.00 '
                            || 'c:S2A:tier2:earned:-:15.75 c:S2A:tier2:earned:-:5.25:line',
  'B2 the fault, before 527: a suspended referrer''s package commission is earned while the product line''s is blocked: '
  || pg_temp.rows('S/cp'));
rollback to savepoint b527;

-- ═════ U Undo, and 527 again ═════
\if :m527_has535
savepoint u527_535;
\ir ../undo-535.sql
\endif
\ir ../undo-527.sql
select pg_temp.check(md5(pg_get_functiondef('public.earn_credit_package_commission(uuid)'::regprocedure)) = '13ce59fd892c027338a41de4113ae55d'
    and md5(pg_get_functiondef('public.earn_premium_bundle_commission(uuid)'::regprocedure)) = 'b75ffbea70fd020e75d1ddf4f7b06ba1'
    and md5(pg_get_functiondef('public.invoice_package_commission_preview(uuid)'::regprocedure)) = '5ed13af2d3104dd04b4739b3ab8507bc'
    and (select bool_and(p.proacl::text = '{postgres=X/postgres,service_role=X/postgres}') from pg_proc p
          where p.oid in ('public.earn_credit_package_commission(uuid)'::regprocedure, 'public.earn_premium_bundle_commission(uuid)'::regprocedure,
                          'public.invoice_package_commission_preview(uuid)'::regprocedure)),
  'U1 undo-527 puts the three functions back (their BEFORE md5s) with their grants');
\ir ../../../supabase/527_package_commission_blocked_like_products.sql
select pg_temp.check(md5(pg_get_functiondef('public.earn_credit_package_commission(uuid)'::regprocedure)) = 'ad9bbf2183d6e19da85e7f59ce4a4b6e'
    and md5(pg_get_functiondef('public.earn_premium_bundle_commission(uuid)'::regprocedure)) = '39429d3a496274811dce3c3f5f7ca29b'
    and md5(pg_get_functiondef('public.invoice_package_commission_preview(uuid)'::regprocedure)) = '966e8b7166607aa1d986f20fbbbc1e52',
  'U2 527 again after the undo: the same three functions');
\if :m527_has535
rollback to savepoint u527_535;
\endif

-- ═════ M 527 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m527 m
                                   full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) n
                                     on n.fn = m.fn
                                  where m.fn is null or n.fn is null or m.md5 <> n.md5 or m.acl is distinct from n.acl),
  'M1 running 527 a second time (and the undo and 527 again) left every function and its rights as 527 made them');
\endif
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 527 checks passed.';
end $$;
rollback;
