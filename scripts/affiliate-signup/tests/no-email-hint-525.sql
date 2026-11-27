-- The affiliate sign-up makes no hint of anyone's login email (525).
--
-- An affiliate with a login, and a sign-up typing her phone with a new email, as the
-- sign-up function asks (affiliate_signup_existing, as the service role): the phone is
-- answered as an affiliate's, with no hint of her login email, and the Audit Log row of
-- the try says no hint was shown. Her login email typed is still answered as hers; an
-- unknown phone and email are answered as no one's. The fuller cases (households, shared
-- phones, the mask) are scripts/affiliate-signup/tests/existing-affiliate-466.sql, which
-- expects no hint once 525 is in.
--
--   sh scripts/invoices/local-sql.sh -f scripts/affiliate-signup/tests/no-email-hint-525.sql
-- 525 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L525, @example.invalid, +61491570...).
\set ON_ERROR_STOP on
begin;
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first, as this file pins
-- md5s of functions it changes (only their search path); this run only, rolled back with the rest.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
select position('-- 525 (security audit' in pg_get_functiondef('public.affiliate_signup_existing(text,text,text,uuid)'::regprocedure)) > 0 as m525_in \gset
\if :m525_in
\else
\ir ../../../supabase/525_the_sign_up_makes_no_email_hint.sql
\endif
-- A second run changes nothing.
\ir ../../../supabase/525_the_sign_up_makes_no_email_hint.sql

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l525(k text primary key, v text not null);
create function pg_temp.fx(p_k text) returns text language sql as $f$ select v from l525 where k = p_k $f$;
-- The sign-up function's call, as the service role (it is the service role's alone).
create function pg_temp.ask(p_phone text, p_email text, p_name text) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  execute 'set local role service_role';
  r := public.affiliate_signup_existing(p_phone, p_email, p_name, gen_random_uuid());
  execute 'reset role';
  return r;
end $f$;

do $$
declare u uuid := gen_random_uuid(); c uuid; a uuid;
        sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
        phone constant text := '+61491570525';
begin
  insert into auth.users(id, email, email_confirmed_at) values (u, 'l525-ava-' || sfx || '@example.invalid', now());
  insert into public.customers(full_name, first_name, last_name, phone, email)
    values ('L525 Ava', 'L525', 'Ava', phone, 'l525-ava-' || sfx || '@example.invalid') returning id into c;
  insert into public.customer_affiliates(customer_id, status, activated_at, referral_code)
    values (c, 'active', now(), 'L525' || upper(sfx)) returning id into a;
  insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status, email_verified_at)
    values (u, c, a, 'claimed', now());
  insert into l525 values ('phone', phone), ('login', 'l525-ava-' || sfx || '@example.invalid'), ('cust', c::text), ('sfx', sfx);
end $$;

create temp table asked as
  select 'phone' k, pg_temp.ask(pg_temp.fx('phone'), 'l525-new-' || pg_temp.fx('sfx') || '@example.invalid', 'Pat Sample') r
  union all select 'login', pg_temp.ask('+61491570999', pg_temp.fx('login'), 'Pat Sample')
  union all select 'unknown', pg_temp.ask('+61491570998', 'l525-nobody-' || pg_temp.fx('sfx') || '@example.invalid', 'Pat Sample');

select pg_temp.check((select r->>'matched' = 'phone' and r ? 'email_hint' and r->'email_hint' = 'null'::jsonb
                             and position('•••' in r::text) = 0 and position('@' in r::text) = 0 from asked where k = 'phone'),
  '1 her phone with a new email: answered as an affiliate''s phone, with no hint and no part of any email: '
  || (select r::text from asked where k = 'phone'));
select pg_temp.check((select (l.new_data->>'email_hint_shown') = 'false' and l.new_data->>'answered' = 'phone'
                        from public.audit_logs l
                       where l.action = 'affiliate_signup_sent_to_sign_in' and l.record_id = pg_temp.fx('cust')::uuid
                         and l.new_data->>'answered' = 'phone'
                       order by l.created_at desc limit 1),
  '2 the Audit Log row of the try says no hint was shown');
select pg_temp.check((select r->>'matched' = 'email' and (r->>'login_email')::boolean and r->'email_hint' = 'null'::jsonb from asked where k = 'login'),
  '3 her login email typed: still answered as hers (Sign in), no hint: ' || (select r::text from asked where k = 'login'));
select pg_temp.check((select r->'matched' = 'null'::jsonb and r->'email_hint' = 'null'::jsonb from asked where k = 'unknown'),
  '4 an unknown phone and email: no one''s');
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_signup_existing(text,text,text,uuid)'::regprocedure)) = '6df6e72e2942db0ea39818666a68bf57'
                     and not has_function_privilege('authenticated', 'public.affiliate_signup_existing(text,text,text,uuid)', 'execute')
                     and not has_function_privilege('anon', 'public.affiliate_signup_existing(text,text,text,uuid)', 'execute'),
  '5 the function is 525''s, and still the service role''s alone');
rollback;
