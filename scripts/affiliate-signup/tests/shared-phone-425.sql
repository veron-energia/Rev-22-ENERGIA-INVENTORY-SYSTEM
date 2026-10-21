-- 425: a referral sign-up on a customer's phone under another name is
-- checked by staff before it counts (AFFILIATES-12; the Owner, Q19 = A, 9 Oct
-- 2026), and a link takes at most 20 new customers an hour.
--
--   W  The same person: a name with the same words as the customer who has
--      the phone (432's rule) is "already registered" and makes nothing; the
--      referrer's own name in another order is "You cannot refer yourself".
--   F  Another name on a phone a customer has (a family member, or the same
--      person written differently): the customer is made, as before, the
--      person sees the same answer as any new sign-up, the event is
--      'phone_shared', and a pending check lists who had the phone. The
--      referrer's own phone counts too. A phone no one has: made, no check.
--   K  The promotion: a friend with a pending check who visited in the window
--      is listed, not counted; the report marks them needs_check and counts
--      waiting_check; the portal's count leaves them out.
--   D  The check: Owners and Managers only (staff, an affiliate and a pending
--      invitee are refused; the pending invitee is refused the promotion
--      report too); a note and a known answer are required.
--      "Different person": they count from then on. "Same person": neither
--      counted nor listed. A second answer changes nothing. Each answer is in
--      the Audit Log.
--   L  The list for the Affiliates page: pending checks only, oldest first,
--      with the referrer and who had the phone (and their paid invoices).
--   C  The per-link limit: 20 new customers through one link in the last
--      hour stop the 21st ('link_limit', nothing made); older sign-ups and
--      other links do not count. Spaces typed around the code count for the
--      same link, and each event keeps the code without them.
--   X  A merge (merge_customer_records) leaves each check with the record it
--      was made for: the kept customer still counts for their own referrer
--      after a "same person" merge, two records that both have a check merge
--      without error, and a pending check on the merged record does not make
--      the kept customer wait.
--   M  425 installs twice; the second run changes nothing.
--
-- Disposable database only; everything is rolled back. Run with the
-- migration's path (and, on a database without 424, a prelude that installs
-- it):
--   psql -X -v ON_ERROR_STOP=1 -v mig=supabase/425_affiliates_directory_portal_and_cleanup.sql \
--        [-v prelude=supabase/424_exchanges_and_promotions.sql] -f scripts/affiliate-signup/tests/shared-phone-425.sql
-- Every name, phone and email is invented (T425, ACMA fictional +614915xxxxx
-- numbers, @example.com).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
\if :{?mig}
\else
\set mig ../../../supabase/425_affiliates_directory_portal_and_cleanup.sql
\endif
\ir :mig
create temp table fp1 as select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) fp
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\ir :mig

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table rx(k text primary key, v jsonb);
create function pg_temp.rx(key text) returns jsonb language sql as $$ select v from rx where k = key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', case when key is null then '' else 'authenticated' end, true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
-- A sign-up through the link, as a signed-out visitor; its answer is kept
-- under key, and the customer it made (if any) under key too.
create function pg_temp.signup(key text, p_code text, p_first text, p_last text, p_phone text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  r := public.affiliate_referral_signup(p_code, p_first, p_last, p_phone, null, null);
  insert into rx values (key, r) on conflict (k) do update set v = excluded.v;
  insert into fx select key, c.id from public.customers c
   where c.full_name = btrim(p_first || ' ' || p_last) and public.normalize_customer_phone(c.phone) = public.normalize_customer_phone(p_phone)
     and c.referral_source = 'affiliate_link' and c.deleted_at is null
  on conflict (k) do update set v = excluded.v;
  perform set_config('request.jwt.claim.role', '', true);
  return r;
end$$;
create function pg_temp.check_of(key text) returns public.referral_signup_checks language sql as
$$ select * from public.referral_signup_checks where customer_id = pg_temp.fx(key) $$;
-- A first visit through the centre's QR link, on a day.
create function pg_temp.visit(key text, on_day date) returns void language sql as
$$ insert into public.health_surveys(survey_no, store_id, survey_link_id, customer_id, full_name, phone, source, submitted_at)
   select 'HS-T425-' || key, pg_temp.fx('st'), pg_temp.fx('link'), c.id, c.full_name, c.phone, 'public_form',
          (on_day + time '11:00') at time zone 'Asia/Singapore'
     from public.customers c where c.id = pg_temp.fx(key) $$;
create function pg_temp.friend(key text) returns record language sql as
$$ select f.counted, f.first_visit_on from public.referral_campaign_friends(pg_temp.fx('camp')) f where f.friend_customer_id = pg_temp.fx(key) $$;

select pg_temp.check((select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
                        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select fp from fp1)
    and to_regclass('public.referral_signup_checks') is not null,
  'M1 425 installs, and a second run changes nothing');
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+6149157%'),
  'P0 no customer uses the test phones +61 491 57x xxx (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare k text;
begin
  foreach k in array array['own', 'mgr', 'stf', 'pend', 'affl'] loop
    insert into fx values (k, gen_random_uuid());
    insert into auth.users(id, email) values (pg_temp.fx(k), 't425s-' || k || '@example.com');
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status) values
    (pg_temp.fx('own'), 'T425 Owner', 't425s-own@example.com', 'owner', true, 'accepted'),
    (pg_temp.fx('mgr'), 'T425 Manager', 't425s-mgr@example.com', 'manager', true, 'accepted'),
    (pg_temp.fx('stf'), 'T425 Staff', 't425s-stf@example.com', 'staff', true, 'accepted'),
    (pg_temp.fx('pend'), 'T425 Pending', 't425s-pend@example.com', 'manager', true, 'pending');
  insert into fx values ('st', gen_random_uuid()), ('link', gen_random_uuid()), ('camp', gen_random_uuid());
  insert into public.stores(id, name, code, country_code) values (pg_temp.fx('st'), 'T425 Store', 'T425S', 'SG');
  insert into public.survey_links(id, token, store_id) values (pg_temp.fx('link'), 't425-centre', pg_temp.fx('st'));
  -- The referrer (an affiliate with a portal login) and two links.
  insert into fx values ('ref', gen_random_uuid()), ('ref2', gen_random_uuid()), ('ann', gen_random_uuid());
  insert into public.customers(id, full_name, phone) values
    (pg_temp.fx('ref'), 'T425 Rita Lim', '+61491570006'),
    (pg_temp.fx('ref2'), 'T425 Ravi Nair', '+61491570156'),
    -- A past customer: Ann Lee Koh, a paid invoice in September.
    (pg_temp.fx('ann'), 'T425 Ann Lee Koh', '+61491570157');
  insert into public.customer_affiliates(customer_id, status, activated_at, referral_code) values
    (pg_temp.fx('ref'), 'active', now() - interval '30 days', 'T425RITA'),
    (pg_temp.fx('ref2'), 'active', now() - interval '30 days', 'T425RAVI');
  insert into public.affiliate_accounts(auth_user_id, customer_id, status) values (pg_temp.fx('affl'), pg_temp.fx('ref'), 'claimed');
  set local session_replication_role = replica;
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, total_amount, business_date)
  values ('T425-ANN-1', pg_temp.fx('st'), pg_temp.fx('ann'), pg_temp.fx('own'), 'paid', 300, public.sg_today() - 40);
  set local session_replication_role = origin;
  -- A promotion that runs from 5 days ago to 5 days ahead.
  insert into public.referral_campaigns(id, code, title, reward_reason, starts_on, ends_on, tiers)
  values (pg_temp.fx('camp'), 'T425-PROMO', 'T425 promotion', 'T425 reward', public.sg_today() - 5, public.sg_today() + 5, array[1, 3]);
end $$;

-- ═════ W The same person ═════
select pg_temp.signup('w1', 'T425RITA', 'Koh Ann', 'Lee T425', '+61491570157');
select pg_temp.check(pg_temp.rx('w1')->>'outcome' = 'already_registered' and pg_temp.fx('w1') is null
    and (select count(*) from public.customers where public.normalize_customer_phone(phone) = '+61491570157') = 1
    and (select outcome from public.referral_signup_events where normalized_phone = '+61491570157' order by created_at desc limit 1) = 'duplicate',
  'W1 "Koh Ann Lee T425" on Ann Lee Koh''s phone: the same words, so already registered, nothing made');
select pg_temp.signup('w2', 'T425RITA', 'Lim', 'T425 Rita', '+61491570006');
select pg_temp.check(pg_temp.rx('w2')->>'message' = 'You cannot refer yourself.' and pg_temp.fx('w2') is null,
  'W2 the referrer''s own name in another order on their own phone: "You cannot refer yourself"');

-- ═════ F Another name on a phone a customer has ═════
select pg_temp.signup('mary', 'T425RITA', 'Mary', 'Tan T425', '+61491570157');
select pg_temp.check(pg_temp.rx('mary')->>'ok' = 'true' and pg_temp.rx('mary')->>'outcome' = 'registered' and pg_temp.rx('mary')->>'message' = 'Registration successful.'
    and pg_temp.fx('mary') is not null,
  'F1 "Mary Tan" on Ann''s phone: the customer is made and the person is told "Registration successful", as any sign-up');
select pg_temp.check((pg_temp.check_of('mary')).status = 'pending'
    and (pg_temp.check_of('mary')).phone_shared_with = array[pg_temp.fx('ann')]
    and (pg_temp.check_of('mary')).referrer_customer_id = pg_temp.fx('ref')
    and (pg_temp.check_of('mary')).referral_code = 'T425RITA'
    and (select outcome from public.referral_signup_events where new_customer_id = pg_temp.fx('mary')) = 'phone_shared'
    and (select (select referred_by from public.customers where id = pg_temp.fx('mary')) = pg_temp.fx('ref')),
  'F2 a pending check lists Ann as having the phone; the event is phone_shared; Mary is under the referrer');
select pg_temp.signup('sis', 'T425RITA', 'Sara', 'Lim T425', '+61491570006');
select pg_temp.check((pg_temp.check_of('sis')).status = 'pending' and (pg_temp.check_of('sis')).phone_shared_with = array[pg_temp.fx('ref')],
  'F3 another name on the referrer''s own phone is checked too');
select pg_temp.signup('new', 'T425RITA', 'Nina', 'Wong T425', '+61491570737');
select pg_temp.check(pg_temp.fx('new') is not null and (pg_temp.check_of('new')).id is null
    and (select outcome from public.referral_signup_events where new_customer_id = pg_temp.fx('new')) = 'created',
  'F4 a phone no one has: made, no check, the event is created');
select pg_temp.signup('gail', 'T425RAVI', 'Gail', 'Teo T425', '+61491571266');
select pg_temp.signup('gail2', 'T425RAVI', 'Gus', 'Teo T425', '+61491571266');
select pg_temp.check((pg_temp.check_of('gail2')).status = 'pending' and (pg_temp.check_of('gail')).id is null,
  'F5 the second name on a phone that came in through a link is checked; the first is not');

-- ═════ K The promotion ═════
select pg_temp.visit('mary', public.sg_today() - 1);
select pg_temp.visit('new', public.sg_today() - 1);
select pg_temp.visit('sis', public.sg_today() - 2);
select pg_temp.check((select counted from pg_temp.friend('mary') as (counted boolean, first_visit_on date)) = false
    and (select first_visit_on from pg_temp.friend('mary') as (counted boolean, first_visit_on date)) = public.sg_today() - 1
    and (select counted from pg_temp.friend('new') as (counted boolean, first_visit_on date)) = true,
  'K1 Mary visited in the window but waits for a check: listed, not counted; Nina, on a phone no one had, counts');
select pg_temp.as_user('own');
insert into rx select 'report', public.referral_campaign_report('T425-PROMO');
select pg_temp.check((select (r->>'counted')::int = 1 and (r->>'waiting_check')::int = 2
                             and (select bool_and((f->>'needs_check')::boolean = (f->>'customer_id' in (pg_temp.fx('mary')::text, pg_temp.fx('sis')::text)))
                                    from jsonb_array_elements(r->'friends') f)
                        from jsonb_array_elements(pg_temp.rx('report')->'referrers') r where r->>'referrer_customer_id' = pg_temp.fx('ref')::text),
  'K2 the report: Rita has 1 friend counted and 2 waiting for a check, and only Mary and Sara are marked needs_check');
select pg_temp.as_user('affl');
select pg_temp.check((public.affiliate_portal_campaign_progress()->>'counted')::int = 1,
  'K3 the referrer''s portal counts 1 friend, not the 2 waiting');

-- ═════ D The check ═════
select pg_temp.as_user('stf');
select pg_temp.check(pg_temp.err(format('select public.decide_referral_signup_check(%L, ''different_person'', ''T425 asked them'')', (pg_temp.check_of('mary')).id)) like '42501 %'
    and pg_temp.err('select public.referral_signup_checks_pending()') like '42501 %',
  'D1 staff are refused the list and the check');
select pg_temp.as_user('affl');
select pg_temp.check(pg_temp.err(format('select public.decide_referral_signup_check(%L, ''different_person'', ''T425'')', (pg_temp.check_of('mary')).id)) like '42501 %',
  'D2 an affiliate login is refused');
select pg_temp.as_user('pend');
select pg_temp.check(pg_temp.err(format('select public.decide_referral_signup_check(%L, ''different_person'', ''T425'')', (pg_temp.check_of('mary')).id)) like '42501 %',
  'D3 a Manager whose invitation is pending is refused');
-- Before 430 the staff check refuses first; 430 makes is_owner_or_manager()
-- ask the full active test, so its own refusal comes first. 430 is live when
-- current_user_store_ids() exists.
select pg_temp.check(pg_temp.err('select public.referral_campaign_report(''T425-PROMO'')')
                     like case when to_regprocedure('public.current_user_store_ids()') is null
                               then '42501 Only active Energia staff%'
                               else '42501 Only an Owner or Manager%' end,
  'D3b a Manager whose invitation is pending is refused the promotion report');
select pg_temp.as_user('mgr');
select pg_temp.check(pg_temp.err(format('select public.decide_referral_signup_check(%L, ''different_person'', ''  '')', (pg_temp.check_of('mary')).id)) like '%Write how you checked%'
    and pg_temp.err(format('select public.decide_referral_signup_check(%L, ''maybe'', ''T425'')', (pg_temp.check_of('mary')).id)) like '%different person or same person%'
    and (pg_temp.check_of('mary')).status = 'pending',
  'D4 a note and a known answer are required');
insert into rx select 'dmary', public.decide_referral_signup_check((pg_temp.check_of('mary')).id, 'different_person', 'T425 called Ann: Mary is her daughter');
select pg_temp.check(pg_temp.rx('dmary')->>'ok' = 'true' and (pg_temp.check_of('mary')).status = 'different_person'
    and (pg_temp.check_of('mary')).decided_by = pg_temp.fx('mgr') and (pg_temp.check_of('mary')).decision_note = 'T425 called Ann: Mary is her daughter'
    and (select counted from pg_temp.friend('mary') as (counted boolean, first_visit_on date)) = true,
  'D5 a Manager checks Mary as a different person: she counts from then on');
insert into rx select 'dmary2', public.decide_referral_signup_check((pg_temp.check_of('mary')).id, 'same_person', 'T425 second click');
select pg_temp.check(pg_temp.rx('dmary2')->>'ok' = 'false' and (pg_temp.rx('dmary2')->>'already')::boolean
    and (pg_temp.check_of('mary')).status = 'different_person',
  'D6 a second answer changes nothing ("already checked")');
select pg_temp.as_user('own');
insert into rx select 'dsis', public.decide_referral_signup_check((pg_temp.check_of('sis')).id, 'same_person', 'T425 it is Rita herself');
select pg_temp.check((pg_temp.check_of('sis')).status = 'same_person'
    and not exists (select 1 from public.referral_campaign_friends(pg_temp.fx('camp')) f where f.friend_customer_id = pg_temp.fx('sis')),
  'D7 an Owner checks Sara as the same person: neither counted nor listed');
select pg_temp.check((select count(*) from public.audit_logs l where l.action = 'referral_signup_checked'
                        and l.record_id in ((pg_temp.check_of('mary')).id, (pg_temp.check_of('sis')).id)) = 2
    and exists (select 1 from public.audit_logs l where l.action = 'referral_signup_checked' and l.record_id = (pg_temp.check_of('mary')).id
                  and l.changed_by = pg_temp.fx('mgr') and l.new_data->>'status' = 'different_person' and l.old_data->>'status' = 'pending'),
  'D8 each answer is in the Audit Log with who gave it');

-- ═════ L The list ═════
insert into rx select 'list', public.referral_signup_checks_pending();
select pg_temp.check(jsonb_array_length(pg_temp.rx('list')) = 1
    and pg_temp.rx('list')->0->>'customer_id' = pg_temp.fx('gail2')::text
    and pg_temp.rx('list')->0->>'referrer_name' = 'T425 Ravi Nair'
    and pg_temp.rx('list')->0->'shares_with'->0->>'name' = 'Gail Teo T425'
    and (pg_temp.rx('list')->0->'shares_with'->0->>'paid_invoices')::int = 0,
  'L1 the list holds the one check still pending (Gus), with the referrer and who had the phone');
select pg_temp.as_user('mgr');
select pg_temp.check(jsonb_array_length(public.referral_signup_checks_pending()) = 1, 'L2 a Manager reads the list too');
select pg_temp.as_user(null);

-- ═════ C The per-link limit ═════
insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome, created_at)
select 'T425RAVI', pg_temp.fx('ref2'), null, 'created', now() - interval '2 hours'
  from generate_series(3000, 3029) i;
select pg_temp.signup('c0', 'T425RAVI', 'Cara', 'Ong T425', '+61491571491');
select pg_temp.check(pg_temp.fx('c0') is not null, 'C1 30 sign-ups two hours ago do not count against the link');
insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome, created_at)
select 'T425RAVI', pg_temp.fx('ref2'), null, case when i % 2 = 0 then 'created' else 'phone_shared' end, now() - interval '30 minutes'
  from generate_series(4000, 4016) i;
-- Gail, Gus and Cara came through this link this hour too: 20 in all.
select pg_temp.signup('c1', 'T425RAVI', 'Cody', 'Ng T425', '+61491571804');
select pg_temp.check(pg_temp.rx('c1')->>'ok' = 'false'
    and pg_temp.rx('c1')->>'message' like 'This referral link has had many registrations in the last hour.%'
    and pg_temp.fx('c1') is null
    and (select outcome from public.referral_signup_events where normalized_phone = '+61491571804' order by created_at desc limit 1) = 'link_limit',
  'C2 the 21st new customer through one link in an hour is refused and nothing is made');
select pg_temp.signup('c2', 'T425RITA', 'Cody', 'Ng T425', '+61491571804');
select pg_temp.check(pg_temp.fx('c2') is not null, 'C3 another link still registers');

-- Spaces typed around the code reach the same link, so they count for it:
-- 20 sign-ups, each with the code padded differently, fill a new link; the
-- 21st (padded another way), the plain code and a leading space are refused.
insert into fx values ('cap', gen_random_uuid());
insert into public.customers(id, full_name, phone) values (pg_temp.fx('cap'), 'T425 Cora Pang', '+61491579455');
insert into public.customer_affiliates(customer_id, status, activated_at, referral_code)
values (pg_temp.fx('cap'), 'active', now() - interval '30 days', 'T425CAP');
do $$
declare i int; n int := 0;
  ph text[] := array['+61491573087', '+61491573770', '+61491574118', '+61491574632', '+61491575254', '+61491575789', '+61491576398'];
begin
  for i in 1 .. 20 loop
    -- i % 4 spaces before the code and i / 4 after: no two alike, none plain.
    if pg_temp.signup('cap' || i, repeat(' ', i % 4) || 'T425CAP' || repeat(' ', i / 4), 'Cap' || i, 'Teo T425', ph[(i - 1) / 3 + 1])->>'outcome' = 'registered' then
      n := n + 1;
    end if;
  end loop;
  insert into rx values ('cap_registered', to_jsonb(n));
end $$;
select pg_temp.signup('cap21', ' T425CAP     ', 'Cap21', 'Teo T425', '+61491576398');
select pg_temp.signup('cap22', 'T425CAP', 'Cap22', 'Teo T425', '+61491576801');
select pg_temp.signup('cap23', ' T425CAP', 'Cap23', 'Teo T425', '+61491577426');
select pg_temp.check((pg_temp.rx('cap_registered'))::int = 20
    and (select count(*) from public.customers where referred_by = pg_temp.fx('cap')) = 20,
  'C4 20 sign-ups through one link, each with the code padded another way, are all made');
select pg_temp.check(pg_temp.rx('cap21')->>'message' like 'This referral link has had many registrations in the last hour.%'
    and pg_temp.rx('cap22')->>'message' like 'This referral link has had many registrations in the last hour.%'
    and pg_temp.rx('cap23')->>'message' like 'This referral link has had many registrations in the last hour.%'
    and pg_temp.fx('cap21') is null and pg_temp.fx('cap22') is null and pg_temp.fx('cap23') is null,
  'C5 the 21st, padded another way, the plain code and a leading space are all refused, and nothing is made');
select pg_temp.check((select count(*) from public.referral_signup_events where referrer_customer_id = pg_temp.fx('cap')) = 23
    and not exists (select 1 from public.referral_signup_events where referrer_customer_id = pg_temp.fx('cap') and referral_code <> 'T425CAP')
    and (select count(*) from public.referral_signup_events where referrer_customer_id = pg_temp.fx('cap') and outcome = 'link_limit') = 3,
  'C6 every event keeps the code as the link reads it (T425CAP), the 3 refusals as link_limit');

-- ═════ X A merge leaves each check with its own record ═════
-- An Owner merges two records of one person (merge_customer_records, run on
-- request). The check stays with the sign-up it was made for; the retired
-- record keeps it.
insert into fx values ('rex', gen_random_uuid()), ('hana', gen_random_uuid());
insert into public.customers(id, full_name, phone) values
  (pg_temp.fx('rex'), 'T425 Rex Ho', '+61491578148'),
  (pg_temp.fx('hana'), 'T425 Hana Lim', '+61491578957');
insert into public.customer_affiliates(customer_id, status, activated_at, referral_code)
values (pg_temp.fx('rex'), 'active', now() - interval '30 days', 'T425REX');
-- X1: Xena signs up through Rita's link on a new phone and visits; Yan signs
-- up through Rex's link on Xena's phone. The Owner checks Yan as the same
-- person, then merges Yan into Xena.
select pg_temp.signup('xk', 'T425RITA', 'Xena', 'Tay T425', '+61491578888');
select pg_temp.signup('xd', 'T425REX', 'Yan', 'Koh T425', '+61491578888');
select pg_temp.visit('xk', public.sg_today() - 1);
select pg_temp.as_user('own');
select public.decide_referral_signup_check((pg_temp.check_of('xd')).id, 'same_person', 'T425 it is Xena');
select pg_temp.check((select counted from pg_temp.friend('xk') as (counted boolean, first_visit_on date)) = true
    and (pg_temp.check_of('xd')).phone_shared_with = array[pg_temp.fx('xk')],
  'X0 before the merge Xena counts for Rita, and Yan''s check (same person) lists her');
insert into rx select 'mx1', public.merge_customer_records(pg_temp.fx('xk'), pg_temp.fx('xd'), 'T425 same person', gen_random_uuid());
select pg_temp.check(pg_temp.rx('mx1')->>'success' = 'true'
    and not (pg_temp.rx('mx1')->'moved' ? 'referral_signup_checks.customer_id')
    and (pg_temp.check_of('xd')).status = 'same_person' and (pg_temp.check_of('xk')).id is null
    and (select deleted_at is not null from public.customers where id = pg_temp.fx('xd'))
    and (select counted from pg_temp.friend('xk') as (counted boolean, first_visit_on date)) = true
    and (select referred_by from public.customers where id = pg_temp.fx('xk')) = pg_temp.fx('ref'),
  'X1 after the merge Yan''s check stays on Yan''s retired record, and Xena still counts for Rita');
-- X2: Hana has had the phone for years. Pia (Rita's link) and Pam (Rex's
-- link) sign up on it under other names: both are checked. Pam is merged
-- into Pia.
select pg_temp.signup('p1', 'T425RITA', 'Pia', 'Ong T425', '+61491578957');
select pg_temp.signup('p2', 'T425REX', 'Pam', 'Ong T425', '+61491578957');
select pg_temp.check((pg_temp.check_of('p1')).status = 'pending' and (pg_temp.check_of('p2')).status = 'pending',
  'X2a two sign-ups on Hana''s phone under other names are both checked');
select pg_temp.as_user('own');  -- a sign-up signs out
select pg_temp.check(pg_temp.err(format('select public.merge_customer_records(%L, %L, ''T425 same person'', %L)',
                                        pg_temp.fx('p1'), pg_temp.fx('p2'), gen_random_uuid())) is null
    and (pg_temp.check_of('p1')).status = 'pending' and (pg_temp.check_of('p2')).status = 'pending'
    and (select count(*) from public.referral_signup_checks where customer_id in (pg_temp.fx('p1'), pg_temp.fx('p2'))) = 2,
  'X2 two records that both have a check merge without error, and each check stays on its own record');
-- X3: Kai signs up through Rita's link and visits; Kay signs up on Kai's
-- phone and waits for a check. Kay is merged into Kai before anyone checks.
select pg_temp.signup('kk', 'T425RITA', 'Kai', 'Lim T425', '+61491579212');
select pg_temp.signup('kd', 'T425RITA', 'Kay', 'Lum T425', '+61491579212');
select pg_temp.visit('kk', public.sg_today() - 1);
select pg_temp.as_user('own');
select public.merge_customer_records(pg_temp.fx('kk'), pg_temp.fx('kd'), 'T425 same person', gen_random_uuid());
insert into rx select 'xlist', public.referral_signup_checks_pending();
select pg_temp.check((select counted from pg_temp.friend('kk') as (counted boolean, first_visit_on date)) = true
    and (pg_temp.check_of('kk')).id is null and (pg_temp.check_of('kd')).status = 'pending'
    and not exists (select 1 from jsonb_array_elements(pg_temp.rx('xlist')) e where e->>'customer_id' = pg_temp.fx('kk')::text)
    and exists (select 1 from jsonb_array_elements(pg_temp.rx('xlist')) e
                 where e->>'customer_id' = pg_temp.fx('kd')::text and (e->>'customer_deleted')::boolean),
  'X3 a pending check on the merged record does not make Kai wait: she still counts, and the list shows the check on Kay''s retired record');
select pg_temp.as_user(null);

do $$ begin
  if exists (select 1 from failed) then
    raise exception '425 shared phone: % check(s) failed: %', (select count(*) from failed), (select string_agg(msg, ' | ' order by n) from failed);
  end if;
  raise notice 'ALL PASS: 425 shared-phone referral sign-ups (same person, checked before counting, the check, the list, the per-link limit, merges)';
end $$;
rollback;
