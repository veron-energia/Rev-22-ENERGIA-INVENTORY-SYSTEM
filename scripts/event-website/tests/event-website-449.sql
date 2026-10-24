-- Someone staff took off the guest list who signs up again waits for staff (449).
--
-- The owner's answer, 22 Oct 2026: "Hold for staff to decide: They show under
-- Registration holds on the Event page as 'signed up again after being taken
-- off'; staff put them back or close it. The website says their place will be
-- confirmed instead of 'You're registered!'."
--
--   G  Grants and md5s: the five changed functions keep their grants and have
--      449's AFTER md5s, the three page functions check the caller first; the
--      three columns and their check are there; the table is no client's; no
--      new function reaches the page.
--   R  Signing up again after being taken off (their own email): held, not
--      silently left off: the answer gives no days (the website's "your place
--      will be confirmed"), their record and guest record are as they were,
--      the days asked are kept on the hold, one audit row per sign-up; again:
--      the same hold (the days added, one hold, no second entry); the page
--      lists it under To match as signed_up_again (who took them off, why,
--      the days asked; no candidates) and marks the cancelled guest row; the
--      website's person read, answers and sync still say not registered.
--   V  VIP while held: a checkout is refused (person_cancelled, nothing kept,
--      only the held person named); a HitPay payment or a transfer that comes
--      anyway waits for a Manager with the reason; nothing is invoiced.
--   P  Put back (Staff can): registered again on the days they had and the
--      days asked, the hold resolved, audited (days asked and added); VIP and
--      answers open again; the sync says registered; a Close from a page that
--      did not see it is refused; signing up again now is as 436.
--   C  Close (an Owner or Manager with the store's access, a reason): they
--      stay off (guest cancelled with staff's reason, the registration not
--      closed), the hold resolved, audited; attach and New customer refuse a
--      signed-up-again hold; signing up again after Close holds them again.
--   U  Taken off as "Upgraded to VIP" (their VIP record stands): as before.
--   E  Another email: today's anonymous "already registered", no hold.
--   T  A test key: a test person is never held (no guest record), as before.
--   H  Waiting to be matched and taken off on the Guests tab, then signing up
--      again: listed once (To match) with the note and Put back; Put back
--      keeps them under To match.
--   K  Close of a hold takes their unpaid HitPay checkout with it (dismissed,
--      audited, listed), as 444's Close: a payment HitPay reports for it later
--      waits on Website orders, never invoiced by itself.
--   W  A payment invoiced by hand while held (they are VIP): no hold shows,
--      Close says they are VIP (444), Restore is 415's.
--   S  A removal stamped after the sign-up's start (it committed while the
--      sign-up waited): the hold starts at the removal, so it is listed.
--   M  449 twice changes nothing; its self-test leaves no row (when this file
--      installs it).
--
-- Disposable local database only; everything is rolled back. Every name and
-- email is invented (@example.com); phones are ACMA's fictional range (+61 2
-- 5550 ....). Run it on a copy of production as it is (436, 439, 441, 444
-- and 445 applied): it applies 449 twice, or run it with -v skip_install=1
-- where 449 is already installed. Every check runs, then the file fails if
-- any did.
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
create temp table r449 as select pg_temp.row_counts() as before;
\ir ../../../supabase/449_event_website_signed_up_again_held.sql
create temp table m449 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
alter table r449 add column after1 jsonb;
update r449 set after1 = pg_temp.row_counts();
\ir ../../../supabase/449_event_website_signed_up_again_held.sql
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
$$ select 'ht449-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
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
     'method', 'paynow', 'reference', 'PN-449-' || tag, 'paid_on', public.sg_today(), 'amount_cents', 7200 * cardinality(people),
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
    insert into auth.users(id, email) values (u, 'ht449-' || k || '-' || lower(sfx) || '@example.com');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'HT449 ' || initcap(k) || ' ' || sfx, 'ht449-' || k || '-' || lower(sfx) || '@example.com',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'admin' then 'admin' when 'staff' then 'staff'
                   else 'manager' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('HT449 Van ' || sfx, 'HT449V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('HT449 Shop ' || sfx, 'HT449S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id)
  values (pg_temp.fx('manager'), st), (pg_temp.fx('admin'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('manager2'), st2);
  ev := public.event_save(jsonb_build_object('name', 'HT449 Health Seminar ' || sfx,
    'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st, st2),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('HT449 Event ' || sfx, true, true, 9999) returning id into src;
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('HT449 $72 discount Voucher', 'HT449SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT449 3-in-1 Vouchers', 'HT449-3IN1' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true), (v2, st, 216, true);
  perform public.event_web_settings_save(ev, jsonb_build_object('code', 'HT449-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(v1, v2), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://healthtalk.example.com/api/app/sync'));
  insert into tx values ('code', 'HT449-' || sfx);
  -- Someone whose phone the To match person below shares.
  insert into fx values ('holder', pg_temp.cust('Hilda Holder', pg_temp.ph(1), null));
end $$;
do $$ declare r jsonb; begin
  perform pg_temp.as_user('owner');
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'Vercel production');
  insert into tx values ('hash:live', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  r := public.event_web_key_create(pg_temp.fx('ev'), 'test', 'Vercel preview');
  insert into tx values ('hash:test', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
end $$;
select pg_temp.check((pg_temp.call('live', 'event_info', '{}')->>'ok')::boolean, 'F the fixture event answers event_info');

-- ═════ G Grants, md5s and the columns ═════
select pg_temp.check((select bool_and(not has_function_privilege('anon', x.f, 'execute')
                                      and has_function_privilege('authenticated', x.f, 'execute') = x.page
                                      and has_function_privilege('service_role', x.f, 'execute'))
                        from (values ('public.event_web_register(uuid,jsonb)', false), ('public.event_web_guest_extras(uuid)', true),
                                     ('public.event_set_guest_cancelled(uuid,boolean,text)', true),
                                     ('public.event_registration_close(uuid,text)', true),
                                     ('public.event_vip_person_problems(uuid)', false)) x(f, page)),
  'G1 the five changed functions keep their grants (the three page functions signed-in staff''s, register and the problems the service role''s)');
-- (450, where it is applied, refused VIP for anyone taken off the list and a hold's Close while their payment waits:
-- event_vip_person_problems and event_registration_close are 449's or 450's. 469, where it is applied, links by the
-- phone and the email in event_web_register: 449's or 469's.)
select pg_temp.check((select bool_and(md5(pg_get_functiondef(x.f::regprocedure)) = any (string_to_array(x.m, ' ')))
                        from (values ('public.event_web_register(uuid,jsonb)', '3aad1ad2a8a91732d330b2ef149bf969 c188a2dc82b9eb08fc9d01f1e5c15e13'),
                                     ('public.event_web_guest_extras(uuid)', '03358fda2da1b4fda082e3f29b512a38'),
                                     ('public.event_set_guest_cancelled(uuid,boolean,text)', 'af22a3fad6232dad1a748b9cc1ddb2ae'),
                                     ('public.event_registration_close(uuid,text)', '60f3dde4dc9f7d8cc33f5517e54eeed8 39436dab86aa00d5884fceab88cb2d09'),
                                     ('public.event_vip_person_problems(uuid)', 'ec2fbe26fa116505cdd56910d17ce9ea add06a8aba39e4259bcf68bab4092027')) x(f, m)),
  'G2 the five functions have 449''s AFTER md5s (450''s for the problems and the close, where applied)');
select pg_temp.check((select bool_and(pg_get_functiondef(x.f::regprocedure) ~ E'\nbegin\n  perform public\\.require_active_staff\\(')
                        from (values ('public.event_web_guest_extras(uuid)'), ('public.event_set_guest_cancelled(uuid,boolean,text)'),
                                     ('public.event_registration_close(uuid,text)')) x(f)),
  'G3 the three page functions still call require_active_staff first');
select pg_temp.check((select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull || ' ' || a.atthasdef, ', '
                                        order by a.attnum)
                        from pg_attribute a where a.attrelid = 'public.event_registration_people'::regclass and a.attnum > 0
                         and not a.attisdropped and a.attname like 'signed\_up\_again%')
                     = 'signed_up_again_at timestamp with time zone false false, signed_up_again_days date[] false false, '
                       || 'signed_up_again_resolved_at timestamp with time zone false false'
    and exists (select 1 from pg_constraint c where c.conrelid = 'public.event_registration_people'::regclass
                  and c.conname = 'event_registration_people_signed_up_again_check')
    and not has_any_column_privilege('anon', 'public.event_registration_people', 'select,insert,update,references')
    and not has_any_column_privilege('authenticated', 'public.event_registration_people', 'select,insert,update,references')
    and (select c.relrowsecurity from pg_class c where c.oid = 'public.event_registration_people'::regclass),
  'G4 the three columns (nullable, no default) and their check are there; the table is still no client''s (row level security, no grant)');
select pg_temp.check((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                        and (p.proname like 'event\_web\_%' or p.proname like 'event\_vip\_%' or p.proname like 'event\_registration\_%')
                        and has_function_privilege('authenticated', p.oid, 'execute')) = 17
    and to_regprocedure('public.event_registration_put_back(uuid,text)') is null,
  'G5 no new function: the page reaches the same 17 event_web / event_vip / event_registration functions as before (Put back is Restore)');
select pg_temp.check((select count(*) from public.event_registration_people
                       where signed_up_again_at is not null or signed_up_again_days is not null or signed_up_again_resolved_at is not null) = 0,
  'G6 nothing is held before anyone signs up again (449 fills nothing)');

-- ═════ R Signing up again after being taken off ═════
select pg_temp.reg('a', jsonb_build_array(pg_temp.person(1, 'Ada', 'Again', pg_temp.ph(10), pg_temp.mail('ada'))));
select pg_temp.as_user('manager');
select public.event_set_guest_cancelled((pg_temp.pp('a1')).free_guest_id, true, 'Cannot come');
select pg_temp.put('r1', pg_temp.reg('a_again', jsonb_build_array(
  pg_temp.person(1, 'ada', 'AGAIN', pg_temp.ph(10), upper(pg_temp.mail('ada')), array[pg_temp.d(8)])))::text);
select pg_temp.check((pg_temp.tx('r1')::jsonb)->'people'->0 = jsonb_build_object('position', 1, 'person_id', pg_temp.fx('a1'),
                       'upgrade_token', pg_temp.tx('tok:a1'), 'days', '[]'::jsonb, 'already_registered', true, 'vip', 'none')
    and (pg_temp.tx('r1')::jsonb)->>'status' = 'registered'
    and ((pg_temp.fg('a1')).status, (pg_temp.fg('a1')).cancelled_reason) = ('cancelled'::text, 'Cannot come'::text)
    and pg_temp.gdays('a1') = array[pg_temp.d(7)] and (pg_temp.pp('a1')).days = array[pg_temp.d(7)]
    and (pg_temp.pp('a1')).match = 'new_customer'
    and (pg_temp.pp('a1')).signed_up_again_at is not null and (pg_temp.pp('a1')).signed_up_again_days = array[pg_temp.d(8)]
    and (pg_temp.pp('a1')).signed_up_again_resolved_at is null
    and (select count(*) from public.event_registration_people where phone_norm = pg_temp.ph(10)) = 1
    and (select count(*) from public.event_guests where event_id = pg_temp.fx('ev') and phone = pg_temp.ph(10)) = 1,
  'R1 taken off ("Cannot come"), Ada signs up again with her email (any case, any name order): held, not left off silently: '
  || 'no days in the answer (the website: "your place will be confirmed"), the same person and link, her record and guest record as they were, '
  || 'the day asked kept on the hold: ' || pg_temp.tx('r1'));
select pg_temp.check(pg_temp.audits((pg_temp.pp('a1')).free_guest_id, 'event_guest_register_again_refused') = 1
    and (select l.new_data from audit_logs l where l.record_id = (pg_temp.pp('a1')).free_guest_id
           and l.action = 'event_guest_register_again_refused')
        @> jsonb_build_object('registration_id', pg_temp.bid('REG', 'a_again'), 'person_id', pg_temp.fx('a1'), 'hold', 'opened',
                              'source', 'website', 'days', jsonb_build_array(pg_temp.d(8)))
    and (select l.reason from audit_logs l where l.record_id = (pg_temp.pp('a1')).free_guest_id
           and l.action = 'event_guest_register_again_refused') like 'Signed up again on the website after staff took them off the list: held for staff%',
  'R2 one audit row for the sign-up (436''s action, so earlier checks still read it): opened, with the days asked and the person');
select pg_temp.put('r_hold1_at', (pg_temp.pp('a1')).signed_up_again_at::text);
select pg_temp.put('r3', pg_temp.reg('a_again2', jsonb_build_array(
  pg_temp.person(1, 'Ada', 'Again', pg_temp.ph(10), pg_temp.mail('ada'), array[pg_temp.d(7), pg_temp.d(8)])))::text);
select pg_temp.check((pg_temp.tx('r3')::jsonb)->'people'->0->'days' = '[]'::jsonb
    and (pg_temp.pp('a1')).signed_up_again_at = pg_temp.tx('r_hold1_at')::timestamptz
    and (pg_temp.pp('a1')).signed_up_again_days = array[pg_temp.d(7), pg_temp.d(8)]
    and pg_temp.audits((pg_temp.pp('a1')).free_guest_id, 'event_guest_register_again_refused') = 2
    and (select count(*) from audit_logs l where l.record_id = (pg_temp.pp('a1')).free_guest_id
           and l.action = 'event_guest_register_again_refused' and l.new_data->>'hold' = 'updated') = 1
    and pg_temp.holds_of('a1') = 1 and pg_temp.gdays('a1') = array[pg_temp.d(7)],
  'R3 again while held: the same hold (its start kept, the days added), one more audit row (updated), still one entry for staff');
select pg_temp.check(pg_temp.hold('a1') @> jsonb_build_object('reason', 'signed_up_again', 'guest_id', (pg_temp.pp('a1')).free_guest_id,
                       'registration_id', pg_temp.bid('REG', 'a'), 'full_name', 'Ada Again', 'candidates', '[]'::jsonb,
                       'vip_payment', false, 'days', jsonb_build_array(pg_temp.d(7)))
    and (pg_temp.hold('a1')->>'held_at')::timestamptz = (pg_temp.pp('a1')).signed_up_again_at
    and pg_temp.hold('a1')->'signed_up_again' = jsonb_build_object('held_at', (pg_temp.pp('a1')).signed_up_again_at,
          'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)), 'removed_reason', 'Cannot come', 'removed_at', (pg_temp.fg('a1')).cancelled_at)
    and pg_temp.guest('a1')->'signed_up_again' = jsonb_build_object('held_at', (pg_temp.pp('a1')).signed_up_again_at,
          'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)))
    and pg_temp.guest('a1')->'hold' = 'null'::jsonb and pg_temp.guest('a1')->>'match' = 'new_customer',
  'R4 the page lists her under To match as signed_up_again (who took her off, why, when, the days asked; no candidates) and marks her cancelled row: '
  || coalesce(pg_temp.hold('a1')::text, 'none'));
select pg_temp.put('r5_person', pg_temp.person_read('a1')::text);
select pg_temp.put('r5_answers', pg_temp.answers('a1')::text);
select pg_temp.put('r5_sync', pg_temp.synced('a1')::text);
select pg_temp.check((pg_temp.tx('r5_person')::jsonb)->'person' @> '{"can_upgrade": false, "reason": "cancelled", "vip": "none"}'::jsonb
    and (pg_temp.tx('r5_person')::jsonb)->>'planning_open' = 'false'
    and (pg_temp.tx('r5_answers')::jsonb)->'people'->0 @> '{"status": "refused", "reason": "person_cancelled"}'::jsonb
    and (pg_temp.tx('r5_sync')::jsonb) @> jsonb_build_object('status', 'cancelled', 'cancelled_reason', 'Cannot come',
                                                              'days', jsonb_build_array(pg_temp.d(7))),
  'R5 while held the website still reads her as not registered: no VIP, answers refused (its Answers To Send wait), the sync says cancelled');

-- ═════ V VIP while held ═════
select pg_temp.reg('c', jsonb_build_array(pg_temp.person(1, 'Cal', 'Coming', pg_temp.ph(11), pg_temp.mail('cal'))));
select pg_temp.put('v1', pg_temp.checkout('live', 'v1', array['a1'])::text);
select pg_temp.put('v2', pg_temp.checkout('live', 'v2', array['c1', 'a1'])::text);
select pg_temp.check((pg_temp.tx('v1')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'refused',
                       'reason', 'person_cancelled', 'person_ids', jsonb_build_array(pg_temp.fx('a1')))
    and (pg_temp.tx('v2')::jsonb) @> jsonb_build_object('status', 'refused', 'reason', 'person_cancelled',
                                                          'person_ids', jsonb_build_array(pg_temp.fx('a1')))
    and (pg_temp.vorder('v1')).id is null and (pg_temp.vorder('v2')).id is null
    and public.event_web_person_vip_state(pg_temp.fx('a1')) = 'none',
  'V1 while held a VIP checkout is refused (person_cancelled, nothing kept), for her alone or with someone else (only she is named): '
  || pg_temp.tx('v2'));
select pg_temp.put('v3', pg_temp.paid('live', 'v3', array['a1'])::text);
-- Dealt with on Website orders (not this file's): closed as refunded, so it does not wait any more below.
select pg_temp.as_user('manager');
select public.event_vip_order_close_refunded((pg_temp.vorder('v3')).id, 'In HitPay (449 test)', true);
select pg_temp.put('v4', pg_temp.transfer('v4', array['a1'])::text);
select public.event_vip_order_dismiss((pg_temp.vorder('v4')).id, 'Never arrived (449 test)', true);
select pg_temp.check((pg_temp.tx('v3')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('v3')::jsonb)->>'review_reason'
        = 'Person 1 on this order signed up again after staff took them off the list: put them back on the list first (Guests, To match)'
    and (pg_temp.tx('v4')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('v4')::jsonb)->>'review_reason'
        = 'Person 1 on this order signed up again after staff took them off the list: put them back on the list first (Guests, To match)'
    and (select count(*) from pg_temp.vinvoices('v3')) = 0 and (select count(*) from pg_temp.vinvoices('v4')) = 0
    and (pg_temp.fg('a1')).status = 'cancelled',
  'V2 a HitPay payment or a transfer for her anyway waits for a Manager with the reason (to put her back first); nothing invoiced: '
  || pg_temp.tx('v3') || ' | ' || pg_temp.tx('v4'));

-- ═════ P Put back ═════
select pg_temp.as_user('staff');
select pg_temp.put('p1', public.event_set_guest_cancelled((pg_temp.pp('a1')).free_guest_id, false, 'Called her: she can come')::text);
select pg_temp.check((pg_temp.tx('p1')::jsonb) @> jsonb_build_object('status', 'registered', 'days_dropped', '[]'::jsonb,
                       'days_added', jsonb_build_array(pg_temp.d(8)), 'signed_up_again', true)
    and (pg_temp.fg('a1')).status = 'registered' and (pg_temp.fg('a1')).cancelled_reason is null
    and pg_temp.gdays('a1') = array[pg_temp.d(7), pg_temp.d(8)]
    and (pg_temp.pp('a1')).days = array[pg_temp.d(7), pg_temp.d(8)]
    and (pg_temp.pp('a1')).signed_up_again_resolved_at is not null and (pg_temp.pp('a1')).match = 'new_customer'
    and (select l.new_data->'signed_up_again' from audit_logs l where l.record_id = (pg_temp.pp('a1')).free_guest_id
           and l.action = 'event_guest_restored')
        = jsonb_build_object('person_id', pg_temp.fx('a1'), 'held_at', (pg_temp.pp('a1')).signed_up_again_at,
                             'days_asked', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)), 'days_added', jsonb_build_array(pg_temp.d(8)))
    and (select l.reason from audit_logs l where l.record_id = (pg_temp.pp('a1')).free_guest_id and l.action = 'event_guest_restored')
        = 'Called her: she can come'
    and pg_temp.hold('a1') is null and pg_temp.guest('a1')->'signed_up_again' = 'null'::jsonb,
  'P1 Staff put her back (Put back on the list = Restore): registered on the day she had and the day she asked for, the hold ended, '
  || 'audited (days asked and added), off To match: ' || pg_temp.tx('p1'));
select pg_temp.put('p2_person', pg_temp.person_read('a1')::text);
select pg_temp.put('p2_answers', pg_temp.answers('a1')::text);
select pg_temp.put('p2_sync', pg_temp.synced('a1')::text);
select pg_temp.put('p2_co', pg_temp.checkout('live', 'p2v', array['a1'])::text);
select pg_temp.check((pg_temp.tx('p2_person')::jsonb)->'person' @> jsonb_build_object('can_upgrade', true,
                       'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)))
    and (pg_temp.tx('p2_answers')::jsonb)->'people'->0->>'status' = 'saved'
    and (pg_temp.tx('p2_sync')::jsonb) @> jsonb_build_object('status', 'registered', 'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)))
    and (pg_temp.tx('p2_co')::jsonb)->>'status' = 'ok',
  'P2 back on the list: VIP and answers open again (the website''s waiting answers are saved by its sync, which now says registered on both days)');
select pg_temp.as_user('manager');
select pg_temp.put('p3', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('a1'), 'Not coming after all')));
select pg_temp.check(pg_temp.tx('p3') = 'This registration is not waiting for staff any more.'
    and (pg_temp.pp('a1')).match = 'new_customer' and (pg_temp.fg('a1')).status = 'registered',
  'P3 a Close from a page that did not see her put back is refused, and changes nothing: ' || pg_temp.tx('p3'));
select pg_temp.put('p4', pg_temp.reg('a_again3', jsonb_build_array(pg_temp.person(1, 'Ada', 'Again', pg_temp.ph(10), pg_temp.mail('ada'))))::text);
select pg_temp.check((pg_temp.tx('p4')::jsonb)->'people'->0 @> jsonb_build_object('already_registered', true,
                       'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)), 'vip', 'pending')
    and (pg_temp.pp('a1')).signed_up_again_resolved_at is not null and pg_temp.hold('a1') is null,
  'P4 signing up again now that she is back is as 436 (her days, her VIP state; no hold)');

-- ═════ C Close ═════
select pg_temp.reg('b', jsonb_build_array(pg_temp.person(1, 'Bea', 'Removed', pg_temp.ph(12), pg_temp.mail('bea'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('b1')).free_guest_id, true, 'Asked not to come');
select pg_temp.reg('b_again', jsonb_build_array(pg_temp.person(1, 'Bea', 'Removed', pg_temp.ph(12), pg_temp.mail('bea'), array[pg_temp.d(8)])));
select pg_temp.as_user('staff');
select pg_temp.put('c_staff', pg_temp.errcode(format('select public.event_registration_close(%L, %L)', pg_temp.fx('b1'), 'Leave her off')));
select pg_temp.put('c_attach', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx('b1'),
  (pg_temp.pp('b1')).customer_id, 'Same person')));
select pg_temp.put('c_create', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('b1'), null)));
select pg_temp.as_user('manager2');
select pg_temp.put('c_m2', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('b1'), 'Leave her off')));
select pg_temp.as_user('manager');
select pg_temp.put('c_short', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('b1'), 'no')));
select pg_temp.check(pg_temp.tx('c_staff') = '42501' and pg_temp.tx('c_m2') = 'You do not have access to this event''s store'
    and pg_temp.tx('c_short') = 'Give a reason'
    and pg_temp.tx('c_attach') = 'This registration is not waiting to be matched.'
    and pg_temp.tx('c_create') = 'This registration is not waiting to be matched.'
    and pg_temp.hold('b1')->>'reason' = 'signed_up_again' and (pg_temp.pp('b1')).signed_up_again_resolved_at is null,
  'C1 staff cannot close it, nor a Manager without the store''s access, nor without a reason; Attach and New customer refuse it (they have their customer)');
select pg_temp.put('c2', public.event_registration_close(pg_temp.fx('b1'), 'Leave her off: asked not to come')::text);
select pg_temp.check((pg_temp.tx('c2')::jsonb) = '{"ok": true, "checkouts_closed": [], "signed_up_again": "closed"}'::jsonb
    and ((pg_temp.fg('b1')).status, (pg_temp.fg('b1')).cancelled_reason) = ('cancelled'::text, 'Asked not to come'::text)
    and (pg_temp.pp('b1')).match = 'new_customer' and (pg_temp.pp('b1')).signed_up_again_resolved_at is not null
    and pg_temp.gdays('b1') = array[pg_temp.d(7)]
    and pg_temp.audits(pg_temp.fx('b1'), 'event_registration_signed_up_again_closed') = 1
    and pg_temp.audits(pg_temp.fx('b1'), 'event_registration_closed') = 0
    and (select l.reason from audit_logs l where l.record_id = pg_temp.fx('b1') and l.action = 'event_registration_signed_up_again_closed')
        = 'Leave her off: asked not to come'
    and pg_temp.hold('b1') is null and pg_temp.guest('b1')->'signed_up_again' = 'null'::jsonb,
  'C2 a Manager closes it: she stays off (her guest record cancelled with staff''s reason, her registration not closed), the hold ended, audited: '
  || pg_temp.tx('c2'));
select pg_temp.put('c3_again', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('b1'), 'Leave her off')));
select pg_temp.put('c3', pg_temp.reg('b_again2', jsonb_build_array(pg_temp.person(1, 'Bea', 'Removed', pg_temp.ph(12), pg_temp.mail('bea'))))::text);
select pg_temp.check(pg_temp.tx('c3_again') = 'This registration is not waiting for staff any more.'
    and (pg_temp.tx('c3')::jsonb)->'people'->0->'days' = '[]'::jsonb
    and (pg_temp.pp('b1')).signed_up_again_resolved_at is null and (pg_temp.pp('b1')).signed_up_again_days = array[pg_temp.d(7)]
    and pg_temp.hold('b1')->>'reason' = 'signed_up_again' and pg_temp.holds_of('b1') = 1
    and (select count(*) from audit_logs l where l.record_id = (pg_temp.pp('b1')).free_guest_id
           and l.action = 'event_guest_register_again_refused' and l.new_data->>'hold' = 'opened') = 2,
  'C3 closed twice: refused; she signs up again after Close: held again (a new hold, only the days asked now), nothing lets her in by itself');

-- ═════ U Taken off as "Upgraded to VIP": as before ═════
select pg_temp.reg('u', jsonb_build_array(pg_temp.person(1, 'Una', 'Upgraded', pg_temp.ph(13), pg_temp.mail('una'))));
select pg_temp.checkout('live', 'u1v', array['u1']);
select pg_temp.put('u_paid', pg_temp.paid('live', 'u1v', array['u1'])::text);
select pg_temp.put('u1', pg_temp.reg('u_again', jsonb_build_array(pg_temp.person(1, 'Una', 'Upgraded', pg_temp.ph(13), pg_temp.mail('una'))))::text);
select pg_temp.check((pg_temp.tx('u_paid')::jsonb)->>'status' = 'invoiced'
    and (pg_temp.fg('u1')).cancelled_reason like 'Upgraded to VIP%'
    and (pg_temp.tx('u1')::jsonb)->'people'->0 @> jsonb_build_object('already_registered', true, 'vip', 'paid',
                                                                       'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)))
    and (pg_temp.pp('u1')).signed_up_again_at is null and pg_temp.hold('u1') is null,
  'U1 a VIP (her free record parked "Upgraded to VIP") signs up again: as before, her days (both, VIP), no hold: ' || pg_temp.tx('u1'));

-- ═════ E Another email: as before ═════
select pg_temp.reg('e', jsonb_build_array(pg_temp.person(1, 'Eli', 'Elsewhere', pg_temp.ph(14), pg_temp.mail('eli'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('e1')).free_guest_id, true, 'Cannot come');
select pg_temp.put('e1', pg_temp.reg('e_other', jsonb_build_array(pg_temp.person(1, 'Eli', 'Elsewhere', pg_temp.ph(14), pg_temp.mail('eli-other'))))::text);
select pg_temp.check((pg_temp.tx('e1')::jsonb)->'people'->0
        = '{"position": 1, "person_id": null, "upgrade_token": null, "days": null, "already_registered": true, "vip": null}'::jsonb
    and (pg_temp.pp('e1')).signed_up_again_at is null and pg_temp.hold('e1') is null
    and pg_temp.audits((pg_temp.pp('e1')).free_guest_id, 'event_guest_register_again_refused') = 0
    and pg_temp.tx('e1') !~ pg_temp.tx('tok:e1'),
  'E1 taken off, then their phone and name with ANOTHER email: today''s "already registered" (nothing of theirs given out), no hold, no row');

-- ═════ T A test key: as before ═════
select pg_temp.put('t1', pg_temp.reg('t', jsonb_build_array(pg_temp.person(1, 'Tia', 'Testing', pg_temp.ph(15), pg_temp.mail('tia'))), 'test')::text);
select pg_temp.put('t2', pg_temp.reg('t_again', jsonb_build_array(pg_temp.person(1, 'Tia', 'Testing', pg_temp.ph(15), pg_temp.mail('tia'),
  array[pg_temp.d(8)])), 'test')::text);
select pg_temp.check((pg_temp.tx('t2')::jsonb) @> '{"test": true}'::jsonb
    and (pg_temp.tx('t2')::jsonb)->'people'->0 @> jsonb_build_object('already_registered', true, 'person_id', pg_temp.fx('t1'),
                                                                       'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)))
    and (pg_temp.pp('t1')).free_guest_id is null and (pg_temp.pp('t1')).signed_up_again_at is null
    and pg_temp.hold('t1') is null,
  'T1 a test key''s person has no guest record, is never held, and signing up again adds days as before: ' || pg_temp.tx('t2'));

-- ═════ H Waiting to be matched, taken off, then signing up again ═════
select pg_temp.reg('h', jsonb_build_array(pg_temp.person(1, 'Hana', 'Heldtoo', pg_temp.ph(1), pg_temp.mail('hana'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('h1')).free_guest_id, true, 'Duplicate of a phone booking');
select pg_temp.reg('h_again', jsonb_build_array(pg_temp.person(1, 'Hana', 'Heldtoo', pg_temp.ph(1), pg_temp.mail('hana'), array[pg_temp.d(8)])));
select pg_temp.check((pg_temp.pp('h1')).match = 'held' and pg_temp.holds_of('h1') = 1
    and pg_temp.hold('h1')->>'reason' = 'phone_in_use'
    and (pg_temp.hold('h1')->>'held_at')::timestamptz = (pg_temp.pp('h1')).created_at
    and jsonb_array_length(pg_temp.hold('h1')->'candidates') >= 1
    and pg_temp.hold('h1')->'signed_up_again'->'days' = jsonb_build_array(pg_temp.d(8))
    and pg_temp.hold('h1')->'signed_up_again'->>'removed_reason' = 'Duplicate of a phone booking'
    and pg_temp.guest('h1')->'hold' @> '{"reason": "phone_in_use"}'::jsonb,
  'H1 waiting to be matched and taken off, then signing up again: listed once, as To match (its candidates), with the signed-up-again note');
select pg_temp.as_user('staff');
select pg_temp.put('h2', public.event_set_guest_cancelled((pg_temp.pp('h1')).free_guest_id, false, null)::text);
select pg_temp.check((pg_temp.tx('h2')::jsonb) @> jsonb_build_object('signed_up_again', true, 'days_added', jsonb_build_array(pg_temp.d(8)))
    and (pg_temp.pp('h1')).match = 'held' and pg_temp.holds_of('h1') = 1
    and pg_temp.hold('h1')->'signed_up_again' = 'null'::jsonb
    and pg_temp.gdays('h1') = array[pg_temp.d(7), pg_temp.d(8)],
  'H2 put back: on the list on both days, still waiting to be matched (To match), the note gone');

-- ═════ N Nothing else ═════
select pg_temp.as_user('owner');
select pg_temp.put('n1', public.event_set_guest_cancelled((pg_temp.pp('c1')).free_guest_id, true, 'Cannot come')::text);
select pg_temp.put('n2', public.event_set_guest_cancelled((pg_temp.pp('c1')).free_guest_id, false, null)::text);
select pg_temp.check((pg_temp.tx('n2')::jsonb) @> '{"status": "registered", "days_added": [], "signed_up_again": false}'::jsonb
    and pg_temp.gdays('c1') = array[pg_temp.d(7)] and (pg_temp.pp('c1')).signed_up_again_at is null,
  'N1 taken off and restored without signing up again: as 415 (their days, nothing added, nothing held)');
select pg_temp.check((select count(*) from jsonb_array_elements(pg_temp.extras()->'holds') h where h->>'reason' = 'signed_up_again') = 1
    and not exists (select 1 from jsonb_array_elements(pg_temp.extras()->'holds') h
                     where h->>'reason' = 'signed_up_again' and (h->>'person_id')::uuid <> pg_temp.fx('b1')),
  'N2 the page lists only the open signed-up-again hold (Bea''s second), none that was put back or closed, and no test person');

-- ═════ K Close takes their unpaid HitPay checkout with it (as 444's Close) ═════
select pg_temp.reg('k', jsonb_build_array(pg_temp.person(1, 'Kim', 'Checkout', pg_temp.ph(20), pg_temp.mail('kim'))));
select pg_temp.put('k_co', pg_temp.checkout('live', 'k1', array['k1'])::text);
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('k1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('k_again', jsonb_build_array(pg_temp.person(1, 'Kim', 'Checkout', pg_temp.ph(20), pg_temp.mail('kim'), array[pg_temp.d(8)])));
select pg_temp.check((pg_temp.tx('k_co')::jsonb)->>'status' = 'ok' and (pg_temp.vorder('k1')).status = 'pending'
    and pg_temp.hold('k1')->>'reason' = 'signed_up_again'
    and pg_temp.hold('k1')->'vip_checkout'->>'order_id' = pg_temp.bid('VIP', 'k1'),
  'K1 a HitPay checkout she opened before staff took her off, not paid, shows on her hold: ' || coalesce(pg_temp.hold('k1')::text, 'none'));
select pg_temp.as_user('manager');
select pg_temp.put('k2', public.event_registration_close(pg_temp.fx('k1'), 'Leave her off: asked not to come')::text);
select pg_temp.check((pg_temp.tx('k2')::jsonb) = jsonb_build_object('ok', true, 'signed_up_again', 'closed',
                       'checkouts_closed', jsonb_build_array(jsonb_build_object('order_id', pg_temp.bid('VIP', 'k1'), 'people', 1, 'open', true)))
    and (pg_temp.vorder('k1')).status = 'dismissed'
    and (pg_temp.vorder('k1')).review_reason = 'Checkout closed: Leave her off: asked not to come'
    and pg_temp.audits((pg_temp.vorder('k1')).id, 'event_vip_checkout_closed') = 1
    and (select l.new_data->'checkouts_closed' from audit_logs l
          where l.record_id = pg_temp.fx('k1') and l.action = 'event_registration_signed_up_again_closed')
        = (pg_temp.tx('k2')::jsonb)->'checkouts_closed'
    and ((pg_temp.fg('k1')).status, (pg_temp.fg('k1')).cancelled_reason) = ('cancelled'::text, 'Cannot come'::text)
    and (pg_temp.pp('k1')).match = 'new_customer' and pg_temp.hold('k1') is null,
  'K2 closing her hold closes her unpaid HitPay checkout with it (dismissed with the reason, audited, listed in the answer and the audit row), '
  || 'as 444''s Close; she stays off: ' || pg_temp.tx('k2'));
select pg_temp.put('k3', pg_temp.paid('live', 'k1', array['k1'])::text);
select pg_temp.check((pg_temp.tx('k3')::jsonb)->>'status' = 'needs_review'
    and (select count(*) from pg_temp.vinvoices('k1')) = 0
    and not exists (select 1 from public.event_guests g where g.id = (pg_temp.pp('k1')).vip_guest_id and g.status = 'registered')
    and public.event_web_person_vip_state(pg_temp.fx('k1')) is distinct from 'paid'
    and (pg_temp.fg('k1')).status = 'cancelled',
  'K3 HitPay then reports a payment for it: it waits on Website orders (needs review), nothing invoiced, she is not VIP: ' || pg_temp.tx('k3'));

-- ═════ W VIP made by hand while held: no hold while their VIP record stands ═════
select pg_temp.reg('w', jsonb_build_array(pg_temp.person(1, 'Wyn', 'Waiting', pg_temp.ph(21), pg_temp.mail('wyn'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('w1')).free_guest_id, true, 'Cannot come');
select pg_temp.reg('w_again', jsonb_build_array(pg_temp.person(1, 'Wyn', 'Waiting', pg_temp.ph(21), pg_temp.mail('wyn'), array[pg_temp.d(8)])));
select pg_temp.put('w_paid', pg_temp.paid('live', 'w1', array['w1'])::text);
select pg_temp.put('w_held', (pg_temp.holds_of('w1') = 1 and pg_temp.guest('w1')->'signed_up_again' <> 'null'::jsonb)::text);
select pg_temp.as_user('manager');
select pg_temp.put('w_inv', pg_temp.err(format('select public.event_vip_order_invoice(%L)', (pg_temp.vorder('w1')).id)));
select pg_temp.as_user('owner');
select pg_temp.put('w_close', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('w1'), 'Leave them off')));
select pg_temp.check((pg_temp.tx('w_paid')::jsonb)->>'status' = 'needs_review' and pg_temp.tx('w_held') = 'true'
    and pg_temp.tx('w_inv') = 'ok' and (pg_temp.vorder('w1')).status = 'invoiced'
    and exists (select 1 from public.event_guests g where g.id = (pg_temp.pp('w1')).vip_guest_id and g.status = 'registered')
    and pg_temp.holds_of('w1') = 0 and pg_temp.guest('w1')->'signed_up_again' = 'null'::jsonb
    and pg_temp.tx('w_close') = 'Wyn Waiting is VIP: cancel or refund their VIP invoice instead.'
    and (pg_temp.pp('w1')).signed_up_again_resolved_at is null
    and pg_temp.audits(pg_temp.fx('w1'), 'event_registration_signed_up_again_closed') = 0,
  'W1 a Manager invoices her waiting payment by hand while she is held: she is VIP, so no hold shows (no row marker either), and Close says '
  || 'she is VIP (444), not "left off": ' || pg_temp.tx('w_inv') || ' | ' || pg_temp.tx('w_close'));
select pg_temp.as_user('staff');
select pg_temp.put('w_restore', public.event_set_guest_cancelled((pg_temp.pp('w1')).free_guest_id, false, 'Restored')::text);
select pg_temp.check((pg_temp.tx('w_restore')::jsonb) @> '{"days_added": [], "signed_up_again": false}'::jsonb
    and (pg_temp.pp('w1')).signed_up_again_resolved_at is null,
  'W2 Restore on the Guests tab is then 415''s (nothing added, no hold to end): ' || pg_temp.tx('w_restore'));

-- ═════ S A hold starts no earlier than the removal it answers ═════
-- (Staff's removal committing while a sign-up waits for its locks is stamped later than the sign-up's now(): here the
-- removal's time is set ahead of now(), as such a removal would have it.)
select pg_temp.reg('s', jsonb_build_array(pg_temp.person(1, 'Sol', 'Slow', pg_temp.ph(22), pg_temp.mail('sol'))));
select pg_temp.as_user('owner');
select public.event_set_guest_cancelled((pg_temp.pp('s1')).free_guest_id, true, 'Cannot come');
update public.event_guests set cancelled_at = now() + interval '2 seconds' where id = (pg_temp.pp('s1')).free_guest_id;
select pg_temp.put('s1', pg_temp.reg('s_again', jsonb_build_array(pg_temp.person(1, 'Sol', 'Slow', pg_temp.ph(22), pg_temp.mail('sol'),
  array[pg_temp.d(8)])))::text);
select pg_temp.check((pg_temp.tx('s1')::jsonb)->'people'->0->'days' = '[]'::jsonb
    and (pg_temp.pp('s1')).signed_up_again_at = (pg_temp.fg('s1')).cancelled_at
    and pg_temp.holds_of('s1') = 1 and pg_temp.hold('s1')->>'reason' = 'signed_up_again'
    and pg_temp.guest('s1')->'signed_up_again' <> 'null'::jsonb,
  'S1 a removal stamped after the sign-up''s start: the hold starts at the removal, so it is open and listed (not lost): '
  || coalesce(pg_temp.hold('s1')::text, 'none'));
select pg_temp.as_user('staff');
select pg_temp.put('s2', public.event_set_guest_cancelled((pg_temp.pp('s1')).free_guest_id, false, null)::text);
select pg_temp.check((pg_temp.tx('s2')::jsonb) @> jsonb_build_object('signed_up_again', true, 'days_added', jsonb_build_array(pg_temp.d(8))),
  'S2 put back: the day asked is added: ' || pg_temp.tx('s2'));

-- ═════ M 449 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m449 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m449),
  'M1 running 449 a second time changed no function');
select pg_temp.check((select before = after1 from r449),
  'M2 449''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 449 checks passed.';
end $$;
rollback;
