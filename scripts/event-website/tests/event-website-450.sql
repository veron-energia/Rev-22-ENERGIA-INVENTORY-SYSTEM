-- Someone staff took off the guest list buys no VIP until put back, and a signed-up-again hold is not
-- closed while their VIP payment waits (450).
--
-- The owner's answer, 22 Oct 2026, to the two loose ends 449 left: "Small follow-up after 449".
--   (a) a VIP checkout is refused (person_cancelled) for anyone whose free guest record staff took off
--       the list (not "Upgraded to VIP...") with no VIP record standing; a payment or transfer that
--       comes anyway waits for a Manager (needs review, no invoice);
--   (b) a signed-up-again hold is not closed while a VIP payment of theirs waits, with 444's words.
--
--   G  Grants and md5s: the two changed functions keep their grants and have 450's AFTER md5s, the
--      close checks the caller first; 449's other three are as 449 left them; no new function.
--   A  Taken off, never signed up again: a checkout is refused (person_cancelled, nothing kept; with
--      someone still registered, only she is named); a HitPay payment the app never heard of and a
--      transfer wait for a Manager (436's reason), nothing invoiced; the website still reads her as
--      not registered.
--   L  A checkout opened while on the list, paid after staff took her off: waits, not invoiced.
--   H  Her signed-up-again hold closed (still off): a checkout is refused; a transfer waits.
--   R  Her registration closed by a Manager (444: "Closed: ..."), also one waiting to be matched: a checkout
--      is refused; a transfer waits.
--   P  Put back (Restore): she can buy VIP; the payment is invoiced as anyone's.
--   C  Close of a signed-up-again hold while a VIP payment of theirs waits (needs review: a transfer
--      sent while held; recorded: a transfer sent before; recorded: a HitPay payment the website took
--      in Record only; a HitPay payment reported and not recorded yet, also past its expiry; needs
--      review: a HitPay payment while held): refused with 444's words, for an Owner or a Manager,
--      changing nothing; Staff still cannot close; Put back is not refused; once the payment is dealt
--      with on Website orders, Close is 449's; an unpaid checkout alone does not stop it (449).
--   U  A VIP (free record parked "Upgraded to VIP"): already VIP, as before.
--   W  Taken off, then made VIP by hand on Website orders (VIP record stands): already VIP, not
--      "not registered".
--   T  A test key: a test person (no guest record) checks out and transfers as before.
--   M  450 twice changes nothing; its self-test leaves no row (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.com); phones are ACMA's fictional range (+61 2 5550 ....). Run it on a copy of production
-- as it is (436, 439, 441, 444, 445 and 449 applied): it applies 450 twice, or run it with
-- -v skip_install=1 where 450 is already installed. Every check runs, then the file fails if any did.
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
\if :{?skip_install}
\else
create temp table r450 as select pg_temp.row_counts() as before;
\ir ../../../supabase/450_event_vip_taken_off_and_hold_close_waits.sql
create temp table m450 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
alter table r450 add column after1 jsonb;
update r450 set after1 = pg_temp.row_counts();
\ir ../../../supabase/450_event_vip_taken_off_and_hold_close_waits.sql
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
create function pg_temp.errcode(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- Fictional phones: +61 2 5550 nnnn (ACMA's drama range), one block per run.
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad(((pg_temp.tx('phbase')::int + n) % 10000)::text, 4, '0') $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'ht450-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
create function pg_temp.bid(prefix text, tag text) returns text language sql as
$$ select prefix || '-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || prefix || tag), 1, 8)) $$;
create function pg_temp.person(pos int, first text, last text, phone text, email text, days date[] default null)
returns jsonb language sql as
$$ select jsonb_build_object('position', pos, 'first_name', first, 'last_name', last, 'phone', phone, 'email', email,
            'days', to_jsonb(coalesce(days, array[pg_temp.d(7)])), 'vip', false) $$;
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
-- One form (people: a jsonb array); each person's id and token kept under <tag><position> (a person the answer gives
-- no id keeps the one they had).
create function pg_temp.reg(tag text, people jsonb, kind text default 'live') returns jsonb language plpgsql as $$
declare v jsonb; x jsonb;
begin
  v := pg_temp.call(kind, 'register', jsonb_build_object('registration', jsonb_build_object(
         'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', null, 'people', people)));
  for x in select y from jsonb_array_elements(v->'people') y where y->>'person_id' is not null loop
    perform pg_temp.putx(tag || (x->>'position'), (x->>'person_id')::uuid);
    perform pg_temp.put('tok:' || tag || (x->>'position'), x->>'upgrade_token');
  end loop;
  return v;
end $$;
create function pg_temp.pp(tag text) returns public.event_registration_people language sql as
$$ select * from public.event_registration_people where id = pg_temp.fx(tag) $$;
create function pg_temp.fg(tag text) returns public.event_guests language sql as
$$ select * from public.event_guests where id = (pg_temp.pp(tag)).free_guest_id $$;
create function pg_temp.gdays(tag text) returns date[] language sql as
$$ select array_agg(gd.day order by gd.day) from public.event_guest_days gd where gd.guest_id = (pg_temp.pp(tag)).free_guest_id $$;
create function pg_temp.toks(tags text[]) returns jsonb language sql as
$$ select jsonb_agg(pg_temp.tx('tok:' || t) order by n) from unnest(tags) with ordinality u(t, n) $$;
create function pg_temp.checkout(kind text, tag text, people text[]) returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_checkout', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', pg_temp.toks(people),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null),
     'livemode', kind = 'live', 'checkout_opened_at', now() - interval '3 minutes'))) $$;
create function pg_temp.paid(kind text, tag text, people text[]) returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_paid', jsonb_build_object('payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'provider', 'hitpay',
     'payment_request_id', md5('rq' || tag || pg_temp.tx('sfx'))::uuid, 'payment_id', md5('py' || tag || pg_temp.tx('sfx'))::uuid,
     'amount_cents', 7200 * cardinality(people), 'currency', 'SGD', 'livemode', kind = 'live', 'paid_at', now() - interval '1 minute',
     'upgrade_tokens', pg_temp.toks(people),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null)))) $$;
create function pg_temp.transfer(tag text, people text[]) returns jsonb language sql as
$$ select pg_temp.call('live', 'vip_transfer', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', pg_temp.toks(people),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null),
     'method', 'paynow', 'reference', 'PN-450-' || tag, 'paid_on', public.sg_today(), 'amount_cents', 7200 * cardinality(people),
     'submitted_at', now()))) $$;
create function pg_temp.vorder(tag text) returns public.event_vip_orders language sql as
$$ select * from public.event_vip_orders where order_id = pg_temp.bid('VIP', tag) $$;
create function pg_temp.vinvoices(tag text) returns setof public.invoices language sql as
$$ select i.* from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
     join public.invoices i on i.id = op.invoice_id where o.order_id = pg_temp.bid('VIP', tag) $$;
-- What the Event page reads (as the Owner): a person's To match entries, and their free guest's row.
create function pg_temp.extras() returns jsonb language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_user('owner');
  v := public.event_web_guest_extras(pg_temp.fx('ev'));
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
create function pg_temp.hold(tag text) returns jsonb language sql as
$$ select h from jsonb_array_elements(pg_temp.extras()->'holds') h where (h->>'person_id')::uuid = pg_temp.fx(tag) $$;
create function pg_temp.holds_of(tag text) returns bigint language sql as
$$ select count(*) from jsonb_array_elements(pg_temp.extras()->'holds') h where (h->>'person_id')::uuid = pg_temp.fx(tag) $$;
create function pg_temp.guest(tag text) returns jsonb language sql as
$$ select g from jsonb_array_elements(pg_temp.extras()->'guests') g
    where (g->>'person_id')::uuid = pg_temp.fx(tag) and (g->>'guest_id')::uuid = (pg_temp.pp(tag)).free_guest_id $$;
create function pg_temp.audits(rec uuid, act text) returns bigint language sql as
$$ select count(*) from audit_logs l where l.action = act and l.record_id = rec $$;
create function pg_temp.cust(name text, phone text, email text) returns uuid language sql as
$$ insert into customers(full_name, phone, email) values (name, phone, email) returning id $$;
create function pg_temp.person_read(tag text) returns jsonb language sql as
$$ select pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:' || tag))) $$;
create function pg_temp.answers(tag text) returns jsonb language sql as
$$ select pg_temp.call('live', 'planning_answers', jsonb_build_object('planning', jsonb_build_object('submitted_at', now(),
     'people', jsonb_build_array(jsonb_build_object('upgrade_token', pg_temp.tx('tok:' || tag), 'version', 0,
       'answers', jsonb_build_object('food', 'vegetarian', 'food_other', null, 'allergy', 'no', 'allergy_details', null,
         'timing', '[]'::jsonb, 'talks', '[]'::jsonb, 'access', '[]'::jsonb, 'access_other', null, 'heard_from', null,
         'heard_from_other', null, 'question', null)))))) $$;
-- The website's sync (once a minute per key: the last sync time is put back first; all of it is rolled back).
create function pg_temp.synced(tag text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  update public.event_web_settings set last_sync_at = null where event_id = pg_temp.fx('ev');
  v := pg_temp.call('live', 'sync', '{}');
  return (select p from jsonb_array_elements(v->'people') p where p->>'key' = pg_temp.fx(tag)::text);
end $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st2 uuid; ev uuid; src uuid; pm uuid; v1 uuid; v2 uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 9000))::int::text);
  foreach k in array array['owner', 'acting', 'manager', 'manager2', 'admin', 'staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'ht450-' || k || '-' || lower(sfx) || '@example.com');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'HT450 ' || initcap(k) || ' ' || sfx, 'ht450-' || k || '-' || lower(sfx) || '@example.com',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'admin' then 'admin' when 'staff' then 'staff'
                   else 'manager' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('HT450 Van ' || sfx, 'HT450V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('HT450 Shop ' || sfx, 'HT450S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id)
  values (pg_temp.fx('manager'), st), (pg_temp.fx('admin'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('manager2'), st2);
  ev := public.event_save(jsonb_build_object('name', 'HT450 Health Seminar ' || sfx,
    'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st, st2),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('HT450 Event ' || sfx, true, true, 9999) returning id into src;
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('HT450 $72 discount Voucher', 'HT450SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT450 3-in-1 Vouchers', 'HT450-3IN1' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true), (v2, st, 216, true);
  perform public.event_web_settings_save(ev, jsonb_build_object('code', 'HT450-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(v1, v2), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://healthtalk.example.com/api/app/sync'));
  insert into tx values ('code', 'HT450-' || sfx);
end $$;
do $$ declare r jsonb; begin
  perform pg_temp.as_user('owner');
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'Vercel production');
  insert into tx values ('hash:live', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  r := public.event_web_key_create(pg_temp.fx('ev'), 'test', 'Vercel preview');
  insert into tx values ('hash:test', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
end $$;
select pg_temp.check((pg_temp.call('live', 'event_info', '{}')->>'ok')::boolean, 'F the fixture event answers event_info');


-- 444's words when a Close is refused because a VIP payment waits.
create function pg_temp.waits(name text) returns text language sql as
$$ select 'A VIP payment for ' || name || ' is waiting: deal with it on Website orders first.' $$;
create function pg_temp.close_err(tag text, who text) returns text language plpgsql as $$
declare v text; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_user(who);
  v := pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx(tag), 'Leave them off (450 test)'));
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
-- 436's reason for someone no longer registered; 449's while their signed-up-again hold is open.
insert into tx values ('why436', 'Person 1 on this order is no longer registered (cancelled or closed)'),
  ('why449', 'Person 1 on this order signed up again after staff took them off the list: put them back on the list first (Guests, To match)');

-- ═════ G Grants and md5s ═════
select pg_temp.check((select bool_and(not has_function_privilege('anon', x.f, 'execute')
                                      and has_function_privilege('authenticated', x.f, 'execute') = x.page
                                      and has_function_privilege('service_role', x.f, 'execute'))
                        from (values ('public.event_vip_person_problems(uuid)', false),
                                     ('public.event_registration_close(uuid,text)', true)) x(f, page))
    and (select p.proacl::text from pg_proc p where p.oid = 'public.event_vip_person_problems(uuid)'::regprocedure)
        = '{postgres=X/postgres,service_role=X/postgres}'
    and (select p.proacl::text from pg_proc p where p.oid = 'public.event_registration_close(uuid,text)'::regprocedure)
        = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',
  'G1 the two changed functions keep their grants (the close signed-in staff''s, the problems the service role''s alone)');
-- (469, where it is applied, links by the phone and the email in event_web_register: 449's or 469's.)
select pg_temp.check((select bool_and(md5(pg_get_functiondef(x.f::regprocedure)) = any (string_to_array(x.m, ' ')))
                        from (values ('public.event_vip_person_problems(uuid)', 'add06a8aba39e4259bcf68bab4092027'),
                                     ('public.event_registration_close(uuid,text)', '39436dab86aa00d5884fceab88cb2d09'),
                                     ('public.event_web_register(uuid,jsonb)', '3aad1ad2a8a91732d330b2ef149bf969 c188a2dc82b9eb08fc9d01f1e5c15e13'),
                                     ('public.event_web_guest_extras(uuid)', '03358fda2da1b4fda082e3f29b512a38'),
                                     ('public.event_set_guest_cancelled(uuid,boolean,text)', 'af22a3fad6232dad1a748b9cc1ddb2ae')) x(f, m)),
  'G2 the two functions have 450''s AFTER md5s; 449''s other three are as 449 left them');
select pg_temp.check(pg_get_functiondef('public.event_registration_close(uuid,text)'::regprocedure)
                       ~ E'\nbegin\n  perform public\\.require_active_staff\\(''\\{owner,manager\\}''\\);',
  'G3 the close still checks the caller first (an Owner or Manager)');
select pg_temp.check((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                        and (p.proname like 'event\_web\_%' or p.proname like 'event\_vip\_%' or p.proname like 'event\_registration\_%')
                        and has_function_privilege('authenticated', p.oid, 'execute')) = 17,
  'G4 no new function: the page reaches the same 17 event_web / event_vip / event_registration functions as before');

-- ═════ A Taken off, never signed up again ═════
select pg_temp.reg('a', jsonb_build_array(pg_temp.person(1, 'Ada', 'Offlist', pg_temp.ph(10), pg_temp.mail('ada'))));
select pg_temp.reg('n', jsonb_build_array(pg_temp.person(1, 'Nia', 'Onlist', pg_temp.ph(11), pg_temp.mail('nia'))));
select pg_temp.as_user('manager');
select public.event_set_guest_cancelled((pg_temp.pp('a1')).free_guest_id, true, 'Cannot come');
select pg_temp.put('a_orders', (select count(*) from public.event_vip_orders where event_id = pg_temp.fx('ev'))::text);
select pg_temp.put('a1', pg_temp.checkout('live', 'a1', array['a1'])::text);
select pg_temp.put('a1n', pg_temp.checkout('live', 'a1n', array['n1', 'a1'])::text);
select pg_temp.check((pg_temp.tx('a1')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'refused',
                       'reason', 'person_cancelled', 'person_ids', jsonb_build_array(pg_temp.fx('a1')))
    and (pg_temp.tx('a1n')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'refused',
                       'reason', 'person_cancelled', 'person_ids', jsonb_build_array(pg_temp.fx('a1')))
    and (pg_temp.vorder('a1')).id is null and (pg_temp.vorder('a1n')).id is null
    and (select count(*) from public.event_vip_orders where event_id = pg_temp.fx('ev')) = pg_temp.tx('a_orders')::int
    and not exists (select 1 from public.event_vip_order_people where person_id in (pg_temp.fx('a1'), pg_temp.fx('n1')))
    and public.event_web_person_vip_state(pg_temp.fx('a1')) = 'none'
    and ((pg_temp.fg('a1')).status, (pg_temp.fg('a1')).cancelled_reason) = ('cancelled'::text, 'Cannot come'::text)
    and (pg_temp.pp('a1')).signed_up_again_at is null and pg_temp.hold('a1') is null,
  'A1 taken off ("Cannot come") and never signed up again: a VIP checkout is refused (person_cancelled, nothing kept), alone or with '
  || 'someone still on the list (only she is named): ' || pg_temp.tx('a1') || ' | ' || pg_temp.tx('a1n'));
select pg_temp.put('a1_nia', pg_temp.checkout('live', 'a1nia', array['n1'])::text);
select pg_temp.check((pg_temp.tx('a1_nia')::jsonb)->>'status' = 'ok',
  'A2 someone still on the list checks out as before: ' || pg_temp.tx('a1_nia'));
select pg_temp.put('a3', pg_temp.paid('live', 'a3', array['a1'])::text);
-- Dealt with on Website orders (not this file's), so it does not wait any more below.
select public.event_vip_order_close_refunded((pg_temp.vorder('a3')).id, 'In HitPay (450 test)', true);
select pg_temp.put('a4', pg_temp.transfer('a4', array['a1'])::text);
select public.event_vip_order_dismiss((pg_temp.vorder('a4')).id, 'Never arrived (450 test)', true);
select pg_temp.check((pg_temp.tx('a3')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('a3')::jsonb)->>'review_reason' = pg_temp.tx('why436')
    and (pg_temp.tx('a4')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('a4')::jsonb)->>'review_reason' = pg_temp.tx('why436')
    and (select count(*) from pg_temp.vinvoices('a3')) = 0 and (select count(*) from pg_temp.vinvoices('a4')) = 0
    and (pg_temp.pp('a1')).vip_guest_id is null and (pg_temp.fg('a1')).status = 'cancelled',
  'A3 a HitPay payment the app never heard of, and a PayNow transfer, for her anyway: each waits for a Manager (needs review, '
  || '"no longer registered"), nothing invoiced, she is not VIP: ' || pg_temp.tx('a3') || ' | ' || pg_temp.tx('a4'));
select pg_temp.check(pg_temp.person_read('a1')->'person' @> '{"can_upgrade": false, "reason": "cancelled", "vip": "none"}'::jsonb,
  'A4 the website still reads her as not registered (no VIP offered), as before');

-- ═════ L A checkout opened while on the list, paid after staff took her off ═════
select pg_temp.reg('l', jsonb_build_array(pg_temp.person(1, 'Lee', 'Lately', pg_temp.ph(12), pg_temp.mail('lee'))));
select pg_temp.put('l_co', pg_temp.checkout('live', 'l1', array['l1'])::text);
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('l1')).free_guest_id, true, 'Asked not to come');
select pg_temp.put('l1', pg_temp.paid('live', 'l1', array['l1'])::text);
select pg_temp.check((pg_temp.tx('l_co')::jsonb)->>'status' = 'ok'
    and (pg_temp.tx('l1')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('l1')::jsonb)->>'review_reason' = pg_temp.tx('why436')
    and (select count(*) from pg_temp.vinvoices('l1')) = 0 and (pg_temp.pp('l1')).vip_guest_id is null
    and public.event_web_person_vip_state(pg_temp.fx('l1')) <> 'paid'
    and ((pg_temp.fg('l1')).status, (pg_temp.fg('l1')).cancelled_reason) = ('cancelled'::text, 'Asked not to come'::text),
  'L1 a checkout she opened while on the list, paid after staff took her off: it waits for a Manager (needs review), not invoiced: '
  || pg_temp.tx('l1'));

-- ═════ H Her signed-up-again hold closed: still off ═════
select pg_temp.reg('b', jsonb_build_array(pg_temp.person(1, 'Bea', 'Closedhold', pg_temp.ph(13), pg_temp.mail('bea'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('b1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('b_again', jsonb_build_array(pg_temp.person(1, 'Bea', 'Closedhold', pg_temp.ph(13), pg_temp.mail('bea'), array[pg_temp.d(8)])));
select pg_temp.as_user('manager');
select pg_temp.put('b_close', public.event_registration_close(pg_temp.fx('b1'), 'Leave her off: cannot come')::text);
select pg_temp.put('b1', pg_temp.checkout('live', 'b1', array['b1'])::text);
select pg_temp.put('b2', pg_temp.transfer('b2', array['b1'])::text);
select pg_temp.check((pg_temp.tx('b_close')::jsonb) = '{"ok": true, "checkouts_closed": [], "signed_up_again": "closed"}'::jsonb
    and (pg_temp.pp('b1')).signed_up_again_resolved_at is not null and (pg_temp.fg('b1')).status = 'cancelled'
    and (pg_temp.tx('b1')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'refused',
                                                       'reason', 'person_cancelled', 'person_ids', jsonb_build_array(pg_temp.fx('b1')))
    and (pg_temp.vorder('b1')).id is null
    and (pg_temp.tx('b2')::jsonb)->>'status' = 'needs_review' and (pg_temp.tx('b2')::jsonb)->>'review_reason' = pg_temp.tx('why436')
    and (select count(*) from pg_temp.vinvoices('b2')) = 0,
  'H1 her signed-up-again hold closed with nothing waiting (as 449), she stays off: a checkout is refused (nothing kept), a transfer '
  || 'waits for a Manager: ' || pg_temp.tx('b1') || ' | ' || pg_temp.tx('b2'));

-- ═════ R Her registration closed by a Manager (444) ═════
select pg_temp.reg('r', jsonb_build_array(pg_temp.person(1, 'Rex', 'Closedreg', pg_temp.ph(14), pg_temp.mail('rex'))));
select pg_temp.as_user('manager');
select pg_temp.put('r_close', public.event_registration_close(pg_temp.fx('r1'), 'Sent twice by mistake')::text);
select pg_temp.put('r1', pg_temp.checkout('live', 'r1', array['r1'])::text);
select pg_temp.put('r2', pg_temp.transfer('r2', array['r1'])::text);
select pg_temp.check((pg_temp.tx('r_close')::jsonb) = '{"ok": true, "checkouts_closed": []}'::jsonb
    and (pg_temp.pp('r1')).match = 'closed' and (pg_temp.fg('r1')).cancelled_reason = 'Closed: Sent twice by mistake'
    and (pg_temp.tx('r1')::jsonb) @> jsonb_build_object('status', 'refused', 'reason', 'person_cancelled',
                                                        'person_ids', jsonb_build_array(pg_temp.fx('r1')))
    and (pg_temp.vorder('r1')).id is null
    and (pg_temp.tx('r2')::jsonb)->>'status' = 'needs_review' and (pg_temp.tx('r2')::jsonb)->>'review_reason' = pg_temp.tx('why436')
    and (select count(*) from pg_temp.vinvoices('r2')) = 0,
  'R1 a registration a Manager closed ("Closed: ..."): a checkout is refused (nothing kept), a transfer waits for a Manager: '
  || pg_temp.tx('r1') || ' | ' || pg_temp.tx('r2'));
-- R2 waiting to be matched (on the list at once, no customer: the phone is another customer's), then closed by a Manager.
select pg_temp.putx('holder', pg_temp.cust('Hilda Holder', pg_temp.ph(25), null));
select pg_temp.reg('m', jsonb_build_array(pg_temp.person(1, 'Mo', 'Matchclosed', pg_temp.ph(25), pg_temp.mail('mo'))));
select pg_temp.put('m_held', ((pg_temp.pp('m1')).match = 'held' and (pg_temp.fg('m1')).status = 'registered')::text);
select pg_temp.as_user('manager');
select public.event_registration_close(pg_temp.fx('m1'), 'Not a real registration');
select pg_temp.put('m1', pg_temp.checkout('live', 'm1', array['m1'])::text);
select pg_temp.check(pg_temp.tx('m_held') = 'true' and (pg_temp.pp('m1')).match = 'closed'
    and (pg_temp.fg('m1')).cancelled_reason = 'Closed: Not a real registration'
    and (pg_temp.tx('m1')::jsonb) @> jsonb_build_object('status', 'refused', 'reason', 'person_cancelled',
                                                        'person_ids', jsonb_build_array(pg_temp.fx('m1')))
    and (pg_temp.vorder('m1')).id is null,
  'R2 a registration waiting to be matched (on the list at once) that a Manager closed: a checkout is refused: ' || pg_temp.tx('m1'));

-- ═════ P Put back: VIP as anyone's ═════
select pg_temp.reg('p', jsonb_build_array(pg_temp.person(1, 'Pia', 'Putback', pg_temp.ph(15), pg_temp.mail('pia'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('p1')).free_guest_id, true, 'Cannot come');
select pg_temp.put('p_off', pg_temp.checkout('live', 'p0', array['p1'])::text);
select pg_temp.as_user('staff');
select pg_temp.put('p_back', public.event_set_guest_cancelled((pg_temp.pp('p1')).free_guest_id, false, 'She can come after all')::text);
select pg_temp.put('p1', pg_temp.checkout('live', 'p1', array['p1'])::text);
select pg_temp.put('p1_paid', pg_temp.paid('live', 'p1', array['p1'])::text);
select pg_temp.check((pg_temp.tx('p_off')::jsonb)->>'reason' = 'person_cancelled'
    and (pg_temp.tx('p_back')::jsonb)->>'status' = 'registered'
    and (pg_temp.tx('p1')::jsonb)->>'status' = 'ok' and (pg_temp.tx('p1_paid')::jsonb)->>'status' = 'invoiced'
    and exists (select 1 from public.event_guests g where g.id = (pg_temp.pp('p1')).vip_guest_id and g.status = 'registered')
    and public.event_web_person_vip_state(pg_temp.fx('p1')) = 'paid',
  'P1 taken off (refused), then put back (Restore): she checks out and HitPay''s payment is invoiced as anyone''s: '
  || pg_temp.tx('p1_paid'));

-- ═════ C Close of a signed-up-again hold while a VIP payment of theirs waits ═════
-- C1 needs review: a transfer sent while held.
select pg_temp.reg('c', jsonb_build_array(pg_temp.person(1, 'Cora', 'Waiting', pg_temp.ph(16), pg_temp.mail('cora'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('c1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('c_again', jsonb_build_array(pg_temp.person(1, 'Cora', 'Waiting', pg_temp.ph(16), pg_temp.mail('cora'), array[pg_temp.d(8)])));
select pg_temp.put('c_tr', pg_temp.transfer('c1', array['c1'])::text);
select pg_temp.put('c_audits', (select count(*) from audit_logs)::text);
select pg_temp.put('c_m', pg_temp.close_err('c1', 'manager'));
select pg_temp.put('c_o', pg_temp.close_err('c1', 'owner'));
select pg_temp.as_user('staff');
select pg_temp.put('c_s', pg_temp.errcode(format('select public.event_registration_close(%L, %L)', pg_temp.fx('c1'), 'Leave her off')));
select pg_temp.check((pg_temp.tx('c_tr')::jsonb)->>'status' = 'needs_review' and (pg_temp.tx('c_tr')::jsonb)->>'review_reason' = pg_temp.tx('why449')
    and pg_temp.tx('c_m') = pg_temp.waits('Cora Waiting') and pg_temp.tx('c_o') = pg_temp.waits('Cora Waiting')
    and pg_temp.tx('c_s') = '42501'
    and (pg_temp.pp('c1')).signed_up_again_resolved_at is null and (pg_temp.pp('c1')).match = 'new_customer'
    and ((pg_temp.fg('c1')).status, (pg_temp.fg('c1')).cancelled_reason) = ('cancelled'::text, 'Cannot come'::text)
    and (pg_temp.vorder('c1')).status = 'needs_review'
    and (select count(*) from audit_logs) = pg_temp.tx('c_audits')::bigint
    and pg_temp.hold('c1')->>'reason' = 'signed_up_again',
  'C1 her transfer sent while held waits (needs review, 449''s reason): a Manager''s and an Owner''s Close of her hold are refused '
  || 'with 444''s words and change nothing (still held, still off, the transfer still waits, no audit row); Staff still cannot: '
  || pg_temp.tx('c_m'));
select pg_temp.as_user('staff');
select pg_temp.put('c_back', public.event_set_guest_cancelled((pg_temp.pp('c1')).free_guest_id, false, 'Called her: she can come')::text);
select pg_temp.put('c_stale', pg_temp.close_err('c1', 'manager'));
select pg_temp.check((pg_temp.tx('c_back')::jsonb) @> jsonb_build_object('status', 'registered', 'signed_up_again', true,
                       'days_added', jsonb_build_array(pg_temp.d(8)))
    and (pg_temp.vorder('c1')).status = 'needs_review'
    and pg_temp.tx('c_stale') = 'This registration is not waiting for staff any more.',
  'C2 Put back is not refused while her payment waits (it stays on Website orders); a Close after it is 449''s stale refusal: '
  || pg_temp.tx('c_stale'));
-- C3 recorded: a transfer sent while he was on the list, for a Manager to confirm.
select pg_temp.reg('d', jsonb_build_array(pg_temp.person(1, 'Dan', 'Recorded', pg_temp.ph(17), pg_temp.mail('dan'))));
select pg_temp.put('d_tr', pg_temp.transfer('d1', array['d1'])::text);
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('d1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('d_again', jsonb_build_array(pg_temp.person(1, 'Dan', 'Recorded', pg_temp.ph(17), pg_temp.mail('dan'), array[pg_temp.d(8)])));
select pg_temp.put('d_close', pg_temp.close_err('d1', 'manager'));
select pg_temp.check((pg_temp.tx('d_tr')::jsonb)->>'status' = 'recorded'
    and pg_temp.tx('d_close') = pg_temp.waits('Dan Recorded')
    and (pg_temp.vorder('d1')).status = 'recorded' and (pg_temp.pp('d1')).signed_up_again_resolved_at is null,
  'C3 his transfer recorded while he was on the list (for a Manager to confirm): Close of his hold is refused: ' || pg_temp.tx('d_close'));
-- C4 recorded: a HitPay payment the website took in Record only.
select pg_temp.reg('e', jsonb_build_array(pg_temp.person(1, 'Eve', 'Recordonly', pg_temp.ph(18), pg_temp.mail('eve'))));
update public.event_web_settings set mode = 'record_only' where event_id = pg_temp.fx('ev');
select pg_temp.put('e_co', pg_temp.checkout('live', 'e1', array['e1'])::text);
select pg_temp.put('e_paid', pg_temp.paid('live', 'e1', array['e1'])::text);
update public.event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev');
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('e1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('e_again', jsonb_build_array(pg_temp.person(1, 'Eve', 'Recordonly', pg_temp.ph(18), pg_temp.mail('eve'), array[pg_temp.d(8)])));
select pg_temp.put('e_close', pg_temp.close_err('e1', 'manager'));
select pg_temp.check((pg_temp.tx('e_co')::jsonb)->>'status' = 'ok' and (pg_temp.tx('e_paid')::jsonb)->>'status' = 'recorded'
    and (select count(*) from pg_temp.vinvoices('e1')) = 0
    and pg_temp.tx('e_close') = pg_temp.waits('Eve Recordonly')
    and (pg_temp.vorder('e1')).status = 'recorded' and (pg_temp.pp('e1')).signed_up_again_resolved_at is null,
  'C4 her HitPay payment recorded, not invoiced (the website was Record only): Close of her hold is refused: ' || pg_temp.tx('e_close'));
-- C5 a HitPay payment reported and not recorded yet (what event_web_vip_paid writes first, in the transaction that records it:
-- written here by hand), before and after its checkout's expiry.
select pg_temp.reg('f', jsonb_build_array(pg_temp.person(1, 'Fay', 'Midpayment', pg_temp.ph(19), pg_temp.mail('fay'))));
select pg_temp.put('f_co', pg_temp.checkout('live', 'f1', array['f1'])::text);
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('f1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('f_again', jsonb_build_array(pg_temp.person(1, 'Fay', 'Midpayment', pg_temp.ph(19), pg_temp.mail('fay'), array[pg_temp.d(8)])));
update public.event_vip_orders set hitpay_payment_request_id = md5('rq-f1' || pg_temp.tx('sfx'))::uuid::text, paid_at = now(),
       amount_paid_cents = 7200
 where id = (pg_temp.vorder('f1')).id;
select pg_temp.put('f_close', pg_temp.close_err('f1', 'manager'));
update public.event_vip_orders set expires_at = now() - interval '1 hour' where id = (pg_temp.vorder('f1')).id;
select pg_temp.put('f_close2', pg_temp.close_err('f1', 'manager'));
select pg_temp.check((pg_temp.tx('f_co')::jsonb)->>'status' = 'ok'
    and pg_temp.tx('f_close') = pg_temp.waits('Fay Midpayment') and pg_temp.tx('f_close2') = pg_temp.waits('Fay Midpayment')
    and (pg_temp.vorder('f1')).status = 'pending' and pg_temp.audits((pg_temp.vorder('f1')).id, 'event_vip_checkout_closed') = 0
    and (pg_temp.pp('f1')).signed_up_again_resolved_at is null,
  'C5 HitPay reported a payment for her checkout, not recorded yet: Close of her hold is refused (also past the checkout''s expiry), '
  || 'and the order is not closed with it: ' || pg_temp.tx('f_close2'));
-- C6 needs review: a HitPay payment while held; dealt with on Website orders (closed as refunded), Close is 449's.
select pg_temp.reg('g', jsonb_build_array(pg_temp.person(1, 'Gus', 'Paidheld', pg_temp.ph(20), pg_temp.mail('gus'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('g1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('g_again', jsonb_build_array(pg_temp.person(1, 'Gus', 'Paidheld', pg_temp.ph(20), pg_temp.mail('gus'), array[pg_temp.d(8)])));
select pg_temp.put('g_paid', pg_temp.paid('live', 'g1', array['g1'])::text);
select pg_temp.put('g_close', pg_temp.close_err('g1', 'manager'));
select pg_temp.as_user('manager');
select public.event_vip_order_close_refunded((pg_temp.vorder('g1')).id, 'In HitPay (450 test)', true);
select pg_temp.put('g_close2', public.event_registration_close(pg_temp.fx('g1'), 'Leave him off: refunded')::text);
select pg_temp.check((pg_temp.tx('g_paid')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('g_paid')::jsonb)->>'review_reason' = pg_temp.tx('why449')
    and pg_temp.tx('g_close') = pg_temp.waits('Gus Paidheld')
    and (pg_temp.tx('g_close2')::jsonb) = '{"ok": true, "checkouts_closed": [], "signed_up_again": "closed"}'::jsonb
    and (pg_temp.pp('g1')).signed_up_again_resolved_at is not null and (pg_temp.fg('g1')).status = 'cancelled'
    and pg_temp.audits(pg_temp.fx('g1'), 'event_registration_signed_up_again_closed') = 1 and pg_temp.hold('g1') is null,
  'C6 his HitPay payment while held waits (needs review): Close is refused; once a Manager closed it as refunded on Website orders, '
  || 'Close leaves him off as 449: ' || pg_temp.tx('g_close2'));
-- C7 the transfer of C3 dismissed on Website orders (it never arrived): Close is 449's.
select pg_temp.as_user('manager');
select public.event_vip_order_dismiss((pg_temp.vorder('d1')).id, 'Never arrived (450 test)', true);
select pg_temp.put('d_close2', public.event_registration_close(pg_temp.fx('d1'), 'Leave him off: cannot come')::text);
select pg_temp.check((pg_temp.tx('d_close2')::jsonb) = '{"ok": true, "checkouts_closed": [], "signed_up_again": "closed"}'::jsonb
    and (pg_temp.pp('d1')).signed_up_again_resolved_at is not null,
  'C7 his transfer dismissed on Website orders (never arrived): Close leaves him off as 449: ' || pg_temp.tx('d_close2'));
-- C8 an online checkout not paid does not stop it: it closes with the hold (449, as 444).
select pg_temp.reg('k', jsonb_build_array(pg_temp.person(1, 'Kai', 'Unpaid', pg_temp.ph(21), pg_temp.mail('kai'))));
select pg_temp.put('k_co', pg_temp.checkout('live', 'k1', array['k1'])::text);
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('k1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('k_again', jsonb_build_array(pg_temp.person(1, 'Kai', 'Unpaid', pg_temp.ph(21), pg_temp.mail('kai'), array[pg_temp.d(8)])));
select pg_temp.as_user('manager');
select pg_temp.put('k_close', public.event_registration_close(pg_temp.fx('k1'), 'Leave him off: cannot come')::text);
select pg_temp.check((pg_temp.tx('k_co')::jsonb)->>'status' = 'ok'
    and (pg_temp.tx('k_close')::jsonb) = jsonb_build_object('ok', true, 'signed_up_again', 'closed',
          'checkouts_closed', jsonb_build_array(jsonb_build_object('order_id', pg_temp.bid('VIP', 'k1'), 'people', 1, 'open', true)))
    and (pg_temp.vorder('k1')).status = 'dismissed',
  'C8 only his unpaid HitPay checkout: Close of his hold goes ahead and closes it (449, as 444): ' || pg_temp.tx('k_close'));

-- ═════ U A VIP: as before ═════
select pg_temp.reg('u', jsonb_build_array(pg_temp.person(1, 'Una', 'Upgraded', pg_temp.ph(22), pg_temp.mail('una'))));
select pg_temp.checkout('live', 'u1', array['u1']);
select pg_temp.put('u_paid', pg_temp.paid('live', 'u1', array['u1'])::text);
select pg_temp.put('u2', pg_temp.checkout('live', 'u2', array['u1'])::text);
select pg_temp.check((pg_temp.tx('u_paid')::jsonb)->>'status' = 'invoiced'
    and (pg_temp.fg('u1')).status = 'cancelled' and (pg_temp.fg('u1')).cancelled_reason like 'Upgraded to VIP%'
    and (pg_temp.tx('u2')::jsonb) @> '{"status": "refused", "reason": "already_vip"}'::jsonb,
  'U1 a VIP (her free record parked "Upgraded to VIP"): another checkout is refused already_vip, as before, not person_cancelled: '
  || pg_temp.tx('u2'));

-- ═════ W Taken off, then made VIP by hand ═════
select pg_temp.reg('w', jsonb_build_array(pg_temp.person(1, 'Wyn', 'Byhand', pg_temp.ph(23), pg_temp.mail('wyn'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('w1')).free_guest_id, true, 'Cannot come');
select pg_temp.put('w_tr', pg_temp.transfer('w1', array['w1'])::text);
select pg_temp.as_user('manager');
select pg_temp.put('w_inv', pg_temp.err(format('select public.event_vip_order_invoice(%L)', (pg_temp.vorder('w1')).id)));
select pg_temp.put('w2', pg_temp.checkout('live', 'w2', array['w1'])::text);
select pg_temp.check((pg_temp.tx('w_tr')::jsonb)->>'status' = 'needs_review' and (pg_temp.tx('w_tr')::jsonb)->>'review_reason' = pg_temp.tx('why436')
    and pg_temp.tx('w_inv') = 'ok' and (pg_temp.vorder('w1')).status = 'invoiced'
    and exists (select 1 from public.event_guests g where g.id = (pg_temp.pp('w1')).vip_guest_id and g.status = 'registered')
    and ((pg_temp.fg('w1')).status, (pg_temp.fg('w1')).cancelled_reason) = ('cancelled'::text, 'Cannot come'::text)
    and (pg_temp.tx('w2')::jsonb) @> '{"status": "refused", "reason": "already_vip"}'::jsonb,
  'W1 taken off, his transfer waits; a Manager invoices it by hand (his VIP record stands): another checkout says already VIP, '
  || 'not "no longer registered": ' || pg_temp.tx('w_inv') || ' | ' || pg_temp.tx('w2'));

-- ═════ T A test key: as before ═════
select pg_temp.reg('t', jsonb_build_array(pg_temp.person(1, 'Tia', 'Testing', pg_temp.ph(24), pg_temp.mail('tia'))), 'test');
select pg_temp.put('t1', pg_temp.checkout('test', 't1', array['t1'])::text);
select pg_temp.put('t2', pg_temp.call('test', 'vip_transfer', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', 't2'), 'upgrade_tokens', pg_temp.toks(array['t1']),
     'payer', jsonb_build_object('name', 'Payer t2', 'email', pg_temp.mail('payer-t2'), 'phone', null),
     'method', 'paynow', 'reference', 'PN-450-t2', 'paid_on', public.sg_today(), 'amount_cents', 7200, 'submitted_at', now())))::text);
select pg_temp.check((pg_temp.pp('t1')).free_guest_id is null
    and (pg_temp.tx('t1')::jsonb) @> '{"status": "ok", "test": true}'::jsonb
    and (pg_temp.tx('t2')::jsonb) @> '{"status": "test", "test": true}'::jsonb,
  'T1 a test key''s person (no guest record): checkout and transfer as before: ' || pg_temp.tx('t1') || ' | ' || pg_temp.tx('t2'));

-- ═════ M 450 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m450 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m450),
  'M1 running 450 a second time changed no function');
select pg_temp.check((select before = after1 from r450),
  'M2 450''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 450 checks passed.';
end $$;
rollback;
