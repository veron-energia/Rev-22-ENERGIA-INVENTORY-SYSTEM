-- The event website holds a registration on a phone or email inbox that only a merged-away record had (441).
--
-- The owner's answer, 21 Oct 2026 (~11:40), to 439's open question (whether the phones and inboxes of
-- records retired by a merge count as held by the kept record): "Yes, in a later update". Someone who
-- registers after a merge on a phone or inbox only the retired record has (the kept record did not take
-- it: 437's unticked Link) is HELD under To match, as on another customer's phone or inbox: no commission
-- until an Owner or Manager checks them as a different person; earned once after; none if the same person.
--
--   G  The md5 and the grant: event_web_match_customer has 441's AFTER and is still the service role's
--      alone; 439's functions are unchanged.
--   H  Through a link, on the merged-away phone: held (the retired record the candidate, To match lists
--      the kept record, the note says where the phone was), no customer made; a VIP paid while held waits;
--      made a customer: waits for the check, shared with the kept record (audited), the VIP invoiced earns
--      nothing; checked as a different person: referred, the VIP earns once (a second decision changes
--      nothing); attached to the retired id: the kept record, already a customer; checked as the same
--      person: never referred, the VIP earns nothing.
--   E  The merged-away email inbox (a new phone): held (email_in_use), the note, the check; the phone and
--      the inbox: phone_and_email_in_use.
--   C  A chain A -> B -> C on A's phone: A the candidate, C listed.
--   K  The kept record (or anyone live) holds it itself: 436's hold, word for word; a live holder and a
--      merged-away one: both; the kept record has the inbox and not the phone: both reasons.
--   L  Never linked by it: the retired record's own name, or the kept record's, on its phone is held.
--   N  No link: held, no referral either way.
--   T  The test key says what the live key would do (held) and changes nothing.
--   D  A record deleted another way, or a chain that ends in one, holds nothing: a new customer, referred
--      at once (436).
--   A  The affiliate's own record merged into an older one: someone on its phone is held as on her live
--      phone and waits for the check when made a customer; she herself (that record's name) is herself.
--   O  An old 8-digit number on the merged-away record (as 425 reads it): held.
--   P  A registration follows only the merged-away records that match (event_web_kept_customer is not
--      called for the others).
--   M  441 twice changes nothing; its first run changes only event_web_match_customer; its self-test leaves
--      no row (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.com); phones are ACMA's fictional ranges (+61 2 5550 ....), except O's old number, which is
-- found at run time as 436's suite finds it (8 digits starting with 8 that no customer has in any form).
-- It installs 436 and 439 when they are missing, then 441 twice (run with -v skip_install=1 where 441 is
-- already installed). Every check runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
select to_regprocedure('public.event_web_call(text,uuid,text,jsonb)') is null as need_436 \gset
\if :need_436
\ir ../../../supabase/436_event_website_registrations_and_vip.sql
\endif
select to_regprocedure('public.event_web_kept_customer(uuid)') is null as need_439 \gset
\if :need_439
\ir ../../../supabase/439_event_website_follows_merges_and_login_self_check.sql
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
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language sql as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
\if :{?skip_install}
\else
create temp table b441 as select * from pg_temp.fn_md5s();
create temp table r441 as select pg_temp.row_counts() as before;
\ir ../../../supabase/441_event_website_holds_merged_records_phones.sql
create temp table m441 as select * from pg_temp.fn_md5s();
alter table r441 add column after1 jsonb;
update r441 set after1 = pg_temp.row_counts();
\ir ../../../supabase/441_event_website_holds_merged_records_phones.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
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
$$ select 'ht441-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
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

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; ev uuid; src uuid; pm uuid; v1 uuid; v2 uuid; c uuid; a uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 9000))::int::text);
  foreach k in array array['owner', 'acting', 'manager', 'staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'ht441-' || k || '-' || lower(sfx) || '@example.com');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'HT441 ' || initcap(k) || ' ' || sfx, 'ht441-' || k || '-' || lower(sfx) || '@example.com',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'manager' then 'manager' else 'staff' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('HT441 Van ' || sfx, 'HT441V' || sfx, 'SG') returning id into st;
  insert into fx values ('van', st);
  insert into user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st);
  ev := public.event_save(jsonb_build_object('name', 'HT441 Health Seminar ' || sfx,
    'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('HT441 Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src);
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('HT441 $72 discount Voucher', 'HT441SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT441 3-in-1 Vouchers', 'HT441-3IN1' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into fx values ('save72', v1), ('three', v2);
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true), (v2, st, 216, true);
  perform public.event_web_settings_save(ev, jsonb_build_object('code', 'HT441-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(v1, v2), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://healthtalk.example.com/api/app/sync'));
  insert into tx values ('code', 'HT441-' || sfx);
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

create function pg_temp.reg_test(tag text, first text, last text, phone text, email text, code text) returns uuid language sql as
$$ select pg_temp.reg1(tag, first, last, phone, email, code, 'test') $$;
create function pg_temp.make(tag text, why text) returns text language sql as
$$ select pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx(tag), why)) $$;
create function pg_temp.attach(tag text, cust text, why text) returns text language sql as
$$ select pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx(tag), pg_temp.fx(cust), why)) $$;
create function pg_temp.live_on(p_phone text) returns bigint language sql as
$$ select count(*) from customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = public.normalize_customer_phone(p_phone) $$;
create function pg_temp.held_note(what text, gone text, kept text, code text) returns text language sql as
$$ select format('Their %s was on %s''s record, since merged into %s''s (listed). If this is that customer, link that record: an '
          || 'existing customer is not referred through this link (%s). If it is someone else, make a new customer: they become Alma '
          || 'Testref''s referral once an Owner or Manager checks them as a different person (Affiliates page), and no commission comes '
          || 'before that.', what, gone, kept, code) $$;
create function pg_temp.waiting_note(what text, gone text, kept text, code text) returns text language sql as
$$ select format('Waiting for a check: their %s was on %s''s record, since merged into %s''s. They become Alma Testref''s referral '
          || '(link %s) once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
          what, gone, kept, code) $$;

-- ═════ G The md5 and the grant ═════
select pg_temp.check(md5(pg_get_functiondef('public.event_web_match_customer(text,text,text)'::regprocedure))
          in ('9da726006d8055983491b5ec1da1679b', '63bfaf4520406af9f67d3d81c3342baf')
    and (select p.proacl::text from pg_proc p where p.oid = 'public.event_web_match_customer(text,text,text)'::regprocedure)
        = '{postgres=X/postgres,service_role=X/postgres}'
    and not has_function_privilege('anon', 'public.event_web_match_customer(text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_match_customer(text,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.event_web_match_customer(text,text,text)', 'execute'),
  'G1 event_web_match_customer has 441''s AFTER md5 (or 469''s, built on it) and is still the service role''s alone (436''s grant)');
-- (444, where it is applied, added the unpaid checkout to event_web_guest_extras: 439's or 444's. 449, where it is
-- applied, the signed-up-again holds to event_web_guest_extras and event_web_register: 449's. 469, where it is
-- applied, the phone-and-email link to event_web_register.)
select pg_temp.check((select bool_and(md5(pg_get_functiondef(x.f::regprocedure)) = any (string_to_array(x.m, ' ')))
                        from (values ('public.event_web_kept_customer(uuid)', 'cb0720c1088df9209da45e46b91601f4'),
                                     ('public.event_web_new_customer(uuid)', 'a253f76a9db721212a9c110bc41ff483'),
                                     ('public.event_web_referral_note(uuid)', 'd68893db63938cc774b157708bd341f1'),
                                     ('public.event_web_guest_extras(uuid)', '18b56a28bb4965b2188cd73dde056209 369914bd689e9aa1d34e8e2d887b1d43 03358fda2da1b4fda082e3f29b512a38'),
                                     ('public.event_registration_attach(uuid,uuid,text)', 'b31be4d82d20000df026e7cfa9b24095'),
                                     ('public.event_web_register(uuid,jsonb)', 'e3efd309e81d17c97f7984f7ecbaafff 3aad1ad2a8a91732d330b2ef149bf969 c188a2dc82b9eb08fc9d01f1e5c15e13'),
                                     ('public.event_web_phone_holders(text)', '614602e9cbc483d79bdef7d60aaf6a33')) x(f, m)),
  'G2 439''s functions and 436''s register and phone holders are as they were (441 changes none of them)');

-- ═════ Fixtures: merged before anyone registers ═════
do $$ begin
  -- H/E: Hana's old record (phone 1, an inbox) merged into Hana Kept (phone 2, no email): neither taken.
  insert into fx values ('hana', pg_temp.cust('Hana Gonerec', pg_temp.ph(1), pg_temp.mail('hana'))),
                        ('hana_k', pg_temp.cust('Hana Keptrec', pg_temp.ph(2), null));
  -- C: a chain on A's phone.
  insert into fx values ('ca', pg_temp.cust('Cal Chainone', pg_temp.ph(10), null)), ('cb', pg_temp.cust('Cal Chaintwo', pg_temp.ph(11), null)),
                        ('cc', pg_temp.cust('Cal Chainthree', pg_temp.ph(12), null));
  -- K: the kept record took the phone; a live holder beside a merged-away one; the kept record has the inbox only.
  insert into fx values ('kim', pg_temp.cust('Kim Dupone', pg_temp.ph(20), null)), ('kim_k', pg_temp.cust('Kim Keepone', pg_temp.ph(20), null)),
                        ('liv', pg_temp.cust('Liv Liveholder', pg_temp.ph(21), null)), ('ret', pg_temp.cust('Ret Goneholder', pg_temp.ph(21), null)),
                        ('ret_k', pg_temp.cust('Ret Keptholder', pg_temp.ph(22), null)),
                        ('mo', pg_temp.cust('Mo Gonemail', pg_temp.ph(23), pg_temp.mail('mo'))),
                        ('mo_k', pg_temp.cust('Mo Keptmail', pg_temp.ph(24), pg_temp.mail('mo')));
  -- D: deleted another way; a chain whose end was deleted another way.
  insert into fx values ('dee', pg_temp.cust('Dee Deletedrec', pg_temp.ph(30), null)),
                        ('fin', pg_temp.cust('Fin Gonerec', pg_temp.ph(31), null)), ('fin_k', pg_temp.cust('Fin Keptrec', pg_temp.ph(32), null));
end $$;
-- A: the affiliate Gia signed up on a fresh record (phone 40), linked to her older record (phone 41) without its phone.
do $$ declare g uuid; gk uuid; gu uuid; begin
  g := pg_temp.cust('Gia Freshrec', pg_temp.ph(40), pg_temp.mail('gia'));
  insert into customer_affiliates(customer_id, status, referral_code) values (g, 'active', 'HG' || pg_temp.tx('sfx'));
  gk := pg_temp.cust('Gia Testold', pg_temp.ph(41), null);
  gu := pg_temp.cust('Gia Upline', pg_temp.ph(42), null);
  update customers set referred_by = gu where id = gk;
  insert into fx values ('gia', g), ('gia_k', gk), ('gia_up', gu);
  insert into tx values ('code_gia', 'HG' || pg_temp.tx('sfx'));
end $$;
-- O: an old 8-digit number on the merged-away record. 425 reads an 8-digit number starting with 8 as Singapore
-- or Malaysia; one no customer has in any form is found at run time, so no real-format number is written here.
insert into tx values ('legacy8', (select s.d from (select '8' || lpad(floor(random() * 1e7)::int::text, 7, '0') as d
                                                      from generate_series(1, 500)) s
                                    where public.normalize_customer_phone(s.d) is null
                                      and (public.inspect_customer_phone(s.d)->'candidates') ? ('+65' || s.d)
                                      and not exists (select 1 from customers c
                                                       where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')
                                                             in (s.d, '65' || s.d, '60' || s.d))
                                    limit 1));
-- A legacy record, as old data has it: added with the triggers off (its phone is not normalized).
set local session_replication_role = replica;
with c as (insert into customers(full_name, phone) values ('Ola Oldnumber', pg_temp.tx('legacy8')) returning id)
insert into fx select 'ola', c.id from c;
set local session_replication_role = origin;
do $$ begin insert into fx values ('ola_k', pg_temp.cust('Ola Keptrec', pg_temp.ph(50), null)); end $$;
select pg_temp.as_user('owner');
select pg_temp.put('merges', concat_ws(',', pg_temp.merge('hana_k', 'hana'), pg_temp.merge('cb', 'ca'), pg_temp.merge('cc', 'cb'),
  pg_temp.merge('kim_k', 'kim'), pg_temp.merge('ret_k', 'ret'), pg_temp.merge('mo_k', 'mo'), pg_temp.merge('fin_k', 'fin'),
  pg_temp.merge('gia_k', 'gia'), pg_temp.merge('ola_k', 'ola')));
select pg_temp.as_service();
update customers set deleted_at = now() where id in (pg_temp.fx('dee'), pg_temp.fx('fin_k'));
select pg_temp.check(pg_temp.tx('merges') = 'ok,ok,ok,ok,ok,ok,ok,ok,ok'
    and public.event_web_kept_customer(pg_temp.fx('hana')) = pg_temp.fx('hana_k')
    and public.event_web_kept_customer(pg_temp.fx('ca')) = pg_temp.fx('cc')
    and public.event_web_kept_customer(pg_temp.fx('fin')) is null and public.event_web_kept_customer(pg_temp.fx('dee')) is null
    and (select customer_id from customer_affiliates where referral_code = pg_temp.tx('code_gia')) = pg_temp.fx('gia_k')
    and pg_temp.live_on(pg_temp.ph(1)) = 0 and (select phone from customers where id = pg_temp.fx('hana')) = pg_temp.ph(1),
  'F the merges: the retired records keep their phones and emails, the kept records do not have them (Gia''s link now names Gia Testold): '
  || pg_temp.tx('merges'));

-- ═════ H, E, L, N, T Registered on the merged-away phone or inbox (everyone registers before staff act:
-- each person made a customer has the phone or inbox too, and To match and the notes read who has it now) ═════
select pg_temp.reg1('h1', 'Ian', 'Other', pg_temp.ph(1), pg_temp.mail('ian'), pg_temp.tx('code_alma'));
select pg_temp.reg1('h7', 'Jo', 'Other', pg_temp.ph(1), pg_temp.mail('jo'), pg_temp.tx('code_alma'));
select pg_temp.reg1('h8', 'Kai', 'Other', pg_temp.ph(1), pg_temp.mail('kai'), pg_temp.tx('code_alma'));
select pg_temp.reg1('e1', 'Lia', 'Mail', pg_temp.ph(3), pg_temp.mail('hana'), pg_temp.tx('code_alma'));
select pg_temp.reg1('e3', 'Mia', 'Both', pg_temp.ph(1), pg_temp.mail('hana'), pg_temp.tx('code_alma'));
select pg_temp.reg1('l1', 'Hana', 'Gonerec', pg_temp.ph(1), pg_temp.mail('hana-l1'), null);
select pg_temp.reg1('l2', 'Hana', 'Keptrec', pg_temp.ph(1), pg_temp.mail('hana-l2'), null);
select pg_temp.reg1('n1', 'Rae', 'Other', pg_temp.ph(1), pg_temp.mail('rae'), null);
select pg_temp.reg_test('t1', 'Sam', 'Tester', pg_temp.ph(1), pg_temp.mail('sam'), pg_temp.tx('code_alma'));
select pg_temp.put('h1_paid', pg_temp.paid('h1v', 'h1')::text);
select pg_temp.put('h8_paid', pg_temp.paid('h8v', 'h8')::text);
-- H Through a link, on the merged-away phone; E its inbox; L names; N no link; T the test key.
select pg_temp.check((pg_temp.pp('h1')).match = 'held' and (pg_temp.pp('h1')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('h1')).candidate_customer_ids = array[pg_temp.fx('hana')] and (pg_temp.pp('h1')).referral_outcome = 'held'
    and (pg_temp.pp('h1')).customer_id is null and pg_temp.live_on(pg_temp.ph(1)) = 0
    and (select g.status from event_guests g where g.id = (pg_temp.pp('h1')).free_guest_id) = 'registered'
    and not exists (select 1 from referral_signup_events e where e.normalized_phone = pg_temp.ph(1)),
  'H1 on a phone only Hana''s merged-away record has, through Alma''s link: held (phone_in_use) for that record, no customer made, not referred, still a guest');
select pg_temp.check(pg_temp.cands('h1') = array[pg_temp.fx('hana_k')]
    and (select (c->'merged_from'->0->>'customer_id')::uuid = pg_temp.fx('hana') and (c->'merged_from'->0->>'phone_matches')::boolean
                and not (c->'merged_from'->0->>'email_matches')::boolean and not (c->>'phone_matches')::boolean
           from jsonb_array_elements(pg_temp.hold('h1')->'candidates') c),
  'H2 To match lists the kept record, Hana''s record under merged_from (its phone matched): ' || coalesce((pg_temp.hold('h1')->'candidates')::text, 'none'));
select pg_temp.check(pg_temp.note('h1') = pg_temp.held_note('phone', 'Hana Gonerec', 'Hana Keptrec', pg_temp.tx('code_alma'))
    and pg_temp.hold('h1')->>'referral_note' = pg_temp.note('h1'),
  'H3 the note says where the phone was and what each choice does: ' || coalesce(pg_temp.note('h1'), 'no note'));
select pg_temp.check((pg_temp.vorder('h1v')).status = 'needs_review' and (pg_temp.vorder('h1v')).waiting_for_match
    and pg_temp.vinv('h1v') is null,
  'H4 a VIP paid while held waits for the match (no invoice yet)');
select pg_temp.check((pg_temp.pp('e1')).match = 'held' and (pg_temp.pp('e1')).hold_reason = 'email_in_use'
    and (pg_temp.pp('e1')).candidate_customer_ids = array[pg_temp.fx('hana')] and (pg_temp.pp('e1')).referral_outcome = 'held'
    and pg_temp.cands('e1') = array[pg_temp.fx('hana_k')]
    and (select (c->'merged_from'->0->>'email_matches')::boolean and not (c->'merged_from'->0->>'phone_matches')::boolean
           from jsonb_array_elements(pg_temp.hold('e1')->'candidates') c)
    and pg_temp.note('e1') = pg_temp.held_note('email inbox', 'Hana Gonerec', 'Hana Keptrec', pg_temp.tx('code_alma')),
  'E1 a new phone with the inbox only Hana''s merged-away record has: held (email_in_use) for it, the note says so: ' || coalesce(pg_temp.note('e1'), 'no note'));
select pg_temp.check((pg_temp.pp('e3')).hold_reason = 'phone_and_email_in_use' and (pg_temp.pp('e3')).candidate_customer_ids = array[pg_temp.fx('hana')]
    and pg_temp.cands('e3') = array[pg_temp.fx('hana_k')]
    and pg_temp.note('e3') = pg_temp.held_note('phone', 'Hana Gonerec', 'Hana Keptrec', pg_temp.tx('code_alma')),
  'E3 her phone and inbox both only on the merged-away record: held (phone_and_email_in_use), listed once');
select pg_temp.check((select bool_and((pg_temp.pp(t)).match = 'held' and (pg_temp.pp(t)).hold_reason = 'phone_in_use'
                                      and (pg_temp.pp(t)).customer_id is null
                                      and (pg_temp.pp(t)).candidate_customer_ids = array[pg_temp.fx('hana')])
                        from unnest(array['l1', 'l2']) t),
  'L1 the merged-away record''s own name, or the kept record''s, on its phone: held for staff, not linked');
select pg_temp.check((pg_temp.pp('n1')).match = 'held' and (pg_temp.pp('n1')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('n1')).referral_outcome is null and pg_temp.note('n1') is null,
  'N1 no link: held the same way, no referral note');
select pg_temp.check((pg_temp.pp('t1')).match = 'test' and (pg_temp.pp('t1')).customer_id is null
    and (pg_temp.pp('t1')).test_outcome = jsonb_build_object('match', 'held', 'hold_reason', 'phone_in_use', 'referral', 'held')
    and pg_temp.live_on(pg_temp.ph(1)) = 0
    and pg_temp.note('t1') like 'Their phone is on another customer''s record. If this is that customer, link their record:%',
  'T1 the test key says what the live key would do (held, not referred) and makes nobody; its note is 436''s (439 leaves test rows): ' || coalesce((pg_temp.pp('t1')).test_outcome::text, 'none'));
-- ═════ H Staff act on them ═════
select pg_temp.as_user('staff');
select pg_temp.put('h5_make', pg_temp.make('h1', 'Not Hana'));
select pg_temp.putx('ian', (pg_temp.pp('h1')).customer_id);
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('h5_make') = 'ok' and (pg_temp.pp('h1')).match = 'staff_created' and (pg_temp.pp('h1')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = pg_temp.fx('ian')) is null
    and (pg_temp.check_of(pg_temp.fx('ian'))).status = 'pending'
    and (pg_temp.check_of(pg_temp.fx('ian'))).referrer_customer_id = pg_temp.fx('alma')
    and (pg_temp.check_of(pg_temp.fx('ian'))).phone_shared_with = array[pg_temp.fx('hana_k')]
    and exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('ian') and l.action = 'referral_check_waiting'
                  and l.new_data->'merged_holders' = jsonb_build_array(pg_temp.fx('hana_k'))
                  and l.reason like 'Their phone was on a customer''s record since merged into another:%')
    and (pg_temp.vorder('h1v')).status = 'invoiced' and (pg_temp.vinv('h1v')).customer_id = pg_temp.fx('ian')
    and pg_temp.comm((pg_temp.vinv('h1v')).id) = '[]'::jsonb
    and pg_temp.note('h1') = pg_temp.waiting_note('phone', 'Hana Gonerec', 'Hana Keptrec', pg_temp.tx('code_alma')),
  'H5 made a customer: not referred yet, a check shared with the kept record (audited); the VIP is invoiced and earns nothing yet: '
  || pg_temp.tx('h5_make') || ' ' || coalesce(pg_temp.note('h1'), ''));
select pg_temp.as_user('owner');
select pg_temp.put('h6_check', public.decide_referral_signup_check((pg_temp.check_of(pg_temp.fx('ian'))).id, 'different_person', 'A different person')::text);
select pg_temp.put('h6_again', public.decide_referral_signup_check((pg_temp.check_of(pg_temp.fx('ian'))).id, 'same_person', 'Again')::text);
select pg_temp.as_service();
select pg_temp.check((pg_temp.tx('h6_check')::jsonb)->>'ok' = 'true' and (pg_temp.tx('h6_again')::jsonb)->>'already' = 'true'
    and (select referred_by from customers where id = pg_temp.fx('ian')) = pg_temp.fx('alma')
    and (pg_temp.pp('h1')).referral_outcome = 'check_confirmed'
    and pg_temp.comm((pg_temp.vinv('h1v')).id) = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('alma')), jsonb_build_array('tier2', pg_temp.fx('alma_up')))
    and (select count(*) from commissions c where c.invoice_id = (pg_temp.vinv('h1v')).id) = 2
    and (select bool_and(c.invoice_paid_date = public.sg_today()) from commissions c where c.invoice_id = (pg_temp.vinv('h1v')).id),
  'H6 checked as a different person: Alma''s referral, the VIP earns Alma and her upline once (dated the check''s day); a second decision changes nothing: '
  || pg_temp.comm((pg_temp.vinv('h1v')).id)::text);
select pg_temp.as_user('staff');
select pg_temp.put('h7_att', pg_temp.attach('h7', 'hana', 'Hana herself, a new email'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('h7_att') = 'ok' and (pg_temp.pp('h7')).match = 'staff_attached'
    and (pg_temp.pp('h7')).customer_id = pg_temp.fx('hana_k') and (pg_temp.pp('h7')).referral_outcome = 'already_customer'
    and (select referred_by from customers where id = pg_temp.fx('hana_k')) is null
    and pg_temp.check_of(pg_temp.fx('hana_k')) is null
    and exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('h7') and l.action = 'event_registration_matched'
                  and (l.new_data->>'merged_into')::uuid = pg_temp.fx('hana_k') and (l.new_data->>'suggested_customer')::boolean),
  'H7 attached to the retired id: the kept record, already a customer (not referred, no check): ' || coalesce(pg_temp.tx('h7_att'), 'none'));
select pg_temp.as_user('staff');
select pg_temp.put('h8_make', pg_temp.make('h8', 'Made one'));
select pg_temp.putx('kai', (pg_temp.pp('h8')).customer_id);
select pg_temp.as_user('manager');
select pg_temp.put('h8_check', public.decide_referral_signup_check((pg_temp.check_of(pg_temp.fx('kai'))).id, 'same_person', 'Hana''s son, the same household')::text);
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('h8_make') = 'ok' and (pg_temp.tx('h8_check')::jsonb)->>'ok' = 'true'
    and (pg_temp.pp('h8')).referral_outcome = 'check_same_person'
    and (select referred_by from customers where id = pg_temp.fx('kai')) is null
    and pg_temp.comm((pg_temp.vinv('h8v')).id) = '[]'::jsonb
    and not exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('kai') and a.action = 'referral_registered'),
  'H8 checked as the same person (a Manager): never referred, the VIP earns nothing: ' || coalesce(pg_temp.tx('h8_check'), 'none'));
-- ═════ E Made a customer on the merged-away inbox ═════
select pg_temp.as_user('staff');
select pg_temp.put('e2_make', pg_temp.make('e1', 'Not Hana'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('e2_make') = 'ok' and (pg_temp.pp('e1')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = (pg_temp.pp('e1')).customer_id) is null
    and (pg_temp.check_of((pg_temp.pp('e1')).customer_id)).phone_shared_with = array[pg_temp.fx('hana_k')]
    and exists (select 1 from audit_logs l where l.record_id = (pg_temp.pp('e1')).customer_id and l.action = 'referral_check_waiting'
                  and l.reason like 'Their email inbox was on a customer''s record since merged into another:%')
    and pg_temp.note('e1') = pg_temp.waiting_note('email inbox', 'Hana Gonerec', 'Hana Keptrec', pg_temp.tx('code_alma')),
  'E2 made a customer: waits for the check (R6-1), shared with the kept record: ' || coalesce(pg_temp.note('e1'), pg_temp.tx('e2_make')));
-- ═════ N Made a customer without a link ═════
select pg_temp.as_user('staff');
select pg_temp.put('n2_make', pg_temp.make('n1', 'Someone else'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('n2_make') = 'ok' and (pg_temp.pp('n1')).referral_outcome is null
    and (select referred_by from customers where id = (pg_temp.pp('n1')).customer_id) is null
    and pg_temp.check_of((pg_temp.pp('n1')).customer_id) is null,
  'N2 made a customer: no referral, no check (no link)');

-- ═════ C A chain ═════
select pg_temp.reg1('c1', 'Nat', 'Other', pg_temp.ph(10), pg_temp.mail('nat'), pg_temp.tx('code_alma'));
select pg_temp.check((pg_temp.pp('c1')).hold_reason = 'phone_in_use' and (pg_temp.pp('c1')).candidate_customer_ids = array[pg_temp.fx('ca')]
    and pg_temp.cands('c1') = array[pg_temp.fx('cc')]
    and pg_temp.note('c1') = pg_temp.held_note('phone', 'Cal Chainone', 'Cal Chainthree', pg_temp.tx('code_alma')),
  'C1 A merged into B, then B into C, on A''s phone: A the candidate, C listed and named: ' || coalesce(pg_temp.note('c1'), 'no note'));

-- ═════ K The kept record (or anyone live) holds it itself ═════
select pg_temp.reg1('k1', 'Oli', 'Other', pg_temp.ph(20), pg_temp.mail('oli'), pg_temp.tx('code_alma'));
select pg_temp.reg1('k2', 'Pia', 'Other', pg_temp.ph(21), pg_temp.mail('pia'), pg_temp.tx('code_alma'));
select pg_temp.reg1('k3', 'Quy', 'Other', pg_temp.ph(23), pg_temp.mail('mo'), pg_temp.tx('code_alma'));
select pg_temp.check((pg_temp.pp('k1')).hold_reason = 'phone_in_use' and (pg_temp.pp('k1')).candidate_customer_ids = array[pg_temp.fx('kim_k')]
    and pg_temp.note('k1') like 'Their phone is on another customer''s record. If this is that customer, link their record:%',
  'K1 the kept record took the phone: 436''s hold, word for word (only the kept record, 436''s note)');
select pg_temp.check((pg_temp.pp('k2')).hold_reason = 'phone_in_use'
    and (select array_agg(x order by x) from unnest((pg_temp.pp('k2')).candidate_customer_ids) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('liv'), pg_temp.fx('ret')]) x)
    and (select array_agg(x order by x) from unnest(pg_temp.cands('k2')) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('liv'), pg_temp.fx('ret_k')]) x)
    and pg_temp.note('k2') like 'Their phone is on another customer''s record.%',
  'K2 a live customer and a merged-away record have the phone: both candidates (the kept record listed), 436''s note');
select pg_temp.check((pg_temp.pp('k3')).hold_reason = 'phone_and_email_in_use'
    and (select array_agg(x order by x) from unnest((pg_temp.pp('k3')).candidate_customer_ids) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('mo'), pg_temp.fx('mo_k')]) x)
    and pg_temp.cands('k3') = array[pg_temp.fx('mo_k')],
  'K3 the kept record has the inbox, not the phone: held for both (the inbox live, the phone merged-away), the kept record listed once');

-- ═════ D Deleted another way ═════
select pg_temp.reg1('d1', 'Tia', 'Other', pg_temp.ph(30), pg_temp.mail('tia'), pg_temp.tx('code_alma'));
select pg_temp.reg1('d2', 'Uli', 'Other', pg_temp.ph(31), pg_temp.mail('uli'), pg_temp.tx('code_alma'));
select pg_temp.check((select bool_and((pg_temp.pp(t)).match = 'new_customer' and (pg_temp.pp(t)).referral_outcome = 'created'
                                      and (select referred_by from customers where id = (pg_temp.pp(t)).customer_id) = pg_temp.fx('alma'))
                        from unnest(array['d1', 'd2']) t),
  'D1 a record deleted another way, or merged into one deleted another way, holds nothing: a new customer, referred at once (436)');

-- ═════ A The affiliate's own record merged into an older one ═════
select pg_temp.reg1('a1', 'Vin', 'Kin', pg_temp.ph(40), pg_temp.mail('vin'), pg_temp.tx('code_gia'));
select pg_temp.reg1('a2', 'Gia', 'Freshrec', pg_temp.ph(40), pg_temp.mail('gia-a2'), pg_temp.tx('code_gia'));
select pg_temp.check((pg_temp.pp('a1')).match = 'held' and (pg_temp.pp('a1')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('a1')).candidate_customer_ids = array[pg_temp.fx('gia')] and (pg_temp.pp('a1')).referral_outcome = 'held'
    and pg_temp.cands('a1') = array[pg_temp.fx('gia_k')]
    and pg_temp.note('a1') like format('Shares the phone of Gia Testold, the affiliate whose link (%s) was used.%%', pg_temp.tx('code_gia')),
  'A1 someone on the phone of the affiliate''s merged-away record: held as on her live phone (her record listed, the note): ' || coalesce(pg_temp.note('a1'), 'no note'));
select pg_temp.as_user('staff');
select pg_temp.put('a1_make', pg_temp.make('a1', 'Her nephew'));
select pg_temp.put('a2_att', pg_temp.attach('a2', 'gia', 'Gia herself'));
select pg_temp.as_service();
select pg_temp.check(pg_temp.tx('a1_make') = 'ok' and (pg_temp.pp('a1')).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = (pg_temp.pp('a1')).customer_id) is null
    and (pg_temp.check_of((pg_temp.pp('a1')).customer_id)).referrer_customer_id = pg_temp.fx('gia_k')
    and pg_temp.fx('gia_k') = any ((pg_temp.check_of((pg_temp.pp('a1')).customer_id)).phone_shared_with),
  'A2 made a customer: waits for the check (her phone, the A rule), no referrer: ' || coalesce(pg_temp.tx('a1_make'), 'none'));
select pg_temp.check((pg_temp.pp('a2')).hold_reason = 'phone_in_use' and pg_temp.tx('a2_att') = 'ok'
    and (pg_temp.pp('a2')).customer_id = pg_temp.fx('gia_k') and (pg_temp.pp('a2')).referral_outcome = 'self',
  'A3 she herself (her merged-away record''s name, on its phone): held, then attached to the retired id: her kept record, herself: ' || coalesce(pg_temp.tx('a2_att'), 'none'));

-- ═════ O An old number on the merged-away record ═════
select pg_temp.reg1('o1', 'Wes', 'Other', '+65 ' || substr(pg_temp.tx('legacy8'), 1, 4) || ' ' || substr(pg_temp.tx('legacy8'), 5),
                    pg_temp.mail('wes'), pg_temp.tx('code_alma'));
select pg_temp.check(pg_temp.tx('legacy8') is not null and (pg_temp.pp('o1')).hold_reason = 'phone_in_use'
    and (pg_temp.pp('o1')).candidate_customer_ids = array[pg_temp.fx('ola')] and pg_temp.cands('o1') = array[pg_temp.fx('ola_k')],
  'O1 an old 8-digit number on the merged-away record that reads as this phone (as 425 reads it): held for it');

-- ═════ P Only the matching merged-away records are followed ═════
set local track_functions = 'all';
create function pg_temp.kept_calls() returns bigint language sql as
$$ select coalesce((select s.calls from pg_stat_xact_user_functions s where s.funcid = 'public.event_web_kept_customer(uuid)'::regprocedure), 0) $$;
select pg_temp.put('p0', pg_temp.kept_calls()::text);
select pg_temp.put('p_new', public.event_web_match_customer(pg_temp.ph(95), 'Nobody Newcomer', pg_temp.mail('nobody'))::text);
select pg_temp.put('p1', pg_temp.kept_calls()::text);
select pg_temp.put('p_old', public.event_web_match_customer(pg_temp.ph(1), 'Somebody Else', pg_temp.mail('somebody'))::text);
select pg_temp.put('p2', pg_temp.kept_calls()::text);
select pg_temp.check(pg_temp.tx('p_new')::jsonb = '{"kind": "new"}'::jsonb and pg_temp.tx('p1') = pg_temp.tx('p0')
    and (pg_temp.tx('p_old')::jsonb)->>'kind' = 'held' and pg_temp.tx('p2')::bigint = pg_temp.tx('p1')::bigint + 1
    and (select count(*) from customers where deleted_at is not null) >= 11,
  format('P1 with %s retired records, a new phone follows none of them, and Hana''s phone follows hers alone (%s, %s, %s calls)',
         (select count(*) from customers where deleted_at is not null), pg_temp.tx('p0'), pg_temp.tx('p1'), pg_temp.tx('p2')));
set local track_functions = 'none';

-- ═════ M 441 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m441 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m441),
  'M1 running 441 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m441 m left join b441 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5) <@ array['event_web_match_customer(text,text,text)']
    and (select count(*) from m441) = (select count(*) from b441),
  'M2 its first run changed event_web_match_customer alone (no function added or dropped)');
select pg_temp.check((select before = after1 from r441),
  'M3 441''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 441 checks passed.';
end $$;
rollback;
