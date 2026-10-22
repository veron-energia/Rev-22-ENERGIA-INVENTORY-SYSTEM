-- The affiliate portal shows each affiliate their short seminar link (454).
--
-- The owner's change list, 22 Oct 2026, item 8: the affiliate's referral code as the seminar link
-- (<site>/<code>), shown in the portal with copy and share like the existing link. affiliate_portal_referral_info
-- adds 'seminar_links': one {event_name, first_day, last_day, url} for each event whose website takes
-- registrations now (event_web_open_state), on the Website tab's sync URL's origin (as event_web_settings_get
-- reads site_url) + '/' + the code.
--
--   G  The md5 and the grant: affiliate_portal_referral_info has 454's AFTER and is still signed-in logins' and
--      the service role's (never anon); the three functions it relies on are unchanged.
--   S  Which events: Live and Record only with a day ahead are listed; Off, deleted, tickets off, over (the last
--      day past, or today past its daily end) and no sync URL are not; today with no daily end is; ordered by
--      first day.
--   U  The address: the sync URL's origin and the code, the same origin the Website tab shows (site_url);
--      a sync URL with no path works too.
--   K  The three keys are as before (code, accepting, direct referrals); a link holds its four keys and
--      nothing else (no venue, store, event code or counts).
--   A  The affiliate: suspended (accepting false; the links still listed, the page hides them); a code the
--      site's short link would not take as one (not EN and six of generate_affiliate_referral_code's
--      characters, even one the contract's REFERRAL_CODE_RE takes): no link; an affiliate record deleted: no
--      code, no link; a login that is not a claimed affiliate's (staff, a disabled account): refused as before.
--   D  One link per address: two or three open events on one site (its host in other capitals too) give one
--      link, under the earliest while none has synced, then under the one the site last synced as.
--   M  454 twice changes nothing; its first run changes only affiliate_portal_referral_info; its self-test
--      leaves no row (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.com, *.example.com); phones are ACMA's fictional range (+61 2 5550 ....). It installs 454 twice
-- (run with -v skip_install=1 where 454 is already installed). Every check runs, then the file fails if any
-- did.
\set ON_ERROR_STOP on
begin;
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language sql as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
\if :{?skip_install}
\else
create temp table b454 as select * from pg_temp.fn_md5s();
create temp table r454 as select pg_temp.row_counts() as before;
\ir ../../../supabase/454_affiliate_portal_seminar_link.sql
create temp table m454 as select * from pg_temp.fn_md5s();
alter table r454 add column after1 jsonb;
update r454 set after1 = pg_temp.row_counts();
\ir ../../../supabase/454_affiliate_portal_seminar_link.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '120s';
set local search_path = public;
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
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claims', '', true),
          set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- The portal's answer for an affiliate login (by its key in fx).
create function pg_temp.info(key text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user(key);
  v := public.affiliate_portal_referral_info();
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  return v;
end $$;
-- This run's links in it (the fixtures' sites only: a copy may hold other events), by site tag.
create function pg_temp.links(key text) returns jsonb language sql as
$$ select coalesce(jsonb_agg(x order by o), '[]'::jsonb)
     from jsonb_array_elements(pg_temp.info(key)->'seminar_links') with ordinality t(x, o)
    where x->>'url' like 'https://%-' || lower(pg_temp.tx('sfx')) || '.example.com/%' $$;
create function pg_temp.site(tag text) returns text language sql as
$$ select 'https://' || tag || '-' || lower(pg_temp.tx('sfx')) || '.example.com' $$;
create function pg_temp.event_of(tag text) returns text language sql as
$$ select 'HT454 ' || tag || ' seminar ' || pg_temp.tx('sfx') $$;
-- An event with a website: its days, mode, tickets on sale, daily end, sync URL (null: none) and site (default: its own).
create function pg_temp.ev(tag text, mode text, days date[], on_sale boolean default true,
                           daily_end time default '19:00', sync text default '/api/app/sync', site_tag text default null) returns uuid
language plpgsql as $$
declare e uuid;
begin
  insert into events(name, daily_start, daily_end, is_active)
  values (pg_temp.event_of(tag), case when daily_end is null or daily_end <= '09:00' then null else time '09:00' end, daily_end, on_sale)
  returning id into e;
  insert into event_days(event_id, day) select e, x from unnest(days) x;
  insert into event_stores(event_id, store_id) values (e, pg_temp.fx('store'));
  insert into event_web_settings(event_id, code, mode, venue, store_id, acting_profile_id, sync_url)
  values (e, 'HT454-' || upper(tag) || '-' || pg_temp.tx('sfx'), mode, 'HT454 Hall ' || pg_temp.tx('sfx'), pg_temp.fx('store'),
          pg_temp.fx('owner'), case when sync is null then null else pg_temp.site(coalesce(site_tag, tag)) || sync end);
  insert into fx values ('ev:' || tag, e);
  return e;
end $$;
-- An affiliate with a claimed login (status: claimed or disabled).
create function pg_temp.aff(key text, code text, phone_n int, acct_status text default 'claimed') returns void
language plpgsql as $$
declare u uuid; c uuid; a uuid;
begin
  u := gen_random_uuid();
  insert into auth.users(id, email) values (u, 'ht454-' || key || '-' || lower(pg_temp.tx('sfx')) || '@example.com');
  insert into customers(full_name, phone)
  values ('Test ' || initcap(key) || ' ' || pg_temp.tx('sfx'),
          '+6125550' || lpad(((pg_temp.tx('phbase')::int + phone_n) % 10000)::text, 4, '0'))
  returning id into c;
  insert into customer_affiliates(customer_id, status, referral_code) values (c, 'active', code) returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (u, c, a, acct_status);
  insert into fx values (key, u), (key || ':cust', c), (key || ':aff', a);
end $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); u uuid; st uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 9000))::int::text), ('code', public.generate_affiliate_referral_code());
  u := gen_random_uuid();
  insert into auth.users(id, email) values (u, 'ht454-owner-' || lower(sfx) || '@example.com');
  insert into profiles(id, full_name, email, role, is_active)
  values (u, 'HT454 Owner ' || sfx, 'ht454-owner-' || lower(sfx) || '@example.com', 'owner', true);
  insert into fx values ('owner', u);
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  insert into stores(name, code, country_code) values ('HT454 Store ' || sfx, 'HT454S' || sfx, 'SG') returning id into st;
  insert into fx values ('store', st);
end $$;
select set_config('request.jwt.claim.role', 'service_role', true);
-- Every phone this run uses is one no customer has.
select pg_temp.check(not exists (select 1 from customers c, generate_series(0, 9) g
                                  where public.normalize_customer_phone(c.phone)
                                        = '+6125550' || lpad(((pg_temp.tx('phbase')::int + g) % 10000)::text, 4, '0')),
  'F0 this run''s fictional phones are no customer''s');
select pg_temp.aff('ria', pg_temp.tx('code'), 0);
-- Her direct referral, so direct_referrals reads 1.
insert into customers(full_name, phone, referred_by)
values ('Test Friend ' || pg_temp.tx('sfx'), '+6125550' || lpad(((pg_temp.tx('phbase')::int + 1) % 10000)::text, 4, '0'), pg_temp.fx('ria:cust'));
select pg_temp.ev('live', 'live', array[pg_temp.d(30), pg_temp.d(31)]);
select pg_temp.ev('rec', 'record_only', array[pg_temp.d(10)]);
select pg_temp.ev('off', 'off', array[pg_temp.d(30)]);
select pg_temp.ev('gone', 'live', array[pg_temp.d(30)]);
-- Deleted (the Event page asks for the website Off first; set back to Live after, by hand).
update event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev:gone');
update events set deleted_at = now() where id = pg_temp.fx('ev:gone');
update event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev:gone');
select pg_temp.ev('closed', 'live', array[pg_temp.d(30)], false);
select pg_temp.ev('over', 'live', array[pg_temp.d(-3), pg_temp.d(-2)]);
-- Today, past its daily end (one second after midnight, Singapore), and today with no daily end.
select pg_temp.ev('ended', 'live', array[pg_temp.d(0)], true, '00:00:01');
select pg_temp.ev('allday', 'record_only', array[pg_temp.d(0)], true, null);
select pg_temp.ev('nosync', 'live', array[pg_temp.d(30)], true, '19:00', null);
select pg_temp.ev('bare', 'live', array[pg_temp.d(20)], true, '19:00', '');
-- Two more open events on the Live one's site (the next seminar set up on it; its host in capitals): not listed
-- while none has synced (D).
select pg_temp.ev('next', 'record_only', array[pg_temp.d(40)], true, '19:00', '/api/app/sync', 'live');
select pg_temp.ev('caps', 'live', array[pg_temp.d(35)], true, '19:00', '/api/app/sync', 'LIVE');

-- ═════ G The md5 and the grant ═════
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_portal_referral_info()'::regprocedure)) = '42453f972e0349eb1353e231a659fa55',
  'G1 affiliate_portal_referral_info is 454''s AFTER');
select pg_temp.check(has_function_privilege('authenticated', 'public.affiliate_portal_referral_info()', 'execute')
    and has_function_privilege('service_role', 'public.affiliate_portal_referral_info()', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_portal_referral_info()', 'execute'),
  'G2 still signed-in logins'' and the service role''s, never anon''s');
select pg_temp.check(md5(pg_get_functiondef('public.current_affiliate_customer_id()'::regprocedure)) = '51695acf5f26ce3918d6003d0c980b0f'
    and md5(pg_get_functiondef('public.event_web_open_state(uuid)'::regprocedure)) = 'ef87a22efbb62f69759838db2dfc0d0c'
    and md5(pg_get_functiondef('public.generate_affiliate_referral_code()'::regprocedure)) = '29ae3d463f13788ccf88a952eb3e70b8',
  'G3 current_affiliate_customer_id, event_web_open_state and generate_affiliate_referral_code are unchanged');

-- ═════ S Which events ═════
select pg_temp.check((select array_agg(x->>'event_name' order by o) from jsonb_array_elements(pg_temp.links('ria')) with ordinality t(x, o))
                     = array[pg_temp.event_of('allday'), pg_temp.event_of('rec'), pg_temp.event_of('bare'), pg_temp.event_of('live')],
  'S1 listed: today with no daily end, Record only, Live (a bare sync URL too), by first day: '
  || coalesce((select string_agg(x->>'event_name', ', ') from jsonb_array_elements(pg_temp.links('ria')) x), 'none'));
select pg_temp.check(not exists (select 1 from jsonb_array_elements(pg_temp.info('ria')->'seminar_links') x
                                  where x->>'event_name' in (pg_temp.event_of('off'), pg_temp.event_of('gone'), pg_temp.event_of('closed'),
                                                             pg_temp.event_of('over'), pg_temp.event_of('ended'), pg_temp.event_of('nosync'))),
  'S2 not listed: Off, deleted, tickets off, over, today past its daily end, no sync URL');
select pg_temp.check((public.event_web_open_state(pg_temp.fx('ev:ended'))->>'closed_reason') = 'ended'
    and (public.event_web_open_state(pg_temp.fx('ev:closed'))->>'closed_reason') = 'off_sale'
    and (public.event_web_open_state(pg_temp.fx('ev:off'))->>'closed_reason') = 'website_off'
    and (public.event_web_open_state(pg_temp.fx('ev:allday'))->>'closed_reason') is null,
  'S3 as the website judges them (event_web_open_state): ended, off_sale, website_off, open');
-- The website switched on later: listed from then; switched off: gone.
update event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev:off');
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.links('ria')) x where x->>'event_name' = pg_temp.event_of('off')),
  'S4 its website switched to Live: listed');
update event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev:off');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(pg_temp.links('ria')) x where x->>'event_name' = pg_temp.event_of('off')),
  'S5 switched Off again: gone');

-- ═════ U The address ═════
select pg_temp.check((select x from jsonb_array_elements(pg_temp.links('ria')) x where x->>'event_name' = pg_temp.event_of('live'))
                     = jsonb_build_object('event_name', pg_temp.event_of('live'), 'first_day', pg_temp.d(30), 'last_day', pg_temp.d(31),
                                          'url', pg_temp.site('live') || '/' || pg_temp.tx('code')),
  'U1 a link: the event''s name, its first and last day, and <the sync URL''s origin>/<code>');
select pg_temp.check((select x->>'url' from jsonb_array_elements(pg_temp.links('ria')) x where x->>'event_name' = pg_temp.event_of('bare'))
                     = pg_temp.site('bare') || '/' || pg_temp.tx('code'),
  'U2 a sync URL with no path: <it>/<code>');
select pg_temp.as_user('owner');
select pg_temp.check((public.event_web_settings_get(pg_temp.fx('ev:live'))->'settings'->>'site_url') || '/' || pg_temp.tx('code')
                     = (select x->>'url' from jsonb_array_elements(pg_temp.links('ria')) x where x->>'event_name' = pg_temp.event_of('live')),
  'U3 the same origin the Website tab shows as site_url');
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'service_role', true);

-- ═════ K The other keys, and nothing else ═════
select pg_temp.check(pg_temp.info('ria') - 'seminar_links'
                     = jsonb_build_object('referral_code', pg_temp.tx('code'), 'accepting', true, 'direct_referrals', 1),
  'K1 referral_code, accepting and direct_referrals as before: ' || (pg_temp.info('ria') - 'seminar_links')::text);
select pg_temp.check(not exists (select 1 from jsonb_array_elements(pg_temp.info('ria')->'seminar_links') x
                                  where (select array_agg(k order by k) from jsonb_object_keys(x) k) <> array['event_name', 'first_day', 'last_day', 'url'])
    and position('HT454 Hall' in pg_temp.info('ria')::text) = 0
    and position('HT454 Store' in pg_temp.info('ria')::text) = 0
    and position('HT454-LIVE-' in pg_temp.info('ria')::text) = 0
    and position('/api/app/sync' in pg_temp.info('ria')::text) = 0,
  'K2 a link holds its four keys only: no venue, store, event code or sync path');

-- ═════ A The affiliate ═════
update customer_affiliates set manually_suspended = true where id = pg_temp.fx('ria:aff');
select pg_temp.check((pg_temp.info('ria')->>'accepting')::boolean = false and jsonb_array_length(pg_temp.links('ria')) = 4,
  'A1 suspended: accepting false, the links still listed (the page shows none while not accepting)');
update customer_affiliates set manually_suspended = false where id = pg_temp.fx('ria:aff');
select pg_temp.aff('odd', 'odd-' || lower(pg_temp.tx('sfx')), 2);
select pg_temp.check(pg_temp.info('odd')->'seminar_links' = '[]'::jsonb
    and pg_temp.info('odd')->>'referral_code' = 'odd-' || lower(pg_temp.tx('sfx')),
  'A2 a code the site would not take as one (not even ^[A-Z0-9]{4,16}$): no link, the code as before');
select pg_temp.aff('t454', 'T454' || pg_temp.tx('sfx'), 5);
select pg_temp.check(pg_temp.info('t454')->'seminar_links' = '[]'::jsonb
    and pg_temp.info('t454')->>'referral_code' = 'T454' || pg_temp.tx('sfx')
    and pg_temp.tx('code') ~ '^EN[0-9A-HJKMNP-TV-Z]{6}$',
  'A2b a code the contract takes but the short link does not (not EN and six of the app''s characters): no link; '
  || 'generate_affiliate_referral_code''s are of that shape (' || pg_temp.tx('code') || ')');
select pg_temp.aff('gone', 'G454' || pg_temp.tx('sfx'), 3);
update customer_affiliates set deleted_at = now() where id = pg_temp.fx('gone:aff');
select pg_temp.check(pg_temp.info('gone') = jsonb_build_object('referral_code', null, 'accepting', null, 'direct_referrals', 0, 'seminar_links', '[]'::jsonb),
  'A3 an affiliate record deleted: no code, no link: ' || pg_temp.info('gone')::text);
select pg_temp.aff('off', 'F454' || pg_temp.tx('sfx'), 4, 'disabled');
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.err('select public.affiliate_portal_referral_info()') = 'Not an affiliate account',
  'A4 a staff login: refused as before');
select pg_temp.as_user('off');
select pg_temp.check(pg_temp.err('select public.affiliate_portal_referral_info()') = 'Not an affiliate account',
  'A5 a disabled affiliate login: refused as before');
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'service_role', true);

-- ═════ D One link per address ═════
create function pg_temp.on_site(tag text) returns jsonb language sql as
$$ select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(pg_temp.links('ria')) x
    where lower(x->>'url') = lower(pg_temp.site(tag) || '/' || pg_temp.tx('code')) $$;
select pg_temp.check(jsonb_array_length(pg_temp.on_site('live')) = 1
    and pg_temp.on_site('live')->0->>'event_name' = pg_temp.event_of('live'),
  'D1 three open events on one site (its host in capitals too), none synced: one link, under the earliest: '
  || pg_temp.on_site('live')::text);
update event_web_settings set last_sync_at = now() - interval '5 minutes' where event_id = pg_temp.fx('ev:caps');
update event_web_settings set last_sync_at = now() where event_id = pg_temp.fx('ev:next');
select pg_temp.check(pg_temp.on_site('live') = jsonb_build_array(jsonb_build_object(
                       'event_name', pg_temp.event_of('next'), 'first_day', pg_temp.d(40), 'last_day', pg_temp.d(40),
                       'url', pg_temp.site('live') || '/' || pg_temp.tx('code')))
    and (select array_agg(x->>'event_name' order by o) from jsonb_array_elements(pg_temp.links('ria')) with ordinality t(x, o))
        = array[pg_temp.event_of('allday'), pg_temp.event_of('rec'), pg_temp.event_of('bare'), pg_temp.event_of('next')],
  'D2 the site last synced as the next one: the one link is under it (still by first day): ' || pg_temp.on_site('live')::text);
update event_web_settings set last_sync_at = null, last_test_sync_at = now() where event_id = pg_temp.fx('ev:next');
select pg_temp.check(pg_temp.on_site('live')->0->>'event_name' = pg_temp.event_of('caps') and jsonb_array_length(pg_temp.on_site('live')) = 1,
  'D3 a test sync does not count: under the one the site last synced as with its live key');

-- ═════ M 454 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m454 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m454),
  'M1 running 454 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m454 m left join b454 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5) = array['affiliate_portal_referral_info()']
    and (select count(*) from m454) = (select count(*) from b454),
  'M2 its first run changed affiliate_portal_referral_info alone (no function added or dropped)');
select pg_temp.check((select before = after1 from r454),
  'M3 454''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 454 checks passed.';
end $$;
rollback;
