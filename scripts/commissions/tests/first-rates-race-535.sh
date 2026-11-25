#!/bin/sh
# Two earnings of one invoice at once keep one set of rates (535; security audit of 17 Nov 2026,
# M12; the user, 24 Nov 2026: "An invoice keeps the commission rates it first earned at").
#
# An invoice paid in full by a buyer with no referrer earned nothing and keeps no rates. The
# buyer's referrer is then set (as the event website's referral check does before it calls
# earn_invoice_commission, trg_event_web_referral_check_decided, without locking the invoice).
# Connection A earns the invoice and holds its transaction open; meanwhile the rates change
# (tier 1 own 15 to 20, committed); then connection B earns the same invoice. 535 locks the
# invoice before the first rates are read, so B waits for A, then reads the rates A kept (15),
# and every row is at 15. Without that lock B would read no kept rates yet and write rows at 20,
# while the invoice keeps 15.
#
# It makes its own disposable copy of a template that has 535 in (no session may be open on the
# template), COMMITS fictional rows there only (names M535R…, phones +61 491 570 6nn, emails
# @example.invalid), and drops the copy at the end. The connection comes from the usual PG*
# variables, the template from the first argument:
#   PGHOST=127.0.0.1 PGPORT=54396 PGUSER=postgres sh scripts/commissions/tests/first-rates-race-535.sh <template>
set -eu
TPL=${1:?give the template database (with 535 in)}
DB=m535race_$$
psql -X -q -At -d postgres -c "create database $DB template $TPL" >/dev/null
cleanup() { psql -X -q -At -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT
q() { psql -X -q -At -v ON_ERROR_STOP=1 -d $DB -c "$1"; }

if [ "$(q "select to_regclass('public.invoice_affiliate_rates') is not null")" != t ]; then
  echo "FAIL: 535 is not in on $TPL"; exit 1; fi

# The fixture, committed: an Owner, a store, a S$100 product of ours, the rates pinned (15 / 4.5 /
# 35 / 35), a chain T2 -> T1 and a buyer with no referrer yet; the buyer's invoice, paid in full.
inv=$(q "do \$\$
declare o uuid := gen_random_uuid(); st uuid; m uuid; p uuid; t2 uuid; t1 uuid; b uuid; v uuid;
begin
  insert into auth.users(id, email) values (o, 'm535r-owner@example.invalid');
  insert into public.profiles(id, full_name, email, role) values (o, 'M535R Owner', 'm535r-owner@example.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.app_settings(id) values (true) on conflict do nothing;
  update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
    commission_tier2_own_rate = 35, commission_tier2_third_rate = 35 where id = true;
  insert into public.stores(name, code, country_code) values ('M535R Store', 'M535R', 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (o, st);
  insert into public.payment_methods(name, is_active) values ('M535R Cash', true) returning id into m;
  insert into public.products(name, sku, product_type) values ('M535R Item', 'M535R-I', 'own') returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 10);
  perform public.set_product_prices(st, p, 100, 100, 'available');
  insert into public.customers(full_name, phone) values ('M535R T2', '+61491570601') returning id into t2;
  insert into public.customers(full_name, phone, referred_by) values ('M535R T1', '+61491570602', t2) returning id into t1;
  insert into public.customers(full_name, phone) values ('M535R Buyer', '+61491570603') returning id into b;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (t2, 'active', st, now()), (t1, 'active', st, now());
  v := public.create_invoice(st, b, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', p, 'quantity', 1)),
                             0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', m, 'amount', 100)), gen_random_uuid());
  update public.customers set referred_by = t1 where id = b;
  perform set_config('m535r.inv', v::text, false);
end \$\$;
select id from public.invoices where customer_id = (select id from public.customers where full_name = 'M535R Buyer');")
[ "$(q "select count(*) from public.commissions where invoice_id = '$inv'")/$(q "select count(*) from public.invoice_affiliate_rates where invoice_id = '$inv'")" = "0/0" ] \
  || { echo "FAIL: the fixture invoice already earned or keeps rates"; exit 1; }

# A: earns it and holds its transaction 4 seconds.
psql -X -q -At -v ON_ERROR_STOP=1 -d $DB >/dev/null <<EOF &
begin;
select public.earn_invoice_commission('$inv');
select pg_sleep(4);
commit;
EOF
A=$!
sleep 1
# The rates change meanwhile (committed).
q "update public.app_settings set commission_tier1_own_rate = 20 where id = true"
# B: earns it too, and says how long it waited.
t0=$(q "select extract(epoch from clock_timestamp())")
q "select public.earn_invoice_commission('$inv')" >/dev/null
t1=$(q "select extract(epoch from clock_timestamp())")
wait $A

rates=$(q "select string_agg(distinct rate::text, ',' order by rate::text) from public.commissions where invoice_id = '$inv' and tier = 'tier1'")
kept=$(q "select tier1_own_rate from public.invoice_affiliate_rates where invoice_id = '$inv'")
rows=$(q "select count(*) from public.commissions where invoice_id = '$inv' and tier = 'tier1'")
waited=$(q "select ($t1 - $t0) >= 2")
echo "tier 1 rows: $rows, their rates: $rates; kept: $kept; B waited for A: $waited"
if [ "$rates" = "15.000" ] && [ "$kept" = "15" ] && [ "$rows" = "2" ] && [ "$waited" = t ]; then
  echo "PASS: B waited for A and earned at the rates A kept (15), though the rates had changed to 20"
else
  echo "FAIL: the two earnings did not keep one set of rates"; exit 1
fi
