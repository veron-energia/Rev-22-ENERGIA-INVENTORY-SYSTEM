-- The event website after a customer merge, and the affiliate login's own details (439).
--
-- The owner's answers, 21 Oct 2026 (08:40):
--   1. To match follows a customer Link or merge: a held registration whose
--      candidate was retired by a merge (merge_customer_records, its audit row
--      customers_merged; chains A -> B -> C) shows the KEPT record; attaching
--      to the retired id attaches to the kept record; making a new customer
--      counts the kept record as the holder of that phone or email inbox, so
--      the affiliate's (A) and Q19's checks still apply (no referral at once,
--      no commission before the check); the note says what is true now.
--   2. No self-referral also compares the affiliate LOGIN's own details: its
--      email (auth.users) and the name and phone it signed up with
--      (raw_user_meta_data). A family member's record joined to her login by
--      phone alone (437's rule 7) no longer lets her earn on herself.
--
--   G  Grants and md5s: the new helper is the service role's alone; the six
--      changed functions keep their grants and have 439's AFTER md5s.
--   K  event_web_kept_customer: itself; a deleted record (not merged) none; a
--      chain A -> B -> C gives C; the retired record's note changed, the
--      audit log still finds it.
--   MA Q19 on another customer's phone, merged after the hold (the kept
--      record does not have the phone): the kept record is the candidate (with
--      the retired one under merged_from), the note says the phone was on a
--      record since merged; a VIP paid while held; made a customer, they wait
--      for the check (sharing with the kept record) and earn nothing; checked
--      as a different person: referred, the VIP earns once. Attached to the
--      retired id: the kept record, already a customer (audited).
--   MB The affiliate's own record merged into an older one: someone else on
--      her old phone shares her phone (note), made a customer they wait; she
--      herself under that record's name (affiliate_name hold): attached to the
--      retired id she is herself, her VIP paid while held lands on the kept
--      record and earns her upline once and her nothing; made a new customer
--      under that name: not referred.
--   MC A chain A -> B -> C on an email inbox (R6-1): the end of the chain is
--      the candidate, the note and the check name it.
--   MD Merged before the registration: the kept record with the phone holds
--      them as before; the kept record without it: a new customer, referred at
--      once (436's rule: nobody has the phone; NOT COVERED); the affiliate's
--      merged record's phone: a check at once (not referred at once); her
--      merged record's name: held as herself.
--   ME Merged after staff attached them: they follow the merge (as before).
--   MF The kept record already has the phone: one candidate, 436's note and
--      check.
--   MG The phone left the holder's record by an edit (no merge): the note
--      says it is on no record now, and what making a customer does.
--   MN No link: the kept record is the candidate, no note; attaching to the
--      retired id works.
--   MR Hers only while still retired and kept by her record: a record merged
--      into hers and then restored is its own again, so a stranger merged
--      into it later (name, phone) and a login put on it are not hers;
--      a chain merged into hers (V into Q, Q into her) still is.
--   MP A retired record's phone that cannot be read: merged_from says its
--      phone did not match (only its email did).
--   (The attach looking again when the record it follows is merged while it
--   waits for that record's lock needs two sessions, so it is not in this
--   file; it was checked on a throwaway copy, 21 Oct 2026.)
--   L  The login: her login's sign-up name on a new phone with the login
--      email (A1) is held as herself, no customer made; made a new customer:
--      not referred, her VIP earns nobody anything; on the household phone
--      (A2) she is herself while held and made a customer; someone else on a
--      login's sign-up phone or email (not on any record): a check at once;
--      the mother (the record) herself: self, the note names the login; a
--      real family member: referred as before; the test key says self; a
--      login signed up under the record's own name changes no wording. Where
--      437 is applied, the review's own case through 437's sign-up (L9).
--   N  Nothing else: a plain registration through the link is referred, an
--      exact match is already a customer.
--   M  439 twice changes nothing; its self-test leaves no row (when this file
--      installs it).
--
-- Disposable local database only; everything is rolled back. Every name and
-- email is invented (@example.com); phones are ACMA's fictional ranges (+61 2
-- 5550 ...., and +61 491 570 737, 572 983, 573 770, 570 006). It installs 436
-- when it is missing, then 439 twice (run with -v skip_install=1 where 439 is
-- already installed). Every check runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
select to_regprocedure('public.event_web_call(text,uuid,text,jsonb)') is null as need_436 \gset
\if :need_436
\ir ../../../supabase/436_event_website_registrations_and_vip.sql
\endif
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
\if :{?skip_install}
\else
create temp table r439 as select pg_temp.row_counts() as before;
\ir ../../../supabase/439_event_website_follows_merges_and_login_self_check.sql
create temp table m439 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
alter table r439 add column after1 jsonb;
update r439 set after1 = pg_temp.row_counts();
\ir ../../../supabase/439_event_website_follows_merges_and_login_self_check.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
-- 441 (the owner, 21 Oct 2026, ~11:40) closed one of 439's NOT COVERED: a registration made after a merge
-- on a phone or inbox only the retired record had is held for the kept record. MD2, MD3, MR1 and MR3 check
-- 441's outcome where it is installed (its own suite, event-website-441.sql, has the rest), 439's where not.
create function pg_temp.has441() returns boolean language sql as
$$ select pg_get_functiondef('public.event_web_match_customer(text,text,text)'::regprocedure) like '%-- 441 (the owner, 21 Oct 2026, ~11:40)%' $$;
select pg_temp.has441() as has441 \gset
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
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'service_role', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- Fictional phones: +61 2 5550 nnnn (ACMA's drama range), one block per run.
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad(((pg_temp.tx('phbase')::int + n) % 10000)::text, 4, '0') $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'ht439-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
create function pg_temp.bid(prefix text, tag text) returns text language sql as
$$ select prefix || '-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || prefix || tag), 1, 8)) $$;
create function pg_temp.person(pos int, first text, last text, phone text, email text, days date[])
returns jsonb language sql as
$$ select jsonb_build_object('position', pos, 'first_name', first, 'last_name', last, 'phone', phone, 'email', email,
            'days', to_jsonb(days), 'vip', false) $$;
create function pg_temp.call(kind text, typ text, body jsonb, req uuid default gen_random_uuid()) returns jsonb
language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_service();
  v := public.event_web_call(pg_temp.tx('hash:' || kind), case when typ in ('event_info','referral_info','person','sync') then null else req end,
                             typ, jsonb_build_object('type', typ, 'event', pg_temp.tx('code')) || body);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
-- One person registered through a link (code null: none); the answer is kept under the tag.
create function pg_temp.reg1(tag text, first text, last text, phone text, email text, code text, kind text default 'live')
returns uuid language plpgsql as $$
declare v jsonb;
begin
  v := pg_temp.call(kind, 'register', jsonb_build_object('registration', jsonb_build_object(
         'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', code,
         'people', jsonb_build_array(pg_temp.person(1, first, last, phone, email, array[pg_temp.d(7)])))));
  perform pg_temp.put('ans:' || tag, v::text);
  perform pg_temp.putx(tag, (v->'people'->0->>'person_id')::uuid);
  perform pg_temp.put('tok:' || tag, v->'people'->0->>'upgrade_token');
  return (v->'people'->0->>'person_id')::uuid;
end $$;
create function pg_temp.pp(tag text) returns public.event_registration_people language sql as
$$ select * from public.event_registration_people where id = pg_temp.fx(tag) $$;
create function pg_temp.note(tag text) returns text language sql as
$$ select public.event_web_referral_note(pg_temp.fx(tag)) $$;
-- A HitPay VIP payment for one person, by their token.
create function pg_temp.paid(tag text, person_tag text) returns jsonb language sql as
$$ select pg_temp.call('live', 'vip_paid', jsonb_build_object('payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'provider', 'hitpay',
     'payment_request_id', md5('rq' || tag || pg_temp.tx('sfx'))::uuid, 'payment_id', md5('py' || tag || pg_temp.tx('sfx'))::uuid,
     'amount_cents', 7200, 'currency', 'SGD', 'livemode', true, 'paid_at', now() - interval '1 minute',
     'upgrade_tokens', jsonb_build_array(pg_temp.tx('tok:' || person_tag)),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null)))) $$;
create function pg_temp.vorder(tag text) returns public.event_vip_orders language sql as
$$ select * from public.event_vip_orders where order_id = pg_temp.bid('VIP', tag) $$;
create function pg_temp.vinv(tag text) returns public.invoices language sql as
$$ select i.* from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
     join public.invoices i on i.id = op.invoice_id where o.order_id = pg_temp.bid('VIP', tag) limit 1 $$;
create function pg_temp.comm(inv uuid) returns jsonb language sql as
$$ select coalesce(jsonb_agg(jsonb_build_array(c.tier::text, c.referrer_customer_id) order by c.tier::text), '[]'::jsonb)
     from commissions c where c.invoice_id = inv and c.status::text <> 'reversed' $$;
-- The To match entry of a held person, as the Event page reads it (as the Owner).
create function pg_temp.hold(tag text) returns jsonb language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_user('owner');
  select h into v from jsonb_array_elements(public.event_web_guest_extras(pg_temp.fx('ev'))->'holds') h
   where (h->>'person_id')::uuid = pg_temp.fx(tag);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
create function pg_temp.cands(tag text) returns uuid[] language sql as
$$ select coalesce(array_agg((c->>'customer_id')::uuid order by c->>'customer_id'), '{}'::uuid[])
     from jsonb_array_elements(pg_temp.hold(tag)->'candidates') c $$;
create function pg_temp.check_of(cust uuid) returns public.referral_signup_checks language sql as
$$ select * from referral_signup_checks where customer_id = cust $$;
create function pg_temp.cust(sfx_name text, phone text, email text) returns uuid language sql as
$$ insert into customers(full_name, phone, email) values (sfx_name, phone, email) returning id $$;
create function pg_temp.merge(keep text, gone text) returns text language sql as
$$ select pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)', pg_temp.fx(keep), pg_temp.fx(gone),
                             'The same person (test)', gen_random_uuid())) $$;
-- 440 (where it is applied) reads an affiliate login's sign-up details from the server's own copy
-- (affiliate_signup_identities), not from its user metadata. A fixture login is given that copy too, made
-- the way 440's backfill makes it from the login (its email and raw_user_meta_data), so every check below
-- reads the same with or without 440. Without 440 the table is not there and this does nothing.
create function pg_temp.signup_copy(p_login uuid) returns void language plpgsql as
$$begin
  if to_regclass('public.affiliate_signup_identities') is null then return; end if;
  execute $q$
    insert into public.affiliate_signup_identities (auth_user_id, affiliate_account_id, customer_id, first_name, last_name,
        full_name, phone, email, source, name_from, phone_from)
    select u.id, a.id, a.customer_id, m.first_name, m.last_name,
           coalesce(nullif(btrim(coalesce(m.first_name, '') || ' ' || coalesce(m.last_name, '')), ''), m.full_name),
           m.phone, nullif(lower(btrim(coalesce(u.email, ''))), ''), 'backfill',
           case when m.first_name is not null or m.last_name is not null or m.full_name is not null then 'user_metadata' end,
           case when m.phone is not null then 'user_metadata' end
      from auth.users u
      join public.affiliate_accounts a on a.auth_user_id = u.id
      cross join lateral (
        select nullif(btrim(coalesce(u.raw_user_meta_data ->> 'first_name', '')), '') as first_name,
               nullif(btrim(coalesce(u.raw_user_meta_data ->> 'last_name', '')), '') as last_name,
               nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), '') as full_name,
               nullif(btrim(coalesce(u.raw_user_meta_data ->> 'phone', '')), '') as phone) m
     where u.id = $1
       and not exists (select 1 from public.affiliate_signup_identities x where x.auth_user_id = u.id)$q$ using p_login;
end$$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; ev uuid; src uuid; pm uuid; v1 uuid; v2 uuid; c uuid; a uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 9000))::int::text);
  foreach k in array array['owner', 'acting', 'manager', 'staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'ht439-' || k || '-' || lower(sfx) || '@example.com');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'HT439 ' || initcap(k) || ' ' || sfx, 'ht439-' || k || '-' || lower(sfx) || '@example.com',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'manager' then 'manager' else 'staff' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('HT439 Van ' || sfx, 'HT439V' || sfx, 'SG') returning id into st;
  insert into fx values ('van', st);
  insert into user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st);
  ev := public.event_save(jsonb_build_object('name', 'HT439 Health Seminar ' || sfx,
    'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('HT439 Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src);
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('HT439 $72 discount Voucher', 'HT439SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT439 3-in-1 Vouchers', 'HT439-3IN1' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into fx values ('save72', v1), ('three', v2);
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true), (v2, st, 216, true);
  perform public.event_web_settings_save(ev, jsonb_build_object('code', 'HT439-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(v1, v2), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://healthtalk.example.com/api/app/sync'));
  insert into tx values ('code', 'HT439-' || sfx);
  -- The affiliates whose links people come through (no login: Alma; the others below).
  a := pg_temp.cust('Alma Testref', pg_temp.ph(900), pg_temp.mail('alma'));
  insert into customer_affiliates(customer_id, status, referral_code) values (a, 'active', 'HN' || sfx);
  c := pg_temp.cust('Alma Upline', pg_temp.ph(901), null);
  update customers set referred_by = c where id = a;
  insert into fx values ('alma', a), ('alma_up', c);
  insert into tx values ('code_alma', 'HN' || sfx);
end $$;
do $$ declare r jsonb; begin
  perform pg_temp.as_user('owner');
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'Vercel production');
  insert into tx values ('hash:live', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  r := public.event_web_key_create(pg_temp.fx('ev'), 'test', 'Vercel preview');
  insert into tx values ('hash:test', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
end $$;
select pg_temp.check((pg_temp.call('live', 'event_info', '{}')->>'ok')::boolean, 'F the fixture event answers event_info');

-- ═════ G Grants and md5s ═════
select pg_temp.check(not has_function_privilege('anon', 'public.event_web_kept_customer(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_kept_customer(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.event_web_kept_customer(uuid)', 'execute'),
  'G1 event_web_kept_customer is the service role''s alone');
select pg_temp.check((select bool_and(not has_function_privilege('anon', x.f, 'execute')
                                      and has_function_privilege('authenticated', x.f, 'execute') = x.page
                                      and has_function_privilege('service_role', x.f, 'execute'))
                        from (values ('public.event_web_affiliate_contact(uuid)', false), ('public.event_web_check_self_referral(uuid,uuid)', false),
                                     ('public.event_web_referral_note(uuid)', false), ('public.event_web_new_customer(uuid)', false),
                                     ('public.event_web_guest_extras(uuid)', true), ('public.event_registration_attach(uuid,uuid,text)', true)) x(f, page)),
  'G2 the six changed functions keep 436''s grants (the page''s two signed-in staff''s, the four others the service role''s)');
-- (440, where it is applied, patched two of them: their AFTER is 439's or 440's.)
select pg_temp.check((select bool_and(md5(pg_get_functiondef(x.f::regprocedure)) = any (string_to_array(x.m, ' ')))
                        from (values ('public.event_web_kept_customer(uuid)', 'cb0720c1088df9209da45e46b91601f4'),
                                     ('public.event_web_affiliate_contact(uuid)', 'e4adbd007d847daee24e8d5d28b96b75 3c81727e93dc5b73ca1d8833d95f75bb'),
                                     ('public.event_web_check_self_referral(uuid,uuid)', '11475114504d5bab79981ed8bb8c12b0 2a5ab36c3d878197c21221a9a1ff193f'),
                                     ('public.event_web_referral_note(uuid)', 'd68893db63938cc774b157708bd341f1'),
                                     ('public.event_web_new_customer(uuid)', 'a253f76a9db721212a9c110bc41ff483'),
                                     ('public.event_web_guest_extras(uuid)', '18b56a28bb4965b2188cd73dde056209'),
                                     ('public.event_registration_attach(uuid,uuid,text)', 'b31be4d82d20000df026e7cfa9b24095')) x(f, m)),
  'G3 the seven functions have 439''s AFTER md5s (440''s for the two it patched, where it is applied)');
select pg_temp.check((select bool_and(pg_get_functiondef(x.f::regprocedure) ~ E'\nbegin\n  perform public\\.require_active_staff\\(')
                        from (values ('public.event_web_guest_extras(uuid)'), ('public.event_registration_attach(uuid,uuid,text)')) x(f)),
  'G4 the two page functions still call require_active_staff first');

-- ═════ K event_web_kept_customer ═════
do $$ declare a uuid; b uuid; c uuid; d uuid; begin
  a := pg_temp.cust('Kay Chain', pg_temp.ph(800), null); b := pg_temp.cust('Kay Chain', pg_temp.ph(801), null);
  c := pg_temp.cust('Kay Chain', pg_temp.ph(802), null); d := pg_temp.cust('Kay Gone', pg_temp.ph(803), null);
  insert into fx values ('k_a', a), ('k_b', b), ('k_c', c), ('k_d', d);
end $$;
select pg_temp.as_user('owner');
select pg_temp.put('k_m1', pg_temp.merge('k_b', 'k_a'));
select pg_temp.put('k_m2', pg_temp.merge('k_c', 'k_b'));
update customers set deleted_at = now() where id = pg_temp.fx('k_d');
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('k_m1') = 'ok' and pg_temp.tx('k_m2') = 'ok'
    and public.event_web_kept_customer(pg_temp.fx('k_a')) = pg_temp.fx('k_c')
    and public.event_web_kept_customer(pg_temp.fx('k_b')) = pg_temp.fx('k_c')
    and public.event_web_kept_customer(pg_temp.fx('k_c')) = pg_temp.fx('k_c')
    and public.event_web_kept_customer(pg_temp.fx('k_d')) is null
    and public.event_web_kept_customer(null) is null
    and public.event_web_kept_customer(gen_random_uuid()) is null,
  'K1 a live record is itself; A merged into B, then B into C: C for each; a record deleted another way, null, or no record: none');
update customers set notes = 'Note rewritten by hand' where id = pg_temp.fx('k_a');
select pg_temp.check(public.event_web_kept_customer(pg_temp.fx('k_a')) = pg_temp.fx('k_c'),
  'K2 the retired record''s note rewritten: the audit log still names the record that kept it');

-- ═════ MA Q19 on another customer's phone, merged after the hold ═════
do $$ begin
  insert into fx values ('fay', pg_temp.cust('Fay Holder', pg_temp.ph(1), null)),
                        ('fay_k', pg_temp.cust('Fay Keptrec', pg_temp.ph(2), pg_temp.mail('fay-k')));
end $$;
select pg_temp.reg1('ma1', 'Gus', 'Other', pg_temp.ph(1), pg_temp.mail('gus'), pg_temp.tx('code_alma'));
select pg_temp.reg1('ma2', 'Hal', 'Other', pg_temp.ph(1), pg_temp.mail('hal'), pg_temp.tx('code_alma'));
select pg_temp.put('ma_note_before', pg_temp.note('ma1'));
select pg_temp.put('ma1_paid', pg_temp.paid('ma1v', 'ma1')::text);
select pg_temp.check((pg_temp.pp('ma1')).match = 'held' and (pg_temp.pp('ma1')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('ma1')).candidate_customer_ids = array[pg_temp.fx('fay')] and (pg_temp.pp('ma1')).referral_outcome = 'held'
    and pg_temp.tx('ma_note_before') like 'Their phone is on another customer''s record.%'
    and (pg_temp.vorder('ma1v')).status = 'needs_review' and (pg_temp.vorder('ma1v')).waiting_for_match,
  'MA0 before the merge: held on Fay''s phone (436 as before), her VIP paid while held waits: ' || pg_temp.tx('ma_note_before'));
select pg_temp.as_user('owner');
select pg_temp.put('ma_merge', pg_temp.merge('fay_k', 'fay'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('ma_merge') = 'ok'
    and pg_temp.cands('ma1') = array[pg_temp.fx('fay_k')]
    and (select (c->'merged_from'->0->>'customer_id')::uuid = pg_temp.fx('fay') and (c->'merged_from'->0->>'phone_matches')::boolean
                and not (c->>'phone_matches')::boolean and c->>'full_name' = 'Fay Keptrec'
           from jsonb_array_elements(pg_temp.hold('ma1')->'candidates') c),
  'MA1 merged into Fay Keptrec (who does not have the phone): the kept record is the candidate, the retired one under merged_from (its phone matched): '
  || coalesce((pg_temp.hold('ma1')->'candidates')::text, 'none'));
select pg_temp.check(pg_temp.note('ma1') = format('Their phone was on Fay Holder''s record, since merged into Fay Keptrec''s (listed). '
      || 'If this is that customer, link that record: an existing customer is not referred through this link (%s). If it is someone '
      || 'else, make a new customer: they become Alma Testref''s referral once an Owner or Manager checks them as a different person '
      || '(Affiliates page), and no commission comes before that.', pg_temp.tx('code_alma'))
    and pg_temp.hold('ma1')->>'referral_note' = pg_temp.note('ma1'),
  'MA2 the note no longer says the phone is on another customer''s record: it says where it was, and what each choice does: ' || pg_temp.note('ma1'));
select pg_temp.as_user('staff');
select pg_temp.put('ma3_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('ma1'), 'His own record')));
select pg_temp.putx('gus', (pg_temp.pp('ma1')).customer_id);
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('ma3_make') = 'ok' and (pg_temp.pp('ma1')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = pg_temp.fx('gus')) is null
    and (pg_temp.check_of(pg_temp.fx('gus'))).status = 'pending'
    and (pg_temp.check_of(pg_temp.fx('gus'))).referrer_customer_id = pg_temp.fx('alma')
    and (pg_temp.check_of(pg_temp.fx('gus'))).phone_shared_with = array[pg_temp.fx('fay_k')]
    and (pg_temp.vorder('ma1v')).status = 'invoiced' and (pg_temp.vinv('ma1v')).customer_id = pg_temp.fx('gus')
    and pg_temp.comm((pg_temp.vinv('ma1v')).id) = '[]'::jsonb
    and exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('gus') and l.action = 'referral_check_waiting'
                  and l.new_data->'merged_holders' = jsonb_build_array(pg_temp.fx('fay_k'))
                  and l.reason like 'Their phone was on a customer''s record since merged into another:%'),
  'MA3 made a customer: no referral at once (Q19 as before the merge), a check shared with the kept record, audited; the VIP paid while held is invoiced and earns nothing yet: '
  || pg_temp.tx('ma3_make'));
select pg_temp.check(pg_temp.note('ma1') = format('Waiting for a check: their phone was on Fay Holder''s record, since merged into Fay Keptrec''s. '
      || 'They become Alma Testref''s referral (link %s) once an Owner or Manager checks them as a different person (Affiliates page); '
      || 'no commission comes before that.', pg_temp.tx('code_alma')),
  'MA3 the waiting note says where the phone was: ' || pg_temp.note('ma1'));
select pg_temp.as_user('owner');
select pg_temp.put('ma3_check', public.decide_referral_signup_check((pg_temp.check_of(pg_temp.fx('gus'))).id, 'different_person', 'Asked: a different person')::text);
select pg_temp.as_service();
select pg_temp.check((select referred_by from customers where id = pg_temp.fx('gus')) = pg_temp.fx('alma')
    and (pg_temp.pp('ma1')).referral_outcome = 'check_confirmed'
    and pg_temp.comm((pg_temp.vinv('ma1v')).id) = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('alma')), jsonb_build_array('tier2', pg_temp.fx('alma_up'))),
  'MA4 checked as a different person: referred by Alma, and the VIP earns Alma and her upline once: ' || pg_temp.comm((pg_temp.vinv('ma1v')).id)::text);
select pg_temp.as_user('staff');
select pg_temp.put('ma5_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx('ma2'), pg_temp.fx('fay'), 'The page listed Fay before the merge')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('ma5_att') = 'ok' and (pg_temp.pp('ma2')).match = 'staff_attached'
    and (pg_temp.pp('ma2')).customer_id = pg_temp.fx('fay_k') and (pg_temp.pp('ma2')).referral_outcome = 'already_customer'
    and (select referred_by from customers where id = pg_temp.fx('fay_k')) is null
    and (select g.customer_id from event_guests g where g.id = (pg_temp.pp('ma2')).free_guest_id) = pg_temp.fx('fay_k')
    and exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('ma2') and l.action = 'event_registration_matched'
                  and (l.new_data->>'asked_customer_id')::uuid = pg_temp.fx('fay') and (l.new_data->>'merged_into')::uuid = pg_temp.fx('fay_k')
                  and (l.new_data->>'suggested_customer')::boolean),
  'MA5 attached to the retired id: attached to the kept record (no "Customer not found"), already a customer, audited with both ids: ' || pg_temp.tx('ma5_att'));
do $$ begin insert into fx values ('del', pg_temp.cust('Dee Holder', pg_temp.ph(48), null)); end $$;
select pg_temp.reg1('ma6', 'Ida', 'Other', pg_temp.ph(48), pg_temp.mail('ida'), null);
update customers set deleted_at = now() where id = pg_temp.fx('del');
select pg_temp.as_user('staff');
select pg_temp.put('ma6_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx('ma6'), pg_temp.fx('del'), 'Deleted one')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('ma6_att') = 'Customer not found.' and (pg_temp.pp('ma6')).match = 'held'
    and pg_temp.cands('ma6') = '{}'::uuid[],
  'MA6 a candidate deleted another way (not merged): not listed, and attaching to it is still "Customer not found.": ' || pg_temp.tx('ma6_att'));

-- ═════ MB The affiliate's own record merged into an older one ═════
do $$ declare fa uuid; ka uuid; u2 uuid; begin
  fa := pg_temp.cust('Bea Testaff', pg_temp.ph(10), pg_temp.mail('bea'));
  insert into customer_affiliates(customer_id, status, referral_code) values (fa, 'active', 'HB' || pg_temp.tx('sfx'));
  ka := pg_temp.cust('Bea T Testaff', pg_temp.ph(11), null);
  u2 := pg_temp.cust('Bea Upline', pg_temp.ph(12), null);
  update customers set referred_by = u2 where id = ka;
  insert into fx values ('bea', fa), ('bea_k', ka), ('bea_up', u2);
  insert into tx values ('code_bea', 'HB' || pg_temp.tx('sfx'));
end $$;
select pg_temp.reg1('mb1', 'Ned', 'Kin', pg_temp.ph(10), pg_temp.mail('ned'), pg_temp.tx('code_bea'));
select pg_temp.reg1('mb2', 'Bea', 'Testaff', pg_temp.ph(13), pg_temp.mail('bea2'), pg_temp.tx('code_bea'));
select pg_temp.reg1('mb3', 'Testaff', 'Bea', pg_temp.ph(14), pg_temp.mail('bea3'), pg_temp.tx('code_bea'));
select pg_temp.put('mb2_paid', pg_temp.paid('mb2v', 'mb2')::text);
select pg_temp.check((pg_temp.pp('mb1')).hold_reason = 'phone_in_use' and (pg_temp.pp('mb1')).referral_outcome = 'held'
    and (pg_temp.pp('mb2')).hold_reason = 'affiliate_name' and (pg_temp.pp('mb2')).referral_outcome = 'self'
    and (pg_temp.pp('mb2')).candidate_customer_ids = array[pg_temp.fx('bea')]
    and (pg_temp.pp('mb3')).hold_reason = 'affiliate_name' and (pg_temp.vorder('mb2v')).waiting_for_match,
  'MB0 before the merge: Ned held on Bea''s phone, Bea herself (twice, new phones) held under her name, her VIP waits');
select pg_temp.as_user('owner');
select pg_temp.put('mb_merge', pg_temp.merge('bea_k', 'bea'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mb_merge') = 'ok'
    and (select referrer_customer_id from event_registrations where id = (pg_temp.pp('mb1')).registration_ref) = pg_temp.fx('bea_k')
    and pg_temp.cands('mb1') = array[pg_temp.fx('bea_k')] and pg_temp.cands('mb2') = array[pg_temp.fx('bea_k')],
  'MB1 merged into Bea T Testaff (her phone not taken): the link''s referrer and both holds'' candidate are the kept record: ' || pg_temp.tx('mb_merge'));
select pg_temp.check(pg_temp.note('mb1') = format('Shares the phone of Bea T Testaff, the affiliate whose link (%s) was used. If this is Bea T Testaff, '
      || 'link that record: not referred. If it is someone else, make a new customer: they become Bea T Testaff''s referral once an Owner '
      || 'or Manager checks them as a different person (Affiliates page), and no commission comes before that.', pg_temp.tx('code_bea')),
  'MB2 her merged record''s phone is still hers: Ned shares it (the note): ' || pg_temp.note('mb1'));
select pg_temp.as_user('staff');
select pg_temp.put('mb3_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('mb1'), 'Her cousin')));
select pg_temp.putx('ned', (pg_temp.pp('mb1')).customer_id);
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mb3_make') = 'ok' and (pg_temp.pp('mb1')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = pg_temp.fx('ned')) is null
    and (pg_temp.check_of(pg_temp.fx('ned'))).referrer_customer_id = pg_temp.fx('bea_k')
    and pg_temp.fx('bea_k') = any ((pg_temp.check_of(pg_temp.fx('ned'))).phone_shared_with),
  'MB3 Ned made a customer: waits for the check (the A rule as before the merge), no referrer: ' || pg_temp.tx('mb3_make'));
select pg_temp.as_user('staff');
select pg_temp.put('mb4_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx('mb2'), pg_temp.fx('bea'), 'Bea herself')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mb4_att') = 'ok' and (pg_temp.pp('mb2')).customer_id = pg_temp.fx('bea_k')
    and (pg_temp.pp('mb2')).referral_outcome = 'self' and 'customer' = any ((pg_temp.pp('mb2')).referral_self_by)
    and (pg_temp.vorder('mb2v')).status = 'invoiced' and (pg_temp.vinv('mb2v')).customer_id = pg_temp.fx('bea_k')
    and pg_temp.comm((pg_temp.vinv('mb2v')).id) = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('bea_up'))),
  'MB4 Bea attached to her retired record: her kept record, herself; her VIP paid while held lands there and earns her upline once, her nothing: '
  || pg_temp.comm((pg_temp.vinv('mb2v')).id)::text);
select pg_temp.as_user('staff');
select pg_temp.put('mb5_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('mb3'), 'Staff made one')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mb5_make') = 'ok' and (pg_temp.pp('mb3')).referral_outcome = 'self'
    and (select referred_by from customers where id = (pg_temp.pp('mb3')).customer_id) is null
    and pg_temp.check_of((pg_temp.pp('mb3')).customer_id) is null
    and not exists (select 1 from referral_signup_events e where e.new_customer_id = (pg_temp.pp('mb3')).customer_id),
  'MB5 her merged record''s name, made a new customer: not referred (no referrer, no check, no sign-up event): ' || pg_temp.tx('mb5_make'));

-- ═════ MC A chain on an email inbox ═════
do $$ begin
  insert into fx values ('ivy1', pg_temp.cust('Ivy One', pg_temp.ph(20), pg_temp.mail('ivy'))),
                        ('ivy2', pg_temp.cust('Ivy Two', pg_temp.ph(21), null)),
                        ('ivy3', pg_temp.cust('Ivy Three', pg_temp.ph(22), null));
end $$;
select pg_temp.reg1('mc1', 'Jon', 'Mail', pg_temp.ph(23), pg_temp.mail('ivy'), pg_temp.tx('code_alma'));
select pg_temp.as_user('owner');
select pg_temp.put('mc_m1', pg_temp.merge('ivy2', 'ivy1'));
select pg_temp.put('mc_m2', pg_temp.merge('ivy3', 'ivy2'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mc_m1') = 'ok' and pg_temp.tx('mc_m2') = 'ok' and (pg_temp.pp('mc1')).hold_reason = 'email_in_use'
    and pg_temp.cands('mc1') = array[pg_temp.fx('ivy3')]
    and (select (c->'merged_from'->0->>'customer_id')::uuid = pg_temp.fx('ivy1') and (c->'merged_from'->0->>'email_matches')::boolean
           from jsonb_array_elements(pg_temp.hold('mc1')->'candidates') c),
  'MC1 Ivy One merged into Ivy Two, then into Ivy Three: Ivy Three is the candidate (Ivy One under merged_from, her email matched)');
select pg_temp.check(pg_temp.note('mc1') = format('Their email inbox was on Ivy One''s record, since merged into Ivy Three''s (listed). If this is '
      || 'that customer, link that record: an existing customer is not referred through this link (%s). If it is someone else, make a new '
      || 'customer: they become Alma Testref''s referral once an Owner or Manager checks them as a different person (Affiliates page), and no '
      || 'commission comes before that.', pg_temp.tx('code_alma')),
  'MC2 the note names the end of the chain: ' || pg_temp.note('mc1'));
-- Jon pays VIP after the merge, still held.
select pg_temp.put('mc1_paid', pg_temp.paid('mc1v', 'mc1')::text);
select pg_temp.as_user('staff');
select pg_temp.put('mc3_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('mc1'), 'A different Jon')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mc3_make') = 'ok' and (pg_temp.pp('mc1')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = (pg_temp.pp('mc1')).customer_id) is null
    and (pg_temp.check_of((pg_temp.pp('mc1')).customer_id)).phone_shared_with = array[pg_temp.fx('ivy3')]
    and pg_temp.note('mc1') like 'Waiting for a check: their email inbox was on Ivy One''s record, since merged into Ivy Three''s. They become Alma Testref''s referral%'
    and (pg_temp.vorder('mc1v')).status = 'invoiced' and (pg_temp.vinv('mc1v')).customer_id = (pg_temp.pp('mc1')).customer_id
    and pg_temp.comm((pg_temp.vinv('mc1v')).id) = '[]'::jsonb,
  'MC3 made a customer: waits for the check (R6-1 as before the merge), shared with Ivy Three; the VIP paid after the merge is invoiced and earns nothing yet: '
  || pg_temp.note('mc1'));

-- ═════ MD Merged before the registration ═════
do $$ declare fb uuid; kb uuid; begin
  insert into fx values ('kim', pg_temp.cust('Kim Dup', pg_temp.ph(30), null)), ('kim_k', pg_temp.cust('Kim Keep', pg_temp.ph(30), null)),
                        ('moe', pg_temp.cust('Moe Old', pg_temp.ph(31), null)), ('moe_k', pg_temp.cust('Moe New', pg_temp.ph(32), null));
  fb := pg_temp.cust('Cora Fresh', pg_temp.ph(33), pg_temp.mail('cora'));
  insert into customer_affiliates(customer_id, status, referral_code) values (fb, 'active', 'HC' || pg_temp.tx('sfx'));
  kb := pg_temp.cust('Cora Testold', pg_temp.ph(34), null);
  insert into fx values ('cora', fb), ('cora_k', kb);
  insert into tx values ('code_cora', 'HC' || pg_temp.tx('sfx'));
end $$;
select pg_temp.as_user('owner');
select pg_temp.put('md_m1', pg_temp.merge('kim_k', 'kim'));
select pg_temp.put('md_m2', pg_temp.merge('moe_k', 'moe'));
select pg_temp.put('md_m3', pg_temp.merge('cora_k', 'cora'));
select pg_temp.as_service();
select pg_temp.reg1('md1', 'Lou', 'Other', pg_temp.ph(30), pg_temp.mail('lou'), pg_temp.tx('code_alma'));
select pg_temp.reg1('md2', 'Max', 'Other', pg_temp.ph(31), pg_temp.mail('max'), pg_temp.tx('code_alma'));
select pg_temp.reg1('md3', 'Nia', 'Kin', pg_temp.ph(33), pg_temp.mail('nia'), pg_temp.tx('code_cora'));
select pg_temp.reg1('md4', 'Cora', 'Fresh', pg_temp.ph(35), pg_temp.mail('cora4'), pg_temp.tx('code_cora'));
select pg_temp.check(pg_temp.tx('md_m1') = 'ok' and (pg_temp.pp('md1')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('md1')).candidate_customer_ids = array[pg_temp.fx('kim_k')]
    and pg_temp.note('md1') like 'Their phone is on another customer''s record. If this is that customer, link their record:%',
  'MD1 merged before, the kept record has the phone: held on it, 436''s note: ' || pg_temp.note('md1'));
\if :has441
select pg_temp.check(pg_temp.tx('md_m2') = 'ok' and (pg_temp.pp('md2')).match = 'held' and (pg_temp.pp('md2')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('md2')).candidate_customer_ids = array[pg_temp.fx('moe')] and (pg_temp.pp('md2')).referral_outcome = 'held'
    and (pg_temp.pp('md2')).customer_id is null and pg_temp.cands('md2') = array[pg_temp.fx('moe_k')],
  'MD2 (441) merged before, the kept record without the phone: held for the kept record (the retired one the candidate), not referred at once');
select pg_temp.check((pg_temp.pp('md3')).match = 'held' and (pg_temp.pp('md3')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('md3')).candidate_customer_ids = array[pg_temp.fx('cora')] and (pg_temp.pp('md3')).referral_outcome = 'held'
    and pg_temp.note('md3') = format('Shares the phone of Cora Testold, the affiliate whose link (%s) was used. If this is Cora Testold, '
          || 'link that record: not referred. If it is someone else, make a new customer: they become Cora Testold''s referral once an Owner '
          || 'or Manager checks them as a different person (Affiliates page), and no commission comes before that.', pg_temp.tx('code_cora')),
  'MD3 (441) the affiliate''s record merged before (its phone dropped): someone else on that phone is held first, as on her live phone: ' || pg_temp.note('md3'));
select pg_temp.as_user('staff');
select pg_temp.put('md3_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('md3'), 'Her niece')));
select pg_temp.as_service();
\else
select pg_temp.check(pg_temp.tx('md_m2') = 'ok' and (pg_temp.pp('md2')).match = 'new_customer' and (pg_temp.pp('md2')).referral_outcome = 'created'
    and (select referred_by from customers where id = (pg_temp.pp('md2')).customer_id) = pg_temp.fx('alma'),
  'MD2 merged before, the kept record without the phone: nobody has it, so a new customer referred at once (436''s rule; NOT COVERED)');
select pg_temp.put('md3_make', 'ok');
\endif
select pg_temp.check(pg_temp.tx('md_m3') = 'ok' and pg_temp.tx('md3_make') = 'ok'
    and (pg_temp.pp('md3')).match = case when pg_temp.has441() then 'staff_created' else 'new_customer' end
    and (pg_temp.pp('md3')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = (pg_temp.pp('md3')).customer_id) is null
    and (pg_temp.check_of((pg_temp.pp('md3')).customer_id)).referrer_customer_id = pg_temp.fx('cora_k')
    and pg_temp.note('md3') = format('Waiting for a check: shares the phone of Cora Testold, the affiliate whose link (%s) was used. They become '
          || 'Cora Testold''s referral once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
          pg_temp.tx('code_cora')),
  'MD3 the affiliate''s record merged before (its phone dropped): someone else on that phone waits for a check, not referred at once: ' || pg_temp.note('md3'));
select pg_temp.check((pg_temp.pp('md4')).hold_reason = 'affiliate_name' and (pg_temp.pp('md4')).candidate_customer_ids = array[pg_temp.fx('cora_k')]
    and (pg_temp.pp('md4')).referral_outcome = 'self' and (pg_temp.pp('md4')).referral_self_by = array['name']
    and exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('md4') and l.action = 'event_registration_self_referral'
                  and l.new_data->>'name_from' = 'merged_record'),
  'MD4 her merged record''s name on a new phone and email: held as herself (audited: name_from merged_record)');

-- ═════ ME Merged after staff attached them ═════
do $$ begin
  insert into fx values ('ola', pg_temp.cust('Ola Holder', pg_temp.ph(40), null)), ('ola_k', pg_temp.cust('Ola Keep', pg_temp.ph(41), null));
end $$;
select pg_temp.reg1('me1', 'Pam', 'Other', pg_temp.ph(40), pg_temp.mail('pam'), pg_temp.tx('code_alma'));
select pg_temp.as_user('staff');
select pg_temp.put('me_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx('me1'), pg_temp.fx('ola'), 'Her')));
select pg_temp.as_user('owner');
select pg_temp.put('me_merge', pg_temp.merge('ola_k', 'ola'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('me_att') = 'ok' and pg_temp.tx('me_merge') = 'ok' and (pg_temp.pp('me1')).customer_id = pg_temp.fx('ola_k')
    and (pg_temp.pp('me1')).referral_outcome = 'already_customer'
    and pg_temp.note('me1') like 'Already a customer, so not referred again through this link%',
  'ME1 attached, then merged: the person follows the merge as before (436), the note unchanged');

-- ═════ MF The kept record already has the phone ═════
do $$ begin
  insert into fx values ('quin', pg_temp.cust('Quin Holder', pg_temp.ph(42), null)), ('quin_k', pg_temp.cust('Quin Keep', pg_temp.ph(42), null));
end $$;
select pg_temp.reg1('mf1', 'Rex', 'Other', pg_temp.ph(42), pg_temp.mail('rex'), pg_temp.tx('code_alma'));
select pg_temp.as_user('owner');
select pg_temp.put('mf_merge', pg_temp.merge('quin_k', 'quin'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mf_merge') = 'ok' and pg_temp.cands('mf1') = array[pg_temp.fx('quin_k')]
    and pg_temp.note('mf1') like 'Their phone is on another customer''s record. If this is that customer, link their record:%',
  'MF1 the kept record has the phone too: listed once, 436''s note');
select pg_temp.as_user('staff');
select pg_temp.put('mf_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('mf1'), 'Another Rex')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mf_make') = 'ok' and (pg_temp.pp('mf1')).referral_outcome = 'check_waiting'
    and (pg_temp.check_of((pg_temp.pp('mf1')).customer_id)).phone_shared_with = array[pg_temp.fx('quin_k')]
    and exists (select 1 from audit_logs l where l.record_id = (pg_temp.pp('mf1')).customer_id and l.action = 'referral_check_waiting'
                  and l.reason like 'Their phone is on another customer''s record:%'),
  'MF2 made a customer: waits for the check, as 436 (its audit wording)');

-- ═════ MG The phone left the holder's record by an edit ═════
do $$ begin insert into fx values ('sia', pg_temp.cust('Sia Holder', pg_temp.ph(44), null)); end $$;
select pg_temp.reg1('mg1', 'Tom', 'Other', pg_temp.ph(44), pg_temp.mail('tom'), pg_temp.tx('code_alma'));
select pg_temp.as_user('owner');
select pg_temp.put('mg_edit', pg_temp.err(format('update customers set phone = %L where id = %L', pg_temp.ph(45), pg_temp.fx('sia'))));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mg_edit') = 'ok'
    and pg_temp.note('mg1') = format('Their phone was on another customer''s record when they registered, but is on no customer''s record now. If this '
          || 'is an existing customer, link their record: an existing customer is not referred through this link (%s). If it is someone else, '
          || 'make a new customer: they become Alma Testref''s referral at once.', pg_temp.tx('code_alma')),
  'MG1 the holder''s phone edited away (no merge): the note says it is on no record now: ' || coalesce(pg_temp.note('mg1'), pg_temp.tx('mg_edit')));
select pg_temp.as_user('staff');
select pg_temp.put('mg_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('mg1'), 'New')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mg_make') = 'ok' and (pg_temp.pp('mg1')).referral_outcome = 'created'
    and (select referred_by from customers where id = (pg_temp.pp('mg1')).customer_id) = pg_temp.fx('alma'),
  'MG2 made a customer then: referred at once, as the note says (436''s rule)');

-- ═════ MN No link ═════
do $$ begin
  insert into fx values ('uma', pg_temp.cust('Uma Holder', pg_temp.ph(46), null)), ('uma_k', pg_temp.cust('Uma Keep', pg_temp.ph(47), null));
end $$;
select pg_temp.reg1('mn1', 'Vic', 'Other', pg_temp.ph(46), pg_temp.mail('vic'), null);
select pg_temp.as_user('owner');
select pg_temp.put('mn_merge', pg_temp.merge('uma_k', 'uma'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mn_merge') = 'ok' and pg_temp.cands('mn1') = array[pg_temp.fx('uma_k')] and pg_temp.note('mn1') is null,
  'MN1 no link: the kept record is the candidate, no referral note');
select pg_temp.as_user('staff');
select pg_temp.put('mn_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx('mn1'), pg_temp.fx('uma'), 'Her')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mn_att') = 'ok' and (pg_temp.pp('mn1')).customer_id = pg_temp.fx('uma_k') and (pg_temp.pp('mn1')).referral_outcome is null,
  'MN2 attached to the retired id: the kept record, no referral outcome');

-- ═════ MR Hers only while still retired and kept by her record ═════
do $$ begin
  insert into fx values ('mr_x', pg_temp.cust('Xena Restored', pg_temp.ph(500), null)),
                        ('mr_z', pg_temp.cust('Zed Stranger', pg_temp.ph(501), pg_temp.mail('mr-zed'))),
                        ('mr_v', pg_temp.cust('Vic Chainone', pg_temp.ph(510), pg_temp.mail('mr-vic'))),
                        ('mr_q', pg_temp.cust('Quo Chaintwo', pg_temp.ph(511), null));
end $$;
select pg_temp.as_user('owner');
select pg_temp.put('mr_m1', pg_temp.merge('alma', 'mr_x'));
select pg_temp.put('mr_rs', pg_temp.err(format('select public.restore_customer_with_phone(%L)', pg_temp.fx('mr_x'))));
select pg_temp.put('mr_m2', pg_temp.merge('mr_x', 'mr_z'));
select pg_temp.put('mr_m3', pg_temp.merge('mr_q', 'mr_v'));
select pg_temp.put('mr_m4', pg_temp.merge('alma', 'mr_q'));
select pg_temp.as_service();
-- X, live again, gets its own affiliate login (signed up under another name, with its own phone and email).
do $$ declare xa uuid; xl uuid := gen_random_uuid(); begin
  insert into customer_affiliates(customer_id, status, referral_code) values (pg_temp.fx('mr_x'), 'active', 'HX' || pg_temp.tx('sfx'))
    returning id into xa;
  insert into auth.users(id, email, raw_user_meta_data)
  values (xl, pg_temp.mail('mr-xlogin'), jsonb_build_object('first_name', 'Xavi', 'last_name', 'Loginname', 'phone', pg_temp.ph(506)));
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (xl, pg_temp.fx('mr_x'), xa, 'claimed');
  perform pg_temp.signup_copy(xl);
end $$;
select pg_temp.reg1('mr1', 'Zed', 'Stranger', pg_temp.ph(502), pg_temp.mail('mr-zed1'), pg_temp.tx('code_alma'));
select pg_temp.reg1('mr2', 'Pat', 'Other', pg_temp.ph(501), pg_temp.mail('mr-pat'), pg_temp.tx('code_alma'));
select pg_temp.reg1('mr3', 'Xavi', 'Loginname', pg_temp.ph(507), pg_temp.mail('mr-xavi'), pg_temp.tx('code_alma'));
select pg_temp.reg1('mr4', 'Kit', 'Other', pg_temp.ph(506), pg_temp.mail('mr-xlogin'), pg_temp.tx('code_alma'));
select pg_temp.reg1('mr5', 'Vic', 'Chainone', pg_temp.ph(512), pg_temp.mail('mr-vic5'), pg_temp.tx('code_alma'));
select pg_temp.reg1('mr6', 'Ula', 'Other', pg_temp.ph(510), pg_temp.mail('mr-ula'), pg_temp.tx('code_alma'));
select pg_temp.check(pg_temp.tx('mr_m1') = 'ok' and pg_temp.tx('mr_rs') = 'ok' and pg_temp.tx('mr_m2') = 'ok'
    and (select deleted_at is null from customers where id = pg_temp.fx('mr_x'))
    and public.event_web_kept_customer(pg_temp.fx('mr_z')) = pg_temp.fx('mr_x'),
  'MR0 X merged into Alma, then restored, then Zed merged into X: X is live and keeps Zed: '
  || pg_temp.tx('mr_m1') || ', ' || pg_temp.tx('mr_rs') || ', ' || pg_temp.tx('mr_m2'));
select pg_temp.check((select bool_and((pg_temp.pp(t)).match = 'new_customer' and (pg_temp.pp(t)).referral_outcome = 'created'
                                      and (pg_temp.pp(t)).referral_self_by is null
                                      and public.event_web_affiliate_contact(pg_temp.fx(t)) is null
                                      and (select referred_by from customers where id = (pg_temp.pp(t)).customer_id) = pg_temp.fx('alma'))
                        from unnest(case when pg_temp.has441() then array['mr1'] else array['mr1', 'mr2'] end) t)
    and (not pg_temp.has441()
         or ((pg_temp.pp('mr2')).match = 'held' and (pg_temp.pp('mr2')).hold_reason = 'phone_in_use'
             and (pg_temp.pp('mr2')).candidate_customer_ids = array[pg_temp.fx('mr_z')] and (pg_temp.pp('mr2')).referral_outcome = 'held'
             and (pg_temp.pp('mr2')).referral_self_by is null and public.event_web_affiliate_contact(pg_temp.fx('mr2')) is null
             and pg_temp.cands('mr2') = array[pg_temp.fx('mr_x')])),
  case when pg_temp.has441()
       then 'MR1 (441) Zed''s name on a new phone through Alma''s link is not her (X was restored before Zed was merged into it): referred at once; someone else on Zed''s phone is held for X (not her either)'
       else 'MR1 Zed''s name on a new phone, and someone else on Zed''s phone, through Alma''s link: neither is her (X was restored before Zed was merged into it): referred at once, as anyone new' end);
select pg_temp.check((select bool_and((pg_temp.pp(t)).match = 'new_customer' and (pg_temp.pp(t)).referral_outcome = 'created'
                                      and (pg_temp.pp(t)).referral_self_by is null
                                      and (select referred_by from customers where id = (pg_temp.pp(t)).customer_id) = pg_temp.fx('alma'))
                        from unnest(array['mr3', 'mr4'])  t),
  'MR2 the restored record''s own login (its name; its sign-up phone and email) is not Alma''s: referred at once');
\if :has441
select pg_temp.check((pg_temp.pp('mr6')).match = 'held' and (pg_temp.pp('mr6')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('mr6')).candidate_customer_ids = array[pg_temp.fx('mr_v')] and (pg_temp.pp('mr6')).referral_outcome = 'held'
    and pg_temp.cands('mr6') = array[pg_temp.fx('alma')],
  'MR3 (441) someone else on Vic''s phone (Vic into Quo, Quo into Alma) is held first, for Alma''s record, as on her live phone');
select pg_temp.as_user('staff');
select pg_temp.put('mr6_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('mr6'), 'Someone else')));
select pg_temp.as_service();
\else
select pg_temp.put('mr6_make', 'ok');
\endif
select pg_temp.check(pg_temp.tx('mr_m3') = 'ok' and pg_temp.tx('mr_m4') = 'ok' and pg_temp.tx('mr6_make') = 'ok'
    and (pg_temp.pp('mr5')).hold_reason = 'affiliate_name' and (pg_temp.pp('mr5')).referral_outcome = 'self'
    and (pg_temp.pp('mr5')).referral_self_by = array['name']
    and (pg_temp.pp('mr6')).match = case when pg_temp.has441() then 'staff_created' else 'new_customer' end
    and (pg_temp.pp('mr6')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = (pg_temp.pp('mr6')).customer_id) is null
    and public.event_web_affiliate_contact(pg_temp.fx('mr6')) = array['phone'],
  'MR3 a chain merged into hers (Vic into Quo, Quo into Alma) is still hers: Vic''s name is held as herself, someone else on Vic''s phone waits for a check');

-- ═════ MP A retired record's phone that cannot be read ═════
-- A legacy record (its phone is a word), as old data has it: added with the triggers off.
set local session_replication_role = replica;
with c as (insert into customers(full_name, phone, email) values ('Lee Legacy', 'unknown', pg_temp.mail('mp-lee')) returning id)
insert into fx select 'mp_lee', c.id from c;
set local session_replication_role = origin;
do $$ begin
  insert into fx values ('mp_hal', pg_temp.cust('Hal Holder', pg_temp.ph(600), null)),
                        ('mp_kai', pg_temp.cust('Kai Keep', pg_temp.ph(601), null));
end $$;
select pg_temp.reg1('mp1', 'Rex', 'Person', pg_temp.ph(600), pg_temp.mail('mp-lee'), pg_temp.tx('code_alma'));
select pg_temp.as_user('owner');
select pg_temp.put('mp_merge', pg_temp.merge('mp_kai', 'mp_lee'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('mp_merge') = 'ok' and (pg_temp.pp('mp1')).hold_reason = 'phone_and_email_in_use'
    and (select (c->'merged_from'->0->>'customer_id')::uuid = pg_temp.fx('mp_lee')
                and not (c->'merged_from'->0->>'phone_matches')::boolean and (c->'merged_from'->0->>'email_matches')::boolean
           from jsonb_array_elements(pg_temp.hold('mp1')->'candidates') c where (c->>'customer_id')::uuid = pg_temp.fx('mp_kai')),
  'MP1 Lee (phone "unknown", Rex''s email) merged into Kai: under Kai, merged_from says only the email matched: '
  || coalesce((pg_temp.hold('mp1')->'candidates')::text, 'none'));

-- ═════ L The affiliate login's own details ═════
do $$ declare m uuid; u3 uuid; rl uuid; n uuid; nl uuid; begin
  m := pg_temp.cust('Siew Lan Testmum', '+61491570737', null);
  insert into customer_affiliates(customer_id, status, referral_code) values (m, 'active', 'HL' || pg_temp.tx('sfx'));
  u3 := pg_temp.cust('Mum Upline', pg_temp.ph(50), null);
  update customers set referred_by = u3 where id = m;
  rl := gen_random_uuid();
  -- Rachel's login, joined to her mother's record by its phone alone (437's rule 7).
  insert into auth.users(id, email, raw_user_meta_data)
  values (rl, pg_temp.mail('rachel'), jsonb_build_object('first_name', 'Rachel', 'last_name', 'Testmum', 'phone', '+61491570737'));
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
  values (rl, m, (select id from customer_affiliates where customer_id = m), 'claimed');
  perform pg_temp.signup_copy(rl);
  n := pg_temp.cust('Nora Testrec', pg_temp.ph(60), pg_temp.mail('nora'));
  insert into customer_affiliates(customer_id, status, referral_code) values (n, 'active', 'HO' || pg_temp.tx('sfx'));
  nl := gen_random_uuid();
  -- Nora's login, under her own name, signed up with another phone and email.
  insert into auth.users(id, email, raw_user_meta_data)
  values (nl, pg_temp.mail('nora-login'), jsonb_build_object('first_name', 'Nora', 'last_name', 'Testrec', 'phone', '+61491570006'));
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
  values (nl, n, (select id from customer_affiliates where customer_id = n), 'claimed');
  perform pg_temp.signup_copy(nl);
  insert into fx values ('mum', m), ('mum_up', u3), ('nora', n);
  insert into tx values ('code_mum', 'HL' || pg_temp.tx('sfx')), ('code_nora', 'HO' || pg_temp.tx('sfx'));
end $$;
select pg_temp.reg1('l1', 'Rachel', 'Testmum', '+61491572983', pg_temp.mail('rachel'), pg_temp.tx('code_mum'));
select pg_temp.put('l1_paid', pg_temp.paid('l1v', 'l1')::text);
select pg_temp.check((pg_temp.pp('l1')).match = 'held' and (pg_temp.pp('l1')).hold_reason = 'affiliate_name'
    and (pg_temp.pp('l1')).candidate_customer_ids = array[pg_temp.fx('mum')] and (pg_temp.pp('l1')).referral_outcome = 'self'
    and (pg_temp.pp('l1')).referral_self_by = array['name', 'email']
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) = '+61491572983')
    and not exists (select 1 from referral_signup_events e where e.referral_code = pg_temp.tx('code_mum'))
    and exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('l1') and l.action = 'event_registration_self_referral'
                  and l.new_data->>'name_from' = 'login')
    and (pg_temp.vorder('l1v')).waiting_for_match,
  'L1 (A1) Rachel through her own link, on her own mobile with her login email: held as herself (her login''s name and email), no customer, no referral, audited');
select pg_temp.check(pg_temp.note('l1') = format('Not referred: the same name and email inbox as Siew Lan Testmum (or Rachel Testmum, whose affiliate '
      || 'login is on her record), the affiliate whose link (%s) was used. If this is Siew Lan Testmum (or Rachel Testmum, whose affiliate login '
      || 'is on her record), link her record: she earns no commission from it. If it is someone else, make a new customer: they are not '
      || 'referred through this link either.', pg_temp.tx('code_mum')),
  'L1 the note names the login: ' || pg_temp.note('l1'));
select pg_temp.as_user('staff');
select pg_temp.put('l1_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('l1'), 'Rachel''s own record')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('l1_make') = 'ok' and (pg_temp.pp('l1')).referral_outcome = 'self'
    and (select referred_by from customers where id = (pg_temp.pp('l1')).customer_id) is null
    and pg_temp.check_of((pg_temp.pp('l1')).customer_id) is null
    and (pg_temp.vorder('l1v')).status = 'invoiced' and (pg_temp.vinv('l1v')).customer_id = (pg_temp.pp('l1')).customer_id
    and pg_temp.comm((pg_temp.vinv('l1v')).id) = '[]'::jsonb,
  'L1 made her own customer: not referred, no check; her VIP paid while held earns nobody anything (before 439: tier-1 for her mother''s record): ' || pg_temp.tx('l1_make'));
select pg_temp.reg1('l2', 'Rachel', 'Testmum', '+61491570737', pg_temp.mail('rachel2'), pg_temp.tx('code_mum'));
select pg_temp.check((pg_temp.pp('l2')).hold_reason = 'phone_in_use' and (pg_temp.pp('l2')).candidate_customer_ids = array[pg_temp.fx('mum')]
    and (pg_temp.pp('l2')).referral_outcome = 'self' and (pg_temp.pp('l2')).referral_self_by = array['name', 'phone'],
  'L2 (A2) Rachel on the household phone: held on her mother''s phone, and herself (her login''s name)');
select pg_temp.as_user('staff');
select pg_temp.put('l2_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('l2'), 'Not the mother')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('l2_make') = 'ok' and (pg_temp.pp('l2')).referral_outcome = 'self'
    and (select referred_by from customers where id = (pg_temp.pp('l2')).customer_id) is null
    and pg_temp.check_of((pg_temp.pp('l2')).customer_id) is null,
  'L2 made a customer: not referred, no check to confirm (before 439: a check, then tier-1 on her own VIP): ' || pg_temp.tx('l2_make'));
select pg_temp.reg1('l3', 'Otto', 'Friend', '+61491570006', pg_temp.mail('otto'), pg_temp.tx('code_nora'));
select pg_temp.check((pg_temp.pp('l3')).match = 'new_customer' and (pg_temp.pp('l3')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = (pg_temp.pp('l3')).customer_id) is null
    and (pg_temp.check_of((pg_temp.pp('l3')).customer_id)).referrer_customer_id = pg_temp.fx('nora')
    and pg_temp.note('l3') = format('Waiting for a check: shares the phone of Nora Testrec, the affiliate whose link (%s) was used. They become '
          || 'Nora Testrec''s referral once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
          pg_temp.tx('code_nora')),
  'L3 someone else on the phone Nora''s login signed up with (on no record): a check, not referred at once; her own name keeps 436''s wording: ' || pg_temp.note('l3'));
select pg_temp.reg1('l4', 'Pia', 'Friend', pg_temp.ph(61), pg_temp.mail('nora-login'), pg_temp.tx('code_nora'));
select pg_temp.check((pg_temp.pp('l4')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = (pg_temp.pp('l4')).customer_id) is null
    and pg_temp.note('l4') like 'Waiting for a check: shares the email inbox of Nora Testrec, the affiliate whose link%',
  'L4 someone else on Nora''s login email: a check, not referred at once');
select pg_temp.reg1('l5', 'Siew Lan', 'Testmum', '+61491570737', null, pg_temp.tx('code_mum'));
select pg_temp.check((pg_temp.pp('l5')).match = 'exact' and (pg_temp.pp('l5')).customer_id = pg_temp.fx('mum') and (pg_temp.pp('l5')).referral_outcome = 'self'
    and pg_temp.note('l5') = format('Not referred: this is Siew Lan Testmum, the affiliate whose link (%s) was used (her record''s affiliate login was '
          || 'signed up as Rachel Testmum). She earns no commission from it.', pg_temp.tx('code_mum')),
  'L5 the record''s own person through the link: herself, and the note names the login: ' || pg_temp.note('l5'));
select pg_temp.reg1('l6', 'Tan', 'Testdad', pg_temp.ph(62), pg_temp.mail('tan'), pg_temp.tx('code_mum'));
select pg_temp.check((pg_temp.pp('l6')).match = 'new_customer' and (pg_temp.pp('l6')).referral_outcome = 'created'
    and (select referred_by from customers where id = (pg_temp.pp('l6')).customer_id) = pg_temp.fx('mum'),
  'L6 a real family member on his own phone and email: referred at once, as before');
-- (Her login email is on the record staff made for her in L1 now, so another email here.)
select pg_temp.reg1('l7', 'Rachel', 'Testmum', pg_temp.ph(63), pg_temp.mail('rachel7'), pg_temp.tx('code_mum'), 'test');
select pg_temp.check((pg_temp.pp('l7')).is_test and (pg_temp.pp('l7')).test_outcome->>'referral' = 'self'
    and (pg_temp.pp('l7')).test_outcome->>'hold_reason' = 'affiliate_name' and (pg_temp.pp('l7')).referral_self_by = array['name']
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) = pg_temp.ph(63)),
  'L7 the test key says the same (self, held under her name) and makes nothing');
select pg_temp.reg1('l8', 'Nora', 'Testrec', pg_temp.ph(64), pg_temp.mail('nora8'), pg_temp.tx('code_nora'));
select pg_temp.check((pg_temp.pp('l8')).hold_reason = 'affiliate_name'
    and pg_temp.note('l8') = format('Not referred: the same name as Nora Testrec, the affiliate whose link (%s) was used. If this is Nora Testrec, link '
          || 'her record: she earns no commission from it. If it is someone else, make a new customer: they are not referred through this link either.',
          pg_temp.tx('code_nora')),
  'L8 a login signed up under the record''s own name: 436''s wording, unchanged: ' || pg_temp.note('l8'));

-- L9 (only where 437 is applied): the review's own case, through 437's sign-up. Rachel's login joins her mother's
-- record by its phone alone (rule 7); she registers herself through that link on her own mobile with her login email.
select to_regprocedure('public.affiliate_signup_matches_open()') is not null as has_437 \gset
\if :has_437
do $$ declare m uuid; u uuid; r jsonb; begin
  m := pg_temp.cust('Siew Lin Testmum', '+61491573770', null);
  u := gen_random_uuid();
  insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
  values (u, pg_temp.mail('rachel-437'), now(), jsonb_build_object('first_name', 'Rachel', 'last_name', 'Testlin', 'phone', '+61491573770'));
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  r := public.complete_affiliate_onboarding(null, null, null, true);
  insert into fx values ('lin', m);
  insert into tx values ('l9_onb', r::text), ('code_lin', r->>'referral_code');
end $$;
select pg_temp.as_service();
select pg_temp.check((pg_temp.tx('l9_onb')::jsonb->>'customer_id')::uuid = pg_temp.fx('lin') and pg_temp.tx('code_lin') is not null
    and not (pg_temp.tx('l9_onb')::jsonb->>'new_customer')::boolean,
  'L9 (437) Rachel''s sign-up joins her login to her mother''s record by its phone alone: ' || pg_temp.tx('l9_onb'));
select pg_temp.reg1('l9', 'Rachel', 'Testlin', pg_temp.ph(81), pg_temp.mail('rachel-437'), pg_temp.tx('code_lin'));
select pg_temp.put('l9_paid', pg_temp.paid('l9v', 'l9')::text);
select pg_temp.as_user('staff');
select pg_temp.put('l9_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('l9'), 'Rachel herself')));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('l9_make') = 'ok' and (pg_temp.pp('l9')).hold_reason = 'affiliate_name'
    and (pg_temp.pp('l9')).referral_outcome = 'self' and (pg_temp.pp('l9')).referral_self_by = array['name', 'email']
    and (select referred_by from customers where id = (pg_temp.pp('l9')).customer_id) is null
    and (pg_temp.vorder('l9v')).status = 'invoiced' and pg_temp.comm((pg_temp.vinv('l9v')).id) = '[]'::jsonb,
  'L9 (437) she registers herself on her own mobile with her login email: held as herself; made her own customer, not referred; her VIP earns nothing (the review''s S$10.80 tier-1 is gone)');
\endif

-- ═════ N Nothing else ═════
select pg_temp.reg1('n1', 'Wen', 'Newcomer', pg_temp.ph(70), pg_temp.mail('wen'), pg_temp.tx('code_alma'));
do $$ begin insert into fx values ('xia', pg_temp.cust('Xia Exact', pg_temp.ph(71), null)); end $$;
select pg_temp.reg1('n2', 'Xia', 'Exact', pg_temp.ph(71), pg_temp.mail('xia'), pg_temp.tx('code_alma'));
select pg_temp.reg1('n3', 'Alma', 'Testref', pg_temp.ph(72), pg_temp.mail('alma3'), pg_temp.tx('code_alma'));
select pg_temp.check((pg_temp.pp('n1')).referral_outcome = 'created'
    and (select referred_by from customers where id = (pg_temp.pp('n1')).customer_id) = pg_temp.fx('alma')
    and (pg_temp.pp('n2')).match = 'exact' and (pg_temp.pp('n2')).referral_outcome = 'already_customer'
    and (pg_temp.pp('n3')).hold_reason = 'affiliate_name' and (pg_temp.pp('n3')).referral_self_by = array['name']
    and pg_temp.note('n3') like 'Not referred: the same name as Alma Testref, the affiliate whose link%',
  'N1 a new person through the link is referred, an exact match is already a customer, the affiliate''s own name is held as herself, as 436');

-- ═════ M 439 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m439 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m439),
  'M1 running 439 a second time changed no function');
select pg_temp.check((select before = after1 from r439),
  'M2 439''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 439 checks passed.';
end $$;
rollback;
