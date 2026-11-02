-- A form's email no longer goes onto a customer record that has a portal
-- login or an affiliate record, not even when staff attach or link a held
-- one (485).
--
-- The Owner, 2 Nov 2026 (484's Q4, both orders): the QR health form and the
-- event website's registration must not put an email on such a record, as
-- 484's proof (d) takes a login whose verified email is its record's as
-- proven. Everything else they fill, they fill as before; on any other
-- record they fill a blank email as before.
--
--   Q  The QR form, signed out, for records it finds by phone and name: an
--      affiliate's record (active, suspended, inactive, deleted), a portal
--      login's (claimed, disabled) and one with both keep their email (none,
--      or an empty one) and take the occupation, date of birth, sex and
--      source as before; each form keeps the email typed and names its
--      customer; every reply has the same shape. A plain record: a missing
--      email is filled with the email typed; an empty or a set one stays (all
--      as before). Someone new: a customer with the email typed.
--   P  484's reverse order (where 484 is in), with the join and the
--      verification simulated: a login joined to a record with no email, not
--      proven, sends the QR form with its own email and verifies its inbox:
--      the record keeps no email and the login stays unproven.
--   S  Staff (an active Owner, signed in), the Owner, 2 Nov 2026: neither
--      staff path copies the email. Attaching a held QR form: an affiliate's
--      record (active, suspended, inactive, deleted) and a portal login's
--      (claimed, disabled) keep a missing email, an empty one and a set one
--      exactly, and take the other empty details; a plain record takes the
--      email typed when it has none, and keeps an empty or a set one (as
--      before). Linking a held registration on the Event page: an
--      affiliate's record (active, suspended) and a portal login's keep a
--      missing email and take the source the event names; a plain record
--      takes the email typed (as before).
--   E  The event website's registration, as its server (the fill it calls,
--      event_web_fill_customer, run directly): an affiliate's record (active,
--      suspended, inactive, deleted), a portal login's (claimed, disabled) and
--      one with both keep their email exactly (also an empty one and one with
--      spaces around it) and still take the source an event names; one with
--      nothing else to fill is not updated at all. A plain record's blank email (none, or empty) is
--      filled, trimmed; a plain record updated for its source has its email
--      trimmed; one with nothing to fill is not updated (all as before).
--   G  Grants: the QR form is a signed-out endpoint; the registration's fill
--      is the server's only.
--   U  UNDO, as written in 485's header (its DO block; the header's begin,
--      lock timeout and commit are this file's transaction): the three
--      functions go back to their versions before 485 and the history row holding the
--      text goes; a second UNDO is refused and changes nothing; 485 installs
--      again.
--   M  485 installs itself here twice (unless -v skip_install=1, where it is
--      in); the second run changes nothing; the functions are its AFTER.
--
-- Every check runs, then the file fails if any did. Disposable database
-- only; everything is rolled back. Needs production as of 2 Nov 2026 (head
-- 484). Every name, phone and email below is invented: phones from the
-- ACMA's fictional range (+61 2 5550 4850 to 4899), emails @example.invalid.
--   psql -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/survey/tests/affiliate-email-485.sql
\set ON_ERROR_STOP on
begin;
\if :{?skip_install}
create temp table m485 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\else
\ir ../../../supabase/485_forms_do_not_fill_affiliate_record_email.sql
create temp table m485 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\ir ../../../supabase/485_forms_do_not_fill_affiliate_record_email.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '120s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k=key $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.as_staff() returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true),
          set_config('request.jwt.claim.role', 'authenticated', true),
          set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx('owner'), 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_server() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', '', true),
          set_config('request.jwt.claims', '', true) $$;
create function pg_temp.mail(local text) returns text language sql as
$$ select 'z485-' || local || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
-- A customer (key c:<key>) with the next fictional phone, the email given and:
-- plain; aff (an active affiliate record), susp (suspended), inactive, soft (deleted);
-- login (a claimed portal login, no affiliate record), dis (a disabled one);
-- both (a claimed login and an active affiliate record); q4 (both, the login
-- joined a day later on the phone alone: not proven, its email not verified).
create function pg_temp.cust(key text, last text, email text, kind text) returns void language plpgsql as
$$declare c uuid; u uuid; a uuid; n int := (select count(*) from fx where k like 'c:%');
begin
  if n >= 49 then raise exception 'out of fictional phones'; end if;
  insert into customers(full_name, phone, email) values ('Zed485 ' || last, '+6125550' || (4850 + n), email) returning id into c;
  insert into fx values ('c:' || key, c);
  if kind in ('aff', 'susp', 'inactive', 'soft', 'both', 'q4') then
    insert into customer_affiliates(customer_id, status, manually_suspended, deleted_at)
    values (c, case kind when 'susp' then 'suspended_manual' when 'soft' then 'soft_deleted' when 'inactive' then 'inactive' else 'active' end,
            kind = 'susp', case when kind = 'soft' then now() end)
    returning id into a;
  end if;
  if kind in ('login', 'dis', 'both', 'q4') then
    u := gen_random_uuid(); insert into fx values ('u:' || key, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, pg_temp.mail('login-' || key), now());
    -- the welcome-WhatsApp trigger off for this insert only
    set local session_replication_role = replica;
    insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status, created_at)
    values (u, c, a, case when kind = 'dis' then 'disabled' else 'claimed' end,
            case when kind = 'q4' then now() + interval '1 day' else now() end);
    set local session_replication_role = origin;
  end if;
end$$;
create function pg_temp.phone(key text) returns text language sql as
$$ select phone from customers where id = pg_temp.fx('c:' || key) $$;
-- The QR form as the public page sends it, signed out; the reply (or the
-- error) under 'qr:<key>'.
create function pg_temp.qr(key text, last text, phone text, email text) returns void language plpgsql as
$$declare tok text := pg_temp.tx('token'); src text := pg_temp.fx('src')::text; r jsonb; e text;
begin
  begin
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
    r := public.submit_health_survey(tok, jsonb_build_object('first_name', 'Zed485', 'last_name', last, 'phone', phone,
           'email', email, 'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', src, 'sex', 'female',
           'date_of_birth', '1980-02-03', 'occupation', 'Tester'), null, null);
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then e := sqlerrm;
  end;
  insert into tx values ('qr:' || key, coalesce(r::text, 'ERROR: ' || e)) on conflict (k) do update set v = excluded.v;
end$$;
-- A registration of one person (the customer c:<cust>) for an event ('ev'
-- has no website settings; 'ev2' names a source), as the website's server,
-- then the fill; whether the customer's row was updated under 'touched:<key>'.
create function pg_temp.reg(key text, cust text, ev text, p_email text) returns void language plpgsql as
$$declare r uuid; p uuid; c0 text; c1 text; h text := md5(key || pg_temp.tx('sfx'));
begin
  insert into event_registrations(event_id, registration_id, people_count, people_md5)
  values (pg_temp.fx(ev), 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(h, 1, 8)), 1, h)
  returning id into r;
  insert into event_registration_people(registration_ref, event_id, position, first_name, full_name, phone, phone_norm,
         days, match, upgrade_token, email, customer_id)
  select r, pg_temp.fx(ev), 1, 'Zed485', c.full_name, c.phone, public.normalize_customer_phone(c.phone), array[public.sg_today()],
         'exact', 'vip_' || translate(substr(h || md5(h), 1, 26), '0189', 'wxyz'), p_email, c.id
    from customers c where c.id = pg_temp.fx('c:' || cust)
  returning id into p;
  select ctid::text into c0 from customers where id = pg_temp.fx('c:' || cust);
  perform public.event_web_fill_customer(pg_temp.fx('c:' || cust), p);
  select ctid::text into c1 from customers where id = pg_temp.fx('c:' || cust);
  insert into tx values ('touched:' || key, (c0 is distinct from c1)::text) on conflict (k) do update set v = excluded.v;
  insert into tx values ('regmail:' || key, p_email) on conflict (k) do update set v = excluded.v;
end$$;
create function pg_temp.email(cust text) returns text language sql as
$$ select email from customers where id = pg_temp.fx('c:' || cust) $$;
-- What the QR form fills besides the email.
create function pg_temp.rest(cust text) returns text language sql as
$$ select concat_ws('|', occupation, date_of_birth, gender, source_option_id = pg_temp.fx('src'))
     from customers where id = pg_temp.fx('c:' || cust) $$;
create function pg_temp.form(key text) returns public.health_surveys language sql as
$$ select s from public.health_surveys s where s.id = (pg_temp.tx('qr:' || key)::jsonb ->> 'survey_id')::uuid $$;

select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = '860743f4f2e92f669e257121de0a9308'
    and md5(pg_get_functiondef('public.event_web_fill_customer(uuid,uuid)'::regprocedure)) = '4cefb8a7ae96aa5836041cf57cb3f33f'
    and md5(pg_get_functiondef('public.attach_held_health_survey(uuid,uuid,text)'::regprocedure)) = '8a66d8e6d7008c79d94c5b20ffecb4df',
  'P0 485 is installed (the three functions are its AFTER versions)');
select pg_temp.check(not exists (select 1 from customers where public.normalize_customer_phone(phone) between '+61255504850' and '+61255504899'),
  'P0 no customer uses the test phones +61 2 5550 4850 to 4899 (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); c uuid; u uuid;
begin
  insert into tx values ('sfx', sfx), ('token', 'z485-' || sfx);
  u := gen_random_uuid(); insert into fx values ('owner', u);
  insert into auth.users(id, email, email_confirmed_at) values (u, 'z485-o-' || sfx || '@example.invalid', now());
  insert into profiles(id, full_name, email, role, is_active) values (u, 'Z485 Owner', 'z485-o-' || sfx || '@example.invalid', 'owner', true);
  insert into stores(name, code) values ('Z485 Test Store', 'Z485' || sfx) returning id into c; insert into fx values ('store', c);
  insert into customer_source_options(label) values ('Z485 Walk-in ' || sfx) returning id into c; insert into fx values ('src', c);
  insert into customer_source_options(label) values ('Z485 Event ' || sfx) returning id into c; insert into fx values ('evsrc', c);
  insert into survey_links(token, store_id) values ('z485-' || sfx, pg_temp.fx('store'));
  insert into events(name) values ('Z485 Event One ' || sfx) returning id into c; insert into fx values ('ev', c);
  insert into events(name) values ('Z485 Event Two ' || sfx) returning id into c; insert into fx values ('ev2', c);
  insert into event_web_settings(event_id, code, store_id, acting_profile_id, source_option_id, source_details)
  values (pg_temp.fx('ev2'), 'Z485-' || upper(sfx), pg_temp.fx('store'), pg_temp.fx('owner'), pg_temp.fx('evsrc'), 'Z485 details');
  insert into event_stores(event_id, store_id) values (pg_temp.fx('ev2'), pg_temp.fx('store'));
end $$;
-- In this order (each takes the next phone, from +61 2 5550 4850; someone new is 4899): for the QR form ...
do $$ begin
  perform pg_temp.cust('aff', 'Aff', null, 'aff');           perform pg_temp.cust('susp', 'Susp', null, 'susp');
  perform pg_temp.cust('soft', 'Soft', null, 'soft');        perform pg_temp.cust('login', 'Login', null, 'login');
  perform pg_temp.cust('dis', 'Dis', null, 'dis');           perform pg_temp.cust('both', 'Both', null, 'both');
  perform pg_temp.cust('affe', 'Affe', '', 'aff');           perform pg_temp.cust('plain', 'Plain', null, 'plain');
  perform pg_temp.cust('pe', 'Pe', '', 'plain');             perform pg_temp.cust('set', 'Set', pg_temp.mail('kept'), 'plain');
  perform pg_temp.cust('q4', 'Qfour', null, 'q4');
  -- ... and for the registration (no source yet), 4861 to 4872.
  perform pg_temp.cust('raff', 'Raff', null, 'aff');         perform pg_temp.cust('rlogin', 'Rlogin', null, 'login');
  perform pg_temp.cust('rboth', 'Rboth', null, 'both');      perform pg_temp.cust('raffe', 'Raffe', '', 'aff');
  perform pg_temp.cust('rsrc', 'Rsrc', null, 'both');
  perform pg_temp.cust('rspace', 'Rspace', ' ' || pg_temp.mail('spaced-aff') || ' ', 'aff');
  perform pg_temp.cust('rplain', 'Rplain', null, 'plain');   perform pg_temp.cust('rpe', 'Rpe', '', 'plain');
  perform pg_temp.cust('rpspace', 'Rpspace', ' ' || pg_temp.mail('spaced-plain') || ' ', 'plain');
  perform pg_temp.cust('rpset', 'Rpset', pg_temp.mail('rpset'), 'plain');
  perform pg_temp.cust('rsoft', 'Rsoft', null, 'soft');      perform pg_temp.cust('rdis', 'Rdis', null, 'dis');
  -- ... for staff attaching a held QR form, and linking a held registration.
  perform pg_temp.cust('hsaff', 'Hsaff', null, 'aff');       perform pg_temp.cust('hslogin', 'Hslogin', null, 'login');
  perform pg_temp.cust('hsplain', 'Hsplain', null, 'plain');
  perform pg_temp.cust('esaff', 'Esaff', null, 'aff');       perform pg_temp.cust('esplain', 'Esplain', null, 'plain');
  -- ... and the other statuses and email shapes on each path.
  perform pg_temp.cust('qinactive', 'Qinactive', null, 'inactive');
  perform pg_temp.cust('rsusp', 'Rsusp', null, 'susp');      perform pg_temp.cust('rinactive', 'Rinactive', null, 'inactive');
  perform pg_temp.cust('hsdis', 'Hsdis', null, 'dis');       perform pg_temp.cust('hssoft', 'Hssoft', null, 'soft');
  perform pg_temp.cust('hssusp', 'Hssusp', null, 'susp');    perform pg_temp.cust('hsinactive', 'Hsinactive', null, 'inactive');
  perform pg_temp.cust('hsaffe', 'Hsaffe', '', 'aff');       perform pg_temp.cust('hsaffset', 'Hsaffset', pg_temp.mail('own-hsaffset'), 'aff');
  perform pg_temp.cust('hspe', 'Hspe', '', 'plain');         perform pg_temp.cust('hspset', 'Hspset', pg_temp.mail('own-hspset'), 'plain');
  perform pg_temp.cust('eslogin', 'Eslogin', null, 'login'); perform pg_temp.cust('essusp', 'Essusp', null, 'susp');
end $$;
update customers set source_option_id = pg_temp.fx('src') where id = pg_temp.fx('c:rpset');

-- ═════ Q  The QR form ═════
select pg_temp.qr(k, l, pg_temp.phone(k), pg_temp.mail('q-' || k))
  from (values ('aff', 'Aff'), ('susp', 'Susp'), ('soft', 'Soft'), ('login', 'Login'), ('dis', 'Dis'), ('both', 'Both'), ('affe', 'Affe'),
               ('plain', 'Plain'), ('pe', 'Pe'), ('set', 'Set'), ('qinactive', 'Qinactive')) v(k, l);
select pg_temp.qr('new', 'Newcomer', '+61255504899', pg_temp.mail('q-new'));
select pg_temp.check((select bool_and(pg_temp.tx('qr:' || k) not like 'ERROR:%'
                                      and (select array_agg(x order by x) from jsonb_object_keys(pg_temp.tx('qr:' || k)::jsonb) x)
                                          = array['success', 'survey_id', 'survey_no']
                                      and pg_temp.tx('qr:' || k)::jsonb -> 'success' = 'true')
                        from unnest(array['aff', 'susp', 'soft', 'login', 'dis', 'both', 'affe', 'plain', 'pe', 'set', 'qinactive', 'new']) k),
  'Q every form went through, and every reply has the same shape (success, survey_id, survey_no), whoever the record is: '
  || coalesce((select string_agg(k || '=' || left(pg_temp.tx('qr:' || k), 80), '; ')
                 from unnest(array['aff', 'susp', 'soft', 'login', 'dis', 'both', 'affe', 'plain', 'pe', 'set', 'qinactive', 'new']) k
                where pg_temp.tx('qr:' || k) like 'ERROR:%'), 'none failed'));
select pg_temp.check(pg_temp.email(k) is null, 'Q a record with ' || d || ' keeps no email after the QR form')
  from (values ('aff', 'an active affiliate record'), ('susp', 'a suspended affiliate record'), ('soft', 'a deleted affiliate record'),
               ('qinactive', 'an inactive affiliate record'),
               ('login', 'a claimed portal login and no affiliate record'), ('dis', 'a disabled portal login'),
               ('both', 'a portal login and an affiliate record')) t(k, d);
select pg_temp.check(pg_temp.email('affe') = '', 'Q an affiliate''s record with an empty email keeps it empty (as before: only a missing email was ever filled)');
select pg_temp.check(pg_temp.rest(k) = 'Tester|1980-02-03|female|t', 'Q the record with ' || k || ' still takes the occupation, date of birth, sex and source: ' || coalesce(pg_temp.rest(k), 'null'))
  from unnest(array['aff', 'susp', 'soft', 'login', 'dis', 'both', 'plain', 'qinactive']) k;
select pg_temp.check((pg_temp.form(k)).email = pg_temp.mail('q-' || k) and (pg_temp.form(k)).customer_id = pg_temp.fx('c:' || k),
  'Q the form for ' || k || ' keeps the email typed and names its customer')
  from unnest(array['aff', 'susp', 'soft', 'login', 'dis', 'both', 'affe', 'plain', 'pe', 'set', 'qinactive']) k;
select pg_temp.check(pg_temp.email('plain') = pg_temp.mail('q-plain'), 'Q a plain record with no email takes the email typed (as before)');
select pg_temp.check(pg_temp.email('pe') = '', 'Q a plain record with an empty email keeps it empty (as before)');
select pg_temp.check(pg_temp.email('set') = pg_temp.mail('kept'), 'Q a plain record''s own email stays (as before)');
select pg_temp.check((select c.email = pg_temp.mail('q-new') and c.full_name = 'Zed485 Newcomer'
                        from customers c where c.id = (pg_temp.form('new')).customer_id),
  'Q someone new: the form makes a customer with the email typed (as before)');

-- ═════ P  484's reverse order ═════
do $$ begin
  if to_regprocedure('public.affiliate_login_link_proof(uuid,uuid)') is null then
    raise notice 'SKIP  P (484 is not in this database)'; return; end if;
  perform pg_temp.check(public.affiliate_login_link_proof(pg_temp.fx('u:q4'), pg_temp.fx('c:q4')) is null,
    'P the login joined on the phone alone is not proven before');
  perform pg_temp.qr('q4', 'Qfour', pg_temp.phone('q4'), pg_temp.mail('login-q4'));
  update affiliate_accounts set email_verified_at = now() where auth_user_id = pg_temp.fx('u:q4');
  perform pg_temp.check(pg_temp.tx('qr:q4') not like 'ERROR:%' and pg_temp.email('q4') is null
                          and (pg_temp.form('q4')).email = pg_temp.mail('login-q4'),
    'P its QR form with the login''s own email goes through, the form keeps that email, the record keeps none');
  perform pg_temp.check(public.affiliate_login_link_proof(pg_temp.fx('u:q4'), pg_temp.fx('c:q4')) is null,
    'P with its inbox verified, the login is still not proven (no email of its own on the record)');
end $$;

-- ═════ E  The event website's registration ═════
select pg_temp.reg('raff', 'raff', 'ev', ' ' || pg_temp.mail('e-raff') || ' '), pg_temp.reg('rlogin', 'rlogin', 'ev', pg_temp.mail('e-rlogin')),
       pg_temp.reg('rboth', 'rboth', 'ev', pg_temp.mail('e-rboth')), pg_temp.reg('raffe', 'raffe', 'ev', pg_temp.mail('e-raffe')),
       pg_temp.reg('rsrc', 'rsrc', 'ev2', pg_temp.mail('e-rsrc')), pg_temp.reg('rspace', 'rspace', 'ev2', pg_temp.mail('e-rspace')),
       pg_temp.reg('rplain', 'rplain', 'ev', ' ' || pg_temp.mail('e-rplain') || ' '), pg_temp.reg('rpe', 'rpe', 'ev', pg_temp.mail('e-rpe')),
       pg_temp.reg('rpspace', 'rpspace', 'ev2', pg_temp.mail('e-rpspace')), pg_temp.reg('rpset', 'rpset', 'ev', pg_temp.mail('e-rpset')),
       pg_temp.reg('rsoft', 'rsoft', 'ev', pg_temp.mail('e-rsoft')), pg_temp.reg('rdis', 'rdis', 'ev', pg_temp.mail('e-rdis')),
       pg_temp.reg('rsusp', 'rsusp', 'ev', pg_temp.mail('e-rsusp')), pg_temp.reg('rinactive', 'rinactive', 'ev', pg_temp.mail('e-rinactive'));
select pg_temp.check(pg_temp.email(k) is null and pg_temp.tx('touched:' || k) = 'false',
  'E a record with ' || d || ' keeps no email and, with nothing else to fill, is not updated at all')
  from (values ('raff', 'an affiliate record'), ('rlogin', 'a portal login'), ('rboth', 'both'),
               ('rsoft', 'a deleted affiliate record'), ('rdis', 'a disabled portal login'),
               ('rsusp', 'a suspended affiliate record'), ('rinactive', 'an inactive affiliate record')) t(k, d);
select pg_temp.check(pg_temp.email('raffe') = '' and pg_temp.tx('touched:raffe') = 'false',
  'E an affiliate''s record with an empty email keeps it empty and is not updated');
select pg_temp.check((select c.email is null and c.source_option_id = pg_temp.fx('evsrc') and c.source_label = 'Z485 Event ' || pg_temp.tx('sfx')
                             and c.source_details = 'Z485 details'
                        from customers c where c.id = pg_temp.fx('c:rsrc')),
  'E a record with a login and an affiliate record still takes the source the event names, and no email');
select pg_temp.check((select c.email = ' ' || pg_temp.mail('spaced-aff') || ' ' and c.source_option_id = pg_temp.fx('evsrc')
                        from customers c where c.id = pg_temp.fx('c:rspace')),
  'E an affiliate''s record updated for its source keeps its email exactly (not even trimmed)');
select pg_temp.check(pg_temp.email('rplain') = pg_temp.mail('e-rplain') and pg_temp.tx('touched:rplain') = 'true',
  'E a plain record with no email takes the email registered, trimmed (as before)');
select pg_temp.check(pg_temp.email('rpe') = pg_temp.mail('e-rpe'), 'E a plain record with an empty email takes the email registered (as before)');
select pg_temp.check((select c.email = pg_temp.mail('spaced-plain') and c.source_option_id = pg_temp.fx('evsrc')
                        from customers c where c.id = pg_temp.fx('c:rpspace')),
  'E a plain record updated for its source has its own email trimmed (as before)');
select pg_temp.check(pg_temp.email('rpset') = pg_temp.mail('rpset') and pg_temp.tx('touched:rpset') = 'false',
  'E a plain record with an email and a source is not updated (as before)');
select pg_temp.check(count(*) = 14 and bool_and(p.email = pg_temp.tx('regmail:' || k)), 'E every registration keeps the email typed')
  from unnest(array['raff', 'rlogin', 'rboth', 'raffe', 'rsrc', 'rspace', 'rplain', 'rpe', 'rpspace', 'rpset', 'rsoft', 'rdis', 'rsusp', 'rinactive']) k
  join event_registration_people p on p.customer_id = pg_temp.fx('c:' || k) and p.event_id in (pg_temp.fx('ev'), pg_temp.fx('ev2'));

-- ═════ S  Staff attach a held QR form, and link a held registration ═════
select pg_temp.qr(k, 'Other', pg_temp.phone(k), pg_temp.mail('h-' || k))
  from unnest(array['hsaff', 'hslogin', 'hsplain', 'hsdis', 'hssoft', 'hssusp', 'hsinactive', 'hsaffe', 'hsaffset', 'hspe', 'hspset']) k;
select pg_temp.check(pg_temp.tx('qr:' || k) not like 'ERROR:%' and (pg_temp.form(k)).customer_id is null
    and exists (select 1 from health_survey_holds h where h.survey_id = (pg_temp.form(k)).id and h.resolved_at is null),
  'S a form under another name with the phone of ' || k || ' waits for staff')
  from unnest(array['hsaff', 'hslogin', 'hsplain', 'hsdis', 'hssoft', 'hssusp', 'hsinactive', 'hsaffe', 'hsaffset', 'hspe', 'hspset']) k;
select pg_temp.as_staff();
insert into tx select 'att:' || k, pg_temp.err(format('select public.attach_held_health_survey(%L, %L, %L)',
                 (pg_temp.form(k)).id, pg_temp.fx('c:' || k), 'Checked her IC at the counter'))
  from unnest(array['hsaff', 'hslogin', 'hsplain', 'hsdis', 'hssoft', 'hssusp', 'hsinactive', 'hsaffe', 'hsaffset', 'hspe', 'hspset']) k;
select pg_temp.as_server();
select pg_temp.check(pg_temp.tx('att:' || k) = 'ok' and pg_temp.email(k) is null and pg_temp.rest(k) = 'Tester|1980-02-03|female|t',
  'S staff attaching a held form to ' || d || ' leave its email empty and fill its other details: ' || pg_temp.tx('att:' || k))
  from (values ('hsaff', 'an affiliate''s record'), ('hslogin', 'a portal login''s record'), ('hsdis', 'a disabled portal login''s record'),
               ('hssoft', 'a deleted affiliate''s record'), ('hssusp', 'a suspended affiliate''s record'),
               ('hsinactive', 'an inactive affiliate''s record')) t(k, d);
select pg_temp.check(pg_temp.tx('att:hsaffe') = 'ok' and pg_temp.email('hsaffe') = ''
    and pg_temp.tx('att:hsaffset') = 'ok' and pg_temp.email('hsaffset') = pg_temp.mail('own-hsaffset'),
  'S staff attaching a held form to an affiliate''s record keep an empty or a set email exactly');
select pg_temp.check(pg_temp.tx('att:hsplain') = 'ok' and pg_temp.email('hsplain') = pg_temp.mail('h-hsplain'),
  'S staff attaching a held form to a plain record fill its missing email (as before): ' || pg_temp.tx('att:hsplain'));
select pg_temp.check(pg_temp.tx('att:hspe') = 'ok' and pg_temp.email('hspe') = ''
    and pg_temp.tx('att:hspset') = 'ok' and pg_temp.email('hspset') = pg_temp.mail('own-hspset'),
  'S staff attaching a held form to a plain record keep an empty or a set email (as before)');
do $$ declare r uuid; p uuid; k text; h text; begin
  foreach k in array array['esaff', 'esplain', 'eslogin', 'essusp'] loop
    h := md5(k || pg_temp.tx('sfx'));
    insert into event_registrations(event_id, registration_id, people_count, people_md5)
    values (pg_temp.fx('ev2'), 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(h, 1, 8)), 1, h)
    returning id into r;
    insert into event_registration_people(registration_ref, event_id, position, first_name, full_name, phone, phone_norm, days, match,
           upgrade_token, email, hold_reason, candidate_customer_ids)
    select r, pg_temp.fx('ev2'), 1, 'Zed485', 'Zed485 Other', c.phone, public.normalize_customer_phone(c.phone), array[public.sg_today()],
           'held', 'vip_' || translate(substr(h || md5(h), 1, 26), '0189', 'wxyz'), pg_temp.mail('l-' || k), 'phone_in_use', array[c.id]
      from customers c where c.id = pg_temp.fx('c:' || k)
    returning id into p;
    insert into fx values ('p:' || k, p);
  end loop;
end $$;
select pg_temp.as_staff();
insert into tx select 'link:' || k, pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)',
                 pg_temp.fx('p:' || k), pg_temp.fx('c:' || k), 'Checked by phone'))
  from unnest(array['esaff', 'esplain', 'eslogin', 'essusp']) k;
select pg_temp.as_server();
select pg_temp.check(pg_temp.tx('link:' || k) = 'ok' and pg_temp.email(k) is null
    and (select source_option_id from customers where id = pg_temp.fx('c:' || k)) = pg_temp.fx('evsrc'),
  'S staff linking a held registration to ' || d || ' leave its email empty and still fill the source the event names: '
  || pg_temp.tx('link:' || k))
  from (values ('esaff', 'an affiliate''s record'), ('eslogin', 'a portal login''s record'), ('essusp', 'a suspended affiliate''s record')) t(k, d);
select pg_temp.check(pg_temp.tx('link:esplain') = 'ok' and pg_temp.email('esplain') = pg_temp.mail('l-esplain'),
  'S staff linking a held registration to a plain record fill its empty email (as before): ' || pg_temp.tx('link:esplain'));
select pg_temp.check((select email from event_registration_people where id = pg_temp.fx('p:esaff')) = pg_temp.mail('l-esaff')
    and (pg_temp.form('hsaff')).email = pg_temp.mail('h-hsaff'),
  'S the held registration and the held form keep the email typed');

-- ═════ G  Grants ═════
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)
                     = array['anon=X/postgres', 'authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'],
  'G the QR form stays a signed-out endpoint (anon, authenticated, the owner and the service role)');
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.event_web_fill_customer(uuid,uuid)'::regprocedure)
                     = array['postgres=X/postgres', 'service_role=X/postgres']
    and not has_function_privilege('anon', 'public.event_web_fill_customer(uuid,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_fill_customer(uuid,uuid)', 'execute'),
  'G the registration''s fill stays the server''s only');
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.attach_held_health_survey(uuid,uuid,text)'::regprocedure)
                     = array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres']
    and not has_function_privilege('anon', 'public.attach_held_health_survey(uuid,uuid,text)', 'execute'),
  'G staff attaching a held form stays for signed-in staff only (not signed out)');

-- ═════ U  UNDO, as written in 485's header ═════
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('29991231000485', '485_forms_do_not_fill_affiliate_record_email', array['485 suite: a stand-in for the file''s text']);
insert into tx values ('undo1', pg_temp.err($u485$
do $undo$
declare
  c_sig constant text[] := array['submit_health_survey(text,jsonb,jsonb,text)', 'event_web_fill_customer(uuid,uuid)',
                                 'attach_held_health_survey(uuid,uuid,text)'];
  c_before constant text[] := array['014a970de2e5dee64e4027459cac5280', '89488f15e0b030b9ed14c3c31049a71e', '53aabcdd564da445131633c41bef8249'];
  c_after constant text[] := array['860743f4f2e92f669e257121de0a9308', '4cefb8a7ae96aa5836041cf57cb3f33f', '8a66d8e6d7008c79d94c5b20ffecb4df'];
  -- this file's md5 as applied (its history row's): fill in before running
  c_m constant text := 'e9b18de44761f8d632bd2f5516fa13f8';
  v_def text; v_path text := current_setting('search_path'); n int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. 3 loop
    if to_regprocedure('public.' || c_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) is distinct from c_after[i] then
      raise exception 'UNDO 485: public.% is not 485''s version; nothing changed', c_sig[i]; end if;
  end loop;
  -- The QR form: 485's lines back to 468's.
  v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[1])),
$s_new$    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
    -- any referral attribution (referred_by / referred_at / referral_source /
    -- referral_code_used).
    -- 485 (the Owner, 2 Nov 2026): nor the email of a record that has a portal
    -- login or an affiliate record: 484's proof (d) takes a login whose
    -- verified email is its record's as proven, so a form must not put an
    -- email there. The form keeps the email typed; staff may copy it.
    update public.customers
       set email             = case when email is null
                                     and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                     and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                    then v_email else email end,
$s_new$,
$s_old$    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
    -- any referral attribution (referred_by / referred_at / referral_source /
    -- referral_code_used).
    update public.customers
       set email             = coalesce(email, v_email),
$s_old$);
  if md5(v_def) <> c_before[1] then
    raise exception 'UNDO 485: the rebuilt public.% is not 468''s (md5 %); nothing changed', c_sig[1], md5(v_def); end if;
  execute v_def;
  -- The registration's fill: 485's three edits back to 436's.
  v_def := replace(replace(replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[2])),
$e_new1$  v_src public.customer_source_options%rowtype;
  -- 485 (the Owner, 2 Nov 2026): the record has a portal login or an affiliate
  -- record, so the registration leaves its email as it is (484's proof (d)
  -- reads it); the registration keeps the email typed.
  v_keep_email boolean;
begin
$e_new1$,
$e_old1$  v_src public.customer_source_options%rowtype;
begin
$e_old1$),
$e_new2$  v_keep_email := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_customer_id)
                  or exists (select 1 from public.customer_affiliates f where f.customer_id = p_customer_id);
  update public.customers
     set email             = case when v_keep_email then email
                                  else coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')) end,
$e_new2$,
$e_old2$  update public.customers
     set email             = coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')),
$e_old2$),
$e_new3$     and ((not v_keep_email and nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
$e_new3$,
$e_old3$     and ((nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
$e_old3$);
  if md5(v_def) <> c_before[2] then
    raise exception 'UNDO 485: the rebuilt public.% is not 436''s (md5 %); nothing changed', c_sig[2], md5(v_def); end if;
  execute v_def;
  -- Staff attaching a held QR form: 485's lines back to 419's.
  v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[3])),
$a_new$  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
  -- 485 (the Owner, 2 Nov 2026): never the email of a record that has a portal
  -- login or an affiliate record. Attaching decides whose form this is, not
  -- whose login, and 484's proof (d) reads that email; staff add it in Edit
  -- customer when it is theirs. The form keeps the email typed.
  update public.customers
     set email             = case when email is null
                                   and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                   and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                  then nullif(btrim(v_s.email), '') else email end,
$a_new$,
$a_old$  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
  update public.customers
     set email             = coalesce(email, nullif(btrim(v_s.email), '')),
$a_old$);
  if md5(v_def) <> c_before[3] then
    raise exception 'UNDO 485: the rebuilt public.% is not 419''s (md5 %); nothing changed', c_sig[3], md5(v_def); end if;
  execute v_def;
  for i in 1 .. 3 loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i] then
      raise exception 'UNDO 485: public.% did not go back to its version before 485', c_sig[i]; end if;
  end loop;
  -- Every 485 history row holding this file's text.
  delete from supabase_migrations.schema_migrations
   where name = '485_forms_do_not_fill_affiliate_record_email' and md5(array_to_string(statements, '')) = c_m;
  get diagnostics n = row_count;
  if n < 1 then raise exception 'UNDO 485: no 485 history row holds the text with md5 %; nothing changed', c_m; end if;
  raise notice 'UNDO 485: the three functions are back to their versions before 485; % history row(s) deleted', n;
  perform set_config('search_path', v_path, true);
end $undo$;
$u485$));
select pg_temp.check(pg_temp.tx('undo1') = 'ok'
    and md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = '014a970de2e5dee64e4027459cac5280'
    and md5(pg_get_functiondef('public.event_web_fill_customer(uuid,uuid)'::regprocedure)) = '89488f15e0b030b9ed14c3c31049a71e'
    and md5(pg_get_functiondef('public.attach_held_health_survey(uuid,uuid,text)'::regprocedure)) = '53aabcdd564da445131633c41bef8249'
    and not exists (select 1 from supabase_migrations.schema_migrations where version = '29991231000485'),
  'U UNDO puts the three functions back to their versions before 485 (468''s, 436''s and 419''s) and deletes the history row: ' || pg_temp.tx('undo1'));
select pg_temp.check(pg_temp.tx('undo1') = 'ok'
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)
                     = array['anon=X/postgres', 'authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres']
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.event_web_fill_customer(uuid,uuid)'::regprocedure) = array['postgres=X/postgres', 'service_role=X/postgres']
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.attach_held_health_survey(uuid,uuid,text)'::regprocedure)
        = array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'],
  'U UNDO (once it ran) keeps the three functions'' grants');
insert into tx values ('undo2', pg_temp.err($u485$
do $undo$
declare
  c_sig constant text[] := array['submit_health_survey(text,jsonb,jsonb,text)', 'event_web_fill_customer(uuid,uuid)',
                                 'attach_held_health_survey(uuid,uuid,text)'];
  c_before constant text[] := array['014a970de2e5dee64e4027459cac5280', '89488f15e0b030b9ed14c3c31049a71e', '53aabcdd564da445131633c41bef8249'];
  c_after constant text[] := array['860743f4f2e92f669e257121de0a9308', '4cefb8a7ae96aa5836041cf57cb3f33f', '8a66d8e6d7008c79d94c5b20ffecb4df'];
  -- this file's md5 as applied (its history row's): fill in before running
  c_m constant text := 'e9b18de44761f8d632bd2f5516fa13f8';
  v_def text; v_path text := current_setting('search_path'); n int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. 3 loop
    if to_regprocedure('public.' || c_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) is distinct from c_after[i] then
      raise exception 'UNDO 485: public.% is not 485''s version; nothing changed', c_sig[i]; end if;
  end loop;
  -- The QR form: 485's lines back to 468's.
  v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[1])),
$s_new$    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
    -- any referral attribution (referred_by / referred_at / referral_source /
    -- referral_code_used).
    -- 485 (the Owner, 2 Nov 2026): nor the email of a record that has a portal
    -- login or an affiliate record: 484's proof (d) takes a login whose
    -- verified email is its record's as proven, so a form must not put an
    -- email there. The form keeps the email typed; staff may copy it.
    update public.customers
       set email             = case when email is null
                                     and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                     and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                    then v_email else email end,
$s_new$,
$s_old$    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
    -- any referral attribution (referred_by / referred_at / referral_source /
    -- referral_code_used).
    update public.customers
       set email             = coalesce(email, v_email),
$s_old$);
  if md5(v_def) <> c_before[1] then
    raise exception 'UNDO 485: the rebuilt public.% is not 468''s (md5 %); nothing changed', c_sig[1], md5(v_def); end if;
  execute v_def;
  -- The registration's fill: 485's three edits back to 436's.
  v_def := replace(replace(replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[2])),
$e_new1$  v_src public.customer_source_options%rowtype;
  -- 485 (the Owner, 2 Nov 2026): the record has a portal login or an affiliate
  -- record, so the registration leaves its email as it is (484's proof (d)
  -- reads it); the registration keeps the email typed.
  v_keep_email boolean;
begin
$e_new1$,
$e_old1$  v_src public.customer_source_options%rowtype;
begin
$e_old1$),
$e_new2$  v_keep_email := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_customer_id)
                  or exists (select 1 from public.customer_affiliates f where f.customer_id = p_customer_id);
  update public.customers
     set email             = case when v_keep_email then email
                                  else coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')) end,
$e_new2$,
$e_old2$  update public.customers
     set email             = coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')),
$e_old2$),
$e_new3$     and ((not v_keep_email and nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
$e_new3$,
$e_old3$     and ((nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
$e_old3$);
  if md5(v_def) <> c_before[2] then
    raise exception 'UNDO 485: the rebuilt public.% is not 436''s (md5 %); nothing changed', c_sig[2], md5(v_def); end if;
  execute v_def;
  -- Staff attaching a held QR form: 485's lines back to 419's.
  v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[3])),
$a_new$  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
  -- 485 (the Owner, 2 Nov 2026): never the email of a record that has a portal
  -- login or an affiliate record. Attaching decides whose form this is, not
  -- whose login, and 484's proof (d) reads that email; staff add it in Edit
  -- customer when it is theirs. The form keeps the email typed.
  update public.customers
     set email             = case when email is null
                                   and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                   and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                  then nullif(btrim(v_s.email), '') else email end,
$a_new$,
$a_old$  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
  update public.customers
     set email             = coalesce(email, nullif(btrim(v_s.email), '')),
$a_old$);
  if md5(v_def) <> c_before[3] then
    raise exception 'UNDO 485: the rebuilt public.% is not 419''s (md5 %); nothing changed', c_sig[3], md5(v_def); end if;
  execute v_def;
  for i in 1 .. 3 loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i] then
      raise exception 'UNDO 485: public.% did not go back to its version before 485', c_sig[i]; end if;
  end loop;
  -- Every 485 history row holding this file's text.
  delete from supabase_migrations.schema_migrations
   where name = '485_forms_do_not_fill_affiliate_record_email' and md5(array_to_string(statements, '')) = c_m;
  get diagnostics n = row_count;
  if n < 1 then raise exception 'UNDO 485: no 485 history row holds the text with md5 %; nothing changed', c_m; end if;
  raise notice 'UNDO 485: the three functions are back to their versions before 485; % history row(s) deleted', n;
  perform set_config('search_path', v_path, true);
end $undo$;
$u485$));
select pg_temp.check(pg_temp.tx('undo2') like 'UNDO 485: public.submit_health_survey(text,jsonb,jsonb,text) is not 485''s version; nothing changed%'
    and md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = '014a970de2e5dee64e4027459cac5280',
  'U a second UNDO is refused and changes nothing: ' || pg_temp.tx('undo2'));
\ir ../../../supabase/485_forms_do_not_fill_affiliate_record_email.sql

-- ═════ M  Installs ═════
select pg_temp.check(not exists (select 1 from m485 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m485),
  'M running 485 a second time (and again after the UNDO) changed no function (with skip_install: nothing changed during the checks)');
select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = '860743f4f2e92f669e257121de0a9308'
    and md5(pg_get_functiondef('public.event_web_fill_customer(uuid,uuid)'::regprocedure)) = '4cefb8a7ae96aa5836041cf57cb3f33f'
    and md5(pg_get_functiondef('public.attach_held_health_survey(uuid,uuid,text)'::regprocedure)) = '8a66d8e6d7008c79d94c5b20ffecb4df',
  'M the three functions are 485''s AFTER versions');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All affiliate-email-485 checks passed.';
end $$;
rollback;
