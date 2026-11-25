-- For the referral promotion, a visit counts once an Owner or Manager has written on the survey
-- (534; security audit of 17 Nov 2026, M5; the user, 24 Nov 2026: "Same test for all").
--
--   A  The anonymous route the audit found: a made-up friend made signed out through the referral
--      page /r/<code> (affiliate_referral_signup), then the QR form through the centre's link sent
--      signed out for them (submit_health_survey). The friend is listed as not yet visited, not
--      counted. Where 530 is in, the form is held for staff, and once Staff attach it to the
--      friend (attach_held_health_survey) it still does not count. A Manager's saved review makes
--      it count, dated the day the form was sent.
--   R  What makes a form count, each on its own form: (a) a saved review with an answer (Manager,
--      review_health_survey: acidity only is enough), (b) a consultant note with text (Manager,
--      add_consultant_note), or with only an attachment, (c) an attached file (Owner,
--      add_survey_attachment). What does not: no staff writing at all; a note with blank texts and
--      no attachment; a review saved then cleared (reviewed_at set, every answer blank); a review
--      time with blank answers; answers with no review time. A form that does not count is not a
--      visit for the promotion: such a friend referred in the window is listed as not counted yet.
--   D  The date stays the day the form was sent (sent_on): not the date typed on it, nor the day
--      it was reviewed.
--   K  The same test for a consultant's survey: with a note it counts as before; an empty record is
--      no visit, as before; a record a Staff login alone made with one yes/no answer
--      (upsert_consultant_survey, p_smokes => false), or answered on an existing record
--      (update_survey_particulars_v2), is a visit on the Customers page but not counted; Staff are
--      refused a finding; a Manager's finding through the same call (which sets reviewed_at), or an
--      Owner's file on a record Staff made, makes it count. An event's form with a later note counts
--      exactly as before 534.
--   F  The first visit for the promotion moves to the earliest visit that counts: an unreviewed
--      earlier form is passed over for a later form with a note, for a consultant's visit, and,
--      when the earlier form was before the window, the friend now counts in the window. (A
--      customer has one survey at most today, uq_health_survey_customer; these three run with that
--      index dropped inside a savepoint that is rolled back.) Staff writing on another form does
--      not count for this one; a form sent before the window and reviewed in it keeps its day.
--   P  The report (referral_campaign_report), the affiliate's own progress
--      (affiliate_portal_campaign_progress) and the reward (give_referral_campaign_reward) follow
--      the new count: the report's counted and not yet visited, the portal's count and tier, the
--      reward's tier and friends counted, and a referrer below the first tier is refused, with no
--      reward recorded and no stock taken.
--   V  The visit rule itself and the "Visited" screens are unchanged: customer_centre_visits still
--      shows an unreviewed form as the customer's visit, dated as before.
--   G  534's AFTER md5, marker, grants, return type and attributes; its relied-on functions
--      unchanged; nothing a signed-out caller can run writes reviewed_at, a finding, a consultant
--      note or a file, and the anon key cannot write them on the tables; for a signed-in login only
--      the four pinned functions write them.
--   M  534 a second time refuses "already in" and changes nothing; a function at another version,
--      a relied-on function changed, or a write rule wider than is_owner_or_manager() refuses
--      (when this file installs it).
--   U  scripts/referrals/undo-534.sql puts the function back exactly (b5f4f76d...): the unreviewed
--      form and the Staff-only record count again; a second undo refuses; 534 again is 534's text.
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (T534, @example.invalid); phones are the fictional +61 491 570 9nn range. Run it on a copy of
-- production as it is (after 533; or after 529, or with 537): it applies 534 (and tries it again);
-- with -v skip_install=1 where 534 is already in; with -v control=1 on a copy WITHOUT 534 (it
-- does not install it, skips G, M and U, and fails on exactly the checks 534 makes pass; see the
-- end of this file). Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/referrals/tests/staff-written-visit-counts-534.sql
\set ON_ERROR_STOP on
begin;
\if :{?control}
do $$ begin
  if position('534 (security audit' in pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) > 0 then
    raise exception 'control: 534 is in on this copy; run -v control=1 on a copy without it'; end if;
end $$;
\elif :{?skip_install}
do $$ begin
  if position('534 (security audit' in pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) = 0 then
    raise exception 'skip_install: 534 is not in on this copy; run without -v skip_install=1'; end if;
end $$;
\else
\ir ../../../supabase/534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it.sql
create temp table m534 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
savepoint t534_again;
\set ON_ERROR_STOP off
\ir ../../../supabase/534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it.sql
\set ON_ERROR_STOP on
rollback to savepoint t534_again;
release savepoint t534_again;
select :'LAST_ERROR_MESSAGE' as t534_again_msg \gset
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
select position('534 (security audit' in pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) > 0 as t534_in \gset
select to_regprocedure('public.request_sender()') is not null as t534_m530 \gset
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
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- Fictional phones: +61 491 570 9nn.
create function pg_temp.ph(n int) returns text language sql as $$ select '+61491570' || (900 + n)::text $$;
create function pg_temp.mail(key text) returns text language sql as
$$ select 't534-' || lower(key) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- One statement as a signed-in login (p_who) or signed out (null): its first column as text, or
-- 'ERROR: <message>'.
create function pg_temp.as_login(p_who text, q text) returns text language plpgsql as $f$
declare v text; u uuid := pg_temp.fx(p_who);
begin
  perform set_config('request.headers', '', true);
  if p_who is null then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'anon', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', u::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
  execute q into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  return coalesce(nullif(v, ''), 'ok');
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  return 'ERROR: ' || sqlerrm;
end $f$;
-- A form on file for a customer, made as the QR form or the Surveys page would leave it: kind
-- 'centre' (the centre's link), 'event' (an event's link) or 'consultant' (a consultant's record);
-- sent at 11:00 Singapore time on a day, with the date typed on it (signed_date).
create function pg_temp.form(key text, cust text, kind text, sent date, signed date default null) returns uuid language plpgsql as
$$declare v uuid; begin
  insert into public.health_surveys(survey_no, store_id, survey_link_id, customer_id, full_name, phone, source,
                                    submitted_at, signed_date)
  select 'HS-T534-' || key || '-' || pg_temp.tx('sfx'), pg_temp.fx('st'),
         case kind when 'centre' then pg_temp.fx('link') when 'event' then pg_temp.fx('elink') end,
         c.id, c.full_name, c.phone, case when kind = 'consultant' then 'consultant' else 'public_form' end,
         (sent + time '11:00') at time zone 'Asia/Singapore', signed
    from public.customers c where c.id = pg_temp.fx(cust)
  returning id into v;
  insert into fx values ('form:' || key, v);
  return v;
end$$;
-- A friend of a referrer (customers.referred_by), made as the database's own functions make one,
-- referred today or on a day given.
create function pg_temp.friend(key text, ref text, n int, referred date default null) returns uuid language plpgsql as
$$declare v uuid; begin
  insert into public.customers(full_name, phone, referred_by, referred_at, referral_source)
  values ('T534 Friend ' || key, pg_temp.ph(n), pg_temp.fx(ref),
          coalesce((referred + time '09:00') at time zone 'Asia/Singapore', now()), 'affiliate_link') returning id into v;
  insert into fx values (key, v);
  return v;
end$$;
-- A friend's row in a promotion, as 'counted/first visit', or 'not listed'; now and as before 534.
create function pg_temp.fr(key text, camp text default 'campA') returns text language sql as
$$ select coalesce((select f.counted::text || '/' || coalesce(f.first_visit_on::text, '-')
                      from public.referral_campaign_friends(pg_temp.fx(camp)) f
                     where f.friend_customer_id = pg_temp.fx(key)), 'not listed') $$;
create function pg_temp.row_of(counted boolean, first date) returns text language sql as
$$ select counted::text || '/' || coalesce(first::text, '-') $$;

-- ═════ The version before 534, as a temporary function, to compare with ═════
-- Where 534 is in, its own undo gives that text (inside a savepoint, rolled back at once).
\if :t534_in
savepoint t534_before;
\ir ../undo-534.sql
select pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure) as t534_def_before \gset
rollback to savepoint t534_before;
release savepoint t534_before;
\else
select pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure) as t534_def_before \gset
\endif
select set_config('t534.def_before', :'t534_def_before', true) is not null as t534_ok \gset
do $$
declare d text := current_setting('t534.def_before');
begin
  if md5(d) <> 'b5f4f76d7d22369ee4706a4b5f9dd465' then
    raise exception 'the version before 534 is not b5f4f76d... (md5 %); this suite compares with it', md5(d); end if;
  d := replace(d, 'FUNCTION public.referral_campaign_friends(', 'FUNCTION pg_temp.t534_before(');
  d := replace(d, E' STABLE SECURITY DEFINER\n', E' STABLE\n');
  execute d;
end $$;
create function pg_temp.frb(key text, camp text default 'campA') returns text language sql as
$$ select coalesce((select f.counted::text || '/' || coalesce(f.first_visit_on::text, '-')
                      from pg_temp.t534_before(pg_temp.fx(camp)) f
                     where f.friend_customer_id = pg_temp.fx(key)), 'not listed') $$;

-- ═════ Fixtures ═════
do $$ begin insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))); end $$;
select pg_temp.check(not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) ~ '^\+61491570(9[0-9][0-9])$')
    and not exists (select 1 from public.health_surveys s where s.phone ~ '^\+61491570(9[0-9][0-9])$'),
  'P0 no customer and no survey uses the test phones (+61491570900..999)');
do $$
declare sfx text := pg_temp.tx('sfx'); k text; u uuid; c uuid;
begin
  foreach k in array array['own', 'mgr', 'stf', 'affl'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 't534-' || k || '-' || sfx || '@example.invalid', now());
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status) values
    (pg_temp.fx('own'), 'T534 Owner',   't534-own-' || sfx || '@example.invalid', 'owner', true, 'accepted'),
    (pg_temp.fx('mgr'), 'T534 Manager', 't534-mgr-' || sfx || '@example.invalid', 'manager', true, 'accepted'),
    (pg_temp.fx('stf'), 'T534 Staff',   't534-stf-' || sfx || '@example.invalid', 'staff', true, 'accepted');
  insert into public.stores(name, code, country_code) values ('T534 Sample Store', 'T534' || sfx, 'SG') returning id into c;
  insert into fx values ('st', c);
  insert into public.customer_source_options(label) values ('T534 Walk-in ' || sfx) returning id into c; insert into fx values ('src', c);
  insert into public.survey_links(token, store_id) values ('t534-centre-' || sfx, pg_temp.fx('st')) returning id into c;
  insert into fx values ('link', c);
  insert into public.survey_links(token, store_id, event_name) values ('t534-event-' || sfx, pg_temp.fx('st'), 'T534 Expo ' || sfx)
  returning id into c;
  insert into fx values ('elink', c);
  -- Three referrers, affiliates with referral links; ref has a portal login, made with the record
  -- in this transaction (so its link is proven: "own_record").
  insert into public.customers(full_name, phone) values ('T534 Rita Referrer', pg_temp.ph(1)) returning id into c; insert into fx values ('ref', c);
  insert into public.customers(full_name, phone) values ('T534 Ravi Referrer', pg_temp.ph(2)) returning id into c; insert into fx values ('ref2', c);
  insert into public.customers(full_name, phone) values ('T534 Rosa Referrer', pg_temp.ph(3)) returning id into c; insert into fx values ('ref3', c);
  insert into public.customer_affiliates(customer_id, status, activated_at, referral_code) values
    (pg_temp.fx('ref'), 'active', now() - interval '60 days', 'T534RITA' || upper(sfx)),
    (pg_temp.fx('ref2'), 'active', now() - interval '60 days', 'T534RAVI' || upper(sfx)),
    (pg_temp.fx('ref3'), 'active', now() - interval '60 days', 'T534ROSA' || upper(sfx));
  insert into public.affiliate_accounts(auth_user_id, customer_id, status) values (pg_temp.fx('affl'), pg_temp.fx('ref'), 'claimed');
  -- Promotion A runs from 10 days ago to 5 days ahead (the latest that has started: the portal's);
  -- promotion B ran from 20 days ago to yesterday (ended: its rewards can be given).
  insert into fx values ('campA', gen_random_uuid()), ('campB', gen_random_uuid());
  insert into public.referral_campaigns(id, code, title, reward_reason, starts_on, ends_on, tiers) values
    (pg_temp.fx('campA'), 'T534-A-' || sfx, 'T534 promotion A', 'T534 reward A', pg_temp.d(-10), pg_temp.d(5), array[3, 8, 12]),
    (pg_temp.fx('campB'), 'T534-B-' || sfx, 'T534 promotion B', 'T534 reward B', pg_temp.d(-20), pg_temp.d(-1), array[2, 4]);
  -- A product in the store's stock, for the reward.
  insert into public.products(name, sku, product_type) values ('T534 Gift ' || sfx, 'T534-G-' || sfx, 'own') returning id into c;
  insert into fx values ('gift', c);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('st'), pg_temp.fx('gift'), 5);
end $$;
select pg_temp.check(not exists (select 1 from public.referral_campaigns x
                                  where x.id <> pg_temp.fx('campA') and x.starts_on <= public.sg_today()
                                    and x.starts_on >= pg_temp.d(-10)),
  'P1 promotion A is the latest that has started (the one the affiliate''s portal shows)');

-- ═════ A The anonymous route ═════
select pg_temp.put('a:signup', pg_temp.as_login(null, format(
  'select public.affiliate_referral_signup(%L, %L, %L, %L, null, null)::text',
  'T534RITA' || upper(pg_temp.tx('sfx')), 'Ana', 'T534Anon', pg_temp.ph(10))));
insert into fx select 'anon', c.id from public.customers c
 where c.deleted_at is null and public.normalize_customer_phone(c.phone) = pg_temp.ph(10);
select pg_temp.put('a:form', pg_temp.as_login(null, format(
  'select public.submit_health_survey(%L, %L::jsonb, ''[]''::jsonb, null)::text', 't534-centre-' || pg_temp.tx('sfx'),
  json_build_object('full_name', 'Ana T534Anon', 'phone', pg_temp.ph(10), 'email', pg_temp.mail('anon'),
                    'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', pg_temp.fx('src')))));
insert into fx select 'form:anon', (pg_temp.tx('a:form')::jsonb->>'survey_id')::uuid where pg_temp.tx('a:form') like '{%';
select pg_temp.check(pg_temp.tx('a:signup')::jsonb->>'outcome' = 'registered' and pg_temp.fx('anon') is not null
    and (select referred_by from public.customers where id = pg_temp.fx('anon')) = pg_temp.fx('ref')
    and pg_temp.tx('a:form')::jsonb->>'success' = 'true' and pg_temp.fx('form:anon') is not null,
  'A0 signed out: the referral page made the friend under Rita, and the QR form through the centre''s link was taken: '
  || pg_temp.tx('a:signup') || ' / ' || pg_temp.tx('a:form'));
select pg_temp.check(pg_temp.fr('anon') = 'false/-',
  'A1 the friend made by the two signed-out calls is listed as not yet visited, not counted (before 534 they counted: '
  || pg_temp.frb('anon') || '); now ' || pg_temp.fr('anon'));
\if :t534_m530
-- 530 holds that form for staff (the friend is an existing customer with no survey); Staff
-- attach it after checking, which is the intended way.
select pg_temp.check((select customer_id from public.health_surveys where id = pg_temp.fx('form:anon')) is null
    and exists (select 1 from public.health_survey_holds h where h.survey_id = pg_temp.fx('form:anon') and h.reason = 'existing_customer'),
  'A2a (530) the form waits under To match, with no customer');
select pg_temp.put('a:attach', pg_temp.as_login('stf', format('select public.attach_held_health_survey(%L, %L, %L)::text',
  pg_temp.fx('form:anon'), pg_temp.fx('anon'), 'T534 checked the phone and name at the counter')));
select pg_temp.check(pg_temp.tx('a:attach') like '{"ok": true%'
    and (select customer_id from public.health_surveys where id = pg_temp.fx('form:anon')) = pg_temp.fx('anon')
    and (select reviewed_at from public.health_surveys where id = pg_temp.fx('form:anon')) is null,
  'A2b (530) Staff attach the held form to the friend; that writes no review: ' || pg_temp.tx('a:attach'));
select pg_temp.check(pg_temp.fr('anon') = 'false/-',
  'A2 (530) a form held and attached by staff still needs a review, a note or a file: not counted (before 534: '
  || pg_temp.frb('anon') || '); now ' || pg_temp.fr('anon'));
\else
select pg_temp.check((select customer_id from public.health_surveys where id = pg_temp.fx('form:anon')) = pg_temp.fx('anon'),
  'A2a (no 530) the form went to the friend at once');
\endif
select pg_temp.put('a:review', pg_temp.as_login('mgr', format(
  'select public.review_health_survey(p_survey_id => %L, p_acidity => %L)::text', pg_temp.fx('form:anon'), 'green')));
select pg_temp.check(pg_temp.tx('a:review') = 'ok' and pg_temp.fr('anon') = pg_temp.row_of(true, public.sg_today()),
  'A3 a Manager saves a review (acidity only): the friend counts, first visit the day the form was sent: '
  || pg_temp.tx('a:review') || ' / ' || pg_temp.fr('anon'));

-- ═════ R What makes a form count ═════
-- Each friend has one form through the centre's link, sent 3 days ago, the date typed on it 4 days ago.
do $$
declare k text; n int := 20;
begin
  foreach k in array array['none', 'rev', 'note', 'natt', 'file', 'enote', 'clr', 'blank', 'unrev'] loop
    perform pg_temp.friend(k, 'ref', n); n := n + 1;
    perform pg_temp.form(k, k, 'centre', pg_temp.d(-3), pg_temp.d(-4));
  end loop;
end $$;
-- (a) a review, acidity only, by a Manager
select pg_temp.put('r:rev', pg_temp.as_login('mgr', format(
  'select public.review_health_survey(p_survey_id => %L, p_acidity => %L)::text', pg_temp.fx('form:rev'), 'blue')));
-- (b) a note with text; a note with only an attachment; a note with nothing in it
select pg_temp.put('r:note', pg_temp.as_login('mgr', format(
  'select public.add_consultant_note(%L, null, null, %L, null, null)::text', pg_temp.fx('form:note'), 'Sleep better')));
select pg_temp.put('r:natt', pg_temp.as_login('mgr', format(
  'select public.add_consultant_note(%L, null, null, %L, %L, null, %L::jsonb)::text', pg_temp.fx('form:natt'), '  ', '',
  '[{"name": "t534-scan.jpg", "path": "t534/scan.jpg"}]')));
select pg_temp.put('r:enote', pg_temp.as_login('mgr', format(
  'select public.add_consultant_note(%L, null, null, %L, %L, null, ''[]''::jsonb)::text', pg_temp.fx('form:enote'), ' ', '')));
-- (c) a file attached by an Owner (the file is put in storage first, as the page uploads it)
insert into storage.objects(id, bucket_id, name, metadata)
values (gen_random_uuid(), 'survey-attachments', pg_temp.fx('st')::text || '/' || pg_temp.fx('form:file')::text || '/t534.pdf',
        '{"size": 1200, "mimetype": "application/pdf"}'::jsonb);
select pg_temp.put('r:file', pg_temp.as_login('own', format(
  'select public.add_survey_attachment(%L, %L, %L)::text', pg_temp.fx('form:file'),
  pg_temp.fx('st')::text || '/' || pg_temp.fx('form:file')::text || '/t534.pdf', 't534.pdf')));
-- A review saved, then cleared by a Manager: reviewed_at is set and every answer is blank.
select pg_temp.put('r:clr1', pg_temp.as_login('mgr', format(
  'select public.review_health_survey(p_survey_id => %L, p_health_goals => %L)::text', pg_temp.fx('form:clr'), 'Walk more')));
select pg_temp.put('r:clr2', pg_temp.as_login('mgr', format(
  'select public.review_health_survey(p_survey_id => %L, p_clear => true)::text', pg_temp.fx('form:clr'))));
-- A review time with blank answers, and answers with no review time (states as a row can hold them).
-- (acidity_result is red, green, blue or null by its check.)
update public.health_surveys set reviewed_at = now(), reviewed_by = pg_temp.fx('mgr'), acidity_result = null,
       remarks_condition = '', remarks_recommendation = ' ', health_goals = '  '
 where id = pg_temp.fx('form:blank');
update public.health_surveys set health_goals = 'Typed on the form', remarks_condition = 'Typed too'
 where id = pg_temp.fx('form:unrev');
select pg_temp.check(pg_temp.tx('r:rev') = 'ok' and pg_temp.tx('r:note') ~ '^[0-9a-f-]{36}$'
    and pg_temp.tx('r:natt') ~ '^[0-9a-f-]{36}$' and pg_temp.tx('r:enote') ~ '^[0-9a-f-]{36}$'
    and pg_temp.tx('r:file') ~ '^[0-9a-f-]{36}$' and pg_temp.tx('r:clr1') = 'ok' and pg_temp.tx('r:clr2') = 'ok'
    and (select reviewed_at is not null and health_goals is null and acidity_result is null
           from public.health_surveys where id = pg_temp.fx('form:clr')),
  'R0 the staff writing was saved through the pages'' own calls: ' || concat_ws(' / ', pg_temp.tx('r:rev'), pg_temp.tx('r:note'),
  pg_temp.tx('r:natt'), pg_temp.tx('r:enote'), pg_temp.tx('r:file'), pg_temp.tx('r:clr1'), pg_temp.tx('r:clr2')));
select pg_temp.check(pg_temp.fr('rev') = pg_temp.row_of(true, pg_temp.d(-3)),
  'R1 (a) a Manager''s saved review (acidity only) makes the form count: ' || pg_temp.fr('rev'));
select pg_temp.check(pg_temp.fr('note') = pg_temp.row_of(true, pg_temp.d(-3)),
  'R2 (b) a Manager''s consultant note with text on the form makes it count: ' || pg_temp.fr('note'));
select pg_temp.check(pg_temp.fr('natt') = pg_temp.row_of(true, pg_temp.d(-3)),
  'R3 (b) a note with blank texts but an attachment makes it count: ' || pg_temp.fr('natt'));
select pg_temp.check(pg_temp.fr('file') = pg_temp.row_of(true, pg_temp.d(-3)),
  'R4 (c) a file an Owner attached to the form makes it count: ' || pg_temp.fr('file'));
select pg_temp.check(pg_temp.fr('none') = 'false/-',
  'R5 no staff writing: not a visit for the promotion, listed as not yet visited (before 534: ' || pg_temp.frb('none') || '); now ' || pg_temp.fr('none'));
select pg_temp.check(pg_temp.fr('enote') = 'false/-',
  'R6 a note with blank texts and no attachment does not count (before 534: ' || pg_temp.frb('enote') || '); now ' || pg_temp.fr('enote'));
select pg_temp.check(pg_temp.fr('clr') = 'false/-',
  'R7 a review saved then cleared (reviewed_at set, every answer blank) does not count (before 534: ' || pg_temp.frb('clr') || '); now ' || pg_temp.fr('clr'));
select pg_temp.check(pg_temp.fr('blank') = 'false/-',
  'R8 a review time with blank answers (no acidity; spaces, empty) does not count (before 534: ' || pg_temp.frb('blank') || '); now ' || pg_temp.fr('blank'));
select pg_temp.check(pg_temp.fr('unrev') = 'false/-',
  'R9 answers on the form with no review time do not count (before 534: ' || pg_temp.frb('unrev') || '); now ' || pg_temp.fr('unrev'));
select pg_temp.check(pg_temp.frb('rev') = pg_temp.fr('rev') and pg_temp.frb('note') = pg_temp.fr('note')
    and pg_temp.frb('natt') = pg_temp.fr('natt') and pg_temp.frb('file') = pg_temp.fr('file'),
  'R10 a form staff wrote on is counted on the same day as before 534');

-- ═════ D The date ═════
select pg_temp.check(pg_temp.fr('rev') = pg_temp.row_of(true, pg_temp.d(-3))
    and (select (submitted_at at time zone 'Asia/Singapore')::date = pg_temp.d(-3) and signed_date = pg_temp.d(-4)
                and (reviewed_at at time zone 'Asia/Singapore')::date = public.sg_today()
           from public.health_surveys where id = pg_temp.fx('form:rev')),
  'D1 the form counts on the day it was sent (3 days ago), not the date typed on it (4 days ago) nor the day of the review (today)');

-- ═════ K Consultant and event visits: the same test ═════
do $$
declare v uuid;
begin
  perform pg_temp.friend('cons', 'ref', 40);
  v := pg_temp.form('cons', 'cons', 'consultant', pg_temp.d(-6));
  insert into public.consultant_notes(survey_id, customer_id, health_goals, created_by, created_at)
  values (v, pg_temp.fx('cons'), 'Rest', pg_temp.fx('mgr'), (pg_temp.d(-4) + time '15:00') at time zone 'Asia/Singapore');
  perform pg_temp.friend('event', 'ref', 41);
  v := pg_temp.form('event', 'event', 'event', pg_temp.d(-6), pg_temp.d(-6));
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, created_by, created_at)
  values (v, pg_temp.fx('event'), 'Back pain', pg_temp.fx('mgr'), (pg_temp.d(-3) + time '15:00') at time zone 'Asia/Singapore');
  -- An empty consultant's record (the Surveys page makes one when staff open a customer): no visit, as before.
  perform pg_temp.friend('cempty', 'ref', 42);
  perform pg_temp.form('cempty', 'cempty', 'consultant', pg_temp.d(-5));
end $$;
select pg_temp.check(pg_temp.fr('cons') = pg_temp.row_of(true, pg_temp.d(-4)) and pg_temp.fr('cons') = pg_temp.frb('cons')
    and exists (select 1 from public.customer_centre_visit_days() d where d.customer_id = pg_temp.fx('cons') and d.visit_kind = 'consultant'),
  'K1 a consultant''s survey with a note counts as before, on the note''s day: ' || pg_temp.fr('cons'));
select pg_temp.check(pg_temp.fr('event') = pg_temp.row_of(true, pg_temp.d(-3)) and pg_temp.fr('event') = pg_temp.frb('event')
    and exists (select 1 from public.customer_centre_visit_days() d where d.customer_id = pg_temp.fx('event') and d.visit_kind = 'event_then_centre'),
  'K2 an event''s form with a later note counts as before, on the note''s day: ' || pg_temp.fr('event'));
select pg_temp.check(pg_temp.fr('cempty') = 'false/-' and pg_temp.fr('cempty') = pg_temp.frb('cempty'),
  'K3 an empty consultant''s record is no visit, as before: ' || pg_temp.fr('cempty'));
-- The consultant's record through the pages' own calls. Staff work at the store.
insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('stf'), pg_temp.fx('st'));
do $$ begin
  perform pg_temp.friend('cstaff', 'ref', 43); perform pg_temp.friend('cpart', 'ref', 44);
  perform pg_temp.friend('cfind', 'ref', 45); perform pg_temp.friend('cfile', 'ref', 46);
end $$;
-- A Staff login alone: a record with one yes/no answer.
select pg_temp.put('k:cstaff', pg_temp.as_login('stf', format(
  'select public.upsert_consultant_survey(%L, p_smokes => false, p_store_id => %L)::text', pg_temp.fx('cstaff'), pg_temp.fx('st'))));
-- A Staff login: an empty record, then a yes/no answer on it through the particulars.
select pg_temp.put('k:cpart0', pg_temp.as_login('stf', format(
  'select public.upsert_consultant_survey(%L, p_store_id => %L)::text', pg_temp.fx('cpart'), pg_temp.fx('st'))));
select pg_temp.put('k:cpart', pg_temp.as_login('stf', format(
  'select public.update_survey_particulars_v2(%L, %L::jsonb, %L)::text', pg_temp.tx('k:cpart0'), '{"drinks_alcohol": false}', 'T534 asked at the counter')));
-- Staff try to write a finding on the record they made: refused.
select pg_temp.put('k:stf_find', pg_temp.as_login('stf', format(
  'select public.upsert_consultant_survey(%L, p_health_goals => %L, p_store_id => %L)::text', pg_temp.fx('cstaff'), 'Sleep', pg_temp.fx('st'))));
-- A Manager's finding through the same call.
select pg_temp.put('k:cfind', pg_temp.as_login('mgr', format(
  'select public.upsert_consultant_survey(%L, p_acidity_result => %L, p_store_id => %L)::text', pg_temp.fx('cfind'), 'green', pg_temp.fx('st'))));
-- A record Staff made with an answer, and an Owner's file on it.
select pg_temp.put('k:cfile0', pg_temp.as_login('stf', format(
  'select public.upsert_consultant_survey(%L, p_on_treatment => true, p_store_id => %L)::text', pg_temp.fx('cfile'), pg_temp.fx('st'))));
insert into storage.objects(id, bucket_id, name, metadata)
select gen_random_uuid(), 'survey-attachments', pg_temp.fx('st')::text || '/' || pg_temp.tx('k:cfile0') || '/t534-c.pdf',
       '{"size": 900, "mimetype": "application/pdf"}'::jsonb
 where pg_temp.tx('k:cfile0') ~ '^[0-9a-f-]{36}$';
select pg_temp.put('k:cfile', pg_temp.as_login('own', format(
  'select public.add_survey_attachment(%L, %L, %L)::text', pg_temp.tx('k:cfile0'),
  pg_temp.fx('st')::text || '/' || pg_temp.tx('k:cfile0') || '/t534-c.pdf', 't534-c.pdf')));
select pg_temp.check(pg_temp.tx('k:cstaff') ~ '^[0-9a-f-]{36}$'
    and exists (select 1 from public.customer_centre_visit_days() d where d.customer_id = pg_temp.fx('cstaff')
                  and d.visit_kind = 'consultant' and d.visit_on = public.sg_today())
    and (select reviewed_at is null from public.health_surveys where id = pg_temp.tx('k:cstaff')::uuid)
    and pg_temp.fr('cstaff') = 'false/-',
  'K4 a consultant''s record a Staff login alone made with one yes/no answer is a visit on the Customers page but not counted (before 534: '
  || pg_temp.frb('cstaff') || '); now ' || pg_temp.fr('cstaff') || ' / ' || pg_temp.tx('k:cstaff'));
select pg_temp.check(pg_temp.tx('k:cpart0') ~ '^[0-9a-f-]{36}$' and pg_temp.tx('k:cpart') like '{%'
    and exists (select 1 from public.customer_centre_visit_days() d where d.customer_id = pg_temp.fx('cpart') and d.visit_kind = 'consultant')
    and pg_temp.fr('cpart') = 'false/-',
  'K5 a yes/no answer Staff write on an existing record (the particulars) is a visit on the Customers page but not counted (before 534: '
  || pg_temp.frb('cpart') || '); now ' || pg_temp.fr('cpart') || ' / ' || pg_temp.tx('k:cpart'));
select pg_temp.check(pg_temp.tx('k:stf_find') like 'ERROR: Only an Owner or Manager can write the consultant''s findings%'
    and (select coalesce(health_goals, acidity_result) is null and reviewed_at is null from public.health_surveys where id = pg_temp.tx('k:cstaff')::uuid),
  'K6 Staff are refused a finding on the record: ' || pg_temp.tx('k:stf_find'));
select pg_temp.check(pg_temp.tx('k:cfind') ~ '^[0-9a-f-]{36}$'
    and (select reviewed_at is not null and acidity_result = 'green' from public.health_surveys where id = pg_temp.tx('k:cfind')::uuid)
    and pg_temp.fr('cfind') = pg_temp.row_of(true, public.sg_today()),
  'K7 a Manager''s finding on a consultant''s record (it sets reviewed_at) makes it count: ' || pg_temp.fr('cfind'));
select pg_temp.check(pg_temp.tx('k:cfile') ~ '^[0-9a-f-]{36}$' and pg_temp.fr('cfile') = pg_temp.row_of(true, public.sg_today()),
  'K8 an Owner''s file on a record Staff made makes it count: ' || pg_temp.tx('k:cfile') || ' / ' || pg_temp.fr('cfile'));

-- ═════ F The first visit moves to the earliest visit that counts ═════
-- A customer has one health survey at most today (the unique index uq_health_survey_customer), so
-- each friend has one visit row at most and their first visit is that one, once it counts. The
-- rule is written for several (customer_centre_visit_days returns one row per survey): to test
-- it, the index is dropped inside a savepoint, the friends below get two surveys each, their rows
-- are read into psql variables, and the savepoint is rolled back (the index and those friends
-- with it) before the checks.
savepoint t534_f;
drop index public.uq_health_survey_customer;
do $$
declare v uuid;
begin
  -- two forms through the centre's link: 6 days ago (unreviewed), 2 days ago (a note)
  perform pg_temp.friend('two', 'ref', 50);
  perform pg_temp.form('two1', 'two', 'centre', pg_temp.d(-6), pg_temp.d(-6));
  v := pg_temp.form('two2', 'two', 'centre', pg_temp.d(-2), pg_temp.d(-2));
  insert into public.consultant_notes(survey_id, customer_id, acidity_result, created_by)
  values (v, pg_temp.fx('two'), 'red', pg_temp.fx('mgr'));
  -- an unreviewed form 15 days ago (before promotion A), and one 2 days ago reviewed
  perform pg_temp.friend('twob', 'ref', 51);
  perform pg_temp.form('twob1', 'twob', 'centre', pg_temp.d(-15), pg_temp.d(-15));
  v := pg_temp.form('twob2', 'twob', 'centre', pg_temp.d(-2), pg_temp.d(-2));
  update public.health_surveys set reviewed_at = now(), reviewed_by = pg_temp.fx('mgr'), remarks_recommendation = 'Come weekly'
   where id = v;
  -- an unreviewed form 7 days ago, and a consultant's visit 4 days ago
  perform pg_temp.friend('mix', 'ref', 52);
  perform pg_temp.form('mix1', 'mix', 'centre', pg_temp.d(-7), pg_temp.d(-7));
  v := pg_temp.form('mix2', 'mix', 'consultant', pg_temp.d(-6));
  insert into public.consultant_notes(survey_id, customer_id, health_goals, created_by, created_at)
  values (v, pg_temp.fx('mix'), 'Energy', pg_temp.fx('mgr'), (pg_temp.d(-4) + time '10:00') at time zone 'Asia/Singapore');
end $$;
select pg_temp.fr('two') as t534_f_two, pg_temp.frb('two') as t534_fb_two, pg_temp.fr('twob') as t534_f_twob,
       pg_temp.frb('twob') as t534_fb_twob, pg_temp.fr('mix') as t534_f_mix, pg_temp.frb('mix') as t534_fb_mix,
       pg_temp.row_of(true, pg_temp.d(-2)) as t534_d2, pg_temp.row_of(true, pg_temp.d(-4)) as t534_d4 \gset
rollback to savepoint t534_f;
release savepoint t534_f;
delete from fx where k in ('two', 'twob', 'mix') or k like 'form:two%' or k like 'form:mix%';
select pg_temp.check(:'t534_f_two' = :'t534_d2',
  'F1 an unreviewed form 6 days ago is passed over for the later form with a note (2 days ago): before 534 ' || :'t534_fb_two' || ', now ' || :'t534_f_two');
select pg_temp.check(:'t534_f_twob' = :'t534_d2',
  'F2 an unreviewed form before the window no longer hides a reviewed one in it: the friend counts (before 534 '
  || :'t534_fb_twob' || '), now ' || :'t534_f_twob');
select pg_temp.check(:'t534_f_mix' = :'t534_d4',
  'F3 an unreviewed form 7 days ago is passed over for the consultant''s visit 4 days ago: before 534 ' || :'t534_fb_mix' || ', now ' || :'t534_f_mix');
select pg_temp.check(exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'uq_health_survey_customer'),
  'F0 the unique index is back after the savepoint');
-- Staff writing on another friend's form (Rita's friend 'note', above) does not make this one count.
do $$ begin
  perform pg_temp.friend('other', 'ref', 53);
  perform pg_temp.form('other', 'other', 'centre', pg_temp.d(-2), pg_temp.d(-2));
end $$;
select pg_temp.check(pg_temp.fr('other') = 'false/-',
  'F4 staff writing on another form does not make this one count: ' || pg_temp.fr('other'));
-- A form sent before the window and reviewed today keeps the day it was sent: it does not come
-- into promotion A (nor did it before 534); it counts in promotion B, whose window holds that day.
do $$ declare v uuid; begin
  perform pg_temp.friend('late', 'ref', 54, pg_temp.d(-18));
  v := pg_temp.form('late', 'late', 'centre', pg_temp.d(-15), pg_temp.d(-15));
  update public.health_surveys set reviewed_at = now(), reviewed_by = pg_temp.fx('mgr'), health_goals = 'Swim'
   where id = v;
end $$;
select pg_temp.check(pg_temp.fr('late') = 'not listed' and pg_temp.frb('late') = 'not listed'
    and pg_temp.fr('late', 'campB') = pg_temp.row_of(true, pg_temp.d(-15)),
  'F5 a form sent before the window and reviewed in it keeps the day it was sent: not in A, counted in B on that day: '
  || pg_temp.fr('late') || ' / ' || pg_temp.fr('late', 'campB'));

-- ═════ P The report, the portal and the reward ═════
-- Promotion A, Rita: counted anon, rev, note, natt, file, cons, event, cfind, cfile (9); not
-- counted yet (no counted visit) none, enote, clr, blank, unrev, other, cstaff, cpart, and cempty
-- (no visit at all) (9); 'late' is not listed.
select pg_temp.put('p:report', pg_temp.as_login('own', format('select public.referral_campaign_report(%L)::text', 'T534-A-' || pg_temp.tx('sfx'))));
select pg_temp.put('p:rita', (select r::text from jsonb_array_elements(pg_temp.tx('p:report')::jsonb->'referrers') r
                               where r->>'referrer_customer_id' = pg_temp.fx('ref')::text));
select pg_temp.check((pg_temp.tx('p:rita')::jsonb->>'counted')::int = 9 and (pg_temp.tx('p:rita')::jsonb->>'not_yet_visited')::int = 9
    and (pg_temp.tx('p:rita')::jsonb->>'tier_reached')::int = 8
    and (select count(*) from public.referral_campaign_friends(pg_temp.fx('campA')) f
          where f.referrer_customer_id = pg_temp.fx('ref') and f.counted) = 9,
  'P1 the report counts Rita''s 9 friends with a visit an Owner or Manager wrote on, tier 8, and 9 with no counted visit yet (before 534: '
  || (select count(*) filter (where counted) || ' counted, ' || count(*) filter (where first_visit_on is null) || ' not yet visited'
        from pg_temp.t534_before(pg_temp.fx('campA')) f where f.referrer_customer_id = pg_temp.fx('ref')) || '): '
  || coalesce(pg_temp.tx('p:rita')::jsonb->>'counted', '?') || ' counted, ' || coalesce(pg_temp.tx('p:rita')::jsonb->>'not_yet_visited', '?') || ' not yet visited');
select pg_temp.check((select bool_and(case when f->>'customer_id' in (pg_temp.fx('none')::text, pg_temp.fx('enote')::text, pg_temp.fx('clr')::text,
                                                                      pg_temp.fx('blank')::text, pg_temp.fx('unrev')::text, pg_temp.fx('other')::text,
                                                                      pg_temp.fx('cempty')::text, pg_temp.fx('cstaff')::text, pg_temp.fx('cpart')::text)
                                           then (f->>'counted')::boolean = false and f->>'first_visit_on' is null
                                           else (f->>'counted')::boolean end)
                        from jsonb_array_elements(pg_temp.tx('p:rita')::jsonb->'friends') f)
    and jsonb_array_length(pg_temp.tx('p:rita')::jsonb->'friends') = 18,
  'P2 the report''s list: the 6 friends whose only form nobody wrote on, the 2 whose only record has a Staff answer, and the one with an empty record show no first visit and are not counted; the other 9 are counted');
select pg_temp.put('p:portal', pg_temp.as_login('affl', 'select public.affiliate_portal_campaign_progress()::text'));
select pg_temp.check((pg_temp.tx('p:portal')::jsonb->>'counted')::int = 9 and (pg_temp.tx('p:portal')::jsonb->>'not_yet_visited')::int = 9
    and (pg_temp.tx('p:portal')::jsonb->>'tier_reached')::int = 8 and (pg_temp.tx('p:portal')::jsonb->>'next_tier')::int = 12
    and pg_temp.tx('p:portal')::jsonb->'campaign'->>'code' = 'T534-A-' || pg_temp.tx('sfx'),
  'P3 Rita''s own portal shows 9 counted, tier 8, next 12, 9 not counted yet: ' || pg_temp.tx('p:portal'));
-- Promotion B (ended): Ravi's four friends sent their forms 15 days ago, one reviewed, one with a
-- note, two nobody wrote on; Rosa's two friends' forms nobody wrote on. Tiers 2 and 4.
do $$
declare k text; n int := 60; v uuid;
begin
  foreach k in array array['g1', 'g2', 'g3', 'g4'] loop
    perform pg_temp.friend(k, 'ref2', n, pg_temp.d(-18)); n := n + 1;
    perform pg_temp.form(k, k, 'centre', pg_temp.d(-15), pg_temp.d(-15));
  end loop;
  foreach k in array array['h1', 'h2'] loop
    perform pg_temp.friend(k, 'ref3', n, pg_temp.d(-18)); n := n + 1;
    perform pg_temp.form(k, k, 'centre', pg_temp.d(-15), pg_temp.d(-15));
  end loop;
  update public.health_surveys set reviewed_at = now(), reviewed_by = pg_temp.fx('mgr'), acidity_result = 'green'
   where id = pg_temp.fx('form:g1');
  insert into public.consultant_notes(survey_id, customer_id, remarks_condition, created_by)
  values (pg_temp.fx('form:g4'), pg_temp.fx('g4'), 'Shoulder', pg_temp.fx('mgr'));
end $$;
select pg_temp.put('p:ravi', pg_temp.as_login('own', format(
  'select public.give_referral_campaign_reward(%L, %L, %L, %L::jsonb, %L)::text', 'T534-B-' || pg_temp.tx('sfx'), pg_temp.fx('ref2'),
  pg_temp.fx('st'), json_build_array(json_build_object('product_id', pg_temp.fx('gift'), 'quantity', 1)), 'T534 reward')));
select pg_temp.check(pg_temp.tx('p:ravi') like '{%' and (pg_temp.tx('p:ravi')::jsonb->>'tier')::int = 2
    and (pg_temp.tx('p:ravi')::jsonb->>'friends_counted')::int = 2
    and (select tier = 2 and friends_counted = 2 from public.referral_campaign_rewards
          where campaign_id = pg_temp.fx('campB') and referrer_customer_id = pg_temp.fx('ref2') and voided_at is null)
    and (select current_qty from public.store_inventory where store_id = pg_temp.fx('st') and product_id = pg_temp.fx('gift')) = 4,
  'P4 Ravi''s reward is for tier 2 with 2 friends counted (the reviewed form and the one with a note; before 534 '
  || (select count(*) filter (where counted) from pg_temp.t534_before(pg_temp.fx('campB')) f where f.referrer_customer_id = pg_temp.fx('ref2'))
  || ' counted, tier 4), and one gift leaves the store: ' || pg_temp.tx('p:ravi'));
select pg_temp.put('p:rosa', pg_temp.as_login('own', format(
  'select public.give_referral_campaign_reward(%L, %L, %L, %L::jsonb, %L)::text', 'T534-B-' || pg_temp.tx('sfx'), pg_temp.fx('ref3'),
  pg_temp.fx('st'), json_build_array(json_build_object('product_id', pg_temp.fx('gift'), 'quantity', 1)), 'T534 reward')));
select pg_temp.check(pg_temp.tx('p:rosa') like 'ERROR: T534 Rosa Referrer has 0 friend(s) counted, fewer than the first tier (2).'
    and not exists (select 1 from public.referral_campaign_rewards where campaign_id = pg_temp.fx('campB') and referrer_customer_id = pg_temp.fx('ref3'))
    and (select current_qty from public.store_inventory where store_id = pg_temp.fx('st') and product_id = pg_temp.fx('gift')) = 4,
  'P5 Rosa, whose friends'' forms nobody wrote on, has not reached the first tier: refused, no reward recorded, no stock taken (before 534 '
  || (select count(*) filter (where counted) from pg_temp.t534_before(pg_temp.fx('campB')) f where f.referrer_customer_id = pg_temp.fx('ref3'))
  || ' counted, tier 2): ' || pg_temp.tx('p:rosa'));
select pg_temp.put('p:reportB', pg_temp.as_login('mgr', format('select public.referral_campaign_report(%L)::text', 'T534-B-' || pg_temp.tx('sfx'))));
select pg_temp.check((select (r->>'counted')::int = 2 and (r->>'not_yet_visited')::int = 2 and (r->'reward'->>'tier')::int = 2
                        from jsonb_array_elements(pg_temp.tx('p:reportB')::jsonb->'referrers') r
                       where r->>'referrer_customer_id' = pg_temp.fx('ref2')::text)
    and (select (r->>'counted')::int = 0 and (r->>'not_yet_visited')::int = 2 and r->'reward' = 'null'::jsonb
                        from jsonb_array_elements(pg_temp.tx('p:reportB')::jsonb->'referrers') r
                       where r->>'referrer_customer_id' = pg_temp.fx('ref3')::text),
  'P6 promotion B''s report (a Manager): Ravi 2 counted and 2 not yet visited, with his tier 2 reward; Rosa 0 counted, 2 not yet visited, no reward');

-- ═════ V The visit rule and the "Visited" screens are unchanged ═════
select pg_temp.check(exists (select 1 from public.customer_centre_visits() v where v.customer_id = pg_temp.fx('none')
                               and v.first_visit_on = pg_temp.d(-4) and v.visit_kind = 'centre_link')
    and exists (select 1 from public.customer_centre_visit_days() d where d.customer_id = pg_temp.fx('none')
                  and d.visit_kind = 'centre_link' and d.sent_on = pg_temp.d(-3) and d.visit_on = pg_temp.d(-4)),
  'V1 the Customers page''s first visit is as before: an unreviewed form is still a visit there, dated the date typed on it');
select pg_temp.check(md5(pg_get_functiondef('public.customer_centre_visit_days()'::regprocedure)) = '2129857d6ff9f29dcf2cbccc9f13e5bc'
    and md5(pg_get_functiondef('public.customer_centre_visits()'::regprocedure)) = 'c07a5a0cbbf52ba45e5dc911b20002da',
  'V2 customer_centre_visit_days and customer_centre_visits are their production text');
do $$
declare v int;
begin
  -- Production-like rows (any promotion this file did not make): how many friends' rows 534
  -- changes. A count only; no row is printed. (24 Nov 2026: none.)
  select count(*) into v from (
    (select rc.id, f.* from public.referral_campaigns rc, lateral pg_temp.t534_before(rc.id) f where rc.code not like 'T534-%'
     except select rc.id, f.* from public.referral_campaigns rc, lateral public.referral_campaign_friends(rc.id) f where rc.code not like 'T534-%')
    union all
    (select rc.id, f.* from public.referral_campaigns rc, lateral public.referral_campaign_friends(rc.id) f where rc.code not like 'T534-%'
     except select rc.id, f.* from public.referral_campaigns rc, lateral pg_temp.t534_before(rc.id) f where rc.code not like 'T534-%')) x;
  raise notice 'NOTE  on the promotions already on this copy, 534 changes % friend row(s) (a count only)', v;
end $$;

-- ═════ G The function, what it relies on, and who can write what makes a form count ═════
\if :t534_in
select pg_temp.check(md5(pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) = '59d2cf59d32a59f02bd8504b36707a20'
    and position('534 (security audit' in pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) > 0
    and (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.referral_campaign_friends(uuid)'::regprocedure) = 'postgres=X/postgres,service_role=X/postgres'
    and not has_function_privilege('anon', 'public.referral_campaign_friends(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.referral_campaign_friends(uuid)', 'execute')
    and (select p.prosecdef and p.provolatile = 's' and p.prolang = (select oid from pg_language where lanname = 'sql')
                and p.proconfig = array['search_path=public']
                and pg_get_function_result(p.oid) = 'TABLE(referrer_customer_id uuid, friend_customer_id uuid, referred_on date, first_visit_on date, counted boolean)'
           from pg_proc p where p.oid = 'public.referral_campaign_friends(uuid)'::regprocedure)
    and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'referral_campaign_friends') = 1,
  'G1 referral_campaign_friends is 534''s (59d2cf59...), marked, the owner''s and the service role''s alone, SQL, STABLE, SECURITY DEFINER, search_path public, its return type as before, no overload');
\endif
select pg_temp.check(md5(pg_get_functiondef('public.referral_campaign_report(text)'::regprocedure)) = '018b34673b2f32fd146d8d5e9c791d1a'
    and md5(pg_get_functiondef('public.give_referral_campaign_reward(text,uuid,uuid,jsonb,text)'::regprocedure)) = 'db5bae60bc6bf65d2ae206a031ff62eb'
    and md5(pg_get_functiondef('public.affiliate_portal_campaign_progress()'::regprocedure)) = 'cc07104f1bda30a36468f615c9fbb410'
    and md5(pg_get_functiondef('public.review_health_survey(uuid,text,text,text,text,boolean)'::regprocedure)) = '46bddd90d9badfae99cff53379275e64'
    and md5(pg_get_functiondef('public.add_consultant_note(uuid,uuid,text,text,text,text,jsonb)'::regprocedure)) = 'aea5303b89708bb9d1f2d5434b9b0813'
    and md5(pg_get_functiondef('public.add_survey_attachment(uuid,text,text,text,integer,text)'::regprocedure)) = 'a856b3463d4e9c8784e2cf1e6d2b649b'
    and md5(pg_get_functiondef('public.upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)'::regprocedure)) = 'e5e6922d5fbe16ee81d44246cabd9d60'
    and md5(pg_get_functiondef('public.update_survey_particulars_v2(uuid,jsonb,text)'::regprocedure)) = 'c8df8ff415d633bd29a1d6cd752eff73',
  'G2 the three callers, the three writers, the consultant''s record and the particulars are their production text (unchanged by 534)');
select pg_temp.check(pg_temp.as_login('stf', format('select public.review_health_survey(p_survey_id => %L, p_acidity => %L)::text', pg_temp.fx('form:none'), 'red')) like 'ERROR: %'
    and pg_temp.as_login('stf', format('select public.add_consultant_note(%L, null, null, %L, null, null)::text', pg_temp.fx('form:none'), 'x')) like 'ERROR: %'
    and pg_temp.as_login(null, format('select public.review_health_survey(p_survey_id => %L, p_acidity => %L)::text', pg_temp.fx('form:none'), 'red')) like 'ERROR: %'
    and pg_temp.as_login(null, format('select public.add_consultant_note(%L, null, null, %L, null, null)::text', pg_temp.fx('form:none'), 'x')) like 'ERROR: %'
    and pg_temp.as_login(null, format('select public.add_survey_attachment(%L, %L, %L)::text', pg_temp.fx('form:none'), 'x', 'x')) like 'ERROR: %',
  'G3 Staff and a signed-out caller cannot save a review or a note, and signed out no file: refused');
select pg_temp.put('g:anon_upd', pg_temp.as_login(null, format(
  'with u as (update public.health_surveys set reviewed_at = now(), acidity_result = ''red'' where id = %L returning 1) select count(*)::text from u',
  pg_temp.fx('form:none'))));
select pg_temp.put('g:anon_note', pg_temp.as_login(null, format(
  'with i as (insert into public.consultant_notes(survey_id, health_goals) values (%L, ''x'') returning 1) select count(*)::text from i', pg_temp.fx('form:none'))));
select pg_temp.put('g:anon_file', pg_temp.as_login(null, format(
  'with i as (insert into public.health_survey_attachments(survey_id, storage_path, file_name) values (%L, ''t534/x'', ''x'') returning 1) select count(*)::text from i',
  pg_temp.fx('form:none'))));
select pg_temp.put('g:stf_upd', pg_temp.as_login('stf', format(
  'with u as (update public.health_surveys set reviewed_at = now(), acidity_result = ''red'' where id = %L returning 1) select count(*)::text from u',
  pg_temp.fx('form:none'))));
select pg_temp.check(pg_temp.tx('g:anon_upd') in ('0') or pg_temp.tx('g:anon_upd') like 'ERROR: %',
  'G4 signed out, the table API cannot set a review on a form: ' || pg_temp.tx('g:anon_upd'));
select pg_temp.check(pg_temp.tx('g:anon_note') like 'ERROR: %' and pg_temp.tx('g:anon_file') like 'ERROR: %'
    and (pg_temp.tx('g:stf_upd') = '0' or pg_temp.tx('g:stf_upd') like 'ERROR: %'),
  'G5 signed out, the table API cannot add a note or a file; Staff cannot set a review: ' || concat_ws(' / ', pg_temp.tx('g:anon_note'),
  pg_temp.tx('g:anon_file'), pg_temp.tx('g:stf_upd')));
select pg_temp.check((select reviewed_at is null and acidity_result is null from public.health_surveys where id = pg_temp.fx('form:none'))
    and not exists (select 1 from public.consultant_notes where survey_id = pg_temp.fx('form:none'))
    and not exists (select 1 from public.health_survey_attachments where survey_id = pg_temp.fx('form:none')),
  'G6 after those tries the form has no review, note or file');
-- A function that writes what makes a visit count: a note, a file, reviewed_at, or a finding (by
-- update, or by an insert that names one of those columns).
create function pg_temp.writes_count(src text) returns boolean language sql immutable as
$$ select src ~* '(insert\s+into|update)\s+(public\.)?(consultant_notes|health_survey_attachments)\M'
       or src ~* '\mreviewed_at\s*='
       or src ~* 'update\s+(public\.)?health_surveys\s+(\w+\s+)?set[^;]*\m(acidity_result|remarks_condition|remarks_recommendation|health_goals)\s*='
       or src ~* 'insert\s+into\s+(public\.)?health_surveys\s*\([^)]*\m(reviewed_at|acidity_result|remarks_condition|remarks_recommendation|health_goals)\M' $$;
select pg_temp.put('g:writers', (
  select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '')
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and has_function_privilege('anon', p.oid, 'execute') and pg_temp.writes_count(p.prosrc)));
select pg_temp.check(pg_temp.tx('g:writers') = '',
  'G7 no function a signed-out caller can run writes reviewed_at, a finding, a consultant note or a file: [' || pg_temp.tx('g:writers') || ']');
select pg_temp.put('g:writers_in', (
  select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '')
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and has_function_privilege('authenticated', p.oid, 'execute') and pg_temp.writes_count(p.prosrc)));
select pg_temp.check(pg_temp.tx('g:writers_in') = 'add_consultant_note(uuid,uuid,text,text,text,text,jsonb), add_survey_attachment(uuid,text,text,text,integer,text), review_health_survey(uuid,text,text,text,text,boolean), upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)',
  'G8 for a signed-in login only the four pinned functions write them (each an Owner''s or Manager''s for that writing): [' || pg_temp.tx('g:writers_in') || ']');

-- ═════ M 534 again, and its guards ═════
\if :{?control}
\elif :{?skip_install}
\else
select pg_temp.check(:'t534_again_msg' = '534 is already in on this database; nothing was changed.'
    and not exists (select 1 from m534 m
                      full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) n
                        on n.fn = m.fn
                     where m.fn is null or n.fn is null or m.md5 <> n.md5 or m.acl is distinct from n.acl),
  'M1 534 a second time refuses "already in" and changes nothing: ' || :'t534_again_msg');
\endif

-- ═════ U The undo ═════
\if :t534_in
\ir ../undo-534.sql
select pg_temp.check(md5(pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) = 'b5f4f76d7d22369ee4706a4b5f9dd465'
    and (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.referral_campaign_friends(uuid)'::regprocedure) = 'postgres=X/postgres,service_role=X/postgres'
    and pg_temp.fr('none') = pg_temp.row_of(true, pg_temp.d(-3)) and pg_temp.fr('twob') = 'not listed',
  'U1 undo-534 puts the function back exactly (b5f4f76d...) with its grants: the unreviewed form counts again (' || pg_temp.fr('none') || ')');
savepoint t534_undo2;
\set ON_ERROR_STOP off
\ir ../undo-534.sql
\set ON_ERROR_STOP on
rollback to savepoint t534_undo2;
release savepoint t534_undo2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' = 'undo 534: public.referral_campaign_friends(uuid) is already as before 534; nothing was changed.',
  'U2 a second undo refuses: ' || :'LAST_ERROR_MESSAGE');
-- The guards, on the version before 534: a relied-on function changed; a write rule wider than
-- is_owner_or_manager(); the function at another version.
savepoint t534_g1;
create or replace function public.customer_centre_visit_days()
returns table(customer_id uuid, survey_id uuid, visit_kind text, visit_on date, submitted_at timestamptz, sent_on date)
language sql stable security definer set search_path = public
as $f$ select null::uuid, null::uuid, null::text, null::date, null::timestamptz, null::date where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it.sql
\set ON_ERROR_STOP on
rollback to savepoint t534_g1;
release savepoint t534_g1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '534: public.customer_centre_visit_days() is missing or not the version this was tested against.%',
  'U3 534 refuses when the visit rule it reads is another text: ' || :'LAST_ERROR_MESSAGE');
savepoint t534_g2;
create policy "t534 anyone notes" on public.consultant_notes for insert to anon with check (true);
\set ON_ERROR_STOP off
\ir ../../../supabase/534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it.sql
\set ON_ERROR_STOP on
rollback to savepoint t534_g2;
release savepoint t534_g2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '534: public.consultant_notes has a write rule that asks more than is_owner_or_manager() (t534 anyone notes).%',
  'U4 534 refuses when a table staff write on has a wider write rule: ' || :'LAST_ERROR_MESSAGE');
savepoint t534_g3;
create or replace function public.referral_campaign_friends(p_campaign_id uuid)
returns table(referrer_customer_id uuid, friend_customer_id uuid, referred_on date, first_visit_on date, counted boolean)
language sql stable security definer set search_path = public
as $f$ select null::uuid, null::uuid, null::date, null::date, false where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it.sql
\set ON_ERROR_STOP on
rollback to savepoint t534_g3;
release savepoint t534_g3;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '534: public.referral_campaign_friends(uuid) is not the version this was tested against (md5 %',
  'U5 534 refuses a counting function at another version: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.check(md5(pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) = 'b5f4f76d7d22369ee4706a4b5f9dd465',
  'U6 each refused run left the function as it was');
\ir ../../../supabase/534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it.sql
select pg_temp.check(md5(pg_get_functiondef('public.referral_campaign_friends(uuid)'::regprocedure)) = '59d2cf59d32a59f02bd8504b36707a20'
    and pg_temp.fr('none') = 'false/-' and pg_temp.fr('rev') = pg_temp.row_of(true, pg_temp.d(-3)),
  'U7 534 again after the undo: its version, the unreviewed form does not count, the reviewed one does');
\endif

-- With -v control=1 (a copy without 534) exactly these fail, the fault 534 closes (run 25 Nov 2026):
--   on a copy of production after 533 (with or without 537; 31 pass, 18 fail; G1, M and U are
--   skipped): A2 (530 holds the form; Staff attaching it is what makes it count), R5-R9 (a form
--   nobody wrote on counts), K4 and K5 (a consultant's record with only a Staff login's yes/no
--   answer counts), F1-F4 (it is the first visit, and hides nothing), P1-P6 (the report and the
--   portal count 17 for Rita, Ravi's reward is for tier 4, Rosa's for tier 2);
--   on a copy after 529 alone (29 pass, 18 fail): A1 in place of A2 (the form goes to the friend at
--   once, so the two signed-out calls make a friend who counts), and the same others.
-- With 534 in, every check passes: 58 after 533 (install), 56 after 529 alone (A2a and A2b do not
-- run there), one fewer with -v skip_install=1 (M1 is skipped).
do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 534 checks passed.';
end $$;
rollback;
