#!/bin/sh
# Two earnings of one invoice at once keep one kind for each line (538; security audit of 17 Nov
# 2026, M12; the user, 25 Nov 2026: "Keep each line's type").
#
# An invoice paid in full by a buyer with no referrer earned nothing and keeps no rates or line
# kinds. The buyer's referrer is then set (as the event website's referral check does before it
# calls earn_invoice_commission, without locking the invoice). Connection A earns the invoice and
# holds its transaction open; meanwhile the product is made third party (committed); then
# connection B earns the same invoice. 538 locks the invoice while a line has no kept kind, so B
# waits for A, then reads the kind A kept (own), and every row is own. Without the lock B would
# read no kept kind yet and write third-party rows, while the line keeps own.
#
# It makes its own disposable copy of a template that has 538 in (no session may be open on the
# template), COMMITS fictional rows there only (names M538R..., phones +61 491 570 6nn, emails
# @example.invalid), and drops the copy at the end. The connection comes from the usual PG*
# variables, the template from the first argument:
#   PGHOST=127.0.0.1 PGPORT=54396 PGUSER=postgres sh scripts/commissions/tests/first-kinds-race-538.sh <template>
set -eu
TPL=${1:?give the template database (with 538 in)}
DB=m538race_$$
psql -X -q -At -d postgres -c "create database $DB template $TPL" >/dev/null
cleanup() { psql -X -q -At -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT
q() { psql -X -q -At -v ON_ERROR_STOP=1 -d $DB -c "$1"; }

if [ "$(q "select to_regclass('public.invoice_line_commission_kinds') is not null")" != t ]; then
  echo "FAIL: 538 is not in on $TPL"; exit 1; fi

# The fixture, committed: an Owner, a store, a S$100 product of ours, the rates pinned (15 / 4.5 /
# 35 / 35), a chain T2 -> T1 and a buyer with no referrer yet; the buyer's invoice, paid in full.
inv=$(q "do \$\$
declare o uuid := gen_random_uuid(); st uuid; m uuid; p uuid; t2 uuid; t1 uuid; b uuid; v uuid;
begin
  insert into auth.users(id, email) values (o, 'm538r-owner@example.invalid');
  insert into public.profiles(id, full_name, email, role) values (o, 'M538R Owner', 'm538r-owner@example.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.app_settings(id) values (true) on conflict do nothing;
  update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
    commission_tier2_own_rate = 35, commission_tier2_third_rate = 35 where id = true;
  insert into public.stores(name, code, country_code) values ('M538R Store', 'M538R', 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (o, st);
  insert into public.payment_methods(name, is_active) values ('M538R Cash', true) returning id into m;
  insert into public.products(name, sku, product_type) values ('M538R Item', 'M538R-I', 'own') returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 10);
  perform public.set_product_prices(st, p, 100, 100, 'available');
  insert into public.customers(full_name, phone) values ('M538R T2', '+61491570611') returning id into t2;
  insert into public.customers(full_name, phone, referred_by) values ('M538R T1', '+61491570612', t2) returning id into t1;
  insert into public.customers(full_name, phone) values ('M538R Buyer', '+61491570613') returning id into b;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (t2, 'active', st, now()), (t1, 'active', st, now());
  v := public.create_invoice(st, b, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', p, 'quantity', 1)),
                             0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', m, 'amount', 100)), gen_random_uuid());
  update public.customers set referred_by = t1 where id = b;
  perform set_config('m538r.inv', v::text, false);
end \$\$;
select id from public.invoices where customer_id = (select id from public.customers where full_name = 'M538R Buyer');")
[ "$(q "select count(*) from public.commissions where invoice_id = '$inv'")/$(q "select count(*) from public.invoice_line_commission_kinds where invoice_id = '$inv'")" = "0/0" ] \
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
# The product is made third party meanwhile (committed).
q "update public.products set product_type = 'third_party' where sku = 'M538R-I'"
# B: earns it too, and says how long it waited.
t0=$(q "select extract(epoch from clock_timestamp())")
q "select public.earn_invoice_commission('$inv')" >/dev/null
t1=$(q "select extract(epoch from clock_timestamp())")
wait $A

kinds=$(q "select string_agg(distinct product_type, ',') from public.commissions where invoice_id = '$inv' and tier = 'tier1'")
kept=$(q "select kind from public.invoice_line_commission_kinds where invoice_id = '$inv'")
rows=$(q "select count(*) from public.commissions where invoice_id = '$inv' and tier = 'tier1'")
waited=$(q "select ($t1 - $t0) >= 2")
echo "tier 1 rows: $rows, their kinds: $kinds; kept: $kept; B waited for A: $waited"
if [ "$kinds" = "own" ] && [ "$kept" = "own" ] && [ "$rows" = "2" ] && [ "$waited" = t ]; then
  echo "PASS: B waited for A and earned at the kind A kept (own), though the product had become third party"
else
  echo "FAIL: the two earnings did not keep one kind for the line"; exit 1
fi
