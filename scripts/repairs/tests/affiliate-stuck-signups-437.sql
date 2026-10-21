-- The one-off repair that lets in the affiliate sign-ups stuck before 437
-- (the Owner, 20 Oct 2026, AFF-SIGNUP-5):
-- scripts/repairs/affiliate-stuck-signups-437.sql.
--
--   * without "apply" it is a dry run: it counts and changes nothing;
--   * a count other than the one expected is refused, changing nothing;
--   * with "apply" it confirms exactly the stuck affiliate sign-ups (not a
--     staff login, not a login from elsewhere, not a deleted or banned one,
--     not one already confirmed), marks their email as not verified, and
--     writes one audit row each, with no email or name in it;
--   * a second run finds none and changes nothing;
--   * a switched-on login then finishes its sign-up at its next sign-in with
--     the details it gave (437), its email shown as not verified.
--
-- Disposable database only; everything is rolled back. Needs 437 (it installs
-- it unless run with -v nomig=1). Every email is @example.com and every phone
-- an ACMA fictional number. Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/repairs/tests/affiliate-stuck-signups-437.sql
\set ON_ERROR_STOP on
begin;
\if :{?nomig}
\else
\ir ../../../supabase/437_affiliate_signup_straight_in.sql
\endif
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.confirmed(key text) returns boolean language sql as
$$ select email_confirmed_at is not null from auth.users where id = pg_temp.fx(key) $$;
create function pg_temp.marked(key text) returns boolean language sql as
$$ select coalesce(raw_app_meta_data ->> 'affiliate_email_unverified', '') = 'true' from auth.users where id = pg_temp.fx(key) $$;
create function pg_temp.switched_rows() returns int language sql as
$$ select count(*)::int from audit_logs where action = 'affiliate_signup_switched_on' $$;

-- Fixtures: three stuck sign-ups, and logins the repair must leave alone.
do $$
declare sfx text := lower(substr(md5(random()::text), 1, 6)); k text; u uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['sA', 'sB', 'sC', 'staff', 'other', 'conf', 'gone', 'banned', 'acct'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (u, 'r437-' || lower(k) || '-' || sfx || '@example.com',
            case when k = 'conf' then now() - interval '5 days' end,
            '{"provider": "email"}'::jsonb,
            case when k = 'other' then '{}'::jsonb
                 else jsonb_build_object('first_name', 'R437 ' || k, 'last_name', 'Teststuck', 'phone', '+61491570737',
                                         'signup_source', 'affiliate_join') end);
  end loop;
  update auth.users set deleted_at = now() where id = pg_temp.fx('gone');
  update auth.users set banned_until = now() + interval '10 years' where id = pg_temp.fx('banned');
  insert into profiles (id, full_name, email, role) values (pg_temp.fx('staff'), 'R437 Staff', 'r437-staff-' || sfx || '@example.com', 'staff');
  insert into customers (full_name, phone) values ('R437 Acct Customer', '+61491572983') returning id into u;
  insert into customer_affiliates (customer_id, status, activated_at, referral_code) values (u, 'active', now(), 'R437ACCT');
  insert into affiliate_accounts (auth_user_id, customer_id, status) values (pg_temp.fx('acct'), u, 'claimed');
end $$;
set local energia.repair_437_expected = '3';

-- ── 1. The dry run changes nothing ──────────────────────────────────────
\ir ../affiliate-stuck-signups-437.sql
select pg_temp.check(not pg_temp.confirmed('sA') and not pg_temp.confirmed('sB') and not pg_temp.confirmed('sC')
    and pg_temp.switched_rows() = 0,
  '1 without "apply" it is a dry run: nothing confirmed, no audit row');

-- ── 2. A count other than the one expected is refused ──────────────────
set local energia.repair_437 = 'apply';
set local energia.repair_437_expected = '14';
savepoint wrong_count;
\set ON_ERROR_STOP off
\echo '(the next ERROR is expected: the count is not the one expected)'
\ir ../affiliate-stuck-signups-437.sql
\set ON_ERROR_STOP on
rollback to savepoint wrong_count;
select pg_temp.check(not pg_temp.confirmed('sA') and pg_temp.switched_rows() = 0,
  '2 a count other than the one expected is refused, and nothing changes');

-- ── 3. Apply ─────────────────────────────────────────────────────────────
set local energia.repair_437_expected = '3';
\ir ../affiliate-stuck-signups-437.sql
select pg_temp.check(pg_temp.confirmed('sA') and pg_temp.confirmed('sB') and pg_temp.confirmed('sC')
    and pg_temp.marked('sA') and pg_temp.marked('sB') and pg_temp.marked('sC'),
  '3 the three stuck sign-ups are confirmed and marked "email not verified"');
select pg_temp.check(not pg_temp.confirmed('staff') and not pg_temp.confirmed('other') and not pg_temp.confirmed('gone')
    and not pg_temp.confirmed('banned') and not pg_temp.confirmed('acct')
    and not pg_temp.marked('conf') and not pg_temp.marked('staff') and not pg_temp.marked('other'),
  '3 a staff login, a login from elsewhere, a deleted, a banned, an onboarded and an already confirmed login are left alone');
select pg_temp.check(pg_temp.switched_rows() = 3
    and (select bool_and(new_data->>'auth_user_id' in (pg_temp.fx('sA')::text, pg_temp.fx('sB')::text, pg_temp.fx('sC')::text)
                         and module = 'affiliate' and new_data::text !~ '@')
           from audit_logs where action = 'affiliate_signup_switched_on'),
  '3 one audit row each, naming the login and no email');
select pg_temp.check((select raw_user_meta_data->>'first_name' from auth.users where id = pg_temp.fx('sA')) = 'R437 sA'
    and (select encrypted_password is not distinct from null from auth.users where id = pg_temp.fx('sA')),
  '3 the details and the password are untouched');

-- ── 4. A second run changes nothing ─────────────────────────────────────
\ir ../affiliate-stuck-signups-437.sql
select pg_temp.check(pg_temp.switched_rows() = 3, '4 a second run finds none and writes nothing');

-- ── 5. The next sign-in finishes the sign-up ───────────────────────────
do $$ declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('sA')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  r := public.complete_affiliate_onboarding(null, null, null, true);
  perform pg_temp.check(r->>'status' = 'active' and not (r->>'email_verified')::boolean
      and exists (select 1 from affiliate_accounts where auth_user_id = pg_temp.fx('sA')),
    '5 at the next sign-in the sign-up finishes with the details it gave; the email shows as not verified: ' || r::text);
end $$;

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'affiliate-stuck-signups-437: % check(s) failed:\n  %', n, m; end if;
  raise notice 'affiliate-stuck-signups-437: all checks passed';
end $$;
rollback;
