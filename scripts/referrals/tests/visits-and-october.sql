-- 398: who visited the centre, the referral date, the downline with visits,
-- and the October referral promotion; 404: the promotion counts by the first
-- visit.
--
-- The Owner's rules of 6 Oct 2026: a customer visited the centre when they
-- have a health survey sent through the public form via one of the centre's
-- own links (no event name), or a consultant's survey with answers on it,
-- a consultant note with text or an attachment, or an attached file; an
-- event's link only from a later day's note or file; not the empty record
-- the Surveys page creates. The first visit is that survey's date (a
-- consultant's: the day its first answer, note or file was written). The referral date is
-- recorded whenever a referrer is set or changed (the sign-up link keeps its
-- own; a merge keeps the friend's; a staff login writing the table cannot set
-- it), older links falling back to created_at. Owner/Manager see a
-- downline with visits. The Owner's rule of 8 Oct 2026 (404): a Tier 1
-- friend counts for their referrer when their first visit is in the
-- promotion's window, whenever they were referred, as long as the referral
-- was recorded by the window's last day; the report lists those friends and
-- the friends referred in the window who have not visited yet (not
-- counted), and nobody else. A past customer (a paid or part-paid invoice
-- dated before the window) is neither counted nor listed; cancelled,
-- refunded, unpaid, draft and FOC invoices do not make one. For the
-- promotion a visit through the centre's own link is dated the day the form
-- was sent, never the date typed on it, and the first visit is the earliest
-- of all the friend's visits dated so; the visit rule and the first visit
-- the Customers page shows do not change (customer_centre_visit_days holds
-- the rule, customer_centre_visits picks from it as before: sections 12-14).
-- The reward is for the highest tier reached,
-- given after the window ends, once, and takes its products out of a store's
-- stock as stock uses; the Owner can undo it. An affiliate sees their own
-- progress only.
--
-- Disposable local database only; everything is rolled back. The migrations
-- (398, then 404) are applied inside this transaction, so run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/referrals/tests/visits-and-october.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions, run right after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name, phone, number and amount here is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

\ir ../../../supabase/398_visits_downline_october_referrals.sql

-- ===== 1. The migration re-runs as a no-op =====
create temp table t398_before as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t398_shape_before as
  select table_name::text, column_name::text, data_type::text from information_schema.columns
   where table_schema = 'public' and table_name like 'referral_campaign%';
create temp table t398_campaigns_before as select * from public.referral_campaigns;
\ir ../../../supabase/398_visits_downline_october_referrals.sql
do $$
begin
  if exists (select fn, md5, acl from t398_before
             except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)),
                           coalesce(array_to_string(p.proacl, ','), '')
                      from pg_proc p where p.pronamespace = 'public'::regnamespace)
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace)
        <> (select count(*) from t398_before) then
    raise exception 'FAIL 1: a second run of 398 changed a function or a grant'; end if;
  if exists (select * from t398_shape_before except
             select table_name::text, column_name::text, data_type::text from information_schema.columns
              where table_schema = 'public' and table_name like 'referral_campaign%')
     or exists (select * from public.referral_campaigns except select * from t398_campaigns_before)
     or (select count(*) from public.referral_campaigns) <> (select count(*) from t398_campaigns_before) then
    raise exception 'FAIL 1: a second run of 398 changed a table or the promotion'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.customers'::regclass
         and tgname = 'trg_customers_referral_date') <> 1 then
    raise exception 'FAIL 1: the referral-date trigger is not there exactly once'; end if;
  raise notice 'PASS 1: a second run of 398 changes no function, grant, table, promotion or trigger';
end $$;

-- ===== 1b. 404 on top of 398: a re-run is a no-op; another version refuses =====
-- (398 cannot run again after 404: its new functions are no longer its version.)
create temp table t404_398 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
-- customer_centre_visits as 398 left it (production's), for section 14.
create temp table t404_defs as
  select 'visits_398'::text as k, pg_get_functiondef('public.customer_centre_visits()'::regprocedure) as def;
\ir ../../../supabase/404_referral_promotion_counts_first_visit.sql
insert into t404_defs
  select 'visits_404', pg_get_functiondef('public.customer_centre_visits()'::regprocedure)
  union all select 'days_404', pg_get_functiondef('public.customer_centre_visit_days()'::regprocedure);
create temp table t404_before as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
\ir ../../../supabase/404_referral_promotion_counts_first_visit.sql
-- A function at another version: the one replaced, then one relied on. Each
-- run refuses, naming it, and is rolled back to before the change. (psql
-- prints those two refusals as ERROR lines; they are expected, and checked
-- below.)
savepoint t404_guard;
create or replace function public.referral_campaign_friends(p_campaign_id uuid)
returns table(referrer_customer_id uuid, friend_customer_id uuid, referred_on date, first_visit_on date, counted boolean)
language sql stable security definer set search_path = public
as $f$ select null::uuid, null::uuid, null::date, null::date, false where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/404_referral_promotion_counts_first_visit.sql
\set ON_ERROR_STOP on
rollback to savepoint t404_guard;
release savepoint t404_guard;
select set_config('t404.refused_changed', :'LAST_ERROR_MESSAGE', true) as t404_kept \gset
savepoint t404_guard2;
create or replace function public.referral_campaign_standing(p_tiers integer[], p_count integer)
returns jsonb language sql immutable set search_path = public
as $f$ select '{}'::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/404_referral_promotion_counts_first_visit.sql
\set ON_ERROR_STOP on
rollback to savepoint t404_guard2;
release savepoint t404_guard2;
select set_config('t404.refused_relied', :'LAST_ERROR_MESSAGE', true) as t404_kept \gset
-- The new visit-rule function there with another text; then an invoice
-- status nobody has decided about.
savepoint t404_guard3;
create or replace function public.customer_centre_visit_days()
returns table(customer_id uuid, survey_id uuid, visit_kind text, visit_on date, submitted_at timestamptz, sent_on date)
language sql stable security definer set search_path = public
as $f$ select null::uuid, null::uuid, null::text, null::date, null::timestamptz, null::date where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/404_referral_promotion_counts_first_visit.sql
\set ON_ERROR_STOP on
rollback to savepoint t404_guard3;
release savepoint t404_guard3;
select set_config('t404.refused_days', :'LAST_ERROR_MESSAGE', true) as t404_kept \gset
savepoint t404_guard4;
alter type public.invoice_status add value 'fixture_404_status';
\set ON_ERROR_STOP off
\ir ../../../supabase/404_referral_promotion_counts_first_visit.sql
\set ON_ERROR_STOP on
rollback to savepoint t404_guard4;
release savepoint t404_guard4;
select set_config('t404.refused_status', :'LAST_ERROR_MESSAGE', true) as t404_kept \gset
do $$
declare v_rule_398 text; v_rule_404 text;
begin
  -- 404 changed exactly its four functions and added customer_centre_visit_days,
  -- keeping the four's grants and giving the new one customer_centre_visits'.
  if (select string_agg(b.fn, ',' order by b.fn) from t404_398 b join t404_before a using (fn)
       where a.md5 <> b.md5) <> 'affiliate_portal_campaign_progress(),customer_centre_visits(),referral_campaign_friends(uuid),referral_campaign_report(text)'
     or exists (select 1 from t404_398 b join t404_before a using (fn) where a.acl <> b.acl)
     or (select string_agg(a.fn, ',') from t404_before a where not exists (select 1 from t404_398 b where b.fn = a.fn))
        is distinct from 'customer_centre_visit_days()'
     or exists (select 1 from t404_398 b where not exists (select 1 from t404_before a where a.fn = b.fn))
     or (select acl from t404_before where fn = 'customer_centre_visit_days()')
        is distinct from (select acl from t404_before where fn = 'customer_centre_visits()') then
    raise exception 'FAIL 1b: 404 changed other functions or grants than its four, or added another than customer_centre_visit_days'; end if;
  -- The visit rule moved word for word: the text from "with s as (" to the end
  -- of q is the same in 398's customer_centre_visits and in 404's
  -- customer_centre_visit_days, and is no longer in customer_centre_visits.
  v_rule_398 := (select substring(def from position('  with s as (' in def)
                                  for position(E'end as visit_on\n      from s\n  )' in def) + 32 - position('  with s as (' in def))
                   from t404_defs where k = 'visits_398');
  v_rule_404 := (select substring(def from position('  with s as (' in def)
                                  for position(E'end as visit_on\n      from s\n  )' in def) + 32 - position('  with s as (' in def))
                   from t404_defs where k = 'days_404');
  if v_rule_398 is null or length(v_rule_398) < 3000 or v_rule_398 is distinct from v_rule_404
     or right(v_rule_404, 32) <> E'end as visit_on\n      from s\n  )'
     or (select def from t404_defs where k = 'visits_404') like '%health_surveys%' then
    raise exception 'FAIL 1b: the visit rule in customer_centre_visit_days is not 398''s, word for word, or is still in customer_centre_visits (% / % characters)',
      length(v_rule_398), length(v_rule_404); end if;
  if exists (select fn, md5, acl from t404_before
             except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)),
                           coalesce(array_to_string(p.proacl, ','), '')
                      from pg_proc p where p.pronamespace = 'public'::regnamespace)
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace)
        <> (select count(*) from t404_before) then
    raise exception 'FAIL 1b: a second run of 404, or a refused one, changed a function or a grant'; end if;
  if current_setting('t404.refused_changed') not like
       '404: public.referral_campaign_friends(uuid) is not the version this was tested against%' then
    raise exception 'FAIL 1b: 404 did not refuse a counting function it was not tested against (%)',
      current_setting('t404.refused_changed'); end if;
  if current_setting('t404.refused_relied') not like
       '404: public.referral_campaign_standing(integer[],integer) is missing or not the version read on 8 Oct 2026%' then
    raise exception 'FAIL 1b: 404 did not refuse a tiers function it was not tested against (%)',
      current_setting('t404.refused_relied'); end if;
  if current_setting('t404.refused_days') not like
       '404: public.customer_centre_visit_days() already exists with another text%' then
    raise exception 'FAIL 1b: 404 did not refuse a customer_centre_visit_days of another text (%)',
      current_setting('t404.refused_days'); end if;
  if current_setting('t404.refused_status') not like
       '404: the invoice statuses are not the ones read on 8 Oct 2026%fixture_404_status%' then
    raise exception 'FAIL 1b: 404 did not refuse an invoice status nobody has decided about (%)',
      current_setting('t404.refused_status'); end if;
  raise notice 'PASS 1b: 404 changes only customer_centre_visits, referral_campaign_friends, referral_campaign_report and affiliate_portal_campaign_progress, keeping their grants, and adds customer_centre_visit_days with customer_centre_visits'' grants, the visit rule moved into it word for word; a second run changes nothing; a function at another version, a customer_centre_visit_days of another text or a new invoice status refuses and nothing is kept';
end $$;

-- ===== 2. Grants: the pages reach what they call; the helpers nobody =====
do $$
declare v text;
begin
  if to_regprocedure('public.search_customers(text,text,integer,integer)') is not null then
    raise exception 'FAIL 2: the four-argument search_customers is still there'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'search_customers') <> 1 then
    raise exception 'FAIL 2: there is not exactly one search_customers'; end if;
  foreach v in array array['search_customers(text,text,integer,integer,text,date,date)', 'referrer_downline(uuid)',
                           'customer_downline_visits(uuid)', 'referral_campaign_report(text)',
                           'give_referral_campaign_reward(text,uuid,uuid,jsonb,text)',
                           'void_referral_campaign_reward(uuid,text,boolean)',
                           'affiliate_portal_campaign_progress()'] loop
    if not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception 'FAIL 2: % is not callable by a signed-in login', v; end if;
    if has_function_privilege('anon', 'public.' || v, 'execute') then
      raise exception 'FAIL 2: % is callable signed out', v; end if;
  end loop;
  foreach v in array array['customer_centre_visits()', 'customer_centre_visit_days()', 'tg_customers_referral_date()',
                           'referral_campaign_friends(uuid)', 'referral_campaign_standing(integer[],integer)',
                           'merge_customer_records(uuid,uuid,text,uuid)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception 'FAIL 2: internal % is callable by a client role', v; end if;
  end loop;
  -- 404's new function: the service role's alone (339), no PUBLIC grant, no overload.
  if not has_function_privilege('service_role', 'public.customer_centre_visit_days()', 'execute')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                 where p.oid = 'public.customer_centre_visit_days()'::regprocedure and a.grantee = 0)
     or (select proacl is null from pg_proc where oid = 'public.customer_centre_visit_days()'::regprocedure)
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
           and proname in ('customer_centre_visit_days', 'customer_centre_visits')) <> 2 then
    raise exception 'FAIL 2: customer_centre_visit_days is not the service role''s alone, or has an overload'; end if;
  foreach v in array array['referral_campaigns', 'referral_campaign_rewards', 'referral_campaign_reward_items'] loop
    if has_table_privilege('authenticated', 'public.' || v, 'select')
       or has_table_privilege('authenticated', 'public.' || v, 'insert')
       or has_table_privilege('anon', 'public.' || v, 'select') then
      raise exception 'FAIL 2: % is readable or writable by a client role', v; end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || v)::regclass) then
      raise exception 'FAIL 2: % has no row level security', v; end if;
  end loop;
  if not exists (select 1 from public.referral_campaigns where code = '2026-10' and starts_on = '2026-10-01'
                   and ends_on = '2026-10-31' and tiers = '{10,20,50,80}' and reward_reason = 'October referral reward') then
    raise exception 'FAIL 2: the October promotion is not seeded as the Owner set it'; end if;
  raise notice 'PASS 2: one search_customers (the new one); the pages'' functions are granted to signed-in logins only; the helpers (404''s customer_centre_visit_days too, the service role''s alone) and tables to no client role; October 2026 is seeded with tiers 10/20/50/80';
end $$;

-- ===== Fixtures =====
create temp table t398(k text primary key, id uuid);
-- Parts of the test run as the API roles themselves (set local role), as the
-- pages and anyone calling the API do; they read and add fixture keys.
grant all on t398 to authenticated, anon;

create function pg_temp.t398_id(p_k text) returns uuid language sql as $f$
  select id from t398 where k = p_k
$f$;

create function pg_temp.t398_as(p_k text) returns void language sql as $f$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.t398_id(p_k)::text, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', pg_temp.t398_id(p_k)::text, true);
$f$;

-- A customer; p_ref names their referrer; p_referred_at their referral date
-- ('none': an older link without a date); p_created when they were created.
create function pg_temp.t398_customer(p_k text, p_name text, p_phone text, p_ref text default null,
  p_referred_at text default null, p_created timestamptz default null) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.customers(full_name, phone, notes, referred_by, referred_at, created_at)
  values (p_name, p_phone, 'fixture T398', pg_temp.t398_id(p_ref),
          case when p_referred_at is null or p_referred_at = 'none' then null else p_referred_at::timestamptz end,
          coalesce(p_created, now()))
  returning id into v;
  -- An older link without a date: the trigger dated it, as any insert now is,
  -- so the date is taken off again (an update that does not touch referred_by).
  if p_referred_at = 'none' then update public.customers set referred_at = null where id = v; end if;
  insert into t398 values (p_k, v);
  return v;
end $f$;

-- A public-form survey through link p_link, submitted at p_at, signed on p_signed.
create function pg_temp.t398_link_survey(p_cust text, p_link text, p_at timestamptz, p_signed date default null,
  p_event text default null) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.health_surveys(survey_no, store_id, survey_link_id, customer_id, event_name, full_name,
                                    phone, source, submitted_at, signed_date)
  select 'HS-T398-' || p_cust, l.store_id, l.id, pg_temp.t398_id(p_cust),
         coalesce(p_event, l.event_name), c.full_name, c.phone, 'public_form', p_at, p_signed
    from public.survey_links l, public.customers c
   where l.id = pg_temp.t398_id(p_link) and c.id = pg_temp.t398_id(p_cust)
  returning id into v;
  insert into t398 values ('survey_' || p_cust, v);
  return v;
end $f$;

-- A consultant's survey created at p_at, empty unless p_set says otherwise.
create function pg_temp.t398_consultant(p_cust text, p_at timestamptz, p_set text default null) returns uuid
language plpgsql as $f$
declare v uuid;
begin
  insert into public.health_surveys(survey_no, customer_id, full_name, phone, source, submitted_at)
  select 'HS-T398-' || p_cust, c.id, c.full_name, c.phone, 'consultant', p_at
    from public.customers c where c.id = pg_temp.t398_id(p_cust)
  returning id into v;
  if p_set is not null then execute format('update public.health_surveys set %s where id = %L', p_set, v); end if;
  insert into t398 values ('survey_' || p_cust, v);
  return v;
end $f$;

create function pg_temp.t398_visit(p_k text) returns date language sql as $f$
  select first_visit_on from public.customer_centre_visits() where customer_id = pg_temp.t398_id(p_k)
$f$;

create function pg_temp.t398_refused(p_label text, p_sql text, p_like text) returns void language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm not like '%' || p_like || '%' then
      raise exception 'FAIL %: refused, but with "%" (expected "%")', p_label, sqlerrm, p_like; end if;
    return;
  end;
  raise exception 'FAIL %: was not refused', p_label;
end $f$;

do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); m2 uuid := gen_random_uuid();
  s uuid := gen_random_uuid(); ad uuid := gen_random_uuid(); af uuid := gen_random_uuid(); af2 uuid := gen_random_uuid();
  st uuid; st2 uuid; p uuid; q uuid; so uuid; sym uuid;
begin
  insert into auth.users(id, email) values
    (o, 'owner398@sig.invalid'), (m, 'manager398@sig.invalid'), (m2, 'manager398b@sig.invalid'),
    (s, 'staff398@sig.invalid'), (ad, 'admin398@sig.invalid'), (af, 'aff398@sig.invalid'), (af2, 'aff398b@sig.invalid');
  insert into public.profiles(id, full_name, email, role, is_active) values
    (o, 'Fixture Owner', 'owner398@sig.invalid', 'owner', true),
    (m, 'Fixture Manager', 'manager398@sig.invalid', 'manager', true),
    (m2, 'Fixture Manager Two', 'manager398b@sig.invalid', 'manager', true),
    (s, 'Fixture Staff', 'staff398@sig.invalid', 'staff', true),
    (ad, 'Fixture Admin', 'admin398@sig.invalid', 'admin', true);
  insert into t398 values ('owner', o), ('manager', m), ('manager2', m2), ('staff', s), ('admin', ad),
                          ('aff_login', af), ('aff_login2', af2);
  perform pg_temp.t398_as('owner');
  insert into public.stores(name, code, country_code) values ('Fixture Store 398', 'T398S', 'SG') returning id into st;
  insert into public.stores(name, code, country_code) values ('Fixture Store 398 B', 'T398B', 'SG') returning id into st2;
  insert into public.user_store_assignments(user_id, store_id) values (s, st), (m, st2), (m2, st);
  insert into t398 values ('store', st), ('store_b', st2);
  insert into public.products(name, sku, product_type) values ('Fixture Gift Set 398', 'T398-G', 'own') returning id into p;
  insert into public.products(name, sku, product_type) values ('Fixture Water Bottle 398', 'T398-W', 'own') returning id into q;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 5), (st, q, 2);
  insert into t398 values ('gift', p), ('bottle', q);
  -- Survey links: the centre's own (no event name, and one with a blank one)
  -- and an event's.
  with x as (insert into public.survey_links(token, store_id) values ('t398-centre', st) returning id)
    insert into t398 select 'link_centre', id from x;
  with x as (insert into public.survey_links(token, store_id, event_name) values ('t398-blank', st, '  ') returning id)
    insert into t398 select 'link_blank', id from x;
  with x as (insert into public.survey_links(token, store_id, event_name)
               values ('t398-event', st, 'Roadshow @ Fixture Mall') returning id)
    insert into t398 select 'link_event', id from x;
  insert into public.customer_source_options(label) values ('Fixture Walk-in 398') returning id into so;
  insert into public.health_symptom_options(category, label) values ('Fixture', 'Fixture back ache 398') returning id into sym;
  insert into t398 values ('source', so), ('symptom', sym);
end $$;

-- ===== 3. Visited the centre: the one rule =====
do $$
declare v uuid; r jsonb; n int;
begin
  perform pg_temp.t398_as('owner');
  -- (a) The centre's link, signed on the day.
  perform pg_temp.t398_customer('v_link', 'Jane Tan', '+6591398001');
  perform pg_temp.t398_link_survey('v_link', 'link_centre', '2026-10-05 01:00+00', '2026-10-05');
  if pg_temp.t398_visit('v_link') is distinct from '2026-10-05' then
    raise exception 'FAIL 3a: a survey through the centre''s link is not a visit on its signed date (%)', pg_temp.t398_visit('v_link'); end if;
  -- (b) No signed date: the Singapore date it was submitted (17:30 UTC is 01:30 the next day).
  perform pg_temp.t398_customer('v_nosign', 'May Lee', '+6591398002');
  perform pg_temp.t398_link_survey('v_nosign', 'link_centre', '2026-10-02 17:30+00', null);
  if pg_temp.t398_visit('v_nosign') is distinct from '2026-10-03' then
    raise exception 'FAIL 3b: an unsigned survey is not dated the Singapore day it was submitted (%)', pg_temp.t398_visit('v_nosign'); end if;
  -- (c) An event's link: not a visit.
  perform pg_temp.t398_customer('v_event', 'Ken Ong', '+6591398003');
  perform pg_temp.t398_link_survey('v_event', 'link_event', '2026-10-04 03:00+00', '2026-10-04');
  if pg_temp.t398_visit('v_event') is not null then
    raise exception 'FAIL 3c: a survey through an event''s link counted as a visit'; end if;
  -- (d) An "Event" typed on the centre's link (the public form's optional field) is still the centre.
  perform pg_temp.t398_customer('v_typed', 'Ann Goh', '+6591398004');
  perform pg_temp.t398_link_survey('v_typed', 'link_centre', '2026-10-04 03:00+00', '2026-10-04', 'Facebook');
  if pg_temp.t398_visit('v_typed') is distinct from '2026-10-04' then
    raise exception 'FAIL 3d: an event name typed on the centre''s link stopped the visit'; end if;
  -- (e) A link whose event name is blank is the centre's.
  perform pg_temp.t398_customer('v_blank', 'Tom Ng', '+6591398005');
  perform pg_temp.t398_link_survey('v_blank', 'link_blank', '2026-10-04 03:00+00', '2026-10-04');
  if pg_temp.t398_visit('v_blank') is null then
    raise exception 'FAIL 3e: a link with a blank event name is not the centre''s'; end if;
  -- (f) A public-form survey with no link: not a visit.
  perform pg_temp.t398_customer('v_nolink', 'Sam Teo', '+6591398006');
  insert into public.health_surveys(survey_no, customer_id, full_name, phone, source, submitted_at, signed_date)
  values ('HS-T398-v_nolink', pg_temp.t398_id('v_nolink'), 'Sam Teo', '+6591398006', 'public_form', '2026-10-04 03:00+00', '2026-10-04');
  if pg_temp.t398_visit('v_nolink') is not null then
    raise exception 'FAIL 3f: a public-form survey without a link counted'; end if;

  -- (g) The Surveys page's own path: staff open a customer, an empty record is made. Not a visit.
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_customer('v_empty', 'Lily Chua', '+6591398007');
  v := public.upsert_consultant_survey(pg_temp.t398_id('v_empty'), null, null, null, null, null, null, null, null, null,
                                       pg_temp.t398_id('store'));
  if not exists (select 1 from public.health_surveys where id = v and source = 'consultant') then
    raise exception 'FIXTURE 3g: no consultant record was made'; end if;
  if pg_temp.t398_visit('v_empty') is not null then
    raise exception 'FAIL 3g: the empty record the Surveys page makes counted as a visit'; end if;
  -- ... answered later through the same path: a visit, dated the day the record was made.
  perform pg_temp.t398_customer('v_filled', 'Ray Koh', '+6591398008');
  v := public.upsert_consultant_survey(pg_temp.t398_id('v_filled'), null, null, null, null, null, null, null, null, null,
                                       pg_temp.t398_id('store'));
  update public.health_surveys set submitted_at = '2026-10-06 18:00+00' where id = v;  -- 7 Oct in Singapore
  if pg_temp.t398_visit('v_filled') is not null then
    raise exception 'FAIL 3h: an unanswered consultant record counted'; end if;
  perform public.upsert_consultant_survey(pg_temp.t398_id('v_filled'), 'Stiff shoulders', null, null, null,
                                          null, null, null, null, null, null);
  if pg_temp.t398_visit('v_filled') is distinct from '2026-10-07' then
    raise exception 'FAIL 3h: a consultant survey with an answer is not a visit on the Singapore day it was made (%)', pg_temp.t398_visit('v_filled'); end if;
  perform pg_temp.t398_as('owner');

  -- (i) Each kind of answer on the consultant's survey itself makes it a
  -- visit, and so does a consultant note with text or an attachment, or an
  -- attached file (the Owner, 6 Oct 2026); blanks and empty notes do not. A
  -- survey answered only by a note or a file is dated by it.
  perform pg_temp.t398_customer('v_ws', 'Joy Lim', '+6591398009');
  perform pg_temp.t398_consultant('v_ws', '2026-10-03 02:00+00', $s$remarks_condition = '   ', health_goals = ''$s$);
  if pg_temp.t398_visit('v_ws') is not null then raise exception 'FAIL 3i: blank text counted as an answer'; end if;
  perform pg_temp.t398_customer('v_bool', 'Ben Tay', '+6591398010');
  perform pg_temp.t398_consultant('v_bool', '2026-10-03 02:00+00', 'smokes = false');
  if pg_temp.t398_visit('v_bool') is distinct from '2026-10-03' then raise exception 'FAIL 3i: a yes/no answer did not count'; end if;
  perform pg_temp.t398_customer('v_sym', 'Eve Sim', '+6591398011');
  insert into public.health_survey_symptoms(survey_id, option_id)
  values (pg_temp.t398_consultant('v_sym', '2026-10-03 02:00+00'), pg_temp.t398_id('symptom'));
  if pg_temp.t398_visit('v_sym') is null then raise exception 'FAIL 3i: a symptom did not count'; end if;
  perform pg_temp.t398_customer('v_note', 'Ivy Yeo', '+6591398012');
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, attachments, created_by)
  values (pg_temp.t398_consultant('v_note', '2026-10-03 02:00+00'), pg_temp.t398_id('v_note'), 'Tired legs', '[]', pg_temp.t398_id('staff'));
  update public.consultant_notes set created_at = '2026-10-04 02:00+00' where survey_id = pg_temp.t398_id('survey_v_note');
  if pg_temp.t398_visit('v_note') is distinct from '2026-10-04' then
    raise exception 'FAIL 3i: a consultant note with text is not a visit on its day (%)', pg_temp.t398_visit('v_note'); end if;
  perform pg_temp.t398_customer('v_note_blank', 'Gus Low', '+6591398013');
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, health_goals, attachments, created_by)
  values (pg_temp.t398_consultant('v_note_blank', '2026-10-03 02:00+00'), pg_temp.t398_id('v_note_blank'), ' ', '', '[]',
          pg_temp.t398_id('staff'));
  if pg_temp.t398_visit('v_note_blank') is not null then raise exception 'FAIL 3i: an empty consultant note counted'; end if;
  perform pg_temp.t398_customer('v_note_file', 'Hal Woo', '+6591398014');
  insert into public.consultant_notes(survey_id, customer_id, attachments, created_by)
  values (pg_temp.t398_consultant('v_note_file', '2026-10-03 02:00+00'), pg_temp.t398_id('v_note_file'),
          '[{"name":"scan.pdf"}]', pg_temp.t398_id('staff'));
  update public.consultant_notes set created_at = '2026-10-05 02:00+00' where survey_id = pg_temp.t398_id('survey_v_note_file');
  if pg_temp.t398_visit('v_note_file') is distinct from '2026-10-05' then
    raise exception 'FAIL 3i: a consultant note with an attachment is not a visit on its day (%)', pg_temp.t398_visit('v_note_file'); end if;
  perform pg_temp.t398_customer('v_file', 'Kai Pang', '+6591398015');
  insert into public.health_survey_attachments(survey_id, storage_path, file_name)
  values (pg_temp.t398_consultant('v_file', '2026-10-03 02:00+00'), 't398/scan.pdf', 'scan.pdf');
  update public.health_survey_attachments set uploaded_at = '2026-10-02 02:00+00' where survey_id = pg_temp.t398_id('survey_v_file');
  if pg_temp.t398_visit('v_file') is distinct from '2026-10-03' then
    raise exception 'FAIL 3i: an attached file is not a visit, never before the record was made (%)', pg_temp.t398_visit('v_file'); end if;
  -- ... a note beside an answer changes nothing: the answer counts, dated as the survey.
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, attachments, created_by, created_at)
  values (pg_temp.t398_id('survey_v_bool'), pg_temp.t398_id('v_bool'), 'Later note', '[]', pg_temp.t398_id('staff'), '2026-09-01 02:00+00');
  if pg_temp.t398_visit('v_bool') is distinct from '2026-10-03' then raise exception 'FAIL 3i: a note moved a visit''s date'; end if;

  -- (j) The real public form (submit_health_survey): the centre's link is a visit today, an event's is not.
  r := public.submit_health_survey('t398-centre', jsonb_build_object('full_name', 'Zoe Quek', 'phone', '+6591398016',
         'email', 'zq@sig.invalid', 'signature_data', 'data:fixture', 'source_option_id', pg_temp.t398_id('source')), '[]');
  insert into t398 select 'v_form', customer_id from public.health_surveys where id = (r->>'survey_id')::uuid;
  if pg_temp.t398_visit('v_form') is distinct from public.sg_today() then
    raise exception 'FAIL 3j: the public form through the centre''s link is not a visit today'; end if;
  r := public.submit_health_survey('t398-event', jsonb_build_object('full_name', 'Yan Seah', 'phone', '+6591398017',
         'email', 'ys@sig.invalid', 'signature_data', 'data:fixture', 'source_option_id', pg_temp.t398_id('source')), '[]');
  insert into t398 select 'v_form_event', customer_id from public.health_surveys where id = (r->>'survey_id')::uuid;
  if pg_temp.t398_visit('v_form_event') is not null then
    raise exception 'FAIL 3j: the public form through an event''s link counted'; end if;
  -- ... a note written the same day (at the event) still is not a visit;
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, attachments, created_by)
  values ((r->>'survey_id')::uuid, pg_temp.t398_id('v_form_event'), 'Seen at the roadshow', '[]', pg_temp.t398_id('staff'));
  if pg_temp.t398_visit('v_form_event') is not null then
    raise exception 'FAIL 3j: a note on the event day made an event survey a visit'; end if;
  -- ... a file on a later day is (the Owner, 6 Oct 2026), dated that day, and
  -- an even later note does not move it.
  insert into public.health_survey_attachments(survey_id, storage_path, file_name, uploaded_at)
  values ((r->>'survey_id')::uuid, 't398/later.pdf', 'later.pdf', now() + interval '2 days');
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, attachments, created_by, created_at)
  values ((r->>'survey_id')::uuid, pg_temp.t398_id('v_form_event'), 'Came to the centre', '[]', pg_temp.t398_id('staff'),
          now() + interval '5 days');
  if pg_temp.t398_visit('v_form_event') is distinct from ((now() + interval '2 days') at time zone 'Asia/Singapore')::date then
    raise exception 'FAIL 3j: a later file did not make the event survey a visit on its day (%)', pg_temp.t398_visit('v_form_event'); end if;
  if (select visit_kind from public.customer_centre_visits() where customer_id = pg_temp.t398_id('v_form_event')) <> 'event_then_centre' then
    raise exception 'FAIL 3j: the later visit is not marked as after an event'; end if;

  -- (k) The Surveys page makes the consultant's record when staff open the
  -- customer, possibly days before the consultation: the visit is the
  -- Singapore day its answers were first saved (the survey's audit rows),
  -- never before the record was made. The record is made on 28 Oct here.
  -- Save Review (review_health_survey, Owner/Manager) on 3 Nov.
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_customer('v_late_rev', 'Amy Png', '+6591398018');
  v := public.upsert_consultant_survey(pg_temp.t398_id('v_late_rev'), null, null, null, null, null, null, null, null, null,
                                       pg_temp.t398_id('store'));
  insert into t398 values ('survey_v_late_rev', v);
  update public.health_surveys set submitted_at = '2026-10-28 02:00+00' where id = v;
  perform pg_temp.t398_as('manager');
  perform public.review_health_survey(p_survey_id => v, p_acidity => 'green', p_health_goals => 'Sleep better',
                                      p_condition => 'Back pain', p_recommendation => 'Weekly therapy');
  update public.audit_logs set created_at = '2026-11-02 17:30+00'   -- 01:30 on 3 Nov in Singapore
   where record_id = v and action = 'health_survey_reviewed';
  if pg_temp.t398_visit('v_late_rev') is distinct from '2026-11-03' then
    raise exception 'FAIL 3k: a record answered (Save Review) on 3 Nov is dated %', pg_temp.t398_visit('v_late_rev'); end if;
  -- ... an answer row dated before the record was made does not date the visit earlier.
  update public.audit_logs set created_at = '2026-10-20 02:00+00' where record_id = v and action = 'health_survey_reviewed';
  if pg_temp.t398_visit('v_late_rev') is distinct from '2026-10-28' then
    raise exception 'FAIL 3k: a visit was dated before its record (%)', pg_temp.t398_visit('v_late_rev'); end if;
  update public.audit_logs set created_at = '2026-11-03 03:00+00' where record_id = v and action = 'health_survey_reviewed';
  -- Particulars (update_survey_particulars: yes/no answers, symptoms) saved on 4 Nov.
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_customer('v_late_part', 'Bo Seet', '+6591398019');
  v := public.upsert_consultant_survey(pg_temp.t398_id('v_late_part'), null, null, null, null, null, null, null, null, null,
                                       pg_temp.t398_id('store'));
  update public.health_surveys set submitted_at = '2026-10-28 02:00+00' where id = v;
  perform public.update_survey_particulars(p_survey_id => v, p_first_name => 'Bo', p_last_name => 'Seet',
    p_phone => '+6591398019', p_smokes => false,
    p_symptoms => jsonb_build_array(jsonb_build_object('option_id', pg_temp.t398_id('symptom'))));
  update public.audit_logs set created_at = '2026-11-04 03:00+00' where record_id = v and action = 'survey_particulars_edited';
  if pg_temp.t398_visit('v_late_part') is distinct from '2026-11-04' then
    raise exception 'FAIL 3k: a record answered (particulars) on 4 Nov is dated %', pg_temp.t398_visit('v_late_part'); end if;
  -- A save of particulars without answers (a name fixed on 29 Oct) and a blank
  -- Save Review (30 Oct) do not date it; the Save Review with answers (5 Nov) does.
  perform pg_temp.t398_customer('v_late_mix', 'Cy Tan', '+6591398033');
  v := public.upsert_consultant_survey(pg_temp.t398_id('v_late_mix'), null, null, null, null, null, null, null, null, null,
                                       pg_temp.t398_id('store'));
  update public.health_surveys set submitted_at = '2026-10-28 02:00+00' where id = v;
  perform public.update_survey_particulars(p_survey_id => v, p_first_name => 'Cy', p_last_name => 'Tan', p_phone => '+6591398033');
  update public.audit_logs set created_at = '2026-10-29 03:00+00' where record_id = v and action = 'survey_particulars_edited';
  perform pg_temp.t398_as('manager');
  perform public.review_health_survey(p_survey_id => v, p_acidity => null, p_health_goals => ' ', p_condition => null, p_recommendation => null);
  update public.audit_logs set created_at = '2026-10-30 03:00+00' where record_id = v and action = 'health_survey_reviewed';
  if pg_temp.t398_visit('v_late_mix') is not null then
    raise exception 'FAIL 3k: a name fixed and a blank Save Review made a visit'; end if;
  perform public.review_health_survey(p_survey_id => v, p_acidity => 'blue', p_health_goals => null, p_condition => 'Neck', p_recommendation => null);
  update public.audit_logs set created_at = '2026-11-05 03:00+00'
   where record_id = v and action = 'health_survey_reviewed' and created_at <> '2026-10-30 03:00+00';
  if pg_temp.t398_visit('v_late_mix') is distinct from '2026-11-05' then
    raise exception 'FAIL 3k: the first Save Review with answers (5 Nov) did not date the visit (%)', pg_temp.t398_visit('v_late_mix'); end if;
  perform pg_temp.t398_as('owner');

  -- One row per customer.
  select count(*) - count(distinct customer_id) into n from public.customer_centre_visits();
  if n <> 0 then raise exception 'FAIL 3: customer_centre_visits has % duplicate customers', n; end if;
  raise notice 'PASS 3: the centre''s link (signed date, else the Singapore day) and a consultant''s survey with an answer, a note with text or an attachment, or a file are visits; an event''s link counts only from a later day''s note or file; a link-less form, blanks, empty notes and the Surveys page''s empty record are not; a consultant''s visit is the Singapore day its first answer, note or file was written, never before the record';
end $$;

-- ===== 4. The referral date =====
do $$
declare v uuid; r jsonb; t timestamptz;
begin
  -- Fixtures, written as the database itself (postgres): dated links and an
  -- older link without a date.
  perform pg_temp.t398_as('owner');
  perform pg_temp.t398_customer('ref_x', 'Ada Chan', '+6591398020');
  perform pg_temp.t398_customer('ref_y', 'Leo Foo', '+6591398021');
  perform pg_temp.t398_customer('r_edit', 'Noah Kwek', '+6591398023');
  perform pg_temp.t398_customer('r_old', 'Olga Pek', '+6591398024', 'ref_x', 'none', '2026-08-15 04:00+00');
  perform pg_temp.t398_customer('r_fix', 'Quinn Toh', '+6591398026', 'ref_x', '2026-09-01 02:00+00');
  perform pg_temp.t398_customer('r_sep', 'Ray Sim', '+6591398035', 'ref_x', '2026-09-20 02:00+00');
  perform pg_temp.t398_customer('r_rm', 'Una Kho', '+6591398036', 'ref_x', '2026-09-21 02:00+00');

  -- (a)-(c) The Customers page writes the table directly, as the signed-in
  -- staff login: the API role authenticated, under the table's own policies,
  -- as anyone calling the API by hand would.
  perform pg_temp.t398_as('staff');
  execute 'set local role authenticated';
  if current_user <> 'authenticated' then raise exception 'FIXTURE 4: not running as the API role'; end if;
  -- (a) Add with a referrer: dated now.
  insert into public.customers(full_name, phone, notes, referred_by, is_referrer)
  values ('Mia Hoo', '+6591398022', 'fixture T398', pg_temp.t398_id('ref_x'), true) returning id into v;
  if (select referred_at from public.customers where id = v) is distinct from now() then
    raise exception 'FAIL 4a: the Customers page''s Add did not date the referral'; end if;
  -- ... an Add that sends a referral date of its own (say, inside a promotion's window) is dated now all the same.
  insert into public.customers(full_name, phone, notes, referred_by, referred_at)
  values ('Pat Lui', '+6591398037', 'fixture T398', pg_temp.t398_id('ref_x'), '2026-10-02 02:00+00') returning id into v;
  if (select referred_at from public.customers where id = v) is distinct from now() then
    raise exception 'FAIL 4a: a staff login''s insert wrote its own referral date'; end if;
  -- ... and without a referrer, a date sent is dropped.
  insert into public.customers(full_name, phone, notes, referred_at)
  values ('Kay Ho', '+6591398038', 'fixture T398', '2026-10-02 02:00+00') returning id into v;
  if (select referred_at from public.customers where id = v) is not null then
    raise exception 'FAIL 4a: a staff login''s insert without a referrer kept a referral date'; end if;
  -- (b) Edit: the whole form is written back; a referrer set now is dated now.
  update public.customers set full_name = 'Noah Kwek', phone = '+6591398023', referred_by = pg_temp.t398_id('ref_x'),
         is_referrer = true where id = pg_temp.t398_id('r_edit');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_edit')) is distinct from now() then
    raise exception 'FAIL 4b: the Customers page''s Edit did not date a new referral'; end if;
  -- ... an Edit that writes the same referrer back leaves an older link's missing date alone (no backfill).
  update public.customers set notes = 'fixture T398 edited', referred_by = pg_temp.t398_id('ref_x')
   where id = pg_temp.t398_id('r_old');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_old')) is not null then
    raise exception 'FAIL 4b: an Edit that kept the referrer gave an older link a date'; end if;
  -- ... a staff login cannot move a referral date into a promotion's window (PATCH /customers {referred_at}),
  update public.customers set referred_at = '2026-10-02 02:00+00' where id = pg_temp.t398_id('r_sep');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_sep')) is distinct from '2026-09-20 02:00+00' then
    raise exception 'FAIL 4b: a staff login moved a referral date'; end if;
  -- ... nor clear it,
  update public.customers set referred_at = null where id = pg_temp.t398_id('r_sep');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_sep')) is distinct from '2026-09-20 02:00+00' then
    raise exception 'FAIL 4b: a staff login cleared a referral date'; end if;
  -- ... nor with the same referrer written back beside it, nor with the merge's setting on.
  perform set_config('energia.keep_referral_date', '1', true);
  update public.customers set referred_by = pg_temp.t398_id('ref_x'), referred_at = '2026-10-02 02:00+00'
   where id = pg_temp.t398_id('r_sep');
  perform set_config('energia.keep_referral_date', '0', true);
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_sep')) is distinct from '2026-09-20 02:00+00' then
    raise exception 'FAIL 4b: a staff login moved a referral date with the referrer or the merge setting'; end if;
  -- ... removing the referrer leaves the date as it was, whatever is sent.
  update public.customers set referred_by = null, referred_at = '2026-10-02 02:00+00' where id = pg_temp.t398_id('r_rm');
  if (select referred_by from public.customers where id = pg_temp.t398_id('r_rm')) is not null
     or (select referred_at from public.customers where id = pg_temp.t398_id('r_rm')) is distinct from '2026-09-21 02:00+00' then
    raise exception 'FAIL 4b: removing a referrer as a staff login changed the date'; end if;
  -- (c) Quick create (the Invoices page), by the same login.
  r := public.create_customer_quick('Pia', 'Sng', '+6591398025', null, null, null, null, null, 'fixture T398',
                                    pg_temp.t398_id('ref_x'), null);
  if (select referred_at from public.customers where id = (r->>'customer_id')::uuid) is distinct from now() then
    raise exception 'FAIL 4c: quick create did not date the referral'; end if;
  execute 'reset role';
  -- (d) Correct Referrer, by the Owner's login: a new date, replacing the old one.
  perform pg_temp.t398_as('owner');
  execute 'set local role authenticated';
  perform public.reassign_customer_referrer(pg_temp.t398_id('r_fix'), pg_temp.t398_id('ref_y'), 'Fixture: wrong referrer');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_fix')) is distinct from now() then
    raise exception 'FAIL 4d: Correct Referrer did not date the new referral'; end if;
  perform public.reassign_customer_referrer(pg_temp.t398_id('r_old'), pg_temp.t398_id('ref_y'), 'Fixture: wrong referrer');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_old')) is distinct from now() then
    raise exception 'FAIL 4d: Correct Referrer did not date an older link it changed'; end if;
  -- ... removing a referrer leaves the date alone.
  t := (select referred_at from public.customers where id = pg_temp.t398_id('r_fix'));
  perform public.reassign_customer_referrer(pg_temp.t398_id('r_fix'), null, 'Fixture: no referrer');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_fix')) is distinct from t then
    raise exception 'FAIL 4d: removing a referrer changed the date'; end if;
  execute 'reset role';
  -- (e) The database's own functions run as their owner (postgres, as here)
  -- and may write a date of their own: an insert, and an update of both.
  perform pg_temp.t398_customer('r_own', 'Rhea Yap', '+6591398027', 'ref_x', '2026-09-15 03:00+00');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_own')) <> '2026-09-15 03:00+00' then
    raise exception 'FAIL 4e: a referral date written with the referrer was overwritten'; end if;
  perform pg_temp.t398_customer('r_own2', 'Sid Ang', '+6591398028');
  update public.customers set referred_by = pg_temp.t398_id('ref_x'), referred_at = '2026-09-20 03:00+00'
   where id = pg_temp.t398_id('r_own2');
  if (select referred_at from public.customers where id = pg_temp.t398_id('r_own2')) <> '2026-09-20 03:00+00' then
    raise exception 'FAIL 4e: an update writing its own referral date was overwritten'; end if;
  -- (f) The sign-up link (/r/:code), signed out (the API role anon), keeps its own date and source.
  with x as (insert into public.customer_affiliates(customer_id, store_id, status, activated_at, referral_code)
               values (pg_temp.t398_id('ref_x'), pg_temp.t398_id('store'), 'active', now(), 'T398ADA') returning id)
    insert into t398 select 'aff_x', id from x;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  r := public.affiliate_referral_signup('T398ADA', 'Tia', 'Boon', '+6591398029', 'tb@sig.invalid', null);
  execute 'reset role';
  perform pg_temp.t398_as('owner');
  if (r->>'outcome') <> 'registered' then raise exception 'FIXTURE 4f: the sign-up did not register (%)', r; end if;
  select id into v from public.customers where phone = '+6591398029' and deleted_at is null;
  if (select referred_by from public.customers where id = v) <> pg_temp.t398_id('ref_x')
     or (select referred_at from public.customers where id = v) is distinct from now()
     or (select referral_source from public.customers where id = v) <> 'affiliate_link' then
    raise exception 'FAIL 4f: the sign-up link''s referral and date were not kept'; end if;
  -- (g) A merge moves the duplicate's friends with their dates (or none); afterwards the rule is back.
  perform pg_temp.t398_customer('dup_keep', 'Uma Lau', '+6591398030');
  perform pg_temp.t398_customer('dup_dup', 'Uma Lau (dup)', '+6591398030');
  perform pg_temp.t398_customer('dup_f1', 'Val Kee', '+6591398031', 'dup_dup', '2026-08-20 02:00+00');
  perform pg_temp.t398_customer('dup_f2', 'Wes Gan', '+6591398032', 'dup_dup', 'none', '2026-08-01 02:00+00');
  r := public.merge_customer_records(pg_temp.t398_id('dup_keep'), pg_temp.t398_id('dup_dup'), 'Fixture: same person', gen_random_uuid());
  if (select referred_by from public.customers where id = pg_temp.t398_id('dup_f1')) <> pg_temp.t398_id('dup_keep')
     or (select referred_at from public.customers where id = pg_temp.t398_id('dup_f1')) <> '2026-08-20 02:00+00' then
    raise exception 'FAIL 4g: a merge did not keep the friend''s referral date'; end if;
  if (select referred_at from public.customers where id = pg_temp.t398_id('dup_f2')) is not null then
    raise exception 'FAIL 4g: a merge gave an older link a date'; end if;
  if coalesce(current_setting('energia.keep_referral_date', true), '') = '1' then
    raise exception 'FAIL 4g: the merge left its setting on'; end if;
  perform public.reassign_customer_referrer(pg_temp.t398_id('dup_f2'), pg_temp.t398_id('ref_y'), 'Fixture: after the merge');
  if (select referred_at from public.customers where id = pg_temp.t398_id('dup_f2')) is distinct from now() then
    raise exception 'FAIL 4g: after a merge, Correct Referrer no longer dates the referral'; end if;
  raise notice 'PASS 4: the Customers page''s Add and Edit, quick create and Correct Referrer date a referral now, run as the API role; a staff login cannot write, move or clear a referral date itself (with or without the referrer or the merge setting); the database''s own functions keep a date they write (the sign-up link''s, signed out); a kept referrer, a removal and a merge leave dates as they were; nothing is backfilled';
end $$;

-- ===== 5. The downline with visits (Owner/Manager) =====
do $$
declare d jsonb; t1 jsonb; t2 jsonb;
begin
  perform pg_temp.t398_as('owner');
  -- Al Wee referred Bea (dated, visited), Cal (an older link, no visit); Bea referred Dee (visited).
  perform pg_temp.t398_customer('dl_top', 'Al Wee', '+6591398040');
  perform pg_temp.t398_customer('dl_bea', 'Bea Ho', '+6591398041', 'dl_top', '2026-09-10 02:00+00');
  perform pg_temp.t398_link_survey('dl_bea', 'link_centre', '2026-09-12 02:00+00', '2026-09-12');
  perform pg_temp.t398_customer('dl_cal', 'Cal Ee', '+6591398042', 'dl_top', 'none', '2026-08-03 18:00+00');
  perform pg_temp.t398_customer('dl_dee', 'Dee Ku', '+6591398043', 'dl_bea', '2026-09-20 02:00+00');
  perform pg_temp.t398_consultant('dl_dee', '2026-09-21 02:00+00', $s$remarks_condition = 'Knee'$s$);

  perform pg_temp.t398_as('manager');
  d := public.customer_downline_visits(pg_temp.t398_id('dl_top'));
  t1 := d->'tier1'; t2 := d->'tier2';
  if jsonb_array_length(t1) <> 2 or jsonb_array_length(t2) <> 1 then
    raise exception 'FAIL 5: Tier 1 / Tier 2 are % / %, not 2 / 1', jsonb_array_length(t1), jsonb_array_length(t2); end if;
  if not exists (select 1 from jsonb_array_elements(t1) e where e->>'name' = 'Bea Ho' and e->>'phone' = '+6591398041'
                  and e->>'joined_on' = '2026-09-10' and (e->>'joined_from_created')::boolean = false
                  and (e->>'visited')::boolean and e->>'first_visit_on' = '2026-09-12') then
    raise exception 'FAIL 5: Bea''s row is wrong: %', t1; end if;
  -- Cal: no referral date, so joined is the Singapore day he was created (18:00 UTC, 4 Aug).
  if not exists (select 1 from jsonb_array_elements(t1) e where e->>'name' = 'Cal Ee'
                  and e->>'joined_on' = '2026-08-04' and (e->>'joined_from_created')::boolean
                  and not (e->>'visited')::boolean and e->'first_visit_on' = 'null'::jsonb) then
    raise exception 'FAIL 5: Cal''s row (created date, not visited) is wrong: %', t1; end if;
  if not exists (select 1 from jsonb_array_elements(t2) e where e->>'name' = 'Dee Ku' and e->>'parent_name' = 'Bea Ho'
                  and (e->>'visited')::boolean and e->>'first_visit_on' = '2026-09-21') then
    raise exception 'FAIL 5: Dee''s Tier 2 row is wrong: %', t2; end if;
  perform pg_temp.t398_as('owner');
  if jsonb_array_length(public.customer_downline_visits(pg_temp.t398_id('dl_top'))->'tier1') <> 2 then
    raise exception 'FAIL 5: the Owner does not see the downline'; end if;
  -- Refused: staff, an Admin, an affiliate login, nobody.
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_refused('5 staff', format('select public.customer_downline_visits(%L)', pg_temp.t398_id('dl_top')), 'Only an Owner or Manager');
  perform pg_temp.t398_as('admin');
  perform pg_temp.t398_refused('5 admin', format('select public.customer_downline_visits(%L)', pg_temp.t398_id('dl_top')), 'Only an Owner or Manager');
  perform pg_temp.t398_as('aff_login');
  perform pg_temp.t398_refused('5 affiliate', format('select public.customer_downline_visits(%L)', pg_temp.t398_id('dl_top')), 'Only an Owner or Manager');

  -- referrer_downline (the Commissions page): the same rows as before for Owner, Manager and Admin; refused otherwise.
  perform pg_temp.t398_as('manager');
  if (select count(*) from public.referrer_downline(pg_temp.t398_id('dl_top'))) <> 3
     or (select count(*) from public.referrer_downline(pg_temp.t398_id('dl_top')) x where x.depth = 2 and x.full_name = 'Dee Ku') <> 1
     or (select string_agg(x.full_name, ',' order by x.depth, x.full_name) from public.referrer_downline(pg_temp.t398_id('dl_top')) x)
        <> 'Bea Ho,Cal Ee,Dee Ku' then
    raise exception 'FAIL 5: referrer_downline does not give the Manager the same rows'; end if;
  perform pg_temp.t398_as('admin');
  if (select count(*) from public.referrer_downline(pg_temp.t398_id('dl_top'))) <> 3 then
    raise exception 'FAIL 5: referrer_downline refused an Admin, who opens the Commissions page'; end if;
  perform pg_temp.t398_as('owner');
  if (select sum(x.paid_purchases) from public.referrer_downline(pg_temp.t398_id('dl_top')) x) <> 0 then
    raise exception 'FAIL 5: referrer_downline''s purchases changed'; end if;
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_refused('5 staff referrer_downline', format('select * from public.referrer_downline(%L)', pg_temp.t398_id('dl_top')), 'Commission access denied');
  perform pg_temp.t398_as('aff_login');
  perform pg_temp.t398_refused('5 affiliate referrer_downline', format('select * from public.referrer_downline(%L)', pg_temp.t398_id('dl_top')), 'Commission access denied');
  -- referrer_list (the Referrers tab) calls referrer_downline for each
  -- referrer: an Admin still gets the list with its downline counts, and
  -- anyone without access still gets no rows rather than an error.
  perform pg_temp.t398_as('admin');
  if (select total_downline from public.referrer_list() where customer_id = pg_temp.t398_id('dl_top')) <> 3 then
    raise exception 'FAIL 5: referrer_list no longer counts the downline for an Admin'; end if;
  perform pg_temp.t398_as('staff');
  if exists (select 1 from public.referrer_list()) then raise exception 'FAIL 5: referrer_list gave staff rows'; end if;
  perform pg_temp.t398_as('aff_login');
  if exists (select 1 from public.referrer_list()) then raise exception 'FAIL 5: referrer_list gave an affiliate rows'; end if;
  raise notice 'PASS 5: Owner and Manager see Tier 1 and Tier 2 with phone, joined (else created), visited and first visit; staff, Admin and affiliate logins are refused; referrer_downline gives Owner, Manager and Admin the same rows and refuses staff and affiliate logins; referrer_list, which calls it, still counts the downline for an Admin and gives others nothing, without an error';
end $$;

-- ===== 6. search_customers: Visited and the first visit date =====
do $$
declare n_all int; n_vis int; n_not int; n_rng int; v date; n int;
begin
  perform pg_temp.t398_as('staff');
  select count(*) into n_all from public.search_customers('fixture T398', null, 1000, 0);
  select count(*) into n_vis from public.search_customers('fixture T398', null, 1000, 0, 'visited');
  select count(*) into n_not from public.search_customers('fixture T398', null, 1000, 0, 'not_visited');
  if n_all = 0 or n_vis = 0 or n_not = 0 or n_vis + n_not <> n_all then
    raise exception 'FAIL 6: all % <> visited % + not visited %', n_all, n_vis, n_not; end if;
  if n_vis <> (select count(*) from public.customers c join public.customer_centre_visits() x on x.customer_id = c.id
                where c.notes like 'fixture T398%' and c.deleted_at is null) then
    raise exception 'FAIL 6: Visited does not follow customer_centre_visits'; end if;
  if (select count(*) from public.search_customers('fixture T398', null, 1000, 0, 'all')) <> n_all
     or (select count(*) from public.search_customers('fixture T398', null, 1000, 0, '')) <> n_all then
    raise exception 'FAIL 6: All is not every customer'; end if;
  select first_visit_on into v from public.search_customers('+6591398001', null, 10, 0) where phone = '+6591398001';
  if v is distinct from '2026-10-05' then raise exception 'FAIL 6: the list''s first visit date is %', v; end if;
  if exists (select 1 from public.search_customers('fixture T398', null, 1000, 0, 'not_visited') where first_visit_on is not null)
     or exists (select 1 from public.search_customers('fixture T398', null, 1000, 0, 'visited') where first_visit_on is null) then
    raise exception 'FAIL 6: Visited / Not visited disagree with the first visit date'; end if;
  -- From - to: both ends included; a date leaves out those who never visited.
  select count(*) into n_rng from public.search_customers('fixture T398', null, 1000, 0, null, '2026-10-03', '2026-10-04');
  if n_rng <> (select count(*) from public.customers c join public.customer_centre_visits() x on x.customer_id = c.id
                where c.notes like 'fixture T398%' and c.deleted_at is null
                  and x.first_visit_on between '2026-10-03' and '2026-10-04') or n_rng = 0 then
    raise exception 'FAIL 6: the first-visit range found %', n_rng; end if;
  if exists (select 1 from public.search_customers('fixture T398', null, 1000, 0, null, '2026-10-05', null) where first_visit_on < '2026-10-05' or first_visit_on is null)
     or exists (select 1 from public.search_customers('fixture T398', null, 1000, 0, null, null, '2026-10-03') where first_visit_on > '2026-10-03' or first_visit_on is null) then
    raise exception 'FAIL 6: an open-ended range let the wrong customers in'; end if;
  -- The page now live passes four named arguments; the total is still on every row.
  select count(*) into n from public.search_customers(p_query => 'fixture T398', p_source => null, p_limit => 3, p_offset => 0);
  if n <> 3 or (select total_count from public.search_customers(p_query => 'fixture T398', p_source => null, p_limit => 3, p_offset => 0) limit 1) <> n_all then
    raise exception 'FAIL 6: the four-argument call (the page now live) no longer pages'; end if;
  if (select total_count from public.search_customers('fixture T398', null, 2, 0, 'visited') limit 1) <> n_vis then
    raise exception 'FAIL 6: total_count does not follow the Visited filter'; end if;
  -- Only staff logins get rows (the customers table's own read policy).
  perform pg_temp.t398_as('aff_login');
  if exists (select 1 from public.search_customers('fixture T398', null, 1000, 0)) then
    raise exception 'FAIL 6: a login with no staff role got customers'; end if;
  raise notice 'PASS 6: search_customers filters Visited / Not visited / All and the first visit date (both ends included), returns the first visit date, pages and counts as before with four arguments, and gives a login with no staff role nothing';
end $$;

-- ===== 7. The October promotion: who counts (404: by the first visit) =====
do $$
declare f record; n int;
begin
  perform pg_temp.t398_as('owner');
  -- Fay Lum, an affiliate with a portal login, referred:
  perform pg_temp.t398_customer('oct_ref', 'Fay Lum', '+6591398050');
  with x as (insert into public.customer_affiliates(customer_id, store_id, status, activated_at, referral_code)
               values (pg_temp.t398_id('oct_ref'), pg_temp.t398_id('store'), 'active', now(), 'T398FAY') returning id)
    insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
    select pg_temp.t398_id('aff_login'), pg_temp.t398_id('oct_ref'), id, 'claimed' from x;
  -- Count: a first visit in October, referred by 31 Oct (Singapore time).
  -- (a) referred in October (3 Oct 23:30 Singapore is still the 3rd), visited in October.
  perform pg_temp.t398_customer('o_yes', 'Gia Lo', '+6591398051', 'oct_ref', '2026-10-03 15:30+00');
  perform pg_temp.t398_link_survey('o_yes', 'link_centre', '2026-10-05 02:00+00', '2026-10-05');
  -- (b) referred on 30 Sep at 23:00 Singapore (15:00 UTC), first visit in October.
  perform pg_temp.t398_customer('o_sep', 'Hui Ma', '+6591398052', 'oct_ref', '2026-09-30 15:00+00');
  perform pg_temp.t398_link_survey('o_sep', 'link_centre', '2026-10-02 02:00+00', '2026-10-02');
  -- (c) referred in August, first visit (a consultant's) in October.
  perform pg_temp.t398_customer('o_aug', 'Uri Lee', '+6591398064', 'oct_ref', '2026-08-14 02:00+00');
  perform pg_temp.t398_consultant('o_aug', '2026-10-09 02:00+00', $s$remarks_condition = 'Hip'$s$);
  -- (d) first visit on 2 Oct, referred afterwards (10 Oct), both in October.
  perform pg_temp.t398_customer('o_after', 'Vic Tan', '+6591398065', 'oct_ref', '2026-10-10 02:00+00');
  perform pg_temp.t398_link_survey('o_after', 'link_centre', '2026-10-02 03:00+00', '2026-10-02');
  -- (e) an older link with no date, created in October, visited in October (created_at).
  perform pg_temp.t398_customer('o_nodate', 'Kit Au', '+6591398055', 'oct_ref', 'none', '2026-10-06 02:00+00');
  perform pg_temp.t398_consultant('o_nodate', '2026-10-07 02:00+00', $s$remarks_condition = 'Neck'$s$);
  -- (f) an older link with no date, created in September, first visit in October.
  perform pg_temp.t398_customer('o_olddate', 'Lou Ang', '+6591398056', 'oct_ref', 'none', '2026-09-06 02:00+00');
  perform pg_temp.t398_link_survey('o_olddate', 'link_centre', '2026-10-07 02:00+00', '2026-10-07');
  -- (g) visited on 31 Oct at 23:59 Singapore (the window is Singapore time).
  perform pg_temp.t398_customer('o_last', 'Pam Ee', '+6591398060', 'oct_ref', '2026-10-31 15:00+00');
  perform pg_temp.t398_link_survey('o_last', 'link_centre', '2026-10-31 15:59+00', null);
  -- (h) referred on the window's last day, 31 Oct at 23:30 Singapore, after a visit on 20 Oct.
  perform pg_temp.t398_customer('o_edge', 'Wan Ho', '+6591398066', 'oct_ref', '2026-10-31 15:30+00');
  perform pg_temp.t398_link_survey('o_edge', 'link_centre', '2026-10-20 02:00+00', '2026-10-20');
  -- Listed, not counted: referred in October, no first visit yet.
  -- (i) no survey at all;
  perform pg_temp.t398_customer('o_none', 'Xia Ong', '+6591398067', 'oct_ref', '2026-10-10 02:00+00');
  -- (j) surveyed through an event's link only (not a visit);
  perform pg_temp.t398_customer('o_event', 'Max Ow', '+6591398057', 'oct_ref', '2026-10-08 02:00+00');
  perform pg_temp.t398_link_survey('o_event', 'link_event', '2026-10-09 02:00+00', '2026-10-09');
  -- (k) only the Surveys page's empty record;
  perform pg_temp.t398_customer('o_empty', 'Ned Bo', '+6591398058', 'oct_ref', '2026-10-08 02:00+00');
  perform pg_temp.t398_consultant('o_empty', '2026-10-09 02:00+00');
  -- (l) an older link with no date, created in October.
  perform pg_temp.t398_customer('o_nodate_wait', 'Yus Lai', '+6591398068', 'oct_ref', 'none', '2026-10-12 02:00+00');
  -- Not listed:
  -- (m) referred in October, first visit in November;
  perform pg_temp.t398_customer('o_nov', 'Ian Su', '+6591398053', 'oct_ref', '2026-10-10 02:00+00');
  perform pg_temp.t398_link_survey('o_nov', 'link_centre', '2026-11-02 02:00+00', '2026-11-02');
  -- (n) referred in October, but first visited in September;
  perform pg_temp.t398_customer('o_before', 'Jo Yee', '+6591398054', 'oct_ref', '2026-10-04 02:00+00');
  perform pg_temp.t398_link_survey('o_before', 'link_centre', '2026-09-20 02:00+00', '2026-09-20');
  -- (o) first visit in October, but the referrer set on 1 Nov at 00:30 Singapore (16:30 UTC on 31 Oct);
  perform pg_temp.t398_customer('o_late_ref', 'Zac Chia', '+6591398069', 'oct_ref', '2026-10-31 16:30+00');
  perform pg_temp.t398_link_survey('o_late_ref', 'link_centre', '2026-10-06 02:00+00', '2026-10-06');
  -- (p) an older link with no date, created in November, no visit;
  perform pg_temp.t398_customer('o_nodate_nov', 'Abe Loh', '+6591398072', 'oct_ref', 'none', '2026-11-02 02:00+00');
  -- (q) referred in September, no visit;
  perform pg_temp.t398_customer('o_old_wait', 'Bea Kwa', '+6591398073', 'oct_ref', '2026-09-20 02:00+00');
  -- (r) deleted, though referred and visited in October.
  perform pg_temp.t398_customer('o_deleted', 'Cas Yeo', '+6591398074', 'oct_ref', '2026-10-05 02:00+00');
  perform pg_temp.t398_link_survey('o_deleted', 'link_centre', '2026-10-06 02:00+00', '2026-10-06');
  update public.customers set deleted_at = now() where id = pg_temp.t398_id('o_deleted');
  -- (s) Gia's friend (Fay's Tier 2), referred and visited in October: counts for Gia, not for Fay.
  perform pg_temp.t398_customer('o_t2', 'Oli Ting', '+6591398059', 'o_yes', '2026-10-11 02:00+00');
  perform pg_temp.t398_link_survey('o_t2', 'link_centre', '2026-10-12 02:00+00', '2026-10-12');
  -- Hal Ong, a plain customer, referred two friends in October whose
  -- consultant records the Surveys page made before the consultation:
  -- (t) referred 25 Oct, record made 28 Oct, answered (Save Review) 3 Nov:
  -- the first visit is 3 Nov, so she is not listed;
  perform pg_temp.t398_customer('oct_ref2', 'Hal Ong', '+6591398061');
  perform pg_temp.t398_customer('o_late', 'Qi Lam', '+6591398062', 'oct_ref2', '2026-10-25 02:00+00');
  perform pg_temp.t398_consultant('o_late', '2026-10-28 02:00+00');
  perform public.review_health_survey(p_survey_id => pg_temp.t398_id('survey_o_late'), p_acidity => 'red',
    p_health_goals => null, p_condition => 'Back pain', p_recommendation => null);
  update public.audit_logs set created_at = '2026-11-03 03:00+00'
   where record_id = pg_temp.t398_id('survey_o_late') and action = 'health_survey_reviewed';
  -- (u) record made 20 Sep (opened, left empty), referred 5 Oct, answered 10 Oct: the first visit is 10 Oct, so he counts.
  perform pg_temp.t398_customer('o_reopen', 'Rex Poh', '+6591398063', 'oct_ref2', '2026-10-05 02:00+00');
  perform pg_temp.t398_consultant('o_reopen', '2026-09-20 02:00+00');
  perform public.review_health_survey(p_survey_id => pg_temp.t398_id('survey_o_reopen'), p_acidity => 'green',
    p_health_goals => 'More energy', p_condition => null, p_recommendation => null);
  update public.audit_logs set created_at = '2026-10-10 03:00+00'
   where record_id = pg_temp.t398_id('survey_o_reopen') and action = 'health_survey_reviewed';
  -- Ivy Wong's one friend, referred in October, has not visited yet.
  perform pg_temp.t398_customer('oct_ref3', 'Ivy Wong', '+6591398075');
  perform pg_temp.t398_customer('o_wait', 'Dan Ng', '+6591398076', 'oct_ref3', '2026-10-15 02:00+00');
  -- Jon Hew's one friend, referred in October, first visited in September.
  perform pg_temp.t398_customer('oct_ref4', 'Jon Hew', '+6591398077');
  perform pg_temp.t398_customer('o_prior', 'Eli Soo', '+6591398078', 'oct_ref4', '2026-10-05 02:00+00');
  perform pg_temp.t398_link_survey('o_prior', 'link_centre', '2026-09-15 02:00+00', '2026-09-15');
  -- Kim Soh, deleted, referred a friend who visited in October.
  perform pg_temp.t398_customer('oct_ref5', 'Kim Soh', '+6591398079');
  perform pg_temp.t398_customer('o_kimf', 'Fin Lau', '+6591398080', 'oct_ref5', '2026-10-05 02:00+00');
  perform pg_temp.t398_link_survey('o_kimf', 'link_centre', '2026-10-06 02:00+00', '2026-10-06');
  update public.customers set deleted_at = now() where id = pg_temp.t398_id('oct_ref5');

  create temp table t398_oct as
    select x.* from public.referral_campaign_friends((select id from public.referral_campaigns where code = '2026-10')) x;
  for f in select * from (values
             ('o_yes', 'counts'), ('o_sep', 'counts'), ('o_aug', 'counts'), ('o_after', 'counts'),
             ('o_nodate', 'counts'), ('o_olddate', 'counts'), ('o_last', 'counts'), ('o_edge', 'counts'),
             ('o_none', 'waits'), ('o_event', 'waits'), ('o_empty', 'waits'), ('o_nodate_wait', 'waits'),
             ('o_nov', 'absent'), ('o_before', 'absent'), ('o_late_ref', 'absent'), ('o_nodate_nov', 'absent'),
             ('o_old_wait', 'absent'), ('o_deleted', 'absent')) x(k, expect) loop
    if f.expect = 'absent' then
      if exists (select 1 from t398_oct where friend_customer_id = pg_temp.t398_id(f.k)) then
        raise exception 'FAIL 7: % should not be listed', f.k; end if;
    elsif not exists (select 1 from t398_oct where friend_customer_id = pg_temp.t398_id(f.k)
                        and referrer_customer_id = pg_temp.t398_id('oct_ref')
                        and counted = (f.expect = 'counts')
                        and (f.expect = 'counts') = (first_visit_on is not null)) then
      raise exception 'FAIL 7: % should be listed for Fay and % (%)', f.k,
        case when f.expect = 'counts' then 'count' else 'not count, not yet visited' end,
        (select row_to_json(t)::text from t398_oct t where friend_customer_id = pg_temp.t398_id(f.k)); end if;
  end loop;
  if (select count(*) from t398_oct where referrer_customer_id = pg_temp.t398_id('oct_ref') and counted) <> 8
     or (select count(*) from t398_oct where referrer_customer_id = pg_temp.t398_id('oct_ref')) <> 12 then
    raise exception 'FAIL 7: Fay should have 8 friends counted of 12 listed, has % of %',
      (select count(*) from t398_oct where referrer_customer_id = pg_temp.t398_id('oct_ref') and counted),
      (select count(*) from t398_oct where referrer_customer_id = pg_temp.t398_id('oct_ref')); end if;
  -- referred_on is the referral's own Singapore date, before the window too; else the creation's.
  if (select referred_on from t398_oct where friend_customer_id = pg_temp.t398_id('o_aug')) is distinct from '2026-08-14'
     or (select referred_on from t398_oct where friend_customer_id = pg_temp.t398_id('o_sep')) is distinct from '2026-09-30'
     or (select referred_on from t398_oct where friend_customer_id = pg_temp.t398_id('o_olddate')) is distinct from '2026-09-06'
     or (select referred_on from t398_oct where friend_customer_id = pg_temp.t398_id('o_nodate_wait')) is distinct from '2026-10-12'
     or (select referred_on from t398_oct where friend_customer_id = pg_temp.t398_id('o_edge')) is distinct from '2026-10-31'
     or (select first_visit_on from t398_oct where friend_customer_id = pg_temp.t398_id('o_after')) is distinct from '2026-10-02' then
    raise exception 'FAIL 7: a referral or first visit date is wrong'; end if;
  -- Every row anywhere is one of the two kinds: counted (first visit in the
  -- window, referred by its end) or not yet visited (referred in it, no visit).
  if exists (select 1 from t398_oct where not (
               (counted and first_visit_on between '2026-10-01' and '2026-10-31' and referred_on <= '2026-10-31')
               or (not counted and first_visit_on is null and referred_on between '2026-10-01' and '2026-10-31'))) then
    raise exception 'FAIL 7: a row is neither a friend who counts nor one referred in the window not yet visited'; end if;
  if (select referrer_customer_id from t398_oct where friend_customer_id = pg_temp.t398_id('o_t2'))
     is distinct from pg_temp.t398_id('o_yes')
     or not (select counted from t398_oct where friend_customer_id = pg_temp.t398_id('o_t2')) then
    raise exception 'FAIL 7: a Tier 2 friend counted for the wrong referrer'; end if;
  if pg_temp.t398_visit('o_late') is distinct from '2026-11-03'
     or exists (select 1 from t398_oct where friend_customer_id = pg_temp.t398_id('o_late')) then
    raise exception 'FAIL 7: a record made in October but answered in November is listed for October'; end if;
  if (select first_visit_on from t398_oct where friend_customer_id = pg_temp.t398_id('o_reopen')) is distinct from '2026-10-10'
     or not (select counted from t398_oct where friend_customer_id = pg_temp.t398_id('o_reopen')) then
    raise exception 'FAIL 7: a record made empty in September and answered in October did not count'; end if;
  if (select count(*) from t398_oct where referrer_customer_id = pg_temp.t398_id('oct_ref3') and not counted) <> 1
     or (select count(*) from t398_oct where referrer_customer_id = pg_temp.t398_id('oct_ref3')) <> 1
     or exists (select 1 from t398_oct where referrer_customer_id in (pg_temp.t398_id('oct_ref4'), pg_temp.t398_id('oct_ref5'))) then
    raise exception 'FAIL 7: Ivy''s friend not yet visited, Jon''s friend who visited before, or a deleted referrer''s friend is wrong'; end if;
  raise notice 'PASS 7: a friend counts when their first visit is within 1-31 Oct (Singapore time), whether referred in August, September, before or after that visit, or on 31 Oct, older links by created_at; friends referred in October with no visit (none, an event''s link, an empty record) are listed, not counted; a first visit before or after October, a referral after it, one before it with no visit, a deleted friend or referrer are not listed; a Tier 2 friend counts for their own referrer; a consultant''s record counts by the day it was answered';
end $$;

-- ===== 8. Tiers: the highest reached only =====
do $$
declare x record;
begin
  for x in select * from (values (0, null, 10, 10), (9, null, 10, 1), (10, 10, 20, 10), (19, 10, 20, 1),
                                 (20, 20, 50, 30), (55, 50, 80, 25), (80, 80, null, null), (120, 80, null, null))
             v(cnt, reached, nxt, tonext) loop
    if (public.referral_campaign_standing('{10,20,50,80}', x.cnt)->>'tier_reached')::int is distinct from x.reached
       or (public.referral_campaign_standing('{10,20,50,80}', x.cnt)->>'next_tier')::int is distinct from x.nxt
       or (public.referral_campaign_standing('{10,20,50,80}', x.cnt)->>'to_next')::int is distinct from x.tonext then
      raise exception 'FAIL 8: % friends stand at %', x.cnt, public.referral_campaign_standing('{10,20,50,80}', x.cnt); end if;
  end loop;
  raise notice 'PASS 8: the tier reached is the highest at or below the count; the next tier and how many more';
end $$;


-- ===== 9. The report (Owner/Manager), provisional until the window ends =====
do $$
declare r jsonb; fr jsonb;
begin
  perform pg_temp.t398_as('manager');
  r := public.referral_campaign_report('2026-10');
  if r->'campaign'->>'status' <> (case when public.sg_today() > '2026-10-31' then 'final'
                                       when public.sg_today() < '2026-10-01' then 'not_started' else 'provisional' end) then
    raise exception 'FAIL 9: the report''s status is %', r->'campaign'->>'status'; end if;
  if r->'campaign'->'tiers' <> '[10,20,50,80]'::jsonb then raise exception 'FAIL 9: tiers %', r->'campaign'->'tiers'; end if;
  select e into fr from jsonb_array_elements(r->'referrers') e where e->>'referrer_customer_id' = pg_temp.t398_id('oct_ref')::text;
  -- Fay: 8 counted, 4 referred in October not yet visited; 9 of the friends
  -- listed were referred in October (referred_in_window, kept for the page
  -- before 404); tier 10 is 2 away.
  if fr is null or (fr->>'counted')::int is distinct from 8 or (fr->>'not_yet_visited')::int is distinct from 4
     or (fr->>'referred_in_window')::int is distinct from 9 or fr->'tier_reached' is distinct from 'null'::jsonb
     or (fr->>'next_tier')::int is distinct from 10 or (fr->>'to_next')::int is distinct from 2
     or (fr->>'is_affiliate')::boolean is not true or fr->'reward' is distinct from 'null'::jsonb then
    raise exception 'FAIL 9: Fay''s row is wrong: %', fr - 'friends'; end if;
  -- The drill-down: the friends listed, the counted ones first.
  if jsonb_array_length(fr->'friends') <> 12
     or (select count(*) from jsonb_array_elements(fr->'friends') e where (e->>'counted')::boolean) <> 8
     or (select count(*) from jsonb_array_elements(fr->'friends') e
          where not (e->>'counted')::boolean and e->'first_visit_on' = 'null'::jsonb) <> 4
     or exists (select 1 from jsonb_array_elements(fr->'friends') with ordinality e(x, i)
                 where (x->>'counted')::boolean is not true and i <= 8)
     or not exists (select 1 from jsonb_array_elements(fr->'friends') e where e->>'name' = 'Kit Au'
                      and e->>'referred_on' = '2026-10-06' and e->>'first_visit_on' = '2026-10-07' and (e->>'counted')::boolean)
     or not exists (select 1 from jsonb_array_elements(fr->'friends') e where e->>'name' = 'Uri Lee'
                      and e->>'referred_on' = '2026-08-14' and e->>'first_visit_on' = '2026-10-09' and (e->>'counted')::boolean)
     or not exists (select 1 from jsonb_array_elements(fr->'friends') e where e->>'name' = 'Xia Ong'
                      and e->>'referred_on' = '2026-10-10' and e->'first_visit_on' = 'null'::jsonb and not (e->>'counted')::boolean)
     or exists (select 1 from jsonb_array_elements(fr->'friends') e
                 where e->>'name' in ('Ian Su', 'Jo Yee', 'Zac Chia', 'Abe Loh', 'Bea Kwa', 'Cas Yeo', 'Oli Ting')) then
    raise exception 'FAIL 9: Fay''s friends are wrong: %', fr->'friends'; end if;
  -- Gia, a plain customer, is in it with her one friend.
  if not exists (select 1 from jsonb_array_elements(r->'referrers') e
                  where e->>'referrer_customer_id' = pg_temp.t398_id('o_yes')::text and (e->>'counted')::int = 1
                    and (e->>'not_yet_visited')::int = 0 and not (e->>'is_affiliate')::boolean) then
    raise exception 'FAIL 9: a plain customer''s friends are not reported'; end if;
  -- Ivy, whose one friend has not visited yet, is listed with none counted;
  -- Jon (his friend visited before October) and Kim (deleted) are not.
  if not exists (select 1 from jsonb_array_elements(r->'referrers') e
                  where e->>'referrer_customer_id' = pg_temp.t398_id('oct_ref3')::text and (e->>'counted')::int = 0
                    and (e->>'not_yet_visited')::int = 1 and e->'tier_reached' = 'null'::jsonb
                    and (e->>'to_next')::int = 10 and jsonb_array_length(e->'friends') = 1) then
    raise exception 'FAIL 9: a referrer whose only friend has not visited yet is not listed with 0 counted'; end if;
  if exists (select 1 from jsonb_array_elements(r->'referrers') e
              where e->>'referrer_customer_id' in (pg_temp.t398_id('oct_ref4')::text, pg_temp.t398_id('oct_ref5')::text)) then
    raise exception 'FAIL 9: a referrer with no friend listed is in the report'; end if;
  -- Every referrer listed has a friend listed, and its figures are its friends'.
  if exists (select 1 from jsonb_array_elements(r->'referrers') e
              where jsonb_array_length(e->'friends') = 0
                 or (e->>'counted')::int is distinct from
                      (select count(*) from jsonb_array_elements(e->'friends') x where (x->>'counted')::boolean)::int
                 or (e->>'not_yet_visited')::int is distinct from
                      (select count(*) from jsonb_array_elements(e->'friends') x where x->'first_visit_on' = 'null'::jsonb)::int
                 or (e->>'counted')::int + (e->>'not_yet_visited')::int is distinct from jsonb_array_length(e->'friends')) then
    raise exception 'FAIL 9: a referrer''s figures do not match their friends'; end if;
  -- No code: the latest promotion that has started.
  perform pg_temp.t398_as('owner');
  if (public.referral_campaign_report(null)->'campaign'->>'code') <>
     (select code from public.referral_campaigns where starts_on <= public.sg_today() order by starts_on desc limit 1) then
    raise exception 'FAIL 9: the default promotion is not the latest started'; end if;
  perform pg_temp.t398_refused('9 unknown', $q$select public.referral_campaign_report('no-such-code')$q$, 'not found');
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_refused('9 staff', $q$select public.referral_campaign_report('2026-10')$q$, 'Only an Owner or Manager');
  perform pg_temp.t398_as('admin');
  perform pg_temp.t398_refused('9 admin', $q$select public.referral_campaign_report('2026-10')$q$, 'Only an Owner or Manager');
  perform pg_temp.t398_as('aff_login');
  perform pg_temp.t398_refused('9 affiliate', $q$select public.referral_campaign_report('2026-10')$q$, 'Only an Owner or Manager');
  raise notice 'PASS 9: the report gives friends counted, friends not yet visited, tier reached and next tier, and the friends listed (counted first, referred before October too), plain customers and a referrer whose friend has not visited yet included, nobody without a friend listed; provisional until 31 Oct; staff, Admin and affiliate logins are refused';
end $$;

-- ===== 10. The reward: after the window, the highest tier, once, out of a store's stock =====
do $$
declare c uuid; k int; r jsonb; v_reward uuid; n_uses int; n_moves int;
  items jsonb; b jsonb;
begin
  perform pg_temp.t398_as('owner');
  -- A promotion that has ended (September), tiers 10 and 20.
  insert into public.referral_campaigns(code, title, reward_reason, starts_on, ends_on, tiers)
  values ('T398-SEP', 'Fixture September promotion', 'Fixture September reward', '2026-09-01', '2026-09-30', '{10,20}')
  returning id into c;
  -- Bob Lim's friends whose first visit was in September (404): 7 referred
  -- in September and 3 in August, so 10 count (398 counted 7, below the
  -- first tier). Not counted: one referred in September who has not visited,
  -- one whose referrer was set on 1 Oct, after the window, and one referred
  -- in September who first visited in August.
  perform pg_temp.t398_customer('sep_ref', 'Bob Lim', '+6591398070');
  for k in 1 .. 10 loop
    perform pg_temp.t398_customer('sep_f' || k, 'Fixture Friend ' || k, '+65913981' || lpad(k::text, 2, '0'),
                                  'sep_ref', case when k <= 7 then '2026-09-0' || k else '2026-08-2' || k - 7 end || ' 02:00+00');
    perform pg_temp.t398_link_survey('sep_f' || k, 'link_centre', '2026-09-15 02:00+00', '2026-09-15');
  end loop;
  perform pg_temp.t398_customer('sep_f11', 'Fixture Friend 11', '+6591398111', 'sep_ref', '2026-09-12 02:00+00');
  perform pg_temp.t398_customer('sep_late', 'Fixture Late Referral', '+6591398121', 'sep_ref', '2026-10-01 02:00+00');
  perform pg_temp.t398_link_survey('sep_late', 'link_centre', '2026-09-17 02:00+00', '2026-09-17');
  perform pg_temp.t398_customer('sep_prev', 'Fixture Earlier Visit', '+6591398122', 'sep_ref', '2026-09-10 02:00+00');
  perform pg_temp.t398_link_survey('sep_prev', 'link_centre', '2026-08-20 02:00+00', '2026-08-20');
  -- Cy Ong: 9 friends who first visited in September, below the first tier;
  -- a tenth, referred in September, first visited in October.
  perform pg_temp.t398_customer('sep_low', 'Cy Ong', '+6591398071');
  for k in 1 .. 9 loop
    perform pg_temp.t398_customer('sep_l' || k, 'Fixture Low ' || k, '+65913982' || lpad(k::text, 2, '0'),
                                  'sep_low', '2026-09-0' || k || ' 02:00+00');
    perform pg_temp.t398_link_survey('sep_l' || k, 'link_centre', '2026-09-16 02:00+00', '2026-09-16');
  end loop;
  perform pg_temp.t398_customer('sep_l10', 'Fixture Low 10', '+6591398210', 'sep_low', '2026-09-10 02:00+00');
  perform pg_temp.t398_link_survey('sep_l10', 'link_centre', '2026-10-05 02:00+00', '2026-10-05');
  items := jsonb_build_array(jsonb_build_object('product_id', pg_temp.t398_id('gift'), 'quantity', 2),
                             jsonb_build_object('product_id', pg_temp.t398_id('bottle'), 'quantity', 1));
  execute format('create temp table t398_items as select %L::jsonb as items', items);

  -- Before the window ends (October, today): refused.
  if public.sg_today() <= '2026-10-31' then
    perform pg_temp.t398_refused('10 before the end', format(
      'select public.give_referral_campaign_reward(%L, %L, %L, (select items from t398_items), null)',
      '2026-10', pg_temp.t398_id('oct_ref'), pg_temp.t398_id('store')), 'Its rewards are given after it ends');
  end if;
  -- Below the first tier: refused.
  perform pg_temp.t398_refused('10 below', format(
    'select public.give_referral_campaign_reward(%L, %L, %L, (select items from t398_items), null)',
    'T398-SEP', pg_temp.t398_id('sep_low'), pg_temp.t398_id('store')), 'fewer than the first tier (10)');
  -- Staff and affiliate logins: refused.
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_refused('10 staff', format(
    'select public.give_referral_campaign_reward(%L, %L, %L, (select items from t398_items), null)',
    'T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store')), 'Only an Owner or Manager');
  perform pg_temp.t398_as('aff_login');
  perform pg_temp.t398_refused('10 affiliate', format(
    'select public.give_referral_campaign_reward(%L, %L, %L, (select items from t398_items), null)',
    'T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store')), 'Only an Owner or Manager');
  -- A Manager without that store: refused by record_stock_use, and nothing is kept.
  perform pg_temp.t398_as('manager');
  perform pg_temp.t398_refused('10 store access', format(
    'select public.give_referral_campaign_reward(%L, %L, %L, (select items from t398_items), null)',
    'T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store')), 'No access to this store');
  -- More than the store holds: refused, and nothing is kept.
  perform pg_temp.t398_as('owner');
  perform pg_temp.t398_refused('10 stock', format(
    'select public.give_referral_campaign_reward(%L, %L, %L, %L::jsonb, null)', 'T398-SEP', pg_temp.t398_id('sep_ref'),
    pg_temp.t398_id('store'), jsonb_build_array(jsonb_build_object('product_id', pg_temp.t398_id('gift'), 'quantity', 1),
                                                jsonb_build_object('product_id', pg_temp.t398_id('bottle'), 'quantity', 3))),
    'in stock at this store');
  -- Bad lines: refused.
  perform pg_temp.t398_refused('10 no lines', format('select public.give_referral_campaign_reward(%L, %L, %L, %L::jsonb, null)',
    'T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store'), '[]'), 'at least one product');
  perform pg_temp.t398_refused('10 zero', format('select public.give_referral_campaign_reward(%L, %L, %L, %L::jsonb, null)',
    'T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store'),
    jsonb_build_array(jsonb_build_object('product_id', pg_temp.t398_id('gift'), 'quantity', 0))), 'at least 1');
  perform pg_temp.t398_refused('10 twice', format('select public.give_referral_campaign_reward(%L, %L, %L, %L::jsonb, null)',
    'T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store'),
    jsonb_build_array(jsonb_build_object('product_id', pg_temp.t398_id('gift'), 'quantity', 1),
                      jsonb_build_object('product_id', pg_temp.t398_id('gift'), 'quantity', 1))), 'one line only');
  perform pg_temp.t398_refused('10 no store', format('select public.give_referral_campaign_reward(%L, %L, null, (select items from t398_items), null)',
    'T398-SEP', pg_temp.t398_id('sep_ref')), 'Choose the store');
  if exists (select 1 from public.referral_campaign_rewards where campaign_id = c)
     or exists (select 1 from public.stock_uses where reason like 'Fixture September reward%')
     or (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('gift')) <> 5
     or (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('bottle')) <> 2 then
    raise exception 'FAIL 10: a refused reward left something behind'; end if;

  -- Given, by the Owner: tier 10 (the highest reached), 2 gift sets and a bottle out of the store, once.
  r := public.give_referral_campaign_reward('T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store'),
                                            items, 'Handed over at the counter');
  v_reward := (r->>'reward_id')::uuid;
  if (r->>'tier')::int <> 10 or (r->>'friends_counted')::int <> 10 then
    raise exception 'FAIL 10: the reward is %', r; end if;
  if (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('gift')) <> 3
     or (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('bottle')) <> 1 then
    raise exception 'FAIL 10: the stock was not taken out once'; end if;
  select count(*) into n_uses from public.stock_uses
   where reason = 'Fixture September reward — Bob Lim' and store_id = pg_temp.t398_id('store') and location_type = 'store'
     and note = 'Handed over at the counter' and used_by = pg_temp.t398_id('owner');
  if n_uses <> 2 then raise exception 'FAIL 10: % stock uses, not 2', n_uses; end if;
  if (select count(*) from public.referral_campaign_reward_items i join public.stock_uses u on u.id = i.stock_use_id
       where i.reward_id = v_reward and u.product_id = i.product_id and u.quantity = i.quantity) <> 2
     or not exists (select 1 from public.referral_campaign_rewards where id = v_reward and campaign_id = c and tier = 10
                      and friends_counted = 10 and store_id = pg_temp.t398_id('store') and given_by = pg_temp.t398_id('owner')
                      and note = 'Handed over at the counter' and voided_at is null)
     or not exists (select 1 from public.audit_logs where record_id = v_reward and action = 'referral_reward_given') then
    raise exception 'FAIL 10: the reward is not recorded with its products, stock uses and audit'; end if;
  -- A second reward for the same referrer and promotion: refused, stock unchanged.
  perform pg_temp.t398_refused('10 second', format(
    'select public.give_referral_campaign_reward(%L, %L, %L, (select items from t398_items), null)',
    'T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store')), 'already has a reward');
  if (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('gift')) <> 3 then
    raise exception 'FAIL 10: a refused second reward took stock'; end if;
  -- The report shows it, with the count and tier it was given for.
  select e into b from jsonb_array_elements(public.referral_campaign_report('T398-SEP')->'referrers') e
   where e->>'referrer_customer_id' = pg_temp.t398_id('sep_ref')::text;
  if b->'reward'->>'tier' is distinct from '10' or (b->>'counted')::int is distinct from 10
     or (b->>'not_yet_visited')::int is distinct from 1 or (b->>'tier_reached')::int is distinct from 10
     or (select (e->>'counted')::int from jsonb_array_elements(public.referral_campaign_report('T398-SEP')->'referrers') e
          where e->>'referrer_customer_id' = pg_temp.t398_id('sep_low')::text) is distinct from 9
     or public.referral_campaign_report('T398-SEP')->'campaign'->>'status' <> 'final' then
    raise exception 'FAIL 10: the report does not show the reward, the counts (10 counted and 1 not visited for Bob, 9 for Cy) or the final status'; end if;

  -- Undo: the Owner alone, with a reason; the products go back.
  perform pg_temp.t398_as('manager2');
  perform pg_temp.t398_refused('10 undo manager', format('select public.void_referral_campaign_reward(%L, %L)', v_reward, 'Wrong'),
    'Only the Owner');
  perform pg_temp.t398_as('owner');
  perform pg_temp.t398_refused('10 undo reason', format('select public.void_referral_campaign_reward(%L, %L)', v_reward, ' '),
    'A reason is required');
  r := public.void_referral_campaign_reward(v_reward, 'Fixture: wrong products');
  select count(*) into n_moves from public.stock_movements
   where to_store_id = pg_temp.t398_id('store') and notes like 'Referral reward undone — %(Fixture: wrong products)';
  if (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('gift')) <> 5
     or (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('bottle')) <> 2
     or n_moves <> 2
     or not exists (select 1 from public.referral_campaign_rewards where id = v_reward and voided_at is not null
                      and voided_by = pg_temp.t398_id('owner') and void_reason = 'Fixture: wrong products' and stock_put_back) then
    raise exception 'FAIL 10: undoing did not put the stock back once and keep the reward marked undone'; end if;
  perform pg_temp.t398_refused('10 undo twice', format('select public.void_referral_campaign_reward(%L, %L)', v_reward, 'Again'),
    'already undone');
  -- Marked again, correctly, by a Manager of the store: one active reward.
  perform pg_temp.t398_as('manager2');
  r := public.give_referral_campaign_reward('T398-SEP', pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store'),
         jsonb_build_array(jsonb_build_object('product_id', pg_temp.t398_id('gift'), 'quantity', 1)), null);
  if (select count(*) from public.referral_campaign_rewards where campaign_id = c and referrer_customer_id = pg_temp.t398_id('sep_ref')
        and voided_at is null) <> 1
     or (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('gift')) <> 4 then
    raise exception 'FAIL 10: the reward could not be marked again after it was undone'; end if;
  -- Undone without putting stock back (the products did leave): stock stays.
  perform pg_temp.t398_as('owner');
  perform public.void_referral_campaign_reward((r->>'reward_id')::uuid, 'Fixture: given, recorded twice', false);
  if (select current_qty from public.store_inventory where store_id = pg_temp.t398_id('store') and product_id = pg_temp.t398_id('gift')) <> 4 then
    raise exception 'FAIL 10: undoing without putting back changed stock'; end if;
  raise notice 'PASS 10: the reward follows the first-visit count (friends referred before the window count; one referred after it, one who visited before it or after it do not); a reward is refused before the window ends, below the first tier, to staff, affiliate logins and a Manager without the store, beyond the stock and for bad lines, leaving nothing; given, it records tier 10 and takes each product out once as a stock use; a second is refused; the Owner alone undoes it, putting stock back or not; it can then be marked again';
end $$;


-- ===== 11. The affiliate portal: own progress only =====
do $$
declare r jsonb;
begin
  -- Fay's portal login sees her own counts (404: 8 counted by the first
  -- visit, 4 referred in October not yet visited) and the next tier.
  perform pg_temp.t398_as('aff_login');
  r := public.affiliate_portal_campaign_progress();
  if r->'campaign'->>'code' <> (select code from public.referral_campaigns where starts_on <= public.sg_today()
                                  order by starts_on desc limit 1) then
    raise exception 'FAIL 11: the portal shows %', r->'campaign'; end if;
  if r->'campaign'->>'code' = '2026-10' and ((r->>'counted')::int is distinct from 8
       or (r->>'not_yet_visited')::int is distinct from 4 or (r->>'referred_in_window')::int is distinct from 9
       or (r->>'next_tier')::int is distinct from 10 or (r->>'to_next')::int is distinct from 2
       or r->'tier_reached' is distinct from 'null'::jsonb) then
    raise exception 'FAIL 11: Fay''s progress is %', r; end if;
  -- Counts only: these keys and no others, no names, no phones.
  if (select string_agg(k, ',' order by k) from jsonb_object_keys(r) k)
       <> 'campaign,counted,next_tier,not_yet_visited,referred_in_window,reward_given_at,reward_tier,tier_reached,to_next'
     or r::text like '%Gia Lo%' or r::text like '%Uri Lee%' or r::text like '%Xia Ong%' or r::text like '%+65913980%' then
    raise exception 'FAIL 11: the portal''s progress names people or carries more than counts: %', r; end if;
  -- Bob, another affiliate, sees his own, not Fay's.
  perform pg_temp.t398_as('owner');
  with x as (insert into public.customer_affiliates(customer_id, store_id, status, activated_at, referral_code)
               values (pg_temp.t398_id('sep_ref'), pg_temp.t398_id('store'), 'active', now(), 'T398BOB') returning id)
    insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
    select pg_temp.t398_id('aff_login2'), pg_temp.t398_id('sep_ref'), id, 'claimed' from x;
  perform pg_temp.t398_as('aff_login2');
  r := public.affiliate_portal_campaign_progress();
  if r->'campaign'->>'code' = '2026-10' and ((r->>'counted')::int is distinct from 0
       or (r->>'not_yet_visited')::int is distinct from 0) then
    raise exception 'FAIL 11: another affiliate sees %', r; end if;
  perform pg_temp.t398_as('staff');
  perform pg_temp.t398_refused('11 staff', 'select public.affiliate_portal_campaign_progress()', 'Not an affiliate account');
  raise notice 'PASS 11: an affiliate sees their own friends counted (by the first visit), those not yet visited and the next tier, counts only, no names; another affiliate sees theirs; staff are refused';
end $$;

-- ===== 12. 404: a past customer is neither counted nor listed =====
-- An invoice of p_cust with status p_status, dated p_business (null: an
-- older invoice without a business date, dated by p_created), for p_amount
-- (paid in full when paid), paid at p_paid_at.
create function pg_temp.t404_invoice(p_cust text, p_status text, p_business date, p_created timestamptz default null,
  p_deleted boolean default false, p_amount numeric default 100, p_paid_at timestamptz default null)
  returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount,
                              business_date, created_at, deleted_at, paid_at, notes)
  values ('T404-' || p_cust || '-' || p_status, pg_temp.t398_id('store'), pg_temp.t398_id(p_cust), pg_temp.t398_id('owner'),
          p_status::public.invoice_status, p_amount, p_amount,
          case p_status when 'paid' then p_amount when 'partially_paid' then 40 else 0 end,
          p_business, coalesce(p_created, (p_business + time '10:00') at time zone 'Asia/Singapore'),
          case when p_deleted then now() end, p_paid_at, 'fixture T404')
  returning id into v;
  return v;
end $f$;

do $$
declare f record; r jsonb; pia jsonb; af3 uuid := gen_random_uuid();
begin
  perform pg_temp.t398_as('owner');
  -- Pia Chong, an affiliate with a portal login, referred these friends; each
  -- but the waiting ones first visited the centre in October.
  insert into auth.users(id, email) values (af3, 'aff404@sig.invalid');
  insert into t398 values ('aff_login3', af3);
  perform pg_temp.t398_customer('pc_ref', 'Pia Chong', '+6591398300');
  with x as (insert into public.customer_affiliates(customer_id, store_id, status, activated_at, referral_code)
               values (pg_temp.t398_id('pc_ref'), pg_temp.t398_id('store'), 'active', now(), 'T404PIA') returning id)
    insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
    select af3, pg_temp.t398_id('pc_ref'), id, 'claimed' from x;
  for f in select * from (values
      -- Past customers: not listed.
      ('pc_paid',        'Ali Yeo',  '301', '2026-10-02', '2026-10-05'),  -- paid on 20 Sep
      ('pc_part',        'Bee Ong',  '302', '2026-09-15', '2026-10-06'),  -- part-paid on 25 Sep
      ('pc_nodate',      'Cai Lim',  '303', '2026-10-02', '2026-10-07'),  -- paid, no business date, made 23:59 on 30 Sep in Singapore
      ('pc_wait_paid',   'Dee Tan',  '304', '2026-10-03', null),          -- paid on 10 Aug, not visited yet
      ('pc_foc_paid',    'Rui Ng',   '318', '2026-10-02', '2026-10-09'),  -- FOC on 1 Sep and paid on 2 Sep
      -- The invoice as it is now, by its date and status (header rule 5):
      ('pc_zero',        'Sol Yap',  '319', '2026-10-02', '2026-10-08'),  -- a S$0 invoice marked paid, on 22 Sep
      ('pc_paid_oct',    'Tia Kee',  '320', '2026-10-02', '2026-10-08'),  -- dated 28 Sep, paid on 3 Oct
      -- Not past customers: they count.
      ('pc_cancel',      'Eng Koh',  '305', '2026-10-02', '2026-10-08'),  -- cancelled
      ('pc_refund',      'Fei Goh',  '306', '2026-10-02', '2026-10-08'),  -- refunded
      ('pc_foc',         'Gan Seah', '307', '2026-10-02', '2026-10-08'),  -- FOC
      ('pc_unpaid',      'Hoa Tay',  '308', '2026-10-02', '2026-10-08'),  -- unpaid
      ('pc_draft',       'Ivy Pek',  '309', '2026-10-02', '2026-10-08'),  -- draft
      ('pc_cancel_req',  'Jin Ang',  '310', '2026-10-02', '2026-10-08'),  -- cancellation requested
      ('pc_refund_req',  'Kat Teo',  '311', '2026-10-02', '2026-10-08'),  -- refund requested
      ('pc_deleted',     'Lea Woo',  '312', '2026-10-02', '2026-10-08'),  -- paid, deleted
      ('pc_window',      'Mo Chan',  '313', '2026-08-20', '2026-10-08'),  -- paid on 1 Oct, the window's first day
      ('pc_nodate_oct',  'Nia Low',  '314', '2026-10-02', '2026-10-08'),  -- paid, no business date, made 00:30 on 1 Oct in Singapore
      ('pc_bd_wins',     'Oz Kwek',  '315', '2026-10-02', '2026-10-08'),  -- paid, dated 1 Oct, made 20 Sep
      -- Not a past customer, not visited yet: listed, not counted.
      ('pc_wait_cancel', 'Pam Sim',  '316', '2026-10-04', null)           -- cancelled on 5 Sep
    ) x(k, name, ph, referred, visit) loop
    perform pg_temp.t398_customer(f.k, f.name, '+6591398' || f.ph, 'pc_ref', f.referred || ' 02:00+00');
    if f.visit is not null then
      perform pg_temp.t398_link_survey(f.k, 'link_centre', (f.visit || ' 02:00+00')::timestamptz, f.visit::date);
    end if;
  end loop;
  perform pg_temp.t404_invoice('pc_paid', 'paid', '2026-09-20');
  perform pg_temp.t404_invoice('pc_part', 'partially_paid', '2026-09-25');
  perform pg_temp.t404_invoice('pc_nodate', 'paid', null, '2026-09-30 15:59+00');
  perform pg_temp.t404_invoice('pc_wait_paid', 'paid', '2026-08-10');
  perform pg_temp.t404_invoice('pc_foc_paid', 'completed_foc', '2026-09-01');
  perform pg_temp.t404_invoice('pc_foc_paid', 'paid', '2026-09-02');
  perform pg_temp.t404_invoice('pc_zero', 'paid', '2026-09-22', null, false, 0);
  perform pg_temp.t404_invoice('pc_paid_oct', 'paid', '2026-09-28', null, false, 100, '2026-10-03 02:00+00');
  perform pg_temp.t404_invoice('pc_cancel', 'cancelled', '2026-09-10');
  perform pg_temp.t404_invoice('pc_refund', 'refunded', '2026-09-11');
  perform pg_temp.t404_invoice('pc_foc', 'completed_foc', '2026-09-12');
  perform pg_temp.t404_invoice('pc_unpaid', 'unpaid', '2026-09-13');
  perform pg_temp.t404_invoice('pc_draft', 'draft', '2026-09-14');
  perform pg_temp.t404_invoice('pc_cancel_req', 'cancellation_requested', '2026-09-15');
  perform pg_temp.t404_invoice('pc_refund_req', 'refund_requested', '2026-09-16');
  perform pg_temp.t404_invoice('pc_deleted', 'paid', '2026-09-17', null, true);
  perform pg_temp.t404_invoice('pc_window', 'paid', '2026-10-01');
  perform pg_temp.t404_invoice('pc_nodate_oct', 'paid', null, '2026-09-30 16:30+00');
  perform pg_temp.t404_invoice('pc_bd_wins', 'paid', '2026-10-01', '2026-09-20 02:00+00');
  perform pg_temp.t404_invoice('pc_wait_cancel', 'cancelled', '2026-09-05');
  if (select count(*) from public.invoices where notes = 'fixture T404' and business_date is null) <> 2 then
    raise exception 'FIXTURE 12: the invoices without a business date were given one'; end if;
  if (select count(*) from public.invoices where notes = 'fixture T404' and customer_id = pg_temp.t398_id('pc_zero')
         and status = 'paid' and total_amount = 0 and paid_amount = 0) <> 1
     or (select count(*) from public.invoices where notes = 'fixture T404' and customer_id = pg_temp.t398_id('pc_paid_oct')
           and status = 'paid' and business_date = '2026-09-28'
           and (paid_at at time zone 'Asia/Singapore')::date = '2026-10-03') <> 1 then
    raise exception 'FIXTURE 12: the S$0 invoice or the one paid in October is not as made'; end if;

  create temp table t404_pc as
    select x.* from public.referral_campaign_friends((select id from public.referral_campaigns where code = '2026-10')) x
     where x.referrer_customer_id = pg_temp.t398_id('pc_ref');
  for f in select * from (values
             ('pc_paid', 'absent'), ('pc_part', 'absent'), ('pc_nodate', 'absent'), ('pc_wait_paid', 'absent'),
             ('pc_foc_paid', 'absent'), ('pc_zero', 'absent'), ('pc_paid_oct', 'absent'),
             ('pc_cancel', 'counts'), ('pc_refund', 'counts'), ('pc_foc', 'counts'), ('pc_unpaid', 'counts'),
             ('pc_draft', 'counts'), ('pc_cancel_req', 'counts'), ('pc_refund_req', 'counts'), ('pc_deleted', 'counts'),
             ('pc_window', 'counts'), ('pc_nodate_oct', 'counts'), ('pc_bd_wins', 'counts'),
             ('pc_wait_cancel', 'waits')) x(k, expect) loop
    if f.expect = 'absent' then
      if exists (select 1 from t404_pc where friend_customer_id = pg_temp.t398_id(f.k)) then
        raise exception 'FAIL 12: past customer % is listed', f.k; end if;
    elsif not exists (select 1 from t404_pc where friend_customer_id = pg_temp.t398_id(f.k)
                        and counted = (f.expect = 'counts') and (f.expect = 'counts') = (first_visit_on is not null)) then
      raise exception 'FAIL 12: % should % (%)', f.k,
        case when f.expect = 'counts' then 'count' else 'be listed as not yet visited' end,
        (select row_to_json(t)::text from t404_pc t where friend_customer_id = pg_temp.t398_id(f.k)); end if;
  end loop;
  if (select count(*) from t404_pc where counted) <> 11 or (select count(*) from t404_pc) <> 12 then
    raise exception 'FAIL 12: Pia should have 11 friends counted of 12 listed, has % of %',
      (select count(*) from t404_pc where counted), (select count(*) from t404_pc); end if;
  -- The visit rule is not touched: a past customer still visited, on the same day.
  if pg_temp.t398_visit('pc_paid') is distinct from '2026-10-05' or pg_temp.t398_visit('pc_part') is distinct from '2026-10-06' then
    raise exception 'FAIL 12: a past customer''s visit changed'; end if;
  -- The report (Owner/Manager): the same, by name.
  perform pg_temp.t398_as('manager');
  r := public.referral_campaign_report('2026-10');
  select e into pia from jsonb_array_elements(r->'referrers') e where e->>'referrer_customer_id' = pg_temp.t398_id('pc_ref')::text;
  if pia is null or (pia->>'counted')::int is distinct from 11 or (pia->>'not_yet_visited')::int is distinct from 1
     or (pia->>'tier_reached')::int is distinct from 10 or jsonb_array_length(pia->'friends') <> 12
     or exists (select 1 from jsonb_array_elements(pia->'friends') e
                 where e->>'name' in ('Ali Yeo', 'Bee Ong', 'Cai Lim', 'Dee Tan', 'Rui Ng', 'Sol Yap', 'Tia Kee'))
     or not exists (select 1 from jsonb_array_elements(pia->'friends') e
                     where e->>'name' = 'Pam Sim' and not (e->>'counted')::boolean and e->'first_visit_on' = 'null'::jsonb)
     or not exists (select 1 from jsonb_array_elements(pia->'friends') e
                     where e->>'name' = 'Gan Seah' and (e->>'counted')::boolean) then
    raise exception 'FAIL 12: Pia''s report row is wrong: %', pia; end if;
  -- The portal (Pia's own login): counts only, past customers in neither figure.
  perform pg_temp.t398_as('aff_login3');
  r := public.affiliate_portal_campaign_progress();
  if r->'campaign'->>'code' = '2026-10' and ((r->>'counted')::int is distinct from 11
       or (r->>'not_yet_visited')::int is distinct from 1 or (r->>'tier_reached')::int is distinct from 10) then
    raise exception 'FAIL 12: Pia''s portal progress counts a past customer: %', r; end if;
  if r->'campaign'->>'code' <> '2026-10' then
    raise notice 'NOTE 12: the portal shows %, not 2026-10, so its October figures were not checked', r->'campaign'->>'code'; end if;
  perform pg_temp.t398_as('owner');
  raise notice 'PASS 12: a friend with a paid or part-paid invoice dated before the window (its business date, else the Singapore day it was made) is neither counted nor listed, visited or not, in the counting, the report and the portal, read as the invoice is now (a S$0 invoice marked paid, and one dated before the window and paid in it, make one too); cancelled, refunded, FOC, unpaid, draft, requested-but-not-done and deleted invoices, and one dated on the window''s first day, do not make a past customer; the visit itself is unchanged';
end $$;

-- ===== 13. 404: for the promotion, a form through the centre's link is dated the day it was sent =====
-- Production holds one survey per customer (uq_health_survey_customer), but
-- the visit rule, and the promotion's earliest visit, are written for
-- several. The index is dropped here, inside this rolled-back transaction,
-- so that two customers can have two surveys each.
drop index public.uq_health_survey_customer;
do $$
declare f record; r jsonb; dov jsonb; v uuid;
begin
  perform pg_temp.t398_as('owner');
  -- Dov Lin, a plain customer, referred:
  perform pg_temp.t398_customer('pd_ref', 'Dov Lin', '+6591398330');
  -- (a) a form signed 20 Oct but sent on 2 Nov: the promotion's first visit
  -- is 2 Nov, after the window, so not listed (the Customers page: 20 Oct);
  perform pg_temp.t398_customer('pd_nov', 'Ada Ko', '+6591398331', 'pd_ref', '2026-10-04 02:00+00');
  perform pg_temp.t398_link_survey('pd_nov', 'link_centre', '2026-11-02 02:00+00', '2026-10-20');
  -- (b) a form signed 25 Sep but sent on 3 Oct, no other visit: counts, on 3 Oct;
  perform pg_temp.t398_customer('pd_sep', 'Bo Lum', '+6591398332', 'pd_ref', '2026-09-10 02:00+00');
  perform pg_temp.t398_link_survey('pd_sep', 'link_centre', '2026-10-03 02:00+00', '2026-09-25');
  -- (c) a form signed 30 Sep, sent at 00:30 on 1 Oct in Singapore (16:30 UTC on 30 Sep): counts, on 1 Oct;
  perform pg_temp.t398_customer('pd_night', 'Cy Poh', '+6591398333', 'pd_ref', '2026-09-12 02:00+00');
  perform pg_temp.t398_link_survey('pd_night', 'link_centre', '2026-09-30 16:30+00', '2026-09-30');
  -- (d) a form sent on 28 Sep with 2 Oct typed on it: the promotion's first
  -- visit is 28 Sep, before the window, so not listed (the Customers page: 2 Oct);
  perform pg_temp.t398_customer('pd_early', 'Di Seng', '+6591398334', 'pd_ref', '2026-10-02 02:00+00');
  perform pg_temp.t398_link_survey('pd_early', 'link_centre', '2026-09-28 02:00+00', '2026-10-02');
  -- (e) an event's survey of 20 Sep with a note at the centre on 6 Oct: an
  -- event survey's later visit keeps its own date (6 Oct), not the day the survey was sent;
  perform pg_temp.t398_customer('pd_event', 'Ed Wu', '+6591398335', 'pd_ref', '2026-09-15 02:00+00');
  perform pg_temp.t398_link_survey('pd_event', 'link_event', '2026-09-20 02:00+00', '2026-09-20');
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, attachments, created_by, created_at)
  values (pg_temp.t398_id('survey_pd_event'), pg_temp.t398_id('pd_event'), 'Came to the centre', '[]',
          pg_temp.t398_id('staff'), '2026-10-06 02:00+00');
  -- (f) a consultant's record made 28 Sep and answered (Save Review) on 4
  -- Oct: a consultant's visit keeps its date (4 Oct), not the day the record was made;
  perform pg_temp.t398_customer('pd_consult', 'Fa Yap', '+6591398336', 'pd_ref', '2026-09-15 02:00+00');
  perform pg_temp.t398_consultant('pd_consult', '2026-09-28 02:00+00');
  perform pg_temp.t398_as('manager');
  perform public.review_health_survey(p_survey_id => pg_temp.t398_id('survey_pd_consult'), p_acidity => 'blue',
    p_health_goals => null, p_condition => 'Shoulder', p_recommendation => null);
  update public.audit_logs set created_at = '2026-10-04 03:00+00'
   where record_id = pg_temp.t398_id('survey_pd_consult') and action = 'health_survey_reviewed';
  perform pg_temp.t398_as('owner');
  -- (g) a consultant's visit on 5 Oct and a form signed 28 Sep but sent on
  -- 3 Nov: the Customers page's first visit is the form (28 Sep, the earlier
  -- date typed); the promotion's is the consultant's visit, 5 Oct, the
  -- earliest once the form is dated the day it was sent (not the form re-dated to 3 Nov);
  perform pg_temp.t398_customer('pd_two', 'Gu Hoe', '+6591398337', 'pd_ref', '2026-09-20 02:00+00');
  perform pg_temp.t398_consultant('pd_two', '2026-10-05 02:00+00', $s$remarks_condition = 'Knee'$s$);
  update public.health_surveys set survey_no = survey_no || '-C' where id = pg_temp.t398_id('survey_pd_two');
  update t398 set k = 'survey_pd_two_consultant' where k = 'survey_pd_two';
  perform pg_temp.t398_link_survey('pd_two', 'link_centre', '2026-11-03 02:00+00', '2026-09-28');
  -- (h) two visits on 7 Oct: a consultant's record made 05:00 UTC and a form
  -- sent at 01:00 UTC; the form's id sorts after the record's, so the
  -- Customers page's pick (the date, then when submitted, then the id) is the form.
  perform pg_temp.t398_customer('pd_tie', 'Hy Ong', '+6591398338', 'pd_ref', '2026-10-01 02:00+00');
  insert into public.health_surveys(id, survey_no, customer_id, full_name, phone, source, submitted_at, remarks_condition)
  values ('00000000-0000-4000-8000-000000000404', 'HS-T404-pd_tie-C', pg_temp.t398_id('pd_tie'), 'Hy Ong', '+6591398338',
          'consultant', '2026-10-07 05:00+00', 'Back');
  insert into public.health_surveys(id, survey_no, store_id, survey_link_id, customer_id, full_name, phone, source,
                                    submitted_at, signed_date)
  select 'ffffffff-ffff-4fff-bfff-ffffffff0404', 'HS-T404-pd_tie-F', l.store_id, l.id, pg_temp.t398_id('pd_tie'),
         'Hy Ong', '+6591398338', 'public_form', '2026-10-07 01:00+00', '2026-10-07'
    from public.survey_links l where l.id = pg_temp.t398_id('link_centre');

  -- The visit rule and the Customers page: unchanged (the date typed on the form).
  for f in select * from (values
             ('pd_nov', '2026-10-20', 'centre_link'), ('pd_sep', '2026-09-25', 'centre_link'),
             ('pd_night', '2026-09-30', 'centre_link'), ('pd_early', '2026-10-02', 'centre_link'),
             ('pd_event', '2026-10-06', 'event_then_centre'), ('pd_consult', '2026-10-04', 'consultant'),
             ('pd_two', '2026-09-28', 'centre_link'), ('pd_tie', '2026-10-07', 'centre_link')) x(k, d, kind) loop
    if not exists (select 1 from public.customer_centre_visits() c where c.customer_id = pg_temp.t398_id(f.k)
                    and c.first_visit_on = f.d::date and c.visit_kind = f.kind) then
      raise exception 'FAIL 13: customer_centre_visits for % is not % (%): %', f.k, f.d, f.kind,
        (select row_to_json(c)::text from public.customer_centre_visits() c where c.customer_id = pg_temp.t398_id(f.k)); end if;
  end loop;
  if (select survey_id from public.customer_centre_visits() where customer_id = pg_temp.t398_id('pd_two'))
       is distinct from pg_temp.t398_id('survey_pd_two')
     or (select survey_id from public.customer_centre_visits() where customer_id = pg_temp.t398_id('pd_tie'))
       is distinct from 'ffffffff-ffff-4fff-bfff-ffffffff0404' then
    raise exception 'FAIL 13: customer_centre_visits did not pick the survey it picked before 404'; end if;
  -- Every visit, with both dates.
  if (select count(*) from public.customer_centre_visit_days() where customer_id = pg_temp.t398_id('pd_two')) <> 2
     or (select count(*) from public.customer_centre_visit_days() where customer_id = pg_temp.t398_id('pd_tie')) <> 2
     or not exists (select 1 from public.customer_centre_visit_days() d where d.customer_id = pg_temp.t398_id('pd_night')
                     and d.visit_on = '2026-09-30' and d.sent_on = '2026-10-01' and d.submitted_at = '2026-09-30 16:30+00')
     or not exists (select 1 from public.customer_centre_visit_days() d where d.customer_id = pg_temp.t398_id('pd_event')
                     and d.visit_kind = 'event_then_centre' and d.visit_on = '2026-10-06' and d.sent_on = '2026-09-20') then
    raise exception 'FAIL 13: customer_centre_visit_days does not give every visit with its date and the day it was sent'; end if;
  perform pg_temp.t398_as('staff');
  if (select first_visit_on from public.search_customers('+6591398332', null, 10, 0) where phone = '+6591398332')
       is distinct from '2026-09-25' then
    raise exception 'FAIL 13: the Customers page''s first visit moved to the day the form was sent'; end if;
  perform pg_temp.t398_as('owner');

  -- The promotion.
  create temp table t404_pd as
    select x.* from public.referral_campaign_friends((select id from public.referral_campaigns where code = '2026-10')) x
     where x.referrer_customer_id = pg_temp.t398_id('pd_ref');
  for f in select * from (values
             ('pd_nov', null), ('pd_early', null),
             ('pd_sep', '2026-10-03'), ('pd_night', '2026-10-01'), ('pd_event', '2026-10-06'),
             ('pd_consult', '2026-10-04'), ('pd_two', '2026-10-05'), ('pd_tie', '2026-10-07')) x(k, d) loop
    if f.d is null then
      if exists (select 1 from t404_pd where friend_customer_id = pg_temp.t398_id(f.k)) then
        raise exception 'FAIL 13: % is listed (%)', f.k,
          (select row_to_json(t)::text from t404_pd t where friend_customer_id = pg_temp.t398_id(f.k)); end if;
    elsif not exists (select 1 from t404_pd where friend_customer_id = pg_temp.t398_id(f.k)
                        and counted and first_visit_on = f.d::date) then
      raise exception 'FAIL 13: % should count with a first visit on % (%)', f.k, f.d,
        (select row_to_json(t)::text from t404_pd t where friend_customer_id = pg_temp.t398_id(f.k)); end if;
  end loop;
  if (select count(*) from t404_pd) <> 6 or exists (select 1 from t404_pd where not counted) then
    raise exception 'FAIL 13: Dov should have 6 friends listed, all counted'; end if;
  -- The report shows the promotion's first visit.
  perform pg_temp.t398_as('manager');
  select e into dov from jsonb_array_elements(public.referral_campaign_report('2026-10')->'referrers') e
   where e->>'referrer_customer_id' = pg_temp.t398_id('pd_ref')::text;
  if (dov->>'counted')::int is distinct from 6 or (dov->>'not_yet_visited')::int is distinct from 0
     or not exists (select 1 from jsonb_array_elements(dov->'friends') e
                     where e->>'name' = 'Bo Lum' and e->>'first_visit_on' = '2026-10-03' and e->>'referred_on' = '2026-09-10')
     or not exists (select 1 from jsonb_array_elements(dov->'friends') e
                     where e->>'name' = 'Gu Hoe' and e->>'first_visit_on' = '2026-10-05')
     or exists (select 1 from jsonb_array_elements(dov->'friends') e where e->>'name' in ('Ada Ko', 'Di Seng')) then
    raise exception 'FAIL 13: Dov''s report row is wrong: %', dov; end if;
  perform pg_temp.t398_as('owner');
  raise notice 'PASS 13: for the promotion a form through the centre''s link counts on the Singapore day it was sent (signed in October and sent in November: not listed; signed in September and sent in October: counts; sent before the window with an October date typed: not listed), a consultant''s and an event survey''s visits keep their dates, and the first visit is the earliest of all the friend''s visits so dated; the report shows that date; customer_centre_visits, its pick and the Customers page keep the date typed on the form';
end $$;

-- ===== 14. customer_centre_visits, search_customers and the downline: the same as before 404 =====
-- Read under 404, then with 398's customer_centre_visits put back (its text
-- as read before 404 ran), then 404's again: every customer's first visit
-- (every fixture above, 404's included), the Customers page's search and
-- every fixture referrer's downline must be the same both times.
create temp table t404_same(side text, k text, row_text text);
create function pg_temp.t404_snapshot(p_side text) returns void language plpgsql as $f$
declare rf record;
begin
  insert into t404_same select p_side, 'visits', row(x.*)::text from public.customer_centre_visits() x;
  perform pg_temp.t398_as('staff');
  insert into t404_same select p_side, 'search', row(x.*)::text from public.search_customers('fixture T398', null, 1000, 0) x;
  insert into t404_same select p_side, 'search visited', row(x.*)::text
    from public.search_customers('fixture T398', null, 1000, 0, 'visited') x;
  insert into t404_same select p_side, 'search not visited', row(x.*)::text
    from public.search_customers('fixture T398', null, 1000, 0, 'not_visited') x;
  insert into t404_same select p_side, 'search range', row(x.*)::text
    from public.search_customers('fixture T398', null, 1000, 0, null, '2026-09-25', '2026-10-20') x;
  perform pg_temp.t398_as('manager');
  for rf in select distinct c.referred_by as id from public.customers c
             where c.notes like 'fixture T398%' and c.referred_by is not null loop
    insert into t404_same select p_side, 'downline', rf.id || ' ' || public.customer_downline_visits(rf.id)::text;
  end loop;
  perform pg_temp.t398_as('owner');
end $f$;
select pg_temp.t404_snapshot('404');
do $$ begin execute (select def from t404_defs where k = 'visits_398'); end $$;
select pg_temp.t404_snapshot('398');
do $$ begin execute (select def from t404_defs where k = 'visits_404'); end $$;
do $$
declare x record; n int;
begin
  if md5(pg_get_functiondef('public.customer_centre_visits()'::regprocedure))
       is distinct from (select md5 from t404_before where fn = 'customer_centre_visits()')
     or (select coalesce(array_to_string(proacl, ','), '') from pg_proc where oid = 'public.customer_centre_visits()'::regprocedure)
       is distinct from (select acl from t404_before where fn = 'customer_centre_visits()') then
    raise exception 'FIXTURE 14: 404''s customer_centre_visits was not put back as it was'; end if;
  for x in select k, count(*) filter (where side = '404') as n404, count(*) filter (where side = '398') as n398
             from t404_same group by k order by k loop
    if x.n404 = 0 or x.n404 <> x.n398
       or exists (select row_text from t404_same where side = '404' and k = x.k
                  except all select row_text from t404_same where side = '398' and k = x.k)
       or exists (select row_text from t404_same where side = '398' and k = x.k
                  except all select row_text from t404_same where side = '404' and k = x.k) then
      raise exception 'FAIL 14: % differs from before 404 (% rows after, % before)', x.k, x.n404, x.n398; end if;
  end loop;
  if (select count(distinct k) from t404_same) <> 6 then raise exception 'FIXTURE 14: not every read was taken'; end if;
  -- The fixtures do exercise the new dating: their promotion first visit differs from the Customers page's.
  select count(*) into n
    from public.customer_centre_visits() c
    join (select d.customer_id, min(case when d.visit_kind = 'centre_link' then d.sent_on else d.visit_on end) as p
            from public.customer_centre_visit_days() d group by d.customer_id) p on p.customer_id = c.customer_id
    join public.customers cu on cu.id = c.customer_id and cu.notes like 'fixture T398%'
   where p.p <> c.first_visit_on;
  if n <> 5 then raise exception 'FIXTURE 14: % fixtures have a promotion first visit other than the Customers page''s, not 5', n; end if;
  raise notice 'PASS 14: customer_centre_visits gives exactly the rows 398''s did for every customer, 5 fixtures among them dated otherwise for the promotion; search_customers (all, Visited, Not visited, a date range) and every fixture downline read the same as before 404 (rows each way: %)',
    (select string_agg(c.kind || ' ' || c.rows_read, ', ' order by c.kind)
       from (select t.k as kind, count(*) as rows_read from t404_same t where t.side = '404' group by t.k) c);
end $$;

rollback;
