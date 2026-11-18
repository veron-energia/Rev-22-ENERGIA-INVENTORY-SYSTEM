-- A person's VIP link is read one at a time, and each read is in the Audit Log; the website's
-- key is checked before its message is read (526; security audit of 17 Nov 2026, L11; the
-- user, 18 Nov 2026).
--
--   G  Grants and md5s: event_web_key_check is the service role's only; event_web_vip_link
--      signed-in staff's (and the service role's), never anon's; event_web_guest_extras keeps
--      its grants and has 526's AFTER md5; the two page functions check the caller first.
--   K  event_web_key_check: a live key and a test key: ok; a revoked key, an unknown hash, no
--      hash, a key whose event has no website settings, a key of a deleted event (left
--      unrevoked): bad_key, as event_web_call answers each of them; it writes nothing (not
--      last_used_at).
--   L  The guest list (event_web_guest_extras) carries no token anywhere, and
--      vip_link_ready: true for a registered person not VIP; false for one closed, for a paid
--      VIP (both their records); 'upgrade_token' is still in every row, null.
--   V  event_web_vip_link: for a person who may have the link, their own token, and exactly one
--      Audit Log row per fetch (who, the person, the event and their guest records; never the
--      token); for a closed person, a paid VIP, a person of another event, an unknown person:
--      not_available and no row. A login that is not active staff, and staff who cannot run
--      the event, are refused (42501) and nothing is written.
--   U  scripts/event-website/undo-526.sql puts event_web_guest_extras back (449's md5) and drops
--      the two functions; 526 again makes them as before (all rolled back).
--   M  526 twice changes nothing (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.com); phones are the fictional +61 491 570 ... range. Run it on a copy of
-- production as it is (after 525): it applies 526 twice, or run it with -v skip_install=1 where
-- 526 is already installed. Every check runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
\if :{?skip_install}
\else
\ir ../../../supabase/526_a_vip_link_is_read_one_at_a_time.sql
create temp table m526 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
\ir ../../../supabase/526_a_vip_link_is_read_one_at_a_time.sql
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
$$begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- Fictional phones: +61 491 570 nnn, one block per run.
create function pg_temp.ph(n int) returns text language sql as
$$ select '+61491570' || lpad(((pg_temp.tx('phbase')::int + n) % 1000)::text, 3, '0') $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'vl526-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
create function pg_temp.bid(prefix text, tag text) returns text language sql as
$$ select prefix || '-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || prefix || tag), 1, 8)) $$;
create function pg_temp.person(pos int, first text, last text, phone text, email text) returns jsonb language sql as
$$ select jsonb_build_object('position', pos, 'first_name', first, 'last_name', last, 'phone', phone, 'email', email,
            'days', to_jsonb(array[pg_temp.d(7)]), 'vip', false) $$;
-- One website message with a key (by its hash), as the event-website function sends it.
create function pg_temp.call(key text, typ text, body jsonb, code_key text default 'code') returns jsonb
language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_service();
  v := public.event_web_call(pg_temp.tx('hash:' || key), case when typ in ('event_info','referral_info','person','sync') then null else gen_random_uuid() end,
                             typ, jsonb_build_object('type', typ, 'event', pg_temp.tx(code_key)) || body);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
create function pg_temp.key_check(hash text) returns jsonb language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_service();
  v := public.event_web_key_check(hash);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
-- One sign-up form of one person; their id and token kept under <tag>.
create function pg_temp.reg(tag text, p jsonb, key text default 'live', code_key text default 'code') returns jsonb language plpgsql as $$
declare v jsonb;
begin
  v := pg_temp.call(key, 'register', jsonb_build_object('registration', jsonb_build_object(
         'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(p))),
       code_key);
  if v->'people'->0->>'person_id' is not null then
    perform pg_temp.putx(tag, (v->'people'->0->>'person_id')::uuid);
    perform pg_temp.put('tok:' || tag, v->'people'->0->>'upgrade_token');
  end if;
  return v;
end $$;
create function pg_temp.checkout(tag text, person text) returns jsonb language sql as
$$ select pg_temp.call('live', 'vip_checkout', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', jsonb_build_array(pg_temp.tx('tok:' || person)),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null),
     'livemode', true, 'checkout_opened_at', now() - interval '3 minutes'))) $$;
create function pg_temp.paid(tag text, person text) returns jsonb language sql as
$$ select pg_temp.call('live', 'vip_paid', jsonb_build_object('payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'provider', 'hitpay',
     'payment_request_id', md5('rq' || tag || pg_temp.tx('sfx'))::uuid, 'payment_id', md5('py' || tag || pg_temp.tx('sfx'))::uuid,
     'amount_cents', 7200, 'currency', 'SGD', 'livemode', true, 'paid_at', now() - interval '1 minute',
     'upgrade_tokens', jsonb_build_array(pg_temp.tx('tok:' || person)),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null)))) $$;
create function pg_temp.pp(tag text) returns public.event_registration_people language sql as
$$ select * from public.event_registration_people where id = pg_temp.fx(tag) $$;
-- What the Event page reads, as the Owner.
create function pg_temp.extras(ev text default 'ev') returns jsonb language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_user('owner');
  v := public.event_web_guest_extras(pg_temp.fx(ev));
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
-- A person's rows in the guest list (their free record and, for a VIP, their VIP record).
create function pg_temp.rows_of(tag text) returns setof jsonb language sql as
$$ select g from jsonb_array_elements(pg_temp.extras()->'guests') g where (g->>'person_id')::uuid = pg_temp.fx(tag) $$;
create function pg_temp.link_audits(tag text) returns bigint language sql as
$$ select count(*) from public.audit_logs l where l.action = 'event_web_vip_link_copied' and l.record_id = pg_temp.fx(tag) $$;
create function pg_temp.all_link_audits() returns bigint language sql as
$$ select count(*) from public.audit_logs l where l.action = 'event_web_vip_link_copied' $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st_out uuid; ev uuid; ev2 uuid; ev_bare uuid; src uuid; pm uuid; v1 uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 800))::int::text);
  foreach k in array array['owner', 'acting', 'manager', 'staff', 'outsider', 'inactive', 'nobody'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'vl526-' || k || '-' || lower(sfx) || '@example.com');
    if k <> 'nobody' then
      insert into profiles(id, full_name, email, role, is_active)
      values (u, 'VL526 ' || initcap(k) || ' ' || sfx, 'vl526-' || k || '-' || lower(sfx) || '@example.com',
              case k when 'owner' then 'owner' when 'acting' then 'owner' when 'staff' then 'staff' when 'inactive' then 'staff'
                     else 'manager' end::user_role, k <> 'inactive');
    end if;
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('VL526 Van ' || sfx, 'VL526V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('VL526 Other ' || sfx, 'VL526O' || sfx, 'SG') returning id into st_out;
  insert into fx values ('van', st), ('other', st_out);
  insert into user_store_assignments(user_id, store_id)
  values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('inactive'), st), (pg_temp.fx('outsider'), st_out);
  ev := public.event_save(jsonb_build_object('name', 'VL526 Health Seminar ' || sfx, 'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  ev2 := public.event_save(jsonb_build_object('name', 'VL526 Second Seminar ' || sfx, 'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7))), 'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 1, 'price', 72))));
  ev_bare := public.event_save(jsonb_build_object('name', 'VL526 No Website ' || sfx, 'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7))), 'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 10))));
  insert into fx values ('ev', ev), ('ev2', ev2), ('ev_bare', ev_bare),
    ('vip', (select id from public.event_ticket_options where event_id = ev)),
    ('vip2', (select id from public.event_ticket_options where event_id = ev2));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('VL526 Event ' || sfx, true, true, 9999) returning id into src;
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('VL526 $72 discount Voucher', 'VL526SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true);
  perform public.event_web_settings_save(ev, jsonb_build_object('code', 'VL526-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(v1), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://seminar.example.com/api/app/sync'));
  perform public.event_web_settings_save(ev2, jsonb_build_object('code', 'VL526B-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip2'),
     'vip_voucher_ids', jsonb_build_array(v1), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Second Seminar (website)', 'sync_url', 'https://second.example.com/api/app/sync'));
  insert into tx values ('code', 'VL526-' || sfx), ('code2', 'VL526B-' || sfx);
  -- Someone whose phone the held person below shares.
  insert into customers(full_name, phone, email) values ('Hilda Holder', pg_temp.ph(1), null) returning id into u;
  insert into fx values ('holder', u);
end $$;
do $$ declare r jsonb; begin
  perform pg_temp.as_user('owner');
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'Website production');
  insert into tx values ('hash:live', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  r := public.event_web_key_create(pg_temp.fx('ev'), 'test', 'Website preview');
  insert into tx values ('hash:test', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'Revoked one');
  insert into tx values ('hash:revoked', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  perform public.event_web_key_revoke((r->>'key_id')::uuid, 'No longer used');
  r := public.event_web_key_create(pg_temp.fx('ev2'), 'live', 'Second website');
  insert into tx values ('hash:ev2', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  -- A key of an event with no website settings (only a hand-made row can be one).
  insert into tx values ('hash:bare', encode(extensions.digest('evk_live_' || md5(random()::text), 'sha256'), 'hex'));
  insert into public.event_web_keys(event_id, kind, key_hash, key_hint, label, created_by)
  values (pg_temp.fx('ev_bare'), 'live', pg_temp.tx('hash:bare'), 'evk_live_VL52…bare', 'No settings', pg_temp.fx('owner'));
  -- A made-up hash no key has.
  insert into tx values ('hash:unknown', encode(extensions.digest('evk_live_unknown_' || md5(random()::text), 'sha256'), 'hex'));
end $$;
select pg_temp.check((pg_temp.call('live', 'event_info', '{}')->>'ok')::boolean, 'F the fixture event answers event_info');

-- ═════ G Grants and md5s ═════
select pg_temp.check(has_function_privilege('service_role', 'public.event_web_key_check(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_key_check(text)', 'execute')
    and not has_function_privilege('anon', 'public.event_web_key_check(text)', 'execute')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = 'public.event_web_key_check(text)'::regprocedure and a.grantee = 0),
  'G1 event_web_key_check: the service role only (not signed-in staff, anon or PUBLIC)');
select pg_temp.check(has_function_privilege('authenticated', 'public.event_web_vip_link(uuid,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.event_web_vip_link(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.event_web_vip_link(uuid,uuid)', 'execute')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = 'public.event_web_vip_link(uuid,uuid)'::regprocedure and a.grantee = 0),
  'G2 event_web_vip_link: signed-in staff (it checks who) and the service role; not anon or PUBLIC');
select pg_temp.check(md5(pg_get_functiondef('public.event_web_guest_extras(uuid)'::regprocedure)) = '1e1af232acf928680d5f630c63541002'
    and md5(pg_get_functiondef('public.event_web_key_check(text)'::regprocedure)) = 'd86522bca42a63007dde3b93d8d84758'
    and md5(pg_get_functiondef('public.event_web_vip_link(uuid,uuid)'::regprocedure)) = 'aa91b87f6b11549a9c216e58e03eb414'
    and (select p.proacl::text from pg_proc p where p.oid = 'public.event_web_guest_extras(uuid)'::regprocedure)
        = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',
  'G3 the three functions have 526''s md5s; event_web_guest_extras keeps its grants');
select pg_temp.check((select bool_and(pg_get_functiondef(x.f::regprocedure) ~ E'\nbegin\n  perform public\\.require_active_staff\\('
                                      or pg_get_functiondef(x.f::regprocedure) ~ E'\nbegin\n(  --[^\n]*\n)*  perform public\\.require_active_staff\\(')
                        from (values ('public.event_web_guest_extras(uuid)'), ('public.event_web_vip_link(uuid,uuid)')) x(f))
    and pg_get_functiondef('public.event_web_guest_extras(uuid)'::regprocedure) like '%''vip_link_ready'', false, -- 526%',
  'G4 the two page functions call require_active_staff first; a VIP sold at the counter is never vip_link_ready');

-- ═════ K The key, before the message ═════
select pg_temp.check(pg_temp.key_check(pg_temp.tx('hash:live')) = '{"ok": true}'::jsonb
    and pg_temp.key_check(pg_temp.tx('hash:test')) = '{"ok": true}'::jsonb
    and pg_temp.key_check(pg_temp.tx('hash:ev2')) = '{"ok": true}'::jsonb,
  'K1 a live key, a test key and another event''s key: ok');
select pg_temp.check(pg_temp.key_check(pg_temp.tx('hash:revoked')) = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.call('revoked', 'event_info', '{}') = '{"ok": false, "error": "bad_key"}'::jsonb,
  'K2 a revoked key: bad_key, as event_web_call answers');
select pg_temp.check(pg_temp.key_check(pg_temp.tx('hash:unknown')) = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.call('unknown', 'event_info', '{}') = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.key_check(null) = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.key_check('') = '{"ok": false, "error": "bad_key"}'::jsonb,
  'K3 an unknown hash, none, or an empty one: bad_key');
select pg_temp.check(pg_temp.key_check(pg_temp.tx('hash:bare')) = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.call('bare', 'event_info', '{}') = '{"ok": false, "error": "bad_key"}'::jsonb,
  'K4 a key whose event has no website settings: bad_key, as event_web_call answers');
select pg_temp.check((select count(*) from public.event_web_keys where key_hash = pg_temp.tx('hash:test') and last_used_at is not null) = 0
    and (select count(*) from public.event_web_requests r join public.event_web_keys k on k.id = r.key_id
          where k.key_hash = pg_temp.tx('hash:test')) = 0,
  'K5 the check writes nothing: the test key it said ok to is still never used, and no request is kept for it');
-- A deleted event, its key left unrevoked (as 436's D3: the event's delete also revokes them). Its
-- website is switched Off first, as deleting an event asks; both are put back after.
update public.event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev2');
update public.events set deleted_at = now() where id = pg_temp.fx('ev2');
-- (Deleting the event revoked its key; it is unrevoked by hand, so the deleted event alone refuses it.)
update public.event_web_keys set revoked_at = null, revoked_by = null, revoked_reason = null where key_hash = pg_temp.tx('hash:ev2');
select pg_temp.check((select revoked_at is null from public.event_web_keys where key_hash = pg_temp.tx('hash:ev2'))
    and pg_temp.key_check(pg_temp.tx('hash:ev2')) = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.call('ev2', 'event_info', '{}', 'code2') = '{"ok": false, "error": "bad_key"}'::jsonb,
  'K6 a key of a deleted event (not revoked): bad_key, as event_web_call answers');
update public.events set deleted_at = null where id = pg_temp.fx('ev2');
update public.event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev2');
select pg_temp.check(pg_temp.key_check(pg_temp.tx('hash:ev2')) = '{"ok": true}'::jsonb, 'K7 the same event not deleted: ok again');

-- ═════ People ═════
select pg_temp.reg('free', pg_temp.person(1, 'Fern', 'Free', pg_temp.ph(10), pg_temp.mail('fern')));
select pg_temp.reg('vip', pg_temp.person(1, 'Vera', 'Vipson', pg_temp.ph(11), pg_temp.mail('vera')));
select pg_temp.put('vip_co', pg_temp.checkout('v1', 'vip')::text);
select pg_temp.put('vip_paid', pg_temp.paid('v1', 'vip')::text);
-- Held (their phone is Hilda's), then closed by the Owner.
select pg_temp.reg('shut', pg_temp.person(1, 'Cleo', 'Closed', pg_temp.ph(1), pg_temp.mail('cleo')));
select pg_temp.as_user('owner');
select pg_temp.put('shut_close', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('shut'), 'Not coming after all')));
select pg_temp.reg('other', pg_temp.person(1, 'Otto', 'Other', pg_temp.ph(12), pg_temp.mail('otto')), 'ev2', 'code2');
select pg_temp.check((pg_temp.pp('free')).match <> 'closed' and public.event_web_person_vip_state(pg_temp.fx('free')) = 'none'
    and pg_temp.tx('tok:free') ~ '^vip_[a-z2-7]{26}$'
    and public.event_web_person_vip_state(pg_temp.fx('vip')) = 'paid' and (pg_temp.tx('vip_paid')::jsonb)->>'status' = 'invoiced'
    and pg_temp.tx('shut_close') = 'ok' and (pg_temp.pp('shut')).match = 'closed'
    and (pg_temp.pp('other')).event_id = pg_temp.fx('ev2') and pg_temp.tx('tok:other') ~ '^vip_[a-z2-7]{26}$',
  'P the people: Fern registered (not VIP), Vera a paid VIP, Cleo held then closed, Otto of the second event: '
  || pg_temp.tx('vip_paid') || ' | ' || pg_temp.tx('shut_close'));

-- ═════ L The guest list carries no token ═════
select pg_temp.put('list', pg_temp.extras()::text);
select pg_temp.check(position(pg_temp.tx('tok:free') in pg_temp.tx('list')) = 0
    and position(pg_temp.tx('tok:vip') in pg_temp.tx('list')) = 0
    and position(pg_temp.tx('tok:shut') in pg_temp.tx('list')) = 0
    and pg_temp.tx('list') !~ 'vip_[a-z2-7]{26}'
    and (select bool_and(g ? 'upgrade_token' and g->'upgrade_token' = 'null'::jsonb and jsonb_typeof(g->'vip_link_ready') = 'boolean')
           from jsonb_array_elements(pg_temp.tx('list')::jsonb->'guests') g)
    and (select count(*) from jsonb_array_elements(pg_temp.tx('list')::jsonb->'guests')) >= 4,
  'L1 the guest list carries no one''s token anywhere; every row has upgrade_token null and vip_link_ready (a true or false)');
select pg_temp.check((select array_agg((g->>'vip_link_ready')::boolean) from pg_temp.rows_of('free') g) = array[true]
    and (select bool_and(not (g->>'vip_link_ready')::boolean) and count(*) = 2 from pg_temp.rows_of('vip') g)
    and (select bool_and(not (g->>'vip_link_ready')::boolean) and count(*) >= 1 from pg_temp.rows_of('shut') g),
  'L2 vip_link_ready: Fern (registered, not VIP) yes; Vera (paid VIP: her VIP record and her parked free one) no; Cleo (closed) no');

-- ═════ V One link per click, each in the Audit Log ═════
select pg_temp.put('n_audit0', pg_temp.all_link_audits()::text);
select pg_temp.as_user('staff');
select pg_temp.put('v1', public.event_web_vip_link(pg_temp.fx('ev'), pg_temp.fx('free'))::text);
select pg_temp.check(pg_temp.tx('v1')::jsonb = jsonb_build_object('ok', true, 'upgrade_token', pg_temp.tx('tok:free'))
    and pg_temp.link_audits('free') = 1,
  'V1 staff who can run the event get Fern''s own token, and one Audit Log row');
select pg_temp.check((select l.changed_by = pg_temp.fx('staff') and l.table_name = 'event_registration_people' and l.module = 'events'
                             and l.store_id = pg_temp.fx('van') and l.old_data is null
                             and l.new_data = jsonb_build_object('event_id', pg_temp.fx('ev'), 'person_id', pg_temp.fx('free'),
                                   'free_guest_id', (pg_temp.pp('free')).free_guest_id, 'vip_guest_id', null, 'position', 1, 'is_test', false)
                             and position(pg_temp.tx('tok:free') in l::text) = 0 and l::text !~ 'vip_[a-z2-7]{26}'
                        from public.audit_logs l where l.action = 'event_web_vip_link_copied' and l.record_id = pg_temp.fx('free')),
  'V2 the row: who (staff), when, the person, the event, their guest records, the store; never the token');
select pg_temp.as_user('manager');
select pg_temp.put('v3', public.event_web_vip_link(pg_temp.fx('ev'), pg_temp.fx('free'))::text);
select pg_temp.check((pg_temp.tx('v3')::jsonb)->>'upgrade_token' = pg_temp.tx('tok:free') and pg_temp.link_audits('free') = 2
    and (select count(*) from public.audit_logs l where l.action = 'event_web_vip_link_copied' and l.record_id = pg_temp.fx('free')
           and l.changed_by = pg_temp.fx('manager')) = 1,
  'V3 another click (a Manager): the link again, and a second row, hers');
select pg_temp.as_user('owner');
select pg_temp.check(public.event_web_vip_link(pg_temp.fx('ev'), pg_temp.fx('vip')) = '{"ok": false, "reason": "not_available"}'::jsonb
    and public.event_web_vip_link(pg_temp.fx('ev'), pg_temp.fx('shut')) = '{"ok": false, "reason": "not_available"}'::jsonb
    and public.event_web_vip_link(pg_temp.fx('ev'), pg_temp.fx('other')) = '{"ok": false, "reason": "not_available"}'::jsonb
    and public.event_web_vip_link(pg_temp.fx('ev'), gen_random_uuid()) = '{"ok": false, "reason": "not_available"}'::jsonb
    and public.event_web_vip_link(pg_temp.fx('ev'), null) = '{"ok": false, "reason": "not_available"}'::jsonb
    and pg_temp.link_audits('vip') = 0 and pg_temp.link_audits('shut') = 0 and pg_temp.link_audits('other') = 0,
  'V4 a paid VIP, a closed person, a person of another event, no one: not_available, the same answer, and no row');
select pg_temp.check((public.event_web_vip_link(pg_temp.fx('ev2'), pg_temp.fx('other'))->>'upgrade_token') = pg_temp.tx('tok:other')
    and pg_temp.link_audits('other') = 1,
  'V5 Otto by his own event: his token (and his row)');
select pg_temp.put('n_audit1', pg_temp.all_link_audits()::text);
select pg_temp.as_user('outsider');
select pg_temp.put('v6', pg_temp.err(format('select public.event_web_vip_link(%L, %L)', pg_temp.fx('ev'), pg_temp.fx('free'))));
select pg_temp.as_user('nobody');
select pg_temp.put('v7', pg_temp.err(format('select public.event_web_vip_link(%L, %L)', pg_temp.fx('ev'), pg_temp.fx('free'))));
select pg_temp.as_user('inactive');
select pg_temp.put('v8', pg_temp.err(format('select public.event_web_vip_link(%L, %L)', pg_temp.fx('ev'), pg_temp.fx('free'))));
select pg_temp.as_user('outsider');
select pg_temp.put('v9', pg_temp.err(format('select public.event_web_guest_extras(%L)', pg_temp.fx('ev'))));
select pg_temp.check(pg_temp.tx('v6') = '42501 You do not have access to this event'
    and pg_temp.tx('v9') = '42501 You do not have access to this event'
    and pg_temp.tx('v7') = '42501 Only active Energia staff can do this.'
    and pg_temp.tx('v8') = '42501 Only active Energia staff can do this.'
    and pg_temp.all_link_audits() = pg_temp.tx('n_audit1')::bigint,
  'V6 staff of another store (as the list refuses them), a login with no staff profile, a deactivated one: 42501, and no row: '
  || pg_temp.tx('v6') || ' | ' || pg_temp.tx('v7') || ' | ' || pg_temp.tx('v8'));
select pg_temp.check(pg_temp.all_link_audits() - pg_temp.tx('n_audit0')::bigint = 3,
  'V7 three links given, three rows; nothing else wrote one');

-- ═════ U Undo, and 526 again ═════
select pg_temp.as_service();
\ir ../undo-526.sql
select pg_temp.check(md5(pg_get_functiondef('public.event_web_guest_extras(uuid)'::regprocedure)) = '03358fda2da1b4fda082e3f29b512a38'
    and (select p.proacl::text from pg_proc p where p.oid = 'public.event_web_guest_extras(uuid)'::regprocedure)
        = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
    and to_regprocedure('public.event_web_key_check(text)') is null and to_regprocedure('public.event_web_vip_link(uuid,uuid)') is null
    and position(pg_temp.tx('tok:free') in pg_temp.extras()::text) > 0,
  'U1 undo-526 puts event_web_guest_extras back (449''s md5, its grants; the list has the token again) and drops the two functions');
\ir ../../../supabase/526_a_vip_link_is_read_one_at_a_time.sql
select pg_temp.check(md5(pg_get_functiondef('public.event_web_guest_extras(uuid)'::regprocedure)) = '1e1af232acf928680d5f630c63541002'
    and md5(pg_get_functiondef('public.event_web_key_check(text)'::regprocedure)) = 'd86522bca42a63007dde3b93d8d84758'
    and md5(pg_get_functiondef('public.event_web_vip_link(uuid,uuid)'::regprocedure)) = 'aa91b87f6b11549a9c216e58e03eb414'
    and (select p.proacl::text from pg_proc p where p.oid = 'public.event_web_key_check(text)'::regprocedure)
        = '{postgres=X/postgres,service_role=X/postgres}'
    and (select p.proacl::text from pg_proc p where p.oid = 'public.event_web_vip_link(uuid,uuid)'::regprocedure)
        = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
    and position(pg_temp.tx('tok:free') in pg_temp.extras()::text) = 0,
  'U2 526 again after the undo: the same three functions and rights');

-- ═════ M 526 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m526 m
                                   full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) n
                                     on n.fn = m.fn
                                  where m.fn is null or n.fn is null or m.md5 <> n.md5 or m.acl is distinct from n.acl),
  'M1 running 526 a second time (and the undo and 526 again) left every function and its rights as 526 made them');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 526 checks passed.';
end $$;
rollback;
