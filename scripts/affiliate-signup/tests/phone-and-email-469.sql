-- The same phone and the same email are the same customer on the three public
-- forms (469; the Owner, 24 Oct 2026): "if both phone number and email are
-- the same, the customer should not duplicate, it should lead to the same
-- customer". Several customers with that phone and email: "No new record;
-- staff sort it". The referrer rule is kept.
--
--   R  The referral link (/r/<code>, affiliate_referral_signup):
--      R1 one record with the phone (in another format) and the email (a Gmail
--         inbox spelt another way) under another name: "already registered",
--         no customer, the record's referrer (none, or another affiliate's)
--         unchanged, a 'duplicate' event, no entry for staff;
--      R2 two records with that phone and email: the same answer, nothing
--         made, an Audit Log entry on each record;
--      R3 the phone alone (another email, or none): a new customer for 425's
--         check, as before; R4 the email alone (another phone): a new
--         customer, as before; R5 the name alone (another phone): a new
--         customer, as before;
--      R6 the referrer herself on her own phone and email under another name
--         (442): 'self_known' on file, with 442's entry ('record' among what
--         matched), never a customer;
--      R7 limits as before: the "already registered" answer is never limited,
--         but counts in the phone's 10 minutes (a new customer on it is then
--         refused); a phone 3 customers have, with one's email: "already
--         registered" (before: the phone's limit); the link's hour limit
--         counts no such try; R2's records get no second entry from the
--         tries again (at most one an hour on each record);
--      R7b an hour after the last entries, a try again writes one more on
--         each record;
--      R8 a record with an old 8-digit number that could be the phone typed
--         (425's reading) and the email: "already registered";
--      R9 namesakes (the Owner, 24 Oct 2026, as 468 reads them): two records
--         on the phone with the name typed and one of another name with the
--         phone and the email, or one of the namesakes with the email and one
--         of another name with both: the referral link's answer for several,
--         as before (the name exactly: refused as ambiguous; in the same
--         words: "already registered"), nothing made, no entry.
--   J  The affiliate sign-up (complete_affiliate_onboarding):
--      J1 a household phone, the login's email (a Gmail inbox spelt another
--         way) on one record: joined to it (rule 'phone_and_email'), no
--         record made, nothing listed;
--      J2 two records with the phone and the login's email: "identity
--         verification needed", one pending claim suggesting no one, its
--         Audit Log entry and the login's sign-up copy (440's: the name and
--         phone typed, the login's email; no account yet); again: the same
--         answer, nothing more; an Owner resolves it, and the login is in at
--         its next sign-in, its copy read for her record (440's
--         affiliate_login_signup_details);
--      J2c through her own link, her Join name (another phone and email),
--         her login email (another phone and name) or her phone (another
--         name and email): herself ('self', 442), no customer made;
--      J3 the one record with the phone and the email has a portal login: a
--         pending claim suggesting it, with its copy (before: a second
--         account on a fresh record);
--      J4 that record is protected (an Owner unlinked a login from it, 378):
--         a fresh record, listed 'protected_customer', as before;
--      J5 the phone alone on a shared phone: a fresh record, listed
--         'shared_phone', as before; J6 the one record on the phone, another
--         email and name: joined on the phone, listed 'phone_other_name', as
--         before; J7 a record whose old 8-digit number only could be the
--         phone, with the email: a pending claim suggesting it; J8 the name
--         picks one record, the email another: the name's, as before; J9 a
--         login whose claim was rejected stays rejected; J10 the email alone
--         (a phone no one has): a fresh record listed 'email_match', as
--         before;
--      J11 the name picks two records (the same name twice), one with the
--         email: joined to it; the email on a third record on that phone whose
--         name is not the one typed (the Owner, 24 Oct 2026, as 468): a
--         pending claim suggesting no one ('several_name_matches'), nothing
--         made;
--      J12 one of two namesakes with the email, and a record of another name
--         with the phone and the email too: a pending claim suggesting no
--         one, nothing made.
--   S  The seminar website (event_web_register / event_web_match_customer):
--      S1 one record with the phone and the email under another name, its
--         household's other record on the phone: linked to it
--         ('phone_and_email'), through a link 'already_customer' (no
--         referrer given), on the guest list, nothing made;
--      S2 two records with them: held 'phone_and_email_in_use', both
--         candidates, as before; S3 the phone alone: held 'phone_in_use';
--         S4 the email alone: held 'email_in_use', as before;
--      S5 a Gmail inbox spelt another way: linked; S6 the affiliate herself
--         through her own link: linked to her record, 'self'; S8 an old
--         8-digit number that could be the phone: linked;
--      S9 the name picks two records, one with the email: linked to it; the
--         email on a third record whose name is not the one typed: held
--         'several_name_matches' with the two, as before; one of the two
--         with the email and the third with both too: held
--         'several_name_matches' with all three;
--      S10 already on this event's list (449, 450): taken off the list by
--         staff, then signs up under another name with the same phone and
--         email: held 'phone_and_email_in_use' (that customer the
--         candidate), no guest back on the record; still on the list, under
--         another name: held; one form, two new people of different names
--         sharing a phone and an email: the second held; an existing
--         customer and a relative in one form: the relative held;
--      S11 merged records (441): one live record with the phone and the
--         email, and another kept record holding both through a record it
--         merged away (both, the phone only, or the email only through it):
--         held 'phone_and_email_in_use', as before; the merged-away record
--         kept by that same live record, or another kept record holding the
--         phone alone through it: linked;
--      S12 on this event's list in any way (the Owner, 24 Oct 2026): a guest
--         staff added (event_save_guest), a ticket guest from an invoice, a
--         guest staff added and took off, a sign-up staff closed: a sign-up
--         under another name with that customer's phone and email is held
--         'phone_and_email_in_use', no second guest row; under the name of
--         two customers on the phone, the email picking one on the list:
--         held 'several_name_matches' with the two; the same name as the
--         customer staff added keeps today's rules (linked, a second guest
--         row, as before 469);
--      S7 (after S12) a test key: says a live key would have linked a
--         customer not on the list, makes nothing; one on the list (S1's):
--         says held, as a live key would.
--   G  Grants: each function keeps its own; the match check allows the new
--      value and nothing else new.
--   M  469 twice changes nothing; its first run changes the four functions
--      alone; its self-test leaves no row (when this suite installs it).
--
-- Disposable database only; everything is rolled back. Needs production's
-- functions as of 466 (436..466; 462 and 463 after it, as production has them). Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/phone-and-email-469.sql
-- (with -v skip_install=1 on a database where 469 is applied, to skip
-- installing it).
-- Every name and email below is invented (@example.com, and random
-- @gmail.com / @googlemail.com test addresses); phones are ACMA's fictional
-- range (+61 2 5550 ....), one block per run, and old 8-digit numbers found at
-- run time that no customer has in any form.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true),
          set_config('request.jwt.claims', '', true) $$;
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'service_role', true),
          set_config('request.jwt.claims', '', true) $$;
create function pg_temp.as_anon() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'anon', true),
          set_config('request.jwt.claims', '', true) $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 't469-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.com' $$;
-- A random Gmail test address: 'gmail(tag)' as a login or record has it.
create function pg_temp.gmail(tag text) returns text language sql as
$$ select 't469.' || lower(tag) || '.' || pg_temp.tx('sfx') || '@gmail.com' $$;
-- Fictional phones: +61 2 5550 nnnn, one block per run.
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad(((pg_temp.tx('phbase')::int + n) % 10000)::text, 4, '0') $$;
create function pg_temp.cust(key text, name text, phone text, email text) returns uuid language plpgsql as
$$declare c uuid; begin
  insert into public.customers(full_name, phone, email) values (name, phone, email) returning id into c;
  perform pg_temp.putx(key, c);
  return c;
end$$;
-- A record as old data has it: added with the triggers off (its 8-digit phone is not normalised).
create function pg_temp.legacy_cust(key text, name text, phone8 text, email text) returns uuid language plpgsql as
$$declare c uuid; begin
  set local session_replication_role = replica;
  insert into public.customers(full_name, phone, email) values (name, phone8, email) returning id into c;
  set local session_replication_role = origin;
  perform pg_temp.putx(key, c);
  return c;
end$$;
-- An 8-digit number starting with 8 (Singapore or Malaysia, as 425 reads it) no customer has in any form.
create function pg_temp.legacy8() returns text language sql as
$$ select s.d from (select '8' || lpad(floor(random() * 1e7)::int::text, 7, '0') as d from generate_series(1, 500)) s
    where public.normalize_customer_phone(s.d) is null
      and (public.inspect_customer_phone(s.d)->'candidates') ? ('+65' || s.d)
      and not exists (select 1 from public.customers c
                       where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') in (s.d, '65' || s.d, '60' || s.d))
      and not exists (select 1 from tx where tx.v = s.d)
    limit 1 $$;
-- A login, as the sign-up function makes it (confirmed, marked unverified).
create function pg_temp.login(key text, email text) returns uuid language plpgsql as
$$declare u uuid := gen_random_uuid(); begin
  insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  values (u, email, now(), '{"provider": "email", "affiliate_email_unverified": true}'::jsonb, '{}'::jsonb);
  perform pg_temp.putx(key, u);
  return u;
end$$;
-- The sign-up the pages run, as the login.
create function pg_temp.onboard(key text, first text, last text, phone text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(key);
  begin
    r := public.complete_affiliate_onboarding(first, last, phone, true);
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  perform pg_temp.put('onb:' || key, r::text);
  perform pg_temp.as_service();
  return r;
end$$;
create function pg_temp.ans(key text) returns jsonb language sql as $$ select pg_temp.tx('onb:' || key)::jsonb $$;
create function pg_temp.acct_cust(key text) returns uuid language sql as
$$ select customer_id from public.affiliate_accounts where auth_user_id = pg_temp.fx(key) $$;
create function pg_temp.claims(key text) returns setof public.affiliate_account_claims language sql as
$$ select * from public.affiliate_account_claims where auth_user_id = pg_temp.fx(key) $$;
create function pg_temp.parked(key text) returns setof public.audit_logs language sql as
$$ select * from public.audit_logs where action = 'affiliate_claim_parked' and new_data->>'auth_user_id' = pg_temp.fx(key)::text $$;
create function pg_temp.claimed(key text) returns public.audit_logs language sql as
$$ select * from public.audit_logs where action = 'affiliate_portal_claimed' and new_data->>'auth_user_id' = pg_temp.fx(key)::text
    order by created_at desc limit 1 $$;
-- 440's sign-up copies of a login (affiliate_signup_identities).
create function pg_temp.copies(key text) returns setof public.affiliate_signup_identities language sql as
$$ select * from public.affiliate_signup_identities where auth_user_id = pg_temp.fx(key) $$;
create function pg_temp.listed(key text) returns setof public.affiliate_signup_matches language sql as
$$ select * from public.affiliate_signup_matches where auth_user_id = pg_temp.fx(key) $$;
-- The referral page's call, with the anon key; an error comes back as {error}.
create function pg_temp.refer(tag text, code text, first text, last text, phone text, email text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_anon();
  begin
    r := public.affiliate_referral_signup(code, first, last, phone, email, null);
  exception when others then r := jsonb_build_object('error', sqlerrm);
  end;
  perform pg_temp.put('ref:' || tag, r::text);
  perform pg_temp.as_service();
  return r;
end$$;
create function pg_temp.r(tag text) returns jsonb language sql as $$ select pg_temp.tx('ref:' || tag)::jsonb $$;
create function pg_temp.on_phone(p_phone text) returns bigint language sql as
$$ select count(*) from public.customers c where c.deleted_at is null
     and public.normalize_customer_phone(c.phone) = public.normalize_customer_phone($1) $$;
create function pg_temp.events(p_phone text, p_outcome text) returns bigint language sql as
$$ select count(*) from public.referral_signup_events e
    where e.normalized_phone = public.normalize_customer_phone($1) and e.outcome = $2 $$;
create function pg_temp.several(key text) returns setof public.audit_logs language sql as
$$ select * from public.audit_logs where action = 'referral_signup_several_records' and record_id = pg_temp.fx(key) $$;
-- What a sign-up could make, counted.
create function pg_temp.made() returns jsonb language sql as
$$ select jsonb_build_object('customers', (select count(*) from public.customers),
     'affiliates', (select count(*) from public.customer_affiliates), 'accounts', (select count(*) from public.affiliate_accounts),
     'claims', (select count(*) from public.affiliate_account_claims), 'matches', (select count(*) from public.affiliate_signup_matches),
     'checks', (select count(*) from public.referral_signup_checks)) $$;
create function pg_temp.delta(before jsonb) returns jsonb language sql as
$$ select jsonb_object_agg(k, (pg_temp.made()->>k)::int - (before->>k)::int) from jsonb_object_keys(before) k $$;
-- The seminar's call (live or test key), one person; the answer under 'reg:<tag>', the person under fx(<tag>).
create function pg_temp.reg1(tag text, first text, last text, phone text, email text, code text, kind text default 'live')
returns uuid language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_service();
  v := public.event_web_call(pg_temp.tx('hash:' || kind), gen_random_uuid(), 'register',
         jsonb_build_object('type', 'register', 'event', pg_temp.tx('code'), 'registration', jsonb_build_object(
           'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || tag), 1, 8)),
           'submitted_at', now(), 'referral_code', code,
           'people', jsonb_build_array(jsonb_build_object('position', 1, 'first_name', first, 'last_name', last, 'phone', phone,
                                                          'email', email, 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
  perform pg_temp.put('reg:' || tag, v::text);
  perform pg_temp.putx(tag, (v->'people'->0->>'person_id')::uuid);
  return (v->'people'->0->>'person_id')::uuid;
end $$;
create function pg_temp.pp(tag text) returns public.event_registration_people language sql as
$$ select * from public.event_registration_people where id = pg_temp.fx(tag) $$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language sql as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
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
create function pg_temp.match_con() returns text language sql as
$$ select pg_get_constraintdef(c.oid) from pg_constraint c
    where c.conrelid = 'public.event_registration_people'::regclass and c.conname = 'event_registration_people_match_check' $$;
create temp table want(fn text primary key, before_md5 text, after_md5 text, anon boolean, auth boolean);
insert into want values
  ('affiliate_referral_signup(text,text,text,text,text,text)', 'c76573912de0a4ded29e81e5c56c96d3', '2942e3d4d0e8c76600c3e0ad5e15cc2b', true, true),
  ('complete_affiliate_onboarding(text,text,text,boolean)', '43084deab54968eacaf1793c470fd08f', '1b9dfc819b860dcb19244063a4628f47', false, true),
  ('event_web_match_customer(text,text,text)', '9da726006d8055983491b5ec1da1679b', '63bfaf4520406af9f67d3d81c3342baf', false, false),
  ('event_web_register(uuid,jsonb)', '3aad1ad2a8a91732d330b2ef149bf969', 'c188a2dc82b9eb08fc9d01f1e5c15e13', false, false);
create temp table c469(k text primary key, v text);
insert into c469 values
  ('before', 'CHECK ((match = ANY (ARRAY[''exact''::text, ''same_words''::text, ''new_customer''::text, ''held''::text, ''staff_attached''::text, ''staff_created''::text, ''closed''::text, ''test''::text])))'),
  ('after', 'CHECK ((match = ANY (ARRAY[''exact''::text, ''same_words''::text, ''phone_and_email''::text, ''new_customer''::text, ''held''::text, ''staff_attached''::text, ''staff_created''::text, ''closed''::text, ''test''::text])))');
create temp table known as select jsonb_build_object('ok', true, 'outcome', 'already_registered',
  'message', 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.') as v;
create temp table pending as select jsonb_build_object('status', 'pending_verification',
  'message', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.') as v;

-- ═════ P0, and 469 ═════
do $$ begin
  insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))),
                        ('phbase', (floor(random() * 9000))::int::text);
end $$;
select pg_temp.check(not exists (select 1 from public.customers c, generate_series(0, 99) g
                                  where public.normalize_customer_phone(c.phone) = pg_temp.ph(g)),
  'P0 no customer uses this run''s test phones (+61 2 5550 ' || pg_temp.tx('phbase') || '..+99; the checks assume so)');

\if :{?skip_install}
select pg_temp.check((select bool_and(md5(pg_get_functiondef(('public.' || w.fn)::regprocedure)) = w.after_md5) from want w)
    and pg_temp.match_con() = (select v from c469 where k = 'after'),
  'P1 469 is installed (skip_install)');
\else
select pg_temp.check((select bool_and(md5(pg_get_functiondef(('public.' || w.fn)::regprocedure)) = w.before_md5) from want w)
    and pg_temp.match_con() = (select v from c469 where k = 'before'),
  'P1 the four functions and the match check are production''s of 24 Oct 2026 (this suite installs 469; use -v skip_install=1 where it is)');
create temp table b469 as select * from pg_temp.fn_md5s();
create temp table r469 as select pg_temp.row_counts() as before;
\ir ../../../supabase/469_same_phone_and_email_same_customer.sql
create temp table m469 as select * from pg_temp.fn_md5s();
alter table r469 add column after1 jsonb;
update r469 set after1 = pg_temp.row_counts();
\ir ../../../supabase/469_same_phone_and_email_same_customer.sql
select pg_temp.check(not exists (select 1 from m469 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m469),
  'M1 running 469 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m469 m left join b469 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5)
                     = array['affiliate_referral_signup(text,text,text,text,text,text)', 'complete_affiliate_onboarding(text,text,text,boolean)',
                             'event_web_match_customer(text,text,text)', 'event_web_register(uuid,jsonb)']
    and (select count(*) from m469) = (select count(*) from b469),
  'M2 its first run changed the four functions alone (no function added or dropped)');
select pg_temp.check((select before = after1 from r469),
  'M3 469''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif
select pg_temp.check((select bool_and(md5(pg_get_functiondef(('public.' || w.fn)::regprocedure)) = w.after_md5) from want w)
    and pg_temp.match_con() = (select v from c469 where k = 'after'),
  'M4 the four functions have 469''s AFTER md5s; event_registration_people.match allows phone_and_email');

-- ═════ Fixtures ═════
do $$
declare u uuid; st uuid; ev uuid; h text;
begin
  -- An Owner.
  u := gen_random_uuid(); insert into fx values ('o', u);
  insert into auth.users(id, email, email_confirmed_at) values (u, pg_temp.mail('owner'), now());
  insert into profiles(id, full_name, email, role, is_active) values (u, 'T469 Owner', pg_temp.mail('owner'), 'owner', true);
  -- The seminar: a store, an event with a day, its website settings, a live key and a test key.
  insert into stores(name, code, country_code) values ('T469 Van ' || pg_temp.tx('sfx'), 'T469V' || upper(pg_temp.tx('sfx')), 'SG')
    returning id into st;
  insert into events(name, daily_start, daily_end, is_active) values ('T469 Seminar ' || pg_temp.tx('sfx'), '09:00', '19:00', true)
    returning id into ev;
  insert into fx values ('ev', ev), ('van', st);
  insert into event_days(event_id, day) values (ev, public.sg_today() + 30);
  insert into event_stores(event_id, store_id) values (ev, st);
  insert into event_web_settings(event_id, code, mode, store_id, acting_profile_id)
  values (ev, 'T469-' || upper(pg_temp.tx('sfx')), 'live', st, u);
  insert into tx values ('code', 'T469-' || upper(pg_temp.tx('sfx')));
  foreach h in array array['live', 'test'] loop
    insert into tx values ('hash:' || h, encode(extensions.digest('evk_' || h || '_' || rpad(pg_temp.tx('sfx'), 43, 'K'), 'sha256'), 'hex'));
    insert into event_web_keys(event_id, kind, key_hash, key_hint, created_by) values (ev, h, pg_temp.tx('hash:' || h), 'T469 ' || h, u);
  end loop;
end $$;
select pg_temp.as_service();
-- Rhea: an affiliate through the real sign-up (a new customer: her record has her login's email and phone).
select pg_temp.login('lRhea', pg_temp.mail('rhea'));
select pg_temp.onboard('lRhea', 'Rhea', 'Testref', pg_temp.ph(0));
insert into fx select 'rhea', (pg_temp.ans('lRhea')->>'customer_id')::uuid;
insert into tx select 'code_rhea', pg_temp.ans('lRhea')->>'referral_code';
-- Uma: another affiliate (no login), Ivy's referrer.
select pg_temp.cust('uma', 'Uma Testother', pg_temp.ph(1), null);
insert into customer_affiliates(customer_id, status, referral_code) values (pg_temp.fx('uma'), 'active', upper('T469U' || pg_temp.tx('sfx')));
select pg_temp.check(pg_temp.ans('lRhea')->>'status' = 'active' and pg_temp.tx('code_rhea') is not null
    and (select email from customers where id = pg_temp.fx('rhea')) = pg_temp.mail('rhea'),
  'F the fixture affiliate signed up (her record has her login''s email): ' || pg_temp.ans('lRhea')::text);
create temp table made0 as select pg_temp.made() as m;

-- ═════ R The referral link ═════
-- R1: Hugo's record has a Gmail address with dots; the sign-up types it without them, with a +tag, at googlemail.com,
-- his phone with spaces, and another name. Ivy has a referrer already (Uma).
select pg_temp.cust('hugo', 'Hugo Testholder', pg_temp.ph(10), 'T469.Hugo.' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.cust('ivy', 'Ivy Testreferred', pg_temp.ph(11), pg_temp.mail('ivy'));
update customers set referred_by = pg_temp.fx('uma'), referral_source = 'affiliate_link', referral_code_used = upper('T469U' || pg_temp.tx('sfx'))
 where id = pg_temp.fx('ivy');
create temp table r1made as select pg_temp.made() as m;
select pg_temp.refer('r1', pg_temp.tx('code_rhea'), 'Totally', 'Different',
                     '+61 2 5550 ' || right(pg_temp.ph(10), 4), 't469hugo' || pg_temp.tx('sfx') || '+promo@GoogleMail.com');
select pg_temp.refer('r1b', pg_temp.tx('code_rhea'), 'Someone', 'Else', pg_temp.ph(11), upper(pg_temp.mail('ivy')));
select pg_temp.check(pg_temp.r('r1') = (select v from known) and pg_temp.r('r1b') = (select v from known)
    and pg_temp.on_phone(pg_temp.ph(10)) = 1 and pg_temp.on_phone(pg_temp.ph(11)) = 1
    and (select referred_by from customers where id = pg_temp.fx('hugo')) is null
    and (select (referred_by, referral_code_used) from customers where id = pg_temp.fx('ivy'))
        = (pg_temp.fx('uma'), upper('T469U' || pg_temp.tx('sfx')))
    and pg_temp.events(pg_temp.ph(10), 'duplicate') = 1 and pg_temp.events(pg_temp.ph(11), 'duplicate') = 1
    and not exists (select 1 from pg_temp.several('hugo')) and not exists (select 1 from pg_temp.several('ivy'))
    and pg_temp.delta((select m from r1made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 0, "matches": 0, "checks": 0}'::jsonb,
  'R1 one record with the phone and the email (a Gmail inbox spelt another way; the phone in another format) under another name: "already registered", no customer, no check, the referrer (none; Uma) unchanged, a duplicate event: '
  || pg_temp.r('r1')::text || ' ' || pg_temp.r('r1b')::text);
-- R2: Jo and her sister share a phone and an email.
select pg_temp.cust('jo', 'Jo Testtwin', pg_temp.ph(12), pg_temp.mail('jo-family'));
select pg_temp.cust('jen', 'Jen Testtwin', pg_temp.ph(12), pg_temp.mail('jo-family'));
create temp table r2made as select pg_temp.made() as m;
select pg_temp.refer('r2', pg_temp.tx('code_rhea'), 'Jojo', 'Nickname', pg_temp.ph(12), pg_temp.mail('jo-family'));
select pg_temp.check(pg_temp.r('r2') = (select v from known) and pg_temp.on_phone(pg_temp.ph(12)) = 2
    and (select count(*) from pg_temp.several('jo')) = 1 and (select count(*) from pg_temp.several('jen')) = 1
    and (select bool_and(l.table_name = 'customers' and l.module = 'affiliate' and l.changed_by is null
                         and l.new_data->'customer_ids' @> to_jsonb(array[pg_temp.fx('jo'), pg_temp.fx('jen')])
                         and jsonb_array_length(l.new_data->'customer_ids') = 2
                         and l.new_data->>'outcome' = 'duplicate' and l.new_data->>'matched' = 'phone_and_email'
                         and l.new_data->>'referrer_customer_id' = pg_temp.fx('rhea')::text
                         and l.new_data->>'referral_code' = pg_temp.tx('code_rhea')
                         and l.new_data->>'phone' = pg_temp.ph(12) and l.new_data->>'name' = 'Jojo Nickname'
                         and l.new_data->>'email' = pg_temp.mail('jo-family'))
           from public.audit_logs l where l.action = 'referral_signup_several_records' and l.record_id in (pg_temp.fx('jo'), pg_temp.fx('jen')))
    and pg_temp.events(pg_temp.ph(12), 'duplicate') = 1
    and pg_temp.delta((select m from r2made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 0, "matches": 0, "checks": 0}'::jsonb,
  'R2 two records with the phone and the email: "already registered", nothing made, an Audit Log entry on each record for staff: ' || pg_temp.r('r2')::text);
-- R3..R5: the phone alone (another email; no email), the email alone, the name alone: as before.
select pg_temp.refer('r3', pg_temp.tx('code_rhea'), 'Totally', 'Different', pg_temp.ph(10), pg_temp.mail('r3-other'));
select pg_temp.refer('r3b', pg_temp.tx('code_rhea'), 'Someone', 'Else', pg_temp.ph(11), null);
select pg_temp.refer('r4', pg_temp.tx('code_rhea'), 'Totally', 'Different', pg_temp.ph(13), 'T469.Hugo.' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.refer('r5', pg_temp.tx('code_rhea'), 'Hugo', 'Testholder', pg_temp.ph(14), pg_temp.mail('r5'));
select pg_temp.check(pg_temp.r('r3')->>'outcome' = 'registered' and pg_temp.r('r3b')->>'outcome' = 'registered'
    and pg_temp.r('r4')->>'outcome' = 'registered' and pg_temp.r('r5')->>'outcome' = 'registered'
    and pg_temp.on_phone(pg_temp.ph(10)) = 2 and pg_temp.on_phone(pg_temp.ph(11)) = 2
    and pg_temp.events(pg_temp.ph(10), 'phone_shared') = 1 and pg_temp.events(pg_temp.ph(11), 'phone_shared') = 1
    and pg_temp.events(pg_temp.ph(13), 'created') = 1 and pg_temp.events(pg_temp.ph(14), 'created') = 1
    and exists (select 1 from referral_signup_checks k join customers c on c.id = k.customer_id
                 where c.phone = pg_temp.ph(10) and k.phone_shared_with = array[pg_temp.fx('hugo')] and c.referred_by = pg_temp.fx('rhea'))
    and exists (select 1 from referral_signup_checks k join customers c on c.id = k.customer_id
                 where c.phone = pg_temp.ph(11) and k.phone_shared_with = array[pg_temp.fx('ivy')] and c.referred_by = pg_temp.fx('rhea'))
    and (select count(*) from customers c where c.referred_by = pg_temp.fx('rhea') and c.phone in (pg_temp.ph(13), pg_temp.ph(14))) = 2,
  'R3-R5 the phone alone (another email, or none), the email alone, the name alone: a new customer as before (425''s check on a phone in use)');
-- R6: Rhea through her own link, her phone and her email under another name (442): herself, on file.
select pg_temp.refer('r6', pg_temp.tx('code_rhea'), 'Another', 'Name', pg_temp.ph(0), pg_temp.mail('rhea'));
select pg_temp.check(pg_temp.r('r6') = (select v from known) and pg_temp.on_phone(pg_temp.ph(0)) = 1
    and pg_temp.events(pg_temp.ph(0), 'self_known') = 1 and pg_temp.events(pg_temp.ph(0), 'self') = 0
    and exists (select 1 from audit_logs l
                 where l.action = 'referral_self_signup_refused' and l.record_id = pg_temp.fx('rhea')
                   and l.new_data->>'outcome' = 'self_known' and l.new_data->'matched' ? 'record'
                   and l.new_data->'matched' ? 'login_phone' and l.new_data->'matched' ? 'login_email')
    and not exists (select 1 from customers c where c.referred_by = pg_temp.fx('rhea') and c.phone = pg_temp.ph(0)),
  'R6 the referrer herself on her phone and email under another name: "already registered", 442''s self_known with its entry (her record among what matched), no customer');
-- R7: limits. Jo's phone: 3 more tries in the 10 minutes, all answered; then a new customer on it is refused (the
-- tries count, as before); a phone 3 customers have, with one's email: on file.
select pg_temp.refer('r7a', pg_temp.tx('code_rhea'), 'Jojo', 'Nickname', pg_temp.ph(12), pg_temp.mail('jo-family'));
select pg_temp.refer('r7b', pg_temp.tx('code_rhea'), 'Jojo', 'Nickname', pg_temp.ph(12), pg_temp.mail('jo-family'));
select pg_temp.refer('r7c', pg_temp.tx('code_rhea'), 'Jojo', 'Nickname', pg_temp.ph(12), pg_temp.mail('jo-family'));
select pg_temp.refer('r7d', pg_temp.tx('code_rhea'), 'Third', 'Sister', pg_temp.ph(12), pg_temp.mail('r7-other'));
select pg_temp.cust('fa', 'Fay Testfull', pg_temp.ph(15), null);
select pg_temp.cust('fb', 'Fen Testfull', pg_temp.ph(15), null);
select pg_temp.cust('fc', 'Fox Testfull', pg_temp.ph(15), pg_temp.mail('fox'));
select pg_temp.refer('r7e', pg_temp.tx('code_rhea'), 'Foxy', 'Nickname', pg_temp.ph(15), pg_temp.mail('fox'));
select pg_temp.refer('r7f', pg_temp.tx('code_rhea'), 'Foxy', 'Nickname', pg_temp.ph(15), pg_temp.mail('r7f-other'));
select pg_temp.check(pg_temp.r('r7a') = (select v from known) and pg_temp.r('r7b') = (select v from known)
    and pg_temp.r('r7c') = (select v from known)
    and pg_temp.r('r7d') = '{"ok": false, "message": "Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia."}'::jsonb
    and pg_temp.on_phone(pg_temp.ph(12)) = 2
    and (select count(*) from pg_temp.several('jo')) = 1 and (select count(*) from pg_temp.several('jen')) = 1
    and pg_temp.events(pg_temp.ph(12), 'duplicate') = 4
    and pg_temp.r('r7e') = (select v from known) and pg_temp.on_phone(pg_temp.ph(15)) = 3
    and pg_temp.r('r7f')->>'error' like 'CUSTOMER_PHONE_LIMIT:%'
    and (select count(*) from referral_signup_events e where e.referrer_customer_id = pg_temp.fx('rhea')
           and e.outcome in ('created', 'phone_shared', 'self')) = 4,
  'R7 "already registered" is never limited but counts in the phone''s 10 minutes (each try its duplicate event; R2''s records no second entry within the hour); a phone 3 customers have, with one''s email: on file (another email: the phone''s limit, as before); the link''s hour counts only the 4 customers made: '
  || pg_temp.r('r7d')::text || ' ' || pg_temp.r('r7f')::text);
-- R7b: an hour after the entries (moved back 61 minutes here), a try again writes one more on each record.
update audit_logs set created_at = created_at - interval '61 minutes'
 where action = 'referral_signup_several_records' and record_id in (pg_temp.fx('jo'), pg_temp.fx('jen'));
select pg_temp.refer('r7g', pg_temp.tx('code_rhea'), 'Jojo', 'Nickname', pg_temp.ph(12), pg_temp.mail('jo-family'));
select pg_temp.check(pg_temp.r('r7g') = (select v from known)
    and (select count(*) from pg_temp.several('jo')) = 2 and (select count(*) from pg_temp.several('jen')) = 2
    and (select count(*) from pg_temp.several('jo') l where l.created_at > now() - interval '1 hour') = 1
    and pg_temp.events(pg_temp.ph(12), 'duplicate') = 5,
  'R7b an hour after the last entries, a try again writes one more on each record (the same answer)');
-- R8: Lena's record has an old 8-digit number that could be the phone typed (as Singapore).
do $$ begin perform pg_temp.put('l8a', pg_temp.legacy8()); end $$;
select pg_temp.legacy_cust('lena', 'Lena Testlegacy', pg_temp.tx('l8a'), pg_temp.mail('lena'));
select pg_temp.refer('r8', pg_temp.tx('code_rhea'), 'Helena', 'Otherwise', '+65' || pg_temp.tx('l8a'), pg_temp.mail('lena'));
select pg_temp.check(pg_temp.r('r8') = (select v from known)
    and not exists (select 1 from customers c where c.phone = '+65' || pg_temp.tx('l8a'))
    and pg_temp.events('+65' || pg_temp.tx('l8a'), 'duplicate') = 1,
  'R8 a record whose old 8-digit number could be the phone typed, with the email: "already registered" (425 counts it): ' || pg_temp.r('r8')::text);
-- R9: namesakes (the Owner, 24 Oct 2026, as 468 reads them). (a) two records with the name typed, a third of another
-- name with the phone and the email; (b) the same, the namesakes' name in other words; (c) one namesake with the email
-- too; (d) the same, in other words.
select pg_temp.cust('r9a1', 'Nia Testsame', pg_temp.ph(70), null);
select pg_temp.cust('r9a2', 'Nia Testsame', pg_temp.ph(70), null);
select pg_temp.cust('r9a3', 'Noor Testother', pg_temp.ph(70), pg_temp.mail('r9a'));
select pg_temp.cust('r9b1', 'Oma Testsame', pg_temp.ph(71), null);
select pg_temp.cust('r9b2', 'Testsame Oma', pg_temp.ph(71), null);
select pg_temp.cust('r9b3', 'Odo Testother', pg_temp.ph(71), pg_temp.mail('r9b'));
select pg_temp.cust('r9c1', 'Pam Testsame', pg_temp.ph(72), null);
select pg_temp.cust('r9c2', 'Pam Testsame', pg_temp.ph(72), pg_temp.mail('r9c'));
select pg_temp.cust('r9c3', 'Pat Testother', pg_temp.ph(72), pg_temp.mail('r9c'));
select pg_temp.cust('r9d1', 'Rue Testsame', pg_temp.ph(73), pg_temp.mail('r9d'));
select pg_temp.cust('r9d2', 'Testsame Rue', pg_temp.ph(73), null);
select pg_temp.cust('r9d3', 'Roy Testother', pg_temp.ph(73), pg_temp.mail('r9d'));
create temp table r9made as select pg_temp.made() as m;
select pg_temp.refer('r9a', pg_temp.tx('code_rhea'), 'Nia', 'Testsame', pg_temp.ph(70), pg_temp.mail('r9a'));
select pg_temp.refer('r9b', pg_temp.tx('code_rhea'), 'OmaTestsame', null, pg_temp.ph(71), pg_temp.mail('r9b'));
select pg_temp.refer('r9c', pg_temp.tx('code_rhea'), 'Pam', 'Testsame', pg_temp.ph(72), pg_temp.mail('r9c'));
select pg_temp.refer('r9d', pg_temp.tx('code_rhea'), 'RueTestsame', null, pg_temp.ph(73), pg_temp.mail('r9d'));
select pg_temp.check(pg_temp.r('r9a')->>'error' = 'AMBIGUOUS_CUSTOMER_MATCH' and pg_temp.r('r9c')->>'error' = 'AMBIGUOUS_CUSTOMER_MATCH'
    and pg_temp.r('r9b') = (select v from known) and pg_temp.r('r9d') = (select v from known)
    and pg_temp.on_phone(pg_temp.ph(70)) = 3 and pg_temp.on_phone(pg_temp.ph(71)) = 3
    and pg_temp.on_phone(pg_temp.ph(72)) = 3 and pg_temp.on_phone(pg_temp.ph(73)) = 3
    and pg_temp.events(pg_temp.ph(71), 'duplicate') = 1 and pg_temp.events(pg_temp.ph(73), 'duplicate') = 1
    and not exists (select 1 from audit_logs l where l.action = 'referral_signup_several_records'
                     and l.record_id in (select v from fx where k like 'r9%'))
    and not exists (select 1 from customers c where c.id in (select v from fx where k like 'r9%') and c.referred_by is not null)
    and pg_temp.delta((select m from r9made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 0, "matches": 0, "checks": 0}'::jsonb,
  'R9 namesakes with another name''s phone and email, or one namesake with the email and another name with both: the answer for several, as before (the name exactly: refused as ambiguous; in other words: "already registered"), nothing made, no entry: '
  || pg_temp.r('r9a')::text || ' ' || pg_temp.r('r9b')::text || ' ' || pg_temp.r('r9c')::text || ' ' || pg_temp.r('r9d')::text);

-- ═════ J The affiliate sign-up ═════
-- J1: Kai and Kim share a phone; Kim's record has the login's Gmail inbox, spelt another way.
select pg_temp.cust('kai', 'Kai Testfamily', pg_temp.ph(20), null);
select pg_temp.cust('kim', 'Kim Testjoin', pg_temp.ph(20), 'T469Kim' || pg_temp.tx('sfx') || '@GoogleMail.com');
select pg_temp.login('lKim', pg_temp.gmail('kim'));
create temp table j1made as select pg_temp.made() as m;
select pg_temp.onboard('lKim', 'Kimberly', 'Otherwise', pg_temp.ph(20));
select pg_temp.check(pg_temp.ans('lKim')->>'status' = 'active' and (pg_temp.ans('lKim')->>'customer_id')::uuid = pg_temp.fx('kim')
    and (pg_temp.ans('lKim')->>'new_customer')::boolean = false and pg_temp.acct_cust('lKim') = pg_temp.fx('kim')
    and public.customer_email_match_key((select email from customers where id = pg_temp.fx('kim'))) = public.customer_email_match_key(pg_temp.gmail('kim'))
    and (select email from customers where id = pg_temp.fx('kim')) <> pg_temp.gmail('kim')
    and (pg_temp.claimed('lKim')).new_data->>'rule' = 'phone_and_email'
    and not exists (select 1 from pg_temp.listed('lKim')) and not exists (select 1 from pg_temp.claims('lKim'))
    and pg_temp.on_phone(pg_temp.ph(20)) = 2
    and pg_temp.delta((select m from j1made)) = '{"customers": 0, "affiliates": 1, "accounts": 1, "claims": 0, "matches": 0, "checks": 0}'::jsonb,
  'J1 a household phone, the login''s email (a Gmail inbox spelt another way) on one record: joined to it (rule phone_and_email), nothing made or listed: '
  || pg_temp.ans('lKim')::text);
-- J2: Lou and Lia share a phone and an email; so does the login.
select pg_temp.cust('lou', 'Lou Testshared', pg_temp.ph(21), pg_temp.mail('lou-family'));
select pg_temp.cust('lia', 'Lia Testshared', pg_temp.ph(21), pg_temp.mail('lou-family'));
select pg_temp.login('lLou', pg_temp.mail('lou-family'));
create temp table j2made as select pg_temp.made() as m;
select pg_temp.onboard('lLou', 'Louise', 'Otherwise', pg_temp.ph(21));
select pg_temp.put('j2first', pg_temp.ans('lLou')::text);
select pg_temp.onboard('lLou', 'Louise', 'Otherwise', pg_temp.ph(21));
select pg_temp.check(pg_temp.tx('j2first')::jsonb = (select v from pending) and pg_temp.ans('lLou') = (select v from pending)
    and (select count(*) from pg_temp.claims('lLou')) = 1
    and (select (status, candidate_customer_id, entered_phone, verified_email, entered_name) from pg_temp.claims('lLou'))
        = ('pending'::text, null::uuid, pg_temp.ph(21), pg_temp.mail('lou-family'), 'Louise Otherwise'::text)
    and (select count(*) from pg_temp.parked('lLou')) = 1
    and (select l.new_data->>'reason' = 'several_phone_and_email' and l.new_data->>'version' = '469'
                and l.new_data->'phone_and_email_customers' @> to_jsonb(array[pg_temp.fx('lou'), pg_temp.fx('lia')])
                and l.table_name = 'affiliate_account_claims' and l.module = 'affiliate' and l.changed_by is null
           from pg_temp.parked('lLou') l)
    and pg_temp.acct_cust('lLou') is null and pg_temp.on_phone(pg_temp.ph(21)) = 2
    and (select count(*) from pg_temp.copies('lLou')) = 1
    and (select (x.source, x.affiliate_account_id, x.customer_id, x.first_name, x.last_name, x.full_name, x.phone, x.email,
                 x.name_from, x.phone_from) from pg_temp.copies('lLou') x)
        is not distinct from ('backfill'::text, null::uuid, null::uuid, 'Louise'::text, 'Otherwise'::text, 'Louise Otherwise'::text,
                              pg_temp.ph(21), pg_temp.mail('lou-family'), 'arguments'::text, 'arguments'::text)
    and pg_temp.delta((select m from j2made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 1, "matches": 0, "checks": 0}'::jsonb,
  'J2 two records with the phone and the login''s email: "identity verification needed", one pending claim suggesting no one with its entry and the login''s sign-up copy (440''s, no account yet), nothing made; again: the same, nothing more');
do $$ declare r jsonb; begin
  perform pg_temp.as_user('o');
  begin
    r := public.resolve_affiliate_account_claim((select id from pg_temp.claims('lLou')), pg_temp.fx('lou'), 'T469: the same person (test)');
  exception when others then r := jsonb_build_object('error', sqlerrm);
  end;
  perform pg_temp.put('j2resolve', r::text);
  perform pg_temp.as_service();
end $$;
select pg_temp.onboard('lLou', 'Louise', 'Otherwise', pg_temp.ph(21));
select pg_temp.check((pg_temp.tx('j2resolve')::jsonb->>'ok')::boolean and pg_temp.acct_cust('lLou') = pg_temp.fx('lou')
    and (pg_temp.ans('lLou')->>'already')::boolean and (pg_temp.ans('lLou')->>'customer_id')::uuid = pg_temp.fx('lou')
    and (select status from pg_temp.claims('lLou')) = 'resolved'
    and (select count(*) from pg_temp.copies('lLou')) = 1
    and (select count(*) from public.affiliate_login_signup_details(pg_temp.fx('lou')) d
          where d.auth_user_id = pg_temp.fx('lLou') and d.full_name = 'Louise Otherwise' and d.phone = pg_temp.ph(21)
            and d.email = pg_temp.mail('lou-family')) = 1,
  'J2b an Owner resolves the claim to Lou; at the next sign-in the login is in, and its sign-up copy is read for her record (440): '
  || pg_temp.ans('lLou')::text);
-- J2c: through her own link, her Join name, her login email or her phone (each with other details): herself (442).
insert into tx select 'code_lou', ca.referral_code from customer_affiliates ca where ca.customer_id = pg_temp.fx('lou') and ca.deleted_at is null;
create temp table j2cmade as select pg_temp.made() as m;
select pg_temp.refer('j2ca', pg_temp.tx('code_lou'), 'Louise', 'Otherwise', pg_temp.ph(63), pg_temp.mail('j2c-a'));
select pg_temp.refer('j2cb', pg_temp.tx('code_lou'), 'Nobody', 'Elsewhere', pg_temp.ph(64), pg_temp.mail('lou-family'));
select pg_temp.refer('j2cc', pg_temp.tx('code_lou'), 'Third', 'Person', pg_temp.ph(21), pg_temp.mail('j2c-c'));
select pg_temp.check(pg_temp.tx('code_lou') is not null
    and pg_temp.r('j2ca') = (select v from known) and pg_temp.r('j2cb') = (select v from known) and pg_temp.r('j2cc') = (select v from known)
    and pg_temp.events(pg_temp.ph(63), 'self') = 1 and pg_temp.events(pg_temp.ph(64), 'self') = 1 and pg_temp.events(pg_temp.ph(21), 'self') = 1
    and not exists (select 1 from customers c where c.referred_by = pg_temp.fx('lou'))
    and pg_temp.delta((select m from j2cmade)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 0, "matches": 0, "checks": 0}'::jsonb,
  'J2c through her own link, her Join name, her login email or her phone (other details each): herself (442''s self), no customer made: '
  || pg_temp.r('j2ca')::text || ' ' || pg_temp.r('j2cb')::text || ' ' || pg_temp.r('j2cc')::text);
-- J3: Max is an affiliate (his record has his login's Gmail address); a second login with that inbox spelt without dots.
select pg_temp.login('lMax', pg_temp.gmail('max'));
select pg_temp.onboard('lMax', 'Max', 'Testlogin', pg_temp.ph(22));
insert into fx select 'max', (pg_temp.ans('lMax')->>'customer_id')::uuid;
select pg_temp.login('lMax2', replace(pg_temp.gmail('max'), 't469.max.', 't469max'));
create temp table j3made as select pg_temp.made() as m;
select pg_temp.onboard('lMax2', 'Maximilian', 'Other', pg_temp.ph(22));
select pg_temp.check(pg_temp.ans('lMax')->>'status' = 'active' and pg_temp.ans('lMax2') = (select v from pending)
    and (select (status, candidate_customer_id) from pg_temp.claims('lMax2')) = ('pending'::text, pg_temp.fx('max'))
    and (select l.new_data->>'reason' from pg_temp.parked('lMax2') l) = 'customer_has_login'
    and pg_temp.acct_cust('lMax2') is null and pg_temp.on_phone(pg_temp.ph(22)) = 1
    and (select count(*) from pg_temp.copies('lMax2') x where x.source = 'backfill' and x.affiliate_account_id is null
           and x.full_name = 'Maximilian Other') = 1 and (select count(*) from pg_temp.copies('lMax2')) = 1
    and pg_temp.delta((select m from j3made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 1, "matches": 0, "checks": 0}'::jsonb,
  'J3 the one record with the phone and the email has a portal login: a pending claim suggesting it (with the login''s sign-up copy), no second account on a fresh record: '
  || pg_temp.ans('lMax2')::text);
-- J4: an Owner unlinked a login from Nell (378): protected; a fresh record, listed, as before.
select pg_temp.cust('nell', 'Nell Testprotected', pg_temp.ph(23), pg_temp.mail('nell'));
insert into audit_logs(table_name, record_id, action, old_data, actor_role, module)
values ('affiliate_accounts', gen_random_uuid(), 'affiliate_login_unlinked',
        jsonb_build_object('auth_user_id', gen_random_uuid(), 'customer_id', pg_temp.fx('nell')), 'owner', 'affiliate');
select pg_temp.login('lNell', pg_temp.mail('nell'));
select pg_temp.onboard('lNell', 'Nelly', 'Other', pg_temp.ph(23));
select pg_temp.check(pg_temp.ans('lNell')->>'status' = 'active' and (pg_temp.ans('lNell')->>'new_customer')::boolean
    and pg_temp.acct_cust('lNell') <> pg_temp.fx('nell') and (select reason from pg_temp.listed('lNell')) = 'protected_customer'
    and not exists (select 1 from pg_temp.claims('lNell')),
  'J4 the one record with the phone and the email is protected (378): a fresh record, listed protected_customer, as before');
-- J5..J10: as before.
select pg_temp.cust('oa', 'Oli Testone', pg_temp.ph(24), pg_temp.mail('oa'));
select pg_temp.cust('ob', 'Ola Testtwo', pg_temp.ph(24), null);
select pg_temp.login('lOli', pg_temp.mail('oli-own'));
select pg_temp.onboard('lOli', 'Olivia', 'Different', pg_temp.ph(24));
select pg_temp.cust('pia', 'Pia Testsingle', pg_temp.ph(25), pg_temp.mail('pia'));
select pg_temp.login('lPia', pg_temp.mail('pia-other'));
select pg_temp.onboard('lPia', 'Pip', 'Other', pg_temp.ph(25));
do $$ begin perform pg_temp.put('l8q', pg_temp.legacy8()); end $$;
select pg_temp.legacy_cust('quin', 'Quin Testlegacy', pg_temp.tx('l8q'), pg_temp.mail('quin'));
select pg_temp.login('lQuin', pg_temp.mail('quin'));
select pg_temp.onboard('lQuin', 'Quincy', 'Other', '+65' || pg_temp.tx('l8q'));
select pg_temp.cust('rex', 'Rex Testname', pg_temp.ph(26), pg_temp.mail('rex'));
select pg_temp.cust('ros', 'Ros Testmail', pg_temp.ph(26), pg_temp.mail('ros'));
select pg_temp.login('lRex', pg_temp.mail('ros'));
select pg_temp.onboard('lRex', 'Rex', 'Testname', pg_temp.ph(26));
select pg_temp.cust('sid', 'Sid Testrejected', pg_temp.ph(27), pg_temp.mail('sid'));
select pg_temp.login('lSid', pg_temp.mail('sid'));
insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, status, rejected_at, rejection_reason)
values (pg_temp.fx('lSid'), pg_temp.ph(27), pg_temp.mail('sid'), 'rejected', now(), 'T469 test');
select pg_temp.onboard('lSid', 'Sidney', 'Other', pg_temp.ph(27));
select pg_temp.cust('tom', 'Tom Testemail', pg_temp.ph(28), pg_temp.mail('tom'));
select pg_temp.login('lTom', pg_temp.mail('tom'));
select pg_temp.onboard('lTom', 'Thomas', 'Other', pg_temp.ph(29));
select pg_temp.check((pg_temp.ans('lOli')->>'new_customer')::boolean and (select reason from pg_temp.listed('lOli')) = 'shared_phone',
  'J5 the phone alone on a shared phone: a fresh record, listed shared_phone, as before: ' || pg_temp.ans('lOli')::text);
select pg_temp.check(pg_temp.acct_cust('lPia') = pg_temp.fx('pia') and (pg_temp.claimed('lPia')).new_data->>'rule' = 'phone'
    and (select reason from pg_temp.listed('lPia')) = 'phone_other_name',
  'J6 the one record on the phone, another email and name: joined on the phone, listed phone_other_name, as before: ' || pg_temp.ans('lPia')::text);
select pg_temp.check(pg_temp.ans('lQuin') = (select v from pending)
    and (select (status, candidate_customer_id) from pg_temp.claims('lQuin')) = ('pending'::text, pg_temp.fx('quin'))
    and (select l.new_data->>'reason' from pg_temp.parked('lQuin') l) = 'phone_unconfirmed_and_email'
    and pg_temp.acct_cust('lQuin') is null and not exists (select 1 from customers c where c.phone = '+65' || pg_temp.tx('l8q'))
    and (select count(*) from pg_temp.copies('lQuin') x where x.source = 'backfill' and x.phone = '+65' || pg_temp.tx('l8q')) = 1,
  'J7 a record whose old 8-digit number only could be the phone, with the email: a pending claim suggesting it, no record: ' || pg_temp.ans('lQuin')::text);
select pg_temp.check(pg_temp.acct_cust('lRex') = pg_temp.fx('rex') and (pg_temp.claimed('lRex')).new_data->>'rule' = 'phone_and_name',
  'J8 the name picks Rex, the email Ros: Rex, by the name, as before: ' || pg_temp.ans('lRex')::text);
select pg_temp.check(pg_temp.ans('lSid')->>'status' = 'rejected' and pg_temp.acct_cust('lSid') is null
    and (select count(*) from pg_temp.claims('lSid')) = 1,
  'J9 a login whose claim was rejected stays rejected, whatever its phone and email: ' || pg_temp.ans('lSid')::text);
select pg_temp.check((pg_temp.ans('lTom')->>'new_customer')::boolean and (select reason from pg_temp.listed('lTom')) = 'email_match'
    and (select candidate_ids from pg_temp.listed('lTom')) @> array[pg_temp.fx('tom')],
  'J10 the email alone (a phone no one has): a fresh record listed email_match, as before: ' || pg_temp.ans('lTom')::text);
select pg_temp.cust('wen1', 'Wen Testsame', pg_temp.ph(30), null);
select pg_temp.cust('wen2', 'Wen Testsame', pg_temp.ph(30), pg_temp.mail('wen'));
select pg_temp.login('lWen', pg_temp.mail('wen'));
select pg_temp.onboard('lWen', 'Wen', 'Testsame', pg_temp.ph(30));
select pg_temp.cust('xia1', 'Xia Testsame', pg_temp.ph(31), null);
select pg_temp.cust('xia2', 'Xia Testsame', pg_temp.ph(31), null);
select pg_temp.cust('xav', 'Xavier Testother', pg_temp.ph(31), pg_temp.mail('xav'));
select pg_temp.login('lXia', pg_temp.mail('xav'));
create temp table j11made as select pg_temp.made() as m;
select pg_temp.onboard('lXia', 'Xia', 'Testsame', pg_temp.ph(31));
select pg_temp.check(pg_temp.acct_cust('lWen') = pg_temp.fx('wen2') and (pg_temp.claimed('lWen')).new_data->>'rule' = 'phone_and_email'
    and pg_temp.on_phone(pg_temp.ph(30)) = 2
    and pg_temp.ans('lXia') = (select v from pending) and pg_temp.acct_cust('lXia') is null
    and (select (status, candidate_customer_id, entered_phone) from pg_temp.claims('lXia')) = ('pending'::text, null::uuid, pg_temp.ph(31))
    and (select l.new_data->>'reason' = 'several_name_matches'
                and l.new_data->'phone_and_email_customers' = to_jsonb(array[pg_temp.fx('xav')])
                and (select array_agg(x::uuid order by x::uuid) from jsonb_array_elements_text(l.new_data->'name_matches') x)
                    = (select array_agg(x order by x) from unnest(array[pg_temp.fx('xia1'), pg_temp.fx('xia2')]) x)
           from pg_temp.parked('lXia') l)
    and (select count(*) from pg_temp.copies('lXia') x where x.source = 'backfill' and x.full_name = 'Xia Testsame') = 1
    and pg_temp.on_phone(pg_temp.ph(31)) = 3
    and pg_temp.delta((select m from j11made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 1, "matches": 0, "checks": 0}'::jsonb,
  'J11 the name picks two records, one with the email: joined to it; the email on a third record whose name is not the one typed: a pending claim suggesting no one (several_name_matches), nothing made: '
  || pg_temp.ans('lWen')::text || ' ' || pg_temp.ans('lXia')::text);
-- J12: one of two namesakes has the email, and a record of another name has the phone and the email too.
select pg_temp.cust('yul1', 'Yul Testsame', pg_temp.ph(74), null);
select pg_temp.cust('yul2', 'Yul Testsame', pg_temp.ph(74), pg_temp.mail('yul'));
select pg_temp.cust('yves', 'Yves Testother', pg_temp.ph(74), pg_temp.mail('yul'));
select pg_temp.login('lYul', pg_temp.mail('yul'));
create temp table j12made as select pg_temp.made() as m;
select pg_temp.onboard('lYul', 'Yul', 'Testsame', pg_temp.ph(74));
select pg_temp.check(pg_temp.ans('lYul') = (select v from pending) and pg_temp.acct_cust('lYul') is null
    and (select (status, candidate_customer_id) from pg_temp.claims('lYul')) = ('pending'::text, null::uuid)
    and (select l.new_data->>'reason' = 'several_name_matches'
                and (select array_agg(x::uuid order by x::uuid) from jsonb_array_elements_text(l.new_data->'phone_and_email_customers') x)
                    = (select array_agg(x order by x) from unnest(array[pg_temp.fx('yul2'), pg_temp.fx('yves')]) x)
           from pg_temp.parked('lYul') l)
    and pg_temp.on_phone(pg_temp.ph(74)) = 3
    and pg_temp.delta((select m from j12made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 1, "matches": 0, "checks": 0}'::jsonb,
  'J12 one of two namesakes with the email, and a record of another name with the phone and the email too: a pending claim suggesting no one, nothing made: '
  || pg_temp.ans('lYul')::text);

-- ═════ S The seminar website ═════
select pg_temp.cust('sam', 'Sam Testseminar', pg_temp.ph(40), pg_temp.mail('sam'));
select pg_temp.cust('sue', 'Sue Testhousehold', pg_temp.ph(40), null);
create temp table s1made as select pg_temp.made() as m;
select pg_temp.reg1('s1', 'Samantha', 'Other', pg_temp.ph(40), upper(pg_temp.mail('sam')), pg_temp.tx('code_rhea'));
select pg_temp.check(pg_temp.tx('reg:s1')::jsonb->>'status' = 'registered'
    and ((pg_temp.pp('s1')).match, (pg_temp.pp('s1')).customer_id, (pg_temp.pp('s1')).referral_outcome, (pg_temp.pp('s1')).hold_reason)
        is not distinct from ('phone_and_email'::text, pg_temp.fx('sam'), 'already_customer'::text, null::text)
    and (pg_temp.pp('s1')).free_guest_id is not null
    and (select referred_by from customers where id = pg_temp.fx('sam')) is null
    and pg_temp.on_phone(pg_temp.ph(40)) = 2
    and pg_temp.delta((select m from s1made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 0, "matches": 0, "checks": 0}'::jsonb
    and not (pg_temp.tx('reg:s1') ~ ('phone_and_email|' || pg_temp.fx('sam')::text)),
  'S1 one record with the phone and the email under another name (its household''s other record on the phone): linked (phone_and_email), already_customer through the link, on the guest list, nothing made, and the answer says none of it: '
  || pg_temp.tx('reg:s1'));
select pg_temp.cust('tia', 'Tia Testtwin', pg_temp.ph(41), pg_temp.mail('tia-family'));
select pg_temp.cust('tea', 'Tea Testtwin', pg_temp.ph(41), pg_temp.mail('tia-family'));
select pg_temp.reg1('s2', 'Tiatea', 'Nickname', pg_temp.ph(41), pg_temp.mail('tia-family'), null);
select pg_temp.reg1('s3', 'Sammy', 'Third', pg_temp.ph(40), pg_temp.mail('s3-other'), null);
select pg_temp.reg1('s4', 'Samantha', 'Other', pg_temp.ph(42), pg_temp.mail('sam'), null);
select pg_temp.check(((pg_temp.pp('s2')).match, (pg_temp.pp('s2')).hold_reason) = ('held'::text, 'phone_and_email_in_use'::text)
    and (select array_agg(x order by x) from unnest((pg_temp.pp('s2')).candidate_customer_ids) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('tia'), pg_temp.fx('tea')]) x)
    and ((pg_temp.pp('s3')).match, (pg_temp.pp('s3')).hold_reason) = ('held'::text, 'phone_in_use'::text)
    and ((pg_temp.pp('s4')).match, (pg_temp.pp('s4')).hold_reason) = ('held'::text, 'email_in_use'::text)
    and pg_temp.on_phone(pg_temp.ph(41)) = 2 and pg_temp.on_phone(pg_temp.ph(42)) = 0,
  'S2-S4 two records with the phone and the email: held phone_and_email_in_use (both candidates); the phone alone: phone_in_use; the email alone: email_in_use; as before');
select pg_temp.cust('uli', 'Uli Testgmail', pg_temp.ph(43), pg_temp.gmail('uli'));
select pg_temp.reg1('s5', 'U', 'Other', pg_temp.ph(43), upper(replace(pg_temp.gmail('uli'), '@gmail.com', '+seminar@googlemail.com')), null);
select pg_temp.reg1('s6', 'Another', 'Name', pg_temp.ph(0), pg_temp.mail('rhea'), pg_temp.tx('code_rhea'));
do $$ begin perform pg_temp.put('l8v', pg_temp.legacy8()); end $$;
select pg_temp.legacy_cust('vi', 'Vi Testlegacy', pg_temp.tx('l8v'), pg_temp.mail('vi'));
select pg_temp.reg1('s8', 'Violet', 'Other', '+65' || pg_temp.tx('l8v'), pg_temp.mail('vi'), null);
select pg_temp.check(((pg_temp.pp('s5')).match, (pg_temp.pp('s5')).customer_id) = ('phone_and_email'::text, pg_temp.fx('uli')),
  'S5 a Gmail inbox spelt another way (dots, a +tag, googlemail, capitals): linked');
select pg_temp.check(((pg_temp.pp('s6')).match, (pg_temp.pp('s6')).customer_id, (pg_temp.pp('s6')).referral_outcome)
        = ('phone_and_email'::text, pg_temp.fx('rhea'), 'self'::text)
    and (pg_temp.pp('s6')).referral_self_by @> array['customer'],
  'S6 the affiliate herself through her own link, her phone and email under another name: linked to her record, self (436/439), not referred');
select pg_temp.check(((pg_temp.pp('s8')).match, (pg_temp.pp('s8')).customer_id) = ('phone_and_email'::text, pg_temp.fx('vi')),
  'S8 a record whose old 8-digit number could be the phone, with the email: linked (436 counts it)');
select pg_temp.cust('yan1', 'Yan Testsame', pg_temp.ph(44), null);
select pg_temp.cust('yan2', 'Yan Testsame', pg_temp.ph(44), pg_temp.mail('yan'));
select pg_temp.reg1('s9', 'Yan', 'Testsame', pg_temp.ph(44), pg_temp.mail('yan'), null);
select pg_temp.cust('zed1', 'Zed Testsame', pg_temp.ph(45), null);
select pg_temp.cust('zed2', 'Zed Testsame', pg_temp.ph(45), null);
select pg_temp.cust('zara', 'Zara Testother', pg_temp.ph(45), pg_temp.mail('zara'));
select pg_temp.reg1('s9b', 'Zed', 'Testsame', pg_temp.ph(45), pg_temp.mail('zara'), null);
select pg_temp.check(((pg_temp.pp('s9')).match, (pg_temp.pp('s9')).customer_id) = ('phone_and_email'::text, pg_temp.fx('yan2'))
    and ((pg_temp.pp('s9b')).match, (pg_temp.pp('s9b')).hold_reason) = ('held'::text, 'several_name_matches'::text)
    and (select array_agg(x order by x) from unnest((pg_temp.pp('s9b')).candidate_customer_ids) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('zed1'), pg_temp.fx('zed2')]) x),
  'S9 the name picks two records, one with the email: linked to it; the email on a third record whose name is not the one typed: held several_name_matches with the two, as before');
select pg_temp.cust('zoe1', 'Zoe Testsame', pg_temp.ph(75), null);
select pg_temp.cust('zoe2', 'Zoe Testsame', pg_temp.ph(75), pg_temp.mail('zoe'));
select pg_temp.cust('zack', 'Zack Testother', pg_temp.ph(75), pg_temp.mail('zoe'));
select pg_temp.reg1('s9c', 'Zoe', 'Testsame', pg_temp.ph(75), pg_temp.mail('zoe'), null);
select pg_temp.check(((pg_temp.pp('s9c')).match, (pg_temp.pp('s9c')).hold_reason, (pg_temp.pp('s9c')).customer_id)
        is not distinct from ('held'::text, 'several_name_matches'::text, null::uuid)
    and (select array_agg(x order by x) from unnest((pg_temp.pp('s9c')).candidate_customer_ids) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('zoe1'), pg_temp.fx('zoe2'), pg_temp.fx('zack')]) x)
    and pg_temp.on_phone(pg_temp.ph(75)) = 3,
  'S9c one of two namesakes with the email, and a record of another name with the phone and the email too: held several_name_matches with all three, nothing made');
-- S10: already on this event's list (449, 450). A form's people, and the guests of a record on this event.
create function pg_temp.person(pos int, first text, last text, phone text, email text) returns jsonb language sql as
$$ select jsonb_build_object('position', pos, 'first_name', first, 'last_name', last, 'phone', phone, 'email', email,
                             'days', jsonb_build_array(public.sg_today() + 30), 'vip', false) $$;
create function pg_temp.regn(tag text, people jsonb) returns jsonb language plpgsql as $$
declare v jsonb; i int;
begin
  perform pg_temp.as_service();
  v := public.event_web_call(pg_temp.tx('hash:live'), gen_random_uuid(), 'register',
         jsonb_build_object('type', 'register', 'event', pg_temp.tx('code'), 'registration', jsonb_build_object(
           'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || tag), 1, 8)),
           'submitted_at', now(), 'referral_code', null, 'people', people)));
  perform pg_temp.put('reg:' || tag, v::text);
  for i in 0 .. jsonb_array_length(v->'people') - 1 loop
    perform pg_temp.putx(tag || '-' || (i + 1)::text, (v->'people'->i->>'person_id')::uuid);
  end loop;
  return v;
end $$;
create function pg_temp.guests(cust uuid, st text) returns bigint language sql as
$$ select count(*) from public.event_guests g where g.event_id = pg_temp.fx('ev') and g.customer_id = cust and g.status = st $$;
-- (a) Ella signs up, staff take her off the list, she signs up again under another name with her phone and email.
select pg_temp.reg1('la', 'Ella', 'Testlist', pg_temp.ph(50), pg_temp.mail('ella'), null);
insert into fx select 'ella', (pg_temp.pp('la')).customer_id;
do $$ begin
  perform pg_temp.as_user('o');
  perform public.event_set_guest_cancelled((pg_temp.pp('la')).free_guest_id, true, 'Asked not to come');
  perform pg_temp.as_service();
end $$;
select pg_temp.reg1('la2', 'Elle', 'Nickname', pg_temp.ph(50), pg_temp.mail('ella'), null);
-- (b) Fay is on the list and signs up again under another name.
select pg_temp.reg1('lb', 'Fay', 'Testlist', pg_temp.ph(51), pg_temp.mail('fay'), null);
insert into fx select 'fay', (pg_temp.pp('lb')).customer_id;
select pg_temp.reg1('lb2', 'Faye', 'Other', pg_temp.ph(51), pg_temp.mail('fay'), null);
-- (c) one form, two new people of different names sharing a phone and an email.
select pg_temp.regn('lc', jsonb_build_array(pg_temp.person(1, 'Gina', 'Testalpha', pg_temp.ph(52), pg_temp.mail('gg')),
                                            pg_temp.person(2, 'Gus', 'Testbeta', pg_temp.ph(52), pg_temp.mail('gg'))));
-- (d) an existing customer and a relative in one form, one phone and one email.
select pg_temp.cust('hana', 'Hana Testexist', pg_temp.ph(53), pg_temp.mail('hh'));
select pg_temp.regn('ld', jsonb_build_array(pg_temp.person(1, 'Hana', 'Testexist', pg_temp.ph(53), pg_temp.mail('hh')),
                                            pg_temp.person(2, 'Hiro', 'Testrelative', pg_temp.ph(53), pg_temp.mail('hh'))));
select pg_temp.check((pg_temp.pp('la')).match = 'new_customer' and pg_temp.fx('ella') is not null
    and pg_temp.tx('reg:la2')::jsonb->>'status' = 'registered'
    and ((pg_temp.pp('la2')).match, (pg_temp.pp('la2')).hold_reason, (pg_temp.pp('la2')).customer_id, (pg_temp.pp('la2')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, null::uuid, array[pg_temp.fx('ella')])
    and pg_temp.guests(pg_temp.fx('ella'), 'registered') = 0 and pg_temp.guests(pg_temp.fx('ella'), 'cancelled') = 1
    and pg_temp.on_phone(pg_temp.ph(50)) = 1,
  'S10a taken off the list, then the same phone and email under another name: held phone_and_email_in_use (her record the candidate), not back on the list: '
  || pg_temp.tx('reg:la2'));
select pg_temp.check(((pg_temp.pp('lb2')).match, (pg_temp.pp('lb2')).hold_reason, (pg_temp.pp('lb2')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, array[pg_temp.fx('fay')])
    and pg_temp.guests(pg_temp.fx('fay'), 'registered') = 1,
  'S10b still on the list, the same phone and email under another name: held, one guest on her record');
select pg_temp.check((pg_temp.pp('lc-1')).match = 'new_customer'
    and ((pg_temp.pp('lc-2')).match, (pg_temp.pp('lc-2')).hold_reason, (pg_temp.pp('lc-2')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, array[(pg_temp.pp('lc-1')).customer_id])
    and pg_temp.on_phone(pg_temp.ph(52)) = 1 and pg_temp.guests((pg_temp.pp('lc-1')).customer_id, 'registered') = 1,
  'S10c one form, two new people of different names sharing a phone and an email: the second held, not put on the first''s record: '
  || pg_temp.tx('reg:lc'));
select pg_temp.check(((pg_temp.pp('ld-1')).match, (pg_temp.pp('ld-1')).customer_id) = ('exact'::text, pg_temp.fx('hana'))
    and ((pg_temp.pp('ld-2')).match, (pg_temp.pp('ld-2')).hold_reason, (pg_temp.pp('ld-2')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, array[pg_temp.fx('hana')])
    and pg_temp.guests(pg_temp.fx('hana'), 'registered') = 1,
  'S10d an existing customer and a relative in one form, one phone and email: the relative held, one guest on her record');
-- S11: merged records (441): a merge here takes nothing onto the kept record (437's unticked Link).
do $$ begin
  perform pg_temp.cust('m1finn', 'Finn Testmergeone', pg_temp.ph(54), pg_temp.mail('m1'));
  perform pg_temp.cust('m1hal', 'Hal Testmergeone', pg_temp.ph(54), pg_temp.mail('m1'));
  perform pg_temp.cust('m1gwen', 'Gwen Testmergeone', pg_temp.ph(55), null);
  perform pg_temp.cust('m2finn', 'Finn Testmergetwo', pg_temp.ph(56), pg_temp.mail('m2'));
  perform pg_temp.cust('m2gwen', 'Gwen Testmergetwo', pg_temp.ph(56), null);
  perform pg_temp.cust('m2hal', 'Hal Testmergetwo', pg_temp.ph(57), pg_temp.mail('m2'));
  perform pg_temp.cust('m3finn', 'Finn Testmergethree', pg_temp.ph(58), pg_temp.mail('m3'));
  perform pg_temp.cust('m3gwen', 'Gwen Testmergethree', pg_temp.ph(59), pg_temp.mail('m3'));
  perform pg_temp.cust('m3hal', 'Hal Testmergethree', pg_temp.ph(58), null);
  perform pg_temp.cust('m4finn', 'Finn Testmergefour', pg_temp.ph(60), pg_temp.mail('m4'));
  perform pg_temp.cust('m4hal', 'Hal Testmergefour', pg_temp.ph(60), pg_temp.mail('m4'));
  perform pg_temp.cust('m5finn', 'Finn Testmergefive', pg_temp.ph(61), pg_temp.mail('m5'));
  perform pg_temp.cust('m5hal', 'Hal Testmergefive', pg_temp.ph(61), null);
  perform pg_temp.cust('m5gwen', 'Gwen Testmergefive', pg_temp.ph(62), null);
  perform pg_temp.as_user('o');
  perform pg_temp.put('merges', jsonb_build_array(
    public.merge_customer_records(pg_temp.fx('m1gwen'), pg_temp.fx('m1hal'), 'T469: the same person (test)', gen_random_uuid()),
    public.merge_customer_records(pg_temp.fx('m2gwen'), pg_temp.fx('m2hal'), 'T469: the same person (test)', gen_random_uuid()),
    public.merge_customer_records(pg_temp.fx('m3gwen'), pg_temp.fx('m3hal'), 'T469: the same person (test)', gen_random_uuid()),
    public.merge_customer_records(pg_temp.fx('m4finn'), pg_temp.fx('m4hal'), 'T469: the same person (test)', gen_random_uuid()),
    public.merge_customer_records(pg_temp.fx('m5gwen'), pg_temp.fx('m5hal'), 'T469: the same person (test)', gen_random_uuid()))::text);
  perform pg_temp.as_service();
end $$;
create temp table s11 as
select k, public.event_web_match_customer(pg_temp.ph(n), 'Zed Testnewname', pg_temp.mail(k)) as m
  from (values ('m1', 54), ('m2', 56), ('m3', 58), ('m4', 60), ('m5', 61)) t(k, n);
select pg_temp.check((select bool_and((x ->> 'success')::boolean) from jsonb_array_elements(pg_temp.tx('merges')::jsonb) x)
    and (select (c.phone, c.email) is not distinct from (pg_temp.ph(55), null::text) from customers c where c.id = pg_temp.fx('m1gwen'))
    and (select deleted_at is not null from customers where id = pg_temp.fx('m1hal'))
    and public.event_web_kept_customer(pg_temp.fx('m1hal')) = pg_temp.fx('m1gwen')
    and public.event_web_kept_customer(pg_temp.fx('m4hal')) = pg_temp.fx('m4finn'),
  'S11 fixture: five merges, nothing taken onto the kept records: ' || pg_temp.tx('merges'));
select pg_temp.check((select m->>'kind' = 'held' and m->>'hold_reason' = 'phone_and_email_in_use'
                             and (select array_agg(x::uuid order by x::uuid) from jsonb_array_elements_text(m->'candidates') x)
                                 = (select array_agg(x order by x) from unnest(array[pg_temp.fx('m1finn'), pg_temp.fx('m1hal')]) x)
                        from s11 where k = 'm1')
    and (select bool_and(m->>'kind' = 'held' and m->>'hold_reason' = 'phone_and_email_in_use') from s11 where k in ('m2', 'm3')),
  'S11a one live record with the phone and the email, and another kept record holding both through a record it merged away (both, the phone alone, or the email alone through it): held phone_and_email_in_use, as before (441): '
  || (select string_agg(k || ' ' || m::text, '; ' order by k) from s11 where k in ('m1', 'm2', 'm3')));
select pg_temp.check((select m from s11 where k = 'm4') = jsonb_build_object('kind', 'phone_and_email', 'customer_id', pg_temp.fx('m4finn'))
    and (select m from s11 where k = 'm5') = jsonb_build_object('kind', 'phone_and_email', 'customer_id', pg_temp.fx('m5finn')),
  'S11b the merged-away record kept by that same live record, or another kept record holding the phone alone through it: linked: '
  || (select string_agg(k || ' ' || m::text, '; ' order by k) from s11 where k in ('m4', 'm5')));
-- S12: on this event's list in any way (the Owner, 24 Oct 2026), then a sign-up under another name with that
-- customer's phone and email. A guest staff add, as the Event page adds one.
create function pg_temp.staff_guest(cust text, name text, phone text) returns uuid language plpgsql as $$
declare r jsonb; begin
  perform pg_temp.as_user('o');
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', name, 'phone', phone,
         'customer_id', pg_temp.fx(cust), 'days', jsonb_build_array(public.sg_today() + 30)));
  perform pg_temp.as_service();
  perform pg_temp.putx('g:' || cust, (r->>'guest_id')::uuid);
  return (r->>'guest_id')::uuid;
end $$;
create function pg_temp.guests_all(cust uuid) returns bigint language sql as
$$ select count(*) from public.event_guests g where g.event_id = pg_temp.fx('ev') and g.customer_id = cust $$;
-- (a) a guest staff added.
select pg_temp.cust('ada', 'Ada Teststaff', pg_temp.ph(76), pg_temp.mail('ada'));
select pg_temp.staff_guest('ada', 'Ada Teststaff', pg_temp.ph(76));
select pg_temp.reg1('s12a', 'Adeline', 'Other', pg_temp.ph(76), pg_temp.mail('ada'), null);
-- (b) a ticket guest from an invoice (written as the invoice's sale writes it).
select pg_temp.cust('ben', 'Ben Testticket', pg_temp.ph(77), pg_temp.mail('ben'));
do $$ declare v_inv uuid; begin
  perform pg_temp.as_user('o');
  insert into invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, discount_total, total_amount, paid_amount, business_date)
  values ('T469-TK-' || pg_temp.tx('sfx'), pg_temp.fx('van'), pg_temp.fx('ben'), pg_temp.fx('o'), 'unpaid', 10, 0, 10, 0, public.sg_today())
  returning id into v_inv;
  insert into event_guests(event_id, name, phone, customer_id, source, invoice_id, invoice_item_id, line_position)
  values (pg_temp.fx('ev'), 'Ben Testticket', pg_temp.ph(77), pg_temp.fx('ben'), 'ticket', v_inv, gen_random_uuid(), 1);
  perform pg_temp.as_service();
end $$;
select pg_temp.reg1('s12b', 'Benny', 'Other', pg_temp.ph(77), pg_temp.mail('ben'), null);
-- (c) a guest staff added, then took off the list.
select pg_temp.cust('cal', 'Cal Testoff', pg_temp.ph(78), pg_temp.mail('cal'));
select pg_temp.staff_guest('cal', 'Cal Testoff', pg_temp.ph(78));
do $$ begin
  perform pg_temp.as_user('o');
  perform public.event_set_guest_cancelled(pg_temp.fx('g:cal'), true, 'Asked not to come');
  perform pg_temp.as_service();
end $$;
select pg_temp.reg1('s12c', 'Callum', 'Other', pg_temp.ph(78), pg_temp.mail('cal'), null);
-- (d) a website sign-up staff closed.
select pg_temp.reg1('s12d0', 'Dee', 'Testclosed', pg_temp.ph(79), pg_temp.mail('dee'), null);
insert into fx select 'dee', (pg_temp.pp('s12d0')).customer_id;
do $$ declare r jsonb; begin
  perform pg_temp.as_user('o');
  begin
    r := public.event_registration_close(pg_temp.fx('s12d0'), 'Not coming (test)');
  exception when others then r := jsonb_build_object('error', sqlerrm);
  end;
  perform pg_temp.put('s12d_close', r::text);
  perform pg_temp.as_service();
end $$;
select pg_temp.reg1('s12d', 'Deena', 'Other', pg_temp.ph(79), pg_temp.mail('dee'), null);
-- (e) the same name as a customer staff added: today's rules.
select pg_temp.cust('eve', 'Eve Testsamename', pg_temp.ph(80), pg_temp.mail('eve'));
select pg_temp.staff_guest('eve', 'Eve Testsamename', pg_temp.ph(80));
select pg_temp.reg1('s12e', 'Eve', 'Testsamename', pg_temp.ph(80), pg_temp.mail('eve'), null);
-- (f) the name of two customers on the phone, the email picking the one staff added.
select pg_temp.cust('fia1', 'Fia Testsame', pg_temp.ph(81), null);
select pg_temp.cust('fia2', 'Fia Testsame', pg_temp.ph(81), pg_temp.mail('fia'));
select pg_temp.staff_guest('fia2', 'Fia Testsame', pg_temp.ph(81));
select pg_temp.reg1('s12f', 'Fia', 'Testsame', pg_temp.ph(81), pg_temp.mail('fia'), null);
select pg_temp.check(((pg_temp.pp('s12a')).match, (pg_temp.pp('s12a')).hold_reason, (pg_temp.pp('s12a')).customer_id, (pg_temp.pp('s12a')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, null::uuid, array[pg_temp.fx('ada')])
    and pg_temp.guests_all(pg_temp.fx('ada')) = 1 and pg_temp.guests(pg_temp.fx('ada'), 'registered') = 1
    and pg_temp.tx('reg:s12a')::jsonb->>'status' = 'registered',
  'S12a a guest staff added, a sign-up under another name with their phone and email: held phone_and_email_in_use (that customer), no second guest row: '
  || pg_temp.tx('reg:s12a'));
select pg_temp.check(((pg_temp.pp('s12b')).match, (pg_temp.pp('s12b')).hold_reason, (pg_temp.pp('s12b')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, array[pg_temp.fx('ben')])
    and pg_temp.guests_all(pg_temp.fx('ben')) = 1,
  'S12b a ticket guest from an invoice: held, no second guest row');
select pg_temp.check(((pg_temp.pp('s12c')).match, (pg_temp.pp('s12c')).hold_reason, (pg_temp.pp('s12c')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, array[pg_temp.fx('cal')])
    and pg_temp.guests(pg_temp.fx('cal'), 'registered') = 0 and pg_temp.guests(pg_temp.fx('cal'), 'cancelled') = 1
    and pg_temp.guests_all(pg_temp.fx('cal')) = 1,
  'S12c a guest staff added and took off the list: held, not put back, no second guest row');
select pg_temp.check((pg_temp.tx('s12d_close')::jsonb->>'ok')::boolean and (pg_temp.pp('s12d0')).match = 'closed'
    and ((pg_temp.pp('s12d')).match, (pg_temp.pp('s12d')).hold_reason, (pg_temp.pp('s12d')).candidate_customer_ids)
        is not distinct from ('held'::text, 'phone_and_email_in_use'::text, array[pg_temp.fx('dee')])
    and pg_temp.guests(pg_temp.fx('dee'), 'registered') = 0 and pg_temp.guests_all(pg_temp.fx('dee')) = 1,
  'S12d a website sign-up staff closed: held, not put back: ' || pg_temp.tx('s12d_close'));
select pg_temp.check(((pg_temp.pp('s12e')).match, (pg_temp.pp('s12e')).customer_id) = ('exact'::text, pg_temp.fx('eve'))
    and pg_temp.guests(pg_temp.fx('eve'), 'registered') = 2,
  'S12e the same name as a customer staff added: today''s rules (linked by the name, a second guest row, as before 469)');
select pg_temp.check(((pg_temp.pp('s12f')).match, (pg_temp.pp('s12f')).hold_reason, (pg_temp.pp('s12f')).customer_id)
        is not distinct from ('held'::text, 'several_name_matches'::text, null::uuid)
    and (select array_agg(x order by x) from unnest((pg_temp.pp('s12f')).candidate_customer_ids) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('fia1'), pg_temp.fx('fia2')]) x)
    and pg_temp.guests_all(pg_temp.fx('fia2')) = 1,
  'S12f the name of two customers on the phone, the email picking the one staff added: held several_name_matches with the two (that sign-up''s hold before 469), no second guest row');
-- S7: a test key (after S12: it sees the event's guests as a live key does).
select pg_temp.cust('tess', 'Tess Testkey', pg_temp.ph(82), pg_temp.mail('tess'));
create temp table s7made as select pg_temp.made() as m;
select pg_temp.reg1('s7', 'Tessa', 'Other', pg_temp.ph(82), pg_temp.mail('tess'), pg_temp.tx('code_rhea'), 'test');
select pg_temp.reg1('s7b', 'Samantha', 'Other', pg_temp.ph(40), pg_temp.mail('sam'), pg_temp.tx('code_rhea'), 'test');
select pg_temp.reg1('s7c', 'Adeline', 'Other', pg_temp.ph(76), pg_temp.mail('ada'), null, 'test');
select pg_temp.check((pg_temp.pp('s7')).match = 'test' and (pg_temp.pp('s7')).customer_id is null
    and (pg_temp.pp('s7')).test_outcome = '{"match": "phone_and_email", "hold_reason": null, "referral": "already_customer"}'::jsonb
    and (pg_temp.pp('s7b')).test_outcome = '{"match": "held", "hold_reason": "phone_and_email_in_use", "referral": "held"}'::jsonb
    and (pg_temp.pp('s7c')).test_outcome = '{"match": "held", "hold_reason": "phone_and_email_in_use", "referral": null}'::jsonb
    and pg_temp.guests_all(pg_temp.fx('tess')) = 0 and pg_temp.guests_all(pg_temp.fx('ada')) = 1
    and pg_temp.delta((select m from s7made)) = '{"customers": 0, "affiliates": 0, "accounts": 0, "claims": 0, "matches": 0, "checks": 0}'::jsonb,
  'S7 a test key: what a live key would have done (a customer not on the list: linked by the phone and the email, already a customer; S1''s and S12a''s, on the list: held), nothing made: '
  || (pg_temp.pp('s7')).test_outcome::text || ' ' || (pg_temp.pp('s7b')).test_outcome::text || ' ' || (pg_temp.pp('s7c')).test_outcome::text);

-- ═════ G Grants ═════
select pg_temp.check((select bool_and((select array_agg(coalesce(r.rolname, 'public') || ':' || a.privilege_type order by coalesce(r.rolname, 'public') || ':' || a.privilege_type)
                                         from pg_proc p cross join lateral aclexplode(p.proacl) a left join pg_roles r on r.oid = a.grantee
                                        where p.oid = ('public.' || w.fn)::regprocedure)
                                      = (select array_agg(x order by x) from unnest(array['postgres:EXECUTE', 'service_role:EXECUTE']
                                           || case when w.anon then array['anon:EXECUTE'] else '{}'::text[] end
                                           || case when w.auth then array['authenticated:EXECUTE'] else '{}'::text[] end) x)
                                      and has_function_privilege('anon', 'public.' || w.fn, 'execute') = w.anon
                                      and has_function_privilege('authenticated', 'public.' || w.fn, 'execute') = w.auth
                                      and has_function_privilege('service_role', 'public.' || w.fn, 'execute')
                                      and (select prosecdef and proconfig = array['search_path=public'] from pg_proc
                                            where oid = ('public.' || w.fn)::regprocedure))
                       from want w),
  'G1 each function keeps its grants (the referral page: the anon key; the sign-up: signed-in logins; the seminar: the service role alone), security definer, search_path public');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                  and p.proname ~ '(phone_and_email|phone_email|469)'),
  'G2 no function was added (no name of this rule to collide with)');

select pg_temp.check(pg_temp.delta((select m from made0))->>'customers' is not null,
  'Z the counts were read: ' || pg_temp.delta((select m from made0))::text);

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'phone-and-email-469: % check(s) failed:\n  %', n, m; end if;
  raise notice 'phone-and-email-469: all checks passed';
end $$;
rollback;
