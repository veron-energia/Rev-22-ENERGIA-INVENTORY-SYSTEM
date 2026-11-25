-- Only an Owner changes the commission rates; an invoice keeps the affiliate rates it first
-- earned at; a package's or bundle's own rates are 0 to 100 and the Owner's; the staff rebase and
-- staff rate change are closed to logins (535; security audit of 17 Nov 2026, M12; the user,
-- 24 Nov 2026).
--
-- Every call is made as the pages make it: a signed-in login (the authenticated role, its JWT)
-- calling the page's server function; a function no login may call (record_invoice_payment's
-- earning, reconcile, the previews) is called as the database owner with the Owner's claims, as
-- the server function that reaches it calls it. The logins: an Owner, a Manager, an Admin, Staff.
-- The rates are pinned to production's (tier 1 15% own, 4.5% third party; tier 2 35% of tier 1
-- for both; staff 3%), and changed by the Owner to 20 / 6 / 40 / 40 in K.
--
--   B  The backfill, on invoices made before 535 (install mode only): every invoice with a
--      commission row (one paid in full, one whose only rows are reversed and carry tier 2 own at
--      5%, as two rows of 10 Sep 2026 do, one paid in part) keeps the current settings rates,
--      marked backfilled; for each of them, what the two previews say and what a reconcile earns
--      (each in a rolled-back step) are the same before and after 535.
--   O  set_commission_rates: a Manager and an Admin are refused with the sentence, the rates
--      unchanged; Staff are refused as before; a Manager still reads the rates; the Owner changes
--      them, and the audit row has the old and the new rates.
--   K  After the Owner's change: an older invoice reconciled, corrected (Correct Invoice, lines
--      as they are) or paid its next instalment keeps 15 / 35 (tier 1 15.00, tier 2 5.25 on
--      S$100; on S$1000 paid 400, then 300, then 300: 60.00, 105.00, then 150.00 and 52.50); a new
--      invoice earns at 20 / 40 (20.00 and 8.00) and keeps those; a package sold with its own tier
--      1 rate of 10 keeps 10 and the invoice's tier 2 of 35 (100.00 and 35.00), also when the
--      Owner later sets the package to 12, in the part-payment preview too; a bundle without its
--      own rate keeps 4.5 / 35 (90.00 and 31.50); an invoice with a referrer that earned nothing
--      keeps nothing; a dry-run part payment keeps nothing.
--   P  A package's and a bundle's own rates: 500, -1 and 100.001 are refused by the function (for
--      the Owner) and by the constraint (straight on the table); 0 and 100 pass; the rates a
--      package or bundle sale snapshots refuse 500 by their constraints too; the five settings rates
--      written straight on app_settings refuse 150 and -1 (0 and 100 pass); a Manager's save
--      that leaves the three rates as stored passes (name, price changed), one that changes or
--      sets any of them is refused, a Manager's new package or bundle with no rate passes, with a
--      rate is refused; the audit row has the old and new rates.
--   B0 (install mode) a standing row at a rate other than today's settings makes 535 refuse.
--   A  A change straight on app_settings, credit_packages or premium_bundles with the secret key
--      is in the audit log with its old and new value (532's trigger, attached by 535).
--   C  apply_commission_rebase_all() and set_staff_commission_rate(numeric) are closed to anon
--      and authenticated (a Manager's call is refused, the staff rate unchanged); the service role
--      keeps them; rebase_staff_commissions is closed.
--   G  535's fixed parts: the AFTER md5s and grants of the nine functions, the two helpers and the
--      table closed to logins, the seventeen constraints, the relied-on functions unchanged; installed here,
--      only those eleven functions and the two closed grants differ from before.
--   U  scripts/commissions/undo-535.sql puts every function, grant and constraint back exactly and
--      drops the table and the seventeen constraints; 535 again makes exactly what it made.
--   M  535 a second time refuses ("535 is already in") and changes nothing.
--
-- Disposable local database only; everything is rolled back. Every name and number is invented
-- (M535 …, @example.invalid); phones are the fictional +61 491 570 nnn range. Run it on a copy of
-- production without 535 (production after 533, or with 534 or 537 too; it applies 535, then again); with -v skip_install=1 where 535 is
-- already in (B, U and M are skipped, G in part); with -v control=1 on a copy WITHOUT 535 (it
-- does not install it, skips B, G, U and M, and fails on exactly the checks 535 makes pass).
-- Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/commissions/tests/invoice-keeps-its-rates-535.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
select position('535 (security audit' in coalesce(pg_get_functiondef(to_regprocedure('public.set_commission_rates(numeric,numeric,numeric,numeric)')), '')) > 0 as had535 \gset
\if :{?control}
\if :had535
\echo control: 535 is in on this copy; run -v control=1 on a copy without it
select 1/0;
\endif
\set mode control
\elif :{?skip_install}
\if :had535
\else
\echo 535 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had535
\echo 535 is already in: run with -v skip_install=1
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
create temp table sfx as select lower(substr(md5(gen_random_uuid()::text), 1, 6)) as s,
                                (floor(random() * 900))::int as ph;
create function pg_temp.sfx() returns text language sql as $$ select s from sfx $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+61491570' || lpad((((select ph from sfx) + n) % 1000)::text, 3, '0') $$;

-- The sentences the pages show (the data contract).
create function pg_temp.s(key text) returns text language sql as $$
  select case key
    when 'rates' then 'Only an Owner can change the commission rates.'
    when 'own_rates' then 'Only an Owner can set a package''s or bundle''s own commission rates.'
    when 't1' then 'A package''s or bundle''s Tier 1 rate must be between 0 and 100.'
    when 't2' then 'A package''s or bundle''s Tier 2 rate must be between 0 and 100.'
    when 'staff' then 'A package''s or bundle''s Staff commission rate must be between 0 and 100.' end $$;
create function pg_temp.refused(t text, key text) returns boolean language sql as $$ select t = 'ERR 42501 ' || pg_temp.s(key) $$;

-- One statement as someone: a signed-in login (its key), 'anon', or 'pg:<login>' (the database
-- owner with that login's claims, as a server function's own call). 'ok:<first column>', or
-- 'ERR <sqlstate> <message>'.
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    if who = 'anon' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'anon', true);
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    elsif who = 'service' then
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
-- Production's rates, pinned (the column defaults differ: tier 2 = 5).
insert into public.app_settings(id) values (true) on conflict do nothing;
update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
  commission_tier2_own_rate = 35, commission_tier2_third_rate = 35, staff_commission_rate = 3,
  instalment_commission_from = public.sg_today() - 100
 where id = true;
create function pg_temp.pin_rates() returns void language sql as $$
  update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
    commission_tier2_own_rate = 35, commission_tier2_third_rate = 35, staff_commission_rate = 3 where id = true $$;
do $fx$
declare r record; u uuid; s text := pg_temp.sfx();
begin
  for r in select * from (values ('own', 'owner'), ('mgr', 'manager'), ('adm', 'admin'), ('stf', 'staff')) t(k, role) loop
    insert into auth.users(id, email, email_confirmed_at)
    values (gen_random_uuid(), 'm535-' || r.k || '-' || s || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active)
    values (u, 'M535 ' || r.k, 'm535-' || r.k || '-' || s || '@example.invalid', r.role::public.user_role, true);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.stores(name, code, country_code) values ('M535 Store', 'M535' || s, 'SG') returning id into u; perform pg_temp.put('st', u);
  insert into public.user_store_assignments(user_id, store_id)
  values (pg_temp.fx('own'), pg_temp.fx('st')), (pg_temp.fx('mgr'), pg_temp.fx('st')), (pg_temp.fx('stf'), pg_temp.fx('st'));
  insert into public.payment_methods(name, is_active) values ('M535 Cash ' || s, true) returning id into u; perform pg_temp.put('m', u);
  insert into public.products(name, sku, product_type) values ('M535 Item', 'M535-I-' || s, 'own') returning id into u; perform pg_temp.put('p', u);
  insert into public.products(name, sku, product_type) values ('M535 Chair', 'M535-C-' || s, 'own') returning id into u; perform pg_temp.put('pk', u);
  insert into public.products(name, sku, product_type) values ('M535 Session', 'M535-S-' || s, 'no_commission') returning id into u; perform pg_temp.put('pz', u);
  insert into public.store_inventory(store_id, product_id, current_qty)
  values (pg_temp.fx('st'), pg_temp.fx('p'), 500), (pg_temp.fx('st'), pg_temp.fx('pk'), 500);
  -- A Credit Package of S$1000 with its own tier 1 rate of 10, one without, a Premium Bundle of S$2000.
  insert into public.credit_packages(name, customer_price, paid_credit_amount, allow_product, allow_therapy, tier1_rate)
    values ('M535 Package Ten ' || s, 1000, 1000, true, true, 10) returning id into u; perform pg_temp.put('cpr', u);
  insert into public.credit_package_stores(package_id, store_id) values (pg_temp.fx('cpr'), pg_temp.fx('st'));
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('M535 Bundle ' || s, 2000, 2000, 200, 0, false) returning id into u; perform pg_temp.put('pb', u);
  insert into public.premium_bundle_stores(bundle_id, store_id) values (pg_temp.fx('pb'), pg_temp.fx('st'));
end $fx$;
select pg_temp.must('pg:own', format('select public.set_product_prices(%L, %L, 100, 100, %L)::text', pg_temp.fx('st'), pg_temp.fx('p'), 'available'));
select pg_temp.must('pg:own', format('select public.set_product_prices(%L, %L, 1000, 1000, %L)::text', pg_temp.fx('st'), pg_temp.fx('pk'), 'available'));
select pg_temp.must('pg:own', format('select public.set_product_prices(%L, %L, 50, 50, %L)::text', pg_temp.fx('st'), pg_temp.fx('pz'), 'available'));

-- A buyer referred by tier 1 (an active affiliate), referred by tier 2 (an active affiliate).
create function pg_temp.chain(key text, n int) returns void language plpgsql as $$
declare t2 uuid; t1 uuid; b uuid;
begin
  insert into public.customers(full_name, phone, email) values ('M535 ' || key || ' T2', pg_temp.ph(n * 3), 'm535-' || lower(key) || '-t2-' || pg_temp.sfx() || '@example.invalid') returning id into t2;
  insert into public.customers(full_name, phone, email, referred_by) values ('M535 ' || key || ' T1', pg_temp.ph(n * 3 + 1), 'm535-' || lower(key) || '-t1-' || pg_temp.sfx() || '@example.invalid', t2) returning id into t1;
  insert into public.customers(full_name, phone, referred_by) values ('M535 ' || key || ' Buyer', pg_temp.ph(n * 3 + 2), t1) returning id into b;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at)
  values (t2, 'active', pg_temp.fx('st'), now()), (t1, 'active', pg_temp.fx('st'), now());
  perform pg_temp.put('c:' || key, b);
end $$;
-- An invoice for a chain's buyer: 'p' S$100, 'pk' S$1000, 'pz' a no-commission S$50, 'cpr' the
-- package with its own rate, 'pb' the bundle. Made and paid by the Owner's server calls.
create function pg_temp.inv(key text, chain text, kinds text[]) returns uuid language plpgsql as $$
declare items jsonb := '[]'::jsonb; k text; v uuid;
begin
  foreach k in array kinds loop
    items := items || case k
      when 'cpr' then jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cpr'),'quantity',1)
      when 'pb' then jsonb_build_object('kind','premium_bundle','premium_bundle_id',pg_temp.fx('pb'),'quantity',1,'voucher_selection','[]'::jsonb)
      else jsonb_build_object('kind','product','product_id',pg_temp.fx(k),'quantity',1) end;
  end loop;
  v := pg_temp.must('pg:own', format('select public.create_invoice(%L, %L, null, %L::jsonb, 0::numeric, null::text, null::uuid, %L::jsonb)::text',
         pg_temp.fx('st'), pg_temp.fx('c:' || chain), items, '[]'))::uuid;
  return pg_temp.put('i:' || key, v);
end $$;
create function pg_temp.pay(key text, amount numeric) returns text language sql as $$
  select pg_temp.must('pg:own', format('select public.record_invoice_payment(%L, %L::jsonb, %L)::text', pg_temp.fx('i:' || key),
    jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('m'), 'amount', amount)), gen_random_uuid())) $$;
create function pg_temp.reconcile(key text) returns text language sql as $$
  select pg_temp.as_('pg:own', format('select public.reconcile_invoice_commissions(%L, %L)::text', pg_temp.fx('i:' || key), 'M535 worked out again')) $$;
-- An invoice's lines exactly as they are, for a Correct Invoice that changes nothing else.
create function pg_temp.same_lines(inv uuid) returns jsonb language sql as $$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'invoice_item_id', it.id, 'kind', it.line_kind::text, 'quantity', it.quantity,
           'product_id', it.product_id, 'credit_package_id', it.credit_package_id,
           'premium_bundle_id', it.premium_bundle_id, 'unit_price', it.unit_price,
           'voucher_selection', case when it.line_kind = 'premium_bundle'
                                     then coalesce(it.bundle_voucher_selection, '[]'::jsonb) end)) order by it.id)
    from public.invoice_items it where it.invoice_id = inv $$;
create function pg_temp.correct(key text) returns text language sql as $$
  select pg_temp.as_('pg:own', format('select public.correct_invoice(%L, %L::jsonb, %L::jsonb, %L, %L)::text',
    pg_temp.fx('i:' || key), pg_temp.same_lines(pg_temp.fx('i:' || key)),
    jsonb_build_object('expected_edit_count', (select coalesce(edit_count, 0) from public.invoices where id = pg_temp.fx('i:' || key))),
    'M535 corrected, lines as they are', gen_random_uuid())) $$;
-- What an invoice's referrers hold (earned or paid), per tier, across settlement and part payments.
create function pg_temp.amt(key text, which text) returns numeric language sql as $$
  select coalesce(sum(c.commission_amount), 0) from public.commissions c
   where c.invoice_id = pg_temp.fx('i:' || key) and c.tier::text = $2 and c.status in ('earned','paid') $$;
create function pg_temp.amts(key text) returns text language sql as $$
  select pg_temp.amt(key, 'tier1') || '/' || pg_temp.amt(key, 'tier2') $$;
-- The rates kept for an invoice ('-' when none), and whether they are backfilled.
create function pg_temp.kept(key text) returns text language plpgsql as $$
declare t text;
begin
  if to_regclass('public.invoice_affiliate_rates') is null then return 'no table'; end if;
  execute 'select concat_ws(''/'', tier1_own_rate, tier1_third_rate, tier2_own_rate, tier2_third_rate) || case when backfilled then '' backfilled'' else '''' end
             from public.invoice_affiliate_rates where invoice_id = $1' into t using pg_temp.fx('i:' || key);
  return coalesce(t, '-');
end $$;

-- ═════ B Invoices made before 535 (in every mode; compared in install mode) ═════
select pg_temp.chain('B1', 1), pg_temp.chain('B2', 2), pg_temp.chain('B3', 3);
select pg_temp.inv('B1', 'B1', array['p']), pg_temp.inv('B2', 'B2', array['p']), pg_temp.inv('B3', 'B3', array['pk']);
select pg_temp.pay('B1', 100);
-- B2: earned while tier 2 own was 5%, then every row reversed (as the two rows of 10 Sep 2026).
update public.app_settings set commission_tier2_own_rate = 5 where id = true;
select pg_temp.pay('B2', 100);
select pg_temp.pin_rates();
update public.commissions set status = 'reversed', reversed_at = now(), reversal_reason = 'M535 reversed before 535'
 where invoice_id = pg_temp.fx('i:B2');
select pg_temp.pay('B3', 400);

-- What the previews say and what a reconcile earns, per invoice with commission rows, each in a
-- step rolled back by itself.
create temp table seen(phase text, inv uuid, preview text, reearned text, primary key (phase, inv));
create function pg_temp.look(p_phase text) returns int language plpgsql as $$
declare v uuid; pv text; re text; n int := 0;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);
  for v in select distinct c.invoice_id from public.commissions c where c.invoice_id is not null loop
    select coalesce(string_agg(concat_ws('|', o_invoice_item_id, o_referrer, o_tier, o_product_type, o_line_amount, o_rate, o_amount, o_status), ' ' order by 1), '-')
      into pv from (select * from public.invoice_affiliate_commission_preview(v)
                    union all select * from public.invoice_package_commission_preview(v)) q;
    re := null;
    begin
      perform public.reconcile_invoice_commissions(v, 'M535 rehearsal');
      select coalesce(string_agg(concat_ws('|', c.referrer_customer_id, c.tier, c.product_type, c.invoice_item_id, c.line_amount,
                                           c.rate, c.commission_amount, c.status, c.block_reason, c.invoice_paid_date, c.earning_basis,
                                           c.adjusts_commission_id is not null, split_part(coalesce(c.reversal_reason, ''), ':', 1)), ' ' order by 1), '-')
        into re from public.commissions c where c.invoice_id = v and c.status in ('earned','paid','blocked');
      raise exception 'M535_ROLLBACK';
    exception when others then
      if sqlerrm <> 'M535_ROLLBACK' then re := 'ERR ' || sqlerrm; end if;
    end;
    insert into seen values (p_phase, v, pv, re);
    n := n + 1;
  end loop;
  return n;
end $$;
\if :by_us
-- B0 the backfill guard: an invoice paid while tier 1 own was 14 (a standing row at a rate other
-- than today's) makes 535 refuse, changing nothing; rolled back.
savepoint b0;
select pg_temp.chain('B0', 9);
update public.app_settings set commission_tier1_own_rate = 14 where id = true;
select pg_temp.inv('B0', 'B0', array['p']);
select pg_temp.pay('B0', 100);
select pg_temp.pin_rates();
\set ON_ERROR_STOP off
\ir ../../../supabase/535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own.sql
\set ON_ERROR_STOP on
rollback to savepoint b0;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '535: 1 standing commission row(s) on 1 invoice(s) carry a rate other than today''s settings%'
                     and to_regclass('public.invoice_affiliate_rates') is null,
  'B0 a standing row at a rate other than today''s settings makes 535 refuse, changing nothing: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.look('before');
\ir ../../../supabase/535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own.sql
create temp table fn1 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
select pg_temp.look('after');
select pg_temp.check(pg_temp.kept('B1') = '15/4.5/35/35 backfilled' and pg_temp.kept('B2') = '15/4.5/35/35 backfilled'
                     and pg_temp.kept('B3') = '15/4.5/35/35 backfilled',
  'B1 the backfill keeps the current settings for an invoice paid in full, one whose only rows are reversed at tier 2 own 5%, and one paid in part: '
  || pg_temp.kept('B1') || ' / ' || pg_temp.kept('B2') || ' / ' || pg_temp.kept('B3'));
select pg_temp.check((select count(*) from public.invoice_affiliate_rates)
                     = (select count(distinct invoice_id) from public.commissions where invoice_id is not null)
                     and not exists (select 1 from public.invoice_affiliate_rates r cross join public.app_settings a
                                      where a.id and (r.tier1_own_rate, r.tier1_third_rate, r.tier2_own_rate, r.tier2_third_rate)
                                            is distinct from (a.commission_tier1_own_rate, a.commission_tier1_third_rate,
                                                              a.commission_tier2_own_rate, a.commission_tier2_third_rate)),
  'B2 every invoice with a commission row on this copy is backfilled, each with the settings rates');
select pg_temp.check((select count(*) from seen where phase = 'before') = (select count(*) from seen where phase = 'after')
                     and not exists (select 1 from seen b join seen a on a.inv = b.inv and a.phase = 'after'
                                      where b.phase = 'before' and (a.preview, a.reearned) is distinct from (b.preview, b.reearned)),
  'B3 for every invoice with commission rows, the previews and a reconcile (each rolled back) are the same before and after 535 ('
  || (select count(*) from seen where phase = 'after') || ' invoices)');
select pg_temp.check((select reearned from seen where phase = 'after' and inv = pg_temp.fx('i:B2')) like '%|tier2|own|%|15.00|35.000|5.25|%',
  'B4 the invoice reversed at tier 2 own 5% earns again at 35, as it did before 535 (not at its first row''s 5)');
\else
create temp table fn1 as select * from fn0;
\echo NOTE  B is skipped (535 was not installed by this file)
\endif

-- ═════ O set_commission_rates ═════
do $O$
declare t text;
begin
  t := pg_temp.as_('mgr', 'select public.set_commission_rates(99, 9, 99, 99)::text');
  perform pg_temp.pin_rates();   -- without 535 the Manager's change went in; put the rates back
  perform pg_temp.check(pg_temp.refused(t, 'rates'), 'O1 a Manager cannot change the commission rates: ' || t);
  t := pg_temp.as_('adm', 'select public.set_commission_rates(99, 9, 99, 99)::text');
  perform pg_temp.pin_rates();
  perform pg_temp.check(t like 'ERR %' and t not like 'ok:%', 'O2 nor an Admin: ' || t);
  t := pg_temp.as_('stf', 'select public.set_commission_rates(99, 9, 99, 99)::text');
  perform pg_temp.pin_rates();
  perform pg_temp.check(t = 'ERR P0001 Only an Owner or Manager can edit commission rates', 'O3 Staff are refused as before: ' || t);
  t := pg_temp.as_('mgr', 'select concat_ws(''/'', commission_tier1_own_rate, commission_tier1_third_rate, commission_tier2_own_rate, commission_tier2_third_rate) from public.app_settings');
  perform pg_temp.check(t = 'ok:15/4.5/35/35', 'O4 a Manager still reads the rates: ' || t);
  t := pg_temp.as_('own', 'select public.set_commission_rates(16, 4.5, 35, 35)::text');
  perform pg_temp.check(t like 'ok:%' and (select commission_tier1_own_rate from public.app_settings where id) = 16,
    'O5 the Owner changes them: ' || t);
  perform pg_temp.check(exists (select 1 from public.audit_logs l where l.action = 'commission_rates_set'
                                   and l.old_data->>'tier1_own' = '15' and l.new_data->>'tier1_own' = '16'),
    'O6 the audit row has the old and the new rates');
  perform pg_temp.pin_rates();
end $O$;

-- ═════ K An invoice keeps the rates it first earned at ═════
select pg_temp.chain('KA', 11), pg_temp.chain('KC', 12), pg_temp.chain('KD', 13), pg_temp.chain('KE', 14),
       pg_temp.chain('KN', 15), pg_temp.chain('KZ', 16), pg_temp.chain('KY', 17);
select pg_temp.inv('KA', 'KA', array['p']), pg_temp.inv('KC', 'KC', array['pk']), pg_temp.inv('KD', 'KD', array['cpr']),
       pg_temp.inv('KE', 'KE', array['pb']), pg_temp.inv('KZ', 'KZ', array['pz']), pg_temp.inv('KY', 'KY', array['pk']);
select pg_temp.pay('KA', 100), pg_temp.pay('KC', 400), pg_temp.pay('KD', 1000), pg_temp.pay('KE', 2000), pg_temp.pay('KZ', 50);
select pg_temp.check(pg_temp.amts('KA') = '15.00/5.25' and pg_temp.amts('KC') = '60.00/21.00'
                     and pg_temp.amts('KD') = '100.00/35.00' and pg_temp.amts('KE') = '90.00/31.50',
  'K0 at 15 / 35: S$100 earns 15.00 and 5.25; S$400 of S$1000 60.00 and 21.00; the package with its own 10% 100.00 and 35.00; the bundle 90.00 and 31.50: '
  || pg_temp.amts('KA') || ' ' || pg_temp.amts('KC') || ' ' || pg_temp.amts('KD') || ' ' || pg_temp.amts('KE'));
\if :is_control
\else
select pg_temp.check(pg_temp.kept('KA') = '15/4.5/35/35' and pg_temp.kept('KC') = '15/4.5/35/35'
                     and pg_temp.kept('KD') = '15/4.5/35/35' and pg_temp.kept('KE') = '15/4.5/35/35' and pg_temp.kept('KZ') = '-',
  'K1 each keeps the settings rates once it earns (settled, part paid, package, bundle); the one that earned nothing keeps nothing: '
  || pg_temp.kept('KA') || ' ' || pg_temp.kept('KC') || ' ' || pg_temp.kept('KD') || ' ' || pg_temp.kept('KE') || ' ' || pg_temp.kept('KZ'));
\endif
-- The Owner changes the rates.
select pg_temp.check(pg_temp.as_('own', 'select public.set_commission_rates(20, 6, 40, 40)::text') like 'ok:%',
  'K2 the Owner sets the rates to 20 / 6 / 40 / 40');
do $K$
declare t text;
begin
  t := pg_temp.reconcile('KA');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KA') = '15.00/5.25',
    'K3 reconciling the older invoice keeps 15 / 35: ' || t || ' ' || pg_temp.amts('KA'));
  t := pg_temp.correct('KA');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KA') = '15.00/5.25',
    'K4 correcting it (Correct Invoice) keeps 15 / 35: ' || left(t, 60) || ' ' || pg_temp.amts('KA'));
  perform pg_temp.pay('KC', 300);
  perform pg_temp.check(pg_temp.amts('KC') = '105.00/36.75',
    'K5 its next instalment keeps 15 / 35 (S$700 of S$1000: 105.00 and 36.75): ' || pg_temp.amts('KC'));
  perform pg_temp.pay('KC', 300);
  perform pg_temp.check(pg_temp.amts('KC') = '150.00/52.50',
    'K6 paid in full it settles at 15 / 35 (150.00 and 52.50): ' || pg_temp.amts('KC'));
  t := pg_temp.reconcile('KD');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KD') = '100.00/35.00',
    'K7 the package keeps its own tier 1 of 10 and the invoice''s tier 2 of 35: ' || pg_temp.amts('KD'));
  t := pg_temp.reconcile('KE');
  perform pg_temp.check(t like 'ok:%' and pg_temp.amts('KE') = '90.00/31.50',
    'K8 the bundle without its own rate keeps 4.5 / 35: ' || pg_temp.amts('KE'));
end $K$;
select pg_temp.inv('KN', 'KN', array['p']);
select pg_temp.pay('KN', 100);
select pg_temp.check(pg_temp.amts('KN') = '20.00/8.00', 'K9 a new invoice earns at the new rates (20.00 and 8.00): ' || pg_temp.amts('KN'));
\if :is_control
\else
select pg_temp.check(pg_temp.kept('KN') = '20/6/40/40' and pg_temp.kept('KA') = '15/4.5/35/35',
  'K10 the new invoice keeps the new rates, the older keeps its own: ' || pg_temp.kept('KN') || ' ' || pg_temp.kept('KA'));
\endif
select pg_temp.check(pg_temp.reconcile('KN') like 'ok:%' and pg_temp.amts('KN') = '20.00/8.00',
  'K11 reconciled, the new invoice keeps 20 / 40: ' || pg_temp.amts('KN'));
-- The package set to 12 by the Owner after the sale: the sale keeps 10, in the part-payment preview too.
update public.credit_packages set tier1_rate = 12 where id = pg_temp.fx('cpr');
select pg_temp.check(pg_temp.reconcile('KD') like 'ok:%' and pg_temp.amts('KD') = '100.00/35.00',
  'K12 the package set to 12 after its sale: the invoice still earns 10 on it: ' || pg_temp.amts('KD'));
select pg_temp.check((select string_agg(o_tier || ':' || o_rate, ' ' order by o_tier) from public.invoice_package_commission_preview(pg_temp.fx('i:KD'))) = 'tier1:10.000 tier2:35',
  'K13 the part-payment preview of the settled package line reads its sale''s 10 and the invoice''s 35: '
  || coalesce((select string_agg(o_tier || ':' || o_rate, ' ' order by o_tier) from public.invoice_package_commission_preview(pg_temp.fx('i:KD'))), '-'));
update public.credit_packages set tier1_rate = 10 where id = pg_temp.fx('cpr');
-- KZ earned nothing; a part payment made after the change, dry run first.
\if :is_control
\else
select pg_temp.check(pg_temp.kept('KZ') = '-', 'K14 the invoice that earned nothing still keeps nothing: ' || pg_temp.kept('KZ'));
select pg_temp.pay('KY', 400);
select pg_temp.check(pg_temp.amts('KY') = '80.00/32.00' and pg_temp.kept('KY') = '20/6/40/40',
  'K15 a part payment after the change earns at, and keeps, the new rates: ' || pg_temp.amts('KY') || ' ' || pg_temp.kept('KY'));
delete from public.invoice_affiliate_rates where invoice_id = pg_temp.fx('i:KY');
select count(*) from public.sync_instalment_commissions(pg_temp.fx('i:KY'), 'M535 dry run', null, true);
select pg_temp.check(pg_temp.kept('KY') = '-', 'K16 a dry-run part payment keeps nothing: ' || pg_temp.kept('KY'));
\endif
select pg_temp.pin_rates();

-- ═════ P A package's or bundle's own rates ═════
create function pg_temp.pkg(who text, id uuid, name text, t1 numeric, t2 numeric, staff numeric) returns text language sql as $$
  select pg_temp.as_(who, format('select public.upsert_credit_package(p_id => %L, p_name => %L, p_customer_price => 500, p_paid_credit_amount => 500,
    p_effective_from => %L, p_commission_classification => %L, p_staff_commission_rate => %L, p_tier1_rate => %L, p_tier2_rate => %L)::text',
    id, name, public.sg_today(), 'third_party', staff, t1, t2)) $$;
create function pg_temp.bdl(who text, id uuid, name text, t1 numeric, t2 numeric, staff numeric) returns text language sql as $$
  select pg_temp.as_(who, format('select public.upsert_premium_bundle(p_id => %L, p_name => %L, p_customer_payment_amount => 800, p_paid_credit_amount => 800,
    p_bonus_credit_amount => 0, p_free_voucher_qty => 0, p_effective_from => %L, p_commission_classification => %L,
    p_staff_commission_rate => %L, p_tier1_rate => %L, p_tier2_rate => %L)::text',
    id, name, public.sg_today(), 'third_party', staff, t1, t2)) $$;
create function pg_temp.rates_of(tbl text, id uuid) returns text language plpgsql as $$
declare t text;
begin
  execute format('select concat_ws(''/'', coalesce(tier1_rate::text, ''-''), coalesce(tier2_rate::text, ''-''), coalesce(staff_commission_rate::text, ''-'')) from public.%I where id = $1', tbl)
    into t using id;
  return t;
end $$;
do $P$
declare t text; v uuid; s text := pg_temp.sfx(); k record;
begin
  -- the Owner: a package of its own, rates 10 / none / none
  v := substr(pg_temp.pkg('own', null, 'M535 P Package ' || s, 10, null, null), 4)::uuid; perform pg_temp.put('ppk', v);
  perform pg_temp.check(pg_temp.rates_of('credit_packages', v) = '10.000/-/-', 'P0 the Owner makes a package with its own tier 1 of 10');
  v := substr(pg_temp.bdl('own', null, 'M535 P Bundle ' || s, 10, null, null), 4)::uuid; perform pg_temp.put('pbd', v);
  perform pg_temp.check(pg_temp.rates_of('premium_bundles', v) = '10.000/-/-', 'P0b and a bundle');
  for k in select * from (values ('credit_packages', 'ppk'), ('premium_bundles', 'pbd')) x(tbl, key) loop
    -- 0 to 100, in the function (the Owner)
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('own', pg_temp.fx(k.key), 'M535 P ' || s, 500, null, null)
                    else pg_temp.bdl('own', pg_temp.fx(k.key), 'M535 P ' || s, 500, null, null) end;
    perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('t1') and pg_temp.rates_of(k.tbl, pg_temp.fx(k.key)) = '10.000/-/-',
      'P1 ' || k.tbl || ': the Owner cannot set tier 1 to 500: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('own', pg_temp.fx(k.key), 'M535 P ' || s, 10, -1, null)
                    else pg_temp.bdl('own', pg_temp.fx(k.key), 'M535 P ' || s, 10, -1, null) end;
    perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('t2'), 'P2 ' || k.tbl || ': nor tier 2 to -1: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('own', pg_temp.fx(k.key), 'M535 P ' || s, 10, null, 100.001)
                    else pg_temp.bdl('own', pg_temp.fx(k.key), 'M535 P ' || s, 10, null, 100.001) end;
    perform pg_temp.check(t = 'ERR P0001 ' || pg_temp.s('staff'), 'P3 ' || k.tbl || ': nor the staff rate to 100.001: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('own', pg_temp.fx(k.key), 'M535 P ' || s, 0, 100, 0)
                    else pg_temp.bdl('own', pg_temp.fx(k.key), 'M535 P ' || s, 0, 100, 0) end;
    perform pg_temp.check(t like 'ok:%' and pg_temp.rates_of(k.tbl, pg_temp.fx(k.key)) = '0.000/100.000/0.000',
      'P4 ' || k.tbl || ': 0 and 100 pass: ' || t || ' ' || pg_temp.rates_of(k.tbl, pg_temp.fx(k.key)));
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('own', pg_temp.fx(k.key), 'M535 P ' || s, 10, null, null)
                    else pg_temp.bdl('own', pg_temp.fx(k.key), 'M535 P ' || s, 10, null, null) end;
    -- 0 to 100, straight on the table
    t := pg_temp.as_('pg:own', format('update public.%I set tier1_rate = 500 where id = %L returning tier1_rate::text', k.tbl, pg_temp.fx(k.key)));
    perform pg_temp.check(t like 'ERR 23514 %', 'P5 ' || k.tbl || ': the constraint refuses a tier 1 of 500 on the table: ' || t);
    t := pg_temp.as_('pg:own', format('update public.%I set staff_commission_rate = -0.001 where id = %L returning staff_commission_rate::text', k.tbl, pg_temp.fx(k.key)));
    perform pg_temp.check(t like 'ERR 23514 %', 'P5b ' || k.tbl || ': and a staff rate below 0: ' || t);
    -- a Manager: everything else, but not the three rates
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('mgr', pg_temp.fx(k.key), 'M535 P renamed ' || s, 10, null, null)
                    else pg_temp.bdl('mgr', pg_temp.fx(k.key), 'M535 P renamed ' || s, 10, null, null) end;
    perform pg_temp.check(t like 'ok:%', 'P6 ' || k.tbl || ': a Manager''s save that leaves the rates as stored passes: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('mgr', pg_temp.fx(k.key), 'M535 P ' || s, 11, null, null)
                    else pg_temp.bdl('mgr', pg_temp.fx(k.key), 'M535 P ' || s, 11, null, null) end;
    perform pg_temp.check(pg_temp.refused(t, 'own_rates') and pg_temp.rates_of(k.tbl, pg_temp.fx(k.key)) = '10.000/-/-',
      'P7 ' || k.tbl || ': a Manager cannot change tier 1 (10 to 11): ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('mgr', pg_temp.fx(k.key), 'M535 P ' || s, null, null, null)
                    else pg_temp.bdl('mgr', pg_temp.fx(k.key), 'M535 P ' || s, null, null, null) end;
    perform pg_temp.check(pg_temp.refused(t, 'own_rates'), 'P8 ' || k.tbl || ': nor clear it: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('mgr', pg_temp.fx(k.key), 'M535 P ' || s, 10, 5, null)
                    else pg_temp.bdl('mgr', pg_temp.fx(k.key), 'M535 P ' || s, 10, 5, null) end;
    perform pg_temp.check(pg_temp.refused(t, 'own_rates'), 'P9 ' || k.tbl || ': nor set tier 2: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('mgr', pg_temp.fx(k.key), 'M535 P ' || s, 10, null, 2)
                    else pg_temp.bdl('mgr', pg_temp.fx(k.key), 'M535 P ' || s, 10, null, 2) end;
    perform pg_temp.check(pg_temp.refused(t, 'own_rates'), 'P10 ' || k.tbl || ': nor set the staff rate: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('mgr', null, 'M535 P new ' || s, null, null, null)
                    else pg_temp.bdl('mgr', null, 'M535 P new ' || s, null, null, null) end;
    perform pg_temp.check(t like 'ok:%', 'P11 ' || k.tbl || ': a Manager makes a new one with no rate of its own: ' || t);
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('mgr', null, 'M535 P new rate ' || s, 5, null, null)
                    else pg_temp.bdl('mgr', null, 'M535 P new rate ' || s, 5, null, null) end;
    perform pg_temp.check(pg_temp.refused(t, 'own_rates'), 'P12 ' || k.tbl || ': but not with a rate of its own: ' || t);
    -- the Owner changes tier 1 (10 to 12): the audit row has the old and the new rates
    t := case k.tbl when 'credit_packages' then pg_temp.pkg('own', pg_temp.fx(k.key), 'M535 P ' || s, 12, null, null)
                    else pg_temp.bdl('own', pg_temp.fx(k.key), 'M535 P ' || s, 12, null, null) end;
    perform pg_temp.check(t like 'ok:%' and exists (
        select 1 from public.audit_logs l where l.table_name = k.tbl and l.record_id = pg_temp.fx(k.key)
           and l.old_data->>'tier1_rate' = '10.000' and l.new_data->>'tier1_rate' = '12.000'
           and l.old_data ? 'tier2_rate' and l.old_data ? 'staff_commission_rate'
           and l.new_data ? 'tier2_rate' and l.new_data ? 'staff_commission_rate' and l.new_data ? 'name'),
      'P13 ' || k.tbl || ': the Owner''s change is in the audit row with the old and the new rates: ' || t);
  end loop;
end $P$;

-- P14 the rates a sale snapshots: null or 0 to 100, straight on the table (the package sale of KD,
-- the bundle sale of KE), each rolled back by itself.
do $P14$
declare k record; t text;
begin
  for k in select * from (values ('credit_package_sales', 'KD'), ('premium_bundle_sales', 'KE')) x(tbl, inv),
                         unnest(array['tier1_rate_snapshot', 'tier2_rate_snapshot', 'staff_rate_snapshot']) c(col) loop
    t := pg_temp.as_('pg:own', format('update public.%I set %I = 500 where invoice_id = %L returning %I::text', k.tbl, k.col, pg_temp.fx('i:' || k.inv), k.col));
    perform pg_temp.check(t like 'ERR 23514 %', 'P14 ' || k.tbl || '.' || k.col || ': the constraint refuses 500: ' || t);
  end loop;
  t := pg_temp.as_('pg:own', format('update public.credit_package_sales set tier1_rate_snapshot = 100, staff_rate_snapshot = 0 where invoice_id = %L returning tier1_rate_snapshot::text', pg_temp.fx('i:KD')));
  perform pg_temp.check(t like 'ok:%', 'P14b 0 and 100 pass: ' || t);
  -- back as sold (without 535 the updates above went in): the package's 10, nothing else
  update public.credit_package_sales set tier1_rate_snapshot = 10, tier2_rate_snapshot = null, staff_rate_snapshot = null
   where invoice_id = pg_temp.fx('i:KD');
  update public.premium_bundle_sales set tier1_rate_snapshot = null, tier2_rate_snapshot = null, staff_rate_snapshot = null
   where invoice_id = pg_temp.fx('i:KE');
end $P14$;

-- P15 the settings' rates written straight on app_settings (the secret key, or SQL): 0 to 100.
do $P15$
declare c text; t text;
begin
  foreach c in array array['commission_tier1_own_rate', 'commission_tier1_third_rate', 'commission_tier2_own_rate',
                           'commission_tier2_third_rate', 'staff_commission_rate'] loop
    t := pg_temp.as_('pg:own', format('update public.app_settings set %I = 150 where id = true returning %I::text', c, c));
    perform pg_temp.check(t like 'ERR 23514 %', 'P15 app_settings.' || c || ': the constraint refuses 150: ' || t);
    t := pg_temp.as_('service', format('update public.app_settings set %I = -1 where id = true returning %I::text', c, c));
    perform pg_temp.check(t like 'ERR 23514 %', 'P15b app_settings.' || c || ': and -1 from the secret key: ' || t);
    t := pg_temp.as_('pg:own', format('update public.app_settings set %I = 0 where id = true returning %I::text', c, c))
         || ' / ' || pg_temp.as_('pg:own', format('update public.app_settings set %I = 100 where id = true returning %I::text', c, c));
    perform pg_temp.check(t like 'ok:0% / ok:100%', 'P15c app_settings.' || c || ': 0 and 100 pass: ' || t);
    perform pg_temp.pin_rates();
  end loop;
end $P15$;

-- ═════ A A change straight on the three tables with the secret key is recorded ═════
do $A$
declare t text; n0 bigint := (select count(*) from public.audit_logs);
begin
  t := pg_temp.as_('service', 'update public.app_settings set commission_tier2_third_rate = 34 where id = true returning 1::text');
  t := t || ' / ' || pg_temp.as_('service', format('update public.credit_packages set tier2_rate = 9 where id = %L returning 1::text', pg_temp.fx('cpr')));
  t := t || ' / ' || pg_temp.as_('service', format('update public.premium_bundles set tier1_rate = 8 where id = %L returning 1::text', pg_temp.fx('pb')));
  perform pg_temp.check(t = 'ok:1 / ok:1 / ok:1', 'A0 the secret key changes the three (as it could): ' || t);
  perform pg_temp.check(
    exists (select 1 from public.audit_logs l where l.table_name = 'app_settings' and l.action = 'settings_updated' and l.record_id is null
              and l.old_data = '{"commission_tier2_third_rate": 35}'::jsonb and l.new_data = '{"commission_tier2_third_rate": 34}'::jsonb
              and l.actor_role = 'service_role' and l.module = 'settings')
    and exists (select 1 from public.audit_logs l where l.table_name = 'credit_packages' and l.action = 'credit_package_updated'
              and l.record_id = pg_temp.fx('cpr') and l.old_data = '{"tier2_rate": null}'::jsonb and l.new_data = '{"tier2_rate": 9.000}'::jsonb)
    and exists (select 1 from public.audit_logs l where l.table_name = 'premium_bundles' and l.action = 'premium_bundle_updated'
              and l.record_id = pg_temp.fx('pb') and l.old_data = '{"tier1_rate": null}'::jsonb and l.new_data = '{"tier1_rate": 8.000}'::jsonb),
    'A1 each is in the audit log with its old and new value (the settings under no record, its module settings)');
  update public.credit_packages set tier2_rate = null where id = pg_temp.fx('cpr');
  update public.premium_bundles set tier1_rate = null where id = pg_temp.fx('pb');
  perform pg_temp.pin_rates();
  perform pg_temp.check((select count(*) from public.audit_logs) = n0 + 3, 'A2 the server''s own changes (postgres) are not recorded twice');
end $A$;

-- ═════ C The staff rebase and staff rate change, closed to logins ═════
select pg_temp.check(not has_function_privilege('authenticated', 'public.apply_commission_rebase_all()', 'execute')
                     and not has_function_privilege('anon', 'public.apply_commission_rebase_all()', 'execute')
                     and has_function_privilege('service_role', 'public.apply_commission_rebase_all()', 'execute'),
  'C1 apply_commission_rebase_all() is closed to anon and authenticated, open to the service role');
select pg_temp.check(not has_function_privilege('authenticated', 'public.set_staff_commission_rate(numeric)', 'execute')
                     and not has_function_privilege('anon', 'public.set_staff_commission_rate(numeric)', 'execute')
                     and has_function_privilege('service_role', 'public.set_staff_commission_rate(numeric)', 'execute'),
  'C2 set_staff_commission_rate(numeric) likewise');
select pg_temp.as_('mgr', 'select public.set_staff_commission_rate(9)::text') as c3 \gset
select pg_temp.check(:'c3' like 'ERR 42501 permission denied%' and (select staff_commission_rate from public.app_settings where id) = 3,
  'C3 a Manager''s call is refused, the staff rate unchanged: ' || :'c3');
select pg_temp.pin_rates();
select pg_temp.check(not has_function_privilege('authenticated', 'public.rebase_staff_commissions(date,date,boolean)', 'execute')
                     and not has_function_privilege('anon', 'public.rebase_staff_commissions(date,date,boolean)', 'execute'),
  'C4 rebase_staff_commissions is closed to logins (as before 535)');

-- ═════ G 535's fixed parts ═════
\if :is_control
\echo NOTE  G, U and M are skipped (control)
\else
create temp table g535(fn text, after_md5 text, acl text);
insert into g535 values
  ('set_commission_rates(numeric,numeric,numeric,numeric)', '6f21984954600ef460aec9bdf4b4fdd2', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
  ('earn_invoice_commission(uuid)', '762c06868e2c2256f008b9468b8a255b', '{postgres=X/postgres,service_role=X/postgres}'),
  ('earn_credit_package_commission(uuid)', '44d10e4bcceb9a94080f1802c1da946f', '{postgres=X/postgres,service_role=X/postgres}'),
  ('earn_premium_bundle_commission(uuid)', '86ea3b1215ed6fd896bfd63ceba21152', '{postgres=X/postgres,service_role=X/postgres}'),
  ('invoice_affiliate_commission_preview(uuid)', '927b9e2129e354c0f061a713083cdb54', '{postgres=X/postgres,service_role=X/postgres}'),
  ('invoice_package_commission_preview(uuid)', 'ef34e72a6bffaebb33af83f2b38f2ade', '{postgres=X/postgres,service_role=X/postgres}'),
  ('sync_instalment_commissions(uuid,text,date,boolean,boolean)', '98fbe647100e8890957f098c6d90fca4', '{postgres=X/postgres,service_role=X/postgres}'),
  ('upsert_credit_package(uuid,text,numeric,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,numeric,text,uuid[],uuid[],boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,numeric)', '51dfbba874668b8d0c75c3d72c859aab', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
  ('upsert_premium_bundle(uuid,text,numeric,numeric,numeric,integer,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,text,uuid[],uuid[])', 'c08e7ed4eed6d8d5772dfcb2305439b6', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
  ('trg_audit_direct_change()', '5dcea97b6479d9bb6a53adfa9dfbcba4', '{postgres=X/postgres,service_role=X/postgres}'),
  ('invoice_affiliate_rates_for(uuid)', '64e6ed85a8f169477fc85bd8452da453', '{postgres=X/postgres}'),
  ('record_invoice_affiliate_rates(uuid,numeric,numeric,numeric,numeric)', 'ae5132e23be0b0acbdec3d92e500bd4c', '{postgres=X/postgres}');
select pg_temp.check(not exists (select 1 from g535 g where md5(pg_get_functiondef(to_regprocedure('public.' || g.fn))) is distinct from g.after_md5),
  'G1 the ten functions and two helpers are 535''s (AFTER md5s)');
select pg_temp.check(not exists (select 1 from g535 g
                                  where (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
                                          where p.oid = to_regprocedure('public.' || g.fn))
                                        is distinct from (select string_agg(x, ',' order by x) from unnest(g.acl::text[]) x)),
  'G2 their grants: the helpers postgres''s alone (not the service role''s), the others as before');
select pg_temp.check(not has_table_privilege('authenticated', 'public.invoice_affiliate_rates', 'select')
                     and not has_table_privilege('authenticated', 'public.invoice_affiliate_rates', 'insert')
                     and not has_table_privilege('anon', 'public.invoice_affiliate_rates', 'select')
                     and not has_table_privilege('service_role', 'public.invoice_affiliate_rates', 'select')
                     and not has_table_privilege('service_role', 'public.invoice_affiliate_rates', 'insert')
                     and not has_table_privilege('service_role', 'public.invoice_affiliate_rates', 'update')
                     and (select string_agg(x::text, ',') from pg_class c, unnest(c.relacl) x where c.oid = 'public.invoice_affiliate_rates'::regclass) = 'postgres=arwdDxtm/postgres'
                     and (select relrowsecurity from pg_class where oid = 'public.invoice_affiliate_rates'::regclass),
  'G3 no login and not the service role reads or writes the kept rates (postgres alone)');
select pg_temp.as_('service', format('insert into public.invoice_affiliate_rates(invoice_id, tier1_own_rate, tier1_third_rate, tier2_own_rate, tier2_third_rate) values (%L, 1, 1, 1, 1) returning 1::text', pg_temp.fx('i:KZ'))) as g3b \gset
select pg_temp.check(:'g3b' like 'ERR 42501 permission denied%', 'G3b the secret key cannot set an invoice''s rates ahead of its first earning: ' || :'g3b');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                    and pg_get_functiondef(p.oid) ~ 'invoice_affiliate_rates_for|record_invoice_affiliate_rates'
                                    and p.proname not in ('invoice_affiliate_rates_for', 'record_invoice_affiliate_rates')
                                    and not (p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres')),
  'G3c every function that calls the two helpers is a postgres-owned SECURITY DEFINER function');
select pg_temp.as_('mgr', 'select count(*)::text from public.invoice_affiliate_rates') as g4 \gset
select pg_temp.check(:'g4' like 'ERR 42501 permission denied%', 'G4 a Manager''s read of the table is refused: ' || :'g4');
select pg_temp.check((select count(*) from pg_constraint where conname in
                       ('credit_packages_tier1_rate_0_100', 'credit_packages_tier2_rate_0_100', 'credit_packages_staff_commission_rate_0_100',
                        'premium_bundles_tier1_rate_0_100', 'premium_bundles_tier2_rate_0_100', 'premium_bundles_staff_commission_rate_0_100',
                        'credit_package_sales_tier1_rate_snapshot_0_100', 'credit_package_sales_tier2_rate_snapshot_0_100',
                        'credit_package_sales_staff_rate_snapshot_0_100', 'premium_bundle_sales_tier1_rate_snapshot_0_100',
                        'premium_bundle_sales_tier2_rate_snapshot_0_100', 'premium_bundle_sales_staff_rate_snapshot_0_100',
                        'app_settings_commission_tier1_own_rate_0_100', 'app_settings_commission_tier1_third_rate_0_100',
                        'app_settings_commission_tier2_own_rate_0_100', 'app_settings_commission_tier2_third_rate_0_100',
                        'app_settings_staff_commission_rate_0_100')) = 17,
  'G5 the seventeen constraints are in (the packages'', bundles'', their sales'' and the settings'' rates)');
select pg_temp.check(
  md5(pg_get_functiondef('public.current_user_role()'::regprocedure)) = '519b0a33a3548f970c5d585b6e76a389'
  and md5(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure)) = '877b3aa74cea559881979bb161c450e2'
  and md5(pg_get_functiondef('public.reconcile_invoice_commissions(uuid,text)'::regprocedure)) = '3c267728e215d17ebeb9cfe9cb7db47c'
  and md5(pg_get_functiondef('public.invoice_instalment_commission_targets(uuid)'::regprocedure)) = 'dc47c3c7b9e41d67b89713fce2a4b480'
  and md5(pg_get_functiondef('public.apply_commission_rebase_all()'::regprocedure)) = '48272cee4f2c9810d66b1e63d0cb8f97'
  and md5(pg_get_functiondef('public.set_staff_commission_rate(numeric)'::regprocedure)) = '84a406c3d260930b444825f1f694b481',
  'G6 the relied-on functions and the two closed ones are unchanged in text');
select pg_temp.check((select count(*) from pg_trigger t where t.tgname = 'audit_direct_change'
                       and t.tgrelid in ('public.app_settings'::regclass, 'public.credit_packages'::regclass, 'public.premium_bundles'::regclass)
                       and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER audit_direct_change AFTER INSERT OR DELETE OR UPDATE ON public.% FOR EACH ROW WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) EXECUTE FUNCTION trg_audit_direct_change()') = 3
                     and (select count(*) from pg_trigger where tgfoid = 'public.trg_audit_direct_change()'::regprocedure) = 16,
  'G9 532''s audit trigger is on app_settings, credit_packages and premium_bundles too (16 tables in all)');
\if :by_us
select pg_temp.check((select string_agg(coalesce(a.fn, b.fn), ', ' order by coalesce(a.fn, b.fn))
                        from fn0 a full join fn1 b using (fn) where a.md5 is distinct from b.md5)
                     = (select string_agg(fn, ', ' order by fn) from g535),
  'G7 installed here, only the ten functions and the two helpers changed text');
select pg_temp.check((select string_agg(a.fn, ', ' order by a.fn) from fn0 a join fn1 b using (fn) where a.acl is distinct from b.acl)
                     = 'apply_commission_rebase_all(), set_staff_commission_rate(numeric)',
  'G8 and only the two closed functions changed grants');

-- ═════ U The undo, then 535 again ═════
savepoint u1;
\ir ../undo-535.sql
select pg_temp.check(not exists (select 1 from fn0 a full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) b using (fn)
                                  where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
                     and to_regclass('public.invoice_affiliate_rates') is null
                     and not exists (select 1 from pg_constraint where conname like '%\_0\_100'
                                       and conrelid in ('public.credit_packages'::regclass, 'public.premium_bundles'::regclass,
                                                        'public.credit_package_sales'::regclass, 'public.premium_bundle_sales'::regclass,
                                                        'public.app_settings'::regclass)),
  'U1 undo-535 puts every function and grant back exactly, drops the table and the seventeen constraints');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-535.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 535: % is already its version of before 535%', 'U2 the undo a second time refuses: ' || :'LAST_ERROR_MESSAGE');
-- After the undo, KN and KY first earned at 20 / 40 while the settings are back at 15 / 35: 535
-- again would keep 15 / 35 for them, so it refuses (as its header says). Their rows are taken
-- away here (rolled back below), and 535 goes in again.
savepoint u2b;
\set ON_ERROR_STOP off
\ir ../../../supabase/535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own.sql
\set ON_ERROR_STOP on
rollback to savepoint u2b;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '535: 4 standing commission row(s) on 2 invoice(s) carry a rate other than today''s settings%',
  'U2b 535 again after the undo refuses while invoices that first earned at other rates stand: ' || :'LAST_ERROR_MESSAGE');
delete from public.commissions where invoice_id in (pg_temp.fx('i:KN'), pg_temp.fx('i:KY'));
\ir ../../../supabase/535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl),
  'U3 535 after the undo makes exactly what it made the first time');
rollback to savepoint u1;
-- M 535 a second time refuses and changes nothing.
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '535 is already in on this database%', 'M1 535 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  G7, G8, U and M are skipped (535 was not installed by this file)
\endif
\endif

select count(*) as n_failed from failed \gset
\if :is_control
\echo control: :n_failed checks failed without 535 (each is one 535 makes pass)
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
