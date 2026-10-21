-- Credit Package credit and Premium Bundle credit kept apart (443; the
-- Owner's answers of 21 Oct 2026, CREDIT-SPLIT-1..14).
--
--   M  443 installs, a second run changes nothing, its self-test leaves no
--      row; the four new wallet methods are there, system and on; the
--      three-argument allocate_invoice_wallet_credit is gone; the grants are
--      as planned; an unknown version of a function it changes, or a live
--      method already using one of the new names, stops it.
--   G  Source groups (credit_lot_source_group): package lots, bundle lots,
--      opening balances and Adjust lots; moved credit counts as its origin;
--      a Legacy lot linked to a Premium Bundle line counts as Premium Bundle.
--   B  Balances (customer_credit_balances): the categories and total as
--      before; by source; each package and bundle bought with what is left,
--      a used-up one too (S$0.00 left), not one refunded in full or gone with
--      its invoice to another customer; moved credit at the recipient, as
--      received; the linked Legacy lot under the bundle.
--   P  Each new method pays only from its source and category; 'Wallet —
--      Paid Credit' and 'Wallet — Bonus Credit' only from 'other' credit;
--      Legacy, Promotional/FOC and Exchange from any source, as before.
--   O  Ordering and the default: Credit Package methods are listed first;
--      the default is the first that can pay; a method of any source takes
--      Credit Package credit first (after Bonus first).
--   X  One invoice paid from both, one payment row per source.
--   R  A refund returns the credit to the lot it came from; a correction
--      keeps the method's source; a past 'Wallet — Paid Credit' payment of
--      Premium Bundle credit is corrected from Premium Bundle credit; a
--      refunded payment cannot change where its credit comes from.
--   A  'available' per method: a product-only invoice and a therapy invoice;
--      paying exactly what is available works, a cent more does not; an
--      invoice selling credit offers none.
--   L  Past payments' sources (invoice_payment_credit_sources).
--   S  The system methods are protected; a source only on a system Paid or
--      Bonus wallet method.
--   K  Who may call what.
--
-- Disposable database only; everything is rolled back. Run from the
-- repository root on a copy of production:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/credit-sources-443.sql
-- (it installs 443 twice; with -v nomig=1 where 443 is in already). Every
-- name, phone and email below is invented: ACMA fictional mobile numbers
-- (+61491570800..+61491570899) and @example.com addresses. A copy without
-- production's five wallet methods gets them, as 82 seeds them, for the run.
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
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
create function pg_temp.fp() returns text language sql as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') $$;
create function pg_temp.md5_of(sig text) returns text language sql as
$$ select md5(pg_get_functiondef(to_regprocedure('public.' || sig))) $$;
create function pg_temp.method(nm text) returns uuid language sql as
$$ select id from public.payment_methods where name = nm and deleted_at is null $$;
-- The sources of a payment's lots, in order (package, bundle, other).
-- (PL/pgSQL, so they can be made before 443 is in.)
create function pg_temp.pay_sources(pay uuid) returns text language plpgsql as
$$begin return (select string_agg(g, ',' order by case g when 'credit_package' then 0 when 'premium_bundle' then 1 else 2 end)
     from (select distinct public.credit_lot_source_group(a.lot_id) g
             from public.invoice_line_credit_allocations a where a.payment_id = pay) x); end$$;
-- One method's entry in invoice_wallet_availability().
create function pg_temp.avail(inv uuid, nm text) returns jsonb language plpgsql as
$$begin return (select m from jsonb_array_elements(public.invoice_wallet_availability(inv) -> 'methods') m
    where m ->> 'name' = nm); end$$;
create function pg_temp.therapy_invoice(qty int) returns uuid language sql as
$$ select public.create_invoice(pg_temp.fx('st'), pg_temp.fx('cust'), null::uuid,
            jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.fx('svc'), 'quantity', qty)),
            0::numeric, null::text, null::uuid, '[]'::jsonb) $$;
create function pg_temp.product_invoice(cust uuid) returns uuid language sql as
$$ select public.create_invoice(pg_temp.fx('st'), cust, null::uuid,
            jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('own'), 'quantity', 1)),
            0::numeric, null::text, null::uuid, '[]'::jsonb) $$;
create function pg_temp.pay(inv uuid, nm text, amount numeric) returns uuid language plpgsql as
$$declare before uuid[]; begin
  before := array(select id from public.invoice_payments where invoice_id = inv);
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', pg_temp.method(nm), 'amount', amount)), gen_random_uuid());
  return (select id from public.invoice_payments where invoice_id = inv and not (id = any (before)));
end$$;

-- ═════ Fixtures (before 443 is installed, where the suite installs it) ═════
-- The five wallet methods production has (82), where the copy has none.
insert into public.payment_methods (name, is_active, is_wallet_credit, wallet_category, is_system)
select v.name, true, true, v.cat, true
  from (values ('Wallet — Paid Credit', 'paid'), ('Wallet — Bonus Credit', 'bonus'),
               ('Wallet — Legacy Credit', 'legacy'), ('Wallet — Promotional/FOC Credit', 'promotional'),
               ('Wallet — Exchange Credit', 'exchange')) v(name, cat)
 where not exists (select 1 from public.payment_methods m where m.name = v.name and m.deleted_at is null);

do $$
declare o uuid := gen_random_uuid(); st uuid; svc uuid; own uuid; third uuid; pk uuid; pb uuid; inv uuid; c uuid;
  cash uuid; r jsonb;
begin
  if exists (select 1 from public.customers where phone like '+614915708%') then
    raise exception 'FIXTURE: a customer already uses the test phones +614915708xx'; end if;
  insert into auth.users(id, email) values (o, 't443-owner@example.com');
  insert into public.profiles(id, full_name, email, role) values (o, 'T443 Owner', 't443-owner@example.com', 'owner');
  perform pg_temp.putx('owner', o);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.stores(name, code, country_code) values ('T443 Store', 'T443S', 'SG') returning id into st;
  perform pg_temp.putx('st', st);
  insert into public.payment_methods(name) values ('T443 Cash') returning id into cash;
  perform pg_temp.putx('cash', cash);
  svc := (public.upsert_therapy_service(null, 'T443-S', 'T443 Session', 100, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform public.set_therapy_service_store(svc, st, true, null);
  perform pg_temp.putx('svc', svc);
  insert into public.products(name, sku, product_type) values ('T443 Own Product', 'T443-OWN', 'own') returning id into own;
  insert into public.products(name, sku, product_type) values ('T443 Third Product', 'T443-THIRD', 'third_party') returning id into third;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, own, 50), (st, third, 50);
  perform public.set_product_prices(st, own, 40, 40, 'available');
  perform public.set_product_prices(st, third, 30, 30, 'available');
  perform pg_temp.putx('own', own);
  insert into public.credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                     allow_product, allow_therapy, allow_voucher, grants_reward)
  values ('T443 Package', 1000, 1000, true, 100, true, true, true, false) returning id into pk;
  insert into public.credit_package_stores(package_id, store_id) values (pk, st);
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
  values ('T443 Bundle', 500, 500, 50, 0, false) returning id into pb;
  insert into public.premium_bundle_stores(bundle_id, store_id) values (pb, st);
  perform pg_temp.putx('pk', pk); perform pg_temp.putx('pb', pb);

  -- Each customer below buys with cash, through invoices, as the till does.
  foreach r in array array[
      jsonb_build_object('k', 'cust', 'name', 'T443 Alpha', 'phone', '+61491570801', 'buy', 'both'),
      jsonb_build_object('k', 'charlie', 'name', 'T443 Charlie', 'phone', '+61491570803', 'buy', 'package'),
      jsonb_build_object('k', 'bravo', 'name', 'T443 Bravo', 'phone', '+61491570802', 'buy', ''),
      jsonb_build_object('k', 'delta', 'name', 'T443 Delta', 'phone', '+61491570804', 'buy', 'bundle'),
      jsonb_build_object('k', 'echo', 'name', 'T443 Echo', 'phone', '+61491570805', 'buy', 'package'),
      jsonb_build_object('k', 'fox', 'name', 'T443 Foxtrot', 'phone', '+61491570806', 'buy', 'bundle')] loop
    insert into public.customers(full_name, phone) values (r ->> 'name', r ->> 'phone') returning id into c;
    perform pg_temp.putx(r ->> 'k', c);
    if r ->> 'buy' in ('both', 'package') then
      inv := public.create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind', 'credit_package',
               'credit_package_id', pk, 'quantity', 1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 1000)), gen_random_uuid());
      perform pg_temp.putx(r ->> 'k' || ':pk_inv', inv);
    end if;
    if r ->> 'buy' in ('both', 'bundle') then
      inv := public.create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind', 'premium_bundle',
               'premium_bundle_id', pb, 'quantity', 1, 'voucher_selection', '[]'::jsonb)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 500)), gen_random_uuid());
      perform pg_temp.putx(r ->> 'k' || ':pb_inv', inv);
    end if;
  end loop;

  c := pg_temp.fx('cust');
  -- Alpha's other credit: a Paid opening balance (older than her purchases),
  -- an Adjust Bonus, a Legacy opening balance, Promotional and Exchange.
  perform public.add_legacy_credit(c, 'paid', 70, public.sg_today() - 400, st, 'T443-OB-PAID', 'T443 opening paid', public.sg_today() - 30, gen_random_uuid());
  perform public.adjust_customer_credit(c, 'bonus', 'increase', 20, 'T443 adjust bonus', 'T443-ADJ-B', public.sg_today() - 30, null, st, gen_random_uuid());
  perform public.add_legacy_credit(c, 'legacy', 60, public.sg_today() - 400, st, 'T443-OB-LEG', 'T443 opening legacy', public.sg_today() - 60, gen_random_uuid());
  perform public.adjust_customer_credit(c, 'promotional', 'increase', 15, 'T443 adjust promo', 'T443-ADJ-P', null, null, st, gen_random_uuid());
  perform public.adjust_customer_credit(c, 'exchange', 'increase', 12, 'T443 adjust exchange', 'T443-ADJ-X', null, null, st, gen_random_uuid());
  -- A Legacy lot recorded as a Premium Bundle line's released credit, as the
  -- 3 Legacy lots of 25 Sep 2026 are (the one-off repair is not in the repo).
  perform public.add_legacy_credit(c, 'legacy', 45, public.sg_today() - 400, st, 'T443-OB-LINK', 'T443 linked legacy', public.sg_today(), gen_random_uuid());
  insert into public.credit_package_progress_lots(lot_id, invoice_item_id, invoice_id, released_amount)
  select l.id, ii.id, ii.invoice_id, 45
    from public.customer_credit_lots l, public.invoice_items ii
   where l.reference_no = 'T443-OB-LINK' and ii.invoice_id = pg_temp.fx('cust:pb_inv');
  perform pg_temp.putx('linked_lot', (select id from public.customer_credit_lots where reference_no = 'T443-OB-LINK'));
  perform pg_temp.putx('other_legacy_lot', (select id from public.customer_credit_lots where reference_no = 'T443-OB-LEG'));
  perform pg_temp.putx('other_paid_lot', (select id from public.customer_credit_lots where reference_no = 'T443-OB-PAID'));

  -- Charlie's Paid package credit moved to Bravo (Move, 186).
  r := public.transfer_invoice_unused_benefit(
         (select v.id from public.invoice_benefit_values v join public.customer_credit_lots l on l.id = v.lot_id
           where v.invoice_id = pg_temp.fx('charlie:pk_inv') and l.category = 'paid'),
         pg_temp.fx('bravo'), st, 'T443 move the unused paid credit', gen_random_uuid());
  perform pg_temp.putx('moved_lot', (select lot_id from public.invoice_benefit_values where id = (r ->> 'benefit_id')::uuid));

  -- Echo: a Bonus Adjust older than her package's Bonus.
  perform public.adjust_customer_credit(pg_temp.fx('echo'), 'bonus', 'increase', 30, 'T443 older bonus', 'T443-ADJ-E',
                                        public.sg_today() - 10, null, st, gen_random_uuid());
  insert into public.payment_methods(name, is_wallet_credit) values ('T443 Any Wallet', true) returning id into c;
  perform pg_temp.putx('any_wallet', c);
end $$;

-- A payment taken through 'Wallet — Paid Credit' before 443, which drew from
-- any source: Foxtrot's bundle credit (made the way record_invoice_payment
-- made it then: the allocation with no source, the payment row, the link).
do $$
declare inv uuid; pay uuid := gen_random_uuid();
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('fox'), null::uuid,
           jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.fx('svc'), 'quantity', 1)),
           0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform public.allocate_invoice_wallet_credit(inv, 100, 'paid');
  perform public.invoice_record_payments_internal(inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', pg_temp.method('Wallet — Paid Credit'), 'amount', 100, 'payment_id', pay)));
  update public.invoice_line_credit_allocations set payment_id = pay where invoice_id = inv and payment_id is null;
  perform pg_temp.putx('fox:inv', inv); perform pg_temp.putx('fox:pay', pay);
end $$;

-- ═════ M Install ═════
create temp table m443(fp_before text, n_methods int, n_lots int, n_ledger int, n_alloc int, n_cust int, n_inv int,
                       lots_hash text);
insert into m443 select pg_temp.fp(), (select count(*) from public.payment_methods), (select count(*) from public.customer_credit_lots),
                        (select count(*) from public.customer_credit_ledger), (select count(*) from public.invoice_line_credit_allocations),
                        (select count(*) from public.customers), (select count(*) from public.invoices),
                        (select md5(string_agg(to_jsonb(l)::text, '|' order by l.id)) from public.customer_credit_lots l);
\if :{?nomig}
select pg_temp.check(pg_temp.md5_of('credit_lot_source_group(uuid)') is not null
    and to_regprocedure('public.allocate_invoice_wallet_credit(uuid,numeric,text)') is null,
  'M0 443 is installed (nomig)');
\else
select pg_temp.check(to_regprocedure('public.credit_lot_source_group(uuid)') is null
    and to_regprocedure('public.allocate_invoice_wallet_credit(uuid,numeric,text)') is not null,
  'M0 443 is not in yet (this suite installs it; use -v nomig=1 where it is in)');
-- M5 a live method already named as one of the new ones stops it.
savepoint m5;
insert into public.payment_methods(name) values ('Wallet — Premium Bundle Paid');
\set ON_ERROR_STOP off
\ir ../../../supabase/443_credit_package_and_premium_bundle_credit_apart.sql
\set m5_failed :ERROR
\set m5_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m5;
-- M6 an unknown version of a function it changes stops it.
savepoint m6;
do $$ begin
  execute replace(pg_get_functiondef('public.customer_credit_balances(uuid)'::regprocedure),
                  'declare v_cats jsonb;', 'declare /* another version */ v_cats jsonb;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/443_credit_package_and_premium_bundle_credit_apart.sql
\set m6_failed :ERROR
\set m6_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m6;
select pg_temp.check(:'m5_failed' = 'true' and :'m5_msg' like '443: a live payment method is already called "Wallet — Premium Bundle Paid"%'
    and to_regprocedure('public.credit_lot_source_group(uuid)') is null,
  'M5 a live method already using a new name stops it, changing nothing: ' || :'m5_msg');
select pg_temp.check(:'m6_failed' = 'true' and :'m6_msg' like '443: public.customer_credit_balances(uuid) is not the version this was tested against%',
  'M6 an unknown version of a function it changes stops it: ' || :'m6_msg');
\ir ../../../supabase/443_credit_package_and_premium_bundle_credit_apart.sql
do $$ begin perform pg_temp.put('fp1', pg_temp.fp()); end $$;
\ir ../../../supabase/443_credit_package_and_premium_bundle_credit_apart.sql
select pg_temp.check(pg_temp.fp() = pg_temp.tx('fp1') and pg_temp.fp() <> (select fp_before from m443)
    and split_part(pg_temp.fp(), ' ', 2)::int = split_part((select fp_before from m443), ' ', 2)::int + 4,
  'M1 443 installs (4 functions more: 5 new, the old allocate dropped) and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check((select count(*) from public.payment_methods) = (select n_methods from m443) + 4
    and (select count(*) from public.customer_credit_lots) = (select n_lots from m443)
    and (select md5(string_agg(to_jsonb(l)::text, '|' order by l.id)) from public.customer_credit_lots l) = (select lots_hash from m443)
    and (select count(*) from public.customer_credit_ledger) = (select n_ledger from m443)
    and (select count(*) from public.invoice_line_credit_allocations) = (select n_alloc from m443)
    and (select count(*) from public.customers) = (select n_cust from m443)
    and (select count(*) from public.invoices) = (select n_inv from m443),
  'M2 it adds the 4 methods and nothing else: no lot changed, no ledger row, allocation, customer or invoice (its self-test, twice, left none)');
\endif
select pg_temp.check((select count(*) from public.payment_methods m
                       where m.deleted_at is null and m.is_system and m.is_active and m.is_wallet_credit
                         and (m.name, m.wallet_category, m.wallet_source) in
                             (('Wallet — Credit Package Paid', 'paid', 'credit_package'),
                              ('Wallet — Credit Package Bonus', 'bonus', 'credit_package'),
                              ('Wallet — Premium Bundle Paid', 'paid', 'premium_bundle'),
                              ('Wallet — Premium Bundle Bonus', 'bonus', 'premium_bundle'))) = 4
    and (select count(*) from public.payment_methods m where m.wallet_source is not null) = 4
    and (select count(*) from public.payment_methods m
          where m.deleted_at is null and m.is_system and m.wallet_source is null
            and (m.name, m.wallet_category) in (('Wallet — Paid Credit', 'paid'), ('Wallet — Bonus Credit', 'bonus'),
                 ('Wallet — Legacy Credit', 'legacy'), ('Wallet — Promotional/FOC Credit', 'promotional'),
                 ('Wallet — Exchange Credit', 'exchange'))) = 5,
  'M3 the four methods per source are there (system, on), and the five of 82 keep their names, categories and no source');
select pg_temp.check(to_regprocedure('public.allocate_invoice_wallet_credit(uuid,numeric,text)') is null
    and to_regprocedure('public.allocate_invoice_wallet_credit(uuid,numeric,text,text)') is not null
    and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'allocate_invoice_wallet_credit') = 1,
  'M4 allocate_invoice_wallet_credit has one signature, (uuid,numeric,text,text); the three-argument one is gone');

-- ═════ G Source groups ═════
do $$
declare c uuid := pg_temp.fx('cust');
begin
  perform pg_temp.check(
    (select bool_and(public.credit_lot_source_group(l.id) = 'credit_package') from public.customer_credit_lots l
      where l.customer_id = c and l.source_type = 'credit_package')
    and (select count(*) from public.customer_credit_lots l where l.customer_id = c and l.source_type = 'credit_package') = 2
    and (select bool_and(public.credit_lot_source_group(l.id) = 'premium_bundle') from public.customer_credit_lots l
          where l.customer_id = c and l.source_type = 'premium_bundle')
    and (select count(*) from public.customer_credit_lots l where l.customer_id = c and l.source_type = 'premium_bundle') = 2,
    'G1 a Credit Package''s lots (Paid and Bonus) are credit_package; a Premium Bundle''s are premium_bundle');
  perform pg_temp.check(
    (select bool_and(public.credit_lot_source_group(l.id) = 'other') from public.customer_credit_lots l
      where l.customer_id = c and l.source_type in ('manual_legacy', 'manual_adjustment') and l.id <> pg_temp.fx('linked_lot'))
    and (select count(*) from public.customer_credit_lots l
          where l.customer_id = c and l.source_type in ('manual_legacy', 'manual_adjustment') and l.id <> pg_temp.fx('linked_lot')) = 5,
    'G2 opening balances (Paid, Legacy) and Adjust lots (Bonus, Promotional, Exchange) are other');
  perform pg_temp.check(public.credit_lot_source_group(pg_temp.fx('linked_lot')) = 'premium_bundle'
      and (select category from public.customer_credit_lots where id = pg_temp.fx('linked_lot')) = 'legacy'
      and (select source_type from public.customer_credit_lots where id = pg_temp.fx('linked_lot')) = 'manual_legacy',
    'G3 a Legacy lot recorded as a Premium Bundle line''s released credit is premium_bundle (still Legacy, still manual_legacy)');
  perform pg_temp.check(public.credit_lot_source_group(pg_temp.fx('moved_lot')) = 'credit_package'
      and (select source_type from public.customer_credit_lots where id = pg_temp.fx('moved_lot')) = 'invoice_benefit_transfer'
      and (select customer_id from public.customer_credit_lots where id = pg_temp.fx('moved_lot')) = pg_temp.fx('bravo'),
    'G4 credit moved to another customer counts as its origin (credit_package)');
  perform pg_temp.check(public.credit_lot_source_group(gen_random_uuid()) is null, 'G5 no such lot: null');
end $$;

-- ═════ B Balances ═════
do $$
declare b jsonb; p jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  b := public.customer_credit_balances(pg_temp.fx('cust'));
  perform pg_temp.check(b -> 'categories' = '{"paid": 1570, "bonus": 170, "legacy": 105, "promotional": 15, "exchange": 12}'::jsonb
      and (b ->> 'available_total')::numeric = 1872 and b ->> 'customer_id' = pg_temp.fx('cust')::text,
    'B1 the categories and the total are as before: ' || (b -> 'categories')::text || ' ' || (b ->> 'available_total'));
  perform pg_temp.check(b -> 'sources' = jsonb_build_object(
      'credit_package', '{"paid": 1000, "bonus": 100, "legacy": 0, "promotional": 0, "exchange": 0, "total": 1100}'::jsonb,
      'premium_bundle', '{"paid": 500, "bonus": 50, "legacy": 45, "promotional": 0, "exchange": 0, "total": 595}'::jsonb,
      'other', '{"paid": 70, "bonus": 20, "legacy": 60, "promotional": 15, "exchange": 12, "total": 177}'::jsonb),
    'B2 by source: Credit Package 1100, Premium Bundle 595 (the linked Legacy lot under it), Other 177: ' || (b -> 'sources')::text);
  perform pg_temp.check(jsonb_array_length(b -> 'purchases') = 2
      and b -> 'purchases' -> 0 ->> 'source' = 'credit_package' and b -> 'purchases' -> 0 ->> 'name' = 'T443 Package'
      and b -> 'purchases' -> 0 ->> 'invoice_no' = (select invoice_no from public.invoices where id = pg_temp.fx('cust:pk_inv'))
      and (b -> 'purchases' -> 0 ->> 'paid')::numeric = 1000 and (b -> 'purchases' -> 0 ->> 'bonus')::numeric = 100
      and (b -> 'purchases' -> 0 ->> 'total')::numeric = 1100 and (b -> 'purchases' -> 0 ->> 'bought_on')::date = public.sg_today()
      and b -> 'purchases' -> 1 ->> 'source' = 'premium_bundle' and b -> 'purchases' -> 1 ->> 'name' = 'T443 Bundle'
      and b -> 'purchases' -> 1 ->> 'invoice_no' = (select invoice_no from public.invoices where id = pg_temp.fx('cust:pb_inv'))
      and (b -> 'purchases' -> 1 ->> 'paid')::numeric = 500 and (b -> 'purchases' -> 1 ->> 'bonus')::numeric = 50
      and (b -> 'purchases' -> 1 ->> 'legacy')::numeric = 45 and (b -> 'purchases' -> 1 ->> 'total')::numeric = 595
      and not (b -> 'purchases' -> 0 ->> 'received')::boolean and not (b -> 'purchases' -> 1 ->> 'received')::boolean,
    'B3 each package and bundle bought, with what is left (the linked Legacy lot under its bundle): ' || (b -> 'purchases')::text);
  b := public.customer_credit_balances(pg_temp.fx('bravo'));
  perform pg_temp.check((b -> 'sources' -> 'credit_package' ->> 'paid')::numeric = 1000
      and (b -> 'sources' -> 'other' ->> 'total')::numeric = 0
      and jsonb_array_length(b -> 'purchases') = 1 and b -> 'purchases' -> 0 ->> 'name' = 'T443 Package'
      and b -> 'purchases' -> 0 ->> 'invoice_no' = (select invoice_no from public.invoices where id = pg_temp.fx('charlie:pk_inv'))
      and (b -> 'purchases' -> 0 ->> 'received')::boolean,
    'B4 moved credit shows at the recipient as Credit Package credit, under the purchase it came from, as received: ' || b::text);
  b := public.customer_credit_balances(pg_temp.fx('charlie'));
  perform pg_temp.check((b -> 'sources' -> 'credit_package' ->> 'paid')::numeric = 0
      and (b -> 'sources' -> 'credit_package' ->> 'bonus')::numeric = 100
      and jsonb_array_length(b -> 'purchases') = 1 and (b -> 'purchases' -> 0 ->> 'paid')::numeric = 0
      and (b -> 'purchases' -> 0 ->> 'bonus')::numeric = 100 and not (b -> 'purchases' -> 0 ->> 'received')::boolean,
    'B5 the customer it moved from keeps only what was not moved');
end $$;

-- B6..B8: a purchase used up stays listed (S$0.00 left); one refunded in full,
-- or gone with its invoice to another customer, does not.
do $$
declare st uuid := pg_temp.fx('st'); pk uuid := pg_temp.fx('pk'); cash uuid := pg_temp.fx('cash');
  g uuid; h uuid; i uuid; j uuid; inv1 uuid; inv2 uuid; inv3 uuid; inv4 uuid; b jsonb; req jsonb; res jsonb; item uuid;
  cp jsonb := jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('pk'), 'quantity', 1));
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into public.customers(full_name, phone) values ('T443 Golf', '+61491570807') returning id into g;
  insert into public.customers(full_name, phone) values ('T443 Hotel', '+61491570808') returning id into h;
  insert into public.customers(full_name, phone) values ('T443 India', '+61491570809') returning id into i;
  insert into public.customers(full_name, phone) values ('T443 Juliet', '+61491570810') returning id into j;
  -- B6 Golf buys a package, uses it all up (Adjust decreases), buys another.
  inv1 := public.create_invoice(st, g, null::uuid, cp, 0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform public.record_invoice_payment(inv1, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 1000)), gen_random_uuid());
  perform public.adjust_customer_credit(g, 'paid', 'decrease', 1000, 'T443 used up paid', 'T443-ADJ-G1', null, null, st, gen_random_uuid());
  perform public.adjust_customer_credit(g, 'bonus', 'decrease', 100, 'T443 used up bonus', 'T443-ADJ-G2', null, null, st, gen_random_uuid());
  b := public.customer_credit_balances(g);
  perform pg_temp.check(jsonb_array_length(b -> 'purchases') = 1 and (b -> 'purchases' -> 0 ->> 'total')::numeric = 0
      and b -> 'purchases' -> 0 ->> 'invoice_no' = (select invoice_no from public.invoices where id = inv1)
      and (b ->> 'available_total')::numeric = 0,
    'B6a a package whose credit is all used up is still listed, with S$0.00 left: ' || (b -> 'purchases')::text);
  inv2 := public.create_invoice(st, g, null::uuid, cp, 0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform public.record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 1000)), gen_random_uuid());
  b := public.customer_credit_balances(g);
  perform pg_temp.check(jsonb_array_length(b -> 'purchases') = 2
      and (select (x ->> 'total')::numeric from jsonb_array_elements(b -> 'purchases') x
            where x ->> 'invoice_no' = (select invoice_no from public.invoices where id = inv1)) = 0
      and (select (x ->> 'total')::numeric from jsonb_array_elements(b -> 'purchases') x
            where x ->> 'invoice_no' = (select invoice_no from public.invoices where id = inv2)) = 1100,
    'B6b bought again: both purchases, the first with S$0.00 left, the second with S$1,100.00: ' || (b -> 'purchases')::text);
  -- B7 Hotel buys a package and it is refunded in full: its credit is taken back.
  inv3 := public.create_invoice(st, h, null::uuid, cp, 0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform public.record_invoice_payment(inv3, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 1000)), gen_random_uuid());
  req := public.request_invoice_action_v2(inv3, 'refund_full', '[]'::jsonb, 'T443 refund the package', null, gen_random_uuid());
  res := public.resolve_invoice_action_v2((req ->> 'request_id')::uuid, true, 'T443 agreed', null, '[]'::jsonb, null, false);
  b := public.customer_credit_balances(h);
  perform pg_temp.check((select status::text from public.invoices where id = inv3) = 'refunded'
      and (b ->> 'available_total')::numeric = 0 and jsonb_array_length(b -> 'purchases') = 0,
    'B7 a package refunded in full (its credit taken back) is not listed: ' || coalesce(res ->> 'status', '?') || ' ' || (b -> 'purchases')::text);
  -- B8 India buys a package; the invoice is reassigned to Juliet with its credit.
  inv4 := public.create_invoice(st, i, null::uuid, cp, 0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform public.record_invoice_payment(inv4, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 1000)), gen_random_uuid());
  select id into item from public.invoice_items where invoice_id = inv4;
  perform public.correct_invoice(inv4,
    jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'kind', 'credit_package', 'credit_package_id', pk, 'quantity', 1)),
    jsonb_build_object('customer_id', j, 'benefit_action', 'transfer'), 'T443 reassign to Juliet', gen_random_uuid());
  b := public.customer_credit_balances(i);
  perform pg_temp.check(jsonb_array_length(b -> 'purchases') = 0 and (b ->> 'available_total')::numeric = 0,
    'B8a a package whose invoice went to another customer with its credit is no longer listed at the first: ' || (b -> 'purchases')::text);
  b := public.customer_credit_balances(j);
  perform pg_temp.check(jsonb_array_length(b -> 'purchases') = 1 and (b -> 'purchases' -> 0 ->> 'total')::numeric = 1100
      and b -> 'purchases' -> 0 ->> 'invoice_no' = (select invoice_no from public.invoices where id = inv4)
      and not (b -> 'purchases' -> 0 ->> 'received')::boolean,
    'B8b it is listed at the customer the invoice went to, as bought: ' || (b -> 'purchases')::text);
end $$;

-- ═════ A What each method can pay of THIS invoice ═════
do $$
declare inv uuid; a jsonb; m jsonb; v text;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  -- A therapy session of 100.
  inv := pg_temp.therapy_invoice(1); perform pg_temp.putx('inv_t', inv);
  a := public.invoice_wallet_availability(inv);
  select string_agg((x ->> 'name') || '=' || trim_scale((x ->> 'available')::numeric) || '/' || trim_scale((x ->> 'held')::numeric),
                    '; ' order by (x ->> 'rank')::int) into v
    from jsonb_array_elements(a -> 'methods') x where x ->> 'name' like 'Wallet —%';
  perform pg_temp.check(v = 'Wallet — Credit Package Paid=100/1000; Wallet — Credit Package Bonus=0/100; '
      || 'Wallet — Premium Bundle Paid=100/500; Wallet — Premium Bundle Bonus=50/50; Wallet — Paid Credit=70/70; '
      || 'Wallet — Bonus Credit=20/20; Wallet — Legacy Credit=100/105; Wallet — Promotional/FOC Credit=15/15; '
      || 'Wallet — Exchange Credit=12/12',
    'A1 a therapy invoice (100): what each method can pay of it / what it holds, Credit Package first: ' || v);
  perform pg_temp.check((a ->> 'payable')::boolean and not (a ->> 'credit_line')::boolean
      and (a ->> 'default_method_id')::uuid = pg_temp.method('Wallet — Credit Package Paid'),
    'O1 when both could pay, the default is Credit Package credit (Wallet — Credit Package Paid)');
  -- An own-brand product of 40.
  inv := pg_temp.product_invoice(pg_temp.fx('cust')); perform pg_temp.putx('inv_p', inv);
  a := public.invoice_wallet_availability(inv);
  select string_agg((x ->> 'name') || '=' || trim_scale((x ->> 'available')::numeric), '; ' order by (x ->> 'rank')::int) into v
    from jsonb_array_elements(a -> 'methods') x where x ->> 'name' like 'Wallet —%';
  perform pg_temp.check(v = 'Wallet — Credit Package Paid=0; Wallet — Credit Package Bonus=40; '
      || 'Wallet — Premium Bundle Paid=40; Wallet — Premium Bundle Bonus=40; Wallet — Paid Credit=40; '
      || 'Wallet — Bonus Credit=20; Wallet — Legacy Credit=40; Wallet — Promotional/FOC Credit=15; Wallet — Exchange Credit=12',
    'A2 a product-only invoice (40): Credit Package Paid credit (therapy sessions only) can pay none of it: ' || v);
  perform pg_temp.check((a ->> 'default_method_id')::uuid = pg_temp.method('Wallet — Credit Package Bonus'),
    'O2 the default is the first method that can pay: here Wallet — Credit Package Bonus');
  -- Exactly what is available is accepted; a cent more is not (the same rules as payment).
  perform pg_temp.check(pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', pg_temp.fx('inv_t'),
      jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Premium Bundle Bonus'), 'amount', 50.01)),
      gen_random_uuid())) like '%Only 50.00 of the requested 50.01 could be funded by eligible credit%',
    'A3 a cent more than available is refused, as the server would');
  perform pg_temp.check(pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', pg_temp.fx('inv_p'),
      jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Credit Package Paid'), 'amount', 1)),
      gen_random_uuid())) like '%Only 0.00 of the requested 1.00 could be funded by eligible credit%'
      or pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', pg_temp.fx('inv_p'),
      jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Credit Package Paid'), 'amount', 1)),
      gen_random_uuid())) like '%Only 0 of the requested 1.00 could be funded by eligible credit%',
    'A4 a method with nothing available for the invoice is refused at payment too');
  -- An invoice that sells credit offers none.
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('cust'), null::uuid, jsonb_build_array(jsonb_build_object('kind', 'credit_package',
           'credit_package_id', pg_temp.fx('pk'), 'quantity', 1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
  a := public.invoice_wallet_availability(inv);
  perform pg_temp.check(not (a ->> 'payable')::boolean and (a ->> 'credit_line')::boolean and a ->> 'default_method_id' is null
      and (select bool_and((x ->> 'available')::numeric = 0) from jsonb_array_elements(a -> 'methods') x)
      and (pg_temp.avail(inv, 'Wallet — Credit Package Paid') ->> 'held')::numeric = 1000,
    'A5 an invoice that sells a Credit Package: no method can pay any of it (held still shown)');
end $$;

-- ═════ P / X Paying: each method from its own source; two sources as two rows ═════
do $$
declare inv uuid := pg_temp.fx('inv_t'); p1 uuid; p2 uuid; p3 uuid; before_rows int; r jsonb; s jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  -- X: one Record Payment with two wallet rows, Credit Package Paid 50 and
  -- Premium Bundle Paid 30: two payment rows, one per source.
  before_rows := (select count(*) from public.invoice_payments where invoice_id = inv);
  perform public.record_invoice_payment(inv, jsonb_build_array(
    jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Credit Package Paid'), 'amount', 50),
    jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Premium Bundle Paid'), 'amount', 30)), gen_random_uuid());
  select id into p1 from public.invoice_payments where invoice_id = inv and payment_method_id = pg_temp.method('Wallet — Credit Package Paid');
  select id into p2 from public.invoice_payments where invoice_id = inv and payment_method_id = pg_temp.method('Wallet — Premium Bundle Paid');
  perform pg_temp.check((select count(*) from public.invoice_payments where invoice_id = inv) = before_rows + 2
      and pg_temp.pay_sources(p1) = 'credit_package' and pg_temp.pay_sources(p2) = 'premium_bundle'
      and (select sum(amount) from public.invoice_line_credit_allocations where payment_id = p1) = 50
      and (select sum(amount) from public.invoice_line_credit_allocations where payment_id = p2) = 30
      and (select bool_and(l.category = 'paid') from public.invoice_line_credit_allocations a
             join public.customer_credit_lots l on l.id = a.lot_id where a.payment_id in (p1, p2)),
    'X1/P1 one invoice paid from both: two payment rows, Credit Package Paid from package Paid credit, Premium Bundle Paid from bundle Paid credit');
  -- P2: 'Wallet — Paid Credit' draws only 'other' Paid credit (the opening balance).
  p3 := pg_temp.pay(inv, 'Wallet — Paid Credit', 20);
  perform pg_temp.check(pg_temp.pay_sources(p3) = 'other'
      and (select bool_and(a.lot_id = pg_temp.fx('other_paid_lot')) from public.invoice_line_credit_allocations a where a.payment_id = p3)
      and (select status::text from public.invoices where id = inv) = 'paid',
    'P2 Wallet — Paid Credit pays from other Paid credit only (the opening balance), and the invoice is paid');
  s := public.invoice_payment_credit_sources(inv);
  perform pg_temp.check(s -> p1::text = '["credit_package"]'::jsonb and s -> p2::text = '["premium_bundle"]'::jsonb
      and s -> p3::text = '["other"]'::jsonb
      and (select count(*) from jsonb_object_keys(s)) = 3,
    'L1 each wallet payment''s source, from the lots it used: ' || s::text);

  -- P3: the Bonus methods on the product invoice (40): 10 each.
  inv := pg_temp.fx('inv_p');
  p1 := pg_temp.pay(inv, 'Wallet — Credit Package Bonus', 10);
  p2 := pg_temp.pay(inv, 'Wallet — Premium Bundle Bonus', 10);
  p3 := pg_temp.pay(inv, 'Wallet — Bonus Credit', 10);
  perform pg_temp.check(pg_temp.pay_sources(p1) = 'credit_package' and pg_temp.pay_sources(p2) = 'premium_bundle'
      and pg_temp.pay_sources(p3) = 'other'
      and (select bool_and(l.category = 'bonus') from public.invoice_line_credit_allocations a
             join public.customer_credit_lots l on l.id = a.lot_id where a.payment_id in (p1, p2, p3)),
    'P3 the Bonus methods: Credit Package Bonus, Premium Bundle Bonus and Wallet — Bonus Credit each from its own Bonus credit');
  -- P4: Bonus Credit has no other Bonus left (20 - 10 = 10): 10.01 is refused, though bundle Bonus is there.
  perform pg_temp.check(pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', inv,
      jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Bonus Credit'), 'amount', 10.01)),
      gen_random_uuid())) like '%could be funded by eligible credit%',
    'P4 Wallet — Bonus Credit never reaches Credit Package or Premium Bundle Bonus credit');
end $$;

-- P5: a customer holding only Premium Bundle credit: Wallet — Paid Credit pays nothing; Premium Bundle Paid does.
do $$
declare inv uuid; p uuid;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('delta'), null::uuid,
           jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.fx('svc'), 'quantity', 1)),
           0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform pg_temp.check((pg_temp.avail(inv, 'Wallet — Paid Credit') ->> 'available')::numeric = 0
      and (pg_temp.avail(inv, 'Wallet — Paid Credit') ->> 'held')::numeric = 0
      and (pg_temp.avail(inv, 'Wallet — Premium Bundle Paid') ->> 'available')::numeric = 100
      and (public.invoice_wallet_availability(inv) ->> 'default_method_id')::uuid = pg_temp.method('Wallet — Premium Bundle Paid')
      and pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', inv,
            jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Paid Credit'), 'amount', 10)),
            gen_random_uuid())) like '%could be funded by eligible credit%',
    'P5 bundle credit only: Wallet — Paid Credit can pay none of it and is refused; the default is Premium Bundle Paid');
  p := pg_temp.pay(inv, 'Wallet — Premium Bundle Paid', 100);
  perform pg_temp.check(pg_temp.pay_sources(p) = 'premium_bundle', 'P6 Premium Bundle Paid pays it');
end $$;

-- P7: Legacy, Promotional/FOC and Exchange pay from any source, as before.
do $$
declare inv uuid; p uuid; p2 uuid; p3 uuid;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  inv := pg_temp.therapy_invoice(1);
  p := pg_temp.pay(inv, 'Wallet — Legacy Credit', 100);
  p2 := pg_temp.pay(pg_temp.product_invoice(pg_temp.fx('cust')), 'Wallet — Promotional/FOC Credit', 15);
  p3 := pg_temp.pay(pg_temp.product_invoice(pg_temp.fx('cust')), 'Wallet — Exchange Credit', 12);
  perform pg_temp.check(pg_temp.pay_sources(p) = 'premium_bundle,other'
      and (select sum(amount) from public.invoice_line_credit_allocations where payment_id = p and lot_id = pg_temp.fx('other_legacy_lot')) = 60
      and (select sum(amount) from public.invoice_line_credit_allocations where payment_id = p and lot_id = pg_temp.fx('linked_lot')) = 40
      and pg_temp.pay_sources(p2) = 'other' and pg_temp.pay_sources(p3) = 'other',
    'P7 Wallet — Legacy Credit draws Legacy credit of any source (the older opening balance first, then the linked lot); Promotional/FOC and Exchange as before');
  perform pg_temp.check(public.invoice_payment_credit_sources(inv) -> p::text = '["premium_bundle", "other"]'::jsonb,
    'L2 a payment that drew on two sources lists both, Premium Bundle before Other');
end $$;

-- O3: a method of any source takes Bonus first and then Credit Package credit
-- before older credit (Echo: an older Adjust Bonus 30, her package's Bonus 100).
do $$
declare inv uuid; p uuid;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  inv := pg_temp.product_invoice(pg_temp.fx('echo'));
  p := pg_temp.pay(inv, 'T443 Any Wallet', 40);
  perform pg_temp.check(pg_temp.pay_sources(p) = 'credit_package'
      and (select bool_and(l.category = 'bonus' and l.source_type = 'credit_package') from public.invoice_line_credit_allocations a
             join public.customer_credit_lots l on l.id = a.lot_id where a.payment_id = p),
    'O3 a wallet method naming no category or source takes Credit Package Bonus before the older Adjust Bonus');
  perform pg_temp.check((select (x ->> 'rank')::int from jsonb_array_elements(public.invoice_wallet_availability(inv) -> 'methods') x
                           where x ->> 'name' = 'T443 Any Wallet')
                        > (select max((x ->> 'rank')::int) from jsonb_array_elements(public.invoice_wallet_availability(inv) -> 'methods') x
                            where x ->> 'name' like 'Wallet —%'),
    'O4 other wallet methods are listed after the nine Wallet methods');
end $$;

-- ═════ R Refunds and corrections ═════
do $$
declare inv uuid; p uuid; item uuid; lot uuid; before numeric; r jsonb; rep uuid; v text;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  -- R1: a refund of a Premium Bundle Paid payment returns to the very lot.
  inv := pg_temp.therapy_invoice(1);
  select id into lot from public.customer_credit_lots where customer_id = pg_temp.fx('cust') and source_type = 'premium_bundle' and category = 'paid';
  before := (select remaining_amount from public.customer_credit_lots where id = lot);
  p := pg_temp.pay(inv, 'Wallet — Premium Bundle Paid', 100);
  select id into item from public.invoice_items where invoice_id = inv;
  perform public.refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', p, 'amount', 100)), '[]'::jsonb, 'T443 refund', gen_random_uuid());
  perform pg_temp.check((select remaining_amount from public.customer_credit_lots where id = lot) = before
      and (select sum(amount - reversed_amount) from public.invoice_line_credit_allocations where payment_id = p) = 0
      and public.invoice_payment_credit_sources(inv) -> p::text = '["premium_bundle"]'::jsonb,
    'R1 a refund of a Premium Bundle Paid payment puts the credit back on the lot it came from (and it still reads Premium Bundle)');

  -- R2: a correction keeps the method, and so the source.
  inv := pg_temp.therapy_invoice(1);
  p := pg_temp.pay(inv, 'Wallet — Credit Package Paid', 60);
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 40)), gen_random_uuid());
  r := public.correct_invoice_payment(p, 50, public.sg_today(), pg_temp.method('Wallet — Credit Package Paid'), 'T443 fifty, not sixty', gen_random_uuid());
  rep := (r ->> 'replacement_id')::uuid;
  perform pg_temp.check(pg_temp.pay_sources(rep) = 'credit_package'
      and (select sum(amount) from public.invoice_line_credit_allocations where payment_id = rep) = 50
      and (select sum(amount - reversed_amount) from public.invoice_line_credit_allocations where payment_id = p) = 0,
    'R2 a correction of a Credit Package Paid payment is drawn again from Credit Package credit');
  perform pg_temp.check((public.invoice_payment_credit_sources(inv) -> (select id::text from public.invoice_payments
                           where corrects_payment_id = p and entry_kind = 'correction_reversal')) = '["credit_package"]'::jsonb,
    'L3 the correction''s reversal row reads the source of the payment it reverses');

  -- R3: Foxtrot's payment through Wallet — Paid Credit before 443 drew Premium
  -- Bundle credit: it reads so, and corrected through that method it is drawn
  -- from Premium Bundle credit again (the method alone now pays other credit).
  inv := pg_temp.fx('fox:inv'); p := pg_temp.fx('fox:pay');
  perform pg_temp.check(public.invoice_payment_credit_sources(inv) -> p::text = '["premium_bundle"]'::jsonb,
    'L4 a past Wallet — Paid Credit payment of Premium Bundle credit reads its source: Premium Bundle');
  v := pg_temp.err(format('select public.correct_invoice_payment(%L, 90, public.sg_today(), %L, %L, %L)', p,
         pg_temp.method('Wallet — Paid Credit'), 'T443 ninety', gen_random_uuid()));
  rep := (select id from public.invoice_payments where corrects_payment_id = p and entry_kind = 'correction_replacement');
  perform pg_temp.check(v = 'ok' and pg_temp.pay_sources(rep) = 'premium_bundle'
      and (select sum(amount) from public.invoice_line_credit_allocations where payment_id = rep) = 90,
    'R3 corrected through the same method, a past payment keeps the source its credit came from: ' || v);

  -- R4: a refunded wallet payment cannot change where its credit comes from
  -- (two sessions paid from Premium Bundle Paid credit, one refunded).
  inv := pg_temp.therapy_invoice(2);
  p := pg_temp.pay(inv, 'Wallet — Premium Bundle Paid', 200);
  select id into item from public.invoice_items where invoice_id = inv;
  perform public.refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', p, 'amount', 100)), '[]'::jsonb, 'T443 part refund', gen_random_uuid());
  v := pg_temp.err(format('select public.correct_invoice_payment(%L, 200, public.sg_today(), %L, %L, %L)', p,
         pg_temp.method('Wallet — Credit Package Paid'), 'T443 other source', gen_random_uuid()));
  perform pg_temp.check(v like '%A refunded wallet payment requires source review before changing where its credit comes from%',
    'R4 a part-refunded Premium Bundle payment cannot be moved to Credit Package credit: ' || v);
end $$;

-- ═════ S Protected methods ═════
do $$
declare m uuid := pg_temp.method('Wallet — Premium Bundle Bonus'); old uuid := pg_temp.method('Wallet — Paid Credit');
begin
  perform pg_temp.check(pg_temp.err(format('update public.payment_methods set name = %L where id = %L', 'T443 renamed', m))
                          like '%A system wallet payment method cannot be renamed%'
      and pg_temp.err(format('update public.payment_methods set is_active = false where id = %L', m))
                          like '%cannot be switched off%'
      and pg_temp.err(format('update public.payment_methods set deleted_at = now() where id = %L', m))
                          like '%cannot be deleted%'
      and pg_temp.err(format('delete from public.payment_methods where id = %L', m)) like '%cannot be deleted%'
      and pg_temp.err(format('update public.payment_methods set wallet_source = %L where id = %L', 'credit_package', m))
                          like '%cannot be reconfigured%'
      and pg_temp.err(format('update public.payment_methods set wallet_source = %L where id = %L', 'premium_bundle', old))
                          like '%cannot be reconfigured%'
      and pg_temp.err(format('update public.payment_methods set wallet_category = %L where id = %L', 'paid', m))
                          like '%cannot be reconfigured%',
    'S1 a new method cannot be renamed, switched off, deleted or given another source or category; nor can an old one be given a source');
  perform pg_temp.check(pg_temp.err($q$insert into public.payment_methods(name, is_wallet_credit, wallet_category, wallet_source)
                                        values ('T443 Not System', true, 'paid', 'credit_package')$q$) like '23514 %'
      and pg_temp.err($q$insert into public.payment_methods(name, is_wallet_credit, wallet_category, wallet_source, is_system)
                         values ('T443 Legacy Source', true, 'legacy', 'premium_bundle', true)$q$) like '23514 %'
      and pg_temp.err($q$insert into public.payment_methods(name, is_wallet_credit, wallet_category, wallet_source, is_system)
                         values ('T443 Odd Source', true, 'paid', 'tiktok', true)$q$) like '23514 %',
    'S2 a source only on a system Paid or Bonus wallet method, and only Credit Package or Premium Bundle');
end $$;

-- ═════ K Who may call what ═════
select pg_temp.check(not has_function_privilege('anon', 'public.invoice_wallet_availability(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.invoice_wallet_availability(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.invoice_payment_credit_sources(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.invoice_payment_credit_sources(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.credit_lot_source_group(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.credit_lot_source_group(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.credit_lot_source_group(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.wallet_method_source_filter(text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.allocate_invoice_wallet_credit(uuid,numeric,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.allocate_invoice_wallet_credit(uuid,numeric,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.allocate_invoice_wallet_credit(uuid,numeric,text,text)', 'execute')
    and has_function_privilege('authenticated', 'public.customer_credit_balances(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.customer_credit_balances(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.record_invoice_payment(uuid,jsonb,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', 'execute'),
  'K1 the two new page functions are for signed-in staff, the helpers and the allocator for the server; the changed ones keep their grants');
do $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (u, 't443-nostaff@example.com');
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_temp.check(pg_temp.err(format('select public.invoice_wallet_availability(%L)', pg_temp.fx('inv_t'))) like '42501 %'
      and pg_temp.err(format('select public.invoice_payment_credit_sources(%L)', pg_temp.fx('inv_t'))) like '42501 %',
    'K2 a login that is not staff is refused (42501)');
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
end $$;

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'credit-sources-443: % check(s) failed:\n  %', n, m; end if;
  raise notice 'credit-sources-443: all checks passed';
end $$;
rollback;
