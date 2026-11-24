#!/bin/sh
# Two welcomes at once at 29 give exactly 30 (531; security audit of 17 Nov 2026, M6; the user,
# 20 Nov 2026: "30 welcomes a day").
#
# Two connections each link a login to an affiliate account at the same moment (the trigger
# queues the welcome), with 29 welcomes already queued in the last 24 hours. The welcomes' lock
# in affiliate_whatsapp_enqueue makes the second wait for the first to commit, so exactly one is
# queued and the other kept skipped ('daily_limit'). Without the lock both would count 29.
#
# DISPOSABLE COPY ONLY (a copy with 531 in): this COMMITS fictional rows (logins and emails
# t531race-*@example.invalid, phones +61 491 570 69n, outbox keys T531-race-*), and deletes
# them again at the end. The connection comes from the usual PG* variables.
#   PGDATABASE=m6_copy sh scripts/affiliate-signup/tests/welcome-limit-race-531.sh
set -eu
q() { psql -X -q -At -v ON_ERROR_STOP=1 -c "$1"; }

if [ "$(q "select position('-- 531 (security audit' in pg_get_functiondef('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)'::regprocedure)) > 0")" != t ]; then
  echo "FAIL: 531 is not in on $PGDATABASE"; exit 1; fi

cleanup() {
  psql -X -q -At -c "
    delete from public.affiliate_whatsapp_outbox where idempotency_key like 'T531-race-%'
       or auth_user_id in (select id from auth.users where email like 't531race-%@example.invalid');
    delete from public.affiliate_accounts where auth_user_id in (select id from auth.users where email like 't531race-%@example.invalid');
    delete from public.customer_affiliates where customer_id in (select id from public.customers where last_name = 'T531race');
    delete from public.customers where last_name = 'T531race';
    delete from auth.users where email like 't531race-%@example.invalid';" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

# 29 welcomes in the last 24 hours (every one not skipped or expired), counting any already there.
q "do \$\$ declare v_have int; begin
  select count(*) into v_have from public.affiliate_whatsapp_outbox
   where kind = 'welcome' and status not in ('skipped', 'expired') and created_at > now() - interval '24 hours';
  if v_have > 29 then raise exception 'more than 29 welcomes already in the last 24 hours (%)', v_have; end if;
  insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, phone_e164, wa_country_code, wa_number, message, status, created_at)
  select 'welcome', 'T531-race-fill-' || i, '+61491570699', '61', '491570699', 'T531', 'queued', now() - interval '1 hour'
    from generate_series(1, 29 - v_have) i;
end \$\$;"
# Two affiliates whose logins are not linked yet (records made days before the logins).
for k in 1 2; do
  q "do \$\$ declare u uuid := gen_random_uuid(); c uuid; begin
    insert into auth.users(id, email, email_confirmed_at, created_at) values (u, 't531race-$k@example.invalid', now(), now());
    insert into public.customers(first_name, last_name, full_name, phone, created_at)
      values ('Race$k', 'T531race', 'Race$k T531race', '+6149157069$k', now() - interval '3 days') returning id into c;
    insert into public.customer_affiliates(customer_id, status, activated_at, referral_code)
      values (c, 'active', now(), public.generate_affiliate_referral_code());
  end \$\$;"
done
link() {
  psql -X -q -At -v ON_ERROR_STOP=1 <<EOF
begin;
insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
select u.id, c.id, a.id, 'claimed' from auth.users u, public.customers c join public.customer_affiliates a on a.customer_id = c.id
 where u.email = 't531race-$1@example.invalid' and c.first_name = 'Race$1' and c.last_name = 'T531race';
select pg_sleep($2);
commit;
EOF
}
link 1 2 & p1=$!
sleep 0.5
link 2 0 & p2=$!
wait $p1; wait $p2

res=$(q "select count(*) filter (where status not in ('skipped', 'expired'))
         || ' ' || count(*) filter (where o.auth_user_id is not null and status = 'skipped' and skip_reason = 'daily_limit')
         || ' ' || count(*) filter (where o.auth_user_id is not null and status = 'queued')
           from public.affiliate_whatsapp_outbox o
          where kind = 'welcome' and created_at > now() - interval '24 hours'")
echo "welcomes in 24 hours, daily_limit skipped, new queued: $res"
if [ "$res" = "30 1 1" ]; then
  echo "PASS  two welcomes at once at 29: exactly 30 (one queued, one skipped daily_limit)"
else
  echo "FAIL  expected '30 1 1'"; exit 1
fi
